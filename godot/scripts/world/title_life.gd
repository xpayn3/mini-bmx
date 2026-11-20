class_name TitleLife
extends Node3D
## The title screen's backdrop comes alive: now and then a few birds cross the sky (a small flock, a lone bird, one
## soaring on a thermal), fine dust blowing through the air on the wind, and little dust wisps round the desert
## bushes (the same bush instances the terrain is planted with, found in the loaded chunks). Menu only.
## Birds are rare on purpose: each group shows up, crosses the view and is gone for a minute or so.

const BIRD_SCALE := 2.4          # a big bird: ~2.5 m span, readable as a silhouette ~200 m out
const BUSH_SPOTS := 7            # bushes that get their own dust
const BUSH_RANGE := Vector2(12.0, 110.0)
# the groups: how many birds, when the first one appears (s), and how long it stays away between visits (s)
const GROUPS := [
	{"n": 5, "first": 5.0, "gap": Vector2(45.0, 100.0)},
	{"n": 3, "first": 26.0, "gap": Vector2(55.0, 120.0)},
	{"n": 1, "first": 15.0, "gap": Vector2(35.0, 80.0)},
]

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _birds: Array = []           # one per MultiMesh instance (see _build_birds)
var _flocks: Array = []
var _soar: Dictionary = {}       # the one thermal soarer
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _motes: CPUParticles3D
var _bush_fx: Array = []         # CPUParticles3D, one per picked bush
var _bush_t := 0.0


func _init() -> void:
	_rng.randomize()
	_build_birds()
	_motes = TitleLife._make_motes()
	add_child(_motes)


