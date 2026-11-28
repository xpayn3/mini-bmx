using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using Runout.Sim;
using static Runout.Sim.Gd;

namespace Runout.Sim.Tests
{
    /// Rides the C# BikePhysics through the same scripted runs as godot/tools/port_trace.gd and compares every step with
    /// the Godot reference (SimTests/ref/*.csv). A run "matches" while the position stays within POS_TOL of Godot's;
    /// the report shows the first step past that and the biggest gaps, which points at the stage to look at.
    static class TraceCompare
    {
        const double POS_TOL = 0.02;   // m

        /// slope_stress's synthetic ground (godot/tools/slope_stress.gd Ground), the kinds the trace runs use
        sealed class Ground : IGround
        {
            public string kind = "flat"; public double a, b, x0 = 20.0; public int surf = 0;
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
            public int surface(double x, double z) => surf;
            public double jump_mask(double x, double z) => 0.0;
            public void colliders_near(double x, double z, List<Obstacle> into) { }
        }

        sealed class Host : IBikeHost
        {
            public Ground g = new Ground();
            public BikePhysics phys;
            public string crash = "";
            public IGround terrain => g;
            public ISuspensionLimits susp => null;
            public bool msg_idle() => false;
            public void flow_up() => phys.flow_up();
            public void start_crash(string r) { if (crash == "") crash = r; phys.begin_crash(); }
        }

        static RideInput Input(string script, double t)
        {
            var i = new RideInput();
            switch (script)
            {
                case "pedal": i.throttle = 1.0; break;
                case "brake": i.brake = t > 1.0 ? 1.0 : 0.0; break;
                case "turn": i.throttle = 0.4; i.steer = t > 1.0 ? 0.5 : 0.0; break;
                case "swaps": i.throttle = 0.3; i.steer = t > 0.5 ? 0.7 * sin(TAU * t / 1.6) : 0.0; break;
                case "pump": i.hop = fmod(t, 1.0) < 0.45; break;
                case "hop": i.hop = (t > 1.0 && t < 1.35) || (t > 2.5 && t < 2.8); break;
                case "manual": i.body_fwd = (t > 1.0 && t < 3.0) ? -0.75 : 0.0; i.pad = true; break;
                case "sprint": i.throttle = 1.0; i.sprint = t > 0.5; break;
            }
            return i;
        }

        static double Num(JsonElement e) => e.ValueKind == JsonValueKind.True ? 1 : e.ValueKind == JsonValueKind.False ? 0 : e.GetDouble();

        static SuspSetup.Unit Unit(JsonElement u) => new SuspSetup.Unit
        {
            air = u.GetProperty("air").GetBoolean(), travel = Num(u.GetProperty("travel")), sag = Num(u.GetProperty("sag")),
            prog = Num(u.GetProperty("prog")), zc = Num(u.GetProperty("zc")), zr = Num(u.GetProperty("zr")),
            hs = Num(u.GetProperty("hs")), fric = Num(u.GetProperty("fric")), bump = Num(u.GetProperty("bump")),
        };

