extends Node
## Ruts + tyre prints: where tyres rolled, kept in the ground itself (off-road-game style).
## Ruts (2026-11-24, MX vs ATV-style): the ground dug in where the tyres roll, deeper with every pass, and felt by the
## bike: the terrain's height() / deck_height() / top_height() subtract the depth (Terrain.rut_at), so a wheel drops into
## a groove, its walls tilt the ground under the tyre and the physics' side-slope knock steers the bike along it or kicks
## it crossing one. Tyre prints (2026-11-25, were a mesh ribbon in fx.gd): the tread pressed into the ground, drawn by
## the ground shaders from the same field (knob dimples, skid smears, blood), lit and mipmapped like the ground.
## The field is C# (world/RutFieldCs.cs: sparse 8 m tiles of 5 cm cells, stamped once per pass). The ground shaders read
## it through a toroidal GPU window round the rider (shaders/rut_upload.glsl writes the tiles in, ruts.gdshaderinc reads)
## and a coarse far layer. Made by Game in rides, built levels and the test playground. Settings › Gameplay › Ruts only
## switches the DIGGING (the physics' grooves); the prints are always on. Tests: BMX_RUTS_PROBE=1 (RUTS / RUTSWIN lines),
## BMX_RUTS=0|1 (digging), BMX_NO_TRACKS=1 (no prints).

## per surface (0 grass, 1 trail / dirt, 2 water / wet, 3 sand): [depth a pass adds in the groove's middle (m), most it gets]
const DIG := {0: [0.004, 0.035], 1: [0.007, 0.07], 2: [0.012, 0.09], 3: [0.02, 0.11]}
const HALF_W := 0.045      # m: the groove is a bit wider than the tyre
const LIP := 0.4           # share of the dig pushed up beside it
const LOAD_MIN := 0.3      # x the dig: a light tyre barely marks it, a landing digs in
const LOAD_MAX := 3.0
const SKID := 2.0          # x the dig under a locked rear
const PATCH_L := 0.10      # m: the rear tyre's contact patch length (a slide sweeps it sideways)
const SKID_WIDEN := 1.35   # a locked rear scrubs this much wider

var game
var field = null           # RutFieldCs
var dig := true            # the physics' grooves (Settings "ruts"); off = prints only
var prints := Env.s("BMX_NO_TRACKS") == ""
var _probe := Env.s("BMX_RUTS_PROBE") != ""
var _probe_t := 0.0
var _us := 0
var _n := 0

func _init(g) -> void:
	game = g
	name = "Ruts"
	var sc = load("res://scripts/world/RutFieldCs.cs") if ClassDB.class_exists("CSharpScript") else null
	field = sc.new() if sc else null
	if field != null: _gpu_init()

func active() -> bool:
	return field != null

func clear() -> void:
	if field == null: return
	field.Clear()
	_publish()
	_slot_tile.fill(Vector2i(1 << 30, 0))
	_win_tile = Vector2i(1 << 30, 0)
	_fcorner = Vector2i(1 << 30, 0)
	_fdirty.clear()

## a tyre's print for this frame (fx.gd track() hands it here): wheel 0 front / 1 rear, strength 0 = lifted
func track(wheel: int, contact: Vector3, strength: float, width: float, smear: bool, blood: float) -> void:
	if field == null or not prints: return
	field.StampTrack(wheel, contact.x, contact.z, width * 0.5, strength, smear, blood)

# ---- the ground shaders' near window: WT x WT tiles round the rider, toroidal on the GPU (only the tiles that come in,
# or were dug / printed, are copied in: shaders/rut_upload.glsl). 88 m: the rider is always >= 36 m from its edges, the
# near layer dissolves into the far one by 34 m (distance from the RIDER, so the window's hops never show)
const WT := 11
const T := 160             # RutFieldCs.TILE
const FADE_A := 26.0
const FADE_B := 34.0
const UP_HZ := 10.0
const BUDGET := 24         # tiles copied an update (a respawn fills the window over a few updates)
var _rd: RenderingDevice
var _ta: RID               # rgba16f: depth, prints' edge distance, strength, blood
var _tb: RID               # rgba8: skid smear, print direction
var _buf: RID
var _sh: RID
var _pipe: RID
var _set: RID
var _tex_a: Texture2DRD
var _tex_b: Texture2DRD
var _slot_tile: Array[Vector2i] = []
var _need := {}            # world tile -> true: copy it in (or clear its place) when the budget allows
var _win_tile := Vector2i(1 << 30, 0)   # the window's corner tile
var _up_t := 0.0
var _ok := false

