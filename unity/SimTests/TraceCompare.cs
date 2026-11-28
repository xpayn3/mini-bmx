using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using Runout.Sim;
using static Runout.Sim.Gd;

namespace Runout.Sim.Tests
{
    /// Rides the shared ride physics (godot/sim BikeSim) through the scripted runs of godot/tools/port_trace.gd and
    /// compares every step with the Godot reference (SimTests/ref/*.csv, written by the GDScript ride before it was
    /// replaced by godot/sim). A run "matches" while the position stays within POS_TOL of Godot's; TRACE_DETAIL=1
    /// prints the first step any column differs at all.
    static class TraceCompare
    {
        const double POS_TOL = 0.02;   // m

        /// slope_stress's synthetic ground (godot/tools/slope_stress.gd Ground), the kinds the trace runs use
        public sealed class Ground : IGround
        {
            public string kind = "flat"; public double a, b, x0 = 20.0; public long surf = 0;
            public double height(double x, double z)
            {
                switch (kind)
                {
                    case "flat": return 0.0;
                    case "grade":
                    {
                        double s = x - x0;
                        if (s <= 0.0) return 0.0;
                        double r = 4.0;
                        if (s < r) return tan(a) * s * s / (2.0 * r);
                        return tan(a) * (s - r * 0.5);
                    }
                    case "camber": return -tan(a) * z;
                    case "crest":
                    {
                        double s = x - x0;
                        double w = sqrt(2.0 * b * a);
                        if (s < -w || s > w) return 0.0;
                        return a - s * s / (2.0 * b);
                    }
                    case "rollers": return x < x0 ? 0.0 : a * (1.0 - cos(TAU * (x - x0) / b)) * 0.5;
                    case "washboard": return x < x0 ? 0.0 : a * sin(TAU * (x - x0) / b);
                    case "step": return b * clampf((x - x0) / 0.02, 0.0, 1.0);
                }
                return 0.0;
            }
            public double deck_height(double x, double z) => height(x, z);
            public double top_height(double x, double z) => height(x, z);
            public long surface(double x, double z) => surf;
            public double jump_mask(double x, double z) => 0.0;
            public List<GdDict> colliders_near(double x, double z) => new List<GdDict>();
            public RayHit cast(V3 o, V3 d, double m) => new RayHit();
        }

        /// slope_stress's Host: nothing drawn, a crash starts the ride's crash
        public sealed class Host : IRideHost
        {
            public Ground g = new Ground();
            public BikeSim phys;
            public string crash = "";
            readonly List<double> _a0 = new List<double> { 0.0, Math.PI };
            public IGround terrain => g;
            public ISusp susp => null;
            public object ragdoll => null;
            public object getup_anim => null;
            public List<double> pedal_a0 => _a0;
            public bool has_method(string name) => true;
            public void flash(string text) { }
            public bool msg_idle() => false;
            public bool smash(GdDict c, V3 vel, V3 pos) => false;
            public void rock_chips(GdDict c) { }
            public void burst(V3 pos, long n, long surf, double power) { }
            public void start_crash(string r) { if (crash == "") crash = r; phys.begin_crash(); }
            public void begin_getup() => phys.get_up();
            public void on_style(long points, string text) { }
            public void on_trick(string trick) { }
            public void on_takeoff() { }
            public void on_landing(double air_time, double impact) { }
            public void on_bad_landing(double k) { }
            public void ride_fx(double dt, V3 f, double va, bool in_water) { }
            public void log(string text) { }
            public void crashlog_note(string text) { }
            public void crash_body_step(BikeSim s, double dt, RideInput inp) { }
            public long get_ticks_usec() => 0;
            public long get_ticks_msec() => 0;
            public long get_physics_frames() => 0;
        }

        static RideInput Input(string script, double t)
        {
            var i = new RideInput();
            foreach (var k in new[] { "throttle", "brake", "steer", "body_fwd", "body_lean" }) i.set(k, 0.0);
            i.set("hop", false); i.set("sprint", false); i.set("pad", false);
            switch (script)
            {
                case "pedal": i.set("throttle", 1.0); break;
                case "brake": i.set("brake", t > 1.0 ? 1.0 : 0.0); break;
                case "turn": i.set("throttle", 0.4); i.set("steer", t > 1.0 ? 0.5 : 0.0); break;
                case "swaps": i.set("throttle", 0.3); i.set("steer", t > 0.5 ? 0.7 * sin(TAU * t / 1.6) : 0.0); break;
                case "pump": i.set("hop", t % 1.0 < 0.45); break;
                case "hop": i.set("hop", (t > 1.0 && t < 1.35) || (t > 2.5 && t < 2.8)); break;
                case "manual": i.set("body_fwd", (t > 1.0 && t < 3.0) ? -0.75 : 0.0); i.set("pad", true); break;
                case "sprint": i.set("throttle", 1.0); i.set("sprint", t > 0.5); break;
            }
            return i;
        }

        static double Num(JsonElement e) => e.ValueKind == JsonValueKind.True ? 1 : e.ValueKind == JsonValueKind.False ? 0 : e.GetDouble();

