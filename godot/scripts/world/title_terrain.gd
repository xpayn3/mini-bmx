class_name TitleTerrain
extends Terrain
## The title screen's land: a small fixed place, the same every launch, loaded from a file baked once
## (tools/bake_title.tscn -> res://assets/title/title_land.bin: the chunks round Game.TITLE_SPOT of the title world +
## the far hills' backdrop). No terrain generator (TerrainField.setup was ~1.5 s), no chunk building or streaming
## (~2.4 s), no worker threads. Heights are read from the saved chunk grids (the drawn ground) + the rock domes.
## The base Terrain keeps an EMPTY field with an empty trail, so code that looks for the trail finds none.
## No file (not baked) = Game falls back to the procedural title world.

const FILE := "res://assets/title/title_land.bin"
const VER := 1

var far: Dictionary = {}   # the far hills' saved arrays (Game hands them to its FarHills: load_baked)
var spot := Vector3.ZERO
var _data: Dictionary = {}

static func available() -> bool:
	return FileAccess.file_exists(FILE)

func _init(seed_in := 37) -> void:
	super(seed_in)

## no generator: an empty field (no trail, no route features) and the saved land read in
func set_seed(seed_in: int) -> void:
	seed_value = seed_in
	field = TerrainField.new()
	field.course = TrailCourse.new()
	field.route_feats = []
	fcs = null
	water_enabled = false
	cs_tyres = false
	var f := FileAccess.open_compressed(FILE, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("TitleTerrain: %s missing (run tools/bake_title.tscn)" % FILE)
		return
	var d = f.get_var(true)
	f.close()
	if not (d is Dictionary) or int(d.get("ver", 0)) != VER:
		push_warning("TitleTerrain: %s is from another version, bake it again" % FILE)
		return
	_data = d
	far = d.get("far", {})
	spot = d.get("spot", Vector3.ZERO)

var _built := false
## the saved chunks turned into nodes, once (where the rider is doesn't matter: the land is fixed)
func update_stream(_px: float, _pz: float, _budget_ms: float = 4.0, _sync_r := -1) -> void:
	if _built: return
	_built = true
	var cs: Dictionary = _data.get("chunks", {})
	for k in cs:
		_finalize_out(k, cs[k]["o"], int(cs[k]["N"]))
	_data = {}   # (the nodes hold what they need now)

func stream_complete() -> bool:
	return _built

func _update_ropes() -> void:
	pass

func update_water(_px: float, _pz: float, _t: float) -> void:
	pass

func water_near(_px: float, _pz: float, _reach: float) -> bool:
	return false

func take_pack(_x: float, _y: float, _z: float, _r: float = 1.6):
	return null

# ---- physics queries: the drawn ground + rock domes ---------------------------------------------------------------
func _ground(x: float, z: float) -> float:
	var m := mesh_height(x, z)
	return m if m > -INF else 0.0

func _height0(x: float, z: float) -> float:
	var g := _ground(x, z)
	var list = _rock_grid.get(_rock_key(floori(x / ROCK_CELL), floori(z / ROCK_CELL)))
	if list != null:
		for c in list:
			var dx: float = x - c["x"]
			var dz: float = z - c["z"]
			var r: float = c["r"]
			var q := (dx * dx + dz * dz) / (r * r)
			if q < 1.0:
				g = maxf(g, dome_h(c["base"], c["top"], c.get("sink", 0.0), q))
	return g

func height(x: float, z: float) -> float:
	return _height0(x, z)

func deck_height(x: float, z: float) -> float:
	return _ground(x, z)

func top_height(x: float, z: float) -> float:
	return _height0(x, z)

func drawn_height(x: float, z: float) -> float:
	return _height0(x, z)

func surface(_x: float, _z: float) -> int:
	return 3   # the title's desert summit: sand (dust, no grass sounds)

func jump(x: float, z: float) -> Array:
	return [_ground(x, z), 0.0, 0.0, 0.0, null]

func jump_mask(_x: float, _z: float) -> float:
	return 0.0

func biome_name(_x: float, _z: float) -> String:
	return "Lookout"

func ground_color(_x: float, _z: float, _ny: float = 1.0) -> Color:
	return Color(0.78, 0.6, 0.42)

func trail(_x: float, _z: float) -> float:
	return 0.0
