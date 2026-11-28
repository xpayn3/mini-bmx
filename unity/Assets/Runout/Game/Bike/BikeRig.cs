using System;
using System.Collections.Generic;
using UnityEngine;

namespace Runout.Game
{
    /// Port of godot/scripts/bike/bike_rig.gd's riding pose (drawing): root (position + heading) > pitch > lean > model,
    /// bars about the steering axis, wheels, cranks, the suspension (Suspension), fitting the wheels to the ground and
    /// lifting the bike out of it. Every number is in Godot space; the model (a glTFast-imported Godot glb) is placed
    /// through GodotSpace. Not ported yet: part swaps / paint / decals, the pedals kept level (they turn with the crank),
    /// the chain, wheel-size fit (fit_g = identity), the crashed bike's own body.
    public sealed class BikeRig
    {
        public readonly Transform model;
        public readonly BikeExtras extras;
        public Transform steer_n, wheel_f, wheel_r, crank_n;
        public Vector3 steer_axis = new Vector3(-0.2546f, 0.967f, 0f).normalized;
        public float wheel_rf = 0.374f, wheel_rr = 0.355f;
        public float tyre_hw = 0.03f;
        public Suspension susp;
        public float crank_angle;
        static readonly float[] TYRE_ACROSS = { -0.8f, 0f, 0.8f };

        // the rig chain (Godot: BikeRig node > pitch_g > lean_g > fit_g > model), Godot space
        public Vector3 position;
        public float heading, pitch_z, lean_x;
        Quaternion steerRest = Quaternion.identity, wfRest = Quaternion.identity, wrRest = Quaternion.identity, crRest = Quaternion.identity;

        public BikeRig(Transform model, BikeExtras extras)
        {
            this.model = model;
            this.extras = extras;
            steer_axis = extras.v3("steerAxis", steer_axis).normalized;
            steer_n = Find(model, "steer");
            wheel_f = Find(model, "wheel_front");
            wheel_r = Find(model, "wheel_rear");
            crank_n = Find(model, "crank");
            wheel_rf = (float)extras.f("wheelRadius", 0.261);
            wheel_rr = (float)extras.f("wheelRadiusRear", wheel_rf);
            if (steer_n != null) steerRest = GodotSpace.LocalRot(steer_n);
            if (wheel_f != null) wfRest = GodotSpace.LocalRot(wheel_f);
            if (wheel_r != null) wrRest = GodotSpace.LocalRot(wheel_r);
            if (crank_n != null) crRest = GodotSpace.LocalRot(crank_n);
            if (extras.has_prefix("suspension.")) susp = new Suspension(model, extras) { wheels_follow = true };
        }

        public static Transform Find(Transform root, string name)
        {
            if (root.name == name) return root;
            foreach (Transform c in root)
            {
                var r = Find(c, name);
                if (r != null) return r;
            }
            return null;
        }

        static Quaternion RotY(float a) => Quaternion.AngleAxis(a * Mathf.Rad2Deg, Vector3.up);
        static Quaternion RotZ(float a) => Quaternion.AngleAxis(a * Mathf.Rad2Deg, Vector3.forward);
        static Quaternion RotX(float a) => Quaternion.AngleAxis(a * Mathf.Rad2Deg, Vector3.right);

        /// the rig root's basis (heading only) and the model's Godot-space world rotation
        public Quaternion RootRot => RotY(heading);
        public Quaternion PitchRot => RootRot * RotZ(pitch_z);
        public Quaternion ModelRot => PitchRot * RotX(lean_x);

        /// write the chain to the model (call after changing position / heading / pitch_z / lean_x)
        public void Place() => GodotSpace.SetModelWorld(model, position, ModelRot);

        /// pose from the (interpolated) physics state (Godot: BikeRig.pose)
        public void pose(float px, float py, float pz, float hd, float pitch, float hop_nose, float lean,
                         float steer, float wf, float wr, float crank)
        {
            _ground_cache.Clear();
            position = new Vector3(px, py, pz);
            heading = hd;
            pitch_z = pitch + hop_nose;
            lean_x = -lean;
            if (steer_n != null) steer_n.localRotation = GodotSpace.MRot(steerRest * Quaternion.AngleAxis(steer * Mathf.Rad2Deg, steer_axis));
            if (wheel_f != null) wheel_f.localRotation = GodotSpace.MRot(wfRest * RotZ(-wf));
            if (wheel_r != null) wheel_r.localRotation = GodotSpace.MRot(wrRest * RotZ(-wr));
            if (crank_n != null) crank_n.localRotation = GodotSpace.MRot(crRest * RotZ(-crank));
            crank_angle = crank;
            Place();
            susp?.apply();
        }

        /// a point / axis of a part in Godot world space (the model placed by Place())
        public static Vector3 GPos(Transform t) => GodotSpace.WorldPos(t);