## the tyre's tread as a small tiling texture WITH MIPMAPS (racing-game style detail texture): the ground shaders draw
## the knobs from it, so they show as far as a pixel can resolve them and blur into their average beyond that, never
## shimmering. x = across the print 0 (middle) .. 1 (its edge) (the pattern is symmetric), y = two knob rows along it
## (4.8 cm, repeats). R = depth of the knob dimples 0..1 (a downhill tyre: a pair of centre knobs, then a centre knob +
## shoulder knobs). Made once.
const TREAD_W := 64
const TREAD_H := 128
const TREAD_ROW := 0.024
static var _tread: ImageTexture
static func tread_texture() -> ImageTexture:
	if _tread != null: return _tread
	var img := Image.create_empty(TREAD_W, TREAD_H, false, Image.FORMAT_R8)
	for j in TREAD_H:
		var v := (j + 0.5) / TREAD_H * 2.0 * TREAD_ROW   # metres along
		for i in TREAD_W:
			var u := (i + 0.5) / TREAD_W                  # across, 0 middle .. 1 edge
			img.set_pixel(i, j, Color(_tread_at(u, v), 0, 0))
	img.generate_mipmaps()
	_tread = ImageTexture.create_from_image(img)
	return _tread

static func _knob(px: float, py: float, hx: float, hy: float, soft: float) -> float:
	var dx := absf(px) - hx
	var dy := absf(py) - hy
	var sd := Vector2(maxf(dx, 0.0), maxf(dy, 0.0)).length() + minf(maxf(dx, dy), 0.0)
	return 1.0 - smoothstep(-soft, soft, sd)

## the pattern is SYMMETRIC along the print (rows centred on v = r x ROW, knobs symmetric about their row): the
## ground shader reads the direction from a doubled angle, whose half can come out either way round between
## neighbouring cells; a pattern that isn't the same both ways then mirrored cell by cell (a zigzag)
static func _tread_at(u: float, v: float) -> float:
	var r := roundf(v / TREAD_ROW)
	var f := v - r * TREAD_ROW
	var x := u * 0.5
	if fposmod(r, 2.0) < 0.5:
		return maxf(_knob(x - 0.17, f, 0.09, 0.006, 0.006), _knob(x + 0.17, f, 0.09, 0.006, 0.006))
	var h := _knob(x, f, 0.08, 0.007, 0.006)
	return maxf(h, _knob(absf(x) - 0.38, f, 0.07, 0.005, 0.006))

func _gpu_init() -> void:
	RenderingServer.global_shader_parameter_set("rut_tread_tex", tread_texture())
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	_slot_tile.resize(WT * WT); _slot_tile.fill(Vector2i(1 << 30, 0))
	_tex_a = Texture2DRD.new(); _tex_b = Texture2DRD.new()
	RenderingServer.call_on_render_thread(_gpu_create)

func _gpu_create() -> void:
	var n := WT * T
	var fa := RDTextureFormat.new()
	fa.width = n; fa.height = n
	fa.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fa.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	_ta = _rd.texture_create(fa, RDTextureView.new(), [])
	var fb := RDTextureFormat.new()
	fb.width = n; fb.height = n
	fb.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fb.usage_bits = fa.usage_bits
	_tb = _rd.texture_create(fb, RDTextureView.new(), [])
	_rd.texture_clear(_ta, Color(0, 9.0, 0, 0), 0, 1, 0, 1)   # (edge distance 9 = RutFieldCs.NO_E: no print here)
	_rd.texture_clear(_tb, Color(0.0, 0.5, 0.5, 0), 0, 1, 0, 1)
	_buf = _rd.storage_buffer_create(BUDGET * T * T * 16)
	var sf: RDShaderFile = load("res://shaders/rut_upload.glsl")
	var spirv := sf.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("ruts upload: %s" % spirv.compile_error_compute)
		return
	_sh = _rd.shader_create_from_spirv(spirv)
	_pipe = _rd.compute_pipeline_create(_sh)
	var us: Array[RDUniform] = []
	for b in [[RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0, _buf], [RenderingDevice.UNIFORM_TYPE_IMAGE, 1, _ta], [RenderingDevice.UNIFORM_TYPE_IMAGE, 2, _tb]]:
		var u := RDUniform.new()
		u.uniform_type = b[0]; u.binding = b[1]; u.add_id(b[2])
		us.append(u)
	_set = _rd.uniform_set_create(us, _sh, 0)
	_tex_a.texture_rd_rid = _ta
	_tex_b.texture_rd_rid = _tb
	_ok = true

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	# the globals stop pointing at this window's textures before they are freed (every ground material binds them)
	RenderingServer.global_shader_parameter_set("rut_win", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("rut_far_win", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("rut_tex", _placeholder())
	RenderingServer.global_shader_parameter_set("rut_dir_tex", _placeholder())
	if _rd != null:
		_ok = false
		for r in [_ta, _tb, _buf, _sh]:   # (the uniform set and pipeline go with them)
			if r.is_valid(): _rd.free_rid(r)

static var _ph: ImageTexture
static func _placeholder() -> ImageTexture:
	if _ph == null: _ph = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBAH))
	return _ph

