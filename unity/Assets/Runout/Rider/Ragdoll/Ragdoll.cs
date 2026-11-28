using System;
using System.Collections.Generic;

namespace Runout.Rider
{
    /// The crash ragdoll: port of godot/scripts/rider/ragdoll.gd's rigid-body path (today's behaviour): the start
    /// (joints + velocities, the startle, buried joints settled onto the ground) and the behaviour layer that aims the
    /// muscles of RagdollRb every step: neutral tone ("still alive" firm at first), startle reflex, self-preservation
    /// (legs reach down / arms brace while airborne), TUCK + ROLL, SPREAD to stop sliding, BRACE before a hit, WINDMILL
    /// high in the air, PAIN (curl up, a hand to the hurt part) with ROCKING, KNOCKED OUT on a hard head hit, the squirm.
    /// Space: Godot / sim world (x, y up, z). The 15 points p / q (Ragdoll order, = RiderPose.J):
    ///   0 head, 1 chest (collar), 2 pelvis, 3 shoulder L, 4 elbow L, 5 hand L, 6 shoulder R, 7 elbow R, 8 hand R,
    ///   9 hip L, 10 knee L, 11 foot L, 12 hip R, 13 knee R, 14 foot R.
    /// Not ported (dropped): the old point-ragdoll solver (+ its RagdollSolverCs passes), blood / severed limbs / broken
    /// bones (sever, break_joint, cut, free pieces), the balance controller (off in Godot too: BMX_BALANCE), probes / dumps.
    public sealed class Ragdoll
    {
        public const int HEAD = 0, CHEST = 1, PELVIS = 2, SH_L = 3, EL_L = 4, HA_L = 5, SH_R = 6, EL_R = 7, HA_R = 8,
            HIP_L = 9, KN_L = 10, FT_L = 11, HIP_R = 12, KN_R = 13, FT_R = 14;
        public const double WATER = -2.2;   // terrain.js WATER: below it the body floats and drags
        const int SUB = 3;                  // (the start velocity is per substep of the old point ragdoll: kept as Godot does)
        public static readonly double[] RAD = { 0.2, 0.15, 0.12, 0.08, 0.06, 0.06, 0.08, 0.06, 0.06, 0.08, 0.07, 0.07, 0.08, 0.07, 0.07 };

        /// [a, b, stiffness] (used to settle buried joints at the start)
        static readonly (int a, int b, double k)[] BONES = {
            (HEAD, CHEST, 1.0), (HEAD, SH_L, 0.6), (HEAD, SH_R, 0.6), (HEAD, PELVIS, 0.4),
            (CHEST, PELVIS, 1.0), (CHEST, SH_L, 1.0), (CHEST, SH_R, 1.0), (SH_L, SH_R, 1.0),
            (PELVIS, HIP_L, 1.0), (PELVIS, HIP_R, 1.0), (HIP_L, HIP_R, 1.0),
            (SH_L, HIP_L, 1.0), (SH_R, HIP_R, 1.0), (SH_L, HIP_R, 0.8), (SH_R, HIP_L, 0.8),
            (SH_L, EL_L, 1.0), (EL_L, HA_L, 1.0), (SH_R, EL_R, 1.0), (EL_R, HA_R, 1.0),
            (HIP_L, KN_L, 1.0), (KN_L, FT_L, 1.0), (HIP_R, KN_R, 1.0), (KN_R, FT_R, 1.0) };

