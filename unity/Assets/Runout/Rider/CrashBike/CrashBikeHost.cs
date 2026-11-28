using System;
using System.Collections.Generic;
using Runout.Sim;

namespace Runout.Rider
{
    /// What the engine knows about the drawn bike at the moment of the crash, in SIM space (Godot axes, world). The Unity
    /// adapter fills it from BikeRig (convert Unity -> sim with GodotSpace: points W(p), the model's world matrix
    /// G = W U M). See CrashBikeStart.Build for what each one is used for.
    public sealed class CrashBikeStartInput
    {
        /// the frame group's hull points in the world: for every non-steer, non-wheel part of the model, its
        /// `rig.hull.frame.<node>` support points (glb_extras.py, in that node's own mesh space) times that node's world
        /// transform now (incl. scale). Godot: BikeRig.crash_points().frame (before Reduce)
        public readonly List<Vec3> frameHull = new List<Vec3>();
        /// ... the same for the steer group (`rig.hull.steer.<node>`: bars, levers, stem, fork; the bars as turned now)
        public readonly List<Vec3> steerHull = new List<Vec3>();
        /// the model's world transform (Godot: rig.model.global_transform; may carry scale)
        public Xf model = Xf.IDENTITY;
        /// the rig's lean frame in the world = the rider's space (BikeRig.position + ModelRot): read back from the body
        public Xf leanFrame = Xf.IDENTITY;
        /// the wheel nodes' world transforms (basis z = the axle) and the tyres
        public Xf wheelF = Xf.IDENTITY, wheelR = Xf.IDENTITY;
        public double wheelRF = 0.374, wheelRR = 0.355, tyreHW = 0.03;
        /// the steer node's world position, the steering axis (world, unit: the steer's parent basis * steer_axis) and the
        /// bars' angle about it now (rad)
        public Vec3 steerPivot, steerAxis = Vec3.UP;
        public double steerAngle;
        /// the crank node's world position (bottom bracket), the grips' middles (world: steer xf * grip_l / grip_r) and
        /// the pedal pivots (world; 0..2 of them, null = none)
        public Vec3 crank, gripL, gripR;
        public Vec3[] pedals;
        /// a bail on purpose: the hands / feet let go at once (no holds)
        public bool bail;
    }

    /// Godot game.gd _crash_bike_begin: the point cloud (frame + steer hull reduced to 26 directions, a ring of
    /// CB_RING points round each tyre + its axle, the bottom bracket / saddle / head tube / grips / pedals), the
    /// capsules the rider can hit, the holds (hands on the grips, feet on the pedals), the start velocity / spin.
    public static class CrashBikeStart
    {
        public const int CB_RING = 12;
        // ragdoll joint order (ragdoll.gd / RiderPose.J)
        public const int HA_L = 5, HA_R = 8, FT_L = 11, FT_R = 14;

        /// the points it built, for the holds / capsules (indices into the body's points)
        public sealed class Built
        {
            public CrashBike bike;
            public int axleF = -1, axleR = -1, bb = -1, saddle = -1, headTop = -1, headBot = -1, gripL = -1, gripR = -1;
            public int[] pedals = { -1, -1 };
        }

