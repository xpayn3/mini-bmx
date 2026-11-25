class_name RoadDetail
extends RefCounted
## The road's surface detail baked into textures, racing-game style (2026-11-25, user: "racing games' roads look so
## nice, ours fades in a lot"). The trail's marks (ridden lines, tyre prints, stray lines, playful marks, skids, damp
## soil, puddles, grit, edge stones, the worn relief) used to be worked out per pixel every frame in ground.gdshader;
## maths can't mipmap, so each mark was switched off by pixel size and a ring of detail followed the camera. Here they
## are worked out once per texel (compute shader shaders/road_detail_bake.glsl, supersampled, every mark filtered to the
## texel) into a CLIPMAP: three camera-following windows of world-aligned texels, toroidal (a texel is world cell mod N,
## so moving the window only re-bakes the tiles that came in), each with its own mip chain (road_detail_mip.glsl). The
## ground shader (`road_vt`) reads the finest window that holds the pixel with anisotropic mips: far off the marks blur
## into their average, nothing switches off.
##
## Texture layout (one Texture2DArrayRD each, layer = level): see LAYOUT. Params (the bake's knobs, a storage buffer):
## PARAMS, set with set_param() (re-bakes everything). New layers: road_detail_bake.glsl's header says how.
## Settings "road_detail" 0 off (the old per-pixel path), 1 low (512^2: half the windows, ~22 MB), 2 high (1024^2, ~85 MB);
## BMX_ROAD=0|1|2 overrides, BMX_ROAD_PROBE=1 prints ROAD lines, BMX_ROAD_SET="edge_stones=2,pebbles=1.5" sets params.

const LAYOUT := {
	"A": "rgba8: k / 2 (dirt colour multiplier), tyre prints, damp soil, standing water",
	"B": "rgba16f: relief slope x, z (m/m), mean squared slope, pebble height",
	"C": "rgba8: baked flag, ridden lines, loose grit, edge stones",
}
## the bake's knobs, in the order road_detail_bake.glsl reads them (P_*): name, default, what it does
const PARAMS := [
	["play", 0.34, "share of 26 m stretches with a playful mark (donut, figure of eight, slalom, skid arc)"],
	["puddles", 1.0, "0 none, 1 normal, > 1 puddles on every wet road"],
	["lines", 1.0, "ridden lines' strength"],
	["prints", 1.0, "tyre prints' strength"],
	["stray", 1.0, "stray single lines' strength"],
	["pebbles", 1.0, "grit / small pebbles on the dirt"],
	["edge_stones", 1.0, "stones along the trail's edges (0 = none)"],
	["edge_size", 1.0, "size of the edge stones (x)"],
	["edge_var", 1.0, "how far the ragged edge wanders (ground.gdshader trail_edge_var)"],
	["edge_fade", 1.0, "edge fade width (ground.gdshader trail_edge_fade)"],
	["groove", 0.05, "how much darker the worn riding line is (a racing game's groove)"],
	["footprints", 1.0, "footprints of many people over time, scattered at random (0 = none, higher = more)"],
]
const MAX_PARAMS := 32

## m per texel per level (windows 12.8 / 25.6 / 77 / 192 m at 1024): each divides 48 m and lines its tiles up with the
## chunk edges. The finest is ~1 cm like a racing game's near road texture: 2-4 cm tyre marks stay crisp under the rider
const CELLS := [0.0125, 0.025, 0.075, 0.1875]
const SAMPLES := [2, 2, 2, 3]           # samples per texel side (the bake's own anti-aliasing)
const TILE := 64                        # texels; a tile lies wholly in one 48 m chunk
const TILE_MIPS := 6                    # a tile's own mips go down to 1 texel (64 -> 1)
const AHEAD := 0.25                     # each window sits this share of its size ahead of the rider, along the view
const BUDGET := 24                      # tiles baked a frame (more while a lot is missing: a respawn / new world)
const BUDGET_RUSH := 160
const CHUNK := 48.0

var ok := false
var n := 0                              # texels per window side
var tex_a: Texture2DArrayRD
var tex_b: Texture2DArrayRD
var tex_c: Texture2DArrayRD
var info: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]   # per level: window min x, z (m), cell, n (0 = off)