        /// NEUTRAL BODY POSTURE: [child, parent, direction in the torso frame (right side; the left mirrors x)]
        static readonly (int c, int p, Vec3 d)[] NEUTRAL = {
            (HEAD, CHEST, new Vec3(0.0, 0.91, 0.41)),
            (EL_R, SH_R, new Vec3(0.25, -0.68, 0.69)),
            (HA_R, EL_R, new Vec3(-0.18, 0.45, 0.87)),
            (KN_R, HIP_R, new Vec3(0.1, -0.64, 0.76)),
            (FT_R, KN_R, new Vec3(0.04, -0.97, -0.22)),
            (EL_L, SH_L, new Vec3(-0.25, -0.68, 0.69)),
            (HA_L, EL_L, new Vec3(0.18, 0.45, 0.87)),
            (KN_L, HIP_L, new Vec3(-0.1, -0.64, 0.76)),
            (FT_L, KN_L, new Vec3(-0.04, -0.97, -0.22)),
        };
        const double ALIVE_K = 1.8, ALIVE_T = 1.4, REFLEX_T = 0.9;
        static readonly Dictionary<int, Vec3> REFLEX = new Dictionary<int, Vec3> {
            { 1, new Vec3(0.45, 0.72, 0.53) }, { 2, new Vec3(0.1, 0.95, 0.3) },
            { 5, new Vec3(-0.45, 0.72, 0.53) }, { 6, new Vec3(-0.1, 0.95, 0.3) } };
        const double HAND_FLING = 1.3, FEET_KICK = 0.8, SQUIRM_T = 4.0;
        const double AGENCY_T = 2.5, LEG_REACH = 0.85, ARM_BRACE = 0.7;
        static readonly int[] LEGS = { 3, 4, 7, 8 };
        static readonly int[] ARMS = { 1, 2, 5, 6 };
        const double TUCK_V = 5.5, TUCK_MAX = 1.2;
        const double ROCK_HZ = 0.7, ROCK_T = 4.0, ROCK_DRIVE = 3.0, SPREAD_DRIVE = 2.5;
        static readonly Vec3[] SPREAD = { new Vec3(0.0, 0.85, 0.5), new Vec3(0.9, 0.1, 0.4), new Vec3(0.8, 0.1, 0.55), new Vec3(0.45, -0.85, 0.25), new Vec3(0.1, -0.97, -0.1) };
        const double TUCK_SPIN = 3.5, TUCK_DRIVE = 4.5, BRACE_T = 0.3, BRACE_DRIVE = 3.5;
        const double PAIN_FROM = 0.6, PAIN_T = 3.5, PAIN_DRIVE = 1.6, KO_HIT = 8.0, KO_TONE = 0.35;
        const double MILL_DRIVE = 2.5, MILL_HZ = 1.4, HURT_MIN = 4.0;
        static readonly Vec3[] TUCK = { new Vec3(0.0, 0.5, 0.87), new Vec3(0.25, 0.4, 0.88), new Vec3(-0.5, 0.78, 0.1), new Vec3(0.12, 0.55, 0.83), new Vec3(0.0, -0.8, -0.6) };
        static readonly Vec3[] PAIN = { new Vec3(0.0, 0.7, 0.71), new Vec3(0.15, -0.35, 0.92), new Vec3(-0.65, 0.45, 0.6), new Vec3(0.15, -0.05, 0.98), new Vec3(0.0, -0.85, -0.5) };
        /// child point -> joint (motor) index of RagdollRb
        static readonly Dictionary<int, int> RB_JOINT = new Dictionary<int, int> {
            { HEAD, 1 }, { EL_L, 2 }, { EL_R, 3 }, { KN_L, 4 }, { KN_R, 5 }, { HA_L, 6 }, { HA_R, 7 }, { FT_L, 8 }, { FT_R, 9 } };
        public const double RB_PUSH_DV = 3.0;   // m/s a step at most from the bike's pushes / holds
        const double RB_SQUIRM = 9.0;

        // ---- bodies ----
        public const int BODIES = RagdollRb.NB;
        public static readonly string[] BODY_NAMES = { "pelvis", "chest", "head", "uarm_l", "farm_l", "uarm_r", "farm_r", "thigh_l", "shin_l", "thigh_r", "shin_r", "foot_l", "foot_r" };

        // ---- the world / state ----
        public Func<double, double, double> top_height;   // the drawn ground (Godot: Terrain.top_height); null / NaN = none
        public double water = WATER;
        public bool active;
        public Vec3[] p = new Vec3[15], q = new Vec3[15];
        public readonly double[] rad = (double[])RAD.Clone();
        public double speed, last_h, t_fall, contact_ext = 9.0;
        public bool ko;
        public double w_tuck, w_brace, w_pain, w_mill, w_spread, agency;
        public int hurt = -1;
        /// shoe mesh box (shoe space: x heel -> toe, y sole -> top, z across): Godot Game._shoe_box(); the default is Godot's
        public Vec3 shoe_min = new Vec3(-0.11, 0.0, -0.05), shoe_max = new Vec3(0.17, 0.1, 0.05);
        public double tone_k = 1.0;