# ---------------------------------------------------------------- birds
## nose +X, wings out along +-Z, each wing cut into 5 strips so it can bend: the flap runs along the span in the shader
static func _bird_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	v.append_array([Vector3(0.52, 0, 0), Vector3(0.05, 0.06, 0.09), Vector3(0.05, 0.06, -0.09), Vector3(-0.6, 0.0, 0.0),
		Vector3(-0.1, 0.0, 0.0)])
	idx.append_array([0, 1, 2, 1, 3, 2, 1, 4, 3, 2, 3, 4])
	for sd in [1.0, -1.0]:
		var base := v.size()
		var n := 5
		for k in n + 1:
			var s := float(k) / n
			var z: float = sd * (0.05 + s * 1.0)
			var lead := lerpf(0.26, 0.05, pow(s, 1.6))            # leading edge sweeps back a little
			var trail := lerpf(-0.32, -0.62, pow(s, 0.8)) + (s * s * 0.0)
			if k == n:
				trail = -0.5                                         # a pointed tip
				lead = -0.04
			v.append(Vector3(lead, 0, z))
			v.append(Vector3(trail, 0, z))
		for k in n:
			var a := base + k * 2
			if sd > 0.0:
				idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
			else:
				idx.append_array([a, a + 3, a + 1, a, a + 2, a + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## wing beat from the phase the script keeps (ph, no TIME: so the rate can change smoothly without a jump). The wing
## turns about the shoulder; the tip follows the root a little later, the downstroke is the strong slow one, the upstroke
## folds the wing in as it comes up. amp = how hard (0.15 = gliding), custom.w = the held-up V of a glide / soar.
const BIRD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.14, 0.10, 0.09);
void vertex() {
	float ph = INSTANCE_CUSTOM.x;
	float amp = INSTANCE_CUSTOM.z;
	float dih = INSTANCE_CUSTOM.w;
	float sg = sign(VERTEX.z);
	float s = clamp(abs(VERTEX.z), 0.0, 1.05);
	float pt = ph - s * 1.15;                              // the tip lags the root
	float st = sin(pt) + 0.28 * sin(2.0 * pt + 0.6);        // sharper on the way down than up
	float ang = dih + amp * 0.85 * st;
	float fold = 1.0 - 0.22 * amp * max(0.0, -sin(pt));     // the wing draws in on the upstroke
	float len = s * fold;
	VERTEX.y = sin(ang) * len + VERTEX.y;
	VERTEX.z = sg * cos(ang) * len;
	VERTEX.x -= 0.05 * amp * s * cos(pt);                   // the tips sweep back and forth a touch
}
void fragment() {
	ALBEDO = tint;
}
"""


func _new_bird(flock: int, off: Vector3, size: float) -> Dictionary:
	return {
		"flock": flock, "off": off, "size": size,
		"ph": _rng.randf() * TAU, "rate": 8.0, "amp": 0.9, "dih": 0.12,
		"phase": _rng.randf() * TAU,            # also drives this bird's own glide / flap rhythm and drift
		"flap_len": _rng.randf_range(2.2, 5.0), "glide_len": _rng.randf_range(1.2, 4.0),
		"rate_flap": _rng.randf_range(6.5, 10.5), "pace": _rng.randf_range(-1.5, 1.5),
		"wob": _rng.randf_range(0.12, 0.3),
	}


func _build_birds() -> void:
	var sh := Shader.new()
	sh.code = BIRD_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _bird_mesh()
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 4000.0
	add_child(_mmi)
	for gi in GROUPS.size():
		var g: Dictionary = GROUPS[gi]
		var f := {"on": false, "wait": float(g.first), "pos": Vector3.ZERO, "dir": Vector2.RIGHT, "speed": 12.0, "alt": 70.0,
			"dist": 200.0, "ang": 0.0, "side": 1.0, "vis": 0.0, "gap": g.gap}
		_flocks.append(f)
		for i in int(g.n):
			# a loose, uneven cluster (not a tidy V): some stragglers, some leaders, different heights
			var off := Vector3(-_rng.randf_range(0.0, 11.0), _rng.randf_range(-4.5, 4.5), _rng.randf_range(-7.0, 7.0))
			if i == 0:
				off = Vector3(_rng.randf_range(0.0, 3.0), 0.0, 0.0)
			_birds.append(_new_bird(gi, off, _rng.randf_range(0.7, 1.25)))
	# the thermal soarer: wide lazy circles, wings held out and still
	_soar = {"on": false, "wait": 12.0, "a": 0.0, "w": 0.13, "r": 45.0, "alt": 110.0, "dist": 220.0, "ang": 0.0, "life": 0.0, "age": 0.0, "vis": 0.0}
	var sb := _new_bird(-1, Vector3.ZERO, 1.4)
	sb.amp = 0.08
	sb.dih = 0.22
	_birds.append(sb)
	_mm.instance_count = _birds.size()
	for i in _birds.size():
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0)))


# ---------------------------------------------------------------- dust in the air
static func _make_motes() -> CPUParticles3D:
	var p := Tumbleweeds.make_dust(70, 7.0, 0.16, 0.2)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(35, 2.0, 35)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.spread = 180.0
	p.damping_min = 0.0
	p.damping_max = 0.1
	p.emitting = true
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.7))
	grow.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = grow
	return p


## cam = the menu camera, wind = Atmos.wind (x / z), at = the bike
func update(dt: float, cam: Camera3D, wind: Vector2, at: Vector3, t) -> void:
	if cam == null or dt <= 0.0:
		return
	_t += dt
	var wl := wind.length()
	var wd := (wind / wl) if wl > 0.01 else Vector2(0.8, 0.6)
	var cpos := cam.global_position
	var fwd3 := -cam.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector2(1, 0)
	_update_birds(dt, cpos, fwd, wd)
	_update_dust(dt, cpos, wd, wl, at)
	_update_bushes(dt, cam, wd, wl, t)


func _update_birds(dt: float, cpos: Vector3, fwd: Vector2, wd: Vector2) -> void:
	var cp2 := Vector2(cpos.x, cpos.z)
	# a group arrives from one side of the view, crosses it on a gentle arc and leaves; then it is gone for a while
	for i in _flocks.size():
		var f: Dictionary = _flocks[i]
		if not f.on:
			f.wait -= dt
			if f.wait <= 0.0:
				f.on = true
				f.side = 1.0 if _rng.randf() < 0.5 else -1.0
				f.ang = -f.side * 0.72
				f.dist = _rng.randf_range(150.0, 300.0)
				f.alt = _rng.randf_range(35.0, 120.0)
				f.speed = _rng.randf_range(10.0, 17.0)
				f.vis = 0.0
			continue
		f.ang += f.side * dt * f.speed / f.dist
		f.vis = minf(f.vis + dt * 0.5, 1.0)
		if f.ang * f.side > 0.75:
			f.on = false
			f.wait = _rng.randf_range(f.gap.x, f.gap.y)
			continue
		var dir2 := fwd.rotated(f.ang)
		var p2: Vector2 = cp2 + dir2 * f.dist
		f.pos = Vector3(p2.x, cpos.y + f.alt + sin(_t * 0.17 + i * 2.0) * 6.0, p2.y)
		f.dir = Vector2(-dir2.y, dir2.x) * float(f.side)
	var s := _soar
	if not s.on:
		s.wait -= dt
		if s.wait <= 0.0:
			s.on = true
			s.life = _rng.randf_range(45.0, 80.0)
			s.age = 0.0
			s.ang = _rng.randf_range(-0.45, 0.45)
			s.dist = _rng.randf_range(170.0, 260.0)
			s.alt = _rng.randf_range(80.0, 140.0)
			s.r = _rng.randf_range(35.0, 60.0)
			s.w = _rng.randf_range(0.10, 0.17) * (1.0 if _rng.randf() < 0.5 else -1.0)
			s.a = _rng.randf() * TAU
	else:
		s.life -= dt
		s.age += dt
		s.vis = clampf(minf(s.age / 5.0, s.life / 6.0), 0.0, 1.0)
		if s.life <= 0.0:
			s.on = false
			s.wait = _rng.randf_range(40.0, 90.0)
			s.vis = 0.0
		s.a += s.w * dt
	for i in _birds.size():
		var b: Dictionary = _birds[i]
		var pos: Vector3
		var head: Vector2
		var vis := 1.0
		var gliding := false
		if b.flock >= 0:
			var f: Dictionary = _flocks[b.flock]
			if not f.on:
				_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0)))
				continue
			vis = f.vis
			# every bird has its own heading wobble, drift along the flock and height bob: nothing marches in step
			head = f.dir.rotated(sin(_t * 0.45 + b.phase) * b.wob)
			var bx := Vector3(f.dir.x, 0, f.dir.y)
			var bz := Vector3(-f.dir.y, 0, f.dir.x)
			var o: Vector3 = b.off
			pos = f.pos + bx * (o.x + sin(_t * 0.23 + b.phase * 2.0) * 3.0 + b.pace * sin(_t * 0.1) * 2.0) \
				+ bz * (o.z + sin(_t * 0.17 + b.phase) * 2.0) + Vector3(0, o.y + sin(_t * 0.7 + b.phase) * 1.2, 0)
			# flap bursts and glides, each bird on its own rhythm
			var cyc: float = fmod(_t + float(b.phase) * 4.0, float(b.flap_len) + float(b.glide_len))
			gliding = cyc > float(b.flap_len)
		else:
			if not s.on:
				_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0)))
				continue
			vis = s.vis
			var base: Vector2 = cp2 + fwd.rotated(float(s.ang)) * float(s.dist)
			var cc: Vector2 = base + wd * sin(_t * 0.05 + float(s.ang) * 10.0) * 25.0
			var rr: float = float(s.r) * (1.0 + 0.12 * sin(_t * 0.2))
			var p2: Vector2 = cc + Vector2(cos(float(s.a)), sin(float(s.a))) * rr
			pos = Vector3(p2.x, cpos.y + float(s.alt) + sin(_t * 0.3 + float(s.a)) * 3.0, p2.y)
			head = Vector2(-sin(float(s.a)), cos(float(s.a))) * signf(float(s.w))
			gliding = true
			# the odd lazy flap while it circles
			if sin(_t * 0.37 + b.phase) > 0.93:
				gliding = false
		# wing state eases between flapping and gliding (no jump)
		var want_amp := 0.12 if gliding else (0.7 if b.flock < 0 else 0.95)
		var want_rate: float = 1.2 if gliding else float(b.rate_flap)
		var want_dih := 0.26 if gliding else 0.06
		b.rate = lerpf(float(b.rate), want_rate, minf(dt * 2.5, 1.0))
		b.amp = lerpf(float(b.amp), want_amp, minf(dt * 3.0, 1.0))
		b.dih = lerpf(float(b.dih), want_dih, minf(dt * 2.0, 1.0))
		b.ph += float(b.rate) * dt
		# orientation: along the heading, nose a little up while flapping hard, banked into its wobble / circle
		var h3 := Vector3(head.x, 0, head.y).normalized()
		var pitch := 0.10 if not gliding else -0.04
		if b.flock >= 0:
			pitch += cos(_t * 0.7 + b.phase) * 0.12
		var fv := (h3 + Vector3.UP * pitch).normalized()
		var right := fv.cross(Vector3.UP).normalized()
		var up := right.cross(fv).normalized()
		var basis := Basis(fv, up, right)
		var bank := 0.0
		if b.flock >= 0:
			bank = -cos(_t * 0.45 + b.phase) * b.wob * 1.6
		else:
			bank = 0.38 * signf(float(s.w))
		basis = basis.rotated(fv, bank)
		basis = basis.scaled(Vector3.ONE * BIRD_SCALE * b.size * vis)
		_mm.set_instance_transform(i, Transform3D(basis, pos))
		_mm.set_instance_custom_data(i, Color(b.ph, b.rate, b.amp, b.dih))


func _update_dust(dt: float, cpos: Vector3, wd: Vector2, wl: float, at: Vector3) -> void:
	# fine dust hanging in the air round the bike and drifting downwind
	_motes.global_position = Vector3(at.x, at.y + 1.2, at.z) - Vector3(wd.x, 0, wd.y) * 6.0
	_motes.gravity = Vector3(wd.x, 0.02, wd.y) * (0.9 + 1.4 * wl)


func _update_bushes(dt: float, cam: Camera3D, wd: Vector2, wl: float, t) -> void:
	_bush_t -= dt
	if _bush_t <= 0.0:
		_bush_t = 1.0
		if _bush_fx.size() < BUSH_SPOTS and t != null:
			_pick_bushes(cam, t)
	var g := Vector3(wd.x, 0.0, wd.y) * (1.1 + 1.6 * wl)
	for p in _bush_fx:
		(p as CPUParticles3D).gravity = g + Vector3(0, 0.25, 0)


## find desert bushes in the loaded chunks that the menu camera sees, and give each a puff of wind-blown dust
func _pick_bushes(cam: Camera3D, t) -> void:
	if not TerrainGeo.MESH.has("weed"):
		return
	var weed: Mesh = TerrainGeo.MESH["weed"]
	var cands: Array = []
	var cpos := cam.global_position
	for k in t.chunks:
		var n = t.chunks[k].get("node")
		if not is_instance_valid(n):
			continue
		for mi in (n as Node).get_children():
			if not (mi is MultiMeshInstance3D):
				continue
			var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh != weed:
				continue
			for i in mm.instance_count:
				var xf: Transform3D = (mi as MultiMeshInstance3D).global_transform * mm.get_instance_transform(i)
				var d := cpos.distance_to(xf.origin)
				if d < BUSH_RANGE.x or d > BUSH_RANGE.y or not cam.is_position_in_frustum(xf.origin):
					continue
				if cam.is_position_behind(xf.origin):
					continue
				cands.append(xf)
	if cands.is_empty():
		return
	cands.shuffle()
	for xf in cands:
		if _bush_fx.size() >= BUSH_SPOTS:
			break
		var far := false
		for p in _bush_fx:
			if (p as Node3D).global_position.distance_to(xf.origin) < 7.0:
				far = true
				break
		if far:
			continue
		var r := maxf(xf.basis.get_scale().x, 0.2) * 0.45
		var fx := Tumbleweeds.make_dust(14, 2.6, 0.45, 0.28)
		fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
		fx.emission_sphere_radius = r
		fx.initial_velocity_min = 0.1
		fx.initial_velocity_max = 0.5
		fx.spread = 70.0
		fx.tangential_accel_min = 0.15
		fx.tangential_accel_max = 0.5
		add_child(fx)
		fx.global_position = Vector3(xf.origin.x, xf.origin.y - r * 0.5, xf.origin.z)
		fx.emitting = true
		_bush_fx.append(fx)
