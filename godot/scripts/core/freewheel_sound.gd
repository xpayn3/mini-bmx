class_name FreewheelSound
extends RefCounted
## The freewheel's sound settings (the tuning card's Sound › Freewheel sliders): every knob of
## FreewheelSynth.cs plus the volume / engagement that ride_audio.gd applies, built-in hub presets and the
## player's own named presets. Saved to user://freewheel.cfg. ride_audio.gd re-reads when `version` changes.

## [key, label, default, min, max, step, unit] - the defaults are the recorded hub
const PARAMS := [
	["vol", "Volume", 1.0, 0.0, 2.5, 0.05, "×"],
	["poe", "Engagement (clicks / wheel turn)", 24.0, 4.0, 144.0, 1.0, ""],
	["pitch", "Pitch", 1.0, 0.4, 2.0, 0.01, "×"],
	["ring", "Ring length", 1.0, 0.2, 4.0, 0.05, "×"],
	["tilt", "Brightness (dark / bright)", 0.0, -1.5, 1.5, 0.05, ""],
	["crack", "Snap", 1.0, 0.0, 3.0, 0.05, "×"],
	["crack_len", "Snap length", 1.0, 0.2, 4.0, 0.05, "×"],
	["detune", "Click-to-click detune", 0.035, 0.0, 0.2, 0.005, ""],
	["uneven", "Pawl unevenness", 1.0, 0.0, 2.5, 0.05, "×"],
	["jitter", "Timing wobble", 0.06, 0.0, 0.3, 0.01, ""],
	["vary", "Click strength spread", 0.55, 0.0, 1.0, 0.05, ""],
	["fade", "Quieter at speed", 0.0, 0.0, 1.0, 0.05, ""],
	# the wheel's turn and speed (FreewheelSynth.SetSpeedParams); 0 on all = the old speed-blind sound
	["warble", "Wheel-turn warble (swell each turn)", 0.04, 0.0, 1.0, 0.05, ""],
	["repeat", "Pattern repeats each turn", 0.3, 0.0, 1.0, 0.05, ""],
	["sp_pitch", "Pitch rise at speed", 0.06, -0.2, 0.5, 0.01, ""],
	["sp_bright", "Brighter at speed", 0.3, -1.0, 1.5, 0.05, ""],
	["sp_ring", "Shorter ring at speed", 0.3, 0.0, 0.8, 0.05, ""],
	["sp_soft", "Softer snap at speed", 0.6, 0.0, 1.0, 0.05, ""],
	["sp_from", "Speed effects start", 12.0, 0.0, 60.0, 1.0, " km/h"],
	["sp_full", "Speed effects full", 60.0, 10.0, 120.0, 1.0, " km/h"],
]

## built-in hubs: only the values that differ from the defaults
const BUILTIN := {
	"Stock": {},
	"Loud buzz": {"vol": 1.7, "poe": 44.0, "pitch": 0.85, "ring": 1.6, "crack": 1.4, "tilt": 0.2, "fade": 0.0, "sp_pitch": 0.1},
	"Quiet": {"vol": 0.45, "poe": 36.0, "ring": 0.6, "crack": 0.5, "tilt": -0.4, "fade": 0.5},
	"Deep ratchet": {"poe": 36.0, "pitch": 0.7, "ring": 1.4, "crack": 0.8, "tilt": -0.3, "uneven": 0.2, "jitter": 0.03},
	"High engagement": {"vol": 0.9, "poe": 102.0, "pitch": 1.15, "ring": 0.7, "uneven": 0.4, "crack": 0.9},
	"Old school": {"poe": 18.0, "pitch": 0.9, "ring": 1.2, "crack": 1.2, "uneven": 1.5, "jitter": 0.1, "vary": 0.7, "warble": 0.12, "repeat": 0.6},
}

const PATH := "user://freewheel.cfg"

static var current := {}
static var active := "Stock"
static var customs := {}       # name -> full params
static var version := 0        # bumped on every change
static var preview_speed := 0.0   # > 0: play the freewheel at this wheel speed (m/s) even standing still
static var _loaded := false


