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
            StepperIsDeterministic();
            StepperInterpolates();
            BikeSmoke();
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
