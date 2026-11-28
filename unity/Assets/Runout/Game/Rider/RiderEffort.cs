using System;
using Runout.Sim;

namespace Runout.Game
{
    /// The rider's effort as the Godot HUD makes it up (godot/scripts/ui/hud.gd _ride_stats): pedalling power from the
    /// drive, a heart rate that builds and recovers slowly from power, sprint, used-up stamina, speed and a crash, and the
    /// cadence read off the cranks (which turn at the real gear ratio). The stamina itself is the sim's (BikeSim
    /// _step_sprint: sprintTime / sprintRecharge, tired below 0); the rider pose reads hr + stamina for its breathing /
    /// fatigue (pose inputs "hr", "stamina"). Plain C#: update once a drawn frame.
    public sealed class RiderEffort
    {
        public double hr = 72.0;     // bpm (72 at rest .. ~175 flat out)
        public double power;         // W
        public double cad;           // rpm, as the computer shows it
        double _crankLast = double.NaN;

        public void Reset() { hr = 72.0; power = 0.0; cad = 0.0; _crankLast = double.NaN; }

        public void Update(BikeSim st, double dt)
        {
            if (st == null || dt <= 0.0) return;
            if (double.IsNaN(_crankLast)) _crankLast = st.crank;
            double dc = st.crank - _crankLast;
            _crankLast = st.crank;
            double rpm = st.pedal > 0.15 && !st.air ? Math.Abs(dc) / Math.Max(dt, 1e-4) / (2.0 * Math.PI) * 60.0 : 0.0;
            cad += (Math.Min(rpm, 220.0) - cad) * Math.Min(1.0, dt * 3.0);
            double v = Math.Abs(st.v);
            double pw = 0.0;
            if (!st.air && !st.crash_on && st.pedal > 0.05)
                pw = 32.0 * Math.Max(0.0, st.a_pedal) * v + st.pedal * (30.0 + 5.0 * v);
            power += (Math.Min(pw, 1100.0) - power) * Math.Min(1.0, dt * 2.0);
            double hr_t = 68.0 + 95.0 * Clamp01(power / 650.0) + 22.0 * st.sprint + 18.0 * (1.0 - st.stamina)
                + 8.0 * Clamp01(v / 15.0) + (st.crash_on ? 25.0 : 0.0);
            hr += (hr_t - hr) * Math.Min(1.0, dt * 0.35);
        }

        /// heart-rate zone 1..5 (as the computer's EFFORT page)
        public int Zone => Math.Max(1, Math.Min(5, (int)((hr - 95.0) / 18.0) + 1));

        static double Clamp01(double x) => x < 0.0 ? 0.0 : x > 1.0 ? 1.0 : x;
    }
}
