// Port of godot/scripts/bike/bike_physics.gd, group E: the vertical step (_step_vertical: springs, tyres, suspension
// substeps, the rider's legs, the manual / nose holds, air, take-off, landing judging) and _sus_cache, _leg_dv,
// _pop_apply, _pop_along. Line for line; every BMX_OLD_* switch is ported as off, probes / prints / profiling dropped.
using System;
using System.Collections.Generic;
using System.Globalization;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    public sealed partial class BikePhysics
    {
        static readonly V2[] _BODY_PTS = { new V2(0.02, 0.98), new V2(0.0, 0.66) };

        void _step_vertical(double dt, V3 f, double throttle, bool brake)
        {
            var terrain = host.terrain;
            // --- vertical + pitch: spring physics ---
            if (_bog > 0.0)
            {
                double take = minf(_bog, _bog_rate * dt);
                _bog -= take;
                if (absf(v) > take) v -= signf(v) * take;
            }
            _sample(f);
            bool natural;
            double dP = _g_pitch - _or(g_pitch, _g_pitch);
            double v_pre = v;
            if (!air && dP > 0.02 && v > 0) v *= cos(minf(dP, 1.2));
            double proj_dv = v - v_pre;   // speed lost to the ground kinking up this step (a rock's edge, a curb)
            g_pitch = _g_pitch;
            natural = terrain.jump_mask(x, z) < 0.05;
            double climb_max = absf(v) * 0.9 + 0.3;
            double XF = L - BB_REAR;
            double XR = -BB_REAR;
            double cp0 = cos(clampf(pitch, -1.3, 1.3));
            double hfC = _wheel_ground(f, XF, RWF, cp0);
            double hrC = _wheel_ground(f, XR, RWR, cp0);
            if (!w_init || is_nan(hf_prev))
            {
                hf_prev = hfC; hr_prev = hrC; pitch_v = 0; w_init = true;
            }
            if (!is_finite(zw_f + zw_r + vw_f + vw_r))
            {
                zw_f = hfC; zw_r = hrC; vw_f = 0.0; vw_r = 0.0;
            }
            double hfP = hf_prev;
            double hrP = hr_prev;
            double vgF = minf((hfC - hfP) / dt, climb_max);
            double vgR = minf((hrC - hrP) / dt, climb_max);
            hf_prev = hfC; hr_prev = hrC;
            double shF = 1 - SH_R;
            double shR = SH_R;
            double IK = 0.32;
            bool coupled = !air && !(hop_t > 0) && !(lift_t > 0);
            double PHI = coupled ? clampf(T["riderMass"], 0, 0.7) : 0.0;
            double mB = 1 - PHI;
            double Kb = pow(2 * PI * T["tyreHz"], 2);
            double K = Kb * mB;
            double C = 2 * T["tyreDamp"] * sqrt(Kb) * mB;
            // legs stiffen as the rider crouches into a lip, and brace for the first moments after a landing
            double brace = 1.0 - smooth01(since_land / 0.35);
            double kB = T["legStiff"] * (1 + 5 * prep + 4 * brace);
            // --- auto-absorb: a crest the bike can't follow at this speed is seen coming; the legs bend on the face before
            // it (the leg spring's rest moves, rel_t: no speed gained) so they have their stroke to hold the bike down on it
            double rel_t = 0.0;
            double ab = T.get("autoAbsorb", 0.0);
            bool ab_on = ab > 0.0 && !air && prep < 0.1 && natural && !(hop_t > 0) && kick_t <= 0.0 && man_a < 0.05 && nose_a < 0.05 && absf(pleg) < 0.1 && since_land > 0.3;
            _ab_k = move_toward(_ab_k, ab_on ? 1.0 : 0.0, dt * 6.0);
            if (_ab_k > 0.0 && absf(v) > 4.0)
            {
                double worst = 0.0;   // the hardest throw-off ahead, in g past standing (< 0 = it flies)
                double here = 0.0;    // the same under the bike now
                for (int q = 0; q < 4; q++)
                {
                    double dq = q == 0 ? 0.0 : signf(v) * absf(v) * (0.02 + 0.1 * q);   // (0.12 .. 0.32 s ahead)
                    // (the curve read over about an eighth of a second of travel)
                    double sp = clampf(absf(v) * 0.12, 0.7, 3.0);
                    double hq = terrain.deck_height(x + f.x * dq, z + f.z * dq);
                    double kq = (terrain.deck_height(x + f.x * (dq + sp), z + f.z * (dq + sp)) + terrain.deck_height(x + f.x * (dq - sp), z + f.z * (dq - sp)) - 2.0 * hq) / (sp * sp);
                    if (q == 0) here = minf(0.0, 1.0 + v * v * kq / G);
                    else worst = minf(worst, 1.0 + v * v * kq / G);
                }
                // bend for the crest coming (from 0.3 g short of flying); on it the legs come back to their rest
                double on_it = smooth01(-here / 0.6);
                _ab_bend = move_toward(_ab_bend, smooth01((0.3 - worst) / 0.8) * (1.0 - on_it), dt * 5.0);
                rel_t = -0.85 * T["legComp"] * _ab_bend * minf(1.0, ab) * _ab_k;
                kB *= 1.0 + 1.5 * _ab_k * minf(1.0, ab);   // (working legs, not hanging ones)
            }
            else
            {
                _ab_bend = 0.0;
            }
            dg_abs = rel_t;
            double cB = 2 * sqrt(kB) * T["legDamp"];
            double press = (natural && !(hop_t > 0) && !(lift_t > 0)) ? T["legPress"] * G : 0.0;
            // (a bike with a real suspension setup needs much less of this: its rebound damping keeps it on the ground)
            if (sus != null) press *= 0.35;
            n_ref = _or(n_ref, G + press) + (G + press - _or(n_ref, G + press)) * minf(1.0, dt * 2 * PI * T["tyreHz"] * 0.6);
            double TRAVEL = T["travel"];
            double WHEEL_M = T.get("wheelMass", 0.03);
            double BLOW_V = T.get("damperKnee", 0.6);
            double BLOW_K = T.get("damperBlow", 0.2);
            // ---- the two ends, each its own suspension unit (SuspSetup): travel (tr), spring rate (k) with its ramp-up
            // (pg: F = k x (1 + pg (x / tr)^2)), the compression it rests at (s0: its sag), compression damping (cc; past the
            // knee BLOW_V only hs of it), rebound (cr), seal friction (fr), the bump stop (bs), the tyre's stiffness (ty, from
            // the pressure). A bike with no setup (the BMX) keeps the one simple spring, the same at both ends
            double trF = TRAVEL; double trR = TRAVEL;
            double kF = shF * K; double kR = shR * K;
            double pgF = 0.0; double pgR = 0.0;
            double ccF = shF * C; double ccR = shR * C; double crF = ccF; double crR = ccR;
            double hsF = BLOW_K; double hsR = BLOW_K;
            double frF = 0.0; double frR = 0.0;
            double bsF = 6.0; double bsR = 6.0;
            double sq_cm = T.get("tyreSquash", 1.2) * 0.01;
            double tyKF = 0.5 * G / sq_cm; double tyKR = tyKF;
            double s0F = (G + press) / K; double s0R = s0F;
            if (sus != null)
            {
                if (_su.Length != 18) _sus_cache();   // (the units' numbers as plain floats)
                // (the Ride sliders still work on top of the setup, as multipliers)
                double k_mul = (T["tyreHz"] / 2.4) * (T["tyreHz"] / 2.4);
                double d_mul = T["tyreDamp"] / 0.39;
                double sag_mul = T.get("suspSag", 1.0);
                double pg_mul = T.get("suspProg", 1.0);
                double rb_mul = T.get("suspRebound", 1.0);
                trF = _su[0]; trR = _su[8];
                if (host.susp != null)   // never more than the drawn fork / rear end can move (the tyres follow the ground)
                {
                    if (host.susp.has_f) trF = minf(trF, host.susp.front_max - host.susp.front_min);
                    if (host.susp.has_r) trR = minf(trR, host.susp.rear_max - host.susp.rear_min);
                }
                trF = maxf(trF, 0.03); trR = maxf(trR, 0.03);
                pgF = _su[2] * pg_mul; pgR = (_su[10] + FRAME_PROG * T.get("shockProg", 1.0)) * pg_mul;   // (+ the frame's linkage)
                double sgF = clampf(_su[1] * sag_mul, 0.1, 0.5);
                double sgR = clampf(_su[9] * sag_mul, 0.1, 0.5);
                // the rate that sits this end at its sag under its share of the weight
                kF = shF * G / (sgF * trF * (1.0 + pgF * sgF * sgF)) * k_mul;
                kR = shR * G / (sgR * trR * (1.0 + pgR * sgR * sgR)) * k_mul;
                double ccrF = 2.0 * sqrt(kF * shF * mB);
                double ccrR = 2.0 * sqrt(kR * shR * mB);
                ccF = _su[3] * ccrF * d_mul; ccR = _su[11] * ccrR * d_mul;
                crF = _su[4] * ccrF * d_mul * rb_mul; crR = _su[12] * ccrR * d_mul * rb_mul;
                hsF = clampf(_su[5] * BLOW_K / 0.4, 0.05, 1.0); hsR = clampf(_su[13] * BLOW_K / 0.4, 0.05, 1.0);
                frF = _su[6] * shF * G; frR = _su[14] * shR * G;
                bsF = _su[7]; bsR = _su[15];
                tyKF = 0.5 * G / (sq_cm * SuspSetup.PSI_REF / _su[16]); tyKR = 0.5 * G / (sq_cm * SuspSetup.PSI_REF / _su[17]);
                s0F = SuspSetup.rest(shF * (G + press), kF, trF, pgF); s0R = SuspSetup.rest(shR * (G + press), kR, trR, pgR);
                if (!_sus_synced && host.susp != null)   // the drawn fork / rear end sit at the same sag
                {
                    _sus_synced = true;
                    host.susp.set_sag(SuspSetup.rest(shF * G, kF, trF, pgF) / trF, SuspSetup.rest(shR * G, kR, trR, pgR) / trR);
                }
                if (absf(sag_mul - _sag_seen) > 0.001)   // (the sag slider moved: the drawn ends follow)
                {
                    _sag_seen = sag_mul; _sus_synced = false;
                }
            }
            else if (host.susp != null)   // (Godot: and host.susp.wheels_follow, always on in a ride)
            {
                if (host.susp.has_f) trF = clampf(s0F + host.susp.front_max, 0.05, TRAVEL);
                if (host.susp.has_r) trR = clampf(s0R + host.susp.rear_max, 0.05, TRAVEL);
            }
            double tyCF = 0.5 * sqrt(tyKF * WHEEL_M); double tyCR = 0.5 * sqrt(tyKR * WHEEL_M);
            // ---- what the step can integrate: a wheel is a small mass between two springs and a damper, stepped explicitly;
            // past stiffness x step^2 / mass ~ 4, or damping x step / mass ~ 2 it would blow apart. Every stiffness shares
            // k_cap, each damping rate is at most c_cap
            int n_sub = clampi((int)round(T.get("suspSubsteps", 4.0)), 1, 32);   // substeps a tick (4 = 480 Hz)
            double h_sub = dt / n_sub;
            double k_cap = WHEEL_M * (1.1 / h_sub) * (1.1 / h_sub);
            double c_cap = 0.9 * WHEEL_M / h_sub;
            ccF = minf(ccF, c_cap); ccR = minf(ccR, c_cap); crF = minf(crF, c_cap); crR = minf(crR, c_cap);
            double fr_w = maxf(0.04, maxf(frF, frR) / maxf(0.3 * c_cap, 1e-6));   // (the friction's ease through zero is a damper too)
            double ks_cap = 0.35 * k_cap;
            double kt_cap = 0.65 * k_cap;
            tyKF = minf(tyKF, kt_cap); tyKR = minf(tyKR, kt_cap);
            tyCF = minf(tyCF, 0.5 * c_cap); tyCR = minf(tyCR, 0.5 * c_cap);
            // ---- the suspension's geometry: brake dive (the fork slides along the tilted steering axis, so the front brake
            // pushes it in by brake x tan(tilt)), anti-squat under drive and anti-rise under the rear brake.
            // dvF / dvR = that extra push on each spring (+ = compresses). The tyres' loads on the ground don't change
            double dvF = 0.0;
            double dvR = 0.0;
            if (sus != null && !air && v > 0.3)
            {
                double geo = T.get("suspGeo", 1.0);
                double tan_f = 0.5;
                // (Godot: axis.y > 0.3 -> |axis.x| / axis.y; axis.y > 0.3 of a unit axis = tan < sqrt(0.91) / 0.3)
                if (host.susp != null && host.susp.axis_tan < sqrt(1.0 - 0.09) / 0.3) tan_f = clampf(absf(host.susp.axis_tan), 0.2, 0.75);
                bool braking = _b_prev > 0.0;
                if (braking) dvF = _fb_f * tan_f * geo;
                double h_l = T["loadHeight"] / maxf(L, 0.5);   // (the same lever the weight transfer's pitch torque uses)
                double a_sq = T.get("antiSquat", 0.9);
                dvR = ((braking ? (_fb_r * ANTI_RISE) : 0.0) - maxf(0.0, a_drive) * a_sq) * h_l * geo;
                // pedal bob: the chain pulls hardest on the downstrokes, what the anti-squat doesn't cancel pumps the shock.
                // Zero on average. Only a bike with a rear shock; the push goes through its own spring and damper
                if (pedal > 0.05 && a_drive > 0.3 && _rear_shock())
                {
                    double stroke = (absf(sin(crank)) - 0.6366) / 0.6366;
                    dvR += stroke * a_drive * (1.1 - 0.7 * a_sq) * h_l * BOB_K * T.get("pedalBob", 1.0);
                }
            }
            double bal_max = T["riderBalance"] * G * BB_REAR / IK;
            // rolling off an edge at speed the rider holds the bike level with his weight (only where the ground really falls
            // away under the front, off level ground: a drop's deck)
            double edge_k = 0.0;
            if (front_air && !rear_air && !air && wheelie_up <= 0.0 && nose_a <= 0.0)
            {
                edge_k = smooth01((absf(v) - 2.0) / 5.0) * smooth01((zw_f - hfC - 0.15) / 0.25) * (1.0 - smooth01((absf(_local_slope(f, XR, RWR, cp0)) - 0.05) / 0.1));
                // (not just after a touch-down: a rear-first landing has the front axle high over level ground too)
                edge_k *= smooth01((since_land - SETDOWN_T) / 0.3);
                bal_max *= 1.0 + 2.5 * edge_k;
            }
            // hands off the rider loads a lip's face so the bike follows it to its edge, the front held up to LIP_NOSE over the
            // face (popping LIP_NOSE_POP); a squash pushes the front down to the face. Not while he soaks the lip up
            double lip_hold = 0.0; double lip_ref = 0.0;
            if (front_air && !rear_air && !air && lip_state == 2 && wheelie_up <= 0.0
                && nose_a <= 0.0 && auto_absorb * prep < 0.05)
            {
                bool popping = (pop_wait > 0.0 && pro_pop) || crouch > 0.1;
                double face_sl = _local_slope(f, XR, RWR, cp0);
                // (the front comes up on a STEEP lip taken SLOW; on a flatter or fast lip it stays near the face)
                nose_k = smooth01((face_sl - 0.4) / 0.35) * (1.0 - smooth01((absf(v) - 9.0) / 6.0));
                lip_ref = face_sl + (squash > 0.2 ? 0.0 : (popping ? LIP_NOSE_POP : LIP_NOSE) * nose_k);
                lip_hold = clampf(maxf(prep, popping ? 1.0 : 0.0) / 0.3, 0.0, 1.0);
                bal_max *= 1.0 + 2.5 * lip_hold;
            }
            // after a rear-first landing the rider lowers the front: the nose may only come down at SETDOWN_W0 + SETDOWN_K x
            // how far up it still is. Not in a manual, at a lip, off an edge
            double setdown = 0.0;
            if (front_air && !rear_air && !air && wheelie_up <= 0.0 && nose_a <= 0.0 && lip_hold <= 0.0)
                setdown = 1.0 - smooth01((since_land - SETDOWN_T) / 0.3);
            {
                double R = T["weightShift"];
                double x_brake = -0.8 * R * ((brake && !air) ? 1.0 : 0.0) + 0.5 * R * clampf(a_pedal / 4, 0, 1);
                double xT = air ? 0.0 : x_brake + R * clampf(_g_pitch * 2.2, -1, 1);
                // in the air the rider leans where they choose (W forward, S back)
                if (air)
                    xT = air_lean * R;
                double hT = air ? air_lean * R : x_brake;
                // the body stick moves the rider fore / aft on the ground too, further than the auto shift reaches
                double reach = R * T.get("stickShift", 1.7);
                double R2 = maxf(R, absf(body_in_s) * reach);   // stick idle: exactly the old limits
                if (!air)
                {
                    xT = clampf(xT, -R, R) + body_in_s * reach; hT = clampf(hT, -R, R) + body_in_s * reach;
                }
                else   // in the air the body shifts with the stick too (the bike tilts against it)
                {
                    xT += body_in_s * reach * 0.7; hT += body_in_s * reach * 0.7;
                }
                // a damped spring to where the rider wants to be, pushed by the bike's own speed changes
                double a_body = 0.0;
                if (!is_nan(v_last) && !air)
                {
                    // (not the kink loss above: over a rock that is a one-step spike)
                    a_body = clampf((v - v_last - proj_dv) / maxf(dt, 1e-4), -40.0, 40.0);
                }
                // (not through a flight: the landing re-projects v onto the slope)
                v_last = air ? NAN : v;
                double kx = T["bodyStiff"];
                double cx = 2 * sqrt(kx) * 0.75;
                double push = -a_body * T["bodyInertia"];
                body_xv += (kx * (clampf(xT, -R2, R2) - body_x) - cx * body_xv + push) * dt;
                body_x = clampf(body_x + body_xv * dt, -R2 * 1.4, R2 * 1.4);
                hip_v += (kx * (clampf(hT, -R2, R2) - hip_shift) - cx * hip_v + push) * dt;
                hip_shift = clampf(hip_shift + hip_v * dt, -R2 * 1.6, R2 * 1.6);
            }
            double tq = a_drive * T["loadHeight"];
            // sprint wheelie: stamping on the pedals from slow lifts the front into the balance manual (manSprintLift)
            bool pulling = sprint > 0.5 && !air && throttle > 0.1 && !brake;
            _sprint_lift = pulling ? sprint * minf(throttle, 1.0) * slowness(v) : 0.0;
            // the balance, either end (_balance_step): manual / wheelie (man_a), nose manual / stoppie (nose_a)
            bool pedalling = throttle > 0.1 && !brake;
            _balance_step(dt, pedalling, throttle, brake);
            // style: a wheelie / manual held a while scores when it comes down
            if (man_a > 0.12 && front_air && !rear_air)
            {
                wheelie_time += dt; wheelie_pedal = wheelie_pedal || pedalling;
            }
            else if (man_a < 0.05 && wheelie_time > 0.0)
            {
                if (wheelie_time > 1.0)
                    host.on_style(roundi(wheelie_time * 220.0), string.Format(CultureInfo.InvariantCulture, "{0} {1:0.0} s", wheelie_pedal ? "WHEELIE" : "MANUAL", wheelie_time));
                wheelie_time = 0.0; wheelie_pedal = false;
            }
            // (wheelie_up = the front's hold in the vertical step: man_a, set down no faster than wheelieDrop)
            wheelie_up = maxf(man_a, wheelie_up - T.get("wheelieDrop", 1.6) * (1.0 + 3.0 * T.get("manDirect", 1.0)) * dt);
            if (nose_a > 0.12 && rear_air && !front_air)
            {
                nose_time += dt;
                if (brake) nose_brake_t += dt;
            }
            else if (nose_a < 0.05 && nose_time > 0.0)
            {
                if (nose_time > 0.8)
                    host.on_style(roundi(nose_time * 260.0), string.Format(CultureInfo.InvariantCulture, "{0} {1:0.0} s", nose_brake_t > nose_time * 0.6 ? "STOPPIE" : "NOSE MANUAL", nose_time));
                nose_time = 0.0; nose_brake_t = 0.0;
            }
            // a held manual / wheelie follows the ground it rolls onto
            if ((wheelie_up > 0.0 || nose_a > 0.0) && !air && !is_nan(nose_ref))
                nose_ref = lerpf(nose_ref, _g_pitch, minf(1.0, dt * 6.0));
            if (wheelie_up > 0.0 || nose_a > 0.0)
                bal_max = maxf(bal_max, 30.0);   // the whole body holds a wheelie, not just the hands
            // (on the front wheel the whole weight is ~twice as far from the contact: the hold takes more)
            if (nose_a > 0.0) bal_max = maxf(bal_max, 75.0);
            bool was_air = air;
            double g_jolt = 0.0;   // legs bottomed out on the ground this step (a compression, not a landing)
            double vy_in = vy;
            bool was_f = c_f;
            bool was_r = c_r;
            bool cF = false;
            bool cR = false;
            double sumF = 0.0;
            double sumR = 0.0;
            if (!is_finite(body_y))
            {
                body_y = y; body_v = vy;
            }
            int N = n_sub;
            double h = dt / N;
            for (int i = 1; i < N + 1; i++)
            {
                double u = (double)i / N;
                double gF = hfP + (hfC - hfP) * u;
                double gR = hrP + (hrC - hrP) * u;
                double cs = cos(pitch);
                double sn = sin(pitch);
                double dF = zw_f - (y + XF * sn) + s0F;
                double dR = zw_r - (y + XR * sn) + s0R;
                double pvF = vy + XF * cs * pitch_v;
                double pvR = vy + XR * cs * pitch_v;
                // touching the ground = the tyre is squashed by it
                cF = gF > zw_f; cR = gR > zw_r;
                // shock damper: full up to a knee, then it blows off; rebound its own rate; plus seal friction
                double relF = vw_f - pvF;
                double relR = vw_r - pvR;
                double cdF = (relF >= 0.0 ? ccF * (relF <= BLOW_V ? relF : BLOW_V + hsF * (relF - BLOW_V)) : crF * relF) + frF * clampf(relF / fr_w, -1.0, 1.0);
                double cdR = (relR >= 0.0 ? ccR * (relR <= BLOW_V ? relR : BLOW_V + hsR * (relR - BLOW_V)) : crR * relR) + frR * clampf(relR / fr_w, -1.0, 1.0);
                // the last fifth of the travel is the bump stop (rubber: pushes back hard only while being squeezed)
                double bpF = maxf(0.0, dF / trF - 0.8) * 5.0 * smooth01(relF / 0.3);
                double bpR = maxf(0.0, dR / trR - 0.8) * 5.0 * smooth01(relR / 0.3);
                double uF = dF / trF;
                double uR = dR / trR;
                double FF = dF > 0.0 ? maxf(0.0, minf(kF * (1.0 + pgF * uF * uF) * (1.0 + bsF * bpF * bpF), ks_cap) * dF + cdF) : 0.0;
                double FR = dR > 0.0 ? maxf(0.0, minf(kR * (1.0 + pgR * uR * uR) * (1.0 + bsR * bpR * bpR), ks_cap) * dR + cdR) : 0.0;
                // on the stop (100 %: it never goes past) the tyre's push goes straight into the frame
                if (dF >= trF - 0.0005) FF = maxf(FF, _ty_f);
                if (dR >= trR - 0.0005) FR = maxf(FR, _ty_r);
                sumF += maxf(0.0, FF - (cF ? dvF : 0.0)); sumR += maxf(0.0, FR - (cR ? dvR : 0.0));   // (the tyres' loads: less the geometry's part)
                if (i == 1)
                {
                    dg_botF = false; dg_botR = false; dg_blowF = false; dg_blowR = false;
                }
                dg_xF = dF; dg_xR = dR; dg_vF = relF; dg_vR = relR; dg_fF = FF; dg_fR = FR;
                dg_blowF = dg_blowF || relF > BLOW_V; dg_blowR = dg_blowR || relR > BLOW_V;
                double leg_f = 0.0;
                // a turn's load presses down through the leaned bike (corner_g): the body sinks into the legs
                double cg = was_air ? 0.0 : corner_g;
                if (!was_air)
                {
                    double f_leg = kB * (y + rel_t - body_y) - cB * (body_v - vy);
                    body_v += (f_leg - cg) * h; body_y += body_v * h;
                    leg_f = PHI * (G + f_leg);
                    dg_leg_f = f_leg;
                }
                double geoF = cF ? dvF : 0.0;
                double geoR = cR ? dvR : 0.0;
                double alpha = ((FF - geoF) * XF + (FR - geoR) * XR - leg_f * body_x) * cs / IK + ((cF || cR) ? tq / IK : 0.0);
                bool w_up = wheelie_up > 0.0 && cR;
                bool e_up = nose_a > 0.0 && cF && !w_up;   // a nose manual: the same hold, about the front wheel
                if (cF != cR || w_up || e_up)
                {
                    double @ref = _or(nose_ref, _g_pitch) + (cR ? wheelie_up : 0.0) - (e_up ? nose_a : 0.0);
                    double wk = e_up ? 8.0 : (w_up ? 4.0 : 1.0 + 5.0 * edge_k);   // holding a wheelie: the whole body works it
                    if (lip_hold > 0.0 && cR)   // (loading the lip: the bike held to the face under the rear wheel)
                    {
                        @ref = lerpf(@ref, lip_ref, lip_hold); wk = maxf(wk, 1.0 + 5.0 * lip_hold);
                    }
                    alpha += clampf(30 * wk * (@ref - pitch) - 9 * sqrt(wk) * pitch_v, -bal_max, bal_max);
                    // the rider's weight is over the front axle in a nose manual: the fork's push doesn't lever the bike back
                    if (e_up) alpha -= FF * XF * cs / IK * smooth01(nose_a / 0.15);
                }
                vy += (FF + FR - geoF - geoR - ((cF || cR) ? press : 0.0) - mB * (G + cg) - leg_f) / mB * h;
                pitch_v += alpha * h;
                if (setdown > 0.0 && cR && !cF && pitch_v < 0.0)   // (rear-first landing: the front lowered, not dropped)
                {
                    double sd_err = pitch - _g_pitch;   // (the ground it landed on)
                    if (sd_err > 0.0)
                    {
                        // (the harder the hit into the landing, the less of the rear's kick his arms and body hold back)
                        double sd_hit = SETDOWN_HIT * maxf(0.0, _vn_td - SETDOWN_HIT0);
                        double sd_w = minf(SETDOWN_MAX + sd_hit, SETDOWN_W0 + sd_hit + SETDOWN_K * sd_err);
                        if (pitch_v < -sd_w) pitch_v = lerpf(pitch_v, -sd_w, setdown);
                    }
                }
                if (!cF && !cR && was_air)
                {
                    // in the air: no outside torque. The shared spin air_w only changes with the inertia (tuck), the bike
                    // turns with it plus whatever tilt the rider gives it against their own body
                    if (_absorb_k > 0.0)   // the hands-off absorb of a small lip, now that the rear is off it too
                    {
                        if (vy > 0.3)
                        {
                            double ad = minf(T["popPower"] * 1.4 * _absorb_k, 0.6 * vy);
                            double sp2a = v * v + vy * vy;
                            vy -= ad;
                            v = signf(v) * sqrt(maxf(0.0, sp2a - vy * vy));
                        }
                        _absorb_k = 0.0;
                    }
                    double I_new = 1.0 - T["riderShare"] * T["tuckSpin"] * air_pull;
                    air_w *= air_inertia / I_new; air_inertia = I_new;
                    // arcade air control: holding W / S spins the bike at a steady rate, letting go eases it out
                    double arc = T["airArcade"];
                    if (arc > 0.0)
                    {
                        if (absf(flip_in) > 0.05)
                        {
                            // (a flip is thrown at the lip: without a throw the stick only rolls it FLIP_AIR_ONLY as fast;
                            // tucked it turns faster)
                            double f_cap = lerpf(FLIP_AIR_ONLY, 1.0, maxf(0.0, _flip_in * signf(flip_in))) / maxf(air_inertia, 0.5);
                            double f_rate = flip_in * T["airSpinRate"] * spin_k * f_cap;
                            // (a flip THROWN at the lip and held turns fast enough to come round before the predicted touch-down)
                            double thrown = maxf(0.0, _flip_in * signf(flip_in));
                            if (thrown > 0.3 && absf(flip_in) > 0.5 && !is_nan(_land_pitch) && _land_t > 0.05)
                            {
                                // (only for the first turn)
                                double done = absf(flip_acc);
                                double left = TAU - done;
                                if (left > 0.35)
                                {
                                    double need = left / maxf(_land_t, 0.12) * 1.05;
                                    f_rate = signf(f_rate) * clampf(maxf(absf(f_rate), need), 0.0, FLIP_RATE_MAX);
                                }
                            }
                            air_w += (f_rate - air_w) * minf(1.0, T["airSpinResp"] * h) * arc;
                        }
                        else
                        {
                            air_w *= 1.0 - minf(1.0, T["airSpinStop"] * h) * arc;
                        }
                    }
                    double tgt;
                    double kt_base = 70.0;
                    if (absf(flip_in) > 0.05)
                    {
                        tgt = flip_in * T["airTilt"];
                    }
                    else
                    {
                        double hh = maxf(0.0, y - _g_y);
                        double tg = (vy + sqrt(vy * vy + 2 * G * hh)) / G;
                        double aim_g = is_nan(_land_pitch) ? _g_pitch : _land_pitch;   // (the landing's slope ahead, not the deck below)
                        tgt = wrapf(aim_g - (pitch - air_tilt + air_w * minf(tg, 1.0)), -PI, PI);
                        // hands off he holds the take-off attitude for airAimDelay s, then eases round, reaching for the
                        // landing only in the last moments (a bike turned well away from the landing slope is brought back at once)
                        double off_k = clampf((absf(tgt) - 0.3) / 0.3, 0.0, 1.0);
                        // a SHORT flight levels the bike sooner, firmer, quicker
                        double aim_delay = T.get("airAimDelay", 1.0);
                        double aim_ramp = 0.5;
                        double short_k = 0.0;
                        if (!is_nan(_land_pitch) && _land_t > 0.0)
                        {
                            double tot = air_time + _land_t;
                            short_k = (1.0 - smooth01((tot - SHORT_FROM) / (SHORT_TO - SHORT_FROM))) * clampf(T.get("shortAim", 0.0), 0.0, 1.0);
                            aim_delay = lerpf(aim_delay, SHORT_DELAY * tot, short_k);
                            aim_ramp = lerpf(aim_ramp, SHORT_RAMP * tot, short_k);
                        }
                        double aim_k = maxf(maxf(smooth01((air_time - aim_delay) / maxf(aim_ramp, 0.05)), land_prep), off_k);
                        // (a pro flight: the pull-up owns the first part of it)
                        if (pro_flight) aim_k = maxf(smooth01((air_time - PULL_HOLD) / 0.35), land_prep);
                        double help_s = lerpf(air_help, maxf(air_help, SHORT_HELP * (1.0 - _air_own) * (air_help > 0.0 ? 1.0 : 0.0)), short_k);
                        tgt *= aim_k * (pro_flight ? maxf(air_help, 0.95 * (1.0 - _air_own)) : help_s);   // landing help: hands off only (a pro flight: he puts it down himself)
                        // a popped take-off: he pulls the bars to his waist, the bike leaves pointing well above the lip and he
                        // holds it there a moment before he levels it
                        _pull_k = 0.0;
                        if (_air_pop > 0.0)
                        {
                            _pull_k = smooth01((air_time - 0.02) / 0.12) * (1.0 - aim_k);
                            tgt += AIR_PULL_UP * _air_pop * _pull_k;
                        }
                        kt_base = lerpf(lerpf(lerpf(T.get("airAimSpeed", 14.0), SHORT_SPEED, short_k), 45.0, off_k), 70.0, land_prep);
                    }
                    // (hands off he may bring the nose further DOWN for the landing than the arms alone tilt it)
                    double scoop = SCOOP_TILT * (1.0 - _air_own);
                    tgt = clampf(tgt, -T["airTilt"] - scoop, T["airTilt"]);
                    // right stick: the nose goes where it points, on top of the landing aim
                    double st_t = T.get("stickAirTilt", 0.55);
                    tgt += air_stick.y * st_t;
                    double t_lim = T["airTilt"] + absf(air_stick.y) * st_t;
                    // quick when they aim it at the landing on their own, softer when the stick swings it round
                    double soft = clampf(air_stick.length() * 3.0 + absf(edge_s) * 2.0, 0.0, 1.0);
                    double kt = lerpf(kt_base, 50.0, soft);
                    if (pro_flight) kt = maxf(kt, lerpf(55.0, 90.0, maxf(_pull_k, land_prep)));   // (a pull on the bars: quick, the whole body)
                    air_tilt_v += (kt * (tgt - air_tilt) - 2.0 * sqrt(kt) * 0.85 * air_tilt_v) * h;
                    air_tilt += air_tilt_v * h;
                    double t_lo = t_lim + scoop;
                    if (air_tilt > t_lim || air_tilt < -t_lo)
                    {
                        air_tilt = clampf(air_tilt, -t_lo, t_lim);
                        if (air_tilt_v * air_tilt > 0) air_tilt_v = 0.0;
                    }
                    pitch_v = air_w + air_tilt_v;
                }
                y += vy * h; pitch += pitch_v * h;
                // wheels: tyre spring from the ground, the shock's reaction, gravity (a tyre squashed deep gets much stiffer)
                double sqF = gF - zw_f;
                double sqR = gR - zw_r;
                double tyF = sqF > 0.0 ? maxf(0.0, minf(tyKF * (1.0 + minf(5.0, sqF * sqF / 0.0009)), kt_cap) * sqF + tyCF * (vgF - vw_f)) : 0.0;
                double tyR = sqR > 0.0 ? maxf(0.0, minf(tyKR * (1.0 + minf(5.0, sqR * sqR / 0.0009)), kt_cap) * sqR + tyCR * (vgR - vw_r)) : 0.0;
                _ty_f = tyF; _ty_r = tyR;
                vw_f += ((tyF - FF + (sqF > 0.0 ? dvF : 0.0)) / WHEEL_M - G) * h; zw_f += vw_f * h;
                vw_r += ((tyR - FR + (sqR > 0.0 ? dvR : 0.0)) / WHEEL_M - G) * h; zw_r += vw_r * h;
                dg_tyF = tyF; dg_tyR = tyR; dg_sqF = maxf(0.0, gF - zw_f); dg_sqR = maxf(0.0, gR - zw_r);
                double wsn = sin(pitch);
                double wcs = cos(pitch);
                double topF = y + XF * wsn - s0F;
                double topR = y + XR * wsn - s0R;
                if (zw_f < topF) { zw_f = topF; vw_f = maxf(vw_f, vy + XF * wcs * pitch_v); }
                if (zw_r < topR) { zw_r = topR; vw_r = maxf(vw_r, vy + XR * wcs * pitch_v); }
                // ... and at full compression: the wheel never goes further into the frame than its travel
                if (zw_f > topF + trF) { zw_f = topF + trF; vw_f = minf(vw_f, vy + XF * wcs * pitch_v); }
                if (zw_r > topR + trR) { zw_r = topR + trR; vw_r = minf(vw_r, vy + XR * wcs * pitch_v); }
                if (!cF && !cR)   // in the air the bike can go all the way round (flips)
                {
                    flip_acc += pitch_v * h;
                    pitch = wrapf(pitch, -PI, PI);
                }
                // the very end: suspension on its stop AND the tyre flat on the rim (TYRE_MAX). The frame is stopped by the
                // ground; the speed lost here is the hit that got through everything (_rim_hit)
                for (int wi = 0; wi < 2; wi++)
                {
                    double xx = wi == 0 ? XF : XR;
                    double gg = wi == 0 ? gF : gR;
                    double vg = wi == 0 ? vgF : vgR;
                    double c2 = cos(pitch);
                    double dd = gg - (y + xx * sin(pitch) - (wi == 0 ? s0F : s0R) + (wi == 0 ? trF : trR)) - TYRE_MAX;
                    if (dd <= 0) continue;
                    probe_bottom += 1;
                    if (wi == 0) dg_botF = true;
                    else dg_botR = true;
                    double lx = xx * c2;
                    double m_inv = 1 / mB + lx * lx / IK;
                    double dq = dd / m_inv;
                    y += dq / mB; pitch += dq * lx / IK;
                    double vpp = vy + lx * pitch_v;
                    // (into a rock or a kerb on the rim: carried up over it, but thrown up at no more than RIM_CLIMB of the
                    // edge's rise, counted from the slope the bike rides; a landing is not touched)
                    double slope_vy = minf(0.0, v * tan(clampf(_g_pitch, -1.2, 1.2)));
                    vg = minf(vg, slope_vy + RIM_CLIMB);
                    if (vpp < vg)
                    {
                        double j = (vg - vpp) / m_inv;
                        vy += j / mB; pitch_v += j * lx / IK;
                        _rim_hit = maxf(_rim_hit, j / mB);   // (what it did to the bike as a whole)
                    }
                    if (wi == 0) cF = true;
                    else cR = true;
                }
                // (the rim is as far as a tyre squashes: the wheel sits on it)
                zw_f = maxf(zw_f, gF - TYRE_MAX); zw_r = maxf(zw_r, gR - TYRE_MAX);
                // ... but never further into the frame than its travel: that limit has the last word
                double endF = y + XF * sin(pitch) - s0F + trF;
                double endR = y + XR * sin(pitch) - s0R + trR;
                if (zw_f > endF) { zw_f = endF; vw_f = minf(vw_f, vy + XF * cos(pitch) * pitch_v); }
                if (zw_r > endR) { zw_r = endR; vw_r = minf(vw_r, vy + XR * cos(pitch) * pitch_v); }
                dg_sqF = maxf(0.0, gF - zw_f); dg_sqR = maxf(0.0, gR - zw_r);
                if (!was_air)
                {
                    double rel = body_y - y;
                    if (rel < -T["legComp"])
                    {
                        body_y = y - T["legComp"];
                        // legs bottomed out: the speed the body still had into the bike is the hit the rider takes
                        if (body_v < vy && since_land < 0.6 && land_jolt >= 0) land_jolt = maxf(land_jolt, vy - body_v);
                        if (body_v < vy && since_land >= 0.6) g_jolt = maxf(g_jolt, vy - body_v);
                        if (body_v < vy)
                        {
                            double vc = coupled ? PHI * body_v + mB * vy : vy;
                            body_v = vc; vy = vc;
                        }
                    }
                    else if (rel > T["legExt"])
                    {
                        body_y = y + T["legExt"];
                        if (body_v > vy)
                        {
                            double vc = coupled ? PHI * body_v + mB * vy : vy;
                            body_v = vc; vy = vc;
                        }
                    }
                }
            }
            // (the graphs read both ends against one travel: the rear's compression is given on the front's scale)
            dg_xR *= trF / trR;
            dg_travel = trF; dg_sag = s0F; dg_sag_r = s0R * trF / trR; dg_knee = BLOW_V; dg_cF = cF; dg_cR = cR;
            dg_leg = !was_air ? body_y - y : 0.0;
            double kN = minf(1.0, dt * 30);
            n_f = _or(n_f, shF * G) + (sumF / N - _or(n_f, shF * G)) * kN;
            n_r = _or(n_r, shR * G) + (sumR / N - _or(n_r, shR * G)) * kN;
            bool now_air = !cF && !cR;
            front_air = !now_air && !cF; rear_air = !now_air && !cR;
            double gpC = asin(clampf((hfC - hrC) / L, -1, 1));
            // looped out: on the back wheel past what the rider can hold, or still rotating back well past the balance point
            double back_up = (cR && !cF && pitch - gpC > 0.6) ? pitch - _local_slope(f, XR, RWR, cp0) : 0.0;
            // (touching down turned past 83 deg from the slope: the landing verdict names it UNDER- / OVER-ROTATED)
            bool flipped = was_air && !now_air && air_time >= 0.2 && absf(wrapf(pitch - _g_pitch, -PI, PI)) > 1.45;   // (_land_trick's own test)
            if (_balancing() || _man_grace > 0.0 || flipped) { }   // the balance manual handles its own loop-out (no crash)
            else if (back_up > T["landBack"] + 0.1 || (back_up > 1.15 && pitch_v > 0.5 && !was_air))
            {
                // weight held back on purpose rolling over rollers / crests: the rider throws the front back down (speed
                // lost, no crash). Thrown back off a landing, or nobody leaning back, it is still the crash
                if ((body_in_s < -0.3 || _man_pw > 0.05) && !was_air && since_land > 0.3)
                {
                    if (_loop_saved <= 0.0)
                    {
                        v *= T.get("manLoopKeep", 0.72); shake = maxf(shake, 0.25); _man_pw = 0.0;
                        if (host.msg_idle()) host.flash("LOOPED OUT!");
                    }
                    _loop_saved = 0.6;
                    pitch_v = minf(pitch_v, -2.5);
                }
                else _crash("LOOPED OUT!");
            }
            else if (_nosing() || _nose_grace > 0.0) { }   // so does the nose manual
            else if (cF && !cR && gpC - pitch > 0.6 && _local_slope(f, XF, RWF, cp0) - pitch > 1.15) _crash("NOSE DIVE!");
            // (not on the touch-down step: the clamp would run before the landing verdict)
            if (absf(pitch) > 1.45 && (cF || cR) && !was_air)   // on the ground only: in the air flips go all the way round
            {
                pitch = signf(pitch) * 1.45; pitch_v = 0;
            }
            // one wheel just left the ground: the rider holds the bike at the slope it was on with both wheels down
            if (!now_air && (front_air || rear_air) && was_f && was_r) nose_ref = _or(_gpc_last, gpC);
            _gpc_last = (cF && cR) ? gpC : _gpc_last;
            // (on the touch-down step itself the reference is the ground it lands on)
            // (GDScript names this local n_ref, shadowing the member used above: renamed for C#)
            double n_ref_l = air ? _g_pitch : _or(nose_ref, _g_pitch);
            if (front_air && pitch - n_ref_l < -T["noseDive"] && !_balancing() && _man_grace <= 0.0 && !flipped) _crash("NOSE DIVE!");
            // the rider's head and chest ride on the bike: turned well past the ground's slope they reach the terrain before
            // the bike does. A body point under the ground = the crash
            if (!_balancing() && !_nosing() && absf(pitch - _g_pitch) > 1.0)
            {
                double sp = sin(pitch); double cp = cos(pitch);
                double cr = cos(clampf(bike_lean, -1.4, 1.4));   // (roll)
                // (forward, up) from the bottom bracket in the bike's frame: head, chest
                foreach (var pt in _BODY_PTS)
                {
                    double wx = pt.x * cp - pt.y * sp * cr;
                    double wy = y + pt.x * sp + pt.y * cp * cr;
                    double gh = terrain.top_height(x + f.x * wx, z + f.z * wx);
                    if (wy < gh + (pt.y > 0.8 ? 0.12 : 0.10))
                    {
                        _crash(pt.y > 0.8 ? "HEAD HIT!" : "BODY HIT!"); break;
                    }
                }
            }
            double snN = sin(pitch);
            w_f = cF ? hfC : y + XF * snN;
            w_r = cR ? hrC : y + XR * snN;
            pitch_w = pitch;
            if (host.susp != null)
            {
                y_draw = y; pitch_draw = pitch;
            }
            else
            {
                y_draw = w_r + (w_f - w_r) * (BB_REAR / L); pitch_draw = asin(clampf((w_f - w_r) / L, -1, 1));
            }
            if (!was_air && !now_air && !was_f && cF)
            {
                double slap = maxf(0.0, vgF - (vy_in + XF * cos(pitch) * pitch_v));
                if (slap > 2)
                {
                    compress_v -= minf(1.5, slap * 0.25);   // (no camera shake: at speed it rattled all the time)
                    if (slap > 3.5) host.burst(new V3(x + f.x * XF, _g_hf + 0.03, z + f.z * XF), 10, surf, 0.8);
                }
            }
            c_f = cF; c_r = cR;
            if (!now_air)
            {
                // the rider's body turns with the bike, smoothed by the arms and legs
                body_pw += (pitch_v - body_pw) * minf(1.0, dt * 4);
            }
            if (now_air && !was_air)
            {
                air = true; air_time = 0; air_peak = 0.0; flip_acc = 0.0; spin_acc = 0.0; style_air = 0.0; _whip_peak = 0.0; _lean_peak = 0.0; _scrub_k = 0.0;
                // rider + bike fly off at the speed of their shared centre of mass
                if (coupled && !is_nan(body_v)) vy = PHI * body_v + mB * vy;
                // never off steeper than the lip itself (+ LIP_SPARE: the legs, the spring): the climb is held to the lip's
                // angle so it never exceeds the speed along the ground
                if (!_balancing() && _man_grace <= 0.0 && vy > 0.0)
                {
                    double lip_a = maxf(_or(_gpc_last, gpC), _local_slope(f, XR, RWR, cp0));
                    // (hands off he rides WITH the lip: LIP_SPARE_OWN; the player's pop / crouch may leave steeper)
                    double spare = ((pop_wait > 0.0 && pro_pop) || crouch > 0.1) ? LIP_SPARE : LIP_SPARE_OWN;
                    double up_max = minf(lip_a + spare, 1.2);
                    double vy_cap = maxf(absf(v) * sin(up_max), 2.5);   // (a bounce / small hop off a crest: never cut)
                    // (where the climb had to be cut, the frame leaves along its flight, turning no faster than a lip throws)
                    if (vy > vy_cap)
                    {
                        vy = vy_cap;
                        double nose_room = (spare == LIP_SPARE ? LIP_NOSE_POP : LIP_NOSE) * nose_k;   // (the front lifted over the lip)
                        pitch = minf(pitch, up_max + 0.15 + nose_room); pitch_v = minf(pitch_v, 0.6); body_pw = minf(body_pw, 0.6);
                    }
                    else if (pitch > up_max + 0.5)
                    {
                        pitch = up_max + 0.5; pitch_v = minf(pitch_v, 1.0); body_pw = minf(body_pw, 1.0);
                    }
                }
                // the speed along the lip splits into the horizontal part (v from now on) and the climb (vy)
                v *= cos(asin(clampf(vy / maxf(absf(v), 0.5), -0.94, 0.94)));
                // the legs: a pop that was waiting for this edge goes now; or the lip is squashed (absorbed)
                double pop = 0.0;
                if (kick_t <= 0.0) _pop_used = 0.0;
                _air_pop = 0.0; pro_flight = false;
                if (since_land > 0.6) _land_hit = 0.0;   // (a new jump: not a bounce off the last landing)
                if (_graze) _graze = false;   // (the same take-off, after a brush with the lip: the legs have had their say)
                else if (pop_wait > 0.0)
                {
                    pop = maxf(0.0, _leg_dv(pop_wait) - _pop_used); pop_q = pop_wait; pop_wait = 0.0;
                    _air_pop = pro_pop ? clampf(pop_q, 0.0, 1.0) : 0.0;   // (the pro pull-up: only after the player's own pump)
                    pro_flight = pro_pop; pro_pop = false;
                    // the player's own pop pushes off the face (square to it); the rider's own hands-off one rides WITH the lip
                    if (pro_flight) _pop_apply(pop);
                    else _pop_along(pop);
                    _pop_used += pop; pop_fx = 1.0;
                    if (pop_time > 0.9 && pop_q > 0.85 && host.msg_idle()) host.flash("PERFECT POP");
                }
                else if (vy > 0.3 && ((squash > 0.05 && kick_t <= 0.0) || auto_absorb * prep > 0.05))
                {
                    // the legs let the bike come up into the body: the centre of mass flies a flatter line, speed kept
                    double sq_k = maxf(squash, auto_absorb * prep);
                    double sq_d = minf(T["popPower"] * 0.7 * squash, 0.45 * vy);
                    if (auto_absorb * prep > squash)
                    {
                        // (hands off: applied once BOTH wheels are off - here the rear is still on the face)
                        _absorb_k = sq_k; sq_d = 0.0;
                    }
                    double sp2 = v * v + vy * vy;
                    vy -= sq_d;
                    v = signf(v) * sqrt(maxf(0.0, sp2 - vy * vy));
                    squash_fx = clampf(sq_k, 0.0, 1.0);
                    _scrub_k = sq_k;
                    if (squash > 0.6 && sq_d > 0.8 && host.msg_idle()) host.flash("SQUASH");
                }
                // the legs push off along the ground's surface: off a lip tilted sideways part of the pop throws rider + bike
                // towards its low side. The bike keeps pointing where it did
                if (pop > 0.0 && absf(bank) > 0.03 && absf(v) > 1.0)
                {
                    double dc_t = atan(pop * sin(bank) / absf(v)) * signf(v);
                    course += dc_t; slip -= dc_t;
                }
                // the spin rider + bike leave with: mostly the rider's, plus the throw
                double sh = T["riderShare"];
                // leaving the ground from ONE wheel is a bounce: it flies on with the gentler of the bike's spin and the body's
                if (was_f != was_r && !_balancing() && absf(pitch_v) < absf(body_pw)) body_pw = pitch_v;
                if (_man_grace > 0.0 || _balancing())
                {
                    pitch_v = clampf(pitch_v, -0.8, 0.8); body_pw = clampf(body_pw, -0.8, 0.8);
                }
                air_w = (1 - sh) * pitch_v + sh * body_pw + throw_v;
                // (a pro off his own pump soaks the lip's nose-down kick with his arms and legs)
                if (pro_flight && absf(throw_v) < 0.05) air_w = maxf(air_w, -0.15);
                air_tilt = 0.0; air_tilt_v = sh * (pitch_v - body_pw);
                air_inertia = 1.0;
                pitch_v = air_w + air_tilt_v;
                _flip_in = clampf(throw_v / maxf(T["flipRate"], 0.1), -1.0, 1.0);
                throw_v = 0.0;
                air_yaw = yaw_rate; air_tw = 0.0; air_tw_v = 0.0; _air_steer_s = 0.0; _air_aim_s = 0.0;
                // a whip wound up at the lip leaves swinging out (a ground whip held off any lip or bump carries into the air)
                if (whip > 0.3 && absf(whip_load) < whip * 0.8) whip_load = whip_side * whip * 0.8;
                _whip_in = whip_load;
                air_tw_v = WHIP_KICK * _whip_in;
                whip_load = 0.0;
                // a spin wound up at the lip leaves already turning; a flip thrown at the lip sets how far it can be carried
                _spin_in = spin_load; spin_load = 0.0;
                if (absf(_spin_in) > 0.05)
                {
                    stick_yaw = T.get("stickYawRate", 5.0) * _spin_in;
                    yaw_edge_s = _spin_in;
                }
                host.on_takeoff();
            }
            else if (!now_air && was_air)
            {
                // the ground it comes down on, tilt and all
                double b_land = _bank_at(f);
                bank = b_land; _bank_raw = b_land;
                // how fast the bike comes down into the slope (the speed along it is kept). Tilted sideways only cos(tilt)
                // of it is the hit...
                double impact = maxf(0.0, v * sin(_g_pitch) - vy_in * cos(_g_pitch)) * cos(b_land);
                // ...and the rest slides rider + bike towards the low side
                if (vy_in < 0.0 && absf(b_land) > 0.03 && absf(v) > 0.5)
                {
                    double s_lat = -vy_in * cos(_g_pitch) * sin(b_land) * T.get("landSlide", 1.0);
                    double dc_l = atan(s_lat / absf(v)) * signf(v);
                    course += dc_l; slip -= dc_l;
                    v = signf(v) * sqrt(v * v + s_lat * s_lat);
                }
                double at = air_time;
                bool back_land = cR && !cF && wrapf(pitch - _g_pitch, -PI, PI) > 0.4;
                _land_pe = absf(wrapf(pitch - _g_pitch, -PI, PI));   // (how square to the ground it came down)
                _land_up = wrapf(pitch - _g_pitch, -PI, PI) > 0.0;   // (back wheel first)
                _rev_land = false; _land_fix = false;
                _land_trick(at);
                if (_land_fix)
                {
                    // the tyres grab the nearer axis: the travel is dragged round to within slipMax of the heading, speed lost
                    // by the angle dragged through. Past 90 deg that axis is backwards (fakie)
                    double @base = _rev_land ? wrapf(slip - PI, -PI, PI) : wrapf(slip, -PI, PI);
                    double keep = minf(absf(@base), 0.9 * T["slipMax"]);
                    double sl = signf(@base) * keep;
                    double drag_a = absf(@base) - keep;
                    v = (_rev_land ? -v : v) * cos(minf(drag_a, 1.4));
                    course = heading - sl; slip = sl; slip_w = 0.0; turn_off = 0.0;
                    if (_rev_land) rev_cap = maxf(3.0, -v);
                    _rev_land = false; _land_fix = false;
                }
                air = false; since_land = 0; land_jolt = 0.0; _rim_hit = 0.0; land_heavy = 0.0;
                body_v = vy_in;
                body_pw = air_w;
                nose_ref = _g_pitch;
                // the velocity into the slope is stopped; along the slope it carries on (a tyre brushing the lip's edge on the
                // way up, a moment after take-off, is not a landing: all of the speed carries on)
                _graze = vy_in > 0.3 && at < 0.2;
                if (_graze) v = signf(v) * sqrt(v * v + vy_in * vy_in);
                else v = v * cos(_g_pitch) + vy_in * sin(_g_pitch);
                // landed turned to the way it is going: the speed across the tyres has to be stopped by their grip; what
                // they can take at once is caught (land_yaw), the rest is a slide. Past landYawCrash at once = a highside
                land_yaw = 0.0;
                // landing carve: steered round in the air, a heading near the travel is turned INTO first
                double carve_k = T.get("landCarve", 0.8);
                double a_c = wrapf(slip, -PI, PI);
                if (carve_k > 0.0 && !_graze && at > 0.1 && absf(v) > 3.0 && crash_pending == ""
                    && absf(_air_steer_s + _air_aim_s) > 0.05 && signf(a_c) == signf(_air_steer_s + _air_aim_s) && absf(a_c) < CARVE_MAX)
                {
                    double turn_c = a_c * carve_k;
                    course += turn_c; slip -= turn_c; slip_w = 0.0;
                    v *= 1.0 - CARVE_COST * minf(1.0, absf(sin(turn_c)));
                    carve_now = turn_c;
                    // a reward for it (carveStyle, 0 = none): a few points + a notch of flow
                    double cs = T.get("carveStyle", 1.0);
                    if (cs > 0.0 && absf(turn_c) >= CARVE_REWARD_MIN)
                    {
                        host.on_style(roundi(120.0 * cs * clampf(absf(turn_c) / 0.4, 0.5, 1.5)), "CARVE");
                        flow_up();
                    }
                }
                _air_steer_s = 0.0; _air_aim_s = 0.0;
                double a_y = wrapf(slip, -PI, PI);
                double yaw_free = T.get("landYawFree", 0.12);
                if (!_graze && at > 0.2 && absf(v) > 2.0 && absf(a_y) > yaw_free && absf(a_y) < 1.35 && crash_pending == "")
                {
                    double v_abs = absf(v);
                    double v_lat = v_abs * sin(absf(a_y) - yaw_free);
                    double v_lon = v_abs * cos(absf(a_y) - yaw_free);
                    double catch_v = _or(_mu_r, 0.8) * (impact * 0.8 + 2.5) * T.get("landYawGrip", 1.0);
                    double rem = maxf(0.0, v_lat - catch_v);
                    land_yaw = v_lat - rem;
                    double a_new = signf(a_y) * (atan2(rem, maxf(v_lon, 0.1)) + yaw_free * minf(1.0, rem / 0.5));
                    v = signf(v) * sqrt(v_lon * v_lon + rem * rem);
                    course = heading - a_new; slip = a_new; slip_w = 0.0;
                    shake = maxf(shake, minf(0.25, land_yaw * 0.035));
                    if (land_yaw > T.get("landYawCrash", 5.5)) _crash("HIGHSIDE!");
                    else if (land_yaw > 1.8)
                    {
                        land_fold = maxf(land_fold, minf(0.8, land_yaw / 5.0)); _stun = maxf(_stun, 0.15 + 0.07 * land_yaw);
                        if (host.msg_idle()) host.flash(land_yaw > 3.5 ? "SIDEWAYS!" : "SKETCHY!");
                    }
                }
                // the rider folds into the landing by how hard it is, then gathers himself
                if (!_graze && at > 0.2) land_fold = maxf(land_fold, clampf((impact - 1.5) / 5.5, 0.0, 1.0));
                // perfect landing: a real jump landed in line with the slope and pointing down the trail. On a downslope the
                // rider pumps part of the fall back as speed (landBoost at most, none on flat ground)
                double land_err = absf(wrapf(pitch - _g_pitch, -PI, PI));
                if (at > T.get("landPerfectAir", 0.45) && crash_pending == "" && land_err < T.get("landPerfect", 0.14) && absf(slip) < 0.25 && v > 1.0)
                {
                    double boost = T.get("landBoost", 1.6) * clampf(-sin(_g_pitch) / 0.3, 0.0, 1.0) * clampf(impact / 2.5, 0.0, 1.0);
                    v += boost; land_perfect = 1.0;
                    if (host.msg_idle()) host.flash(boost > 0.4 ? $"PERFECT LANDING +{roundi(boost * 3.6)} km/h" : "PERFECT LANDING");
                }
                // (MX vs ATV style: the landing's angle decides your speed) well off the slope the bike bogs: none within
                // LAND_ANGLE_FREE, rising to landAngleCost of it at 35 deg; a soft one pays less, taken off over BOG_T
                if (at > T.get("landPerfectAir", 0.45) && crash_pending == "" && absf(v) > 2.0)
                {
                    double bad = smooth01((land_err - LAND_ANGLE_FREE) / (deg_to_rad(35.0) - LAND_ANGLE_FREE));
                    if (bad > 0.0)
                    {
                        double cut = absf(v) * T.get("landAngleCost", 0.25) * bad;
                        cut *= lerpf(BOG_SOFT, 1.0, smooth01(impact / 4.0));
                        _bog = cut; _bog_rate = cut / BOG_T;
                        if (cut > 1.0 && host.msg_idle()) host.flash($"BAD LANDING -{roundi(cut * 3.6)} km/h");
                    }
                }
                compress_v -= minf(2.2, impact * 0.35) + (back_land ? minf(1.2, impact * 0.2 + 0.4) : 0.0);
                // drawing: host side (Godot host.susp.land(...) returns at once while wheels_follow: the drawn ends follow the ground)
                // only a real landing shakes the camera (rollers at speed give lots of tiny hops)
                if (at > 0.4 && impact > 3.0) shake = maxf(shake, minf(0.2, (impact - 3.0) * 0.04));
                if (at > 0.15) host.burst(new V3(x, y + 0.03, z), roundi(10 + minf(30, impact * 6)), surf, 0.8 + minf(1.5, impact * 0.25));
                if (at > 0.45 && impact < 5) flow_up();
                host.on_landing(at, impact);
            }
            // ride roughness: the body's vertical acceleration vs the ground's under it (riding, not landing)
            double gy_now = hrC + (hfC - hrC) * (BB_REAR / L);
            if (!air && !was_air && since_land > 0.6 && !is_nan(probe_vy) && !is_nan(probe_gy[1]))
            {
                double ay = (vy - probe_vy) / dt;
                double ag = (gy_now - 2.0 * probe_gy[0] + probe_gy[1]) / (dt * dt);
                probe_acc2 += ay * ay; probe_g2 += ag * ag; probe_n += 1;
            }
            probe_vy = vy; probe_gy[1] = probe_gy[0]; probe_gy[0] = gy_now;   // (in place: no array per step)
            // a compression on the ground (a steep chute slamming into flat) is judged like a landing
            ground_jolt = maxf(ground_jolt, g_jolt);
            if (!air && g_jolt > 0.0 && since_land >= 0.6)
            {
                if (g_jolt > T["slamJolt"] * LAND) _crash("SLAM!");
                else if (g_jolt > T["slamJolt"] * LAND * 0.6 && host.msg_idle()) host.flash("OOF!");
            }
            if (air)
            {
                air_time += dt; air_peak = maxf(air_peak, y - _g_y);
            }
            else if (land_jolt >= 0 && since_land < 0.6)
            {
                // the landing's verdict, from what got through: the body's speed into the bike when the legs ran out
                // (land_jolt) and the speed the frame lost with suspension and tyres on their stops (_rim_hit, 1.3x).
                // Past slamJolt it throws him down; from landHeavy of that it is a heavy landing
                double hit = sqrt(maxf(land_jolt, 0.0) * maxf(land_jolt, 0.0) + _rim_hit * _rim_hit * 1.69);
                // (the landing's biggest: a little bounce after it re-lands and clears land_jolt / _rim_hit)
                _land_hit = maxf(_land_hit, hit); hit = _land_hit;
                // a landing square to the ground is forgiven a much bigger hit: it costs speed and a wobble, not the crash
                double clean = 1.0 - smoothstep(0.18, 0.6, _land_pe);
                // back wheel first (nose up) is a way to land: forgiven nearly as much up to ~30 deg, none past ~55 deg
                if (_land_up) clean = 1.0 - 0.15 * smoothstep(0.18, 0.5, _land_pe) - 0.85 * smoothstep(0.5, 0.95, _land_pe);
                double slam0 = T["slamJolt"] * LAND;
                double slam = slam0 * (1.0 + T.get("landForgive", 1.0) * clean);
                if (hit > slam)
                {
                    host.on_bad_landing(1.0);
                    _crash("SLAM!"); land_jolt = -1.0;
                }
                else if (since_land > 0.4)
                {
                    double hv = T.get("landHeavy", 0.6);
                    // (heavy from the plain limit up: a clean landing's bigger allowance is all heavy landing)
                    if (hit > slam0 * hv)
                    {
                        land_heavy = clampf((hit - slam0 * hv) / maxf(0.05, slam - slam0 * hv), 0.0, 1.0);
                        v *= 1.0 - 0.12 * land_heavy;
                        land_fold = maxf(land_fold, 0.3 + 0.3 * land_heavy);   // (he stays down: a slower way back up)
                        _stun = 0.15 + 0.45 * land_heavy;
                        if (land_heavy > 0.12) host.on_bad_landing(land_heavy);
                        shake = maxf(shake, 0.1 + 0.15 * land_heavy);
                        if (host.msg_idle()) host.flash(land_heavy > 0.5 ? "HEAVY LANDING" : "OOF!");
                    }
                    land_jolt = -1.0;   // one verdict per landing
                    _land_hit = 0.0;    // (judged: a hop 0.4-0.6 s later carried this hit into the NEXT landing's verdict)
                }
            }
            kick_t = maxf(0.0, kick_t - dt);
        }

        /// the suspension setup's numbers out of its units, once (the vertical step reads them 120 times a second)
        void _sus_cache()
        {
            _su = new double[18];
            int i = 0;
            foreach (var u in new[] { sus.f, sus.r })
            {
                _su[i++] = u.travel; _su[i++] = u.sag; _su[i++] = u.prog; _su[i++] = u.zc;
                _su[i++] = u.zr; _su[i++] = u.hs; _su[i++] = u.fric; _su[i++] = u.bump;
            }
            _su[16] = clampf(sus.psi_f, 5.0, 80.0); _su[17] = clampf(sus.psi_r, 5.0, 80.0);
        }

        /// the speed one push of the legs adds to rider + bike (m/s), along the ground's normal: the one budget for the hop
        /// and the pop off a lip. Pressed into the ground by a compression the legs have less left to push with
        double _leg_dv(double power)
        {
            return T["popPower"] * clampf(power, 0.0, 1.15) * (1.0 - 0.45 * clampf(_n_grd - 1.0, 0.0, 1.4));
        }

        /// the push leaves along the ground's normal = square to the way the bike is going: it adds dv^2 / 2, nothing else
        void _pop_apply(double dv)
        {
            double th = clampf(atan2(vy, maxf(absf(v), 0.5)), -0.6, 1.2);
            vy += dv * cos(th); v -= signf(v) * minf(absf(v), dv * sin(th));
        }

        /// the legs' push given along the way rider + bike are going (the same energy as dv square to it)
        void _pop_along(double dv)
        {
            double sp = sqrt(v * v + vy * vy);
            if (sp < 0.5)
            {
                _pop_apply(dv); return;
            }
            double k = sqrt(sp * sp + dv * dv) / sp;
            v *= k; vy *= k;
        }
    }
}
