using System;
using System.Collections.Generic;
using System.IO;
using Runout.World;

namespace Runout.Sim.Tests
{
    /// The world port (Assets/Runout/World, engine-free) vs Godot (godot/tools/world_dump.gd -> SimTests/world_ref):
    /// step 1 = Godot's setup tables loaded into the C# TerrainField, every sample point must match exactly.
    static class WorldCheck
    {
        public static int Run(string simTestsDir)
        {
            string dir = Path.Combine(simTestsDir, "world_ref");
            if (!Directory.Exists(dir)) { Console.WriteLine("SKIP world_check (no world_ref: run godot/tools/world_dump.gd)"); return 0; }
            int fail = 0;
            if (Environment.GetEnvironmentVariable("GEN_COLORS") == "1") GenColors(Path.Combine(dir, "setup_4242.rwd"), Path.Combine(simTestsDir, "..", "Assets", "Runout", "World", "Setup", "WorldColors.g.cs"));
            foreach (var setup in Directory.GetFiles(dir, "setup_*.rwd"))
            {
                string seed = Path.GetFileNameWithoutExtension(setup).Substring(6);
                var t0 = DateTime.Now;
                var tree = (Dictionary<object, object>)Rwd.Load(setup);
                var gd = (RwdObject)tree["field"];
                var tables = GodotTables.FromGodot(gd, (Dictionary<object, object>)tree["land"]);
                var f = new TerrainField();
                f.setup_from(tables);
                var smp = (Dictionary<object, object>)Rwd.Load(Path.Combine(dir, "samples_" + seed + ".rwd"));
                fail += CompareSamples("world_query seed " + seed, f, smp, (DateTime.Now - t0).TotalMilliseconds);
                fail += SpineCheck(seed, f, tables, gd);
                fail += CourseCheck(seed, f, tables, gd);
                fail += BuildCheck(seed, tables, smp, simTestsDir);
                // tile fill cost (WorldStreamer: 257 x 257 heights over 128 m round the trail start)
                var sp = WorldGround.TrailStart(tables);
                var sw = System.Diagnostics.Stopwatch.StartNew();
                double acc = 0;
                for (int j = 0; j < 257; j++) for (int i = 0; i < 257; i++) acc += f.height(sp.x - 64 + i * 0.5, sp.z - 64 + j * 0.5);
                Console.WriteLine($"  tile fill seed {seed}: {sw.Elapsed.TotalMilliseconds:0} ms for 257x257 ({sw.Elapsed.TotalMilliseconds * 1000 / 66049:0.0} us/height){(double.IsNaN(acc) ? " NaN!" : "")}");
            }
            return fail;
        }

        /// the C# RouteSpine (setup port) vs Godot's: every point and the query grid
        static int SpineCheck(string seed, TerrainField f, FieldTables t, RwdObject gd)
        {
            var g = (RwdObject)gd["spine"];
            var sw = System.Diagnostics.Stopwatch.StartNew();
            var sp = RouteSpine.make(f, t.seed_value, 4000.0 + 4000.0);
            double ms = sw.Elapsed.TotalMilliseconds;
            var gx = Rwd.F64(g["X"]); var gz = Rwd.F64(g["Z"]); var gs = Rwd.F64(g["S"]);
            int bad = 0, first = -1;
            int n = Math.Min(gx.Length, sp.X.Count);
            for (int i = 0; i < n; i++)
                if (!gx[i].Equals(sp.X[i]) || !gz[i].Equals(sp.Z[i]) || !gs[i].Equals(sp.S[i])) { bad++; if (first < 0) first = i; }
            if (gx.Length != sp.X.Count) bad++;
            var gst = Rwd.I32(g["cell_start"]); var git = Rwd.I32(g["cell_items"]);
            bool grid = gst.Length == sp.cell_start.Length && git.Length == sp.cell_items.Length && Rwd.L(g["gx0"]) == sp.gx0 && Rwd.L(g["gnz"]) == sp.gnz;
            for (int i = 0; grid && i < gst.Length; i++) grid = gst[i] == sp.cell_start[i];
            for (int i = 0; grid && i < git.Length; i++) grid = git[i] == sp.cell_items[i];
            string where = first >= 0 ? $", first at point {first} (C# {sp.X[first]:0.###},{sp.Z[first]:0.###} vs {gx[first]:0.###},{gz[first]:0.###})" : "";
            Console.WriteLine($"{(bad == 0 && grid ? "PASS" : "FAIL")} world_spine seed {seed}: {sp.X.Count} points (Godot {gx.Length}), {bad} differ, grid {(grid ? "same" : "DIFFERS")}{where}; {ms:0} ms");
            return bad == 0 && grid ? 0 : 1;
        }