        /// How deep the tyre on `wheel` (radius R) sits inside the ground (m, > 0 = inside); ground = top(x, z)
        public float tyre_depth(Transform wheel, float R, Func<double, double, double> top)
        {
            Vector3 c = GodotSpace.WorldPos(wheel);
            Vector3 ax = GodotSpace.WorldAxisZ(wheel).normalized;
            Vector3 down = Vector3.down - ax * Vector3.Dot(ax, Vector3.down);
            float dl = down.magnitude;
            Vector3 d0 = dl > 1e-3f ? down / dl : GodotSpace.WorldAxisX(wheel).normalized;
            Vector3 side = Vector3.Cross(ax, d0);
            bool full = dl < 0.6f;
            int n = full ? 16 : 11;
            float hw = tyre_hw;
            float worst = float.NegativeInfinity;
            for (int i = 0; i < n; i++)
            {
                float a = full ? 2f * Mathf.PI * i / n : -1.4f + 2.8f * i / (n - 1);
                Vector3 dir = d0 * Mathf.Cos(a) + side * Mathf.Sin(a);
                foreach (float wo in TYRE_ACROSS)
                {
                    float off = wo * hw;
                    float r = R - hw + Mathf.Sqrt(hw * hw - off * off);
                    Vector3 p = c + dir * r + ax * off;
                    long key = ((long)Mathf.RoundToInt(p.x * 1000f) << 32) ^ (Mathf.RoundToInt(p.z * 1000f) & 0xffffffffL);
                    if (!_ground_cache.TryGetValue(key, out float h))
                    {
                        h = (float)top(p.x, p.z);
                        _ground_cache[key] = h;
                    }
                    worst = Mathf.Max(worst, h - p.y);
                }
            }
            return worst;
        }

        readonly Dictionary<long, float> _ground_cache = new Dictionary<long, float>();

        /// Riding: put each wheel on the ground with the suspension (the frame stays where the physics put the body)
        public void fit_wheels(Func<double, double, double> top)
        {
            if (susp == null || !susp.wheels_follow) return;
            // fork travel solved with the bars STRAIGHT (turning the bars must not compress the fork)
            Quaternion steer_q = steer_n != null ? steer_n.localRotation : Quaternion.identity;
            Quaternion straightQ = GodotSpace.MRot(steerRest);
            bool straight = steer_n != null && Quaternion.Angle(steer_q, straightQ) > 1e-3f && susp.has_f;
            if (straight) { steer_n.localRotation = straightQ; susp.apply(); }
            Quaternion mb = ModelRot;
            float up_f = Mathf.Max(0.4f, (mb * susp.axis).normalized.y);   // world rise per metre of fork travel
            float up_r = Mathf.Max(0.4f, (mb * Vector3.up).normalized.y);  // ... per metre of rear axle rise
            float gF = up_f, gR = up_r;
            float pdF = 0f, pdR = 0f, pxF = 0f, pxR = 0f;
            for (int it = 0; it < 6; it++)
            {
                float dF = tyre_depth(wheel_f, wheel_rf, top);
                float dR = tyre_depth(wheel_r, wheel_rr, top);
                if (it > 0)
                {
                    if (Mathf.Abs(susp.xF - pxF) > 1e-4f) gF = Mathf.Clamp((pdF - dF) / (susp.xF - pxF), up_f * 0.7f, 4f);
                    if (Mathf.Abs(susp.xR - pxR) > 1e-4f) gR = Mathf.Clamp((pdR - dR) / (susp.xR - pxR), up_r * 0.7f, 4f);
                }
                pdF = dF; pdR = dR; pxF = susp.xF; pxR = susp.xR;
                float nF = susp.has_f ? Mathf.Clamp(susp.xF + dF / gF, susp.F_min, susp.F_max) : 0f;
                float nR = susp.has_r ? Mathf.Clamp(susp.xR + dR / gR, susp.R_min, susp.R_max) : 0f;
                if (Mathf.Abs(nF - susp.xF) < 5e-4f && Mathf.Abs(nR - susp.xR) < 5e-4f) break;
                susp.xF = nF; susp.xR = nR;
                susp.apply();
            }
            if (straight) { steer_n.localRotation = steer_q; susp.apply(); }
        }

        /// Lift / tilt the drawn bike (not the physics) until no tyre is inside the ground, leaving `gap` m.
        /// Returns how deep the deepest tyre was before.
        public float unclip_tyres(Func<double, double, double> top, float gap = 0.003f)
        {
            float first = float.NegativeInfinity;
            for (int it = 0; it < 5; it++)
            {
                float pf = tyre_depth(wheel_f, wheel_rf, top) + gap;
                float pr = tyre_depth(wheel_r, wheel_rr, top) + gap;
                if (it == 0) first = Mathf.Max(pf, pr) - gap;
                if (pf <= 1e-4f && pr <= 1e-4f) break;
                pf = Mathf.Max(pf, 0f); pr = Mathf.Max(pr, 0f);
                // rotate about the pitch pivot (the rig's origin) + lift, so each wheel rises by what it needs
                Vector3 fw = (RootRot * Vector3.right).normalized;
                float aF = Vector3.Dot(GodotSpace.WorldPos(wheel_f) - position, fw);
                float aR = Vector3.Dot(GodotSpace.WorldPos(wheel_r) - position, fw);
                float dth = 0f;
                if (aF - aR > 0.3f && it < 4) dth = Mathf.Clamp((pf - pr) / (aF - aR), -0.25f, 0.25f);
                float dy = Mathf.Max(pf - aF * dth, pr - aR * dth);
                pitch_z += dth;
                position.y += dy;
                Place();
            }
            return first;
        }

        /// a world point in the pitch node's space (Godot: pitch_g.to_local)
        public Vector3 PitchLocal(Vector3 gworld) => Quaternion.Inverse(PitchRot) * (gworld - position);
    }
}
