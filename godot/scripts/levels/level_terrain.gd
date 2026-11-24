class_name LevelTerrain
extends Terrain
## A level built in the Godot editor (the level builder: addons/level_builder, res://levels/*.tscn, BmxLevel +
## BmxTrail) in the ride's Terrain slot. Main starts it with --level=res://levels/<name>.tscn (the editor's
## "Ride this level" button does that). The scene is loaded, its BmxLevel makes the LevelField, which bakes the
## ground at 0.5 m: the physics reads that grid, the drawn ground is the same grid at 1 m. The base
## Terrain's field gets the level's trail as its TrailCourse (LevelField.to_course) and no route features.

var path := ""
var title := "Level"
var lf: LevelField
var _built := false
var _mat: ShaderMaterial


func _init(scene_path: String, seed_in := 12345) -> void:
	path = scene_path
	var t0 := Time.get_ticks_msec()
	var ps = load(scene_path) if ResourceLoader.exists(scene_path) else null
	var root: Node = ps.instantiate() if ps is PackedScene else null
	var lvl: BmxLevel = root if root is BmxLevel else null
	if lvl == null and root != null:
		for c in root.get_children():
			if c is BmxLevel: lvl = c; break
	if lvl == null:
		push_warning("LevelTerrain: no BmxLevel in '%s'" % scene_path)
		lf = LevelField.new()
	else:
		lf = lvl.make_field()
		title = lvl.title
	if root: root.free()
	lf.bake(0.5)
	print("LEVEL ", scene_path, " baked ms=", Time.get_ticks_msec() - t0, " grid=", lf.nx, "x", lf.nz, " | ", lf.summary())
	super(seed_in)


func set_seed(seed_in: int) -> void:
	super(seed_in)
	field.course = lf.to_course()   # the level's own trail (demo AI, follow rider, trail camera, bend alerts)
	field.route_feats = []
	water_enabled = false
	cs_tyres = false   # its own ground: the drawn tyres sample it in GDScript


func update_stream(_px: float, _pz: float, _budget_ms: float = 4.0, _sync_r := -1) -> void:
	if _built: return
	_built = true
	var t0 := Time.get_ticks_msec()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/playground_ground.gdshader")
	_mat.set_shader_parameter("line_1m", 0.0)
	_mat.set_shader_parameter("line_5m", 0.0)
	_mat.set_shader_parameter("contour", 0.0)
	_add_mesh(lf.ground_mesh(2), "Ground")
	_add_mesh(lf.far_mesh(1400.0, 14.0), "FarLand")
	chunk_serial += 1
	print("LEVEL ground built ms=", Time.get_ticks_msec() - t0)


func _add_mesh(m: ArrayMesh, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.material_override = _mat
	mi.layers = 1 | GROUND_LAYER
	add_child(mi)


func stream_complete() -> bool:
	return _built

func _update_ropes() -> void:
	pass

func update_water(_px: float, _pz: float, _t: float) -> void:
	pass

func water_near(_px: float, _pz: float, _reach: float) -> bool:
	return false


# ---- physics queries -------------------------------------------------------------------------------------
func _height0(x: float, z: float) -> float:
	return lf.height(x, z)

func height(x: float, z: float) -> float:
	return lf.height(x, z) - rut_at(x, z)

func deck_height(x: float, z: float) -> float:
	return lf.height(x, z) - rut_at(x, z)

func mesh_height(x: float, z: float) -> float:
	return lf.height(x, z)

func top_height(x: float, z: float) -> float:
	return lf.height(x, z) - rut_at(x, z)

func grid_height(x: float, z: float) -> float:
	return lf.height(x, z)

## trail + berm faces = dirt (1), the land = grass (0)
func surface(x: float, z: float) -> int:
	return 1 if lf.surface_at(x, z) > 0 else 0

func jump(x: float, z: float) -> Array:
	return [lf.height(x, z), 0.0, 0.0, 0.0, null]

func jump_mask(_x: float, _z: float) -> float:
	return 0.0

func biome_name(_x: float, _z: float) -> String:
	return title

func ground_color(x: float, z: float, _ny: float = 1.0) -> Color:
	var sf := lf.surface_at(x, z)
	if sf == 1: return LevelField.DIRT
	if sf == 2: return LevelField.CLAY
	return LevelField.GRASS

func trail(x: float, z: float) -> float:
	return 1.0 if lf.surface_at(x, z) == 1 else 0.0

func colliders_near(_x: float, _z: float) -> Array:
	return []

func take_pack(_x: float, _y: float, _z: float, _r: float = 1.6):
	return null

## the start: the trail's first point, facing down it ((x, heading, z) as Game.respawn takes it)
func level_spawn() -> Vector3:
	return lf.stand_at(2)

## the bail tap: back on the nearest point of the trail, a few metres up it, facing down it
func level_reset(x: float, z: float) -> Vector3:
	var i := lf.nearest(x, z)
	return lf.stand_at(maxi(2, i - 8)) if i >= 0 else level_spawn()
