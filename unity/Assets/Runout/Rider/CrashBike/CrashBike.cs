using System;
using System.Collections.Generic;
using Runout.Sim;

namespace Runout.Rider
{
    /// The crashed bike as a real body: engine-free port of godot/scripts/bike/CrashBikeCs.cs (same maths, constants and
    /// order; Godot's float32 Vector3 / Transform3D at the API became double Vec3 / Xf). Position-based dynamics with
    /// rigid shape matching (Mueller et al. 2005, rotation extraction after Mueller et al. 2016):
    ///   - the bike = a cloud of points: the hull of the frame's meshes (support points along 26 directions), the hull of
    ///     the steer's meshes (bars, levers, fork), and a ring round each tyre (CrashBikeStart builds it).
    ///   - every substep the points move on their own (Verlet: gravity, air drag), are pushed out of the drawn ground and
    ///     of trunks with Coulomb friction (a tyre standing up rolls along its plane, lying flat it slides), then the whole
    ///     cloud is matched back to its rigid shape. The steer points are matched to the rest shape turned by the bars'
    ///     angle theta about the head tube; theta is fitted to where the steer points were pushed (stops at SteerLim).
    ///   - a wheel can come off: its ring + axle then become a rigid body of their own.
    /// It sleeps once it lies still. Everything in SIM space (Godot axes: y up, forward = (cos h, 0, -sin h)).
    /// Implements ICrashSim: set BikeSim.crash_sim to it (CrashBikeHost.Step drives it and reads the bike back).
    public sealed class CrashBike : ICrashSim
    {
        // ---- points -------------------------------------------------------------------------------------------------------
        private int _n;
        private double[] _x = Array.Empty<double>(), _y = Array.Empty<double>(), _z = Array.Empty<double>();   // now
        private double[] _px = Array.Empty<double>(), _py = Array.Empty<double>(), _pz = Array.Empty<double>(); // a substep ago
        private double[] _rx = Array.Empty<double>(), _ry = Array.Empty<double>(), _rz = Array.Empty<double>(); // rest (owner's frame)
        private double[] _m = Array.Empty<double>(), _rad = Array.Empty<double>();
        private int[] _grp = Array.Empty<int>();   // 0 frame, 1 steer (turns with theta)
        private int[] _wid = Array.Empty<int>();   // -1 none, 0 front wheel, 1 rear wheel (its ring / axle)
        private int[] _own = Array.Empty<int>();   // 0 bike, 1 the front wheel off on its own, 2 the rear wheel off
        private double[] _gh = Array.Empty<double>(), _ghx = Array.Empty<double>(), _ghz = Array.Empty<double>();   // ground read cache
        private double[] _nacc = Array.Empty<double>(), _vin = Array.Empty<double>();

        // ---- the bike's rigid frame + steer hinge (body coordinates = the model at the crash start, metric) ----------------
        private DQ _qB = DQ.Identity;
        private DV _cB, _c0B;           // centre of mass now / in rest coords
        private DV _piv, _axis;         // head tube: a point on the steering axis and its direction (body coords)
        private double _theta, _theta0;
        private Xf _K0 = Xf.IDENTITY, _K1 = Xf.IDENTITY;            // each wheel node's transform in body coords at the crash start (front at theta0)
        private readonly DQ[] _qW = { DQ.Identity, DQ.Identity };
        private readonly DV[] _cW = new DV[2], _c0W = new DV[2];
        private readonly bool[] _off = new bool[2];
        private readonly Xf[] _wd = { Xf.IDENTITY, Xf.IDENTITY };   // the wheel node's transform when it came off
        private readonly Xf[] _wr = { Xf.IDENTITY, Xf.IDENTITY };   // ... its rigid frame (the wheel body's rest frame)
        private readonly double[] _hit = new double[2];   // the hardest hit on each wheel this step (m/s)
        private readonly double[] _axR = new double[2];   // tyre radius

        // interpolation (drawing between physics steps)
        private Xf _bodyPrev = Xf.IDENTITY, _bodyCur = Xf.IDENTITY;
        private double _thPrev, _thCur;
        private readonly Xf[] _wPrev = { Xf.IDENTITY, Xf.IDENTITY }, _wCur = { Xf.IDENTITY, Xf.IDENTITY };

        // ---- the world ----------------------------------------------------------------------------------------------------
        private Func<double, double, double> _top;   // the drawn ground's height (x, z); null = none (-1e9)
        private double[] _cyl = Array.Empty<double>();   // trunks: x, z, r, top per collider

        /// the lean frame (BikeRig's root after heading / pitch / lean = the rider's space) in body coords: read back by
        /// CrashBikeHost as BodyAt(1) * RK (Godot: phys.crash_RK). Set by CrashBikeStart.
        public Xf RK = Xf.IDENTITY;
        /// the model in body coords (draw the crashed model at BodyAt(a) * K; Godot: phys.crash_K)
        public Xf K = Xf.IDENTITY;

        // ---- tuning -------------------------------------------------------------------------------------------------------
        public double Mu = 0.72;            // sliding friction, metal / plastic on dirt
        public double TyreMu = 0.95;        // tyres sideways
        public double RollMu = 0.035;       // a tyre rolling along its plane
        public double Bounce = 0.18;        // restitution of a hard hit (frame / bars)
        public double TyreBounce = 0.32;    // ... of a tyre
        public double SteerLim = 1.2;       // rad: the bars' lock either way (they hit the frame)
        public double SteerFric = 0.03;     // headset + cable drag (share of the bars' swing lost per substep)
        public double Drag = 0.02;          // air, per second
        public double WallRise = 0.4;       // m: ground this much higher in one move = a wall, not a slope
        public int Iters = 4;
        public int Substeps = 2;   // per physics step (120 Hz -> 240 Hz)

