class_name TerrainWater
extends MeshInstance3D
## The water surface at Terrain.WATER, following the player (port of water.js). Depth is baked into a
## small texture from the loaded chunks' height grids, a few rows per frame.

const BAKE_RES := 128     # texels per side
const BAKE_SIZE := 128.0  # metres covered
const BAKE_SNAP := 16.0
const BAKE_MS := 1.0

var terrain: Terrain
var _img: Image
var _tex: ImageTexture
var _buf := PackedByteArray()
var _center := Vector2(INF, INF)
var _job_center := Vector2.ZERO
var _job_row := -1
var _dirty := false
var _dirty_t := 0.0
var _mat: ShaderMaterial


func _init() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(280, 280)
	pm.subdivide_width = 160
	pm.subdivide_depth = 160
	mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/world/water.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_buf.resize(BAKE_RES * BAKE_RES)
	_img = Image.create_empty(BAKE_RES, BAKE_RES, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_img)
	_mat.set_shader_parameter("u_depth", _tex)
	_mat.set_shader_parameter("u_size", BAKE_SIZE)
	position.y = Terrain.WATER
	extra_cull_margin = 2.0


func invalidate() -> void:
	_center = Vector2(INF, INF)
	_job_row = -1


## a chunk (centre, size) was built or dropped: re-bake only if it touches the baked square
## (or the one being baked); far chunks stream in and out all the time and change nothing here
func mark_dirty(c: Vector2, size: float) -> void:
	var reach := BAKE_SIZE / 2 + size / 2
	for ctr in [_center, _job_center]:
		if is_finite(ctr.x) and absf(c.x - ctr.x) < reach and absf(c.y - ctr.y) < reach:
			_dirty = true
			return


## virtual depth: undo the terrain's lake-bed flattening so deep lakes still read as deep
func _depth(x: float, z: float) -> float:
	var h := terrain.grid_height(x, z)
	if is_nan(h):
		return 1.5
	var bed := Terrain.WATER - 0.35
	return 0.35 + (bed - h) / 0.08 if h < bed else Terrain.WATER - h


func follow(px: float, pz: float, t: float) -> void:
	_mat.set_shader_parameter("u_time", t)
	position = Vector3(roundf(px / 10) * 10, Terrain.WATER, roundf(pz / 10) * 10)
	var c := Vector2(roundf(px / BAKE_SNAP) * BAKE_SNAP, roundf(pz / BAKE_SNAP) * BAKE_SNAP)
	if not is_finite(_center.x):
		_start(c)
		_bake(INF)
		return
	_dirty_t += get_process_delta_time()
	if _job_row < 0:
		if maxf(absf(px - _center.x), absf(pz - _center.y)) > BAKE_SNAP * 1.5 or (_dirty and _dirty_t > 0.5):
			_start(c)
	if _job_row >= 0:
		_bake(BAKE_MS)


func _start(c: Vector2) -> void:
	_job_center = c
	_job_row = 0
	_dirty = false
	_dirty_t = 0.0


func _bake(ms: float) -> void:
	var step := BAKE_SIZE / BAKE_RES
	var x0 := _job_center.x - BAKE_SIZE / 2 + step / 2
	var z0 := _job_center.y - BAKE_SIZE / 2 + step / 2
	var t0 := Time.get_ticks_usec()
	var j := _job_row
	while j < BAKE_RES:
		if j > _job_row and Time.get_ticks_usec() - t0 > ms * 1000.0:
			break
		var z := z0 + j * step
		for i in BAKE_RES:
			var d := _depth(x0 + i * step, z)
			_buf[j * BAKE_RES + i] = clampi(int((d + 1) / 5 * 255), 0, 255)
		j += 1
	_job_row = j
	if _job_row >= BAKE_RES:
		_img.set_data(BAKE_RES, BAKE_RES, false, Image.FORMAT_R8, _buf)
		_tex.update(_img)
		_center = _job_center
		_mat.set_shader_parameter("u_center", _center)
		_job_row = -1
