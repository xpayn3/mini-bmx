class_name Rider
extends Node3D
## Port of src/rider.js: the low-poly cartoon rider, posed procedurally every frame.
## This node is the JS rider.group: parent it under the bike's lean node. Local frame: +X forward,
## +Y up, +Z the rider's right; the bottom bracket sits near the origin (0.297 up on the BMX).

const G := preload("res://scripts/rider/rider_geo.gd")
const GEAR := preload("res://scripts/rider/rider_gear.gd")

## neutral riding style (posepanel.js NEUTRAL): BMX = all of these
const NEUTRAL := {hipX = 0.0, hipY = 0.0, lean = 0.0, elbowsOut = 0.0, kneesOut = 0.0, stance = 0.0, seatFloor = false,
	crouch = 1.0, standPedal = 1.0, sway = 1.0, bikeRock = 1.0, upright = 1.0, hipSway = 0.015, torso = 0.46,
	shoulders = 0.2, headTilt = 0.0, headTurn = 1.0, lookAhead = 0.0,
	# per-bone controls (garage Rider tab / K panel); 0 = the riding pose as computed
	hipZ = 0.0, pelvisTilt = 0.0, pelvisRoll = 0.0, pelvisYaw = 0.0,
	spineCurve = 0.0, spineSide = 0.0, spineLow = 0.5, chestFwd = 0.0, chestUp = 0.0, chestSide = 0.0, twist = 0.0,
	neck = 0.0, headYaw = 0.0, headRoll = 0.0,
	shoulderFwd = 0.0, shoulderUp = 0.0, elbowsDown = 0.0, elbowOutL = 0.0, elbowOutR = 0.0, wristRoll = 0.0,
	kneesFwd = 0.0, kneeOutL = 0.0, kneeOutR = 0.0, heelFwd = 0.0, heelUp = 0.0, footAngle = 0.0, footOut = 0.0}
## lookpanel.js DEFAULT_LOOK
const DEFAULT_LOOK := {shell = "#16171a", peak = "#ececec", goggleFrame = "#f2f2ee", lens = "#ff7a2a", strap = "#ff6a4d",
	jersey = "#ff6a4d", pants = "#1d2b64", gloves = "#ffd21f", shoes = "#26292f", shoeAccent = "#d8232a"}
## where the helmet model sits on the head (head-local m / rad) and its scale
const HELMET_FIT := {x = 0.01, y = 0.0, tilt = 0.0, scale = 1.3}
## goggles (RiderGear.build_goggles): lens position / tilt / size, strap ellipse round the shell
const GOGGLE_FIT := {x = 0.15, y = 0.025, tilt = 0.25, w = 0.2, h = 0.075, R = 0.12, strap = {cx = 0.01, ra = 0.236, rc = 0.162}}

const L_THIGH := 0.44
const L_SHIN := 0.44
const L_UARM := 0.31
const L_FARM := 0.29

var style: Dictionary = {}
var look: Dictionary = {}
var seat = null              # {top, rear, front} of the saddle in this node's space, or null
var fit := Vector3.ZERO      # pelvis offset for bikes bigger / smaller than the BMX
var J: Array[Vector3] = []   # ragdoll joints in local space (Ragdoll order), refreshed by update_pose()

var kit := {}
var shoe_mats := {}
var goggle_mats := {}
var hand_mats := {}
var helmet_mats := {}
var helmet_model: Node3D = null
var goggles: Node3D = null

var torso: MeshInstance3D
var hood_hem: MeshInstance3D
var pelvis_mesh: MeshInstance3D
var hood: MeshInstance3D
var shoulder_sph: Array[MeshInstance3D] = []
var thigh: Array[MeshInstance3D] = []
var shin: Array[MeshInstance3D] = []
var knee: Array[MeshInstance3D] = []
var shoe: Array[Node3D] = []
var upper_arm: Array[MeshInstance3D] = []
var fore_arm: Array[MeshInstance3D] = []
var elbow: Array[MeshInstance3D] = []
var glove: Array[Node3D] = []
var head: Node3D
var hel: Node3D

var poles_leg: Array[Vector3] = []
var poles_arm: Array[Vector3] = []
var sm_shift_z := 0.0
var pel_s := Vector3.ZERO
var pel_v := Vector3.ZERO
var ch_s := Vector3.ZERO
var ch_v := Vector3.ZERO
var spring_init := false


