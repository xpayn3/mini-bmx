@tool
class_name LandParams
## The land generator's knobs, in plain words and plain units (metres, 0..1), for the Land Lab (dev/land_lab.gd) and
## for tweaking by hand / with Claude: res://data/land_params.json (only the values that differ from the defaults).
## apply() turns them into TerrainField's static vars (and land_get -> TerrainFieldCs, so C# == GDScript stays EXACT).
## The world reads the file at the first field setup; nothing in the file = the hand-tuned land, bit for bit.
## Tests: BMX_LAND="big_h=24,warp=60" overrides, BMX_LAND_FILE=0 ignores the file.

const FILE := "res://data/land_params.json"
const USER_FILE := "user://land_params.json"   # where the editor saves when res:// can't be written (an exported game)

## key, default, min, max, group, what it does
const DEFS := [
	["land_scale", 1.0, 0.0, 2.5, "Overall", "every hill and bump higher / lower (not the mountains)"],
	["big_h", 16.0, 0.0, 45.0, "Big shapes", "rolling hills: height (m)"],
	["big_p", 240.0, 80.0, 700.0, "Big shapes", "rolling hills: size across (m)"],
	["ridge_h", 14.0, 0.0, 45.0, "Big shapes", "ridgelines: height (m)"],
	["ridge_p", 150.0, 50.0, 500.0, "Big shapes", "ridgelines: spacing (m)"],
	["region_p", 700.0, 200.0, 2500.0, "Big shapes", "how big the hilly vs flat regions are (m)"],
	["mid_h", 10.0, 0.0, 30.0, "Bumps", "90 m bumps: height (m)"],
	["mid_p", 90.0, 25.0, 250.0, "Bumps", "90 m bumps: size (m)"],
	["fine_h", 3.2, 0.0, 12.0, "Bumps", "small bumps: height (m)"],
	["fine_p", 28.0, 6.0, 90.0, "Bumps", "small bumps: size (m)"],
	["relief", 1.3, 0.0, 3.0, "Bumps", "extra bumpiness in rough patches"],
	["relief_p", 260.0, 60.0, 900.0, "Bumps", "size of the rough patches (m)"],
	["warp", 38.0, 0.0, 140.0, "Flow", "how much the shapes swirl / bend (m)"],
	["warp_p", 170.0, 40.0, 600.0, "Flow", "size of the swirls (m)"],
	["talus", 0.30, 0.05, 2.0, "Steepness", "how steep big faces may get (higher = steeper)"],
	["detail_s", 0.30, 0.05, 2.0, "Steepness", "bumps on slopes (higher = bumpier faces)"],
	["fine_s", 0.55, 0.05, 2.0, "Steepness", "small bumps on slopes (higher = bumpier)"],
	["rough_p", 2600.0, 500.0, 8000.0, "Regions", "plains vs rough country: region size (m)"],
	["macro_p", 1800.0, 500.0, 8000.0, "Regions", "low vs big-hill country: region size (m)"],
	["valley_flat", 0.65, 0.0, 1.0, "Valleys", "valley floors smooth"],
	["valley_macro", 0.40, 0.0, 1.0, "Valleys", "valleys flatten the big hills"],
	["valley_p", 420.0, 100.0, 2000.0, "Valleys", "valley size (m)"],
	["strata", 0.7, 0.0, 1.0, "Rock bands", "stepped rock ledges in rugged land"],
	["strata_step", 3.2, 0.8, 12.0, "Rock bands", "ledge height (m)"],
]

static var values := {}       # key -> value (all keys)
static var _loaded := false


static func defaults() -> Dictionary:
	var d := {}
	for e in DEFS:
		d[e[0]] = float(e[1])
	return d


static func def_of(key: String) -> float:
	for e in DEFS:
		if e[0] == key:
			return float(e[1])
	return 0.0


## once, before the first field: the file (+ test overrides), then apply
static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	load_values()
	var ov := OS.get_environment("BMX_LAND")
	for kv in ov.split(",", false):
		var p := kv.split("=")
		if p.size() == 2 and values.has(p[0].strip_edges()):
			values[p[0].strip_edges()] = float(p[1])
	apply()


## values = defaults + the file (no apply: the Land Lab editor tab uses this, TerrainField can't run in the editor)
static func load_values() -> void:
	values = defaults()
	if OS.get_environment("BMX_LAND_FILE") == "0":
		return
	var path := USER_FILE if FileAccess.file_exists(USER_FILE) else FILE
	if FileAccess.file_exists(path):
		var j = JSON.parse_string(FileAccess.get_file_as_string(path))
		if j is Dictionary:
			for k in j:
				if values.has(k):
					values[k] = float(j[k])