        private bool _asleep;
        private double _still;
        public bool Asleep => _asleep;
        public double HitFront => _hit[0];
        public double HitRear => _hit[1];
        public bool WheelOff(int w) => _off[w];
        public int PointCount => _n;

        private const double G = 9.81;

        // =====================================================================================================================
        /// pts: world positions (x, y, z per point); grp / wid per point (see above); mass, radius per point.
        /// body0: the model's rigid frame at the crash start (world, orthonormal); pivot / axis: the steering axis (world);
        /// theta0: the bars' angle now. k0 / k1: the front / rear wheel nodes' global transforms (world, with any scale; basis
        /// z = the axle). vel: the bike's velocity (world), omega: its spin (world, rad/s); rf / rr: wheel radii.
        public void Begin(double[] pts, int[] grp, int[] wid, double[] mass, double[] radius, Xf body0, Vec3 pivot,
            Vec3 axis, double theta0, Xf k0, Xf k1, Vec3 vel, Vec3 omega, double rf, double rr, double dt)
        {
            _n = grp.Length;
            dt /= Math.Max(1, Substeps);   // (Verlet keeps the velocity as one substep's move)
            _h = dt;
            _x = new double[_n]; _y = new double[_n]; _z = new double[_n];
            _px = new double[_n]; _py = new double[_n]; _pz = new double[_n];
            _rx = new double[_n]; _ry = new double[_n]; _rz = new double[_n];
            _m = new double[_n]; _rad = new double[_n];
            _grp = (int[])grp.Clone(); _wid = (int[])wid.Clone(); _own = new int[_n];
            _gh = new double[_n]; _ghx = new double[_n]; _ghz = new double[_n];
            _nacc = new double[_n]; _vin = new double[_n];
            Xf inv = AffInv(body0);
            _piv = DV.From(inv * pivot);
            _axis = DV.From(inv.b * axis).Norm();
            _theta = _theta0 = _thLast = theta0;
            _K0 = Mul(inv, k0); _K1 = Mul(inv, k1);
            _axR[0] = rf; _axR[1] = rr;
            _off[0] = _off[1] = false;
            _qW[0] = _qW[1] = DQ.Identity;
            DQ unturn = DQ.AxisAngle(_axis, -theta0);
            DV c = default; double mt = 0;
            for (int i = 0; i < _n; i++)
            {
                _x[i] = pts[3 * i]; _y[i] = pts[3 * i + 1]; _z[i] = pts[3 * i + 2];
                _m[i] = mass[i]; _rad[i] = radius[i];
                DV r = DV.From(inv * new Vec3(pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]));
                if (_grp[i] == 1) r = _piv + unturn.Rot(r - _piv);   // steer points rest with the bars straight
                _rx[i] = r.X; _ry[i] = r.Y; _rz[i] = r.Z;
                _ghx[i] = double.NaN;   // (the first height read on first use)
                c += new DV(_x[i], _y[i], _z[i]) * _m[i]; mt += _m[i];
            }
            c /= Math.Max(mt, 1e-9);
            // velocity: Verlet keeps it as the step back to the last position
            DV v = DV.From(vel), w = DV.From(omega);
            for (int i = 0; i < _n; i++)
            {
                DV p = new DV(_x[i], _y[i], _z[i]);
                DV vi = v + w.Cross(p - c);
                _px[i] = _x[i] - vi.X * dt; _py[i] = _y[i] - vi.Y * dt; _pz[i] = _z[i] - vi.Z * dt;
            }
            _qB = DQ.From(body0.b.get_rotation_quaternion());
            _asleep = false; _still = 0;
            _MatchBike(false);
            _bodyPrev = _bodyCur = BodyNow();
            _thPrev = _thCur = _theta;
        }

        /// the ground: the drawn ground's height at (x, z) (null = no ground)
        public void SetGround(Func<double, double, double> top) => _top = top;

        /// trunks and other standing colliders near: x, z, r, top (top = 1e6 for a trunk) per collider
        public void SetColliders(double[] cyl) => _cyl = cyl != null ? (double[])cyl.Clone() : Array.Empty<double>();

        /// a hard knock (fence smash, the ragdoll...): wakes it and adds velocity to every point
        public void Kick(Vec3 dv)
        {
            double dt = _h;
            _asleep = false; _still = 0;
            for (int i = 0; i < _n; i++) { _px[i] -= dv.x * dt; _py[i] -= dv.y * dt; _pz[i] -= dv.z * dt; }
        }

        /// a shove that tips it: every point gets dv x (its height over the lowest point / h0), so the top goes and the
        /// tyres stay (the rider stepping off a slow bail pushes the bike away and lets it drop)
        public void Shove(Vec3 dv, double h0)
        {
            double dt = _h;
            _asleep = false; _still = 0;
            double lo = 1e9;
            for (int i = 0; i < _n; i++) lo = Math.Min(lo, _py[i]);
            for (int i = 0; i < _n; i++)
            {
                double k = Clamp((_py[i] - lo) / Math.Max(h0, 0.1), 0.0, 1.5);
                _px[i] -= dv.x * dt * k; _py[i] -= dv.y * dt * k; _pz[i] -= dv.z * dt * k;
            }
        }

