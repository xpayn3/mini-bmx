using System;
using Runout.Sim;

namespace Runout.Rider
{
    /// The rider at a stop: port of godot/scripts/game/game.gd _update_dab, _pick_dab_side, _dab_foot, _idle_life,
    /// _idle_look / _update_look (riding path), _hand_to_hip, the stop poses (stand over the top tube / sit on the saddle)
    /// and the bike's lean onto the foot (dab_lean, the player's tipping, the idle weight shifts + bars). Engine-free: the
    /// caller gives the bike's frame (sim / Godot world space) and turns the world targets into its own spaces.
    /// (Foot out in flat corners is off in Godot by default (user: "it ruins our style"): not ported.)
    /// Order per drawn frame, as Godot's Game._process: update() -> lean() (the drawn bike's dab lean, before posing it)
    /// -> after the bike is posed: foot targets (DabFoot / StandFoot) + hand_hip -> the pose inputs.
    public sealed class RiderStops
    {
        public const double IDLE_SHIFT = 0.07, IDLE_BAR = 0.24, IDLE_BAR_DRIFT = 0.05;
        public const double STAND_LEAN = 0.3, STAND_OVER = 0.08, LOOK_TWIST = 0.45, HAND_HIP_YAW = 1.0;
        public const double STOP_AFTER = 0.5, STOP_IN = 0.7, STAND_FOOT_OUT = 0.3, IDLE_IN = 0.8;
        public const double DAB_LEAN = 0.24, DAB_OUT = 0.36, DAB_FWD = 0.10;

        public Func<double, double, double> top_height;   // the drawn ground (Godot / sim space)
        readonly Random _rng;

        // state (Godot names)
        public double dab_lin, dab_k, dab_side = -1.0;
        public int stop_mode;                 // 1 stands over the top tube (both feet down), 2 sits on the saddle
        public double stop_w;                 // eased into it
        public double stand_var;              // the stop lean's moving part (toward the foot +): the body holds against it
        public double dab_lean_s, dab_hold, idle_lean, idle_steer;
        public double look_yaw, look_pitch;
        public double hand_hip, hand_hip_side = -1.0;
        double _dab_vprev, _dab_dec, _dab_gap;
        double _idle_k, _idle_shift, _idle_shift_v, _idle_shift_t, _idle_shift_next, _idle_bar, _idle_bar_v, _idle_bar_t, _idle_bar_next;
        double _idle_tgt_y, _idle_tgt_p, _idle_next;
        double t;

        public RiderStops(int seed = 4711) { _rng = new Random(seed); }

        double randf() => _rng.NextDouble();
        double randf_range(double a, double b) => a + (b - a) * _rng.NextDouble();
        static double clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
        static double move_toward(double f, double to, double d) => Math.Abs(to - f) <= d ? to : f + Math.Sign(to - f) * d;
        static double smooth01(double x) { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); }
        double Top(double x, double z) => top_height != null ? top_height(x, z) : 0.0;

        public void reset()
        {
            dab_lin = dab_k = 0; stop_w = 0; stand_var = 0; dab_lean_s = 0; dab_hold = 0; idle_lean = idle_steer = 0;
            look_yaw = look_pitch = 0; hand_hip = 0; _idle_k = 0; _idle_shift = _idle_shift_v = _idle_shift_t = 0;
            _idle_bar = _idle_bar_v = _idle_bar_t = 0; _idle_tgt_y = _idle_tgt_p = 0; _idle_next = 0;
        }

