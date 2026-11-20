class_name TunePresets
extends RefCounted
## Named ride-feel presets for the tuning card: every Tune value (Ride tab + Rider › Physics).
## Built-ins hold only what they change from the defaults; the player's own presets hold every value.
## Saved to user://tune_presets.cfg (the live slider values stay in Tune's user://tune.cfg).
## A custom preset follows its sliders as they move; a built-in shows "changed" until Save as.

const BUILTIN := {
	"Default": {},
	"Flowy": {"flowCarry": 0.7, "flowTime": 7.0, "carveBoost": 2.2, "pumpGain": 14.0, "rollRes": 0.6, "turnWeight": 0.15, "popKick": 2.0},
	"Grippy": {"grip": 1.55, "oversteer": 0.1, "slipRecover": 12.0, "slipMax": 1.3, "carveGrip": 0.2, "counter": 0.1},
	"Drifty": {"grip": 0.9, "oversteer": 0.8, "slipRecover": 3.0, "slipMax": 1.35, "counter": 0.4},
	"Floaty air": {"airTwist": 0.9, "flipRate": 9.0, "flipAccel": 40.0, "airTilt": 0.7, "tuckSpin": 0.5, "slamJolt": 8.5, "popKick": 2.2},
	"Fast": {"topSpeed": 1.6, "pedalPower": 30.0, "pedalTop": 15.0, "airDrag": 0.0024, "sprintTop": 5.0},
}
const PATH := "user://tune_presets.cfg"

static var active := "Default"
static var customs := {}      # name -> {key: value} (every Tune key)
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		active = str(cf.get_value("presets", "active", "Default"))
		customs = cf.get_value("presets", "customs", {})
	if not (active in BUILTIN or active in customs): active = "Default"


static func save() -> void:
	if OS.get_environment("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
	var cf := ConfigFile.new()
	cf.set_value("presets", "active", active)
	cf.set_value("presets", "customs", customs)
	cf.save(PATH)


static func get_active() -> String:
	ensure_loaded()
	return active


static func builtin_count() -> int:
	return BUILTIN.size()


static func names() -> Array:
	ensure_loaded()
	var cn: Array = customs.keys(); cn.sort()
	return BUILTIN.keys() + cn


static func is_builtin(n: String) -> bool:
	return n in BUILTIN


## full values of a preset (defaults filled in)
static func preset(n: String) -> Dictionary:
	ensure_loaded()
	var out: Dictionary = Tune.defaults.duplicate()
	var src: Dictionary = customs[n] if n in customs else BUILTIN.get(n, {})
	for k in src:
		if out.has(k): out[k] = float(src[k])
	# dust sliders aren't ride feel: a ride preset leaves them as they are
	for k in out:
		if str(k).begins_with("dust") or str(k).begins_with("demo"): out[k] = float(Tune.base.get(k, out[k]))
	return out


static func value_of(k: String) -> float:
	return float(preset(get_active()).get(k, Tune.defaults.get(k, 0.0)))


static func select(n: String) -> void:
	ensure_loaded()
	active = n
	Tune.apply_values(preset(n))
	save()


## Tune calls this whenever a slider moves: a custom preset keeps up with its sliders
static func value_changed(k: String, v: float) -> void:
	ensure_loaded()
	if active in customs:
		customs[active][k] = v
		save()


## the sliders differ from the active preset (only shows for a built-in)
static func modified() -> bool:
	var p := preset(get_active())
	for k in p:
		if absf(float(p[k]) - float(Tune.base.get(k, p[k]))) > 1e-5: return true
	return false


static func save_as(n: String) -> String:
	ensure_loaded()
	n = n.strip_edges()
	if n == "": n = "My tune %d" % (customs.size() + 1)
	if n in BUILTIN: n += " (mine)"
	customs[n] = Tune.base.duplicate()
	active = n
	save()
	return n


static func delete(n: String) -> void:
	ensure_loaded()
	if not n in customs: return
	customs.erase(n)
	if active == n: active = "Default"
	save()
