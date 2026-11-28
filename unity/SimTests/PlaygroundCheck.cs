using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;
using Runout.Levels;
using Runout.Sim;

namespace Runout.Sim.Tests
{
    /// The playground course port (unity/Assets/Runout/Levels) vs Godot's PlaygroundCourse: ref/playground/playground.txt.gz
    /// (written by godot/tools/pg_dump.gd). Every lane profile, feature, bowl, rock, spawn and ~150k ground samples.
    /// Then PlacedFeature: a placed copy of a lane feature must have the lane's shape along its own axis.
    static class PlaygroundCheck
    {
        static int _bad;
        static readonly List<string> _msgs = new List<string>();

        static void Bad(string m) { _bad++; if (_msgs.Count < 25) _msgs.Add(m); }

        // ---- the dump's value format (see pg_dump.gd _val)
        static double Hx(string hex)
        {
            var b = new byte[8];
            for (int i = 0; i < 8; i++) b[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber);
            return BitConverter.ToDouble(b, 0);
        }
        static byte[] Bytes(string hex)
        {
            var b = new byte[hex.Length / 2];
            for (int i = 0; i < b.Length; i++) b[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber);
            return b;
        }

        /// parsed value: double, long, bool, string, float[], List<object>, Dictionary<string, object>
        static object Val(string s, ref int i)
        {
            char t = s[i];
            if (t == 'D') { i += 1; return Dict(s, ref i); }
            i += 2;   // "x:"
            switch (t)
            {
                case 'f': { var v = Hx(s.Substring(i, 16)); i += 16; return v; }
                case 'i': { int j = i; while (i < s.Length && (char.IsDigit(s[i]) || s[i] == '-')) i++; return long.Parse(s.Substring(j, i - j)); }
                case 'b': { bool v = s[i] == '1'; i++; return v; }
                case 's': { int j = i; while (i < s.Length && ";}|]\t".IndexOf(s[i]) < 0) i++; return s.Substring(j, i - j); }
                case 'h':
                    {
                        int j = i; while (i < s.Length && Uri.IsHexDigit(s[i])) i++;
                        var b = Bytes(s.Substring(j, i - j));
                        var f = new float[b.Length / 4];
                        for (int k = 0; k < f.Length; k++) f[k] = BitConverter.ToSingle(b, k * 4);
                        return f;
                    }
                case 'a':
                    {
                        var l = new List<object>();
                        i++;   // '['
                        while (s[i] != ']') { l.Add(Val(s, ref i)); if (s[i] == '|') i++; }
                        i++;
                        return l;
                    }
                case 'd': return Dict(s, ref i);
            }
            throw new Exception("bad value at " + i + ": " + s.Substring(Math.Max(0, i - 10), Math.Min(40, s.Length - Math.Max(0, i - 10))));
        }
        static Dictionary<string, object> Dict(string s, ref int i)
        {
            var d = new Dictionary<string, object>();
            i++;   // '{'
            while (s[i] != '}')
            {
                int e = s.IndexOf('=', i);
                string k = s.Substring(i, e - i);
                i = e + 1;
                d[k] = Val(s, ref i);
                if (s[i] == ';') i++;
            }
            i++;
            return d;
        }
        static object ParseVal(string s) { int i = 0; return Val(s, ref i); }

        static string Rect(Rect4 r) => $"{r.x},{r.z},{r.w},{r.h}";
        static string Rect(string hexes)
        {
            var p = hexes.Split(',');
            return $"{(float)Hx(p[0])},{(float)Hx(p[1])},{(float)Hx(p[2])},{(float)Hx(p[3])}";
        }

        static void Num(string what, double want, double got)
        {
            if (!(want == got || (double.IsNaN(want) && double.IsNaN(got)))) Bad($"{what}: godot {want:R} c# {got:R}");
        }

        static void Arrays(string what, List<object> want, List<double[]> got)
        {
            if (want.Count != got.Count) { Bad($"{what}: count godot {want.Count} c# {got.Count}"); return; }
            for (int i = 0; i < want.Count; i++)
            {
                var w = (List<object>)want[i];
                if (w.Count != got[i].Length) { Bad($"{what}[{i}] length"); continue; }
                for (int k = 0; k < w.Count; k++) Num($"{what}[{i}][{k}]", Convert.ToDouble(w[k], CultureInfo.InvariantCulture), got[i][k]);
            }
        }