        /// one drawn frame before the bike is posed: _update_dab (sets st.foot_down), _idle_life, the look round.
        /// bb = the bottom bracket (crank centre, world), fwd / rgt = the bike's heading frame flat (Godot: rig basis x / z),
        /// pedalDy = left pedal pivot height minus the right one (world)
        public void update(double dt, BikeSim st, Vec3 bb, Vec3 fwd, Vec3 rgt, double pedalDy)
        {
            t += dt;
            if (st.crash_on)
            {
                dab_lin = 0; dab_k = 0; st.foot_down = false;
                _dab_vprev = st.v;
                IdleLife(dt); Look(dt);
                return;
            }
            // slowing to a stop the foot comes off the pedal a moment before the bike stands
            double decel = (_dab_vprev - st.v) / Math.Max(dt, 1e-3);
            _dab_vprev = st.v;
            _dab_dec += (decel - _dab_dec) * (1.0 - Math.Exp(-dt * 6.0));
            bool coming = st.v < 1.8 && st.v > 0.0 && _dab_dec > 0.8;
            bool want = !st.air && st.pedal < 0.05 && (dab_lin > 0.0 ? (st.v < 1.2 && st.v > -0.7) : (Math.Abs(st.v) < 0.5 || coming));
            if (want && dab_lin <= 0.0)
            {
                PickSide(st, bb, fwd, rgt, pedalDy);
                stop_mode = randf() < 0.55 ? 1 : 2;
            }
            dab_lin = move_toward(dab_lin, want ? 1.0 : 0.0, dt / (want ? 0.45 : 0.4));
            dab_k = smooth01(dab_lin);
            st.foot_down = want && dab_lin >= 0.6;
            // the bike settles onto the foot: more when the foot's ground is lower than the other side's, a slow sway once settled
            double lean_t = DAB_LEAN * (1.0 - 0.65 * smooth01(stop_w) * (stop_mode == 1 ? 1.0 : 0.0)) + clamp(-_dab_gap * 0.9, -0.08, 0.1)
                + 0.02 * Math.Sin(t * 0.8) * clamp(dab_hold - 0.5, 0.0, 1.0);
            dab_lean_s += (lean_t - dab_lean_s) * (1.0 - Math.Exp(-dt * 3.0));
            dab_hold = dab_k > 0.99 ? dab_hold + dt : 0.0;
            bool sw_on = stop_mode > 0 && dab_hold > STOP_AFTER;
            stop_w = move_toward(stop_w, sw_on ? 1.0 : 0.0, Math.Min(dt, 0.05) / (sw_on ? STOP_IN : 0.3));
            IdleLife(dt);
            Look(dt);
        }

        /// which foot goes down: the uphill one on a side slope, never onto a rock / bank much higher than the other side,
        /// on flat ground the lower pedal's, level cranks -> the side the bike leans to, else left
        void PickSide(BikeSim st, Vec3 bb0, Vec3 fwd, Vec3 rgt, double dy)
        {
            Vec3 bb = bb0 + fwd * DAB_FWD;
            Vec3 l = bb - rgt * DAB_OUT, r = bb + rgt * DAB_OUT;
            double gl = Top(l.x, l.z), gr = Top(r.x, r.z);
            double dg = gr - gl;   // > 0: the ground on the right is higher
            if (Math.Abs(dg) > 0.35) dab_side = -Math.Sign(dg);
            else if (Math.Abs(dg) > 0.04) dab_side = Math.Sign(dg);
            else if (Math.Abs(dy) > 0.03) dab_side = dy < 0.0 ? -1.0 : 1.0;
            else if (Math.Abs(st.bike_lean) > 0.02) dab_side = -Math.Sign(st.bike_lean);
            else dab_side = -1.0;
            _dab_gap = (gr - gl) * dab_side;
        }

        /// weight shifts and bars while settled at a stop (critically damped springs)
        void IdleLife(double dt)
        {
            bool on = dab_k > 0.5 && dab_hold > 0.4;
            _idle_k = move_toward(_idle_k, on ? 1.0 : 0.0, dt / (on ? IDLE_IN : 0.3));
            double k = smooth01(_idle_k);
            double h = Math.Min(dt, 0.05);
            if (on)
            {
                _idle_shift_next -= h;
                if (_idle_shift_next <= 0.0)
                {
                    _idle_shift_t = randf() < 0.55 ? randf_range(-1.0, 1.0) : clamp(_idle_shift_t + randf_range(-0.3, 0.3), -1.0, 1.0);
                    _idle_shift_next = randf() < 0.4 ? randf_range(0.6, 2.0) : randf_range(2.0, 5.5);
                }
                _idle_bar_next -= h;
                if (_idle_bar_next <= 0.0)
                {
                    _idle_bar_t = randf() < 0.35 ? 0.0 : randf_range(-1.0, 1.0);
                    _idle_bar_next = randf_range(1.2, 4.0);
                }
            }
            else { _idle_shift_t = 0.0; _idle_bar_t = 0.0; }
            Vec2 ss = RiderPose.crit_spring(_idle_shift, _idle_shift_v, _idle_shift_t, 0.35, h);
            _idle_shift = ss.x; _idle_shift_v = ss.y;
            Vec2 bs = RiderPose.crit_spring(_idle_bar, _idle_bar_v, _idle_bar_t, 0.25, h);
            _idle_bar = bs.x; _idle_bar_v = bs.y;
            idle_lean = IDLE_SHIFT * _idle_shift * k;
            idle_steer = (IDLE_BAR * _idle_bar + IDLE_BAR_DRIFT * Math.Sin(t * 0.37 + 1.3) * Math.Sin(t * 0.19)) * k;
        }

