// Port of godot/scripts/bike/bike_physics.gd, group B: stage 5 (_step_drive: pedalling, brakes, pump, drag), the drag /
// spin-out helpers and the tyre helpers (_fric, _ls, _relax_t, _brake_mu, _lock_slide, _brake_dirt, _grip_step,
// _local_slope), flow_up, is_sane, reset_body. Line for line; BMX_OLD_* branches and probes left out.
using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    public sealed partial class BikePhysics
    {
        /// stage 5: along the bike: pedalling, sprint, brakes (each limited by its tyre), the pump, rolling + air drag,
        /// holding at a stop / backing up, flow. Returns the longitudinal acceleration used (a_long)
        double _step_drive(double dt, in RideInput inp, double throttle, bool brake, bool in_water, double slope, bool rear_down, double nR, double nF)
        {
            double a_long = 0.0;
            double sp_k = sprint;
            double n_tot = n_load;
            _speed_tuck_step(dt, throttle);
            // the brakes cool, and fade once they are hot enough (the rotor glow reads the same heat)
            brake_heat *= exp(-dt / HEAT_TAU);
            brake_fade = smooth01((brake_heat - FADE_FROM) / (FADE_FULL - FADE_FROM));
            if (brake_fade > 0.3 && !_fade_warn)
            {
                _fade_warn = true;
                if (host.msg_idle()) host.flash("BRAKES FADING");
            }
            else if (brake_fade < 0.1)
                _fade_warn = false;
            double mu_f = _mu_f * T["grip"];
            double mu_r = _mu_r * T["grip"];
            double mu = mu_r * SH_R + mu_f * (1.0 - SH_R);
            // --- longitudinal ---
            if (!air)
            {
                double vp = maxf(v, 0.5);
                double gk = gear_k();
                // Top speed: scales the pedalling power to reach it and less drag holding it back
                double ts = T["topSpeed"];
                double p_top = spin_top(sp_k);
                // sprinting, the slower the rider is the harder they stamp on it: all of the extra push from a
                // standstill, less and less as the speed comes back, none by ~40 km/h
                double kick = T.get("sprintKick", 0.9) * slowness(v);
                double p_mul = (1 + (T["sprintPower"] - 1 + kick) * sp_k) * ts;
                double cad = v / (0.7 * spin_top(0.0));   // (1 = ~105 rpm)
                double grind = gear < 0 ? 1.0 : 0.35 + 0.65 * smooth01((cad - 0.15) / 0.7);
                double drive = ((rear_down && !(v < -0.3 && rev_cap > 3.0)) ? throttle : 0.0) * minf(T["pedalLaunch"] * p_mul / ts / gk, T["pedalPower"] * p_mul / vp) * grind * clampf((p_top - v) / 2.5, 0, 1);
                drive *= 1.0 - KICK_LOSS * _kick_k;   // (a kicked-back crank costs a little of the stroke)
                drive *= 1.0 - chain_slip_k;   // (the chain skipping after a shift under load)
                double drive_cap = mu_r * nR;
                // (the rear's grip follows its load only after a little rolling: _nR_s is eased in _grip_step)
                if (!is_nan(_nR_s)) drive_cap = mu_r * _nR_s;
                drive_cap *= _ls(_or(_nR_s, nR), G * SH_R);
                if (drive > drive_cap)
                {
                    spin = minf(1.0, (drive - drive_cap) / 3); drive = drive_cap + (drive - drive_cap) * 0.15;
                }
                a_long = absf(drive);
                double a = drive - G * sin(slope);
                // two brakes, each limited by its own tyre: the front does most of the stopping, the rear goes light and
                // locks easily. Squeeze a lever past what its tyre can hold and that wheel locks and slides
                // (the levers are strong enough to lock either wheel on any surface: the tyre's braking grip is what stops)
                double lever = T["brakeForce"];
                double fb_r = lever * T.get("brakeRear", 0.6) * brake_r;
                double fb_f = lever * T.get("brakeFront", 0.75) * brake_f * (front_air ? 0.0 : 1.0);
                double bg = T.get("brakeGrip", 1.0);
                double bmu_f = _or(_bmu_f, 0.7) * bg;
                double bmu_r = _or(_bmu_r, 0.7) * bg;
                double cap_r = maxf(0.05, bmu_r * nR * _ls(nR, G * SH_R));
                double cap_f = maxf(0.05, bmu_f * nF * _ls(nF, G * (1.0 - SH_R)) * T.get("frontGrip", 1.0));
                double slide_r = 0.8; double slide_f = 0.8;
                {
                    // dirt isn't asphalt: the brake limit under each tyre wanders with loose patches and jumps about on
                    // rough ground, and a locked tyre ploughs at less
                    V2 dk = _brake_dirt(dt);
                    cap_f = maxf(0.05, cap_f * dk.x); cap_r = maxf(0.05, cap_r * dk.y);
                    slide_f = _lock_slide(surf_f) * (1.0 - 0.15 * minf(1.0, brk_loose_f));
                    slide_r = _lock_slide(surf_r) * (1.0 - 0.15 * minf(1.0, brk_loose_r));
                }
                if (_brake_feel)
                {
                    // the brake key = a rider squeezing by feel. He brakes to the grip he FEELS (the last ~0.15 s of it)
                    double fcap_f = cap_f; double fcap_r = cap_r;
                    // brake drift: braking hard INTO a turn he keeps the rear locked and lets it come round.
                    // tk = how much he lets it: brakeDrift x how hard the bike is turning (none riding straight)
                    double tk = clampf(T.get("brakeDrift", 0.6) * smooth01((absf(lat_a) - 1.0) / 3.0), 0.0, 1.5);
                    {
                        double lag = maxf(0.01, T.get("brakeFeelLag", 0.15));
                        double fk = minf(1.0, dt / lag);
                        _feel_f = is_nan(_feel_f) ? cap_f : _feel_f + (cap_f - _feel_f) * fk;
                        // (the rear: he hears it skid and lets off, so a lock tells him quickly)
                        double fk_r = minf(1.0, dt * (1.0 / lag + 24.0 * T.get("brakeSkidEar", 1.0) * rear_lock * maxf(0.0, 1.0 - 0.8 * tk)));
                        _feel_r = is_nan(_feel_r) ? cap_r : _feel_r + (cap_r - _feel_r) * fk_r;
                        fcap_f = _feel_f * T.get("brakeFrontHold", 0.93); fcap_r = _feel_r;
                    }
                    // ...and eases the rear off the moment it starts stepping out sideways, so it grips sideways again
                    double r_ease = smooth01((absf(slip) - 0.04 - T.get("brakeDriftAngle", 0.3) * tk) / 0.08);
                    fb_r = minf(fb_r, fcap_r * lerpf(1.0 + 0.25 * T.get("brakeSkid", 0.4) + 0.4 * tk, 0.85, r_ease));
                    fb_f = minf(fb_f, fcap_f);
                }
                else
                {
                    _feel_f = cap_f; _feel_r = cap_r;
                    // the bare rear lever locks what you squeeze, but a rider whose locked rear swings well out of line
                    // lets it off a little (riderSkill) before it washes out
                    if (fb_r > cap_r)
                    {
                        double out_k = smooth01((absf(slip) - T.get("brakeRearLet", 0.55) * T["slipMax"]) / (0.3 * T["slipMax"])) * clampf(T.get("riderSkill", 1.0), 0.0, 1.0);
                        fb_r = lerpf(fb_r, minf(fb_r, cap_r * 0.92), out_k);
                    }
                }
                rear_lock = move_toward(rear_lock, fb_r > cap_r ? clampf((fb_r - cap_r) / (0.25 * cap_r), 0.0, 1.0) : 0.0, dt * 8.0);
                front_lock = move_toward(front_lock, fb_f > cap_f ? clampf((fb_f - cap_f) / (0.25 * cap_f), 0.0, 1.0) : 0.0, dt * 8.0);
                fb_r = rear_down ? lerpf(minf(fb_r, cap_r), cap_r * slide_r, rear_lock) : 0.0;
                fb_f = lerpf(minf(fb_f, cap_f), cap_f * slide_f, front_lock);
                // hot brakes: what the pads can still deliver (taken off the force that gets through, not off the lever)
                double fade_k = 1.0 - T.get("brakeFade", 0.35) * brake_fade;
                fb_r *= fade_k; fb_f *= fade_k;
                double b_all = fb_r + fb_f;
                // (gated on any tyre down, not on the rear; each brake is already zero while its own wheel is off the ground)
                bool braked_fwd = brake && !air && v > 0.3;
                // braking while rolling backwards; a fresh press from a standstill backs up on purpose (brake_back)
                bool braked_rev = brake && !air && v < -0.3 && (rev_cap > 3.0 || !brake_back);
                bool braked = braked_fwd || braked_rev;
                // (only what was really applied: backing up on purpose holds the brake key with no brake on)
                _fb_f = braked ? fb_f : 0.0; _fb_r = braked ? fb_r : 0.0;
                _a_rear = maxf(0.0, drive) + ((braked && rear_down) ? fb_r : 0.0);   // what the REAR tyre carries along the bike
                _b_prev = braked ? b_all : 0.0;
                double drive_p = drive;
                if (braked_fwd)
                {
                    a -= b_all; a_long += b_all; drive -= b_all;
                    brake_heat += b_all * v * dt / 45.0;
                    drive_p = drive;
                }
                else if (braked_rev)
                {
                    a += b_all; a_long += b_all; drive += b_all;
                    brake_heat += b_all * -v * dt / 45.0;
                }
                else
                {
                    rear_lock = move_toward(rear_lock, 0.0, dt * 8.0); front_lock = move_toward(front_lock, 0.0, dt * 8.0);
                }
                a_drive = drive;
                // (a_drive is the signed push along the bike, right for the pitch torque. Things that read it as
                // "pedalling" read a_pedal)
                a_pedal = drive_p;
                // --- the pump = the legs' stroke. Pumping is work done against the ground's push: straightening the legs
                // while the ground presses harder than standing weight or bending them while it goes light adds that
                // difference x the stroke to the ride's speed; the other way round costs it. On a straight slope there is
                // nothing to gain. (Luginbuhl et al. 2023, Golembiewski et al. 2023)
                pump_push = 0.0;
                bool btn = inp.hop && !hop_block;
                double p_fwd = clampf((body_in - 0.12) / 0.6, 0.0, 1.0);
                double p_back = clampf((-body_in - 0.12) / maxf(0.05, 0.4 - 0.12), 0.0, 1.0);
                double p_in = maxf(btn ? 1.0 : 0.0, p_fwd * T.get("pumpStick", 1.2));
                // (one wheel down is enough: over a roller's crest the front goes light and leaves the ground)
                bool ground_ok = !(front_air && rear_air) && hop_t <= 0.0 && v > T.get("pumpMinSpeed", 2.0) && man_a < 0.08;
                pump_on = ground_ok && (btn || p_fwd > 0.0 || p_back > 0.0);
                var terrain_pump = host.terrain;
                double pl_prev = pleg;
                double pl_t = clampf(p_fwd - _bend_in, -1.0, 1.0);
                // (a rider straightens or bends the legs at most a whole stroke in PUMP_STROKE_T)
                pleg = move_toward(pleg, pl_t, dt * 2.0 / PUMP_STROKE_T);
                if (ground_ok && prep < 0.1 && pop_wait <= 0.0 && kick_t <= 0.0 && since_land > 0.1)
                {
                    // how much harder (or lighter) than standing weight the ground pushes on rider + bike along their
                    // path: speed² x the ground's curve under the bike, across about the wheelbase (+ dip, - crest)
                    double cx = cos(_or(course, heading)) * PUMP_SPAN;
                    double cz = -sin(_or(course, heading)) * PUMP_SPAN;
                    double h0 = terrain_pump.deck_height(x, z);
                    double kap = (terrain_pump.deck_height(x + cx, z + cz) + terrain_pump.deck_height(x - cx, z - cz) - 2.0 * h0) / (PUMP_SPAN * PUMP_SPAN);
                    double n_ex = clampf(v * v * kap / G, -1.0, 1.5);
                    double de = clampf(T["riderMass"], 0.0, 0.7) * n_ex * G * 0.5 * PUMP_STROKE * (pleg - pl_prev) * T.get("pumpLegs", 1.0);
                    pump_push = de / (maxf(2.0, v) * dt);
                    a += pump_push;
                    if (pump_push > 0.0) pump_acc += pump_push * dt;
                    if (btn && absf(n_ex) > 0.15) pump_press_t += dt;   // (a press spent pumping doesn't hop when it's let go)
                }
                if (absf(pleg - pl_t) < 0.02)
                {
                    if (pump_acc > 0.35)
                    {
                        flow_up();
                        if (host.msg_idle()) host.flash($"PUMP +{roundi(pump_acc * 3.6)} km/h");
                    }
                    pump_acc = 0.0;
                }
                // pumping a berm (Golembiewski et al. 2023): the pump held while a berm carries the turn pushes the bike
                // along. Physically small; bermPump scales it
                double berm_c = clampf(berm_k / maxf(0.05, T.get("bermAssist", 1.0)), 0.0, 1.0);
                if (ground_ok && prep < 0.1 && p_in > 0.0 && berm_c > 0.05 && corner_g > 0.3)
                {
                    double bp = T.get("bermPump", 0.12) * minf(corner_g, 8.0) * berm_c * minf(p_in, 1.0);
                    a += bp; pump_push += bp;
                    if (btn) pump_press_t += dt;   // (a press spent pumping the berm doesn't hop when it's let go)
                }
                if (absf(pump_push) > 0.05)
                {
                    pump_gain += pump_push * dt * 3.6; pump_idle = 0.0;
                }
                else
                {
                    pump_idle += dt;
                    if (pump_idle > 1.2) pump_gain = move_toward(pump_gain, 0.0, dt * maxf(4.0, absf(pump_gain) * 1.5));
                }
                pump_gain = clampf(pump_gain, -30.0, 60.0);
                // a manual held in the sweet spot keeps the speed rolling (like the games' manual boost)
                if (man_zone) a += T.get("manBoost", 0.5);
                double carry = 1 - T["flowCarry"] * flow / FLOW_MAX;
                // rolling drag per tyre on its own ground (sand drags, hardpack rolls), weighted by the load like the grip
                double rr_f = surf_f == 0 ? 0.32 : surf_f == 3 ? 0.42 : 0.1;
                double rr_r = surf_r == 0 ? 0.32 : surf_r == 3 ? 0.42 : 0.1;
                double roll = (rr_r * SH_R + rr_f * (1.0 - SH_R)) * T["rollRes"] * signf(v) * minf(1.0, absf(v) * 4);
                // fresh snow: the tyres plough through it, more the faster
                if (snow_k > 0.0 && !air)
                    roll += snow_k * (SNOW_DRAG + SNOW_DRAG_V * absf(v)) * signf(v) * minf(1.0, absf(v) * 4);
                // aerodynamics: the drag is the rider's frontal area (tucked = less, sat up = an air brake)
                _aero_update(throttle);
                double k_drag = T["airDrag"] / (ts * ts) * drag_k();
                a -= (roll + k_drag * v * absf(v) * aero_k) * carry;
                if (in_water) a -= 0.06 * v;   // (was 0.7: the water dragged a rider to a halt)
                v = clampf(v + a * dt, -maxf(3.0, rev_cap), 24 * maxf(1.0, ts));
                rev_cap = maxf(3.0, minf(rev_cap, -v));   // the extra reverse room (fakie landing) only shrinks
                // braked to a stop the brake holds the bike where it is until it's let go; pressing brake again from a
                // standstill backs the bike up
                if (!brake)
                {
                    brake_stop = false; brake_back = absf(v) < 0.3;
                }
                else if (absf(v) <= 0.3 && !brake_back)
                    brake_stop = true;
                // reverse like bike / moto games: the brake held at a stop for REV_HOLD s backs the bike up
                // (only on ground flatter than ~8 deg: on a real slope the held brake keeps you parked)
                if (brake && brake_stop && throttle < 0.1 && rev_on_hold && absf(_g_pitch) < REV_SLOPE)
                {
                    _rev_hold += dt;
                    if (_rev_hold > REV_HOLD) { brake_stop = false; brake_back = true; }
                }
                else
                    _rev_hold = 0.0;
                // ...but only where the tyres can: past the friction angle the locked bike slides down the slope
                if (brake_stop && G * absf(sin(slope)) > minf(T["brakeForce"] * (T.get("brakeRear", 0.6) * brake_r + T.get("brakeFront", 0.75) * brake_f), 0.85 * mu * n_tot))
                    brake_stop = false;
                if (brake_stop || (foot_down && throttle < 0.1 && !(brake && brake_back)))
                    v = 0.0;   // a foot on the ground holds the bike still (no creeping on a slope)
                else if (brake && brake_back && v <= 0.3)
                    v += (-1.3 - v) * minf(1.0, dt * 3);
                if (throttle < 0.1 && !brake && absf(v) < 0.05 && absf(_g_pitch) < 0.03) v = 0;
            }
            else
            {
                // no pumping in the air (these kept their last ground value through a jump: the HUD pump bar stayed up)
                pump_push = 0.0; pump_on = false; pump_acc = 0.0;
                pleg = clampf(clampf((body_in - 0.12) / 0.6, 0.0, 1.0) - _bend_in, -1.0, 1.0);   // (the legs' length carried to the landing)
                // air drag doesn't stop at the lip: the same body area slows the flight (on the full speed, along it)
                _aero_update(throttle);   // (the flight tucks too)
                double k_air = T["airDrag"] / (T["topSpeed"] * T["topSpeed"]) * aero_k * drag_k();
                double sp_air = sqrt(v * v + vy * vy);
                v -= k_air * sp_air * v * dt; vy -= k_air * sp_air * vy * dt;
            }
            if (flow > 0)
            {
                flow_t += dt;
                if (brake && v > 1) flow = maxf(0.0, flow - dt * 3);
                else if (flow_t > T["flowTime"]) flow = maxf(0.0, flow - dt * 1.5);
            }
            skid = brake && rear_down && v > 0.5 && rear_lock > 0.15;
            double top_now = spin_top(sprint);
            // the chain skip: full loss for most of it, biting back over the last third
            chain_slip = maxf(0.0, chain_slip - dt);
            chain_slip_k = chain_slip > 0.0 ? smoothstep(0.0, CHAIN_SLIP_T * 0.35, chain_slip) : 0.0;
            spin_out_k = 0.0;
            if (!air && throttle_in > 0.3 && !crash_on && top_now > 0.5)
                spin_out_k = smoothstep(0.9, 1.0, v / top_now) * clampf(throttle_in, 0.0, 1.0);
            if (v > top_now + 0.3) spun_out = true;
            else if (v < top_now - 0.8) spun_out = false;
            pedal += (((!air && !spun_out) ? throttle : 0.0) - pedal) * minf(1.0, dt * 6);
            throttle_in = throttle;
            return a_long;
        }

        // real rider air drag (2026-11-28): an upright DH rider with pads, CdA ~0.55 m^2 -> DRAG_REAL scales every drag term
        public static double drag_k() => DRAG_REAL;

        /// the speed the legs spin out at in the current gear (m/s): cadence x the real ratio x the rear wheel
        public double spin_top(double p_sprint)
        {
            return lerpf(SPIN_RPM, SPIN_SPRINT, clampf(p_sprint, 0.0, 1.0)) / 60.0 * TAU * drive_ratio() * RWR;
        }

        /// the sideways friction (force / normal) the tyres need for a horizontal turn a_lat (+ = left) on ground
        /// tilted bk (+ = rising to the right): 0 = the ground's tilt carries it all, + = the tyres push left
        static double _fric(double a_lat, double cb, double sb)
        {
            return (a_lat * cb - G * sb) / maxf(0.2 * G, G * cb + a_lat * sb);
        }

        /// load sensitivity (Magic Formula pD2 < 0, Schmeitz 2013 sl. 8): a tyre pressed harder grips a little less per
        /// unit of load: x the grip at the tyre's resting load n0, -LOAD_SENS per 100 % more load
        double _ls(double n, double n0)
        {
            return clampf(1.0 - LOAD_SENS * (n / maxf(0.1, n0) - 1.0), 0.75, 1.15);
        }

        /// a tyre's grip follows a change over a DISTANCE rolled, not a time (relaxation length): t_ref is the lag at
        /// RELAX_V (6 m/s), so it is shorter at speed and longer slow, within 0.015 .. 0.12 s
        double _relax_t(double t_ref, double va)
        {
            return t_ref > 0.005 ? clampf(t_ref * RELAX_V / maxf(va, 1.5), 0.015, 0.12) : 0.005;
        }

        /// a surface's braking grip (Ride > Brakes > Surfaces) / a locked tyre's slide share there
        double _brake_mu(int su)
        {
            int i = clampi(su, 0, 3);
            return T.get(BRAKE_MU_KEYS[i], BRAKE_MU[i]);
        }

        double _lock_slide(int su)
        {
            int i = clampi(su, 0, 3);
            return T.get(LOCK_SLIDE_KEYS[i], LOCK_SLIDE[i]);
        }

        /// dirt braking: what share of its braking grip each tyre has where it is now (x = front, y = rear). Loose
        /// patches take up to brakeLoose x 0.45 off, rough ground makes it jump about by up to brakeRough x 0.3 every
        /// ~0.4 m rolled. Sets brk_loose_f / brk_loose_r.
        V2 _brake_dirt(double _dt)
        {
            if (_grip_noise == null)
            {
                _grip_noise = new Noise(913) { frequency = 0.22, fractal_octaves = 2 };
                _grip_rng.seed = 4711;
            }
            if (_brk_noise == null)
                _brk_noise = new Noise(2741) { frequency = 0.9, fractal_octaves = 2 };
            double ch = cos(heading); double sh = sin(heading);
            double rx = x - ch * BB_REAR; double rz = z + sh * BB_REAR;
            double fx = rx + ch * L; double fz = rz - sh * L;
            double lk = T.get("brakeLoose", 1.0) * 0.45;
            double rk = T.get("brakeRough", 1.0) * 0.3 * smooth01(_grip_rough / 30.0);
            V2 @out = new V2(1.0, 1.0);
            for (int i = 0; i < 2; i++)
            {
                double px = i == 0 ? fx : rx;
                double pz = i == 0 ? fz : rz;
                double s = BRAKE_LOOSE_S[clampi(i == 0 ? surf_f : surf_r, 0, 3)];
                double n = 0.6 * (0.5 + 0.5 * _grip_noise.get_noise_2d(px, pz)) + 0.4 * (0.5 + 0.5 * _brk_noise.get_noise_2d(px, pz));
                double ls = smooth01((n - 0.35) / 0.5) * s;
                double jit = 0.5 + 0.5 * _brk_noise.get_noise_2d(px * 3.0 + 517.0, pz * 3.0 - 233.0);
                double k = clampf(1.0 - lk * ls - rk * jit, 0.35, 1.0);
                if (i == 0) { @out.x = k; brk_loose_f = ls; }
                else { @out.y = k; brk_loose_r = ls; }
            }
            return @out;
        }

        /// the rear tyre's grip sim: the slip (heading vs travel) as a second-order motion slip_w; returns the rear's
        /// sideways grip (grip_r)
        double _grip_step(double dt, double va, double mu, double nR, double u_lat_in)
        {
            if (_grip_noise == null)
            {
                _grip_noise = new Noise(913) { frequency = 0.22, fractal_octaves = 2 };
                _grip_rng.seed = 4711;
            }
            double spd = smooth01((va - 1.0) / 5.0);
            // the ground under the rear tyre: loose patches a few metres across (gravel, dust over hardpack)
            double rx = x - cos(heading) * BB_REAR;
            double rz = z + sin(heading) * BB_REAR;
            double s_loose = surf_r == 0 ? 1.0 : surf_r == 1 ? 0.2 : surf_r == 2 ? 0.7 : 1.4;
            double n = 0.5 + 0.5 * _grip_noise.get_noise_2d(rx, rz);
            loose = smooth01((n - 0.4) / 0.45) * s_loose;
            double patch = 1.0 - T.get("gripLoose", 0.5) * 0.4 * loose;
            // the rear tyre's friction circle: what braking / driving uses along the bike isn't there sideways
            double @lock = rear_lock;   // the rear brake past what the tyre holds (the brakes, longitudinal step)
            // (its grip follows the load over ~0.08 s, a few tens of cm rolled)
            _nR_s = is_nan(_nR_s) ? nR : _nR_s + (nR - _nR_s) * minf(1.0, dt / _relax_t(0.08, va));
            nR = _nR_s;
            double r_cap = maxf(0.3, mu * nR);
            double use = clampf(_a_rear / r_cap, 0.0, 1.0);   // its own drive / brake only (the front brake is the front's)
            use = maxf(use, @lock);
            if (spin > 0.0) use = maxf(use, 0.85 + 0.15 * spin);
            double lat_k = sqrt(maxf(0.0, 1.0 - use * use));
            lat_k = lerpf(lat_k, 0.12, @lock);   // a sliding tyre still drags a little sideways
            double load_r = clampf(nR / (G * SH_R), 0.0, 1.4);   // a light rear (bumps, nose-heavy braking) grips less
            double g = clampf(lat_k * patch * sqrt(load_r), 0.0, 1.2);
            grip_r = g;
            // tyre squirm: in a turn the tyres run a few degrees of slip angle, more as they near the limit
            double u_lat = clampf(u_lat_in, -1.0, 1.0);   // + = the tyres pushing left
            double a_lat = u_lat;   // (only its sign is used below: which way the rear is thrown)
            _squirm = T.get("gripSquirm", 1.0) * (0.025 * u_lat + 0.07 * u_lat * u_lat * u_lat) * spd * (1.0 + 0.5 * loose);
            // yaw against the travel: rear tyre stiffness vs the front pushing it round, the rider catching it
            double catch_r = T.get("gripCatch", 0.6);
            double k_r = 15.0 * g;
            // (the front can only swing the rear round with sideways grip it has left)
            double k_f = 18.0 * T.get("gripRearLock", 1.0) * spd * _circ_f;
            double k = k_r - k_f + 4.0 * catch_r;
            double c = 2.2 + 3.0 * g + 1.5 * catch_r;
            double acc = -k * (sin(slip) - _squirm) - c * slip_w;
            // wheelspin in a turn: the spinning rear is thrown out of the turn
            double pw = T.get("gripPower", 1.0);
            acc += pw * spin * signf(a_lat) * 6.0 * spd;
            // pedal strokes on loose ground: each stamp nudges the rear (alternating sides)
            acc += pw * sin(crank * 2.0) * clampf(a_pedal / r_cap, 0.0, 1.0) * (1.25 - minf(1.0, g)) * 3.0 * spd;
            slip_w += acc * dt;
            // bumps: rough ground makes a rear that's cornering near its limit drift out of the turn - a gentle push.
            // weight over the outside pedal keeps the rear planted over bumps; hanging inside it skips about more
            double bmp = T.get("gripBumps", 1.0) * (1.0 - T.get("weightSteady", 0.5) * maxf(0.0, weight_in) + 0.5 * maxf(0.0, -weight_in));
            // (a held whip: the rider has the rear light and floats it over the bumps)
            bmp *= 1.0 - T.get("whipGlide", 0.6) * whip_hold;
            double jolt = minf(absf(compress_v - _grip_cv) / maxf(dt, 1e-4), 60.0);
            _grip_cv = compress_v;
            _grip_rough += (jolt - _grip_rough) * minf(1.0, dt * 5.0);
            double lim_k = smooth01((absf(u_lat) - 0.5) / 0.5);   // only near the grip limit
            slip_w += bmp * signf(a_lat) * lim_k * minf(_grip_rough / 30.0, 1.0) * 1.2 * spd * dt;
            // chatter: pebbles, ruts - a small smooth random wander, bigger on loose ground / sliding
            slip_w += bmp * _grip_rng.randfn(0.0, 1.0) * sqrt(dt) * spd * (0.1 + 0.45 * loose + 0.8 * (1.0 - minf(1.0, g)));
            slip_w = clampf(slip_w, -4.0, 4.0);
            // drawn: the rider steers into the slide (front pointing along the travel) - catch strength sets how much
            double bc = clampf(-(slip - _squirm) * (0.5 + 0.4 * catch_r) - slip_w * 0.06, -0.55, 0.55) * spd;
            bar_catch += (bc - bar_catch) * minf(1.0, dt * 14.0);
            return g;
        }

        double _local_slope(V3 f, double xx, double R, double cp0)
        {
            return atan((_wheel_ground(f, xx + 0.05 / cp0, R, cp0) - _wheel_ground(f, xx - 0.05 / cp0, R, cp0)) / 0.1);
        }

        public void flow_up()
        {
            flow = minf(FLOW_MAX, floor(flow) + 1); flow_t = 0;
        }

        /// Every float field finite? (the frame loop's safety net)
        public bool is_sane()
        {
            foreach (double k in new double[] {
                x, z, y, vy, v, heading, pitch, pitch_v, lean, lean_v, steer, steer_in, steer_in_v, slip, slip_w, course, compress, compress_v,
                body_x, body_xv, hip_shift, hip_v, air_lean, air_pull, a_drive,
                body_y, body_v, air_w, air_tilt, air_tilt_v, bike_lean, counter, flick, flick_v, man_a, man_w, bank, corner_g })
            {
                if (!is_finite(k))
                    return false;
            }
            return true;
        }

        /// after a bad step: zero the body / rider state so a NaN there can't keep poisoning the ride
        public void reset_body()
        {
            body_v = 0; body_y = y; body_x = 0; body_xv = 0; hip_shift = 0; hip_v = 0; v_last = NAN;
            air_lean = 0; air_pull = 0; _air_pull_v = 0.0; a_drive = 0; pitch_v = 0; compress_v = 0; lean_v = 0; steer_in_v = 0;
            air_w = 0; air_tilt = 0; air_tilt_v = 0; flick = 0; flick_v = 0; bike_lean = 0; counter = 0;
            man_a = 0.0; man_w = 0.0; bank = 0.0; _bank_hold = 0.0; bank_v = 0.0; corner_g = 0.0;
            nose_a = 0.0; nose_w = 0.0; gest_hop = 0.0; _hop_buf = 0.0; _pop_miss = 0.0;
            // (is_sane checks slip_w / steer_in too: left NaN they failed every later step and froze the bike)
            slip_w = 0.0; steer_in = 0.0; knock = 0.0; _gx_lean = 0.0; bank_lean = 0.0; bank_sq = 0.0; _bike_lead = 0.0; _weave = 0.0;
            _amax = 99.0; _amin = -99.0; yaw_rate = 0.0;
        }
    }
}