        /// call right AFTER s.begin_crash() (it clears s.air: the start velocity is the ground one then, as in Godot).
        /// top(x, z) = the drawn ground's height. Sets s.crash_sim, s._cb_hit; the bike's RK / K read-back frames.
        public static Built Build(BikeSim s, CrashBikeStartInput d, Func<double, double, double> top, double dt = 1.0 / 120.0)
        {
            var pts = new List<double>(); var grp = new List<int>(); var wid = new List<int>();
            var mass = new List<double>(); var rad = new List<double>();
            void Add(Vec3 p, int g, int w, double m, double r)
            {
                pts.Add(p.x); pts.Add(p.y); pts.Add(p.z); grp.Add(g); wid.Add(w); mass.Add(m); rad.Add(r);
            }
            Basis mbo = d.model.b.orthonormalized();
            Vec3[] frame = CrashBike.Reduce(d.frameHull.ToArray(), mbo, 0.025);
            Vec3[] steer = CrashBike.Reduce(d.steerHull.ToArray(), mbo, 0.025);
            foreach (var p in frame) Add(p, 0, -1, 1.0, 0.006);
            foreach (var p in steer) Add(p, 1, -1, 0.45, 0.006);
            var o = new Built();
            int[] axle = { -1, -1 };
            // the tyres: a ring at the tread's middle each (radius = the casing's half width: it bulges past the rim's plane)
            for (int w = 0; w < 2; w++)
            {
                Xf wn = w == 0 ? d.wheelF : d.wheelR;
                double R = (w == 0 ? d.wheelRF : d.wheelRR) - d.tyreHW;
                Vec3 c = wn.o;
                Vec3 ax = wn.b.z.normalized();
                Vec3 u = ax.cross(Vec3.UP);
                if (u.length() < 0.1) u = ax.cross(Vec3.RIGHT);
                u = u.normalized();
                Vec3 vv = ax.cross(u).normalized();
                int g = w == 0 ? 1 : 0;
                for (int k = 0; k < CB_RING; k++)
                {
                    double a = 2.0 * Math.PI * k / CB_RING;
                    Add(c + (u * Math.Cos(a) + vv * Math.Sin(a)) * R, g, w, 0.25, d.tyreHW);
                }
                axle[w] = grp.Count;
                Add(c, g, w, 1.0, 0.0);   // the axle / hub
            }
            Xf body0 = new Xf(mbo, d.model.o);
            Vec3 axis = d.steerAxis.normalized();
            // the tubes the rider can hit (capsules between these points): bottom bracket, head tube ends, saddle, grips
            Vec3 up = d.model.b.y.normalized();
            Vec3 sad = d.crank + up * 0.7;
            double best = double.NegativeInfinity;
            foreach (var p in frame) if (p.dot(up) > best) { best = p.dot(up); sad = p; }   // (the frame's highest point: the saddle)
            Vec3 piv = d.steerPivot;
            o.bb = grp.Count; Add(d.crank, 0, -1, 0.5, 0.01);
            o.saddle = grp.Count; Add(sad, 0, -1, 0.2, 0.01);
            o.headTop = grp.Count; Add(piv + axis * 0.06, 0, -1, 0.3, 0.01);
            o.headBot = grp.Count; Add(piv - axis * 0.1, 0, -1, 0.3, 0.01);
            o.gripL = grp.Count; Add(d.gripL, 1, -1, 0.15, 0.02);
            o.gripR = grp.Count; Add(d.gripR, 1, -1, 0.15, 0.02);
            if (d.pedals != null)
                for (int k = 0; k < Math.Min(2, d.pedals.Length); k++) { o.pedals[k] = grp.Count; Add(d.pedals[k], 0, -1, 0.1, 0.01); }
            int[] caps = { axle[1], o.bb, o.bb, o.headBot, o.headTop, o.saddle, o.bb, o.saddle, o.headTop, o.headBot, o.headBot, axle[0], o.gripL, o.gripR, o.headTop, o.gripL, o.headTop, o.gripR };
            double[] capsR = { 0.035, 0.045, 0.035, 0.035, 0.04, 0.035, 0.03, 0.025, 0.025 };
            // the start velocity and spin: falling over toward its lean (lean_g turns about the bike's forward axis by -lean),
            // its yaw, and in the air its pitch spin
            V3 f = s.fwd();
            Vec3 vel = new Vec3(f.x, f.y, f.z) * s.v + new Vec3(0, s.air ? Gd.clampf(s.vy, -12.0, 6.0) : Math.Min(s.vy, 0.4), 0);
            Vec3 bx = d.model.b.x.normalized(), bz = d.model.b.z.normalized();
            Vec3 omega = -bx * s.crash_fall_v + Vec3.UP * s.yaw_rate + bz * (s.air ? s.air_w : 0.0);
            var bike = new CrashBike();
            bike.Begin(pts.ToArray(), grp.ToArray(), wid.ToArray(), mass.ToArray(), rad.ToArray(), body0, piv, axis, d.steerAngle,
                d.wheelF, d.wheelR, vel, omega, d.wheelRF, d.wheelRR, dt);
            bike.SetGround(top);
            bike.SetCapsules(caps, capsR, axle[0], axle[1]);
            // hands on the bars, feet on the pedals for the first moments: the grip slips after a short random time, a hard
            // yank breaks it sooner; flat pedals let go first. A bail on purpose lets go at once
            if (!d.bail)
            {
                var hb = new List<int> { o.gripL, o.gripR }; var hr = new List<int> { HA_L, HA_R };
                var hd = new List<double> { 0.12, 0.12 };
                var ht = new List<double> { 0.25 + Gd.randf() * 0.45, 0.25 + Gd.randf() * 0.45 };
                for (int k = 0; k < 2; k++)
                {
                    if (o.pedals[k] < 0) continue;
                    hb.Add(o.pedals[k]); hr.Add(k == 0 ? FT_L : FT_R); hd.Add(0.07); ht.Add(0.08 + Gd.randf() * 0.22);
                }
                bike.SetHolds(hb.ToArray(), hr.ToArray(), hd.ToArray(), ht.ToArray());
            }
            Xf binv = CrashBike.AffInv(body0);
            bike.K = CrashBike.Mul(binv, d.model);
            bike.RK = CrashBike.Mul(binv, d.leanFrame);
            s._cb_hit = new double[] { 0.0, 0.0 };
            s.crash_sim = bike;
            o.axleF = axle[0]; o.axleR = axle[1];
            o.bike = bike;
            return o;
        }
    }

