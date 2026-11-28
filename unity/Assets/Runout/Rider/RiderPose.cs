using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Rider
{
    /// The rider's riding pose, translated as is from godot/scripts/rider/rider.gd (update_pose + _constrain + limb_ik + the
    /// spine, the helpers they call) and rider_skeleton.gd (follow + _carry_fold). Engine-free; Unity's adapter maps the
    /// output onto a Humanoid. Probes / test flags / meshes / gear / fingers are left out (all BMX_OLD_* = off = today's pose).
    ///
    /// SPACE ("rider space" = Godot's rider node = the bike's lean node): +X forward, +Y up, +Z the rider's RIGHT; the bottom
    /// bracket sits near the origin (cranks at y ~0.3 on the DH). Right-handed. Every input and output is in this space.
    ///
    /// OUTPUTS after update_pose:
    ///   J[15]  joint points, Ragdoll order: 0 head, 1 chest (collar / top of the spine), 2 pelvis,
    ///          3 shoulder L, 4 elbow L, 5 hand L (grip), 6 shoulder R, 7 elbow R, 8 hand R,
    ///          9 hip L, 10 knee L, 11 foot L (= shoe origin + 5 cm up), 12 hip R, 13 knee R, 14 foot R.
    ///   head   the head node (origin = head centre, basis = euler_xyz(roll, yaw, pitch): its x = where the face points)
    ///   handL / handR  the glove nodes: origin on the grip, basis x = along the forearm into the hand, y = back of the hand,
    ///          z = along the bar (orient_grip / orient_hand)
    ///   shoeL / shoeR  the shoe nodes: origin = the shoe's origin (ankle sits at b*(ANKLE_X, ANKLE_UP, 0)), basis x = heel ->
    ///          toe, y = up out of the sole, z = the rider's right
    ///   spine[5] the torso's spine bones (set_spine): Xf with basis (f, tangent * length, right): y SCALED by the torso length
    ///   bones / bones_rest  Godot SkeletonProfileHumanoid bones, global poses in rider space (origin = joint, orthonormal-ish
    ///          basis; translated from the profile's quarter-turned frame by TO_RIDER). bones_rest = the profile T-pose (facing
    ///          +X, arms out along +-Z, x1.17 scale), so D = bones[k].b * bones_rest[k].b^-1 is each bone's turn from T-pose.
    ///          Each bone's y axis runs along the bone toward its child (Hips / Spine.. Head: up the torso; arms: out of the
    ///          shoulder toward the elbow / hand; legs: down toward the knee / ankle; Foot / Toes: toward the toes).
    ///          Rest axes per bone (rider space, columns x | y | z):
    ///            Hips, Spine, Chest, UpperChest, Neck, Head:  x=(0,0,-1) y=(0,1,0) z=(1,0,0)   (z = forward, x = left)
    ///            LeftShoulder  x=(1,0,0)  y=(0,0,-1) z=(0,1,0)      RightShoulder  x=(-1,0,0) y=(0,0,1) z=(0,1,0)
    ///            LeftUpperArm  x=(-1,0,0) y=(0,0,-1) z=(0,-1,0)     RightUpperArm  x=(1,0,0)  y=(0,0,1) z=(0,-1,0)
    ///            LeftLowerArm  x=(0,-1,0) y=(0,0,-1) z=(1,0,0)      RightLowerArm  x=(0,1,0)  y=(0,0,1) z=(1,0,0)
    ///            LeftHand      x=(-1,0,0) y=(0,0,-1) z=(0,-1,0)     RightHand      x=(1,0,0)  y=(0,0,1) z=(0,-1,0)
    ///            Left/RightUpperLeg  x=(0,0,1) y=(0,-1,0) z=(1,0,0)  Left/RightLowerLeg  x=(0,0,-1) y=(0,-1,0) z=(-1,0,0)
    ///            Left/RightFoot      x=(0,0,1) y=(1,0,0) z=(0,1,0)   Left/RightToes      x=(0,0,-1) y=(1,0,0) z=(0,-1,0)
    ///          The twist of each bone about its y follows rider_skeleton.gd's _aim (the rest axis that is turned toward a
    ///          reference): Hips / Spine / Chest / UpperChest: rest (0,0,1) (rider's right) -> the hip / shoulder line;
    ///          Neck / Head: rest (1,0,0) -> the head's facing; Upper / Lower arm and leg: rest (1,0,0) -> the elbow's fold /
    ///          the knee's bend; Shoulder: rest up -> up the torso; Hand: rest up -> back of the hand; Foot / Toes: rest up ->
    ///          up out of the sole. Not posed: fingers, eyes, jaw (keep their rest under the hand / head).
    ///   foot_pitch[2]  each foot's pitch on its pedal (rad, + = toes up): the pedals turn with it
    ///   body_off, tuck_out, speed_tuck_k, bump_pitch  as Godot (Game reads body_off / tuck_out for the drawn bike in the air)
    ///
    /// INPUTS (PoseInput, Godot game.gd ~4296-4415; missing = its default). Vec3 = rider space, angles rad:
    ///   footL, footR (Vec3)  pedal pivots (the pedal axle points)        handL, handR (Vec3)  grip middles
    ///   gripX_L, gripX_R, gripZ (Vec3)  the grip's frame: forward across the bar, the bar's axis (+Z side)
    ///   v  speed m/s (+ forward)        lean  drawn bike lean (+ left) incl. the pedalling rock     steer  drawn bar angle
    ///   yawRate  rad/s (smoothed)       counter  how far the body stays more upright than the bike (rad; null = old shift)
    ///   rockRoll  the pedalling rock    frameY  physics frame height (world m, for the bump bounce)  headRoll  head roll
    ///   absorb  legs' compression m (body_y - y_draw, - = bent)   pitch  drawn bike pitch (+ nose up)
    ///   bodyLevel (0.85)  attackDrop (0.18)  Tune values       pedal 0..1  sprint 0..1 (x pedal)  spinOut 0..1
    ///   stamina 0..1   hr  heart rate bpm (72)   crank  crank angle rad   air  0..1 (st.air_k)   compress  m (>= 0, legs in)
    ///   extend  m (>= 0)  preload 0..1  popFx 0..1  airPull 0..1  squash 0..1  lipK 0..1  landFold 0..1  landReach 0..1
    ///   inAir 0/1   brakeF, brakeR 0..1   hipShift m   bodyStick -1..1 (right stick fore/aft, + forward)   speedTuck 0..1
    ///   relax 0..1  tall 0..1  lookYaw, lookPitch, lookTwist rad   slope  the land's slope under the wheels (rad; key present
    ///   = on a bike)   frontUp  manual angle rad   airTilt rad   bodyLat -1..1   airWhip rad   torsoVmax m/s (2.5)
    ///   latG  lateral g   wheelR, wheelF (Vec3) axles   wheelRR, wheelRF  radii m   t  seconds   airSpin  yaw rate in air
    ///   flipTwist, flipArch, flipExt  0..1   wheelY  world m (mean axle height)   turn  yaw rate on the ground   pedalTop m
    ///   dab 0..1, dabSide -1/1, dabNormal (Vec3 or null), footOut 0..1, footOutSide -1/1, dabLean rad, dabLeanVar rad,
    ///   stopStand 0..1, stopSit 0..1   bumpPitch (0.85)   stand 0/1 (standing on the floor: garage)
    ///   pk  Dictionary<string, double> Pose Lab offsets (hip_x/y/z, torso_pitch/roll/yaw, head_pitch/yaw, elbows_out, knees_out...)
    public sealed class RiderPose
    {
        // ---- body (Godot values; Unity may set them from the character model)
        public double L_THIGH = 0.44, L_SHIN = 0.44, L_UARM = 0.32, L_FARM = 0.32;
        /// torso length (pelvis -> chest) when no style sets it: style "torso" wins (NEUTRAL 0.46, the DH pose 0.52)
        public double TORSO = 0.46;
        public double SHOULDERS = 0.2;        // half the shoulder width (style "shoulders" wins when set)
        public double HIP_HALF = 0.11;        // m: each hip joint off the pelvis's middle (+ style stance)
        public double HEAD_UP = 0.2;          // m: head centre above the chest joint
        public double HEAD_FWD = 0.05;        // m: ... and ahead of it
        public double SHOULDER_BACK = 0.03, SHOULDER_DOWN = 0.04;   // the shoulder joint off the chest joint (back, down)
        public double HEM_Y = 0.05;           // Belt.HEM_Y: the jersey's hem above the pelvis (spine root)
        public double NECK_TOP_X = -0.035, NECK_TOP_Y = -0.07;   // Rider.NECK_TOP: the neck's top in head space
        public double WRIST_TO_GRIP = 0.07;   // follow: the wrist this far back from the grip along the hand
        public double TOES_FWD = 0.09;        // follow: the Toes bone this far along the shoe from its origin
        public double ANKLE_X = -0.055, ANKLE_UP = 0.09, BALL_X = 0.08;   // the ankle off the shoe origin, ball of the foot

        public Func<string, double, double> tune = (k, d) => d;
        public double[] seat;                 // null or {top, rear, front}
        public Vec3 fit = Vec3.ZERO;
        public double pedal_top = 0.017;

        public Vec3[] J = new Vec3[15];
        public Xf head = Xf.IDENTITY, handL = Xf.IDENTITY, handR = Xf.IDENTITY, shoeL = Xf.IDENTITY, shoeR = Xf.IDENTITY, pelvis_xf = Xf.IDENTITY;
        public Xf[] spine = new Xf[SPINE_BONES];
        public Dictionary<string, Xf> bones = new Dictionary<string, Xf>();
        public Dictionary<string, Xf> bones_rest = new Dictionary<string, Xf>();
        public double[] foot_pitch = new double[2];
        public Vec2 body_off = Vec2.ZERO;
        public double tuck_out, speed_tuck_k, bump_pitch;
        public Dictionary<string, double> style = new Dictionary<string, double>();

        readonly Random _rng = new Random(1234);
        double randf_range(double a, double b) => a + (b - a) * _rng.NextDouble();

        public RiderPose()
        {
            set_style(null);
            for (int i = 0; i < 15; i++) J[i] = Vec3.ZERO;
            for (int i = 0; i < SPINE_BONES; i++) spine[i] = Xf.IDENTITY;
            RiderSkeleton.FillRest(bones_rest);
        }

        // ---------------- style ----------------
        /// riding style (rider.gd NEUTRAL): bools as 0 / 1 (seatFloor)
        public static readonly Dictionary<string, double> NEUTRAL = new Dictionary<string, double>
        {
            {"hipX", 0.0}, {"hipY", 0.0}, {"lean", 0.0}, {"elbowsOut", 0.0}, {"kneesOut", 0.0}, {"stance", 0.0}, {"seatFloor", 0.0},
            {"crouch", 1.0}, {"standPedal", 1.0}, {"aero", 1.0}, {"speedTuckPose", 1.0}, {"sway", 1.0}, {"bikeRock", 1.0}, {"upright", 1.0},
            {"hipSway", 0.015}, {"torso", 0.46}, {"attackStand", 1.0}, {"kneeOpen", 1.0}, {"bumpAbsorb", 2.0}, {"bodyBounce", 0.4},
            {"leanFollow", 1.0}, {"leanSwing", 1.0}, {"leanUnweight", 1.0}, {"leanLively", 1.0}, {"leanBalance", 1.0}, {"leanBumps", 1.0},
            {"leanLoad", 1.0}, {"cornerCrouch", 1.0}, {"bodyBob", 1.0},
            {"flowBend", 1.0}, {"flowLead", 1.0}, {"flowSink", 1.0},
            {"headSteady", 1.0}, {"ankling", 1.0}, {"heelsDown", 1.0}, {"ankleRoll", 1.0}, {"heelTurn", 1.0},
            {"hipSteady", 90.0}, {"standHeight", 0.15}, {"standBack", 0.03}, {"pedalChest", 0.05}, {"turnLow", 1.0}, {"turnTwist", 1.0},
            {"turnHips", 1.0}, {"slowWobble", 1.0}, {"airCrouch", 1.0},
            {"shoulders", 0.2}, {"headTilt", 0.0}, {"headTurn", 1.0}, {"lookAhead", 0.0},
            {"hipZ", 0.0}, {"pelvisTilt", 0.0}, {"pelvisRoll", 0.0}, {"pelvisYaw", 0.0},
            {"spineCurve", 0.0}, {"spineSide", 0.0}, {"spineLow", 0.5}, {"chestFwd", 0.0}, {"chestUp", 0.0}, {"chestSide", 0.0}, {"twist", 0.0},
            {"neck", 0.0}, {"headYaw", 0.0}, {"headRoll", 0.0},
            {"shoulderFwd", 0.0}, {"shoulderUp", 0.0}, {"elbowsDown", 0.0}, {"elbowOutL", 0.0}, {"elbowOutR", 0.0}, {"wristRoll", 0.0},
            {"elbowsBack", 0.0}, {"armBend", 0.6},
            {"kneesFwd", 0.0}, {"kneeOutL", 0.0}, {"kneeOutR", 0.0}, {"heelFwd", 0.0}, {"heelUp", 0.0}, {"footAngle", 0.0}, {"footOut", 0.0}, {"footSlide", 0.025},
        };

        Vec3[] poles_leg = new Vec3[2], poles_arm = new Vec3[2];

        /// riding position; keys as NEUTRAL (missing keys take the neutral value)
        public void set_style(Dictionary<string, double> s)
        {
            style = new Dictionary<string, double>(NEUTRAL);
            style["torso"] = TORSO; style["shoulders"] = SHOULDERS;
            if (s != null) foreach (var kv in s) style[kv.Key] = kv.Value;
            double kneesOut = S("kneesOut"), elbowsOut = S("elbowsOut");
            for (int i = 0; i < 2; i++)
            {
                double sd = i == 0 ? -1.0 : 1.0;
                double ko = kneesOut + S(sd < 0 ? "kneeOutL" : "kneeOutR");
                double eo = elbowsOut + S(sd < 0 ? "elbowOutL" : "elbowOutR");
                poles_leg[i] = new Vec3(1 + S("kneesFwd"), 0.1 - 0.5 * S("kneesFwd"), sd * (0.1 + 0.3 * ko)).normalized();
                poles_arm[i] = new Vec3(-0.3 + 0.2 * eo - S("elbowsBack"), -0.25 + 0.3 * eo - S("elbowsDown"), sd * clampf(0.75 + 0.5 * eo, 0.1, 1.3)).normalized();
            }
        }
        double S(string k, double d = 0.0) => style.TryGetValue(k, out var v) ? v : d;

        static double _num(PoseInput p, string k, double def = 0.0)
        {
            var v = p.get(k);
            if (v == null) return def;
            if (v is bool b) return b ? 1.0 : 0.0;
            if (v is double d) return d;
            if (v is float f) return f;
            if (v is int i) return i;
            return def;
        }
        static double sm(double a, double b, double s) => smoothstep(a, b, s);
        static double exp_(double x) => Math.Exp(x);

        // ---------------- constants (rider.gd) ----------------
        const double LAT_HIP = 0.06, LAT_CHEST = 0.22, LAT_DROP = 0.03;
        const double SPR_LAG = 0.5;
        const double SPR_KNEE_IN = 0.85, SPR_KNEE_CLEAR = 0.085, SPR_HIP_ROCK = 0.5, SPR_HIP_BACK = 0.05, SPR_CHEST_LOW = 0.30;
        const double SPR_PULL_TWIST = 0.16, SPR_PULL_FWD = 0.015, SPR_PULL_DOWN = 0.012, SPR_PUSH_UP = 0.01, SPR_HEAD_DOWN = 0.34;
        const double SPIN_CALM_FROM = 85.0, SPIN_CALM_FULL = 125.0, SPIN_CALM_LEFT = 0.08;
        const double SPIN_LOOK_DOWN = 0.5;
        const double PITCH_LEVEL_RATE = 2.5;
        const double FACE_SINK = 0.35;
        const double TUCK_ANG = 1.2, TUCK_HIP_BACK = 0.16, TUCK_HIP_DOWN = 0.10;
        static readonly Vec2 TUCK_HEAD = new Vec2(0.07, -0.08);
        const double FLIP_LEAN = 0.7, FLIP_ARCH = 0.5, FACE_REACH = 0.96, FACE_POSE = 0.85;
        static readonly Vec2 FACE_HIP = new Vec2(-0.42, 0.68);
        const double FACE_TORSO = 0.08;
        const double HEAD_PITCH_HL = 0.16, HEAD_YAW_HL = 0.22, NECK_W = 15.0, NECK_Z = 0.7;
        const double CHEST_KY = 0.6, CHEST_PUSH = 0.6;
        static readonly Vec3 NECK_MAX = new Vec3(0.025, 0.035, 0.012);
        const double ANKLE_SWING = 0.17, ANKLE_PHASE = 0.26;
        static readonly double ANKLE_DORSI = 50.0 * Math.PI / 180.0, ANKLE_PLANTAR = 135.0 * Math.PI / 180.0;
        const double HEEL_TURN_MAX = 0.3, ANKLE_ROLL_MAX = 0.21, HEEL_OUT_DROP = 0.1;
        const double NECK_ROLL = 0.6, NECK_BEND = 0.4;
        const double ROLL_HIP_W = 8.0, ROLL_HIP_Z = 0.55, ROLL_CHEST_W = 6.5, ROLL_CHEST_Z = 0.5, ROLL_UNWEIGHT = 0.045;
        const double LIMB_TORSO = 0.18, LIMB_LIMB = 0.105, AIR_COUNTER = 1.4, AIR_HIP_ROLL = 1.05, LIMB_BAR = 0.12, AIR_FACE = 0.7;
        const double AIR_HIP_SIDE = 0.5, AIR_SIDE = 1.2;
        const double SLOW_FROM = 4.0, SLOW_TO = 11.0, SLOW_PIVOT = 0.18, LEAN_REACH = 0.97, HIP_SIDE = 0.22;
        const double CORNER_HIP = 0.07, CORNER_CHEST = 0.08, OUT_ELBOW_DOWN = 0.7;
        const double STOP_HIP_FWD = 0.12, STOP_LEG = 0.95, STOP_TORSO = 0.3, SIT_TORSO = 0.15, SLOW_TALL = 0.05;
        const double AIR_HIP_SHARE = 0.3, AIR_CHEST_CAP = 0.75;
        const double BAR_CHEST = 0.32, BAR_HEAD = 0.31, TORSO_VMAX = 2.5;
        public const int SPINE_BONES = 5;
        const double WRIST_BEND = 0.0, WRIST_MAX = 0.9, GRIP_TILT = 0.12, KNEE_CLEAR = 0.12;
        const double ELBOW_MIN = 12.0, ELBOW_MAX = 150.0, KNEE_MIN = 4.0, KNEE_MAX = 160.0, BEND_RATE = 6.0;
        const double SHIN_INTO = 0.04;

        // ---------------- state ----------------
        double sm_shift_z;
        Vec3 pel_s, pel_v, ch_s, ch_v;
        bool spring_init;
        Vec3 _roll_dp, _roll_dc, _roll_dp_prev, _roll_dc_prev;
        double sm_turn, sm_aero, sm_fold, sm_reach, _sink, sm_airst, _abs_p, _abs_c;
        double sm_pre, sm_ext, sm_popfx, sm_squash, sm_lip, sm_tuck;
        Vec2 _air_ref = Vec2.ZERO; bool _air_ref_ok;
        double sm_effort, _cad_acc, _cad_t, _cad_prev, _cad_s, _inhale, _winded, _breath_ph;
        double[] _arm_pull = new double[2];
        double _spin_calm, _hd_s; bool _hd_on; double _hd_t;
        double _so_s, _so_up, _so_t, _so_next = 1.5;
        double _spr_arm, sm_pitch0, sm_pitch_slow, sm_wheelie, _face_k, _fat;
        bool _hp_init; double _hp_s, _hp_v, _yr_s, _yr_v, _hy; Vec3 _neck_d, _neck_v;
        double[] _heel_yaw = new double[2], _ank_roll = new double[2];
        double _spring3_v_x, _spring3_v_y, _spring3_v_z;
        double _fy_prev = double.NaN, _fv_prev = double.NaN, _facc;
        bool roll_init; double roll_p, roll_pv, roll_c, roll_cv, knee_lean, lat_g_s, flow_e;
        double slow_up, _stop_long, _body_roll;
        Vec3 _cap_pel, _cap_ch; bool _cap_ok;
        Vec3[] _bd_prev = new Vec3[4];
        double _pk_tyaw, _pk_hp, _pk_hy, _pk_eo, _pk_ko, _pk_wb, _pk_wt, _pk_grip, _pk_lp;
        readonly RiderSkeleton _skel = new RiderSkeleton();

        public void reset_pose()
        {
            _so_s = 0.0; _so_up = 0.0; _so_t = 0.0;
            _cap_ok = false;
            spring_init = false;
            for (int i = 0; i < 4; i++) _bd_prev[i] = Vec3.ZERO;
            pel_v = Vec3.ZERO; ch_v = Vec3.ZERO;
            sm_wheelie = 0.0; sm_aero = 0.0; sm_effort = 0.0; sm_turn = 0.0;
            sm_pre = 0.0; sm_ext = 0.0; sm_popfx = 0.0; sm_tuck = 0.0; sm_squash = 0.0; sm_lip = 0.0; sm_fold = 0.0; sm_reach = 0.0;
            roll_init = false; roll_pv = 0.0; roll_cv = 0.0; lat_g_s = 0.0; flow_e = 0.0;
            _fy_prev = double.NaN; _fv_prev = double.NaN; _facc = 0.0;
            _hp_init = false; _hy = 0.0; _neck_d = Vec3.ZERO; _neck_v = Vec3.ZERO;
            _spr_arm = 0.0; _fat = 0.0; body_off = Vec2.ZERO; _air_ref_ok = false;
            _skel.reset();
        }

        static double slowness(double va, Func<string, double, double> tune)
        {
            double t = clampf(absf(va) / tune("sprintSlowTo", 11.0), 0.0, 1.0);
            return 1.0 - t * t * (3.0 - 2.0 * t);
        }

        // ---------------- springs ----------------
        /// exact step of x'' = k (g - x) - c x' + a over dt (Holden, "Spring-It-On"): (x, v)
        public static Vec2 spring_exact(double x, double v, double g, double k, double c, double a, double dt)
        {
            if (k <= 1e-6 || dt <= 0.0) return new Vec2(x + v * dt, v);
            double gg = g + a / k;
            double x0 = x - gg;
            double y = c * 0.5;
            double disc = k - y * y;
            if (absf(disc) < 1e-4 * k)
            {
                double j1 = v + x0 * y;
                double e = exp_(-y * dt);
                return new Vec2(e * (x0 + j1 * dt) + gg, e * (v - j1 * y * dt));
            }
            if (disc > 0.0)
            {
                double w = Math.Sqrt(disc);
                double B = (v + y * x0) / w;
                double e = exp_(-y * dt);
                double cs = Math.Cos(w * dt), sn = Math.Sin(w * dt);
                return new Vec2(gg + e * (x0 * cs + B * sn), e * ((B * w - y * x0) * cs - (x0 * w + y * B) * sn));
            }
            {
                double r = Math.Sqrt(y * y - k);
                double y0 = y + r, y1 = y - r;
                double j1 = (-y0 * x0 - v) / (y1 - y0);
                double j0 = x0 - j1;
                double e0 = exp_(-y0 * dt), e1 = exp_(-y1 * dt);
                return new Vec2(j0 * e0 + j1 * e1 + gg, -y0 * j0 * e0 - y1 * j1 * e1);
            }
        }

        Vec3 _spring3(Vec3 x, Vec3 v, Vec3 g, double k, double ky, double z, double ay, double dt)
        {
            double c = 2.0 * Math.Sqrt(k) * z;
            double cy = 2.0 * Math.Sqrt(ky) * z;
            var rx = spring_exact(x.x, v.x, g.x, k, c, 0.0, dt);
            var ry = spring_exact(x.y, v.y, g.y, ky, cy, ay, dt);
            var rz = spring_exact(x.z, v.z, g.z, k, c, 0.0, dt);
            _spring3_v_x = rx.y; _spring3_v_y = ry.y; _spring3_v_z = rz.y;
            return new Vec3(rx.x, ry.x, rz.x);
        }
        Vec3 _spring3_v => new Vec3(_spring3_v_x, _spring3_v_y, _spring3_v_z);

        public static Vec2 crit_spring(double x, double v, double g, double hl, double dt)
        {
            double y = 1.3862944 / maxf(hl, 1e-4);
            double j0 = x - g;
            double j1 = v + j0 * y;
            double e = exp_(-y * dt);
            return new Vec2(e * (j0 + j1 * dt) + g, e * (v - j1 * y * dt));
        }

        // ---------------- the pose ----------------
        public void update_pose(double dt, PoseInput p)
        {
            double v = _num(p, "v");
            double pedal = clampf(_num(p, "pedal"), 0, 1);
            double t = _num(p, "t");
            double low_speed = 1.0 - clampf(absf(v) / 6.0, 0, 1);

            double target_shift = p.get("counter") != null ? 0.0 : _num(p, "lean") * low_speed;
            double k = 1.0 - exp_(-10.0 * minf(dt, 0.1));
            sm_shift_z += (target_shift - sm_shift_z) * k;
            double shift = clampf(sm_shift_z, -0.6, 0.6);

            double crank = _num(p, "crank");
            double spr = clampf(_num(p, "sprint"), 0, 1);
            double hi_fade = 1.0 - 0.85 * sm(5.0, 12.0, absf(v));
            double effort = spr * pedal * slowness(v, tune) * tune("sprintEffort", 1.0);
            sm_effort += (effort - sm_effort) * (1.0 - exp_(-6.0 * minf(dt, 0.1)));
            double eff = sm_effort;
            if (dt > 0.0 && dt <= 0.1)
            {
                _cad_acc += absf(wrapf(crank - _cad_prev, -PI, PI));
                _cad_t += dt;
                if (_cad_t >= 0.15)
                {
                    _cad_s += (_cad_acc / _cad_t * 9.549 - _cad_s) * 0.35;
                    _cad_acc = 0.0; _cad_t = 0.0;
                }
            }
            _cad_prev = crank;
            double cad_k = sm(70.0, 130.0, _cad_s) * clampf(spr + sm_effort, 0.0, 1.0);
            double calm_t = sm(SPIN_CALM_FROM, SPIN_CALM_FULL, _cad_s) * clampf(spr + sm_effort, 0.0, 1.0);
            _spin_calm += (calm_t - _spin_calm) * (1.0 - exp_(-(calm_t > _spin_calm ? 0.7 : 2.5) * minf(dt, 0.1)));
            double calm_k = lerpf(1.0, SPIN_CALM_LEFT, _spin_calm);
            double arm_tgt = clampf(maxf(spr * pedal, sm_effort), 0.0, 1.0);
            _spr_arm += (arm_tgt - _spr_arm) * (1.0 - exp_(-(arm_tgt > _spr_arm ? 7.0 : 1.3) * minf(dt, 0.1)));
            if (_spr_arm > 0.5 && _num(p, "air") < 0.3)
            {
                _hd_t -= dt;
                if (_hd_t <= 0.0)
                {
                    _hd_on = !_hd_on;
                    double fast = sm(6.0, 15.0, absf(v));
                    _hd_t = _hd_on ? randf_range(lerpf(0.6, 0.3, fast), lerpf(1.1, 0.6, fast)) : randf_range(lerpf(0.4, 0.8, fast), lerpf(0.9, 1.7, fast));
                }
            }
            else { _hd_on = false; _hd_t = randf_range(0.15, 0.4); }
            _hd_s += ((_hd_on ? 1.0 : 0.0) * _spr_arm - _hd_s) * (1.0 - exp_(-(_hd_on ? 9.0 : 12.0) * minf(dt, 0.1)));
            double so_in = _num(p, "air") > 0.3 ? 0.0 : clampf(_num(p, "spinOut"), 0.0, 1.0);
            if (so_in > 0.3)
            {
                _so_t += dt;
                if (_so_up > 0.0) _so_up -= dt;
                else if (_so_t > _so_next) { _so_up = randf_range(0.35, 0.6); _so_t = 0.0; _so_next = randf_range(1.1, 2.2); }
            }
            else { _so_t = 0.0; _so_up = 0.0; }
            double so_tgt = so_in * (_so_up > 0.0 ? 0.15 : 1.0);
            _so_s += (so_tgt - _so_s) * (1.0 - exp_(-(so_tgt > _so_s ? 6.0 : 8.0) * minf(dt, 0.1)));
            double fat_tgt = Math.Pow(1.0 - clampf(_num(p, "stamina", 1.0), 0.0, 1.0), 1.5) * _spr_arm;
            _fat += (fat_tgt - _fat) * (1.0 - exp_(-(fat_tgt > _fat ? 2.0 : 0.6) * minf(dt, 0.1)));
            double fat = _fat;
            double sway = Math.Sin(crank) * pedal * S("sway") * (1 + 0.9 * spr + 0.8 * eff) * lerpf(1.0, 0.55, cad_k) * hi_fade;
            double hip_rock = Math.Sin(crank) * pedal * _spr_arm * S("sway") * 0.04 * lerpf(1.0, 0.5, cad_k) * calm_k;
            double hip_tilt = Math.Sin(crank - SPR_LAG) * pedal * _spr_arm * S("sway") * 0.12 * lerpf(1.0, 0.5, cad_k) * calm_k * (1.0 + 0.6 * fat);
            double bob = Math.Sin(crank * 2) * pedal * S("sway") * S("bodyBob", 1.0) * (1 + 0.4 * spr + 0.35 * eff) * lerpf(0.4, 1.0, hi_fade);
            double wig = clampf(1 - absf(v) / 3, 0, 1) * S("sway") * S("slowWobble") * (1.0 - 0.9 * clampf(eff * 1.5, 0.0, 1.0));
            double air = _num(p, "air");
            double su_t = (1.0 - sm(SLOW_FROM, SLOW_TO, absf(v))) * (1.0 - clampf(air, 0.0, 1.0));
            slow_up += (su_t - slow_up) * (1.0 - exp_(-4.0 * minf(dt, 0.05)));
            double comp = _num(p, "compress") * S("crouch");
            double jh = minf(dt, 0.1);
            sm_pre += (clampf(_num(p, "preload"), 0.0, 1.0) - sm_pre) * (1.0 - exp_(-16.0 * jh));
            sm_ext += (clampf(_num(p, "extend") / 0.1, 0.0, 1.0) - sm_ext) * (1.0 - exp_(-22.0 * jh));
            sm_popfx += (clampf(_num(p, "popFx"), 0.0, 1.0) - sm_popfx) * (1.0 - exp_(-18.0 * jh));
            sm_squash += (clampf(_num(p, "squash"), 0.0, 1.0) - sm_squash) * (1.0 - exp_(-12.0 * jh));
            sm_lip += (clampf(_num(p, "lipK"), 0.0, 1.0) - sm_lip) * (1.0 - exp_(-8.0 * jh));
            double fold_in = clampf(_num(p, "landFold"), 0.0, 1.0);
            sm_fold += (fold_in - sm_fold) * (1.0 - exp_(-(fold_in > sm_fold ? 26.0 : 7.0) * jh));
            sm_reach += (clampf(_num(p, "landReach"), 0.0, 1.0) - sm_reach) * (1.0 - exp_(-14.0 * jh));
            double j_fold = sm_fold * S("landFold", 1.0);
            double j_pre = sm_pre * S("jumpPreload", 1.0);
            double j_ext = sm_ext * S("jumpExtend", 1.0);
            double j_sq = sm_squash * S("jumpSquash", 1.0);
            double bstick = clampf(_num(p, "bodyStick"), -1.0, 1.0);
            bstick *= 1.0 - (bstick > 0.0 ? maxf(sm_ext, sm_popfx) : 0.85 * sm_pre);
            double aero_t = clampf(bstick, 0.0, 1.0) * S("aero", 1.0);
            sm_aero += (aero_t - sm_aero) * (1.0 - exp_(-(3.0 + 12.0 * air) * minf(dt, 0.1)));
            double aero = sm_aero;
            double aero_g = aero * (1.0 - air);
            double aero_a = aero * air;
            double stk = clampf(_num(p, "speedTuck"), 0.0, 1.0) * S("speedTuckPose", 1.0);
            stk *= 1.0 - clampf(maxf(maxf(sm_pre, sm_ext), maxf(sm_popfx * air, sm_squash)) * 1.5, 0.0, 1.0);
            stk *= 1.0 - clampf(maxf(maxf(sm_reach, sm_fold), clampf(_num(p, "airPull"), 0.0, 1.0) * air) * 1.5, 0.0, 1.0);
            stk *= (1.0 - sm(0.5, 2.0, absf(_num(p, "airSpin")))) * (1.0 - clampf(_num(p, "flipExt") + _num(p, "flipArch"), 0.0, 1.0));
            stk *= 1.0 - clampf(maxf(_num(p, "tall"), _num(p, "relax")), 0.0, 1.0);
            double stk_stick = 0.0;
            if (_num(p, "tall") < 0.5)
            {
                double bb0 = clampf(-bstick, 0.0, 1.0);
                stk_stick = sm(0.05, 0.3, bb0) * (1.0 - sm(0.55, 0.95, bb0));
            }
            speed_tuck_k = stk;

            double air_tg = _num(p, "inAir") > 0.5 ? air * (1.0 - sm_reach) : 0.0;
            sm_airst += (air_tg - sm_airst) * (1.0 - exp_(-(air_tg < sm_airst ? 30.0 : 60.0) * jh));
            if (!spring_init) sm_airst = air_tg;
            double air_st = sm_airst;
            comp *= 1.0 - sm_reach * air;
            double stand = maxf(pedal, clampf(0.85 * S("attackStand"), 0.0, 1.3) * sm(0.6, 2.2, absf(v)) * (1.0 - air_st));

            // pelvis
            var pelvis = new Vec3(
                -0.16 - 0.07 * air * S("airCrouch") + 0.06 * pedal * S("standPedal") - S("standBack") * stand - comp * 0.25,
                0.80 - comp + (S("standHeight") * stand + 0.05 * spr + SLOW_TALL * slow_up * stand) * S("standPedal") + 0.035 * bob + 0.14 * aero_a - 0.07 * aero_g,
                sway * S("hipSway") + hip_rock + shift * 0.3 + Math.Sin(t * 2.1) * 0.02 * wig) + fit;
            pelvis.x += S("hipX") * (1 - 0.5 * pedal) + 0.10 * aero_a - 0.05 * aero_g - 0.03 * eff;
            pelvis.y += 0.02 * eff;
            {
                double spk = _spr_arm * (1.0 - clampf(eff, 0.0, 1.0)) * (1.0 - air);
                pelvis.x -= SPR_HIP_BACK * spk;
                pelvis.y += 0.015 * spk;
            }
            pelvis.y += S("hipY") * (1 - 0.6 * pedal);
            double air_y = (-0.07 * S("airCrouch") * (1.0 - aero) - 0.05 * sm(0.8, 3.5, absf(_num(p, "airSpin")))) * air_st * (1.0 - clampf(_num(p, "flipExt"), 0.0, 1.0));
            double j_tall = maxf(j_ext, sm_popfx * air * S("jumpExtend", 1.0));
            air_y *= 1.0 - clampf(j_tall, 0.0, 1.0);
            pelvis.y += air_y + 0.10 * sm_popfx * air;
            sm_tuck += (clampf(_num(p, "airPull"), 0.0, 1.0) * air * (1.0 - clampf(j_tall, 0.0, 1.0)) - sm_tuck) * (1.0 - exp_(-10.0 * jh));
            double j_tuck = sm_tuck * (1.0 - sm_reach) * S("airTuck", 1.0);
            tuck_out = j_tuck;
            pelvis.y -= 0.15 * j_tuck;
            pelvis.x += 0.03 * j_tuck;
            {
                double jp = j_pre * (1.0 - clampf(j_ext * 1.5, 0.0, 1.0));
                pelvis.x += -0.06 * jp + 0.10 * j_ext - 0.16 * j_sq - 0.07 * j_fold - 0.02 * sm_reach;
                pelvis.y += -0.17 * jp + 0.17 * j_ext - 0.12 * j_sq - 0.13 * j_fold + 0.09 * sm_reach;
                double j_up = sm_popfx * air;
                pelvis.x -= 0.20 * j_up; pelvis.y += 0.06 * j_up;
            }

            // chest
            double ang = 0.52 - 0.2 * clampf(-bstick, 0.0, 1.0) - S("pedalChest") * pedal + 0.12 * spr + 0.3 * eff
                + SPR_CHEST_LOW * _spr_arm * (1.0 - clampf(eff, 0.0, 1.0)) * (1.0 - air) + 0.18 * fat + 0.15 * (comp / 0.3) + 0.08 * air
                + S("lean") * (1 - 0.5 * pedal) + 0.32 * aero_a + 0.6 * aero_g;
            ang += 0.2 * clampf(-bstick, 0.0, 1.0) * stk_stick;
            ang = lerpf(ang, TUCK_ANG, stk);
            ang -= FLIP_LEAN * clampf(_num(p, "flipArch"), 0.0, 1.0);
            ang += 0.22 * (1.0 - clampf(j_ext * 1.5, 0.0, 1.0)) * j_pre - 0.3 * j_ext + 0.38 * j_sq - 0.35 * sm_popfx * air + (-0.22) * sm_popfx * air + 0.28 * j_tuck + 0.42 * j_fold - 0.18 * sm_reach;
            double spin_style = sm(0.8, 3.5, absf(_num(p, "airSpin"))) * air * (1.0 - clampf(_num(p, "flipExt"), 0.0, 1.0));
            ang = lerpf(ang, 0.42, 0.7 * spin_style);
            double relax = clampf(_num(p, "relax"), 0.0, 1.0);
            ang = lerpf(ang, 0.22, 0.8 * relax);
            double tall = clampf(_num(p, "tall"), 0.0, 1.0);
            ang = lerpf(ang, 0.0, tall);
            // breathing
            double wind_tgt = clampf(maxf(maxf((_num(p, "hr", 72.0) - 80.0) / 95.0, 1.0 - _num(p, "stamina", 1.0)), 0.6 * _spr_arm), 0.0, 1.0);
            _winded += (wind_tgt - _winded) * (1.0 - exp_(-(wind_tgt > _winded ? 1.5 : 0.08) * minf(dt, 0.1)));
            double br_hz = lerpf(0.25, 0.9, _winded);
            double cad_hz = _cad_s / 60.0;
            if (_winded > 0.45 && cad_hz > 0.8)
            {
                double n = maxf(1.0, round(cad_hz / br_hz));
                br_hz = lerpf(br_hz, cad_hz / n, 0.5 * sm(0.45, 0.8, _winded));
            }
            _breath_ph = fposmod(_breath_ph + dt * TAU * br_hz, TAU);
            double still = 1.0 - sm(1.0, 4.0, absf(v));
            double heave = 1.0 + 1.2 * _winded * (1.0 - clampf(absf(v) / 4.0, 0.0, 1.0));
            _inhale = maxf(0.0, Math.Sin(_breath_ph)) * sm(0.25, 0.8, _winded) * still * (1.0 - air);
            double br_ang = -Math.Sin(_breath_ph) * lerpf(0.022, 0.045, _winded) * heave * still * (1.0 - air);
            double L = S("torso");
            var chest = new Vec3(
                pelvis.x + Math.Sin(ang + br_ang) * L + 0.03 * pedal * (0.5 + 0.5 * bob),
                pelvis.y + Math.Cos(ang + br_ang) * L,
                pelvis.z + shift * 0.3 - sway * S("hipSway") - 0.7 * hip_rock + Math.Sin(t * 1.7 + 1.0) * 0.02 * wig);

            pelvis.z += S("hipZ");
            chest += new Vec3(S("chestFwd"), S("chestUp"), S("chestSide"));

            double absorb = _num(p, "absorb");
            double fs_k = sm(0.25, 0.55, clampf(wrapf(_num(p, "pitch"), -PI, PI), 0.0, 1.2)) * (1.0 - sm(6.5, 9.5, absf(_num(p, "v"))));
            if (absorb < 0.0) absorb *= 1.0 - (1.0 - FACE_SINK) * clampf(sm_lip, 0.0, 1.0) * (1.0 - air) * fs_k;
            absorb = lerpf(absorb, maxf(absorb, 0.08), j_ext);
            double deep_c = comp + maxf(0.0, -absorb) + 0.09 * j_fold - (0.22 + 0.10 * clampf(j_fold * 1.5, 0.0, 1.0));
            if (deep_c > 0.0) absorb += deep_c;
            pelvis.y += absorb;
            chest.y += absorb * 0.9;
            chest.y -= 0.05 * j_fold;
            double by_k = sm(0.03, 0.10, -absorb);
            _abs_p = absorb * by_k;
            _abs_c = absorb * 0.9 * by_k;
            _sink = clampf(-absorb - 0.04, 0.0, 0.3);
            pelvis.x -= 0.45 * _sink; chest.x -= 0.2 * _sink;
            double hs = _num(p, "hipShift");
            if (hs < 0.0) hs *= 1.0 - 0.75 * sm_pre;
            pelvis.x += hs * (hs > 0.0 ? 1.0 - 0.7 * aero_g : 1.0);
            chest.x += hs * 0.6;
            double bs = bstick;
            if (bs < 0.0) bs *= 1.0 - stk_stick;
            double back_k = clampf(-bs, 0.0, 1.0);
            pelvis.x -= TUCK_HIP_BACK * stk; pelvis.y -= TUCK_HIP_DOWN * stk;
            chest.x -= TUCK_HIP_BACK * stk; chest.y -= TUCK_HIP_DOWN * stk;
            chest.x -= 0.06 * back_k;
            double lat = clampf(_num(p, "bodyLat"), -1.0, 1.0);
            {
                double g_l = 1.0 - air;
                pelvis.z += lat * (0.07 * 0.4 * air - LAT_HIP * g_l);
                chest.z += lat * (0.035 * air - LAT_CHEST * g_l);
                chest.y -= LAT_DROP * absf(lat) * g_l;
            }
            pelvis.y -= 0.12 * absf(lat) * air;
            if (bs < 0.0)
            {
                pelvis += new Vec3(0.04, 0.09, 0.0) * bs;
                chest += new Vec3(0.0, 0.03, 0.0) * bs;
            }
            double pitch0 = wrapf(_num(p, "pitch"), -PI, PI);
            double lip_lv = clampf(maxf(sm_lip * (1.0 - air), sm_popfx * air), 0.0, 1.0);
            pitch0 *= 1.0 - sm(lerpf(0.7, 1.15, lip_lv), lerpf(1.3, 1.6, lip_lv), absf(pitch0));
            double h0 = minf(dt, 0.1);
            if (!spring_init) sm_pitch0 = pitch0;
            double dp0 = (pitch0 - sm_pitch0) * (1.0 - exp_(-12.0 * h0));
            sm_pitch0 += clampf(dp0, -PITCH_LEVEL_RATE * h0, PITCH_LEVEL_RATE * h0);
            pitch0 = sm_pitch0;
            bool has_slope = p.has("slope");
            double slope0 = has_slope ? clampf(_num(p, "slope", pitch0), -1.3, 1.3) : pitch0;
            double raw_p = wrapf(_num(p, "pitch"), -PI, PI);
            double wh_t = has_slope ? clampf(raw_p - slope0, 0.0, 1.1) * (1.0 - clampf(air * 3.0, 0.0, 1.0)) : 0.0;
            if (wh_t < 0.08) wh_t = 0.0;
            if (p.has("frontUp")) wh_t *= sm(0.02, 0.1, _num(p, "frontUp"));
            sm_wheelie = move_toward(sm_wheelie, wh_t, 2.5 * minf(dt, 0.1));
            double wheelie = sm_wheelie;
            double baseP = pitch0 - wheelie;
            double pit = baseP * (baseP > 0 ? 0.2 : _num(p, "bodyLevel", 0.85)) + wheelie * 0.75;
            double face_k = has_slope ? sm(0.1, 0.4, sm_lip) * sm(0.04, 0.15, slope0) : 0.0;
            double rel_p = wrapf(raw_p - slope0 * face_k, -PI, PI);
            if (!spring_init) sm_pitch_slow = rel_p;
            sm_pitch_slow += wrapf(rel_p - sm_pitch_slow, -PI, PI) * (1.0 - exp_(-(3.0 + 30.0 * air) * h0));
            double kick_r = wrapf(rel_p - sm_pitch_slow, -PI, PI);
            double kick = 0.4 * Math.Tanh(kick_r / 0.4) * (1.0 - air) * (1.0 - sm(0.7, 1.3, absf(raw_p)));
            bump_pitch = kick;
            double at = _num(p, "airTilt");
            if (at != 0.0)
            {
                pit += at;
                pelvis.x -= clampf(-at, 0.0, 0.6) * 0.12;
                chest.y -= absf(at) * 0.05;
            }
            if (pit != 0.0)
            {
                double c = Math.Cos(-pit), sn = Math.Sin(-pit), y0 = 0.3;
                pelvis = RotPitch(pelvis, c, sn, y0);
                chest = RotPitch(chest, c, sn, y0);
                double down = maxf(0.0, -baseP);
                double drop = _num(p, "attackDrop", 0.18);
                pelvis.y -= down * drop;
                pelvis.x -= down * drop * 0.45;
            }
            _face_k = 0.0;
            double climb = clampf(slope0, 0, 0.6) * (1.0 - 0.85 * sm_lip);
            if (wheelie > 0.0)
            {
                pelvis.x -= 0.15 * wheelie; pelvis.y -= 0.06 * wheelie;
                chest.x -= 0.27 * wheelie; chest.y -= 0.03 * wheelie;
            }
            if (climb > 0)
            {
                pelvis.x += climb * 0.22; pelvis.y -= climb * 0.04;
                chest.x += climb * 0.42; chest.y -= climb * 0.24;
            }
            // the body's own roll
            double bl = _num(p, "lean") - _num(p, "rockRoll");
            double c_cap = lerpf(0.85, AIR_COUNTER, air);
            double roll_t = bl - clampf(_num(p, "counter"), -c_cap, c_cap);
            double hr = minf(dt, 0.05);
            if (!roll_init) { roll_p = roll_t; roll_c = roll_t; roll_pv = 0.0; roll_cv = 0.0; knee_lean = bl; roll_init = true; }
            double fol = clampf(S("leanFollow", 1.0), 0.3, 3.0);
            double swing = clampf(S("leanSwing", 1.0), 0.0, 2.0);
            double hw = ROLL_HIP_W * fol, cw = ROLL_CHEST_W * fol;
            double hz = lerpf(1.0, ROLL_HIP_Z, minf(swing, 1.0)) - 0.2 * maxf(swing - 1.0, 0.0);
            double cz = lerpf(1.0, ROLL_CHEST_Z, minf(swing, 1.0)) - 0.2 * maxf(swing - 1.0, 0.0);
            {
                var rp = spring_exact(roll_p, roll_pv, roll_t, hw * hw, 2.0 * hz * hw, 0.0, hr);
                roll_p = rp.x; roll_pv = rp.y;
                var rc = spring_exact(roll_c, roll_cv, roll_t, cw * cw, 2.0 * cz * cw, 0.0, hr);
                roll_c = rc.x; roll_cv = rc.y;
            }
            knee_lean += (bl - knee_lean) * (1.0 - exp_(-7.0 * hr));
            double live = clampf(S("leanLively", 1.0), 0.0, 3.0) * (1.0 - air);
            double in_turn = sm(0.08, 0.5, absf(bl)) * live;
            roll_pv += (0.022 * Math.Sin(t * 1.9 + 0.7) + 0.014 * Math.Sin(t * 3.3 + 2.1) + 0.008 * Math.Sin(t * 5.7)) * in_turn * hw * hw * 0.6 * S("leanBalance", 1.0) * hr;
            roll_pv -= _facc * Math.Sin(bl) * 0.15 * live * S("leanBumps", 1.0) * hr;
            lat_g_s += (clampf(absf(_num(p, "latG")), 0.0, 1.5) - lat_g_s) * (1.0 - exp_(-5.0 * hr));
            double sink = sm(0.1, 1.0, lat_g_s) * live * S("leanLoad", 1.0);
            pelvis.y -= 0.03 * sink;
            chest.y -= 0.035 * sink;
            chest.x += 0.02 * sink;
            double hip_cap = lerpf(0.85, AIR_HIP_ROLL, air);
            double ch_cap = lerpf(0.95, AIR_COUNTER, air);
            double cr = clampf(bl - roll_p, -hip_cap, hip_cap);
            double cr_c = clampf(bl - roll_c, -ch_cap, ch_cap);
            double unweight = ROLL_UNWEIGHT * S("leanUnweight", 1.0) * clampf(absf(roll_pv) / 1.6, 0.0, 1.0) * (1.0 - sm(0.15, 0.6, absf(roll_p))) * (1.0 - air);
            pelvis.y += unweight; chest.y += unweight * 0.8;
            double re = absf(roll_pv);
            flow_e = re > flow_e ? maxf(re, flow_e - hr * 2.0) : flow_e + (re - flow_e) * (1.0 - exp_(-1.6 * hr));
            double settle = clampf(flow_e / 1.6, 0.0, 1.0) * sm(0.15, 0.5, absf(roll_p)) * clampf(1.0 - re / 2.5, 0.0, 1.0) * (1.0 - air);
            double fsink = 0.04 * settle * S("flowSink", 1.0);
            pelvis.y -= fsink; chest.y -= fsink * 0.9; chest.x += fsink * 0.4;
            double air_piv = air;
            bool air_hip_piv = air > 0.0;
            if (air_hip_piv)
            {
                cr *= lerpf(1.0, AIR_HIP_SHARE, air);
                double cc_air = lerpf(ch_cap, AIR_CHEST_CAP, air);
                cr_c = clampf(cr_c, -cc_air, cc_air);
                air_piv = 0.0;
            }
            Vec3 pel0 = pelvis, ch0 = chest;
            double roll_piv = lerpf(0.3, SLOW_PIVOT, slow_up);
            _roll_dp = Vec3.ZERO; _roll_dc = Vec3.ZERO;
            if (cr != 0.0 || cr_c != 0.0)
            {
                double c = Math.Cos(cr), sn = Math.Sin(cr), y0 = roll_piv;
                double dy = pelvis.y - y0, dz = pelvis.z;
                pelvis.y = y0 + dy * c - dz * sn;
                pelvis.z = dy * sn + dz * c;
                c = Math.Cos(cr_c); sn = Math.Sin(cr_c);
                dy = chest.y - y0; dz = chest.z;
                chest.y = y0 + dy * c - dz * sn;
                chest.z = dy * sn + dz * c;
                double g_k = 1.0 - clampf(air, 0.0, 1.0);
                if (g_k > 0.0)
                {
                    var pel_g = new Vec3(pelvis.x, pelvis.y, clampf(pelvis.z, -HIP_SIDE, HIP_SIDE));
                    Vec3 ch_g = pel_g + Basis.axis_angle(Vec3.RIGHT, cr_c) * (ch0 - pel0);
                    pelvis = pelvis.lerp(pel_g, g_k);
                    chest = chest.lerp(ch_g, g_k);
                }
                if (air_piv > 0.0)
                {
                    double ty = pel0.y - ch0.y, tz = pel0.z - ch0.z;
                    double ca = Math.Cos(cr_c), sa = Math.Sin(cr_c);
                    Vec3 ch_a = ch0 + new Vec3(0.0, 0.0, 0.08 * Math.Sin(cr_c));
                    var pel_a = new Vec3(pel0.x, ch_a.y + ty * ca - tz * sa, ch_a.z + ty * sa + tz * ca);
                    pelvis = pelvis.lerp(pel_a, air_piv);
                    chest = chest.lerp(ch_a, air_piv);
                }
                if (air_hip_piv)
                {
                    double ca2 = Math.Cos(cr_c), sa2 = Math.Sin(cr_c);
                    double ty2 = ch0.y - pel0.y, tz2 = ch0.z - pel0.z;
                    Vec3 ch_h = pelvis + new Vec3(ch0.x - pel0.x, ty2 * ca2 - tz2 * sa2, ty2 * sa2 + tz2 * ca2);
                    chest = chest.lerp(ch_h, air);
                }
                _roll_dp = pelvis - pel0; _roll_dc = chest - ch0;
                double crk = sm(0.1, 0.7, absf(cr)) * (1.0 - air) * S("turnLow") * S("cornerCrouch", 1.0) * (1.0 - slow_up);
                pelvis.y -= CORNER_HIP * crk;
                chest.y -= CORNER_CHEST * crk;
                chest.x += 0.04 * crk;
            }
            double awh_pos = clampf(_num(p, "airWhip"), -1.4, 1.4) * air * AIR_FACE;
            if (absf(awh_pos) > 1e-3)
            {
                chest = pelvis + Basis.axis_angle(Vec3.UP, -awh_pos) * (chest - pelvis);
                chest.x += absf(cr) * 0.05;
            }
            // stops
            double dab = clampf(_num(p, "dab"), 0, 1);
            double st_w = clampf(_num(p, "stopStand"), 0.0, 1.0);
            double si_w = clampf(_num(p, "stopSit"), 0.0, 1.0);
            _stop_long = maxf(st_w, si_w);
            if ((st_w > 0.0 || si_w > 0.0) && seat != null)
            {
                if (st_w > 0.0)
                {
                    Vec3 fl = p.vec("footL", Vec3.ZERO), fr = p.vec("footR", Vec3.ZERO);
                    var pt = new Vec3(seat[2] + STOP_HIP_FWD, (fl.y + fr.y) * 0.5 + 0.12 + (L_THIGH + L_SHIN) * STOP_LEG, 0.0);
                    pelvis = pelvis.lerp(pt, st_w);
                    chest = chest.lerp(pt + new Vec3(Math.Sin(STOP_TORSO), Math.Cos(STOP_TORSO), 0.0) * S("torso"), st_w);
                }
                if (si_w > 0.0)
                {
                    var ps = new Vec3((seat[1] + seat[2]) * 0.5, seat[0] + 0.09, 0.0);
                    pelvis = pelvis.lerp(ps, si_w);
                    chest = chest.lerp(ps + new Vec3(Math.Sin(SIT_TORSO), Math.Cos(SIT_TORSO), 0.0) * S("torso"), si_w);
                }
            }
            if (dab > 0.0)
            {
                double ds = signf(_num(p, "dabSide", -1.0));
                double a = -ds * (_num(p, "dabLean") * 0.8 + _num(p, "dabLeanVar")) * dab;
                double c = Math.Cos(a), sn = Math.Sin(a);
                double y0 = lerpf(0.3, pelvis.y, si_w);
                double z0 = pelvis.z * si_w;
                double dy = pelvis.y - y0, dz = pelvis.z - z0;
                pelvis.y = y0 + dy * c - dz * sn;
                pelvis.z = z0 + dy * sn + dz * c;
                dy = chest.y - y0; dz = chest.z - z0;
                chest.y = y0 + dy * c - dz * sn;
                chest.z = z0 + dy * sn + dz * c;
                double free_k = 1.0 - maxf(st_w, si_w);
                pelvis.z += ds * 0.04 * dab * free_k;
                pelvis.y -= 0.05 * dab * free_k;
                chest.y -= 0.03 * dab * free_k;
            }
            if (S("seatFloor") != 0.0 && seat != null)
            {
                double over = clampf((pelvis.x - (seat[1] - 0.18)) / 0.08, 0, 1) * (1.0 - st_w);
                double floor_y = seat[0] + 0.085 - 0.3 * _sink;
                floor_y -= 0.14 * j_pre * (1.0 - clampf(j_ext * 1.5, 0.0, 1.0)) * (1.0 - air);
                if (pelvis.y < floor_y) pelvis.y += (floor_y - pelvis.y) * over;
                if (chest.y < pelvis.y + 0.15) chest.y = pelvis.y + 0.15;
            }
            bool standing = _num(p, "stand") > 0.5;
            if (standing)
            {
                Vec3 fl = p.vec("footL", Vec3.ZERO), fr = p.vec("footR", Vec3.ZERO);
                double ank_x = (fl.x + fr.x) * 0.5 - 0.04 + S("heelFwd");
                double ank_y = (fl.y + fr.y) * 0.5 + 0.12 + S("heelUp");
                pelvis = new Vec3(ank_x + 0.01, ank_y + (L_THIGH + L_SHIN) * 0.985 + 0.02 + absorb, (fl.z + fr.z) * 0.5);
                chest = pelvis + new Vec3(Math.Sin(0.05) * S("torso"), Math.Cos(0.05) * S("torso"), 0.0);
                ang = 0.05;
                double arm = L_UARM + L_FARM;
                p = new PoseInput(p);
                for (int si = 0; si < 2; si++)
                {
                    double sd = si == 0 ? -1.0 : 1.0;
                    Vec3 sh = chest + new Vec3(-SHOULDER_BACK, -SHOULDER_DOWN, sd * S("shoulders"));
                    p[sd < 0 ? "handL" : "handR"] = sh + new Vec3(0.07, -arm * 0.95, sd * 0.07);
                }
            }
            if (lip_lv > 0.0 && p.has("footL"))
            {
                Vec3 bbp = (p.vec("footL", Vec3.ZERO) + p.vec("footR", Vec3.ZERO)) * 0.5;
                double steep_k = sm(0.25, 0.55, clampf(raw_p, 0.0, 1.2)) * (1.0 - sm(6.5, 9.5, absf(v)));
                double fk = FACE_POSE * sm(0.1, 0.45, lip_lv) * (1.0 - clampf(j_sq * 1.5, 0.0, 1.0)) * steep_k;
                _face_k = fk;
                double pp = clampf(raw_p, 0.0, 1.2);
                var fhw = new Vec2(FACE_HIP.x, FACE_HIP.y - 0.05 * j_pre + 0.06 * sm_popfx * air);
                var ph_t = new Vec2(bbp.x + fhw.x * Math.Cos(pp) + fhw.y * Math.Sin(pp), bbp.y - fhw.x * Math.Sin(pp) + fhw.y * Math.Cos(pp));
                double ta = pp + FACE_TORSO - FLIP_LEAN * clampf(_num(p, "flipArch"), 0.0, 1.0);
                Vec2 ch_t = ph_t + new Vec2(Math.Sin(ta), Math.Cos(ta)) * S("torso");
                pelvis.x = lerpf(pelvis.x, ph_t.x, fk); pelvis.y = lerpf(pelvis.y, ph_t.y, fk);
                chest.x = lerpf(chest.x, ch_t.x, fk); chest.y = lerpf(chest.y, ch_t.y, fk);
            }
            {
                _constrain(ref pelvis, ref chest, p, standing, aero);
            }
            if (spring_init)
            {
                pel_s += _roll_dp - _roll_dp_prev;
                ch_s += _roll_dc - _roll_dc_prev;
            }
            _roll_dp_prev = _roll_dp; _roll_dc_prev = _roll_dc;
            if (!spring_init)
            {
                pel_s = pelvis; ch_s = chest;
                pel_s.y -= _abs_p; ch_s.y -= _abs_c;
                spring_init = true;
            }
            double h = minf(dt, 0.05);
            double bump_k = S("bumpAbsorb", 2.0) * (1.0 - air);
            double fy0 = _num(p, "frameY", double.NaN);
            double gy = (!double.IsNaN(fy0) ? fy0 : 0.0) * 0.85 + _num(p, "wheelY") * 0.15;
            double acc = 0.0;
            if (!double.IsNaN(_fy_prev) && absf(gy - _fy_prev) > 1.0) { _fy_prev = double.NaN; _fv_prev = double.NaN; }
            if (h > 1e-4 && !double.IsNaN(_fy_prev))
            {
                double vy_f = (gy - _fy_prev) / h;
                if (!double.IsNaN(_fv_prev)) acc = clampf((vy_f - _fv_prev) / h, -80.0, 80.0);
                _fv_prev = vy_f;
            }
            _fy_prev = gy;
            _facc += (acc - _facc) * (1.0 - exp_(-40.0 * h));
            double zeta = clampf(S("bodyBounce", 0.4), 0.15, 1.0);
            double ky = clampf(S("hipSteady"), 20.0, 600.0);
            pelvis.y -= _abs_p;
            pel_s = _spring3(pel_s, pel_v, pelvis, 260.0, ky, zeta, -_facc * bump_k, h);
            pel_v = _spring3_v;
            pel_s.y = clampf(pel_s.y, pelvis.y - 0.14, pelvis.y + 0.05);
            pelvis.y += _abs_p; pel_s.y += _abs_p;
            pelvis = pel_s;
            pel_s.y -= _abs_p;
            chest.y -= _abs_c;
            ch_s = _spring3(ch_s, ch_v, chest, 200.0, ky * CHEST_KY, zeta, -_facc * bump_k * 0.85 * CHEST_PUSH, h);
            ch_v = _spring3_v;
            ch_s.y = clampf(ch_s.y, chest.y - 0.14, chest.y + 0.06);
            chest.y += _abs_c; ch_s.y += _abs_c;
            chest = ch_s;
            ch_s.y -= _abs_c;
            {
                Vec3 sp0 = pelvis, sp1 = chest;
                _constrain(ref sp0, ref sp1, p, standing, aero);
                Vec3 dpel = sp0 - pelvis, dch = sp1 - chest;
                if (dpel.length_squared() > 1e-10)
                {
                    Vec3 n = dpel.normalized();
                    pel_v -= n * minf(0.0, pel_v.dot(n));
                    pel_s += dpel;
                }
                if (dch.length_squared() > 1e-10)
                {
                    Vec3 n = dch.normalized();
                    ch_v -= n * minf(0.0, ch_v.dot(n));
                    ch_s += dch;
                }
                pelvis = pel_s; chest = ch_s;
                pelvis.y += _abs_p; chest.y += _abs_c;
            }
            // pedalling rock: undo the bike's rock for hips and chest about the tyres' contact line
            double rr = _num(p, "rockRoll") * S("upright");
            if (rr != 0.0)
            {
                double c = Math.Cos(rr), sn = Math.Sin(rr);
                double dy = pelvis.y, dz = pelvis.z;
                pelvis.y = dy * c - dz * sn;
                pelvis.z = dy * sn + dz * c;
                dy = chest.y; dz = chest.z;
                if (_spr_arm > 0.0)
                {
                    double hr2 = -rr * SPR_HIP_ROCK * _spr_arm * (1.0 - air);
                    double py = pelvis.y, pz = pelvis.z;
                    pelvis.y = py * Math.Cos(hr2) - pz * Math.Sin(hr2);
                    pelvis.z = py * Math.Sin(hr2) + pz * Math.Cos(hr2);
                }
                chest.y = dy * c - dz * sn;
                chest.z = dy * sn + dz * c;
            }
            double kp = bump_pitch * clampf(_num(p, "bumpPitch", 0.85), 0.0, 1.0);
            if (kp != 0.0)
            {
                double kc = Math.Cos(kp), ks = Math.Sin(kp);
                double kdy = pelvis.y - 0.3, kdx = pelvis.x;
                pelvis.x = kdx * kc + kdy * ks;
                pelvis.y = 0.3 - kdx * ks + kdy * kc;
                kdy = chest.y - 0.3; kdx = chest.x;
                chest.x = kdx * kc + kdy * ks;
                chest.y = 0.3 - kdx * ks + kdy * kc;
            }
            _constrain(ref pelvis, ref chest, p, standing, aero);
            // Pose Lab keys
            var pk = p.get("pk") as Dictionary<string, double>;
            double PK(string key) => pk != null && pk.TryGetValue(key, out var pv) ? pv : 0.0;
            _pk_tyaw = PK("torso_yaw"); _pk_hp = PK("head_pitch"); _pk_hy = PK("head_yaw");
            _pk_eo = PK("elbows_out"); _pk_ko = PK("knees_out");
            _pk_wb = PK("wrist_bend"); _pk_wt = PK("wrist_turn");
            _pk_grip = PK("grip"); _pk_lp = PK("lever_pull");
            if (pk != null && pk.Count > 0)
            {
                var hipd = new Vec3(PK("hip_x"), PK("hip_y"), PK("hip_z"));
                pelvis += hipd; chest += hipd;
                Vec3 tv = chest - pelvis;
                tv = Basis.axis_angle(new Vec3(0, 0, 1), -PK("torso_pitch")) * tv;
                tv = Basis.axis_angle(new Vec3(1, 0, 0), PK("torso_roll")) * tv;
                chest = pelvis + tv;
                _constrain(ref pelvis, ref chest, p, standing, aero);
            }
            // motion cap
            double vcap = _num(p, "torsoVmax", TORSO_VMAX) * clampf(dt, 0.0, 0.05);
            if (_cap_ok && vcap > 0.0)
            {
                for (int which = 0; which < 2; which++)
                {
                    Vec3 cur = which == 0 ? pelvis : chest;
                    Vec3 prev = which == 0 ? _cap_pel : _cap_ch;
                    Vec3 dmv = cur - prev;
                    double dl = dmv.length();
                    if (dl > vcap && dl < 0.4)
                    {
                        cur = prev + dmv / dl * vcap;
                        if (which == 0) pelvis = cur; else chest = cur;
                    }
                }
            }
            _cap_pel = pelvis; _cap_ch = chest; _cap_ok = true;
            if (air > 0.5 && _num(p, "inAir") > 0.5)
            {
                if (!_air_ref_ok) { _air_ref = new Vec2(pelvis.x, pelvis.y); _air_ref_ok = true; }
                body_off = new Vec2(pelvis.x, pelvis.y) - _air_ref;
            }
            else
            {
                _air_ref_ok = false;
                body_off = body_off.move_toward(Vec2.ZERO, 1.5 * minf(dt, 0.1));
            }
            // torso from pelvis to chest
            var hip = new Vec3(pelvis.x, pelvis.y + 0.02, pelvis.z);
            Vec3 tw_axis = (chest - hip).normalized();
            double turn = clampf(_num(p, "turn"), -3.0, 3.0);
            sm_turn += (turn - sm_turn) * (1.0 - exp_(-8.0 * minf(dt, 0.1)));
            double tab = clampf(_num(p, "bodyLat"), -1.0, 1.0) * air;
            double lead = clampf(0.3 * clampf(_num(p, "lean") - _num(p, "rockRoll") - clampf(_num(p, "counter"), -0.85, 0.85), -0.9, 0.9) + 0.06 * roll_pv, -0.35, 0.35) * S("flowLead", 1.0) * (1.0 - air);
            double awhip = clampf(_num(p, "airWhip"), -1.4, 1.4) * air;
            double tw_k = 0.07;
            lead = clampf(lead, -0.18, 0.18);
            double tw_cap = lerpf(0.3, 0.6, air);
            double tw_base = _pk_tyaw + S("twist") + clampf(_num(p, "airSpin") * 0.07 + sm_turn * tw_k * S("turnTwist") + lead, -tw_cap, tw_cap) + _num(p, "flipTwist");
            double tw_air = -0.22 * tab - 0.85 * awhip;
            tw_base += _num(p, "lookTwist");
            tw_base += SPR_PULL_TWIST * 0.5 * (_arm_pull[1] - _arm_pull[0]) * (1.0 - air);
            Basis tw = Basis.axis_angle(tw_axis, tw_base + tw_air);
            double roll_fix = 1.0 - air;
            if (roll_fix > 0.0) tw = Basis.axis_angle(Vec3.RIGHT, cr_c * roll_fix) * tw;
            _body_roll = cr_c * roll_fix;
            object hl0 = p.get("handL"), hr0 = p.get("handR");
            if (absf(tw_air) > 1e-3 && hl0 is Vec3 hl0v && hr0 is Vec3 hr0v && !standing)
            {
                double reach_max = (L_UARM + L_FARM) * 0.99;
                for (int it = 0; it < 6; it++)
                {
                    bool ok = true;
                    for (int si = 0; si < 2; si++)
                    {
                        double sd2 = si == 0 ? -1.0 : 1.0;
                        Vec3 tgt2 = si == 0 ? hl0v : hr0v;
                        var so2 = new Vec3(-SHOULDER_BACK + S("shoulderFwd"), -SHOULDER_DOWN + S("shoulderUp"), sd2 * S("shoulders"));
                        Vec3 sh2 = (chest + tw * so2).lerp(shoulder_at(pelvis, chest, tw, so2), air);
                        if (sh2.distance_to(tgt2) > reach_max) ok = false;
                    }
                    if (ok) break;
                    tw_air *= 0.7;
                    tw = Basis.axis_angle(tw_axis, tw_base + tw_air);
                }
            }
            Basis pel_b = Basis.axis_angle(Vec3.UP, S("pelvisYaw") + clampf(sm_turn * 0.07 * S("turnHips"), -0.4, 0.4) + 0.3 * tab - 0.4 * awhip)
                * Basis.axis_angle(Vec3.RIGHT, S("pelvisRoll") - clampf(sm_turn * 0.04 * S("turnHips"), -0.25, 0.25) + hip_tilt);
            double t_act = Math.Atan2(chest.x - pelvis.x, maxf(0.05, chest.y - pelvis.y));
            double p_tilt = lerpf(ang * 0.3, t_act * 0.85, _face_k);
            Basis pel_full = pel_b * Basis.axis_angle(Vec3.BACK, -p_tilt - S("pelvisTilt"));
            hip = pelvis + pel_full.y * HEM_Y;
            double bend = clampf((roll_c - roll_p) * 0.6, -0.2, 0.2) * S("flowBend", 1.0) * (1.0 - air);
            set_spine(hip, chest, pel_b * new Vec3(0, 0, 1), tw * new Vec3(0, 0, 1),
                S("spineCurve") * (1.0 - 0.7 * relax) * (1.0 - _face_k) - FLIP_ARCH * clampf(_num(p, "flipArch"), 0.0, 1.0), S("spineSide") + bend, S("spineLow"), pel_full, true);
            pelvis_xf = new Xf(pel_full, pelvis);

            // neck / head
            Vec3 neck = chest;
            var head_p = new Vec3(neck.x + HEAD_FWD + S("lookAhead") + 0.04 * aero + TUCK_HEAD.x * speed_tuck_k, neck.y + HEAD_UP + S("neck") + TUCK_HEAD.y * speed_tuck_k, neck.z);
            double steady = clampf(S("headSteady", 1.0), 0.0, 2.0) * (standing ? 0.0 : 1.0);
            double flip_k = 1.0 - sm(0.7, 1.3, absf(raw_p));
            double hdt = clampf(dt, 0.0, 0.1);
            if (!_hp_init)
            {
                _hp_s = raw_p; _hp_v = 0.0; _yr_s = _num(p, "yawRate"); _yr_v = 0.0; _hy = 0.0;
                _neck_d = Vec3.ZERO; _neck_v = Vec3.ZERO; _hp_init = true;
            }
            var hps = crit_spring(_hp_s, _hp_v, _hp_s + wrapf(raw_p - _hp_s, -PI, PI), HEAD_PITCH_HL, hdt);
            _hp_s = wrapf(hps.x, -PI, PI); _hp_v = hps.y;
            if (absf(wrapf(raw_p - _hp_s, -PI, PI)) > 0.9) { _hp_s = raw_p; _hp_v = 0.0; }
            double head_kick = clampf(wrapf(raw_p - _hp_s, -PI, PI), -0.45, 0.45) * flip_k * steady;
            double yr = _num(p, "yawRate");
            var yrs = crit_spring(_yr_s, _yr_v, yr, HEAD_YAW_HL, hdt);
            _yr_s = yrs.x; _yr_v = yrs.y;
            _hy -= (yr - _yr_s) * hdt;
            _hy *= Math.Pow(0.5, hdt / HEAD_YAW_HL);
            _hy = clampf(_hy, -0.3, 0.3);
            double head_yaw_hold = _hy * steady * (1.0 - air);
            if (hdt > 0.0)
            {
                int nsub = (int)Math.Ceiling(hdt * 240.0);
                double nh = hdt / nsub;
                for (int i = 0; i < nsub; i++)
                {
                    _neck_v += (-_neck_d * (NECK_W * NECK_W) - _neck_v * (2.0 * NECK_Z * NECK_W)) * nh;
                    _neck_v.y -= _facc * (1.0 - air) * nh;
                    _neck_d += _neck_v * nh;
                }
                _neck_d = _neck_d.clamp(-NECK_MAX, NECK_MAX);
            }
            head_p += _neck_d * minf(steady, 1.0);
            J[0] = head_p; J[1] = chest; J[2] = pelvis;
            double yaw = clampf((_num(p, "steer") * 1.2 + _num(p, "yawRate") * 0.15) * S("headTurn") + lead * 0.8, -0.8, 0.8) + S("headYaw") + _num(p, "lookYaw") - 0.95 * awhip + head_yaw_hold + _pk_hy;
            double rx = (p.get("headRoll") != null ? _num(p, "headRoll") : _num(p, "lean") * 0.6) + S("headRoll") + _num(p, "rockRoll") * minf(steady, 1.0);
            double rz = -0.12 * (ang - 0.72) + 0.04 * Math.Sin(t * 3.3) * wig - S("headTilt") * (1.0 - 0.6 * relax) + 0.12 * tall + _num(p, "lookPitch") - head_kick - _pk_hp - maxf(SPR_HEAD_DOWN * _hd_s, SPIN_LOOK_DOWN * _so_s);
            if (!standing)
            {
                Vec3 sp_v = chest - hip;
                double a_sp = Math.Atan2(sp_v.z, maxf(0.05, sp_v.y));
                double rel = wrapf(rx - a_sp, -PI, PI);
                double rel_c = NECK_ROLL * Math.Tanh(rel / NECK_ROLL);
                rx = a_sp + rel_c;
                Vec3 nd = head_p - chest;
                head_p = chest + Basis.axis_angle(Vec3.RIGHT, a_sp + NECK_BEND * rel_c) * nd;
                J[0] = head_p;
            }
            head = new Xf(Basis.euler_xyz(rx, yaw, rz), head_p);

            Vec3 right = new Vec3(0, 0, 1);
            double max_turn = dt > 0.0 ? BEND_RATE * minf(dt, 0.1) : PI;
            var bb = Vec2.ZERO;
            object fL0 = p.get("footL"), fR0 = p.get("footR");
            if (fL0 is Vec3 fl0 && fR0 is Vec3 fr0) bb = new Vec2((fl0.x + fr0.x) * 0.5, (fl0.y + fr0.y) * 0.5);
            pedal_top = clampf(_num(p, "pedalTop", 0.017), 0.0, 0.05);
            double dab_w = clampf(_num(p, "dab"), 0.0, 1.0);
            double ank_k = clampf(S("ankling", 1.0), 0.0, 2.5) * (standing ? 0.0 : 1.0);
            double heels = clampf(S("heelsDown", 1.0), 0.0, 2.5) * (standing ? 0.0 : 1.0);
            double ank_swing = ANKLE_SWING * pedal * (1.0 - 0.7 * air) * ank_k * (1.0 + 0.5 * _spr_arm);
            double ank_bias = -0.07 * spr * pedal * ank_k
                + heels * (0.12 * stand * (1.0 - pedal) * (1.0 - air) + 0.15 * j_fold + 0.25 * clampf(comp, 0.0, 0.3) + 0.06 * sm_reach);
            for (int i = 0; i < 2; i++)
            {
                double side = i == 0 ? -1.0 : 1.0;
                Vec3 foot = p.vec(i == 0 ? "footL" : "footR", Vec3.ZERO);
                foot.z += side * S("footSlide");
                Vec3 hand = p.vec(i == 0 ? "handL" : "handR", Vec3.ZERO);
                // leg
                Vec3 hp = pelvis + pel_b * new Vec3(0, -0.02, side * (HIP_HALF + S("stance")));
                double phi = Math.Atan2(foot.y - bb.y, foot.x - bb.x);
                double out_heel = HEEL_OUT_DROP * heels * clampf(side * knee_lean * 1.6, 0.0, 1.0) * (1.0 - air);
                double toe_up = clampf(ank_swing * Math.Cos(phi + ANKLE_PHASE) + ank_bias + out_heel, -0.35, 0.4);
                double f_pitch = S("footAngle") + toe_up;
                foot_pitch[i] = f_pitch;
                Basis pb = Basis.axis_angle(Vec3.BACK, f_pitch);
                Basis sb = Basis.axis_angle(Vec3.UP, -side * S("footOut")) * pb;
                Vec3 shoe_o = standing ? foot + new Vec3(0.0, 0.03, 0.0) : foot + pb.y * pedal_top - sb.x * BALL_X;
                Vec3 ankle = !standing ? shoe_o + sb * new Vec3(ANKLE_X + S("heelFwd"), ANKLE_UP + S("heelUp"), 0.0)
                    : new Vec3(foot.x - 0.04 + S("heelFwd"), foot.y + 0.12 + S("heelUp"), foot.z);
                double inside = clampf(-side * knee_lean * 1.6, 0.0, 0.9) * S("kneeOpen") * (1.0 - air);
                Vec3 pole_l = (poles_leg[i] + new Vec3(0, 0, side * (inside + _pk_ko))).normalized();
                if (_spr_arm > 0.01 && !standing && air < 0.3)
                {
                    pole_l = (pole_l + new Vec3(0.25, 0.7, 0.0) * (_spr_arm * Math.Pow(clampf(Math.Sin(phi), 0.0, 1.0), 2.0) * lerpf(1.0, 0.6, cad_k))).normalized();
                    pole_l.z *= 1.0 - SPR_KNEE_IN * _spr_arm;
                    pole_l = pole_l.normalized();
                }
                object dn = p.get("dabNormal");
                double gw = signf(_num(p, "dabSide", -1.0)) == side ? dab_w : 0.0;
                double fo_w = signf(_num(p, "footOutSide", -1.0)) == side ? clampf(_num(p, "footOut"), 0.0, 1.0) : 0.0;
                if (fo_w > gw) gw = fo_w;
                if (dn is Vec3 dnv && gw > 0.0)
                {
                    Quat q0 = sb.get_rotation_quaternion();
                    Quat tilt = Quat.arc(sb.y.normalized(), dnv.normalized());
                    Quat q1 = (tilt * q0).normalized();
                    sb = Basis.from_quat(q0.slerp(q1, gw));
                    shoe_o = foot + sb.y * pedal_top - sb.x * BALL_X;
                    ankle = shoe_o + sb * new Vec3(ANKLE_X + S("heelFwd"), ANKLE_UP + S("heelUp"), 0.0);
                }
                var ik = limb_ik(hp, ankle, L_THIGH, L_SHIN, pole_l, Vec3.UP, KNEE_MIN, KNEE_MAX, _bd_prev[i], max_turn);
                bool foot_on_ground = dn is Vec3 && (dab_w > 0.5 || _num(p, "footOut") > 0.5)
                    && absf(signf(_num(p, _num(p, "footOut") > 0.5 ? "footOutSide" : "dabSide", -1.0)) - side) < 0.1;
                if (!standing && !foot_on_ground)
                {
                    Vec3 mid = hp.lerp(ankle, 0.5);
                    double knee_out = side * (ik.j.z - mid.z);
                    double yaw_t = clampf(knee_out / 0.18, -0.5, 1.0) * HEEL_TURN_MAX * S("heelTurn", 1.0);
                    Vec3 s_dir = (ik.j - ankle).normalized();
                    double ar_t = clampf(-side * s_dir.z * 0.6, -1.0, 1.0) * ANKLE_ROLL_MAX * S("ankleRoll", 1.0);
                    double ek = dt > 0.0 ? 1.0 - exp_(-12.0 * maxf(dt, 0.0)) : 1.0;
                    _heel_yaw[i] = lerpf(_heel_yaw[i], yaw_t, ek);
                    _ank_roll[i] = lerpf(_ank_roll[i], ar_t, ek);
                    if (absf(_heel_yaw[i]) > 1e-4 || absf(_ank_roll[i]) > 1e-4)
                    {
                        sb = Basis.axis_angle(Vec3.UP, -side * S("footOut")) * pb * Basis.axis_angle(Vec3.UP, -side * _heel_yaw[i]);
                        shoe_o = foot + sb.y * pedal_top - sb.x * BALL_X;
                        ankle = shoe_o + sb * new Vec3(ANKLE_X + S("heelFwd"), ANKLE_UP + S("heelUp"), 0.0);
                        ik = limb_ik(hp, ankle, L_THIGH, L_SHIN, pole_l, Vec3.UP, KNEE_MIN, KNEE_MAX, _bd_prev[i], max_turn);
                    }
                }
                if (!standing && gw < 0.5)
                {
                    for (int it = 0; it < 3; it++)
                    {
                        Vec3 shin_up = ik.j - ankle;
                        Vec3 fwd = sb.x;
                        Vec3 sz = sb.z.normalized();
                        shin_up -= sz * shin_up.dot(sz);
                        fwd -= sz * fwd.dot(sz);
                        if (shin_up.length() < 1e-4 || fwd.length() < 1e-4) break;
                        double a_ank = fwd.angle_to(shin_up);
                        double fix = 0.0;
                        if (a_ank > ANKLE_PLANTAR) fix = a_ank - ANKLE_PLANTAR;
                        else if (a_ank < ANKLE_DORSI) fix = a_ank - ANKLE_DORSI;
                        if (absf(fix) < 0.005) break;
                        f_pitch += fix;
                        foot_pitch[i] = f_pitch;
                        pb = Basis.axis_angle(Vec3.BACK, f_pitch);
                        sb = Basis.axis_angle(Vec3.UP, -side * S("footOut")) * pb * Basis.axis_angle(Vec3.UP, -side * _heel_yaw[i]);
                        shoe_o = foot + sb.y * pedal_top - sb.x * BALL_X;
                        ankle = shoe_o + sb * new Vec3(ANKLE_X + S("heelFwd"), ANKLE_UP + S("heelUp"), 0.0);
                        ik = limb_ik(hp, ankle, L_THIGH, L_SHIN, pole_l, Vec3.UP, KNEE_MIN, KNEE_MAX, _bd_prev[i], max_turn);
                    }
                }
                _bd_prev[i] = ik.bd;
                Vec3 kn = _knee_clear(hp, ankle, ik.j, side, lerpf(KNEE_CLEAR, SPR_KNEE_CLEAR, _spr_arm * (1.0 - air)));
                kn = _swing_clear(hp, ik.end, kn, side, new[] { pelvis.lerp(chest, 0.35), chest }, LIMB_TORSO);
                object hL = p.get("handL"), hR = p.get("handR");
                if (air > 0.3 && hL is Vec3 hLv && hR is Vec3 hRv)
                    kn = _swing_clear(hp, ik.end, kn, side, new[] { hLv, hRv }, LIMB_BAR);
                shoe_o += ik.end - ankle;
                var shoe_xf = new Xf(sb, shoe_o);
                if (i == 0) shoeL = shoe_xf; else shoeR = shoe_xf;
                J[9 + i * 3] = hp;
                J[10 + i * 3] = kn;
                J[11 + i * 3] = shoe_o + new Vec3(0.0, 0.05, 0.0);
                // arm
                var sh_off = new Vec3(-SHOULDER_BACK + S("shoulderFwd"), -SHOULDER_DOWN + S("shoulderUp"), side * S("shoulders"));
                Vec3 shp = chest + tw * sh_off;
                if (_spr_arm > 0.01 && !standing && air < 0.3)
                {
                    double ph = Math.Cos(phi + SPR_LAG);
                    double spk_k = _spr_arm * clampf(S("sway") / 0.035, 0.5, 1.5) * lerpf(1.0, 0.7, cad_k) * calm_k * (1.0 + 0.3 * fat);
                    double pull = Math.Pow(clampf(ph, 0.0, 1.0), 1.5) * spk_k;
                    double push = Math.Pow(clampf(-ph, 0.0, 1.0), 1.5) * spk_k;
                    _arm_pull[i] = pull - push;
                    shp += new Vec3(SPR_PULL_FWD * pull - 0.01 * push, -SPR_PULL_DOWN * pull + SPR_PUSH_UP * push, 0.0);
                }
                if (air > 0.0) shp = shp.lerp(shoulder_at(hip, chest, tw, sh_off), air);
                Vec3 pole_a = poles_arm[i];
                if (aero > 0.01) pole_a = pole_a.lerp(new Vec3(-0.15, 0.15, side * 1.0).normalized(), 0.7 * aero).normalized();
                if (back_k > 0.01) pole_a = pole_a.lerp(new Vec3(-0.35, -0.85, side * 0.3).normalized(), 0.5 * back_k).normalized();
                if (_spr_arm > 0.01 && !standing && air < 0.3)
                {
                    Vec3 wide = new Vec3(-0.15, -0.15, side * 1.0).normalized().lerp(new Vec3(-0.25, -0.15, side * 0.7).normalized(), 0.8 * cad_k).normalized();
                    pole_a = pole_a.lerp(wide, 0.85 * _spr_arm * (1.0 - 0.4 * fat)).normalized();
                    double ap = _arm_pull[i];
                    pole_a = (pole_a + new Vec3(-0.25, 0.1, side * 0.35) * maxf(ap, 0.0) + new Vec3(0.0, -0.2, -side * 0.25) * maxf(-ap, 0.0)).normalized();
                }
                if (_inhale > 0.01 && !standing)
                {
                    pole_a = pole_a.lerp(new Vec3(pole_a.x, pole_a.y * 0.5, side * 1.1).normalized(), 0.12 * _inhale).normalized();
                    shp.z += side * 0.008 * _inhale;
                    shp.y += 0.002 * _inhale;
                }
                if (standing) pole_a = new Vec3(-1.0, 0.0, side * 0.25).normalized();
                if (_pk_eo != 0.0) pole_a = (pole_a + new Vec3(0, 0, side * _pk_eo)).normalized();
                var pole2_a = new Vec3(0, -0.5, side);
                if (!standing && absf(_body_roll) > 1e-4)
                {
                    Basis br = Basis.axis_angle(Vec3.RIGHT, _body_roll);
                    pole_a = br * pole_a; pole2_a = br * pole2_a;
                    object other = p.get(i == 0 ? "handR" : "handL");
                    if (other is Vec3 ov)
                    {
                        double dk = OUT_ELBOW_DOWN * clampf(absf(_body_roll) / 0.4, 0.0, 1.0) * sm(-0.01, 0.06, hand.y - ov.y);
                        pole_a = pole_a.lerp(br * new Vec3(-0.35, -0.8, side * 0.45).normalized(), dk).normalized();
                    }
                }
                var ika = limb_ik(shp, hand, L_UARM, L_FARM, pole_a, pole2_a, ELBOW_MIN, ELBOW_MAX, _bd_prev[2 + i], max_turn);
                _bd_prev[2 + i] = ika.bd;
                Vec3 el = _swing_clear(shp, ika.end, ika.j, side, new[] { hp.lerp(kn, 0.3), kn, kn, ik.end }, LIMB_LIMB);
                if (air > 0.3)
                {
                    int o = 1 - i;
                    el = _swing_clear(shp, ika.end, el, side, new[] { J[9 + o * 3].lerp(J[10 + o * 3], 0.3), J[10 + o * 3], J[10 + o * 3], J[11 + o * 3] }, LIMB_LIMB);
                }
                hand = ika.end;
                Basis hb;
                object gx_v = p.get(i == 0 ? "gripX_L" : "gripX_R"), gz_v = p.get("gripZ");
                if (standing || !(gx_v is Vec3 gxv && gz_v is Vec3 gzv)) hb = orient_hand(el, hand, right);
                else hb = orient_grip(el, hand, gxv, gzv, S("wristBend", WRIST_BEND) + _pk_wb, _pk_wt * side);
                if (S("wristRoll") != 0.0) hb = hb * Basis.axis_angle(Vec3.RIGHT, side * S("wristRoll"));
                if (S("palmIn") != 0.0) hb = hb * Basis.axis_angle(Vec3.RIGHT, S("palmIn") * side);
                var hand_xf = new Xf(hb, hand);
                if (i == 0) handL = hand_xf; else handR = hand_xf;
                J[3 + i * 3] = shp;
                J[4 + i * 3] = el;
                J[5 + i * 3] = hand;
            }
            _skel.follow(this);
        }

        static Vec3 RotPitch(Vec3 q, double c, double sn, double y0)
        {
            double dx = q.x, dy = q.y - y0;
            return new Vec3(dx * c - dy * sn, y0 + dx * sn + dy * c, q.z);
        }

        void _constrain(ref Vec3 pelvis, ref Vec3 chest, PoseInput p, bool standing, double aero)
        {
            object handL = p.get("handL"), handR = p.get("handR");
            if (handL is Vec3 hl && handR is Vec3 hr && !standing)
            {
                double reach = (L_UARM + L_FARM) * clampf(0.9 - 0.2 * S("armBend"), 0.55, 0.98);
                reach = lerpf(reach, (L_UARM + L_FARM) * FACE_REACH, maxf(_face_k, clampf(_num(p, "flipExt"), 0.0, 1.0)));
                reach = lerpf(reach, (L_UARM + L_FARM) * LEAN_REACH, maxf(clampf(absf(_body_roll) / 0.35, 0.0, 1.0), _stop_long));
                double worst = 0.0;
                for (int si = 0; si < 2; si++)
                {
                    double sd = si == 0 ? -1.0 : 1.0;
                    Vec3 tgt = si == 0 ? hl : hr;
                    Vec3 shp = chest + Basis.axis_angle(Vec3.RIGHT, _body_roll) * new Vec3(-SHOULDER_BACK, -SHOULDER_DOWN, sd * S("shoulders"));
                    double over = shp.distance_to(tgt) - reach;
                    if (over > worst) worst = over;
                }
                if (worst > 0)
                {
                    Vec3 d = (hl + hr) * 0.5 - new Vec3(chest.x - SHOULDER_BACK, chest.y - SHOULDER_DOWN, chest.z);
                    double len = d.length();
                    if (len > 1e-4)
                    {
                        d *= minf(worst * 1.2, len * 0.6) / len;
                        chest += d;
                        pelvis += d * 0.35;
                    }
                }
            }
            pelvis.x = clampf(pelvis.x, -0.6, 0.22);
            pelvis.y = clampf(pelvis.y, 0.42, 1.08);
            double z_cap = lerpf(HIP_SIDE, AIR_HIP_SIDE, clampf(_num(p, "air"), 0.0, 1.0));
            pelvis.z = clampf(pelvis.z, -z_cap, z_cap);
            if (handL is Vec3 hl2 && handR is Vec3 hr2 && !standing)
            {
                Vec3 bar_c = (hl2 + hr2) * 0.5;
                var head_off = new Vec2(HEAD_FWD + S("lookAhead") + 0.04 * aero + TUCK_HEAD.x * speed_tuck_k, HEAD_UP + S("neck") + TUCK_HEAD.y * speed_tuck_k);
                var push = Vec2.ZERO;
                double bar_hw = absf(hl2.z - hr2.z) * 0.5;
                double ez = maxf(0.0, absf(chest.z - bar_c.z) - bar_hw);
                for (int pass_i = 0; pass_i < 2; pass_i++)
                {
                    for (int which = 0; which < 2; which++)
                    {
                        double bar_r = which == 1 ? BAR_HEAD : BAR_CHEST;
                        bar_r = Math.Sqrt(maxf(0.0, bar_r * bar_r - ez * ez));
                        if (bar_r < 1e-3) continue;
                        Vec2 d2b = new Vec2(chest.x - bar_c.x, chest.y - bar_c.y) + push + (which == 1 ? head_off : Vec2.ZERO);
                        double dl2 = d2b.length();
                        if (dl2 >= bar_r) continue;
                        var ub = new Vec2(-0.92, 0.39);
                        Vec2 rad = dl2 > 1e-3 ? d2b / dl2 : ub;
                        double rw = 0.5 * clampf(0.5 + 0.5 * rad.dot(ub), 0.0, 1.0);
                        Vec2 dir = (rad * rw + ub * (1.0 - rw)).normalized();
                        double bd = d2b.dot(dir);
                        double tt = -bd + Math.Sqrt(maxf(0.0, bd * bd - (dl2 * dl2 - bar_r * bar_r)));
                        push += dir * tt;
                    }
                }
                if (push != Vec2.ZERO)
                {
                    chest.x += push.x; chest.y += push.y;
                    pelvis.x = maxf(-0.6, pelvis.x + push.x * 0.85); pelvis.y += push.y * 0.6;
                }
            }
            object wr = p.get("wheelR");
            if (wr is Vec3 wrv)
            {
                double clear_r = _num(p, "wheelRR", 0.36) + 0.16;
                var d2 = new Vec2(pelvis.x - wrv.x, pelvis.y - wrv.y);
                if (d2.length() < clear_r)
                {
                    Vec2 outv = (d2.length() > 1e-3 ? d2.normalized() : Vec2.UP) * clear_r - d2;
                    outv.x = d2.x < 0.0 ? minf(outv.x, 0.0) : outv.x;
                    pelvis.x += outv.x; pelvis.y += outv.y;
                    chest.x += outv.x; chest.y += outv.y;
                }
            }
            Vec3 tv0 = chest - pelvis;
            double tl0 = maxf(tv0.length(), 1e-4);
            double f_ang = tv0.y < 0.05 ? 1.4 : clampf(Math.Atan2(tv0.x, tv0.y), -0.45, 1.4);
            double s_cap = lerpf(0.6, AIR_SIDE, clampf(_num(p, "air"), 0.0, 1.0));
            double s_ang = clampf(Math.Asin(clampf(tv0.z / tl0, -1.0, 1.0)) - _body_roll, -s_cap, s_cap) + _body_roll;
            chest = pelvis + new Vec3(Math.Sin(f_ang) * Math.Cos(s_ang), Math.Cos(f_ang) * Math.Cos(s_ang), Math.Sin(s_ang)) * tl0;
            Vec3 tv = chest - pelvis;
            double tl = tv.length();
            double t_max = S("torso"), t_min = S("torso") * 0.75;
            if (tl > t_max) pelvis = chest - tv / tl * t_max;
            else if (tl < t_min && tl > 1e-4) chest = pelvis + tv / tl * t_min;
            double hip_lift = 0.0;
            if (S("seatFloor") != 0.0 && seat != null && !standing)
            {
                double s_in = clampf((pelvis.x - (seat[1] - 0.1)) / 0.08, 0.0, 1.0) * clampf((seat[2] + 0.1 - pelvis.x) / 0.08, 0.0, 1.0);
                hip_lift = maxf(0.0, (seat[0] + 0.078 - 0.3 * _sink - pelvis.y) * s_in);
            }
            if (wr is Vec3 wrv2 && !standing)
            {
                var dw = new Vec2(pelvis.x - wrv2.x, pelvis.y + hip_lift - wrv2.y);
                double cr2 = _num(p, "wheelRR", 0.36) + 0.12;
                if (dw.length() < cr2 && dw.y > -0.1) hip_lift += Math.Sqrt(maxf(0.0, cr2 * cr2 - dw.x * dw.x)) - dw.y;
            }
            if (hip_lift > 0.0) { pelvis.y += hip_lift; chest.y += hip_lift; }
        }

        // ---------------- helpers ----------------
        public static Vec3 shoulder_at(Vec3 hip_p, Vec3 chest_p, Basis tw, Vec3 off)
        {
            Vec3 up = (chest_p - hip_p).normalized();
            if (up.length_squared() < 0.5) up = Vec3.UP;
            Vec3 r = tw * new Vec3(0, 0, 1);
            r = r - up * r.dot(up);
            if (r.length_squared() < 1e-6) r = new Vec3(0, 0, 1);
            r = r.normalized();
            Vec3 fw = up.cross(r);
            return chest_p + fw * off.x + up * off.y + r * off.z;
        }

        /// the torso as a quadratic curve from hip a to chest b (rider.gd set_spine): writes the 5 spine bone transforms
        void set_spine(Vec3 a, Vec3 b, Vec3 right_lo, Vec3 right_hi, double curve, double side, double low, Basis bas, bool lock_base)
        {
            Vec3 d = b - a;
            double l = maxf(d.length(), 1e-4);
            Vec3 dn = d / l;
            Vec3 r0 = (right_hi - dn * right_hi.dot(dn)).normalized();
            Vec3 fwd = dn.cross(r0);
            Vec3 ctrl = a + d * clampf(low, 0.05, 0.95) - fwd * curve * l + r0 * side * l;
            for (int k = 0; k < SPINE_BONES; k++)
            {
                double tt = (double)k / (SPINE_BONES - 1);
                Vec3 pt = a * ((1 - tt) * (1 - tt)) + ctrl * (2 * tt * (1 - tt)) + b * (tt * tt);
                Vec3 tg = (ctrl - a) * (2 * (1 - tt)) + (b - ctrl) * (2 * tt);
                double tl = maxf(tg.length(), 1e-4);
                Vec3 tn = tg / tl;
                if (k == 0 && lock_base) tn = bas.y.normalized();
                Vec3 rr = right_lo.lerp(right_hi, tt);
                if (k == 0 && lock_base) rr = bas.z;
                rr = rr - tn * rr.dot(tn);
                if (rr.length_squared() < 1e-6)
                {
                    rr = r0 - tn * r0.dot(tn);
                    if (rr.length_squared() < 1e-6) rr = tn.cross(absf(tn.y) < 0.9 ? Vec3.UP : Vec3.RIGHT);
                }
                rr = rr.normalized();
                Vec3 f = tn.cross(rr);
                spine[k] = new Xf(new Basis(f, tn * tl, rr), pt - tn * tl * (tt - 0.5));
            }
        }

        static Basis orient_grip(Vec3 el, Vec3 at, Vec3 gx, Vec3 gz, double bend, double yaw)
        {
            Vec3 z = gz.normalized();
            Vec3 x = (gx - z * gx.dot(z)).normalized();
            Vec3 up = z.cross(x);
            x = (x * Math.Cos(GRIP_TILT + bend) - up * Math.Sin(GRIP_TILT + bend)).normalized();
            if (absf(yaw) > 1e-4) x = x.rotated(up, yaw);
            Vec3 fore = (at - el).normalized();
            double ang = fore.angle_to(x);
            if (ang > WRIST_MAX) x = fore.slerp(x, WRIST_MAX / ang);
            Vec3 zz = (z - x * z.dot(x)).normalized();
            return new Basis(x, zz.cross(x), zz);
        }

        static Basis orient_hand(Vec3 el, Vec3 at, Vec3 right)
        {
            Vec3 x = (at - el).normalized();
            Vec3 z = (right - x * right.dot(x)).normalized();
            Vec3 y = z.cross(x);
            return new Basis(x, y, z);
        }

        static Vec3 _knee_clear(Vec3 hip, Vec3 ankle, Vec3 kn, double side, double clear)
        {
            if (side * kn.z >= clear) return kn;
            Vec3 ax = ankle - hip;
            if (ax.length_squared() < 1e-6) return kn;
            ax = ax.normalized();
            Vec3 c = hip + ax * (kn - hip).dot(ax);
            double r = (kn - c).length();
            if (r < 1e-4) return kn;
            Vec3 u = (kn - c) / r;
            Vec3 outv = new Vec3(0, 0, side) - ax * (ax.z * side);
            if (outv.length_squared() < 1e-6) return kn;
            outv = outv.normalized();
            if (u.dot(outv) < -0.999 || side * (c + outv * r).z < clear) return c + outv * r;
            double lo = 0.0, hi = 1.0;
            for (int k = 0; k < 14; k++)
            {
                double m = (lo + hi) * 0.5;
                if (side * (c + u.slerp(outv, m) * r).z >= clear) hi = m; else lo = m;
            }
            return c + u.slerp(outv, hi) * r;
        }

        public struct IK { public Vec3 j, end, bd; }

        /// two-bone IK with joint limits -> joint, reachable end, bend direction (rider.gd limb_ik)
        public static IK limb_ik(Vec3 root, Vec3 target, double l1, double l2, Vec3 pole, Vec3 pole2,
            double min_deg, double max_deg, Vec3 prev, double max_turn)
        {
            Vec3 d = target - root;
            double dist = d.length();
            Vec3 dir = dist > 1e-5 ? d / dist : Vec3.DOWN;
            double dmax = Math.Sqrt(maxf(0.0, l1 * l1 + l2 * l2 + 2 * l1 * l2 * Math.Cos(min_deg * Math.PI / 180.0)));
            double dmin = Math.Sqrt(maxf(0.0, l1 * l1 + l2 * l2 + 2 * l1 * l2 * Math.Cos(max_deg * Math.PI / 180.0)));
            dist = clampf(dist, maxf(dmin, absf(l1 - l2) + 0.01), dmax);
            Vec3 p1 = pole - dir * pole.dot(dir);
            Vec3 p2 = pole2 - dir * pole2.dot(dir);
            double w = sm(0.2, 0.5, p1.length() / maxf(pole.length(), 1e-6));
            Vec3 bd = Vec3.ZERO;
            if (p1.length_squared() > 1e-10) bd += p1.normalized() * w;
            if (p2.length_squared() > 1e-10) bd += p2.normalized() * (1.0 - w);
            if (bd.length_squared() < 1e-8) bd = dir.cross(absf(dir.z) < 0.9 ? Vec3.FORWARD : Vec3.RIGHT);
            bd = (bd - dir * bd.dot(dir)).normalized();
            if (prev != Vec3.ZERO && max_turn < PI)
            {
                Vec3 pr = prev - dir * prev.dot(dir);
                if (pr.length_squared() > 1e-6)
                {
                    pr = pr.normalized();
                    double ang = pr.signed_angle_to(bd, dir);
                    if (absf(ang) > max_turn) bd = pr.rotated(dir, clampf(ang, -max_turn, max_turn)).normalized();
                }
            }
            double a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
            double hh = Math.Sqrt(maxf(0.0, l1 * l1 - a * a));
            return new IK { j = root + dir * a + bd * hh, end = root + dir * dist, bd = bd };
        }

        public static double seg_dist(Vec3 a0, Vec3 a1, Vec3 b0, Vec3 b1)
        {
            Vec3 d1 = a1 - a0, d2 = b1 - b0, r = a0 - b0;
            double a = d1.dot(d1), e = d2.dot(d2), f = d2.dot(r);
            double s = 0.0, t = 0.0;
            if (a <= 1e-9 && e <= 1e-9) return r.length();
            if (a <= 1e-9) t = clampf(f / e, 0.0, 1.0);
            else
            {
                double c = d1.dot(r);
                if (e <= 1e-9) s = clampf(-c / a, 0.0, 1.0);
                else
                {
                    double b = d1.dot(d2);
                    double den = a * e - b * b;
                    s = den > 1e-9 ? clampf((b * f - c * e) / den, 0.0, 1.0) : 0.0;
                    t = (b * s + f) / e;
                    if (t < 0.0) { t = 0.0; s = clampf(-c / a, 0.0, 1.0); }
                    else if (t > 1.0) { t = 1.0; s = clampf((b - c) / a, 0.0, 1.0); }
                }
            }
            return (a0 + d1 * s).distance_to(b0 + d2 * t);
        }

        static Vec3 _swing_clear(Vec3 root, Vec3 tip, Vec3 mid, double side, Vec3[] segs, double clear, double max_a = 1.15)
        {
            Vec3 ax = tip - root;
            if (ax.length_squared() < 1e-6) return mid;
            ax = ax.normalized();
            if (_swing_need(root, tip, mid, segs, clear) <= 0.0) return mid;
            Vec3 c = root + ax * (mid - root).dot(ax);
            Vec3 rel = mid - c;
            if (rel.length_squared() < 1e-8) return mid;
            double sgn = ax.cross(rel).z * side > 0.0 ? 1.0 : -1.0;
            double lo = 0.0, hi = max_a;
            if (_swing_need(root, tip, c + rel.rotated(ax, sgn * hi), segs, clear) <= 0.0)
            {
                for (int k = 0; k < 9; k++)
                {
                    double m = (lo + hi) * 0.5;
                    if (_swing_need(root, tip, c + rel.rotated(ax, sgn * m), segs, clear) <= 0.0) hi = m; else lo = m;
                }
            }
            return c + rel.rotated(ax, sgn * hi);
        }

        static double _swing_need(Vec3 root, Vec3 tip, Vec3 m, Vec3[] segs, double clear)
        {
            double worst = 0.0;
            for (int k = 0; k + 1 < segs.Length; k += 2)
            {
                double d = minf(seg_dist(root.lerp(m, 0.45), m, segs[k], segs[k + 1]), seg_dist(m, m.lerp(tip, 0.75), segs[k], segs[k + 1]));
                worst = maxf(worst, clear - d);
            }
            return worst;
        }
    }
}
