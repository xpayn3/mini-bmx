class_name StrapTail
extends MeshInstance3D
## The loose velcro end of a knee pad strap (KneePad): flaps like the goggle strap's tail (HelmetFlap). It
## streams back from its buckle against the direction of travel with a travelling wave (quicker and bigger
## with speed), eases down to hang when slow, trails a little through moves, and is kept out of the leg
## (never closer to the bone's axis than `clear_r`). Built in world space every frame as a twisting ribbon.
## `part` = the pad group it's buckled to (its Y = the bone's axis), `anchor_local` = the buckle there.

const N := 8
const SEG := 0.018   # ~13 cm loose end

var part: Node3D
var anchor_local := Vector3.ZERO
var clear_r := 0.09
var width := 0.011       # half width
var _imesh := ImmediateMesh.new()
var _P := PackedVector3Array()
var _have := false
var _last := Vector3.ZERO
var _vs := Vector3.ZERO
var _t := 0.0
var _ph := 0.0
var _back := Vector3.DOWN


func _init() -> void:
	mesh = _imesh
	top_level = true
	process_priority = 100        # after the rider has been posed this frame
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	_ph = randf() * TAU
	_t = randf() * 10.0


func _process(dt: float) -> void:
	if part == null or not part.is_visible_in_tree() or dt <= 0.0:
		return
	dt = minf(dt, 1.0 / 30.0)
	_t += dt
	var a := part.global_transform * anchor_local
	if not _have or a.distance_to(_last) > 4.0:   # first frame / respawn: hang straight down
		_P.resize(N)
		for i in N:
			_P[i] = a + Vector3(0, -SEG * i, 0)
		_vs = Vector3.ZERO
		_last = a
		_have = true
	var vi := (a - _last) / dt
	_last = a
	_vs += (vi - _vs) * (1.0 - exp(-dt / 0.12))   # smoothed: pedalling averages out, riding speed stays
	var speed := _vs.length()
	var fwd := _vs / speed if speed > 0.05 else Vector3.ZERO
	if speed > 1.0: _back = (_back.lerp(-fwd, minf(1.0, dt * 6.0))).normalized()
	var stream := smoothstep(0.5, 7.0, speed)
	# the bone: the strap leaves the leg on the outside of the buckle, never back into it
	var bone_o := part.global_position
	var bone_y := part.global_basis.y.normalized()
	var radial := a - bone_o
	radial -= bone_y * radial.dot(bone_y)
	var out := radial.normalized() if radial.length_squared() > 1e-8 else part.global_basis.z.normalized()
	var dir := (_back * stream + Vector3.DOWN * (1.0 - stream) * 0.9 + _back * 0.2).normalized()
	dir = (dir + out * 0.45).normalized()
	var wside := dir.cross(Vector3.UP)
	wside = wside.normalized() if wside.length_squared() > 1e-4 else Vector3.RIGHT
	var wup := wside.cross(dir).normalized()
	var freq: float = 7.0 + speed * 1.1
	var amp: float = 0.004 + 0.012 * stream
	_P[0] = a
	for i in range(1, N):
		var k := float(i) / (N - 1)
		var ph := _t * freq - i * 0.95 + _ph
		var off := wside * sin(ph) * amp * k + wup * sin(ph * 0.7 + 1.3) * amp * 0.5 * k
		var tgt := a + dir * (SEG * i) + off
		_P[i] = _P[i].lerp(tgt, minf(1.0, dt * 22.0))   # a touch of lag: it trails smoothly through moves
	for i in range(1, N):   # links keep their length, and the strap stays outside the leg
		var d := _P[i] - _P[i - 1]
		_P[i] = _P[i - 1] + (d.normalized() * SEG if d.length_squared() > 1e-10 else dir * SEG)
		var r := _P[i] - bone_o
		var rr := r - bone_y * r.dot(bone_y)
		if rr.length() < clear_r:
			_P[i] += (rr.normalized() if rr.length_squared() > 1e-8 else out) * (clear_r - rr.length())
	_draw(speed)


func _draw(speed: float) -> void:
	_imesh.clear_surfaces()
	var ta := clampf(0.1 + speed * 0.02, 0.1, 0.5)   # a little twist at the tip, more with speed
	var E := PackedVector3Array()
	E.resize(N)
	var bone_y := part.global_basis.y.normalized()
	for i in N:
		var d := (_P[mini(N - 1, i + 1)] - _P[maxi(0, i - 1)]).normalized()
		var ax := bone_y - d * bone_y.dot(d)   # flat against the leg at the buckle: across = along the bone
		if ax.length_squared() < 1e-4:
			ax = d.cross(Vector3.UP)
			if ax.length_squared() < 1e-4: ax = Vector3.RIGHT
		ax = ax.normalized()
		var bx := ax.cross(d)
		var tw := sin(_t * 10.0 - i * 0.8 + _ph) * ta * (float(i) / (N - 1))
		E[i] = (ax * cos(tw) + bx * sin(tw)) * width
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in N - 1:
		var p0 := _P[i]
		var p1 := _P[i + 1]
		var nn := (p1 - p0).cross(E[i]).normalized()
		for v in [p0 + E[i], p1 + E[i + 1], p0 - E[i], p1 + E[i + 1], p1 - E[i + 1], p0 - E[i]]:
			_imesh.surface_set_normal(nn)
			_imesh.surface_add_vertex(v)
	_imesh.surface_end()
