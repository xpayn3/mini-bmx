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

# ---- the ground shaders' window: 5 x 5 tiles (40 m) round the rider as an RH texture (shaders/ruts.gdshaderinc)
const WT := 5
var _img: Image
var _tex: ImageTexture
var _win_tile := Vector2i(1 << 30, 0)   # the window's corner tile
var _up_t := 0.0
const UP_HZ := 10.0

func _process(dt: float) -> void:
	if field == null or game == null or game.phys == null: return
	_up_t -= dt
	if _up_t > 0.0: return
	_up_t = 1.0 / UP_HZ
	var T: int = 160   # RutFieldCs.TILE
	var tile_m := T * 0.05
	var c := Vector2i(floori(game.phys.x / tile_m), floori(game.phys.z / tile_m))
	var corner := c - Vector2i(WT / 2, WT / 2)
	var dirty: PackedInt32Array = field.TakeDirty()
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

## the terrain's height queries read the field (inside its bounds only)
func _publish() -> void:
	var t = game.terrain
	if t == null: return
	t.rut_field = field
	t.rut_box = field.Bounds()

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
		field.Stamp(w, x, z, HALF_W, add, dig[1], LIP)
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
