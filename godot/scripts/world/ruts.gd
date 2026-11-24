extends Node
## Ruts (2026-11-24, MX vs ATV-style): the ground dug in where the tyres roll, deeper with every pass, and felt by the
## bike: the terrain's height() / deck_height() / top_height() subtract the depth (Terrain.rut_at), so a wheel drops into
## a groove, its walls tilt the ground under the tyre and the physics' side-slope knock steers the bike along it or kicks
## it crossing one. The field is C# (world/RutFieldCs.cs: sparse 8 m tiles of 5 cm cells, stamped once per pass).
## Made by Game in the test playground (for now) and in rides with BMX_RUTS=1. Tests: BMX_RUTS_PROBE=1 (RUTS lines).

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
var _probe := Env.s("BMX_RUTS_PROBE") != ""
var _probe_t := 0.0
var _us := 0
var _n := 0

func _init(g) -> void:
	game = g
	name = "Ruts"
	var sc = load("res://scripts/world/RutFieldCs.cs") if ClassDB.class_exists("CSharpScript") else null
	field = sc.new() if sc else null

func active() -> bool:
	return field != null

func clear() -> void:
	if field == null: return
	field.Clear()
	_publish()
	_win_tile = Vector2i(1 << 30, 0)
	_fcorner = Vector2i(1 << 30, 0)
	_fdirty.clear()

# ---- the ground shaders' window: 7 x 7 tiles (56 m) round the rider as an RH texture (shaders/ruts.gdshaderinc)
const WT := 7   # (56 m: the rider is always >= 24 m from every edge, and the fade is done by 20 m, even with the window 2 m behind at speed: the window never shows)
const FADE_A := 12.0
const FADE_B := 20.0
var _img: Image
var _tex: ImageTexture
var _win_tile := Vector2i(1 << 30, 0)   # the window's corner tile
var _up_t := 0.0
const UP_HZ := 10.0

func _process(dt: float) -> void:
	if field == null or game == null or game.phys == null: return
	var _t0 := Time.get_ticks_usec()
	_process_inner(dt)
	if _probe:
		var us := Time.get_ticks_usec() - _t0
		_pus += us; _pn += 1; _pmax = maxi(_pmax, us)
		if _pn >= 300:
			print("RUTSPROC avg_us=%.1f max_us=%d" % [float(_pus) / _pn, _pmax])
			_pus = 0; _pn = 0; _pmax = 0

var _pus := 0
var _pn := 0
var _pmax := 0

func _process_inner(dt: float) -> void:
	RenderingServer.global_shader_parameter_set("rut_ctr", Vector4(game.phys.x, game.phys.z, FADE_A, FADE_B))   # every frame: the fade follows the rider smoothly
	_up_t -= dt
	if _up_t > 0.0: return
	_up_t = 1.0 / UP_HZ
	var T: int = 160   # RutFieldCs.TILE
	var tile_m := T * 0.05
	var c := Vector2i(floori(game.phys.x / tile_m), floori(game.phys.z / tile_m))
	var corner := c - Vector2i(WT / 2, WT / 2)
	var dirty: PackedInt32Array = field.TakeDirty()
	for k in dirty.size() / 2: _fdirty[Vector2i(dirty[2 * k], dirty[2 * k + 1])] = true
	_far_update(c, tile_m)
	if _img == null:
		_img = Image.create_empty(T * WT, T * WT, false, Image.FORMAT_RH)
		_tex = ImageTexture.create_from_image(_img)
		RenderingServer.global_shader_parameter_set("rut_tex", _tex)
	var redo: Array = []
	if corner != _win_tile:
		_win_tile = corner
		_img.fill(Color(0, 0, 0))
		for j in WT:
			for i in WT: redo.append(corner + Vector2i(i, j))
	else:
		for k in dirty.size() / 2:
			var t := Vector2i(dirty[2 * k], dirty[2 * k + 1])
			if t.x >= corner.x and t.y >= corner.y and t.x < corner.x + WT and t.y < corner.y + WT: redo.append(t)
	if redo.is_empty() and _tex != null: return
	for t in redo:
		var b: PackedByteArray = field.TileRH(t.x, t.y)
		if b.is_empty(): continue
		var ti := Image.create_from_data(T, T, false, Image.FORMAT_RH, b)
		_img.blit_rect(ti, Rect2i(0, 0, T, T), Vector2i((t.x - corner.x) * T, (t.y - corner.y) * T))
	_tex.update(_img)
	RenderingServer.global_shader_parameter_set("rut_win", Vector4(corner.x * tile_m, corner.y * tile_m, tile_m * WT, 1.0))

