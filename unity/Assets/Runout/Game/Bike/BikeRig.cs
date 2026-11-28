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
            // measured off the meshes by unity/Tools/glb_extras.py (Godot: _grips, _split_pedals, _saddle)
            grip_l = extras.v3("rig.gripL", new Vector3(0f, 0f, -0.3f));
            grip_r = extras.v3("rig.gripR", new Vector3(0f, 0f, 0.3f));
            // the grips as cylinders (glb_extras.py measures any bar: width, sweep, rise): a rider holds a grip with the
            // little finger at the bar end, so the hand's middle sits HAND_IN in from the outer end, along the grip's axis
            if (extras.has("rig.gripLOut") && extras.has("rig.gripROut"))
            {
                Vector3 li = extras.v3("rig.gripLIn", grip_l), lo = extras.v3("rig.gripLOut", grip_l);
                Vector3 ri = extras.v3("rig.gripRIn", grip_r), ro = extras.v3("rig.gripROut", grip_r);
                grip_axis_l = (lo - li).normalized; grip_axis_r = (ro - ri).normalized;
                float inL = Mathf.Min(HAND_IN, (lo - li).magnitude * 0.5f), inR = Mathf.Min(HAND_IN, (ro - ri).magnitude * 0.5f);
                grip_l = lo - grip_axis_l * inL;
                grip_r = ro - grip_axis_r * inR;
                grip_radius = (float)extras.f("rig.gripLR", 0.014);
            }
            SplitPedals();
            pedal_l = extras.v3("rig.pedalL", new Vector3(0f, 0f, -0.1f));
            pedal_r = extras.v3("rig.pedalR", new Vector3(0f, 0f, 0.1f));
            pedal_top = (float)extras.f("rig.pedalTop", 0.017);
            var st = extras.list("rig.seat");
            if (st.Length == 3) seat = st;
        }

        // ---- the rider's contact points (Godot: limb_targets) ----
        public Vector3 grip_l, grip_r, pedal_l, pedal_r;   // steer / crank mesh space (Godot axes)
        public float pedal_top = 0.017f;
        public double[] seat;   // top, rear, front of the saddle (frame mesh space) or null

        /// a point in a part's own (Godot) mesh space -> Godot world
        public static Vector3 GPoint(Transform t, Vector3 local) => GodotSpace.PInv(t.TransformPoint(GodotSpace.M(local)));
        /// a Godot world point -> lean space (= the rider's space: Godot parents the rider to lean_g, identity)
        public Vector3 LeanLocal(Vector3 gworld) => Quaternion.Inverse(ModelRot) * (gworld - position);
        /// lean space -> Godot world
        public Vector3 LeanToWorld(Vector3 lean) => position + ModelRot * lean;

        public const float HAND_IN = 0.045f;   // m: the hand's middle in from the grip's outer end (half a gloved palm)
        public Vector3 grip_axis_l = new Vector3(0f, 0f, -1f), grip_axis_r = new Vector3(0f, 0f, 1f);   // steer mesh space, pointing out
        public float grip_radius = 0.014f;

        /// a grip's axis (pointing out of the bar end) in lean space, as the bar is turned now
        public Vector3 GripAxis(int side)
        {
            if (steer_n == null) return side == 0 ? Vector3.back : Vector3.forward;
            Vector3 a = side == 0 ? grip_axis_l : grip_axis_r;
            Vector3 g0 = GPoint(steer_n, Vector3.zero), g1 = GPoint(steer_n, a);
            return (Quaternion.Inverse(ModelRot) * (g1 - g0)).normalized;
        }

        // ---- pedals kept level (Godot: _pedals): the crank's "plastic" surface (both pedals) cut into one pedal per
        // side, each on its own pivot under the crank, turned back by the crank angle every frame (+ the rider's foot
        // pitch: flat pedals tip under the shoe) ----
        public readonly Transform[] pedal_pivots = new Transform[2];

        void SplitPedals()
        {
            if (crank_n == null) return;
            var mf = crank_n.GetComponent<MeshFilter>();
            var mr = crank_n.GetComponent<MeshRenderer>();
            if (mf == null || mr == null || mf.sharedMesh == null) return;
            Mesh mesh = mf.sharedMesh;
            if (!mesh.isReadable) { Debug.LogWarning("BikeRig: the crank mesh is not readable: the pedals turn with it"); return; }
            int si = -1;
            var mats = mr.sharedMaterials;
            for (int k = 0; k < mats.Length && k < mesh.subMeshCount; k++)
                if (mats[k] != null && mats[k].name.StartsWith("plastic")) si = k;
            if (si < 0) return;
            Vector3[] v = mesh.vertices; Vector3[] n = mesh.normals; Vector2[] uv = mesh.uv;
            int[] tri = mesh.GetTriangles(si);
            for (int side = 0; side < 2; side++)
            {
                float want = side == 0 ? -1f : 1f;   // (z is the same in Godot and in glTFast's mirrored-x space)
                var sel = new List<int>();
                Vector3 c = Vector3.zero; int cn = 0;
                for (int t = 0; t + 2 < tri.Length; t += 3)
                {
                    float zc = (v[tri[t]].z + v[tri[t + 1]].z + v[tri[t + 2]].z) / 3f;
                    if (Mathf.Sign(zc) != want || zc == 0f) continue;
                    for (int k = 0; k < 3; k++) { sel.Add(tri[t + k]); c += v[tri[t + k]]; cn++; }
                }
                if (cn == 0) continue;
                c /= cn;
                var remap = new Dictionary<int, int>();
                var pv = new List<Vector3>(); var pn = new List<Vector3>(); var pu = new List<Vector2>(); var pi = new List<int>();
                foreach (int vi in sel)
                {
                    if (!remap.TryGetValue(vi, out int ni))
                    {
                        ni = pv.Count; remap[vi] = ni;
                        pv.Add(v[vi] - c);
                        pn.Add(n != null && n.Length > vi ? n[vi] : Vector3.up);
                        pu.Add(uv != null && uv.Length > vi ? uv[vi] : Vector2.zero);
                    }
                    pi.Add(ni);
                }
                var pm = new Mesh { name = "pedal_" + (side == 0 ? "L" : "R") };
                pm.SetVertices(pv); pm.SetNormals(pn); pm.SetUVs(0, pu); pm.SetTriangles(pi, 0);
                pm.RecalculateBounds();
                var go = new GameObject(pm.name);
                go.transform.SetParent(crank_n, false);
                go.transform.localPosition = c;
                go.AddComponent<MeshFilter>().sharedMesh = pm;
                go.AddComponent<MeshRenderer>().sharedMaterial = mats[si];
                pedal_pivots[side] = go.transform;
                // (the pedal pivot's place = the foot's target: the measured centre in Godot axes)
                if (side == 0) pedal_l = GodotSpace.M(c); else pedal_r = GodotSpace.M(c);
            }
            // the crank without its pedals
            var cm = Instantiate(mesh);
            cm.name = mesh.name + "_nopedals";
            cm.SetTriangles(new int[0], si);
            mf.sharedMesh = cm;
        }

        static Mesh Instantiate(Mesh m) => UnityEngine.Object.Instantiate(m);

        /// turn the pedals back level against the crank, tipped by each foot's pitch (Godot: pivot.rotation.z = crank + foot_pitch)
        public void pose_pedals(float crank, float pitchL, float pitchR)
        {
            for (int i = 0; i < 2; i++)
                if (pedal_pivots[i] != null)
                    pedal_pivots[i].localRotation = GodotSpace.MRot(RotZ(crank + (i == 0 ? pitchL : pitchR)));
        }

        public struct Limbs { public Vector3 handL, handR, footL, footR, gripX, gripZ; }
        /// where the hands / feet go, in lean space (Godot BikeRig.limb_targets); the pedals are the pedal pivots
        /// (children of the crank: they go round with it)
        public Limbs limb_targets()
        {
            var o = new Limbs();
            if (steer_n != null)
            {
                o.handL = LeanLocal(GPoint(steer_n, grip_l));
                o.handR = LeanLocal(GPoint(steer_n, grip_r));
                Quaternion inv = Quaternion.Inverse(ModelRot);
                o.gripX = (inv * GodotSpace.WorldAxisX(steer_n)).normalized;
                o.gripZ = (inv * GodotSpace.WorldAxisZ(steer_n)).normalized;
            }
            if (crank_n != null)
            {
                o.footL = LeanLocal(GPoint(crank_n, pedal_l));
                o.footR = LeanLocal(GPoint(crank_n, pedal_r));
            }
            return o;
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
            pose_pedals(crank, 0f, 0f);   // (level; the rider tips them with his feet after posing)
            Place();
            susp?.apply();
        }

        /// the bars turned to `steer` about the steering axis (the crashed bike sets them alone)
        public void set_steer(float steer)
        {
            if (steer_n != null) steer_n.localRotation = GodotSpace.MRot(steerRest * Quaternion.AngleAxis(steer * Mathf.Rad2Deg, steer_axis));
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