var rd: RenderingDevice
var _ta: RID
var _tb: RID
var _tc: RID
var _views: Array = []                  # [level][mip] -> [A view, B view, C view]
var _samp: RID
var _dummy: RID
var _pbuf: RID
var _bake_sh: RID
var _bake_pipe: RID
var _mip_sh: RID
var _mip_pipe: RID
var _mip_sets: Array = []               # [level][mip 1..] -> uniform set
var _clear_sets: Array = []             # per level: a bake set with dummy inputs (the clear path)
var _sets := {}                         # "mat id:level" -> uniform set (render thread only)

var _nt := 0
var _tmin: Array[Vector2i] = []
var _ns := 0                            # slots per level (flat arrays below: index = level * _ns + slot)
var _st: Array[Vector2i] = []           # the world tile each slot holds
var _ss := PackedByteArray()            # 1 = waiting for a bake, 2 = baked, 3 = no chunk there yet
var _sm := PackedInt64Array()           # the chunk material a slot was baked from
var _serial := -1
var _params := PackedFloat32Array()
var _dirty_params := false
var _pending := 0
var _probe := Env.s("BMX_ROAD_PROBE") != ""
var _pr_t := 0.0
var _pr_baked := 0
var _pr_cleared := 0
var _pr_us := 0


func _init(quality: int) -> void:
	if quality <= 0: return
	rd = RenderingServer.get_rendering_device()
	if rd == null: return
	n = 1024 if quality >= 2 else 512
	_nt = n / TILE
	_params.resize(MAX_PARAMS)
	for i in PARAMS.size(): _params[i] = PARAMS[i][1]
	# the old per-material knobs' test overrides still work here
	if Env.s("BMX_TRAIL_PLAY") != "": _params[0] = float(Env.s("BMX_TRAIL_PLAY"))
	if Env.s("BMX_TRAIL_PUDDLES") != "": _params[1] = float(Env.s("BMX_TRAIL_PUDDLES"))
	for kv in Env.s("BMX_ROAD_SET").split(",", false):
		var p := kv.split("=")
		if p.size() == 2: _set_param_raw(p[0].strip_edges(), float(p[1]))
	_ns = _nt * _nt
	for l in CELLS.size(): _tmin.append(Vector2i(1 << 30, 1 << 30))
	_st.resize(_ns * CELLS.size()); _st.fill(Vector2i(1 << 30, 1 << 30))
	_ss.resize(_ns * CELLS.size())
	_sm.resize(_ns * CELLS.size())
	tex_a = Texture2DArrayRD.new(); tex_b = Texture2DArrayRD.new(); tex_c = Texture2DArrayRD.new()
	ok = true
	RenderingServer.call_on_render_thread(_gpu_create)


## a bake knob by name (PARAMS): everything baked is re-baked with it
func set_param(pname: String, v: float) -> void:
	if _set_param_raw(pname, v): _dirty_params = true


func get_param(pname: String) -> float:
	for i in PARAMS.size():
		if PARAMS[i][0] == pname: return _params[i]
	return 0.0


func _set_param_raw(pname: String, v: float) -> bool:
	for i in PARAMS.size():
		if PARAMS[i][0] == pname:
			if _params[i] == v: return false
			_params[i] = v
			return true
	push_warning("RoadDetail: no param '%s'" % pname)
	return false


