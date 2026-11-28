// Port of godot/scripts/bike/bike_physics.gd: group D, stage 7 (_step_move): move along the travel direction, then
// everything it can run into (rocks, trees, fences, tape, cacti, walls).
using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    public sealed partial class BikePhysics
    {
        /// Godot Vector2.cross
        static double _cross2(V2 a, V2 b) => a.x * b.y - a.y * b.x;

        /// the tape span a collider belongs to (Godot: c["tape"] = {broken, pts}, shared by several colliders)
        static bool _tape_span(Obstacle c, out object span, out bool broken, out V3[] pts)
        {
            var t = c.tape_span;
            span = t; broken = t == null || t.broken; pts = t?.pts;
            return t != null && t.pts != null && t.pts.Length >= 2;
        }

        List<object> _tapes_seen_spans() => _tapes_seen;

        /// stage 7: move along the travel direction, then everything it can run into (rocks, trees, fences, tape, walls)
        void _step_move(double dt, V3 f)
        {
            var terrain = host.terrain;
            // --- move ---
            double px = x;
            double pz = z;
            double g_prev = terrain.deck_height(px, pz);
            // on the ground v is the speed along the slope (the tyres carry the bike up / down it, so only its
            // horizontal part moves it across the map); in the air v is the horizontal speed
            double v_h = air ? v : v * cos(_g_pitch);
            x += cos(course) * v_h * dt; z -= sin(course) * v_h * dt;
            distance += absf(v) * dt;
            {
                double stp = maxf(absf(v) * dt, 1e-3);
                double g_new = terrain.deck_height(x, z);
                double sv = v != 0.0 ? signf(v) : 1.0;
                bool wall = false;
                if (air) wall = g_new > y + 0.35;
                else
                {
                    // an edge is read over at least EDGE_BASE whatever the speed (a slow bike's steps were too short to
                    // see a curb, a fast one's long enough to stop dead on 20 cm)
                    double bs = maxf(stp, EDGE_BASE);
                    double g_c = maxf(g_new, terrain.deck_height(px + cos(course) * bs * sv, pz - sin(course) * bs * sv));
                    wall = (g_c - g_prev) / bs > 1.6 && g_c - g_prev > 0.05;
                }
                if (wall && !air)
                {
                    // a steep edge is only a wall if it's taller than a tyre rolls up; look a little further along the
                    // travel so a real face (that keeps rising) still is one
                    double g_ahead = terrain.deck_height(x + cos(course) * 0.3 * sv, z - sin(course) * 0.3 * sv);
                    double rise = maxf(g_new, g_ahead) - g_prev;
                    double lim = 0.5 * minf(RWF, RWR);
                    // the frame's point is the bottom bracket: by the time it reaches an edge the front has climbed it
                    // and the edge is the REAR wheel's to roll up (up to REAR_ROLL x its radius, front up on top)
                    if (v > 0.0 && rise > lim)
                    {
                        double fr = L - BB_REAR;
                        double g_fr = terrain.deck_height(x + f.x * fr, z + f.z * fr);
                        if (g_fr >= g_prev + 0.7 * rise && rise <= REAR_ROLL * RWR)
                            lim = rise + 0.01;
                    }
                    wall = rise > lim;
                }
                if (wall)
                {
                    x = px; z = pz;
                    if (absf(v) > 6) _crash("SMACK! Hit the cliff");
                    else
                    {
                        if (absf(v) > 1.5)
                        {
                            shake = 0.3; host.flash("BONK!");
                        }
                        v *= -0.25;
                    }
                }
            }

            // --- obstacles ---
            double FRONT = L - BB_REAR;
            // race tape: a swept test (the front tyre's leading edge this step vs each span's line), so a fast bike
            // never slips between the span's hit points
            double tf = FRONT + RWF;
            var a0 = new V2(px + f.x * tf, pz + f.z * tf);
            var a1 = new V2(x + f.x * tf, z + f.z * tf);
            List<Obstacle> near = colliders_near(x, z);   // one grid walk for tape + obstacles
            _tapes_seen.Clear();
            List<object> tapes_seen = null;
            foreach (var c in near)
            {
                if (!c.tape) continue;
                if (!_tape_span(c, out object sp, out bool sp_broken, out V3[] tp)) continue;
                if (sp_broken) continue;
                if (tapes_seen == null) tapes_seen = _tapes_seen_spans();
                bool seen = false;
                foreach (var o in tapes_seen)
                    if (ReferenceEquals(o, sp)) { seen = true; break; }
                if (seen) continue;
                tapes_seen.Add(sp);
                var tA = new V2(tp[0].x, tp[0].z);
                var tB = new V2(tp[tp.Length - 1].x, tp[tp.Length - 1].z);
                V2 dm = a1 - a0;
                V2 dt_ab = tB - tA;
                double den = _cross2(dm, dt_ab);
                if (absf(den) < 1e-9) continue;
                double sm = _cross2(tA - a0, dt_ab) / den;   // along the tyre's move
                double su = _cross2(tA - a0, dm) / den;      // along the tape
                if (sm < 0.0 || sm > 1.0 || su < 0.0 || su > 1.0) continue;
                double tape_y = tp[clampi(roundi(su * (tp.Length - 1)), 0, tp.Length - 1)].y;
                if (y > tape_y - 0.05) continue;   // the wheels are over it
                V2 hp = tA + dt_ab * su;
                if (host.smash(c, new V3(f.x * v, vy, f.z * v), new V3(hp.x, tape_y, hp.y)))
                    v *= 0.97;   // ("SNAP!" pops when it tears)
            }
            // the rider's body and the bars take tape too (swept like the tyre, from where each point was a step ago): a
            // whip, a flip or a low jump over a span that the wheels clear can still catch the chest / head / bars
            {
                double cb0 = cos(pitch); double sb0 = sin(pitch);
                for (int bi = 1; bi < BODY_PTS.Length; bi++)
                {
                    V3 bp = BODY_PTS[bi];
                    double off = bp.x * cb0 - bp.y * sb0;
                    double by = y + bp.x * sb0 + bp.y * cb0;
                    var b0 = new V2(px + f.x * off, pz + f.z * off);
                    var b1 = new V2(x + f.x * off, z + f.z * off);
                    foreach (var c in near)
                    {
                        if (!c.tape) continue;
                        if (!_tape_span(c, out object _sp, out bool sp_broken, out V3[] tp)) continue;
                        if (sp_broken) continue;
                        var tA = new V2(tp[0].x, tp[0].z);
                        V2 dt_ab = new V2(tp[tp.Length - 1].x, tp[tp.Length - 1].z) - tA;
                        V2 dm = b1 - b0;
                        double den = _cross2(dm, dt_ab);
                        if (absf(den) < 1e-9) continue;
                        double sm = _cross2(tA - b0, dt_ab) / den;
                        double su = _cross2(tA - b0, dm) / den;
                        if (sm < 0.0 || sm > 1.0 || su < 0.0 || su > 1.0) continue;
                        double tape_y = tp[clampi(roundi(su * (tp.Length - 1)), 0, tp.Length - 1)].y;
                        if (absf(by - tape_y) > bp.z) continue;
                        V2 hp = tA + dt_ab * su;
                        if (host.smash(c, new V3(f.x * v, vy, f.z * v), new V3(hp.x, tape_y, hp.y)))
                            v *= 0.97;
                    }
                }
            }
            double cbp = cos(pitch); double sbp = sin(pitch);
            foreach (var c in near)
            {
                if (c.tape) continue;   // handled above
                double fx0 = x + f.x * FRONT;
                double fz0 = z + f.z * FRONT;
                double fdx = fx0 - c.x;
                double fdz = fz0 - c.z;
                double fd = sqrt(fdx * fdx + fdz * fdz);
                double cdx = x - c.x;
                double cdz = z - c.z;
                double cd = sqrt(cdx * cdx + cdz * cdz);
                double f_min = c.r + 0.05;
                double c_min = c.r + 0.16;
                bool hit_f = fd < f_min;
                bool hit_c = cd < c_min;
                // fences and cacti: the rider's body, the bars and the rear wheel count too, at their own height (a flip,
                // a whip, a low jump over the top rail: it's the body that goes through it)
                bool hit_b = false;
                double bdx = 0.0; double bdz = 0.0; double b_min = c_min;
                // (GDScript: c.has("fence") or c.has("cactus"), key presence; the plug's flags stand in for it)
                if (!hit_f && !hit_c && cd < c.r + 2.4 && (c.fence || c.cactus))
                {
                    double gr = terrain.height(c.x, c.z);
                    double top = c.has_ceil ? c.ceil : gr + (c.fence ? 1.2 : 2.0);
                    foreach (var bp in BODY_PTS)
                    {
                        double wy = y + bp.x * sbp + bp.y * cbp;
                        if (wy > top + bp.z || wy < gr - 0.1) continue;
                        double off = bp.x * cbp - bp.y * sbp;
                        double ddx = x + f.x * off - c.x;
                        double ddz = z + f.z * off - c.z;
                        if (ddx * ddx + ddz * ddz < (c.r + bp.z + 0.04) * (c.r + bp.z + 0.04))
                        {
                            hit_b = true; bdx = ddx; bdz = ddz; b_min = c.r + bp.z + 0.04; break;
                        }
                    }
                }
                if (!hit_f && !hit_c && !hit_b) continue;
                double dx = hit_f ? fdx : (hit_c ? cdx : bdx);
                double dz = hit_f ? fdz : (hit_c ? cdz : bdz);
                double d = maxf(1e-4, hit_f ? fd : (hit_c ? cd : sqrt(bdx * bdx + bdz * bdz)));
                // (a body point is pushed out to its own reach: with the frame's, smaller, the push came out negative and
                // a slow bike was pulled INTO the fence / cactus its rear wheel or the rider's chest touched)
                double mn = hit_f ? f_min : (hit_c ? c_min : b_min);
                var vel = new V3(f.x * v, vy, f.z * v);
                if (c.cactus && absf(v) > 2.5 && !(air && y > (c.has_ceil ? c.ceil : INF)))
                {
                    if (host.smash(c, vel, new V3(x, y, z)))
                    {
                        v *= 0.8; shake = maxf(shake, 0.35); host.flash("OUCH! CACTUS!");
                    }
                    continue;
                }
                if (c.fence && (absf(v) > 2.2 || (air && vy < -2)) && !(air && y > terrain.height(c.x, c.z) + 1.2 && !hit_b))
                {
                    if (host.smash(c, vel, new V3(x, y, z)))
                    {
                        v *= 0.86; shake = maxf(shake, 0.3); host.flash(c.fence_style == "picket" ? "CRUNCH!" : "SMASH!");
                    }
                    continue;
                }
                if (c.has_top)
                {
                    // how tall the rock stands: over the bike's own height, but never more than over the ground it sits
                    // on (on a climb / bank / leaned in a turn a 15 cm stone measured from the bike read as a wall)
                    double clear = minf(c.top - y, c.top - (c.has_base ? c.@base : y));
                    if (clear < CLIMB * RWF) continue;
                    if (!hit_f || fd > c.r * 0.85) continue;
                    if ((f.x * fdx + f.z * fdz) / fd >= 0) continue;
                    if (absf(v) > 2 && !ReferenceEquals(joint_rock, c))
                    {
                        joint_rock = c;
                        host.rock_chips(c);
                    }
                    double back = (c.r * 0.85 - fd) / fd;
                    x += fdx * back; z += fdz * back;
                    double head = (f.x * fdx + f.z * fdz) / fd;
                    // over the bars only when the hit could really throw you: the taller the rock against the wheel, the
                    // less speed it takes (just past rolling height ~12 m/s, a boulder ~6); a front already unweighted /
                    // in the air (a hop, a manual) rides up it
                    double tall = clampf((clear - CLIMB * RWF) / (RWF * 0.8), 0.0, 1.0);
                    double bb = T.get("bonkBoulder", 6.0);
                    double bonk_v = bb + (T.get("bonkSmall", 12.0) - bb) * (1.0 - tall);
                    if (head < -0.77 && -v * head > bonk_v && !front_air)
                        _crash("BONK! Over the bars");
                    else if (head < -0.3 && v > 1.5)
                    {
                        host.burst(new V3(fx0, y + 0.3, fz0), 16, 0, 1.2); v *= -0.25; shake = 0.35; host.flash("BONK!");
                    }
                    else v *= exp(-3.6 * dt);   // rubbing past it (0.97 a step at 120 Hz, the same at any rate)
                    continue;
                }
                if (air)
                {
                    double ceil_h = c.has_ceil ? c.ceil : terrain.height(c.x, c.z) + (c.fence ? 1.2 : 3.2);
                    if (y > ceil_h) continue;
                }
                double push = (mn - d) / d;
                x += dx * push; z += dz * push;
                double hd = (f.x * dx + f.z * dz) / d;
                if (hd < -0.77 && -v * hd > 6 && !front_air)   // a front already up (manual, hop) rides into it, like rocks
                    _crash("BONK! Over the bars");
                else if (hd < -0.3 && v > 1.5)
                {
                    host.burst(new V3(fx0, y + 0.3, fz0), 16, 0, 1.2); v *= -0.25; shake = 0.35; host.flash("BONK!");
                }
                else v *= exp(-3.6 * dt);
            }
        }
    }
}
