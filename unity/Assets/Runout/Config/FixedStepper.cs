using System;
using Runout.Sim;

namespace Runout.Config
{
    /// Anything stepped at the fixed physics rate (the bike, the ragdoll, the tape sim...).
    public interface ISimStep
    {
        /// One fixed step. Must be deterministic: same state + same input = same result.
        void Step(double dt, RideInput input);
        /// Copy the drawable state (for interpolation between the last two steps).
        void Capture(ref SimPose pose);
    }

    /// What the drawing reads from a step: enough to place the bike and drive the rider pose.
    /// Grows as systems are ported (Godot: the fields Game reads off BikePhysics each frame).
    public struct SimPose
    {
        public float X, Y, Z;
        public float Heading, Pitch, BikeLean, Steer;
        public float Speed, Vy;
        public bool Air;

        public static SimPose Lerp(in SimPose a, in SimPose b, float t)
        {
            SimPose p = b;
            p.X = a.X + (b.X - a.X) * t;
            p.Y = a.Y + (b.Y - a.Y) * t;
            p.Z = a.Z + (b.Z - a.Z) * t;
            p.Heading = LerpAngle(a.Heading, b.Heading, t);
            p.Pitch = a.Pitch + (b.Pitch - a.Pitch) * t;
            p.BikeLean = a.BikeLean + (b.BikeLean - a.BikeLean) * t;
            p.Steer = a.Steer + (b.Steer - a.Steer) * t;
            p.Speed = a.Speed + (b.Speed - a.Speed) * t;
            p.Vy = a.Vy + (b.Vy - a.Vy) * t;
            return p;
        }

        static float LerpAngle(float a, float b, float t)
        {
            float d = b - a;
            while (d > MathF.PI) d -= 2f * MathF.PI;
            while (d < -MathF.PI) d += 2f * MathF.PI;
            return a + d * t;
        }
    }

    /// Fixed-rate accumulator, independent of the engine's own physics tick (Godot: physics 120 Hz +
    /// drawing interpolated between the last two states). Feed it real frame time; it runs 0..MaxSteps steps
    /// and gives the interpolation factor between the previous and current pose.
    public sealed class FixedStepper
    {
        public const double Rate = 120.0;
        public const double Dt = 1.0 / Rate;
        public int MaxSteps = 8;   // a long hitch drops time rather than spiralling

        readonly ISimStep _sim;
        double _acc;
        SimPose _prev, _cur;
        public long Steps { get; private set; }

        public FixedStepper(ISimStep sim)
        {
            _sim = sim;
            _sim.Capture(ref _cur);
            _prev = _cur;
        }

        /// Returns how many steps ran. `input` is sampled once per frame and held for each step in it.
        public int Advance(double frameDt, RideInput input)
        {
            _acc += Math.Max(0.0, Math.Min(frameDt, 0.25));
            int n = 0;
            while (_acc >= Dt && n < MaxSteps)
            {
                _prev = _cur;
                _sim.Step(Dt, input);
                _sim.Capture(ref _cur);
                _acc -= Dt;
                n++;
                Steps++;
            }
            if (n == MaxSteps && _acc > Dt) _acc = 0;
            return n;
        }

        /// The pose to draw this frame (between the last two steps).
        public SimPose Drawn => SimPose.Lerp(_prev, _cur, (float)(_acc / Dt));
        public SimPose Current => _cur;
    }
}