## once a drawn frame. rider = the rider's xz, fwd = the camera's flat view direction, terrain = whose chunks to bake
func update(dt: float, rider: Vector2, fwd: Vector2, terrain: Terrain) -> void:
	if not ok or not _bake_pipe.is_valid(): return
	var t0 := Time.get_ticks_usec()
	if fwd.length() > 0.01: fwd = fwd.normalized()
	var serial: int = terrain.chunk_serial
	var rescan_all := serial != _serial
	_serial = serial
	if _dirty_params:
		_dirty_params = false
		RenderingServer.call_on_render_thread(_gpu_params.bind(_params.to_byte_array()))
		for i in _ss.size():
			if _ss[i] == 2: _ss[i] = 1
		_pending = 1
	var clears: Array = []
	for l in CELLS.size():
		var cell: float = CELLS[l]
		var tw := TILE * cell
		var c := rider + fwd * (n * cell * AHEAD)
		var tm := Vector2i(floori(c.x / tw) - _nt / 2, floori(c.y / tw) - _nt / 2)
		if tm != _tmin[l] or rescan_all:
			_tmin[l] = tm
			_rescan(l, terrain, clears)
		info[l] = Vector4(tm.x * tw, tm.y * tw, cell, n)
	# bake: the waiting tiles nearest the rider, finest level first
	var jobs: Array = []
	var mats: Array = []
	if _pending > 0 or not clears.is_empty():
		var cand: Array = []
		for i in _ss.size():
			if _ss[i] != 1: continue
			var l := i / _ns
			var w: Vector2i = _st[i]
			var mat := _chunk_mat(terrain, l, w)
			if mat == null:
				_ss[i] = 3   # no chunk there (yet): looked at again when chunks change
				continue
			var mid: Vector2 = (Vector2(w) + Vector2(0.5, 0.5)) * (TILE * float(CELLS[l]))
			cand.append([mid.distance_squared_to(rider) * (1.0 + l * 0.6), i, mat])
		_pending = cand.size()
		if not cand.is_empty():
			var budget := BUDGET_RUSH if cand.size() > 120 else BUDGET
			if cand.size() > budget: cand.sort_custom(func(a, b): return a[0] < b[0])
			for k in mini(budget, cand.size()):
				var i: int = cand[k][1]
				var mat: ShaderMaterial = cand[k][2]
				var l := i / _ns
				var w: Vector2i = _st[i]
				_ss[i] = 2
				_sm[i] = mat.get_instance_id()
				mats.append(mat)
				jobs.append([l, i % _ns, w, _chunk_centre(l, w), mat.get_instance_id()])
			_pending -= jobs.size()
	if not jobs.is_empty() or not clears.is_empty():
		RenderingServer.call_on_render_thread(_gpu_run.bind(jobs, clears, mats))
	if _probe:
		_pr_baked += jobs.size(); _pr_cleared += clears.size(); _pr_us += Time.get_ticks_usec() - t0; _pr_t += dt
		if _pr_t >= 1.0:
			print("ROAD baked=%d cleared=%d pending=%d cpu_ms=%.2f win0=(%.0f,%.0f)" % [_pr_baked, _pr_cleared, _pending, _pr_us / 1000.0, info[0].x, info[0].y])
			_pr_t = 0.0; _pr_baked = 0; _pr_cleared = 0; _pr_us = 0


## the window of level l moved (or chunks came / went): slots now standing for another tile are cleared and wait for a
## bake, baked slots whose chunk was rebuilt wait for a new one
func _rescan(l: int, terrain: Terrain, clears: Array) -> void:
	var tm: Vector2i = _tmin[l]
	for ty in _nt:
		for tx in _nt:
			var w := Vector2i(tm.x + tx, tm.y + ty)
			var s := posmod(w.x, _nt) + posmod(w.y, _nt) * _nt
			var i := l * _ns + s
			if _st[i] != w:
				_st[i] = w
				_ss[i] = 1
				_sm[i] = 0
				clears.append([l, s])
			elif _ss[i] == 2:
				var mat := _chunk_mat(terrain, l, w)
				if mat == null or mat.get_instance_id() != _sm[i]:
					_ss[i] = 1
					if mat == null: clears.append([l, s])
			elif _ss[i] == 3:
				_ss[i] = 1   # waiting for its chunk: try again
	_pending = 1


func _chunk_key(l: int, w: Vector2i) -> Vector2i:
	var tw: float = TILE * CELLS[l]
	var mid := (Vector2(w) + Vector2(0.5, 0.5)) * tw
	return Vector2i(floori((mid.x + CHUNK * 0.5) / CHUNK), floori((mid.y + CHUNK * 0.5) / CHUNK))


func _chunk_centre(l: int, w: Vector2i) -> Vector2:
	return Vector2(_chunk_key(l, w)) * CHUNK


func _chunk_mat(terrain: Terrain, l: int, w: Vector2i) -> ShaderMaterial:
	var rec = terrain.chunks.get(_chunk_key(l, w))
	if rec == null: return null
	var m = rec.get("mat")
	return m as ShaderMaterial


## off: the ground shader goes back to its per-pixel path. The globals are pointed at a placeholder first (every ground
## material binds them: a freed texture there is an error on every draw)
func free_gpu() -> void:
	if not ok: return
	ok = false
	info = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
	for g in ["road_a", "road_b", "road_c"]: RenderingServer.global_shader_parameter_set(g, placeholder())
	RenderingServer.call_on_render_thread(_gpu_free)