static func defaults() -> Dictionary:
	var d := {}
	for r in PARAMS: d[r[0]] = float(r[2])
	return d


static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	current = defaults()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		active = str(cf.get_value("fw", "active", "Stock"))
		var c: Dictionary = cf.get_value("fw", "customs", {})
		for n in c: customs[n] = _complete(c[n])
		current = _complete(cf.get_value("fw", "current", {}))
		# ver 2 (2026-11-27): "Quieter at speed" 0.3 -> 0 (a real hub at speed is a loud, dense buzz);
		# saves still at the old default move with it
		if int(cf.get_value("fw", "ver", 1)) < 2:
			if is_equal_approx(float(current.get("fade", 0.0)), 0.3): current["fade"] = 0.0
			for n in customs:
				if is_equal_approx(float(customs[n].get("fade", 0.0)), 0.3): customs[n]["fade"] = 0.0
	if not (active in BUILTIN or active in customs): active = "Stock"
	# tests: BMX_FW_PRESET=<name> and BMX_FW=pitch=1.3,poe=60 (not saved unless a slider is touched)
	var ep := Env.raw("BMX_FW_PRESET")
	if ep in BUILTIN or ep in customs:
		active = ep; current = preset(ep)
	for kv in Env.raw("BMX_FW").split(",", false):
		var p := kv.split("=")
		if p.size() == 2 and current.has(p[0]): current[p[0]] = float(p[1])
	preview_speed = float(Env.raw("BMX_FW_PREVIEW"))   # tests: Preview on at this speed
	version += 1


static func _complete(d: Dictionary) -> Dictionary:
	var out := defaults()
	for k in d:
		if out.has(k): out[k] = float(d[k])
	return out


static func save() -> void:
	if Env.raw("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
	var cf := ConfigFile.new()
	cf.set_value("fw", "ver", 2)
	cf.set_value("fw", "active", active)
	cf.set_value("fw", "current", current)
	cf.set_value("fw", "customs", customs)
	cf.save(PATH)


static func names() -> Array:
	ensure_loaded()
	var out: Array = BUILTIN.keys()
	var cn: Array = customs.keys(); cn.sort()
	return out + cn


static func get_active() -> String:
	ensure_loaded()
	return active


static func builtin_count() -> int:
	return BUILTIN.size()


static func is_builtin(n: String) -> bool:
	return n in BUILTIN


static func preset(n: String) -> Dictionary:
	if n in customs: return (customs[n] as Dictionary).duplicate()
	return _complete(BUILTIN.get(n, {}))


static func get_value(k: String) -> float:
	ensure_loaded()
	return float(current.get(k, 0.0))


## a slider moved: a custom preset saves straight into itself, a built-in shows as modified
static func set_value(k: String, v: float) -> void:
	ensure_loaded()
	current[k] = v
	if active in customs: customs[active][k] = v
	version += 1
	save()


static func select(n: String) -> void:
	ensure_loaded()
	active = n
	current = preset(n)
	version += 1
	save()


## true when the sliders differ from the active preset (only possible for a built-in)
static func modified() -> bool:
	var p := preset(active)
	for k in p:
		if absf(float(p[k]) - float(current.get(k, 0.0))) > 1e-4: return true
	return false


## save the sliders as a new (or existing) custom preset and switch to it
static func save_as(n: String) -> String:
	ensure_loaded()
	n = n.strip_edges()
	if n == "": n = "Custom %d" % (customs.size() + 1)
	if n in BUILTIN: n += " (custom)"
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
		active = "Stock"
	version += 1
	save()


## back to the active preset's values (a custom: its stored values; built-in: its factory values)
static func reset() -> void:
	ensure_loaded()
	current = preset(active) if not active in customs else _complete(BUILTIN.get("Stock", {}))
	if active in customs: customs[active] = current.duplicate()
	version += 1
	save()
