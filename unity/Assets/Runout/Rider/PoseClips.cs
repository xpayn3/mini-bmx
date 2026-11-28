using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using Runout.Sim;

namespace Runout.Rider
{
    /// The Pose Lab clip library, port of godot/scripts/rider/pose_keys.gd (PoseKeys) + game.gd _pose_phase / _clip_signal /
    /// _clips_mix / _pose_keys_apply. STYLE only, never physics: authored ADDITIVE clips (keys of pose offsets over a
    /// timeline) faded in on top of the live procedural pose when the game's state says so (a whip, a tabletop, a flip, a
    /// manual, a jump...). Godot's default (no pose_keys.json: res://data has none) = the starter clips, library ON,
    /// amount 1. Of those "Jump style" has no keys (plays nothing) and "Attack stance" is off.
    ///
    /// Call Apply(dt, sim, pi) every drawn frame AFTER pi is filled and BEFORE RiderPose.update_pose (Godot's order).
    /// It reads from pi: "landFold", "preload", "popFx" (the jump timeline), "airWhip" (= Game._awhip_s), "bodyLat"
    /// (= Game._blat_s), "dab" (a foot down: no clips), and from the sim: air, _land_t, land_prep, land_reach, prep,
    /// squash_fx, auto_absorb, squash, flip_acc, yaw_rate, man_a, nose_a, bike_lean, sprint, pedal.
    /// It WRITES pi["pk"] = Dictionary<string, double> (channel -> offset; the channels in CH; empty = none), which
    /// RiderPose reads like rider.gd. When a "bike under body" key is on (rel_pitch / rel_roll), it also rewrites pi
    /// "handL", "handR", "footL", "footR" (points), "gripX_L", "gripX_R", "gripZ" (directions), "wheelR", "wheelF"
    /// (points) into the turned rider space: call SetCrankPivot first (see below).
    ///
    /// Outside pi (Game applied these; apply them in Unity):
    ///   barSteer  rad added to the DRAWN steer when the rig is posed (Godot: rig.pose(..., _steer_c - wobble * 1.5 + _pk_bar, ...),
    ///             _pk_bar = -bar_steer: + = left like the rig's steer). Used the NEXT frame in Godot (the rig is posed first).
    ///   riderXf   the rider node's transform in lean space (Godot: rider.transform = rt): the rider's whole pose (RiderPose
    ///             output, rider space) is drawn through it: lean = riderXf * riderPoint. IDENTITY when no key turns him.
    ///             = the bike turned under the body about the bottom bracket (crank centre) by -rel_roll about X, -rel_pitch
    ///             about Z (Basis(X, -rr) * Basis(Z, -rp)).
    ///   underBody true while riderXf is not identity.
    public sealed class PoseClips
    {
        /// [id, min, max] (Godot CH: angles rad, offsets m)
        public static readonly (string id, double min, double max)[] CH =
        {
            ("rel_pitch", -0.9, 0.9), ("rel_roll", -0.9, 0.9), ("bar_steer", -0.9, 0.9),
            ("hip_x", -0.3, 0.3), ("hip_y", -0.3, 0.3), ("hip_z", -0.25, 0.25),
            ("torso_pitch", -0.8, 0.8), ("torso_roll", -0.6, 0.6), ("torso_yaw", -0.8, 0.8),
            ("head_pitch", -0.6, 0.6), ("head_yaw", -0.9, 0.9),
            ("elbows_out", -0.6, 0.9), ("knees_out", -0.6, 0.9), ("wrist_bend", -0.6, 0.6), ("wrist_turn", -0.6, 0.6),
            ("grip", -1.0, 1.0), ("lever_pull", 0.0, 1.0),
        };
        /// channels that flip sign when a clip is mirrored (a left whip -> a right whip)
        public static readonly HashSet<string> MIRROR = new HashSet<string> { "rel_roll", "bar_steer", "hip_z", "torso_roll", "torso_yaw", "head_yaw", "wrist_turn" };

