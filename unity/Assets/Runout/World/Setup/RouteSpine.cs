using System;
using System.Collections.Generic;
using Runout.Sim;

namespace Runout.World
{
    /// The world's route (port of godot/scripts/world/route_spine.gd, same numbers): a 2D line the whole world is laid
    /// out along. A walker steps every STEP m towards random waypoints (1.2-4 km apart, often off to a side, now and
    /// then back), wobbling, and each step picks of a few headings the one that best fits the bare land (no climbing
    /// into hills, round lakes and cliffs, away from its own earlier legs). Immutable once built: grown() returns a NEW
    /// spine laid further, continuing the walker's state (a grown spine == one built in one go).
    /// Godot's sin / cos / atan2 (SimMath) and float32 Vector2 lengths (Gd.V2) keep it bit-identical to Godot.
    public sealed class RouteSpine
    {
        public const double STEP = 20.0;
        public const double R = 450.0;            // the query's reach (m)
        public const double CELL = 160.0;
        public const double S0 = -636.0;          // the spine starts here, on +x
        public const double STRAIGHT_TO = 150.0;  // straight +x up to this s, then the walker
        public const double DH = 0.0262;          // rad: one turning notch per step
        public const int TURN_N = 4;
        public const double GAP = 1100.0;         // m: kept from its own legs further back than GAP_BACK along it
        public const double GAP_BACK = 1600.0;
        public const double LOOK = 80.0;          // m ahead it reads the land
        public const double ZMAX = 7000.0;
        public const double WP_NEAR = 1200.0, WP_FAR = 4000.0;
        public const double WP_TURN = 1.95;
        public const double BACK_MAX = 3500.0;

        public readonly List<double> X = new List<double>(), Z = new List<double>(), S = new List<double>();
        public long n;
        public long gx0, gz0, gnx, gnz;
        public int[] cell_start = Array.Empty<int>(), cell_items = Array.Empty<int>();

        // walker state (grown() carries on from it)
        WorldRng _rng = new WorldRng();
        double _x, _z, _h, _s, _wx, _wz, _wob, _maxx, _amp_k = 1.0;

        public static RouteSpine make(TerrainField field, long seed_v, double to_s, double twist = 1.0)
        {
            var sp = new RouteSpine();
            sp._rng = new WorldRng(seed_v * 7243 + 11);
            sp._amp_k = Gd.clampf(Math.Sqrt(twist), 0.6, 1.3);
            sp._x = S0; sp._z = 0.0; sp._h = 0.0; sp._s = S0;
            sp.X.Add(sp._x); sp.Z.Add(sp._z); sp.S.Add(sp._s);
            sp._wx = 900.0; sp._wz = 0.0;
            sp._extend(field, to_s);
            return sp;
        }

        public RouteSpine grown(TerrainField field, double to_s)
        {
            var sp = new RouteSpine();
            sp.X.AddRange(X); sp.Z.AddRange(Z); sp.S.AddRange(S);
            sp._rng = new WorldRng { a = _rng.a };
            sp._x = _x; sp._z = _z; sp._h = _h; sp._s = _s; sp._wx = _wx; sp._wz = _wz; sp._wob = _wob; sp._maxx = _maxx;
            sp._amp_k = _amp_k;
            sp._extend(field, to_s);
            return sp;
        }

        public double end_s() => _s;

        static double len2(double x, double z) => new V2(x, z).length();   // Godot's Vector2(x, z).length(), float32

