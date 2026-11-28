using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.World
{
    /// The trail's layout (port of godot/scripts/world/trail_course.gd, same numbers): laid out by a "turtle" down the
    /// mountain and then on through the hills for ever; grown() continues the turtle into a NEW course (the old one stays
    /// untouched for threads still reading it), everything already laid out stays exactly as it was.
    /// Float32 arrays (TX ... VA) round like Godot's PackedFloat32Array; Godot's sin / cos / atan2 come from SimMath.
    /// The marking (fences, tape, signs, flags: TrailCourse.Marking.cs) is laid on by plan_marking().
    public sealed partial class TrailCourse
    {
        public const double STEP = 2.0;
        public const int START = 0, ROAD = 1, SWITCH = 2, ESSES = 3, ROCKS = 4, JUMP = 5, FINISH = 6, FOREST = 7;
        public static readonly double[] WIDTH = { 3.0, 2.7, 1.35, 1.45, 1.7, 2.5, 3.0, 0.35 };
        public static readonly double[] BERM = { 0.0, 0.45, 1.0, 0.9, 0.3, 0.0, 0.0, 1.8 };
        public const double CELL = 16.0;
        public const double QR = 19.0;
        public const double D2R = Math.PI / 180.0;
        const double TAU = 6.283185307179586;

        // layout (centreline, every STEP m)
        public List<double> X = new List<double>(), Z = new List<double>();
        public List<int> KD = new List<int>();
        public long n;
        // derived (float32 like Godot)
        public float[] TX = new float[0], TZ = new float[0], KAP = new float[0], W = new float[0], BT = new float[0], E = new float[0];
        public float[] RD = new float[0], RK = new float[0], LN = new float[0], RO = new float[0], ROS = new float[0], VA = new float[0];
        public const double VA_START = 4.0, VA_PEDAL = 0.6, VA_PED_TOP = 8.5, VA_ROLL = 0.08, VA_DRAG = 0.0033, VA_MAX = 17.5;
        public const double A_RIDE = 6.0, A_COMF = 4.0, BANK_MAX = 0.70, BERM_LINE = 0.9, BERM_LINE_FROM = 0.08, BERM_LINE_FULL = 0.22;
        public double length;
        public List<int[]> drops = new List<int[]>();
        public float[] DL = new float[0];
        public long gx0, gz0, gnx, gnz;
        public int[] cell_start = new int[0], cell_items = new int[0];

        // build state
        TerrainField _M;
        WorldRng _r;
        double _x;
        double[] _sps = new double[0];
        double _send;
        const double RUNIN = 20.0, RUNOUT = 16.0;
        const double A_BEND = 9.4;
        const int CLO_MAX = 6;
        double _v = 4.0, _hv = double.NaN, _lt = 1.0;
        double _z, _h;
        Dictionary<long, List<int>> _cells = new Dictionary<long, List<int>>();
        double _L, _hill, _corr;
        long _mark_seed;
        double _forest_end = double.NegativeInfinity;
        public List<int> flow_starts = new List<int>();

        public static double smooth(double a, double b, double x)
        {
            double t = minf(1.0, maxf(0.0, (x - a) / (b - a)));
            return t * t * (3.0 - 2.0 * t);
        }

        public static double wrap_angle(double a) => atan2(sin(a), cos(a));

        /// a new course: the mountain, then on to s = course_len
        public static TrailCourse make(WorldRng rnd, TerrainField field, double hill_len, double corridor, double course_len, long mark_seed)
        {
            var c = new TrailCourse { _M = field, _r = rnd, _hill = hill_len, _L = course_len, _corr = corridor, _mark_seed = mark_seed };
            c._x = -36; c._z = 0; c._h = 0;
            c._straight(76, START);
            c._commit(0);
            c._build();
            c._finish();
            c._M = null;
            return c;
        }

        public double end_s() => _send;

        /// (tests) the turtle's state after the start straight + the next RNG draws, like godot/tools/course_trace.gd
        public static string TraceStart(TerrainField field, long seed, double hill, double corr, double L)
        {
            var c = new TrailCourse { _M = field, _r = new WorldRng(seed * 31337 + 5), _hill = hill, _L = L, _corr = corr, _mark_seed = seed * 6151 + 3 };
            c._x = -36; c._z = 0; c._h = 0;
            c._straight(76, START);
            var sb = new System.Text.StringBuilder();
            string F(double v) => v.ToString("F17", System.Globalization.CultureInfo.InvariantCulture);
            sb.AppendLine($"TRACE after_start x={F(c._x)} z={F(c._z)} h={F(c._h)} v={F(c._v)} hv={F(c._hv)} rng={(int)c._r.a}");
            sb.AppendLine($"TRACE sp={F(c._sp())} pitch={c._next_pitch()} P0={F(field.pitches[0])} P1={F(field.pitches[1])} hill={F(hill)}");
            sb.AppendLine($"TRACE landform(0,0)={F(field.landform(0, 0))} landform(40,0)={F(field.landform(40, 0))} off={F(c._off())} rel={F(c._rel(0.0))}");
            for (int i = 0; i < 6; i++) sb.AppendLine($"TRACE rng{i}={F(c._r.next())}");
            return sb.ToString();
        }

        /// a copy of this course laid out on to s = to_s (call plan_marking(field) on the result). This one is not changed.
        public TrailCourse grown(TerrainField field, double to_s)
        {
            var c = new TrailCourse { _M = field, _r = new WorldRng { a = _r.a }, _hill = _hill, _L = to_s, _corr = _corr, _mark_seed = _mark_seed };
            c._x = _x; c._z = _z; c._h = _h; c._v = _v; c._hv = _hv; c._lt = _lt; c._forest_end = _forest_end;
            c.X = new List<double>(X); c.Z = new List<double>(Z); c.KD = new List<int>(KD); c.flow_starts = new List<int>(flow_starts);
            c._cells = new Dictionary<long, List<int>>();
            foreach (var kv in _cells) c._cells[kv.Key] = new List<int>(kv.Value);
            c._lnr_prev = _lnr;
            c._build();
            c._finish();
            c._M = null;
            return c;
        }

        // ---------------- layout ----------------
        static long _key(long gx, long gz) => gx * 100003 + gz;

        void _commit(int from)
        {
            for (int i = from; i < X.Count; i++)
            {
                long k = _key(floori(X[i] / CELL), floori(Z[i] / CELL));
                if (!_cells.TryGetValue(k, out var l)) _cells[k] = l = new List<int>();
                l.Add(i);
            }
        }

        bool _clashes(int from, double gap = 19.0)
        {
            for (int i = from; i < X.Count; i++)
            {
                long gx = floori(X[i] / CELL), gz = floori(Z[i] / CELL);
                for (int a = -2; a < 3; a++)
                    for (int b = -2; b < 3; b++)
                    {
                        if (!_cells.TryGetValue(_key(gx + a, gz + b), out var l))
                            continue;
                        foreach (int j in l)
                            if ((i - j) * STEP > 70)
                            {
                                double ddx = X[i] - X[j], ddz = Z[i] - Z[j];
                                if (sqrt(ddx * ddx + ddz * ddz) < gap)
                                    return true;
                            }
                    }
                if ((i - from) % 2 == 0)
                {
                    _M.spine_near(X[i], Z[i]);
                    if (_M.sp_ad > _corr + 15)
                        return true;
                }
            }
            return false;
        }

        void _emit(int kind, double dh = 0.0)
        {
            _x += cos(_h) * STEP;
            _z += sin(_h) * STEP;
            X.Add(_x); Z.Add(_z); KD.Add(kind);
            double h = _M.landform(_x, _z);
            double v2 = _v * _v;
            if (!double.IsNaN(_hv))
                v2 += 2.0 * 9.81 * (_hv - h);
            v2 -= 2.0 * STEP * (VA_ROLL + VA_DRAG * v2);
            if (_v < VA_PED_TOP)
                v2 += 2.0 * VA_PEDAL * STEP;
            if (absf(dh) > 1e-6)
                v2 = minf(v2, A_BEND * STEP / absf(dh));
            _v = clampf(sqrt(maxf(v2, 0.0)), VA_START, VA_MAX);
            _hv = h;
        }

        void _straight(double len, int kind, double wob = 0.0)
        {
            long cnt = maxi(1, WorldRng.jround(len / STEP));
            double ph = _r.next() * 6.28;
            for (long i = 0; i < cnt; i++)
            {
                _h += wob * cos(ph + i * 0.35) * 0.06;
                _emit(kind);
            }
        }

        void _arc(double ang, double R, int kind)
        {
            long cnt0 = maxi(1, WorldRng.jround(absf(ang) * R / STEP));
            if (cnt0 < 4)
            {
                double dh = ang / cnt0;
                for (long i = 0; i < cnt0; i++)
                {
                    _h += dh / 2;
                    _emit(kind, dh);
                    _h += dh / 2;
                }
                return;
            }
            long m = mini(CLO_MAX, maxi(1, WorldRng.jround(cnt0 * 0.25)));
            long cnt = cnt0 + m;
            double wsum = 0.0;
            for (long i = 0; i < cnt; i++)
                wsum += minf(1.0, minf((i + 0.5) / m, (cnt - i - 0.5) / m));
            for (long i = 0; i < cnt; i++)
            {
                double dh = ang * minf(1.0, minf((i + 0.5) / m, (cnt - i - 0.5) / m)) / wsum;
                _h += dh / 2;
                _emit(kind, dh);
                _h += dh / 2;
            }
        }

        void _turn_to(double target, double R, int kind) => _arc(wrap_angle(target - _h), R, kind);

        double _side_slope()
        {
            double nx = -sin(_h), nz = cos(_h);
            return absf(_M.landform(_x + nx * 40.0, _z + nz * 40.0) - _M.landform(_x - nx * 40.0, _z - nz * 40.0)) / 80.0;
        }

        double _sp() { _M.spine_near(_x, _z); return _M.sp_s; }
        double _rel(double a) { _M.spine_near(_x, _z); return _M.sp_dir + a; }
        double _off() { _M.spine_near(_x, _z); return _M.sp_d; }

        int _next_pitch()
        {
            var P = _M.pitches;
            for (int k = 0; k < P.Length; k += 3)
                if (P[k] + P[k + 1] / 2 > _sp())
                    return k;
            return -1;
        }

        struct Snap { public double x, z, h, v, hv, lt; public int size; }
        Snap _snap() => new Snap { x = _x, z = _z, h = _h, size = X.Count, v = _v, hv = _hv, lt = _lt };

        void _undo(Snap s)
        {
            _x = s.x; _z = s.z; _h = s.h; _v = s.v; _hv = s.hv; _lt = s.lt;
            X.RemoveRange(s.size, X.Count - s.size); Z.RemoveRange(s.size, Z.Count - s.size); KD.RemoveRange(s.size, KD.Count - s.size);
            while (flow_starts.Count > 0 && flow_starts[flow_starts.Count - 1] >= s.size)
                flow_starts.RemoveAt(flow_starts.Count - 1);
        }

        // sections: (code, arg)  0 road(maxLen) 1 switchbacks(endS) 2 esses(endS) 3 chute(endS) 4 jumpLine 5 esses(s+50)
        // 6 tech(endS) 7 forest(endS) 8 flow trail(endS)
        void _run((int code, double arg) sec)
        {
            switch (sec.code)
            {
                case 0: _road(sec.arg); break;
                case 1: _switchbacks(sec.arg); break;
                case 2: _esses(sec.arg); break;
                case 3: _chute(sec.arg); break;
                case 4: _jump_line(); break;
                case 5: _esses(_sp() + 50); break;
                case 6: _tech(sec.arg); break;
                case 7: _forest(sec.arg); break;
                case 8: _flow_trail(sec.arg); break;
            }
        }

        bool _attempt(params (int, double)[] fns)
        {
            for (int t = 0; t < 6; t++)
            {
                var s = _snap();
                _run(fns[t % fns.Length]);
                if (!_clashes(s.size))
                {
                    _commit(s.size);
                    return true;
                }
                _undo(s);
            }
            var s2 = _snap();
            _turn_to(_rel(0.0), 30, ROAD);
            _straight(24, ROAD);
            _commit(s2.size);
            return false;
        }

        double _sv(string k) => _M == null ? 1.0 : _M.style_v(k);

        static double _jump_remap(double p, double j, double old_band)
        {
            if (j == 1.0) return p;
            double nb = minf(old_band * j, 0.9);
            if (p < nb) return p / maxf(nb, 1e-6) * old_band;
            return old_band + (p - nb) / (1.0 - nb) * (1.0 - old_band);
        }

        void _section((int, double)[] fns, bool swap)
        {
            if ((fns[0].Item1 == 1 || fns[0].Item1 == 6) && _side_slope() < 0.10)
                swap = true;
            if (swap) _attempt((0, 50.0 + fposmod(_x * 0.37, 1.0) * 80.0));
            else _attempt(fns);
        }

        void _road(double max_len)
        {
            double len = minf(max_len, 90 + _r.next() * 150);
            double done = 0.0;
            double tw = _sv("twist");
            while (done < len)
            {
                double o = _off();
                double lim = _corr - 30;
                double tgt = (_r.next() * 2 - 1) * 72 * D2R * sqrt(tw);
                double mag = absf(tgt);
                _lt = _r.next() < 0.75 ? -_lt : _lt;
                tgt = _lt * maxf(mag, 18.0 * D2R);
                if (absf(o) > lim * 0.75)
                {
                    tgt = -signf(o) * (22 + _r.next() * 44) * D2R;
                    _lt = signf(tgt);
                }
                tgt = _rel(tgt);
                double seg = minf(len - done, 18 + _r.next() * 40);   // (the old spacing: its draw stays, so the stream matches)
                seg = minf(len - done, clampf(_v * (1.5 + _r.next() * 1.5), 15.0, 70.0));
                double R;
                if (_r.next() < minf(0.42 * tw, 0.95)) R = 13 + _r.next() * 16;
                else R = (34 + _r.next() * 56) / maxf(0.6, sqrt(tw));
                R = maxf(R, _v * _v / A_BEND);
                int n0 = X.Count;
                _turn_to(tgt, R, ROAD);
                double used = (X.Count - n0) * STEP;
                if (used < seg)
                    _straight(seg - used, ROAD);
                done += maxf(seg, used);
                if (_sp() > _L - 70)
                    break;
            }
        }

        void _switchbacks(double end_x)
        {
            int first = _off() > 0 ? -1 : 1;
            double alpha = (12 + _r.next() * 10) * D2R;
            double R = 7 + _r.next() * 2.5;
            int dir = first;
            int k = 0;
            _turn_to(_rel(dir * (Math.PI / 2 - alpha)), 11 + _r.next() * 4, SWITCH);
            while (k < 6)
            {
                double room = (_corr - 12 - dir * _off()) / cos(alpha);
                _straight(maxf(14, minf(26 + _r.next() * 20, room)), SWITCH, 0.4);
                if (_sp() > end_x && k >= 2)
                    break;
                dir = -dir;
                k += 1;
                _turn_to(_rel(dir * (Math.PI / 2 - alpha)), R, SWITCH);
            }
            _turn_to(_rel(0.0), 12 + _r.next() * 4, SWITCH);
            _straight(8, SWITCH);
        }

        void _esses(double end_x, int kind = ESSES)
        {
            int dir = _r.next() < 0.5 ? 1 : -1;
            int k = 0;
            if (absf(_off()) > 30)
                dir = -(int)signf(_off());
            while (k < 9)
            {
                double ang = (38 + _r.next() * 34) * D2R;
                double R = 10 + _r.next() * 8;
                _turn_to(_rel(dir * ang), R, kind);
                _straight(3 + _r.next() * 6, kind);
                dir = -dir;
                k += 1;
                if (_sp() > end_x && k >= 3)
                    break;
            }
            _turn_to(_rel(0.0), 14, kind);
        }

        void _tech(double end_x)
        {
            int dir = _r.next() < 0.5 ? 1 : -1;
            if (absf(_off()) > 25)
                dir = -(int)signf(_off());
            double alpha = (14 + _r.next() * 16) * D2R;
            double R = 5.0 + _r.next() * 1.5;
            int k = 0;
            _turn_to(_rel(dir * (Math.PI / 2 - alpha)), 8 + _r.next() * 3, SWITCH);
            while (k < 7)
            {
                double leg = 8 + _r.next() * 9;
                if (_r.next() < 0.35)
                {
                    _straight(leg * 0.4, SWITCH);
                    _arc(-dir * 0.7, 6.5, SWITCH);
                    _arc(dir * 0.7, 6.5, SWITCH);
                    _straight(leg * 0.3, SWITCH);
                }
                else _straight(leg, SWITCH, 0.3);
                if (_sp() > end_x && k >= 3)
                    break;
                dir = -dir;
                k += 1;
                _turn_to(_rel(dir * (Math.PI / 2 - alpha)), R, SWITCH);
            }
            _turn_to(_rel(0.0), 9, SWITCH);
            _straight(6, SWITCH);
        }

        void _forest(double end_x)
        {
            int dir = _r.next() < 0.5 ? 1 : -1;
            if (absf(_off()) > 25)
                dir = -(int)signf(_off());
            _turn_to(_rel(dir * 0.4), 14, FOREST);
            int k = 0;
            while (k < 16)
            {
                _straight(5 + _r.next() * 9, FOREST, 0.5);
                if (_sp() > end_x && k >= 5)
                    break;
                dir = -dir;
                if (absf(_off()) > _corr - 35)
                    dir = -(int)signf(_off());
                _turn_to(_rel(dir * (35 + _r.next() * 35) * D2R), 6 + _r.next() * 4, FOREST);
                k += 1;
            }
            _turn_to(_rel(0.0), 12, FOREST);
            _straight(6, FOREST);
        }

        bool _forest_here()
        {
            if (_sp() < _forest_end + 250.0)
                return false;
            _M.biome(_x, _z);
            return _M.b_forest > 0.45 && _side_slope() > 0.03;
        }

        void _chute(double end_x)
        {
            _turn_to(_rel((_r.next() - .5) * 16 * D2R), 18, ROCKS);
            _straight(maxf(26, end_x - _sp() + 6), ROCKS, 0.25);
        }

        void _flow_trail(double end_x)
        {
            flow_starts.Add(X.Count);
            int dir = _r.next() < 0.5 ? 1 : -1;
            if (absf(_off()) > 30)
                dir = -(int)signf(_off());
            _turn_to(_rel(dir * 0.3), 30, ROAD);
            _straight(8, ROAD);
            int k = 0;
            while (k < 9)
            {
                _straight(RUNIN, ROAD);
                _straight(36 + _r.next() * 24, JUMP);
                _straight(RUNOUT, ROAD);
                if (_sp() > end_x && k >= 3)
                    break;
                if (absf(_off()) > _corr - 40)
                    dir = -(int)signf(_off());
                _turn_to(_rel(dir * (28 + _r.next() * 28) * D2R), 16 + _r.next() * 8, ESSES);
                _straight(4, ESSES);
                dir = -dir;
                k += 1;
            }
            _turn_to(_rel(0.0), 25, ROAD);
            _straight(8, ROAD);
        }

        void _jump_pick(double sh)
        {
            if (fposmod(sh * 0.917, 1.0) < 0.55)
                _attempt((8, sh + 200.0 + fposmod(sh * 0.371, 1.0) * 180.0), (4, 0.0));
            else
                _attempt((4, 0.0));
        }

        const double FALL_SPREAD = 0.7;
        double _fall_heading()
        {
            double l0 = _M.landform(_x, _z);
            _M.spine_near(_x, _z);
            double sd = _M.sp_dir;
            double best = double.NaN;
            double best_drop = 0.45;
            for (int k = -7; k < 8; k++)
            {
                double hh = _h + k * FALL_SPREAD / 7.0;
                if (absf(wrap_angle(hh - sd)) > 1.0) continue;
                double prev = l0;
                bool ok = true;
                foreach (double d in new[] { 50.0, 100.0, 150.0 })
                {
                    double ld = _M.landform(_x + cos(hh) * d, _z + sin(hh) * d);
                    if (ld > prev + 0.6) { ok = false; break; }
                    prev = ld;
                }
                if (ok && l0 - prev > best_drop)
                {
                    best_drop = l0 - prev;
                    best = hh;
                }
            }
            return best;
        }

        void _jump_line()
        {
            double fh = _fall_heading();
            if (double.IsNaN(fh)) _turn_to(_rel((_r.next() - .5) * 14 * D2R), 40, ROAD);
            else _turn_to(fh, 40, ROAD);
            _straight(RUNIN, ROAD);
            _straight(110 + _r.next() * 60, JUMP);
            _straight(RUNOUT, ROAD);
        }

        void _build()
        {
            int guard = 0;
            var P = _M.pitches;
            while (_sp() < _L - 80 && guard < 4000)
            {
                guard += 1;
                double sh = _sp();
                int pk = _next_pitch();
                double to_pitch = pk >= 0 ? (P[pk] - P[pk + 1] / 2 - sh) : double.PositiveInfinity;
                if (to_pitch < 30)
                {
                    double end_x0 = P[pk] + P[pk + 1] / 2 + 6;
                    double pick = _r.next();
                    if (pick < 0.45) _attempt((1, end_x0), (2, end_x0), (3, end_x0));
                    else if (pick < 0.75) _attempt((3, end_x0), (2, end_x0), (1, end_x0));
                    else _attempt((2, end_x0), (1, end_x0), (3, end_x0));
                    continue;
                }
                double room = minf(to_pitch, _L - 80 - sh);
                double pick2 = _r.next();
                double jst = _sv("jumps");
                double tst = _sv("twist");
                if (pk < 0 && sh > _hill - 80)
                {
                    _attempt((0, 40 + _r.next() * 90));
                    sh = _sp();
                    if (_forest_here() && fposmod(sh * 0.0137, 1.0) < 0.7)
                    {
                        _attempt((7, sh + 140.0 + fposmod(sh * 0.731, 1.0) * 220.0));
                        _forest_end = _sp();
                        continue;
                    }
                    double end_x = sh + 50 + _r.next() * 70;
                    _M.range_at(sh + 30.0);
                    bool down = _M.rg_down > 0.5;
                    bool climbing = _M.hill_top(sh + 60.0) > _M.hill_top(sh) + 1.5;
                    climbing = double.IsNaN(_fall_heading());
                    bool swap = tst < 1.0 && fposmod(pick2 * 977.0, 1.0) < (1.0 - tst) * 0.9;
                    bool did_jump = false;
                    double c_es = 0.7;
                    double c_ch = 1.0 - 0.22 * clampf(jst, 0.0, 2.0);
                    if (down)
                    {
                        if (pick2 < 0.4) _section(new[] { (6, end_x), (1, end_x), (2, end_x) }, swap);
                        else if (pick2 < 0.62) _section(new[] { (1, end_x), (6, end_x), (2, end_x) }, swap);
                        else if (pick2 < c_es) _section(new[] { (2, end_x), (1, end_x), (3, end_x) }, swap);
                        else if (pick2 < c_ch || climbing) _section(new[] { (3, end_x), (2, end_x), (1, end_x) }, swap);
                        else { _jump_pick(sh); did_jump = true; }
                    }
                    else
                    {
                        double q = _jump_remap(pick2, jst, 0.3);
                        double jq = 0.45;
                        if (q < jq && !climbing) { _jump_pick(sh); did_jump = true; }
                        else if (q < 0.55) _section(new[] { (2, end_x), (1, end_x), (3, end_x) }, swap);
                        else if (q < 0.68) _section(new[] { (6, end_x), (1, end_x), (2, end_x) }, swap);
                        else if (q < 0.84) _section(new[] { (1, end_x), (2, end_x), (3, end_x) }, swap);
                        else _section(new[] { (3, end_x), (2, end_x), (1, end_x) }, swap);
                    }
                    if (tst > 1.0 && !did_jump && fposmod(pick2 * 613.0, 1.0) < (tst - 1.0) * 0.7)
                        _attempt((6, end_x), (1, end_x), (2, end_x));
                    continue;
                }
                if (room > 230 && pick2 < 0.7 * clampf(jst, 0.0, 1.35))
                {
                    _attempt((0, maxf(50, room - 190)));
                    if (jst > 0.05 && !double.IsNaN(_fall_heading())) _attempt((4, 0.0));
                    else _attempt((5, 0.0));
                }
                else if (room > 150 && pick2 < 0.85)
                {
                    _attempt((0, maxf(50, room - 110)));
                    _attempt((5, 0.0));
                }
                else
                    _attempt((0, maxf(40, to_pitch - 20)));
            }
            n = X.Count;
            _send = _sp();
        }

        // ---------------- derived data ----------------
        float[] _fade_mask(float[] m, int rad)
        {
            var lo = new float[n];
            for (long i = 0; i < n; i++)
            {
                double v = 1.0;
                for (long k = maxi(0, i - rad); k < mini(n - 1, i + rad) + 1; k++)
                    v = minf(v, m[k]);
                lo[i] = (float)v;
            }
            var o = _avg(lo, rad);
            for (long i = 0; i < n; i++) o[i] = (float)smooth(0.0, 1.0, o[i]);
            return o;
        }

        float[] _avg(float[] src, int rad)
        {
            var o = new float[n];
            for (long i = 0; i < n; i++)
            {
                double s = 0.0;
                long c = 0;
                for (long k = maxi(0, i - rad); k < mini(n - 1, i + rad) + 1; k++)
                {
                    s += src[k];
                    c += 1;
                }
                o[i] = (float)(s / c);
            }
            return o;
        }

        void _finish()
        {
            _sps = new double[n];
            for (int i = 0; i < n; i++)
            {
                _M.spine_near(X[i], Z[i]);
                _sps[i] = _M.sp_s;
            }
            TX = new float[n]; TZ = new float[n];
            var th = new float[n];
            for (long i = 0; i < n; i++)
            {
                int a = (int)maxi(0, i - 1), b = (int)mini(n - 1, i + 1);
                double dx = X[b] - X[a], dz = Z[b] - Z[a];
                double l = sqrt(dx * dx + dz * dz);
                if (l == 0.0) l = 1.0;
                TX[i] = (float)(dx / l); TZ[i] = (float)(dz / l); th[i] = (float)atan2(dz, dx);
            }
            var kap = new float[n];
            for (long i = 1; i < n - 1; i++)
                kap[i] = (float)(wrap_angle((double)th[i + 1] - th[i - 1]) / (2 * STEP));
            KAP = _avg(kap, 2);
            var wsrc = new float[n];
            for (int i = 0; i < n; i++) wsrc[i] = (float)WIDTH[KD[i]];
            W = _avg(wsrc, 5);
            var raw = new float[n];
            for (int i = 0; i < n; i++) raw[i] = (float)maxf(TerrainField.WATER + 0.7, _M.landform(X[i], Z[i]));
            var smv = _avg(raw, 5);
            for (long i = 1; i < n; i++) smv[i] = (float)minf(smv[i], smv[i - 1]);
            E = _avg(smv, 2);
            if (_L > _hill + 1.0)
            {
                var fr = _avg(_avg(_avg(raw, 10), 10), 10);
                for (long i = 0; i < n; i++)
                {
                    double w = smooth(_hill + 60, _hill + 360, _sps[i]);
                    if (w > 0.0) E[i] = (float)(E[i] + (fr[i] - (double)E[i]) * w);
                }
            }
            _shape_profile();
            var bsrc = new float[n];
            for (int i = 0; i < n; i++)
            {
                double k = KAP[i];
                bsrc[i] = (float)(signf(k) * minf(0.6, 17 * absf(k)) * smooth(0.012, 0.03, absf(k)) * BERM[KD[i]]);
            }
            var need = _bank_need(bsrc);
            for (long i = 0; i < n; i++)
                if (absf(need[i]) > absf(bsrc[i])) bsrc[i] = need[i];
            var held = new float[n];
            for (long i = 0; i < n; i++)
            {
                double best = 0.0;
                for (long k = maxi(0, i - 6); k < mini(n - 1, i + 6) + 1; k++)
                    if (absf(bsrc[k]) > absf(best)) best = bsrc[k];
                held[i] = (float)best;
            }
            BT = _avg(_avg(_avg(held, 5), 5), 5);
            _racing_line();
            var rd = new float[n];
            var rk = new float[n];
            for (int i = 0; i < n; i++)
            {
                int k = KD[i];
                rd[i] = (k == ROAD || k == START || k == FINISH) ? 1f : 0f;
                rk[i] = k == ROCKS ? 1f : 0f;
            }
            RD = _avg(rd, 4);
            RK = _avg(rk, 4);
            _speed_profile();
            length = (n - 1) * STEP;
            // dense spatial hash
            long minx = 1 << 30, minz = 1 << 30, maxx = -(1 << 30), maxz = -(1 << 30);
            var keys = new int[maxi(0, n - 1) * 2];
            for (int i = 0; i < n - 1; i++)
            {
                long gx = floori((X[i] + X[i + 1]) / 2 / CELL), gz = floori((Z[i] + Z[i + 1]) / 2 / CELL);
                keys[i * 2] = (int)gx; keys[i * 2 + 1] = (int)gz;
                minx = mini(minx, gx); minz = mini(minz, gz);
                maxx = maxi(maxx, gx); maxz = maxi(maxz, gz);
            }
            gx0 = minx; gz0 = minz;
            gnx = maxx - minx + 1; gnz = maxz - minz + 1;
            var counts = new int[gnx * gnz + 1];
            for (int i = 0; i < n - 1; i++)
                counts[(keys[i * 2] - gx0) * gnz + keys[i * 2 + 1] - gz0 + 1] += 1;
            for (int c = 1; c < counts.Length; c++) counts[c] += counts[c - 1];
            cell_start = (int[])counts.Clone();
            cell_items = new int[n - 1];
            var fill = (int[])counts.Clone();
            for (int i = 0; i < n - 1; i++)
            {
                long c = (keys[i * 2] - gx0) * gnz + keys[i * 2 + 1] - gz0;
                cell_items[fill[c]] = i;
                fill[c] += 1;
            }
        }

        // ---------------- the racing line ----------------
        const double BERM_FLOOR = 0.15, LINE_MARGIN = 0.45;
        static readonly int[][] LINE_PASSES = { new[] { 16, 24 }, new[] { 8, 24 }, new[] { 4, 30 }, new[] { 2, 30 }, new[] { 1, 20 } };
        const int LINE_REACH = 800;
        float[] _lnr = new float[0];
        float[] _lnr_prev = new float[0];

        float[] _min_curvature_line()
        {
            var ln = new float[n];
            long keep = clampi(_lnr_prev.Length - LINE_REACH, 0, n);
            for (long i = 0; i < keep; i++) ln[i] = _lnr_prev[i];
            _lnr_prev = new float[0];
            var lim = new float[n];
            var bs = new float[n];
            var bf = new float[n];
            for (long i = 0; i < n; i++)
            {
                lim[i] = (float)maxf(0.0, W[i] - LINE_MARGIN);
                double bw = smooth(BERM_LINE_FROM, BERM_LINE_FULL, absf(BT[i]));
                bs[i] = (float)(-signf(BT[i]));
                double fl = lerpf(BERM_FLOOR, BERM_LINE, smooth(0.3, 0.55, absf(BT[i])));
                bf[i] = (float)minf(lim[i], bw * minf(fl, maxf(0.0, W[i] - 0.9)));
            }
            var nx = new float[n];
            foreach (var pass in LINE_PASSES)
            {
                int k = pass[0];
                for (int it = 0; it < pass[1]; it++)
                {
                    for (long i = maxi(k, keep); i < n - k; i++)
                    {
                        int a = (int)(i - k), b = (int)(i + k);
                        double mx = 0.5 * (X[a] - TZ[a] * (double)ln[a] + X[b] - TZ[b] * (double)ln[b]);
                        double mz = 0.5 * (Z[a] + TX[a] * (double)ln[a] + Z[b] + TX[b] * (double)ln[b]);
                        double o = -(mx - X[(int)i]) * TZ[i] + (mz - Z[(int)i]) * TX[i];
                        double v = clampf(lerpf(ln[i], o, 0.7), -lim[i], lim[i]);
                        if (v * bs[i] < bf[i])
                            v = (double)bs[i] * bf[i];
                        nx[i] = (float)v;
                    }
                    for (long i = maxi(k, keep); i < n - k; i++)
                        ln[i] = nx[i];
                }
            }
            _lnr = ln;
            return ln;
        }

        void _racing_line()
        {
            var ln = _min_curvature_line();
            LN = _avg(ln, 3);
            RO = new float[n];
            ROS = new float[n];
            long seed_i = _mark_seed % 9973;
            int i = 12;
            while (i < n - 60)
            {
                double k = absf(KAP[i]);
                if (k < 0.035 || k < absf(KAP[i - 1]) || k <= absf(KAP[i + 1]) || _hash(i, seed_i + 77) > 0.4)
                {
                    i += 1;
                    continue;
                }
                int i0 = i - 3 - (int)(_hash(i, seed_i + 78) * 5.0);
                double p0x = X[i0] - TZ[i0] * (double)LN[i0];
                double p0z = Z[i0] + TX[i0] * (double)LN[i0];
                double dx = TX[i0], dz = TZ[i0];
                int j = i0;
                double last = 0.0;
                while (j < n - 2 && j < i0 + 40)
                {
                    double den = dx * TX[j] + dz * TZ[j];
                    if (den < 0.3)
                        break;
                    double tt = ((X[j] - p0x) * TX[j] + (Z[j] - p0z) * TZ[j]) / den;
                    last = -(p0x + dx * tt - X[j]) * TZ[j] + (p0z + dz * tt - Z[j]) * TX[j];
                    RO[j] = (float)last;
                    ROS[j] = (float)minf(1.0, 0.35 + 0.35 * (j - i0));
                    j += 1;
                    if (absf(last) > W[j] + 2.4)
                        break;
                }
                for (int q = (int)maxi(0, i0 - 2); q < i0; q++)
                    if (ROS[q] == 0.0f) RO[q] = RO[i0];
                for (int q = j; q < mini(n, j + 2); q++)
                    if (ROS[q] == 0.0f) RO[q] = (float)last;
                i = j + 20;
            }
        }

        public static double _hash(long k, long salt)
        {
            double v = sin((double)k * 12.9898 + (double)salt * 78.233) * 43758.5453;
            return v - Math.Floor(v);
        }

        // ---------------- the trail's height: rolling dips, grade reversals, drop-offs ----------------
        void _shape_profile()
        {
            long seed_i = _mark_seed % 9973;
            double roll = _sv("rolling");
            var on_road = new float[n];
            for (int i = 0; i < n; i++) on_road[i] = KD[i] == ROAD ? 1f : 0f;
            on_road = _fade_mask(on_road, 6);
            for (long i = 0; i < n; i++)
            {
                double w = smooth(_hill + 60, _hill + 360, _sps[i]) * on_road[i];
                if (w <= 0.0)
                    continue;
                double s = i * STEP;
                double amp = (0.3 + 1.5 * (0.5 + 0.5 * sin(s / 310.0 + seed_i))) * roll;
                E[i] = (float)(E[i] + w * amp * sin(s * TAU / 60.0 + 0.7 * sin(s / 140.0)));
            }
            {
                var e0 = (float[])E.Clone();
                double ph = 0.0;
                var ok_k = new float[n];
                for (int i = 0; i < n; i++)
                {
                    int k = KD[i];
                    ok_k[i] = (i < 10 || i >= n - 10 || k == JUMP || k == ROCKS || k == START || k == FINISH) ? 0f : 1f;
                }
                ok_k = _fade_mask(ok_k, 6);
                for (long i = 0; i < n; i++)
                {
                    double s = i * STEP;
                    ph += TAU * STEP / (35.0 + 10.0 * sin(s / 170.0 + seed_i * 0.37));
                    if (ok_k[i] <= 0.0)
                        continue;
                    double gr = ((double)e0[i + 10] - e0[i - 10]) / (20.0 * STEP);
                    double w = smooth(0.03, 0.07, -gr) * ok_k[i];
                    if (w > 0.0)
                        E[i] = (float)(E[i] + w * (0.45 + 0.15 * sin(s / 230.0 + seed_i)) * sin(ph));
                }
            }
            drops = new List<int[]>();
            DL = new float[n];
            int last_end = 0;
            const int SLOT = 80;
            int kslot = 1;
            while (kslot * SLOT + 20 < n - 80)
            {
                int kk = kslot;
                kslot += 1;
                double r = _hash(kk, seed_i);
                bool big = r < 0.02 * roll;
                if (!big && r > 0.16 * roll)
                    continue;
                double hh = big ? (12.0 + _hash(kk, seed_i + 1) * 10.0) : (3.0 + _hash(kk, seed_i + 1) * 3.5);
                int ramp = (int)(hh / 0.04 / STEP);
                int hold = 6 + (int)(_hash(kk, seed_i + 2) * 6.0);
                var prof = _drop_shape(hh, big);
                int dl = (int)ceil((prof.Length - 1) * DROP_DX / STEP);
                int a = -1, e = 0;
                for (int off = 0; off < SLOT; off += 4)
                {
                    int a0 = kk * SLOT + off + ramp;
                    int e0 = a0 + hold + dl;
                    if (a0 - ramp < last_end + 10 || e0 + 8 >= n - 80)
                        continue;
                    bool ok = true;
                    for (int q = a0 + hold - 14; q < e0 + 8; q++)
                        if (KD[q] != ROAD || absf(KAP[q]) > 0.012) { ok = false; break; }
                    if (ok) { a = a0; e = e0; break; }
                }
                if (a < 0)
                    continue;
                for (int q = a - ramp; q < e + 1; q++)
                {
                    double lift = hh;
                    if (q < a)
                        lift = hh * smooth(0.0, 1.0, (double)(q - (a - ramp)) / ramp);
                    else if (q > a + hold)
                        lift = hh - _drop_at(prof, (q - (a + hold)) * STEP);
                    E[q] = (float)(E[q] + lift);
                    DL[q] = (float)lift;
                }
                drops.Add(new[] { a - ramp, e });
                last_end = e;
            }
        }

        const double DROP_V = 16.0, DROP_SMAX = 0.70, DROP_SMAX_BIG = 0.78, DROP_RB = 22.0, DROP_DX = 0.25;

        /// depth below the lip every DROP_DX m from it, ending at exactly hh
        static float[] _drop_shape(double hh, bool big)
        {
            double smax = big ? DROP_SMAX_BIG : DROP_SMAX;
            var o = new List<float> { 0f };
            double d = 0.0, x = 0.0, s = 0.0;
            bool bending = false;
            int guard = 0;
            while (guard < 4000)
            {
                guard += 1;
                x += DROP_DX;
                double a = atan(s);
                if (!bending && hh - d <= DROP_RB * (1.0 - cos(a)) && s > 0.0)
                    bending = true;
                if (bending)
                {
                    a = maxf(0.0, a - DROP_DX / (DROP_RB * maxf(0.3, cos(a))));
                    s = tan(a);
                }
                else s = minf(smax, 9.81 * x / (DROP_V * DROP_V));
                d += s * DROP_DX;
                o.Add((float)d);
                if (bending && s <= 1e-4) break;
            }
            double k = hh / maxf(1e-3, d);
            var arr = o.ToArray();
            for (int i = 0; i < arr.Length; i++) arr[i] = (float)(arr[i] * k);
            return arr;
        }

        static double _drop_at(float[] prof, double x)
        {
            double f = x / DROP_DX;
            int i = (int)f;
            if (i >= prof.Length - 1) return prof[prof.Length - 1];
            return lerpf(prof[i], prof[i + 1], f - i);
        }

        float[] _bank_need(float[] b)
        {
            var o = new float[n];
            double v2 = VA_START * VA_START;
            for (long i = 1; i < n; i++)
            {
                double v = sqrt(v2);
                double a = -VA_ROLL - VA_DRAG * v2 + (v < VA_PED_TOP ? VA_PEDAL : 0.0);
                v2 = clampf(v2 + 2.0 * (9.81 * ((double)E[i - 1] - E[i]) + a * STEP), 4.0, VA_MAX * VA_MAX);
                double k = absf(KAP[i]);
                if (k > 0.004)
                {
                    double t = 0.0;
                    if (BERM[KD[(int)i]] >= 0.4)
                    {
                        t = clampf((v2 * k - A_RIDE) / 9.81, 0.0, BANK_MAX);
                        o[i] = (float)(signf(KAP[i]) * t);
                    }
                    v2 = minf(v2, (A_RIDE + 9.81 * maxf(t, absf(b[i]))) / k);
                }
            }
            return o;
        }

        void _speed_profile()
        {
            VA = new float[n];
            double v2 = VA_START * VA_START;
            VA[0] = (float)VA_START;
            for (long i = 1; i < n; i++)
            {
                double v = sqrt(v2);
                double a = -VA_ROLL - VA_DRAG * v2 + (v < VA_PED_TOP ? VA_PEDAL : 0.0);
                v2 = clampf(v2 + 2.0 * (9.81 * ((double)E[i - 1] - E[i]) + a * STEP), 4.0, VA_MAX * VA_MAX);
                double k = absf(KAP[i]);
                if (k > 0.004)
                {
                    double bank = BT.Length == n ? absf(BT[i]) : 0.0;
                    v2 = minf(v2, (A_RIDE + 9.81 * bank) / k);
                }
                VA[i] = (float)sqrt(v2);
            }
        }

        /// point on the centreline at arc length s -> (x, z, tx, tz, i)
        public (double x, double z, double tx, double tz, long i) at(double s)
        {
            double f = minf(n - 1.001, maxf(0.0, s / STEP));
            long i = floori(f);
            double t = f - i;
            return (X[(int)i] + (X[(int)i + 1] - X[(int)i]) * t, Z[(int)i] + (Z[(int)i + 1] - Z[(int)i]) * t, TX[i], TZ[i], i);
        }

        /// runs of one kind: (first, last, kind)
        public List<(int, int, int)> runs()
        {
            var o = new List<(int, int, int)>();
            int s = 0;
            for (int i = 1; i < n + 1; i++)
                if (i == n || KD[i] != KD[s])
                {
                    o.Add((s, i - 1, KD[s]));
                    s = i;
                }
            return o;
        }
    }
}
