using System;
using System.Collections.Generic;

namespace Runout.Sim
{
    public readonly struct TuneRow
    {
        public readonly string group, key, label, unit;
        public readonly double def, min, max, step;
        public TuneRow(string group, string key, string label, double def, double min, double max, double step, string unit)
        { this.group = group; this.key = key; this.label = label; this.def = def; this.min = min; this.max = max; this.step = step; this.unit = unit; }
    }

    /// Ride-feel tuning: port of godot/scripts/core/tune.gd (the Tune autoload) without the saving / UI.
    /// v = the effective values the physics reads: the player's slider (base) x the bike's multiplier (ride) x the Feel
    /// macro sliders, plus the FOLLOW values that track a leader slider. The host loads / saves `base` where it likes.
    public sealed class Tune
    {
        public readonly Dictionary<string, double> defaults = new Dictionary<string, double>();
        public readonly Dictionary<string, double> @base = new Dictionary<string, double>();
        public Dictionary<string, double> ride = new Dictionary<string, double>();
        public readonly Dictionary<string, double> v = new Dictionary<string, double>();
        public event Action changed;
        static readonly Dictionary<string, TuneRow> _rows = new Dictionary<string, TuneRow>();

        /// key -> [default, leader key ("" = fixed), exponent]
        public static readonly Dictionary<string, (double def, string lead, double exp)> FOLLOW = new Dictionary<string, (double, string, double)>
        {
            ["brakeForce"] = (13.0, "", 0.0),
            ["steerRate"] = (15.0, "steerEase", 1.0), ["steerRelease"] = (10.0, "steerEase", 1.0), ["barSpeed"] = (28.0, "steerEase", 1.0),
            ["gripCatch"] = (0.6, "slipRecover", 1.0),
            ["reflexBrake"] = (0.6, "", 0.0), ["reflexStandUp"] = (0.3, "", 0.0), ["reflexCatch"] = (1.5, "", 0.0),
            ["leanIn"] = (40.0, "leanRate", 1.0), ["leanOut"] = (30.0, "leanRate", 1.0), ["gyroStable"] = (0.25, "", 0.0),
            ["popPower"] = (2.4, "popKick", 1.0),
            ["antiSquat"] = (0.9, "", 0.0), ["shockProg"] = (1.0, "", 0.0),
            ["pumpCentred"] = (0.75, "", 0.0), ["pumpMinSpeed"] = (2.0, "", 0.0),
            ["airSpinResp"] = (7.0, "airSpinRate", 1.0), ["airSpinStop"] = (3.0, "airSpinRate", 1.0),
            ["stickSpinBuild"] = (5.5, "stickAirEase", 1.0), ["stickSpinGrow"] = (0.4, "", 0.0), ["stickSpinMax"] = (0.7, "", 0.0),
            ["whipSnap"] = (5.0, "whipDrift", 1.0), ["whipLean"] = (0.22, "whipDrift", 1.0), ["whipCarry"] = (0.6, "", 0.0),
            ["whipCatch"] = (0.9, "", 0.0), ["whipMinSpeed"] = (4.0, "", 0.0),
        };

        /// the Feel sliders: macro key -> {detail key: exponent}
        public static readonly Dictionary<string, Dictionary<string, double>> MACROS = new Dictionary<string, Dictionary<string, double>>
        {
            ["feelGrip"] = new Dictionary<string, double> { ["grip"] = 0.6, ["frontGrip"] = 0.4, ["slipRecover"] = 0.6, ["gripLoose"] = -1.0, ["carveGrip"] = 0.5 },
            ["feelAgile"] = new Dictionary<string, double> { ["steerEase"] = 0.8, ["leanIn"] = 0.8, ["leanOut"] = 0.8, ["leanRate"] = 0.7, ["flickSpeed"] = 0.8, ["barSpeed"] = 0.5, ["gyroStable"] = -1.0, ["turnWeight"] = -1.0 },
            ["feelSlide"] = new Dictionary<string, double> { ["oversteer"] = 1.2, ["gripRearLock"] = 1.0, ["gripBumps"] = 1.0, ["gripPower"] = 1.0, ["slipRecover"] = -0.8, ["whipDrift"] = 0.6 },
            ["feelReal"] = new Dictionary<string, double> { ["balanceSim"] = 1.2, ["balanceFall"] = 1.2, ["camberPull"] = 1.2, ["groundKnock"] = 1.2, ["cornerLoad"] = 1.0, ["weightInside"] = 1.0, ["airArcade"] = -1.5, ["frontWashAt"] = -0.4 },
            ["feelSpeed"] = new Dictionary<string, double> { ["topSpeed"] = 0.5, ["pedalPower"] = 0.6, ["pedalTop"] = 0.5, ["sprintTop"] = 0.6, ["airDrag"] = -0.4 },
            ["feelFlow"] = new Dictionary<string, double> { ["flowCarry"] = 1.0, ["carveBoost"] = 1.0, ["pumpLegs"] = 0.8, ["flowTime"] = 0.8, ["rollRes"] = -0.8 },
            ["feelAir"] = new Dictionary<string, double> { ["popKick"] = 0.6, ["popPower"] = 0.5, ["airSpinRate"] = 0.8, ["airTilt"] = 0.6, ["airTwist"] = 0.6, ["flipRate"] = 0.6, ["flipAccel"] = 0.6, ["stickAirEase"] = 0.5, ["slamJolt"] = 0.6 },
            ["feelAirFlow"] = new Dictionary<string, double> { ["airSteer"] = 0.8, ["airAim"] = 0.8, ["airPrelean"] = 0.5, ["landCarve"] = 0.4, ["landSwapRate"] = 0.8, ["camHeadingRate"] = 0.3 },
            ["feelPlush"] = new Dictionary<string, double> { ["tyreHz"] = -0.6, ["travel"] = 0.6, ["damperKnee"] = -0.5, ["damperBlow"] = -0.6, ["legStiff"] = -0.5, ["tyreDamp"] = 0.3 },
        };
        static Dictionary<string, List<(string m, double e)>> _macro_of;

