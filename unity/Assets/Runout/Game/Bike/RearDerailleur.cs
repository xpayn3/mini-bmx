using System;

namespace Runout.Game
{
    /// The rear derailleur + chain as a mechanic and physics see them: a port of the bike HDA's own solve
    /// (houdini bike_skeleton.hda, "rear derailleur" / "THE CAGE AND THE CHAIN, REACTING"), for the SRAM Force eTap AXS
    /// model whose kinematics the HDA measured (tools/export_rd_sram.py -> rd_sram.extras.txt). Nothing is baked per gear:
    /// any chainring / cassette (modular bikes) is solved the same way.
    ///   setup (a mechanic building the bike, at rest):
    ///     B-tension   the body is turned on the B-bolt ONCE so the top pulley holds `gap` to the BIGGEST cog
    ///     chain       cut once: big-big with the cage fully extended (cageMax), even links, + chainSlack
    ///   every frame (the rear end moving with the suspension, the gear in use):
    ///     parallelogram  both links swing until the top pulley is in the selected cog's plane (slant pins, 47 deg:
    ///                    the knuckle translates, carrying the pulley down as it moves out)
    ///     cage           turns on the top pulley's axle until the FIXED chain closes (chain growth as the
    ///                    suspension compresses swings it forward / back)
    ///     dynamics       the cage is a sprung arm with mass and a clutch; the two free runs are strings with the
    ///                    chain's mass at the cage spring's tension: bumps throw the axle, the runs bow, the cage
    ///                    lets chain out, coasting the top run slaps the chainstay
    /// Plain C#, no engine types: all positions in the bike's model frame (Godot axes: +x forward, +y up, +z the drive
    /// side), metres.
    public sealed class RearDerailleur
    {
        public struct V { public double x, y, z; public V(double x, double y, double z) { this.x = x; this.y = y; this.z = z; }
            public static V operator +(V a, V b) => new V(a.x + b.x, a.y + b.y, a.z + b.z);
            public static V operator -(V a, V b) => new V(a.x - b.x, a.y - b.y, a.z - b.z);
            public static V operator *(V a, double s) => new V(a.x * s, a.y * s, a.z * s);
            public double Len => Math.Sqrt(x * x + y * y + z * z);
            public double Len2D => Math.Sqrt(x * x + y * y); }

        public const double PITCH = 0.0127;
        // ---- the model (SRAM Force eTap AXS), model frame, m
        public V axis = new V(0, -0.731188, 0.682176), pinTop = new V(-0.01813, -0.05431, 0.02588),
                 pinBot = new V(-0.02254, -0.06232, 0.00954), link = new V(0.04359, 0.01543, 0.0057), u0 = new V(0.03507, -0.0519, -0.0263);
        public double cageLen = 0.07001, cageRest = 252.17 * Math.PI / 180.0;
        public int jockeyTeeth = 12;
        // ---- this frame's hanger (the B-bolt in the seatstay's frame) and setup
        public V originSeatstay = new V(-0.033882, -0.01641, 0.0775);
        public double gap = 0.011, cageMin = 190.0, cageMax = 320.0, derailAng = 320.0;
        public int chainSlack = 2;
        public double cogZ0 = 0.06322, ringZ = 0.052, stayGap = 0.014;
        // ---- dynamics (the HDA's numbers: chain 0.174 kg/m, cage ~65 g, spring tension, clutch)
        public bool dynamics = true;
        public double cageTension = 25.0, clutch = 1.0, cageMass = 0.065, chainMass = 0.174;

        // ---- the build
        public double[] cogs = { 16 };
        public double ringTeeth = 34;
        public double JockeyR => PitchR(jockeyTeeth);
        public double RingR => PitchR(ringTeeth);
        public static double PitchR(double teeth) => PITCH / (2.0 * Math.Sin(Math.PI / Math.Max(teeth, 6.0)));

