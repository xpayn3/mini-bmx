using System;
using System.Collections.Generic;
using Runout.Config;
using Runout.Sim;

namespace Runout.Sim.Tests
{
    /// Headless checks of the engine plug. Each check prints PASS / FAIL; exit code = failures.
    /// Grows with the port: the Godot slope_stress checks and playground suite move here.
    static class Program
    {
        static int _fail;

        static int Main()
        {
            if (Environment.GetEnvironmentVariable("ALLOC_PROFILE") == "1") { AllocProfile.Run(); return 0; }
            // the world port vs Godot (WORLD_ONLY=1: just this)
            _fail += WorldCheck.Run(System.IO.Path.GetFullPath(System.IO.Path.Combine(RefDir(), "..")));
            if (Environment.GetEnvironmentVariable("WORLD_ONLY") == "1") { Console.WriteLine(_fail == 0 ? "SIMTESTS PASS" : $"SIMTESTS FAIL {_fail}"); return _fail; }
            StepperIsDeterministic();
            StepperInterpolates();
            BikeSmoke();
            RiderSmoke();
            PelvisCheck();
            _fail += CrashBikeSmoke.Run(System.IO.Path.GetFullPath(System.IO.Path.Combine(RefDir(), "..", "..")));
            RagdollSmoke();
            PoseClipsSmoke();
            StopsSmoke();
            // the bike physics port vs the Godot reference traces (godot/tools/port_trace.tscn -> SimTests/ref)
            int diff = TraceCompare.Run(RefDir(), Environment.GetEnvironmentVariable("TRACE_DETAIL") == "1");
            if (diff > 0) { Console.WriteLine($"FAIL trace_compare {diff} run(s) drift from Godot"); _fail += diff; }
            // the test playground course (Assets/Runout/Levels) vs Godot (godot/tools/pg_dump.gd -> SimTests/ref/playground)
            _fail += PlaygroundCheck.Run(RefDir());
            Console.WriteLine(_fail == 0 ? "SIMTESTS PASS" : $"SIMTESTS FAIL {_fail}");
            return _fail;
        }

        /// the shared ride (godot/sim BikeSim) on default tuning: pedals on flat ground for 5 s, then brakes; must stay
        /// finite and move
        static void BikeSmoke()
        {
            var h = new TraceCompare.Host();
            var tune = new Tune();
            var p = new BikeSim(h) { T = tune.fill(new RideParams()) }; h.phys = p;
            var mods = new GdDict(); mods.set("cogs", new List<double> { 11, 12, 14, 16, 18, 21, 24 }); mods["ring_k"] = 1.0;
            mods.set("susp", SuspSetup.resolve(null, SuspSetup.DEFAULT_SHOCK, "air", null).to_sim());
            var cfg = new GdDict(); cfg.set("geared", true); cfg.set("mods", mods);
            var ex = new GdDict(); ex["wheelbase"] = 1.2557; ex["wheelRadius"] = 0.374; ex["wheelRadiusRear"] = 0.355; ex["bbToRearAxle"] = 0.4423;
            p.setup(ex, cfg);
            p.reset_at(0, 0, 0);
            string err = null; double vmax = 0;
            var go = new RideInput(); go.set("throttle", 1.0);
            var stop = new RideInput(); stop.set("brake", 1.0);
            try
            {
                for (int i = 0; i < 600; i++) { p.step(1.0 / 120.0, go); vmax = Math.Max(vmax, p.v); }
                for (int i = 0; i < 360; i++) p.step(1.0 / 120.0, stop);
            }
            catch (Exception e) { err = e.GetType().Name + ": " + e.Message + " @ " + e.StackTrace?.Split('\n')[0]; }
            Check("bike_smoke", err == null && vmax > 4.0 && Math.Abs(p.v) < 1.0 && !double.IsNaN(p.x),
                err ?? $"vmax {vmax * 3.6:0.0} km/h, after braking {p.v * 3.6:0.0} km/h, x {p.x:0.0} m, crashed {p.crash_on}");
        }