        public Tune()
        {
            if (_rows.Count == 0) foreach (var r in TuneDefs.Rows) _rows[r.key] = r;
            foreach (var r in TuneDefs.Rows) { defaults[r.key] = r.def; @base[r.key] = r.def; }
            rebuild();
        }

        /// GDScript `T.get("key", d)`
        public double get(string key, double d)
        {
            return v.TryGetValue(key, out var x) ? x : d;
        }

        /// GDScript `T.key` (an unknown key is a porting bug: fail loudly)
        public double this[string key]
        {
            get
            {
                if (v.TryGetValue(key, out var x)) return x;
                throw new KeyNotFoundException("Tune key '" + key + "' is not defined (godot/scripts/core/tune.gd DEFS / FOLLOW)");
            }
        }

        public static bool row(string key, out TuneRow r) => _rows.TryGetValue(key, out r);

        /// load effective values as they are (a Godot reference trace's Tune.v): no rebuild, no multipliers
        public void set_effective(IDictionary<string, double> values)
        {
            foreach (var kv in values) v[kv.Key] = kv.Value;
            changed?.Invoke();
        }

        public void set_ride(Dictionary<string, double> mult) { ride = mult ?? new Dictionary<string, double>(); rebuild(); }
        public void set_value(string k, double val) { @base[k] = val; rebuild(); }
        public void apply_values(IDictionary<string, double> d) { foreach (var kv in d) if (defaults.ContainsKey(kv.Key)) @base[kv.Key] = kv.Value; rebuild(); }
        public void reset_defaults() { foreach (var kv in defaults) @base[kv.Key] = kv.Value; rebuild(); }

        public double macro_k(string k)
        {
            if (_macro_of == null)
            {
                _macro_of = new Dictionary<string, List<(string, double)>>();
                foreach (var m in MACROS)
                    foreach (var dk in m.Value)
                    {
                        if (!_macro_of.TryGetValue(dk.Key, out var l)) _macro_of[dk.Key] = l = new List<(string, double)>();
                        l.Add((m.Key, dk.Value));
                    }
            }
            double f = 1.0;
            if (_macro_of.TryGetValue(k, out var list))
                foreach (var me in list)
                    f *= Math.Pow(Math.Max(0.05, @base.TryGetValue(me.m, out var b) ? b : 1.0), me.e);
            return f;
        }

        public void rebuild()
        {
            foreach (var kv in @base)
            {
                double raw = kv.Value * (ride.TryGetValue(kv.Key, out var rm) ? rm : 1.0);
                double f = macro_k(kv.Key);
                if (f != 1.0)
                {
                    double val = raw * f;
                    if (_rows.TryGetValue(kv.Key, out var r)) val = Gd.clampf(val, Math.Min(raw, r.min), Math.Max(raw, r.max));
                    raw = val;
                }
                v[kv.Key] = raw;
            }
            foreach (var kv in FOLLOW)
            {
                var fw = kv.Value;
                double lead = 1.0;
                if (fw.lead != "" && defaults.TryGetValue(fw.lead, out var ld))
                    lead = Math.Pow(Math.Max(1e-4, (@base.TryGetValue(fw.lead, out var lb) ? lb : ld) / Math.Max(1e-4, ld)), fw.exp);
                v[kv.Key] = fw.def * lead * (ride.TryGetValue(kv.Key, out var rm) ? rm : 1.0) * macro_k(kv.Key);
            }
            changed?.Invoke();
        }
    }
}
