extends Node3D
## The ghost rider (2026-11-24): your best run on this world (seed + bike) rides with you, a see-through glowing
## figure, and the HUD shows how far ahead / behind it you are.
##
## Recording: 30 samples a second of only what the figure needs: the rider's 15 joints (Ragdoll order; in a crash the
## ragdoll's points, so its falls replay too), 6 bike points (rear axle, crank, saddle, steering pivot, bar middle,
## front axle), the wheels' axle direction, the time and how far down the trail (`s`, m). 68 floats a sample.
## A run starts at the start of a world (ride start, Backspace, new world) and ends at the next one / leaving the ride.
## It replaces the saved ghost when it is the better one: further down the trail at the time the shorter of the two
## ended (runs under 15 s don't count). Saved per seed + bike in user://ghosts/ (tests: user://ghosts/tests/).
##
## Drawing: NOT a second copy of the rider + bike (that was ~275 draw calls): limbs, torso, helmet and frame tubes are
## instances of one low-poly capsule in one MultiMesh, the wheels two rings in another; one unshaded rim-glow shader,
## no shadows, never in the depth buffer. 2 draw calls, ~2.5k triangles. It fades where it overlaps you (it would
## hide the bike) and near the camera.
## Settings › Gameplay › Ghost rider (`ghost`). Tests: BMX_GHOST_PROBE=1 (GHOST lines), BMX_GHOST_SHOT=png.

const HZ := 30.0
const F := 68                 # floats per sample
const MAX_T := 900.0          # s recorded per run at most
const MIN_RUN := 15.0         # s: shorter runs never replace the ghost
const BONES := [[0, 1, 0.055], [1, 2, 0.11], [1, 3, 0.06], [1, 6, 0.06], [3, 4, 0.045], [4, 5, 0.038],
	[6, 7, 0.045], [7, 8, 0.038], [2, 9, 0.07], [2, 12, 0.07], [9, 10, 0.062], [10, 11, 0.05],
	[12, 13, 0.062], [13, 14, 0.05]]   # [joint a, joint b, radius]
const FRAME := [[0, 1, 0.03], [1, 2, 0.034], [2, 3, 0.036], [3, 1, 0.042], [0, 2, 0.026], [3, 4, 0.028],
	[3, 5, 0.034]]   # bike points: 0 rear axle, 1 crank, 2 saddle, 3 steering pivot, 4 bar middle, 5 front axle
const COL_RIDER := Color(0.55, 0.9, 1.0)
const COL_BIKE := Color(0.75, 0.95, 1.0)

var game
var enabled := true
var _rec := PackedFloat32Array()   # this run
var _rec_t := 0.0                  # its clock
var _rec_next := 0.0
var _ghost := PackedFloat32Array() # the saved best run
var _gi := 0                       # sample index cursor into _ghost
var _s_track := 0                  # trail index cursor (player)
var _have_ghost := false
var _key := ""
var _probe := Env.s("BMX_GHOST_PROBE") != ""
var _probe_t := 0.0