        // ---- results
        public double beta;            // B-knuckle turn (rad), set at setup
        public int links;              // the chain, cut once
        public double TargetLen => links * PITCH;
        public double phi;             // parallelogram angle now
        public double cage;            // cage angle now (rad, bike frame, top -> bottom pulley), incl. the dynamics
        public double cageTaut;        // ... the solve alone
        public V upper, lower;         // pulley centres now (bike frame; z = the mech's plane)
        public double[] senses = { -1, -1, -1, 1 };   // wrap sense per pulley: ring, cog, top, bottom
        public double bowTop, bowLow;  // the free runs' bows now, m, + = up
        public double tension;         // N
        public double cageSwing => _dphi;
        public bool valid;

        /// the cog plane of cog i of n (small -> big), bike frame z: the hub's smallest-cog plane, then inboard at the
        /// standard spacing for that many speeds (7-11 speed = the 11-speed 3.74 mm the HDA uses, 12: 3.6, 13: 3.4)
        public double CogZ(int i, int n)
        {
            double p = n <= 11 ? 0.00374 : n == 12 ? 0.0036 : 0.0034;
            return cogZ0 - i * p;
        }

        // ---------------------------------------------------------------- the model's kinematics
        static V Rot(V v, V ax, double a)   // Rodrigues
        {
            double c = Math.Cos(a), s = Math.Sin(a);
            double d = ax.x * v.x + ax.y * v.y + ax.z * v.z;
            V cr = new V(ax.y * v.z - ax.z * v.y, ax.z * v.x - ax.x * v.z, ax.x * v.y - ax.y * v.x);
            return v * c + cr * s + ax * (d * (1 - c));
        }
        public static V RotZ(V v, double a) { double c = Math.Cos(a), s = Math.Sin(a); return new V(v.x * c - v.y * s, v.x * s + v.y * c, v.z); }
        /// how far the P-knuckle moves when both links swing by phi about their pins
        public V Disp(double ph) => Rot(link, axis, ph) - link;
        /// the link angle that puts the top jockey at model z = zm (monotonic inside +-68 deg; held to +-60)
        public double PhiFor(double zm)
        {
            double lo = -60 * Math.PI / 180, hi = 60 * Math.PI / 180;
            for (int i = 0; i < 40; i++) { double m = 0.5 * (lo + hi); if (u0.z + Disp(m).z < zm) lo = m; else hi = m; }
            return 0.5 * (lo + hi);
        }

        /// the guide pulley on the two circles |g - axle| = dj (b-tension) and |g - bk| = blen (the rigid body); the
        /// forward of the two intersections (the knee bends forward only); pref when they miss
        static V GuideSolve(V axle, V bk, double dj, double blen, V pref, double z)
        {
            V o = new V(pref.x, pref.y, z);
            double dx = bk.x - axle.x, dy = bk.y - axle.y, d = Math.Sqrt(dx * dx + dy * dy);
            if (d < 1e-7 || d > dj + blen || d < Math.Abs(dj - blen)) return o;
            double a = (dj * dj - blen * blen + d * d) / (2.0 * d), h2 = dj * dj - a * a;
            if (h2 <= 0) return o;
            double h = Math.Sqrt(h2), mx = axle.x + a * dx / d, my = axle.y + a * dy / d, px = -dy / d, py = dx / d;
            V s1 = new V(mx + h * px, my + h * py, z), s2 = new V(mx - h * px, my - h * py, z);
            return s1.x >= s2.x ? s1 : s2;
        }

