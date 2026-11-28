using System.Collections.Generic;
using System.Diagnostics;
using Runout.Sim;
using Debug = UnityEngine.Debug;

namespace Runout.Game
{
    /// The game side of the ride (Godot: Game, as the physics' host; adapter model: godot/scripts/bike/RideBridge.cs).
    /// The world it rides on, the messages it shows, crashes and getting up. Grows as HUD / fx / ragdoll are ported.
    public sealed class RideHost : IRideHost
    {
        public BikeSim sim;
        readonly IGround _ground;
        readonly List<double> _pedal_a0 = new List<double> { 0.0, System.Math.PI };
        static readonly Stopwatch _clock = Stopwatch.StartNew();
        long _frames;

        public RideHost(IGround ground) { _ground = ground; }

        public IGround terrain => _ground;
        public ISusp drawnSusp;               // the drawn suspension (BikeRig's Suspension), null = none drawn
        public ISusp susp => drawnSusp;
        public object ragdoll => null;        // (ragdoll port)
        public object getup_anim => null;
        public List<double> pedal_a0 => _pedal_a0;
        public bool has_method(string name) => true;

        public void flash(string text) => Debug.Log("RIDE " + text);
        public bool msg_idle() => true;
        public bool smash(GdDict c, V3 vel, V3 pos) => false;
        public void rock_chips(GdDict c) { }
        public void burst(V3 pos, long n, long surf, double power) { }
        /// the crash (Godot Game.start_crash): the physics' crash state, then our crashed-bike body and the ragdoll
        public CrashView crash;
        public System.Action<string> onCrash;            // (the rider: the ragdoll starts from his pose)
        public System.Action<double, RideInput> onCrashStep;
        public System.Action onGetUp;
        public void start_crash(string reason)
        {
            Debug.Log("CRASH " + reason);
            sim.begin_crash();
            crash?.Begin(reason.Contains("BAIL"));
            onCrash?.Invoke(reason);
        }
        /// getting up (Mecanim get-up clips come later): back on the bike where it lies
        public void begin_getup()
        {
            crash?.End();
            onGetUp?.Invoke();
            sim.get_up();
        }
        public void on_style(long points, string text) { }
        public void on_trick(string trick) { }
        public void on_takeoff() { }
        public void on_landing(double air_time, double impact) { }
        public void on_bad_landing(double k) { }
        public void ride_fx(double dt, V3 f, double va, bool in_water) { }
        public void log(string text) => Debug.Log(text);
        public void crashlog_note(string text) => Debug.Log(text);
        public void crash_body_step(BikeSim s, double dt, RideInput inp)
        {
            crash?.Step(dt, inp);
            onCrashStep?.Invoke(dt, inp);
        }
        public long get_ticks_usec() => _clock.ElapsedTicks * 1_000_000 / Stopwatch.Frequency;
        public long get_ticks_msec() => _clock.ElapsedMilliseconds;
        public long get_physics_frames() => _frames;
        public void tick() => _frames++;
    }
}
