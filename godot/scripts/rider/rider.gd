class_name Rider
extends Node3D
## Port of src/rider.js: the low-poly cartoon rider, posed procedurally every frame.
## This node is the JS rider.group: parent it under the bike's lean node. Local frame: +X forward,
## +Y up, +Z the rider's right; the bottom bracket sits near the origin (0.297 up on the BMX).

const G := preload("res://scripts/rider/rider_geo.gd")
const GEAR := preload("res://scripts/rider/rider_gear.gd")

## neutral riding style (posepanel.js NEUTRAL): BMX = all of these
const NEUTRAL := {hipX = 0.0, hipY = 0.0, lean = 0.0, elbowsOut = 0.0, kneesOut = 0.0, stance = 0.0, seatFloor = false,
	crouch = 1.0, standPedal = 1.0, aero = 1.0, sway = 1.0, bikeRock = 1.0, upright = 1.0, hipSway = 0.015, torso = 0.46, attackStand = 1.0, kneeOpen = 1.0, bumpAbsorb = 2.0, bodyBounce = 0.4, bodyBob = 1.0,
	# style (Rider > Style): the numbers the riding pose is built from
	hipSteady = 90.0, standHeight = 0.15, standBack = 0.03, pedalChest = 0.05, turnLow = 1.0, turnTwist = 1.0,
	turnHips = 1.0, slowWobble = 1.0, airCrouch = 1.0,
	shoulders = 0.2, headTilt = 0.0, headTurn = 1.0, lookAhead = 0.0,
	# per-bone controls (garage Rider tab / K panel); 0 = the riding pose as computed
	hipZ = 0.0, pelvisTilt = 0.0, pelvisRoll = 0.0, pelvisYaw = 0.0,
	spineCurve = 0.0, spineSide = 0.0, spineLow = 0.5, chestFwd = 0.0, chestUp = 0.0, chestSide = 0.0, twist = 0.0,
	neck = 0.0, headYaw = 0.0, headRoll = 0.0,
	shoulderFwd = 0.0, shoulderUp = 0.0, elbowsDown = 0.0, elbowOutL = 0.0, elbowOutR = 0.0, wristRoll = 0.0,
	elbowsBack = 0.0, armBend = 0.0,
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
var action_cam: Node3D = null   # helmet-top action camera (ActionCam); its "Lens" is the Helmet camera view
var action_cam_at := Vector3.ZERO   # where it's mounted (head space)

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
	# a belt round the waist: hides the step where the jersey's hem meets the trouser top. Its own shape
	# follows the hips' rounded box (a superellipse just outside it), so no corner pokes through
	var belt := G.inst(_belt_geo(0.106, 0.156, 0.035, 0.08, 0.006), mat("#151517", 0.55, 0.1))
	belt.name = "Belt"
	pelvis_mesh.add_child(belt)
	var buckle := G.inst(G.rounded_box(0.008, 0.042, 0.056, 1, 0.003), mat("#9aa0a8", 0.3, 0.9))
	buckle.name = "Buckle"
	buckle.position = Vector3(0.113, 0.058, 0.0)
	pelvis_mesh.add_child(buckle)
	var bib := BackNumber.new()   # race number paper pinned to the back, flaps with speed
	bib.name = "BackNumber"
	add_child(bib)
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
	# the wordmark printed on the strap (white lettering texture, tinted black / white by the strap colour)
	var logo := mat("#ffffff", 0.8)
	logo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	logo.cull_mode = BaseMaterial3D.CULL_DISABLED
	goggle_mats = {frame = mat("#f2f2ee", 0.45), foam = mat("#15171a", 1.0), strap = strap, lens = lens, logo = logo}
	var baker := StrapLogo.new()
	baker.mat = logo
	baker.text = "GIANT"
	add_child(baker)
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
	_mount_action_cam(Vector3(0.03, hel.position.y + R * 0.96 - 0.004, 0))


## the action camera on top of the helmet, just forward of the crown (`at` = shell top, head space)
func _mount_action_cam(at: Vector3) -> void:
	if action_cam and is_instance_valid(action_cam):
		action_cam.get_parent().remove_child(action_cam)
		action_cam.queue_free()
	action_cam = ActionCam.build()
	action_cam.position = at
	action_cam_at = at
	head.add_child(action_cam)


## crash: the camera body snaps off its hinge (the base + buckle stay on the helmet). Returns the body
## (taken out of the tree) and its world transform, or {} when it's already gone.
func break_action_cam() -> Dictionary:
	if action_cam == null or not is_instance_valid(action_cam):
		return {}
	var b := action_cam.get_node_or_null("Body") as Node3D
	if b == null or not b.is_inside_tree():
		return {}
	var xf := b.global_transform
	action_cam.remove_child(b)
	return {body = b, xform = xf}


## a fresh camera on the helmet (get-up / respawn), if the old one broke off
func remount_action_cam() -> void:
	if action_cam and is_instance_valid(action_cam) and action_cam.get_node_or_null("Body") != null:
		return
	_mount_action_cam(action_cam_at)


## highest point of the shell near (x, z=0), head space (the action cam sits there)
static func _shell_top(tris: PackedVector3Array, x: float) -> float:
	var best := -1e9
	for p in tris:
		if absf(p.z) < 0.03 and absf(p.x - x) < 0.03 and p.y > best:
			best = p.y
	return best


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
	var flap := HelmetFlap.new()   # loose strap tail that flaps with speed
	flap.name = "StrapFlap"
	flap.anchor_local = goggles.get_meta("flap_anchor", Vector3.ZERO)
	flap.material_override = goggle_mats.strap
	goggles.add_child(flap)
	var top := _shell_top(shell_tris, 0.03) if not shell_tris.is_empty() else -1e9
	if top < -1e8:   # no shell triangles: the helmet's bounding box top
		top = 0.2
	_mount_action_cam(Vector3(0.03, top - 0.004, 0))
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
		# elbows bend back and down, only a little out to the side (more with Elbows out)
		poles_arm.append(Vector3(-0.4 + 0.25 * eo - float(style.elbowsBack), -0.5 + 0.4 * eo - float(style.elbowsDown), sd * clampf(0.35 + 0.65 * eo, 0.1, 1.2)).normalized())


# ---------------- posing helpers ----------------

## unit-height (+Y) cylinder between a and b
## a flat strap round a superellipse (|x/a|^4 + |z/b|^4 = 1) from y0 to y1, standing `t` out from it
static func _belt_geo(a: float, b: float, y0: float, y1: float, t: float, n := 48) -> Dictionary:
	var ring: Array[Vector3] = []
	for i in n:
		var u := TAU * i / n
		var cu := cos(u)
		var su := sin(u)
		ring.append(Vector3(a * signf(cu) * sqrt(absf(cu)), 0.0, b * signf(su) * sqrt(absf(su))))
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n:
		var pv: Vector3 = ring[(i - 1 + n) % n]
		var nx: Vector3 = ring[(i + 1) % n]
		var tang := (nx - pv).normalized()
		var outv := Vector3(tang.z, 0.0, -tang.x)
		if outv.dot(ring[i]) < 0.0: outv = -outv
		var q: Vector3 = ring[i]
		pos.append_array([q + Vector3(0, y0, 0) - outv * 0.004, q + outv * t + Vector3(0, y0, 0),
			q + outv * t + Vector3(0, y1, 0), q + Vector3(0, y1, 0) - outv * 0.004])
	for i in n:
		var a0 := i * 4
		var b0 := ((i + 1) % n) * 4
		for f in [[1, 2], [2, 3], [0, 1]]:   # outside face, top edge, bottom edge
			var c0: int = f[0]
			var c1: int = f[1]
			idx.append_array([a0 + c0, b0 + c1, b0 + c0, a0 + c0, a0 + c1, b0 + c1])
	return {pos = pos, idx = idx}

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
var knee_dbg: Array = []   # tests: frames where a knee bends against its pole
var torso_ratio := 1.0   # tests: torso length / its rest length before the limit
## tests (BMX_LIMB_PROBE): per joint, how fast its bend direction turns (deg/s) and how far it moves
## relative to its limb root per frame; frames over the limits are counted
var limb_probe := OS.get_environment("BMX_LIMB_PROBE") != ""
var limb_stats := {}
var _limb_prev := {}
var _probe_pitch := 0.0
func _probe_limb(key: String, root: Vector3, joint: Vector3, end: Vector3, dt: float, air: float) -> void:
	var ax := end - root
	var bend := joint - root
	if ax.length_squared() > 1e-8:
		var an := ax.normalized()
		bend = bend - an * bend.dot(an)
	var bl := bend.length()
	var bd := bend / bl if bl > 1e-6 else Vector3.ZERO
	var rel := joint - root
	var s: Dictionary = limb_stats.get(key, {"turn_max": 0.0, "jump_max": 0.0, "flips": 0, "jumps": 0, "frames": 0, "worst": []})
	var now := Time.get_ticks_msec()
	if _limb_prev.has(key) and dt > 1e-4 and now - int(_limb_prev[key][2]) < 100:   # not across a crash / respawn
		var pv: Array = _limb_prev[key]
		var turn := 0.0
		if bd != Vector3.ZERO and pv[0] != Vector3.ZERO:
			turn = rad_to_deg(acos(clampf(bd.dot(pv[0]), -1.0, 1.0)))
		var jump: float = (rel - pv[1]).length()
		s.frames += 1
		if turn > s.turn_max: s.turn_max = turn
		if jump > s.jump_max: s.jump_max = jump
		if turn > 25.0 and bl > 0.03: s.flips += 1   # a visibly bent limb whose bend swings 25+ deg in one frame
		if jump > 0.06: s.jumps += 1
		if turn > 25.0 and bl > 0.03:
			s.worst.append({"turn": snappedf(turn, 0.1), "jump": snappedf(jump, 0.001), "bend": snappedf(bl, 0.001), "air": snappedf(air, 0.01),
				"reach": snappedf(ax.length(), 0.001), "dir": ax.normalized().snapped(Vector3.ONE * 0.01), "bd": bd.snapped(Vector3.ONE * 0.01), "pbd": (pv[0] as Vector3).snapped(Vector3.ONE * 0.01), "droot": snappedf(root.distance_to(pv[3]), 0.001), "dend": snappedf(end.distance_to(pv[4]), 0.001), "dt": snappedf(dt, 0.0001), "pitch": snappedf(_probe_pitch, 0.01)})
			s.worst.sort_custom(func(x, y): return x.turn > y.turn)
			if s.worst.size() > 8: s.worst.resize(8)
	_limb_prev[key] = [bd, rel, now, root, end]
	limb_stats[key] = s
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
	# the unbent shape, for the mud pass (shaders/grime_mud): its splotches stay put on the jersey
	var rest := PackedFloat32Array()
	rest.resize(pos.size() * 3)
	for i in pos.size():
		rest[i * 3] = pos[i].x; rest[i * 3 + 1] = pos[i].y; rest[i * 3 + 2] = pos[i].z
	arr[Mesh.ARRAY_CUSTOM0] = rest
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
		Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
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

## a point on (just off) the jersey's back in this node's space: t 0 hips .. 1 collar, z sideways, `off` out of the
## surface. Follows the bent spine exactly like the skinned torso (identity binds, linear blend of two bones).
func back_point(t: float, z: float, off := 0.0) -> Vector3:
	var m := Vector3(-GEAR.torso_back_x(t, z) - off, t - 0.5, z)
	var u := clampf(t, 0.0, 1.0) * (SPINE_BONES - 1)
	var k := mini(int(u), SPINE_BONES - 2)
	var w := u - k
	return (spine_skel.get_bone_pose(k) * m) * (1.0 - w) + (spine_skel.get_bone_pose(k + 1) * m) * w


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
		rr = rr - tn * rr.dot(tn)
		if rr.length_squared() < 1e-6:   # hips and shoulders turned opposite ways (a tangled ragdoll)
			rr = r0 - tn * r0.dot(tn)
			if rr.length_squared() < 1e-6: rr = tn.cross(Vector3.UP if absf(tn.y) < 0.9 else Vector3.RIGHT)
		rr = rr.normalized()
		var f := tn.cross(rr)
		spine_skel.set_bone_pose(k, Transform3D(Basis(f, tn * tl, rr), p - tn * tl * (t - 0.5)))
	# the bones move the mesh, not the node, so the culling box must follow the body (in a crash the
	# rider node sits at the world origin and the torso can be anywhere)
	var c := (a + b) * 0.5
	if not torso.custom_aabb.has_point(c - Vector3.ONE) or not torso.custom_aabb.has_point(c + Vector3.ONE):
		torso.custom_aabb = AABB(c - Vector3(3, 3, 3), Vector3(6, 6, 6))


## hand: +X along the forearm, +Z along the bar, +Y the back of the hand
static func orient_hand(n: Node3D, el: Vector3, at: Vector3, right: Vector3) -> void:
	var x := (at - el).normalized()
	var z := (right - x * right.dot(x)).normalized()
	var y := z.cross(x)
	n.basis = Basis(x, y, z)


## Keep a knee clear of the frame: swing it outward round the hip -> ankle line (leg lengths unchanged)
## until it sits at least KNEE_CLEAR off the bike's centre plane (z = 0 in the bike's leaning space).
const KNEE_CLEAR := 0.12
static func _knee_clear(hip: Vector3, ankle: Vector3, kn: Vector3, side: float) -> Vector3:
	if side * kn.z >= KNEE_CLEAR:
		return kn
	var ax := ankle - hip
	if ax.length_squared() < 1e-6:
		return kn
	ax = ax.normalized()
	var c := hip + ax * (kn - hip).dot(ax)
	var r := (kn - c).length()
	if r < 1e-4:
		return kn
	var u := (kn - c) / r
	var out := Vector3(0, 0, side) - ax * ax.z * side
	if out.length_squared() < 1e-6:
		return kn
	out = out.normalized()
	if u.dot(out) < -0.999 or side * (c + out * r).z < KNEE_CLEAR:
		return c + out * r   # can't clear it: as far out as the leg allows
	# smallest swing that clears (bisection, so the knee moves smoothly frame to frame)
	var lo := 0.0
	var hi := 1.0
	for _k in 14:
		var m := (lo + hi) * 0.5
		if side * (c + u.slerp(out, m) * r).z >= KNEE_CLEAR: hi = m
		else: lo = m
	return c + u.slerp(out, hi) * r

## two-bone IK with joint limits -> [joint, reachable end, bend direction]
## The joint is a hinge: it bends between `min_deg` (0 = straight; > 0 never locks out, so it can't snap
## near full reach) and `max_deg` (how far it folds). It points to the side of `pole`; where the limb lines
## up with `pole` (no side defined) it blends smoothly to `pole2`. `prev` (last frame's bend direction, or
## ZERO) and `max_turn` (rad) limit how far the bend may swing round the limb this frame: no flips.
static func limb_ik(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3, pole2: Vector3,
		min_deg: float, max_deg: float, prev: Vector3, max_turn: float) -> Array:
	var d := target - root
	var dist := d.length()
	var dir := d / dist if dist > 1e-5 else Vector3.DOWN
	var dmax := sqrt(maxf(0.0, l1 * l1 + l2 * l2 + 2 * l1 * l2 * cos(deg_to_rad(min_deg))))
	var dmin := sqrt(maxf(0.0, l1 * l1 + l2 * l2 + 2 * l1 * l2 * cos(deg_to_rad(max_deg))))
	dist = clampf(dist, maxf(dmin, absf(l1 - l2) + 0.01), dmax)
	var p1 := pole - dir * pole.dot(dir)
	var p2 := pole2 - dir * pole2.dot(dir)
	var w := smoothstep(0.2, 0.5, p1.length() / maxf(pole.length(), 1e-6))
	var bd := Vector3.ZERO
	if p1.length_squared() > 1e-10: bd += p1.normalized() * w
	if p2.length_squared() > 1e-10: bd += p2.normalized() * (1.0 - w)
	if bd.length_squared() < 1e-8:
		bd = dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT)
	bd = (bd - dir * bd.dot(dir)).normalized()
	if prev != Vector3.ZERO and max_turn < PI:
		var pr := prev - dir * prev.dot(dir)
		if pr.length_squared() > 1e-6:
			pr = pr.normalized()
			var ang := pr.signed_angle_to(bd, dir)
			if absf(ang) > max_turn:
				bd = pr.rotated(dir, clampf(ang, -max_turn, max_turn)).normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	return [root + dir * a + bd * h, root + dir * dist, bd]