        /// RiderStops: the bike rolls to a stop on flat ground, then on a 20 deg side slope (ground rising to the rider's
        /// right): the foot comes down; on the slope the uphill (right) foot is picked; no NaN
        static void StopsSmoke()
        {
            string err = null; int bad = 0; var log = new System.Text.StringBuilder();
            bool okAll = true;
            try
            {
                foreach (double slope in new[] { 0.0, 20.0 * Math.PI / 180.0 })
                {
                    var h = new TraceCompare.Host();
                    var st = new BikeSim(h) { T = new Tune().fill(new RideParams()) }; h.phys = st;
                    var rs = new Runout.Rider.RiderStops();
                    rs.top_height = (x, z) => z * Math.Tan(slope);   // heading +x: the rider's right = +z, the ground rises that way
                    var bb = new Runout.Rider.Vec3(0.0, 0.3, 0.0);
                    var fwd = new Runout.Rider.Vec3(1, 0, 0); var rgt = new Runout.Rider.Vec3(0, 0, 1);
                    double dt = 1.0 / 60.0, v = 3.0, maxDab = 0.0, stopW = 0.0;
                    for (int f = 0; f < 360; f++)
                    {
                        v = Math.Max(0.0, v - 2.5 * dt);
                        st.v = v; st.pedal = 0.0; st.air = false; st.crash_on = false; st.bike_lean = 0.0;
                        rs.update(dt, st, bb, fwd, rgt, 0.0);
                        double lean = rs.lean(0.0);
                        rs.update_hand_hip(dt);
                        foreach (double d in new[] { rs.dab_k, lean, rs.dab_lean_s, rs.idle_lean, rs.idle_steer, rs.look_yaw, rs.look_pitch, rs.stand_var, rs.stop_w })
                            if (double.IsNaN(d) || double.IsInfinity(d)) bad++;
                        maxDab = Math.Max(maxDab, rs.dab_k); stopW = Math.Max(stopW, rs.stop_w);
                    }
                    rs.Ground(bb, fwd, rgt, rs.dab_side, Runout.Rider.RiderStops.DAB_OUT, out var n);
                    bool ok = maxDab > 0.99 && (slope == 0.0 || rs.dab_side > 0.0);
                    okAll &= ok;
                    log.Append($"\n   slope {slope * 180 / Math.PI:0} deg: dab {maxDab:0.00}, side {(rs.dab_side < 0 ? "left" : "right")}, foot_down {st.foot_down}, lean {rs.dab_lean_s:0.000} rad, stop pose {rs.stop_mode} ({stopW:0.00}), ground normal ({n.x:0.00},{n.y:0.00},{n.z:0.00})");
                }
            }
            catch (Exception e) { err = e.ToString(); }
            Check("stops_smoke", err == null && bad == 0 && okAll, err ?? $"NaN {bad}{log}");
        }