        readonly RagdollRb _rb = new RagdollRb();
        readonly Random _rng;
        readonly double[] _rest = new double[BONES.Length];
        readonly double[] _nlen = new double[NEUTRAL.Length];
        byte[] _touch = new byte[15];
        readonly double[] _jn = new double[15];
        readonly Vec3[] _rb_dir = new Vec3[10];
        readonly double[] _rb_k = new double[10];
        object _trunk_src;
        double _fsign = 1.0, _com0;
        Vec3 _down = Vec3.DOWN, _brace = Vec3.DOWN, _sq_ph, _u_prev;
        double _rest_t, _spin, _rock_ph, _rock_dt = 1.0 / 120.0, _tuck_gnd, _mill_ph, _air_t, _hurt_v, _head_vy;
        bool _head_was;

        public Ragdoll(int seed = 12345) { _rng = new Random(seed); }
        double randf() => _rng.NextDouble();

        double Ground(double x, double z)
        {
            if (top_height == null) return -1e9;
            double g = top_height(x, z);
            return double.IsNaN(g) ? -1e9 : g;
        }

        /// The crash start (Godot: Game.start_crash -> ragdoll.start). Fill it like Godot does:
        ///   joints  = the rider's 15 joint points in the world (Rider.joints_world(): RiderPose.J through the rider's
        ///             transform), sim / Godot world space
        ///   vel     = body_vel = fwd * v + (0, min(max(vy, 0), air ? 6 : 0.3) + 0.2, 0)   (fwd = the bike's travel, sim)
        ///   spin    = spin_v   = fwd * (1 + |v| * 0.08)   (extra velocity per metre above the pelvis: the top keeps going)
        ///   shoeL / shoeR = the shoes' world transforms (x heel -> toe, y up out of the sole, z across), sim space
        ///   dt      = 1/60 (Godot's value: the start velocity's per-substep scale; leave it)
        /// Set top_height (and water) first; shoe_min / shoe_max = the shoe's mesh box if known.
        /// Static helper: CrashVelocity(fwd, v, vy, air) gives (vel, spin).
        public void start(Vec3[] joints, Vec3 vel, Vec3 spin, Xf shoeL, Xf shoeR, double dt = 1.0 / 60.0)
        {
            _touch = new byte[15];
            _trunk_src = null;
            Vec3 pel = joints[PELVIS];
            double hs = dt / SUB;
            for (int i = 0; i < 15; i++)
            {
                Vec3 pt = joints[i];
                p[i] = pt;
                double h = pt.y - pel.y;
                Vec3 d = vel + spin * h + new Vec3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.2;
                q[i] = pt - d * hs;
            }
            for (int k = 0; k < BONES.Length; k++) _rest[k] = joints[BONES[k].a].distance_to(joints[BONES[k].b]);
            for (int k = 0; k < NEUTRAL.Length; k++) _nlen[k] = joints[NEUTRAL[k].c].distance_to(joints[NEUTRAL[k].p]);
            _unbury();
            // forward = the side the knees are on in the riding pose
            _fsign = 1.0;
            Basis fr = _frame();
            Vec3 kn = (joints[KN_L] + joints[KN_R]) * 0.5 - (joints[HIP_L] + joints[HIP_R]) * 0.5;
            _fsign = kn.dot(fr.z) < 0.0 ? -1.0 : 1.0;
            // the startle: hands thrown up and out, feet a little up and forward (velocity = p - q per substep)
            fr = _frame();
            foreach (var (el, ha, sd) in new[] { (EL_L, HA_L, -1.0), (EL_R, HA_R, 1.0) })
            {
                Vec3 fling = (fr.y * HAND_FLING + fr.x * (sd * HAND_FLING * 0.35)) * (0.8 + randf() * 0.4);
                q[ha] = q[ha] - fling * hs;
                q[el] = q[el] - fling * 0.6 * hs;
            }
            foreach (int j in new[] { KN_L, FT_L, KN_R, FT_R })
            {
                Vec3 kick = (fr.y + fr.z) * FEET_KICK * ((j == FT_L || j == FT_R) ? 1.0 : 0.6) * (0.8 + randf() * 0.4);
                q[j] = q[j] - kick * hs;
            }
            // the startle is the body's own muscles: take its net push back out evenly (it can't lift the body)
            Vec3 mean = Vec3.ZERO;
            for (int i = 0; i < 15; i++) mean += p[i] - q[i];
            mean /= 15.0;
            Vec3 v_body = Vec3.ZERO;
            for (int i = 0; i < 15; i++) v_body += (vel + spin * (joints[i].y - pel.y)) * hs;
            v_body /= 15.0;
            Vec3 extra = mean - v_body;
            for (int i = 0; i < 15; i++) q[i] = q[i] + extra;
            // the rigid bodies
            var pv = new Vec3[15];
            for (int i = 0; i < 15; i++) pv[i] = (p[i] - q[i]) / hs;
            _rb.Begin((Vec3[])p.Clone(), pv, _fsign, NEUTRAL[1].d, NEUTRAL[3].d, shoeL, shoeR, shoe_min, shoe_max);
            _rb.SetGround(top_height, water);
            for (int k = 0; k < 10; k++) { _rb_dir[k] = Vec3.ZERO; _rb_k[k] = 0.0; }
            t_fall = 0.0;
            ko = false; w_tuck = 0.0; w_brace = 0.0; w_pain = 0.0; _rest_t = 0.0; _u_prev = Vec3.ZERO; _spin = 0.0;
            _head_was = false; _head_vy = 0.0; contact_ext = 0.0; _rock_ph = 0.0; w_spread = 0.0; _tuck_gnd = 0.0;
            w_mill = 0.0; _mill_ph = randf() * Math.PI * 2; _air_t = 0.0; hurt = -1; _hurt_v = 0.0; agency = 0.0;
            _com0 = _com().y;
            _sq_ph = new Vec3(randf(), randf(), randf()) * 10.0;
            active = true;
            last_h = hs;
        }