        /// the C# TrailCourse (setup port) vs Godot's: every layout and derived array
        static int CourseCheck(string seed, TerrainField f, FieldTables t, RwdObject gd)
        {
            var g = (RwdObject)gd["course"];
            // the field as Godot has it while the course is laid out: everything up to the spine, no course / route yet
            var pre = new FieldTables
            {
                seed_value = t.seed_value, sz = t.sz, NT = t.NT, rp_a = t.rp_a, rp_sg = t.rp_sg, pitches = t.pitches, pitch_share = t.pitch_share,
                grade_k = t.grade_k, biome_dry = t.biome_dry, biome_rug = t.biome_rug, col = t.col, red_bands = t.red_bands, grey_bands = t.grey_bands,
                land = t.land, sX = t.sX, sZ = t.sZ, sS = t.sS, s_gx0 = t.s_gx0, s_gz0 = t.s_gz0, s_gnx = t.s_gnx, s_gnz = t.s_gnz,
                s_start = t.s_start, s_items = t.s_items,
                cX = new double[0], cZ = new double[0], cKD = new int[0], cTX = new double[0], cTZ = new double[0], cKAP = new double[0],
                cW = new double[0], cBT = new double[0], cE = new double[0], cRD = new double[0], cRK = new double[0], cLN = new double[0],
                cRO = new double[0], cROS = new double[0], cDL = new double[0], c_drops = new double[0], c_seg = new double[0], c_far = new double[0],
                c_run_start = new int[0], c_runs = new int[0], alt_pts = new double[0], alt_lines = new double[0],
            };
            var pf = new TerrainField();
            pf.setup_from(pre);
            if (Environment.GetEnvironmentVariable("COURSE_TRACE") == seed) Console.Write(TrailCourse.TraceStart(pf, t.seed_value, TerrainField.HILL_LEN, TerrainField.MTN_W - 40, 4000.0));
            var sw = System.Diagnostics.Stopwatch.StartNew();
            long sv = t.seed_value;
            var c = TrailCourse.make(new WorldRng(sv * 31337 + 5), pf, TerrainField.HILL_LEN, TerrainField.MTN_W - 40, 4000.0, sv * 6151 + 3);
            double ms = sw.Elapsed.TotalMilliseconds;
            var bad = new System.Collections.Generic.List<string>();
            void Arr(string k, System.Collections.Generic.IList<double> mine)
            {
                var want = Rwd.F64(g[k]);
                int m = Math.Min(want.Length, mine.Count);
                for (int i = 0; i < m; i++)
                    if (!want[i].Equals(mine[i])) { bad.Add($"{k}[{i}] {mine[i]:R} vs {want[i]:R} (len {mine.Count} vs {want.Length})"); return; }
                if (want.Length != mine.Count) bad.Add($"{k} len {mine.Count} vs {want.Length}");
            }
            System.Collections.Generic.IList<double> F(float[] a) { var o = new double[a.Length]; for (int i = 0; i < a.Length; i++) o[i] = a[i]; return o; }
            System.Collections.Generic.IList<double> I(System.Collections.Generic.IList<int> a) { var o = new double[a.Count]; for (int i = 0; i < a.Count; i++) o[i] = a[i]; return o; }
            Arr("X", c.X); Arr("Z", c.Z);
            Arr("KD", I(c.KD));
            if (bad.Count == 0)
            {
                Arr("TX", F(c.TX)); Arr("TZ", F(c.TZ)); Arr("KAP", F(c.KAP)); Arr("W", F(c.W)); Arr("E", F(c.E)); Arr("BT", F(c.BT));
                Arr("RD", F(c.RD)); Arr("RK", F(c.RK)); Arr("LN", F(c.LN)); Arr("RO", F(c.RO)); Arr("ROS", F(c.ROS)); Arr("VA", F(c.VA)); Arr("DL", F(c.DL));
                Arr("cell_start", I(c.cell_start)); Arr("cell_items", I(c.cell_items)); Arr("flow_starts", I(c.flow_starts));
                if (Rwd.D(g["length"]) != c.length) bad.Add("length");
                var gdrops = (System.Collections.Generic.List<object>)g["drops"];
                if (gdrops.Count != c.drops.Count) bad.Add($"drops {c.drops.Count} vs {gdrops.Count}");
            }
            string why = bad.Count > 0 ? " first: " + bad[0] : "";
            Console.WriteLine($"{(bad.Count == 0 ? "PASS" : "FAIL")} world_course seed {seed}: {c.n} points (Godot {Rwd.F64(g["X"]).Length}), {bad.Count} arrays differ{why}; {ms:0} ms");
            return bad.Count == 0 ? 0 : 1;
        }

