using System.Collections.Generic;
using UnityEngine;

namespace Runout.Game
{
    /// Port of godot/scripts/bike/suspension.gd (drawing): a fork that slides along the steer axis and a Horst-link
    /// four-bar rear end (chainstay G1-C1, seatstay C1-C2 carrying the axle A, rocker G2-C2-D, shock FE-D). Each end in
    /// metres of WHEEL travel from sag (+ = deeper). Riding (wheels_follow) the frame stays where the physics put the
    /// body and BikeRig.fit_wheels sets xF / xR so the tyres touch the ground. Godot-space maths; parts are written
    /// through GodotSpace (the model is a glTFast import).
    public sealed class Suspension
    {
        static readonly string[] PART_NAMES = { "fork_lower", "swing", "seatstay", "rocker", "shock_body", "shock_spring", "shock_shaft" };

        readonly Transform bike;
        readonly Dictionary<string, Transform> n = new Dictionary<string, Transform>();
        public Vector3 axis = new Vector3(-0.2546f, 0.967f, 0f);
        public bool has_f, has_r;
        Vector3 lower0;
        public float F_min, F_max, R_min, R_max;
        public float xF, vF, xR, vR;
        Vector2 fax0;
        float slope0, spring_len = 0.1f;
        readonly List<Vector2> table = new List<Vector2>();   // (phi, rise) sorted by rise
        Vector2 prev_c2;
        public float last_stroke;
        public bool wheels_follow = true;
        Vector3 springScale0 = Vector3.one;

        Vector2 G1, G2, C1, C2, A, D, FE;
        float lCS, lR, lSS, phi0, ss0, rk0, sh0, L0;

        static Transform Find(Transform root, string name)
        {
            if (root.name == name) return root;
            foreach (Transform c in root)
            {
                var r = Find(c, name);
                if (r != null) return r;
            }
            return null;
        }

        /// the node's position in the bike's Godot model space
        Vector2 _pos(string name)
        {
            var o = Find(bike, name);
            if (o == null) return Vector2.zero;
            Vector3 w = GodotSpace.ToModel(bike, o.position);
            return new Vector2(w.x, w.y);
        }

        public Suspension(Transform p_bike, BikeExtras data)
        {
            bike = p_bike;
            foreach (var k in PART_NAMES) n[k] = Find(bike, k);
            axis = data.v3("steerAxis", axis).normalized;
            bool f = data.has("suspension.fork.travel");
            bool r = data.has("suspension.rear.travel");
            has_f = f && n["fork_lower"] != null;
            has_r = r && n["swing"] != null;
            if (has_f)
            {
                lower0 = GodotSpace.LocalPos(n["fork_lower"]);
                float sag = (float)data.f("suspension.fork.sag"), tr = (float)data.f("suspension.fork.travel");
                F_min = -sag * tr; F_max = (1f - sag) * tr;
            }
            if (has_r)
            {
                float sag = (float)data.f("suspension.rear.sag"), tr = (float)data.f("suspension.rear.travel");
                R_min = -sag * tr; R_max = (1f - sag) * tr;
            }
            if (n["shock_spring"] != null) springScale0 = n["shock_spring"].localScale;
            fax0 = _pos("wheel_front");
            if (!has_r)
            {
                A = _pos("wheel_rear");
                slope0 = Mathf.Atan2(fax0.y - A.y, fax0.x - A.x);
                return;
            }
            // ---- four-bar, rest pose ----
            G1 = data.v2("suspension.rear.G1"); G2 = data.v2("suspension.rear.G2"); C1 = data.v2("suspension.rear.C1");
            C2 = data.v2("suspension.rear.C2"); A = data.v2("suspension.rear.A"); D = data.v2("suspension.rear.D"); FE = data.v2("suspension.rear.FE");
            lCS = Vector2.Distance(C1, G1); lR = Vector2.Distance(C2, G2); lSS = Vector2.Distance(C2, C1);
            phi0 = Mathf.Atan2(C1.y - G1.y, C1.x - G1.x);
            ss0 = Mathf.Atan2(C2.y - C1.y, C2.x - C1.x);
            rk0 = Mathf.Atan2(C2.y - G2.y, C2.x - G2.x);
            sh0 = Mathf.Atan2(D.y - FE.y, D.x - FE.x);
            L0 = Vector2.Distance(D, FE);
            spring_len = (float)data.f("suspension.rear.springLen", 0.1);
            // table: chainstay angle -> axle rise (relative to the frame). Walk both ways from rest.
            var rows = new List<Vector2>();
            foreach (int dir in new[] { -1, 1 })
            {
                Vector2 c2 = C2;
                for (int i = dir < 0 ? 1 : 0; i < 400; i++)
                {
                    float phi = phi0 + dir * i * 0.002f;
                    if (!solve(phi, c2, out var p)) break;
                    c2 = p.C2;
                    rows.Add(new Vector2(phi, p.A.y - A.y));
                }
            }
            rows.Sort((a, b) => a.y.CompareTo(b.y));
            table.AddRange(rows);
            slope0 = Mathf.Atan2(fax0.y - A.y, fax0.x - A.x);
            prev_c2 = C2;
        }