        static void FeatField(Feature f, string k, object v)
        {
            string w = $"feat {f.id}.{k}";
            switch (k)
            {
                case "id": if ((string)v != f.id) Bad($"{w}: godot {v} c# {f.id}"); break;
                case "name": if ((string)v != f.name) Bad($"{w}: godot '{v}' c# '{f.name}'"); break;
                case "desc": if ((string)v != f.desc) Bad($"{w}: godot '{v}' c# '{f.desc}'"); break;
                case "lane": if ((string)v != f.lane) Bad($"{w}: godot {v} c# {f.lane}"); break;
                case "kind": if ((string)v != f.kind) Bad($"{w}: godot {v} c# {f.kind}"); break;
                case "which": if ((string)v != f.which) Bad($"{w}: godot {v} c# {f.which}"); break;
                case "bowl": if (f.bowl == null || (string)v != f.bowl.id) Bad($"{w}: godot {v}"); break;
                case "jump": if ((bool)v != f.jump) Bad($"{w}"); break;
                case "surf": if ((long)v != f.surf) Bad($"{w}: godot {v} c# {f.surf}"); break;
                case "n": if ((long)v != f.n) Bad($"{w}: godot {v} c# {f.n}"); break;
                case "u0": Num(w, (double)v, f.u0); break;
                case "u1": Num(w, (double)v, f.u1); break;
                case "lip": Num(w, (double)v, f.lip); break;
                case "top": Num(w, (double)v, f.top); break;
                case "lip_deg": Num(w, (double)v, f.lip_deg); break;
                case "land0": Num(w, (double)v, f.land0); break;
                case "land1": Num(w, (double)v, f.land1); break;
                case "gap": Num(w, (double)v, f.gap); break;
                default: Bad($"{w}: key not ported"); break;
            }
        }

        static void Design(string id, Dictionary<string, object> dd, JumpDesignResult d)
        {
            if (d == null) { Bad($"feat {id}: no design in c#"); return; }
            foreach (var kv in dd)
            {
                string w = $"design {id}.{kv.Key}";
                switch (kv.Key)
                {
                    case "kind": if ((string)kv.Value != d.kind) Bad(w); break;
                    case "h": case "slope":
                        {
                            var a = (float[])kv.Value; var b = kv.Key == "h" ? d.h : d.slope;
                            if (a.Length != b.Length) { Bad($"{w}: length godot {a.Length} c# {b.Length}"); break; }
                            for (int i = 0; i < a.Length; i++) if (BitConverter.SingleToInt32Bits(a[i]) != BitConverter.SingleToInt32Bits(b[i])) { Bad($"{w}[{i}] godot {a[i]:R} c# {b[i]:R}"); break; }
                            break;
                        }
                    case "knots": Arrays(w, (List<object>)kv.Value, d.knots); break;
                    case "p": break;   // the parameters went in; the result is what counts
                    case "pred":
                        {
                            var l = (List<object>)kv.Value;
                            for (int i = 0; i < l.Count; i++)
                            {
                                var pd = (Dictionary<string, object>)l[i]; var pr = d.pred[i];
                                foreach (var pk in pd)
                                {
                                    string pw = $"{w}[{i}].{pk.Key}";
                                    switch (pk.Key)
                                    {
                                        case "spot": if ((string)pk.Value != pr.spot) Bad(pw); break;
                                        case "v": Num(pw, (double)pk.Value, pr.v); break;
                                        case "u": Num(pw, (double)pk.Value, pr.u); break;
                                        case "dist": Num(pw, (double)pk.Value, pr.dist); break;
                                        case "air": Num(pw, (double)pk.Value, pr.air); break;
                                        case "apex": Num(pw, (double)pk.Value, pr.apex); break;
                                        case "efh": Num(pw, (double)pk.Value, pr.efh); break;
                                        case "v_land": Num(pw, (double)pk.Value, pr.v_land); break;
                                        default: Bad(pw + " not ported"); break;
                                    }
                                }
                            }
                            break;
                        }
                    default:
                        {
                            var fi = typeof(JumpDesignResult).GetField(kv.Key);
                            if (fi == null) { Bad(w + " not ported"); break; }
                            Num(w, (double)kv.Value, (double)fi.GetValue(d));
                            break;
                        }
                }
            }
        }