## joint limits (degrees of bend, 0 = straight) and how fast a bend may swing round its limb
const ELBOW_MIN := 12.0
const ELBOW_MAX := 150.0
const KNEE_MIN := 4.0
const KNEE_MAX := 160.0
const BEND_RATE := 6.0   # rad/s
var _bd_prev: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]   # knee L, knee R, elbow L, elbow R


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


## drive the meshes from world-space ragdoll points (this node must sit at the world origin).
## roots: torn-off limbs (Ragdoll.cut): joint index -> the free piece's root point, so the segment that
## ends at that joint is drawn from the root instead of stretching back to the body
func pose_ragdoll(P: Array, roots: Dictionary = {}) -> void:
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
		var ei: int = 4 if i == 0 else 7    # elbow / hand / knee / foot point of this side
		var hi: int = ei + 1
		var ki: int = 10 if i == 0 else 13
		var fi: int = ki + 1
		var el_from: Vector3 = roots.get(ei, sh[i])
		var ha_from: Vector3 = roots.get(hi, el[i])
		var kn_from: Vector3 = roots.get(ki, hp[i])
		var ft_from: Vector3 = roots.get(fi, kn[i])
		shoulder_sph[i].position = sh[i]
		set_limb(upper_arm[i], el_from, el[i])
		set_limb(fore_arm[i], ha_from, ha[i])
		elbow[i].position = el[i]
		glove[i].position = ha[i]
		orient_hand(glove[i], ha_from, ha[i], sh_r)
		set_limb(thigh[i], kn_from, kn[i])
		set_limb(shin[i], ft_from, ft[i])
		knee[i].position = kn[i]
		var up: Vector3 = ft_from - ft[i]
		shoe[i].transform = Transform3D(_basis_from(up, body_r), ft[i] - up.normalized() * 0.08)


