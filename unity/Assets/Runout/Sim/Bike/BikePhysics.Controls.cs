// Port of godot/scripts/bike/bike_physics.gd: _step_controls, _step_ground, _step_sprint, _step_loads,
// _speed_tuck_step, _aero_update (group A, see unity/Tools/PORT_RULES.md).
using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    public sealed partial class BikePhysics
    {
        /// stage 1: the controls. Brake levers, the body stick, air control (tilt / spin / tuck inputs) and the lip throw.
        /// Returns the brake level (0 when S was a flip throw at a lip, not a brake)
        double _step_controls(double dt, in RideInput inp, double throttle, double steer_input)
        {
            // two levers: "brake" (S / LT) squeezes both (the front by brakeFrontMix), brake_front / brake_rear one each
            brake_r = maxf(inp.brake, inp.brake_rear);
            brake_f = maxf(inp.brake * T.get("brakeFrontMix", 0.7), inp.brake_front);
            // the levers take a moment to bite (pads closing, the tyre's load building): squeezed over brakeRamp s, let go
            // at once-ish
            double up = dt / maxf(0.01, T.get("brakeRamp", 0.15));
            _brk_r = move_toward(_brk_r, brake_r, brake_r > _brk_r ? up : dt * 12.0);
            _brk_f = move_toward(_brk_f, brake_f, brake_f > _brk_f ? up : dt * 12.0);
            brake_r = _brk_r; brake_f = _brk_f;
            // the brake key is a rider squeezing both with feel: they keep each wheel at the edge of locking (the rear a
            // touch past it, a light skid). The front-only / rear-only keys are the bare levers: lock what you squeeze
            _brake_feel = inp.brake >= maxf(inp.brake_front, inp.brake_rear);
            // the rider's reflexes in trouble (riderSkill x how full the crash meters are): ease off the brakes, the front most
            double rfx = T.get("riderSkill", 1.0) * smooth01((risk - 0.15) / 0.5);
            double rb = T.get("reflexBrake", 0.6);
            brake_f *= 1.0 - rb * rfx; brake_r *= 1.0 - rb * 0.67 * rfx;
            // the rear thrown up off the ground with the front still down (a rear rim strike, a rock) and no nose manual asked
            // for: the rider lets the front lever off at once (held on, the brake's torque about the front axle turned the
            // kick into a front flip). Eased in over ~0.05 s, back over ~0.25 s
            bool rear_up = _brake_feel && rear_air && !front_air && !air && nose_a <= 0.0 && body_in < 0.3;
            _rear_up_k = move_toward(_rear_up_k, rear_up ? 1.0 : 0.0, dt * (rear_up ? 20.0 : 4.0));
            brake_f *= 1.0 - 0.85 * _rear_up_k;
            double brake_k = maxf(maxf(inp.brake, brake_r), inp.brake_front);
            bool brake = brake_k > 0.1;
            // rider body stick (gamepad right stick): fore / aft weight, side lean. Works the whole ride
            pad = inp.pad;
            // do pedal / brake (W / S) also tilt the bike in the air and throw flips at a lip? Only with the classic keys setting
            bool ws_air = !pad && inp.ws_air;
            body_in = clampf(inp.body_fwd, -1.0, 1.0);
            // the stick snapped forward to pop a lip is still forward for a moment after the take-off: it is the pop,
            // not "nose down". Held until the stick comes back towards the centre, 0.5 s at most
            if (_pop_latch)
            {
                if (body_in < 0.3 || (air && air_time > 0.5) || (!air && pop_wait <= 0.0 && !pro_flight)) _pop_latch = false;
                else if (air) body_in = 0.0;
            }
            left_back = inp.left_back;
            flick_in = clampf(inp.body_lean, -1.0, 1.0);
            body_in_s += (body_in - body_in_s) * minf(1.0, dt * 10);
            // air control: W / S tilt the bike nose down / up against the rider's body (limited, see air_tilt; a
            // flip has to be thrown at the lip), A / D lean it left / right, Space tucks. A / D and Space held at
            // take-off count only once pressed again in the air (carving into a jump mustn't lean you).
            if (!air)
            {
                air_lock_h = inp.hop; air_lock_a = absf(steer_input) > 0.1; _lock_a0 = steer_input;
                _air_own = 0.0;
            }
            else
            {
                if (!inp.hop) air_lock_h = false;
                // (a steer held off the lip counts again as soon as it's let go OR clearly moved)
                if (absf(steer_input) <= 0.1 || absf(steer_input - _lock_a0) > 0.35) air_lock_a = false;
                double used = maxf(new V2(flick_in, body_in).length(), air_lock_a ? 0.0 : absf(steer_input));
                if (ws_air) used = maxf(used, absf(throttle - brake_k));
                _air_own = used > 0.15 ? 1.0 : maxf(0.0, _air_own - 2.5 * dt);
            }
            // (the playground's test rider gets a stronger hand: TEST_ASSIST, so test runs land; the player keeps airAssist)
            air_help = air ? maxf(T.get("airAssist", 0.6), test_rider ? TEST_ASSIST : 0.0) * (1.0 - _air_own) : 0.0;
            double lean_in = 0.0;
            if (air)
            {
                // the right stick doesn't spin the bike, it points it (see air_stick); only pushed right to the top
                // / bottom edge it keeps the bike turning over (flips in the air). The spin builds up gently while the
                // stick is held at the edge and eases out quicker when it comes off; the longer held, the faster
                var es = _edge_spin(body_in, edge_s, spin_hold, dt);
                edge_s = es.x; spin_hold = es.y;
                spin_k = absf(edge_s) > 0.01 ? _edge_grow(spin_hold) : 1.0;
                lean_in = clampf((ws_air ? throttle - brake_k : 0.0) + edge_s * T.get("stickSpinMax", 0.7), -1.0, 1.0);
                // the same at the left / right edge: a flat spin
                var ys = _edge_spin(flick_in, yaw_edge_s, yaw_hold, dt);
                yaw_edge_s = ys.x; yaw_hold = ys.y;
                double y_t = yaw_edge_s * T.get("stickYawRate", 5.0) * _edge_grow(yaw_hold);
                // (a spin is carved off the lip: from the air alone only SPIN_AIR_ONLY of the rate; tucked it turns faster)
                double wound = maxf(0.0, _spin_in * signf(yaw_edge_s));
                y_t *= lerpf(SPIN_AIR_ONLY, 1.0, wound) / maxf(air_inertia, 0.5);
                if (absf(flick_in) < 0.815 && land_prep > 0.2)
                {
                    // coming in to land off a spin: the rider twists it the rest of the way straight if it's close
                    double off = wrapf(slip, -PI, PI);
                    // (landing help: only with the hands off the stick, airAssist of it)
                    if (absf(off) < 1.2) y_t = lerpf(y_t, clampf(-off * 6.0, -4.0, 4.0), air_help);
                }
                // the spin answers the stick at once and stops soon after it's let go
                double y_resp = absf(y_t) > absf(stick_yaw) ? 11.0 : (absf(_spin_in) > 0.2 ? SPIN_OPEN : 10.0);
                stick_yaw += (y_t - stick_yaw) * minf(1.0, y_resp * dt);
            }
            else
            {
                edge_s = 0.0; spin_hold = 0.0; spin_k = 1.0;
                yaw_edge_s = 0.0; yaw_hold = 0.0; stick_yaw = 0.0;
            }
            flip_in = -lean_in;                                          // + = nose up
            // 360 deg air control with the right stick: x = lay the bike over left / right, y = nose up / down. It sets
            // the bike's attitude (held where the stick points, back to the landing aim when let go)
            V2 stick_raw = air ? new V2(flick_in, -body_in) : V2.Zero;
            if (stick_raw.length() < 0.08) stick_raw = V2.Zero;
            // eased: the bike follows a smoothed stick (stickAirEase /s)
            air_stick += (stick_raw - air_stick) * (1.0 - exp(-dt * T.get("stickAirEase", 3.5)));
            if (!air) air_stick = V2.Zero;
            else style_air += minf(air_stick.length(), 1.0) * dt;
            air_lean += (lean_in - air_lean) * minf(1.0, dt * 6);
            // the rider tucks into a flip as well as when Space is held
            _tuck_in = air && inp.hop && !air_lock_h;
            double pull_t = maxf(_tuck_in ? 1.0 : 0.0, air ? 0.7 * absf(flip_in) : 0.0);
            // right after take-off the rider lifts the bike up into the body (it moves about the shared centre of
            // mass, the arc stays the same), then lets it down to reach for the landing (land_prep)
            if (air)
            {
                double lift_k = smooth01((air_time - 0.03) / 0.1) * (1.0 - smooth01((air_time - 0.3) / 0.3)) * (1.0 - land_prep);
                pull_t = maxf(pull_t, T["airLift"] * lift_k * (pro_flight ? 1.0 : 0.0));   // (the pull-up: after the player's pump only)
                // a pop: the legs are straight at the edge, then the rider pulls the bike up under him; a squash: the bike
                // comes right up into the body, then is pushed back down the far side
                pull_t = maxf(pull_t, minf(1.0, 0.55 + 0.45 * pop_q) * smooth01((air_time - 0.02) / 0.08) * smooth01(pop_fx / 0.35) * (1.0 - land_prep) * (pro_flight ? 1.0 : 0.0));
                pull_t = maxf(pull_t, squash_fx * (1.0 - land_prep));
                // the tuck is part of every real jump: once the flight is a real one (air_k) the rider pulls the bike up
                // under him by autoTuck, holds it, lets it down for the landing. The right stick shapes it: back = all of
                // it, forward = the bike pushed away (no tuck)
                double sy = air_stick.y;
                double auto_t = T.get("autoTuck", 0.7) * smooth01((air_time - 0.04) / 0.14) * air_k;
                auto_t = lerpf(auto_t, 1.0, smooth01((sy - 0.3) / 0.5));
                auto_t *= 1.0 - smooth01((-sy - 0.2) / 0.5);
                pull_t = maxf(pull_t, auto_t * (1.0 - land_prep));
            }
            {
                // critically damped spring (SmoothDamp, exact step): eases out of rest and into the target with no kink in
                // its speed
                double yk = 2.0 * 0.6931472 / maxf(0.02, T.get("tuckEase", 0.09));
                double j0 = air_pull - pull_t;
                double j1 = _air_pull_v + j0 * yk;
                double ek = exp(-yk * dt);
                air_pull = ek * (j0 + j1 * dt) + pull_t;
                _air_pull_v = ek * (_air_pull_v - j1 * yk * dt);
            }
            // the lip throw: W / S pressed fresh as the bike leaves a lip (a jump spotted just ahead, or one wheel
            // already off) throw the rider back / forward. That is the only way to start a flip (keys held from before
            // don't count; S there pulls back, it doesn't brake). Not while a balance manual is held
            bool lip_win = !air && !(_balancing() || _man_grace > 0.0 || _nosing() || _nose_grace > 0.0) && (prep > 0.25 || front_air || rear_air);
            // input forgiveness: a throw pressed a moment before the window opens still counts
            double t_buf = T.get("inputForgive", 0.12) * 1.5;
            _tw_t = throttle > 0.1 ? _tw_t + dt : 0.0;
            _ts_t = brake ? _ts_t + dt : 0.0;
            _sb_t = body_in < -0.05 ? _sb_t + dt : 0.0;
            _sf_t = body_in > 0.05 ? _sf_t + dt : 0.0;
            if (!ws_air)   // gamepad / keys: pedal and brake never throw a flip (the right stick / arrow keys do), so brake stays a brake
            {
                lock_tw = true; lock_ts = true;
            }
            else if (!lip_win)
            {
                lock_tw = throttle > 0.1 && _tw_t > t_buf; lock_ts = brake && _ts_t > t_buf;
            }
            else
            {
                if (throttle <= 0.1) lock_tw = false;
                if (!brake) lock_ts = false;
            }
            double throw_in = 0.0;
            if (lip_win)
            {
                throw_in = (lock_ts ? 0.0 : brake_k) - (lock_tw ? 0.0 : throttle);   // + = back (nose up)
                if (!lock_ts)
                {
                    brake_k = 0.0; brake = false; brake_f = 0.0; brake_r = 0.0;
                }
            }
            // the body stick throws too, but only a real yank: pushed past half way, starting from the centre inside
            // the lip window. The stick's throw buffer is FLIP_PULL_EARLY s: held right through the lip it throws,
            // snapped forward at the lip it is still a pop
            double t_buf_s = maxf(t_buf, FLIP_PULL_EARLY);
            if (!lip_win)
            {
                lock_sb = body_in < -0.05 && _sb_t > t_buf_s; lock_sf = body_in > 0.05 && _sf_t > t_buf;
            }
            else
            {
                if (body_in >= -0.15) lock_sb = false;
                if (body_in <= 0.15) lock_sf = false;
            }
            // feathering a balance manual into a lip is not a flip throw (nor is working a nose manual, or the forward
            // snap of a stick hop)
            if (_balancing() || _man_grace > 0.0 || _nosing() || _nose_grace > 0.0 || gest_hop > 0.0)
            {
                lock_sb = true; lock_sf = true;
            }
            double yb = (lock_sb || !lip_win) ? 0.0 : clampf((-body_in - 0.5) / 0.4, 0.0, 1.0);
            double yf = (lock_sf || !lip_win) ? 0.0 : clampf((body_in - 0.5) / 0.4, 0.0, 1.0);
            throw_in = clampf(throw_in + yb - yf, -1.0, 1.0);
            if (!air)
            {
                if (absf(throw_in) > 0.05)
                {
                    double room = 1.0 - clampf(throw_v * signf(throw_in) / T["flipRate"], 0.0, 1.0);
                    throw_v += throw_in * T["flipAccel"] * room * dt;
                }
                else
                    throw_v *= exp(-dt * 6);   // a throw can't be held on the ground: the body settles back
            }
            return brake_k;
        }

        /// stage 2: the ground under the bike: heights at both axles, the surface and grip under each tyre
        void _step_ground(double dt, V3 f)
        {
            var terrain = host.terrain;
            _sample(f);
            if (air)
            {
                _aim_tick = (_aim_tick + 1) % 3;
                if (_aim_tick == 0 || is_nan(_land_pitch)) _land_pitch = _landing_slope(terrain);
            }
            else
                _land_pitch = NAN;
            surf = terrain.surface(x, z);
            // each tyre on its own ground (front on the sand at the trail's edge, rear still on the hardpack), its grip
            // easing across a change over ~0.1 s
            surf_f = terrain.surface(x + f.x * (L - BB_REAR), z + f.z * (L - BB_REAR));
            surf_r = terrain.surface(x - f.x * BB_REAR, z - f.z * BB_REAR);
            double mk = minf(1.0, dt * 12.0);
            _mu_f = is_nan(_mu_f) ? SURF_MU[clampi(surf_f, 0, 3)] : lerpf(_mu_f, SURF_MU[clampi(surf_f, 0, 3)], mk);
            _mu_r = is_nan(_mu_r) ? SURF_MU[clampi(surf_r, 0, 3)] : lerpf(_mu_r, SURF_MU[clampi(surf_r, 0, 3)], mk);
            double bf = _brake_mu(surf_f); double br = _brake_mu(surf_r);
            _bmu_f = is_nan(_bmu_f) ? bf : lerpf(_bmu_f, bf, mk);
            _bmu_r = is_nan(_bmu_r) ? br : lerpf(_bmu_r, br, mk);
            if (is_nan(course))
            {
                course = heading; slip = 0;
            }
            since_land += dt;
            // (a brush with a lip that was NOT followed by the take-off: the flag stayed set and ate the pop of the next jump)
            if (_graze && !air && since_land > 0.25) _graze = false;
        }

        /// stage 3: sprint and stamina (sprinting through water is allowed)
        void _step_sprint(double dt, in RideInput inp, double throttle, bool brake, bool _in_water)
        {
            bool want_sprint = inp.sprint && throttle > 0.1 && !brake && !air;
            if (stamina <= 0) tired = true;
            else if (stamina > 0.25) tired = false;
            bool sprinting = want_sprint && !tired;
            if (sprinting && !air) stamina = maxf(0.0, stamina - dt / T["sprintTime"]);
            else if (!sprinting) stamina = minf(1.0, stamina + dt / T["sprintRecharge"]);
            sprint += ((sprinting ? 1.0 : 0.0) - sprint) * minf(1.0, dt * 5);
        }

        /// stage 4: how the weight sits on the two tyres (slope, rider fore / aft, braking); sets n_rear / n_front / n_load,
        /// and judges OVER THE BARS
        void _step_loads(double dt)
        {
            double n_sc = G / _or(n_ref, G);
            // the tyre springs carry the weight straight down; on a slope only g cos(slope) of it presses the tyres onto
            // the ground (what grip, brakes and drive can use), the rest is the pull down the slope
            double n_cos = cos(clampf(_g_pitch, -1.2, 1.2));
            // the tyre springs also carry the turn's load (corner_g); the tyres' grip is worked out from the tilt of the
            // ground below (_fric / a_max), so take it out here
            n_cos *= G / (G + maxf(0.0, corner_g));
            double nR = air ? 0.0 : _or(n_r, G * SH_R) * n_sc * n_cos;
            double nF = air ? 0.0 : _or(n_f, G * (1 - SH_R)) * n_sc * n_cos;
            double n_tot = nR + nF;
            // rider weight fore / aft moves load between the tyres (total unchanged): leaning back puts it on the rear,
            // leaning forward does the opposite
            double lean_fb = 0.0;
            if (!air)
            {
                // (the hips go back when braking, x_brake in the body stage: that brace only counts a quarter for the load split)
                double xb = -0.8 * T["weightShift"] * (maxf(brake_f, brake_r) > 0.1 ? 1.0 : 0.0) * 0.75;
                lean_fb = clampf(body_in_s + (body_x + hip_shift - 2.0 * xb) * 0.5 / maxf(0.05, T["weightShift"]), -1.0, 1.0);
                // pumping with the stick is pushing down, not leaning over the bars: the rear keeps its load
                if (lean_fb > 0.0 && pump_push > 0.05 && body_in > 0.12) lean_fb *= 1.0 - T.get("pumpCentred", 0.75);
                double dN = -lean_fb * T.get("leanTraction", 0.45) * G;
                // and the slope itself: climbing puts weight on the rear and descending on the front (g sin(slope) x
                // height / wheelbase)
                dN += G * sin(clampf(_g_pitch, -1.2, 1.2)) * SLOPE_TRANSFER;
                // a rider weights the front in a turn: leaned over, frontWeight g of the load moves forward, more while
                // the front is in trouble
                double fw_k = T.get("riderSkill", 1.0) * smooth01((absf(lean) - 0.12) / 0.35);
                double fw_risk = _risk.TryGetValue("FRONT WASHED OUT!", out var rv) ? rv : 0.0;
                dN -= G * T.get("frontWeight", 0.12) * fw_k * (1.0 + 3.5 * fw_risk);
                // braking throws the weight onto the front (last step's brake decel x CoM height / wheelbase); rolling
                // backwards, braking loads the rear
                double d_brake = -_b_prev * SLOPE_TRANSFER * (v >= 0.0 ? 1.0 : -1.0);
                // (how far the rear would go below nothing = how hard it's coming up: the crash judge builds on it)
                double lift = (-nR + 0.03 * G) - (dN + d_brake);
                _danger("OVER THE BARS!", (brake_f > 0.4 && v > 3.0 && !_nosing() && nose_push <= 0.0) ? lift / (0.25 * G) : -1.0, dt);   // (a stoppie on purpose is the nose balance's)
                dN += d_brake;
                // (both tyres nearly weightless: the two limits cross; clampf with min > max would leave a tyre negative)
                double dn_lo = -nR + 0.08 * G;
                double dn_hi = nF - 0.08 * G;
                dN = dn_lo <= dn_hi ? clampf(dN, dn_lo, dn_hi) : 0.5 * (dn_lo + dn_hi);
                nR = maxf(0.0, nR + dN); nF = maxf(0.0, nF - dN);
            }
            n_load = n_tot;
            spin = 0; a_drive = 0; a_pedal = 0;
            n_rear = nR; n_front = nF;
        }

        /// the speed tuck's level this step
        void _speed_tuck_step(double dt, double throttle)
        {
            double b = clampf(-body_in_s, 0.0, 1.0);
            double stick = smoothstep(TUCK_BACK_IN.x, TUCK_BACK_IN.y, b) * (1.0 - smoothstep(TUCK_BACK_OUT.x, TUCK_BACK_OUT.y, b));
            // automatic: by speed, coasting (pedalling stands him up), not with the stick pushed forward (that is the other
            // tuck) or pulled well back, nor while balancing a manual / nose manual
            double auto = smoothstep(T.get("speedTuckFrom", 11.0), T.get("speedTuckFull", 18.0), absf(v)) * T.get("speedTuck", 1.0);
            auto *= (1.0 - clampf(throttle * 1.5, 0.0, 1.0)) * (1.0 - clampf(body_in_s * 2.0, 0.0, 1.0)) * (1.0 - smoothstep(TUCK_BACK_OUT.x, TUCK_BACK_OUT.y, b));
            double bal = clampf(maxf(man_a, nose_a) / 0.15, 0.0, 1.0);
            auto *= 1.0 - bal; stick *= 1.0 - bal;
            auto = clampf(auto, 0.0, 1.0);
            double want = maxf(auto, stick);
            double k = 1.0 - exp(-(want > speed_tuck ? 5.0 : 3.0) * dt);
            speed_tuck += (want - speed_tuck) * k;
            speed_tuck_auto += (auto - speed_tuck_auto) * k;
        }

        /// air drag scale from the body: forward stick = race tuck over the bars, the speed tuck (light pull back / by
        /// itself at speed), pulled all the way back = sat up tall (an air brake)
        void _aero_update(double throttle)
        {
            // the drag is the rider's frontal area. Folded down over the bars (right stick forward) it drops (~40 %);
            // sat up tall (stick back) it catches the wind like an air brake. Pedalling hard spoils the tuck a bit
            double tuck = clampf(body_in_s, 0.0, 1.0) * (1.0 - 0.5 * clampf(throttle, 0.0, 1.0));
            double sit_up = clampf(-body_in_s, 0.0, 1.0);
            // the stick's part of the speed tuck counts fully, the automatic part speedTuckDrag of it
            double st_stick = maxf(0.0, speed_tuck - speed_tuck_auto);
            tuck = maxf(tuck, st_stick + speed_tuck_auto * T.get("speedTuckDrag", 0.5));
            sit_up = smoothstep(TUCK_BACK_OUT.x, TUCK_BACK_OUT.y, sit_up);
            aero_k = 1.0 - T.get("tuckDrag", 0.42) * tuck + T.get("upDrag", 0.3) * sit_up;
        }
    }
}