        void _new_wp()
        {
            double best = double.NegativeInfinity;
            bool found = false;
            for (int tries = 0; tries < 24; tries++)
            {
                double ang = _h + (_rng.next() * 2.0 - 1.0) * WP_TURN;
                double l = (WP_NEAR + _rng.next() * (WP_FAR - WP_NEAR)) * _amp_k;
                double wx = _x + SimMath.Cos(ang) * l;
                double wz = _z + SimMath.Sin(ang) * l;
                double r = _rng.next();
                if (Math.Abs(wz) > ZMAX || wx < _maxx - BACK_MAX)
                    continue;
                if (!_clear_line(wx, wz))
                    continue;
                double score = Gd.minf(_open(wx, wz), 4000.0) + r * 1500.0;
                if (score > best)
                {
                    best = score; _wx = wx; _wz = wz; found = true;
                }
            }
            if (!found)
            {
                _wx = _x + 3000.0; _wz = _z * 0.5;   // nowhere free: on east, back towards the middle
            }
        }

        double _open(double x, double z)
        {
            double m = double.PositiveInfinity;
            for (int j = 0; j < S.Count; j += 4)
            {
                double ddx = X[j] - x, ddz = Z[j] - z;
                m = Gd.minf(m, ddx * ddx + ddz * ddz);
            }
            return Math.Sqrt(m);
        }

        bool _clear_line(double wx, double wz)
        {
            double lim = _s - GAP_BACK;
            long steps = (long)(len2(wx - _x, wz - _z) / 250.0) + 1;
            for (long k = 1; k < steps + 1; k++)
            {
                double px = _x + (wx - _x) * k / steps;
                double pz = _z + (wz - _z) * k / steps;
                int j = 0;
                while (j < S.Count && S[j] < lim + 250.0 * k)
                {
                    double ddx = X[j] - px, ddz = Z[j] - pz;
                    if (ddx * ddx + ddz * ddz < GAP * GAP)
                        return false;
                    j += 3;
                }
            }
            return true;
        }

        void _extend(TerrainField field, double to_s)
        {
            bool was = field.bare;
            field.bare = true;
            field._reset_caches();
            while (_s < to_s)
                _step(field);
            field.bare = was;
            field._reset_caches();
            n = X.Count;
            _build_grid();
        }

        void _step(TerrainField field)
        {
            if (_s >= STRAIGHT_TO)
            {
                if (len2(_wx - _x, _wz - _z) < 400.0)
                    _new_wp();
                _wob = Gd.clampf(_wob * 0.97 + (_rng.next() - 0.5) * 0.16, -0.8, 0.8);
                double fade = TerrainField.sm(STRAIGHT_TO, 900.0, _s);
                double hw = SimMath.Atan2(_wz - _z, _wx - _x) + _wob * fade;
                double best = double.PositiveInfinity;
                double bh = _h;
                for (int k = -TURN_N; k < TURN_N + 1; k++)
                {
                    double th = _h + k * DH;
                    double c = _cost(field, th, hw);
                    if (c < best)
                    {
                        best = c; bh = th;
                    }
                }
                _h = bh;
            }
            _x += SimMath.Cos(_h) * STEP;
            _z += SimMath.Sin(_h) * STEP;
            _s += STEP;
            _maxx = Gd.maxf(_maxx, _x);
            X.Add(_x); Z.Add(_z); S.Add(_s);
        }