        // =====================================================================================================================
        public void Step(double dtf)
        {
            int substeps = Substeps;
            _bodyPrev = _bodyCur; _thPrev = _thCur;
            _wPrev[0] = _wCur[0]; _wPrev[1] = _wCur[1];
            _hit[0] = _hit[1] = 0;
            if (_asleep || _n == 0) return;
            double h = dtf / Math.Max(1, substeps);
            double maxMove = 0;
            for (int s = 0; s < substeps; s++)
            {
                _Predict(h);
                for (int it = 0; it < Iters; it++)
                {
                    _Contacts(h, false);
                    _MatchBike(true);
                    for (int w = 0; w < 2; w++) if (_off[w]) _MatchWheel(w);
                }
                _Contacts(h, true);
                for (int i = 0; i < _n; i++)
                {
                    double dx = _x[i] - _px[i], dy = _y[i] - _py[i], dz = _z[i] - _pz[i];
                    maxMove = Math.Max(maxMove, dx * dx + dy * dy + dz * dz);
                }
            }
            _MatchBike(false);   // (the frame for drawing: points not moved)
            for (int w = 0; w < 2; w++) if (_off[w]) _MatchWheelFrame(w);
            _bodyCur = BodyNow(); _thCur = _theta;
            for (int w = 0; w < 2; w++) if (_off[w]) _wCur[w] = _WheelNode(w);
            // asleep: everything slower than ~0.12 m/s for 0.6 s
            double vmax = Math.Sqrt(maxMove) / h;
            _still = vmax < 0.12 ? _still + dtf : 0;
            if (_still > 0.6) _asleep = true;
        }

        private double _thLast, _h = 1.0 / 240.0;
        private void _Predict(double h)
        {
            _h = h;
            double damp = Math.Exp(-Drag * h);
            for (int i = 0; i < _n; i++)
            {
                double vx = (_x[i] - _px[i]) * damp, vy = (_y[i] - _py[i]) * damp, vz = (_z[i] - _pz[i]) * damp;
                _px[i] = _x[i]; _py[i] = _y[i]; _pz[i] = _z[i];
                _x[i] += vx; _y[i] += vy - G * h * h; _z[i] += vz;
                _vin[i] = (vy - G * h * h) / h;
                _nacc[i] = 0;
            }
            // headset + cable drag: the bars' swing since the last substep is carried on a little less
            double dth = _theta - _thLast;
            _thLast = _theta;
            if (SteerFric > 0 && Math.Abs(dth) > 1e-7)
            {
                DV axW = _qB.Rot(_axis), pivW = _cB + _qB.Rot(_piv - _c0B);
                DQ back = DQ.AxisAngle(axW, -dth * SteerFric);
                for (int i = 0; i < _n; i++)
                {
                    if (_grp[i] != 1 || _own[i] != 0) continue;
                    DV p = pivW + back.Rot(new DV(_x[i], _y[i], _z[i]) - pivW);
                    _x[i] = p.X; _y[i] = p.Y; _z[i] = p.Z;
                }
            }
        }

        private double _Ground(int i, double x, double z)
        {
            if (!double.IsNaN(_ghx[i]) && Math.Abs(x - _ghx[i]) < 0.015 && Math.Abs(z - _ghz[i]) < 0.015) return _gh[i];
            double g = _GroundAt(x, z);
            _gh[i] = g; _ghx[i] = x; _ghz[i] = z;
            return g;
        }

        private double _GroundAt(double x, double z) => _top != null ? _top(x, z) : -1e9;