func _process(dt: float) -> void:
	if field == null or game == null or game.phys == null: return
	var _t0 := Time.get_ticks_usec()
	_process_inner(dt)
	if _probe:
		var us := Time.get_ticks_usec() - _t0
		_pus += us; _pn += 1; _pmax = maxi(_pmax, us)
		if _pn >= 300:
			print("RUTSPROC avg_us=%.1f max_us=%d need=%d" % [float(_pus) / _pn, _pmax, _need.size()])
			_pus = 0; _pn = 0; _pmax = 0

var _pus := 0
var _pn := 0
var _pmax := 0

func _process_inner(dt: float) -> void:
	RenderingServer.global_shader_parameter_set("rut_ctr", Vector4(game.phys.x, game.phys.z, FADE_A, FADE_B))   # every frame: the fade follows the rider smoothly
	_up_t -= dt
	if _up_t > 0.0: return
	_up_t = 1.0 / UP_HZ
	var tile_m := T * 0.05
	var c := Vector2i(floori(game.phys.x / tile_m), floori(game.phys.z / tile_m))
	var corner := c - Vector2i(WT / 2, WT / 2)
	var dirty: PackedInt32Array = field.TakeDirty()
	for k in dirty.size() / 2: _fdirty[Vector2i(dirty[2 * k], dirty[2 * k + 1])] = true
	_far_update(c, tile_m)
	if not _ok: return
	if corner != _win_tile:
		_win_tile = corner
		for j in WT:
			for i in WT:
				var t := corner + Vector2i(i, j)
				var s := posmod(t.x, WT) + posmod(t.y, WT) * WT
				if _slot_tile[s] != t:
					_slot_tile[s] = t
					_need[t] = true
		RenderingServer.global_shader_parameter_set("rut_tex", _tex_a)
		RenderingServer.global_shader_parameter_set("rut_dir_tex", _tex_b)
		RenderingServer.global_shader_parameter_set("rut_win", Vector4(corner.x * tile_m, corner.y * tile_m, tile_m * WT, 1.0))
	for k in dirty.size() / 2:
		var t := Vector2i(dirty[2 * k], dirty[2 * k + 1])
		if t.x >= corner.x and t.y >= corner.y and t.x < corner.x + WT and t.y < corner.y + WT: _need[t] = true
	if _need.is_empty(): return
	# nearest first
	var ts: Array = _need.keys()
	if ts.size() > BUDGET: ts.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	var bytes := PackedByteArray()
	var jobs: Array = []
	var nb := 0
	for t in ts.slice(0, BUDGET):
		_need.erase(t)
		if t.x < corner.x or t.y < corner.y or t.x >= corner.x + WT or t.y >= corner.y + WT: continue   # (left the window meanwhile)
		var b: PackedByteArray = field.TilePack(t.x, t.y)
		var place := Vector2(posmod(t.x, WT) * T, posmod(t.y, WT) * T)
		if b.is_empty():
			jobs.append([place, 0, 1.0])
		else:
			bytes.append_array(b)
			jobs.append([place, nb * T * T, 0.0])
			nb += 1
	RenderingServer.call_on_render_thread(_gpu_copy.bind(bytes, jobs))
	_win_count += jobs.size()

var _win_count := 0

func _gpu_copy(bytes: PackedByteArray, jobs: Array) -> void:
	if not _pipe.is_valid(): return
	if not bytes.is_empty(): _rd.buffer_update(_buf, 0, bytes.size(), bytes)
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	_rd.compute_list_bind_uniform_set(cl, _set, 0)
	for j in jobs:
		var p: Vector2 = j[0]
		var pc := PackedFloat32Array([p.x, p.y, float(j[1]), j[2]]).to_byte_array()
		_rd.compute_list_set_push_constant(cl, pc, pc.size())
		_rd.compute_list_dispatch(cl, T / 8, T / 8, 1)
	_rd.compute_list_end()

# ---- the far layer: 25 x 25 tiles (200 m) at 25 cm a texel (the deepest cell + the prints' cover of each 5 x 5), so
# every rut and print of the ride shows from afar
const FT := 25
const FPX := 32            # texels a tile side (160 / 5)
var _fimg: Image
var _ftex: ImageTexture
var _fcorner := Vector2i(1 << 30, 0)
var _fdirty := {}
var _fup_t := 0.0
const FAR_HZ := 4.0