        /// Godot's start velocities from the bike (Game.start_crash): fwd = the bike's travel direction (sim), v its speed,
        /// vy its climb, air whether it was flying
        public static void CrashVelocity(Vec3 fwd, double v, double vy, bool air, out Vec3 vel, out Vec3 spin)
        {
            vel = fwd * v + new Vec3(0, Math.Min(Math.Max(vy, 0), air ? 6.0 : 0.3) + 0.2, 0);
            spin = fwd * (1.0 + Math.Abs(v) * 0.08);
        }

        public void stop() { active = false; }

        /// buried joints onto the ground, the bones settled round them; p and q move together (no speed)
        void _unbury()
        {
            var g = new double[15];
            bool any = false;
            for (int i = 0; i < 15; i++)
            {
                g[i] = Ground(p[i].x, p[i].z) + rad[i];
                if (p[i].y < g[i]) any = true;
            }
            if (!any) return;
            var p0 = (Vec3[])p.Clone();
            for (int it = 0; it < 12; it++)
            {
                for (int i = 0; i < 15; i++) if (p[i].y < g[i]) p[i] = new Vec3(p[i].x, g[i], p[i].z);
                for (int j = 0; j < BONES.Length; j++) _dist(BONES[j].a, BONES[j].b, _rest[j], BONES[j].k);
            }
            for (int i = 0; i < 15; i++)
            {
                if (p[i].y < g[i]) p[i] = new Vec3(p[i].x, g[i], p[i].z);
                q[i] = q[i] + (p[i] - p0[i]);
            }
        }

        void _dist(int a, int b, double len, double k)
        {
            Vec3 A = p[a], B = p[b];
            Vec3 d = B - A;
            double l = d.length();
            if (l < 1e-6) return;
            double c = (l - len) / l * 0.5 * k;
            p[a] = A + d * c;
            p[b] = B - d * c;
        }