        private double _gCb;
        private readonly double[] _gCw = new double[2];
        private void _Contacts(double h, bool last)
        {
            _gCb = _GroundAt(_cB.X, _cB.Z);
            for (int w = 0; w < 2; w++) if (_off[w]) _gCw[w] = _GroundAt(_cW[w].X, _cW[w].Z);
            int nc = _cyl.Length / 4;
            for (int i = 0; i < _n; i++)
            {
                // trunks: pushed out sideways (rocks / logs are domes in the ground already)
                for (int c = 0; c < nc; c++)
                {
                    double cx = _cyl[4 * c], cz = _cyl[4 * c + 1], cr = _cyl[4 * c + 2] + _rad[i], top = _cyl[4 * c + 3];
                    if (_y[i] > top) continue;
                    double dx = _x[i] - cx, dz = _z[i] - cz;
                    double d2 = dx * dx + dz * dz;
                    if (d2 >= cr * cr || d2 < 1e-10) continue;
                    double d = Math.Sqrt(d2);
                    double vin = ((_px[i] - _x[i]) * dx + (_pz[i] - _z[i]) * dz) / d / h;   // speed into the trunk
                    _x[i] = cx + dx / d * cr; _z[i] = cz + dz / d * cr;
                    if (_own[i] == 0 && _wid[i] >= 0) _hit[_wid[i]] = Math.Max(_hit[_wid[i]], vin);
                    if (last) { _px[i] = _x[i] - (_x[i] - _px[i]) * 0.3; _pz[i] = _z[i] - (_z[i] - _pz[i]) * 0.3; }
                }
                double g = _Ground(i, _x[i], _z[i]);
                double pen = g + _rad[i] - _y[i];
                if (pen > 0)
                {
                    // a wall (cliff, canyon side, a shed): ground standing more than WallRise above the ground under the
                    // body's own centre isn't climbed
                    double gC = _own[i] == 0 ? _gCb : _gCw[_own[i] - 1];
                    if (pen > WallRise && g > gC + WallRise)
                    {
                        double vin = Math.Sqrt((_x[i] - _px[i]) * (_x[i] - _px[i]) + (_z[i] - _pz[i]) * (_z[i] - _pz[i])) / h;
                        if (_own[i] == 0 && _wid[i] >= 0) _hit[_wid[i]] = Math.Max(_hit[_wid[i]], vin);
                        double g0 = _Ground(i, _px[i], _pz[i]);
                        if (g0 <= gC + WallRise || g0 + _rad[i] - _y[i] <= 0)
                        {
                            _x[i] = _px[i]; _z[i] = _pz[i];
                            g = g0; pen = g + _rad[i] - _y[i];
                            if (pen <= 0) continue;
                            if (pen > WallRise) continue;
                        }
                        else
                        {
                            DV cen = _own[i] == 0 ? _cB : _cW[_own[i] - 1];
                            double dx = cen.X - _x[i], dz = cen.Z - _z[i], dl = Math.Sqrt(dx * dx + dz * dz);
                            if (dl > 1e-4) { _x[i] += dx / dl * 0.03; _z[i] += dz / dl * 0.03; }
                            continue;
                        }
                    }
                    _y[i] += pen;
                    _nacc[i] += pen;
                    if (_own[i] == 0 && _wid[i] >= 0) _hit[_wid[i]] = Math.Max(_hit[_wid[i]], -_vin[i]);
                }
                if (!last || _nacc[i] <= 0) continue;
                // friction (Coulomb, position-based: what the normal push allows is taken off the sideways move)
                double ddx = _x[i] - _px[i], ddz = _z[i] - _pz[i];
                bool tyre = _wid[i] >= 0 && _rad[i] > 0.012;
                double budget = (tyre ? TyreMu : Mu) * _nacc[i];
                if (tyre)
                {
                    // along the tyre's rolling line it rolls (upright) .. slides (laid flat)
                    DV ax = _WheelAxis(_wid[i], _own[i]);
                    double up = Math.Sqrt(Math.Max(0, 1 - ax.Y * ax.Y));   // 1 = the wheel stands up
                    double rlx = -ax.Z, rlz = ax.X;                         // axle x up, flat
                    double rl = Math.Sqrt(rlx * rlx + rlz * rlz);
                    if (rl > 1e-6) { rlx /= rl; rlz /= rl; } else { rlx = 1; rlz = 0; }
                    double along = ddx * rlx + ddz * rlz;
                    double cx = ddx - along * rlx, cz = ddz - along * rlz;
                    double alongB = budget * (RollMu + (1 - RollMu) * Math.Pow(1 - up, 2));
                    along = _Shrink(along, alongB);
                    double cl = Math.Sqrt(cx * cx + cz * cz);
                    double k = cl > 1e-12 ? Math.Max(0, cl - budget) / cl : 0;
                    ddx = along * rlx + cx * k; ddz = along * rlz + cz * k;
                }
                else
                {
                    double dl = Math.Sqrt(ddx * ddx + ddz * ddz);
                    double k = dl > 1e-12 ? Math.Max(0, dl - budget) / dl : 0;
                    ddx *= k; ddz *= k;
                }
                _x[i] = _px[i] + ddx; _z[i] = _pz[i] + ddz;
                // a hard hit bounces a little (the next step's move up)
                if (_vin[i] < -2.5)
                {
                    double e = tyre ? TyreBounce : Bounce;
                    _py[i] = _y[i] + _vin[i] * e * h;
                }
            }
        }

        private static double _Shrink(double v, double b) => v > b ? v - b : (v < -b ? v + b : 0);

        private DV _WheelAxis(int w, int own)
        {
            // the wheel's axle: +z of its node in body coords (Begin's k0 / k1), turned with the steer for the front
            Xf Kw = w == 0 ? _K0 : _K1;
            DV a = DV.From(Kw.b.z).Norm();
            if (own == 0)
            {
                if (w == 0) a = DQ.AxisAngle(_axis, _theta - _theta0).Rot(a);
                return _qB.Rot(a);
            }
            DV aw = DV.From(_wd[w].b.z).Norm();       // the axle when it came off (world) ...
            DQ rw0 = DQ.From(_wr[w].b.get_rotation_quaternion());
            return (_qW[w] * rw0.Conj()).Rot(aw);     // ... turned as the wheel turned since
        }