        public static int Run(string refDir)
        {
            string path = Path.Combine(refDir, "playground", "playground.txt.gz");
            if (!File.Exists(path)) { Console.WriteLine("FAIL playground: no reference " + path); return 1; }
            string text;
            using (var fs = File.OpenRead(path))
            using (var gz = new GZipStream(fs, CompressionMode.Decompress))
            using (var rd = new StreamReader(gz, Encoding.UTF8)) text = rd.ReadToEnd();
            var c = new PlaygroundCourse();
            int nl = 0, nf = 0, nb = 0, nr = 0, ns = 0, nsp = 0;
            double hmax = 0; int sbad = 0;
            foreach (var line in text.Split('\n'))
            {
                if (line.Length == 0) continue;
                var p = line.Split('\t');
                switch (p[0])
                {
                    case "BOUNDS":
                        if (Rect(p[1]) != Rect(c.bounds)) Bad($"bounds godot {Rect(p[1])} c# {Rect(c.bounds)}");
                        break;
                    case "LANE":
                        {
                            var l = c.lane_by_id(p[1]);
                            if (l == null) { Bad("lane missing " + p[1]); break; }
                            nl++;
                            if (l.title != p[2]) Bad($"lane {l.id} title");
                            Num($"lane {l.id} z", Hx(p[3]), l.z); Num($"lane {l.id} hw", Hx(p[4]), l.hw); Num($"lane {l.id} band", Hx(p[5]), l.band);
                            if (Rect(p[6]) != Rect(l.rect)) Bad($"lane {l.id} rect godot {Rect(p[6])} c# {Rect(l.rect)}");
                            var hb = Bytes(p[7]);
                            if (hb.Length / 4 != l.h.Count) Bad($"lane {l.id} h count godot {hb.Length / 4} c# {l.h.Count}");
                            else
                                for (int i = 0; i < l.h.Count; i++)
                                    if (BitConverter.ToInt32(hb, i * 4) != BitConverter.SingleToInt32Bits(l.h[i])) { Bad($"lane {l.id} h[{i}] godot {BitConverter.ToSingle(hb, i * 4):R} c# {l.h[i]:R}"); break; }
                            var mb = Bytes(p[8]);
                            if (mb.Length != l.m.Count) Bad($"lane {l.id} m count");
                            else for (int i = 0; i < mb.Length; i++) if (mb[i] != l.m[i]) { Bad($"lane {l.id} m[{i}]"); break; }
                            Arrays($"lane {l.id} camber", (List<object>)ParseVal(p[9]), l.camber);
                            Arrays($"lane {l.id} skews", (List<object>)ParseVal(p[10]), l.skews);
                            Arrays($"lane {l.id} surfs", (List<object>)ParseVal(p[11]), l.surfs);
                            Arrays($"lane {l.id} cones", (List<object>)ParseVal(p[12]), l.cones);
                            break;
                        }
                    case "FEAT":
                        {
                            if (nf >= c.feats.Count) { Bad("more features in godot"); break; }
                            var f = c.feats[nf++];
                            for (int k = 1; k < p.Length; k++)
                            {
                                int e = p[k].IndexOf('=');
                                string key = p[k].Substring(0, e), v = p[k].Substring(e + 1);
                                if (key == "design") { int i = 0; Design(f.id, (Dictionary<string, object>)Val(v, ref i), f.design); }
                                else FeatField(f, key, ParseVal(v));
                            }
                            break;
                        }
                    case "SPAWN":
                        {
                            nsp++;
                            var f = c.feature_by_id(p[1]);
                            if (f == null) { Bad("spawn: no feature " + p[1]); break; }
                            var a = p[2].Split(','); var b = p[3].Split(',');
                            V3 sp = c.spawn_for(f);
                            V3 fp = f.bowl == null ? c.feat_point(f, f.u0 + 1.0) : V3.ZERO;
                            Num($"spawn {f.id}.x", Hx(a[0]), sp.x); Num($"spawn {f.id}.y", Hx(a[1]), sp.y); Num($"spawn {f.id}.z", Hx(a[2]), sp.z);
                            Num($"feat_point {f.id}.x", Hx(b[0]), fp.x); Num($"feat_point {f.id}.y", Hx(b[1]), fp.y); Num($"feat_point {f.id}.z", Hx(b[2]), fp.z);
                            break;
                        }
                    case "BOWL":
                        {
                            var bw = c.bowls[nb++];
                            if (bw.id != p[1] || bw.title != p[2]) Bad($"bowl {bw.id} id / title");
                            var cc = p[3].Split(',');
                            Num($"bowl {bw.id} c.x", Hx(cc[0]), bw.c.x); Num($"bowl {bw.id} c.y", Hx(cc[1]), bw.c.y);
                            Num($"bowl {bw.id} R", Hx(p[4]), bw.R); Num($"bowl {bw.id} W", Hx(p[5]), bw.W); Num($"bowl {bw.id} tn", Hx(p[6]), bw.tn);
                            Num($"bowl {bw.id} deg", Hx(p[7]), bw.deg); Num($"bowl {bw.id} open_dir", Hx(p[8]), bw.open_dir);
                            if (Rect(p[9]) != Rect(bw.rect)) Bad($"bowl {bw.id} rect");
                            break;
                        }
                    case "ROCK":
                        {
                            var d = (Dictionary<string, object>)ParseVal(p[1]);
                            var r = c.rocks[nr++];
                            string w = $"rock {nr - 1}";
                            Num(w + ".x", (double)d["x"], r.x); Num(w + ".z", (double)d["z"], r.z); Num(w + ".r", (double)d["r"], r.r);
                            Num(w + ".top", (double)d["top"], r.top); Num(w + ".base", (double)d["base"], r.@base); Num(w + ".sink", (double)d["sink"], r.sink);
                            Num(w + ".sx", (double)d["sx"], r.sx); Num(w + ".sy", (double)d["sy"], r.sy); Num(w + ".sc", (double)d["sc"], r.sc);
                            Num(w + ".yaw", (double)d["yaw"], r.yaw);
                            break;
                        }
                    case "S":
                        {
                            ns++;
                            double x = Hx(p[1]), z = Hx(p[2]), hg = Hx(p[3]);
                            double h = c.height_rocks(x, z);
                            double dh = Math.Abs(h - hg);
                            if (dh > hmax) hmax = dh;
                            bool ok = dh <= 1e-6;
                            ok &= (int)c.jump_mask(x, z) == int.Parse(p[4]);
                            ok &= (c.is_dirt(x, z) ? 1 : 0) == int.Parse(p[5]);
                            ok &= c.surface_at(x, z) == int.Parse(p[6]);
                            var f = c.feature_at(x, z);
                            ok &= (f == null ? "-" : f.id) == p[7];
                            if (!ok)
                            {
                                sbad++;
                                Bad($"sample ({x:R}, {z:R}): godot h {hg:R} jm {p[4]} dirt {p[5]} surf {p[6]} feat {p[7]} | c# h {h:R} jm {c.jump_mask(x, z)} dirt {c.is_dirt(x, z)} surf {c.surface_at(x, z)} feat {(f == null ? "-" : f.id)}");
                            }
                            break;
                        }
                }
            }
            if (nf != c.feats.Count) Bad($"features: godot {nf} c# {c.feats.Count}");
            if (nr != c.rocks.Count) Bad($"rocks: godot {nr} c# {c.rocks.Count}");
            if (nl != c.lanes.Count) Bad($"lanes: godot {nl} c# {c.lanes.Count}");
            foreach (var m in _msgs) Console.WriteLine("  " + m);
            Console.WriteLine($"{(_bad == 0 ? "PASS" : "FAIL")} playground lanes={nl} feats={nf} bowls={nb} rocks={nr} spawns={nsp} samples={ns} " +
                $"bad_samples={sbad} max_h_diff={hmax:E2} m, mismatches={_bad}");
            int fails = _bad == 0 ? 0 : 1;
            fails += Placed(c);
            return fails;
        }

