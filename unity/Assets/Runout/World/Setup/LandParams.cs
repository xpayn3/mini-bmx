using System;
using System.Collections.Generic;
using System.Globalization;
using static Runout.Sim.Gd;

namespace Runout.World
{
    /// The Land Lab's knobs (port of godot/scripts/world/land_params.gd): defaults, the saved file's overrides, and
    /// Apply() = the values the field reads (TerrainField._land_from keys) + the start mountain's pitches.
    public static class LandParams
    {
        // key, default (min / max / labels live in the Godot editor tab; a Unity editor for them can come later)
        public static readonly (string key, double def)[] DEFS =
        {
            ("start_peak", 1.0), ("start_top", 450.0), ("start_len", 2800.0), ("snow_h", 280.0), ("land_scale", 1.0),
            ("big_h", 16.0), ("big_p", 240.0), ("ridge_h", 14.0), ("ridge_p", 150.0), ("region_p", 700.0),
            ("mid_h", 10.0), ("mid_p", 90.0), ("fine_h", 3.2), ("fine_p", 28.0), ("relief", 1.3), ("relief_p", 260.0),
            ("warp", 38.0), ("warp_p", 170.0), ("talus", 0.30), ("detail_s", 0.30), ("fine_s", 0.55),
            ("rough_p", 2600.0), ("macro_p", 1800.0), ("valley_flat", 0.65), ("valley_macro", 0.40), ("valley_p", 420.0),
            ("strata", 0.7), ("strata_step", 3.2), ("peak_h", 140.0), ("peak_p", 700.0), ("peak_region", 3000.0),
            ("peak_near", 60.0), ("peak_far", 300.0), ("eros_h", 6.0), ("eros_c", 48.0), ("eros_sp", 0.5),
            ("valley_d", 10.0), ("valley_w", 45.0), ("valley_sp", 1100.0), ("bed_d", 1.2), ("bed_w", 4.0),
        };

        public static Dictionary<string, double> Defaults()
        {
            var d = new Dictionary<string, double>();
            foreach (var e in DEFS) d[e.key] = e.def;
            return d;
        }

        /// defaults + a land_params.json ({"key": number, ...}; unknown keys ignored)
        public static Dictionary<string, double> FromJson(string json)
        {
            var v = Defaults();
            if (string.IsNullOrEmpty(json)) return v;
            foreach (var part in json.Trim().Trim('{', '}').Split(','))
            {
                var kv = part.Split(':');
                if (kv.Length != 2) continue;
                string k = kv[0].Trim().Trim('"');
                if (v.ContainsKey(k) && double.TryParse(kv[1].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var x))
                    v[k] = x;
            }
            return v;
        }

        /// knob values -> what the field reads (the same names as TerrainField's statics) + PITCH_N / PITCH_K (setup only)
        public static Dictionary<string, double> Apply(Dictionary<string, double> v)
        {
            double k = v["land_scale"];
            var o = new Dictionary<string, double>
            {
                ["L_A240"] = v["big_h"] * k, ["L_ARDG"] = v["ridge_h"] * k, ["L_A90"] = v["mid_h"] * k, ["L_A28"] = v["fine_h"] * k,
                ["L_REL"] = v["relief"],
                ["L_I240"] = 1.0 / v["big_p"], ["L_I150"] = 1.0 / v["ridge_p"], ["L_I700"] = 1.0 / v["region_p"],
                ["L_I90"] = 1.0 / v["mid_p"], ["L_I28"] = 1.0 / v["fine_p"], ["L_I260"] = 1.0 / v["relief_p"], ["L_I170"] = 1.0 / v["warp_p"],
                ["LAND_WARP"] = v["warp"], ["LAND_TALUS"] = v["talus"], ["LAND_DETAIL_S"] = v["detail_s"], ["LAND_FINE_S"] = v["fine_s"],
                ["LAND_CR"] = 1.0 / v["rough_p"], ["LAND_CM"] = 1.0 / v["macro_p"],
                ["LAND_VALLEY_FLAT"] = v["valley_flat"], ["LAND_VALLEY_MACRO"] = v["valley_macro"], ["LAND_VI"] = 1.0 / v["valley_p"],
                ["LAND_STRATA"] = v["strata"], ["LAND_STRATA_STEP"] = v["strata_step"],
                ["PK_H"] = v["peak_h"], ["PK_I"] = 1.0 / v["peak_p"], ["PK_RI"] = 1.0 / v["peak_region"], ["PK_NEAR"] = v["peak_near"],
                ["PK_FAR"] = maxf(v["peak_far"], v["peak_near"] + 1.0),
                ["ER_H"] = v["eros_h"], ["ER_C"] = v["eros_c"], ["ER_SP"] = v["eros_sp"],
                ["VL_D"] = v["valley_d"], ["VL_W"] = v["valley_w"], ["VL_I"] = 1.0 / v["valley_sp"], ["VL_BD"] = v["bed_d"], ["VL_BW"] = v["bed_w"],
            };
            double sk = clampf(v["start_peak"], 0.0, 1.0);
            o["START_K"] = sk;
            o["HILL_TOP"] = lerpf(105.0, v["start_top"], sk);
            o["HILL_LEN"] = lerpf(1400.0, v["start_len"], sk);
            o["RANGE_X0"] = lerpf(2100.0, v["start_len"] + 700.0, sk);
            o["PITCH_N"] = roundi(lerpf(5.0, 9.0, sk));
            o["PITCH_K"] = lerpf(1.0, 84.0 / v["start_top"], sk);
            o["SNOW_H"] = v["snow_h"];
            return o;
        }
    }
}
