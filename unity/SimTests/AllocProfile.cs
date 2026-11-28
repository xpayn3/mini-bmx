using System;
using System.Collections.Generic;
using System.Diagnostics.Tracing;
using System.Linq;
using Runout.Config;
using Runout.Sim;

namespace Runout.Sim.Tests
{
    /// ALLOC_PROFILE=1: what the ride physics allocates per step (garbage = collector pauses in the game). Rides the
    /// shared BikeSim on flat ground (pedal, turn, brake, hop) for 20k steps; counts exact bytes per step and, from the
    /// runtime's allocation sampling (one event per ~100 KB), which types make up the garbage.
    static class AllocProfile
    {
        sealed class Ticks : EventListener
        {
            public readonly Dictionary<string, long> types = new Dictionary<string, long>();
            protected override void OnEventSourceCreated(EventSource s)
            {
                if (s.Name == "Microsoft-Windows-DotNETRuntime") EnableEvents(s, EventLevel.Verbose, (EventKeywords)0x1);   // GC keyword
            }
            protected override void OnEventWritten(EventWrittenEventArgs e)
            {
                if (e.EventName != "GCAllocationTick_V4" && e.EventName != "GCAllocationTick_V3") return;
                int i = e.PayloadNames.IndexOf("TypeName");
                string t = i >= 0 ? e.Payload[i] as string : "?";
                lock (types) types[t] = types.TryGetValue(t, out var n) ? n + 1 : 1;
            }
        }

        public static void Run()
        {
            var h = new TraceCompare.Host();
            var p = new BikeSim(h) { T = new Tune().fill(new RideParams()) }; h.phys = p;
            var mods = new GdDict(); mods.set("cogs", new List<double> { 11, 12, 14, 16, 18, 21, 24 }); mods["ring_k"] = 1.0;
            mods.set("susp", SuspSetup.resolve(null, SuspSetup.DEFAULT_SHOCK, "air", null).to_sim());
            var cfg = new GdDict(); cfg.set("geared", true); cfg.set("mods", mods);
            var ex = new GdDict(); ex["wheelbase"] = 1.2557; ex["wheelRadius"] = 0.374; ex["wheelRadiusRear"] = 0.355; ex["bbToRearAxle"] = 0.4423;
            p.setup(ex, cfg);
            p.reset_at(0, 0, 0);
            var inp = new RideInput();
            for (int i = 0; i < 600; i++) { Drive(inp, i); p.step(1.0 / 120.0, inp); }   // warm up (JIT, caches)
            using var l = new Ticks();
            const int N = 20000;
            long b0 = GC.GetAllocatedBytesForCurrentThread();
            for (int i = 0; i < N; i++)
            {
                Drive(inp, i);
                p.step(1.0 / 120.0, inp);
                if (p.crash_on && i % 600 == 599) p.reset_at(p.x, 0, p.heading);
            }
            long b = GC.GetAllocatedBytesForCurrentThread() - b0;
            Console.WriteLine($"ALLOC physics: {b / (double)N:0} bytes per step ({b / 1048576.0:0.0} MB over {N} steps)");
            foreach (var kv in l.types.OrderByDescending(k => k.Value).Take(25))
                Console.WriteLine($"ALLOC type {kv.Value * 100 / Math.Max(1, l.types.Values.Sum()),3}% {kv.Key}");
        }

        static void Drive(RideInput inp, int i)
        {
            double t = i / 120.0;
            inp.set("throttle", (t % 8.0) < 6.0 ? 1.0 : 0.0);
            inp.set("brake", (t % 8.0) >= 6.5 ? 1.0 : 0.0);
            inp.set("steer", Math.Sin(t * 0.7) * 0.6);
            inp.set("hop", (t % 3.0) < 0.3 ? 1.0 : 0.0);
        }
    }
}