        /// One physics step (Godot: ragdoll.step with the rigid bodies). near = colliders round the body: (x, z, r, top);
        /// top = NaN for a TRUNK (a vertical cylinder: collided with), a number for a dome (a rock / log: it is already in
        /// top_height, skipped), like Godot's Terrain.colliders_near ("tape" entries: leave them out)
        public void step(double dt, IList<(double x, double z, double r, double top)> near)
        {
            if (!active) return;
            last_h = dt;
            if (!ReferenceEquals(near, _trunk_src))
            {
                _trunk_src = near;
                var cyl = new List<double>();
                if (near != null)
                    foreach (var c in near)
                    {
                        if (!double.IsNaN(c.top)) continue;
                        cyl.Add(c.x); cyl.Add(c.z); cyl.Add(Math.Max(0.08, (c.r - 0.1) * 0.6)); cyl.Add(1e6);
                    }
                _rb.SetTrunks(cyl.ToArray());
            }
            if (t_fall == 0.0) _rb.SetGround(top_height, water);
            _agency_update(dt);
            _behave(dt);
            _rock_dt = dt;
            _neutral_pull();
            _rb.AnkleMax = 1e9;
            _rb.LegDampMul = 1.0;
            _rb.SetMotors(_rb_dir, _rb_k);
            // the squirm: a slow wandering twist of the chest against the pelvis (more while lying hurt), none knocked out
            if (!ko)
            {
                double amp = Math.Max(Math.Exp(-t_fall / SQUIRM_T), 0.5 * w_pain) * tone_k;
                if (amp > 0.01 && t_fall < SQUIRM_T * 1.5 + 6.0)
                {
                    Basis b = _frame();
                    if (!b.x.is_nan())
                    {
                        Vec3 tq = b.y * Math.Sin(t_fall * 2.3 + _sq_ph.x) + b.z * 0.5 * Math.Sin(t_fall * 1.7 + _sq_ph.y);
                        _rb.Couple(RagdollRb.B_CHEST, RagdollRb.B_PELVIS, tq * RB_SQUIRM * amp * dt);
                    }
                }
            }
            _rb.Step(dt);
            Vec3[] P = _rb.Points();
            double sp = 0.0;
            for (int i = 0; i < 15; i++)
            {
                Vec3 v = (P[i] - p[i]) / dt;
                q[i] = p[i]; p[i] = P[i];
                sp = Math.Max(sp, v.length());
            }
            byte[] tch = _rb.Touch();
            double[] hit = _rb.Hit();
            for (int i = 0; i < 15; i++) { _touch[i] = tch[i]; _jn[i] = hit[i] * dt; }
            t_fall += dt;
            speed = sp;
        }

        /// a push from outside on the points (the crashed bike: CrashBikeCs.CollideBody / HoldBody): the new points and their
        /// last positions (q = p - v last_h). Each moved point becomes a push + a velocity change on its body
        public void external_push(Vec3[] np, Vec3[] nq)
        {
            int n = Math.Min(np.Length, p.Length);
            double h = Math.Max(last_h, 1e-5);
            for (int i = 0; i < n; i++)
            {
                Vec3 dp = np[i] - p[i];
                Vec3 dv = ((np[i] - nq[i]) - (p[i] - q[i])) / h;
                if (dv.length() > RB_PUSH_DV) dv = dv.normalized() * RB_PUSH_DV;
                if (dp.length_squared() < 1e-12 && dv.length_squared() < 1e-8) continue;
                _rb.PushPoint(i, dp, dv);
                p[i] = np[i]; q[i] = nq[i];
            }
        }

        /// body i's world transform (sim space): see RagdollRb for the axes; i < BODIES (BODY_NAMES)
        public Xf body(int i) => _rb.BodyXf(i);
        /// the shoe drawn from its foot body (0 left, 1 right)
        public Xf shoe(int side) => _rb.ShoeXf(side);
        /// this step's contacts per point (1 = touching) and the hardest speed into the ground (m/s): dust, sound
        public bool touching(int i) => _touch[i] == 1;
        public double hit(int i) => _jn[i] / Math.Max(last_h, 1e-5);
        public double worst_limit() => _rb.WorstLimit();
        public double body_y(int i) => _rb.BodyY(i);

        Vec3 _com()
        {
            Vec3 c = Vec3.ZERO;
            for (int i = 0; i < 15; i++) c += p[i];
            return c / 15.0;
        }