        /// the Pose Lab clips (Assets/Runout/Rider/PoseClips.cs, port of PoseKeys + game.gd _clips_mix): a scripted jump
        /// (ground, preload, pop, air with a whip, reach, landing fold, then a manual); every clip's weight 4x a second, no NaN
        static void PoseClipsSmoke()
        {
            var h = new TraceCompare.Host();
            var st = new BikeSim(h) { T = new Tune().fill(new RideParams()) }; h.phys = st;
            var pc = new Runout.Rider.PoseClips();
            pc.SetCrankPivot(new Runout.Rider.Vec3(0.0, 0.3, 0.0));
            var pi = new Runout.Rider.PoseInput();
            string err = null; int bad = 0; double maxAbs = 0; var log = new System.Text.StringBuilder();
            double dt = 1.0 / 60.0;
            try
            {
                for (int f = 0; f < 240; f++)
                {
                    double t = f * dt;
                    pi.Clear();
                    pi["handL"] = new Runout.Rider.Vec3(0.44, 0.97, -0.39); pi["handR"] = new Runout.Rider.Vec3(0.44, 0.97, 0.39);
                    st.air = t >= 1.1 && t < 2.1;
                    st.prep = t >= 0.5 && t < 1.1 ? (t - 0.5) / 0.6 : 0.0;
                    pi["preload"] = st.prep * 0.8;
                    pi["popFx"] = t >= 1.0 && t < 1.4 ? 1.0 - (t - 1.0) / 0.4 : 0.0;
                    st._land_t = st.air ? 2.1 - t : 0.0;
                    st.land_prep = st.air && t > 1.8 ? (t - 1.8) / 0.3 : 0.0;
                    st.land_reach = 1.0;
                    pi["airWhip"] = st.air && t > 1.3 && t < 1.9 ? 0.8 : 0.0;
                    pi["bodyLat"] = 0.0;
                    pi["landFold"] = t >= 2.1 && t < 2.6 ? 1.0 - (t - 2.1) / 0.5 : 0.0;
                    st.man_a = t >= 3.0 && t < 3.6 ? 0.4 : 0.0;
                    pc.Apply(dt, st, pi);
                    var pk = pi["pk"] as Dictionary<string, double>;
                    foreach (var kv in pk) { if (double.IsNaN(kv.Value) || double.IsInfinity(kv.Value)) bad++; maxAbs = Math.Max(maxAbs, Math.Abs(kv.Value)); }
                    foreach (var c in pc.clips) if (double.IsNaN(c.w)) bad++;
                    if (f % 15 == 0)
                    {
                        log.Append($"\n   t {t:0.00} pose_t {pc.pose_t:0.00}:");
                        foreach (var c in pc.clips) if (c.w > 0.005) log.Append($" {c.name}={c.w:0.00}");
                        if (pc.underBody) log.Append(" [bike under body]");
                    }
                }
            }
            catch (Exception e) { err = e.GetType().Name + ": " + e.Message + " @ " + e.StackTrace?.Split('\n')[0]; }
            Check("poseclips_smoke", err == null && bad == 0, err ?? $"NaN {bad}, largest offset {maxAbs:0.000}{log}");
        }

