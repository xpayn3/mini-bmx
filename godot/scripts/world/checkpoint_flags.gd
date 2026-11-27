class_name CheckpointFlags
## Feather flags lining both sides of the trail at every 5 km checkpoint (user 2026-11-27: "like racing games' checkpoints
## and real downhill events, flapping in the wind, light code"). One mesh (bent aluminium pole + a cloth grid), every flag
## of a chunk one MultiMesh instance; the flapping, the swing to face downwind and the lighting all happen in
## shaders/feather_flag.gdshader from the shared wind globals (atm_wind): no script runs per frame.
## The print is one atlas of DESIGNS columns of 512 x 1856 px, the user's designs on flag_design/flag_template.png

const H_POLE := 3.8        # m, the top of the flag (the pole's end, over the free edge)
const CLOTH_Y0 := 0.9      # bottom of the cloth (a straight edge): the bare pole below it (user: "start the flag higher")
const CLOTH_W := 0.8       # cloth width (pole to the straight free edge)
const ARC_H := 0.85        # how far down from the top the pole starts curving over
const NY := 22             # cloth grid rows (up)
const NX := 7              # cloth grid columns (across)
const POLE_R := 0.016
const SINK := 0.25         # pole spike into the ground
const DESIGNS := 2         # atlas columns (assets/textures/flags/checkpoint_flags.png): the user's designs, flag_design/flag_*.png
const TEX_W := 1024        # one design: 1024 x 3712 px (2x the template, nearest-scaled: crisp pixel-art edges) = the flag's box
const TEX_H := 3712        # (design at flag_design/flag_template.png: 512 x 1856)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _lb := PackedVector2Array()    # the pole's line (ground .. top corner), sampled
static var _lbl := PackedFloat32Array()   # its length along, per sample


## the feather flag of the user's reference (2026-11-27, "nice geometric curve, bottom straight"): the pole runs straight up
## the cloth's side, then bends over in a quarter ellipse (CLOTH_W across, ARC_H down) to the top of the free edge; the free
## edge and the bottom are straight. Mirrored in flag_design/make_template.py (keep in step).
## pole_line(u): the point u of the way along the cloth's pole side, from the bottom corner (0) to the top corner (1)
static func pole_line(u: float) -> Vector2:
	if _lb.is_empty():
		var ya := H_POLE - ARC_H
		_lb.append(Vector2(0.0, CLOTH_Y0))
		for k in 61:
			var th := float(k) / 60.0 * PI * 0.5
			_lb.append(Vector2(CLOTH_W * (1.0 - cos(th)), ya + ARC_H * sin(th)))
		var acc := 0.0
		for i in _lb.size():
			if i > 0:
				acc += _lb[i].distance_to(_lb[i - 1])
			_lbl.append(acc)
	var want := clampf(u, 0.0, 1.0) * _lbl[_lbl.size() - 1]
	for i in range(1, _lb.size()):
		if _lbl[i] >= want:
			var f := (want - _lbl[i - 1]) / maxf(1e-6, _lbl[i] - _lbl[i - 1])
			return _lb[i - 1].lerp(_lb[i], f)
	return _lb[_lb.size() - 1]


## the cloth point at grid (t up 0..1, s across 0..1), in the flag's own frame (pole on +y, cloth towards +x): row t runs
## from the pole side (t of the way along it) to the straight free edge (t of the way up it)
static func cloth_point(t: float, s: float) -> Vector3:
	var l := pole_line(t)
	var r := Vector2(CLOTH_W, lerpf(CLOTH_Y0, H_POLE, t))
	var p := l.lerp(r, s)
	return Vector3(p.x, p.y, 0.0)


static func mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	# cloth: COLOR.a = 1, UV = (t up, s across)
	for iy in NY + 1:
		for ix in NX + 1:
			var t := float(iy) / NY
			var s := float(ix) / NX
			var cp := cloth_point(t, s)
			v.append(cp)
			n.append(Vector3(0, 0, 1))
			uv.append(Vector2((cp.y - CLOTH_Y0) / (H_POLE - CLOTH_Y0), cp.x / CLOTH_W))   # the print: the flag's box
			uv2.append(Vector2(t, s))
			c.append(Color(1, 1, 1, 1))
	for iy in NY:
		for ix in NX:
			var a := iy * (NX + 1) + ix
			var b := a + NX + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	# pole: COLOR.a = 0 (never displaced), a 6-sided tube from the spike up and over the top arc to the free corner
	var path := PackedVector3Array()
	path.append(Vector3(0, -SINK, 0))
	for k in 25:
		var o := pole_line(float(k) / 24.0)
		path.append(Vector3(o.x, o.y, 0))
	var tip := pole_line(1.0)
	path.append(Vector3(tip.x + 0.04, tip.y, 0))   # (the pole's end sticks out a little past the cloth)
	var sides := 6
	var start := v.size()
	for i in path.size():
		var tg := (path[mini(path.size() - 1, i + 1)] - path[maxi(0, i - 1)]).normalized()
		var a1 := tg.cross(Vector3(0, 0, 1)).normalized()
		var a2 := tg.cross(a1)
		var r := POLE_R * lerpf(1.0, 0.7, float(i) / path.size())   # tapering fibreglass toward the tip
		for k in sides + 1:
			var ang := float(k) / sides * TAU
			var d := a1 * cos(ang) + a2 * sin(ang)
			v.append(path[i] + d * r)
			n.append(d)
			uv.append(Vector2(0, 0))
			uv2.append(Vector2(1, 0))
			c.append(Color(1, 1, 1, 0))
	for i in path.size() - 1:
		for k in sides:
			var a := start + i * (sides + 1) + k
			var b := a + sides + 1
			idx.append_array([a, a + 1, b, a + 1, b + 1, b])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh.custom_aabb = AABB(Vector3(-1.4, -SINK, -1.4), Vector3(2.8, H_POLE + SINK + 0.2, 2.8))   # it swings round the pole
	return _mesh


static func material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/feather_flag.gdshader")
	_mat.set_shader_parameter("designs", float(DESIGNS))
	_mat.set_shader_parameter("board_tex", load("res://assets/textures/flags/checkpoint_flags.png"))
	return _mat