        /// placed copies of lane features: same shape on their own axis (yaw 0 and PI / 2), rocks included
        static int Placed(PlaygroundCourse lanes)
        {
            int bad = 0; double worst = 0; int n = 0;
            var msgs = new List<string>();
            void Cmp(string kind, double[] args, string lane_feat, double yaw)
            {
                var lf = lanes.feature_by_id(lane_feat);
                var l = lanes.lane_by_id(lf.lane);
                var c = new PlaygroundCourse(false);
                var pf = c.add_placed(PlacedFeature.make(kind, args, 100.0, 300.0, yaw, l.hw, ""));
                var f = pf.feat;
                double du = f.u0 - lf.u0;   // placed u = lane u + du (du = -lf.u0)
                if (Math.Abs((f.u1 - f.u0) - (lf.u1 - lf.u0)) > 1e-9 || Math.Abs((f.lip - f.u0) - (lf.lip - lf.u0)) > 1e-9 && lf.lip >= 0)
                { bad++; msgs.Add($"{kind} yaw {yaw:0.00}: feature span differs"); }
                if (c.feature_at(pf.world(f.u0 + 1.0, 0).x, pf.world(f.u0 + 1.0, 0).y) != f) { bad++; msgs.Add($"{kind}: feature_at doesn't find it"); }
                foreach (double v in new[] { 0.0, 1.0, -2.5, 3.5, -4.2 })
                    for (double t = -2.0; t <= lf.u1 - lf.u0 + 4.0; t += 0.05)
                    {
                        double lu = lf.u0 + t;
                        double want = lanes.height_rocks(PlaygroundCourse.X0 + lu, l.z + v);
                        if (lu < 0.0) continue;
                        pf.world_xz(f.u0 + t, v, out double wx, out double wz);
                        double got = c.height_rocks(wx, wz);
                        double d = Math.Abs(want - got);
                        n++;
                        if (d > worst) worst = d;
                        if (d > 1e-6 && msgs.Count < 10) { bad++; msgs.Add($"{kind} yaw {yaw:0.00} t {t:0.00} v {v}: lane {want:R} placed {got:R}"); }
                        // (the mask is per 5 cm sample: compare mid-sample, a sample's edge falls either side by rounding)
                        pf.world_xz(f.u0 + t + 0.025, v, out double jx, out double jz);
                        double jw = lanes.jump_mask(PlaygroundCourse.X0 + lu + 0.025, l.z + v), jg = c.jump_mask(jx, jz);
                        if (jw != jg && msgs.Count < 10) { bad++; msgs.Add($"{kind} yaw {yaw:0.00} t {t:0.00} v {v}: jump lane {jw} placed {jg}"); }
                    }
            }
            foreach (double yaw in new[] { 0.0, Math.PI / 2.0, 2.3 })
            {
                Cmp("table", new[] { 1.5, 32, 4, 30 }, "table_1.5", yaw);
                Cmp("gap", new[] { 1.6, 35, 7, 1.7, 35 }, "gap_7", yaw);
                Cmp("camber", new[] { 20.0, 24 }, "camber_20", yaw);
                Cmp("hip", new[] { 1.5, 32, 4, 30, 35 }, "hip_35", yaw);
                Cmp("rock_row", new[] { 0.3, 0.7, 4, 4.0 }, "rock_10", yaw);
                Cmp("chatter", new[] { 0.3, 40.0, 23 }, "rough_0.3", yaw);
                Cmp("pothole", new[] { 0.3, 1.5 }, "hole_0.3", yaw);
            }
            // a placed bowl = the lanes' bowl
            var cb = new PlaygroundCourse(false);
            var bl = lanes.bowls[1];
            var pb = cb.add_placed(PlacedFeature.make("bowl", new[] { bl.R, bl.W, bl.deg }, bl.c.x, bl.c.y, 0.0, 3.0, ""));
            for (double x = bl.rect.x; x < bl.rect.end_x; x += 0.5)
                for (double z = bl.rect.z; z < bl.rect.end_z; z += 0.5)
                {
                    double d = Math.Abs(bl.at(x, z) - cb.height(x, z)); n++;
                    if (d > worst) worst = d;
                    if (d > 1e-6 && msgs.Count < 10) { bad++; msgs.Add($"bowl ({x}, {z}) {bl.at(x, z)} vs {cb.height(x, z)}"); }
                }
            foreach (var m in msgs) Console.WriteLine("  " + m);
            Console.WriteLine($"{(bad == 0 ? "PASS" : "FAIL")} playground_placed samples={n} max_diff={worst:E2} m, mismatches={bad}");
            return bad == 0 ? 0 : 1;
        }
    }
}
