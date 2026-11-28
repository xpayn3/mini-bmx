using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Rider
{
    /// rider_skeleton.gd follow + _carry_fold: the Godot humanoid profile's body bones placed on the posed rider, global
    /// poses in RIDER space (RiderPose.bones). Fingers / eyes / jaw are not posed (they keep their rest under the hand /
    /// head on the Unity side).
    public sealed class RiderSkeleton
    {
        public static readonly string[] BODY = { "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
            "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
            "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
            "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
            "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes" };

        /// the profile T-pose in rider space (Godot SkeletonProfileHumanoid reference poses composed, origins x SCALE 1.17,
        /// turned by TO_RIDER; dumped from Godot 4.7): origin, then the basis columns x, y, z
        static readonly double[][] REST =
        {
            new double[] { 0, 0.8775, 0,       0, 0, -1,  0, 1, 0,   1, 0, 0 },    // Hips
            new double[] { 0, 0.9945, 0,       0, 0, -1,  0, 1, 0,   1, 0, 0 },    // Spine
            new double[] { 0, 1.1115, 0,       0, 0, -1,  0, 1, 0,   1, 0, 0 },    // Chest
            new double[] { 0, 1.2285, 0,       0, 0, -1,  0, 1, 0,   1, 0, 0 },    // UpperChest
            new double[] { 0, 1.3455, 0,       0, 0, -1,  0, 1, 0,   1, 0, 0 },    // Neck
            new double[] { 0, 1.4625, 0,       0, 0, -1,  0, 1, 0,   1, 0, 0 },    // Head
            new double[] { 0, 1.3455, -0.0585, 1, 0, 0,   0, 0, -1,  0, 1, 0 },    // LeftShoulder
            new double[] { 0, 1.3455, -0.117, -1, 0, 0,   0, 0, -1,  0, -1, 0 },   // LeftUpperArm
            new double[] { 0, 1.3455, -0.4095, 0, -1, 0,  0, 0, -1,  1, 0, 0 },    // LeftLowerArm
            new double[] { 0, 1.3455, -0.702, -1, 0, 0,   0, 0, -1,  0, -1, 0 },   // LeftHand
            new double[] { 0, 1.3455, 0.0585, -1, 0, 0,   0, 0, 1,   0, 1, 0 },    // RightShoulder
            new double[] { 0, 1.3455, 0.117,   1, 0, 0,   0, 0, 1,   0, -1, 0 },   // RightUpperArm
            new double[] { 0, 1.3455, 0.4095,  0, 1, 0,   0, 0, 1,   1, 0, 0 },    // RightLowerArm
            new double[] { 0, 1.3455, 0.702,   1, 0, 0,   0, 0, 1,   0, -1, 0 },   // RightHand
            new double[] { 0, 0.8775, -0.117,  0, 0, 1,   0, -1, 0,  1, 0, 0 },    // LeftUpperLeg
            new double[] { 0, 0.43875, -0.117, 0, 0, -1, 0, -1, 0,  -1, 0, 0 },   // LeftLowerLeg
            new double[] { 0, 0, -0.117,       0, 0, 1,   1, 0, 0,   0, 1, 0 },    // LeftFoot
            new double[] { 0.1755, 0, -0.117,  0, 0, -1,  1, 0, 0,   0, -1, 0 },   // LeftToes
            new double[] { 0, 0.8775, 0.117,   0, 0, 1,   0, -1, 0,  1, 0, 0 },    // RightUpperLeg
            new double[] { 0, 0.43875, 0.117,  0, 0, -1,  0, -1, 0,  -1, 0, 0 },   // RightLowerLeg
            new double[] { 0, 0, 0.117,        0, 0, 1,   1, 0, 0,   0, 1, 0 },    // RightFoot
            new double[] { 0.1755, 0, 0.117,   0, 0, -1,  1, 0, 0,   0, -1, 0 },   // RightToes
        };

        static readonly Dictionary<string, Basis> _rest_g = new Dictionary<string, Basis>();
        static RiderSkeleton()
        {
            for (int i = 0; i < BODY.Length; i++)
            {
                var r = REST[i];
                _rest_g[BODY[i]] = new Basis(new Vec3(r[3], r[4], r[5]), new Vec3(r[6], r[7], r[8]), new Vec3(r[9], r[10], r[11]));
            }
        }

        public static void FillRest(Dictionary<string, Xf> into)
        {
            for (int i = 0; i < BODY.Length; i++)
            {
                var r = REST[i];
                into[BODY[i]] = new Xf(_rest_g[BODY[i]], new Vec3(r[0], r[1], r[2]));
            }
        }

        readonly Vec3[] _fold_prev = new Vec3[4];
        public void reset() { for (int i = 0; i < 4; i++) _fold_prev[i] = Vec3.ZERO; }

        /// a basis whose bone axis (y) points along d, the rest pose swung there (shortest arc), then twisted about d so
        /// the rest axis rest_ref points as close to ref as it can (rider_skeleton.gd _aim)
        static Basis _aim(string b, Vec3 d, Vec3 rest_ref, Vec3 rf)
        {
            Basis r = _rest_g[b];
            if (d.length_squared() < 1e-10) return r;
            d = d.normalized();
            Quat q = r.y.normalized().dot(d) > -0.9999 ? Quat.arc(r.y.normalized(), d) : Quat.axis_angle(r.x.normalized(), Math.PI);
            Basis qb = Basis.from_quat(q);
            Basis s = qb * r;
            if (rf.length_squared() > 1e-10)
            {
                Vec3 a = qb * rest_ref;
                a -= d * a.dot(d);
                Vec3 t = rf - d * rf.dot(d);
                if (a.length_squared() > 1e-8 && t.length_squared() > 1e-8)
                    s = Basis.axis_angle(d, a.normalized().signed_angle_to(t.normalized(), d)) * s;
            }
            return s;
        }

        Vec3 _carry_fold(int k, Vec3 bend, double seg_len, Vec3 line, Vec3 fallback)
        {
            Vec3 ln = line.length_squared() > 1e-10 ? line.normalized() : Vec3.UP;
            Vec3 prev = _fold_prev[k];
            prev = prev - ln * prev.dot(ln);
            if (prev.length_squared() < 1e-8) prev = fallback - ln * fallback.dot(ln);
            Vec3 outv = prev.length_squared() > 1e-8 ? prev.normalized() : bend;
            if (outv.length_squared() > 1e-8 && bend.dot(outv) < 0.0) bend = -bend;
            double s = smoothstep(0.03, 0.15, bend.length() / maxf(seg_len, 1e-4));
            if (s > 0.0 && bend.length_squared() > 1e-10)
                outv = outv.length_squared() > 1e-8 && outv.dot(bend.normalized()) > -0.999 ? outv.slerp(bend.normalized(), s) : bend.normalized();
            if (outv.length_squared() < 1e-8) outv = fallback;
            _fold_prev[k] = outv;
            return outv;
        }

        static void Put(RiderPose rp, string b, Vec3 at, Basis bas) => rp.bones[b] = new Xf(bas, at);

        /// rider_skeleton.gd follow: the bones from the posed joints (rp.J), spine, head, gloves, shoes
        public void follow(RiderPose rp)
        {
            Vec3[] P = rp.J;
            Xf[] spine = rp.spine;
            Xf head_t = rp.head;
            var fwd = new Vec3(1, 0, 0); var up = new Vec3(0, 1, 0);
            Vec3 pe = P[2];
            Vec3 hip_r = P[12] - P[9];
            Vec3 sh_r = P[6] - P[3];
            Vec3 hips_mid = (P[9] + P[12]) * 0.5;
            Vec3 tor_up = P[1] - pe;
            Put(rp, "Hips", hips_mid, _aim("Hips", tor_up, new Vec3(0, 0, 1), hip_r));
            Vec3 spine_at(double t)
            {
                double u = clampf(t, 0.0, 1.0) * (spine.Length - 1);
                int k = Math.Min((int)u, spine.Length - 2);
                var m = new Vec3(0, t - 0.5, 0);
                return (spine[k] * m).lerp(spine[k + 1] * m, u - k);
            }
            Vec3 s1 = spine_at(0.3), s2 = spine_at(0.6), s3 = spine_at(0.85);
            Vec3 collar = spine[spine.Length - 1] * new Vec3(0, 0.5, 0);
            Vec3 head_base = head_t * new Vec3(rp.NECK_TOP_X, rp.NECK_TOP_Y, 0.0);
            Put(rp, "Spine", s1, _aim("Spine", s2 - s1, new Vec3(0, 0, 1), sh_r.lerp(hip_r, 0.6)));
            Put(rp, "Chest", s2, _aim("Chest", s3 - s2, new Vec3(0, 0, 1), sh_r.lerp(hip_r, 0.3)));
            Put(rp, "UpperChest", s3, _aim("UpperChest", collar - s3, new Vec3(0, 0, 1), sh_r));
            Put(rp, "Neck", collar, _aim("Neck", head_base - collar, new Vec3(1, 0, 0), head_t.b.x));
            Put(rp, "Head", head_base, _aim("Head", head_t.b.y, new Vec3(1, 0, 0), head_t.b.x));
            for (int i = 0; i < 2; i++)
            {
                string side = i == 0 ? "Left" : "Right";
                int o = i * 3;
                Vec3 sh = P[3 + o], el = P[4 + o], ha = P[5 + o];
                Vec3 hp = P[9 + o], kn = P[10 + o], ft = P[11 + o];
                Xf hand_t = i == 0 ? rp.handL : rp.handR;
                Xf shoe_t = i == 0 ? rp.shoeL : rp.shoeR;
                Vec3 bend_a = (el - sh) - (el - sh).project(ha - sh);
                Vec3 fold = _carry_fold(i, -bend_a, (el - sh).length(), ha - sh, -fwd);
                Put(rp, side + "Shoulder", collar.lerp(sh, 0.15), _aim(side + "Shoulder", sh - collar, up, tor_up));
                Put(rp, side + "UpperArm", sh, _aim(side + "UpperArm", el - sh, fwd, fold));
                Put(rp, side + "LowerArm", el, _aim(side + "LowerArm", ha - el, fwd, fold));
                Vec3 wrist = ha - hand_t.b.x.normalized() * rp.WRIST_TO_GRIP;
                Put(rp, side + "Hand", wrist, _aim(side + "Hand", hand_t.b.x, up, hand_t.b.y));
                Vec3 bend_l = (kn - hp) - (kn - hp).project(ft - hp);
                Vec3 kf = _carry_fold(2 + i, bend_l, (kn - hp).length(), ft - hp, fwd);
                Put(rp, side + "UpperLeg", hp, _aim(side + "UpperLeg", kn - hp, fwd, kf));
                Put(rp, side + "LowerLeg", kn, _aim(side + "LowerLeg", ft - kn, fwd, kf));
                Vec3 toe_dir = shoe_t.b.x.normalized();
                Put(rp, side + "Foot", ft, _aim(side + "Foot", toe_dir, up, shoe_t.b.y));
                Put(rp, side + "Toes", shoe_t.o + toe_dir * rp.TOES_FWD, _aim(side + "Toes", toe_dir, up, shoe_t.b.y));
            }
        }
    }
}