        struct Pose { public Vector2 C1, C2, A, D; public float ss, rk; }

        static Vector2 Rot(Vector2 v, float a) { float c = Mathf.Cos(a), s = Mathf.Sin(a); return new Vector2(v.x * c - v.y * s, v.x * s + v.y * c); }

        /// the linkage at chainstay angle phi (prev: last C2, picks the branch of the circle intersection)
        bool solve(float phi, Vector2 prev, out Pose p)
        {
            p = default;
            var c1 = new Vector2(G1.x + lCS * Mathf.Cos(phi), G1.y + lCS * Mathf.Sin(phi));
            float d = Vector2.Distance(c1, G2);
            if (d > lR + lSS || d < Mathf.Abs(lR - lSS)) return false;
            float a = (lR * lR - lSS * lSS + d * d) / (2f * d);
            float h = Mathf.Sqrt(Mathf.Max(0f, lR * lR - a * a));
            float ex = (c1.x - G2.x) / d, ey = (c1.y - G2.y) / d;
            float mx = G2.x + a * ex, my = G2.y + a * ey;
            var s1 = new Vector2(mx - h * ey, my + h * ex);
            var s2 = new Vector2(mx + h * ey, my - h * ex);
            var c2 = (s1 - prev).sqrMagnitude < (s2 - prev).sqrMagnitude ? s1 : s2;
            float ss = Mathf.Atan2(c2.y - c1.y, c2.x - c1.x);
            float rk = Mathf.Atan2(c2.y - G2.y, c2.x - G2.x);
            p.C1 = c1; p.C2 = c2; p.ss = ss; p.rk = rk;
            p.A = c1 + Rot(A - C1, ss - ss0);
            p.D = G2 + Rot(D - G2, rk - rk0);
            return true;
        }

        float phi_for(float rise)
        {
            var t = table;
            if (t.Count == 0) return phi0;
            if (t.Count == 1) return t[0].x;
            if (rise <= t[0].y) return t[0].x;
            if (rise >= t[t.Count - 1].y) return t[t.Count - 1].x;
            int lo = 0, hi = t.Count - 1;
            while (hi - lo > 1)
            {
                int m = (lo + hi) >> 1;
                if (t[m].y < rise) lo = m; else hi = m;
            }
            float u = (rise - t[lo].y) / Mathf.Max(1e-9f, t[hi].y - t[lo].y);
            return t[lo].x + (t[hi].x - t[lo].x) * u;
        }

        static Quaternion RotZ(float a) => Quaternion.AngleAxis(a * Mathf.Rad2Deg, Vector3.forward);

        public void apply()
        {
            // fork: the lowers (and the wheel on them) slide up the steer axis
            if (has_f)
                GodotSpace.SetLocal(n["fork_lower"], lower0 + axis * xF, GodotSpace.LocalRot(n["fork_lower"]));
            if (has_r) pose_rear();
            // (riding: wheels_follow, the frame stays where the physics put it: the garage's frame move is not ported)
        }

        /// four-bar at the angle that lifts the axle by xR
        void pose_rear()
        {
            if (!solve(phi_for(xR), prev_c2, out var p)) solve(phi0, C2, out p);
            prev_c2 = p.C2;
            float phi = Mathf.Atan2(p.C1.y - G1.y, p.C1.x - G1.x);
            SetRotZ(n["swing"], phi - phi0);
            if (n["seatstay"] != null)
                GodotSpace.SetLocal(n["seatstay"], new Vector3(p.C1.x, p.C1.y, 0f), RotZ(p.ss - ss0));
            if (n["rocker"] != null) SetRotZ(n["rocker"], p.rk - rk0);
            float sh = Mathf.Atan2(p.D.y - FE.y, p.D.x - FE.x);
            if (n["shock_body"] != null) SetRotZ(n["shock_body"], sh - sh0);
            if (n["shock_shaft"] != null)
                GodotSpace.SetLocal(n["shock_shaft"], new Vector3(p.D.x, p.D.y, 0f), RotZ(sh - sh0));
            last_stroke = L0 - Vector2.Distance(p.D, FE);
            if (n["shock_spring"] != null)
            {
                var s = springScale0;
                s.y = springScale0.y * Mathf.Max(0.3f, (spring_len - last_stroke) / Mathf.Max(1e-3f, spring_len));
                n["shock_spring"].localScale = s;
            }
        }

        /// Godot's `node.rotation.z = a` on a part whose rest rotation is level (the exporters' parts are)
        static void SetRotZ(Transform t, float a) => t.localRotation = GodotSpace.MRot(RotZ(a));

        /// the sag each end sits at (0..1 of its travel), from the ride's suspension setup
        public void set_sag(float sag_f, float sag_r)
        {
            if (has_f)
            {
                float tf = F_max - F_min, s = Mathf.Clamp(sag_f, 0.05f, 0.6f);
                F_min = -s * tf; F_max = (1f - s) * tf;
            }
            if (has_r)
            {
                float tr = R_max - R_min, s = Mathf.Clamp(sag_r, 0.05f, 0.6f);
                R_min = -s * tr; R_max = (1f - s) * tr;
            }
        }
    }
}