        /// the hips + spine rule RiderView uses (the torso's lean shared: pelvis PELVIS_SHARE, spine the rest) through every kind
        /// of pose the solver makes: torso lean, pelvis tilt, lower back (lumbar) bend and hip flexion per scenario, flagged
        /// where a real body wouldn't be (the back arched backwards, folded past ~40 deg in the lumbar, a thigh behind the pelvis)
        static void PelvisCheck()
        {
            const double SHARE = 0.65;
            var scen = new (string name, Dictionary<string, object> keys)[]
            {
                ("coast attack", new Dictionary<string, object>{{"v",8.0}}),
                ("pedalling", new Dictionary<string, object>{{"v",8.0},{"pedal",1.0}}),
                ("sprint", new Dictionary<string, object>{{"v",8.0},{"pedal",1.0},{"sprint",1.0}}),
                ("slow sprint start", new Dictionary<string, object>{{"v",1.5},{"pedal",1.0},{"sprint",1.0}}),
                ("speed tuck", new Dictionary<string, object>{{"v",16.0},{"speedTuck",1.0}}),
                ("stick forward (tuck)", new Dictionary<string, object>{{"v",10.0},{"bodyStick",1.0}}),
                ("stick back (sit up)", new Dictionary<string, object>{{"v",8.0},{"bodyStick",-1.0}}),
                ("preload", new Dictionary<string, object>{{"v",9.0},{"preload",1.0},{"lipK",1.0}}),
                ("pop / extend", new Dictionary<string, object>{{"v",9.0},{"extend",0.1},{"popFx",1.0},{"lipK",1.0}}),
                ("air tuck", new Dictionary<string, object>{{"v",9.0},{"air",1.0},{"inAir",1.0},{"airPull",1.0}}),
                ("reach for landing", new Dictionary<string, object>{{"v",9.0},{"air",1.0},{"inAir",1.0},{"landReach",1.0}}),
                ("landing fold", new Dictionary<string, object>{{"v",9.0},{"landFold",1.0}}),
                ("squash", new Dictionary<string, object>{{"v",9.0},{"squash",1.0},{"lipK",1.0}}),
                ("manual", new Dictionary<string, object>{{"v",6.0},{"frontUp",0.5},{"pitch",0.5},{"bodyStick",-0.7}}),
                ("back flip arch", new Dictionary<string, object>{{"v",9.0},{"air",1.0},{"inAir",1.0},{"flipArch",1.0}}),
                ("stop: stand", new Dictionary<string, object>{{"v",0.0},{"dab",1.0},{"dabSide",-1.0},{"stopStand",1.0}}),
                ("stop: sit", new Dictionary<string, object>{{"v",0.0},{"dab",1.0},{"dabSide",-1.0},{"stopSit",1.0}}),
                ("deep lean turn", new Dictionary<string, object>{{"v",9.0},{"lean",0.9},{"counter",0.3}}),
            };
            var lines = new List<string>(); int flagged = 0; string err = null;
            double Sag(Runout.Rider.Vec3 v) => Math.Atan2(v.x, v.y) * 180.0 / Math.PI;   // forward of straight up, deg
            try
            {
                foreach (var (name, keys) in scen)
                {
                    var rp = new Runout.Rider.RiderPose();
                    rp.set_style(new Dictionary<string, double> { { "torso", 0.52 }, { "hipX", -0.07 }, { "hipY", 0.075 }, { "lean", 0.22 }, { "kneesOut", 0.25 }, { "spineCurve", 0.24 }, { "spineLow", 0.31 }, { "seatFloor", 1.0 } });
                    rp.seat = new double[] { 0.78, -0.3, -0.1 };
                    for (int f = 0; f < 120; f++)
                    {
                        double t = f / 60.0, crank = t * 9.0;
                        var p = new Runout.Rider.PoseInput();
                        p["footL"] = new Runout.Rider.Vec3(0.17 * Math.Cos(crank + Math.PI), 0.3 + 0.17 * Math.Sin(crank + Math.PI), -0.1);
                        p["footR"] = new Runout.Rider.Vec3(0.17 * Math.Cos(crank), 0.3 + 0.17 * Math.Sin(crank), 0.1);
                        p["handL"] = new Runout.Rider.Vec3(0.44, 0.97, -0.39); p["handR"] = new Runout.Rider.Vec3(0.44, 0.97, 0.39);
                        p["gripX_L"] = new Runout.Rider.Vec3(1, 0, 0); p["gripX_R"] = new Runout.Rider.Vec3(1, 0, 0); p["gripZ"] = new Runout.Rider.Vec3(0, 0, 1);
                        p["crank"] = crank; p["t"] = t; p["counter"] = 0.0; p["lean"] = 0.0; p["steer"] = 0.0; p["yawRate"] = 0.0;
                        p["pitch"] = 0.0; p["slope"] = 0.0; p["air"] = 0.0; p["inAir"] = 0.0; p["absorb"] = 0.0; p["frameY"] = 0.6; p["wheelY"] = 0.36;
                        p["wheelR"] = new Runout.Rider.Vec3(-0.44, 0.355, 0); p["wheelRR"] = 0.355;
                        p["wheelF"] = new Runout.Rider.Vec3(0.81, 0.374, 0); p["wheelRF"] = 0.374; p["pedal"] = 0.0;
                        foreach (var kv in keys) p[kv.Key] = kv.Value;
                        rp.update_pose(1.0 / 60.0, p);
                    }
                    var J = rp.J;
                    var tor = (J[1] - J[2]).normalized();
                    var up0 = new Runout.Rider.Vec3(0, 1, 0);
                    double lean0 = Math.Atan2(tor.x, tor.y) * 180.0 / Math.PI, kk = Math.Max(0.0, Math.Min(1.0, (lean0 - 50.0) / 25.0));
                    double share = SHARE + (0.5 - SHARE) * kk * kk * (3 - 2 * kk);   // (RiderView.PelvisShare)
                    var uh = (up0 * (1 - share) + tor * share).normalized();
                    double torso = Sag(tor), pelvis = Sag(uh), lumbar = torso - pelvis;
                    double Flex(Runout.Rider.Vec3 hip, Runout.Rider.Vec3 knee)
                    {
                        var th = (knee - hip).normalized();
                        double a = Math.Atan2(th.x, -th.y) * 180.0 / Math.PI, d = Math.Atan2(-uh.x, uh.y) * 180.0 / Math.PI;
                        return a - d;
                    }
                    double fl = Flex(J[9], J[10]), fr = Flex(J[12], J[13]);
                    var why = new List<string>();
                    if (lumbar < -8) why.Add("back arched");
                    if (lumbar > 40) why.Add("lumbar folded");
                    if (Math.Min(fl, fr) < -15) why.Add("thigh behind pelvis");
                    if (Math.Max(fl, fr) > 135) why.Add("hip over-flexed");
                    if (pelvis < -12) why.Add("pelvis tipped back");
                    if (why.Count > 0) flagged++;
                    lines.Add($"   {name,-22} torso {torso,6:0.0}  pelvis {pelvis,6:0.0}  lumbar {lumbar,6:0.0}  hip flex L {fl,6:0.0} R {fr,6:0.0} deg  {(why.Count > 0 ? "<< " + string.Join(", ", why) : "")}");
                }
            }
            catch (Exception e) { err = e.GetType().Name + ": " + e.Message; }
            Check("pelvis_check", err == null, err ?? $"{scen.Length} poses, {flagged} flagged\n" + string.Join("\n", lines));
        }

