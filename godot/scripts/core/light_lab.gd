class_name LightLab
extends RefCounted
## DEV ONLY (2026-11-26): the knobs of the realistic light model (SunSky, Game._apply_light, the goggle lens grades) for
## tuning while the game is developed. Players never see these: they are on the tuning card's Light > Lab page (a dev
## tool) and their values ship baked in res://data/light_lab.json (only the values that differ from the defaults), which
## the game reads at start. SAVE on the Lab page writes that file (user://light_lab.json if res:// can't be written).
## Tests: BMX_LIGHT_LAB="turbidity=1.5,expo=1.4" overrides for one run, BMX_LIGHT_LAB_FILE=0 ignores the file.

const FILE := "res://data/light_lab.json"
const USER_FILE := "user://light_lab.json"

## [key, label, default, min, max, step, group]
const DEFS := [
	["expo", "Base exposure", 1.2, 0.4, 3.0, 0.01, "Exposure"],
	["ev_full", "Eye adapts fully above (EV)", 12.0, 8.0, 15.0, 0.1, "Exposure"],
	["adapt_dusk", "Darker toward sunset (stop / EV)", 0.2, 0.0, 0.6, 0.01, "Exposure"],
	["adapt_night", "Darker into the night (stop / EV)", 0.25, 0.0, 0.6, 0.01, "Exposure"],
	["turbidity", "Air haziness (aerosol: low sun redder, dimmer)", 1.0, 0.2, 4.0, 0.05, "Sun + sky"],
	["sky_ratio", "Sky light vs sun (shade fill)", 1.0, 0.3, 3.0, 0.05, "Sun + sky"],
	["moon_lux", "Full moon light (lux)", 0.15, 0.02, 0.8, 0.01, "Sun + sky"],
	["golden_below", "Painted sunset sky below (deg)", 10.0, 2.0, 30.0, 0.5, "Sun + sky"],
	["dust_haze", "Dusty horizon (sky + far hills melt into haze)", 1.0, 0.0, 1.0, 0.02, "Atmosphere"],
	["haze_warmth", "Haze colour: clean blue .. warm dust", 0.7, 0.0, 1.0, 0.02, "Atmosphere"],
	["haze_height", "How high up the sky the haze reaches", 0.55, 0.05, 1.0, 0.01, "Atmosphere"],
	["haze_bright", "Haze brightness (sun + sky light it scatters)", 1.6, 0.2, 3.0, 0.05, "Atmosphere"],
	["far_fog", "Far fog thickness", 0.97, 0.0, 1.0, 0.01, "Atmosphere"],
	["fog_far", "Far fog full at (m)", 450.0, 150.0, 3000.0, 10.0, "Atmosphere"],
	["fog_curve", "Fog falloff (low = haze starts close)", 0.85, 0.2, 2.5, 0.05, "Atmosphere"],
	["sun_haze", "Sun in the haze (light shafts)", 1.0, 0.0, 4.0, 0.05, "Haze"],
	["vol_ambient", "Sky light in the haze", 0.2, 0.0, 1.5, 0.01, "Haze"],
	["vol_density", "Haze density", 1.0, 0.0, 4.0, 0.05, "Haze"],
	["sun_scatter", "Glow round the sun (distance fog)", 0.02, 0.0, 0.2, 0.005, "Haze"],
	["fog_aerial", "Distance takes the sky\'s own colour (rest: the haze colour)", 0.25, 0.0, 1.0, 0.05, "Haze"],
	["agx_contrast", "Tonemapper contrast (AgX)", 1.25, 1.0, 1.7, 0.01, "Tone"],
	["agx_white", "Tonemapper white point (AgX)", 12.0, 4.0, 24.0, 0.5, "Tone"],
	["bloom_mix", "Lens glow (bloom mix)", 0.04, 0.0, 0.2, 0.005, "Tone"],
	["night_sat", "Colour left at night", 0.5, 0.0, 1.0, 0.02, "Tone"],
	["wb_warm", "White balance (- cool .. + warm, like a photo)", 0.18, -0.6, 0.6, 0.01, "Camera"],
	["lens_ca", "Lens colour fringes (chromatic aberration)", 0.22, 0.0, 2.0, 0.05, "Camera"],
	["motion_blur", "Motion blur (shutter: 0.5 = 180 deg film)", 0.35, 0.0, 1.0, 0.02, "Camera"],
	["motion_max", "Motion blur longest smear (px)", 32.0, 4.0, 120.0, 1.0, "Camera"],
	["blur_amount", "Old fixed side blur at speed (x)", 0.0, 0.0, 2.5, 0.05, "Camera"],
	["lens_amount", "Goggle lens grade strength", 1.0, 0.0, 1.6, 0.05, "Lens"],
]

static var values := {}
static var version := 0
static var _loaded := false

static func defaults() -> Dictionary:
	var d := {}
	for e in DEFS: d[e[0]] = float(e[2])
	return d

static func def_of(key: String) -> float:
	for e in DEFS:
		if e[0] == key: return float(e[2])
	return 0.0

static func ensure() -> void:
	if _loaded: return
	_loaded = true
	values = defaults()
	if OS.get_environment("BMX_LIGHT_LAB_FILE") != "0":
		for path in [USER_FILE, FILE]:
			if not FileAccess.file_exists(path): continue
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				for k in d:
					if values.has(k): values[k] = float(d[k])
			break
	for kv in OS.get_environment("BMX_LIGHT_LAB").split(",", false):
		var p := kv.split("=")
		if p.size() == 2 and values.has(p[0]): values[p[0]] = float(p[1])
	version += 1

static func v(key: String) -> float:
	ensure()
	return float(values.get(key, def_of(key)))

static func set_value(key: String, x: float) -> void:
	ensure()
	values[key] = x
	version += 1

## only the values that differ from the defaults
static func changed() -> Dictionary:
	var d := {}
	for e in DEFS:
		if not is_equal_approx(float(values.get(e[0], e[2])), float(e[2])):
			d[e[0]] = snappedf(float(values[e[0]]), 0.0001)
	return d

## writes the file (res:// in a dev checkout, else user://); returns the path written, "" on failure
static func save() -> String:
	ensure()
	var txt := JSON.stringify(changed(), "\t", false) + "\n"
	for path in [FILE, USER_FILE]:
		if path == FILE:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(txt)
			f.close()
			if path == FILE and FileAccess.file_exists(USER_FILE):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_FILE))   # the project file wins from now on
			return path
	return ""

## the defaults again (not saved until SAVE)
static func reset() -> void:
	ensure()
	values = defaults()
	version += 1

## back to what the file says
static func reload() -> void:
	_loaded = false
	ensure()