        double _cost(TerrainField field, double th, double hw)
        {
            double dh = SimMath.Atan2(SimMath.Sin(th - hw), SimMath.Cos(th - hw));
            double c = 3.0 * dh * dh;
            double cx = SimMath.Cos(th), cz = SimMath.Sin(th);
            double h0 = field.landform(_x, _z);
            double h1 = field.landform(_x + cx * LOOK * 0.5, _z + cz * LOOK * 0.5);
            double h2 = field.landform(_x + cx * LOOK, _z + cz * LOOK);
            double g = (h2 - h0) / LOOK;
            if (g > 0.0)
                c += 40.0 * g * g;
            if (g < -0.12)
                c += 20.0 * (g + 0.12) * (g + 0.12);
            double lx = _x + cx * LOOK * 0.5 - cz * 30.0, lz = _z + cz * LOOK * 0.5 + cx * 30.0;
            double rx = _x + cx * LOOK * 0.5 + cz * 30.0, rz = _z + cz * LOOK * 0.5 - cx * 30.0;
            double side = Math.Abs(field.landform(lx, lz) - field.landform(rx, rz)) / 60.0;
            if (side > 0.45)
                c += 4.0 * (side - 0.45) * (side - 0.45);
            if (Gd.minf(h1, h2) < TerrainField.WATER + 0.5)
                c += 0.6;
            double qx = _x + cx * LOOK, qz = _z + cz * LOOK;
            double lim = _s - GAP_BACK;
            int j = 0;
            while (j < S.Count && S[j] < lim)
            {
                double ddx = X[j] - qx, ddz = Z[j] - qz;
                double dd = ddx * ddx + ddz * ddz;
                if (dd < GAP * GAP)
                {
                    double d = Math.Sqrt(dd);
                    c += 6.0 * (1.0 - d / GAP) * (1.0 - d / GAP);
                    if (d < GAP * 0.6)
                        c += 50.0;
                }
                j += 3;
            }
            return c;
        }

        static long floori(double v) => (long)Math.Floor(v);

        void _build_grid()
        {
            double minx = double.PositiveInfinity, maxx = double.NegativeInfinity, minz = double.PositiveInfinity, maxz = double.NegativeInfinity;
            for (int i = 0; i < n; i++)
            {
                minx = Gd.minf(minx, X[i]); maxx = Gd.maxf(maxx, X[i]); minz = Gd.minf(minz, Z[i]); maxz = Gd.maxf(maxz, Z[i]);
            }
            gx0 = floori((minx - R - CELL) / CELL);
            gz0 = floori((minz - R - CELL) / CELL);
            gnx = floori((maxx + R + CELL) / CELL) - gx0 + 1;
            gnz = floori((maxz + R + CELL) / CELL) - gz0 + 1;
            double reach = R + CELL * 0.7072;
            var counts = new int[gnx * gnz];
            for (int pass = 0; pass < 2; pass++)
            {
                if (pass == 1)
                {
                    cell_start = new int[gnx * gnz + 1];
                    int acc = 0;
                    for (long c = 0; c < gnx * gnz; c++)
                    {
                        cell_start[c] = acc;
                        acc += counts[c];
                        counts[c] = 0;
                    }
                    cell_start[gnx * gnz] = acc;
                    cell_items = new int[acc];
                }
                for (int i = 0; i < n - 1; i++)
                {
                    double ax = X[i], az = Z[i], bx = X[i + 1], bz = Z[i + 1];
                    long cx0 = floori((Gd.minf(ax, bx) - reach) / CELL) - gx0;
                    long cx1 = floori((Gd.maxf(ax, bx) + reach) / CELL) - gx0;
                    long cz0 = floori((Gd.minf(az, bz) - reach) / CELL) - gz0;
                    long cz1 = floori((Gd.maxf(az, bz) + reach) / CELL) - gz0;
                    for (long cz = Math.Max(cz0, 0); cz < Math.Min(cz1, gnz - 1) + 1; cz++)
                        for (long cx = Math.Max(cx0, 0); cx < Math.Min(cx1, gnx - 1) + 1; cx++)
                        {
                            double mx = (gx0 + cx + 0.5) * CELL, mz = (gz0 + cz + 0.5) * CELL;
                            double sx = bx - ax, sz = bz - az;
                            double l2 = sx * sx + sz * sz;
                            double t = ((mx - ax) * sx + (mz - az) * sz) / l2;
                            t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
                            double ex = ax + sx * t - mx, ez = az + sz * t - mz;
                            if (ex * ex + ez * ez > reach * reach)
                                continue;
                            long ci = cz * gnx + cx;
                            if (pass == 0)
                                counts[ci] += 1;
                            else
                            {
                                cell_items[cell_start[ci] + counts[ci]] = i;
                                counts[ci] += 1;
                            }
                        }
                }
            }
        }
    }
}