        /// the rider pose solver (Assets/Runout/Rider, port of rider.gd update_pose): a DH rider pedalling at 8 m/s for 300
        /// frames, a lean swap, then coasting; joints / bones finite, hands on the grips
        static void RiderSmoke()
        {
            var rp = new Runout.Rider.RiderPose();
            rp.set_style(new Dictionary<string, double> { { "torso", 0.52 } });
            rp.seat = new double[] { 0.78, -0.3, -0.1 };
            var hl = new Runout.Rider.Vec3(0.44, 0.97, -0.39);
            var hr = new Runout.Rider.Vec3(0.44, 0.97, 0.39);
            string err = null; double worst = 0; int bad = 0;
            try
            {
                for (int f = 0; f < 300; f++)
                {
                    double t = f / 60.0, crank = t * 9.0;
                    bool pedalling = f < 200;
                    var p = new Runout.Rider.PoseInput();
                    p["footL"] = new Runout.Rider.Vec3(0.17 * Math.Cos(crank + Math.PI), 0.3 + 0.17 * Math.Sin(crank + Math.PI), -0.1);
                    p["footR"] = new Runout.Rider.Vec3(0.17 * Math.Cos(crank), 0.3 + 0.17 * Math.Sin(crank), 0.1);
                    p["handL"] = hl; p["handR"] = hr;
                    p["gripX_L"] = new Runout.Rider.Vec3(1, 0, 0); p["gripX_R"] = new Runout.Rider.Vec3(1, 0, 0); p["gripZ"] = new Runout.Rider.Vec3(0, 0, 1);
                    p["v"] = 8.0; p["pedal"] = pedalling ? 1.0 : 0.0; p["crank"] = crank; p["t"] = t;
                    p["lean"] = f > 100 && f < 250 ? 0.5 * Math.Sin((f - 100) / 30.0) : 0.0; p["counter"] = 0.0;
                    p["steer"] = 0.0; p["yawRate"] = 0.0; p["pitch"] = 0.0; p["slope"] = 0.0; p["air"] = 0.0; p["inAir"] = 0.0;
                    p["absorb"] = 0.0; p["frameY"] = 0.6; p["wheelY"] = 0.36;
                    p["wheelR"] = new Runout.Rider.Vec3(-0.44, 0.355, 0); p["wheelRR"] = 0.355;
                    p["wheelF"] = new Runout.Rider.Vec3(0.81, 0.374, 0); p["wheelRF"] = 0.374;
                    rp.update_pose(1.0 / 60.0, p);
                    foreach (var j in rp.J) if (j.is_nan()) bad++;
                    foreach (var kv in rp.bones) if (kv.Value.o.is_nan() || kv.Value.b.y.is_nan()) bad++;
                    if (f > 30) worst = Math.Max(worst, Math.Max(rp.J[5].distance_to(hl), rp.J[8].distance_to(hr)));
                }
            }
            catch (Exception e) { err = e.GetType().Name + ": " + e.Message + " @ " + e.StackTrace?.Split('\n')[0]; }
            var J = rp.J;
            Check("rider_smoke", err == null && bad == 0 && worst < 0.02 && rp.bones.Count == 22,
                err ?? $"NaN {bad}, hands off grips max {worst * 100:0.0} cm, bones {rp.bones.Count}, pelvis {J[2]}, chest {J[1]}, head {J[0]}, knee L {J[10]}, elbow R {J[7]}");
        }