        // ---- shape matching -----------------------------------------------------------------------------------------------
        /// the bike: all points it still owns; steer points turned by theta. move = pull the points onto the matched shape.
        private void _MatchBike(bool move)
        {
            DQ turn = DQ.AxisAngle(_axis, _theta);
            DV c = default, c0 = default; double mt = 0;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0) continue;
                DV r = _Rest(i, turn);
                c += new DV(_x[i], _y[i], _z[i]) * _m[i]; c0 += r * _m[i]; mt += _m[i];
            }
            if (mt <= 0) return;
            c /= mt; c0 /= mt;
            DM A = default;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0) continue;
                DV d = new DV(_x[i], _y[i], _z[i]) - c, r = _Rest(i, turn) - c0;
                A.Add(d * _m[i], r);
            }
            _qB = _Extract(A, _qB, 12);
            _cB = c; _c0B = c0;
            if (!move) return;
            // the bars: fitted to where the steer points were pushed (twist about the head tube in body coords)
            DQ qi = _qB.Conj();
            double num = 0, den = 0;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0 || _grp[i] != 1) continue;
                DV u = qi.Rot(new DV(_x[i], _y[i], _z[i]) - c) + c0 - _piv;
                DV e = _Rest(i, turn) - _piv;
                u -= _axis * u.Dot(_axis); e -= _axis * e.Dot(_axis);
                double w = e.Len2() * _m[i];
                if (w < 1e-8 || u.Len2() < 1e-8) continue;
                double ang = Math.Atan2(_axis.Dot(e.Cross(u)), e.Dot(u));
                num += ang * w; den += w;
            }
            if (den > 0) _theta = Clamp(_theta + num / den, -SteerLim, SteerLim);
            turn = DQ.AxisAngle(_axis, _theta);
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0) continue;
                DV g = c + _qB.Rot(_Rest(i, turn) - c0);
                _x[i] = g.X; _y[i] = g.Y; _z[i] = g.Z;
            }
        }

        private DV _Rest(int i, DQ turn)
        {
            DV r = new DV(_rx[i], _ry[i], _rz[i]);
            return _grp[i] == 1 ? _piv + turn.Rot(r - _piv) : r;
        }

        private void _MatchWheel(int w)
        {
            _MatchWheelFrame(w);
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != w + 1) continue;
                DV g = _cW[w] + _qW[w].Rot(new DV(_rx[i], _ry[i], _rz[i]) - _c0W[w]);
                _x[i] = g.X; _y[i] = g.Y; _z[i] = g.Z;
            }
        }

        private void _MatchWheelFrame(int w)
        {
            DV c = default, c0 = default; double mt = 0;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != w + 1) continue;
                c += new DV(_x[i], _y[i], _z[i]) * _m[i]; c0 += new DV(_rx[i], _ry[i], _rz[i]) * _m[i]; mt += _m[i];
            }
            if (mt <= 0) return;
            c /= mt; c0 /= mt;
            DM A = default;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != w + 1) continue;
                A.Add((new DV(_x[i], _y[i], _z[i]) - c) * _m[i], new DV(_rx[i], _ry[i], _rz[i]) - c0);
            }
            _qW[w] = _Extract(A, _qW[w], 12);
            _cW[w] = c; _c0W[w] = c0;
        }

        /// the rotation part of A (Mueller, Bender, Chentanez, Macklin 2016): robust, warm-started from q, works for flat
        /// point sets (a wheel's ring) too
        private static DQ _Extract(DM A, DQ q, int iters)
        {
            for (int it = 0; it < iters; it++)
            {
                DV r0 = q.Rot(new DV(1, 0, 0)), r1 = q.Rot(new DV(0, 1, 0)), r2 = q.Rot(new DV(0, 0, 1));
                DV om = r0.Cross(A.C0) + r1.Cross(A.C1) + r2.Cross(A.C2);
                double den = Math.Abs(r0.Dot(A.C0) + r1.Dot(A.C1) + r2.Dot(A.C2)) + 1e-9;
                om /= den;
                double w = om.Len();
                if (w < 1e-9) break;
                q = (DQ.AxisAngle(om / w, w) * q).Normalized();
            }
            return q;
        }

        // ---- wheels coming off --------------------------------------------------------------------------------------------
        /// the wheel comes off: its ring + axle fly on as their own body, kicked by kick (m/s) and spinning at spin (rad/s
        /// about its axle)
        public void Detach(int w, Vec3 kick, double spin)
        {
            double dt = _h;
            if (_off[w]) return;
            _asleep = false; _still = 0;
            Xf node = _WheelNodeAttached(w);
            _wd[w] = node;
            _wr[w] = new Xf(node.b.orthonormalized(), node.o);
            Xf ri = AffInv(_wr[w]);
            DV ax = DV.From(node.b.z).Norm();
            DV centre = DV.From(node.o);
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0 || _wid[i] != w) continue;
                _own[i] = w + 1;
                Vec3 r = ri * new Vec3(_x[i], _y[i], _z[i]);
                _rx[i] = r.x; _ry[i] = r.y; _rz[i] = r.z;
                DV p = new DV(_x[i], _y[i], _z[i]);
                DV vs = (ax * spin).Cross(p - centre);
                _px[i] -= (kick.x + vs.X) * dt; _py[i] -= (kick.y + vs.Y) * dt; _pz[i] -= (kick.z + vs.Z) * dt;
            }
            _qW[w] = DQ.From(_wr[w].b.get_rotation_quaternion());
            _off[w] = true;
            _MatchWheelFrame(w);
            _wPrev[w] = _wCur[w] = _WheelNode(w);
        }

        private Xf _WheelNodeAttached(int w)
        {
            Xf Kw = w == 0 ? _K0 : _K1;
            Xf body = BodyNow();
            if (w == 0)
            {
                DQ t = DQ.AxisAngle(_axis, _theta - _theta0);
                Basis tb = t.ToBasis();
                Vec3 p = _piv.ToV();
                Xf turn = new Xf(tb, p - tb * p);
                Kw = Mul(turn, Kw);
            }
            return Mul(body, Kw);
        }

        private Xf _WheelNode(int w)
        {
            // the wheel body: rest = _wr's frame; now rotated qW about its centre
            Basis b = _qW[w].ToBasis();
            Vec3 c = _cW[w].ToV(), c0 = _c0W[w].ToV();
            Xf tw = new Xf(b, c - b * c0);
            return Mul(Mul(tw, AffInv(_wr[w])), _wd[w]);
        }

        // ---- the rider's ragdoll against the bike -------------------------------------------------------------------------
        // the bike's tubes as capsules between its points (chainstay, down / top / seat tube, head tube, fork, bars) and each
        // wheel as a disc. A body part is pushed off the bike and the bike's points take the opposite share. A part only
        // collides once it has been clear of the bike (at the crash the rider is wrapped round it and untangles first).
        private int[] _cap = Array.Empty<int>();
        private double[] _capR = Array.Empty<double>();
        private readonly int[] _discAxle = { -1, -1 };
        private bool[] _clear = Array.Empty<bool>();
        public double BodyShare = 0.75;   // share of a push the body part takes (rider part ~5 kg vs the bike ~17 kg at that spot)
        public double LastPush;           // m pushed apart in the last CollideBody
        public int Tangled { get { int k = 0; foreach (bool c in _clear) if (!c) k++; return k; } }

        public void SetCapsules(int[] pairs, double[] radius, int axleFront, int axleRear)
        {
            _cap = (int[])pairs.Clone();
            _capR = (double[])radius.Clone();
            _discAxle[0] = axleFront; _discAxle[1] = axleRear;
            _clear = Array.Empty<bool>();
        }

        /// p, q: the ragdoll's points now and a substep ago (its Verlet velocity = p - q), rad: each part's radius. Returns p
        /// then q (2n points). A push moves both (no velocity from it) and takes out only the part's speed into the bike
        public Vec3[] CollideBody(Vec3[] p, Vec3[] q, double[] rad)
        {
            var o = new Vec3[p.Length * 2];
            if (_n == 0 || _cap.Length == 0) { p.CopyTo(o, 0); q.CopyTo(o, p.Length); return o; }
            if (_clear.Length != p.Length)
            {
                var c2 = new bool[p.Length];
                Array.Copy(_clear, c2, Math.Min(_clear.Length, c2.Length));
                _clear = c2;
            }
            double moved = 0;
            int nc = _capR.Length;
            for (int i = 0; i < p.Length; i++)
            {
                DV P = DV.From(p[i]), Q = DV.From(q[i]);
                double ri = rad != null && i < rad.Length ? rad[i] : 0.05;
                double worst = -1e9;
                for (int c = 0; c < nc; c++)
                {
                    int a = _cap[2 * c], b = _cap[2 * c + 1];
                    DV A = new DV(_x[a], _y[a], _z[a]), B = new DV(_x[b], _y[b], _z[b]);
                    DV ab = B - A;
                    double l2 = ab.Len2();
                    double t = l2 > 1e-9 ? Clamp((P - A).Dot(ab) / l2, 0, 1) : 0;
                    DV C = A + ab * t;
                    DV d = P - C;
                    double dl = d.Len();
                    double pen = _capR[c] + ri - dl;
                    worst = Math.Max(worst, pen);
                    if (!_clear[i] || pen <= 0 || dl < 1e-6) continue;
                    DV nrm = d / dl;
                    _Push(ref P, ref Q, nrm, pen * BodyShare);
                    DV back = nrm * (-pen * (1 - BodyShare));
                    _Shift(a, back * (1 - t)); _Shift(b, back * t);
                    moved += pen;
                }
                for (int w = 0; w < 2; w++)
                {
                    int ai = _discAxle[w];
                    if (ai < 0) continue;
                    DV ax = _WheelAxis(w, _own[ai]);
                    DV rel = P - new DV(_x[ai], _y[ai], _z[ai]);
                    double along = rel.Dot(ax);
                    DV radial = rel - ax * along;
                    if (radial.Len() > _axR[w]) continue;
                    double pen = 0.03 + ri - Math.Abs(along);
                    worst = Math.Max(worst, pen);
                    if (!_clear[i] || pen <= 0) continue;
                    DV nrm = ax * (along >= 0 ? 1 : -1);
                    _Push(ref P, ref Q, nrm, pen * BodyShare);
                    DV back = nrm * (-pen * (1 - BodyShare));
                    for (int k = 0; k < _n; k++) if (_wid[k] == w) _Shift(k, back);
                    moved += pen;
                }
                if (!_clear[i] && worst < -0.02) _clear[i] = true;
                o[i] = P.ToV(); o[p.Length + i] = Q.ToV();
            }
            LastPush = moved;
            return o;
        }

        // a body point pushed out along n by d: moved without speed from it, its speed into the surface taken out
        private static void _Push(ref DV P, ref DV Q, DV n, double d)
        {
            P += n * d; Q += n * d;
            double vn = (P - Q).Dot(n);
            if (vn < 0) Q += n * vn;
        }
        // a bike point moved without speed from it
        private void _Shift(int k, DV d) { _x[k] += d.X; _y[k] += d.Y; _z[k] += d.Z; _px[k] += d.X; _py[k] += d.Y; _pz[k] += d.Z; }

        // ---- hands on the bars, feet on the pedals for the first moments ("stay with the bike") ---------------------------
        // each hold is a rope of length 0 between a body point and a bike point; it lets go when stretched past its break
        // distance (yanked away) or after its time (the grip slips)
        private int[] _hB = Array.Empty<int>(), _hR = Array.Empty<int>();
        private double[] _hBreak = Array.Empty<double>(), _hT = Array.Empty<double>();
        private bool[] _hOn = Array.Empty<bool>();
        private double _hAge;
        public double HoldPull = 0.5;   // share of the gap closed per step (body side only)
        public void SetHolds(int[] bikeIdx, int[] bodyIdx, double[] breakDist, double[] maxT)
        {
            _hB = (int[])bikeIdx.Clone(); _hR = (int[])bodyIdx.Clone();
            _hBreak = (double[])breakDist.Clone(); _hT = (double[])maxT.Clone(); _hOn = new bool[bikeIdx.Length];
            for (int i = 0; i < _hB.Length; i++) _hOn[i] = true;
            _hAge = 0;
        }
        public int HoldsOn { get { int k = 0; foreach (bool b in _hOn) if (b) k++; return k; } }
        public bool HoldOn(int i) => i < _hOn.Length && _hOn[i];
        public void Release() { for (int i = 0; i < _hOn.Length; i++) _hOn[i] = false; }
        /// p, q as CollideBody (returns p then q); hRag = the ragdoll's substep. The held part moves onto the bike point by
        /// HoldPull of the gap (with no speed from that) and its velocity eases to the bike point's
        public Vec3[] HoldBody(Vec3[] p, Vec3[] q, double dt, double hRag)
        {
            _hAge += dt;
            var o = new Vec3[p.Length * 2];
            p.CopyTo(o, 0); q.CopyTo(o, p.Length);
            for (int i = 0; i < _hB.Length; i++)
            {
                if (!_hOn[i]) continue;
                int b = _hB[i], r = _hR[i];
                if (r >= p.Length || _own[b] != 0) { _hOn[i] = false; continue; }
                DV B = new DV(_x[b], _y[b], _z[b]), P = DV.From(p[r]), Q = DV.From(q[r]);
                DV d = B - P;
                double dl = d.Len();
                if (_hAge > _hT[i] || dl > _hBreak[i]) { _hOn[i] = false; continue; }
                // only the bike pulls the body (softly)
                P += d * HoldPull; Q += d * HoldPull;
                DV vb = new DV(_x[b] - _px[b], _y[b] - _py[b], _z[b] - _pz[b]) * (hRag / _h);   // the bike point's move per ragdoll substep
                DV vp = P - Q;
                Q = P - (vp + (vb - vp) * 0.5);
                o[r] = P.ToV(); o[p.Length + r] = Q.ToV();
            }
            return o;
        }

        // ---- results ------------------------------------------------------------------------------------------------------
        /// body coords -> world now (maps the model's frame at the crash start)
        public Xf BodyNow()
        {
            Basis b = _qB.ToBasis();
            return new Xf(b, _cB.ToV() - b * _c0B.ToV());
        }

        public Xf BodyAt(double a) => _Lerp(_bodyPrev, _bodyCur, a);
        public double ThetaAt(double a) => _thPrev + (_thCur - _thPrev) * a;
        /// a wheel that came off (WheelOff(w)): its node's world transform, interpolated
        public Xf WheelAt(int w, double a) => _Lerp(_wPrev[w], _wCur[w], a);

        private static Xf _Lerp(Xf p, Xf c, double a)
        {
            Quat qa = p.b.get_rotation_quaternion(), qb = c.b.get_rotation_quaternion();
            Vec3 sa = Scale(p.b), sb = Scale(c.b);
            Vec3 s = sa.lerp(sb, a);
            Basis r = Basis.from_quat(qa.slerp(qb, a));
            // (Godot Basis.Scaled: scaled in the parent's frame = each column's components times s)
            Basis b = new Basis(r.x * s, r.y * s, r.z * s);
            return new Xf(b, p.o.lerp(c.o, a));
        }

        /// the bike's centre of mass and its velocity (world)
        public Vec3 Centre() => _cB.ToV();
        public Vec3 Velocity()
        {
            DV v = default; double mt = 0;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0) continue;
                v += new DV(_x[i] - _px[i], _y[i] - _py[i], _z[i] - _pz[i]) * _m[i]; mt += _m[i];
            }
            return mt > 0 ? (v / mt / _h).ToV() : Vec3.ZERO;
        }

        /// a wheel's spin while it is on the bike (rad/s): its ring's speed along its rolling line on the ground / radius
        public double AxleRoll(int w)
        {
            DV ax = _WheelAxis(w, 0);
            DV roll = ax.Cross(new DV(0, 1, 0));
            double rl = roll.Len();
            if (rl < 1e-4) return 0;
            roll /= rl;
            DV v = default; double mt = 0;
            for (int i = 0; i < _n; i++)
            {
                if (_own[i] != 0 || _wid[i] != w) continue;
                v += new DV(_x[i] - _px[i], _y[i] - _py[i], _z[i] - _pz[i]); mt += 1;
            }
            if (mt <= 0) return 0;
            return v.Dot(roll) / mt / _h / Math.Max(0.1, _axR[w]);
        }

        /// world positions of every point: x, y, z, owner * 10 + group per point
        public double[] Points()
        {
            var o = new double[_n * 4];
            for (int i = 0; i < _n; i++) { o[4 * i] = _x[i]; o[4 * i + 1] = _y[i]; o[4 * i + 2] = _z[i]; o[4 * i + 3] = _own[i] * 10 + _grp[i]; }
            return o;
        }

        /// a point's world position (the holds / capsule points CrashBikeStart returns)
        public Vec3 PointAt(int i) => new Vec3(_x[i], _y[i], _z[i]);

        /// the deepest point under the drawn ground (m, > 0 = inside): tests
        public double Deepest()
        {
            double worst = -1e9;
            for (int i = 0; i < _n; i++) worst = Math.Max(worst, _GroundAt(_x[i], _z[i]) + _rad[i] - _y[i]);
            return worst;
        }

        // =====================================================================================================================
        /// support points of a mesh's vertices along 26 directions (the bike's point cloud is built from these;
        /// unity/Tools/glb_extras.py does the same offline: rig.hull.*)
        public static Vec3[] MeshSupport(Vec3[] verts)
        {
            if (verts.Length == 0) return Array.Empty<Vec3>();
            var dirs = Dirs26();
            var best = new double[26];
            var bi = new int[26];
            for (int k = 0; k < 26; k++) best[k] = double.NegativeInfinity;
            for (int j = 0; j < verts.Length; j++)
            {
                Vec3 v = verts[j];
                for (int k = 0; k < 26; k++)
                {
                    double d = v.x * dirs[k].x + v.y * dirs[k].y + v.z * dirs[k].z;
                    if (d > best[k]) { best[k] = d; bi[k] = j; }
                }
            }
            var outp = new List<Vec3>();
            for (int k = 0; k < 26; k++)
            {
                Vec3 p = verts[bi[k]];
                bool dup = false;
                foreach (var q in outp) if ((q - p).length_squared() < 1e-6) { dup = true; break; }
                if (!dup) outp.Add(p);
            }
            return outp.ToArray();
        }

        /// the points (world) of a group reduced to its own support points along 26 directions of the frame basis, kept
        /// apart by at least minD
        public static Vec3[] Reduce(Vec3[] pts, Basis frame, double minD)
        {
            if (pts.Length == 0) return Array.Empty<Vec3>();
            var dirs = Dirs26();
            var outp = new List<Vec3>();
            for (int k = 0; k < 26; k++)
            {
                Vec3 d = (frame * dirs[k]).normalized();
                int b = 0; double bd = double.NegativeInfinity;
                for (int j = 0; j < pts.Length; j++)
                {
                    double v = pts[j].dot(d);
                    if (v > bd) { bd = v; b = j; }
                }
                bool dup = false;
                foreach (var q in outp) if ((q - pts[b]).length() < minD) { dup = true; break; }
                if (!dup) outp.Add(pts[b]);
            }
            return outp.ToArray();
        }

        private static Vec3[] _dirs;
        public static Vec3[] Dirs26()
        {
            if (_dirs != null) return _dirs;
            var l = new List<Vec3>();
            for (int a = -1; a <= 1; a++) for (int b = -1; b <= 1; b++) for (int c = -1; c <= 1; c++)
                if (a != 0 || b != 0 || c != 0) l.Add(new Vec3(a, b, c).normalized());
            _dirs = l.ToArray();
            return _dirs;
        }

        // ---- transforms (Godot Transform3D semantics on Rider's Xf) ---------------------------------------------------------
        public static Xf Mul(Xf a, Xf b) => new Xf(a.b * b.b, a.b * b.o + a.o);
        public static Xf AffInv(Xf t) { Basis bi = t.b.inverse(); return new Xf(bi, -(bi * t.o)); }
        /// Godot Basis.Scale: each column's length, signed by the determinant
        public static Vec3 Scale(Basis b)
        {
            double s = b.determinant() < 0 ? -1.0 : 1.0;
            return new Vec3(b.x.length(), b.y.length(), b.z.length()) * s;
        }
        private static double Clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

        // ---- small double maths -------------------------------------------------------------------------------------------
        private struct DV
        {
            public double X, Y, Z;
            public DV(double x, double y, double z) { X = x; Y = y; Z = z; }
            public static DV From(Vec3 v) => new DV(v.x, v.y, v.z);
            public Vec3 ToV() => new Vec3(X, Y, Z);
            public static DV operator +(DV a, DV b) => new DV(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
            public static DV operator -(DV a, DV b) => new DV(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
            public static DV operator *(DV a, double k) => new DV(a.X * k, a.Y * k, a.Z * k);
            public static DV operator /(DV a, double k) => new DV(a.X / k, a.Y / k, a.Z / k);
            public double Dot(DV b) => X * b.X + Y * b.Y + Z * b.Z;
            public DV Cross(DV b) => new DV(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X);
            public double Len2() => X * X + Y * Y + Z * Z;
            public double Len() => Math.Sqrt(Len2());
            public DV Norm() { double l = Len(); return l > 1e-12 ? this / l : new DV(1, 0, 0); }
        }

        private struct DM   // 3x3 by columns
        {
            public DV C0, C1, C2;
            public void Add(DV d, DV r) { C0 += d * r.X; C1 += d * r.Y; C2 += d * r.Z; }
        }

        private struct DQ
        {
            public double W, X, Y, Z;
            public DQ(double w, double x, double y, double z) { W = w; X = x; Y = y; Z = z; }
            public static readonly DQ Identity = new DQ(1, 0, 0, 0);
            public static DQ From(Quat q) => new DQ(q.w, q.x, q.y, q.z).Normalized();
            public Basis ToBasis() => Basis.from_quat(new Quat(X, Y, Z, W).normalized());
            public static DQ AxisAngle(DV a, double ang)
            {
                double s = Math.Sin(ang * 0.5);
                return new DQ(Math.Cos(ang * 0.5), a.X * s, a.Y * s, a.Z * s);
            }
            public static DQ operator *(DQ a, DQ b) => new DQ(
                a.W * b.W - a.X * b.X - a.Y * b.Y - a.Z * b.Z,
                a.W * b.X + a.X * b.W + a.Y * b.Z - a.Z * b.Y,
                a.W * b.Y - a.X * b.Z + a.Y * b.W + a.Z * b.X,
                a.W * b.Z + a.X * b.Y - a.Y * b.X + a.Z * b.W);
            public DQ Conj() => new DQ(W, -X, -Y, -Z);
            public DQ Normalized()
            {
                double l = Math.Sqrt(W * W + X * X + Y * Y + Z * Z);
                return l > 1e-12 ? new DQ(W / l, X / l, Y / l, Z / l) : Identity;
            }
            public DV Rot(DV v)
            {
                // v + 2 w (q x v) + 2 q x (q x v)
                DV q = new DV(X, Y, Z);
                DV t = q.Cross(v) * 2.0;
                return v + t * W + q.Cross(t);
            }
        }
    }
}