## values -> TerrainField statics (call before setting up a field; the C# field takes them in setup_from)
static func apply() -> void:
	if values.is_empty():
		values = defaults()
	_loaded = true
	var v := values
	var k: float = v.land_scale
	TerrainField.L_A240 = v.big_h * k
	TerrainField.L_ARDG = v.ridge_h * k
	TerrainField.L_A90 = v.mid_h * k
	TerrainField.L_A28 = v.fine_h * k
	TerrainField.L_REL = v.relief
	TerrainField.L_I240 = 1.0 / v.big_p
	TerrainField.L_I150 = 1.0 / v.ridge_p
	TerrainField.L_I700 = 1.0 / v.region_p
	TerrainField.L_I90 = 1.0 / v.mid_p
	TerrainField.L_I28 = 1.0 / v.fine_p
	TerrainField.L_I260 = 1.0 / v.relief_p
	TerrainField.L_I170 = 1.0 / v.warp_p
	TerrainField.LAND_WARP = v.warp
	TerrainField.LAND_TALUS = v.talus
	TerrainField.LAND_DETAIL_S = v.detail_s
	TerrainField.LAND_FINE_S = v.fine_s
	TerrainField.LAND_CR = 1.0 / v.rough_p
	TerrainField.LAND_CM = 1.0 / v.macro_p
	TerrainField.LAND_VALLEY_FLAT = v.valley_flat
	TerrainField.LAND_VALLEY_MACRO = v.valley_macro
	TerrainField.LAND_VI = 1.0 / v.valley_p
	TerrainField.LAND_STRATA = v.strata
	TerrainField.LAND_STRATA_STEP = v.strata_step


## what the C# field needs (TerrainFieldCs._land_from: the same names as the static vars)
static func cs_dict() -> Dictionary:
	var d := {}
	for n in ["LAND_WARP", "LAND_TALUS", "LAND_DETAIL_S", "LAND_FINE_S", "LAND_VALLEY_FLAT", "LAND_VALLEY_MACRO", "LAND_VI",
			"LAND_CR", "LAND_CM", "LAND_STRATA_STEP", "LAND_STRATA", "L_A240", "L_ARDG", "L_A90", "L_A28", "L_REL",
			"L_I240", "L_I150", "L_I90", "L_I28", "L_I700", "L_I260", "L_I170"]:
		d[n] = _static(n)
	return d


static func _static(n: String) -> float:
	match n:
		"LAND_WARP": return TerrainField.LAND_WARP
		"LAND_TALUS": return TerrainField.LAND_TALUS
		"LAND_DETAIL_S": return TerrainField.LAND_DETAIL_S
		"LAND_FINE_S": return TerrainField.LAND_FINE_S
		"LAND_VALLEY_FLAT": return TerrainField.LAND_VALLEY_FLAT
		"LAND_VALLEY_MACRO": return TerrainField.LAND_VALLEY_MACRO
		"LAND_VI": return TerrainField.LAND_VI
		"LAND_CR": return TerrainField.LAND_CR
		"LAND_CM": return TerrainField.LAND_CM
		"LAND_STRATA_STEP": return TerrainField.LAND_STRATA_STEP
		"LAND_STRATA": return TerrainField.LAND_STRATA
		"L_A240": return TerrainField.L_A240
		"L_ARDG": return TerrainField.L_ARDG
		"L_A90": return TerrainField.L_A90
		"L_A28": return TerrainField.L_A28
		"L_REL": return TerrainField.L_REL
		"L_I240": return TerrainField.L_I240
		"L_I150": return TerrainField.L_I150
		"L_I90": return TerrainField.L_I90
		"L_I28": return TerrainField.L_I28
		"L_I700": return TerrainField.L_I700
		"L_I260": return TerrainField.L_I260
		"L_I170": return TerrainField.L_I170
	return 0.0


## only the values that differ from the defaults (what the file holds)
static func changed() -> Dictionary:
	var d := {}
	for e in DEFS:
		if not is_equal_approx(float(values.get(e[0], e[1])), float(e[1])):
			d[e[0]] = snappedf(float(values[e[0]]), 0.0001)
	return d


## writes the file (res:// in the editor / a dev checkout, else user://); returns the path written, "" on failure
static func save() -> String:
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


## back to what the file says
static func reload() -> void:
	_loaded = false
	ensure()