        /// the crash ragdoll (Assets/Runout/Rider/Ragdoll, port of ragdoll.gd + RagdollRbCs): a riding-shaped body thrown
        /// forward at 8 m/s from 1 m over flat ground, 4 s at 120 Hz (10 substeps); finite, never above 3 m, lies on the
        /// ground at the end, stopped
        static void RagdollSmoke()
        {
            double[] y = { 1.75, 1.45, 1.0, 1.45, 1.2, 1.05, 1.45, 1.2, 1.05, 0.95, 0.55, 0.1, 0.95, 0.55, 0.1 };
            double[] z = { 0, 0, 0, -0.2, -0.22, -0.22, 0.2, 0.22, 0.22, -0.1, -0.1, -0.1, 0.1, 0.1, 0.1 };
            double[] x = { 0.05, 0, 0, 0, 0.15, 0.4, 0, 0.15, 0.4, 0, 0.25, 0.1, 0, 0.25, 0.1 };
            var J = new Runout.Rider.Vec3[15];
            for (int i = 0; i < 15; i++) J[i] = new Runout.Rider.Vec3(x[i], y[i] + 1.0, z[i]);
            var rag = new Runout.Rider.Ragdoll { top_height = (gx, gz) => 0.0 };
            Runout.Rider.Ragdoll.CrashVelocity(new Runout.Rider.Vec3(1, 0, 0), 8.0, 0.0, true, out var vel, out var spin);
            var shL = new Runout.Rider.Xf(Runout.Rider.Basis.IDENTITY, J[11] + new Runout.Rider.Vec3(0.02, -0.05, 0));
            var shR = new Runout.Rider.Xf(Runout.Rider.Basis.IDENTITY, J[14] + new Runout.Rider.Vec3(0.02, -0.05, 0));
            string err = null, at4 = ""; int bad = 0; double top = 0, worstLimit = 0;
            var near = new List<(double, double, double, double)>();
            try
            {
                rag.start(J, vel, spin, shL, shR);
                for (int s = 0; s < 1200; s++)
                {
                    rag.step(1.0 / 120.0, near);
                    if (s == 479) at4 = $"at 4 s: speed {rag.speed:0.00} m/s, pain {rag.w_pain:0.00}, tuck {rag.w_tuck:0.00}, pelvis y {rag.p[2].y:0.00}";
                    foreach (var pt in rag.p) { if (pt.is_nan()) bad++; top = Math.Max(top, pt.y); }
                    worstLimit = Math.Max(worstLimit, rag.worst_limit());
                }
            }
            catch (Exception e) { err = e.GetType().Name + ": " + e.Message + " @ " + e.StackTrace?.Split('\n')[0]; }
            double highest = 0; string hb = "";
            for (int i = 0; i < Runout.Rider.Ragdoll.BODIES; i++)
            {
                double by = rag.body_y(i);
                if (by > highest) { highest = by; hb = Runout.Rider.Ragdoll.BODY_NAMES[i]; }
            }
            // a body lying on the ground: every part's centre within its own thickness + 0.2 m of it (the chest is 0.15 thick)
            Check("ragdoll_smoke", err == null && bad == 0 && top < 3.0 && highest < 0.35 && rag.speed < 0.3,
                err ?? $"NaN {bad}, highest point ever {top:0.00} m, highest body at the end {hb} {highest:0.00} m, speed {rag.speed:0.000} m/s, " +
                $"pelvis {rag.p[2]}, slid to x {rag.p[2].x:0.0} m, worst joint limit overshoot {worstLimit:0.000} rad, pain {rag.w_pain:0.00}; {at4}");
        }