        public sealed class Key { public double t; public Dictionary<string, double> v = Zero(); }
        public sealed class Clip
        {
            public string name, trigger = "manual_only", time = "clip";
            public double length = 0.6, fade_in = 0.12, fade_out = 0.25, strength = 1.0;
            public bool mirror = true, enabled = true;
            public List<Key> ks = new List<Key>();
            // runtime (Godot rt(c)): fade weight, time since it fired, the side it fired on, its own timeline position
            public double w, age, side = 1.0, t = -1.0;
        }

        public readonly List<Clip> clips = new List<Clip>();
        public bool enabled = true;      // the clips play in rides
        public double amount = 1.0;      // how much of them all (0 .. 1.5)
        public double pose_t = -1.0;     // where on the jump timeline we are (-1 = not in a jump)
        double _pl_air;

        // outputs outside pi (see the class comment)
        public double barSteer;
        public Xf riderXf = Xf.IDENTITY;
        public bool underBody;
        Vec3 _crankPivot;
        bool _pivotSet;

        public PoseClips() { clips.AddRange(Starter()); }

        /// the crank centre in LEAN space this frame (Godot: rig.lean_g.to_local(rig.crank_n.global_position)): the pivot
        /// of a "bike under body" key. Set before Apply when such keys can play
        public void SetCrankPivot(Vec3 leanSpace) { _crankPivot = leanSpace; _pivotSet = true; }

        public static Dictionary<string, double> Zero()
        {
            var v = new Dictionary<string, double>(CH.Length);
            foreach (var c in CH) v[c.id] = 0.0;
            return v;
        }

        static (string id, double min, double max) Info(string id)
        {
            foreach (var c in CH) if (c.id == id) return c;
            return (id, -1e9, 1e9);
        }

        // ---- the starter library (pose_keys.gd starter()) ----
        static Key K(double t, params (string, double)[] vals)
        {
            var k = new Key { t = t };
            foreach (var (id, v) in vals) k.v[id] = v;
            return k;
        }

        static Clip Make(string nm, string trigger = "manual_only", string time = "clip") => new Clip { name = nm, trigger = trigger, time = time };

        public static List<Clip> Starter()
        {
            var o = new List<Clip>();
            var c = Make("Jump style", "jump", "jump"); c.fade_in = 0.05; c.fade_out = 0.1;
            o.Add(c);
            c = Make("Whip", "whip", "clip"); c.length = 0.45; c.fade_in = 0.08; c.fade_out = 0.3;
            c.ks.Add(K(0.0)); c.ks.Add(K(0.35, ("rel_roll", 0.35), ("torso_roll", -0.2), ("hip_z", -0.06), ("torso_yaw", 0.2), ("head_yaw", -0.25), ("knees_out", 0.25)));
            c.ks.Add(K(1.0, ("rel_roll", 0.45), ("torso_roll", -0.25), ("hip_z", -0.08), ("torso_yaw", 0.25), ("head_yaw", -0.3), ("knees_out", 0.3)));
            o.Add(c);
            c = Make("Tabletop", "tabletop", "clip"); c.length = 0.35; c.fade_in = 0.12; c.fade_out = 0.3;
            c.ks.Add(K(0.0)); c.ks.Add(K(1.0, ("rel_roll", 0.7), ("torso_roll", -0.3), ("hip_z", -0.1), ("knees_out", 0.4), ("elbows_out", 0.2), ("head_yaw", -0.2)));
            o.Add(c);
            c = Make("Scrub", "scrub", "clip"); c.length = 0.25; c.fade_in = 0.08; c.fade_out = 0.3;
            c.ks.Add(K(0.0)); c.ks.Add(K(1.0, ("rel_roll", 0.5), ("hip_y", -0.08), ("hip_x", -0.05), ("torso_pitch", 0.3), ("knees_out", 0.3)));
            o.Add(c);
            c = Make("Back flip tuck", "backflip", "clip"); c.length = 0.8; c.fade_in = 0.1; c.fade_out = 0.3; c.mirror = false;
            c.ks.Add(K(0.0)); c.ks.Add(K(0.4, ("hip_y", -0.06), ("torso_pitch", 0.35), ("head_pitch", 0.25), ("knees_out", 0.25)));
            c.ks.Add(K(1.0, ("hip_y", -0.04), ("torso_pitch", 0.2), ("head_pitch", 0.1)));
            o.Add(c);
            c = Make("Front flip tuck", "frontflip", "clip"); c.length = 0.8; c.fade_in = 0.1; c.fade_out = 0.3; c.mirror = false;
            c.ks.Add(K(0.0)); c.ks.Add(K(0.4, ("hip_y", -0.06), ("hip_x", 0.05), ("torso_pitch", 0.45), ("head_pitch", 0.3), ("knees_out", 0.2)));
            c.ks.Add(K(1.0, ("torso_pitch", 0.2), ("head_pitch", 0.1)));
            o.Add(c);
            c = Make("Manual", "manual", "clip"); c.length = 0.4; c.fade_in = 0.15; c.fade_out = 0.3; c.mirror = false;
            c.ks.Add(K(0.0)); c.ks.Add(K(1.0, ("hip_x", -0.07), ("hip_y", -0.03), ("torso_pitch", -0.2), ("head_pitch", -0.1)));
            o.Add(c);
            c = Make("Stoppie", "stoppie", "clip"); c.length = 0.4; c.fade_in = 0.15; c.fade_out = 0.3; c.mirror = false;
            c.ks.Add(K(0.0)); c.ks.Add(K(1.0, ("hip_x", 0.07), ("hip_y", 0.02), ("torso_pitch", 0.3), ("head_pitch", 0.15), ("elbows_out", 0.2)));
            o.Add(c);
            c = Make("Attack stance", "ground", "clip"); c.length = 0.5; c.fade_in = 0.3; c.fade_out = 0.3; c.mirror = false; c.enabled = false;
            c.ks.Add(K(0.0)); c.ks.Add(K(1.0, ("hip_y", -0.03), ("torso_pitch", 0.1), ("elbows_out", 0.25), ("knees_out", 0.15)));
            o.Add(c);
            return o;
        }