static var _ph: Texture2DArray
## a 1 x 1 x 3 texture array of zeros, for the road globals while no RoadDetail owns them
static func placeholder() -> Texture2DArray:
	if _ph == null:
		var imgs: Array[Image] = []
		for i in CELLS.size(): imgs.append(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
		_ph = Texture2DArray.new()
		_ph.create_from_images(imgs)
	return _ph


# ---------------------------------------------------------------- GPU (render thread)
func _fmt(df: int) -> RDTextureFormat:
	var f := RDTextureFormat.new()
	f.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	f.width = n; f.height = n; f.array_layers = CELLS.size()
	f.mipmaps = int(log(n) / log(2.0)) + 1
	f.format = df
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	return f


func _gpu_create() -> void:
	var fa := _fmt(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	_ta = rd.texture_create(fa, RDTextureView.new(), [])
	_tb = rd.texture_create(_fmt(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT), RDTextureView.new(), [])
	_tc = rd.texture_create(_fmt(RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM), RDTextureView.new(), [])
	# nothing baked: k = 1 (0.5 stored), flag 0, every mip (the ones past a tile's own read as "not here": the shader
	# then takes the next level, the right thing when the texels are that much smaller than the pixel)
	rd.texture_clear(_ta, Color(0.5, 0, 0, 0), 0, fa.mipmaps, 0, CELLS.size())
	rd.texture_clear(_tb, Color(0, 0, 0, 0), 0, fa.mipmaps, 0, CELLS.size())
	rd.texture_clear(_tc, Color(0, 0, 0, 0), 0, fa.mipmaps, 0, CELLS.size())
	for l in CELLS.size():
		var lv: Array = []
		for m in TILE_MIPS + 1:
			var v: Array = []
			for t in [_ta, _tb, _tc]:
				v.append(rd.texture_create_shared_from_slice(RDTextureView.new(), t, l, m, 1, RenderingDevice.TEXTURE_SLICE_2D))
			lv.append(v)
		_views.append(lv)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_samp = rd.sampler_create(ss)
	var df := RDTextureFormat.new()
	df.width = 2; df.height = 2
	df.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	df.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var zero := PackedByteArray(); zero.resize(16)
	_dummy = rd.texture_create(df, RDTextureView.new(), [zero])
	_pbuf = rd.storage_buffer_create(MAX_PARAMS * 4, _params.to_byte_array())
	var sb := _shader("res://shaders/road_detail_bake.glsl")
	var sm := _shader("res://shaders/road_detail_mip.glsl")
	if not sb.is_valid() or not sm.is_valid():
		ok = false
		return
	_bake_sh = sb; _mip_sh = sm
	_bake_pipe = rd.compute_pipeline_create(_bake_sh)
	_mip_pipe = rd.compute_pipeline_create(_mip_sh)
	for l in CELLS.size():
		var ms: Array = [RID()]
		for m in range(1, TILE_MIPS + 1):
			var a: Array = _views[l][m - 1]; var b: Array = _views[l][m]
			ms.append(rd.uniform_set_create([_img(0, a[0]), _img(1, a[1]), _img(2, a[2]), _img(3, b[0]), _img(4, b[1]), _img(5, b[2])], _mip_sh, 0))
		_mip_sets.append(ms)
		_clear_sets.append(_bake_set(l, _dummy, _dummy, _dummy, _dummy))
	tex_a.texture_rd_rid = _ta
	tex_b.texture_rd_rid = _tb
	tex_c.texture_rd_rid = _tc


func _shader(path: String) -> RID:
	var sf: RDShaderFile = load(path)
	var spirv := sf.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("road detail %s: %s" % [path, spirv.compile_error_compute])
		return RID()
	return rd.shader_create_from_spirv(spirv)


func _u(type: int, b: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = b
	for id in ids: u.add_id(id)
	return u


func _img(b: int, t: RID) -> RDUniform:
	return _u(RenderingDevice.UNIFORM_TYPE_IMAGE, b, [t])


func _tex(b: int, t: RID) -> RDUniform:
	return _u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, b, [_samp, t])


func _bake_set(l: int, t0: RID, t1: RID, t2: RID, t3: RID) -> RID:
	var v: Array = _views[l][0]
	return rd.uniform_set_create([_tex(0, t0), _tex(1, t1), _tex(2, t2), _tex(3, t3), _img(4, v[0]), _img(5, v[1]), _img(6, v[2]),
		_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 7, [_pbuf])], _bake_sh, 0)


func _rd_of(mat: ShaderMaterial, p: String) -> RID:
	var t := mat.get_shader_parameter(p) as Texture2D
	return RenderingServer.texture_get_rd_texture(t.get_rid()) if t != null else RID()


func _gpu_params(bytes: PackedByteArray) -> void:
	if _pbuf.is_valid(): rd.buffer_update(_pbuf, 0, bytes.size(), bytes)


func _gpu_run(jobs: Array, clears: Array, mats: Array) -> void:
	if not ok or not _bake_pipe.is_valid(): return
	var done: Array = []   # [level, slot] that need their mips
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _bake_pipe)
	for c in clears:
		var l: int = c[0]; var s: int = c[1]
		var pc := PackedFloat32Array([0, 0, CELLS[l], 1.0, 0, 0, 0, 0, (s % _nt) * TILE, (s / _nt) * TILE, 1, 0]).to_byte_array()
		rd.compute_list_bind_uniform_set(cl, _clear_sets[l], 0)
		rd.compute_list_set_push_constant(cl, pc, pc.size())
		rd.compute_list_dispatch(cl, TILE / 8, TILE / 8, 1)
		done.append(c)
	if not clears.is_empty(): rd.compute_list_add_barrier(cl)   # (a slot cleared and baked in one go: the clear first)
	for i in jobs.size():
		var j: Array = jobs[i]
		var l: int = j[0]; var s: int = j[1]; var w: Vector2i = j[2]; var cc: Vector2 = j[3]
		var mat: ShaderMaterial = mats[i]
		var key := "%d:%d" % [j[4], l]
		var us: RID = _sets.get(key, RID())
		if not us.is_valid() or not rd.uniform_set_is_valid(us):
			var r0 := _rd_of(mat, "trail_tex"); var r1 := _rd_of(mat, "trail2_tex"); var r2 := _rd_of(mat, "trail3_tex"); var r3 := _rd_of(mat, "land_tex")
			if not (r0.is_valid() and r1.is_valid() and r2.is_valid() and r3.is_valid()): continue
			us = _bake_set(l, r0, r1, r2, r3)
			_sets[key] = us
		var pc := PackedFloat32Array([w.x * TILE, w.y * TILE, CELLS[l], 0.0, cc.x, cc.y, 0, 0, (s % _nt) * TILE, (s / _nt) * TILE, SAMPLES[l], 0]).to_byte_array()
		rd.compute_list_bind_uniform_set(cl, us, 0)
		rd.compute_list_set_push_constant(cl, pc, pc.size())
		rd.compute_list_dispatch(cl, TILE / 8, TILE / 8, 1)
		done.append([l, s])
	rd.compute_list_add_barrier(cl)
	rd.compute_list_bind_compute_pipeline(cl, _mip_pipe)
	for m in range(1, TILE_MIPS + 1):
		var sz := TILE >> m
		for d in done:
			var l: int = d[0]; var s: int = d[1]
			var pc := PackedFloat32Array([((s % _nt) * TILE) >> m, ((s / _nt) * TILE) >> m, sz, 0]).to_byte_array()
			rd.compute_list_bind_uniform_set(cl, _mip_sets[l][m], 0)
			rd.compute_list_set_push_constant(cl, pc, pc.size())
			rd.compute_list_dispatch(cl, maxi(1, ceili(sz / 8.0)), maxi(1, ceili(sz / 8.0)), 1)
		rd.compute_list_add_barrier(cl)
	rd.compute_list_end()
	# drop cached sets of chunks gone (their textures freed the sets with them)
	if _sets.size() > 256:
		for k in _sets.keys():
			if not rd.uniform_set_is_valid(_sets[k]): _sets.erase(k)


func _gpu_free() -> void:
	for k in _sets: if rd.uniform_set_is_valid(_sets[k]): rd.free_rid(_sets[k])
	_sets.clear()
	for t in [_ta, _tb, _tc, _dummy, _pbuf]:   # (views, sets and pipelines that hang off them go with them)
		if t.is_valid(): rd.free_rid(t)
	for s in [_bake_sh, _mip_sh, _samp]:
		if s.is_valid(): rd.free_rid(s)
