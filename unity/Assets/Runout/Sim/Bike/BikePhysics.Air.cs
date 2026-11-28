// Port of godot/scripts/bike/bike_physics.gd, group F: the hop, reading the lip, wheels / cranks, the balance (manual /
// nose manual), the pop, landing tricks, style points and the crash judge. Line for line with the GDScript.
using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    public sealed partial class BikePhysics
    {
        void _step_hop(double dt, in RideInput inp)
        {
            var terrain = host.terrain;
            // --- hop / pump ---
            if (hop_block && !inp.hop) hop_block = false;
            bool space = inp.hop && !hop_block;
            // --- the crouch (preload): hop held, or the body stick pulled back. The legs bend over crouchTime; let go without
            // a pop they stay bent a moment (the stick is on its way forward), then ease up ---
            double back_in = clampf((-body_in - 0.25) / 0.45, 0.0, 1.0);
            _stick_hold = back_in > 0.05 ? _stick_hold + dt : 0.0;
            // (the stick held back a long while is weight back, not a crouch held ready)
            double pre_in = maxf(space ? 1.0 : 0.0, back_in * (1.0 - smooth01((_stick_hold - 0.9) / 0.6)));
            if (air) pre_in = 0.0;
            _bend_in = pre_in;
            if (pre_in >= crouch - 0.01)
            {
                crouch = minf(pre_in, crouch + dt / maxf(0.08, T.get("crouchTime", 0.25))); _cr_rel = 0.0;
            }
            else
            {
                _cr_rel += dt;
                if (_cr_rel > 0.22) crouch = maxf(pre_in, crouch - dt * 5.0);
            }
            crouch_t = crouch > 0.05 ? crouch_t + dt : 0.0;
            // a pop that comes as the legs and the suspension rebound from a quick dip gets more out of it (the preload's timing)
            rebound = smooth01((crouch_t - 0.08) / 0.12) * (1.0 - smooth01((crouch_t - 0.5) / 0.45));
            load = crouch;
            // (how hard the ground presses just now, 1 = standing weight: the tyre loads against their own resting level)
            if (!air) _n_grd += (clampf((_or(n_f, 0.0) + _or(n_r, 0.0)) / maxf(1.0, _or(n_ref, G)), 0.0, 3.0) - _n_grd) * minf(1.0, dt * 10.0);
            // a lip absorbed: the stick held forward into it (held a while: a fresh push at a lip is a front flip throw)
            double sq_in = (_sf_t > 0.25 && gest_hop <= 0.0 && !_nosing()) ? clampf((body_in - 0.25) / 0.45, 0.0, 1.0) * T.get("squashPower", 1.0) : 0.0;
            if (!air) squash += (sq_in - squash) * minf(1.0, dt * 10.0);
            else squash = maxf(0.0, squash - dt * 4.0);
            pop_fx = maxf(0.0, pop_fx - dt / ((pro_flight && air) ? 0.65 : 0.45)); squash_fx = maxf(0.0, squash_fx - dt / 0.5);
            if (pop_wait > 0.0)
            {
                _pop_arm_t -= dt;
                if (_pop_arm_t <= 0.0) pop_wait = 0.0;   // the lip never came (braked, turned off it)
            }
            bool backside = !air && _g_pitch < -0.06 && terrain.jump_mask(x, z) > 0.05;
            // a press spent pumping a downhill is let go of on the next face without a hop (unless a lip is right there)
            // (not with the front up: in a manual the legs aren't pumping, a hop let go there is the hop out of the manual)
            // (a roller's backside lasts only 0.15-0.4 s at speed: a press that spent most of its time pumping one counts too)
            bool pumped = (_pump_release > 0.25 || (_pump_release > 0.08 && _pump_release > 0.5 * _hop_tap_t)) && prep < 0.1 && man_a < 0.08;
            _pump_release = space ? pump_press_t : _pump_release;
            // (reset whenever hop is up, in the air too: let go mid-jump it used to carry over and eat the next hop)
            if (!inp.hop) pump_press_t = 0.0;
            // --- the pop (one move, the legs' one push: _pop_now). Started by letting go of hop, by the stick (back, then
            // snapped forward), or both; its power = the crouch (_crouch_power) and the scoop (the front already up when it
            // starts: out of a manual), see _hop_power. inputForgive s of slack on the timing ---
            double fgv = T.get("inputForgive", 0.12);
            bool let_go = !space && hop_held;
            _hop_tap_t = (space && !hop_held) ? 0.0 : _hop_tap_t + dt;
            _hop_buf = maxf(0.0, _hop_buf - dt);
            gest_hop = maxf(0.0, gest_hop - dt);
            // the stick: held back (the legs load; out of a quick pull the front comes up through the balance manual), then
            // snapped forward
            if (body_in < -0.5 && !air)
            {
                _bh_back += dt; _bh_since = 0.0; _bh_peak = maxf(_bh_peak, man_a);
            }
            else
            {
                _bh_since += dt;
                if (_bh_since > 0.3)
                {
                    _bh_back = 0.0; _bh_peak = 0.0;
                }
            }
            // (a thumb letting go of a stick held back springs it past centre to ~+0.35 for a moment; a real snap goes well past it)
            bool snapped = _bh_back > 0.04 && body_in > STICK_POP_FWD && _bh_since < 0.22 && T.get("stickHop", 1.0) > 0.0;
            bool can_hop = !air && !rear_air && !_nosing() && !(hop_t > 0) && kick_t <= 0.0;
            if (snapped && can_hop && v > 1.0)
            {
                // (a slow snap is a weaker one; even a bare tap of the stick hops a little)
                double q_snap = 1.0 - 0.6 * smooth01((_bh_since - 0.06) / 0.16);
                double scoop = _scoop_k(maxf(man_a, _bh_peak));
                double pw = _hop_power(maxf(0.45, _crouch_power()), scoop) * q_snap;
                _bh_back = 0.0; _bh_peak = 0.0; gest_hop = 0.4;
                throw_v = 0.0;   // (the pull back was the preload, not a back flip throw)
                if (space) hop_block = true;   // the button's crouch went into this pop: letting go doesn't pop again
                _pop_now(pw);
            }
            else if (let_go && !air && !_nosing() && crouch > 0.1 && !(hop_t > 0) && !backside && !pumped)
            {
                double pw2 = _hop_power(maxf(0.45, _crouch_power()), _scoop_k(man_a));
                _pop_now(pw2);
            }
            else if (let_go && !air && (pumped || backside))
            {
                _cr_rel = 1.0;   // a pumping press let go: the legs straighten now (that is the push), no pop
            }
            else if ((let_go || (snapped && _bh_since < 0.22)) && air && !pumped)
            {
                if (air_time <= fgv && crouch > 0.1 && kick_t <= 0.0)
                {
                    // coyote time: let go a moment after the wheels left the lip still pops (what the legs have left)
                    if (snapped) { _bh_back = 0.0; gest_hop = 0.4; }
                    pop_time = 0.75;
                    _hop_pop(0.5, maxf(0.45, _crouch_power())); crouch = 0.0;
                }
                else if (let_go && _hop_tap_t < 0.25 && fgv > 0.0)
                {
                    _hop_buf = fgv * 1.25;   // a tap just before touch-down: the hop comes as the tyres land
                }
            }
            else if (_hop_buf > 0.0 && can_hop && !space)
            {
                _hop_buf = 0.0;
                _pop_now(0.45);
            }
            if (hop_t > 0)
            {
                hop_t -= dt;
                _hop_nose_t = maxf(_hop_nose_t, (0.22 + 0.15 * hop_load) * 0.6 * (1 - maxf(0.0, hop_t) / HOP_PUSH));
                if (hop_t <= 0 || air)
                {
                    hop_t = 0;
                    _hop_pop(hop_load, hop_charge);
                    hop_charge = 0; lift_t = 0.12;
                }
            }
            if (lift_t > 0) lift_t = air ? 0.0 : maxf(0.0, lift_t - dt);
            hop_bar_show = !air && crouch > 0.12 && (space || back_in > 0.05 || _cr_rel < 0.2);
            hop_bar = _crouch_power();   // (it peaks on the rebound, then sags while the crouch is held: pop at the peak)
            hop_held = space;
            // the pop sets where the drawn nose kick goes and the kick follows (two easing stages: it starts from rest,
            // no jump in its speed either), peaking ~0.1 s after the pop
            _hop_nose_t *= exp(-dt * 3.5);
            double hk = 1.0 - exp(-dt / HOP_NOSE_TAU);
            _hop_nose_m += (_hop_nose_t - _hop_nose_m) * hk;
            hop_nose += (_hop_nose_m - hop_nose) * hk;
            land_perfect = maxf(0.0, land_perfect - dt * 1.2);
        }

        /// where this flight comes down: the ballistic path from here, stepped until it meets the ground; the ground's
        /// slope there along the flight (rad), or NAN. The hands-off landing aim matches the bike to THAT, not to the
        /// ground under it
        double _landing_slope(IGround terrain)
        {
            double c = !is_nan(course) ? course : heading;
            var d = new V2(cos(c), -sin(c));
            double hv = absf(v) * signf(v != 0.0 ? v : 1.0);
            double py = y;
            double pvy = vy;
            double px = x;
            double pz = z;
            for (int i = 0; i < 80; i++)
            {
                double st = 0.04;
                px += d.x * hv * st; pz += d.y * hv * st;
                pvy -= G * st; py += pvy * st;
                double gh = terrain.height(px, pz);
                if (py <= gh && pvy < 0.0)
                {
                    _land_t = (i + 1) * st;
                    double hf = terrain.height(px + d.x * 0.6, pz + d.y * 0.6);
                    double hb = terrain.height(px - d.x * 0.6, pz - d.y * 0.6);
                    return atan2(hf - hb, 1.2);
                }
            }
            return NAN;
        }

        /// air_k = THE ground -> air blend for everything drawn. 1 once the flight is a real one (the predicted whole
        /// flight, air_time + _land_t, at least AIR_BODY_MIN; with no prediction, AIR_BODY_FROM of air), eased in over
        /// ~AIR_BODY_IN and back out over ~AIR_BODY_OUT after touch-down. The physics keeps reading `air`
        void _air_blend(double dt)
        {
            double a_min = T.get("airBodyMin", AIR_BODY_MIN);
            bool real = false;
            if (air)
            {
                if (!is_nan(_land_pitch)) real = air_time + _land_t >= a_min || air_time > a_min;
                else real = air_time > maxf(a_min, AIR_BODY_FROM);
            }
            double k_t = real ? 1.0 : 0.0;
            air_k += (k_t - air_k) * minf(1.0, dt / maxf(0.01, k_t > air_k ? T.get("airBodyIn", AIR_BODY_IN) : T.get("airBodyOut", AIR_BODY_OUT)));
        }

        /// stage 10: reading the trail (a lip ahead: crouch, pop), the legs' compression
        void _step_lip(double dt, V3 f, bool brake)
        {
            var terrain = host.terrain;
            // --- reading the trail: spot a lip ahead ---
            double lip_t = INF;
            lip_scan = (lip_scan + 1) % 3;
            if (lip_scan != 0 && !air && v > 3 && lip_state != 0)
            {
                lip_t = lip_state == 1 ? INF : maxf(0.0, lip_last - dt);
            }
            else if (!air && v > 3)
            {
                double stp = 0.3;
                int n = mini(36, ceili(v * (T["prepTime"] + 0.1) / stp));
                double h_prev = terrain.height(x, z);
                double s_prev = NAN;
                for (int i = 1; i < n + 1; i++)
                {
                    double d = i * stp;
                    double sx = x + f.x * d;
                    double sz = z + f.z * d;
                    double hh = terrain.height(sx, sz);
                    double sl = (hh - h_prev) / stp;
                    if (!is_nan(s_prev) && s_prev > 0.15 && (s_prev - sl) * v * v / stp > 2.5 * G && terrain.jump_mask(sx, sz) > 0.05)
                    {
                        lip_t = (d - stp) / v;
                        if (lip_state != 2) lip_h = maxf(0.0, h_prev - terrain.height(x, z));   // (measured from where it's first seen)
                        break;
                    }
                    s_prev = sl; h_prev = hh;
                }
            }
            if (air || v <= 3) lip_state = 0;
            else if (lip_t == INF) lip_state = 1;
            else
            {
                lip_state = 2; lip_last = lip_t;
            }
            _lip_ago = lip_state == 2 ? 0.0 : _lip_ago + dt;
            // a whip is carved in at the lip, not started in the air: the right stick held to the side in the last
            // WHIP_WINDOW s before the edge winds it up (whip_load, signed, like the stick). Decays when not held.
            // Pushed right to the stick's edge it winds up a SPIN instead; short of the edge it stays a whip
            bool spin_edge = absf(flick_in) >= SPIN_EDGE;
            if (!air && lip_state == 2 && lip_last < WHIP_WINDOW && absf(flick_in) > 0.25 && !spin_edge)
                whip_load = move_toward(whip_load, clampf(flick_in / 0.8, -1.0, 1.0), dt / WHIP_WIND);
            else if (!air)
                whip_load = move_toward(whip_load, 0.0, dt * 3.0);
            if (!air && lip_state == 2 && lip_last < WHIP_WINDOW && spin_edge)
                spin_load = move_toward(spin_load, signf(flick_in), dt / WHIP_WIND);
            else if (!air)
                spin_load = move_toward(spin_load, 0.0, dt * 3.0);
            // hands off he reads the lip: one that height needs about ABSORB_V0 + ABSORB_VH x its height (m/s) to clear;
            // going faster than that he soaks it up instead - the faster, the more. Your own pump / crouch always pops
            double ab_t = 0.0;
            if (lip_state == 2 && crouch < 0.1)
            {
                // small lips only (a real jump he pops): fully under ABSORB_SMALL, none past ABSORB_BIG
                ab_t = smooth01((absf(v) - (ABSORB_V0 + ABSORB_VH * lip_h)) / 3.0) * smooth01((ABSORB_BIG - lip_h) / (ABSORB_BIG - ABSORB_SMALL));
            }
            auto_absorb += (ab_t - auto_absorb) * minf(1.0, dt * (ab_t > auto_absorb ? 12.0 : 3.0));
            if (air) auto_absorb = maxf(0.0, auto_absorb - dt * 3.0);
            double prep_t = lip_t < T["prepTime"] ? smooth01(1 - lip_t / T["prepTime"]) : 0.0;
            prep = air ? maxf(0.0, prep - dt * 4) : prep + (prep_t - prep) * minf(1.0, dt * 8);
            // a skilled rider winds up into the transition (prepTime / prepDepth: the crouch) and drives the legs straight
            // LATE, through the end of the lip. Hands off he pops at autoPump of a full push, fired in the last 0.1 s; a pop
            // the player times well is still worth more (1.0), a held crouch is timed at popAssist
            bool popping = lip_t < 0.10;
            if (popping && !pop_fired)
            {
                // hands off, the rider gives the lip a push of his own (autoPump of a full one). A crouch still held into
                // the lip is timed for the player, at popAssist of what letting go on time gives. A lip being squashed gets
                // no push
                double p_auto = T["autoPump"] * 1.0 * prep * (1.0 - auto_absorb);
                if (crouch > 0.1) p_auto = maxf(p_auto, _crouch_power() * T.get("popAssist", 0.6));
                if (squash > 0.2 || (crouch <= 0.1 && auto_absorb > 0.5)) p_auto = 0.0;   // (soaking it up: no push at all)
                pop_fired = true;
                if (p_auto > pop_wait)
                {
                    pop_wait = p_auto; _pop_arm_t = 0.5;
                    pro_pop = crouch > 0.1;   // (a crouch the player held into the lip: his pump; hands off: the rider's own, plain)
                }
                compress_v += 2.5 * prep * p_auto;
            }
            if (!air && lip_t == INF) pop_fired = false;
            double lp = 0.0;
            double tuck = 0.0;
            if (air)
            {
                double hh = maxf(0.0, y - _g_y);
                double tg = (vy + sqrt(vy * vy + 2 * G * hh)) / G;
                // how hard this landing will be: the speed into the landing's slope, square to it (the part the legs have
                // to stop). land_reach 0.35..1 x legExt; the reach starts up to 1.4x earlier when it's hard
                land_vn = 0.0;
                land_reach = 1.0;
                double tg_l = (!is_nan(_land_pitch) && _land_t > 0.0) ? _land_t : tg;
                double sl = !is_nan(_land_pitch) ? _land_pitch : _g_pitch;
                double vy_td = vy - G * tg_l;
                land_vn = absf(absf(v) * sin(sl) - vy_td * cos(sl));
                land_reach = lerpf(0.35, 1.0, smooth01((land_vn - 1.0) / 3.0));
                _vn_td = land_vn; _reach_td = land_reach;
                double lpt = T["landPrepTime"] * lerpf(0.85, 1.4, (land_reach - 0.35) / 0.65);
                lp = vy < 0 ? smooth01(1 - tg / lpt) : 0.0;
                if (_tuck_in) lp *= 0.25;   // the tuck held into the ground: the legs are still folded, with little left to take the hit
                tuck = smooth01((air_time - 0.08) / 0.2) * (1 - lp);
            }
            land_prep = lp;
            double cT;
            if (air) cT = -0.12 * tuck;
            else if (pop_wait > 0.0 || hop_t > 0) cT = 0.05 + 0.05 * minf(1.0, pop_wait);   // the legs drive straight through the edge
            else if (popping && squash < 0.2) cT = 0.03;
            else cT = -0.15 * crouch - 0.06 * carve - T["prepDepth"] * prep * (1.0 - 0.7 * crouch) - 0.08 * squash;
            compress_v += ((cT - compress) * 120 - compress_v * 14) * dt;
            compress = clampf(compress + compress_v * dt, -0.28, 0.1);
            _air_blend(dt);
            // (Godot: host.susp.update(...) when the drawn suspension doesn't follow the ground. In a ride the tyres always
            // follow the ground (BikeRig.fit_wheels), so the drawing side does it: not part of the sim)
        }

        /// the rear wheel's own spin (rad/s). On the ground the tyre holds it to the ground speed (0 while the rear is
        /// locked). Off the ground it spins free: bearings, seals and air slow it only a little, the rear brake stops it
        /// in ~0.3 s, and pedalling spins it up through the pawls. Touching down, the tyre grabs it back at once
        void _rear_spin_step(double dt)
        {
            if (!(air || rear_air))
            {
                double dv = absf(vw_r - _wr_vr);
                wr_knock = maxf(wr_knock, dv);
                wr_vib2 += dv * dv; wr_vibn += 1;
            }
            _wr_vr = vw_r;
            double ground_w = skid ? 0.0 : v / RWR;
            if (!(air || rear_air))
            {
                wr_w = ground_w;
                return;
            }
            double a = WR_BEARING + WR_AIR * wr_w * wr_w + WR_BRAKE * brake_r;
            wr_w = move_toward(wr_w, 0.0, a * dt);
            // the legs drive the wheel through the pawls only while the driver is the faster one
            if (pedal > 0.05)
                wr_w = maxf(wr_w, crank_rate(v / RWR, gear_k(), T["topSpeed"], sprint, drive_ratio()) * pedal * drive_ratio());
        }

        /// stage 11: wheels and cranks turning, the body in the air, effects
        void _step_wheels(double dt, V3 f, bool in_water, double va)
        {
            // --- wheels / cranks ---
            double w = v / RWF;
            wheel_f += w * dt;
            // pedal kickback: as the rear compresses the chain grows and pulls the cranks back against the feet (the other
            // way on the rebound), only while the legs are on the pedals
            double kick_to = 0.0;
            if (_rear_shock() && !air && pedal > 0.05)
            {
                double kk = T.get("pedalKick", 1.0);
                crank -= clampf(dg_vR, -1.0, 2.0) * CHAIN_GROWTH / CRANK_ARM * kk * dt;
                kick_to = clampf(absf(dg_vR) * kk, 0.0, 1.5) / 1.5;
            }
            _kick_k += (kick_to - _kick_k) * minf(1.0, dt * 25.0);
            _rear_spin_step(dt);
            wheel_r += wr_w * dt;
            if (v < -0.05 && !air && !skid)
            {
                // rolling backwards the freewheel's pawls catch: the chain turns the cranks back with the wheel
                crank += v / RWR / drive_ratio() * dt;
            }
            else if (pedal > 0.05)
            {
                crank += (crank_rate(air ? wr_w : v / RWR, gear_k(), T["topSpeed"], sprint, drive_ratio()) + CHAIN_SLIP_LURCH * chain_slip_k) * pedal * dt;
            }
            else if (!air)
            {
                double aL = host.pedal_a0_left;
                double aR = host.pedal_a0_right;
                double tgt;
                double period = TAU;
                // (the drawn bike's lean, not the shared one: slow, the bike is laid into the turn while the shared lean is
                // small, and the rider stands on the outside pedal)
                double cl = bike_lean * 0.65;
                if (cl > 0.12) tgt = aR + PI / 2;
                else if (cl < -0.12) tgt = aL + PI / 2;
                else
                {
                    tgt = aL; period = PI;
                }
                tgt += period * round((crank - tgt) / period);
                crank += (tgt - crank) * minf(1.0, dt * 3.5);
            }
            if (air)
            {
                // legs reach for the landing; holding Space tucks the bike up into the body instead (tuckPull m of leg)
                double tk_r = T.get("tuckPull", 0.32);
                double rel_t = T["legExt"] * land_prep * land_reach - (tk_r + 0.07 * smooth01(pop_fx / 0.35) * pop_q) * air_pull * (1 - land_prep);
                // on the take-off step the leg spring already moved body_y alongside y; after that body_y is
                // last step's bike height + rel
                double rel = _or(body_y, y) - (air_time <= dt * 1.5 ? y : _or(y_prev, y));
                double nrel = rel + (rel_t - rel) * (1 - exp(-dt * 12));
                // body and bike push apart about their shared centre of mass, which flies on undisturbed:
                // tucking lifts the bike, reaching down for the landing drops it
                y -= TUCK_SHARE * (nrel - rel);
                body_y = y + nrel; body_v = vy;
            }
            y_prev = y;

            skid_fx = skid || spin > 0.3 || (!air && va > 1.5 && (absf(slip - _squirm) > 0.1 || (grip_r < 0.45 && absf(slip_w) > 0.3)));
            host.ride_fx(dt, f, va, in_water);
        }

        /// the right stick held at an edge in the air (one axis, -1..1): the spin it asks for builds up gently towards the
        /// edge (stickSpinBuild /s, eases out quicker) and how long it's been held that way grows (back to 0 at 3 /s).
        /// Returns V2(eased edge, held seconds)
        V2 _edge_spin(double axis, double s, double hold, double dt)
        {
            double edge = signf(axis) * clampf((absf(axis) - 0.8) / 0.15, 0.0, 1.0);
            double rate = absf(edge) > absf(s) ? T.get("stickSpinBuild", 2.5) : 10.0;   // let go = the spin stops soon
            s = move_toward(s, edge, rate * dt);
            if (absf(edge) > 0.5 && signf(edge) == signf(s)) hold += dt;
            else hold = maxf(0.0, hold - dt * 3.0);
            return new V2(s, hold);
        }

        /// the spin-rate multiplier for an edge held that long (x (1 + stickSpinGrow per second), up to 1.5 s)
        double _edge_grow(double hold)
        {
            return 1.0 + T.get("stickSpinGrow", 0.8) * minf(hold, 1.5);
        }

        bool _balancing()
        {
            return man_a > 0.05;
        }

        /// the front is set down (a slide caught in a manual, the rider bailing out of it)
        void _man_drop()
        {
            if (man_w > -2.0) man_w = -2.0;
            man_lock = maxf(man_lock, 0.35);
        }

        bool _nosing()
        {
            return nose_a > 0.05;
        }

        /// One step of a tipping balance, the same for both ends of the bike: the manual / wheelie (the front up, on the
        /// back wheel) and the nose manual / stoppie (the rear up, on the front wheel). a = how far that wheel is up, w its
        /// rate. Gravity pulls it back down below the balance point b and on over past it; drive is everything the rider
        /// adds (rad/s2: + lifts, - drops). Returns (a, w)
        V2 _tip(double a, double w, double b, double grav, double drive, double dt)
        {
            w += (grav * sin(a - b) + drive - T.get("manDamp", 1.6) * w) * dt;
            a += w * dt;
            if (a <= 0.0)
            {
                a = 0.0; w = maxf(0.0, w);
            }
            return new V2(a, w);
        }

        /// gone too far over (either end): the rider saves it by slamming that wheel back down, most of the speed gone.
        /// No crash
        V2 _tip_over(double b, string msg)
        {
            v *= T.get("manLoopKeep", 0.72); shake = maxf(shake, 0.25);
            host.flash(msg);
            return new V2(b * 0.45, -2.5);
        }

        /// the balance, both ends (only one can be up at a time). Back wheel: the body stick pulled back past manualFrom, a
        /// sprint stamp from slow and pedal strokes lift the front; the rear brake and leaning forward drop it. Front wheel:
        /// the front brake with the stick pushed forward past noseFrom tips the rear up; once up the rider's weight over the
        /// bars holds it (no brake needed), the brake tips it further, the stick back sets it down
        void _balance_step(double dt, bool pedalling, double throttle, bool brake)
        {
            double zone = T.get("manZone", 0.14);
            // --- back wheel: manual / wheelie ---
            double b = T.get("manBalance", 0.55);
            double m_from = T.get("manualFrom", 0.4);
            double lift = T.get("manLift", 9.0);
            man_lock = maxf(0.0, man_lock - dt);
            _man_grace = man_a > 0.05 ? 0.5 : maxf(0.0, _man_grace - dt);
            double pull = clampf((-body_in - m_from) / maxf(0.05, 1.0 - m_from), 0.0, 1.0);
            double pull_t = T.get("manPullTime", 0.25);
            // (not in the air: off a roller the stick held back would come back down as a fresh quick pull and arm a manual
            // that is past its edge at once)
            if (air) _pull_age = maxf(_pull_age, 1.0);
            else if (-body_in < 0.15) _pull_age = 0.0;
            else _pull_age += dt;
            if (-body_in < 0.12 && !air) _man_armed = false;   // back at the centre: it has to be pulled again
            // (manBothSticks: on a pad the left stick has to be pulled back with it too)
            // corner gate: the front only comes up from riding roughly straight (manGate = most lean). Once up it stays up
            bool gate_ok = absf(lean) < T.get("manGate", 0.2);
            bool straight = gate_ok || man_a > 0.05;
            // (not with a lip right ahead: there the pull back is the preload for the pop)
            if (!_man_armed && gate_ok && lip_state != 2 && !air && -body_in >= 0.5 && _pull_age <= pull_t && (!pad || T.get("manBothSticks", 0.0) < 0.5 || left_back >= 0.5))
                _man_armed = true;
            // power wheelie, like a motocross game: weight back + pedalling lifts the front with no pull at all, as far as
            // the pedals have the power for (all of it slow, none by manPowerSpeed); stop pedalling and it comes down
            double vp = maxf(1.0, T.get("manPowerSpeed", 9.0));
            double pw_t = (pedalling && straight && !air) ? T.get("manPower", 1.0) * minf(throttle, 1.0) * (1.0 - smooth01((absf(v) - 0.5 * vp) / (0.5 * vp))) : 0.0;
            _man_pw += (pw_t - _man_pw) * minf(1.0, dt * (pw_t > _man_pw ? 6.0 : 3.0));
            if (!straight) _man_pw = 0.0;   // leaned into a corner with the front down: nothing left over lifts it
            if (T.get("manDirect", 1.0) >= 0.5 && pull_t > 0.0)
            {
                // (the pedals alone lift it to the balance point at most: only a pull can take it over the back)
                double p_cap = b / (b + T.get("manLoop", 0.42) + 0.08);
                pull = maxf(_man_armed ? pull : 0.0, minf(pull, p_cap) * minf(1.0, _man_pw));
            }
            else if (!straight) pull = 0.0;   // the corner gate holds in every mode
            bool can = !air && !_nosing() && v > (pedalling ? 0.6 : 1.5) && throw_v <= 0.5;
            man_pull = can ? pull : 0.0;
            if (!can)
            {
                // in the air or too slow the balance is let go (the air control owns the pitch)
                man_w = 0.0; man_a = move_toward(man_a, 0.0, 3.0 * dt);
                man_zone = false; man_zone_t = 0.0;
            }
            else
            {
                double drive = 0.0;
                if (man_lock <= 0.0)
                {
                    drive += lift * pull;
                    // a sprint stamp from slow hauls the front up too, as a lift into the balance
                    drive += lift * T.get("manSprintLift", 1.1) * _sprint_lift * (0.55 + 0.45 * absf(sin(crank)));
                    // pedalling while pulling = a wheelie: each stroke helps lift (the stick is still what holds it)
                    if (pedalling && pull > 0.0)
                        drive += T.get("manPedal", 3.0) * pull * minf(throttle, 1.0) * (0.4 + 0.6 * absf(sin(crank)));
                }
                // (the REAR brake drops a manual: the bare front lever, its wheel in the air, does nothing)
                if (brake && brake_r > 0.1 && man_a > 0.0) drive -= T.get("manBrake", 12.0);
                drive -= lift * 0.8 * clampf((body_in - 0.2) / 0.6, 0.0, 1.0);
                var t = _tip(man_a, man_w, b, T.get("manGravity", 7.0), drive, dt);
                // DIRECT manual (manDirect 1; 0 = the old tipping balance above): the stick IS the front's height. The front
                // follows on a soft spring (manFollow), so it is smooth and never runs away from the stick
                double direct = clampf(T.get("manDirect", 1.0), 0.0, 1.0);
                double loop_at = b + T.get("manLoop", 0.42);
                if (direct > 0.0)
                {
                    double tgt = man_lock <= 0.0 ? pull * (loop_at + 0.08) : 0.0;
                    tgt = maxf(tgt, 0.35 * T.get("manSprintLift", 1.1) * _sprint_lift);
                    if (brake && brake_r > 0.1) tgt *= 1.0 - minf(1.0, brake_r * 1.5);   // the rear brake sets it down
                    tgt *= 1.0 - clampf((body_in - 0.2) / 0.6, 0.0, 1.0);
                    double kf = T.get("manFollow", 40.0);
                    double acc = kf * (tgt - man_a) - 2.0 * sqrt(kf) * 0.9 * man_w;
                    if (pedalling && pull > 0.0 && man_lock <= 0.0)   // a wheelie: each stroke nudges the front
                        acc += 0.35 * T.get("manPedal", 3.0) * pull * minf(throttle, 1.0) * absf(sin(crank));
                    double w2 = man_w + acc * dt;
                    double a2 = man_a + w2 * dt;
                    if (a2 <= 0.0)
                    {
                        a2 = 0.0; w2 = maxf(0.0, w2);
                    }
                    t = new V2(lerpf(t.x, a2, direct), lerpf(t.y, w2, direct));
                }
                if (t.x > loop_at)
                {
                    if (direct >= 0.5)
                    {
                        // pulled too far and kept there: he goes off the back (manFall; 0 = the front just floats at the top)
                        _man_over += dt;
                        if (T.get("manFall", 1.0) < 0.5)
                            t = new V2(loop_at, minf(t.y, 0.0));
                        else if (_man_over > 0.2)
                        {
                            _crash("LOOPED OUT!"); _man_over = 0.0;
                        }
                    }
                    else
                    {
                        t = _tip_over(b, "LOOPED OUT!"); man_lock = 0.6;
                    }
                }
                else
                {
                    _man_over = maxf(0.0, _man_over - dt * 2.0);
                }
                man_a = t.x; man_w = t.y;
                man_zone = man_a > 0.15 && absf(man_a - b) < zone;
                man_zone_t = man_zone ? man_zone_t + dt : 0.0;
            }
            // --- front wheel: nose manual / stoppie ---
            double nb = T.get("noseBalance", 0.5);
            double n_from = T.get("noseFrom", 0.6);
            double n_lift = T.get("noseLift", 9.0);
            nose_lock = maxf(0.0, nose_lock - dt);
            _nose_grace = nose_a > 0.05 ? 0.5 : maxf(0.0, _nose_grace - dt);
            double push = clampf((body_in - n_from) / maxf(0.05, 1.0 - n_from), 0.0, 1.0);
            double grab = minf(1.0, ((brake && !front_air) ? brake_f : 0.0) * 1.8);
            bool n_can = n_lift > 0.0 && !air && !front_air && !_balancing() && v > (nose_a > 0.05 ? 1.0 : 2.5) && gest_hop <= 0.0;
            nose_push = n_can ? push * grab : 0.0;
            if (!n_can)
            {
                nose_w = 0.0; nose_a = move_toward(nose_a, 0.0, 3.0 * dt);
                nose_zone = false;
            }
            else
            {
                double n_drive = 0.0;
                if (nose_lock <= 0.0)
                {
                    n_drive += n_lift * push * (nose_a < 0.08 ? grab : maxf(grab, 0.6));
                    if (nose_a > 0.08) n_drive += T.get("noseBrake", 4.0) * grab;
                }
                n_drive -= n_lift * 0.8 * clampf((-body_in - 0.15) / 0.6, 0.0, 1.0);
                var nt = _tip(nose_a, nose_w, nb, T.get("noseGravity", 7.0), n_drive, dt);
                double n_direct = clampf(T.get("manDirect", 1.0), 0.0, 1.0);
                if (n_direct > 0.0)
                {
                    // the same on the front wheel: the stick forward is how far the rear is up (the brake only starts it);
                    // it tops out just past the balance point, it never throws him over
                    double n_tgt = nose_lock <= 0.0 ? push * (nb + 0.12) * (nose_a < 0.08 ? grab : 1.0) : 0.0;
                    n_tgt *= 1.0 - clampf((-body_in - 0.15) / 0.6, 0.0, 1.0);
                    double nk = T.get("manFollow", 40.0);
                    double nw2 = nose_w + (nk * (n_tgt - nose_a) - 2.0 * sqrt(nk) * 0.9 * nose_w) * dt;
                    double na2 = nose_a + nw2 * dt;
                    if (na2 <= 0.0)
                    {
                        na2 = 0.0; nw2 = maxf(0.0, nw2);
                    }
                    nt = new V2(lerpf(nt.x, na2, n_direct), lerpf(nt.y, nw2, n_direct));
                }
                if (nt.x > nb + T.get("noseLoop", 0.4))
                {
                    nt = _tip_over(nb, "TOO FAR!"); nose_lock = 0.6;
                }
                nose_a = nt.x; nose_w = nt.y;
                nose_zone = nose_a > 0.15 && absf(nose_a - nb) < zone;
            }
        }

        // --- the hop: one move, however it is started (hop let go, the stick snapped forward, both) ---
        /// the legs' push out of the crouch they are in, 0..1 of the best one. Only a pop that rides the rebound of a
        /// quick dip (rebound) gets all of it, a crouch held still gives popRebound less: preload, then go
        double _crouch_power()
        {
            return sqrt(clampf(crouch, 0.0, 1.0)) * (1.0 - T.get("popRebound", 0.18) * (1.0 - rebound));
        }

        /// the legs go. Close to a lip the push runs through it and leaves at its edge (pop_wait; best started in the last
        /// ~0.12 s, earlier part of the stroke is spent before the edge); anywhere else it is a hop, now
        void _pop_now(double pw)
        {
            double win = T.get("popWindow", 0.24);
            crouch = 0.0;
            // (the front wheel already off the edge with the rear still on the face is the lip too: the classic moment)
            bool edge = front_air && !rear_air && _lip_ago < 0.35;
            if (((lip_state == 2 && lip_last < win) || edge) && !rear_air && v > 3.0)
            {
                double lt = (edge || lip_state != 2) ? 0.0 : lip_last;
                pop_time = 1.0 - 0.4 * smooth01((lt - 0.12) / maxf(0.02, win - 0.12));
                pop_wait = maxf(pop_wait, pw * pop_time); _pop_arm_t = lt + 0.3; pop_fired = true;
                pro_pop = true;
                if (body_in > 0.3) _pop_latch = true;
                // (the J-hop: load, lift the front with the arms, then the legs bring the rear up. Popped on a lip's face the
                // front comes up first; the lip hold keeps it LIP_NOSE_POP over the face once it is off)
                if (!front_air && !air)
                {
                    nose_k = smooth01((_g_pitch - 0.4) / 0.35) * (1.0 - smooth01((absf(v) - 9.0) / 6.0));
                    pitch_v += POP_FRONT_LIFT * clampf(pw, 0.0, 1.0) * nose_k;
                }
                compress_v += 2.0 * pw;
                if (man_a > 0.05) man_lock = maxf(man_lock, 0.3);
            }
            else
            {
                pop_time = 0.0;
                _hop_begin(0.5 + 0.5 * minf(1.0, pw), pw);
            }
        }

        /// the scoop of a real bunny hop: hopping with the front already up (out of a manual, or the stick just pulled
        /// back), the rear is scooped up after it. Best with the front well up but short of the balance point; hauled right
        /// back to the loop-out it's a weak one. front = how far the front is up (rad)
        double _scoop_k(double front)
        {
            double b = T.get("manBalance", 0.55);
            return smooth01(front / 0.3) * (1.0 - 0.6 * smooth01((front - b) / 0.3)) * T.get("stickHop", 1.0);
        }

        /// a hop's power from the button charge and the scoop: the better of the two, plus a quarter of the other (both
        /// together beat either alone, up to 1.25 of a fully charged hop)
        double _hop_power(double charge_k, double scoop)
        {
            return minf(1.15, maxf(charge_k, scoop) + 0.15 * minf(charge_k, scoop));
        }

        /// the legs start their push (HOP_PUSH s); the pop comes at its end (_hop_pop)
        void _hop_begin(double load_k, double power)
        {
            hop_t = HOP_PUSH; hop_load = maxf(load_k, 0.5); hop_charge = power;
            compress_v = maxf(compress_v, (0.05 - compress) / HOP_PUSH);
            body_v = vy + (T["legExt"] - minf(0.0, _or(body_y, y) - y)) / HOP_PUSH;
            if (man_a > 0.05)
            {
                // out of a manual: the scoop brings the front back down, the balance lets go
                man_lock = maxf(man_lock, 0.3);
                if (man_a > T.get("manBalance", 0.55)) man_w = minf(man_w, -3.0);
            }
        }

        void _hop_pop(double load_k, double power)
        {
            double dv = _leg_dv(power);
            if (air)
            {
                // (just past a lip: late. The edge is gone, so three quarters of the push at most, less what the legs gave it)
                dv = maxf(0.0, 0.75 * dv - _pop_used);
                _pop_apply(dv);
            }
            else
            {
                _pop_used = 0.0;
                double th = clampf(_g_pitch, -0.6, 0.8);
                // (the climb / fall the bike already has along a slope is kept; the frame coming up as the front is pulled
                // into a manual is the bike turning about its rear wheel, not rider + bike rising)
                vy = clampf(vy, minf(0.0, v * sin(th)), maxf(0.0, v * sin(th)) + 0.2) + dv * cos(th); v -= signf(v) * minf(absf(v), dv * tan(th));
            }
            _pop_used += dv; pop_q = power; pop_fx = 1.0;
            kick_t = 0.3; _hop_nose_t = 0.22 + 0.15 * load_k + 0.08 * power;
            body_v = vy;
        }

        /// touch-down after a jump: the bike must meet the slope roughly lined up and facing down the trail,
        /// or the rider goes down
        void _land_trick(double at)
        {
            slip = wrapf(slip, -PI, PI);
            if (at < 0.2)
                return;
            // Everything else (nose-dive, loop-out, a slide that washes out, a hit the legs can't take) is decided
            // by the ground physics after touch-down. Only geometry is checked here: turned so far that the
            // wheels can't be what meets the ground, the rider or the bars hit first
            double perr_s = wrapf(pitch - _g_pitch, -PI, PI);   // + = nose up (back wheel first)
            if (absf(perr_s) > 1.45)
            {
                // (a flip short of all the way round lands turned against the spin, one too far lands turned with it)
                _crash(absf(flip_acc) > 3.0 && signf(perr_s) != signf(flip_acc) ? "UNDER-ROTATED!" :
                    absf(flip_acc) > 3.0 ? "OVER-ROTATED!" : perr_s > 0 ? "LOOPED OUT!" : "BAD LANDING!");
                return;
            }
            // Graded landing zone instead of a hard cut: within ~60 deg of the travel it is a normal landing; past that
            // the bike lands sideways-ish and the tyres grab the nearer axis (forward, or backwards = fakie past 90 deg)
            double a_s = absf(slip);
            if (a_s > LAND_CONE)
            {
                _rev_land = a_s > PI * 0.5;
                _land_fix = true;
                host.flash(_rev_land ? "FAKIE!" : "SKETCHY!");
            }
            int flips = roundi(absf(flip_acc) / TAU);
            int turns = (int)((absf(spin_acc) + 0.6) / TAU);   // flat spins landed facing forward again (within ~35 deg): 360, 720...
            // a whip thrown (bike kicked > ~35 deg sideways under the body) and brought back straight for the landing
            bool whipped = _whip_peak > 0.6 && turns == 0 && absf(slip) < 0.35;
            if (flips >= 1 || turns >= 1 || whipped)
            {
                string trick = "";
                if (whipped) trick = _whip_peak < 0.95 ? "WHIP" : "BIG WHIP";
                if (turns >= 1) trick = (turns * 360).ToString();
                if (flips >= 1)
                {
                    string kind = flip_acc > 0 ? "BACKFLIP" : "FRONTFLIP";
                    trick = (trick != "" ? trick + " " : "") + (flips > 1 ? new[] { "", "", "DOUBLE ", "TRIPLE " }[mini(flips, 3)] : "") + kind;
                }
                host.flash(trick + "!");
                host.on_trick(trick);
                flow_up();
            }
            _style_points(at, flips, turns);
        }

        /// style points for a landed jump: air time, spins, flips, tweaking the bike about with the stick, and a
        /// clean (straight) landing bonus. The HUD chains them into combos and drops them if the rider goes down
        void _style_points(double at, int flips, int turns)
        {
            if (at < 0.35) return;
            int pts = roundi(at * 250.0) + turns * 600 + flips * 1000 + roundi(minf(style_air, 3.0) * 400.0);
            var parts = new List<string>();
            if (turns >= 1) parts.Add((turns * 360).ToString());
            if (flips >= 1) parts.Add((flips > 1 ? flips + "x " : "") + (flip_acc > 0 ? "BACKFLIP" : "FRONTFLIP"));
            bool whip_ok = _whip_peak > 0.6 && turns == 0 && absf(wrapf(slip, -PI, PI)) < 0.35;
            if (whip_ok)   // an air whip brought back for the landing: more the further it was thrown
            {
                pts += roundi(500.0 * clampf(_whip_peak, 0.6, 1.3));
                parts.Add(_whip_peak < 0.95 ? "WHIP" : "BIG WHIP");
            }
            // a scrub: the lip soaked with the bike laid / whipped low; a tabletop: laid right over in the air and
            // brought back up for the landing
            bool landed_up = absf(bike_lean) < 0.4;
            if (_scrub_k > 0.3 && (_lean_peak > 0.5 || _whip_peak > 0.4))
            {
                pts += 400; parts.Add("SCRUB");
            }
            else if (_lean_peak > 0.9 && landed_up && !whip_ok)
            {
                pts += roundi(450.0 + 400.0 * clampf((_lean_peak - 0.9) / 0.4, 0.0, 1.0));
                parts.Add(_lean_peak < 1.15 ? "TABLETOP" : "BIG TABLETOP");
            }
            else if (style_air > 0.35 && !whip_ok) parts.Add("TWEAK");
            if (parts.Count == 0) parts.Add(at > 1.0 ? "BIG AIR" : "AIR");
            bool clean = absf(wrapf(slip, -PI, PI)) < 0.2 && absf(wrapf(pitch - _g_pitch, -PI, PI)) < 0.15;
            if (clean)
            {
                pts = roundi(pts * 1.5);
                parts.Add("CLEAN");
            }
            host.on_style(pts, string.Join(" + ", parts));
        }

        /// crash judge (see _risk): sev = how far past the line this step (<= 0 = within it). Builds over crashTime at sev
        /// 1 (faster the further past), drains at riderSave /s once back under; a full meter or sev >= crashHard = the crash
        void _danger(string reason, double sev, double dt, double t_build = -1.0)
        {
            double r = _risk.TryGetValue(reason, out var r0) ? r0 : 0.0;
            if (sev > 0.0 && absf(v) > 2.5)
            {
                if (sev >= T.get("crashHard", 3.0)) r = 1.0;
                else r += dt / maxf(0.05, t_build > 0.0 ? t_build : T.get("crashTime", 0.4)) * sev * (0.5 + 0.5 * sev);
            }
            else
            {
                r = maxf(0.0, r - dt * T.get("riderSave", 1.2));
            }
            _risk[reason] = r;
            if (r >= 1.0) _crash(reason);
        }

        /// a crash this step: the first reason found is the one reported (later checks in the same step don't overwrite it)
        void _crash(string reason)
        {
            if (crash_pending == "")
                crash_pending = reason;
        }

        /// once a step, after every _danger: the biggest meter (risk) and a SAVED! when a real scare was fought off
        void _risk_settle(double dt)
        {
            if (air)   // (the ground-only checks don't run in the air: their meters drain there)
            {
                _risk_keys.Clear(); _risk_keys.AddRange(_risk.Keys);   // (a cached list: a Dictionary can't be changed while walked)
                foreach (var k in _risk_keys) _risk[k] = maxf(0.0, _risk[k] - dt * T.get("riderSave", 1.2));
            }
            risk = 0.0;
            foreach (var kv in _risk) risk = maxf(risk, kv.Value);
            _risk_peak = maxf(_risk_peak, risk);
            if (risk < 0.02)
            {
                if (_risk_peak > 0.5 && crash_pending == "" && !crash_on)
                {
                    if (host.msg_idle()) host.flash("SAVED!");
                    host.on_style(roundi(300.0 * _risk_peak), "SAVE");
                }
                _risk_peak = 0.0;
            }
        }
    }
}
