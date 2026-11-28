using System;
using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.Sim
{
    /// Suspension as parts with a setup (port of godot/scripts/bike/susp_setup.gd): a FORK and a REAR SHOCK, each a unit with
    /// spring (air / coil), travel, sag, volume spacers and damper clicks, plus the tyres' pressure. The physics reads only
    /// what `unit` / `resolve` return. Everything per unit of the whole (rider + bike) mass.
    public static class SuspSetup
    {
        public const int CLICKS = 10;
        public const int CLICK_MID = 5;
        public const double SAG_MIN = 15.0, SAG_MAX = 40.0;
        public const double PSI_MIN = 14.0, PSI_MAX = 40.0;
        public const double PSI_REF = 25.0;

        public sealed class Unit
        {
            public bool air;
            public double travel, sag, prog, zc, zr, hs, fric, bump;
        }

        /// a bike's setup: null on a bike without one (the BMX: the single simple spring)
        public sealed class Setup
        {
            public Unit f, r;
            public double psi_f = 23, psi_r = 26, shock_kg = 0.95;
        }

        public sealed class ShockModel
        {
            public string brand, label, spring, note; public string[] adj; public double kg;
        }

        public static readonly Dictionary<string, ShockModel> SHOCK_MODELS = new Dictionary<string, ShockModel>
        {
            ["coil_dh"] = new ShockModel { brand = "KOMODO", label = "KX2 Coil", spring = "coil", adj = new[] { "lsc", "hsc", "reb" }, kg = 0.95, note = "Coil, fully adjustable. Supple and consistent; the downhill standard." },
            ["coil_basic"] = new ShockModel { brand = "STONEWALL", label = "Anvil R", spring = "coil", adj = new[] { "reb" }, kg = 0.9, note = "Coil, rebound only. Simple, hard to get wrong." },
            ["air_dh"] = new ShockModel { brand = "NORDLUND", label = "NL Air X2", spring = "air", adj = new[] { "lsc", "hsc", "reb" }, kg = 0.6, note = "Air, fully adjustable. Lighter, ramps up at the end, pops and pumps harder." },
            ["air_trail"] = new ShockModel { brand = "QVX", label = "Vapor Trail", spring = "air", adj = new[] { "lsc", "reb" }, kg = 0.48, note = "Light air shock. No high-speed adjuster." },
            ["hydro_pro"] = new ShockModel { brand = "AXT", label = "Hydra Pro", spring = "coil", adj = new[] { "lsc", "hsc", "reb" }, kg = 1.05, note = "Coil with a hydraulic bottom-out: takes the biggest hits." },
        };
        public const string DEFAULT_SHOCK = "coil_dh";

        /// the setup keys of a build's `suspension` and their stock values
        public static readonly Dictionary<string, double> DEFAULTS = new Dictionary<string, double>
        {
            ["fork_sag"] = 28, ["fork_tokens"] = 1, ["fork_lsc"] = 5, ["fork_hsc"] = 5, ["fork_reb"] = 5,
            ["shock_sag"] = 30, ["shock_tokens"] = 1, ["shock_lsc"] = 5, ["shock_hsc"] = 5, ["shock_reb"] = 5,
            ["psi_f"] = 23, ["psi_r"] = 26,
        };

        public static Unit unit(string spring, double travel_mm, double sag_pct, int tokens, int lsc, int hsc, int reb, IList<string> adj, bool hydro_stop = false)
        {
            bool air = spring == "air";
            if (!adj.Contains("lsc")) lsc = CLICK_MID;
            if (!adj.Contains("hsc")) hsc = CLICK_MID;
            if (!adj.Contains("reb")) reb = CLICK_MID;
            int tok = clampi(tokens, 0, 4);
            return new Unit
            {
                air = air,
                travel = clampf(travel_mm, 60.0, 260.0) / 1000.0,
                sag = clampf(sag_pct, SAG_MIN, SAG_MAX) / 100.0,
                prog = air ? (0.4 + 0.22 * tok) : (0.04 + 0.03 * tok),
                zc = 0.16 + 0.038 * clampi(lsc, 0, CLICKS),
                zr = 0.25 + 0.06 * clampi(reb, 0, CLICKS),
                hs = 0.22 + 0.055 * clampi(hsc, 0, CLICKS),
                fric = air ? 0.05 : 0.018,
                bump = (5.0 + 1.0 * tok) * (hydro_stop ? 1.6 : 1.0),
            };
        }

        /// a build's suspension values (keys as in the Godot garage build) -> the setup. fork_spring = "air" | "coil",
        /// fork_adj = the fork model's adjusters (null = all three)
        public static Setup resolve(IDictionary<string, double> s, string shock_model, string fork_spring, IList<string> fork_adj,
                                    double fork_travel = 200, double shock_travel = 200)
        {
            double val(string k) => s != null && s.TryGetValue(k, out var x) ? x : DEFAULTS[k];
            if (shock_model == null || !SHOCK_MODELS.TryGetValue(shock_model, out var sm)) { shock_model = DEFAULT_SHOCK; sm = SHOCK_MODELS[DEFAULT_SHOCK]; }
            var f_adj = fork_adj ?? new[] { "lsc", "hsc", "reb" };
            return new Setup
            {
                f = unit(fork_spring == "coil" ? "coil" : "air", fork_travel, val("fork_sag"), (int)val("fork_tokens"),
                    (int)val("fork_lsc"), (int)val("fork_hsc"), (int)val("fork_reb"), f_adj),
                r = unit(sm.spring, shock_travel, val("shock_sag"), (int)val("shock_tokens"),
                    (int)val("shock_lsc"), (int)val("shock_hsc"), (int)val("shock_reb"), sm.adj, shock_model == "hydro_pro"),
                psi_f = clampf(val("psi_f"), PSI_MIN, PSI_MAX),
                psi_r = clampf(val("psi_r"), PSI_MIN, PSI_MAX),
                shock_kg = sm.kg,
            };
        }

        /// a spring's force at compression x (m), per unit of rate k: x (1 + prog (x / travel)^2)
        public static double curve(double x, double travel, double prog)
        {
            double u = x / maxf(travel, 0.01);
            return x * (1.0 + prog * u * u);
        }

        /// the compression (m) at which a spring of rate k carries `load`
        public static double rest(double load, double k, double travel, double prog)
        {
            double kk = maxf(k, 1e-6);
            double it = 1.0 / maxf(travel, 0.01);
            double x = load / kk;
            for (int i = 0; i < 3; i++)
            {
                double u = minf(x * it, 1.5);
                x = load / (kk * (1.0 + prog * u * u));
            }
            return minf(x, travel);
        }
    }
}