        /// the torso's frame: x = right (hip to hip), y = up the spine, z = forward
        Basis _frame()
        {
            Vec3 u = (p[CHEST] - p[PELVIS]).normalized();
            Vec3 r = p[HIP_R] - p[HIP_L] + p[SH_R] - p[SH_L];
            r = (r - u * r.dot(u)).normalized();
            return new Basis(r, u, u.cross(r) * _fsign);
        }

        void _agency_update(double h)
        {
            Vec3 pe = p[PELVIS];
            double up_h = pe.y - Ground(pe.x, pe.z);
            double x = Math.Min(Math.Max((up_h - 0.35) / 0.55, 0.0), 1.0);
            agency = Math.Exp(-t_fall / AGENCY_T) * x * x * (3.0 - 2.0 * x) * tone_k;
            foreach (int j in new[] { FT_L, FT_R, KN_L, KN_R, HA_L, HA_R })
                if (_touch[j] == 1) { agency = 0.0; break; }
            if (agency < 0.01) return;
            Vec3 v = (pe - q[PELVIS]) / Math.Max(h, 1e-5);
            Vec3 hv = new Vec3(v.x, 0, v.z);
            Vec3 lead = hv.length() > 0.2 ? hv.normalized() * Math.Min(Math.Max(hv.length() / 10.0, 0.0), 0.5) : Vec3.ZERO;
            _down = (Vec3.DOWN + lead * 0.6).normalized();
            _brace = (Vec3.DOWN * 0.75 + lead * 1.4).normalized();
        }

        static double move_toward(double f, double t, double d) => Math.Abs(t - f) <= d ? t : f + Math.Sign(t - f) * d;
        static double clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);

        void _behave(double h)
        {
            Vec3 c = _com();
            Vec3 cq = Vec3.ZERO;
            for (int i = 0; i < 15; i++) cq += q[i];
            cq /= 15.0;
            Vec3 v = (c - cq) / Math.Max(h, 1e-5);
            double hs = Math.Sqrt(v.x * v.x + v.z * v.z);
            Vec3 u = (p[CHEST] - p[PELVIS]).normalized();
            if (_u_prev != Vec3.ZERO && !u.is_nan())
            {
                double a = Math.Acos(clamp(u.dot(_u_prev), -1.0, 1.0)) / Math.Max(h, 1e-5);
                _spin += (a - _spin) * Math.Min(1.0, h * 12.0);
            }
            _u_prev = u;
            bool any_touch = contact_ext < 0.1;
            if (!any_touch)
                for (int i = 0; i < 15; i++) if (_touch[i] == 1) { any_touch = true; break; }
            _air_t = any_touch ? 0.0 : _air_t + h;
            bool gnd = _air_t < 0.1;
            Vec3 hv = (p[HEAD] - q[HEAD]) / Math.Max(h, 1e-5);
            if (!ko && _touch[HEAD] == 1 && !_head_was && -_head_vy > KO_HIT) ko = true;
            _head_was = _touch[HEAD] == 1;
            _head_vy = hv.y;
            for (int i = 0; i < 15; i++)
            {
                if (_touch[i] == 1 && i != HEAD)
                {
                    double hit = _jn[i] / Math.Max(h, 1e-5);
                    if (hit > HURT_MIN && hit > _hurt_v) { _hurt_v = hit; hurt = i; }
                }
            }
            double t_tuck = 0.0, t_brace = 0.0, t_pain = 0.0, t_mill = 0.0, t_spread = 0.0;
            _mill_ph += h * Math.PI * 2 * MILL_HZ;
            if (!ko)
            {
                bool tumbling = _spin > TUCK_SPIN && v.length() > 2.0;
                if (gnd)
                {
                    if ((hs > 3.0 || tumbling) && _tuck_gnd < TUCK_MAX) t_tuck = 1.0;
                    else if (hs > 1.2 || tumbling) t_spread = 1.0;
                    if (w_tuck > 0.5) _tuck_gnd += h;
                    bool calm = v.length() < 0.5 || (_rest_t > PAIN_FROM && v.length() < 2.0);
                    _rest_t = calm ? _rest_t + h : Math.Max(0.0, _rest_t - h * 2.0);
                    double pain_len = Math.Max(PAIN_T, ROCK_T + 1.8);
                    if (_rest_t > PAIN_FROM) t_pain = clamp(1.0 - (_rest_t - PAIN_FROM - pain_len * 0.7) / (pain_len * 0.3), 0.0, 1.0);
                }
                else
                {
                    Vec3 ch = p[CHEST];
                    double up_c = ch.y - Ground(ch.x, ch.z);
                    double t_hit = up_c / Math.Max(-v.y, 0.5);
                    if ((hs > TUCK_V || tumbling) && t_hit < 0.35) t_tuck = 1.0;
                    if (t_tuck < 0.5 && v.y < -0.5 && t_hit < BRACE_T) t_brace = 1.0;
                    if (t_tuck < 0.5 && t_brace < 0.5 && _air_t > 0.15 && t_hit > 0.35 && v.length() > 2.5) t_mill = 1.0;
                }
            }
            w_tuck = move_toward(w_tuck, t_tuck, h * (t_tuck > w_tuck ? 6.0 : 2.5));
            w_brace = move_toward(w_brace, t_brace, h * 8.0);
            w_pain = move_toward(w_pain, t_pain, h * 2.0);
            w_mill = move_toward(w_mill, t_mill, h * (t_mill > w_mill ? 5.0 : 6.0));
            w_spread = move_toward(w_spread, t_spread, h * (t_spread > w_spread ? 4.0 : 1.5));
            agency *= 1.0 - w_tuck;
        }