        // ---- Godot's pose_keys.json (v2: {"version", "enabled", "amount", "clips": [...]}; v1: {"keys": [...]} = the jump style) ----
        public bool LoadJson(string text)
        {
            object d;
            try { d = new Json(text).Value(); } catch { return false; }
            if (!(d is Dictionary<string, object> root)) return false;
            var list = new List<Clip>();
            enabled = Bool(root, "enabled", true);
            amount = Num(root, "amount", 1.0);
            if (root.TryGetValue("clips", out var cl) && cl is List<object> arr)
            {
                foreach (var cd in arr)
                {
                    if (!(cd is Dictionary<string, object> m)) continue;
                    var c = Make(Str(m, "name", "Clip"), Str(m, "trigger", "manual_only"), Str(m, "time", "clip"));
                    c.length = Math.Max(Num(m, "length", 0.6), 0.05);
                    c.fade_in = Math.Max(Num(m, "fade_in", 0.12), 0.0);
                    c.fade_out = Math.Max(Num(m, "fade_out", 0.25), 0.0);
                    c.strength = Num(m, "strength", 1.0);
                    c.mirror = Bool(m, "mirror", true);
                    c.enabled = Bool(m, "enabled", true);
                    c.ks = KeysFrom(m.TryGetValue("ks", out var ks) ? ks as List<object> : null);
                    list.Add(c);
                }
            }
            else if (root.TryGetValue("keys", out var k1))
            {
                var c = Make("Jump style", "jump", "jump"); c.fade_in = 0.05; c.fade_out = 0.1;
                c.ks = KeysFrom(k1 as List<object>);
                list.Add(c);
            }
            clips.Clear();
            clips.AddRange(list.Count > 0 ? list : Starter());
            return true;
        }

        static List<Key> KeysFrom(List<object> arr)
        {
            var o = new List<Key>();
            if (arr == null) return o;
            foreach (var e in arr)
            {
                if (!(e is Dictionary<string, object> k) || !k.ContainsKey("t")) continue;
                var key = new Key { t = Clamp(Num(k, "t", 0.0), 0.0, 1.0) };
                var vv = k.TryGetValue("v", out var vo) ? vo as Dictionary<string, object> : null;
                foreach (var c in CH) key.v[c.id] = vv != null ? Num(vv, c.id, 0.0) : 0.0;
                o.Add(key);
            }
            o.Sort((a, b) => a.t.CompareTo(b.t));
            return o;
        }

