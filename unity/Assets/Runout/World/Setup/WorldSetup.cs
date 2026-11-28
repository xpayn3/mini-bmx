using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.World
{
    /// Builds a whole world from a seed (port of terrain_field.gd setup(): noise lattice, the start mountain's pitches,
    /// the route spine, the trail course, the course's query tables, the route features and B-lines), engine-free.
    /// Same seed + style + land knobs = the same world as Godot, bit for bit (unity/SimTests WorldCheck).
    public static class WorldSetup
    {
        public const double COURSE_LEN = 4000.0;
        public const double SPINE_AHEAD = 4000.0;

        /// RouteStyle.BIOMES: (name, dry, rugged)
        public static readonly (string name, double dry, double rug)[] BIOMES =
        {
            ("ANY", 0.0, 0.0), ("GREEN HILLS", -2.0, -2.0), ("ROCKY MOUNTAINS", -2.0, 2.0), ("DUNE SEA", 2.0, -2.0), ("RED CANYONS", 2.0, 2.0),
        };

        static readonly int[] PERM =
        {
            151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
            247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168,
            68, 175, 74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40,
            244, 102, 143, 54, 65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130, 116, 188, 159, 86, 164, 100,
            109, 198, 173, 186, 3, 64, 52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227, 47, 16, 58, 17,
            182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98,
            108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145,
            235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
            222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
        };

        public sealed class World
        {
            public FieldTables tables;
            public TerrainField field;
            public RouteSpine spine;
            public TrailCourse course;
            public double ms;   // how long Build took
        }

        /// the whole world: seed, RouteStyle values (jumps / twist / rolling / grade / biome; missing = 1, biome 0) and the
        /// land knobs (LandParams values; null = defaults)
        public static World Build(long seed, Dictionary<string, double> style = null, Dictionary<string, double> landKnobs = null)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            style ??= new Dictionary<string, double>();
            var land = LandParams.Apply(landKnobs ?? LandParams.Defaults());
            double S(string k, double d) => style.TryGetValue(k, out var v) ? v : d;
            var t = new FieldTables { seed_value = seed, land = land };
            t.grade_k = clampf(S("grade", 1.0), 0.5, 1.7);
            var pick = BIOMES[clampi(roundi(S("biome", 0.0)), 0, BIOMES.Length - 1)];
            t.biome_dry = pick.dry; t.biome_rug = pick.rug;
            t.col = WorldColors.COL();
            t.red_bands = WorldColors.RED_BANDS();
            t.grey_bands = WorldColors.GREY_BANDS();
            t.sz = (seed % 1000) * 0.7311 + 0.37;
            t.NT = BuildNoise(t.sz);
            // the mountain's pitches (steep technical stretches down the start peak)
            var r = new WorldRng(seed * 7919 + 13);
            t.rp_a = r.next() * 6.28;
            r.next();
            t.rp_sg = r.next() < 0.5 ? 1.0 : -1.0;
            var pitches = new List<double>();
            t.pitch_share = 0.0;
            double hillLen = land["HILL_LEN"], pitchK = land["PITCH_K"];
            long pitchN = (long)land["PITCH_N"];
            double x = 170 + r.next() * 80;
            long k = 0;
            while (k < pitchN && x < hillLen - 140)
            {
                double len = 34 + r.next() * 24;
                double sh = (0.06 + r.next() * 0.03) * pitchK;
                pitches.Add(x); pitches.Add(len); pitches.Add(sh);
                t.pitch_share += sh;
                x += len + 190 + r.next() * 170;
                k += 1;
            }
            t.pitches = pitches.ToArray();
            EmptyCourse(t);
            t.sX = t.sZ = t.sS = new double[0];
            t.s_start = new int[1]; t.s_items = new int[0];

            var f = new TerrainField { style = style };
            f.setup_from(t);
            // the route spine (the walker reads the bare land: no spine needed yet)
            var spine = RouteSpine.make(f, seed, COURSE_LEN + SPINE_AHEAD, S("twist", 1.0));
            BindSpine(t, spine);
            f.setup_from(t);
            // the trail
            var course = TrailCourse.make(new WorldRng(seed * 31337 + 5), f, hillLen, TerrainField.MTN_W - 40, COURSE_LEN, seed * 6151 + 3);
            BindCourse(t, course);
            f.setup_from(t);
            // route features + B-lines (read the field with the course bound, no features yet)
            BuildRoute(f, t, course, seed, style);
            f.setup_from(t);
            return new World { tables = t, field = f, spine = spine, course = course, ms = sw.Elapsed.TotalMilliseconds };
        }

        // ---------------- noise lattice (three.js ImprovedNoise at z = sz) ----------------
        static (int x, int y, int z) Grad(int h)
        {
            h &= 15;
            int u = h < 8 ? 0 : 1;
            int v = h < 4 ? 1 : ((h == 12 || h == 14) ? 0 : 2);
            int su = (h & 1) != 0 ? -1 : 1, sv = (h & 2) != 0 ? -1 : 1;
            var c = new int[3];
            c[u] += su;
            c[v] += sv;
            return (c[0], c[1], c[2]);
        }

        static double[] BuildNoise(double sz)
        {
            var p = new int[512];
            for (int i = 0; i < 256; i++) { p[i] = PERM[i]; p[256 + i] = PERM[i]; }
            double fz = Math.Floor(sz);
            int Zi = (int)fz & 255;
            double zf = sz - fz;
            double w = zf * zf * zf * (zf * (zf * 6 - 15) + 10);
            var NT = new double[65536 * 3];
            for (int X = 0; X < 256; X++)
                for (int Y = 0; Y < 256; Y++)
                {
                    int AA = p[p[X] + Y] + Zi;
                    var g0 = Grad(p[AA]);
                    var g1 = Grad(p[AA + 1]);
                    int o = ((X << 8) | Y) * 3;
                    NT[o] = g0.x + w * (g1.x - g0.x);
                    NT[o + 1] = g0.y + w * (g1.y - g0.y);
                    NT[o + 2] = g0.z * zf + w * (g1.z * (zf - 1.0) - g0.z * zf);
                }
            return NT;
        }

        // ---------------- binding (terrain_field.gd _bind_spine / _bind_course / _build_far) ----------------
        static void EmptyCourse(FieldTables t)
        {
            t.cX = t.cZ = t.cTX = t.cTZ = t.cKAP = t.cW = t.cBT = t.cE = t.cRD = t.cRK = t.cLN = t.cRO = t.cROS = t.cDL = new double[0];
            t.cKD = new int[0];
            t.c_drops = t.c_seg = t.c_far = new double[0];
            t.c_run_start = new int[0]; t.c_runs = new int[0];
            t.c_gx0 = t.c_gz0 = t.c_gnx = t.c_gnz = 0;
            t.c_far_x0 = t.c_far_z0 = t.c_far_nx = t.c_far_nz = 0;
            t.alt_pts = new double[0]; t.alt_lines = new double[0];
            t.alt_feats = new List<long[]>();
            t.route_feats = new List<FeatDesc>();
        }

        static void BindSpine(FieldTables t, RouteSpine sp)
        {
            t.sX = sp.X.ToArray(); t.sZ = sp.Z.ToArray(); t.sS = sp.S.ToArray();
            t.s_gx0 = sp.gx0; t.s_gz0 = sp.gz0; t.s_gnx = sp.gnx; t.s_gnz = sp.gnz;
            t.s_start = sp.cell_start; t.s_items = sp.cell_items;
        }

        static double[] D(float[] a) { var o = new double[a.Length]; for (int i = 0; i < a.Length; i++) o[i] = a[i]; return o; }

        public static void BindCourse(FieldTables t, TrailCourse c)
        {
            int n = (int)c.n;
            t.course = c;
            t.cX = c.X.ToArray(); t.cZ = c.Z.ToArray(); t.cKD = c.KD.ToArray();
            t.cTX = D(c.TX); t.cTZ = D(c.TZ); t.cKAP = D(c.KAP); t.cW = D(c.W); t.cBT = D(c.BT); t.cE = D(c.E);
            t.cRD = D(c.RD); t.cRK = D(c.RK); t.cLN = D(c.LN); t.cRO = D(c.RO); t.cROS = D(c.ROS);
            t.cDL = c.DL.Length == n ? D(c.DL) : new double[n];
            var drops = new List<double>();
            foreach (var dr in c.drops)
            {
                int a0 = dr[0], a1 = (int)mini(dr[1], n - 1);
                double mnx = double.PositiveInfinity, mnz = double.PositiveInfinity, mxx = double.NegativeInfinity, mxz = double.NegativeInfinity;
                for (int i = a0; i < a1 + 1; i++)
                {
                    mnx = minf(mnx, t.cX[i]); mnz = minf(mnz, t.cZ[i]); mxx = maxf(mxx, t.cX[i]); mxz = maxf(mxz, t.cZ[i]);
                }
                double r = TerrainField.SPUR_R * 1.25 + 1.0;
                drops.AddRange(new[] { a0, a1, mnx - r, mnz - r, mxx + r, mxz + r });
            }
            t.c_drops = drops.ToArray();
            t.c_gx0 = c.gx0; t.c_gz0 = c.gz0; t.c_gnx = c.gnx; t.c_gnz = c.gnz;
            var cstart = c.cell_start; var citems = c.cell_items;
            var seg = new double[maxi(0, n - 1) * 6];
            for (int i = 0; i < n - 1; i++)
            {
                double bx = t.cX[i + 1] - t.cX[i], bz = t.cZ[i + 1] - t.cZ[i];
                double hl = sqrt(bx * bx + bz * bz) * 0.5;
                seg[i * 6] = bx;
                seg[i * 6 + 1] = bz;
                seg[i * 6 + 2] = bx * bx + bz * bz;
                seg[i * 6 + 3] = (t.cX[i] + t.cX[i + 1]) * 0.5;
                seg[i * 6 + 4] = (t.cZ[i] + t.cZ[i + 1]) * 0.5;
                double rr = TerrainField.QR + 0.01 + hl + 0.001;
                seg[i * 6 + 5] = rr * rr;
            }
            t.c_seg = seg;
            var runStart = new int[cstart.Length];
            var runs = new List<int>();
            for (int ci = 0; ci < cstart.Length - 1; ci++)
            {
                runStart[ci] = runs.Count;
                int a = -1, b = -1;
                for (int kk = cstart[ci]; kk < cstart[ci + 1]; kk++)
                {
                    int it = citems[kk];
                    if (a >= 0 && it == b + 1 && it - a < 255) b = it;
                    else
                    {
                        if (a >= 0) runs.Add(a * 256 + (b - a));
                        a = it; b = it;
                    }
                }
                if (a >= 0) runs.Add(a * 256 + (b - a));
            }
            runStart[cstart.Length - 1] = runs.Count;
            t.c_run_start = runStart;
            t.c_runs = runs.ToArray();
            BuildFar(t);
        }

        static void BuildFar(FieldTables t)
        {
            var cX = t.cX; var cZ = t.cZ;
            int n = cX.Length;
            t.c_far = new double[0];
            t.c_far_nx = 0; t.c_far_nz = 0;
            if (n == 0) return;
            double FC = TerrainField.FAR_CELL, FM = TerrainField.FAR_MAX;
            double mnx = double.PositiveInfinity, mxx = double.NegativeInfinity, mnz = double.PositiveInfinity, mxz = double.NegativeInfinity;
            for (int i = 0; i < n; i++) { mnx = minf(mnx, cX[i]); mxx = maxf(mxx, cX[i]); mnz = minf(mnz, cZ[i]); mxz = maxf(mxz, cZ[i]); }
            t.c_far_x0 = floori((mnx - FM) / FC);
            t.c_far_z0 = floori((mnz - FM) / FC);
            t.c_far_nx = floori((mxx + FM) / FC) - t.c_far_x0 + 1;
            t.c_far_nz = floori((mxz + FM) / FC) - t.c_far_z0 + 1;
            long nx = t.c_far_nx, nz = t.c_far_nz;
            var d = new double[nx * nz];
            for (long q = 0; q < d.Length; q++) d[q] = FM;
            for (int i = 0; i < n; i++)
            {
                long ix = floori(cX[i] / FC) - t.c_far_x0, iz = floori(cZ[i] / FC) - t.c_far_z0;
                double ex = (t.c_far_x0 + ix + 0.5) * FC - cX[i], ez = (t.c_far_z0 + iz + 0.5) * FC - cZ[i];
                long kk = iz * nx + ix;
                d[kk] = minf(d[kk], sqrt(ex * ex + ez * ez));
            }
            double c1 = FC, c2 = FC * 1.4142135623730951;
            for (long iz = 0; iz < nz; iz++)
                for (long ix = 0; ix < nx; ix++)
                {
                    long kk = iz * nx + ix;
                    double v = d[kk];
                    if (ix > 0) v = minf(v, d[kk - 1] + c1);
                    if (iz > 0)
                    {
                        v = minf(v, d[kk - nx] + c1);
                        if (ix > 0) v = minf(v, d[kk - nx - 1] + c2);
                        if (ix < nx - 1) v = minf(v, d[kk - nx + 1] + c2);
                    }
                    d[kk] = v;
                }
            for (long iz = nz - 1; iz > -1; iz--)
                for (long ix = nx - 1; ix > -1; ix--)
                {
                    long kk = iz * nx + ix;
                    double v = d[kk];
                    if (ix < nx - 1) v = minf(v, d[kk + 1] + c1);
                    if (iz < nz - 1)
                    {
                        v = minf(v, d[kk + nx] + c1);
                        if (ix < nx - 1) v = minf(v, d[kk + nx + 1] + c2);
                        if (ix > 0) v = minf(v, d[kk + nx - 1] + c2);
                    }
                    d[kk] = v;
                }
            var far = new double[d.Length];
            for (long q = 0; q < d.Length; q++) far[q] = (float)minf(d[q], FM);   // (a PackedFloat32Array in Godot)
            t.c_far = far;
        }

        // ---------------- route features (terrain_field.gd _build_route / _jump_site_why / _build_alts) ----------------
        static readonly string[][] RHYTHM =
        {
            new[] { "rhythm", "flow", "rhythm" },
            new[] { "kicker", "table", "kicker", "tableLine", "kicker", "flow", "woodKicker", "woodDrop" },
            new[] { "bridge", "skinny", "" },
        };
        static readonly HashSet<string> AIR_TYPES = new HashSet<string> { "table", "kicker", "tableLine", "woodKicker", "woodDrop", "double", "doubleLine", "flow" };
        static readonly HashSet<string> FLAT_TYPES = new HashSet<string> { "gorge", "rope", "bridge", "skinny" };
        static readonly HashSet<string> ALT_TYPES = new HashSet<string> { "table", "kicker", "tableLine", "woodDrop", "double", "doubleLine", "flow", "woodKicker" };
        const double UPHILL_MAX = 0.01, SLOW_K = 0.85, FLAT_MAX = 0.08, SKINNY_VMAX = 8.0, SKINNY_GAP = 25.0, RIDER_K = 1.4;
        const double JUMP_STRAIGHT_R = 60.0, RUNIN_T = 1.5, RUNOUT_T = 1.0, BLIND_H = 0.5;
        const double ALT_IN = 22.0, ALT_OUT = 18.0, ALT_REACH = 9.0;
        const double CSTEP = TerrainField.CSTEP;

        static double CourseE(TrailCourse C, double s)
        {
            long n = C.n;
            double f = clampf(s / CSTEP, 0.0, n - 1.001);
            long i = floori(f);
            return C.E[i] + ((double)C.E[i + 1] - C.E[i]) * (f - i);
        }

        static string JumpSiteWhy(TrailCourse C, double s, double len, double v)
        {
            double kmax = 1.0 / JUMP_STRAIGHT_R;
            double a = maxf(0.0, s - v * RUNIN_T);
            while (a <= s)
            {
                if (absf(C.KAP[clampi((long)(a / CSTEP), 0, C.n - 1)]) > kmax) return "runin";
                a += CSTEP;
            }
            a = s + len;
            while (a <= s + len + v * RUNOUT_T)
            {
                if (absf(C.KAP[clampi((long)(a / CSTEP), 0, C.n - 1)]) > kmax) return "runout";
                a += CSTEP;
            }
            double e0 = CourseE(C, s - 25.0), e1 = CourseE(C, s);
            for (int k = 1; k < 25; k++)
                if (CourseE(C, s - 25.0 + k) - (e0 + (e1 - e0) * k / 25.0) > BLIND_H) return "blind";
            return "";
        }

        static bool CanyonClear(TerrainField f, TrailCourse C, double x, double z, double dx, double dz, double s, double len)
        {
            long i0 = maxi(0, (long)((s - 300.0) / CSTEP));
            long i1 = mini(C.n - 1, (long)((s + len + 300.0) / CSTEP));
            for (long i = i0; i < i1 + 1; i++)
            {
                double si = i * CSTEP;
                if (si > s - 2.0 && si < s + len + 2.0) continue;
                double rx = C.X[(int)i] - x, rz = C.Z[(int)i] - z;
                double u = rx * dx + rz * dz, ws = -rx * dz + rz * dx;
                if (u < -8.0 || u > len + 8.0 || absf(ws) > TerrainField.CANYON_W + 6.0) continue;
                foreach (double o in new[] { -4.0, 0.0, 4.0 })
                    if (f._canyon_dig(s, len, u, ws + o) < -0.2) return false;
            }
            return true;
        }

        static double VAat(TrailCourse C, double s) => C.VA[clampi((long)(s / CSTEP), 0, C.n - 1)];

        static void BuildRoute(TerrainField f, FieldTables t, TrailCourse C, long seed, Dictionary<string, double> style)
        {
            var r = new WorldRng(seed * 104729 + 7);
            var list = new List<TfFeat>();
            double jf = clampf(style.TryGetValue("jumps", out var jv) ? jv : 1.0, 0.25, 2.5);
            foreach (var run in C.runs())
            {
                int i0 = run.Item1, i1 = run.Item2, k = run.Item3;
                bool jmp = k == TrailCourse.JUMP;
                if (!jmp && k != TrailCourse.ROAD) continue;
                double s = i0 * CSTEP + (jmp ? 4.0 : 30.0);
                double s_end = i1 * CSTEP - (jmp ? 2.0 : 30.0);
                if (!jmp) s += r.next() * 60;
                int beat = 0;
                if (jmp && (i1 - i0) * CSTEP < 120.0) beat = 1;
                var rr = jmp ? new WorldRng(seed * 15485863 + i0 * 7919 + 3) : r;
                while (s < s_end)
                {
                    bool in_drop = false;
                    foreach (var dr in C.drops)
                        if (s + 40 > dr[0] * CSTEP - 30 && s < dr[1] * CSTEP + 30) { in_drop = true; break; }
                    if (in_drop) { s += 12; continue; }
                    string[] types = jmp ? RHYTHM[beat % RHYTHM.Length] : new[] { "rhythm", "kicker", "table", "kicker" };
                    string type = types[(int)(rr.next() * types.Length)];
                    if (type == "skinny")
                    {
                        double vs = VAat(C, s + 6.0) * RIDER_K;
                        double since = s - (list.Count > 0 ? list[list.Count - 1].s + list[list.Count - 1].len : double.NegativeInfinity);
                        if (vs > SKINNY_VMAX || since < SKINNY_GAP) type = "";
                    }
                    if (type == "") { s += 10.0 + rr.next() * 6.0; beat += 1; continue; }
                    if (!jmp && r.next() < 0.13) type = "gorge";
                    else if (!jmp && s > 400.0 && (double)(unchecked(((long)(s * 8.0) * 73856093) ^ (seed * 19349663)) & 0xffff) / 65536.0 < 0.3)
                        type = "rope";
                    int size = 3;
                    if (TfSet.SIZED.ContainsKey(type))
                    {
                        double va = VAat(C, s + 12.0) * RIDER_K;
                        size = 3;
                        for (int q = 3; q > -1; q--)
                            if (TfSizes.V[q] >= va * 0.97) size = q;
                    }
                    double len = size < 3 ? TfSet.SIZED[type][size].length : TfSet.PROFILES[type].length;
                    if (s + len > s_end) break;
                    if (AIR_TYPES.Contains(type))
                    {
                        double e0 = CourseE(C, s - 15.0), e1 = CourseE(C, s + len);
                        double vin = VAat(C, s + 12.0) * RIDER_K;
                        string why;
                        if ((e1 - e0) / (len + 15.0) > UPHILL_MAX) why = "uphill";
                        else if (vin < TfSizes.V[0] * SLOW_K) why = "slow";
                        else why = JumpSiteWhy(C, s, len, vin);
                        if (why != "") { s += 10.0; continue; }
                    }
                    var p0 = C.at(s);
                    var p1 = C.at(s + len);
                    double x = p0.x, z = p0.z;
                    double ddx = p1.x - x, ddz = p1.z - z;
                    double l = sqrt(ddx * ddx + ddz * ddz);
                    if (l < len * 0.995) { s += 8; continue; }
                    double dx = ddx / l, dz = ddz / l;
                    if (FLAT_TYPES.Contains(type) && absf(CourseE(C, s + len) - CourseE(C, s)) / len > FLAT_MAX) { s += 12.0; continue; }
                    if (type == "rope" && !CanyonClear(f, C, x, z, dx, dz, s, len)) { s += 8; continue; }
                    var feat = TerrainField.make_feat(x, z, dx, dz, type, f.@base(x, z), f.@base(x + dx * len, z + dz * len), false, size);
                    feat.s = s;
                    list.Add(feat);
                    double rv = rr.next();
                    if (jmp)
                    {
                        long ie = clampi((long)((s + len) / CSTEP), 0, C.n - 1);
                        double gap = clampf(C.VA[ie] * 0.75, 6.0, 14.0) + rv * 3.0;
                        if (beat % RHYTHM.Length == RHYTHM.Length - 1) gap += 12.0;
                        s += len + gap;
                        beat += 1;
                    }
                    else s += len + (45 + rv * 60) / jf;
                }
            }
            t.route_feats = new List<FeatDesc>();
            foreach (var j in list)
                t.route_feats.Add(new FeatDesc { x = j.x, z = j.z, dx = j.dx, dz = j.dz, type = j.type, b0 = j.b0, b1 = j.b1, size = j.size, s = j.s });
            BuildAlts(t, C, list, seed);
        }

        static void BuildAlts(FieldTables t, TrailCourse C, List<TfFeat> route, long seed)
        {
            var pts = new List<double>();
            var lines = new List<double>();
            t.alt_feats = new List<long[]>();
            double last_end = double.NegativeInfinity;
            for (int fi = 0; fi < route.Count; fi++)
            {
                var f = route[fi];
                if (!ALT_TYPES.Contains(f.type)) continue;
                double h0 = (double)(unchecked(((long)(f.s * 4.0) * 73856093) ^ (seed * 83492791)) & 0xffff) / 65536.0;
                if (h0 > 0.7) continue;
                double s0 = f.s - ALT_IN, s1 = f.s + f.len + ALT_OUT;
                if (s0 < last_end + 10.0 || s0 < 30.0 || s1 > (C.n - 20) * CSTEP) continue;
                double side = h0 < 0.35 ? 1.0 : -1.0;
                double off = f.half + 4.2 + h0 * 3.0;
                int first = pts.Count / 3;
                double mnx = double.PositiveInfinity, mnz = double.PositiveInfinity, mxx = double.NegativeInfinity, mxz = double.NegativeInfinity;
                double s = s0;
                while (s <= s1)
                {
                    var p = C.at(s);
                    double w = TerrainField.sm(0.0, 12.0, s - s0) * TerrainField.sm(0.0, 12.0, s1 - s);
                    double x = p.x + (-p.tz) * off * side * w;
                    double z = p.z + p.tx * off * side * w;
                    long i = p.i;
                    double e = C.E[i] + ((double)C.E[mini(i + 1, C.n - 1)] - C.E[i]) * (s / CSTEP - i);
                    pts.Add(x); pts.Add(z); pts.Add(e);
                    mnx = minf(mnx, x); mnz = minf(mnz, z); mxx = maxf(mxx, x); mxz = maxf(mxz, z);
                    s += CSTEP;
                }
                int cnt = pts.Count / 3 - first;
                t.alt_feats.Add(new long[] { fi, lines.Count / 7 });
                lines.AddRange(new double[] { first, cnt, mnx - ALT_REACH, mnz - ALT_REACH, mxx + ALT_REACH, mxz + ALT_REACH, side });
                last_end = s1;
            }
            t.alt_pts = pts.ToArray();
            t.alt_lines = lines.ToArray();
        }
    }
}
