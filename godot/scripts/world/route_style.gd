class_name RouteStyle
extends RefCounted
## What kind of trail the world lays out (picked on the ride setup's ROUTE step, saved in user://route.cfg).
## All 1.0 = the original worlds, laid out exactly as before (a seed keeps its trail). Read by TerrainField.setup
## (a copy rides along on every fork) and by TrailCourse while it lays the trail out.
##   jumps   0 .. 2.5  how many jump lines + route features (0 = none, 1 = as before)
##   twist   0.3 .. 2  flowing sweepers (low) .. tight bends (high)
##   rolling 0 .. 2.5  the trail's own dips, ridges and cliff drops
##   grade   0.5 .. 1.7  how steep the mountains' falls are (their height x this; TerrainField.grade_k, mirrored in TerrainFieldCs)

const KEYS := ["jumps", "twist", "rolling", "grade", "biome"]
const DEFAULT := {"jumps": 1.0, "twist": 1.0, "rolling": 1.0, "grade": 1.0, "biome": 0.0}
const LIMITS := {"jumps": [0.0, 2.5], "twist": [0.3, 2.0], "rolling": [0.0, 2.5], "grade": [0.5, 1.7], "biome": [0.0, 4.0]}
const PRESETS := [
	["FLOW", {"jumps": 0.7, "twist": 0.45, "rolling": 0.8, "grade": 0.75}],
	["BALANCED", {"jumps": 1.0, "twist": 1.0, "rolling": 1.0, "grade": 1.0}],
	["JUMP PARK", {"jumps": 2.4, "twist": 0.7, "rolling": 1.1, "grade": 0.9}],
	["TECHNICAL", {"jumps": 0.35, "twist": 1.8, "rolling": 1.4, "grade": 1.2}],
	["GNARLY", {"jumps": 1.6, "twist": 1.6, "rolling": 2.2, "grade": 1.5}],
]
## where the ride is: [name, dry bias, rugged bias] added to the seed's own biome noise (0 = the seed's mix)
const BIOMES := [["ANY", 0.0, 0.0], ["GREEN HILLS", -2.0, -2.0], ["ROCKY MOUNTAINS", -2.0, 2.0], ["DUNE SEA", 2.0, -2.0], ["RED CANYONS", 2.0, 2.0]]
const PATH := "user://route.cfg"

static var current: Dictionary = DEFAULT.duplicate()
static var _loaded := false


static func ensure() -> void:
	if _loaded: return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in KEYS:
			current[k] = clampf(float(cf.get_value("route", k, DEFAULT[k])), LIMITS[k][0], LIMITS[k][1])
	var tb := OS.get_environment("BMX_ROUTE_BIOME")   # tests: 0 any .. 4 (BIOMES), not saved
	if tb != "": current["biome"] = clampf(float(tb), 0.0, 4.0)


static func get_value(k: String) -> float:
	ensure()
	return float(current.get(k, 1.0))


static func set_value(k: String, v: float, save := true) -> void:
	ensure()
	current[k] = clampf(v, LIMITS[k][0], LIMITS[k][1])
	if save: save_file()


static func apply(d: Dictionary) -> void:
	ensure()
	for k in KEYS:
		if d.has(k): current[k] = clampf(float(d[k]), LIMITS[k][0], LIMITS[k][1])
	save_file()


static func save_file() -> void:
	var st = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")   # (not a global in -s tools)
	if st == null or st._no_save: return
	var cf := ConfigFile.new()
	for k in KEYS: cf.set_value("route", k, current[k])
	cf.save(PATH)


## a copy for a TerrainField (so a change in the menu never reaches a world that is being built)
static func snapshot() -> Dictionary:
	ensure()
	return current.duplicate()


static func is_default(d: Dictionary = current) -> bool:
	for k in KEYS:
		if absf(float(d.get(k, 1.0)) - 1.0) > 0.001: return false
	return true


## the course code: world seed + the four sliders (in 0.05 steps) as one short line, e.g. 4242-20-20-20-20
## (jumps, bends, rolling, steepness: 20 = 1.0). Anyone who types it in gets the same trail.
static func code(seed_in: int, d: Dictionary = {}) -> String:
	ensure()
	var s: Dictionary = d if not d.is_empty() else current
	var c := "%d-%d-%d-%d-%d" % [seed_in, roundi(float(s["jumps"]) * 20.0), roundi(float(s["twist"]) * 20.0), roundi(float(s["rolling"]) * 20.0), roundi(float(s["grade"]) * 20.0)]
	var b := roundi(float(s.get("biome", 0.0)))
	return c + ("-b%d" % b if b > 0 else "")   # (a code without the biome part = the seed's own mix)


## {"seed", + the style keys} from a course code (a bare seed gives just the seed); {} if it isn't one
static func parse(text: String) -> Dictionary:
	var parts := Array(text.strip_edges().replace(" ", "").replace("_", "-").to_lower().split("-"))
	var biome := 0
	if parts.size() == 6 and String(parts[5]).begins_with("b") and String(parts[5]).substr(1).is_valid_int():
		biome = clampi(int(String(parts[5]).substr(1)), 0, BIOMES.size() - 1)
		parts.remove_at(5)
	for p in parts:
		if not String(p).is_valid_int(): return {}
	if parts.size() == 1: return {"seed": int(parts[0])}
	if parts.size() != 5: return {}
	var out := {"seed": int(parts[0]), "biome": float(biome)}
	for i in 4:
		out[KEYS[i]] = clampf(float(int(parts[i + 1])) / 20.0, LIMITS[KEYS[i]][0], LIMITS[KEYS[i]][1])
	return out


static func sig() -> String:
	ensure()
	return JSON.stringify([current["jumps"], current["twist"], current["rolling"], current["grade"], current["biome"]])