        static double Num(Dictionary<string, object> m, string k, double d) => m.TryGetValue(k, out var v) && v is double x ? x : (v is bool b ? (b ? 1.0 : 0.0) : d);
        static bool Bool(Dictionary<string, object> m, string k, bool d) => m.TryGetValue(k, out var v) ? (v is bool b ? b : (v is double x ? x != 0.0 : d)) : d;
        static string Str(Dictionary<string, object> m, string k, string d) => m.TryGetValue(k, out var v) && v is string s ? s : d;

        // ---- evaluation (pose_keys.gd eval_keys): Cardinal cubic between keys, neutral ends at 0 and 1 ----
        public static Dictionary<string, double> EvalKeys(List<Key> ks, double t, double k = 1.0)
        {
            var o = new Dictionary<string, double>();
            if (ks.Count == 0 || k <= 0.0 || t < 0.0) return o;
            t = Clamp(t, 0.0, 1.0);
            var ts = new List<double>(); var vs = new List<Dictionary<string, double>>();
            if (ks[0].t > 0.001) { ts.Add(0.0); vs.Add(Zero()); }
            foreach (var kk in ks) { ts.Add(kk.t); vs.Add(kk.v); }
            if (ks[ks.Count - 1].t < 0.999) { ts.Add(1.0); vs.Add(Zero()); }
            int n = ts.Count;
            int i = 0;
            while (i < n - 2 && t > ts[i + 1]) i++;
            int i1 = Math.Min(i + 1, n - 1);
            double t0 = ts[i], t1 = ts[i1];
            double u = t1 <= t0 + 1e-6 ? 0.0 : Clamp((t - t0) / (t1 - t0), 0.0, 1.0);
            int ia = Math.Max(i - 1, 0), ib = Math.Min(i1 + 1, n - 1);
            foreach (var c in CH)
            {
                string id = c.id;
                double p0 = vs[i][id], p1 = vs[i1][id];
                double m0 = (p1 - vs[ia][id]) / Math.Max(ts[i1] - ts[ia], 1e-4) * (t1 - t0);
                double m1 = (vs[ib][id] - p0) / Math.Max(ts[ib] - ts[i], 1e-4) * (t1 - t0);
                if (i == ia) m0 = p1 - p0;
                if (i1 == ib) m1 = p1 - p0;
                double u2 = u * u, u3 = u2 * u;
                double val = (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1;
                o[id] = Clamp(val * k, c.min * 1.5, c.max * 1.5);
            }
            return o;
        }

        // ---- game.gd ----

        static double F(PoseInput pi, string k) => pi.get(k) is double d ? d : (pi.get(k) is bool b ? (b ? 1.0 : 0.0) : 0.0);

        /// _pose_phase: where we are on the jump timeline (0..1; -1 = not in a jump)
        double PosePhase(double dt, BikeSim st, PoseInput pi)
        {
            if (st.air)
            {
                _pl_air += dt;
                double left = Math.Max(st._land_t, 0.0);
                double t = 0.40 + 0.40 * Clamp(_pl_air / Math.Max(_pl_air + left, 0.05), 0.0, 1.0);
                double rc = st.land_prep * st.land_reach;
                if (rc > 0.05) t = Math.Max(t, 0.80 + 0.10 * Clamp(rc, 0.0, 1.0));
                return t;
            }
            _pl_air = 0.0;
            double fold = F(pi, "landFold");
            if (fold > 0.03) return 0.90 + 0.10 * (1.0 - Clamp(fold, 0.0, 1.0));
            double pre = F(pi, "preload"), pfx = F(pi, "popFx");
            if (pfx > 0.05) return 0.30 + 0.10 * (1.0 - Clamp(pfx, 0.0, 1.0));
            if (pre > 0.03) return 0.12 + 0.18 * Clamp(pre, 0.0, 1.0);
            if (st.prep > 0.05) return 0.12 * Clamp(st.prep, 0.0, 1.0);
            return -1.0;
        }

        static double Sgn(double x) => x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0);