## back on the bike: clear the ragdoll orientations the normal update doesn't set
func reset_pose() -> void:
	pelvis_mesh.basis = Basis()
	head.basis = Basis()
	for s in shoe:
		s.basis = Basis()
	spring_init = false
	_bd_prev.fill(Vector3.ZERO)
	pel_v = Vector3.ZERO
	ch_v = Vector3.ZERO
	# what the pose remembers from before (a crash tumbling the bike nose-up left a "wheelie" behind that
	# shoved the body about after getting up)
	sm_wheelie = 0.0; sm_aero = 0.0; sm_effort = 0.0; sm_turn = 0.0


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
var sm_turn := 0.0
var sm_aero := 0.0
var sm_effort := 0.0
var sm_pitch0 := 0.0
var sm_wheelie := 0.0   # the slope the body levels against, rate-limited
const PITCH_LEVEL_RATE := 2.5   # rad/s
var _fy_prev := NAN; var _fv_prev := NAN; var _facc := 0.0   # the frame's height / speed / acceleration (bump bounce)
var bounce_stats := [0.0, 0, 0.0, 0.0]   # tests: sum of squared body offsets, samples, biggest offset
func update_pose(dt: float, p: Dictionary) -> void:
	var v := _num(p, "v")
	_probe_pitch = _num(p, "pitch")
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
	# hip sway / bob from pedalling: big when pushing off slowly, nearly still when spinning at speed
	var hi_fade: float = 1.0 - 0.85 * smoothstep(5.0, 12.0, absf(v))
	# effort: sprinting from slow the rider throws everything into it - up off the saddle, over the bars,
	# hips swinging, body bobbing hard with every stroke (fades out once up to speed)
	var effort: float = spr * pedal * BikePhysics.slowness(v) * float(Tune.v.get("sprintEffort", 1.0))   # the slower, the harder they fight
	sm_effort += (effort - sm_effort) * (1.0 - exp(-6.0 * minf(dt, 0.1)))
	var eff: float = sm_effort
	var sway: float = sin(crank) * pedal * sty.sway * (1 + 0.9 * spr + 1.3 * eff) * hi_fade
	# (Body bob: how far the body rises and drops with each pedal stroke)
	var bob: float = sin(crank * 2) * pedal * sty.sway * float(sty.get("bodyBob", 1.0)) * (1 + 0.6 * spr + 1.0 * eff) * lerpf(0.4, 1.0, hi_fade)
	var wig: float = clampf(1 - absf(v) / 3, 0, 1) * sty.sway * float(sty.slowWobble)
	var air := _num(p, "air")
	var comp: float = _num(p, "compress") * sty.crouch
	# speed tuck: from ~25 km/h the rider folds down over the bars for less drag (full by ~60 km/h):
	# chest flatter and lower, hips back and down, elbows bend (the arm reach check pulls them in).
	# Less while pedalling hard, none in the air (the jump / trick poses own that).
	# the tuck is the player's: the right stick pushed forward folds the rider down over the bars (full
	# stick = the old full speed tuck). Neutral is an upright attack position; nothing tucks on its own
	var bstick := clampf(_num(p, "bodyStick"), -1.0, 1.0)
	var aero_t: float = clampf(bstick, 0.0, 1.0) * float(sty.get("aero", 1.0))
	sm_aero += (aero_t - sm_aero) * (1.0 - exp(-(3.0 + 12.0 * air) * minf(dt, 0.1)))   # off the ground the tuck goes at once
	var aero: float = sm_aero
	# on the ground forward = fold down over the bars (chest low, hips back a little, knees bent: a race
	# tuck); in the air forward = legs extend and push the bike away (the hips rise). Before, the ground
	# lean also lifted the hips and threw them forward, so the torso came UP instead of down
	var aero_g: float = aero * (1.0 - air)
	var aero_a: float = aero * air

	# attack position: rolling, a downhill rider stands off the saddle (knees and elbows soft, ready),
	# not only while pedalling
	var stand: float = maxf(pedal, clampf(0.85 * float(sty.attackStand), 0.0, 1.3) * smoothstep(1.5, 5.0, absf(v)) * (1.0 - air))

	# pelvis
	var pelvis := Vector3(
		-0.16 - 0.07 * air * float(sty.airCrouch) + 0.06 * pedal * sty.standPedal - float(sty.standBack) * stand - comp * 0.25,
		0.80 - 0.07 * air * float(sty.airCrouch) - comp + (float(sty.standHeight) * stand + 0.05 * spr) * sty.standPedal + 0.035 * bob + 0.14 * aero_a - 0.07 * aero_g,   # (forward: in the air legs extend; on the ground knees bend into the tuck)
		sway * sty.hipSway + shift * 0.3 + sin(t * 2.1) * 0.02 * wig) + fit
	pelvis.x += sty.hipX * (1 - 0.5 * pedal) + 0.10 * aero_a - 0.05 * aero_g + 0.07 * eff   # forward over the cranks (air stick: hips forward; ground tuck: a touch back)
	pelvis.y += 0.04 * eff                                                   # up tall to stamp down
	pelvis.y += sty.hipY * (1 - 0.6 * pedal)
	pelvis.y -= 0.05 * smoothstep(0.8, 3.5, absf(_num(p, "airSpin"))) * air   # knees tucked up in a spin
	pelvis.y += 0.07 * air * float(sty.airCrouch) * aero   # forward in the air: no crouch, legs pushed out

	# chest
	# (pedalling out of the saddle the chest stays forward over the bars)
	var ang: float = 0.52 - 0.2 * clampf(-bstick, 0.0, 1.0) - float(sty.pedalChest) * pedal + 0.12 * spr + 0.2 * eff + 0.15 * (comp / 0.3) + 0.08 * air + sty.lean * (1 - 0.5 * pedal) + 0.32 * aero_a + 0.6 * aero_g
	# spinning in the air: tall and compact over the bike (chest up, knees in), the head and shoulders lead
	var spin_style: float = smoothstep(0.8, 3.5, absf(_num(p, "airSpin"))) * air
	ang = lerpf(ang, 0.42, 0.7 * spin_style)
	# relaxed (garage showcase, `relax` 0..1): sat up tall, back straighter, chin up - whatever the saved riding pose
	var relax := clampf(_num(p, "relax"), 0.0, 1.0)
	ang = lerpf(ang, 0.22, 0.8 * relax)
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
	# (the physics' forward weight shift is carried by the chest going out over the bars in a ground tuck,
	# not by the hips sliding up to the stem)
	pelvis.x += hs * (1.0 - 0.7 * aero_g if hs > 0.0 else 1.0)
	chest.x += hs * 0.6
	# body stick (gamepad right stick): forward = chest low over the bars, back = hips dropped behind the
	# saddle with the arms long (manuals)
	var bs := clampf(_num(p, "bodyStick"), -1.0, 1.0)
	var back_k := clampf(-bs, 0.0, 1.0)
	chest.x -= 0.06 * back_k   # back: the chest stays over the hips, arms long
	# side (stick left / right, or the stick's lean in the air): the bike tips under the rider, the hips go to
	# the outside of it and the upper body stays up over the bike's contact line
	var lat := clampf(_num(p, "bodyLat"), -1.0, 1.0)
	pelvis.z += 0.07 * lat * (1.0 - 0.6 * air)
	chest.z += 0.035 * lat
	# a tabletop in the air: knees bend deep and the hips drop so both feet stay on the pedals of the
	# laid-over bike
	pelvis.y -= 0.12 * absf(lat) * air
	if bs < 0.0:
		pelvis += Vector3(0.04, 0.09, 0.0) * bs   # (bs < 0: back + down)
		chest += Vector3(0.0, 0.03, 0.0) * bs
	# keep the body level while the bike pitches (descents: almost fully; climbs: a little)
	# only for slope-like angles: mid-flip (nose far up / down, upside down) the body stays on the bike
	var pitch0 := wrapf(_num(p, "pitch"), -PI, PI)
	pitch0 *= 1.0 - smoothstep(0.7, 1.3, absf(pitch0))
	# that fade swings the body back ~2x the bike's own pitch rate as a flip passes through it, yanking
	# the shoulders / hips 10-20 cm a frame (the limbs flail): the body follows it at a limited rate
	var h0 := minf(dt, 0.1)
	if not spring_init: sm_pitch0 = pitch0
	var dp0 := (pitch0 - sm_pitch0) * (1.0 - exp(-12.0 * h0))
	sm_pitch0 += clampf(dp0, -PITCH_LEVEL_RATE * h0, PITCH_LEVEL_RATE * h0)
	pitch0 = sm_pitch0
	# the ground slope vs the bike's own nose-up: a wheelie / manual (front up on the ground) is not a
	# climb. Climbing, the rider leans forward over the bars; in a wheelie the bars come up at them, so
	# they sit back with long arms and stay fairly upright (leaning into the bars crushed the arms and
	# threw the elbows up). The garage has no slope: all of the pitch counts as slope there.
	var slope0: float = clampf(_num(p, "slope", pitch0), -1.3, 1.3) if p.has("slope") else pitch0
	# (raw bike pitch vs raw slope: the smoothed pitch0 lags a slope that changes fast in a hard turn and gave
	# false "wheelies" that shoved the body about) - and the result eases in / out
	var raw_p := wrapf(_num(p, "pitch"), -PI, PI)
	var wh_t: float = clampf(raw_p - slope0, 0.0, 1.1) * (1.0 - clampf(air * 3.0, 0.0, 1.0)) if p.has("slope") else 0.0
	if wh_t < 0.08: wh_t = 0.0   # small pitch noise is not a wheelie
	sm_wheelie = move_toward(sm_wheelie, wh_t, 2.5 * minf(dt, 0.1))
	var wheelie: float = sm_wheelie
	var base := pitch0 - wheelie   # the slope part of the bike's pitch
	var pit := base * (0.2 if base > 0 else _num(p, "bodyLevel", 0.85)) + wheelie * 0.75   # most of a wheelie's tilt is taken back
	# in the air, when the rider tilts the bike with the stick, the body stays and the bike rotates under
	# it: nose down = arms push the bars away, hips back; nose up = bars pulled into the chest
	var at := _num(p, "airTilt")
	if at != 0.0:
		pit += at
		pelvis.x -= clampf(-at, 0.0, 0.6) * 0.12
		chest.y -= absf(at) * 0.05
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
		var down := maxf(0.0, -base)
		var drop := _num(p, "attackDrop", 0.18)
		pelvis.y -= down * drop
		pelvis.x -= down * drop * 0.45
	# climbing: hips to the saddle nose, chest low over the bars
	var climb := clampf(slope0, 0, 0.6)
	if wheelie > 0.0:   # hips back and a little down behind the saddle, chest back over them, arms long
		pelvis.x -= 0.15 * wheelie
		pelvis.y -= 0.06 * wheelie
		chest.x -= 0.27 * wheelie
		chest.y -= 0.03 * wheelie
	if climb > 0:
		pelvis.x += climb * 0.22
		pelvis.y -= climb * 0.04
		chest.x += climb * 0.42
		chest.y -= climb * 0.24
	# lean the BIKE, not the body: roll the body back toward upright about the pedals
	var cr := clampf(_num(p, "counter"), -0.85, 0.85)   # past ~50 deg the hips swing off the bike and the legs cross the frame
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
		pelvis.y -= absf(cr) * 0.12 * float(sty.turnLow)
		# in the air a stick lean: the hips move out against the bike (the legs push it over)
		chest.x += absf(cr) * 0.05
	# foot down at a stop: the bike leans onto the foot, the body stays nearly upright over it,
	# hips a little lower and toward the foot (standing over the top tube)
	var dab := clampf(_num(p, "dab"), 0, 1)
	if dab > 0.0:
		var ds := signf(_num(p, "dabSide", -1.0))
		var a := -ds * _num(p, "dabLean") * 0.8 * dab
		var c := cos(a)
		var sn := sin(a)
		var y0 := 0.3
		var dy := pelvis.y - y0
		var dz := pelvis.z
		pelvis.y = y0 + dy * c - dz * sn
		pelvis.z = dy * sn + dz * c
		dy = chest.y - y0
		dz = chest.z
		chest.y = y0 + dy * c - dz * sn
		chest.z = dy * sn + dz * c
		pelvis.z += ds * 0.04 * dab
		pelvis.y -= 0.05 * dab
		chest.y -= 0.03 * dab
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
	# the body is a mass on springy legs and arms: when the bike is kicked up by a bump (or drops) the body
	# lags behind and then springs back, so the knees and elbows soak it up. The frame's up / down
	# acceleration pushes the body the other way (Bump bounce); Body bounce sets how long it rings on
	var bump_k: float = float(sty.get("bumpAbsorb", 2.0)) * (1.0 - air)
	# what the legs feel: half the frame's motion, half the wheels' (the bumps the suspension passes on)
	var gy := (global_position.y if is_inside_tree() else 0.0) * 0.5 + _num(p, "wheelY") * 0.5
	var acc := 0.0
	if not is_nan(_fy_prev) and absf(gy - _fy_prev) > 1.0:
		_fy_prev = NAN; _fv_prev = NAN   # teleports (respawn, a new ride) are not bumps
	if h > 1e-4 and not is_nan(_fy_prev):
		var vy_f := (gy - _fy_prev) / h
		if not is_nan(_fv_prev):
			acc = clampf((vy_f - _fv_prev) / h, -80.0, 80.0)
		_fv_prev = vy_f
	_fy_prev = gy
	_facc += (acc - _facc) * (1.0 - exp(-40.0 * h))   # a touch of smoothing (frame-time jitter)
	var zeta: float = clampf(float(sty.get("bodyBounce", 0.4)), 0.15, 1.0)
	var dp := 2 * sqrt(260.0) * zeta
	pel_v += ((pelvis - pel_s) * 260.0 - pel_v * dp) * h
	# up / down the legs are a softer spring (~1.5 Hz): the body rides bumps and rebounds
	var ky: float = clampf(float(sty.hipSteady), 20.0, 600.0)   # Hips steady: how stiffly the legs hold the hips
	pel_v.y += ((pelvis.y - pel_s.y) * (ky - 260.0) - pel_v.y * 2.0 * (sqrt(ky) - sqrt(260.0)) * zeta) * h
	pel_v.y -= _facc * bump_k * h
	pel_s += pel_v * h
	# the legs only bend / straighten so far
	pel_s.y = clampf(pel_s.y, pelvis.y - 0.14, pelvis.y + 0.05)
	if air < 0.5:   # tests (BMX_CLIP_PROBE): how far the body moves on its legs while riding
		bounce_stats[0] += (pel_s.y - pelvis.y) * (pel_s.y - pelvis.y); bounce_stats[1] += 1
		bounce_stats[2] = maxf(bounce_stats[2], absf(pel_s.y - pelvis.y)); bounce_stats[3] += _facc * _facc
	pelvis = pel_s
	var dc := 2 * sqrt(200.0) * zeta
	ch_v += ((chest - ch_s) * 200.0 - ch_v * dc) * h
	ch_v.y += ((chest.y - ch_s.y) * (ky - 200.0) - ch_v.y * 2.0 * (sqrt(ky) - sqrt(200.0)) * zeta) * h
	ch_v.y -= _facc * bump_k * 0.85 * h
	ch_s += ch_v * h
	ch_s.y = clampf(ch_s.y, chest.y - 0.14, chest.y + 0.06)
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
		# Arm bend: how far the arms may straighten (more bend = chest closer to the bars)
		var reach := (L_UARM + L_FARM) * clampf(0.9 - 0.2 * float(sty.armBend), 0.55, 0.98)
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

	# ---- safety limits. Whatever stacks up (tuck + spin + counter-lean + landing + style sliders), the
	# skeleton stays humanly possible: hips in a box over the bike, the torso bends only so far from the
	# bike's up (back / forward, sideways) and never folds below the hips
	pelvis.x = clampf(pelvis.x, -0.6, 0.22)
	pelvis.y = clampf(pelvis.y, 0.42, 1.08)
	pelvis.z = clampf(pelvis.z, -0.22, 0.22)
	# never INTO the rear wheel (they may go below the saddle, beside it): the hips keep out of the wheel's
	# circle by the thigh / seat thickness. The legs used to go into the wheel when air crouch + landing
	# absorb + the bike lifted into the body all stacked up
	var wr = p.get("wheelR")
	if wr is Vector3:
		var clear_r: float = _num(p, "wheelRR", 0.36) + 0.16
		var d2 := Vector2(pelvis.x - wr.x, pelvis.y - wr.y)
		if d2.length() < clear_r:
			var out := (d2.normalized() if d2.length() > 1e-3 else Vector2.UP) * clear_r - d2
			out.x = minf(out.x, 0.0) if d2.x < 0.0 else out.x   # pushed up / out, never forward through it
			pelvis.x += out.x; pelvis.y += out.y
			chest.x += out.x; chest.y += out.y   # the whole body comes up, not just the hips
	var tv0 := chest - pelvis
	var tl0 := maxf(tv0.length(), 1e-4)
	# forward lean from upright. A chest at or below the hips counts as folded FORWARD whichever side of the
	# hips it is (atan2 there flips between +-180 deg as it crosses over: the torso snapped back and forth)
	var f_ang := 1.4 if tv0.y < 0.05 else clampf(atan2(tv0.x, tv0.y), -0.45, 1.4)
	var s_ang := clampf(asin(clampf(tv0.z / tl0, -1.0, 1.0)), -0.6, 0.6)   # sideways
	chest = pelvis + Vector3(sin(f_ang) * cos(s_ang), cos(f_ang) * cos(s_ang), sin(s_ang)) * tl0
	# the torso never stretches or squashes: past its length range the hips follow the chest
	var tv := chest - pelvis
	var tl := tv.length()
	var t_max: float = sty.torso * 1.08
	var t_min: float = sty.torso * 0.75
	torso_ratio = tl / maxf(float(sty.torso), 1e-4)
	if tl > t_max:
		pelvis = chest - tv / tl * t_max
	elif tl < t_min and tl > 1e-4:
		chest = pelvis + tv / tl * t_min
	# torso from pelvis to chest
	var hip := Vector3(pelvis.x, pelvis.y + 0.02, pelvis.z)
	var tw_axis := (chest - hip).normalized()
	# spinning in the air: shoulders lead the bike round (the head turns via yawRate below)
	# turning on the ground: shoulders and hips steer into the turn, the inside hip drops
	var turn := clampf(_num(p, "turn"), -3.0, 3.0)
	sm_turn += (turn - sm_turn) * (1.0 - exp(-8.0 * minf(dt, 0.1)))
	# a side lean in the air (tabletop): the hips turn with the bike, the shoulders turn back against it
	var tab: float = clampf(_num(p, "bodyLat"), -1.0, 1.0) * air
	var tw := Basis(tw_axis, float(sty.twist) + clampf(_num(p, "airSpin") * 0.07 + sm_turn * 0.13 * float(sty.turnTwist), -0.5, 0.5) - 0.22 * tab)
	# pelvis: turn (yaw about up), roll (one hip drops, about forward), tilt (about the hip line)
	var pel_b := Basis(Vector3.UP, float(sty.pelvisYaw) + clampf(sm_turn * 0.07 * float(sty.turnHips), -0.4, 0.4) + 0.3 * tab) * Basis(Vector3.RIGHT, float(sty.pelvisRoll) - clampf(sm_turn * 0.04 * float(sty.turnHips), -0.25, 0.25))
	set_spine(hip, chest, pel_b * Vector3(0, 0, 1), tw * Vector3(0, 0, 1),
		float(sty.spineCurve) * (1.0 - 0.7 * relax), float(sty.spineSide), float(sty.spineLow))
	pelvis_mesh.transform = Transform3D(pel_b * Basis(Vector3.BACK, -(ang * 0.3) - float(sty.pelvisTilt)), pelvis)
	set_limb(hood_hem, Vector3(pelvis.x, pelvis.y + 0.04, pelvis.z), hip.lerp(chest, 0.2))

	# neck / head
	var neck := chest
	hood.position = Vector3(neck.x - 0.03, neck.y, neck.z)
	var head_p := Vector3(neck.x + 0.05 + sty.lookAhead + 0.04 * aero, neck.y + 0.2 + sty.neck, neck.z)   # (forward: chin over the bars)
	J[0] = head_p
	J[1] = chest
	J[2] = pelvis
	var yaw: float = clampf((_num(p, "steer") * 1.2 + _num(p, "yawRate") * 0.15) * sty.headTurn, -0.8, 0.8) + sty.headYaw
	var rx: float = (_num(p, "headRoll") if p.get("headRoll") != null else _num(p, "lean") * 0.6) + sty.headRoll
	var rz: float = -0.12 * (ang - 0.72) + 0.04 * sin(t * 3.3) * wig - sty.headTilt * (1.0 - 0.6 * relax)
	head.transform = Transform3D(GEAR.euler_xyz(rx, yaw, rz), head_p)

	var right := Vector3(0, 0, 1)
	var max_turn := BEND_RATE * minf(dt, 0.1) if dt > 0.0 else PI
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var foot: Vector3 = p.get("footL" if i == 0 else "footR", Vector3.ZERO)
		var hand: Vector3 = p.get("handL" if i == 0 else "handR", Vector3.ZERO)
		# leg
		var hp: Vector3 = pelvis + pel_b * Vector3(0, -0.02, side * (0.11 + sty.stance))
		var ankle := Vector3(foot.x - 0.04 + sty.heelFwd, foot.y + 0.12 + sty.heelUp, foot.z)
		# turning: the inside knee opens out toward the turn, the outside leg drives down on its pedal
		var inside: float = clampf(-side * _num(p, "lean") * 1.6, 0.0, 0.9) * float(sty.kneeOpen) * (1.0 - air)
		var pole_l: Vector3 = (poles_leg[i] + Vector3(0, 0, side * inside)).normalized()
		var ik := limb_ik(hp, ankle, L_THIGH, L_SHIN, pole_l, Vector3.UP, KNEE_MIN, KNEE_MAX, _bd_prev[i], max_turn)
		_bd_prev[i] = ik[2]
		var ik_raw: Vector3 = ik[0]
		ik[0] = _knee_clear(hp, ankle, ik[0], side)
		if knee_dbg.size() < 40 and OS.get_environment("BMX_KNEE_PROBE") != "" and knee[i].position.distance_to(ik[0]) > 0.08:
			knee_dbg.append([i, snappedf(_num(p, "pitch"), 0.01), knee[i].position.snapped(Vector3.ONE * 0.01), hp.snapped(Vector3.ONE * 0.01), ankle.snapped(Vector3.ONE * 0.01), ik_raw.snapped(Vector3.ONE * 0.01), (ik[0] as Vector3).snapped(Vector3.ONE * 0.01)])
		set_limb(thigh[i], hp, ik[0])
		set_limb(shin[i], ik[0], ik[1])
		knee[i].position = ik[0]
		# out of reach: the foot stays at the end of the leg (limbs never stretch)
		foot += ik[1] - ankle
		shoe[i].position = Vector3(foot.x, foot.y + 0.03, foot.z)
		shoe[i].basis = Basis(Vector3.UP, -side * float(sty.footOut)) * Basis(Vector3.BACK, float(sty.footAngle))
		J[9 + i * 3] = hp
		J[10 + i * 3] = ik[0]
		J[11 + i * 3] = Vector3(foot.x, foot.y + 0.08, foot.z)
		# arm
		var sh_off := Vector3(-0.03 + sty.shoulderFwd, -0.04 + sty.shoulderUp, side * sty.shoulders)
		var shp: Vector3 = chest + tw * sh_off
		shoulder_sph[i].position = shp
		# hand nearly on the elbow's pole line (deep turns, arms up in the air): elbow out and down
		var pole_a: Vector3 = poles_arm[i]
		if aero > 0.01: pole_a = pole_a.lerp(Vector3(-0.15, 0.15, side * 1.0).normalized(), 0.7 * aero).normalized()   # elbows up and out
		if back_k > 0.01: pole_a = pole_a.lerp(Vector3(-0.35, -0.85, side * 0.3).normalized(), 0.5 * back_k).normalized()
		var ika := limb_ik(shp, hand, L_UARM, L_FARM, pole_a, Vector3(0, -0.5, side), ELBOW_MIN, ELBOW_MAX, _bd_prev[2 + i], max_turn)
		_bd_prev[2 + i] = ika[2]
		set_limb(upper_arm[i], shp, ika[0])
		set_limb(fore_arm[i], ika[0], ika[1])
		elbow[i].position = ika[0]
		hand = ika[1]   # out of reach: the hand stays at the end of the arm
		glove[i].position = hand
		orient_hand(glove[i], ika[0], hand, right)
		if sty.wristRoll != 0.0:
			glove[i].rotate_object_local(Vector3.RIGHT, side * float(sty.wristRoll))
		J[3 + i * 3] = shp
		J[4 + i * 3] = ika[0]
		J[5 + i * 3] = hand
		if limb_probe:
			_probe_limb("elbow%d" % i, shp, ika[0], hand, dt, air)
			_probe_limb("knee%d" % i, hp, ik[0], ik[1], dt, air)
