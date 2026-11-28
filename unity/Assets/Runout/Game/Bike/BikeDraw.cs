using System.Collections.Generic;
using Runout.Config;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// The drawn bike each frame, as godot/scripts/game/game.gd _process draws it (ported line for line, drawing only):
    /// the physics interpolated between its last two steps, small slip drawn along the travel, the motion cap on lean and
    /// bars, the drawn bars (_bar_draw: head-angle correction, countersteer, the knock kick, tabletop / carve / manual
    /// bars), BikeRig.pose, the pivot fix (the axle carrying the bike where the physics has it), the wheels fitted to the
    /// ground through the suspension, and the tyre lift out of the ground, eased.
    /// Not ported yet (they need the rider / crash parts): the dab / foot-out / idle life, the rider's air share, the
    /// crashed bike's body.
    public sealed class BikeDraw : MonoBehaviour
    {
        public BikeSim st;
        public IGround ground;
        public BikeRig rig;

        // the physics state the drawing interpolates (Godot: _prev + _lerp_k)
        double _px, _py, _pz, _pyd, _ppd, _ph, _pby, _pp;
        float t;

        public void Init(BikeSim sim, IGround g, BikeRig r, FixedStepper stepper)
        {
            st = sim; ground = g; rig = r;
            Snap();
            stepper.BeforeStep += Snap;
            stepper.AfterStep += () => _bar_tick(st);
        }

        void Snap()
        {
            _px = st.x; _py = st.y; _pz = st.z; _pyd = st.y_draw; _ppd = st.pitch_draw; _ph = st.heading; _pby = st.body_y; _pp = st.pitch;
        }

        double L(double prev, double cur, double a) => prev + (cur - prev) * a;

        const float LIFT_UP = 2.4f, LIFT_DOWN = 0.6f, LIFT_AIR = 1.5f;
        float _slip_k, _piv_w = 0.5f, _piv_c, _lift_s;
        float _lean_c, _steer_c;

        public void Draw(double alpha, float dt)
        {
            if (st == null || rig == null) return;
            dt = Mathf.Min(dt, 0.1f);
            t += dt;
            double a = alpha;
            if (new Vector2((float)(st.x - _px), (float)(st.z - _pz)).magnitude > 2f) a = 1.0;
            float y_draw = (float)(st.crash_on ? L(_py, st.y, a) : L(_pyd, st.y_draw, a));
            // wrapped interpolation: mid-flip the pitch jumps +PI -> -PI between two steps
            double pPrev = st.crash_on ? _pp : _ppd, pCur = st.crash_on ? st.pitch : st.pitch_draw;
            float p_draw = (float)Gd.wrapf(pPrev + BikeSim.ang_diff(pCur, pPrev) * a, -Gd.PI, Gd.PI);
            float hd = (float)(_ph + BikeSim.ang_diff(st.heading, _ph) * a);
            // a small slip nobody asked for is drawn 80 % along the travel (real slides / whips in full)
            float sk_t = 0f;
            if (!st.air && !st.crash_on)
                sk_t = (1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.10f, 0.20f, Mathf.Abs((float)st.slip))))
                       * (1f - Mathf.Clamp01((float)st.whip * 3f)) * (1f - Mathf.Clamp01((float)st.rear_lock / 0.15f));
            _slip_k = Mathf.MoveTowards(_slip_k, sk_t, 4f * Mathf.Min(dt, 0.05f));
            hd -= Mathf.Clamp((float)st.slip, -0.25f, 0.25f) * 0.8f * _slip_k;
            Vector3 drawn_pos = new Vector3((float)L(_px, st.x, a), (float)L(_py, st.y, a), (float)L(_pz, st.z, a));
            float wobble = Mathf.Sin(t * 2.3f) * 0.025f * Mathf.Max(0f, 1f - Mathf.Abs((float)st.v) / 2f);
            float dab_lean = 0f;
            if (st.crash_on) _mc.Clear();
            float mdt = Mathf.Min(Time.deltaTime, 0.05f);
            _lean_c = _mcap("bike_lean", (float)st.bike_lean, mdt);
            _steer_c = _mcap("steer", _bar_draw(st, mdt, dab_lean) + (float)st.bar_catch, mdt);
            rig.pose(drawn_pos.x, y_draw, drawn_pos.z, hd, p_draw, (float)st.hop_nose,
                _lean_c + (float)st.rock + wobble + dab_lean, _steer_c - wobble * 1.5f, (float)st.wheel_f, (float)st.wheel_r, (float)st.crank);
            // the drawn bike moved so the axle carrying it is where the physics has it (back wheel / nose / both / in the air)
            if (!st.crash_on && rig.wheel_f != null && rig.wheel_r != null)
            {
                Vector3 lr = rig.PitchLocal(GodotSpace.WorldPos(rig.wheel_r));
                Vector3 lf = rig.PitchLocal(GodotSpace.WorldPos(rig.wheel_f));
                float sp = Mathf.Sin(p_draw), cp = Mathf.Cos(p_draw);
                float c_r = (-(float)st.BB_REAR * sp + lr.y) - (lr.x * sp + lr.y * cp);
                float c_f = ((float)(st.L - st.BB_REAR) * sp + lf.y) - (lf.x * sp + lf.y * cp);
                float w_t = 0.5f;
                if (st.air) w_t = Mathf.Clamp(0.5f + p_draw * 2f, 0f, 1f);
                else if (st.front_air && !st.rear_air) w_t = 1f;
                else if (st.rear_air && !st.front_air) w_t = 0f;
                _piv_w = Mathf.MoveTowards(_piv_w, w_t, 6f * mdt);
                float c_t = Mathf.Lerp(c_f, c_r, _piv_w);
                if (Mathf.Abs(p_draw) > 1.3f) c_t = 0f;   // (a flip: no ground to match)
                _piv_c = Mathf.Abs(c_t - _piv_c) < 0.6f ? Mathf.MoveTowards(_piv_c, c_t, 2.5f * mdt) : c_t;
                rig.position.y += _piv_c;
                rig.Place();
            }
            else _piv_c = 0f;
            // the physics' tyres follow the smooth ground; the drawn ground is a mesh with rocks: fit the wheels through the
            // suspension, then lift / tilt the drawn bike until no tyre is inside it (eased)
            if (!st.crash_on && rig.wheel_f != null && rig.wheel_r != null)
            {
                System.Func<double, double, double> top = ground.top_height;
                rig.fit_wheels(top);
                float pre_y = rig.position.y;
                rig.unclip_tyres(top);
                float need = rig.position.y - pre_y;
                if (st.crash_on || Mathf.Abs(need - _lift_s) > 0.5f) _lift_s = need;
                else if (st.air && need < _lift_s) _lift_s = Mathf.Max(need, _lift_s - LIFT_AIR * mdt);
                else if (need > _lift_s) _lift_s = Mathf.Min(need, _lift_s + LIFT_UP * mdt);
                else _lift_s = Mathf.Max(need, _lift_s - LIFT_DOWN * mdt);
                rig.position.y = pre_y + _lift_s;
                rig.Place();
            }
        }

        // ---- motion cap (Godot: _mcap / MCAP) ----
        static readonly Dictionary<string, Vector2> MCAP = new Dictionary<string, Vector2>
        {
            ["bike_lean"] = new Vector2(10f, 160f), ["steer"] = new Vector2(9f, 200f), ["counter"] = new Vector2(7f, 110f),
            ["body_roll"] = new Vector2(6f, 100f), ["head_roll"] = new Vector2(8f, 120f), ["lat_g"] = new Vector2(6f, 80f),
            ["hip_shift"] = new Vector2(1.6f, 30f), ["absorb"] = new Vector2(5f, 220f), ["body_stick"] = new Vector2(6f, 80f),
        };
        readonly Dictionary<string, Vector2> _mc = new Dictionary<string, Vector2>();

        float _mcap(string key, float target, float dt)
        {
            float mc = Mathf.Max(0.2f, (float)st.T.get("motionCap", 1.0));
            Vector2 lim = MCAP[key] * mc;
            bool had = _mc.TryGetValue(key, out var s);
            if (float.IsNaN(target) || float.IsInfinity(target)) return had ? s.x : 0f;
            if (!had || float.IsNaN(s.x) || float.IsNaN(s.y)) { _mc[key] = new Vector2(target, 0f); return target; }
            const float w = 60f;
            int n = Mathf.Max(1, Mathf.CeilToInt(dt * 240f));
            float h = dt / n;
            for (int i = 0; i < n; i++)
            {
                float acc = Mathf.Clamp((target - s.x) * w * w - 2f * w * s.y, -lim.y, lim.y);
                s.y = Mathf.Clamp(s.y + acc * h, -lim.x, lim.x);
                s.x = s.x + s.y * h;
            }
            if (Mathf.Abs(target - s.x) > lim.x * 0.1f) s.x = target - Mathf.Sign(target - s.x) * lim.x * 0.1f;
            _mc[key] = s;
            return s.x;
        }

        // ---- the drawn bars (Godot: _bar_draw / _bar_tick) ----
        const float HEAD_TILT = 0.47f, BAR_CS_K = 0.03f, BAR_CS_MAX = 0.07f, BAR_KICK_HZ = 7f, BAR_KICK_Z = 0.25f, BAR_KICK_K = 0.07f;
        const float BAR_FLOP = 0.6f, BAR_HIT_FROM = 1f, BAR_HIT_K = 0.6f, BAR_TABLE = 0.4f;
        float _vwf_prev, _bar_kick, _bar_kick_v, _bar_hit, _bar_carve;
        double _carve_seen;

        void _bar_tick(BikeSim s)
        {
            float dvw = (float)s.vw_f - _vwf_prev;
            _vwf_prev = (float)s.vw_f;
            if (s.air || s.crash_on || Mathf.Abs(dvw) <= BAR_HIT_FROM) return;
            float side = Mathf.Abs((float)s.knock) > 0.02f ? Mathf.Sign((float)s.knock) : (Mathf.Sin((float)(s.x * 7.3 + s.z * 3.1)) > 0f ? 1f : -1f);
            _bar_hit += side * (Mathf.Abs(dvw) - BAR_HIT_FROM) * BAR_HIT_K * Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(2f, 6f, Mathf.Abs((float)s.v)));
        }

        float _bar_draw(BikeSim s, float dt, float dab_lean)
        {
            if (s.crash_on) { _bar_kick = 0f; _bar_kick_v = 0f; _bar_hit = 0f; return (float)s.steer; }
            float ln = Mathf.Clamp((float)s.bike_lean, -1.3f, 1.3f);
            float sd = Mathf.Atan(Mathf.Tan(Mathf.Clamp((float)s.steer, -1.2f, 1.2f)) * Mathf.Cos(ln) / Mathf.Cos(HEAD_TILT));
            float va = Mathf.Abs((float)s.v);
            if (!s.air) sd -= Mathf.Clamp((float)s.lean_v * BAR_CS_K, -BAR_CS_MAX, BAR_CS_MAX) * Sm(3f, 7f, va);
            float w = 2f * Mathf.PI * BAR_KICK_HZ;
            int steps = Mathf.Max(1, Mathf.CeilToInt(dt * 240f));
            float h = dt / steps;
            float push = s.air ? 0f : (float)s.knock * BAR_KICK_K;
            _bar_kick_v += _bar_hit; _bar_hit = 0f;
            for (int i = 0; i < steps; i++)
            {
                _bar_kick_v += (-w * w * (_bar_kick - push) - 2f * BAR_KICK_Z * w * _bar_kick_v) * h;
                _bar_kick += _bar_kick_v * h;
            }
            _bar_kick = Mathf.Clamp(_bar_kick, -0.08f, 0.08f);
            sd += _bar_kick;
            sd += BAR_FLOP * dab_lean;
            if (s.air) sd -= Mathf.Clamp((float)s.bike_lean * BAR_TABLE, -0.5f, 0.5f) * (float)s.air_k;   // a tabletop's bars
            float bc = (float)s.T.get("barCarve", 0.5);
            if (bc > 0f)
            {
                if (s.carve_now != _carve_seen) { _carve_seen = s.carve_now; _bar_carve = (float)s.carve_now; }
                _bar_carve -= _bar_carve * Mathf.Min(1f, dt * 4.5f);
                float inair = s.air ? (float)(s._air_steer_s + s._air_aim_s) * 0.4f : 0f;
                sd += (inair + _bar_carve * 0.8f) * bc;
            }
            else _bar_carve = 0f;
            if (s.man_lk > 0.0)
                sd = Mathf.Lerp(sd, Mathf.Clamp((float)s.steer_in, -1f, 1f) * (float)BikeSim.MAN_BAR + _bar_kick, (float)s.man_lk);
            return sd;
        }

        /// Godot's smoothstep(from, to, x)
        static float Sm(float a, float b, float x) { float u = Mathf.Clamp01((x - a) / (b - a)); return u * u * (3f - 2f * u); }
    }
}