        /// _clip_signal: (how much 0..1, which side +-1). whip / tabletop read Game's smoothed _awhip_s / _blat_s = pi airWhip / bodyLat
        public (double x, double side) Signal(string trig, BikeSim st, PoseInput pi)
        {
            double awhip = F(pi, "airWhip"), blat = F(pi, "bodyLat");
            switch (trig)
            {
                case "jump": return (pose_t >= 0.0 ? 1.0 : 0.0, 1.0);
                case "whip": return (Clamp(Math.Abs(awhip) / 0.9, 0.0, 1.0), awhip != 0.0 ? Sgn(awhip) : 1.0);
                case "tabletop": return (st.air ? Clamp((Math.Abs(blat) - 0.25) / 0.55, 0.0, 1.0) : 0.0, blat != 0.0 ? Sgn(blat) : 1.0);
                case "scrub": return (Clamp(Math.Max(Math.Max(st.squash_fx, st.auto_absorb) * st.prep, st.squash * st.prep), 0.0, 1.0), 1.0);
                case "backflip": return (st.air ? Clamp(st.flip_acc / 1.2, 0.0, 1.0) : 0.0, 1.0);
                case "frontflip": return (st.air ? Clamp(-st.flip_acc / 1.2, 0.0, 1.0) : 0.0, 1.0);
                case "spin": return (st.air ? Clamp(Math.Abs(st.yaw_rate) / 3.0, 0.0, 1.0) : 0.0, st.yaw_rate != 0.0 ? Sgn(st.yaw_rate) : 1.0);
                case "manual": return (Clamp(st.man_a / 0.5, 0.0, 1.0), 1.0);
                case "stoppie": return (Clamp(st.nose_a / 0.4, 0.0, 1.0), 1.0);
                case "corner": return (!st.air ? Clamp(Math.Abs(st.bike_lean) / 0.6, 0.0, 1.0) : 0.0, st.bike_lean != 0.0 ? Sgn(st.bike_lean) : 1.0);
                case "sprint": return (Clamp(st.sprint * st.pedal, 0.0, 1.0), 1.0);
                case "air": return (st.air ? 1.0 : 0.0, 1.0);
                case "ground": return (st.air ? 0.0 : 1.0, 1.0);
                case "always": return (1.0, 1.0);
            }
            return (0.0, 1.0);
        }

        /// _clips_mix: every clip faded by its trigger, read on its own timeline, mirrored by its side, summed x strength x amount
        public Dictionary<string, double> Mix(double dt, BikeSim st, PoseInput pi)
        {
            var o = new Dictionary<string, double>();
            if (clips.Count == 0 || !enabled || F(pi, "dab") >= 0.01) return o;
            double step = Clamp(dt, 0.0, 0.1);
            foreach (var c in clips)
            {
                if (!c.enabled) continue;
                var sg = Signal(c.trigger, st, pi);
                double target = sg.x;
                double fade = target > c.w ? c.fade_in : c.fade_out;
                c.w = MoveToward(c.w, target, step / Math.Max(fade, 0.01));
                if (target > 0.02) { c.age += step; c.side = sg.side; }
                else if (c.w < 0.01) c.age = 0.0;
                double tl = c.time == "jump" ? pose_t : Clamp(c.age / Math.Max(c.length, 0.05), 0.0, 1.0);
                c.t = tl;
                if (tl < 0.0 || c.w < 0.002) continue;
                var v = EvalKeys(c.ks, tl, 1.0);
                if (v.Count == 0) continue;
                double wk = Smooth01(c.w) * c.strength;
                double flip = (c.mirror && c.side < 0.0) ? -1.0 : 1.0;
                foreach (var kv in v)
                {
                    double val = kv.Value * wk;
                    if (flip < 0.0 && MIRROR.Contains(kv.Key)) val = -val;
                    o[kv.Key] = (o.TryGetValue(kv.Key, out var was) ? was : 0.0) + val;
                }
            }
            if (o.Count == 0) return o;
            var res = new Dictionary<string, double>(o.Count);
            foreach (var kv in o)
            {
                var inf = Info(kv.Key);
                res[kv.Key] = Clamp(kv.Value * amount, inf.min * 1.5, inf.max * 1.5);
            }
            return res;
        }