# ---- the far layer: 25 x 25 tiles (200 m) at 25 cm a texel (the deepest cell of each 5 x 5), so every rut of the ride shows from afar
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
		_fimg = Image.create_empty(FT * FPX, FT * FPX, false, Image.FORMAT_RH)
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
		var b: PackedByteArray = field.TileRHFar(t.x, t.y)
		if b.is_empty(): continue
		var ti := Image.create_from_data(FPX, FPX, false, Image.FORMAT_RH, b)
		_fimg.blit_rect(ti, Rect2i(0, 0, FPX, FPX), Vector2i((t.x - corner.x) * FPX, (t.y - corner.y) * FPX))
	_ftex.update(_fimg)
	RenderingServer.global_shader_parameter_set("rut_far_win", Vector4(corner.x * tile_m, corner.y * tile_m, tile_m * FT, 1.0))

## the terrain's height queries read the field: only near the bike (READ_R; the camera, sheep, decorations... far off
## never call it) and inside what was dug. The C# tyre fit gets the field once.
const READ_R := 20.0
var _fcs_set := false
func _publish() -> void:
	var t = game.terrain
	if t == null: return
	t.rut_field = field
	var b: Vector4 = field.Bounds()
	var px: float = game.phys.x if game.phys else 0.0
	var pz: float = game.phys.z if game.phys else 0.0
	t.rut_box = Vector4(maxf(b.x, px - READ_R), maxf(b.y, pz - READ_R), minf(b.z, px + READ_R), minf(b.w, pz + READ_R))
	if not _fcs_set and t.get("fcs") != null and t.fcs.has_method("set_ruts"):
		t.fcs.set_ruts(field); _fcs_set = true

## each physics step, after the bike moved: both tyres dig the stretch they rolled
func step(st) -> void:
	if field == null or st.crash_on or st.air: return
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
		var dig: Array = DIG.get(surf, DIG[1])
		var n: float = float(st.n_front if w == 0 else st.n_rear)
		var load_k := clampf(n / (g * 0.5), LOAD_MIN, LOAD_MAX)
		var add: float = dig[0] * load_k * (SKID if (w == 1 and st.skid) else 1.0)
		# sliding sideways the tyre's patch sweeps across its path: the groove widens with the slide angle (patch ~10 cm
		# long, 9 cm wide), a locked rear scrubs a bit wider even straight. The dig spreads over the wider band.
		var hw := HALF_W
		if w == 1:
			var s := absf(st.slip)
			hw = maxf(HALF_W, 0.5 * (PATCH_L * sin(minf(s, PI * 0.5)) + 2.0 * HALF_W * cos(minf(s, PI * 0.5))) + 0.01)
			if st.skid: hw *= SKID_WIDEN
			add *= HALF_W / hw
		field.Stamp(w, x, z, minf(hw, 0.2), add, dig[1], LIP)
	_publish()
	_us += Time.get_ticks_usec() - t0; _n += 1
	if _probe:
		_probe_t += 1.0 / 120.0
		if _probe_t > 1.0:
			_probe_t = 0.0
			var rx: float = st.x - f.x * st.BB_REAR; var rz: float = st.z - f.z * st.BB_REAR
			print("RUTS tiles=%d stamp_us=%.1f under_rear=%.1f mm under_front=%.1f mm knock=%.3f v=%.1f" % [field.TileCount(), float(_us) / maxi(_n, 1),
				field.Depth(rx, rz) * 1000.0, field.Depth(st.x + f.x * (st.L - st.BB_REAR), st.z + f.z * (st.L - st.BB_REAR)) * 1000.0, st.knock, st.v])
			_us = 0; _n = 0