        /// writes World/Setup/WorldColors.g.cs: Godot's colour table (TerrainField.COL, red / grey bands) as exact float bits
        static void GenColors(string rwd, string outPath)
        {
            var g = (RwdObject)((Dictionary<object, object>)Rwd.Load(rwd))["field"];
            var sb = new System.Text.StringBuilder();
            sb.AppendLine("// generated by unity/SimTests (GEN_COLORS=1) from Godot's TerrainField.COL (godot/tools/world_dump.gd): the linear colours");
            sb.AppendLine("// exactly as Godot's float32 srgb_to_linear makes them. Don't edit; regenerate.");
            sb.AppendLine("using System.Collections.Generic;");
            sb.AppendLine("namespace Runout.World");
            sb.AppendLine("{");
            sb.AppendLine("    public static class WorldColors");
            sb.AppendLine("    {");
            sb.AppendLine("        static TfColor C(int r, int g, int b, int a) => new TfColor(System.BitConverter.Int32BitsToSingle(r), System.BitConverter.Int32BitsToSingle(g), System.BitConverter.Int32BitsToSingle(b), System.BitConverter.Int32BitsToSingle(a));");
            string Cc(TfColor c) => $"C({BitConverter.SingleToInt32Bits(c.R)}, {BitConverter.SingleToInt32Bits(c.G)}, {BitConverter.SingleToInt32Bits(c.B)}, {BitConverter.SingleToInt32Bits(c.A)})";
            sb.AppendLine("        public static Dictionary<string, TfColor> COL() => new Dictionary<string, TfColor>");
            sb.AppendLine("        {");
            foreach (var kv in (Dictionary<object, object>)g["col"]) sb.AppendLine($"            [\"{kv.Key}\"] = {Cc((TfColor)kv.Value)},");
            sb.AppendLine("        };");
            sb.Append("        public static TfColor[] RED_BANDS() => new[] { ");
            foreach (var c in (TfColor[])g["red_bands"]) sb.Append(Cc(c) + ", ");
            sb.AppendLine("};");
            sb.Append("        public static TfColor[] GREY_BANDS() => new[] { ");
            foreach (var c in (TfColor[])g["grey_bands"]) sb.Append(Cc(c) + ", ");
            sb.AppendLine("};");
            sb.AppendLine("    }");
            sb.AppendLine("}");
            File.WriteAllText(outPath, sb.ToString().Replace("\r\n", "\n"));
            Console.WriteLine("GEN_COLORS wrote " + Path.GetFullPath(outPath));
        }