        /// _pose_keys_apply: the jump timeline, the mix into pi["pk"], the drawn bars' key, and a "bike under body" key
        /// turning the rider about the crank centre (the limb targets / wheels in pi moved into his turned space)
        public void Apply(double dt, BikeSim st, PoseInput pi)
        {
            pose_t = PosePhase(dt, st, pi);
            var pk = Mix(dt, st, pi);
            pi["pk"] = pk;
            barSteer = -(pk.TryGetValue("bar_steer", out var bs) ? bs : 0.0);
            double rp = pk.TryGetValue("rel_pitch", out var a) ? a : 0.0;
            double rr = pk.TryGetValue("rel_roll", out var b) ? b : 0.0;
            if ((Math.Abs(rp) > 1e-4 || Math.Abs(rr) > 1e-4) && _pivotSet)
            {
                Basis rb = Basis.axis_angle(new Vec3(1, 0, 0), -rr) * Basis.axis_angle(new Vec3(0, 0, 1), -rp);
                riderXf = new Xf(rb, _crankPivot - rb * _crankPivot);
                underBody = true;
                Xf inv = riderXf.affine_inverse();
                foreach (var k in new[] { "handL", "handR", "footL", "footR", "wheelR", "wheelF" })
                    if (pi.get(k) is Vec3 p) pi[k] = inv * p;
                foreach (var k in new[] { "gripX_L", "gripX_R", "gripZ" })
                    if (pi.get(k) is Vec3 d) pi[k] = inv.b * d;
            }
            else
            {
                riderXf = Xf.IDENTITY;
                underBody = false;
            }
        }

        static double Clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
        static double MoveToward(double f, double t, double d) => Math.Abs(t - f) <= d ? t : f + Math.Sign(t - f) * d;
        static double Smooth01(double x) { x = Clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }

        /// a small JSON reader (objects -> Dictionary<string, object>, arrays -> List<object>, numbers -> double, bool, string, null)
        sealed class Json
        {
            readonly string s; int i;
            public Json(string text) { s = text; }
            void Ws() { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }
            public object Value()
            {
                Ws();
                if (i >= s.Length) throw new FormatException("end");
                char c = s[i];
                if (c == '{')
                {
                    i++; var d = new Dictionary<string, object>();
                    Ws(); if (s[i] == '}') { i++; return d; }
                    while (true)
                    {
                        Ws(); string k = (string)Value(); Ws();
                        if (s[i] != ':') throw new FormatException(":"); i++;
                        d[k] = Value(); Ws();
                        if (s[i] == ',') { i++; continue; }
                        if (s[i] == '}') { i++; return d; }
                        throw new FormatException("}");
                    }
                }
                if (c == '[')
                {
                    i++; var l = new List<object>();
                    Ws(); if (s[i] == ']') { i++; return l; }
                    while (true)
                    {
                        l.Add(Value()); Ws();
                        if (s[i] == ',') { i++; continue; }
                        if (s[i] == ']') { i++; return l; }
                        throw new FormatException("]");
                    }
                }
                if (c == '"')
                {
                    i++; var sb = new StringBuilder();
                    while (s[i] != '"')
                    {
                        if (s[i] == '\\')
                        {
                            i++; char e = s[i];
                            if (e == 'u') { sb.Append((char)Convert.ToInt32(s.Substring(i + 1, 4), 16)); i += 4; }
                            else sb.Append(e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e == 'b' ? '\b' : e == 'f' ? '\f' : e);
                        }
                        else sb.Append(s[i]);
                        i++;
                    }
                    i++; return sb.ToString();
                }
                if (s.Length - i >= 4 && string.CompareOrdinal(s, i, "true", 0, 4) == 0) { i += 4; return true; }
                if (s.Length - i >= 5 && string.CompareOrdinal(s, i, "false", 0, 5) == 0) { i += 5; return false; }
                if (s.Length - i >= 4 && string.CompareOrdinal(s, i, "null", 0, 4) == 0) { i += 4; return null; }
                int j = i;
                while (j < s.Length && "+-0123456789.eE".IndexOf(s[j]) >= 0) j++;
                double num = double.Parse(s.Substring(i, j - i), NumberStyles.Float, CultureInfo.InvariantCulture);
                i = j; return num;
            }
        }
    }
}
