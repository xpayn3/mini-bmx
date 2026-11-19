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
	var h := dt / SUB
	for sub in SUB:
		for i in range(1, N):
			var p := _P[i]
			var k := float(i) / (N - 1)                  # the tip flutters most
			var tu := _t * 14.0 + i * 0.9 + _ph[i]
			var w := side * (sin(tu) * speed * 0.55 * k) + Vector3.UP * (sin(tu * 1.31 + 1.7) * speed * 0.45 * k)
			w += side * (sin(_t * 31.0 + i * 1.3) * speed * 0.12 * k)   # fast rattle
			var v := (p - _Q[i]) / h
			var acc := (w - v) * DRAG + Vector3(0, -9.81 * 0.5, 0)
			_Q[i] = p
			_P[i] = p + v * h + acc * (h * h)
		for it in ITER:
			_P[0] = a
			for i in N - 1:
				var d := _P[i + 1] - _P[i]
				var l := maxf(d.length(), 1e-6)
				var diff := (l - SEG) / l
				var wa := 0.0 if i == 0 else 0.5
				var wb := 1.0 if i == 0 else 0.5
				_P[i] += d * (diff * wa)
				_P[i + 1] -= d * (diff * wb)
		_P[0] = a
		for i in range(2, N):   # not through the helmet
			var r := _P[i] - head_c
			var l := r.length()
			if l < HEAD_R and l > 1e-5:
				_P[i] = head_c + r * (HEAD_R / l)
	_draw(speed)


func _draw(speed: float) -> void:
	_imesh.clear_surfaces()
	var ta := clampf(0.25 + speed * 0.07, 0.25, 1.5)   # twist grows with speed
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