        /// returns the number of runs that drifted past the tolerance (0 = all match); -1 = no reference traces
        public static int Run(string refDir, bool verbose)
        {
            string cfgPath = Path.Combine(refDir, "config.json");
            if (!File.Exists(cfgPath)) { Console.WriteLine($"TRACE no reference at {refDir} (run godot/tools/port_trace.tscn)"); return -1; }
            var root = JsonDocument.Parse(File.ReadAllText(cfgPath)).RootElement;
            var tuneV = new Dictionary<string, double>();
            foreach (var p in root.GetProperty("tune").EnumerateObject()) tuneV[p.Name] = Num(p.Value);
            var ex = root.GetProperty("extras");
            var bc = new BikeConfig
            {
                wheelbase = Num(ex.GetProperty("wheelbase")), wheelRadius = Num(ex.GetProperty("wheelRadius")),
                wheelRadiusRear = Num(ex.GetProperty("wheelRadiusRear")), bbToRearAxle = Num(ex.GetProperty("bbToRearAxle")),
                land = Num(root.GetProperty("land")), geared = root.GetProperty("geared").GetBoolean(),
                ring_k = Num(root.GetProperty("ring_k")), mods_land = Num(root.GetProperty("mods_land")),
            };
            var cogs = new List<double>();
            foreach (var c in root.GetProperty("cogs").EnumerateArray()) cogs.Add(Num(c));
            bc.cogs = cogs.Count > 0 ? cogs : null;
            var su = root.GetProperty("susp");
            if (su.ValueKind == JsonValueKind.Object && su.TryGetProperty("f", out var fu))
                bc.susp = new SuspSetup.Setup { f = Unit(fu), r = Unit(su.GetProperty("r")), psi_f = Num(su.GetProperty("psi_f")), psi_r = Num(su.GetProperty("psi_r")) };
            var cols = new List<string>();
            foreach (var c in root.GetProperty("cols").EnumerateArray()) cols.Add(c.GetString());
            double dt = Num(root.GetProperty("dt"));

            int bad = 0;
            foreach (var r in root.GetProperty("runs").EnumerateArray())
            {
                string name = r[0].GetString();
                var h = new Host();
                h.g.kind = r[1].GetString(); h.g.a = Num(r[2]); h.g.b = Num(r[3]); h.g.x0 = Num(r[4]);
                var tune = new Tune();
                tune.set_effective(tuneV);
                var p = new BikePhysics(h, tune); h.phys = p;
                p.setup(bc);
                tune.set_effective(tuneV);   // (setup applied the bike's ride multipliers: the reference values already have them)
                p.reset_at(0.0, 0.0, 0.0);
                p.v = Num(r[5]);
                string script = r[7].GetString();
                var lines = File.ReadAllLines(Path.Combine(refDir, name + ".csv"));
                var hdr = lines[0].Split(',');
                int first_bad = -1; int first_diff = -1; double worst_pos = 0; string worst_col = ""; double worst_dev = 0; int steps = 0;
                string err = null;
                for (int i = 1; i < lines.Length; i++)
                {
                    double t = (i - 1) * dt;
                    try { p.step(dt, Input(script, t)); }
                    catch (Exception e) { err = $"{e.GetType().Name} at step {i}: {e.Message}"; break; }
                    steps++;
                    var refv = lines[i].Split(',');
                    if (verbose && first_diff < 0)
                        for (int c = 1; c < hdr.Length; c++)
                        {
                            double gv = double.Parse(refv[c], CultureInfo.InvariantCulture);
                            double cv = Col(p, hdr[c]);
                            if (absf(cv - gv) > 2e-9 * maxf(1.0, absf(gv)))
                            {
                                first_diff = i;
                                var sb = new System.Text.StringBuilder($"  FIRSTDIFF {name} step {i}:");
                                for (int c2 = 1; c2 < hdr.Length; c2++)
                                {
                                    double g2 = double.Parse(refv[c2], CultureInfo.InvariantCulture), v2 = Col(p, hdr[c2]);
                                    if (absf(v2 - g2) > 1e-12) sb.Append($" {hdr[c2]} {v2 - g2:E2}");
                                }
                                Console.WriteLine(sb.ToString());
                                break;
                            }
                        }
                    double gx = double.Parse(refv[Array.IndexOf(hdr, "x")], CultureInfo.InvariantCulture);
                    double gy = double.Parse(refv[Array.IndexOf(hdr, "y")], CultureInfo.InvariantCulture);
                    double gz = double.Parse(refv[Array.IndexOf(hdr, "z")], CultureInfo.InvariantCulture);
                    double pos = sqrt((p.x - gx) * (p.x - gx) + (p.y - gy) * (p.y - gy) + (p.z - gz) * (p.z - gz));
                    if (double.IsNaN(pos)) pos = 1e9;
                    if (pos > worst_pos) worst_pos = pos;
                    if (pos > POS_TOL && first_bad < 0)
                    {
                        first_bad = i;
                        // which column is furthest off at that step (the stage to look at)
                        for (int c = 1; c < hdr.Length; c++)
                        {
                            double gv = double.Parse(refv[c], CultureInfo.InvariantCulture);
                            double cv = Col(p, hdr[c]);
                            double d = absf(cv - gv);
                            if (double.IsNaN(d)) d = 1e9;
                            if (d > worst_dev) { worst_dev = d; worst_col = $"{hdr[c]} c#={cv:0.####} gd={gv:0.####}"; }
                        }
                    }
                }
                bool ok = err == null && first_bad < 0;
                if (!ok) bad++;
                Console.WriteLine($"TRACE {(ok ? "MATCH" : "DIFF ")} {name,-11} steps={steps} worst_pos={worst_pos:0.####} m" +
                    (first_bad >= 0 ? $" first_off=step {first_bad} (t={(first_bad) * dt:0.###}s) most_off: {worst_col}" : "") +
                    (err != null ? " ERROR " + err : ""));
            }
            return bad;
        }

        static double Col(BikePhysics p, string c)
        {
            switch (c)
            {
                case "t": return 0;
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
