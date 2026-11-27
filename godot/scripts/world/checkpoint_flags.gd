class_name CheckpointFlags
## Feather flags lining both sides of the trail at every 5 km checkpoint (user 2026-11-27: "like racing games' checkpoints
## and real downhill events, flapping in the wind, light code"). One mesh (bent aluminium pole + a cloth grid), every flag
## of a chunk one MultiMesh instance; the flapping, the swing to face downwind and the lighting all happen in
## shaders/feather_flag.gdshader from the shared wind globals (atm_wind): no script runs per frame.
## The print is one atlas of DESIGNS columns of 512 x 1856 px, the user's designs on flag_design/flag_template.png

const H_POLE := 3.4        # m, top of the pole above the ground
const CLOTH_Y0 := 0.5      # bottom of the cloth at the pole
const CLOTH_W := 0.8       # widest point of the cloth (pole to free edge) = where the top arc starts
const ARC_H := 0.95        # how far down from the pole top the arc meets the free edge
const BOT_X := 0.38        # the tied-back bottom corner: out from the pole ..
const BOT_Y := 0.12        # .. and up from the cloth's bottom at the pole
const T_ARC := 0.6         # grid rows t < this run along the free edge, above it along the arc
const NY := 20             # cloth grid rows (up)
const NX := 7              # cloth grid columns (across)
const POLE_R := 0.016
const SINK := 0.25         # pole spike into the ground
const DESIGNS := 2         # atlas columns (assets/textures/flags/checkpoint_flags.png): the user's designs, flag_design/flag_*.png
const TEX_W := 512         # one design: 512 x 1856 px = the flag's box (CLOTH_W x H_POLE - CLOTH_Y0), 1 px = 1.56 mm
const TEX_H := 1856        # (flag_design/flag_template.png)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


## the classic feather flag outline (user reference photos): the pole runs straight up, then bends over the top in a
## quarter ellipse down to the free edge's top corner (CLOTH_W out, ARC_H down); the free edge falls from there, vertical
## at the corner and curving in to the tied-back bottom corner. Mirrored in flag_design/make_template.py (keep in step).
## outline(t): the point on the outline t of the way from the bottom corner (0) up the free edge and round the arc to
## the pole top (1)
static func outline(t: float) -> Vector2:
	var yc := H_POLE - ARC_H
	if t <= T_ARC:
		var u := t / T_ARC
		return Vector2(BOT_X + (CLOTH_W - BOT_X) * sin(u * PI * 0.5), lerpf(CLOTH_Y0 + BOT_Y, yc, u))
	var th := (t - T_ARC) / (1.0 - T_ARC) * PI * 0.5
	return Vector2(CLOTH_W * cos(th), yc + ARC_H * sin(th))


## the cloth point at grid (t up 0..1, s across 0..1), in the flag's own frame (pole on +y, cloth towards +x): row t runs
## from the pole to outline(t)
static func cloth_point(t: float, s: float) -> Vector3:
	var l := Vector2(0.0, lerpf(CLOTH_Y0, H_POLE, t))
	var p := l.lerp(outline(t), s)
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
	path.append(Vector3(0, H_POLE - 0.3, 0))
	for k in 15:
		var o := outline(1.0 - (1.0 - T_ARC) * float(k) / 14.0)
		path.append(Vector3(o.x, o.y, 0))
	var sides := 6
	var start := v.size()
	for i in path.size():
		var tg := (path[mini(path.size() - 1, i + 1)] - path[maxi(0, i - 1)]).normalized()
		var a1 := tg.cross(Vector3(0, 0, 1)).normalized()
		var a2 := tg.cross(a1)
		var r := POLE_R * (0.75 if i > 1 else 1.0)   # the top arc is the thinner fibreglass section
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
	# the cord tying the cloth's bottom corner back to the pole
	var cs := v.size()
	var p0 := cloth_point(0.0, 1.0)
	var p1 := Vector3(0, CLOTH_Y0 - 0.1, 0)
	for e in [p0, p1]:
		for k in 4:
			var ang := float(k) / 4.0 * TAU
			var d := Vector3(0, cos(ang), sin(ang)) * 0.004
			v.append(e + d)
			n.append(d.normalized())
			uv.append(Vector2(0, 1))
			uv2.append(Vector2(0, 1))   # grid corner (t 0, s 1): the cord's corner end moves with the cloth's corner
			c.append(Color(1, 1, 1, 0.5 if e == p0 else 0.0))
	for k in 4:
		var a := cs + k
		var b := cs + (k + 1) % 4
		idx.append_array([a, b, a + 4, b, b + 4, a + 4])
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
