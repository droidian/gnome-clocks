/*
 * Copyright (C) 2013  Paolo Borelli <pborelli@gnome.org>
 * Copyright (C) 2020  Bilal Elmoussaoui <bilal.elmoussaoui@gnome.org>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

namespace Clocks {
namespace Timer {

public class Item : Object, ContentItem {
    public enum State {
        STOPPED,
        RUNNING,
        PAUSED
    }

    public State state { get; private set; default = State.STOPPED; }

    public string? name { get ; set; }
    public int hours { get; set; default = 0; }
    public int minutes { get; set; default = 0; }
    public int seconds { get; set; default = 0; }

    private double span;
    private GLib.Timer timer;
    private uint timeout_id;
    private int stored_hour;
    private int stored_minute;
    private int stored_second;

    private GLib.DateTime? start_time;

    public signal void ring ();
    public signal void countdown_updated (int hours, int minutes, int seconds);

    public int get_total_seconds () {
        return hours * 3600 + minutes * 60 + seconds;
    }

    public void serialize (GLib.VariantBuilder builder) {
        builder.open (new GLib.VariantType ("a{sv}"));
        builder.add ("{sv}", "duration", new GLib.Variant.int32 (get_total_seconds ()));
        if (span > 0) {
            builder.add ("{sv}", "time_left", new GLib.Variant.int32 ((int32) Math.ceil (span)));
        }
        if (start_time != null) {
            builder.add ("{sv}", "start_time", new GLib.Variant.int64 (((!) start_time).to_unix ()));
        }
        if (name != null) {
            builder.add ("{sv}", "name", new GLib.Variant.string ((string) name));
        }
        builder.close ();
    }

    public static Item? deserialize (Variant time_variant) {
        string key;
        Variant val;
        int duration = 0;
        string? name = null;
        int span = 0;
        GLib.DateTime? start_time = null;

        var iter = time_variant.iterator ();
        while (iter.next ("{sv}", out key, out val)) {
            switch (key) {
                case "time_left":
                    span = (int32) val;
                    break;
                case "start_time":
                    start_time = new GLib.DateTime.from_unix_local ((int64) val);
                    break;
                case "duration":
                    duration = (int32) val;
                    break;
                case "name":
                    name = (string) val;
                    break;
            }
        }

        return duration != 0 ? (Item?) new Item.from_seconds (duration, name, start_time, (double) span) : null;
    }

    public Item.from_seconds (int seconds,
                              string? name,
                              GLib.DateTime? start_time = null,
                              double time_left = 0) {
        int rest = 0;
        int h = seconds / 3600;
        rest = seconds - h * 3600;
        int m = rest / 60;
        int s = rest - m * 60;

        this (h, m, s, name, start_time, time_left);
    }

    public Item (int h,
                 int m,
                 int s,
                 string? name,
                 GLib.DateTime? start_time = null,
                 double time_left = 0) {
        Object (name: name);
        hours = h;
        minutes = m;
        seconds = s;

        timer = new GLib.Timer ();

        if (start_time != null) {
            this.start_time = start_time;
            start ();
        } else if (time_left > 0) {
            this.span = time_left;
            state = State.PAUSED;
        }
    }

    public void update_countdown () {
        int h, m, s;
        if (state == State.STOPPED) {
            countdown_updated (hours, minutes, seconds);
        }else {
            Utils.time_to_hms (span, out h, out m, out s, null);
            countdown_updated (h, m, s);
        }
    }

    public virtual signal void start () {
        if (start_time == null) {
            start_time = new GLib.DateTime.now ();
            if (span == 0)
                span = get_total_seconds ();
        } else {
            span = get_total_seconds () - new GLib.DateTime.now ().difference ((!) start_time) / TimeSpan.SECOND;
        }

        state = State.RUNNING;
        timeout_id = GLib.Timeout.add (100, () => {
            var e = timer.elapsed ();
            if (state != State.RUNNING) {
                return false;
            }
            if (e >= span) {
                reset ();
                ring ();
                timeout_id = 0;
                return false;
            }
            var elapsed = Math.ceil (span - e);
            int h;
            int m;
            int s;
            double r;
            Utils.time_to_hms (elapsed, out h, out m, out s, out r);

            if (stored_hour != h || stored_minute != m || stored_second != s) {
                stored_hour = h;
                stored_minute = m;
                stored_second = s;
                countdown_updated (h, m, s);
            }
            return true;
        });
        timer.start ();
    }

    public virtual signal void pause () {
        start_time = null;
        span -= timer.elapsed ();
        timer.stop ();
        state = State.PAUSED;
    }

    public virtual signal void reset () {
        start_time = null;
        span = 0;
        timer.reset ();
        state = State.STOPPED;
        update_countdown ();
    }
}

} // namespace Timer
} // namespace Clocks
