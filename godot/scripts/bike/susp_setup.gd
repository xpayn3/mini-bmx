class_name SuspSetup
extends RefCounted
## Suspension as parts with a setup, the way a real bike has it: a FORK and a REAR SHOCK, each its own unit with a
## spring (air or coil), travel, sag and a damper (low- / high-speed compression, rebound), plus the tyres' pressure.
## The ride physics (BikePhysics._step_vertical) reads only the numbers `resolve()` returns, so anything that can make
## a unit (the garage, a shop, a rider's own tuning, a preset) plugs in here.
##
## A unit, as stored in a build / sold in a shop (plain data):
##   spring   "air" | "coil"   air ramps up towards the end of its travel (more with volume spacers) and has a little
##                             seal friction; coil is linear and supple on small bumps
##   travel   mm of wheel travel
##   sag      % of the travel the bike sits into under the rider (air: by pressure, coil: by spring rate)
##   tokens   0..4 volume spacers (air) / bottom-out bumper size (coil): how hard the end of the travel ramps
##   lsc, hsc, reb   0..CLICKS damper clicks (CLICK_MID = the middle): low-speed compression (support, brake dive,
##                   pedal bob), high-speed compression (big hits), rebound (how fast it comes back)
##   adj      which of those the damper really has ("lsc", "hsc", "reb"); the others sit at their middle setting
##   kg       its weight
## Everything in the physics is per unit of the whole (rider + bike) mass, like the rest of the ride.

const CLICKS := 10
const CLICK_MID := 5
const SAG_MIN := 15.0
const SAG_MAX := 40.0
const PSI_MIN := 14.0
const PSI_MAX := 40.0
const PSI_REF := 25.0   # the pressure the tyre values in Tune are for

## rear shocks (made-up brands, like every part). damper: what can be adjusted
const SHOCK_MODELS := {
	"coil_dh":   {"brand": "KOMODO",    "label": "KX2 Coil",        "spring": "coil", "adj": ["lsc", "hsc", "reb"], "kg": 0.95,
		"note": "Coil, fully adjustable. Supple and consistent; the downhill standard."},
	"coil_basic": {"brand": "STONEWALL", "label": "Anvil R",         "spring": "coil", "adj": ["reb"], "kg": 0.9,
		"note": "Coil, rebound only. Simple, hard to get wrong."},
	"air_dh":    {"brand": "NORDLUND",  "label": "NL Air X2",       "spring": "air",  "adj": ["lsc", "hsc", "reb"], "kg": 0.6,
		"note": "Air, fully adjustable. Lighter, ramps up at the end, pops and pumps harder."},
	"air_trail": {"brand": "QVX",       "label": "Vapor Trail",     "spring": "air",  "adj": ["lsc", "reb"], "kg": 0.48,
		"note": "Light air shock. No high-speed adjuster."},
	"hydro_pro": {"brand": "AXT",       "label": "Hydra Pro",       "spring": "coil", "adj": ["lsc", "hsc", "reb"], "kg": 1.05,
		"note": "Coil with a hydraulic bottom-out: takes the biggest hits."},
}
const DEFAULT_SHOCK := "coil_dh"

## the setup keys of a build's `suspension` dictionary and their stock values
const DEFAULTS := {
	"fork_sag": 28, "fork_tokens": 1, "fork_lsc": 5, "fork_hsc": 5, "fork_reb": 5,
	"shock_model": "coil_dh", "shock_sag": 30, "shock_tokens": 1, "shock_lsc": 5, "shock_hsc": 5, "shock_reb": 5,
	"psi_f": 23, "psi_r": 26,
}

## a build's setup value (old saves have the 3-step spring / rebound choices instead: those are carried over)
static func val(s: Dictionary, key: String) -> Variant:
	if s.has(key): return s[key]
	match key:
		"fork_sag": return [32, 28, 24][clampi(int(s.get("fork_spring", 1)), 0, 2)]
		"shock_sag": return [34, 30, 26][clampi(int(s.get("shock_spring", 1)), 0, 2)]
		"fork_reb", "shock_reb": return [7, 5, 3][clampi(int(s.get("rebound", 1)), 0, 2)]
	return DEFAULTS[key]

## can this unit's damper be adjusted there? ("lsc" / "hsc" / "reb")
static func has_adj(adj: Array, what: String) -> bool:
	return adj.has(what)