        /// the whole world built in C# from the seed (WorldSetup) vs Godot's tables, then the query samples on it
        static int BuildCheck(string seed, FieldTables g, Dictionary<object, object> smp, string simTestsDir)
        {
            string landPath = Path.Combine(simTestsDir, "..", "..", "godot", "data", "land_params.json");
            var knobs = LandParams.FromJson(File.Exists(landPath) ? File.ReadAllText(landPath) : "");
            var style = new Dictionary<string, double> { ["jumps"] = 1.0, ["bends"] = 1.0, ["rolling"] = 1.0, ["grade"] = 1.0, ["biome"] = 0.0 };
            var w = WorldSetup.Build(g.seed_value, style, knobs);
            var t = w.tables;
            var bad = new List<string>();
            void A(string k, double[] mine, double[] want)
            {
                int m = Math.Min(mine.Length, want.Length);
                for (int i = 0; i < m; i++) if (!mine[i].Equals(want[i])) { bad.Add($"{k}[{i}] {mine[i]:R} vs {want[i]:R}"); return; }
                if (mine.Length != want.Length) bad.Add($"{k} len {mine.Length} vs {want.Length}");
            }
            double[] I(int[] a) { var o = new double[a.Length]; for (int i = 0; i < a.Length; i++) o[i] = a[i]; return o; }
            void V(string k, double a, double b) { if (!a.Equals(b)) bad.Add($"{k} {a:R} vs {b:R}"); }
            V("sz", t.sz, g.sz); V("rp_a", t.rp_a, g.rp_a); V("rp_sg", t.rp_sg, g.rp_sg); V("pitch_share", t.pitch_share, g.pitch_share);
            A("NT", t.NT, g.NT); A("pitches", t.pitches, g.pitches);
            foreach (var kv in g.land) if (!t.land.TryGetValue(kv.Key, out var lv) || !lv.Equals(kv.Value)) bad.Add($"land {kv.Key} {lv:R} vs {kv.Value:R}");
            foreach (var kv in g.col) if (!t.col[kv.Key].Equals(kv.Value)) bad.Add("col " + kv.Key);
            A("sX", t.sX, g.sX); A("cX", t.cX, g.cX); A("cE", t.cE, g.cE); A("cDL", t.cDL, g.cDL); A("c_drops", t.c_drops, g.c_drops);
            A("c_seg", t.c_seg, g.c_seg); A("c_run_start", I(t.c_run_start), I(g.c_run_start)); A("c_runs", I(t.c_runs), I(g.c_runs));
            A("c_far", t.c_far, g.c_far); V("c_far_x0", t.c_far_x0, g.c_far_x0); V("c_far_nx", t.c_far_nx, g.c_far_nx);
            if (t.route_feats.Count != g.route_feats.Count) bad.Add($"route_feats {t.route_feats.Count} vs {g.route_feats.Count}");
            for (int i = 0; i < Math.Min(t.route_feats.Count, g.route_feats.Count); i++)
            {
                var a = t.route_feats[i]; var b = g.route_feats[i];
                if (a.type != b.type || !a.x.Equals(b.x) || !a.z.Equals(b.z) || !a.s.Equals(b.s) || !a.b0.Equals(b.b0) || !a.b1.Equals(b.b1) || a.size != b.size)
                { bad.Add($"route_feat {i}: {a.type}@{a.s:R} size {a.size} vs {b.type}@{b.s:R} size {b.size}"); break; }
            }
            A("alt_pts", t.alt_pts, g.alt_pts); A("alt_lines", t.alt_lines, g.alt_lines);
            Console.WriteLine($"{(bad.Count == 0 ? "PASS" : "FAIL")} world_build seed {seed}: built in {w.ms:0} ms, {t.route_feats.Count} route features, {t.alt_lines.Length / 7} B-lines, {bad.Count} differ{(bad.Count > 0 ? ", first: " + bad[0] : "")}");
            int fail = bad.Count == 0 ? 0 : 1;
            fail += CompareSamples("world_query (C#-built) seed " + seed, w.field, smp, w.ms);
            return fail;
        }

