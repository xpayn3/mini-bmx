// Port of godot/scripts/bike/bike_physics.gd, group C (steering): _step_steer, _slow_body_k, _pivot_step, _bank_at.
// Line for line; only the current behaviour (every BMX_OLD_* switch false, probes / prints dropped, BMX_WEAVE unset).
using System;
using System.Collections.Generic;
using System.Globalization;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    public sealed partial class BikePhysics
    {
        /// stage 6: steering, lean, balance, turn, grip sim, soft crash meters; returns va
        double _step_steer(double dt, V3 f, double brake_k, double steer_input, double roll_keys, double a_long, double nR, double nF)
        {
            var terrain = host.terrain;
            double n_tot = n_load;
            double mu_f = _mu_f * T["grip"];
            double mu_r = _mu_r * T["grip"];
            double mu = mu_r * SH_R + mu_f * (1.0 - SH_R);
            // --- steering, countersteer and lean ---
            double va = absf(v);
            double spd_k = smooth01(va / 14.0);
            // body stick side lean: the bike follows the stick on a critically damped spring (flickSpeed = its natural rate)
            // with a top speed, so a thumb throw left -> right swings the bike over smoothly instead of snapping it
            double fw = T.get("flickSpeed", 14.0);
            flick_v += ((flick_in - flick) * fw * fw - 2.0 * fw * flick_v) * dt;
            flick_v = clampf(flick_v, -FLICK_VMAX, FLICK_VMAX);
            flick = clampf(flick + flick_v * dt, -1.0, 1.0);
            // a deliberate flick (stick thrown from near the centre to the edge within FLICK_WINDOW) whips the bike
            // round once; thumb wobble / holding a lean never does
            if (absf(flick_in) < 0.35)
            {
                _flick_arm = 0.0; _flick_side = 0.0;
            }
            else if (_flick_side == 0.0)
                _flick_side = signf(flick_in);
            double flick_thrown = 0.0;   // +-1 the step a deliberate flick lands (it may start a corner whip)
            if (_flick_side != 0.0 && _flick_arm >= 0.0)
            {
                _flick_arm += dt;
                if (absf(flick_in) > 0.85 && signf(flick_in) == _flick_side)
                {
                    if (_flick_arm < FLICK_WINDOW && !air && va > 2.0)
                    {
                        flick_kick += _flick_side * T.get("flickKick", 0.0) * smooth01((va - 2.0) / 5.0);
                        flick_thrown = _flick_side;
                    }
                    _flick_arm = -1.0;   // spent until the stick comes back towards the centre
                }
            }
            // the side lean steers too, but held AGAINST the steer it's the body hanging off the inside: that costs grip
            // (weight_in below), it hardly undoes the turn
            double fs_k = (absf(steer_input) < 0.2 || signf(flick) == signf(steer_input)) ? 1.0 : 0.25;
            // (MX vs ATV style: by default the side lean no longer steers on its own (flickSteer 0) nor throws the bike over
            // (flickLean 0) nor kicks it round (flickKick 0). It changes the turn the left stick asks for: with it = tighter +
            // grippier (agree), against it = wider + looser (oppose))
            double steer_eff = clampf(steer_input + flick * T.get("flickSteer", 0.0) * fs_k, -1.0, 1.0);
            // leaning with the steer: how much the two agree, smooth through zero
            double agree = clampf(flick * steer_eff * 2.0, 0.0, 1.0) * absf(flick);
            double oppose = clampf(-flick * steer_eff * 2.0, 0.0, 1.0) * absf(flick);
            // corner whip: both sticks thrown the same way (steer + body lean) in a tight corner. The rear steps out into a
            // drift held as long as both stay there (Ride > Body: whip*); let go and the tyres catch it
            double wtr = T.get("whipTrigger", 0.6);
            bool whip_want = !air && va > T.get("whipMinSpeed", 4.0) && absf(steer_input) > wtr && absf(flick_in) > wtr && signf(steer_input) == signf(flick_in) && T.get("whipDrift", 0.42) > 0.0;
            // it only STARTS from a deliberate throw of the right stick with the steer held the same way; once going it is held
            // while both stay past whipTrigger. The throw alone (steer centred) starts the straight whip: the rear swings out
            // to the stick's side and the bike rides on down its line sideways; held through a short skip
            bool straight_ok = absf(steer_input) < wtr;
            double whip_dir = straight_ok ? signf(flick_in) : signf(steer_input);
            bool skip_ok = !air || (air_time < 0.3 && whip > 0.05);
            if (straight_ok)
                whip_want = skip_ok && T.get("whipStraight", 1.0) > 0.0 && va > T.get("whipMinSpeed", 4.0) && absf(flick_in) > wtr && (absf(steer_input) < 0.05 || signf(steer_input) == signf(flick_in)) && T.get("whipDrift", 0.42) > 0.0;
            else if (skip_ok && whip > 0.05)
                whip_want = whip_want || (air && absf(flick_in) > wtr && signf(flick_in) == whip_side);
            if (flick_thrown != 0.0 && ((absf(steer_input) > wtr && signf(steer_input) == flick_thrown) || straight_ok)) _whip_arm = 0.25;
            else _whip_arm = maxf(0.0, _whip_arm - dt);
            if (whip < 0.05 && _whip_arm <= 0.0) whip_want = false;
            if (whip_want && whip < 0.05)
            {
                whip_side = whip_dir; _whip_straight = straight_ok;
            }
            if (whip_want && whip_dir != whip_side) whip_want = false;
            double w_in = _whip_straight ? T.get("whipFlowIn", 2.5) : 4.0;
            double w_out = _whip_straight ? T.get("whipFlowOut", 1.8) : 3.0;
            whip = whip_want ? minf(1.0, whip + dt * w_in) : maxf(0.0, whip - dt * w_out);
            if (whip_want)
            {
                _whip_t += dt;
                _whip_ang = maxf(_whip_ang, absf(slip));
                if (_whip_t > 0.3 && !_whip_flashed)
                {
                    _whip_flashed = true;
                    if (host.msg_idle() && !_whip_straight) host.flash("WHIP!");
                }
            }
            else if (whip <= 0.0)
            {
                // a ground whip held a while, then brought back straight: style (the straight one is all show). More the longer
                // and further out it was held
                if (_whip_straight && _whip_t > 0.45 && _whip_ang > 0.15 && !crash_on)
                {
                    double deg = rad_to_deg(_whip_ang);
                    host.on_style(roundi(T.get("whipStyle", 1.0) * 160.0 * clampf(_whip_t, 0.45, 2.5) * clampf(_whip_ang / 0.35, 0.5, 1.5)),
                        (deg > 28.0 ? "BIG WHIP" : "WHIP") + " " + deg.ToString("0", CultureInfo.InvariantCulture) + "°");
                }
                _whip_t = 0.0; _whip_flashed = false; _whip_ang = 0.0; _whip_straight = false;
            }
            // the bars follow the input on a critically damped spring (steerEase = its natural rate), capped at the
            // build-up / release rate: a key press starts turning gently and builds (an S-curve, no instant full lock)
            double rate = absf(steer_eff) > 0.01 ? T["steerRate"] : T["steerRelease"];
            double se_w = T.get("steerEase", 30.0);
            steer_in_v += ((steer_eff - steer_in) * se_w * se_w - 2.0 * se_w * steer_in_v) * dt;
            steer_in_v = clampf(steer_in_v, -rate, rate);
            steer_in = clampf(steer_in + steer_in_v * dt, -1.0, 1.0);
            double s_in = steer_in * (1 - T["steerCurve"] + T["steerCurve"] * absf(steer_in));
            {
                double b = air ? 0.0 : _bank_at(f);
                _bank_raw = b;
                // the bank the bike feels follows the ground on a critically damped spring (~0.15 s), its speed capped at
                // 3 rad/s: rough ground and a bank-to-bank changeover read as a step every physics tick
                double b0 = _or(bank, b);
                double bw_n = 2.15 / maxf(0.01, T.get("bankSmooth", 0.15));
                bank_v += ((clampf(b, -0.9, 0.9) - b0) * bw_n * bw_n - 2.0 * bw_n * bank_v) * dt;
                bank_v = clampf(bank_v, -3.0, 3.0);
                bank = b0 + bank_v * dt;
            }
            if (!air) _bank_hold = bank;
            double bk = bank;
            bool carving = !air && absf(steer_eff) > 0.01 && va > 4 && !skid && absf(slip) < 0.3;
            carve = carving ? minf(1.0, carve + dt * 2) : maxf(0.0, carve - dt * 5);
            double carve_f = carve * smooth01((va - 4) / 4);
            // the rider's weight in the turn: the body stick into the turn = more grip, steadier over bumps; against it =
            // hanging off the inside, the tyres lose bite. "into the turn" = the way the tyres push (last step)
            double turn_dir = absf(_f_prev) > 0.08 ? signf(_f_prev) : signf(steer_eff);
            weight_in = air ? 0.0 : clampf(flick * turn_dir, -1.0, 1.0);
            double w_grip = 1.0 + T.get("flickGrip", 0.2) * agree - T.get("weightInside", 0.2) * maxf(0.0, -weight_in);
            // a berm helps the turn at any speed (in practice turnFloor below always wins and the grip decides how tight it turns)
            double a_lat_lim = maxf(1.2, 9.0 + spd_k * 4.0 + G * tan(bk) * signf(s_in) * smooth01(va / 3.0) + carve_f * 2.0 + agree * 4.0 * spd_k - oppose * T.get("flickWide", 3.0) * spd_k);
            double @lock = T["steerMax"] + maxf(0.0, T["slowSteer"] - T["steerMax"]) * (1 - smooth01(va / maxf(0.5, T["slowSteerFade"])));
            double d_max = minf(@lock, maxf(atan(a_lat_lim * L / maxf(va * va, 0.01)), atan(T["turnFloor"] * L / maxf(va, 0.1))));
            double cmd = s_in * d_max;
            // berms: steering into a banked turn the rider leans WITH the bank and lets it carry the turn round at the speed it
            // was built for (G tan(bank)); a light touch of the steer is enough for the berm to take over (bermAssist)
            double b_in = signf(bk) * steer_eff;
            double bw_t = air ? 0.0 : T.get("bermAssist", 0.8) * smooth01((b_in - 0.03) / 0.25) * smooth01((absf(bk) - 0.04) / 0.08) * smooth01((va - 2.5) / 3.0);
            // eased in / out (~0.25 s)
            berm_k = air ? 0.0 : move_toward(berm_k, bw_t, dt * 4.0);
            double bw = berm_k;
            if (bw > 0.0)
            {
                // (no tighter than the bars may turn at this speed)
                double cmd_bank = minf(d_max, atan(G * tan(absf(bk)) * L / maxf(va * va, 0.5)));
                double held = signf(cmd) == signf(bk) ? absf(cmd) : 0.0;
                cmd = lerpf(cmd, signf(bk) * maxf(held, cmd_bank), bw);
            }
            double lean_need = clampf(atan(v * (v * tan(cmd) / L) / G), -T["leanMax"] + minf(0.0, bk), T["leanMax"] + maxf(0.0, bk));
            // (on the back wheel he only leans a little: manLean)
            if (_balancing() && !air)
            {
                double ml = T.get("manLean", 0.42);
                lean_need = clampf(lean_need, -ml, ml);
            }
            // balance (balanceSim): rolling, the bike is balanced, not driven. The rider tips it over and the turn follows the
            // lean (the bars end up where the lean needs them, after a countersteer). The rider leans only as far as the grip holds
            bal_k = air ? 0.0 : T.get("balanceSim", 0.4) * smooth01((va - 2.5) / 4.0);
            if (bal_k > 0.0)
            {
                double l_hold = atan(maxf(0.0, lean_need >= 0.0 ? _amax : -_amin) / G) * 0.97;
                lean_need = lerpf(lean_need, signf(lean_need) * minf(absf(lean_need), l_hold), bal_k);
            }
            // reflex: in trouble the rider stands the bike up a little
            lean_need *= 1.0 - T.get("reflexStandUp", 0.3) * T.get("riderSkill", 1.0) * smooth01((risk - 0.15) / 0.5);
            bool tipping_in = absf(steer_eff) > 0.01 && absf(lean_need) > absf(lean) && signf(lean_need) == signf(steer_eff);
            double c_max = absf(cmd) * T["counter"];
            // countersteer
            double ctr = tipping_in ? clampf((lean_need - lean) * T["counter"], -c_max, c_max) * minf(1.0, va / 4) * lerpf(1 - spd_k, 1.0, bal_k) : 0.0;
            double steer_lean = clampf(atan(G * tan(lean) * L / maxf(va * va, 0.5)), -@lock, @lock);
            double steer_target = lerpf(cmd, steer_lean, bal_k) - ctr;
            steer += (steer_target - steer) * (1 - exp(-dt * T["barSpeed"]));
            // a tyre's grip follows its load only after it has rolled a little (relaxation length)
            double load_raw = clampf(pow(maxf(0.0, n_tot / G), 0.7), 0.25, 1.5);
            _load_s = (air || is_nan(_load_s)) ? load_raw : _load_s + (load_raw - _load_s) * minf(1.0, dt / _relax_t(T.get("tyreRelax", 0.04), va));
            double load_k = _load_s;
            double mu_g = mu * G * load_k;
            double a_grip = mu_g * sqrt(maxf(0.05, 1 - pow(a_long / mu_g, 2))) * (skid ? 0.75 : 1.0) * (1 + T["carveGrip"] * carve_f) * w_grip;
            if (!air)
            {
                // front up: no steering, except in a balance manual / wheelie (manTurn of the normal turn).
                // a diving fork shortens the wheelbase the bars' yaw reads (turn-in under the front brake)
                double dive_k = 0.0;
                if (_sprung_fork())
                    dive_k = clampf((dg_xF - dg_sag) / maxf(dg_travel, 0.05), -0.3, 1.0);
                dive += (dive_k - dive) * minf(1.0, dt * 20.0);
                double yaw_cmd = v * tan(steer) / (L * (1.0 - DIVE_L * dive * T.get("diveSteer", 1.0)));
                if (front_air) yaw_cmd *= _balancing() ? T.get("manTurn", 0.65) : 0.0;
                // on the back wheel the turn is the lean, and a rider only leans a wheelie a little (manLean)
                if (front_air && _balancing())
                {
                    double y_lim = G * tan(T.get("manLean", 0.42)) / maxf(absf(v), 2.5);
                    yaw_cmd = clampf(yaw_cmd, -y_lim, y_lim);
                }
                double gE = G * load_k;
                double mE = a_grip / gE;
                double cb = cos(bk);
                double sb = sin(bk);
                double a_max = minf(2.5 * G, gE * (sb + mE * cb) / maxf(0.2, cb - mE * sb));
                double a_min = maxf(-2.5 * G, gE * (sb - mE * cb) / maxf(0.2, cb + mE * sb));
                // (what the rider leans to: the grip a moment ago, not this tick's)
                double ak = minf(1.0, dt * 8.0);
                _amax = _amax > 90.0 ? a_max : _amax + (a_max - _amax) * ak;
                _amin = _amin < -90.0 ? a_min : _amin + (a_min - _amin) * ak;
                double yaw_use = yaw_cmd;
                if (carve_f > 0 && !skid && absf(v) > 0.3)
                {
                    double want = v * yaw_cmd;
                    double cap = (want >= 0 ? a_max : a_min) * 0.97;
                    if (absf(want) > absf(cap)) yaw_use = yaw_cmd + (cap / v - yaw_cmd) * carve_f;
                }
                double a_lat_t = clampf(v * yaw_use, a_min, a_max);
                // the front tyre: its share of the turn on whatever load is on it now. Light or busy braking it runs out
                // first and pushes wide (front_push); pushed hard and long, or locked while leaned over, it washes out
                double fg = T.get("frontGrip", 1.0);
                double f_need = _fric(a_lat_t, cb, sb);
                // (its share of the load eased like the grip above)
                double share_raw = clampf(nF / maxf(0.1, n_tot), 0.05, 1.0);
                _share_f = is_nan(_share_f) ? share_raw : _share_f + (share_raw - _share_f) * minf(1.0, dt / _relax_t(T.get("tyreRelax", 0.04), va));
                double share_f = maxf(0.05, _share_f);
                double circ_f = sqrt(maxf(0.05, 1.0 - pow(_fb_f / maxf(0.1, mu_f * nF * fg), 2)));
                _circ_f = circ_f;
                double mu_fr = mu_f * fg * circ_f * w_grip * (1 + T["carveGrip"] * carve_f) * lerpf(1.0, 0.7, front_lock) * _ls(nF, G * (1.0 - SH_R));
                front_use = front_air ? 0.0 : absf(f_need) * (1.0 - SH_R) / share_f / maxf(0.05, mu_fr);
                if (front_use > 1.0)
                {
                    double f_cap = f_need / front_use;
                    double a_cap = G * (f_cap * cb + sb) / maxf(0.2, cb - f_cap * sb);
                    // the push comes in over the first 15 % past the limit
                    double pk = smooth01((front_use - 1.0) / 0.15);
                    double a_pushed = f_need > 0.0 ? minf(a_lat_t, a_cap) : maxf(a_lat_t, a_cap);
                    a_lat_t = lerpf(a_lat_t, a_pushed, pk);
                    // pushing wide, the front slides with the travel: the bike turns no tighter than it goes
                    if (absf(v) > 0.3) yaw_use = lerpf(yaw_use, a_lat_t / v, pk);
                }
                front_push = maxf(0.0, front_use - 1.0);
                // past frontWashAt the front is losing it: only a LOADED front, LEANED over, washes you out
                double wash_at = T.get("frontWashAt", 1.7);
                double w_load = clampf(share_f / (1.0 - SH_R), 0.0, 1.2);
                double w_lean = smooth01((absf(lean) - 0.1) / 0.3);
                // (never at once: capped under crashHard; not in a manual)
                _danger("FRONT WASHED OUT!", (va > 3.0 && !_balancing()) ? minf(2.2, (front_use - wash_at) / 0.6 * (1.0 + 2.0 * front_lock) * w_load * w_lean) : -1.0, dt, T.get("frontWashTime", 0.7));
                double tau_y = T["turnWeight"] * (0.4 + 0.6 * spd_k);
                lat_m = tau_y > 0.005 ? _or(lat_m, a_lat_t) + (a_lat_t - _or(lat_m, a_lat_t)) * (1 - exp(-dt / tau_y)) : a_lat_t;
                double a_lat = clampf(lat_m, a_min, a_max);
                double course_rate = absf(v) > 0.3 ? a_lat / v : yaw_use;
                double excess = yaw_use - course_rate;
                double share = skid ? 1.0 : T["oversteer"];
                // how much of the tyres' grip the turn uses, measured against the ground's own tilt
                _f_prev = _fric(a_lat, cb, sb);
                double u_lat = clampf(_f_prev / maxf(0.05, mE), -1.5, 1.5);
                double margin = 1 - minf(1.0, absf(u_lat));
                double gr = _grip_step(dt, va, mu_r, nR, u_lat);
                // the plain catch (tyre pulling back in line) only works with grip to pull with
                double catch_k = (T["slipRecover"] * (0.25 + margin) + maxf(0.0, -signf(slip) * steer) * 8) * gr * gr;
                // corner whip: the catch lets go and the rear swings out to the drift angle and is held there; for ~1 s after
                // letting go it brings the rear back in line
                double wk = whip * whip * (3.0 - 2.0 * whip);
                whip_hold = maxf(wk, whip_hold - dt / maxf(0.1, T.get("whipCatch", 0.9)));
                catch_k *= 1.0 - 0.85 * whip_hold;
                catch_k *= 1.0 + T.get("reflexCatch", 1.5) * T.get("riderSkill", 1.0) * risk;   // reflex: fights a slide harder the worse it gets
                // a slide nobody asked for (no locked rear, no whip, no wheelspin sprint) is held near the tyres' own slip
                // angle (slideHold); asked-for slides are left alone
                {
                    double asked = maxf(maxf(rear_lock, whip_hold), spin * sprint);
                    double out_k = smooth01((absf(slip - _squirm) - 0.07) / 0.12);
                    catch_k += T.get("slideHold", 6.0) * out_k * (1.0 - asked) * smooth01((va - 2.0) / 3.0);
                }
                double slip_rate = (excess * share + slip_w) * (1.0 - 0.75 * whip_hold) - (slip - _squirm) * catch_k;
                if (whip_hold > 0.0)
                {
                    double drift_t = whip_side * minf(T.get("whipDrift", 0.42), T["slipMax"] * 0.6) * smooth01((va - 3.0) / 4.0) * wk;
                    if (_whip_straight) drift_t *= T.get("whipStraight", 1.0);   // (the straight whip's own size; 0 = off)
                    slip_rate += clampf((drift_t - slip) * T.get("whipSnap", 5.0), -2.2, 2.2) * whip_hold;
                }
                // on the front wheel (nose manual / stoppie) the rear just trails the front
                if (_nosing() || _nose_grace > 0.0)
                {
                    slip_w *= exp(-dt * 10.0); slip_rate = -slip * 6.0;
                }
                double slip_was = slip;
                slip = clampf(slip + slip_rate * dt, -1.5, 1.5);
                // a side slope pulls the bike down it (the front wheel falls to the low side); on a berm that's into the turn
                if (v > 0.5)
                {
                    // leaned WITH the tilt (into a berm, a banked bend) the pull down it is stronger (bankLock), only while
                    // steering INTO the tilt, held ~1 s after letting go
                    double c_pull = T.get("camberPull", 0.22);
                    _lock_hold = maxf(smooth01((b_in - 0.05) / 0.2), _lock_hold - dt / LOCK_HOLD);
                    c_pull += T.get("bankLock", 0.6) * smooth01((signf(bk) * lean - 0.05) / 0.3) * _lock_hold;
                    course_rate += c_pull * G * sin(bk) / maxf(va, 3.0) * smooth01((v - 0.5) / 2.0);
                }
                // the front tyre is knocked off its line by whatever slopes sideways under it that isn't the land's own tilt
                double kn = T.get("groundKnock", 0.6);
                double knock_t = 0.0;
                if (kn > 0.0 && !front_air)
                {
                    double fwo = L - BB_REAR;
                    double fx = x + f.x * fwo;
                    double fz = z + f.z * fwo;
                    double ox = f.z * 0.12;
                    double oz = -f.x * 0.12;   // to the left
                    double grad = (terrain.top_height(fx + ox, fz + oz) - terrain.top_height(fx - ox, fz - oz)) / 0.24;
                    double loc = clampf(grad + tan(bk), -1.5, 1.5);
                    // small ripples don't steer
                    loc = signf(loc) * maxf(0.0, absf(loc) - 0.08);
                    knock_t = clampf(-kn * loc * 1.6 * clampf(nF / maxf(0.1, G * (1.0 - SH_R)), 0.0, 1.5) * smooth01(va / 3.0), -1.2, 1.2);
                }
                // the knock builds and fades over ~0.08 s
                knock += (knock_t - knock) * minf(1.0, dt / maxf(0.005, T.get("knockSmooth", 0.08)));
                course_rate += knock;
                course += course_rate * dt;
                // the rear swings round the front: the BB moves sideways as the heading turns against the travel
                double ds = slip - slip_was;
                double pv = T.get("gripPivot", 0.7) * (L - BB_REAR) * ds;
                double hh = course + slip;
                x += pv * sin(hh); z += pv * cos(hh);
                if (flick_kick != 0.0)   // a body flick whips the bike round: most of it turns the travel, a little steps the rear out
                {
                    double fk = flick_kick * minf(1.0, dt * 10);
                    flick_kick -= fk;
                    course += fk * 0.9; slip = clampf(slip + fk * 0.1, -T["slipMax"] * 0.8, T["slipMax"] * 0.8);
                }
                if (absf(v) < 1.2)
                {
                    double k = minf(1.0, dt * 6); course += slip * k; slip -= slip * k; slip_w -= slip_w * k;
                }
                // fakie: both sticks towards the pad's centre swing the bike round to face the way it travels
                if (v < -0.5 && steer_input < -0.6 && flick_in > 0.6) _fakie_hold += dt;
                else _fakie_hold = 0.0;
                if (_fakie_hold > 0.1)
                {
                    _fakie_hold = 0.0;
                    course += PI; v = -v; turn_off = -PI; rev_cap = 3.0;
                    host.flash("SWITCH!");
                }
                turn_off -= turn_off * minf(1.0, dt * 7.0);
                if (absf(turn_off) < 0.01) turn_off = 0.0;
                heading = course + slip + turn_off;
                yaw_rate = course_rate + slip_rate;
                lat_a = a_lat;
                // the turn presses down through the leaned bike (sqrt(g^2 + a^2)), eased over ~0.1 s
                double cg_t = T.get("cornerLoad", 0.6) * (sqrt(G * G + a_lat * a_lat) - G);
                corner_g += (cg_t - corner_g) * minf(1.0, dt / maxf(0.005, T.get("cornerSmooth", 0.1)));
                // (the first ~1 deg of slip is the tyre's own give, not a slide)
                double scrub = (mu * G * minf(load_k, 1.5) * maxf(0.0, absf(sin(slip)) - 0.015) * 0.9 + absf(excess) * (1 - share) * absf(v) * 0.15) * (1.0 - T.get("whipCarry", 0.6) * wk);   // a held drift keeps its speed
                v -= signf(v) * minf(absf(v), scrub * dt);
                // a slide past slipMax: the crash judge builds on how far past. In a manual the rider first drops the front
                double wo_sev = va > 3.0 ? (absf(slip) - T["slipMax"]) / 0.25 : -1.0;
                if (_balancing() && (wo_sev > 0.0 || absf(slip) > T["slipMax"] * T.get("manSlideCatch", 0.7)))
                {
                    _man_drop(); wo_sev = -1.0;
                }
                if (_nosing() && rear_air) wo_sev = -1.0;   // the rear is in the air: it swings round the front, nothing slides
                _danger("WASHED OUT!", wo_sev, dt);
                double into_bank = maxf(0.0, bk * signf(a_lat));
                if (absf(slip) > 0.3) carve_acc = 0;
                else if (carve > 0.6) carve_acc += absf(a_lat) * dt * (1 + 3 * into_bank);
                else if (carve < 0.2 && carve_acc > 0)
                {
                    double gain = carve_acc > 2 ? minf(T["carveBoost"] * ((into_bank > 0.1 || carve_berm) ? 1.0 : 0.5), carve_acc * 0.08) : 0.0;
                    carve_acc = 0;
                    if (gain > 0.05 && v > 3)
                    {
                        v += gain; flow_up();
                        if (host.msg_idle()) host.flash((carve_berm ? "BERM" : "CARVE") + " +" + roundi(gain * 3.6).ToString(CultureInfo.InvariantCulture) + " km/h");
                    }
                }
                carve_berm = carve > 0.6 ? (carve_berm || into_bank > 0.15) : (carve_acc > 0 && carve_berm);
            }
            else
            {
                // yaw in the air: a turn carried off the lip keeps turning rider + bike. The rider can only twist the bike at
                // the hips, within airTwist; slip is the bike's heading against the travel direction
                double sys_slip = wrapf(slip - air_tw, -PI, PI) + (air_yaw + stick_yaw) * dt;
                // air WHIP: the right stick to the side (short of its edge) throws the bike sideways under a body that keeps
                // facing where it flies. Carved in at the lip (_whip_in) up to airWhip, from the air alone only WHIP_AIR_ONLY
                double w_cap = lerpf(WHIP_AIR_ONLY, T.get("airWhip", 1.5), absf(_whip_in));
                double whip_t = clampf(air_stick.x / 0.8, -1.0, 1.0) * w_cap * (1.0 - T.get("whipReturn", 0.7) * land_prep * T.get("airAssist", 0.6));
                // steer in the air: the held steer turns the bike off the travel (eased in after take-off, less while spinning flat)
                double st_t = 0.0;
                {
                    st_t = clampf(roll_keys, -1.0, 1.0) * T.get("airSteer", 0.6) * smooth01((air_time - AIR_STEER_DELAY) / AIR_STEER_RAMP);
                    st_t *= 1.0 - clampf(absf(stick_yaw) / 1.2, 0.0, 1.0);
                }
                _air_steer_s += (st_t - _air_steer_s) * minf(1.0, dt * 12.0);
                // next-bend aim: hands off the rider points the bike where the trail goes after the landing, airAim of the way.
                // Any steer / stick of the player takes over at once
                double aim_t = 0.0;
                {
                    double own_k = (1.0 - _air_own) * (1.0 - clampf(absf(roll_keys) * 3.0, 0.0, 1.0)) * (1.0 - clampf(absf(stick_yaw) / 1.2, 0.0, 1.0));
                    aim_t = clampf(aim_off, -AIM_MAX, AIM_MAX) * T.get("airAim", 0.6) * own_k * smooth01((air_time - 0.06) / 0.12);
                }
                _air_aim_s += (aim_t - _air_aim_s) * minf(1.0, dt * AIM_EASE);
                double steered = _air_steer_s + _air_aim_s;
                double tw_lim = maxf(T["airTwist"], absf(whip_t) + absf(steered) + 0.05);
                double tw_t = clampf(-sys_slip + whip_t + steered, -tw_lim, tw_lim);
                // a flat spin turns rider + bike as one: no whip, no hips holding the bike on the travel line
                tw_t *= 1.0 - clampf(absf(stick_yaw) / 1.2, 0.0, 1.0);
                // (thrown out: quick; let go / brought back: it unwinds over ~0.4 s, not a snap)
                bool back_tw = absf(tw_t) < absf(air_tw) - 0.02;
                double k_tw = back_tw ? 22.0 : 60.0;
                // (steering in the air answers fast)
                if (absf(steered) > 0.05) k_tw = maxf(k_tw, lerpf(60.0, AIR_STEER_K, clampf(absf(steered) / 0.3, 0.0, 1.0)));
                double c_tw = 2.0 * sqrt(k_tw) * (back_tw ? 1.0 : 0.77);
                air_tw_v += (k_tw * (tw_t - air_tw) - c_tw * air_tw_v) * dt;
                air_tw += air_tw_v * dt;
                if (absf(air_tw) > tw_lim)
                {
                    air_tw = signf(air_tw) * tw_lim; air_tw_v = 0.0;
                }
                _whip_peak = maxf(_whip_peak, absf(air_tw));
                _lean_peak = maxf(_lean_peak, absf(bike_lean));
                double slip_new = wrapf(sys_slip + air_tw, -PI, PI);
                yaw_rate = wrapf(slip_new - slip, -PI, PI) / dt;
                spin_acc += yaw_rate * dt;
                slip = slip_new;
                turn_off -= turn_off * minf(1.0, dt * 7.0);
                heading = course + slip + turn_off;
                lat_a = 0; lat_m = 0; flick_kick = 0.0; corner_g = 0.0; front_use = 0.0; front_push = 0.0; knock = 0.0;
                slip_w = 0.0; grip_r = 1.0; bar_catch += -bar_catch * minf(1.0, dt * 6);
            }
            if (!air)
                _pivot_step(dt, steer_input, brake_k);
            // (+ a whip lays the bike flatter the further it's thrown; tabletop: stickAirRoll = the lay-over at 0.8 of stick)
            double roll_t = roll_keys * T["airRoll"] + clampf(air_stick.x / 0.8, -1.0, 1.0) * T.get("stickAirRoll", 1.25) + clampf(air_stick.x / 0.8, -1.0, 1.0) * lerpf(WHIP_AIR_ONLY, T.get("airWhip", 1.5), absf(_whip_in)) * 0.3;
            if (air) roll_t *= 1.0 - 0.6 * clampf(absf(stick_yaw) / 1.2, 0.0, 1.0);   // spinning flat: a stylish lean, not laid right over
            if (air) roll_t += (_air_steer_s + _air_aim_s) * T.get("airPrelean", 0.5);   // banks into the steered turn
            double lean_t = air ? (absf(roll_t) > 0.03 ? roll_t : lean * 0.98) : clampf(atan(lat_a / G), -T["leanMax"] + minf(0.0, bk), T["leanMax"] + maxf(0.0, bk));
            // (in the air: blended, not switched, so with both sticks working the lean doesn't jerk)
            if (air)
                lean_t = lerpf(lean * 0.98, roll_t, smooth01(absf(roll_t) / 0.15));
            // slow riding: the rider tips in WITH the steer instead of waiting for the turn to build, and a slow bike rolls
            // quicker. Both fade out with speed (spd_k)
            double slow_k = 1.0 - spd_k;
            if (!air)
            {
                // balanced (bal_k): the rider leans to what the steer asks for and the turn follows the lean
                lean_t = lerpf(lean_t, lean_need, maxf(T.get("leanLead", 0.5) * slow_k, bal_k));
            }
            double kL = absf(steer_eff) > 0.01 ? T["leanIn"] : T["leanOut"];
            if (!air) kL *= 1.0 + T.get("slowRoll", 1.0) * slow_k;
            if (air) kL = lerpf(T["leanOut"], AIR_LEAN_K, smooth01(maxf(air_stick.length(), absf(roll_keys)) / 0.2));
            if (!air)
            {
                // only the ground pushing on the tyres can change the lean: over a crest (tyres light) the bike carries its lean
                kL *= clampf(n_tot / G, 0.12, 1.0);
            }
            lean_v += ((lean_t - lean) * kL - lean_v * 2 * sqrt(kL) * (air ? maxf(1.0, T["leanDamp"]) : T["leanDamp"])) * dt;
            lean_err = 0.0;
            if (!air)
            {
                // a balanced bike leaned further than the tyres can turn it falls on over (an inverted pendulum): held there
                // past lowsideAngle for 0.3 s it's down (LOWSIDE). Measured against the most the tyres could turn it
                double l_grip = atan(maxf(0.0, lean >= 0.0 ? _amax : -_amin) / G);
                lean_err = signf(lean) * maxf(0.0, absf(lean) - l_grip);
                // (just landed: no falling in / lowside for the first moment, it fades in over 0.4 s)
                double land_k = smooth01((since_land - 0.1) / 0.3);
                double fall = T.get("balanceFall", 0.5) * bal_k * land_k;
                if (fall > 0.0 && lean_err != 0.0)
                    lean_v += fall * G * sin(lean_err) * dt;
                _danger("LOWSIDE!", (bal_k > 0.3 && land_k > 0.99 && va > 4.0) ? (absf(lean_err) - T.get("lowsideAngle", 0.3)) / 0.25 : -1.0, dt);
                // a real bike + rider only rolls so fast: the roll speed eases into a top rate (leanRate); fast, the spinning
                // wheels hold the bike up a little (gyroStable)
                double lr = T.get("leanRate", 6.0) / (1.0 + T.get("gyroStable", 0.25) * smooth01((va - 8.0) / 12.0));
                lean_v = lr * tanh(lean_v / lr);
            }
            _risk_settle(dt);
            lean += lean_v * dt;
            // the lean the ground gives on top of the turn's own (drawn only): the body stick, slow steering, tilted ground,
            // the corner whip. Carried into the air and eased out, eased back in on landing
            double gx_t = 0.0;
            double bank_t = 0.0;
            // (gnd = 1 - air_k, the ground share of the drawing: see _air_blend)
            double gnd = 1.0 - air_k;
            if (gnd > 0.0)
            {
                gx_t = flick * T.get("flickLean", 0.0) * smooth01(va / 1.5);
                // (Project X slow corners: the bike is laid into the turn with the steer under a body that stays upright;
                // full up to slowBodyFrom, gone by slowBodyTo)
                double sl_k = 1.0 - _slow_body_k(va);
                gx_t += s_in * T.get("slowLean", 0.5) * sl_k * smooth01(va / 1.2);
                bank_t = T.get("bankLean", 0.6) * (air ? _bank_hold : bank);
                if (whip > 0.0) gx_t += whip_side * T.get("whipLean", 0.22) * whip * whip * (3.0 - 2.0 * whip) * (_whip_straight ? minf(1.5, T.get("whipStraight", 1.0)) : 1.0);
                gx_t *= gnd; bank_t *= gnd;
            }
            // (just landed: landSwapRate for both the drawn lean and the bank part, so a berm-to-berm swap out of a hop isn't heavy)
            double swap_r = T.get("landSwapRate", 7.0);
            bool post_land = !air && since_land < 0.35;
            double gx_rate = air ? 1.2 : (post_land ? swap_r : 60.0);
            _gx_lean = move_toward(_gx_lean, gx_t, gx_rate * dt);
            // (the ground's share eases at most 1.5 rad/s: from one bank straight into the next it swings over, not snaps)
            double bank_r = T.get("bankLeanRate", 1.5);
            if (post_land) bank_r = maxf(bank_r, swap_r);
            bank_lean = move_toward(bank_lean, bank_t, minf(gx_rate, bank_r) * dt);
            // rider + bike are two masses: while the lean is changing the bike runs ahead of it by the roll speed (bikeLead s),
            // the body's target doesn't. Drawn only
            double lead_t = clampf(lean_v * T["bikeLeanMul"] * T.get("bikeLead", 0.08), -0.35, 0.35) * gnd;
            _bike_lead += (lead_t - _bike_lead) * minf(1.0, dt * 20.0);
            // (the bike's own weave under the rider is off: only a test switch, BMX_WEAVE, turns it on)
            double wv_t = 0.0;
            _weave += (wv_t - _weave) * minf(1.0, dt * 8.0);
            double bl = lean * T["bikeLeanMul"] + _gx_lean + bank_lean + _bike_lead + _weave;
            // on one wheel rider + bike balance over the one contact patch, so they lean TOGETHER, by what the turn needs
            // against gravity (atan(lateral accel / g)). man_lk 0..1 = how far into that look. Drawing only
            double mk_t = (!air && front_air && _balancing()) ? 1.0 : 0.0;
            man_lk = move_toward(man_lk, mk_t, (mk_t > man_lk ? 5.0 : 3.0) * dt);
            if (man_lk > 0.0)
            {
                double ml = T.get("manLean", 0.42) * 1.25;
                double ml_t = clampf(atan(lat_a / G) * MAN_LEAN_K + steer_in * MAN_LEAN_IN, -ml, ml);
                _man_lean_s += (ml_t - _man_lean_s) * minf(1.0, dt * 7.0);
                bl = lerpf(bl, _man_lean_s, man_lk);
            }
            else
                _man_lean_s = bl;
            if (!air)
            {
                double cb_t = signf(bk) != signf(bl) ? 0.0 : absf(bk);
                // (eased: it switched on / off in one step as the bank or the lean changed side)
                cap_bank = move_toward(cap_bank, cb_t, 2.0 * dt);
            }
            else   // the bank's extra room is carried off the lip, fading over 2 s
                cap_bank = maxf(0.0, cap_bank - dt * 0.5);
            double cap_b = T["bikeLeanCap"] + cap_bank;
            // (slow, the drawn bike goes no further than slowBikeCap: an upright rider can't reach the bars of a bike laid
            // out past ~45 deg. Gone by slowBodyTo)
            cap_b = lerpf(minf(cap_b, T.get("slowBikeCap", 0.62)), cap_b, _slow_body_k(va));
            bike_lean = cap_b * tanh(bl / cap_b);
            double lim_t = 9.0;
            if (!air && absf(bike_lean) > 0.05)
            {
                // what matters for the tyre is its lean against the ground WHERE IT SWINGS TO: look 0.3 / 0.5 m to the lean
                // side at both wheels: the bike leans at most groundLeanMax against the steepest rise there
                double sg = signf(bike_lean);
                // (+ lean = left = (f.z, -f.x), as in _bank_at)
                double lx = f.z * sg;
                double lz = -f.x * sg;   // unit vector to the lean side
                double phi = -0.5;
                for (int k = 0; k < 2; k++)   // front and rear wheel
                {
                    double wo = k == 0 ? L - BB_REAR : -BB_REAR;
                    double wx = x + f.x * wo;
                    double wz = z + f.z * wo;
                    // the land itself (deck_height: no rock / log domes)
                    double h0 = terrain.deck_height(wx, wz);
                    foreach (double d in LEAN_PROBE)
                        phi = maxf(phi, atan((terrain.deck_height(wx + lx * d, wz + lz * d) - h0) / d));
                }
                lean_room = _or(lean_room, phi);
                // eased (~0.17 s), not only rate limited: the slope beside a tyre picks up every ripple of the ground
                lean_room += clampf((phi - lean_room) * (1.0 - exp(-6.0 * dt)), -3.0 * dt, 3.0 * dt);
                // (ground falling away on the lean side, the inside of a berm: half of that as extra room, at most bermLeanRoom)
                lim_t = maxf(0.25, T.get("groundLeanMax", 1.05) - (lean_room > 0.0 ? lean_room : maxf(lean_room * 0.5, -T.get("bermLeanRoom", 0.15))));
            }
            // the ground's limit on the lean opens / closes over a moment when the bike leaves / meets the ground
            if (air)
                lean_lim = minf(9.0, lean_lim + 2.5 * dt);
            else if (since_land < 0.4)
                lean_lim = maxf(lim_t, lean_lim - 4.0 * dt);
            else
                lean_lim = lim_t;
            if (lean_lim < 8.0)
                bike_lean = signf(bike_lean) * minf(absf(bike_lean), lean_lim);
            // the bike leans under the rider: the body always stays a little more upright than the bike. The body's rules
            // read the bike's lean without the weave (bl_nw); the weave's share is added to the counter at the end
            double w_part = cap_b * (tanh(bl / cap_b) - tanh((bl - _weave) / cap_b));
            weave_lean = w_part;   // (Game pivots the drawn bike about the rider's hips for this share)
            double bl_nw = bike_lean - w_part;
            double b_sg = signf(bl_nw);
            {
                // the clamp holding the body to the bike's side fades in over the first ~0.3 rad of bike lean, so the body
                // passes upright continuously
                double b_t = (lean + bank_lean) * T["bodyLean"];
                double w_c = smooth01(absf(bl_nw) / 0.3);
                // (in a deep turn the body's share falls from 80 % to cornerBody from ~0.5 to 1.1 rad of bike lean)
                double sh_max = lerpf(0.8, T.get("cornerBody", 0.7), smooth01((absf(bl_nw) - 0.5) / 0.6));
                double body_l = b_t - w_c * b_sg * maxf(0.0, (b_t - sh_max * bl_nw) * b_sg);
                // (slow, the rider lays the BIKE into the turn and stays upright: the body's lean is a share of the bike's,
                // slowBody below slowBodyFrom, bodyLean from slowBodyTo, never past the deep-turn share. Drawing only)
                body_l = (bl_nw - _bike_lead) * minf(lerpf(T.get("slowBody", 0.15), T["bodyLean"], _slow_body_k(va)), sh_max);
                counter = bl_nw - body_l;
            }
            // on a bank the rider goes WITH the bike (drawn only): bank_sq (0 flat .. bankBody on banks toward the lean) takes
            // the body that share of the way into line with the bike
            double sq_t = 0.0;
            // the held ground bank through a skip, faded out by the air blend on a real flight
            sq_t = T.get("bankBody", 0.7) * smooth01(((air ? _bank_hold : bank) * signf(bl_nw) - 0.03) / 0.12) * gnd;
            bank_sq = move_toward(bank_sq, sq_t, 3.0 * dt);
            if (bank_sq > 0.0)
            {
                // (berms: the body square to the berm's FACE, the bike leaned further past it: the body leans as far as the
                // bank, at least half the bike's lean and at most 80 % of it)
                double sh_b = lerpf(0.8, T.get("cornerBody", 0.7), smooth01((absf(bl_nw) - 0.5) / 0.6));
                double body_b = minf(maxf(0.8, sh_b) * absf(bl_nw), maxf(absf(bank) * minf(1.0, sh_b / 0.5), sh_b * absf(bl_nw)));
                // (slow in a berm the body still stays nearer upright: at least half of its berm lean, more with speed)
                body_b *= lerpf(maxf(0.5, T.get("slowBody", 0.15)), 1.0, _slow_body_k(va));
                counter = lerpf(counter, bl_nw - signf(bl_nw) * body_b, bank_sq);
            }
            // in the air the stick's lean is the rider's doing: their body goes the other way a little (counter-lean). It
            // comes in with the air blend (air_k); the weight follows the stick over ~0.25 s
            if (air) _air_wl = move_toward(_air_wl, clampf(absf(air_stick.x) * 2.5, 0.0, 1.0), 4.0 * dt);
            if (air_k > 0.0)
                counter = lerpf(counter, bl_nw * (1.0 + T.get("stickBodyCounter", 0.25)), _air_wl * air_k);
            // (on the back wheel the body goes over with the bike: only MAN_BODY_OFF of the bike's lean is left as counter-lean)
            if (man_lk > 0.0) counter = lerpf(counter, bl_nw * MAN_BODY_OFF, man_lk);
            counter += w_part;
            rock = pedal_rock(crank, sprint, pedal, va, bike_rock);
            return va;
        }


        /// 0 slow .. 1 fast: how much of its lean the body takes with the bike (Project X: slow = bike under an upright body)
        double _slow_body_k(double va)
        {
            double v0 = T.get("slowBodyFrom", 4.0);
            return smooth01((va - v0) / maxf(0.5, T.get("slowBodyTo", 11.0) - v0));
        }

        /// slow, braking and steering: the bike pivots round its front wheel (a pirouette)
        void _pivot_step(double dt, double steer_input, double brake_k)
        {
            bool on = absf(v) < 2.5 && brake_k > 0.3 && absf(steer_input) > 0.1 && !front_air && !rear_air;
            // only a forward-rolling nose pivot, never stopped or backing up (that's reverse, it steers like a bike)
            on = on && v > 0.5 && !brake_back;
            if (!on)
            {
                pivot = maxf(0.0, pivot - dt * 5);
                if (pivot == 0.0) pivot_acc = 0.0;
                return;
            }
            pivot = minf(1.0, pivot + dt * 5);
            double FRONT = L - BB_REAR;
            double fx = x + cos(heading) * FRONT;
            double fz = z - sin(heading) * FRONT;
            double dh = signf(steer_input) * T["pivotRate"] * pivot * dt;
            int n0 = floori(absf(pivot_acc) / PI);
            pivot_acc += dh;
            course += dh; heading += dh;
            x = fx - cos(heading) * FRONT; z = fz + sin(heading) * FRONT;
            v = move_toward(v, 0.0, 10.0 * dt);
            yaw_rate = dh / dt;
            int n1 = floori(absf(pivot_acc) / PI);
            if (n1 > n0)
            {
                host.flash((n1 * 180).ToString(CultureInfo.InvariantCulture) + " PIVOT!");
                if (n1 % 2 == 0) flow_up();
            }
        }

        /// the ground's tilt across the bike (+ = rising to the right), read across both axles +-0.5 m on the land only
        double _bank_at(V3 f)
        {
            double w = 0.5;
            double lx = f.z * w;
            double lz = -f.x * w;
            double dh = 0.0;
            for (int k = 0; k < 2; k++)   // front and rear axle
            {
                double wo = k == 0 ? L - BB_REAR : -BB_REAR;
                double mx = x + f.x * wo;
                double mz = z + f.z * wo;
                dh += host.terrain.deck_height(mx - lx, mz - lz) - host.terrain.deck_height(mx + lx, mz + lz);
            }
            return atan(dh * 0.5 / (2 * w));
        }
    }
}