var _mm_body: MultiMesh
var _mm_wheel: MultiMesh
var _mat: ShaderMaterial
var _label: Label
var _hud_layer: CanvasLayer
var _gap_s := 0.0

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform float fade = 1.0;
uniform vec3 player = vec3(0.0, -1e6, 0.0);
varying vec3 v_world;
varying vec4 v_col;
void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	// a soft band that drifts up the figure (alive, not a solid ghost)
	float band = 0.5 + 0.5 * sin(v_world.y * 18.0 - TIME * 3.0);
	float a = (0.1 + 0.55 * rim + 0.06 * band) * fade;
	// where it overlaps the real rider + bike it all but vanishes (it would cover the bike)
	a *= mix(0.18, 1.0, smoothstep(0.6, 1.6, distance(v_world, player)));
	// and close to the camera (it may pass through it)
	a *= smoothstep(0.6, 2.2, length(VERTEX));
	ALBEDO = v_col.rgb * (0.9 + 0.8 * rim);
	ALPHA = clamp(a, 0.0, 0.85);
}
"""

func _init(g) -> void:
	game = g
	name = "GhostRider"
	top_level = true

func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new(); sh.code = SHADER
	_mat.shader = sh
	var cap := CapsuleMesh.new()
	cap.radius = 0.5; cap.height = 2.0; cap.radial_segments = 8; cap.rings = 2
	_mm_body = _make_mm(cap, BONES.size() + FRAME.size() + 1)   # + the helmet
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86; ring.outer_radius = 1.0; ring.rings = 28; ring.ring_segments = 6
	_mm_wheel = _make_mm(ring, 2)
	_hud_layer = CanvasLayer.new(); _hud_layer.layer = 5
	_label = Label.new()
	_label.add_theme_font_override("font", UITheme.display_font(700, 0.0))
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("outline_size", 6)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-120, 172); _label.size = Vector2(240, 36)   # (under the area banner)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.visible = false
	_hud_layer.add_child(_label)
	add_child(_hud_layer)
	enabled = bool(Settings.get_v("ghost")) if Settings.DEFAULTS.has("ghost") else true

func _make_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))   # (instances are in world space)
	add_child(mi)
	return mm

# ---------------------------------------------------------------- runs

func _dir() -> String:
	var d := "user://ghosts/tests" if Settings._test_run else "user://ghosts"
	DirAccess.make_dir_recursive_absolute(d)
	return d

## a new run from the start of this world: the old one is kept if it was the better, the world's ghost loaded
func start_run() -> void:
	end_run()
	_key = "%d_%s" % [GameState.seed, GameState.bike_id]
	if str(GameState.level).ends_with(".tscn"):   # a built level: its own ghost per bike
		_key = "level_%s_%s" % [str(GameState.level).get_file().get_basename(), GameState.bike_id]
	_rec = PackedFloat32Array(); _rec_t = 0.0; _rec_next = 0.0
	_gi = 0; _s_track = 0
	_ghost = PackedFloat32Array(); _have_ghost = false
	var f := FileAccess.open("%s/%s.ghost" % [_dir(), _key], FileAccess.READ)
	if f:
		var raw_size := f.get_32()   # (decompress_dynamic doesn't do zstd: the raw size is stored first)
		var b := f.get_buffer(f.get_length() - 4)
		f.close()
		if raw_size > 0 and raw_size < 64 * 1024 * 1024:
			_ghost = b.decompress(raw_size, FileAccess.COMPRESSION_ZSTD).to_float32_array()
		_have_ghost = _ghost.size() >= F * 2
	if _probe: print("GHOST start key=%s loaded=%s samples=%d" % [_key, _have_ghost, _ghost.size() / F])

## the run so far: saved if it beats the world's ghost
func end_run() -> void:
	if _key == "" or _rec.size() < F * 2: return
	var dur: float = _rec[_rec.size() - F]
	if dur < MIN_RUN: return
	var better := not _have_ghost
	if _have_ghost:
		var t_cmp := minf(dur, _ghost[_ghost.size() - F])
		better = _s_at(_rec, t_cmp) > _s_at(_ghost, t_cmp) + 1.0
	if _probe: print("GHOST end key=%s dur=%.1f s_end=%.0f better=%s" % [_key, dur, _rec[_rec.size() - F + 1], better])
	if not better: return
	var f := FileAccess.open("%s/%s.ghost" % [_dir(), _key], FileAccess.WRITE)
	if f == null: return
	var raw := _rec.to_byte_array()
	f.store_32(raw.size())
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	_rec = PackedFloat32Array()

## trail distance the run had reached at time t (s are kept as the furthest so far, so it only grows)
func _s_at(buf: PackedFloat32Array, t: float) -> float:
	var n := buf.size() / F
	var i := clampi(int(t * HZ), 0, n - 1)
	return buf[i * F + 1]

## time the run first reached trail distance s (binary search: s only grows); -1 = never
func _t_at_s(buf: PackedFloat32Array, s: float) -> float:
	var n := buf.size() / F
	if n == 0 or buf[(n - 1) * F + 1] < s: return -1.0
	var lo := 0; var hi := n - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if buf[mid * F + 1] < s: lo = mid + 1
		else: hi = mid
	return buf[lo * F]

## nearest trail point to (x, z), searched round the last one (the trail is a 2 m polyline)
func _trail_s(x: float, z: float, cur: int) -> int:
	var c = game.terrain.field.course if game.terrain and game.terrain.field else null
	if c == null or c.n < 2: return cur
	var best := cur; var bd := INF
	for i in range(maxi(0, cur - 20), mini(c.n - 1, cur + 40)):
		var dx: float = c.X[i] - x; var dz: float = c.Z[i] - z
		var d := dx * dx + dz * dz
		if d < bd: bd = d; best = i
	return best

# ---------------------------------------------------------------- per frame

func _process(dt: float) -> void:
	if game == null or game.phys == null or _key == "": return
	if game.photo or game.replay_on or get_tree().paused: _show(false); return
	var st = game.phys
	_rec_t += dt
	# record (a fixed 30 Hz)
	# (one sample per 1/30 s slot, also when a frame spans several: playback reads sample i as time i / 30, so with
	# one per FRAME a run recorded under 30 fps played back too fast and "finished" early)
	if _rec_t >= _rec_next and _rec_t < MAX_T:
		_s_track = _trail_s(st.x, st.z, _s_track)
		var s := maxf(float(_s_track) * 2.0, _rec[_rec.size() - F + 1] if _rec.size() >= F else 0.0)
		var smp := _sample(s)
		while _rec_t >= _rec_next:
			_rec_next += 1.0 / HZ
			_rec.append_array(smp)
	if not enabled or not _have_ghost:
		_show(false); return
	# the ghost at this run's time
	var n := _ghost.size() / F
	var ft := _rec_t * HZ
	var i := clampi(int(ft), 0, n - 2)
	var k := clampf(ft - i, 0.0, 1.0)
	var done := _rec_t > _ghost[(n - 1) * F]
	_draw(i, k, done)
	# the gap: when the ghost reached where you are now (+ = you're behind)
	var my_s := _rec[_rec.size() - F + 1] if _rec.size() >= F else 0.0
	var tg := _t_at_s(_ghost, my_s)
	if tg >= 0.0: _gap_s = lerpf(_gap_s, _rec_t - tg, minf(1.0, dt * 4.0))
	_label.visible = game.hud == null or game.hud.visible
	if done: _label.text = "GHOST FINISHED"
	elif tg >= 0.0:
		_label.text = "GHOST %s%.1f s" % ["+" if _gap_s >= 0.0 else "-", absf(_gap_s)]
		_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if _gap_s > 0.05 else Color(0.55, 1.0, 0.65))
	else: _label.text = "GHOST: AHEAD OF IT"
	if _probe:
		_probe_t += dt
		if _probe_t > 1.0:
			_probe_t = 0.0
			print("GHOST t=%.1f my_s=%.0f gap=%.2f s samples=%d" % [_rec_t, my_s, _gap_s, _rec.size() / F])

func _show(on: bool) -> void:
	for c in get_children():
		if c is MultiMeshInstance3D: c.visible = on
	if _label: _label.visible = on and _label.visible

func _sample(s: float) -> PackedFloat32Array:
	var o := PackedFloat32Array(); o.resize(F)
	o[0] = _rec_t; o[1] = s
	var st = game.phys
	var rag = game.ragdoll
	var crashed: bool = st.crash_on and rag != null and rag.p.size() >= 15
	var rx: Transform3D = game.rider.global_transform
	for j in 15:
		var p: Vector3 = (rag.p[j] as Vector3) if crashed else rx * (game.rider.J[j] as Vector3)
		o[2 + j * 3] = p.x; o[3 + j * 3] = p.y; o[4 + j * 3] = p.z
	var rig = game.rig
	var pts := [rig.wheel_r.global_position, rig.crank_n.global_position, _saddle_point(rig),
		rig.steer_n.global_position, rig.steer_n.global_transform * ((rig.grip_l + rig.grip_r) * 0.5), rig.wheel_f.global_position]
	for j in 6:
		var p: Vector3 = pts[j]
		o[47 + j * 3] = p.x; o[48 + j * 3] = p.y; o[49 + j * 3] = p.z
	var ax: Vector3 = rig.wheel_r.global_transform.basis.z.normalized()
	o[65] = ax.x; o[66] = ax.y; o[67] = ax.z
	return o

func _saddle_point(rig) -> Vector3:
	var seat: Dictionary = rig.seat if rig.get("seat") is Dictionary else {}
	if seat.has("top"):
		return rig.model.global_transform * Vector3((float(seat.rear) + float(seat.front)) * 0.5, float(seat.top), 0.0)
	return rig.crank_n.global_position + Vector3(0, 0.45, 0)

func _p(i: int, k: float, off: int) -> Vector3:
	var a := i * F + off; var b := a + F
	return Vector3(lerpf(_ghost[a], _ghost[b], k), lerpf(_ghost[a + 1], _ghost[b + 1], k), lerpf(_ghost[a + 2], _ghost[b + 2], k))

## a capsule from a to b, radius r (the unit capsule is 1 wide, 2 long along y)
func _seg(a: Vector3, b: Vector3, r: float) -> Transform3D:
	var d := b - a
	var l := d.length()
	if l < 1e-4: return Transform3D(Basis.from_scale(Vector3(r * 2.0, r * 2.0, r * 2.0)), a)
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * r * 2.0, y * (l * 0.5 + r) , z * r * 2.0), (a + b) * 0.5)

func _draw(i: int, k: float, done: bool) -> void:
	_show(true)
	_mat.set_shader_parameter("fade", 0.35 if done else 1.0)
	if game.rig: _mat.set_shader_parameter("player", game.rig.crank_n.global_position + Vector3(0, 0.5, 0))
	var J := []
	for j in 15: J.append(_p(i, k, 2 + j * 3))
	var B := []
	for j in 6: B.append(_p(i, k, 47 + j * 3))
	var c := 0
	for bn in BONES:
		_mm_body.set_instance_transform(c, _seg(J[bn[0]], J[bn[1]], bn[2])); _mm_body.set_instance_color(c, COL_RIDER); c += 1
	# the helmet: a ball a little over and in front of the head point
	# (the unit capsule is 1 wide and 2 tall: half the height scale makes it a ball)
	_mm_body.set_instance_transform(c, Transform3D(Basis.from_scale(Vector3(0.25, 0.125, 0.25)), J[0] + Vector3(0, 0.05, 0))); _mm_body.set_instance_color(c, COL_RIDER); c += 1
	for fr in FRAME:
		_mm_body.set_instance_transform(c, _seg(B[fr[0]], B[fr[1]], fr[2])); _mm_body.set_instance_color(c, COL_BIKE); c += 1
	# wheels: rings round the axles, square to the axle direction
	var ax := _p(i, k, 65).normalized()
	if ax.length_squared() < 0.5: ax = Vector3.FORWARD
	var fwd: Vector3 = (B[5] - B[0]).normalized()
	var up := fwd.cross(ax).normalized()   # (fwd, ax, up) right-handed: the ring isn't mirrored inside out
	var radii := [float(game.rig.wheel_rr), float(game.rig.wheel_rf)] if game.rig else [0.36, 0.37]
	for w in 2:
		var r: float = radii[w]
		# the torus lies in its xz plane: its y axis is the wheel's axle
		_mm_wheel.set_instance_transform(w, Transform3D(Basis(fwd * r, ax * r * 0.35, up * r), B[0] if w == 0 else B[5]))
		_mm_wheel.set_instance_color(w, COL_BIKE)
