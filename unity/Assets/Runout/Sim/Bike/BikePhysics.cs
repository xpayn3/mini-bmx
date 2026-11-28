// Port of godot/scripts/bike/bike_physics.gd: the ride, a fixed 1/120 s step. Metres / seconds, y up, the bike travels
// along fwd = (cos heading, 0, -sin heading). Ported line for line: same names, same order, doubles (GDScript floats are
// 64-bit). Only the current behaviour is ported (every BMX_OLD_* switch and test probe is left out).
// This file: setup, shared helpers, resets, the step entry point, ground sampling and the stage driver (_ride_step).
// The stages live in BikePhysics.<Stage>.cs (partial class). STATUS: being ported (see unity/PORTING.md).
using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    /// What a bike brings to the ride (Godot: the glb's extras + GameState.bike_config()).
    public sealed class BikeConfig
    {
        public double wheelbase = 0.8985, wheelRadius = 0.261, wheelRadiusRear = double.NaN, bbToRearAxle = 0.3331;
        public double land = 1.0;
        public bool geared = true;
        /// the build's cassette (teeth per cog, easiest last like Godot) and chainring vs the stock 34T; null = ungeared (BMX)
        public List<double> cogs = null;
        public double ring_k = 1.0, mods_land = 1.0;
        public SuspSetup.Setup susp = null;
        /// per-bike multipliers on the Tune values (GameState.BIKES.*.ride x the garage's mods)
        public Dictionary<string, double> ride = new Dictionary<string, double>();
    }

    public sealed partial class BikePhysics : ISimStep
    {
        public readonly IBikeHost host;
        public readonly Tune T;
        /// the Tune the static helpers read (Godot reads the Tune autoload from static functions)
        public static Tune TuneV { get; private set; }
        readonly Rng _rng = new Rng(1234567);
        readonly Rng _grip_rng = new Rng(4711);
        readonly List<Obstacle> _near = new List<Obstacle>();

        public BikePhysics(IBikeHost h, Tune tune)
        {
            host = h; T = tune; TuneV = tune;
        }

        double randf() => _rng.randf();

        /// obstacles near (x, z) (a shared list: copy before stepping into another query)
        List<Obstacle> colliders_near(double px, double pz)
        {
            _near.Clear();
            host.terrain.colliders_near(px, pz, _near);
            return _near;
        }

        public void setup(BikeConfig c)
        {
            L = c.wheelbase;
            RWF = c.wheelRadius;
            RWR = is_nan(c.wheelRadiusRear) ? RWF : c.wheelRadiusRear;
            BB_REAR = c.bbToRearAxle;
            SH_R = (L - BB_REAR) / L;
            LAND = c.land;
            geared = c.geared;
            sus = c.susp; _sus_synced = false; _su = new double[0];
            if (c.cogs != null)
            {
                cogs = c.cogs; ring_k = c.ring_k;
                LAND *= c.mods_land;
            }
            else
            {
                // no garage build (the BMX): one neutral 16T cog, ratio 1
                cogs = new List<double> { 16 }; ring_k = 1.0;
            }
            if (cogs.Count <= 1) geared = false;
            gear = geared ? start_gear(cogs, ring_k) : -1;
            T.set_ride(c.ride);
        }

        /// the cog a ride starts in: nearest the old 16T reference
        public static int start_gear(List<double> p_cogs, double p_ring_k)
        {
            int g = -1;
            double best = 1e9;
            for (int i = 0; i < p_cogs.Count; i++)
                if (absf(p_cogs[i] / p_ring_k - 16.0) < best) { best = absf(p_cogs[i] / p_ring_k - 16.0); g = i; }
            return g;
        }

        /// crank turn rate (rad/s) for the REAR wheel spinning at w rad/s through `ratio` (the chain ties them)
        public static double crank_rate(double w, double gk, double top_speed, double p_sprint, double ratio = -1.0)
        {
            double spin_up = 3.5 + TuneV.get("sprintSpin", 4.0) * p_sprint * slowness(w * 0.37);
            if (ratio <= 0.0)
                return maxf(w / (2.78 * gk * top_speed), spin_up) * (1 + 0.3 * p_sprint);
            return maxf(w / ratio, spin_up * (1.0 - smooth01(w / ratio / maxf(spin_up, 0.1))));
        }

        /// rear wheel turns per crank turn: chainring / cog (stock ring 34T; gear_k = ring_k x 16 / cog); the BMX 25 / 9
        public static double ratio_for(double gk, bool p_geared) => p_geared ? 2.125 * gk : 2.78;

        public double drive_ratio() => ratio_for(gear_k(), gear >= 0);

        /// how far back (0..1 of the body stick) holds a direct manual on its balance point (the keyboard's held key)
        public static double kb_back_cap()
        {
            double b = TuneV.get("manBalance", 0.55);
            double m_from = TuneV.get("manualFrom", 0.4);
            double p_cap = b / (b + TuneV.get("manLoop", 0.42) + 0.08);
            return clampf(m_from + p_cap * (1.0 - m_from), 0.55, 1.0);
        }

        /// 1 standing still .. 0 by ~40 km/h (smooth): how hard a sprinting rider fights to get up to speed
        public static double slowness(double va) => 1.0 - smooth01(absf(va) / TuneV.get("sprintSlowTo", 11.0));

        /// side-to-side rock from pedalling out of the saddle
        public static double pedal_rock(double p_crank, double p_sprint, double p_pedal, double va, double p_bike_rock)
        {
            double rock_fade = 1.0 - 0.65 * smoothstep(5.0, 12.0, va);
            double effort = p_sprint * slowness(va);
            return sin(p_crank) * 0.105 * (1 + 0.65 * p_sprint + TuneV.get("sprintRock", 0.3) * effort) * p_pedal * minf(1.0, va / 2 + 0.3) * rock_fade * p_bike_rock;
        }

        public double gear_k()
        {
            if (gear < 0) return cogs.Count > 0 ? ring_k * 16.0 / cogs[0] : 1.0;
            return ring_k * 16.0 / cogs[gear];
        }

        public bool shift(int d)
        {
            if (gear < 0) return false;
            int g = clampi(gear + d, 0, cogs.Count - 1);
            if (g == gear) return false;
            gear = g;
            // shifting under load the chain skips before it settles on the new cog
            if (!air && pedal > 0.3 && throttle_in > 0.3)
            {
                double load_k = clampf(pedal * throttle_in * (0.6 + 0.4 * sprint), 0.0, 1.0);
                chain_slip = maxf(chain_slip, CHAIN_SLIP_T * (0.4 + 0.6 * load_k));
            }
            return true;
        }

        public static double smooth01(double t)
        {
            t = clampf(t, 0.0, 1.0);
            return t * t * (3.0 - 2.0 * t);
        }

        public static double ang_diff(double a, double b) => atan2(sin(a - b), cos(a - b));

        static double _or(double a, double d) => is_nan(a) ? d : a;

        public V3 fwd() => new V3(cos(heading), 0.0, -sin(heading));

        /// a rear shock to bob / kick (a setup AND a rear linkage drawn; no drawn bike = the setup alone)
        bool _rear_shock() => sus != null && (host.susp == null || host.susp.has_r);
        /// a sprung fork to dive
        bool _sprung_fork() => sus != null && (host.susp == null || host.susp.has_f);

        // =====================================================================
        public void reset_at(double px, double pz, double hd)
        {
            x = px; z = pz; heading = hd;
            _reset_motion();
        }

        public void get_up()
        {
            _reset_motion();
            hop_block = true;   // the hop held to get up doesn't hop
        }

        /// everything a respawn and a get-up share: the bike stands still on the ground at (x, z), facing heading
        void _reset_motion()
        {
            crash_on = false; crash_pending = ""; crash_hold = 0.0; crash_armed = false; crash_sim = null;
            v = 0; vy = 0; steer = 0; steer_in = 0; steer_in_v = 0; lean = 0; lean_v = 0; pitch = 0; air = false;
            bike_lean = 0; counter = 0; man_lk = 0.0; rock = 0; yaw_rate = 0; hop_nose = 0; _hop_nose_t = 0.0; _hop_nose_m = 0.0; hop_t = 0; air_time = 0; air_k = 0;
            load = 0; compress = 0; compress_v = 0; prep = 0; land_prep = 0; pop_fired = false; spun_out = false; chain_slip = 0.0; chain_slip_k = 0.0; shake = 0;
            turn_off = 0.0; rev_cap = 3.0; _fakie_hold = 0.0;
            course = heading; slip = 0; slip_w = 0.0; bar_catch = 0.0; w_init = false; front_air = false; rear_air = false; pump_acc = 0; since_land = 1; _graze = false;
            pitch_v = 0; c_f = true; c_r = true; wheelie_up = 0.0; _bog = 0.0;
            g_pitch = NAN;
            y = host.terrain.height(x, z); body_y = y; body_v = 0;
            // start lined up with the ground (a bike set down level on a steep slope was judged LOOPED OUT / NOSE DIVE)
            _sample(fwd()); pitch = _g_pitch; g_pitch = _g_pitch; _gpc_last = NAN;
            n_f = NAN; n_r = NAN; n_ref = NAN; lip_state = 0; hf_prev = NAN; hr_prev = NAN; zw_f = NAN; zw_r = NAN;
            bank = 0; _bank_hold = 0.0; _air_wl = 0.0; body_x = 0; hip_shift = 0; spin = 0; a_drive = 0; charge = 0; hop_charge = 0; lift_t = 0;
            body_xv = 0; hip_v = 0; v_last = NAN; air_lean = 0; air_pull = 0; _air_pull_v = 0.0; flip_acc = 0; spin_acc = 0; flip_in = 0;
            body_pw = 0; throw_v = 0; air_w = 0; air_inertia = 1; air_tilt = 0; air_tilt_v = 0; air_yaw = 0; air_tw = 0; air_tw_v = 0; whip_load = 0; _whip_in = 0; spin_load = 0; _spin_in = 0; _flip_in = 0; land_jolt = 0;
            pivot = 0; pivot_acc = 0; body_in_s = 0; flick = 0; flick_v = 0; _flick_arm = 0; _flick_side = 0; flick_kick = 0;
            nose_a = 0.0; nose_w = 0.0; nose_zone = false; nose_lock = 0.0; nose_push = 0.0; nose_time = 0.0; nose_brake_t = 0.0; _nose_grace = 0.0;
            _tw_t = 9.0; _ts_t = 9.0; _sb_t = 9.0; _sf_t = 9.0; _hop_tap_t = 9.0; _hop_buf = 0.0; _pop_miss = 0.0; _pop_miss_t = 0.0; _gl = 0.0; _gc = 0.0;
            _bh_back = 0.0; _bh_since = 9.0; _bh_peak = 0.0; gest_hop = 0.0;
            crouch = 0.0; crouch_t = 0.0; rebound = 0.0; _stick_hold = 0.0; _cr_rel = 0.0; _n_grd = 1.0; pop_wait = 0.0; _pop_arm_t = 0.0; squash = 0.0;
            pop_fx = 0.0; _pop_latch = false; _air_pop = 0.0; pro_pop = false; pro_flight = false; squash_fx = 0.0; pop_q = 0.0; pop_time = 0.0; _pop_used = 0.0;
            land_heavy = 0.0; land_fold = 0.0; _land_hit = 0.0; _land_pe = 0.0; _stun = 0.0; land_yaw = 0.0; _rim_hit = 0.0; _ty_f = 0.0; _ty_r = 0.0; _tuck_in = false;
            man_a = 0.0; man_w = 0.0; man_zone = false; man_lock = 0.0; man_zone_t = 0.0; man_pull = 0.0; _man_over = 0.0; _man_armed = false; _pull_age = 0.0; _man_pw = 0.0; _man_grace = 0.0; _sprint_lift = 0.0;
            pump_push = 0.0; pump_gain = 0.0; pump_idle = 0.0; pump_press_t = 0.0; _pump_release = 0.0; pump_on = false; pleg = 0.0; pump_lift = 0.0; land_perfect = 0.0;
            wheelie_time = 0.0; wheelie_pedal = false; whip = 0; whip_hold = 0; whip_side = 0.0; _whip_arm = 0; _whip_t = 0; _whip_flashed = false; _whip_straight = false; _whip_ang = 0.0; _whip_peak = 0.0;
            edge_s = 0.0; spin_hold = 0.0; spin_k = 1.0; yaw_edge_s = 0.0; yaw_hold = 0.0; stick_yaw = 0.0; air_stick = V2.Zero; style_air = 0.0;
            brake_stop = false; brake_back = false; _rev_hold = 0.0; lean_lim = 9.0; lean_room = NAN;
            sprint = 0; flow = 0; flow_t = 0; lat_m = 0; carve = 0; carve_acc = 0; carve_berm = false;
            y_draw = y; pitch_draw = pitch; nose_ref = NAN; pitch_w = NAN; y_prev = NAN; kick_t = 0;
            w_f = y; w_r = y;
            pedal = 0.0; throttle_in = 0.0; _grip_cv = 0.0; _grip_rough = 0.0; hop_held = false;
            _reset_ground_sim();
        }

        void _reset_ground_sim()
        {
            front_use = 0.0; front_push = 0.0; rear_lock = 0.0; front_lock = 0.0; _fb_f = 0.0; _rear_up_k = 0.0;
            _brk_r = 0.0; _brk_f = 0.0; _feel_r = NAN; _feel_f = NAN; brk_loose_f = 0.0; brk_loose_r = 0.0;
            corner_g = 0.0; weight_in = 0.0; lean_err = 0.0; knock = 0.0; _amax = 99.0; _amin = -99.0; bal_k = 0.0;
            _b_prev = 0.0; _f_prev = 0.0; _circ_f = 1.0; bank_lean = 0.0; bank_sq = 0.0; _gx_lean = 0.0; berm_k = 0.0;
            _mu_f = NAN; _mu_r = NAN; _bmu_f = NAN; _bmu_r = NAN; bank_v = 0.0; _load_s = NAN; _share_f = NAN; _bike_lead = 0.0; _weave = 0.0;
            _risk.Clear(); risk = 0.0; _risk_peak = 0.0;
        }

        public void begin_crash()
        {
            _bal_shoved = false;
            crash_pending = "";
            flow = 0;
            crash_on = true; crash_t = 0; crash_rest = 0; crash_armed = false; crash_hold = 0; wheelie_time = 0.0; wheelie_pedal = false;
            crash_side = absf(bike_lean) > 0.05 ? signf(bike_lean) : (randf() < 0.5 ? -1.0 : 1.0);
            crash_fall_v = crash_side * 1.5;
            crash_bvy = air ? vy : minf(vy, 0.5);
            air = false; pedal = 0; load = 0; shake = 0.45;
        }

        // =====================================================================
        // ISimStep (the plug)
        void ISimStep.Step(double dt, in RideInput inp) => step(dt, inp);

        void ISimStep.Capture(ref SimPose p)
        {
            p.X = (float)x; p.Y = (float)y_draw; p.Z = (float)z;
            p.Heading = (float)heading; p.Pitch = (float)pitch_draw; p.BikeLean = (float)bike_lean; p.Steer = (float)steer;
            p.Speed = (float)v; p.Vy = (float)vy; p.Air = air;
        }

        public void step(double dt, in RideInput inp)
        {
            if (dt <= 0.0) return;   // (time frozen: several rates divide by dt)
            if (crash_pending != "") host.start_crash(crash_pending);
            if (crash_on)
            {
                _crash_step(dt, inp);
                return;
            }
            _ride_step(dt, inp);
        }

        // ---------------------------------------------------------------------
        void _crash_step(double dt, in RideInput inp)
        {
            crash_t += dt;
            var f = fwd();
            v *= exp(-dt * 2.2);
            if (absf(v) < 0.05) v = 0;
            yaw_rate *= exp(-dt * 3); heading += yaw_rate * dt;
            if (crash_sim != null) _crash_sim_step(dt);
            else _crash_old_step(dt, f);
            // (the ragdoll, its smashes and the rider-bike contacts are port step 5: the host steps them for now)
            if (host.getting_up) return;
            bool holding = crash_armed && inp.hop;
            if (holding) crash_hold += dt;
            else { crash_armed = false; crash_hold = maxf(0.0, crash_hold - dt * 3); }
            if (crash_hold >= getup_need) host.begin_getup();
        }

        /// the crashed bike as a body (port step 5): step it and read the bike back
        void _crash_sim_step(double dt)
        {
            if (!crash_sim.Asleep) crash_sim.Step(dt);
            crash_sim.ReadBack(out var p, out var hd, out var pt, out var ln, out var bars, out var vel);
            x = p.x; y = p.y; z = p.z; heading = hd; pitch = pt; bike_lean = ln; steer = bars;
            v = sqrt(vel.x * vel.x + vel.z * vel.z) * (vel.dot(fwd()) >= 0.0 ? 1.0 : -1.0);
            counter = 0; rock = 0; pedal = 0; hop_nose = 0.0; _hop_nose_t = 0.0; _hop_nose_m = 0.0; yaw_rate = 0.0;
            body_y = y; body_v = 0; y_draw = y; pitch_draw = pitch;
        }

        /// the scripted fall: the bike slides as one point, the lean falls to ~85 deg
        void _crash_old_step(double dt, V3 f)
        {
            var terrain = host.terrain;
            double _x0 = x, _z0 = z;
            x += f.x * v * dt; z += f.z * v * dt;
            // a wall (canyon side, cliff face) stops the crashed bike
            if (terrain.height(x, z) > y + CRASH_WALL) { x = _x0; z = _z0; v *= -0.2; }
            foreach (var c in colliders_near(x, z).ToArray())
            {
                if (c.has_top && c.top < y + 0.45) continue;
                if (c.tape) continue;
                if (c.fence && absf(v) > 2 && new V2(x - c.x, z - c.z).length() < c.r + 0.35)
                {
                    host.smash(c, new V3(f.x * v, 0, f.z * v), new V3(x, y, z)); continue;
                }
                double dx = x - c.x, dz = z - c.z;
                double d = sqrt(dx * dx + dz * dz);
                double mn = (c.has_top ? c.r : c.r - 0.1) + 0.25;
                if (d < mn && d > 1e-4) { x = c.x + dx / d * mn; z = c.z + dz / d * mn; v *= -0.2; }
            }
            double lim = 1.48;
            crash_fall_v += sin(bike_lean != 0.0 ? bike_lean : crash_side * 0.05) * 14.0 * dt;
            bike_lean += crash_fall_v * dt;
            if (absf(bike_lean) > lim) { bike_lean = signf(bike_lean) * lim; crash_fall_v *= -0.25; }
            counter = 0; rock = 0; pedal = 0;
            steer += (crash_side * 0.5 - steer) * minf(1.0, dt * 4);
            double ground = terrain.height(x, z) + 0.24 * absf(sin(bike_lean));
            crash_bvy -= G * dt; y += crash_bvy * dt;
            if (y < ground) { y = ground; crash_bvy = crash_bvy < -2 ? -crash_bvy * 0.25 : 0.0; }
            double hr = terrain.height(x - f.x * BB_REAR, z - f.z * BB_REAR);
            double hf = terrain.height(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR));
            pitch += (atan2(hf - hr, L) - pitch) * minf(1.0, dt * 6);
            hop_nose *= exp(-dt * 4); _hop_nose_t = 0.0; _hop_nose_m = 0.0;
            wheel_f += v / RWF * dt; wheel_r += v / RWR * dt;
            body_y = y; body_v = 0; y_draw = y; pitch_draw = pitch;
        }

        // ---------------------------------------------------------------------
        void _sample(V3 f)
        {
            var terrain = host.terrain;
            double hr = terrain.height(x - f.x * BB_REAR, z - f.z * BB_REAR);
            double hf = terrain.height(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR));
            _g_hr = hr; _g_hf = hf;
            _g_y = hr + (hf - hr) * (BB_REAR / L); _g_pitch = atan2(hf - hr, L);
        }

        double _wheel_ground(V3 f, double x0, double R, double cp0)
        {
            var terrain = host.terrain;
            double best = -INF;
            int kb = 0;
            var raw = _wg_raw;
            for (int k = -5; k < 6; k++)   // 11 points across the contact: a small rock can't slip between them
            {
                double s = k / 5.0 * R;
                double d = x0 * cp0 + s;
                double h0 = terrain.height(x + f.x * d, z + f.z * d);
                raw[k + 5] = h0;
                double hh = h0 + sqrt(R * R - s * s) - R;
                if (hh > best) { best = hh; kb = k; }
            }
            // an edge between two of those points: search finer around the best point where the ground bends sharply
            int i = kb + 5;
            bool sharp = false;
            for (int j = maxi(i - 1, 1); j < mini(i + 1, 9) + 1; j++)
                if (absf(raw[j - 1] + raw[j + 1] - 2.0 * raw[j]) > WG_EDGE) { sharp = true; break; }
            if (sharp)
            {
                double ds = R / 5.0;
                for (int j = -WG_FINE + 1; j < WG_FINE; j++)
                {
                    if (j == 0) continue;
                    double s = kb * ds + j * ds / WG_FINE;
                    if (s <= -R || s >= R) continue;
                    double d = x0 * cp0 + s;
                    double hh = terrain.height(x + f.x * d, z + f.z * d) + sqrt(R * R - s * s) - R;
                    if (hh > best) best = hh;
                }
            }
            return best;
        }

        /// One ride step (120 Hz), stage by stage. The stages share only what is passed here; everything else they read
        /// and write is the bike's own state. Order matters: each stage works on what the last one left
        void _ride_step(double dt, in RideInput inp)
        {
            double throttle = inp.throttle;
            // after a heavy / sideways landing the rider needs a moment before he can put power down again, and unfolds
            if (_stun > 0.0) { _stun = maxf(0.0, _stun - dt); throttle = 0.0; }
            land_fold = maxf(0.0, land_fold - dt / (0.45 + 0.9 * land_fold + 1.0 * land_heavy));
            _loop_saved = maxf(0.0, _loop_saved - dt);
            double steer_input = inp.steer;
            double brake_k = _step_controls(dt, inp, throttle, steer_input);
            bool brake = brake_k > 0.1;
            double roll_keys = (!air || air_lock_a) ? 0.0 : steer_input;   // A / D in the air, before the body stick is added
            // a steer held from the ground counts in a short hop and fades out between 0.3 and 0.6 s of air
            if (air && air_lock_a) roll_keys = steer_input * (1.0 - smooth01((air_time - AIR_LOCK_FROM) / AIR_LOCK_FADE));
            var f = fwd();
            _step_ground(dt, f);
            bool in_water = surf == 2;
            double slope = (!air && (front_air || rear_air) && wheelie_up <= 0.0 && nose_a <= 0.0) ? _or(pitch_w, _g_pitch) : _g_pitch;
            // rolling on the rear wheel alone, the hill it feels is the ground under that wheel
            if (!air && front_air && !rear_air && wheelie_up <= 0.0 && nose_a <= 0.0)
                slope = _local_slope(f, -BB_REAR, RWR, cos(clampf(pitch, -1.3, 1.3)));
            bool rear_down = !air && !rear_air;
            skid = false;
            _step_sprint(dt, inp, throttle, brake, in_water);
            _step_loads(dt);
            double a_long = _step_drive(dt, inp, throttle, brake, in_water, slope, rear_down, n_rear, n_front);
            double va = _step_steer(dt, f, brake_k, steer_input, roll_keys, a_long, n_rear, n_front);
            f = fwd();   // (the steering turned the bike)
            _step_move(dt, f);
            _step_vertical(dt, f, throttle, brake);
            _step_hop(dt, inp);
            _step_lip(dt, f, brake);
            _step_wheels(dt, f, in_water, va);
        }
    }
}
