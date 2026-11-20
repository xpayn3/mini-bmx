class_name LightSettings
extends RefCounted
## The level's light (tuning card › Light): time of day, the day / night cycle and the light sliders,
## with built-in times of day and the player's own presets. Saved to user://light.cfg.
## Game reads it (re-applies when `version` changes); the cycle runs the clock in Game, not here.

## [key, label, default, min, max, step, unit]
const PARAMS := [
	["time", "Time of day", 19.33, 0.0, 24.0, 0.05, "h"],
	["cycle", "Day / night cycle", 0.0, 0.0, 1.0, 1.0, ""],
	["day_min", "Day length", 24.0, 2.0, 120.0, 1.0, "min"],
	["sun_turn", "Sun direction", 0.0, -180.0, 180.0, 1.0, "°"],
	["sun", "Sun strength", 1.0, 0.0, 2.5, 0.05, "×"],
	["warmth", "Sun warmth", 1.0, 0.0, 2.0, 0.05, "×"],
	["sky", "Sky light (shade fill)", 1.0, 0.2, 2.5, 0.05, "×"],
	["moon", "Moonlight", 1.0, 0.0, 3.0, 0.05, "×"],
	["exposure", "Exposure", 1.0, 0.5, 2.0, 0.02, "×"],
	["haze", "Haze / fog", 1.0, 0.0, 3.0, 0.05, "×"],
	["rim", "Rim light (rider + bike edge glow)", 1.0, 0.0, 4.0, 0.05, "×"],
	["rim_spec", "Rim light glints", 1.0, 0.0, 3.0, 0.05, "×"],
	["rim_side", "Rim light from the side", 1.0, 0.0, 2.0, 0.05, "×"],
	["bloom", "Bloom / glow", 1.0, 0.0, 3.0, 0.05, "×"],
	["glare", "Glare guard (facing the sun)", 1.0, 0.0, 1.0, 0.05, "×"],
	["mist", "Morning mist", 1.0, 0.0, 3.0, 0.05, "×"],
	["shadow_soft", "Shadow softness", 1.0, 0.0, 3.0, 0.05, "×"],
	["saturation", "Saturation", 1.22, 0.6, 1.8, 0.01, ""],
	["contrast", "Contrast", 1.12, 0.8, 1.5, 0.01, ""],
]

## built-in times of day: only what differs from the defaults (the default is golden hour)
const BUILTIN := {
	"Golden hour": {},
	"Sunrise": {"time": 6.55, "haze": 0.85},
	"Morning": {"time": 9.0},
	"Noon": {"time": 13.0, "warmth": 0.8},
	"Afternoon": {"time": 16.0},
	"Dusk": {"time": 20.1, "haze": 1.1},
	"Night": {"time": 23.5},
	"Day / night cycle": {"time": 8.0, "cycle": 1.0},
}
const PATH := "user://light.cfg"

static var current := {}
static var active := "Golden hour"
static var customs := {}
static var version := 0
static var _loaded := false


static func defaults() -> Dictionary:
	var d := {}
	for r in PARAMS: d[r[0]] = float(r[2])
	return d


static func _complete(d: Dictionary) -> Dictionary:
	var out := defaults()
	for k in d:
		if out.has(k): out[k] = float(d[k])
	return out


static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	current = defaults()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		active = str(cf.get_value("light", "active", "Golden hour"))
		var c: Dictionary = cf.get_value("light", "customs", {})
		for n in c: customs[n] = _complete(c[n])
		current = _complete(cf.get_value("light", "current", {}))
	if not (active in BUILTIN or active in customs): active = "Golden hour"
	# tests: BMX_LIGHT=time=12,haze=2 / BMX_LIGHT_PRESET=Night (not saved unless a slider is touched)
	var ep := OS.get_environment("BMX_LIGHT_PRESET")
	if ep in BUILTIN or ep in customs:
		active = ep; current = preset(ep)
	for kv in OS.get_environment("BMX_LIGHT").split(",", false):
		var p := kv.split("=")
		if p.size() == 2 and current.has(p[0]): current[p[0]] = float(p[1])
	version += 1


static func save() -> void:
	if OS.get_environment("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
	var cf := ConfigFile.new()
	cf.set_value("light", "active", active)
	cf.set_value("light", "current", current)
	cf.set_value("light", "customs", customs)
	cf.save(PATH)


static func get_value(k: String) -> float:
	ensure_loaded()
	return float(current.get(k, 0.0))


static func set_value(k: String, v: float) -> void:
	ensure_loaded()
	current[k] = v
	if active in customs: customs[active][k] = v
	version += 1
	save()


# ---- the preset API shared with TunePresets / FreewheelSound (tuning card _preset_bar)
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


static func preset(n: String) -> Dictionary:
	if n in customs: return (customs[n] as Dictionary).duplicate()
	return _complete(BUILTIN.get(n, {}))


static func select(n: String) -> void:
	ensure_loaded()
	active = n
	current = preset(n)
	version += 1
	save()


static func modified() -> bool:
	var p := preset(get_active())
	for k in p:
		if absf(float(p[k]) - float(current.get(k, 0.0))) > 1e-4: return true
	return false


static func save_as(n: String) -> String:
	ensure_loaded()
	n = n.strip_edges()
	if n == "": n = "My light %d" % (customs.size() + 1)
	if n in BUILTIN: n += " (mine)"
	customs[n] = current.duplicate()
	active = n
	version += 1
	save()
	return n


static func delete(n: String) -> void:
	ensure_loaded()
	if not n in customs: return
	customs.erase(n)
	if active == n:
		active = "Golden hour"
		current = preset(active)
	version += 1
	save()


## back to the active preset's values (own presets: back to golden hour)
static func reset() -> void:
	ensure_loaded()
	current = preset(active) if not active in customs else defaults()
	if active in customs: customs[active] = current.duplicate()
	version += 1
	save()


static func clock(h: float) -> String:
	var m := int(round(fposmod(h, 24.0) * 60.0)) % 1440
	return "%02d:%02d" % [m / 60, m % 60]