        /// windmill pose for NEUTRAL index k (torso frame): arms circle in opposite phase, legs cycle
        Vec3 _mill_dir(int k)
        {
            bool left = k >= 5;
            int kr = left ? k - 4 : k;
            double ph = _mill_ph + (left ? Math.PI : 0.0);
            Vec3 d;
            switch (kr)
            {
                case 0: return NEUTRAL[0].d;
                case 1: d = new Vec3(0.45, Math.Cos(ph), Math.Sin(ph)); break;
                case 2: d = new Vec3(0.25, Math.Cos(ph + 0.7), Math.Sin(ph + 0.7)); break;
                case 3: d = new Vec3(0.1, -0.85 * Math.Cos(ph * 0.8), 0.3 + 0.6 * Math.Sin(ph * 0.8)); break;
                default: d = new Vec3(0.0, -0.9, -0.25 - 0.45 * Math.Max(0.0, Math.Sin(ph * 0.8))); break;
            }
            if (left) d.x = -d.x;
            return d.normalized();
        }

        static bool In(int[] a, int k) { foreach (int x in a) if (x == k) return true; return false; }

        /// the muscles' aims (rigid bodies: _neutral_pull in target mode) -> _rb_dir / _rb_k
        void _neutral_pull()
        {
            Basis b = _frame();
            if (b.x.is_nan() || b.x.length_squared() < 0.5) return;
            for (int k = 0; k < 10; k++) _rb_k[k] = 0.0;
            // the spine: straight on the pelvis, hunched forward tucking / hurt
            double hunch = 0.55 * w_tuck + 0.3 * w_pain;
            _rb_dir[0] = (b.y * Math.Cos(hunch) + b.z * Math.Sin(hunch)).normalized();
            _rb_k[0] = (1.0 + (ALIVE_K - 1.0) * Math.Exp(-t_fall / ALIVE_T)) * (ko ? KO_TONE : 1.0) * tone_k * (1.0 + 2.0 * w_tuck);
            double alive = Math.Exp(-t_fall / ALIVE_T);
            double firm = 1.0 + (ALIVE_K - 1.0) * Math.Max(alive, agency);
            if (ko) { alive = 0.0; firm = KO_TONE; }
            firm *= 1.0 + (TUCK_DRIVE - 1.0) * w_tuck + (BRACE_DRIVE - 1.0) * w_brace + (PAIN_DRIVE - 1.0) * w_pain + (MILL_DRIVE - 1.0) * w_mill + (SPREAD_DRIVE - 1.0) * w_spread;
            double rock = 0.0, rock_w = 0.0;
            if (w_pain > 0.01 && !ko)
            {
                double pt = Math.Max(0.0, _rest_t - PAIN_FROM);
                rock_w = w_pain * clamp(1.0 - (pt - ROCK_T) / 1.5, 0.0, 1.0);
                _rock_ph += _rock_dt * Math.PI * 2 * ROCK_HZ * (1.0 + (0.55 - 1.0) * clamp(pt / (ROCK_T + 1.5), 0.0, 1.0));
                rock = Math.Sin(_rock_ph) * rock_w;
            }
            int hold_arm = -1;
            Vec3 hold_pt = Vec3.ZERO;
            if (w_pain > 0.01 && hurt >= 0 && !ko && rock_w < 0.3)
            {
                bool right_side = hurt == SH_R || hurt == EL_R || hurt == HA_R || hurt == HIP_R || hurt == KN_R || hurt == FT_R;
                hold_arm = right_side ? 5 : 1;
                hold_pt = p[hurt];
                if (hurt == HA_L || hurt == HA_R) hold_pt = (p[hurt] + p[hurt == HA_L ? EL_L : EL_R]) * 0.5;
            }
            double startle = clamp(1.0 - t_fall / REFLEX_T, 0.0, 1.0);
            startle = startle * startle * (3.0 - 2.0 * startle);
            for (int k = 0; k < NEUTRAL.Length; k++)
            {
                int c = NEUTRAL[k].c, par = NEUTRAL[k].p;
                Vec3 pc = p[par];
                Vec3 dir = NEUTRAL[k].d;
                if (startle > 0.0 && REFLEX.TryGetValue(k, out Vec3 rf)) dir = dir.lerp(rf, startle);
                if (w_mill > 0.01) dir = dir.lerp(_mill_dir(k), w_mill);
                if (w_spread > 0.01)
                {
                    int kr2 = k < 5 ? k : k - 4;
                    Vec3 sd = SPREAD[kr2];
                    if (k >= 5) sd.x = -sd.x;
                    dir = dir.lerp(sd, w_spread);
                }
                if (w_tuck > 0.01 || w_pain > 0.01)
                {
                    int kr = k < 5 ? k : k - 4;
                    Vec3 bd = TUCK[kr].lerp(PAIN[kr], w_pain / Math.Max(w_tuck + w_pain, 1e-4));
                    if (k >= 5) bd.x = -bd.x;
                    dir = dir.lerp(bd, clamp(w_tuck + w_pain, 0.0, 1.0));
                }
                if (rock != 0.0)
                {
                    if (k == 3 || k == 7) dir = (dir + new Vec3(rock * 1.6, 0.2, 0.0)).normalized();
                    else if (k == 4 || k == 8) dir = (dir + new Vec3(rock * 0.9, 0.0, 0.0)).normalized();
                    else if (k == 1 || k == 5) dir = dir.lerp(new Vec3(0.15 * (k == 1 ? 1.0 : -1.0), -0.3, 0.95), rock_w).normalized();
                    else if (k == 2 || k == 6) dir = dir.lerp(new Vec3(-0.7 * (k == 2 ? 1.0 : -1.0), -0.2, 0.7), rock_w).normalized();
                    else if (k == 0) dir = (dir + new Vec3(-rock * 0.4, 0.0, 0.0)).normalized();
                }
                Vec3 wdir = (b * dir).normalized();
                if (agency > 0.01)
                {
                    if (In(LEGS, k)) wdir = wdir.lerp(_down, agency * LEG_REACH).normalized();
                    else if (In(ARMS, k)) wdir = wdir.lerp(_brace, agency * ARM_BRACE * (1.0 - startle)).normalized();
                }
                if (hold_arm >= 0 && (k == hold_arm || k == hold_arm + 1))
                {
                    Vec3 tw = hold_pt - pc;
                    if (tw.length_squared() > 1e-6) wdir = wdir.lerp(tw.normalized(), w_pain * 0.9).normalized();
                }
                if (w_brace > 0.01 && In(ARMS, k)) wdir = wdir.lerp(_brace, w_brace * ((k == 1 || k == 5) ? 0.85 : 0.6)).normalized();
                int ji = RB_JOINT[c];
                _rb_dir[ji] = wdir;
                _rb_k[ji] = firm * tone_k * ((k == 3 || k == 7 || k == 4 || k == 8) ? 1.0 + ROCK_DRIVE * rock_w : 1.0);
            }
        }
    }
}