    /// Godot BikePhysicsCs.GameHost.CrashSimStep: one physics step of the crashed bike (trunks near it, a wheel knocked
    /// off by a hard hit), then x, y, z, heading, pitch, lean, bars, speed, wheel spin read back into BikeSim. Call it from
    /// IRideHost.crash_body_step while s.crash_sim is a CrashBike (then the ragdoll: CollideBody / HoldBody).
    /// Left out here (the caller's job): fences / cacti near it being smashed (Godot: Game.smash when the bike moves > 2 m/s
    /// within r + 0.7 m of one); `trunks` must already leave out tape, rock domes ("sink"), fences, cacti and short
    /// colliders (top - base < 0.6 m); trunk top = 1e6 for a full-height trunk.
    public static class CrashBikeHost
    {
        public const double WHEEL_OFF_DV = 7.0, WHEEL_OFF_SPAN = 9.0, WHEEL_OFF_MAX = 0.5;
        public const double STEPOFF_DV = 1.4;

        public static void Step(BikeSim s, CrashBike b, double dt, Func<double, double, double> top_height,
            IList<(double x, double z, double r, double top)> trunks)
        {
            if (top_height != null) b.SetGround(top_height);
            if (!b.Asleep)
            {
                Vec3 vel = b.Velocity();
                var cyl = new List<double>();
                if (trunks != null)
                    foreach (var t in trunks) { cyl.Add(t.x); cyl.Add(t.z); cyl.Add(t.r); cyl.Add(t.top < 1e6 ? t.top : 1e6); }
                b.SetColliders(cyl.ToArray());
                b.Step(dt);
                for (int w = 0; w < 2; w++)
                {
                    if (b.WheelOff(w)) continue;
                    double hv = w == 0 ? b.HitFront : b.HitRear;
                    bool go = false;
                    if (hv > WHEEL_OFF_DV && s._cb_hit[w] <= WHEEL_OFF_DV)
                        go = Gd.randf() < Gd.clampf((hv - WHEEL_OFF_DV) / WHEEL_OFF_SPAN, 0.08, 1.0) * WHEEL_OFF_MAX;
                    s._cb_hit[w] = hv;
                    if (go)
                    {
                        var kick = new Vec3((Gd.randf() - 0.5) * 2.5, 1.2 + Gd.randf() * 1.6, (Gd.randf() - 0.5) * 2.5) + vel * 0.15;
                        b.Detach(w, kick, b.AxleRoll(w));
                    }
                }
            }
            Xf root = CrashBike.Mul(b.BodyAt(1.0), b.RK);
            Vec3 bx = root.b.x.normalized();
            s.x = root.o.x; s.y = root.o.y; s.z = root.o.z;
            if (Math.Sqrt(bx.x * bx.x + bx.z * bx.z) > 0.05) s.heading = Gd.atan2(-bx.z, bx.x);
            s.pitch = Gd.asin(Gd.clampf(bx.y, -1.0, 1.0));
            s.bike_lean = Gd.asin(Gd.clampf(root.b.z.normalized().y, -1.0, 1.0));
            s.steer = b.ThetaAt(1.0);
            Vec3 vv = b.Velocity();
            V3 f = s.fwd();
            double fdot = vv.x * f.x + vv.y * f.y + vv.z * f.z;
            s.v = Math.Sqrt(vv.x * vv.x + vv.z * vv.z) * (fdot >= 0.0 ? 1.0 : -1.0);
            if (!b.WheelOff(0)) s.wheel_f += b.AxleRoll(0) * dt;
            if (!b.WheelOff(1)) s.wheel_r += b.AxleRoll(1) * dt;
            s.counter = 0; s.rock = 0; s.pedal = 0; s.hop_nose = 0.0; s._hop_nose_t = 0.0; s._hop_nose_m = 0.0; s.yaw_rate = 0.0;
            s.body_y = s.y; s.body_v = 0; s.y_draw = s.y; s.pitch_draw = s.pitch;
        }

        /// Godot crash_body_step's slow-bail step-off: the rider's balance controller standing up shoves the bike away to
        /// the side it leans to and drops the holds (call once when that happens; s._bal_shoved guards it)
        public static void StepOff(BikeSim s, CrashBike b)
        {
            if (s._bal_shoved) return;
            s._bal_shoved = true;
            b.Release();
            Basis bb = b.BodyNow().b;
            Vec3 side = new Vec3(bb.z.x, 0.0, bb.z.z).normalized();
            double lean_s = Math.Sign(bb.y.dot(side));
            if (lean_s == 0) lean_s = 1;
            b.Shove(side * lean_s * STEPOFF_DV, 0.9);
        }
    }
}