        // ---------------------------------------------------------------- belts (the HDA's router)
        readonly double[] _aout = new double[4];
        /// a taut belt's length round centres pc with signed radii (sign = wrap sense)
        public double BeltLen(V[] pc, double[] ps)
        {
            int n = ps.Length;
            for (int i = 0; i < n; i++)
            {
                V c0 = pc[i], c1 = pc[(i + 1) % n];
                double ex = c1.x - c0.x, ey = c1.y - c0.y, d = Math.Max(Math.Sqrt(ex * ex + ey * ey), 1e-7);
                _aout[i] = Math.Atan2(ey, ex) + Math.Acos(Clamp((ps[i] - ps[(i + 1) % n]) / d, -1, 1));
            }
            double tot = 0;
            for (int i = 0; i < n; i++)
            {
                double sw = Sweep(_aout[i] - _aout[(i - 1 + n) % n], ps[i]);
                tot += Math.Abs(sw) * Math.Abs(ps[i]);
                int j = (i + 1) % n;
                double x1 = pc[i].x + ps[i] * Math.Cos(_aout[i]), y1 = pc[i].y + ps[i] * Math.Sin(_aout[i]);
                double x2 = pc[j].x + ps[j] * Math.Cos(_aout[i]), y2 = pc[j].y + ps[j] * Math.Sin(_aout[i]);
                tot += Math.Sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) + (pc[j].z - pc[i].z) * (pc[j].z - pc[i].z));
            }
            return tot;
        }
        static double Sweep(double sw, double r)
        {
            const double TAU = 2 * Math.PI;
            if (r > 0) { while (sw > 0) sw -= TAU; while (sw < -TAU) sw += TAU; }
            else { while (sw < 0) sw += TAU; while (sw > TAU) sw -= TAU; }
            return sw;
        }
        static double Clamp(double v, double a, double b) => v < a ? a : v > b ? b : v;

        static bool SegsCross(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy)
        {
            double d1 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax), d2 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
            double d3 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx), d4 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
            return d1 * d2 < -1e-15 && d3 * d4 < -1e-15;
        }
        static double SegPt(double ax, double ay, double bx, double by, double px, double py)
        {
            double ex = bx - ax, ey = by - ay, L2 = ex * ex + ey * ey;
            double t = L2 < 1e-18 ? 0 : Clamp(((px - ax) * ex + (py - ay) * ey) / L2, 0, 1);
            double qx = ax + t * ex - px, qy = ay + t * ey - py;
            return Math.Sqrt(qx * qx + qy * qy);
        }
        readonly double[] _sx = new double[4], _sy = new double[4], _ex = new double[4], _ey = new double[4];
        /// is this a chain path that can exist (tangents exist, turning number +-1, no crossings, no run through a
        /// pulley)? -1 if not, else the wrap on the ring + cog
        double BeltValid(V[] pc, double[] ps)
        {
            int n = ps.Length;
            for (int i = 0; i < n; i++)
            {
                V c0 = pc[i], c1 = pc[(i + 1) % n];
                double ex = c1.x - c0.x, ey = c1.y - c0.y, d = Math.Sqrt(ex * ex + ey * ey);
                if (d < 1e-7) return -1;
                double v = (ps[i] - ps[(i + 1) % n]) / d;
                if (Math.Abs(v) > 1) return -1;
                _aout[i] = Math.Atan2(ey, ex) + Math.Acos(v);
            }
            double sum = 0, driven = 0;
            for (int i = 0; i < n; i++)
            {
                double sw = Sweep(_aout[i] - _aout[(i - 1 + n) % n], ps[i]);
                sum += sw; if (i < 2) driven += Math.Abs(sw);
            }
            if (Math.Abs(Math.Abs(sum) - 2 * Math.PI) > 0.02) return -1;
            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n;
                _sx[i] = pc[i].x + ps[i] * Math.Cos(_aout[i]); _sy[i] = pc[i].y + ps[i] * Math.Sin(_aout[i]);
                _ex[i] = pc[j].x + ps[j] * Math.Cos(_aout[i]); _ey[i] = pc[j].y + ps[j] * Math.Sin(_aout[i]);
            }
            for (int i = 0; i < n; i++)
                for (int k = i + 1; k < n; k++)
                    if (SegsCross(_sx[i], _sy[i], _ex[i], _ey[i], _sx[k], _sy[k], _ex[k], _ey[k])) return -1;
            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n;
                for (int k = 0; k < n; k++)
                {
                    if (k == i || k == j) continue;
                    if (SegPt(_sx[i], _sy[i], _ex[i], _ey[i], pc[k].x, pc[k].y) < Math.Abs(ps[k]) - 0.0005) return -1;
                }
            }
            return driven;
        }
        readonly double[] _rs = new double[4], _try = new double[4];
        /// which way the chain wraps each pulley (the S through the cage first): fills sgn, -1 if no path exists
        public double RouteSolve(double[] sgn, V[] pc, double[] radii)
        {
            double best = -1;
            for (int pass = 0; pass < 3; pass++)
            {
                for (int t = 0; t < 16; t++)
                {
                    for (int i = 0; i < 4; i++) _try[i] = ((t >> i) & 1) != 0 ? 1 : -1;
                    if (pass < 2 && _try[0] != _try[1]) continue;
                    if (pass < 1 && _try[2] == _try[3]) continue;
                    for (int i = 0; i < 4; i++) _rs[i] = _try[i] * radii[i];
                    double sc = BeltValid(pc, _rs);
                    if (sc > best) { best = sc; for (int i = 0; i < 4; i++) sgn[i] = _try[i]; }
                }
                if (best >= 0) break;
            }
            return best;
        }

        // ---------------------------------------------------------------- setup (the mechanic)
        readonly V[] _pc = new V[4];
        readonly double[] _rad = new double[4], _sg = new double[4], _ps = new double[4];

        /// B-tension + chain length for this build, at rest: axle / bb / B-bolt in the bike frame (rest), seatstay turn 0
        public void Setup(double[] cogTeeth, double ring, V axle, V bb, V bknuc)
        {
            cogs = cogTeeth; ringTeeth = ring;
            int n = cogs.Length;
            double rBig = PitchR(cogs[n - 1]);
            double dj = rBig + gap + JockeyR;
            double zbig = CogZ(n - 1, n);
            V umb0 = u0 + Disp(PhiFor(zbig - originSeatstay.z));
            double dra = derailAng * Math.PI / 180;
            V pref = new V(axle.x + Math.Cos(dra) * dj, axle.y + Math.Sin(dra) * dj, zbig);
            V ub = GuideSolve(axle, bknuc, dj, umb0.Len2D, pref, zbig);
            beta = Math.Atan2(ub.y - bknuc.y, ub.x - bknuc.x) - Math.Atan2(umb0.y, umb0.x);
            // the chain: big-big, cage extended
            double cmax = cageMax * Math.PI / 180;
            V lo = new V(ub.x + Math.Cos(cmax) * cageLen, ub.y + Math.Sin(cmax) * cageLen, zbig);
            _pc[0] = new V(bb.x, bb.y, ringZ); _pc[1] = new V(axle.x, axle.y, zbig); _pc[2] = ub; _pc[3] = lo;
            _rad[0] = RingR; _rad[1] = rBig; _rad[2] = JockeyR; _rad[3] = JockeyR;
            if (RouteSolve(_sg, _pc, _rad) >= 0) for (int i = 0; i < 4; i++) _ps[i] = _sg[i] * _rad[i];
            else { _ps[0] = -_rad[0]; _ps[1] = -_rad[1]; _ps[2] = -_rad[2]; _ps[3] = _rad[3]; }
            double target = BeltLen(_pc, _ps);
            int t = (int)(target / PITCH) + 1;
            if (t % 2 == 1) t++;
            links = t + chainSlack;
            cageTaut = cage = cageRest;
            _dynInit = false;
        }

        // ---------------------------------------------------------------- every frame
        public V bknucNow;
        /// the mech now: axle / bb / the B-bolt (the hanger on the seatstay) and the seatstay's turn (rad, about z), the
        /// lateral plane the cable has the mech in (zMech), the cog the chain is on (radius) and its plane (zChain)
        public void Solve(V axle, V bb, V bknuc, double seatTurn, double zMech, double cogR, double zChain)
        {
            // never take in (or leave behind) a non-finite number: keep the last good pose instead
            if (!Finite(axle.x + axle.y + bb.x + bb.y + bknuc.x + bknuc.y + seatTurn + zMech + cogR + zChain) || cogR <= 0) { valid = false; return; }
            if (!Finite(cageTaut)) cageTaut = cageRest;
            bknucNow = bknuc;
            phi = PhiFor(zMech - originSeatstay.z);
            V u = RotZ(u0 + Disp(phi), beta + seatTurn);
            upper = new V(bknuc.x + u.x, bknuc.y + u.y, zMech);
            _pc[0] = new V(bb.x, bb.y, ringZ); _pc[1] = new V(axle.x, axle.y, zChain); _pc[2] = upper;
            _rad[0] = RingR; _rad[1] = cogR; _rad[2] = JockeyR; _rad[3] = JockeyR;
            // the cage angle that closes the fixed chain: Newton from last frame's angle on the same routing; the
            // HDA's full scan when that fails (first frame, a routing change)
            // (a full scan is ~100x a Newton step: at most every ~0.25 s, else hold the last angle this frame)
            valid = NewtonCage(zMech);
            if (!valid && _scanWait <= 0) { valid = ScanCage(zMech); _scanWait = 30; }
            if (_scanWait > 0) _scanWait--;
            if (!Finite(cageTaut)) { cageTaut = cageRest; valid = false; }
            cage = cageTaut;   // (Dynamics swings it from here)
            _pc[3] = lower = Lower(cage, zMech);
        }

        V Lower(double a, double z) => new V(upper.x + Math.Cos(a) * cageLen, upper.y + Math.Sin(a) * cageLen, z);

        double LenAt(double a, double z, bool checkRoute)
        {
            _pc[3] = Lower(a, z);
            if (_pc[3].y >= upper.y) return double.NaN;   // the cage must hang
            if (checkRoute)
            {
                if (RouteSolve(_sg, _pc, _rad) < 0) return double.NaN;
                for (int i = 0; i < 4; i++) _ps[i] = _sg[i] * _rad[i];
            }
            return BeltLen(_pc, _ps);
        }

        bool NewtonCage(double z)
        {
            if (!_routeOk) return false;
            for (int i = 0; i < 4; i++) _ps[i] = senses[i] * _rad[i];
            double a = cageTaut, target = TargetLen, lo = Rad(Clamp(cageMin, 182, 358)), hi = Rad(Clamp(cageMax, 182, 358));
            for (int it = 0; it < 8; it++)
            {
                double L0 = LenAt(a, z, false);
                if (double.IsNaN(L0)) return false;
                double err = L0 - target;
                if (Math.Abs(err) < 1e-6) break;
                double L1 = LenAt(a + 1e-4, z, false);
                double g = (L1 - L0) / 1e-4;
                if (Math.Abs(g) < 1e-6) return false;
                a = Clamp(a - err / g, lo, hi);
                _cgl = Math.Abs(g);
            }
            // the routing must still be a real chain path there
            _pc[3] = Lower(a, z);
            for (int i = 0; i < 4; i++) _ps[i] = senses[i] * _rad[i];
            if (BeltValid(_pc, _ps) < 0) { _routeOk = false; return false; }
            cageTaut = a;
            return true;
        }
        static double Rad(double d) => d * Math.PI / 180;

        bool ScanCage(double z)
        {
            double lo = Clamp(cageMin, 182, 358), hi = Clamp(cageMax, 182, 358);
            if (hi <= lo) { lo = 200; hi = 358; }
            double bestErr = 1e18, bestAng = cageTaut * 180 / Math.PI;
            int nsteps = Math.Max((int)((hi - lo) * 2.0), 8);
            double span = (hi - lo) / nsteps;
            for (int pass = 0; pass < 2; pass++)
            {
                double plo = pass == 0 ? lo : Math.Max(bestAng - span, lo), phi_ = pass == 0 ? hi : Math.Min(bestAng + span, hi);
                int pn = pass == 0 ? nsteps : 64;
                for (int it = 0; it <= pn; it++)
                {
                    double ang = plo + (phi_ - plo) * it / pn;
                    double L = LenAt(Rad(ang), z, true);
                    if (double.IsNaN(L)) continue;
                    double err = Math.Abs(L - TargetLen);
                    if (err < bestErr) { bestErr = err; bestAng = ang; for (int i = 0; i < 4; i++) senses[i] = _sg[i]; }
                }
            }
            if (bestErr > 1e17) return false;
            cageTaut = Rad(bestAng);
            _routeOk = true;
            // the loop's length per radian of cage, for the dynamics
            for (int i = 0; i < 4; i++) _ps[i] = senses[i] * _rad[i];
            double l0 = LenAt(cageTaut - 0.01, z, false), l1 = LenAt(cageTaut + 0.01, z, false);
            if (!double.IsNaN(l0) && !double.IsNaN(l1)) _cgl = Math.Abs(l1 - l0) / 0.02;
            return true;
        }
        bool _routeOk;
        double _cgl = 0.05, _sdir = 1;

        // ---------------------------------------------------------------- the cage and the chain, reacting
        bool _dynInit;
        double _dphi, _om, _yb, _vb, _yt, _vt;
        /// one drawn frame: dt (s), the rear axle's and the BB's vertical acceleration (m/s2, world), the drive force at
        /// the rear tyre's contact (N), the rear wheel radius (m). Leaves cage / bowTop / bowLow / tension set.
        public void Dynamics(double dt, double axleAcc, double bbAcc, double driveN, double wheelR, double cogR)
        {
            if (!dynamics || !valid || !(dt > 0)) { Settle(); return; }
            if (!Finite(axleAcc + bbAcc + driveN + wheelR + cogR)) { Settle(); return; }
            // a hitch just loses the time (an explicit spring step can't be stretched)
            dt = Math.Min(dt, 1.0 / 30.0);
            axleAcc = Clamp(axleAcc, -400, 400); bbAcc = Clamp(bbAcc, -400, 400);
            // which way + phi (chain let out) turns the cage: the loop's slope there
            for (int i = 0; i < 4; i++) _ps[i] = senses[i] * _rad[i];
            double zM = upper.z;
            double l0 = LenAt(cageTaut - 0.01, zM, false), l1 = LenAt(cageTaut + 0.01, zM, false);
            if (Finite(l0) && Finite(l1)) { double gs = (l1 - l0) / 0.02; _sdir = gs > 0 ? -1 : 1; _cgl = Clamp(Math.Abs(gs), 1e-3, 0.5); }
            double cgl = _cgl;
            V lj = Lower(cageTaut, zM);
            double dbx = lj.x - _pc[0].x, dby = lj.y - _pc[0].y, dtx = _pc[1].x - _pc[0].x, dty = _pc[1].y - _pc[0].y;
            double Lb = Math.Max(Math.Sqrt(dbx * dbx + dby * dby), 0.1), Lt = Math.Max(Math.Sqrt(dtx * dtx + dty * dty), 0.1);
            double nyb = Math.Abs(dbx / Lb), nyt = Math.Abs(dtx / Lt);   // how much of a vertical shake lands across each run
            double rc = 0.5 * cageLen, rcx = rc * Math.Cos(cageTaut);
            double J = cageMass * rc * rc * 1.3 + 1e-7;
            double mu = chainMass, T0 = Math.Max(cageTension, 1.0), kp = T0 * cgl;
            double clu = Clamp(clutch, 0, 1), Cf = clu * 2.0 * T0 * cgl, Cv = clu * 0.004;
            const double kch = 2e5, cch = 30.0, zs = 0.04, PI2 = Math.PI * Math.PI, KSTAY = 4e4;
            double Td = Clamp(Math.Max(0.0, driveN) * wheelR / Math.Max(cogR, 0.005), 0, 4000);
            double Tcap = 40.0 * T0 + Td;   // a chain under more than that has snapped; keeps the strings' rates bounded
            double am = 0.5 * (axleAcc + bbAcc);
            // the step: small enough for the stiffest thing in the system (the cage against the chain, the runs at the
            // highest tension they may reach, the top run on the chainstay), symplectic Euler stable at w h < 2: use 0.4
            double me = mu * Lt * 0.5;
            double wmax = Math.Max(Math.Sqrt(kch * cgl * cgl / J), Math.Sqrt(KSTAY / me));
            wmax = Math.Max(wmax, Math.PI / Math.Min(Lb, Lt) * Math.Sqrt(Tcap / mu));
            int sub = (int)Math.Ceiling(dt * wmax / 0.4);
            sub = Math.Max(1, Math.Min(sub, 3000));
            double h = dt / sub;
            if (!_dynInit) { _dphi = _om = _yb = _vb = _yt = _vt = 0; _dynInit = true; }
            double T = T0;
            for (int it = 0; it < sub; it++)
            {
                double Eb = PI2 / (4 * Lb) * _yb * _yb, Et = PI2 / (4 * Lt) * _yt * _yt;
                double sx = Eb + Et - cgl * _dphi;
                double ds = PI2 / (2 * Lb) * _yb * _vb + PI2 / (2 * Lt) * _yt * _vt - cgl * _om;
                T = Clamp(T0 + kch * sx + (sx > -T0 / kch ? cch * ds : 0.0), 0.0, Tcap);
                double tq = T * cgl - (T0 * cgl + kp * _dphi) + _sdir * rcx * (-cageMass * axleAcc);
                double cres = _om > 1e-9 ? Cf * Math.Tanh(_om / 0.5) / _om + Cv : 0.1 * Cv;
                _om = (_om + tq / J * h) / (1.0 + cres / J * h);
                _dphi += _om * h;
                if (_dphi > 0.6) { _dphi = 0.6; if (_om > 0) _om = 0; } else if (_dphi < -0.6) { _dphi = -0.6; if (_om < 0) _om = 0; }
                double Tb = Math.Max(T, 0.3), Tt = Math.Min(Math.Max(T + Td, 0.3), Tcap);
                double wb = Math.PI / Lb * Math.Sqrt(Tb / mu), wt = Math.PI / Lt * Math.Sqrt(Tt / mu);
                // (gravity's own sag is the taut pose's: only the shaking away from 1 g moves the runs)
                double fb = -wb * wb * _yb - 4.0 / Math.PI * nyb * am - 2 * zs * Math.Max(wb, 20) * _vb;
                double ft = -wt * wt * _yt - 4.0 / Math.PI * nyt * am - 2 * zs * Math.Max(wt, 20) * _vt;
                if (_yt < -stayGap)   // the top run on the chainstay
                {
                    double pen = -stayGap - _yt;
                    ft += (KSTAY * pen - (_vt < 0 ? 20.0 * _vt : 0.0)) / me;
                }
                _vb += fb * h; _yb += _vb * h;
                _vt += ft * h; _yt += _vt * h;
                if (_yb > 0.15) { _yb = 0.15; if (_vb > 0) _vb = 0; } else if (_yb < -0.15) { _yb = -0.15; if (_vb < 0) _vb = 0; }
                if (_yt > 0.15) { _yt = 0.15; if (_vt > 0) _vt = 0; } else if (_yt < -0.15) { _yt = -0.15; if (_vt < 0) _vt = 0; }
            }
            if (!Finite(_dphi + _om + _yb + _vb + _yt + _vt + T)) { _dynInit = false; Settle(); return; }
            cage = cageTaut + _sdir * _dphi;
            lower = Lower(cage, zM);
            bowLow = _yb; bowTop = _yt;
            tension = T;
        }

        /// no dynamics this frame (far away, no valid solve, bad input): the taut pose, the springs at rest
        public void Settle()
        {
            cage = cageTaut; lower = Lower(cage, upper.z); bowTop = bowLow = 0; tension = cageTension;
            _dynInit = false;
        }

        public static bool Finite(double x) => !double.IsNaN(x) && !double.IsInfinity(x);
        int _scanWait;

        // ---------------------------------------------------------------- the drawn chain path
        /// the closed path (ring, cog, top pulley, bottom pulley) with the cage where it is now and the runs bowed:
        /// points appended to xs / ys / zs, sampled every ~4 mm on the arcs; returns its length
        public double Path(System.Collections.Generic.List<double> o)
        {
            o.Clear();
            _pc[3] = lower;
            for (int i = 0; i < 4; i++) _ps[i] = senses[i] * _rad[i];
            int n = 4;
            for (int i = 0; i < n; i++)
            {
                V c0 = _pc[i], c1 = _pc[(i + 1) % n];
                double ex = c1.x - c0.x, ey = c1.y - c0.y, d = Math.Max(Math.Sqrt(ex * ex + ey * ey), 1e-7);
                _aout[i] = Math.Atan2(ey, ex) + Math.Acos(Clamp((_ps[i] - _ps[(i + 1) % n]) / d, -1, 1));
            }
            for (int i = 0; i < n; i++)
            {
                double a0 = _aout[(i - 1 + n) % n];
                double sw = Sweep(_aout[i] - a0, _ps[i]);
                int steps = Math.Max(2, (int)(Math.Abs(sw) * Math.Abs(_ps[i]) / 0.004));
                for (int m = 0; m <= steps; m++)
                {
                    double a = a0 + sw * m / steps;
                    o.Add(_pc[i].x + _ps[i] * Math.Cos(a)); o.Add(_pc[i].y + _ps[i] * Math.Sin(a)); o.Add(_pc[i].z);
                }
                // the straight run to the next pulley, bowed: ring -> cog is the top run, bottom pulley -> ring the lower
                int j = (i + 1) % n;
                double bow = i == 0 ? bowTop : i == 3 ? bowLow : 0.0;
                if (bow != 0.0)
                {
                    double x1 = _pc[i].x + _ps[i] * Math.Cos(_aout[i]), y1 = _pc[i].y + _ps[i] * Math.Sin(_aout[i]);
                    double x2 = _pc[j].x + _ps[j] * Math.Cos(_aout[i]), y2 = _pc[j].y + _ps[j] * Math.Sin(_aout[i]);
                    for (int m = 1; m < 12; m++)
                    {
                        double t = m / 12.0, s = Math.Sin(Math.PI * t);
                        o.Add(x1 + (x2 - x1) * t); o.Add(y1 + (y2 - y1) * t + bow * s); o.Add(_pc[i].z + (_pc[j].z - _pc[i].z) * t);
                    }
                }
            }
            o.Add(o[0]); o.Add(o[1]); o.Add(o[2]);
            double L = 0;
            for (int k = 3; k < o.Count; k += 3)
            {
                double dx = o[k] - o[k - 3], dy = o[k + 1] - o[k - 2], dz = o[k + 2] - o[k - 1];
                L += Math.Sqrt(dx * dx + dy * dy + dz * dz);
            }
            return L;
        }

        /// read rd_sram.extras.txt (key=v1,v2,...)
        public void Load(string text)
        {
            if (string.IsNullOrEmpty(text)) return;
            foreach (var line in text.Split('\n'))
            {
                int e = line.IndexOf('=');
                if (e <= 0) continue;
                string k = line.Substring(0, e).Trim();
                var p = line.Substring(e + 1).Trim().Split(',');
                double[] v = new double[p.Length];
                for (int i = 0; i < p.Length; i++) double.TryParse(p[i], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v[i]);
                V v3() => new V(v[0], v.Length > 1 ? v[1] : 0, v.Length > 2 ? v[2] : 0);
                switch (k)
                {
                    case "axis": axis = v3(); break;
                    case "pinTop": pinTop = v3(); break;
                    case "pinBot": pinBot = v3(); break;
                    case "link": link = v3(); break;
                    case "u0": u0 = v3(); break;
                    case "cageLen": cageLen = v[0]; break;
                    case "cageRestDeg": cageRest = v[0] * Math.PI / 180; break;
                    case "jockeyTeeth": jockeyTeeth = (int)Math.Round(v[0]); break;
                    case "originSeatstay": originSeatstay = v3(); break;
                    case "gap": gap = v[0]; break;
                    case "cageMinDeg": cageMin = v[0]; break;
                    case "cageMaxDeg": cageMax = v[0]; break;
                    case "chainSlack": chainSlack = (int)Math.Round(v[0]); break;
                    case "cogZ0": cogZ0 = v[0]; break;
                    case "ringZ": ringZ = v[0]; break;
                }
            }
        }
    }
}