func _far_update(c: Vector2i, tile_m: float) -> void:
	_fup_t -= 1.0 / UP_HZ
	if _fup_t > 0.0: return
	_fup_t = 1.0 / FAR_HZ
	var corner := c - Vector2i(FT / 2, FT / 2)
	if _fimg == null:
		_fimg = Image.create_empty(FT * FPX, FT * FPX, false, Image.FORMAT_RGH)
		_ftex = ImageTexture.create_from_image(_fimg)
		RenderingServer.global_shader_parameter_set("rut_far_tex", _ftex)
	var redo: Array = []
	if corner != _fcorner:
		_fcorner = corner
		_fimg.fill(Color(0, 0, 0))
		for j in FT:
			for i in FT: redo.append(corner + Vector2i(i, j))
	else:
		for t in _fdirty:
			if t.x >= corner.x and t.y >= corner.y and t.x < corner.x + FT and t.y < corner.y + FT: redo.append(t)
	_fdirty.clear()
	if redo.is_empty(): return
	for t in redo:
		var b: PackedByteArray = field.TileRGFar(t.x, t.y)
		if b.is_empty(): continue
		var ti := Image.create_from_data(FPX, FPX, false, Image.FORMAT_RGH, b)
		_fimg.blit_rect(ti, Rect2i(0, 0, FPX, FPX), Vector2i((t.x - corner.x) * FPX, (t.y - corner.y) * FPX))
	_ftex.update(_fimg)
	RenderingServer.global_shader_parameter_set("rut_far_win", Vector4(corner.x * tile_m, corner.y * tile_m, tile_m * FT, 1.0))

## the terrain's height queries read the field: only near the bike (READ_R; the camera, sheep, decorations... far off
## never call it) and inside what was dug. The C# tyre fit gets the field once.
const READ_R := 20.0
var _fcs_set := false
func _publish() -> void:
	var t = game.terrain
	if t == null or not dig: return
	t.rut_field = field
	var b: Vector4 = field.Bounds()
	var px: float = game.phys.x if game.phys else 0.0
	var pz: float = game.phys.z if game.phys else 0.0
	t.rut_box = Vector4(maxf(b.x, px - READ_R), maxf(b.y, pz - READ_R), minf(b.z, px + READ_R), minf(b.w, pz + READ_R))
	if not _fcs_set and t.get("fcs") != null and t.fcs.has_method("set_ruts"):
		t.fcs.set_ruts(field); _fcs_set = true

## each physics step, after the bike moved: both tyres dig the stretch they rolled
func step(st) -> void:
	if field == null or not dig or st.crash_on or st.air: return
	var t0 := Time.get_ticks_usec()
	var f: Vector3 = st.fwd()
	var g := 9.81
	for w in 2:
		var on: bool = st.c_f if w == 0 else st.c_r
		if not on: continue
		var d: float = (st.L - st.BB_REAR) if w == 0 else -st.BB_REAR
		var x: float = st.x + f.x * d
		var z: float = st.z + f.z * d
		var surf: int = game.terrain.surface(x, z)
		var dg: Array = DIG.get(surf, DIG[1])
		var n: float = float(st.n_front if w == 0 else st.n_rear)
		var load_k := clampf(n / (g * 0.5), LOAD_MIN, LOAD_MAX)
		var add: float = dg[0] * load_k * (SKID if (w == 1 and st.skid) else 1.0)
		# sliding sideways the tyre's patch sweeps across its path: the groove widens with the slide angle (patch ~10 cm
		# long, 9 cm wide), a locked rear scrubs a bit wider even straight. The dig spreads over the wider band.
		var hw := HALF_W
		if w == 1:
			var s := absf(st.slip)
			hw = maxf(HALF_W, 0.5 * (PATCH_L * sin(minf(s, PI * 0.5)) + 2.0 * HALF_W * cos(minf(s, PI * 0.5))) + 0.01)
			if st.skid: hw *= SKID_WIDEN
			add *= HALF_W / hw
		field.Stamp(w, x, z, minf(hw, 0.2), add, dg[1], LIP)
	_publish()
	_us += Time.get_ticks_usec() - t0; _n += 1
	if _probe:
		_probe_t += 1.0 / 120.0
		if _probe_t > 1.0:
			_probe_t = 0.0
			var rx: float = st.x - f.x * st.BB_REAR; var rz: float = st.z - f.z * st.BB_REAR
			print("RUTS tiles=%d stamp_us=%.1f under_rear=%.1f mm under_front=%.1f mm knock=%.3f v=%.1f win_copies=%d" % [field.TileCount(), float(_us) / maxi(_n, 1),
				field.Depth(rx, rz) * 1000.0, field.Depth(st.x + f.x * (st.L - st.BB_REAR), st.z + f.z * (st.L - st.BB_REAR)) * 1000.0, st.knock, st.v, _win_count])
			_us = 0; _n = 0; _win_count = 0