        static string RefDir()
        {
            var d = new System.IO.DirectoryInfo(AppContext.BaseDirectory);
            while (d != null && !System.IO.Directory.Exists(System.IO.Path.Combine(d.FullName, "ref"))) d = d.Parent;
            return d == null ? "ref" : System.IO.Path.Combine(d.FullName, "ref");
        }

        static void Check(string name, bool ok, string detail = "")
        {
            Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name} {detail}");
            if (!ok) _fail++;
        }

        /// A trivial falling point: only here to exercise the plumbing, not a ride model.
        sealed class Dropper : ISimStep
        {
            public float Y = 5f, Vy;
            readonly IGround _g;
            public Dropper(IGround g) { _g = g; }
            public void Step(double dt, RideInput i)
            {
                Vy -= (float)(9.81 * dt); Y += (float)(Vy * dt);
                float h = (float)_g.height(0, 0);
                if (Y < h) { Y = h; Vy = 0; }
            }
            public void Capture(ref SimPose p) { p.Y = Y; p.Vy = Vy; }
        }

        sealed class Flat : IGround
        {
            public double height(double x, double z) => 0;
            public double deck_height(double x, double z) => 0;
            public double top_height(double x, double z) => 0;
            public long surface(double x, double z) => 1;
            public double jump_mask(double x, double z) => 0;
            public List<GdDict> colliders_near(double x, double z) => new List<GdDict>();
            public RayHit cast(V3 o, V3 d, double m) => new RayHit();
        }

        static void StepperIsDeterministic()
        {
            // Same total time fed in different frame chunks must give the same steps and state.
            var a = new Dropper(new Flat()); var sa = new FixedStepper(a);
            var b = new Dropper(new Flat()); var sb = new FixedStepper(b);
            for (int i = 0; i < 60; i++) sa.Advance(1.0 / 60.0, new RideInput());
            var rnd = new Random(1);
            double left = 1.0;
            while (left > 1e-9) { double d = Math.Min(left, rnd.NextDouble() * 0.03); sb.Advance(d, new RideInput()); left -= d; }
            Check("stepper_deterministic", sa.Steps == sb.Steps && a.Y == b.Y, $"steps {sa.Steps}/{sb.Steps} y {a.Y}/{b.Y}");
        }

        static void StepperInterpolates()
        {
            var a = new Dropper(new Flat()); var s = new FixedStepper(a);
            s.Advance(0.5 / 120.0, new RideInput());
            s.Advance(1.0 / 120.0, new RideInput());   // one step done, half a step left over
            var d = s.Drawn;
            Check("stepper_interpolates", d.Y < 5f && d.Y > a.Y, $"drawn {d.Y} current {a.Y}");
        }
    }
}