        static int CompareSamples(string name, TerrainField f, Dictionary<object, object> s, double setupMs)
        {
            var xs = (double[])s["x"]; var zs = (double[])s["z"];
            string[] keys = { "ground", "landform", "trail", "berm", "line", "pathN", "jump_mask", "route_dist", "wild", "hill", "mtn", "deck",
                "b_dry", "b_rug", "b_cold", "b_wet", "b_forest", "b_sav", "b_ash" };
            var bad = new Dictionary<string, int>(); var worst = new Dictionary<string, double>();
            var names = (string[])s["biome_name"]; var rgb = (double[])s["color_rgb"];
            int n = xs.Length, cmp = 0;
            var t0 = DateTime.Now;
            for (int i = 0; i < n; i++)
            {
                double x = xs[i], z = zs[i];
                var got = new Dictionary<string, double>
                {
                    ["ground"] = f.ground(x, z), ["landform"] = f.landform(x, z), ["trail"] = f.trail(x, z), ["berm"] = f.berm(x, z),
                    ["line"] = f.line(x, z), ["pathN"] = f.pathN(x, z), ["jump_mask"] = f.jump_mask(x, z),
                    ["route_dist"] = f.route_dist(x, z), ["wild"] = f.wild(x, z), ["hill"] = f.hill(x, z), ["mtn"] = f.mtn(x, z),
                    ["deck"] = f.deck(x, z),
                };
                f.biome(x, z);
                got["b_dry"] = f.b_dry; got["b_rug"] = f.b_rug; got["b_cold"] = f.b_cold; got["b_wet"] = f.b_wet;
                got["b_forest"] = f.b_forest; got["b_sav"] = f.b_sav; got["b_ash"] = f.b_ash;
                foreach (var k in keys)
                {
                    double want = ((double[])s[k])[i], have = got[k];
                    cmp++;
                    bool same = want.Equals(have);   // bit-equal, NaN == NaN
                    if (!same)
                    {
                        bad[k] = bad.GetValueOrDefault(k) + 1;
                        worst[k] = Math.Max(worst.GetValueOrDefault(k), Math.Abs(want - have));
                    }
                }
                cmp++;
                if (f.biome_name(x, z) != names[i]) bad["biome_name"] = bad.GetValueOrDefault("biome_name") + 1;
                var c = f.color(x, z, f.ground(x, z), 0.95);
                double[] cc = { c.R, c.G, c.B };
                for (int ch = 0; ch < 3; ch++)
                {
                    cmp++;
                    if (!cc[ch].Equals(rgb[i * 3 + ch])) { bad["color"] = bad.GetValueOrDefault("color") + 1; worst["color"] = Math.Max(worst.GetValueOrDefault("color"), Math.Abs(cc[ch] - rgb[i * 3 + ch])); }
                }
            }
            double us = (DateTime.Now - t0).TotalMilliseconds * 1000.0 / n;
            int total = 0; foreach (var v in bad.Values) total += v;
            var detail = new System.Text.StringBuilder();
            foreach (var kv in bad) detail.Append($" {kv.Key}={kv.Value}(max {worst.GetValueOrDefault(kv.Key):g3})");
            Console.WriteLine($"{(total == 0 ? "PASS" : "FAIL")} {name}: {n} points, {cmp} values, {total} mismatches{detail}; setup {setupMs:0} ms, {us:0.0} us/point, ties {f.libm_ties}");
            return total == 0 ? 0 : 1;
        }
    }
}