## one end's physical numbers from its parts and setup
##   spring, travel_mm, sag_pct, tokens, lsc / hsc / reb clicks, adj (which clicks count), extra bottom-out
static func unit(spring: String, travel_mm: float, sag_pct: float, tokens: int, lsc: int, hsc: int, reb: int, adj: Array, hydro_stop := false) -> Dictionary:
	var air := spring == "air"
	if not adj.has("lsc"): lsc = CLICK_MID
	if not adj.has("hsc"): hsc = CLICK_MID
	if not adj.has("reb"): reb = CLICK_MID
	var tok := clampi(tokens, 0, 4)
	return {
		"air": air,
		"travel": clampf(travel_mm, 60.0, 260.0) / 1000.0,
		"sag": clampf(sag_pct, SAG_MIN, SAG_MAX) / 100.0,
		# how much the spring rate has climbed by the end of the travel: F = k x (1 + prog (x / travel)^2)
		"prog": (0.4 + 0.22 * tok) if air else (0.04 + 0.03 * tok),
		# damping, as a share of critical for that end: low-speed compression, rebound
		"zc": 0.16 + 0.038 * clampi(lsc, 0, CLICKS),
		"zr": 0.25 + 0.06 * clampi(reb, 0, CLICKS),
		# past the shaft speed where the shim stack opens, this share of the low-speed rate is left
		"hs": 0.22 + 0.055 * clampi(hsc, 0, CLICKS),
		# seal / bushing friction (in g of that end's load): air springs have more, so they are less supple
		"fric": 0.05 if air else 0.018,
		# the bump stop over the last of the travel (rate x this at the very end)
		"bump": (5.0 + 1.0 * tok) * (1.6 if hydro_stop else 1.0),
	}

## a garage build -> {f, r (units), psi_f, psi_r, kg (fork + shock)}
static func resolve(b: Dictionary) -> Dictionary:
	var s: Dictionary = b.get("suspension", {})
	var fm: Dictionary = BikeBuild.FORK_MODELS.get(str(s.get("fork_model", "")), {})
	var sm: Dictionary = SHOCK_MODELS.get(str(val(s, "shock_model")), SHOCK_MODELS[DEFAULT_SHOCK])
	var f_adj: Array = fm.get("adj", ["lsc", "hsc", "reb"])
	var f_spring := "coil" if str(fm.get("spring", "Air")).to_lower() == "coil" else "air"
	var w: Dictionary = b.get("wheels", {})
	return {
		"f": unit(f_spring, float(s.get("fork_travel", 200)), float(val(s, "fork_sag")), int(val(s, "fork_tokens")),
			int(val(s, "fork_lsc")), int(val(s, "fork_hsc")), int(val(s, "fork_reb")), f_adj),
		"r": unit(str(sm.spring), float(s.get("shock_travel", 200)), float(val(s, "shock_sag")), int(val(s, "shock_tokens")),
			int(val(s, "shock_lsc")), int(val(s, "shock_hsc")), int(val(s, "shock_reb")), sm.adj, str(val(s, "shock_model")) == "hydro_pro"),
		"psi_f": clampf(float(w.get("psi_f", DEFAULTS.psi_f)), PSI_MIN, PSI_MAX),
		"psi_r": clampf(float(w.get("psi_r", DEFAULTS.psi_r)), PSI_MIN, PSI_MAX),
		"shock_kg": float(sm.kg),
	}

## a spring's force at compression x (m), per unit of rate k: x (1 + prog (x / travel)^2)
static func curve(x: float, travel: float, prog: float) -> float:
	var u := x / maxf(travel, 0.01)
	return x * (1.0 + prog * u * u)

## the compression (m) at which a spring of rate k carries `load`
static func rest(load: float, k: float, travel: float, prog: float) -> float:
	var kk := maxf(k, 1e-6)
	var it := 1.0 / maxf(travel, 0.01)
	var x := load / kk
	for _i in 3:
		var u := minf(x * it, 1.5)
		x = load / (kk * (1.0 + prog * u * u))
	return minf(x, travel)

## what a setup feels like, in words (the garage's note under the sliders)
static func describe(u: Dictionary) -> String:
	var bits := []
	bits.append("air spring, ramps up" if u.air else "coil spring, linear")
	bits.append("%d %% sag" % roundi(float(u.sag) * 100.0))
	bits.append("soft" if float(u.sag) > 0.31 else ("firm" if float(u.sag) < 0.25 else "balanced"))
	if float(u.zr) > 0.62: bits.append("slow rebound (planted)")
	elif float(u.zr) < 0.48: bits.append("fast rebound (lively)")
	return ", ".join(bits)