        /// returns the number of runs that drifted past the tolerance (0 = all match); -1 = no reference traces
        public static int Run(string refDir, bool verbose)
        {
            string cfgPath = Path.Combine(refDir, "config.json");
            if (!File.Exists(cfgPath)) { Console.WriteLine($"TRACE no reference at {refDir} (run godot/tools/port_trace.tscn)"); return -1; }
            var root = JsonDocument.Parse(File.ReadAllText(cfgPath)).RootElement;
            var tuneV = new Dictionary<string, double>();
            foreach (var p in root.GetProperty("tune").EnumerateObject()) tuneV[p.Name] = Num(p.Value);
            var ex = new GdDict();
            foreach (var p in root.GetProperty("extras").EnumerateObject()) ex[p.Name] = Num(p.Value);
            var mods = new GdDict();
            var cogs = new List<double>();
            foreach (var c in root.GetProperty("cogs").EnumerateArray()) cogs.Add(Num(c));
            if (cogs.Count > 0) { mods.set("cogs", cogs); mods["ring_k"] = Num(root.GetProperty("ring_k")); mods["land"] = Num(root.GetProperty("mods_land")); }
            var su = root.GetProperty("susp");
            if (su.ValueKind == JsonValueKind.Object && su.TryGetProperty("f", out var fu))
            {
                var s = new SusSetup { empty = false };
                int k = 0;
                foreach (var u in new[] { fu, su.GetProperty("r") })
                    foreach (var key in new[] { "travel", "sag", "prog", "zc", "zr", "hs", "fric", "bump" }) s.u[k++] = Num(u.GetProperty(key));
                s.u[16] = Num(su.GetProperty("psi_f")); s.u[17] = Num(su.GetProperty("psi_r"));
                mods.set("susp", s);
            }
            var cfg = new GdDict();
            cfg["land"] = Num(root.GetProperty("land")); cfg.set("geared", root.GetProperty("geared").GetBoolean()); cfg.set("mods", mods);
            double dt = Num(root.GetProperty("dt"));

            int bad = 0;
            foreach (var r in root.GetProperty("runs").EnumerateArray())
            {
                string name = r[0].GetString();
                var h = new Host();
                h.g.kind = r[1].GetString(); h.g.a = Num(r[2]); h.g.b = Num(r[3]); h.g.x0 = Num(r[4]);
                var T = new RideParams();
                foreach (var kv in tuneV) T.v[kv.Key] = kv.Value;
                RideParams.global = T;
                var p = new BikeSim(h) { T = T }; h.phys = p;
                p.setup(ex, cfg);
                p.reset_at(0.0, 0.0, 0.0);
                p.v = Num(r[5]);
                string script = r[7].GetString();
                var lines = File.ReadAllLines(Path.Combine(refDir, name + ".csv"));
                var hdr = lines[0].Split(',');
                int ix = Array.IndexOf(hdr, "x"), iy = Array.IndexOf(hdr, "y"), iz = Array.IndexOf(hdr, "z");
                int first_bad = -1, first_diff = -1; double worst_pos = 0; string worst_col = ""; int steps = 0;
                string err = null;
                for (int i = 1; i < lines.Length; i++)
                {
                    double t = (i - 1) * dt;
                    try { p.step(dt, Input(script, t)); }
                    catch (Exception e) { err = $"{e.GetType().Name} at step {i}: {e.Message}"; break; }
                    steps++;
                    var refv = lines[i].Split(',');
                    double G(int c) => double.Parse(refv[c], CultureInfo.InvariantCulture);
                    if (verbose && first_diff < 0)
                        for (int c = 1; c < hdr.Length; c++)
                            if (absf(Col(p, hdr[c]) - G(c)) > 2e-9 * maxf(1.0, absf(G(c))))
                            {
                                first_diff = i;
                                Console.WriteLine($"  FIRSTDIFF {name} step {i} {hdr[c]} c#={Col(p, hdr[c]):0.##########} gd={G(c):0.##########}");
                                break;
                            }
                    double pos = Math.Sqrt((p.x - G(ix)) * (p.x - G(ix)) + (p.y - G(iy)) * (p.y - G(iy)) + (p.z - G(iz)) * (p.z - G(iz)));
                    if (double.IsNaN(pos)) pos = 1e9;
                    if (pos > worst_pos) worst_pos = pos;
                    if (pos > POS_TOL && first_bad < 0)
                    {
                        first_bad = i;
                        double worst_dev = 0;
                        for (int c = 1; c < hdr.Length; c++)
                        {
                            double d = absf(Col(p, hdr[c]) - G(c));
                            if (double.IsNaN(d)) d = 1e9;
                            if (d > worst_dev) { worst_dev = d; worst_col = $"{hdr[c]} c#={Col(p, hdr[c]):0.####} gd={G(c):0.####}"; }
                        }
                    }
                }
                bool ok = err == null && first_bad < 0;
                if (!ok) bad++;
                Console.WriteLine($"TRACE {(ok ? "MATCH" : "DIFF ")} {name,-11} steps={steps} worst_pos={worst_pos:0.######} m" +
                    (first_bad >= 0 ? $" first_off=step {first_bad} (t={first_bad * dt:0.###}s) most_off: {worst_col}" : "") +
                    (err != null ? " ERROR " + err : ""));
            }
            return bad;
        }

        static double Col(BikeSim p, string c)
        {
            switch (c)
            {
                case "x": return p.x; case "y": return p.y; case "z": return p.z;
                case "v": return p.v; case "vy": return p.vy; case "heading": return p.heading;
                case "pitch": return p.pitch; case "bike_lean": return p.bike_lean; case "lean": return p.lean;
                case "steer": return p.steer; case "air": return p.air ? 1 : 0; case "body_y": return p.body_y;
                case "y_draw": return p.y_draw; case "pitch_draw": return p.pitch_draw; case "slip": return p.slip;
                case "crank": return p.crank; case "man_a": return p.man_a; case "crash": return p.crash_on ? 1 : 0;
            }
            return double.NaN;
        }
    }
}