static func mat(color: Variant, roughness := 0.75, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color if color is Color else Color(color)
	m.roughness = roughness
	m.metallic = metal
	return m


func _init() -> void:
	name = "Rider"
	var mCoral := mat("#ff6a4d", 0.8)
	var mCoralDark := mat("#e04e34", 0.8)
	var mNavy := mat("#1d2b64", 0.8)
	var mNavyLight := mat("#3a4c9a", 0.8)
	var mYellow := mat("#ffd21f", 0.7)
	kit = {jersey = [mCoral, mCoralDark], pants = [mNavy, mNavyLight], gloves = [mYellow]}

	var cyl := func(rt: float, rb: float, m: Material, seg := 16) -> MeshInstance3D:
		var c := CylinderMesh.new()
		c.top_radius = rt
		c.bottom_radius = rb
		c.height = 1.0
		c.radial_segments = seg
		c.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = m
		add_child(mi)
		return mi
	var sph := func(r: float, m: Material, ws := 16, hs := 12) -> MeshInstance3D:
		var s := SphereMesh.new()
		s.radius = r
		s.height = 2 * r
		s.radial_segments = ws
		s.rings = hs
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		add_child(mi)
		return mi

	# torso + hips
	torso = G.inst(GEAR.torso_geometry(), mCoral)
	torso.name = "Torso"
	_skin_torso()
	add_child(torso)
	hood_hem = cyl.call(0.15, 0.15, mCoralDark, 22)
	hood_hem.visible = false
	pelvis_mesh = G.inst(G.rounded_box(0.2, 0.15, 0.3, 3, 0.05), mNavy)
	pelvis_mesh.name = "Pelvis"
	add_child(pelvis_mesh)
	hood = sph.call(0.11, mCoralDark)
	shoulder_sph.assign([sph.call(0.075, mCoral), sph.call(0.075, mCoral)])

	# legs (0 = left, 1 = right)
	thigh.assign([cyl.call(0.075, 0.062, mNavy), cyl.call(0.075, 0.062, mNavy)])
	shin.assign([cyl.call(0.062, 0.05, mNavy), cyl.call(0.062, 0.05, mNavy)])
	knee.assign([sph.call(0.07, mNavyLight), sph.call(0.07, mNavyLight)])
	shoe_mats = {upper = mat("#26292f"), accent = mat("#d8232a"), sole = mat("#111214", 0.95), mid = mat("#f2f2ee"), laces = mat("#f2f2ee")}
	var strap := mat("#ff6a4d", 0.8)
	strap.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lens := mat("#ff7a2a", 0.06, 0.85)
	lens.clearcoat_enabled = true
	lens.clearcoat = 1.0
	lens.clearcoat_roughness = 0.05
	lens.emission_enabled = true
	lens.emission = Color("#401a08")
	lens.cull_mode = BaseMaterial3D.CULL_DISABLED
	goggle_mats = {frame = mat("#f2f2ee", 0.45), foam = mat("#15171a", 1.0), strap = strap, lens = lens}
	for i in 2:
		var s := GEAR.build_shoe(shoe_mats)
		add_child(s)
		shoe.append(s)

	# arms
	upper_arm.assign([cyl.call(0.055, 0.047, mCoral), cyl.call(0.055, 0.047, mCoral)])
	fore_arm.assign([cyl.call(0.047, 0.04, mCoral), cyl.call(0.047, 0.04, mCoral)])
	elbow.assign([sph.call(0.055, mCoralDark), sph.call(0.055, mCoralDark)])
	var dark := mat("#1b1d22", 0.85)
	hand_mats = {glove = mYellow, knuckle = dark, palm = dark, cuff = dark}
	for side in [-1, 1]:
		var hnd := GEAR.build_hand(hand_mats, side)
		add_child(hnd)
		glove.append(hnd)

	# head: the built-in full-face helmet (replaced by set_helmet when the model loads)
	head = Node3D.new()
	head.name = "Head"
	add_child(head)
	_build_builtin_helmet()

	set_style({})
	J.resize(15)
	J.fill(Vector3.ZERO)


func _build_builtin_helmet() -> void:
	var shellMat := mat("#f1f1ec", 0.35)
	shellMat.clearcoat_enabled = true
	shellMat.clearcoat_roughness = 0.15
	var accentMat := mat("#ff6a4d", 0.4)
	accentMat.clearcoat_enabled = true
	accentMat.clearcoat_roughness = 0.2
	var chinMat := mat("#30353d", 0.55)
	var innerMat := mat("#14171c", 0.9)
	var ventMat := mat("#0d0f12", 0.6)
	var frameMat := mat("#1a1d22", 0.5)
	var lensMat := mat("#3a3226", 0.08, 0.7)
	lensMat.emission_enabled = true
	lensMat.emission = Color("#3a1806")
	lensMat.emission_energy_multiplier = 0.5
	var R := 0.185
	hel = Node3D.new()
	hel.name = "Helmet"
	hel.transform = Transform3D(Basis(Vector3.BACK, 0.05).scaled_local(Vector3(1.14, 0.96, 0.9)), Vector3(-0.005, 0.02, 0))
	head.add_child(hel)
	var add := func(g: Dictionary, m: Material, parent: Node3D = hel) -> MeshInstance3D:
		var mi := G.inst(g, m)
		parent.add_child(mi)
		return mi
	add.call(G.sphere(R * 0.92, 10, 8), innerMat)
	add.call(G.sphere(R, 12, 4, 0, TAU, 0, PI * 0.3), shellMat)
	add.call(G.sphere(R, 12, 6, PI + 0.7, TAU - 1.4, PI * 0.3, PI * 0.48), shellMat)
	add.call(G.sphere(R * 1.012, 3, 8, -0.14, 0.28, 0.02, PI * 0.62), accentMat)
	add.call(G.sphere(R * 1.012, 3, 4, PI - 0.14, 0.28, 0.02, PI * 0.27), accentMat)
	add.call(G.sphere(R * 1.025, 12, 1, PI + 0.7, TAU - 1.4, PI * 0.5, PI * 0.07), accentMat)
	add.call(G.sphere(R * 1.025, 12, 1, PI + 0.7, TAU - 1.4, PI * 0.72, PI * 0.06), chinMat)
	var brimG := Node3D.new()
	brimG.transform = Transform3D(Basis(Vector3.BACK, 0.12), Vector3(0.012, 0.012, 0))
	hel.add_child(brimG)
	var brim_geo := G.sphere(R * 1.1, 8, 2, PI - 0.62, 1.24, PI * 0.27, PI * 0.07)
	add.call(brim_geo, accentMat, brimG)
	var under := mat("#c94a33")
	under.cull_mode = BaseMaterial3D.CULL_FRONT
	add.call(brim_geo, under, brimG)
	# chin bar: torus arc round the front (+X)
	var chin_geo := G.xform(G.torus(R * 0.97, 0.026, 4, 10, 1.95), Transform3D(Basis(Vector3.UP, 0.975) * Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO))
	var chin: MeshInstance3D = add.call(chin_geo, chinMat)
	chin.transform = Transform3D(Basis.from_scale(Vector3(1.05, 1.6, 1.02)), Vector3(0.006, -0.088, 0))
	var cv: MeshInstance3D = add.call(G.box(0.014, 0.026, 0.05), ventMat)
	cv.position = Vector3(R * 1.0 + 0.032, -0.088, 0)
	for sz in [-1.0, 1.0]:
		var v: MeshInstance3D = add.call(G.box(0.03, 0.016, 0.01), ventMat)
		v.transform = Transform3D(Basis(Vector3.UP, sz * 0.8), Vector3(R * 0.8 + 0.012, -0.088, sz * R * 0.62))
	for z in [-0.045, 0.045]:
		var v: MeshInstance3D = add.call(G.box(0.05, 0.01, 0.014), ventMat)
		v.transform = Transform3D(Basis(Vector3.BACK, -0.15), Vector3(0.02, R * 0.99, z))
	var gog := Node3D.new()
	gog.position = Vector3(R * 0.86, 0.022, 0)
	hel.add_child(gog)
	add.call(G.box(0.04, 0.062, 0.19), frameMat, gog)
	var gl: MeshInstance3D = add.call(G.box(0.01, 0.048, 0.17), lensMat, gog)
	gl.position.x = 0.021
	for sz in [-1.0, 1.0]:
		var tab: MeshInstance3D = add.call(G.box(0.05, 0.03, 0.012), frameMat, gog)
		tab.transform = Transform3D(Basis(Vector3.UP, sz * 0.5), Vector3(-0.03, 0, sz * 0.1))


## Swap the built-in helmet for the model (helmet.glb's "helmet" MeshInstance3D: centred on its shell,
## +X = face, +Y up). Adds the moto goggles with the strap hugging the shell.
func set_helmet(model: Node3D) -> void:
	var F := HELMET_FIT
	for c in hel.get_children():
		hel.remove_child(c)
		c.queue_free()
	var w := Node3D.new()
	w.name = "HelmetModel"
	w.transform = Transform3D(Basis(Vector3.BACK, F.tilt).scaled(Vector3.ONE * F.scale), Vector3(F.x, F.y, 0))
	model.owner = null
	if model.get_parent():
		model.get_parent().remove_child(model)
	w.add_child(model)
	helmet_mats = {}
	var shell_tris := PackedVector3Array()   # shell triangles in head space, for the strap
	var meshes: Array = [model]
	meshes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	for o in meshes:
		if not (o is MeshInstance3D) or o.mesh == null:
			continue
		var mi: MeshInstance3D = o
		var to_head: Transform3D = w.transform * _rel_xform(mi, model) * model.transform
		for si in mi.mesh.get_surface_count():
			var sm: Material = mi.get_surface_override_material(si)
			if sm == null:
				sm = mi.mesh.surface_get_material(si)
			if sm == null:
				continue
			var nm := sm.resource_name
			var dup: Material = sm.duplicate()   # own copy, so recolouring doesn't touch the shared resource
			dup.resource_name = nm
			mi.set_surface_override_material(si, dup)
			helmet_mats[nm] = dup
			if nm == "shell":
				shell_tris.append_array(_surface_tris(mi.mesh, si, to_head))
	head.add_child(w)
	helmet_model = w
	# dark face behind the opening
	var face := MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.1
	fs.height = 0.2
	fs.radial_segments = 12
	fs.rings = 10
	face.mesh = fs
	face.material_override = mat("#15181d", 0.9)
	face.transform = Transform3D(Basis.from_scale(Vector3(1, 1.2, 0.95)), Vector3(0, -0.01, 0))
	hel.add_child(face)
	# strap hugging the shell: rays from outside looking back in (head space)
	var hug := Callable()
	if not shell_tris.is_empty():
		hug = func(x: float, y: float, dx: float, dz: float) -> Variant:
			return _hug(shell_tris, x, y, dx, dz)
	goggles = GEAR.build_goggles(goggle_mats, GOGGLE_FIT, hug)
	head.add_child(goggles)
	if not look.is_empty():
		set_look(look)


static func _rel_xform(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D()
	var c: Node = n
	while c != root and c is Node3D:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t


static func _surface_tris(mesh: Mesh, si: int, t: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arr := mesh.surface_get_arrays(si)
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
		return out
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx == null or (idx as PackedInt32Array).is_empty():
		for p in v:
			out.append(t * p)
	else:
		for i in idx:
			out.append(t * v[i])
	return out


## distance from (x, y, 0) to the shell's outside along (dx, 0, dz), or null
static func _hug(tris: PackedVector3Array, x: float, y: float, dx: float, dz: float) -> Variant:
	var o := Vector3(x + dx * 0.6, y, dz * 0.6)
	var d := Vector3(-dx, 0, -dz)
	var best := INF
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var b := tris[k + 1]
		var c := tris[k + 2]
		if minf(a.y, minf(b.y, c.y)) > y or maxf(a.y, maxf(b.y, c.y)) < y:
			continue
		var hit = Geometry3D.ray_intersects_triangle(o, d, a, b, c)
		if hit != null:
			best = minf(best, (hit - o).length())
	return null if best == INF else 0.6 - best


## colours: {shell, peak, jersey, pants, gloves, shoes, shoeAccent, goggleFrame, lens, strap} as "#rrggbb"
func set_look(l: Dictionary) -> void:
	look.merge(l, true)
	var L := look
	var c := func(m, k: String) -> void:
		if m != null and L.get(k):
			m.albedo_color = Color(L[k])
	var shade := func(m, k: String, dl: float) -> void:
		if m != null and L.get(k):
			m.albedo_color = _offset_l(Color(L[k]), dl)
	if not helmet_mats.is_empty():
		c.call(helmet_mats.get("shell"), "shell")
		c.call(helmet_mats.get("peak"), "peak")
		var sh = helmet_mats.get("shell")
		if sh is BaseMaterial3D:
			sh.roughness = 0.28
			sh.metallic = 0.25
	c.call(kit.jersey[0], "jersey")
	shade.call(kit.jersey[1], "jersey", -0.08)
	c.call(kit.pants[0], "pants")
	shade.call(kit.pants[1], "pants", 0.1)
	c.call(kit.gloves[0], "gloves")
	c.call(shoe_mats.upper, "shoes")
	c.call(shoe_mats.accent, "shoeAccent")
	c.call(goggle_mats.frame, "goggleFrame")
	c.call(goggle_mats.strap, "strap")
	if L.get("lens"):
		goggle_mats.lens.albedo_color = Color(L.lens)
		var e := Color(L.lens).srgb_to_linear() * 0.25
		goggle_mats.lens.emission = Color(e.r, e.g, e.b).linear_to_srgb()


## three's Color.offsetHSL(0, 0, dl): HSL lightness offset in linear space
static func _offset_l(col: Color, dl: float) -> Color:
	var c := col.srgb_to_linear()
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) / 2.0
	var h := 0.0
	var s := 0.0
	if mx != mn:
		var d := mx - mn
		s = d / (mx + mn) if l <= 0.5 else d / (2.0 - mx - mn)
		if mx == c.r:
			h = (c.g - c.b) / d + (6.0 if c.g < c.b else 0.0)
		elif mx == c.g:
			h = (c.b - c.r) / d + 2.0
		else:
			h = (c.r - c.g) / d + 4.0
		h /= 6.0
	l = clampf(l + dl, 0.0, 1.0)
	var out := Color(l, l, l)
	if s != 0.0:
		var p := l * (1.0 + s) if l <= 0.5 else l + s - l * s
		var q := 2.0 * l - p
		out = Color(_hue2rgb(q, p, h + 1.0 / 3.0), _hue2rgb(q, p, h), _hue2rgb(q, p, h - 1.0 / 3.0))
	return out.linear_to_srgb()


static func _hue2rgb(p: float, q: float, t: float) -> float:
	if t < 0.0: t += 1.0
	if t > 1.0: t -= 1.0
	if t < 1.0 / 6.0: return p + (q - p) * 6.0 * t
	if t < 0.5: return q
	if t < 2.0 / 3.0: return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p


## riding position; keys as NEUTRAL (missing keys take the neutral value) plus elbowsOut / kneesOut
func set_style(s: Dictionary) -> void:
	style = NEUTRAL.duplicate()
	style.merge(s, true)
	var kneesOut: float = style.kneesOut
	var elbowsOut: float = style.elbowsOut
	poles_leg.clear()
	poles_arm.clear()
	for sd in [-1.0, 1.0]:
		var ko: float = kneesOut + float(style.kneeOutL if sd < 0 else style.kneeOutR)
		var eo: float = elbowsOut + float(style.elbowOutL if sd < 0 else style.elbowOutR)
		poles_leg.append(Vector3(1 + float(style.kneesFwd), 0.1 - 0.5 * float(style.kneesFwd), sd * (0.1 + 0.3 * ko)).normalized())
		poles_arm.append(Vector3(-0.4 + 0.25 * eo, -0.5 + 0.4 * eo - float(style.elbowsDown), sd).normalized())


# ---------------- posing helpers ----------------

## unit-height (+Y) cylinder between a and b
static func set_limb(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-5:
		n.transform = Transform3D(Basis.from_scale(Vector3(1, 1e-4, 1)), a + d * 0.5)
		return
	var q := Quaternion(Vector3.UP, d / l)
	n.transform = Transform3D(Basis(q).scaled_local(Vector3(1, l, 1)), a + d * 0.5)


## torso: like set_limb, but keeps its width across the body (`right`) so the section doesn't twist
static func set_torso(n: Node3D, a: Vector3, b: Vector3, right: Vector3) -> void:
	var d := b - a
	var l := maxf(d.length(), 1e-4)
	d /= l
	var r := (right - d * right.dot(d)).normalized()
	var f := d.cross(r)
	n.transform = Transform3D(Basis(f, d * l, r), a + (b - a) * 0.5)


# ---------------- the spine: the torso mesh is skinned to SPINE_BONES bones along its length so it can bend

const SPINE_BONES := 5
var spine_skel: Skeleton3D

## weights each torso vertex to the two spine bones either side of its height (mesh y -0.5 .. 0.5)
func _skin_torso() -> void:
	var arr: Array = torso.mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	bones.resize(pos.size() * 4)
	wts.resize(pos.size() * 4)
	var segs := SPINE_BONES - 1
	for i in pos.size():
		var u := clampf(pos[i].y + 0.5, 0.0, 1.0) * segs
		var b0 := mini(int(u), segs - 1)
		var w := u - b0
		bones[i * 4] = b0
		bones[i * 4 + 1] = b0 + 1
		wts[i * 4] = 1.0 - w
		wts[i * 4 + 1] = w
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = wts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	torso.mesh = m
	spine_skel = Skeleton3D.new()
	spine_skel.name = "Spine"
	add_child(spine_skel)
	var skin := Skin.new()
	for k in SPINE_BONES:
		spine_skel.add_bone("s%d" % k)
		skin.add_bind(k, Transform3D.IDENTITY)
	torso.skin = skin
	torso.skeleton = NodePath("../Spine")
	torso.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))   # the bones move it anywhere

## the torso from hip `a` to chest `b` as a curve: `curve` bows the back out (+, hunched) or in (-, arched),
## `side` bows it sideways; `low` (0..1) moves the bend toward the hips (0) or the shoulders (1).
## The cross-section turns from `right_lo` at the hips to `right_hi` at the chest (twist).
func set_spine(a: Vector3, b: Vector3, right_lo: Vector3, right_hi: Vector3, curve := 0.0, side := 0.0, low := 0.5) -> void:
	var d := b - a
	var l := maxf(d.length(), 1e-4)
	var dn := d / l
	var r0 := (right_hi - dn * right_hi.dot(dn)).normalized()
	var fwd := dn.cross(r0)   # toward the belly
	var ctrl := a + d * clampf(low, 0.05, 0.95) - fwd * curve * l + r0 * side * l
	for k in SPINE_BONES:
		var t := float(k) / (SPINE_BONES - 1)
		var p := a * (1 - t) * (1 - t) + ctrl * 2 * t * (1 - t) + b * t * t
		var tg := (ctrl - a) * 2 * (1 - t) + (b - ctrl) * 2 * t
		var tl := maxf(tg.length(), 1e-4)
		var tn := tg / tl
		var rr := right_lo.lerp(right_hi, t)
		rr = (rr - tn * rr.dot(tn)).normalized()
		var f := tn.cross(rr)
		spine_skel.set_bone_pose(k, Transform3D(Basis(f, tn * tl, rr), p - tn * tl * (t - 0.5)))


## hand: +X along the forearm, +Z along the bar, +Y the back of the hand
static func orient_hand(n: Node3D, el: Vector3, at: Vector3, right: Vector3) -> void:
	var x := (at - el).normalized()
	var z := (right - x * right.dot(x)).normalized()
	var y := z.cross(x)
	n.basis = Basis(x, y, z)


## analytic two-bone IK -> [joint, reachable end]
static func solve_ik(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> Array:
	var d := target - root
	var dist := d.length()
	if dist < 1e-5:
		d = Vector3(0, -1, 0)
		dist = 1e-5
	else:
		d /= dist
	var dir := d
	dist = clampf(dist, absf(l1 - l2) + 0.01, (l1 + l2) * 0.9995)
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var pp := pole - dir * pole.dot(dir)
	if pp.length_squared() < 1e-8:
		pp = Vector3(0, 0, 1) - dir * dir.z
	pp = pp.normalized()
	return [root + dir * a + pp * h, root + dir * dist]


## rotation basis: up = Y, right projected = Z, forward = X
static func _basis_from(up: Vector3, right: Vector3) -> Basis:
	var u := up.normalized()
	var r := (right - u * right.dot(u)).normalized()
	var f := u.cross(r)
	return Basis(f, u, r)


# ---------------- ragdoll hand-off ----------------

## world positions of the 15 ragdoll joints (Ragdoll.HEAD.. order)
func joints_world() -> Array:
	var t := global_transform if is_inside_tree() else transform
	var out := []
	for v in J:
		out.append(t * v)
	return out


## drive the meshes from world-space ragdoll points (this node must sit at the world origin)
func pose_ragdoll(P: Array) -> void:
	var hd: Vector3 = P[0]
	var ch: Vector3 = P[1]
	var pe: Vector3 = P[2]
	var sh := [P[3], P[6]]
	var el := [P[4], P[7]]
	var ha := [P[5], P[8]]
	var hp := [P[9], P[12]]
	var kn := [P[10], P[13]]
	var ft := [P[11], P[14]]
	var body_r: Vector3 = hp[1] - hp[0]
	var bb := _basis_from(ch - pe, body_r)
	pelvis_mesh.transform = Transform3D(bb, pe)
	var hip: Vector3 = pe + (ch - pe).normalized() * 0.02
	set_spine(hip, ch, body_r.normalized(), (sh[1] - sh[0]).normalized())
	set_limb(hood_hem, hip, hip.lerp(ch, 0.2))
	hood.position = ch
	var sh_r: Vector3 = sh[1] - sh[0]
	head.transform = Transform3D(_basis_from(hd - ch, sh_r), hd)
	for i in 2:
		shoulder_sph[i].position = sh[i]
		set_limb(upper_arm[i], sh[i], el[i])
		set_limb(fore_arm[i], el[i], ha[i])
		elbow[i].position = el[i]
		glove[i].position = ha[i]
		orient_hand(glove[i], el[i], ha[i], sh_r)
		set_limb(thigh[i], hp[i], kn[i])
		set_limb(shin[i], kn[i], ft[i])
		knee[i].position = kn[i]
		var up: Vector3 = kn[i] - ft[i]
		shoe[i].transform = Transform3D(_basis_from(up, body_r), ft[i] - up.normalized() * 0.08)


## back on the bike: clear the ragdoll orientations the normal update doesn't set
func reset_pose() -> void:
	pelvis_mesh.basis = Basis()
	head.basis = Basis()
	for s in shoe:
		s.basis = Basis()
	spring_init = false
	pel_v = Vector3.ZERO
	ch_v = Vector3.ZERO


# ---------------- per-frame pose ----------------

static func _num(p: Dictionary, k: String, def := 0.0) -> float:
	var v = p.get(k)
	if v == null:
		return def
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


## p: footL, footR, handL, handR (Vector3, this node's space), v, lean, steer, yawRate, counter, rockRoll,
## headRoll, absorb, pitch, bodyLevel, attackDrop, pedal, sprint, crank, air, compress, hipShift, t
func update_pose(dt: float, p: Dictionary) -> void:
	var v := _num(p, "v")
	var pedal := clampf(_num(p, "pedal"), 0, 1)
	var t := _num(p, "t")
	var low_speed := 1.0 - clampf(absf(v) / 6.0, 0, 1)

	var target_shift := 0.0 if p.get("counter") != null else _num(p, "lean") * low_speed
	var k := 1.0 - exp(-10.0 * minf(dt, 0.1))
	sm_shift_z += (target_shift - sm_shift_z) * k
	var shift := clampf(sm_shift_z, -0.6, 0.6)

	var sty := style
	var crank := _num(p, "crank")
	var spr := clampf(_num(p, "sprint"), 0, 1)
	var sway: float = sin(crank) * pedal * sty.sway * (1 + 0.9 * spr)
	var bob: float = sin(crank * 2) * pedal * sty.sway * (1 + 0.6 * spr)
	var wig: float = clampf(1 - absf(v) / 3, 0, 1) * sty.sway
	var air := _num(p, "air")
	var comp: float = _num(p, "compress") * sty.crouch

	# pelvis
	var pelvis := Vector3(
		-0.16 - 0.07 * air + 0.06 * pedal * sty.standPedal - comp * 0.25,
		0.80 - 0.07 * air - comp + (0.15 * pedal + 0.05 * spr) * sty.standPedal + 0.035 * bob,
		sway * sty.hipSway + shift * 0.3 + sin(t * 2.1) * 0.02 * wig) + fit
	pelvis.x += sty.hipX * (1 - 0.5 * pedal)
	pelvis.y += sty.hipY * (1 - 0.6 * pedal)

	# chest
	var ang: float = 0.72 - 0.14 * pedal + 0.12 * spr + 0.15 * (comp / 0.3) + 0.08 * air + sty.lean * (1 - 0.5 * pedal)
	var L: float = sty.torso
	var chest := Vector3(
		pelvis.x + sin(ang) * L + 0.03 * pedal * (0.5 + 0.5 * bob),
		pelvis.y + cos(ang) * L,
		pelvis.z + shift * 0.3 - sway * sty.hipSway + sin(t * 1.7 + 1.0) * 0.02 * wig)

	pelvis.z += sty.hipZ
	chest += Vector3(sty.chestFwd, sty.chestUp, sty.chestSide)

	var absorb := _num(p, "absorb")
	pelvis.y += absorb
	chest.y += absorb * 0.9
	var hs := _num(p, "hipShift")
	pelvis.x += hs
	chest.x += hs * 0.6
	# keep the body level while the bike pitches (descents: almost fully; climbs: a little)
	var pitch0 := _num(p, "pitch")
	var pit := pitch0 * (0.2 if pitch0 > 0 else _num(p, "bodyLevel", 0.85))
	if pit != 0.0:
		var c := cos(-pit)
		var sn := sin(-pit)
		var y0 := 0.3
		var pts := [pelvis, chest]
		for i in 2:
			var q: Vector3 = pts[i]
			var dx := q.x
			var dy := q.y - y0
			q.x = dx * c - dy * sn
			q.y = y0 + dx * sn + dy * c
			pts[i] = q
		pelvis = pts[0]
		chest = pts[1]
		var down := maxf(0.0, -pitch0)
		var drop := _num(p, "attackDrop", 0.18)
		pelvis.y -= down * drop
		pelvis.x -= down * drop * 0.45
	# climbing: hips to the saddle nose, chest low over the bars
	var climb := clampf(pitch0, 0, 0.6)
	if climb > 0:
		pelvis.x += climb * 0.22
		pelvis.y -= climb * 0.04
		chest.x += climb * 0.42
		chest.y -= climb * 0.24
	# lean the BIKE, not the body: roll the body back toward upright about the pedals
	var cr := _num(p, "counter")
	if cr != 0.0:
		var c := cos(cr)
		var sn := sin(cr)
		var y0 := 0.3
		var dy := pelvis.y - y0
		var dz := pelvis.z
		pelvis.y = y0 + dy * c - dz * sn
		pelvis.z = dy * sn + dz * c
		dy = chest.y - y0
		dz = chest.z
		chest.y = y0 + dy * c - dz * sn
		chest.z = dy * sn + dz * c
		pelvis.y -= absf(cr) * 0.12
		chest.x += absf(cr) * 0.05
	# never sit INTO the saddle
	if sty.seatFloor and seat != null:
		var over := clampf((pelvis.x - (float(seat.rear) - 0.18)) / 0.08, 0, 1)
		var floor_y: float = float(seat.top) + 0.085
		if pelvis.y < floor_y:
			pelvis.y += (floor_y - pelvis.y) * over
		if chest.y < pelvis.y + 0.15:
			chest.y = pelvis.y + 0.15
	# critically-damped-ish springs -> follow-through
	if not spring_init:
		pel_s = pelvis
		ch_s = chest
		spring_init = true
	var h := minf(dt, 0.05)
	var dp := 2 * sqrt(260.0) * 0.85
	pel_v += ((pelvis - pel_s) * 260.0 - pel_v * dp) * h
	pel_s += pel_v * h
	pelvis = pel_s
	var dc := 2 * sqrt(200.0) * 0.85
	ch_v += ((chest - ch_s) * 200.0 - ch_v * dc) * h
	ch_s += ch_v * h
	chest = ch_s
	# pedalling rock: undo the bike's rock for hips and chest about the tyres' contact line
	var rr: float = _num(p, "rockRoll") * sty.upright
	if rr != 0.0:
		var c := cos(rr)
		var sn := sin(rr)
		var dy := pelvis.y
		var dz := pelvis.z
		pelvis.y = dy * c - dz * sn
		pelvis.z = dy * sn + dz * c
		dy = chest.y
		dz = chest.z
		chest.y = dy * c - dz * sn
		chest.z = dy * sn + dz * c
	# arms only reach so far: the torso follows the hands so the elbows keep a bend
	var handL = p.get("handL")
	var handR = p.get("handR")
	if handL is Vector3 and handR is Vector3:
		var reach := (L_UARM + L_FARM) * 0.9
		var worst := 0.0
		for sd in [[-1.0, handL], [1.0, handR]]:
			var shp := Vector3(chest.x - 0.03, chest.y - 0.04, chest.z + sd[0] * sty.shoulders)
			var over: float = shp.distance_to(sd[1]) - reach
			if over > worst:
				worst = over
		if worst > 0:
			var d: Vector3 = (handL + handR) * 0.5 - Vector3(chest.x - 0.03, chest.y - 0.04, chest.z)
			var len := d.length()
			if len > 1e-4:
				d *= minf(worst + 0.01, len * 0.6) / len
				chest += d
				pelvis += d * 0.35

	# torso from pelvis to chest
	var hip := Vector3(pelvis.x, pelvis.y + 0.02, pelvis.z)
	var tw_axis := (chest - hip).normalized()
	var tw := Basis(tw_axis, float(sty.twist))
	# pelvis: turn (yaw about up), roll (one hip drops, about forward), tilt (about the hip line)
	var pel_b := Basis(Vector3.UP, float(sty.pelvisYaw)) * Basis(Vector3.RIGHT, float(sty.pelvisRoll))
	set_spine(hip, chest, pel_b * Vector3(0, 0, 1), tw * Vector3(0, 0, 1),
		float(sty.spineCurve), float(sty.spineSide), float(sty.spineLow))
	pelvis_mesh.transform = Transform3D(pel_b * Basis(Vector3.BACK, -(ang * 0.3) - float(sty.pelvisTilt)), pelvis)
	set_limb(hood_hem, Vector3(pelvis.x, pelvis.y + 0.04, pelvis.z), hip.lerp(chest, 0.2))

	# neck / head
	var neck := chest
	hood.position = Vector3(neck.x - 0.03, neck.y, neck.z)
	var head_p := Vector3(neck.x + 0.05 + sty.lookAhead, neck.y + 0.2 + sty.neck, neck.z)
	J[0] = head_p
	J[1] = chest
	J[2] = pelvis
	var yaw: float = clampf((_num(p, "steer") * 1.2 + _num(p, "yawRate") * 0.15) * sty.headTurn, -1.0, 1.0) + sty.headYaw
	var rx: float = (_num(p, "headRoll") if p.get("headRoll") != null else _num(p, "lean") * 0.6) + sty.headRoll
	var rz: float = -0.12 * (ang - 0.72) + 0.04 * sin(t * 3.3) * wig - sty.headTilt
	head.transform = Transform3D(GEAR.euler_xyz(rx, yaw, rz), head_p)

	var right := Vector3(0, 0, 1)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var foot: Vector3 = p.get("footL" if i == 0 else "footR", Vector3.ZERO)
		var hand: Vector3 = p.get("handL" if i == 0 else "handR", Vector3.ZERO)
		# leg
		var hp: Vector3 = pelvis + pel_b * Vector3(0, -0.02, side * (0.11 + sty.stance))
		var ankle := Vector3(foot.x - 0.04 + sty.heelFwd, foot.y + 0.12 + sty.heelUp, foot.z)
		var ik := solve_ik(hp, ankle, L_THIGH, L_SHIN, poles_leg[i])
		set_limb(thigh[i], hp, ik[0])
		set_limb(shin[i], ik[0], ik[1])
		knee[i].position = ik[0]
		shoe[i].position = Vector3(foot.x, foot.y + 0.03, foot.z)
		shoe[i].basis = Basis(Vector3.UP, -side * float(sty.footOut)) * Basis(Vector3.BACK, float(sty.footAngle))
		J[9 + i * 3] = hp
		J[10 + i * 3] = ik[0]
		J[11 + i * 3] = Vector3(foot.x, foot.y + 0.08, foot.z)
		# arm
		var sh_off := Vector3(-0.03 + sty.shoulderFwd, -0.04 + sty.shoulderUp, side * sty.shoulders)
		var shp: Vector3 = chest + tw * sh_off
		shoulder_sph[i].position = shp
		var ika := solve_ik(shp, hand, L_UARM, L_FARM, poles_arm[i])
		set_limb(upper_arm[i], shp, ika[0])
		set_limb(fore_arm[i], ika[0], ika[1])
		elbow[i].position = ika[0]
		glove[i].position = hand
		orient_hand(glove[i], ika[0], hand, right)
		if sty.wristRoll != 0.0:
			glove[i].rotate_object_local(Vector3.RIGHT, side * float(sty.wristRoll))
		J[3 + i * 3] = shp
		J[4 + i * 3] = ika[0]
		J[5 + i * 3] = hand
