using System;
using System.Collections.Generic;

namespace Runout.Rider
{
    /// The rider's fingers, port of godot/scripts/rider/glove_fingers.gd (GloveFingers.pose) + rider.gd _pose_fingers /
    /// _curl_to. Everything in the HAND's space (RiderPose.handL / handR: +X along the forearm toward the fingers, +Y the
    /// back of the hand, +Z along the bar; the origin is the grip point). On the bike every finger wraps the bar (the
    /// joints on a circle of GRIP_R round it, the thumb the other way under it), tighter with load (landings, braking);
    /// the INDEX and MIDDLE rest on the brake lever and squeeze it with the brake (left hand = rear lever, right = front).
    /// Output per phalanx: Godot humanoid bone name + its direction in hand space (the bones' own lengths come from the
    /// model: only directions are retargeted).
    public sealed class RiderFingers
    {
        public const double GRIP_R = 0.0305, KNUCKLE_ANG = 0.96, OPEN_ANG = -0.12, RELAXED = 0.4;
        static readonly (string name, double z, double[] L, double off)[] FINGERS =
        {
            ("Index", 0.0345, new[] { 0.034, 0.021, 0.018 }, 0.00),
            ("Middle", 0.0115, new[] { 0.037, 0.023, 0.019 }, 0.04),
            ("Ring", -0.0115, new[] { 0.035, 0.022, 0.018 }, 0.00),
            ("Little", -0.0335, new[] { 0.028, 0.017, 0.015 }, -0.10),
        };
        static readonly double[] CURL_EXP = { 0.7, 1.15, 1.7 };
        static readonly double[] LEVER_REST = { -0.30, -0.55, -0.85 };
        static readonly double[] LEVER_PULL = { -0.62, -0.95, -1.25 };
        static readonly Vec3 THUMB_BASE = new Vec3(-0.046, 0.010, 0.026);
        const double THUMB_Z = 0.056, THUMB_START = 2.75, THUMB_OPEN = -0.5;
        static readonly double[] THUMB_L = { 0.029, 0.024 };
        static readonly string[] PH = { "Proximal", "Intermediate", "Distal" };

        // per hand (0 left, 1 right)
        public readonly double[] curls = { RELAXED, RELAXED };
        readonly double[][] fin = { new double[5], new double[5] };
        readonly double[] lever = new double[2], pull = new double[2];
        readonly double[] _lev_s = new double[2], _pull_s = new double[2], _grip_s = new double[2];
        public double leverFingers = 1.0;
        /// this frame's state per hand (0 left, 1 right): each finger's curl [thumb, index, middle, ring, little]
        /// (0 open .. 1 round the bar), index + middle on the lever (0..1), the lever squeezed (0..1)
        public double finger_curl(int hand, int finger) => fin[hand][finger];
        public double on_lever(int hand) => lever[hand];
        public double squeeze(int hand) => pull[hand];

        static double clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
        static double move_toward(double f, double t, double d) => Math.Abs(t - f) <= d ? t : f + Math.Sign(t - f) * d;
        static double lerp_angle(double a, double b, double w)
        {
            double diff = (b - a) % (2 * Math.PI);
            double dist = (2.0 * diff) % (2 * Math.PI) - diff;
            return a + dist * w;
        }

        /// rider.gd: the curl eased to the bar (or relaxed standing), then _pose_fingers' grip / lever / squeeze
        public void update(double dt, bool standing, double brakeF, double brakeR, double landFold, double pkGrip = 0.0, double pkPull = 0.0)
        {
            double step = clamp(dt > 0.0 ? dt : 1.0 / 60.0, 0.0, 0.1);
            for (int i = 0; i < 2; i++)
            {
                curls[i] = move_toward(curls[i], standing ? RELAXED : 1.0, dt * 5.0);
                double brake = clamp(i == 0 ? brakeR : brakeF, 0.0, 1.0);
                double load_k = clamp(landFold * 0.8 + Math.Max(brakeF, brakeR) * 0.5, 0.0, 1.0);
                _lev_s[i] = move_toward(_lev_s[i], standing ? 0.0 : leverFingers, step * 4.0);
                _pull_s[i] += (brake - _pull_s[i]) * (1.0 - Math.Exp(-14.0 * step));
                _grip_s[i] += (load_k - _grip_s[i]) * (1.0 - Math.Exp(-8.0 * step));
                double tight = clamp(_grip_s[i] + pkGrip, -1.0, 1.0);
                double b = curls[i];
                double hold = clamp(0.9 + 0.1 * tight, 0.3, 1.0);
                fin[i][0] = Math.Min(b, hold); fin[i][1] = Math.Min(b, hold - 0.02); fin[i][2] = Math.Min(b, hold - 0.02);
                fin[i][3] = Math.Min(b, hold); fin[i][4] = Math.Min(b, hold + 0.02);
                lever[i] = _lev_s[i];
                pull[i] = clamp(_pull_s[i] + pkPull, 0.0, 1.0);
            }
        }

    }
}
