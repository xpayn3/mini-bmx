class_name HelmetFlap
extends MeshInstance3D
## A loose tail of the goggle strap that flaps in the wind. Same idea as the torn race tape (TapeSim):
## a Verlet chain with tiny mass and big drag, pulled towards the local air velocity, so it hangs limp
## when the rider is slow and streams back and snaps harder the faster he goes. Drawn as a twisting
## double-sided ribbon in world space (rebuilt every frame), pinned to the goggles.

const N := 9                    # points
const SEG := 0.032              # m per segment (tail is ~0.26 m)
const SUB := 3
const ITER := 4
const DRAG := 7.0
const HEAD_R := 0.205           # keep the tail out of the helmet

var anchor_local := Vector3.ZERO
var _imesh := ImmediateMesh.new()
var _P := PackedVector3Array()
var _Q := PackedVector3Array()
var _ph := PackedFloat32Array()
var _have := false
var _last := Vector3.ZERO
var _vs := Vector3.ZERO         # smoothed velocity of the head through the air
var _t := 0.0
var _back := Vector3.DOWN   # which way "behind the rider" is (from the travel), kept while slow
var probe := OS.get_environment("BMX_FLAP_PROBE") != ""
var _probe_k := -1


func _init() -> void:
	mesh = _imesh
	top_level = true
	process_priority = 100        # after the rider has been posed this frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	for i in N:
		_ph.append(randf() * 6.28)


func _reset(a: Vector3) -> void:
	_P.resize(N)
	_Q.resize(N)
	for i in N:
		_P[i] = a + Vector3(0, -SEG * i, 0)
		_Q[i] = _P[i]
	_vs = Vector3.ZERO
	_last = a
	_have = true


func _process(dt: float) -> void:
	var gog := get_parent() as Node3D
	if gog == null or not gog.is_visible_in_tree() or dt <= 0.0:
		return
	dt = minf(dt, 1.0 / 30.0)
	_t += dt
	var a := gog.global_transform * anchor_local
	if not _have or a.distance_to(_last) > 4.0:   # first frame / respawn: hang straight down
		_reset(a)
	var vi := (a - _last) / dt
	_last = a
	_vs += (vi - _vs) * (1.0 - exp(-dt / 0.12))   # smoothed: head bob averages out, riding speed stays
	var speed := _vs.length()
	var fwd := _vs / speed if speed > 0.05 else Vector3.ZERO
	var side := fwd.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-4 else Vector3.RIGHT
	var head_c := (gog.get_parent() as Node3D).global_position if gog.get_parent() is Node3D else a
	# a flag: the tail streams straight back from the clip against the direction of travel, a travelling
	# wave runs down it (stronger toward the tip, quicker and tighter the faster the rider goes); slow, it
	# eases down to hang behind the helmet. Built from that shape every frame, so it can never point forward
	if speed > 1.0: _back = (_back.lerp(-fwd, minf(1.0, dt * 6.0))).normalized()
	var stream := smoothstep(0.5, 7.0, speed)
	var dir := (_back * stream + Vector3.DOWN * (1.0 - stream) * 0.9 + _back * 0.25).normalized()
	# angled a touch out from the head so it clears the shell (pushing it out of the helmet kinked it)
	var radial := a - head_c
	var side_out := radial - dir * radial.dot(dir)
	if side_out.length_squared() > 1e-6: dir = (dir + side_out.normalized() * 0.3).normalized()
	var wside := dir.cross(Vector3.UP)
	wside = wside.normalized() if wside.length_squared() > 1e-4 else Vector3.RIGHT
	var wup := wside.cross(dir).normalized()
	var freq: float = 6.0 + speed * 0.9
	var amp: float = 0.008 + 0.024 * stream   # ripples up to ~3 cm at the tip of the 26 cm strap
	_P[0] = a
	for i in range(1, N):
		var k := float(i) / (N - 1)
		var ph := _t * freq - i * 0.85
		var off := wside * sin(ph) * amp * k + wup * sin(ph * 0.7 + 1.3) * amp * 0.45 * k
		var tgt := a + dir * (SEG * i) + off + Vector3.DOWN * (0.01 * k * k * (1.0 - stream))
		_P[i] = _P[i].lerp(tgt, minf(1.0, dt * 25.0))   # a touch of lag: it trails smoothly through turns
	for i in range(1, N):   # keep the links their length (no stretching while it lags)
		var d := _P[i] - _P[i - 1]
		_P[i] = _P[i - 1] + d.normalized() * SEG if d.length_squared() > 1e-10 else _P[i - 1] + dir * SEG
	_draw(speed)
	if probe and int(_t * 2.0) != _probe_k:   # tests (BMX_FLAP_PROBE): which way the tail points, how bent
		_probe_k = int(_t * 2.0)
		var tail := _P[N - 1] - _P[0]
		var bend := 0.0
		for i in range(1, N - 1):
			bend = maxf(bend, (_P[i] - _P[i - 1]).normalized().angle_to((_P[i + 1] - _P[i]).normalized()))
		print("FLAP speed=%.1f back=%.2f droop=%.2f m max_bend=%.0f deg" % [speed, tail.normalized().dot(-fwd) if speed > 0.5 else 0.0, -tail.y, rad_to_deg(bend)])


func _draw(speed: float) -> void:
	_imesh.clear_surfaces()
	var ta := clampf(0.1 + speed * 0.015, 0.1, 0.4)   # a little twist at the tip, more with speed
	var E := PackedVector3Array()
	E.resize(N)
	for i in N:
		var d := (_P[mini(N - 1, i + 1)] - _P[maxi(0, i - 1)]).normalized()
		var ax := d.cross(Vector3.UP)
		if ax.length_squared() < 1e-4:
			ax = Vector3.RIGHT
		ax = ax.normalized()
		var bx := ax.cross(d)
		var twa := sin(_t * 9.0 - i * 0.7 + _ph[0]) * ta * (float(i) / (N - 1)) + 0.3
		var wdt := lerpf(0.016, 0.012, float(i) / (N - 1))
		E[i] = (bx * cos(twa) + ax * sin(twa)) * wdt
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in N - 1:
		var p0 := _P[i]
		var p1 := _P[i + 1]
		var nn := (p1 - p0).cross(E[i]).normalized()
		for v in [p0 + E[i], p1 + E[i + 1], p0 - E[i], p1 + E[i + 1], p1 - E[i + 1], p0 - E[i]]:
			_imesh.surface_set_normal(nn)
			_imesh.surface_add_vertex(v)
	_imesh.surface_end()