        /// the calm look-round with a foot down (Godot _update_look's riding path + _idle_look)
        void Look(double dt)
        {
            if (dab_k < 0.5 || dab_hold < 0.6) { _idle_tgt_y = 0; _idle_tgt_p = 0; _idle_next = 0.0; }
            else
            {
                _idle_next -= dt;
                if (_idle_next <= 0.0)
                {
                    double r = randf();
                    if (r < 0.25) { _idle_tgt_y = 0.0; _idle_tgt_p = 0.0; }                                       // ahead
                    else if (r < 0.55) { _idle_tgt_y = randf_range(0.6, 1.25) * (randf() < 0.5 ? 1.0 : -1.0); _idle_tgt_p = randf_range(-0.05, 0.2); }   // off to a side
                    else if (r < 0.75) { _idle_tgt_y = dab_side * randf_range(1.4, 1.8); _idle_tgt_p = 0.1; }   // back up the trail over the shoulder
                    else if (r < 0.88) { _idle_tgt_y = -dab_side * 0.35; _idle_tgt_p = -0.45; }                 // down at the foot
                    else { _idle_tgt_y = randf_range(-0.4, 0.4); _idle_tgt_p = randf_range(0.25, 0.4); }        // up at the hills
                    _idle_next = randf_range(1.4, 3.6);
                }
            }
            double k = 1.0 - Math.Exp(-dt * 3.2);
            look_yaw += (_idle_tgt_y * dab_k - look_yaw) * k;
            look_pitch += (_idle_tgt_p * dab_k - look_pitch) * k;
        }

        /// the drawn bike's lean onto the foot (+ = left like bike_lean), the player's tipping (flick = the lean input),
        /// never far past upright away from the foot; sets stand_var (what the body holds against)
        public double lean(double flick)
        {
            double dl = -dab_side * (dab_lean_s + idle_lean) * dab_k;
            if (dab_k > 0.0)
            {
                dl += flick * STAND_LEAN * dab_k;
                double fs = -dab_side;
                dl = fs * Math.Max(dl * fs, -STAND_OVER);
                stand_var = dl * fs - dab_lean_s * dab_k;
            }
            else stand_var = 0.0;
            return dl;
        }

        /// where a foot stands on the ground beside the bike (world): `side` (-1 left / +1 right) at `out_` from the middle,
        /// DAB_FWD ahead of the bottom bracket, the sole just on the drawn ground; n = the ground's normal there
        public Vec3 Ground(Vec3 bb, Vec3 fwd, Vec3 rgt, double side, double out_, out Vec3 n)
        {
            Vec3 g = bb + rgt * (side * out_) + fwd * DAB_FWD;
            g = new Vec3(g.x, Top(g.x, g.z) + 0.012, g.z);
            const double e = 0.08;
            double gx = Top(g.x + e, g.z) - Top(g.x - e, g.z);
            double gz = Top(g.x, g.z + e) - Top(g.x, g.z - e);
            n = new Vec3(-gx, 2.0 * e, -gz).normalized();
            return g;
        }

        /// at a stop, looking back over a shoulder past HAND_HIP_YAW the hand on that side goes to the hip (eased)
        public void update_hand_hip(double dt)
        {
            bool want = dab_k > 0.9 && Math.Abs(look_yaw) > HAND_HIP_YAW;
            if (want && hand_hip <= 0.01) hand_hip_side = look_yaw > 0.0 ? -1.0 : 1.0;
            hand_hip = move_toward(hand_hip, want ? 1.0 : 0.0, Math.Min(dt, 0.05) / 0.35);
        }

        public double stop_stand => stop_mode == 1 ? smooth01(stop_w) * dab_k : 0.0;
        public double stop_sit => stop_mode == 2 ? smooth01(stop_w) * dab_k : 0.0;
        public double look_twist => clamp(look_yaw * LOOK_TWIST, -0.7, 0.7) * dab_k;
    }
}
