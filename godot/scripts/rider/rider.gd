class_name Rider
extends Node3D
## Port of src/rider.js: the low-poly cartoon rider, posed procedurally every frame.
## This node is the JS rider.group: parent it under the bike's lean node. Local frame: +X forward,
## +Y up, +Z the rider's right; the bottom bracket sits near the origin (0.297 up on the BMX).

const G := preload("res://scripts/rider/rider_geo.gd")
static var _OLD_JUMPPOSE := OS.get_environment("BMX_OLD_JUMPPOSE") != ""
static var _OLD_SPEEDTUCK := OS.get_environment("BMX_OLD_SPEEDTUCK") != ""
const GEAR := preload("res://scripts/rider/rider_gear.gd")

## neutral riding style (posepanel.js NEUTRAL): BMX = all of these
const NEUTRAL := {hipX = 0.0, hipY = 0.0, lean = 0.0, elbowsOut = 0.0, kneesOut = 0.0, stance = 0.0, seatFloor = false,
	crouch = 1.0, standPedal = 1.0, aero = 1.0, speedTuckPose = 1.0, sway = 1.0, bikeRock = 1.0, upright = 1.0, hipSway = 0.015, torso = 0.46, attackStand = 1.0, kneeOpen = 1.0, bumpAbsorb = 2.0, bodyBounce = 0.4, leanFollow = 1.0, leanSwing = 1.0, leanUnweight = 1.0, leanLively = 1.0, leanBalance = 1.0, leanBumps = 1.0, leanLoad = 1.0, bodyBob = 1.0,
	flowBend = 1.0, flowLead = 1.0, flowSink = 1.0,   # pro flow through lean changes: spine bend, shoulders / eyes lead, sink into the turn
	headSteady = 1.0, ankling = 1.0, heelsDown = 1.0,   # head held steady against the bike's kicks; ankle swing pedalling; heels drop coasting / landing
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
	kneesFwd = 0.0, kneeOutL = 0.0, kneeOutR = 0.0, heelFwd = 0.0, heelUp = 0.0, footAngle = 0.0, footOut = 0.0, footSlide = 0.025}
## lookpanel.js DEFAULT_LOOK
const DEFAULT_LOOK := {shell = "#16171a", peak = "#ececec", goggleFrame = "#f2f2ee", lens = "#ff7a2a", strap = "#ff6a4d",
	jersey = "#ff6a4d", pants = "#1d2b64", pantsFabric = "denim", pantsPattern = "none", pantsPrint = "#ff7a1a", gloves = "#ffd21f", shoes = "#26292f", shoeAccent = "#d8232a", pads = "#1b1c20", padStyle = "enduro",
	beltStyle = "webbing", belt = "#16171a", buckle = "#9aa0a8", helmet = "glory",
	helmetOn = "1", hairStyle = "long", beard = "1", hair = "#4a3022", skin = "#efc29f", eyes = "#4a6b8a", bibOn = "1", bibNumber = "27", bibText = "RUNOUT  •  DOWNHILL CUP",
	camMount = "top", camModel = "hero", camLens = "stock", camHousing = "none", camMic = "none", camAcc = "none"}
## where the helmet model sits on the head (head-local m / rad) and its scale
## helmet models picked in the Look tab (look.helmet): id -> [label, glb]. The glory one is the stock helmet (recolourable
## shell / peak, our goggles); the others are textured models (tools/export_helmets.py) that always wear their own goggles
## + strap (the glb's "helmet_goggles" node: our goggles don't fit them)
const HELMETS := {
	"glory": ["RUNOUT", "res://assets/helmet.glb"],
	"6d_black": ["HEX6 AT-2 black", "res://assets/helmets/helmet_6d_black.glb"],
	"6d_silver": ["HEX6 AT-2 silver", "res://assets/helmets/helmet_6d_silver.glb"],
	"tld": ["TOPLINE S5", "res://assets/helmets/helmet_tld.glb"],
}
## per helmet model: where it sits on the head, on top of HELMET_FIT (same keys)
const HELMET_FITS := {
	"6d_black": {x = -0.005, y = -0.02, tilt = 0.0, scale = 1.12},
	"6d_silver": {x = -0.005, y = -0.02, tilt = 0.0, scale = 1.12},
	"tld": {x = -0.005, y = -0.02, tilt = 0.0, scale = 1.12},
}
const HELMET_FIT := {x = 0.01, y = 0.0, tilt = 0.0, scale = 1.3}
## goggles (RiderGear.build_goggles): lens position / tilt / size, strap ellipse round the shell
const SKI_GOGGLE_MESH := "res://assets/goggles/ski_goggle.obj"

## the ski goggle model's material: its own textures (albedo with the lens alpha baked in, normal, roughness,
## metal, AO); the lens is see-through where the alpha says so
static func ski_goggle_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "ski_goggle"
	m.albedo_texture = load("res://assets/goggles/ski_goggle_albedo.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.normal_enabled = true
	m.normal_texture = load("res://assets/goggles/ski_goggle_normal.png")
	m.roughness_texture = load("res://assets/goggles/ski_goggle_rough.png")
	m.roughness = 1.0
	m.metallic_texture = load("res://assets/goggles/ski_goggle_metal.png")
	m.metallic = 1.0
	m.ao_enabled = true
	m.ao_texture = load("res://assets/goggles/ski_goggle_ao.png")
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

const GOGGLE_FIT := {x = 0.15, y = 0.025, tilt = 0.25, w = 0.23, h = 0.087, R = 0.12, strap = {cx = 0.01, ra = 0.236, rc = 0.162}}

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
var helmet_id := ""   # which HELMETS entry + goggle source is on, "id/mode" (set by use_helmet)
var goggles: Node3D = null
var action_cam: Node3D = null   # the helmet action camera (ActionCam); its "Lens" is the Helmet camera view (null = look.camMount "none")
var action_cam_at := Vector3.ZERO   # where it's mounted (head space)
var _cam_tpl: Node3D = null   # a built copy of the action cam, never in the tree (remounts duplicate it)
var _cam_tpl_key := ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _cam_tpl != null and is_instance_valid(_cam_tpl):
		_cam_tpl.free()
var cam_mount := ""                 # which ActionCam.HELMET_MOUNTS entry is on
var cam_gear := ""                  # ActionCam.gear_sig of the camera + add-ons on it (look.camModel ...)
var cam_spots := {}                 # mount kind -> where it touches the shell (head space), set when a helmet goes on

var torso: MeshInstance3D
var belt_node: Belt
var pelvis_mesh: MeshInstance3D
var neck_mesh: MeshInstance3D
var bib_node: BackNumber
var face_root: Node3D       # the bare head: skin, eyes, brows, nose, mouth, ears (under the helmet when it is on)
var scalp: MeshInstance3D   # hair-coloured cap over the top / back of the head
var hair: Hair              # long hair, shown instead of the helmet
var skin_mat: StandardMaterial3D
var hair_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var helmet_fill: MeshInstance3D
var hair_tail := false   # helmet on + long / bob hair: the tuft at the back is shown
var scalp_mat: StandardMaterial3D
var neck_mat0: Material
var shoulder_sph: Array[MeshInstance3D] = []
var thigh: Array[MeshInstance3D] = []
var shin: Array[MeshInstance3D] = []
var knee: Array[MeshInstance3D] = []   # joint markers (hidden under the knee pads)
var knee_pad: Array[KneePad] = []
var shoe: Array[Node3D] = []
var upper_arm: Array[MeshInstance3D] = []
var fore_arm: Array[MeshInstance3D] = []
var elbow: Array[MeshInstance3D] = []
var glove: Array[Node3D] = []
var head: Node3D
var hel: Node3D
var skeleton: RiderSkeleton   # Godot humanoid bones that follow the drawn rider (rider_skeleton.gd)

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
	if metal < 0.5 and roughness >= 0.65:
		m.metallic_specular = 0.18   # cloth / rubber / foam: matte, the sky + reflection probe must not make it shine
		m.roughness = maxf(roughness, 0.9)
	return m


func _init() -> void:
	name = "Rider"
	var mCoral := mat("#ff6a4d", 0.8)
	var mCoralDark := mat("#e04e34", 0.8)
	var mNavy := PantsLook.make()        # fabric + printed pattern (rider/pants_look.gd), coloured by set_look
	var mNavyLight := PantsLook.make()   # the knee (a shade lighter), shown when there are no pads
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
	pelvis_mesh = G.inst(G.rounded_box(0.2, 0.15, 0.3, 3, 0.05), mNavy)
	pelvis_mesh.name = "Pelvis"
	add_child(pelvis_mesh)
	# a belt round the waist (style + colours in the look): hides where the jersey's hem meets the trouser top.
	# Its shape follows the hips' rounded box (a superellipse just outside it), so no corner pokes through
	belt_node = Belt.new()
	pelvis_mesh.add_child(belt_node)
	belt_node.set_look(DEFAULT_LOOK.beltStyle, Color(DEFAULT_LOOK.belt), Color(DEFAULT_LOOK.buckle))
	var bib := BackNumber.new()   # race number paper pinned to the back, flaps with speed
	bib.name = "BackNumber"
	bib_node = bib
	add_child(bib)
	# the neck: a tapered tube (jersey collar colour) from inside the collar up into the helmet, posed
	# every frame by _pose_neck (both ends are hidden, so it never shows a cap)
	neck_mesh = cyl.call(NECK_R_TOP, NECK_R_BASE, mCoralDark, 18)
	neck_mesh.name = "Neck"
	shoulder_sph.assign([sph.call(0.075, mCoral), sph.call(0.075, mCoral)])

	# legs (0 = left, 1 = right)
	thigh.assign([cyl.call(0.075, 0.062, mNavy), cyl.call(0.075, 0.062, mNavy)])
	shin.assign([cyl.call(0.062, 0.05, mNavy), cyl.call(0.062, 0.05, mNavy)])
	knee.assign([sph.call(0.07, mNavyLight), sph.call(0.07, mNavyLight)])
	for i in 2:   # downhill knee pads over the knees (articulated: cap on the bend, plates on thigh + shin)
		knee[i].visible = false
		var kp := KneePad.new(-1.0 if i == 0 else 1.0)   # 0 = left leg: its outside is -Z
		add_child(kp)
		knee_pad.append(kp)
	shoe_mats = {upper = mat("#26292f"), accent = mat("#d8232a"), sole = mat("#111214", 0.95), mid = mat("#f2f2ee"), laces = mat("#f2f2ee")}
	for k in ["upper", "accent"]:   # the upper is an open shell (heel / toe fans): draw both faces so nothing shows through from behind
		(shoe_mats[k] as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
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
	# the goggles themselves from the user's ski-goggle model (frame, foam, mirrored lens; its strap cut off - ours
	# goes round the helmet); without the files, the built ones
	if ResourceLoader.exists(SKI_GOGGLE_MESH):
		goggle_mats.model_mesh = load(SKI_GOGGLE_MESH)
		goggle_mats.model_mat = ski_goggle_material()
	var baker := StrapLogo.new()
	baker.mat = logo
	baker.text = "COLOSSUS"
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
	_build_face()
	_build_builtin_helmet()

	set_style({})
	J.resize(15)
	J.fill(Vector3.ZERO)
	# the humanoid skeleton (Godot's profile names): follows the parts every frame, for attachments / animation
	skeleton = RiderSkeleton.new()
	add_child(skeleton)
	skeleton.make_fingers(hand_mats.glove)   # the gloves' fingers ride on its finger bones (GloveFingers)


## the bare head and the hair that replaces the helmet (look.helmetOn = "0"). A friendly, slightly cartoon face:
## big bright eyes with a highlight, soft brows, a small nose, a gentle smile and a touch of blush.
func _build_face() -> void:
	skin_mat = mat("#efc29f", 0.7)
	hair_mat = mat("#4a3022", 0.45)
	eye_mat = mat("#4a6b8a", 0.25)
	scalp_mat = mat("#4a3022", 0.5)
	scalp_mat.vertex_color_use_as_albedo = true
	scalp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scalp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	face_root = Node3D.new()
	face_root.name = "Face"
	head.add_child(face_root)
	helmet_fill = MeshInstance3D.new()
	var hf := SphereMesh.new()
	hf.radius = 0.1; hf.height = 0.2; hf.radial_segments = 16; hf.rings = 10
	helmet_fill.mesh = hf
	helmet_fill.material_override = mat("#15181d", 0.9)
	helmet_fill.transform = Transform3D(Basis.from_scale(Vector3(1, 1.2, 0.95)), Vector3(0, -0.01, 0))
	helmet_fill.visible = false
	head.add_child(helmet_fill)
	scalp = MeshInstance3D.new()
	scalp.mesh = Hair.scalp_mesh()
	scalp.material_override = scalp_mat
	scalp.visible = false
	face_root.add_child(scalp)
	hair = Hair.new()
	hair.name = "Hair"
	hair.head = head
	hair.rider = self
	hair.visible = false
	add_child(hair)



## helmet on: the shell, goggles and action camera; off: the bare head with long hair
func _apply_head_gear(on: bool) -> void:
	if hel: hel.visible = on
	if helmet_model: helmet_model.visible = on
	if goggles: goggles.visible = on
	if action_cam: action_cam.visible = on
	if scalp: scalp.visible = not on
	if face_root: face_root.visible = not on          # helmet on: the head (and its beard) is hidden inside it
	if helmet_fill: helmet_fill.visible = on          # a dark inside, so the opening is not see-through
	if hair: hair.visible = (not on) or hair_tail     # long hair: a tuft still comes out under the back of the helmet
	if neck_mesh:
		if neck_mat0 == null: neck_mat0 = neck_mesh.material_override
		neck_mesh.material_override = neck_mat0 if on else skin_mat
		neck_mesh.visible = true


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
	cam_spots = {top = Vector3(0.03, hel.position.y + R * 0.96 - 0.004, 0),
		side = hel.position + Vector3(0.0, R * 0.28, -R * 0.9 * 0.97),
		chin = Vector3(R * 1.14 + 0.035, -0.064, 0)}
	_mount_action_cam()


## the action camera where look.camMount says (top = just forward of the crown, side = left of the shell,
## chin = front of the chin bar, none = no camera), at the spot the helmet measured (cam_spots, head space)
func _mount_action_cam() -> void:
	if action_cam and is_instance_valid(action_cam):
		action_cam.get_parent().remove_child(action_cam)
		action_cam.queue_free()
	action_cam = null
	cam_mount = str(look.get("camMount", DEFAULT_LOOK.camMount))
	var gear := ActionCam.gear_from_look(look)
	cam_gear = ActionCam.gear_sig(gear)
	if cam_mount == "none" or not cam_spots.has(cam_mount):
		return
	var at: Vector3 = cam_spots[cam_mount]
	# (2026-11-24, frame profiler: building + merging it took ~90 ms on every get-up after a crash) a built copy of this
	# mount + gear is kept off the tree; a remount duplicates it (the meshes are shared: a few nodes, well under 1 ms)
	var key := "%s|%s" % [cam_mount, cam_gear]
	if _cam_tpl == null or _cam_tpl_key != key or Env.s("BMX_CAM_NOCACHE") != "":
		if _cam_tpl != null: _cam_tpl.free()
		_cam_tpl = ActionCam.merged(ActionCam.build(cam_mount, gear))   # one mesh for the mount, one for the camera
		_cam_tpl_key = key
	action_cam = _cam_tpl.duplicate()
	action_cam.position = at
	action_cam_at = at
	action_cam.visible = hel == null or hel.visible or (helmet_model != null and helmet_model.visible)
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
	_mount_action_cam()


## highest point of the shell near (x, z=0), head space (the action cam sits there)
static func _shell_top(tris: PackedVector3Array, x: float) -> float:
	var best := -1e9
	for p in tris:
		if absf(p.z) < 0.03 and absf(p.x - x) < 0.03 and p.y > best:
			best = p.y
	return best


## Swap the built-in helmet for the model (helmet.glb's "helmet" MeshInstance3D: centred on its shell,
## +X = face, +Y up). Adds the moto goggles with the strap hugging the shell.
func set_helmet(model: Node3D, own_goggles: Node3D = null) -> void:
	var F: Dictionary = HELMET_FIT.duplicate()
	F.merge(HELMET_FITS.get(helmet_id.get_slice("/", 0), {}), true)
	var ev := Env.s("BMX_HELMET_FIT").split(",", false)   # tests: "x,y,scale,tilt" for the model on
	if ev.size() == 4 and helmet_id != "glory/game":
		F = {x = float(ev[0]), y = float(ev[1]), scale = float(ev[2]), tilt = float(ev[3])}
	var builtin := own_goggles != null   # the model's own goggles are worn: ours are not built
	if helmet_model and is_instance_valid(helmet_model):   # swapping helmets: the old one goes
		helmet_model.get_parent().remove_child(helmet_model)
		helmet_model.queue_free()
		helmet_model = null
	if goggles and is_instance_valid(goggles):
		goggles.get_parent().remove_child(goggles)
		goggles.queue_free()
		goggles = null
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
	if own_goggles:
		own_goggles.owner = null
		if own_goggles.get_parent():
			own_goggles.get_parent().remove_child(own_goggles)
		w.add_child(own_goggles)
	helmet_mats = {}
	var shell_tris := PackedVector3Array()   # shell triangles in head space, for the strap
	var meshes: Array = [model]
	meshes.append_array(model.find_children("*", "MeshInstance3D", true, false))
	if own_goggles:
		meshes.append(own_goggles)
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
			if nm == "shell" or nm == "tex_shell":
				shell_tris.append_array(_surface_tris(mi.mesh, si, to_head))
	head.add_child(w)
	helmet_model = w
	# strap hugging the shell: rays from outside looking back in (head space)
	var hug := Callable()
	if not shell_tris.is_empty():
		hug = func(x: float, y: float, dx: float, dz: float) -> Variant:
			return _hug(shell_tris, x, y, dx, dz)
	if not builtin:
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
	cam_spots = {top = Vector3(0.03, top - 0.004, 0)}
	# side: on the left of the shell, ~7 cm under the crown, a little behind the ear line's front
	var side_y := top - 0.075
	var sd = _hug(shell_tris, 0.0, side_y, 0.0, -1.0) if not shell_tris.is_empty() else null
	cam_spots.side = Vector3(0.0, side_y, -(float(sd) - 0.002) if sd != null else -0.15)
	# chin: the bottom edge of the chin bar = the lowest shell point in front of the face on the centreline;
	# the camera sits on the bar's front face 3 cm above that edge
	var low := 1e9
	var xmax := 0.0
	for p in shell_tris: xmax = maxf(xmax, p.x)
	for p in shell_tris:   # well forward only (a round shell's underside is not the chin bar)
		if absf(p.z) < 0.03 and p.x > xmax * 0.6 and p.y > top - 0.40: low = minf(low, p.y)
	if low < 1e8:
		var fx := -1e9
		for p in shell_tris:
			if absf(p.z) < 0.03 and p.y > low + 0.02 and p.y < low + 0.08: fx = maxf(fx, p.x)
		if fx > 0.07:
			cam_spots.chin = Vector3(fx - 0.004, low + 0.045, 0)
	if not cam_spots.has("chin"):
		cam_spots.chin = Vector3(0.24, top - 0.27, 0)
	if Env.s("BMX_CAMMOUNT_PROBE") != "":
		var ylo := 1e9; var yhi := -1e9; var xhi := -1e9
		for p in shell_tris: ylo = minf(ylo, p.y); yhi = maxf(yhi, p.y); xhi = maxf(xhi, p.x)
		print("CAMMOUNT helmet %s spots=%s low=%.3f shell y %.3f..%.3f xmax %.3f" % [helmet_id, cam_spots, low, ylo, yhi, xhi])
	_fit_fill(_goggle_front(own_goggles, w) if own_goggles else INF)
	if Env.s("BMX_CAMMOUNT_PROBE") != "":
		print("GOGGLE lens front x %.3f  fill front x %.3f" % [_goggle_front(own_goggles, w) if own_goggles else 0.0, helmet_fill.transform.basis.x.x * FILL_R])
	_mount_action_cam()
	if not look.is_empty():
		set_look(look)


## the model goggles' lens front on the centreline, head space (x of the most forward point near z = 0)
static func _goggle_front(gog: Node3D, w: Node3D) -> float:
	var front := -INF
	for o in [gog] + gog.find_children("*", "MeshInstance3D", true, false):
		if not (o is MeshInstance3D) or o.mesh == null: continue
		var t: Transform3D = w.transform * _rel_xform(o, w)
		for si in o.mesh.get_surface_count():
			for p in _surface_tris(o.mesh, si, t):
				if absf(p.z) < 0.03: front = maxf(front, p.x)
	return front

## The dark inside of the helmet (helmet_fill, so the face opening isn't see-through): its front stays
## FILL_GAP behind the goggle lens, or it shows through the lens (model goggles sit closer to the head than ours)
const FILL_R := 0.1
const FILL_GAP := 0.03
func _fit_fill(lens_front: float) -> void:
	if helmet_fill == null: return
	var sx := 1.0
	if lens_front < INF:
		sx = clampf((lens_front - FILL_GAP) / FILL_R, 0.4, 1.0)
	helmet_fill.transform = Transform3D(Basis.from_scale(Vector3(sx, 1.2, 0.95)), Vector3(0, -0.01, 0))

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


## put a HELMETS model on (loads the glb, mounts it like set_helmet); no-op when it is already on
func use_helmet(id: String) -> void:
	if not HELMETS.has(id):
		id = "glory"
	var own := id != "glory"
	var key := id + ("/own" if own else "/game")
	if key == helmet_id and helmet_model and is_instance_valid(helmet_model):
		return
	var hs: Node3D = load(HELMETS[id][1]).instantiate()
	var helmet := hs.find_child("helmet", true, false)
	if helmet == null:   # a broken model: keep the current helmet, and don't retry the load on every set_look
		hs.free()
		push_warning("helmet model %s has no 'helmet' node" % HELMETS[id][1])
		helmet_id = key
		return
	var gog: Node3D = hs.find_child("helmet_goggles", true, false) if own else null
	helmet.get_parent().remove_child(helmet)
	if gog:
		gog.get_parent().remove_child(gog)
	hs.free()
	helmet_id = key
	set_helmet(helmet, gog)


## colours: {shell, peak, jersey, pants, gloves, shoes, shoeAccent, goggleFrame, lens, strap} as "#rrggbb"
func set_look(l: Dictionary) -> void:
	look.merge(l, true)
	var L := look
	var want := str(L.get("helmet", "glory"))
	var want_key := want + ("/own" if want != "glory" else "/game")
	if hel != null and want_key != helmet_id and HELMETS.has(want):   # another helmet / goggle source: mount it (set_helmet re-applies the look)
		use_helmet(want)
		if helmet_id == want_key and helmet_model and is_instance_valid(helmet_model): return   # set_helmet re-applied the look
	if not cam_spots.is_empty() and (str(L.get("camMount", DEFAULT_LOOK.camMount)) != cam_mount or ActionCam.gear_sig(ActionCam.gear_from_look(L)) != cam_gear):
		_mount_action_cam()
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
	var pc := Color(str(L.get("pants", DEFAULT_LOOK.pants)))
	PantsLook.apply(kit.pants[0], pc, L)
	PantsLook.apply(kit.pants[1], _offset_l(pc, 0.1), L)
	c.call(kit.gloves[0], "gloves")
	for i in knee_pad.size():   # knee pad design + shell colour; the accent (chevron, stripes) takes the gloves' colour
		var kp := knee_pad[i]
		kp.set_design(str(L.get("padStyle", DEFAULT_LOOK.padStyle)))
		kp.set_colors(Color(L.get("pads", DEFAULT_LOOK.pads)), Color(L.get("gloves", DEFAULT_LOOK.gloves)))
		knee[i].visible = kp.design == "none"   # no pads: the plain knee
	if belt_node:
		belt_node.set_look(str(L.get("beltStyle", DEFAULT_LOOK.beltStyle)), Color(str(L.get("belt", DEFAULT_LOOK.belt))),
			Color(str(L.get("buckle", DEFAULT_LOOK.buckle))))
	c.call(shoe_mats.upper, "shoes")
	c.call(shoe_mats.accent, "shoeAccent")
	c.call(goggle_mats.frame, "goggleFrame")
	c.call(goggle_mats.strap, "strap")
	if L.get("lens"):
		goggle_mats.lens.albedo_color = Color(L.lens)
		var e := Color(L.lens).srgb_to_linear() * 0.25
		goggle_mats.lens.emission = Color(e.r, e.g, e.b).linear_to_srgb()
	if skin_mat:
		skin_mat.albedo_color = Color(str(L.get("skin", DEFAULT_LOOK.skin)))
		hair_mat.albedo_color = Color(str(L.get("hair", DEFAULT_LOOK.hair)))
		scalp_mat.albedo_color = hair_mat.albedo_color.lightened(0.04)
		eye_mat.albedo_color = Color(str(L.get("eyes", DEFAULT_LOOK.eyes)))
		hair.set_color(hair_mat.albedo_color)
		var hs := str(L.get("hairStyle", "long"))
		var helmet_on := true   # the rider always wears a helmet: hair only shows coming out under the back of it
		hair_tail = helmet_on and Hair.STYLES.get(hs, {}).get("short", true) == false   # long / bob under a helmet
		hair.set_style(hs, helmet_on)
		_apply_head_gear(true)
	if bib_node:
		bib_node.visible = str(L.get("bibOn", "1")) != "0"
		bib_node.set_content(str(L.get("bibNumber", "27")).substr(0, 3), str(L.get("bibText", DEFAULT_LOOK.bibText)).substr(0, 30))


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
static func set_limb(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-5:
		n.transform = Transform3D(Basis.from_scale(Vector3(1, 1e-4, 1)), a + d * 0.5)
		return
	# the twist about the limb comes from the rider's sideways axis, not the shortest turn from +Y: that one
	# spun the cylinder round its axis whenever a shin / forearm pointed down, and the mud / blood (drawn in
	# the part's own space, shaders/grime_*) slid round the leg as it pedalled. Same as before for an upright limb.
	var y := d / l
	var w := smoothstep(0.8, 0.95, absf(y.z))   # limb along the sideways axis: take the forward one instead
	var ref := Vector3.BACK * (1.0 - w) + Vector3.RIGHT * w
	var z := (ref - y * ref.dot(y)).normalized()
	n.transform = Transform3D(Basis(y.cross(z), y, z).scaled_local(Vector3(1, l, 1)), a + d * 0.5)


## torso: like set_limb, but keeps its width across the body (`right`) so the section doesn't twist
# ---------------- the spine: the torso mesh is skinned to SPINE_BONES bones along its length so it can bend

const SPINE_BONES := 5
static var _KNEE_PROBE := Env.s("BMX_KNEE_PROBE") != ""
var knee_dbg: Array = []   # tests: frames where a knee bends against its pole
var torso_ratio := 1.0   # tests: torso length / its rest length before the limit
const _CLIP_PROBE_ENV := "BMX_BODY_CLIP"
var _CLIP_PROBE: bool = Env.s("BMX_BODY_CLIP") != ""
var clip_pairs := {}   # tests (BMX_BODY_CLIP): pair -> [frames clipping, deepest m], "n" -> frames

## shortest distance between two segments (a0-a1, b0-b1)
static func seg_dist(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var d1 := a1 - a0; var d2 := b1 - b0; var r := a0 - b0
	var a := d1.dot(d1); var e := d2.dot(d2); var f := d2.dot(r)
	var s := 0.0; var t := 0.0
	if a <= 1e-9 and e <= 1e-9: return r.length()
	if a <= 1e-9: t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9: s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-9 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0; s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0; s = clampf((b - c) / a, 0.0, 1.0)
	return (a0 + d1 * s).distance_to(b0 + d2 * t)

## a limb never goes through the body: its middle joint (knee / elbow) swings about the line from its root to its tip,
## outwards (to its own side), by the smallest angle that gets both its bones `clear` of every segment in `segs`
## ([a0, b0, a1, b1, ...]); at most `max_a` rad. Hands and feet stay where they are. This is what a rider does: in a
## deep tuck the knees go out round the chest, an elbow goes out round a knee
static func _swing_clear(root: Vector3, tip: Vector3, mid: Vector3, side: float, segs: Array, clear: float, max_a := 1.15) -> Vector3:
	var ax := tip - root
	if ax.length_squared() < 1e-6: return mid
	ax = ax.normalized()
	if _swing_need(root, tip, mid, segs, clear) <= 0.0: return mid
	var c := root + ax * (mid - root).dot(ax)
	var rel := mid - c
	if rel.length_squared() < 1e-8: return mid
	var sgn := 1.0 if ax.cross(rel).z * side > 0.0 else -1.0   # the way round that takes the joint to its own side
	var lo := 0.0
	var hi := max_a
	if _swing_need(root, tip, c + rel.rotated(ax, sgn * hi), segs, clear) <= 0.0:
		for _k in 9:   # the smallest swing that clears (so it moves smoothly frame to frame)
			var m := (lo + hi) * 0.5
			if _swing_need(root, tip, c + rel.rotated(ax, sgn * m), segs, clear) <= 0.0: hi = m
			else: lo = m
	return c + rel.rotated(ax, sgn * hi)

static func _swing_need(root: Vector3, tip: Vector3, m: Vector3, segs: Array, clear: float) -> float:
	var worst := 0.0
	for k in range(0, segs.size(), 2):
		var d := minf(seg_dist(root.lerp(m, 0.45), m, segs[k], segs[k + 1]), seg_dist(m, m.lerp(tip, 0.75), segs[k], segs[k + 1]))
		worst = maxf(worst, clear - d)
	return worst

## tests (BMX_BODY_CLIP=1): how far the drawn body parts are inside each other / the bike this frame. The body as
## capsules (head, torso, thighs, shins, upper arms, forearms) against the handlebar, the saddle, both wheels and
## each other. Counted per pair: frames more than 1.5 cm in, and the deepest
func _clip_probe(p: Dictionary) -> void:
	clip_pairs["n"] = int(clip_pairs.get("n", 0)) + 1
	var head := J[0] + Vector3(0.02, 0.07, 0.0)
	var R_HEAD := 0.14; var R_TORSO := 0.115; var R_THIGH := 0.07; var R_SHIN := 0.055; var R_UARM := 0.045; var R_FARM := 0.04
	var checks := []   # [name, distance, clear distance]
	var hl = p.get("handL"); var hr = p.get("handR")
	if hl is Vector3 and hr is Vector3:
		checks.append(["head-bar", seg_dist(head, head, hl, hr), R_HEAD + 0.02])
		checks.append(["torso-bar", seg_dist(J[2], J[1], hl, hr), R_TORSO + 0.02])
		for i in 2:
			checks.append(["thigh-bar", seg_dist(J[9 + i * 3], J[10 + i * 3], hl, hr), R_THIGH + 0.02])
	for i in 2:
		var sh := J[3 + i * 3]; var el := J[4 + i * 3]; var hd := J[5 + i * 3]
		var hp := J[9 + i * 3]; var kn := J[10 + i * 3]; var ft := J[11 + i * 3]
		# (a limb against the torso from a third of the way along it: it starts at the body)
		checks.append(["knee-torso", seg_dist(hp.lerp(kn, 0.5), kn, J[2].lerp(J[1], 0.35), J[1]), R_THIGH + R_TORSO])
		checks.append(["knee-head", seg_dist(kn, kn, head, head), R_THIGH + R_HEAD])
		checks.append(["forearm-torso", seg_dist(el, hd, J[2], J[1]), R_FARM + R_TORSO])
		checks.append(["elbow-torso", seg_dist(sh.lerp(el, 0.6), el, J[2], J[1].lerp(J[2], 0.3)), R_UARM + R_TORSO])
		checks.append(["forearm-head", seg_dist(el, hd.lerp(el, 0.25), head, head), R_FARM + R_HEAD])
		checks.append(["arm-thigh", seg_dist(el, hd.lerp(el, 0.2), hp.lerp(kn, 0.3), kn), R_FARM + R_THIGH])
		checks.append(["arm-shin", seg_dist(el, hd.lerp(el, 0.2), kn, ft), R_FARM + R_SHIN])
		for w in [["wheelR", "wheelRR", "rear"], ["wheelF", "wheelRF", "front"]]:
			var wc = p.get(w[0])
			if not (wc is Vector3): continue
			var wr2: float = _num(p, w[1], 0.36)
			# the tyre: a ring in the bike's plane. A part within the tyre's width of that plane and inside the radius
			for part in [[hp, kn, R_THIGH, "thigh"], [kn, ft, R_SHIN, "shin"], [el, hd, R_FARM, "arm"]]:
				var worst := 9.0
				for k in 5:
					var q: Vector3 = (part[0] as Vector3).lerp(part[1], k / 4.0)
					if absf(q.z - wc.z) < 0.035 + float(part[2]):
						worst = minf(worst, Vector2(q.x - wc.x, q.y - wc.y).length() - wr2)
				checks.append(["%s-%swheel" % [part[3], w[2]], worst, float(part[2])])
	for w in [["wheelR", "wheelRR", "rear"], ["wheelF", "wheelRF", "front"]]:
		var wc = p.get(w[0])
		if wc is Vector3:
			checks.append(["pelvis-%swheel" % w[2], Vector2(J[2].x - wc.x, J[2].y - wc.y).length() - _num(p, w[1], 0.36), 0.1])
			checks.append(["head-%swheel" % w[2], Vector2(head.x - wc.x, head.y - wc.y).length() - _num(p, w[1], 0.36), R_HEAD])
	if seat != null and J[2].x > float(seat.rear) - 0.02 and J[2].x < float(seat.front) + 0.02:
		checks.append(["pelvis-saddle", J[2].y - float(seat.top), 0.07])
	for c in checks:
		var inside: float = float(c[2]) - float(c[1])
		var rec: Array = clip_pairs.get(c[0], [0, 0.0])
		if inside > 0.015: rec[0] += 1
		rec[1] = maxf(rec[1], inside)
		clip_pairs[c[0]] = rec

const LIMB_TORSO := 0.18   # m: a thigh's centre line from the torso's (their two thicknesses)
const LIMB_LIMB := 0.105   # m: a forearm's from a thigh's / shin's
const AIR_COUNTER := 1.4    # rad: in the air the body may stay this far upright from a laid-over bike (chest)
const AIR_HIP_ROLL := 1.05  # rad: ... the hips
const LIMB_BAR := 0.12      # m: knees keep this clear of the handlebar line in the air
const AIR_FACE := 0.7       # in a whip the torso's lean turns back this share of the bike's yaw (faces the flight)
const AIR_HIP_SIDE := 0.5   # m: the hips' sideways room in the bike's frame in the air (ground: 0.22)
const AIR_SIDE := 1.2       # rad: ... the torso bent sideways from the bike's up (ground: 0.6)
static var _ROLL_PROBE := OS.get_environment("BMX_ROLL_PROBE") != ""
static var _OLD_AIRBODY := OS.get_environment("BMX_OLD_AIRBODY") != ""
const BAR_CHEST := 0.32   # m: the chest joint stays this far from the middle of the bar (side view)
const BAR_HEAD := 0.31    # m: and the head's centre this far (helmet + chin bar)
var bar_stats := [0.0, 0.0, 0.0, 9.0, 9.0]   # tests: deepest it was held out of the bar, frames held, frames, least chest / head distance
const TORSO_VMAX := 2.5   # m/s: the most the hips / chest move relative to the bike between frames (motion cap)
var _cap_pel := Vector3.ZERO; var _cap_ch := Vector3.ZERO; var _cap_ok := false
## tests (BMX_LIMB_PROBE): per joint, how fast its bend direction turns (deg/s) and how far it moves
## relative to its limb root per frame; frames over the limits are counted
var limb_probe := Env.s("BMX_LIMB_PROBE") != ""
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
## `base` (optional): the hips' basis. The bottom bone then takes the hips' up / sideways, so the jersey's hem
## stays level inside the belt however far the chest leans (it used to tilt with the spine and cross the trousers'
## top: one poked out under the other at the front, the other at the back)
## a shoulder joint on the TORSO's own frame (the one set_spine draws it in: up the spine, sideways = the twist's side
## kept square to it). (2026-11-23) It was offset along the BIKE's axes turned by the twist: fine with the torso over
## the bike, but with it rolled far over in the air the bike's sideways ran along the spine and a shoulder ended up
## above the chest - the joint came apart ("the shoulder pops off")
static func shoulder_at(hip_p: Vector3, chest_p: Vector3, tw: Basis, off: Vector3) -> Vector3:
	var up := (chest_p - hip_p).normalized()
	if up.length_squared() < 0.5: up = Vector3.UP
	var r := tw * Vector3(0, 0, 1)
	r = (r - up * r.dot(up))
	if r.length_squared() < 1e-6: r = Vector3(0, 0, 1)
	r = r.normalized()
	var fw := up.cross(r)
	return chest_p + fw * off.x + up * off.y + r * off.z


func set_spine(a: Vector3, b: Vector3, right_lo: Vector3, right_hi: Vector3, curve := 0.0, side := 0.0, low := 0.5, base := Basis()) -> void:
	var lock_base := base != Basis()
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
		if k == 0 and lock_base:
			tn = base.y.normalized()
		var rr := right_lo.lerp(right_hi, t)
		if k == 0 and lock_base:
			rr = base.z
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


## the neck tube: radii (it narrows from the collar up), where it starts inside the torso (mesh space of the
## top spine bone: y 0.5 = the collar) and where it ends inside the helmet (head space, behind the jaw)
const NECK_R_BASE := 0.056
const NECK_R_TOP := 0.047
const NECK_BASE := Vector3(-0.012, 0.42, 0.0)
const NECK_TOP := Vector3(-0.035, -0.07, 0.0)


## run after set_spine and the head transform: the tube follows the spine's bend and the head's turn / tilt
func _pose_neck() -> void:
	var base := spine_skel.get_bone_pose(SPINE_BONES - 1) * NECK_BASE
	set_limb(neck_mesh, base, head.transform * NECK_TOP)


## the forearm tube ends at the wrist inside the glove's cuff, not at the grip point (it showed between the fingers)
const WRIST_BACK := 0.062
func _wrist(i: int, from: Vector3) -> Vector3:
	var h: Vector3 = glove[i].position
	var d := h - from
	# the wrist sits back along the HAND's own axis (it is bent against the forearm gripping), so the forearm
	# tube ends on the glove's cuff and the bend shows between them
	var hx: Vector3 = glove[i].basis.x
	if hx.length_squared() > 0.5: return h - hx.normalized() * minf(WRIST_BACK, d.length() * 0.5)
	return h - d.normalized() * minf(WRIST_BACK, d.length() * 0.5) if d.length_squared() > 1e-8 else h

## Grip + brake fingers on the bike. Every finger has its own curl: the ring / little finger and the thumb wrap the bar
## (tighter with the load: a landing, a bump, hard braking), the INDEX and MIDDLE finger rest on the brake lever and
## squeeze it with the brake (left hand = rear lever, right = front; both brakes together pull both). Standing: relaxed.
var _lev_s := [0.0, 0.0]; var _pull_s := [0.0, 0.0]; var _grip_s := [0.0, 0.0]
func _pose_fingers(i: int, standing: bool, dt: float, p: Dictionary, sty: Dictionary) -> void:
	if skeleton == null: return
	var step := clampf(dt if dt > 0.0 else 1.0 / 60.0, 0.0, 0.1)
	var brake: float = clampf(_num(p, "brakeR") if i == 0 else _num(p, "brakeF"), 0.0, 1.0)
	var load_k: float = clampf(_num(p, "landFold") * 0.8 + maxf(_num(p, "brakeF"), _num(p, "brakeR")) * 0.5, 0.0, 1.0)
	_lev_s[i] = move_toward(_lev_s[i], 0.0 if standing else float(sty.get("leverFingers", 1.0)), step * 4.0)
	_pull_s[i] = lerpf(_pull_s[i], brake, 1.0 - exp(-14.0 * step))   # (the squeeze follows the lever, a quick spring)
	_grip_s[i] = lerpf(_grip_s[i], load_k, 1.0 - exp(-8.0 * step))
	var tight: float = clampf(_grip_s[i] + _pk_grip, -1.0, 1.0)
	var base: float = skeleton.curls[i]
	# a light grip leaves the hand a touch looser than a fist; load squeezes it right round (the little finger a bit tighter)
	var hold: float = clampf(0.9 + 0.1 * tight, 0.3, 1.0)
	skeleton.fin[i] = [minf(base, hold), minf(base, hold - 0.02), minf(base, hold - 0.02), minf(base, hold), minf(base, hold + 0.02)]
	skeleton.lever[i] = _lev_s[i]
	skeleton.pull[i] = clampf(_pull_s[i] + _pk_lp, 0.0, 1.0)

## ease a hand's finger curl (GloveFingers: 0 open, 0.4 relaxed, 1 round the bar) toward `to`
func _curl_to(i: int, to: float, step: float) -> void:
	if skeleton: skeleton.curls[i] = move_toward(skeleton.curls[i], to, step)

## hand: +X along the forearm, +Z along the bar, +Y the back of the hand
## Gripping, the hand is locked to the GRIP's own frame (as in other games: the IK target carries an orientation, the
## hand never deviates from the bar), so the palm always lies square across the bar, turned with the steering; the
## wrist is just the angle between that hand and the forearm coming from the elbow, which falls out of the arm IK.
## `bend` / `yaw` are Pose Lab offsets on top (wrist up / sideways). The wrist's own range is capped at WRIST_MAX.
const WRIST_BEND := 0.0
const WRIST_MAX := 0.9    # rad, how far the hand may leave the forearm's line
const GRIP_TILT := 0.12   # rad, the hand lies a little down the front of the bar
static func orient_grip(n: Node3D, el: Vector3, at: Vector3, gx: Vector3, gz: Vector3, bend: float, yaw: float) -> void:
	var z := gz.normalized()
	var x := (gx - z * gx.dot(z)).normalized()
	var up := z.cross(x)
	x = (x * cos(GRIP_TILT + bend) - up * sin(GRIP_TILT + bend)).normalized()
	if absf(yaw) > 1e-4: x = x.rotated(up, yaw)
	var fore := (at - el).normalized()
	var ang := fore.angle_to(x)
	if ang > WRIST_MAX: x = fore.slerp(x, WRIST_MAX / ang)
	var zz := (z - x * z.dot(x)).normalized()
	n.basis = Basis(x, zz.cross(x), zz)

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
	_cap_ok = false   # (the motion cap starts fresh once riding again)
	_pose_from_points(P, roots, {})


var anim: RiderAnim = null   # animation clips played in the menus (animate)
var _anim_tried := false

## menus: play the animation clips in RiderAnim.DIR (Mixamo downloads) on the rider. False = there are none:
## pose the rider yourself (update_pose)
func animate(dt: float) -> bool:
	if not _anim_tried:
		_anim_tried = true
		if RiderAnim.available(): anim = RiderAnim.new(self)
	return anim != null and anim.step(dt)


## stand the rider in a pose given as the 15 joint points (Ragdoll order) in this node's space, e.g. from an
## animation clip (RiderAnim). orient (optional): "head" Basis (x forward, y up), "hand0" / "hand1" (x along the
## forearm, y the back of the hand), "foot0" / "foot1" (x toward the toes, y up); left = 0
func pose_points(P: Array, orient: Dictionary = {}) -> void:
	_cap_ok = false
	for k in 15: J[k] = P[k]
	_pose_from_points(P, {}, orient)


func _pose_from_points(P: Array, roots: Dictionary, orient: Dictionary) -> void:
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
	var hip: Vector3 = pe + (ch - pe).normalized() * Belt.HEM_Y
	set_spine(hip, ch, body_r.normalized(), (sh[1] - sh[0]).normalized(), 0.0, 0.0, 0.5, bb)
	var sh_r: Vector3 = sh[1] - sh[0]
	head.transform = Transform3D(orient.get("head", _basis_from(hd - ch, sh_r)), hd)
	_pose_neck()
	# the curl eases by time (0.06 a frame at 60 fps), not per call: no dt reaches here, so real time between calls
	var now_us := Time.get_ticks_usec()
	var cdt := clampf((now_us - _curl_us) / 1e6, 0.0, 0.1) if _curl_us > 0 else 1.0 / 60.0
	_curl_us = now_us
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
		elbow[i].position = el[i]
		glove[i].position = ha[i]
		if orient.has("hand%d" % i): glove[i].basis = orient["hand%d" % i]
		else: orient_hand(glove[i], ha_from, ha[i], sh_r)
		set_limb(fore_arm[i], ha_from, _wrist(i, ha_from))
		_curl_to(i, float(orient.get("curl%d" % i, GloveFingers.RELAXED)), 3.6 * cdt)
		if skeleton: skeleton.fin[i] = null; skeleton.lever[i] = 0.0; skeleton.pull[i] = 0.0   # (clips / ragdoll: no lever, one curl)
		set_limb(thigh[i], kn_from, kn[i])
		set_limb(shin[i], ft_from, ft[i])
		knee[i].position = kn[i]
		knee_pad[i].pose(kn_from, kn[i], ft_from, ft[i], bb.x)
		var up: Vector3 = ft_from - ft[i]
		var sb: Basis = orient.get("foot%d" % i, _basis_from(up, body_r))
		# the ankle sits over the back of the shoe (riding: 4 cm behind the shoe's origin, 9 cm up), not over its middle
		shoe[i].transform = Transform3D(sb, ft[i] - sb.y.normalized() * float(orient.get("shoe_drop", 0.08)) + sb.x.normalized() * float(orient.get("shoe_fwd", 0.0)))
	_sync_skeleton(P)


var _pk_wb := 0.0; var _pk_wt := 0.0; var _pk_grip := 0.0; var _pk_lp := 0.0   # Pose Lab wrist keys (extension / turn, rad)
var _pk_tyaw := 0.0; var _pk_hp := 0.0; var _pk_hy := 0.0; var _pk_eo := 0.0; var _pk_ko := 0.0   # Pose Lab key values of this frame (see the hook in update_pose)
var _curl_us := 0   # Time.get_ticks_usec() of the last _pose_from_points (finger curl easing)

## the humanoid skeleton follows whatever was just drawn (P = the joint points in this node's space)
func _sync_skeleton(P: Array) -> void:
	if skeleton == null: return
	var sp := []
	for k in SPINE_BONES: sp.append(spine_skel.get_bone_pose(k))
	skeleton.follow(P, sp, head.transform, [glove[0].transform, glove[1].transform], [shoe[0].transform, shoe[1].transform])


## back on the bike: clear the ragdoll orientations the normal update doesn't set
func reset_pose() -> void:
	_cap_ok = false
	if bib_node and is_instance_valid(bib_node) and bib_node.has_method("restart"): bib_node.restart()   # (the race number starts flat: it kept the crash's crumple for a frame)
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
	sm_pre = 0.0; sm_ext = 0.0; sm_popfx = 0.0; sm_tuck = 0.0; sm_squash = 0.0; sm_lip = 0.0; sm_fold = 0.0; sm_reach = 0.0
	roll_init = false; roll_pv = 0.0; roll_cv = 0.0; lat_g_s = 0.0; flow_e = 0.0
	_fy_prev = NAN; _fv_prev = NAN; _facc = 0.0   # the bump bounce starts fresh (NAN = no previous frame)
	_hp_init = false; _hy = 0.0; _neck_d = Vector3.ZERO; _neck_v = Vector3.ZERO


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
var sm_fold := 0.0; var sm_reach := 0.0   # landing: folded by the hit, reaching for the ground
# landings: how far the legs are bent past a little (the hips go back and onto the saddle), the air pose's weight (gone
# at touch-down), the physics legs' bend that goes past the drawn body springs (hips / chest)
var _sink := 0.0; var sm_airst := 0.0; var _abs_p := 0.0; var _abs_c := 0.0
var sm_pre := 0.0; var sm_ext := 0.0; var sm_popfx := 0.0; var sm_squash := 0.0; var sm_lip := 0.0   # the jump (see update_pose)
var sm_tuck := 0.0   # the air tuck (bike pulled up into the body), eased
var tuck_out := 0.0  # this frame's tuck (0..1)
var speed_tuck_k := 0.0   # this frame's speed tuck (0..1, after the jump / trick poses took their share)
var body_off := Vector2.ZERO   # in the air: the hips (x fwd, y up, bike frame) against take-off; Game moves the bike against it
var _air_ref := Vector2.ZERO; var _air_ref_ok := false
var sm_effort := 0.0
const SPR_LAG := 0.5   # rad (~30 deg): standing, peak pedal force and the arms' pull come late in the stroke
var _NO_SPR2 := Env.s("BMX_NO_SPR2") != ""   # test: none of the sprint pose additions (elbows, tilt, pull, knee lift, ankle)
var _cad_acc := 0.0
var _cad_t := 0.0
var _cad_prev := 0.0
var _cad_s := 0.0      # smoothed cadence, rpm
var _NO_BREATH := Env.s("BMX_NO_BREATH") != ""   # test: no breathing
var _inhale := 0.0     # 0..1, the in-breath of a winded rider (lifts elbows + shoulders)
var _winded := 0.0   # how out of breath, 0..1 (slow to recover)
var _breath_ph := 0.0
var _fat := 0.0       # sprint fatigue 0..1
var _spr_arm := 0.0   # sprint arm pose 0..1 (quick on, slow off)
var sm_pitch0 := 0.0
var sm_pitch_slow := 0.0   # the bike's pitch averaged over ~0.35 s: what the body swings with
var bump_pitch := 0.0      # this frame's quick pitch kick the body holds against (tests)
var sm_wheelie := 0.0   # the slope the body levels against, rate-limited
const PITCH_LEVEL_RATE := 2.5   # rad/s
const FACE_SINK := 0.35  # share of the legs' sink drawn on a jump face (firm legs loading the lip)
var _face_k := 0.0        # this frame's blend into the jump-face pose (0..1)
# speed tuck pose (a downhill speed record rider, side view): back ~70 deg from upright, hips ~16 cm further back and
# ~10 cm lower than the attack stance, head low and forward (chin just behind the bars)
const TUCK_ANG := 1.2
const TUCK_HIP_BACK := 0.16
const TUCK_HIP_DOWN := 0.10
const TUCK_HEAD := Vector2(0.07, -0.08)
const FLIP_LEAN := 0.7    # rad he lies back throwing a back flip (video: ~45 deg back, legs and arms straight)
const FLIP_ARCH := 0.5    # the spine's arch at the start of a back flip (set_spine curve, - = arched)
const FACE_REACH := 0.96  # arms on a jump face / popped: nearly straight (share of their length)
const FACE_POSE := 0.85   # how far the body goes to the measured face pose (video 2) on a jump face / just popped
const FACE_HIP := Vector2(-0.42, 0.68)   # hips from the crank centre, in the WORLD: behind, up (m; video 2)
const FACE_TORSO := 0.08  # rad the torso leans forward of upright in the world
# head stabilisation (riders keep the head steady and the eyes on the trail: the body soaks the bike's kicks from
# the contact points up, the head sees the least of them; docs/research/rider_animation.md). The head's pitch follows
# a smoothed copy of the bike's (slopes, held manuals) and holds against the quick part (rocks, landings); quick yaw
# twitches of the bike (grip sim, slides) are held against too; the pedalling rock is taken out of its roll; its
# position rides a short neck spring on the chest. Pose key headSteady (0 = the old head glued to the bike / chest)
var _hp_init := false
var _hp_s := 0.0; var _hp_v := 0.0       # the bike's pitch as the head follows it (critical spring)
var _yr_s := 0.0; var _yr_v := 0.0       # the bike's yaw rate, slow
var _hy := 0.0                           # head yaw held against quick yaw twitches (rad)
var _neck_d := Vector3.ZERO; var _neck_v := Vector3.ZERO   # head position off its place on the chest (m)
const HEAD_PITCH_HL := 0.16    # s: halflife the head follows the bike's pitch with
const HEAD_YAW_HL := 0.22      # s: the slow yaw rate / the held yaw letting go
const NECK_W := 15.0; const NECK_Z := 0.7   # neck spring (rad/s, damping ratio)
# the chest rides the hips softer up and down than the hips ride the bike (0.6 x the legs' stiffness, 0.6 x the bump's
# push): each part up the body sees less of the bike's kicks (MTB vibration studies: bike > lower back > head). Measured
# on the rocks lane (BMX_POSE_PROBE, world): hips / chest / head 15-18 % smoother than at 1.0; 0.4 was worse again
const CHEST_KY := 0.6; const CHEST_PUSH := 0.6
const NECK_MAX := Vector3(0.025, 0.035, 0.012)   # m the head may sit off the chest's line
# ankling (Gregor 2000, Road Cycling ch. 2: ~20 deg of ankle swing per crank turn, heel lowest just past the front of the
# stroke, toes down at the back; standing adds toe-down): pose keys ankling, heelsDown
const ANKLE_SWING := 0.17      # rad: half the swing pedalling
const ANKLE_PHASE := 0.26      # rad: heel lowest this far past the front of the stroke
var foot_pitch := [0.0, 0.0]   # this frame's foot pitch per foot (rad, + = toes up; footAngle + ankling): the pedals turn with it
# the shoe on the pedal: riders on flats stand with the ball of the foot over the axle (the shoe runs x -0.115 heel ..
# 0.175 toe, the ball ~70 % along); the sole rests on the pedal's top (set per frame from the bike: pose input pedalTop)
const BALL_X := 0.08
const ANKLE_UP := 0.09         # m: the ankle over the sole (and 4 cm behind the shoe's origin)
var pedal_top := 0.017


## The exact step of a damped spring x'' = k (g - x) - c x' + a (stiffness k, damping c, a constant push a) over dt:
## the same motion at any frame rate (an Euler step drifts with dt). Under-, critically and over-damped.
## Returns Vector2(x, v). (Holden, "Spring-It-On")
static func spring_exact(x: float, v: float, g: float, k: float, c: float, a: float, dt: float) -> Vector2:
	if k <= 1e-6 or dt <= 0.0: return Vector2(x + v * dt, v)
	var gg := g + a / k          # where it settles with the push
	var x0 := x - gg
	var y := c * 0.5
	var disc := k - y * y
	if absf(disc) < 1e-4 * k:   # critical
		var j1 := v + x0 * y
		var e := exp(-y * dt)
		return Vector2(e * (x0 + j1 * dt) + gg, e * (v - j1 * y * dt))
	if disc > 0.0:               # under-damped: rings
		var w := sqrt(disc)
		var B := (v + y * x0) / w
		var e := exp(-y * dt)
		var cs := cos(w * dt); var sn := sin(w * dt)
		return Vector2(gg + e * (x0 * cs + B * sn), e * ((B * w - y * x0) * cs - (x0 * w + y * B) * sn))
	var r := sqrt(y * y - k)     # over-damped
	var y0 := y + r; var y1 := y - r
	var j1 := (-y0 * x0 - v) / (y1 - y0)
	var j0 := x0 - j1
	var e0 := exp(-y0 * dt); var e1 := exp(-y1 * dt)
	return Vector2(j0 * e0 + j1 * e1 + gg, -y0 * j0 * e0 - y1 * j1 * e1)


var _EULER_BODY := Env.s("BMX_EULER_BODY") != ""
var _spring3_v := Vector3.ZERO   # the velocity _spring3 ends with
## the body springs: sideways / fore-aft stiffness k, up / down ky (the legs), damping ratio z, an up / down push ay
func _spring3(x: Vector3, v: Vector3, g: Vector3, k: float, ky: float, z: float, ay: float, dt: float) -> Vector3:
	var c := 2.0 * sqrt(k) * z
	var cy := 2.0 * sqrt(ky) * z
	var rx := spring_exact(x.x, v.x, g.x, k, c, 0.0, dt)
	var ry := spring_exact(x.y, v.y, g.y, ky, cy, ay, dt)
	var rz := spring_exact(x.z, v.z, g.z, k, c, 0.0, dt)
	_spring3_v = Vector3(rx.y, ry.y, rz.y)
	return Vector3(rx.x, ry.x, rz.x)


## Holden's exact critical spring ("Spring-It-On"): x, v towards goal g with halflife hl over dt, stable at any dt.
## Returns Vector2(x, v)
static func crit_spring(x: float, v: float, g: float, hl: float, dt: float) -> Vector2:
	var y := 1.3862944 / maxf(hl, 1e-4)   # = (4 ln 2 / hl) / 2
	var j0 := x - g
	var j1 := v + j0 * y
	var e := exp(-y * dt)
	return Vector2(e * (j0 + j1 * dt) + g, e * (v - j1 * y * dt))
var _fy_prev := NAN; var _fv_prev := NAN; var _facc := 0.0   # the frame's height / speed / acceleration (bump bounce)
var bounce_stats := [0.0, 0, 0.0, 0.0]   # tests: sum of squared body offsets, samples, biggest offset
# the body's own roll (world, rad): hips and chest follow the bike's lean on their own springs, so the bike
# is thrown over first and the body follows through (hips lead, shoulders after, a little overshoot)
var roll_init := false
var roll_p := 0.0; var roll_pv := 0.0; var roll_c := 0.0; var roll_cv := 0.0; var knee_lean := 0.0; var lat_g_s := 0.0
var flow_e := 0.0   # how hard the body has just been rolling (rad/s, quick up, slow down): the sink into a new turn
const ROLL_HIP_W := 8.0; const ROLL_HIP_Z := 0.55      # hips: natural rate (rad/s), damping (the heavy body arrives after the bike)
const ROLL_CHEST_W := 6.5; const ROLL_CHEST_Z := 0.5    # chest / shoulders: slower still, rings on a touch
const ROLL_UNWEIGHT := 0.045                          # m the legs extend through a side-to-side crossover
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
	# cadence (smoothed rpm from the crank's own turn) and the sprint's arm pose, which comes on quickly but lets go slowly
	# (measured over windows of >= 0.15 s: the crank moves in physics steps, so per drawn frame its turn is 0 or double and the
	# rpm flickered, which shook everything that follows cadence)
	if dt > 0.0 and dt <= 0.1:   # (a longer frame - a hitch - is left out: its crank turn would be counted over 0.1 s and spike the rpm)
		_cad_acc += absf(wrapf(crank - _cad_prev, -PI, PI))
		_cad_t += dt
		if _cad_t >= 0.15:
			_cad_s += (_cad_acc / _cad_t * 9.549 - _cad_s) * 0.35
			_cad_acc = 0.0; _cad_t = 0.0
	_cad_prev = crank
	var cad_k: float = smoothstep(70.0, 130.0, _cad_s) * clampf(spr + sm_effort, 0.0, 1.0)   # 0 grinding .. 1 spinning flat out
	var arm_tgt: float = clampf(maxf(spr * pedal, sm_effort), 0.0, 1.0) * (0.0 if _NO_SPR2 else 1.0)
	_spr_arm += (arm_tgt - _spr_arm) * (1.0 - exp(-(7.0 if arm_tgt > _spr_arm else 1.3) * minf(dt, 0.1)))   # ~0.8 s to relax
	# fatigue: as the sprint's stamina runs out the form goes - head and chest sink toward the bars, the elbows narrow,
	# and the bike rocks wilder (a tired rider hauls harder on the bars). Slow in, slower out.
	var fat_tgt: float = pow(1.0 - clampf(_num(p, "stamina", 1.0), 0.0, 1.0), 1.5) * _spr_arm
	_fat += (fat_tgt - _fat) * (1.0 - exp(-(2.0 if fat_tgt > _fat else 0.6) * minf(dt, 0.1)))
	var fat: float = _fat
	# sprint rock: big when grinding a heavy gear (Stone & Hull: bar pull / bike lean fall as cadence rises), calmer when spinning
	var sway: float = sin(crank) * pedal * sty.sway * (1 + 0.9 * spr + 0.8 * eff) * lerpf(1.0, 0.55, cad_k) * hi_fade  # a real sprinter's hips stay fairly still: the bike rocks under them
	# (Body bob: how far the body rises and drops with each pedal stroke)
	# sprint hip rock: out of the saddle the hips swing over the pushing foot every stroke (~3-4 cm each way grinding, less spinning);
	# not faded with speed like the idle sway, a sprint at 40 km/h still rocks
	var hip_rock: float = sin(crank) * pedal * _spr_arm * float(sty.sway) * 0.04 * lerpf(1.0, 0.5, cad_k)
	# sprint hip tilt: out of the saddle the pelvis dips to the side of the foot that is pushing (about 7 deg grinding, half that spinning);
	# the shoulders stay level, so the spine takes the difference. Flip the sign if it dips the wrong side.
	var hip_tilt: float = sin(crank - SPR_LAG) * pedal * _spr_arm * float(sty.sway) * 0.12 * lerpf(1.0, 0.5, cad_k) * (1.0 + 0.6 * fat)
	var bob: float = sin(crank * 2) * pedal * sty.sway * float(sty.get("bodyBob", 1.0)) * (1 + 0.4 * spr + 0.35 * eff) * lerpf(0.4, 1.0, hi_fade)
	# (the idle balance wobble is gone once the rider commits to a sprint: no random drifting)
	var wig: float = clampf(1 - absf(v) / 3, 0, 1) * sty.sway * float(sty.slowWobble) * (1.0 - 0.9 * clampf(eff * 1.5, 0.0, 1.0))
	var air := _num(p, "air")
	var comp: float = _num(p, "compress") * sty.crouch
	var old_lp := Env.s("BMX_OLD_LANDPOSE") != ""
	# the jump, like a rider who knows how. Preload: he sinks low and back over the rear wheel, chest down over the bars,
	# elbows out, heels dropped - a spring wound up. The pop: the legs drive straight and the hips come up and forward to
	# the bars, the back straightens, the arms go long (he stands tall into the lip), then he sucks the bike up under
	# him. A squash: he folds right down over the bike and lets it come up into him. On the face of a lip he stays
	# centred between the wheels (not hauled forward over the bars as on a climb)
	var jh := minf(dt, 0.1)
	sm_pre += (clampf(_num(p, "preload"), 0.0, 1.0) - sm_pre) * (1.0 - exp(-16.0 * jh))
	sm_ext += (clampf(_num(p, "extend") / 0.1, 0.0, 1.0) - sm_ext) * (1.0 - exp(-22.0 * jh))
	sm_popfx += (clampf(_num(p, "popFx"), 0.0, 1.0) - sm_popfx) * (1.0 - exp(-18.0 * jh))
	sm_squash += (clampf(_num(p, "squash"), 0.0, 1.0) - sm_squash) * (1.0 - exp(-12.0 * jh))
	sm_lip += (clampf(_num(p, "lipK"), 0.0, 1.0) - sm_lip) * (1.0 - exp(-8.0 * jh))
	# landing: he reaches for the ground with legs and arms nearly straight (the bike pushed away under him), then the
	# hit folds him: hips down and back over the rear wheel, elbows out, chest and head down towards the bars - as deep as
	# the hit was hard - and he comes back up as he gathers himself (slowly after a heavy one)
	var fold_in := clampf(_num(p, "landFold"), 0.0, 1.0)
	sm_fold += (fold_in - sm_fold) * (1.0 - exp(-(26.0 if fold_in > sm_fold else 7.0) * jh))
	sm_reach += (clampf(_num(p, "landReach"), 0.0, 1.0) - sm_reach) * (1.0 - exp(-14.0 * jh))
	var j_fold: float = sm_fold * float(sty.get("landFold", 1.0))
	var j_pre: float = sm_pre * float(sty.get("jumpPreload", 1.0))
	var j_ext: float = sm_ext * float(sty.get("jumpExtend", 1.0))
	var j_sq: float = sm_squash * float(sty.get("jumpSquash", 1.0))
	# speed tuck: from ~25 km/h the rider folds down over the bars for less drag (full by ~60 km/h):
	# chest flatter and lower, hips back and down, elbows bend (the arm reach check pulls them in).
	# Less while pedalling hard, none in the air (the jump / trick poses own that).
	# the tuck is the player's: the right stick pushed forward folds the rider down over the bars (full
	# stick = the old full speed tuck). Neutral is an upright attack position; nothing tucks on its own
	var bstick := clampf(_num(p, "bodyStick"), -1.0, 1.0)
	# (the forward snap of a pop is not a tuck, and the pull back of a preload is a crouch, not a lean back: see the jump)
	bstick *= 1.0 - (maxf(sm_ext, sm_popfx) if bstick > 0.0 else 0.85 * sm_pre)
	var aero_t: float = clampf(bstick, 0.0, 1.0) * float(sty.get("aero", 1.0))
	sm_aero += (aero_t - sm_aero) * (1.0 - exp(-(3.0 + 12.0 * air) * minf(dt, 0.1)))   # off the ground the tuck goes at once
	var aero: float = sm_aero
	# on the ground forward = fold down over the bars (chest low, hips back a little, knees bent: a race
	# tuck); in the air forward = legs extend and push the bike away (the hips rise). Before, the ground
	# lean also lifted the hips and threw them forward, so the torso came UP instead of down
	var aero_g: float = aero * (1.0 - air)
	var aero_a: float = aero * air
	# speed tuck (2026-11-26, a downhill speed record pose: hips right back over the rear wheel and low, the back flat,
	# head low and forward behind the bars, arms long and in): the physics' speed_tuck (by itself at speed, or a light
	# pull back on the right stick). The jump / landing / trick poses own the body while they play: it gives way to them
	var stk: float = clampf(_num(p, "speedTuck"), 0.0, 1.0) * float(sty.get("speedTuckPose", 1.0))
	stk *= 1.0 - clampf(maxf(maxf(sm_pre, sm_ext), maxf(sm_popfx * air, sm_squash)) * 1.5, 0.0, 1.0)
	stk *= 1.0 - clampf(maxf(maxf(sm_reach, sm_fold), clampf(_num(p, "airPull"), 0.0, 1.0) * air) * 1.5, 0.0, 1.0)
	stk *= (1.0 - smoothstep(0.5, 2.0, absf(_num(p, "airSpin")))) * (1.0 - clampf(_num(p, "flipExt") + _num(p, "flipArch"), 0.0, 1.0))
	stk *= 1.0 - clampf(maxf(_num(p, "tall"), _num(p, "relax")), 0.0, 1.0)
	# (the light pull back that makes the tuck is not also the stick's sit-up / weight-back pose: that starts past it)
	var stk_stick: float = 0.0
	if not _OLD_SPEEDTUCK and _num(p, "tall") < 0.5:
		var bb: float = clampf(-bstick, 0.0, 1.0)
		stk_stick = smoothstep(0.05, 0.3, bb) * (1.0 - smoothstep(0.55, 0.95, bb))
	speed_tuck_k = stk

	# attack position: rolling, a downhill rider stands off the saddle (knees and elbows soft, ready),
	# not only while pedalling
	# reaching for the landing the legs straighten out of the air tuck into the stance he will land in (the hips come up,
	# the bike is pushed down to meet the ground), so the hit has a whole leg to fold
	# (and on the ground the air pose is gone at once: it used to fade over ~0.5 s and lifted the hips by 15-20 cm right
	# through the hit, so every landing looked like a small one. The dip is the legs': the physics' body on its leg
	# spring, `absorb`)
	var air_tg: float = air * (1.0 - sm_reach) if _num(p, "inAir") > 0.5 else 0.0
	sm_airst += (air_tg - sm_airst) * (1.0 - exp(-(30.0 if air_tg < sm_airst else 60.0) * jh))
	if not spring_init: sm_airst = air_tg
	var air_st: float = air if old_lp else sm_airst
	if not old_lp: comp *= 1.0 - sm_reach * air
	var stand: float = maxf(pedal, clampf(0.85 * float(sty.attackStand), 0.0, 1.3) * smoothstep(1.5, 5.0, absf(v)) * (1.0 - air_st))

	# pelvis
	var pelvis := Vector3(
		-0.16 - 0.07 * air * float(sty.airCrouch) + 0.06 * pedal * sty.standPedal - float(sty.standBack) * stand - comp * 0.25,
		0.80 - comp + (float(sty.standHeight) * stand + 0.05 * spr) * sty.standPedal + 0.035 * bob + 0.14 * aero_a - 0.07 * aero_g,   # (forward: in the air legs extend; on the ground knees bend into the tuck)
		sway * sty.hipSway + hip_rock + shift * 0.3 + sin(t * 2.1) * 0.02 * wig) + fit
	pelvis.x += sty.hipX * (1 - 0.5 * pedal) + 0.10 * aero_a - 0.05 * aero_g - 0.03 * eff   # sprint start: hips stay back over the saddle nose, the chest goes forward instead; forward over the cranks (air stick: hips forward; ground tuck: a touch back)
	pelvis.y += 0.02 * eff                                               # up tall to stamp down
	pelvis.y += sty.hipY * (1 - 0.6 * pedal)
	# the air pose's hip height: crouched in the air (none with the stick forward: legs pushed out), knees tucked up in a
	# spin; reaching for the ground it goes (the legs straighten), and on the ground it is gone at once (air_st)
	var air_y: float = (-0.07 * float(sty.airCrouch) * (1.0 - aero) - 0.05 * smoothstep(0.8, 3.5, absf(_num(p, "airSpin")))) * air_st * (1.0 - clampf(_num(p, "flipExt"), 0.0, 1.0))
	# (2026-11-23, slow motion of a pro off a lip, research/jump: from the last of the face to ~0.3 s after the lip he
	# stands TALL - legs nearly straight, torso upright in the world while the bike points 35-45 deg up, the bars pulled
	# in to the chest - and only then the knees come up into the tuck. The air crouch came at once at take-off: the pop
	# never showed. j_tall = the extension through the lip + the pop just gone (popFx, fades over ~0.35 s))
	var j_tall: float = maxf(j_ext, sm_popfx * air * float(sty.get("jumpExtend", 1.0))) if not old_lp else 0.0
	air_y *= 1.0 - clampf(j_tall, 0.0, 1.0)
	pelvis.y += air_y + 0.10 * sm_popfx * air * (0.0 if old_lp else 1.0)
	# then he pulls the bike up into himself (the physics' air_pull): knees up towards the chest, hips down to the
	# saddle, chest folded forward over the bars, elbows up and out - the bike tucked under him; reaching for the
	# landing it goes again
	sm_tuck += ((0.0 if old_lp else clampf(_num(p, "airPull"), 0.0, 1.0)) * air * (1.0 - clampf(j_tall, 0.0, 1.0)) - sm_tuck) * (1.0 - exp(-10.0 * jh))
	var j_tuck: float = sm_tuck * (1.0 - sm_reach) * float(sty.get("airTuck", 1.0))
	tuck_out = j_tuck   # (Game lifts the drawn bike by TUCK_LIFT x this: the bike comes up to him, his body stays on its arc)
	pelvis.y -= 0.15 * j_tuck
	pelvis.x += 0.03 * j_tuck
	# (a squash is NOT folding over the bars: the hips go back and down behind the saddle and the arms push the bars
	# away, so the bike has room to come up in front of him)
	# (2026-11-23, sized from slow-motion of a pro off a lip, research/jump: wound right down into the transition, then
	# stood fully tall through the lip with the bars pulled to the hips. It was -2 / +6 cm: the jump looked dead)
	# (2026-11-24, video 2 side views, research/jump: on every take he loads the face deep - knees ~90 deg, hips ~15 cm
	# down and back, chest low; squashing, the hips go well back and low and the chest folds down over the bars while the
	# arms push the bike forward through the lip; popping, the legs are dead straight at the edge. BMX_OLD_JUMPPOSE=1)
	if _OLD_JUMPPOSE:
		pelvis.x += -0.06 * j_pre + 0.10 * j_ext - 0.13 * j_sq - 0.07 * j_fold - 0.02 * sm_reach
		pelvis.y += -0.08 * j_pre + 0.13 * j_ext - 0.03 * j_sq - (0.09 if old_lp else 0.13) * j_fold + (0.06 if old_lp else 0.09) * sm_reach
	else:
		pelvis.x += -0.06 * j_pre + 0.10 * j_ext - 0.16 * j_sq - 0.07 * j_fold - 0.02 * sm_reach
		pelvis.y += -0.07 * j_pre + 0.17 * j_ext - 0.12 * j_sq - (0.09 if old_lp else 0.13) * j_fold + (0.06 if old_lp else 0.09) * sm_reach
		# popped off the lip (video 2 slow frames): he stands up BEHIND the steep bike - hips back over the rear wheel and
		# up, torso upright, arms straight out to the bars - for ~half a second before the knees come up into the tuck
		var j_up: float = sm_popfx * air
		pelvis.x -= 0.20 * j_up; pelvis.y += 0.06 * j_up

	# chest
	# (pedalling out of the saddle the chest stays forward over the bars)
	var ang: float = 0.52 - 0.2 * clampf(-bstick, 0.0, 1.0) - float(sty.pedalChest) * pedal + 0.12 * spr + 0.3 * eff + 0.18 * fat +0.15 * (comp / 0.3) + 0.08 * air + sty.lean * (1 - 0.5 * pedal) + 0.32 * aero_a + 0.6 * aero_g
	ang += 0.2 * clampf(-bstick, 0.0, 1.0) * stk_stick   # (the light pull is the tuck, not sitting up)
	ang = lerpf(ang, TUCK_ANG, stk)   # speed tuck: the back near flat
	ang -= FLIP_LEAN * clampf(_num(p, "flipArch"), 0.0, 1.0)   # (a back flip's arch: he lies back, chest out)
	ang += (0.3 if _OLD_JUMPPOSE else 0.12) * j_pre - 0.3 * j_ext + (0.06 if _OLD_JUMPPOSE else 0.38) * j_sq - (0.0 if _OLD_JUMPPOSE else 0.35) * sm_popfx * air + (0.12 if old_lp else -0.22) * sm_popfx * air + 0.28 * j_tuck + 0.42 * j_fold - 0.18 * sm_reach
	# spinning in the air: tall and compact over the bike (chest up, knees in), the head and shoulders lead
	var spin_style: float = smoothstep(0.8, 3.5, absf(_num(p, "airSpin"))) * air * (1.0 - clampf(_num(p, "flipExt"), 0.0, 1.0))   # (a flip hangs long, not compact)
	ang = lerpf(ang, 0.42, 0.7 * spin_style)
	# relaxed (garage showcase, `relax` 0..1): sat up tall, back straighter, chin up - whatever the saved riding pose
	var relax := clampf(_num(p, "relax"), 0.0, 1.0)
	ang = lerpf(ang, 0.22, 0.8 * relax)
	var tall := clampf(_num(p, "tall"), 0.0, 1.0)   # title screen: sat right up, looking out at the horizon
	ang = lerpf(ang, 0.0, tall)
	# breathing: the torso tips a hair about the hips, so the chest rises and falls WITHOUT the torso changing length (lifting the
	# chest straight up stretched and squashed the whole upper body). Quiet and slow at rest (~15 a minute, ~10 mm at the chest),
	# fast and deeper when winded (~55 a minute, ~20 mm); ~8 s to settle after a sprint. How winded = the bike computer's heart
	# rate (72 at rest .. ~175 flat out; builds and recovers slowly by itself), or the sprint stamina running out. Flat out the
	# breaths lock part way to the pedalling (one per whole number of crank turns), which riders tend to do at high effort
	# ("locomotor-respiratory coupling"; from memory, not in the research library). None in the air.
	var wind_tgt: float = clampf(maxf(maxf((_num(p, "hr", 72.0) - 80.0) / 95.0, 1.0 - _num(p, "stamina", 1.0)), 0.6 * _spr_arm), 0.0, 1.0)
	_winded += (wind_tgt - _winded) * (1.0 - exp(-(1.5 if wind_tgt > _winded else 0.08) * minf(dt, 0.1)))
	var br_hz: float = lerpf(0.25, 0.9, _winded)
	var cad_hz: float = _cad_s / 60.0
	if _winded > 0.45 and cad_hz > 0.8:
		var n: float = maxf(1.0, roundf(cad_hz / br_hz))   # crank turns per breath nearest to the natural rate
		br_hz = lerpf(br_hz, cad_hz / n, 0.5 * smoothstep(0.45, 0.8, _winded))
	_breath_ph = fposmod(_breath_ph + dt * TAU * br_hz, TAU)
	# (stopped after a hard effort, foot down: he stands there heaving - deeper breaths, shown best when still - and settles slowly)
	# (only when stopped or nearly: gone by ~14 km/h, so nothing breathes mid-ride)
	var still: float = 1.0 - smoothstep(1.0, 4.0, absf(v))
	var heave: float = 1.0 + 1.2 * _winded * (1.0 - clampf(absf(v) / 4.0, 0.0, 1.0))
	# the inhale of a deep breath (only when winded) also lifts the elbows and shoulders a little, used by the arms below
	_inhale = maxf(0.0, sin(_breath_ph)) * smoothstep(0.25, 0.8, _winded) * still * (1.0 - air) * (0.0 if _NO_BREATH else 1.0)
	# (only the chest tips: `ang` itself also turns the pelvis, which made the hips rock back and forth with every breath)
	var br_ang: float = -sin(_breath_ph) * lerpf(0.022, 0.045, _winded) * heave * still * (1.0 - air) * (0.0 if _NO_BREATH else 1.0)   # rad: less lean = chest up
	var L: float = sty.torso
	var chest := Vector3(
		pelvis.x + sin(ang + br_ang) * L + 0.03 * pedal * (0.5 + 0.5 * bob),
		pelvis.y + cos(ang + br_ang) * L,
		pelvis.z + shift * 0.3 - sway * sty.hipSway - 0.7 * hip_rock + sin(t * 1.7 + 1.0) * 0.02 * wig)   # (shoulders stay steadier than the hips)

	pelvis.z += sty.hipZ
	chest += Vector3(sty.chestFwd, sty.chestUp, sty.chestSide)

	var absorb := _num(p, "absorb")
	# (2026-11-24, overlaid on video 2: on a lip's face he loads it with firm legs - "put force through your feet" - his
	# hips stay ~0.3 m higher than ours, which sank with the physics legs pressed in ~20 cm by a tight transition. On a
	# jump face only FACE_SINK of that sink is drawn)
	if not _OLD_JUMPPOSE and absorb < 0.0: absorb *= 1.0 - (1.0 - FACE_SINK) * clampf(sm_lip, 0.0, 1.0) * (1.0 - air)
	absorb = lerpf(absorb, maxf(absorb, 0.08), j_ext)   # driving through the lip the legs are straight, however hard it presses
	# the crouches don't stack past what a rider gets down to (the lip's crouch + the preload + the legs pressed in by a
	# transition came to 35 cm: sat on the rear tyre with the bars at his chin)
	# (the landing fold counts too: on top of legs already driven right in by a hard landing it put the knees in the bar)
	# (a landing may go deeper: a rider soaking a big hit sinks right down, knees in front of the bars, never on the tyre)
	var deep_c: float = comp + maxf(0.0, -absorb) + 0.09 * j_fold - (0.22 if old_lp else 0.22 + 0.10 * clampf(j_fold * 1.5, 0.0, 1.0))
	if deep_c > 0.0: absorb += deep_c
	pelvis.y += absorb
	chest.y += absorb * 0.9
	if not old_lp: chest.y -= 0.05 * j_fold   # (the arms take their share: elbows bend, the chest drops a bit further than the hips)
	# the legs' bend is the physics' own body on its leg spring: it goes past the drawn body springs (a second soft
	# spring on top of it filtered a landing's dip twice: ~0.2 s late and half as deep)
	# (only a real bend: little bumps still go through the body springs, smoothed as before)
	var by_k: float = 0.0 if old_lp else smoothstep(0.03, 0.10, -absorb)
	_abs_p = absorb * by_k
	_abs_c = absorb * 0.9 * by_k
	# soaking a hit the hips go back as well as down, behind the saddle (the saddle stopped them ~12 cm under the stance:
	# every landing came out the same depth); the chest less, so he folds over the bars a little
	_sink = 0.0
	if not old_lp:
		_sink = clampf(-absorb - 0.04, 0.0, 0.3)
		pelvis.x -= 0.45 * _sink; chest.x -= 0.2 * _sink
	var hs := _num(p, "hipShift")
	# (the physics' forward weight shift is carried by the chest going out over the bars in a ground tuck,
	# not by the hips sliding up to the stem)
	if hs < 0.0: hs *= 1.0 - 0.75 * sm_pre   # a preload sinks between the wheels, it doesn't hang off the back
	pelvis.x += hs * (1.0 - 0.7 * aero_g if hs > 0.0 else 1.0)
	chest.x += hs * 0.6
	# body stick (gamepad right stick): forward = chest low over the bars, back = hips dropped behind the
	# saddle with the arms long (manuals)
	var bs := bstick
	if bs < 0.0: bs *= 1.0 - stk_stick   # (inside the light pull: the tuck below, not the weight-back pose)
	var back_k := clampf(-bs, 0.0, 1.0)
	# the speed tuck: hips back over the rear wheel and down, the chest follows (the back flat: `ang` above)
	pelvis.x -= TUCK_HIP_BACK * stk; pelvis.y -= TUCK_HIP_DOWN * stk
	chest.x -= TUCK_HIP_BACK * stk; chest.y -= TUCK_HIP_DOWN * stk
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
	# (2026-11-24, overlaid on video 2: on a steep dirt-jump lip the bike is 45-60 deg and he stands up near vertical
	# over it. This fade - for flips - cut the levelling right there. On a jump face / just off the lip it starts later)
	var lip_lv: float = 0.0 if _OLD_JUMPPOSE else clampf(maxf(sm_lip * (1.0 - air), sm_popfx * air), 0.0, 1.0)
	pitch0 *= 1.0 - smoothstep(lerpf(0.7, 1.15, lip_lv), lerpf(1.3, 1.6, lip_lv), absf(pitch0))
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
	# (frontUp: the physics' own manual angle. A rock kicking the front up is not a wheelie: without this the rider sat
	# back behind the saddle with long arms on every stone, then snapped forward again)
	if p.has("frontUp"): wh_t *= smoothstep(0.02, 0.1, _num(p, "frontUp"))
	sm_wheelie = move_toward(sm_wheelie, wh_t, 2.5 * minf(dt, 0.1))
	var wheelie: float = sm_wheelie
	var base := pitch0 - wheelie   # the slope part of the bike's pitch
	var pit := base * (0.2 if base > 0 else _num(p, "bodyLevel", 0.85)) + wheelie * 0.75   # most of a wheelie's tilt is taken back
	# the body is its own mass in pitch too: a quick kick of the bike (a rock or a root under one wheel, a curb, a
	# landing rocking it) turns the bike UNDER the rider - arms and legs take it, hips and shoulders hold their line.
	# The body used to follow 80 % of any nose-up pitch at once: over rocks the whole rider rocked back and forth with
	# the frame as one stiff piece. Quick = the bike's pitch against its own slow average (~0.35 s): a slope or a held
	# manual is followed as before, only what changes faster than the body can swing is held back (bumpPitch of it)
	# (2026-11-22) a kick is the bike pitching against the LAND under it (`slope`: the ground without rocks / logs): on a
	# jump face, a roller, any change of grade the bike pitches because the ground does - read as a kick, that leaned
	# the whole body back up to ~20 deg running up every lip. In the air the hold eases out (it used to snap off as
	# the air flag passed a half), and the +-0.4 rad limit is soft
	# (only on the face of a jump - a lip ahead, the ground rising: he rides it centred with the bike. A curb, a pothole,
	# a ledge or a rock is a kick the body holds against, though they are ground too; taking every slope out made those
	# ~10 % rougher in the world)
	var face_k: float = smoothstep(0.1, 0.4, sm_lip) * smoothstep(0.04, 0.15, slope0) if p.has("slope") else 0.0
	var rel_p: float = wrapf(raw_p - slope0 * face_k, -PI, PI)
	if not spring_init: sm_pitch_slow = rel_p
	sm_pitch_slow += wrapf(rel_p - sm_pitch_slow, -PI, PI) * (1.0 - exp(-(3.0 + 30.0 * air) * h0))
	var kick_r := wrapf(rel_p - sm_pitch_slow, -PI, PI)
	var kick: float = 0.4 * tanh(kick_r / 0.4) * (1.0 - air) * (1.0 - smoothstep(0.7, 1.3, absf(raw_p)))
	bump_pitch = kick
	if Env.s("BMX_KICK_PROBE") != "" and absf(kick) > 0.02: print("KICK raw=%.3f slow=%.3f kick=%.3f base=%.3f wheelie=%.3f slope=%.3f air=%.2f" % [raw_p, sm_pitch_slow, kick, base, wheelie, slope0, air])
	# (applied after the body's springs, below: it is the bike turning under a body that stays put, not a move of
	# the body - through the springs it arrived ~60 ms late, out of step with an 80 ms kick, and made it worse)
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
	_face_k = 0.0
	# climbing: hips to the saddle nose, chest low over the bars
	var climb := clampf(slope0, 0, 0.6) * (1.0 - 0.85 * sm_lip)   # (not on the face of a jump: there he stays centred)
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
	# lean the BIKE, not the body: roll the body back toward upright about the pedals.
	# The body is a mass of its own: where it should be (bike lean - counter, in the world) is followed on
	# springs, hips first and the chest after, so a quick lean throws the bike over under the rider and the
	# body follows through and settles (a touch of overshoot) instead of the whole rider snapping rigidly to
	# the new angle. Through a crossover (rolling fast near upright) the legs extend: the rider unweights the
	# bike between turns and sinks into the next one
	var bl := _num(p, "lean") - _num(p, "rockRoll")   # the bike's lean without the pedalling rock
	# (in the air the body stays upright over the centre of mass while the bike is laid right over under it: a tabletop /
	# whip, 2026-11-23. The ground caps (the legs crossing the frame past ~50 deg) open up to AIR_* with the air blend)
	var c_cap: float = lerpf(0.85, AIR_COUNTER, air) if not _OLD_AIRBODY else 0.85
	var roll_t := bl - clampf(_num(p, "counter"), -c_cap, c_cap)
	var hr := minf(dt, 0.05)
	if not roll_init:
		roll_p = roll_t; roll_c = roll_t; roll_pv = 0.0; roll_cv = 0.0; knee_lean = bl; roll_init = true
	# sliders (Rider › Movement): Body follows = how quickly (scales both rates), Swings past = how much it
	# overshoots (0 = settles without, 1 = the default ring, 2 = loose), Legs extend = the crossover unweighting
	var fol: float = clampf(float(sty.get("leanFollow", 1.0)), 0.3, 3.0)
	var swing: float = clampf(float(sty.get("leanSwing", 1.0)), 0.0, 2.0)
	var hw: float = ROLL_HIP_W * fol
	var cw: float = ROLL_CHEST_W * fol
	var hz: float = lerpf(1.0, ROLL_HIP_Z, minf(swing, 1.0)) - 0.2 * maxf(swing - 1.0, 0.0)
	var cz: float = lerpf(1.0, ROLL_CHEST_Z, minf(swing, 1.0)) - 0.2 * maxf(swing - 1.0, 0.0)
	if _EULER_BODY:
		roll_pv += ((roll_t - roll_p) * hw * hw - 2.0 * hz * hw * roll_pv) * hr
		roll_p += roll_pv * hr
		roll_cv += ((roll_t - roll_c) * cw * cw - 2.0 * cz * cw * roll_cv) * hr
		roll_c += roll_cv * hr
	else:   # (exact steps, see spring_exact)
		var rp := spring_exact(roll_p, roll_pv, roll_t, hw * hw, 2.0 * hz * hw, 0.0, hr)
		roll_p = rp.x; roll_pv = rp.y
		var rc := spring_exact(roll_c, roll_cv, roll_t, cw * cw, 2.0 * cz * cw, 0.0, hr)
		roll_c = rc.x; roll_cv = rc.y
	knee_lean += (bl - knee_lean) * (1.0 - exp(-7.0 * hr))
	# corner life (Rider › Movement › Corner life, subtle): leaned over, the rider keeps making small balance
	# corrections (a slow, uneven sway of the body roll, ~1-2 deg), a bump under the leaned bike nudges the body's
	# roll, and the turn's load presses them down into the attack position (knees and elbows soak it up, chest
	# a touch lower and forward), rising again as the turn lets go
	var live: float = clampf(float(sty.get("leanLively", 1.0)), 0.0, 3.0) * (1.0 - air)
	var in_turn: float = smoothstep(0.08, 0.5, absf(bl)) * live
	roll_pv += (0.022 * sin(t * 1.9 + 0.7) + 0.014 * sin(t * 3.3 + 2.1) + 0.008 * sin(t * 5.7)) * in_turn * hw * hw * 0.6 * float(sty.get("leanBalance", 1.0)) * hr
	roll_pv -= _facc * sin(bl) * 0.15 * live * float(sty.get("leanBumps", 1.0)) * hr
	lat_g_s += (clampf(absf(_num(p, "latG")), 0.0, 1.5) - lat_g_s) * (1.0 - exp(-5.0 * hr))
	var sink: float = smoothstep(0.1, 1.0, lat_g_s) * live * float(sty.get("leanLoad", 1.0))
	pelvis.y -= 0.03 * sink
	chest.y -= 0.035 * sink
	chest.x += 0.02 * sink
	var hip_cap: float = lerpf(0.85, AIR_HIP_ROLL, air) if not _OLD_AIRBODY else 0.85
	var ch_cap: float = lerpf(0.95, AIR_COUNTER, air) if not _OLD_AIRBODY else 0.95
	var cr := clampf(bl - roll_p, -hip_cap, hip_cap)   # past ~50 deg the hips swing off the bike and the legs cross the frame (in the air: allowed, the knees go over)
	var cr_c := clampf(bl - roll_c, -ch_cap, ch_cap)
	if _ROLL_PROBE and int(t * 4.0) != int((t - dt) * 4.0): print("ROLLP air=%.2f bike=%.1f counter=%.1f roll_t=%.1f hips=%.1f chest=%.1f cr=%.1f cr_c=%.1f" % [air, rad_to_deg(bl), rad_to_deg(_num(p, "counter")), rad_to_deg(roll_t), rad_to_deg(roll_p), rad_to_deg(roll_c), rad_to_deg(cr), rad_to_deg(cr_c)])
	var unweight: float = ROLL_UNWEIGHT * float(sty.get("leanUnweight", 1.0)) * clampf(absf(roll_pv) / 1.6, 0.0, 1.0) * (1.0 - smoothstep(0.15, 0.6, absf(roll_p))) * (1.0 - air)
	pelvis.y += unweight; chest.y += unweight * 0.8
	# pro flow (Rider › Motion, flowSink): after a quick roll into a lean the rider weights the bike as it settles -
	# hips and chest sink into the new turn (the pump after the unweight), fading over ~0.6 s
	var re := absf(roll_pv)
	flow_e = maxf(re, flow_e - hr * 2.0) if re > flow_e else flow_e + (re - flow_e) * (1.0 - exp(-1.6 * hr))
	var settle: float = clampf(flow_e / 1.6, 0.0, 1.0) * smoothstep(0.15, 0.5, absf(roll_p)) * clampf(1.0 - re / 2.5, 0.0, 1.0) * (1.0 - air)
	var fsink: float = 0.04 * settle * float(sty.get("flowSink", 1.0))
	pelvis.y -= fsink; chest.y -= fsink * 0.9; chest.x += fsink * 0.4
	# (in the air the roll pivots about the chest, not the pedals: the hands stay on the grips and the chest at the bars,
	# the hips and legs swing out under him - knees over to one side - so the torso stands upright in the world over a
	# laid-over bike: a tabletop / whip. Turned about the pedals the chest went ~0.5 m out from the bars, the arm-reach
	# limit pulled it straight back and the rider lay over with the bike. Ground: unchanged)
	var air_piv: float = 0.0 if _OLD_AIRBODY else air
	var pel0 := pelvis
	var ch0 := chest
	if cr != 0.0 or cr_c != 0.0:
		var c := cos(cr)
		var sn := sin(cr)
		var y0 := 0.3
		var dy := pelvis.y - y0
		var dz := pelvis.z
		pelvis.y = y0 + dy * c - dz * sn
		pelvis.z = dy * sn + dz * c
		c = cos(cr_c)
		sn = sin(cr_c)
		dy = chest.y - y0
		dz = chest.z
		chest.y = y0 + dy * c - dz * sn
		chest.z = dy * sn + dz * c
		if air_piv > 0.0:
			# about the chest: the chest stays (a little toward the low side), the torso turns by the chest's roll
			var ty := pel0.y - ch0.y
			var tz := pel0.z - ch0.z
			var ca := cos(cr_c)
			var sa := sin(cr_c)
			var ch_a := ch0 + Vector3(0.0, 0.0, 0.08 * sin(cr_c))
			var pel_a := Vector3(pel0.x, ch_a.y + ty * ca - tz * sa, ch_a.z + ty * sa + tz * ca)
			pelvis = pelvis.lerp(pel_a, air_piv)
			chest = chest.lerp(ch_a, air_piv)
		pelvis.y -= absf(cr) * 0.12 * float(sty.turnLow)
	# (in a whip the bike is yawed under him; his torso keeps facing the flight: its lean turns back against the bike's
	# yaw, AIR_FACE of it, about the bike's up through the hips. The shoulders' own twist (below) does the rest)
	var awh_pos: float = clampf(_num(p, "airWhip"), -1.4, 1.4) * air * (0.0 if _OLD_AIRBODY else AIR_FACE)
	if absf(awh_pos) > 1e-3:
		chest = pelvis + Basis(Vector3.UP, -awh_pos) * (chest - pelvis)
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
		var floor_y: float = float(seat.top) + 0.085 - 0.3 * _sink   # (sinking into a landing the thighs come down onto it)
		if pelvis.y < floor_y:
			pelvis.y += (floor_y - pelvis.y) * over
		if chest.y < pelvis.y + 0.15:
			chest.y = pelvis.y + 0.15
	# standing on the floor (garage Kit tab, `stand` 1): no bike under them. Legs nearly straight with the
	# hips right over the feet, the torso upright (a touch forward), arms hanging at the sides
	var standing := _num(p, "stand") > 0.5
	if standing:
		var fl: Vector3 = p.get("footL", Vector3.ZERO)
		var fr: Vector3 = p.get("footR", Vector3.ZERO)
		var ank_x: float = (fl.x + fr.x) * 0.5 - 0.04 + float(sty.heelFwd)
		var ank_y: float = (fl.y + fr.y) * 0.5 + 0.12 + float(sty.heelUp)
		pelvis = Vector3(ank_x + 0.01, ank_y + (L_THIGH + L_SHIN) * 0.985 + 0.02 + absorb, (fl.z + fr.z) * 0.5)
		chest = pelvis + Vector3(sin(0.05) * sty.torso, cos(0.05) * sty.torso, 0.0)
		ang = 0.05
		var arm := L_UARM + L_FARM
		p = p.duplicate()
		for sd in [-1.0, 1.0]:
			var sh := chest + Vector3(-0.03, -0.04, sd * sty.shoulders)
			# hands by the thighs, just in front of the hip line: elbows soft, pointing back
			p["handL" if sd < 0 else "handR"] = sh + Vector3(0.07, -arm * 0.95, sd * 0.07)
	# the target keeps every limit before the springs follow it (docs/research/rider_animation.md, point 4)
	# (2026-11-24, measured off video 2 overlaid on ours, bike frame from the crank centre: on the face of a dirt jump,
	# bike 37-48 deg up, his hips are right over the cranks ~0.77 m up and his torso is upright IN THE WORLD - in the
	# bike's frame it leans forward as far as the bike is tipped back - so his chest is well above the bars (ours sat at
	# bar height, pushed back 0.3 m by the bar limit). On a face / just popped off the lip the body is put there, blended
	# by FACE_POSE; a squash keeps its own low pose)
	if lip_lv > 0.0 and p.has("footL"):
		var bbp: Vector3 = (p.get("footL", Vector3.ZERO) + p.get("footR", Vector3.ZERO)) * 0.5
		# (dynamic, the user: the stand-up-over-the-bike is for a steep bike - a dirt-jump lip taken slow. On a flatter, fast
		# lip he stays in his forward attack position: it fades with the bike's pitch, none under ~20 deg)
		var steep_k: float = smoothstep(0.25, 0.55, clampf(raw_p, 0.0, 1.2)) * (1.0 - smoothstep(6.5, 9.5, absf(v)))
		var fk: float = FACE_POSE * smoothstep(0.1, 0.45, lip_lv) * (1.0 - clampf(j_sq * 1.5, 0.0, 1.0)) * steep_k
		_face_k = fk
		# (the hips' place is set in the WORLD, from the crank centre: with the bike steeper, a spot fixed on the bike sank
		# back and down)
		var pp: float = clampf(raw_p, 0.0, 1.2)
		var fhw := Vector2(FACE_HIP.x, FACE_HIP.y - 0.05 * j_pre + 0.06 * sm_popfx * air)
		var ph_t := Vector2(bbp.x + fhw.x * cos(pp) + fhw.y * sin(pp), bbp.y - fhw.x * sin(pp) + fhw.y * cos(pp))
		var ta: float = pp + FACE_TORSO - FLIP_LEAN * clampf(_num(p, "flipArch"), 0.0, 1.0)   # (throwing a back flip he lies back)
		var ch_t := ph_t + Vector2(sin(ta), cos(ta)) * float(sty.torso)
		pelvis.x = lerpf(pelvis.x, ph_t.x, fk); pelvis.y = lerpf(pelvis.y, ph_t.y, fk)
		chest.x = lerpf(chest.x, ch_t.x, fk); chest.y = lerpf(chest.y, ch_t.y, fk)
	if Env.s("BMX_JPOSE") != "" and sm_lip > 0.3: print("JPOSE pre pel=(%.2f,%.2f) ch=(%.2f,%.2f) lip=%.2f popfx=%.2f air=%.1f absorb=%.3f comp=%.3f pre=%.2f pitch=%.2f" % [pelvis.x, pelvis.y, chest.x, chest.y, sm_lip, sm_popfx, air, _num(p, "absorb"), _num(p, "compress"), sm_pre, _num(p, "pitch")])   # tests
	if Env.s("BMX_OLD_LIMITS") == "":
		var tgt := _constrain(pelvis, chest, p, sty, standing, aero, false)
		pelvis = tgt[0]; chest = tgt[1]
		if Env.s("BMX_JPOSE") != "" and sm_lip > 0.3: print("JPOSE lim pel=(%.2f,%.2f) ch=(%.2f,%.2f)" % [pelvis.x, pelvis.y, chest.x, chest.y])   # tests
	# critically-damped-ish springs -> follow-through
	if not spring_init:
		pel_s = pelvis
		ch_s = chest
		if not _EULER_BODY: pel_s.y -= _abs_p; ch_s.y -= _abs_c
		spring_init = true
	var h := minf(dt, 0.05)
	# the body is a mass on springy legs and arms: when the bike is kicked up by a bump (or drops) the body
	# lags behind and then springs back, so the knees and elbows soak it up. The frame's up / down
	# acceleration pushes the body the other way (Bump bounce); Body bounce sets how long it rings on
	var bump_k: float = float(sty.get("bumpAbsorb", 2.0)) * (1.0 - air)
	# what the legs feel: half the frame's motion, half the wheels' (the bumps the suspension passes on)
	# (frameY: the frame's height from the physics, without the drawn bike's tyre-unclip lift - that lift is a
	# correction of the picture, and as "bumps" it threw the body about over every rock)
	var fy0 := _num(p, "frameY", NAN)
	var gy := (fy0 if not is_nan(fy0) else (global_position.y if is_inside_tree() else 0.0)) * 0.85 + _num(p, "wheelY") * 0.15
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
	# up / down the legs are a softer spring (~1.5 Hz): the body rides bumps and rebounds
	var ky: float = clampf(float(sty.hipSteady), 20.0, 600.0)   # Hips steady: how stiffly the legs hold the hips
	# (exact steps: the same body at any frame rate; BMX_EULER_BODY=1 = the old Euler steps, for comparison)
	if _EULER_BODY:
		var dp := 2 * sqrt(260.0) * zeta
		pel_v += ((pelvis - pel_s) * 260.0 - pel_v * dp) * h
		pel_v.y += ((pelvis.y - pel_s.y) * (ky - 260.0) - pel_v.y * 2.0 * (sqrt(ky) - sqrt(260.0)) * zeta) * h
		pel_v.y -= _facc * bump_k * h
		pel_s += pel_v * h
	else:
		pelvis.y -= _abs_p
		pel_s = _spring3(pel_s, pel_v, pelvis, 260.0, ky, zeta, -_facc * bump_k, h)
		pel_v = _spring3_v
	# the legs only bend / straighten so far
	pel_s.y = clampf(pel_s.y, pelvis.y - 0.14, pelvis.y + 0.05)
	if not _EULER_BODY: pelvis.y += _abs_p; pel_s.y += _abs_p
	if air < 0.5:   # tests (BMX_CLIP_PROBE): how far the body moves on its legs while riding
		bounce_stats[0] += (pel_s.y - pelvis.y) * (pel_s.y - pelvis.y); bounce_stats[1] += 1
		bounce_stats[2] = maxf(bounce_stats[2], absf(pel_s.y - pelvis.y)); bounce_stats[3] += _facc * _facc
	pelvis = pel_s
	if not _EULER_BODY: pel_s.y -= _abs_p   # (the spring's own state stays without the legs' bend)
	if _EULER_BODY:
		var dc := 2 * sqrt(200.0) * zeta
		ch_v += ((chest - ch_s) * 200.0 - ch_v * dc) * h
		ch_v.y += ((chest.y - ch_s.y) * (ky - 200.0) - ch_v.y * 2.0 * (sqrt(ky) - sqrt(200.0)) * zeta) * h
		ch_v.y -= _facc * bump_k * 0.85 * h
		ch_s += ch_v * h
	else:
		chest.y -= _abs_c
		ch_s = _spring3(ch_s, ch_v, chest, 200.0, ky * CHEST_KY, zeta, -_facc * bump_k * 0.85 * CHEST_PUSH, h)
		ch_v = _spring3_v
	ch_s.y = clampf(ch_s.y, chest.y - 0.14, chest.y + 0.06)
	if not _EULER_BODY: chest.y += _abs_c; ch_s.y += _abs_c
	chest = ch_s
	if not _EULER_BODY: ch_s.y -= _abs_c
	# the springs lag their target, so what they made can still break a limit (a quick lean swap, a landing): correct
	# it and write that back into the springs - the body is held at the limit and its speed into it is gone (position
	# based dynamics), instead of the spring pushing in again every frame and being pulled back out (a fight that
	# shook the torso). The quick view-only turns below (pedalling rock, pitch kicks) still get a last check after them
	if Env.s("BMX_OLD_LIMITS") == "":
		var sp := _constrain(pelvis, chest, p, sty, standing, aero, false)
		var dpel: Vector3 = sp[0] - pelvis
		var dch: Vector3 = sp[1] - chest
		if dpel.length_squared() > 1e-10:
			var n := dpel.normalized()
			pel_v -= n * minf(0.0, pel_v.dot(n))   # (only the speed into the limit)
			pel_s += dpel
		if dch.length_squared() > 1e-10:
			var n := dch.normalized()
			ch_v -= n * minf(0.0, ch_v.dot(n))
			ch_s += dch
		pelvis = pel_s; chest = ch_s
		if not _EULER_BODY: pelvis.y += _abs_p; chest.y += _abs_c
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
	# quick pitch kicks: the bike turns under the body (see bump_pitch above)
	var kp: float = bump_pitch * clampf(_num(p, "bumpPitch", 0.85), 0.0, 1.0)
	if kp != 0.0:
		var kc := cos(kp)
		var ks := sin(kp)
		var kdy := pelvis.y - 0.3
		var kdx := pelvis.x
		pelvis.x = kdx * kc + kdy * ks
		pelvis.y = 0.3 - kdx * ks + kdy * kc
		kdy = chest.y - 0.3
		kdx = chest.x
		chest.x = kdx * kc + kdy * ks
		chest.y = 0.3 - kdx * ks + kdy * kc
	# the corrections again on what the springs made (a safety net: the target already keeps them)
	var cpc := _constrain(pelvis, chest, p, sty, standing, aero, true)
	pelvis = cpc[0]; chest = cpc[1]
	# ---- Pose Lab keys (PoseKeys, style only): offsets added on top of the finished pose. The hips carry the torso (and so
	# the head and shoulders); a torso tilt turns the chest about the hips and the head / shoulders go with it; the arms
	# and legs follow by IK (hands / feet stay on the grips / pedals). Then the limits run once more, so a key can't
	# push him through the bars / out of reach
	var pk: Dictionary = p.get("pk", {}) as Dictionary
	_pk_tyaw = float(pk.get("torso_yaw", 0.0)); _pk_hp = float(pk.get("head_pitch", 0.0)); _pk_hy = float(pk.get("head_yaw", 0.0))
	_pk_eo = float(pk.get("elbows_out", 0.0)); _pk_ko = float(pk.get("knees_out", 0.0))
	_pk_wb = float(pk.get("wrist_bend", 0.0)); _pk_wt = float(pk.get("wrist_turn", 0.0))
	_pk_grip = float(pk.get("grip", 0.0)); _pk_lp = float(pk.get("lever_pull", 0.0))
	if not pk.is_empty():
		var hipd := Vector3(float(pk.get("hip_x", 0.0)), float(pk.get("hip_y", 0.0)), float(pk.get("hip_z", 0.0)))
		pelvis += hipd
		chest += hipd
		var tv: Vector3 = chest - pelvis
		tv = Basis(Vector3(0, 0, 1), -float(pk.get("torso_pitch", 0.0))) * tv
		tv = Basis(Vector3(1, 0, 0), float(pk.get("torso_roll", 0.0))) * tv
		chest = pelvis + tv
		var cpk := _constrain(pelvis, chest, p, sty, standing, aero, true)
		pelvis = cpk[0]; chest = cpk[1]
	# ---- motion cap: hips and chest move at most TORSO_VMAX relative to the bike. Whatever drives them (a limit
	# above snapping on, a spike in an input, sliders stacking up), the torso can't jump between frames; real riding
	# moves it well under this. Hands and feet are fitted after this, so they stay on the grips and pedals.
	# A big jump (> 0.4 m: a reset, a respawn) is taken at once
	var vcap: float = _num(p, "torsoVmax", TORSO_VMAX) * clampf(dt, 0.0, 0.05)   # (Ride › Smoothing, passed in by Game)
	if _cap_ok and vcap > 0.0:
		for which in 2:
			var cur: Vector3 = pelvis if which == 0 else chest
			var prev: Vector3 = _cap_pel if which == 0 else _cap_ch
			var dmv := cur - prev
			var dl := dmv.length()
			if dl > vcap and dl < 0.4:
				cur = prev + dmv / dl * vcap
				if which == 0: pelvis = cur
				else: chest = cur
	_cap_pel = pelvis; _cap_ch = chest; _cap_ok = true
	if Env.s("BMX_JPOSE") != "" and sm_lip > 0.3:   # tests: bike frame, from the crank centre
		var bbj: Vector3 = (p.get("footL", Vector3.ZERO) + p.get("footR", Vector3.ZERO)) * 0.5
		var hm: Vector3 = (p.get("handL", Vector3.ZERO) + p.get("handR", Vector3.ZERO)) * 0.5
		print("JPOSE end pitch=%.2f hips=(%.2f,%.2f) chest=(%.2f,%.2f) hands=(%.2f,%.2f)" % [_num(p, "pitch"), pelvis.x - bbj.x, pelvis.y - bbj.y, chest.x - bbj.x, chest.y - bbj.y, hm.x - bbj.x, hm.y - bbj.y])
	if _POSE_PROBE: _pp_mark(8, pelvis, chest)
	# (2026-11-23, user: "the bike is on rails in the air, only the rider moves") in the air the shared centre of mass
	# flies the arc; the bike is ~1/6 of the weight, so a move of the hips against the bike (the tuck, standing tall,
	# the stick pushing the bike away) is mostly the BIKE moving. body_off = the hips against where they were at
	# take-off; Game moves the drawn bike AIR_SHARE of it the other way (the rider rides on the bike, so his body only
	# moves the rest). On the ground it eases back to 0 (landing)
	if air > 0.5 and _num(p, "inAir") > 0.5:
		if not _air_ref_ok: _air_ref = Vector2(pelvis.x, pelvis.y); _air_ref_ok = true
		body_off = Vector2(pelvis.x, pelvis.y) - _air_ref
	else:
		_air_ref_ok = false
		body_off = body_off.move_toward(Vector2.ZERO, 1.5 * minf(dt, 0.1))
	# torso from pelvis to chest
	var hip := Vector3(pelvis.x, pelvis.y + 0.02, pelvis.z)
	var tw_axis := (chest - hip).normalized()
	# spinning in the air: shoulders lead the bike round (the head turns via yawRate below)
	# turning on the ground: shoulders and hips steer into the turn, the inside hip drops
	var turn := clampf(_num(p, "turn"), -3.0, 3.0)
	sm_turn += (turn - sm_turn) * (1.0 - exp(-8.0 * minf(dt, 0.1)))
	# a side lean in the air (tabletop): the hips turn with the bike, the shoulders turn back against it
	var tab: float = clampf(_num(p, "bodyLat"), -1.0, 1.0) * air
	# pro flow (flowLead): the shoulders lead into the turn the body is rolling towards (the target roll + the roll
	# under way), ahead of the hips and the bike's actual turn - the upper body winds up and the bike follows
	var lead: float = clampf(0.3 * clampf(_num(p, "lean") - _num(p, "rockRoll") - clampf(_num(p, "counter"), -0.85, 0.85), -0.9, 0.9) + 0.06 * roll_pv, -0.35, 0.35) * float(sty.get("flowLead", 1.0)) * (1.0 - air)
	# an air whip: the bike is twisted under the body (airWhip = how far, rad, in bike space). The body is drawn in the
	# bike's frame, so it turns back against it - the hips half way (they're on the saddle / pedals), the shoulders
	# nearly all the way: the rider keeps facing where they fly while the bike hangs out sideways
	var awhip: float = clampf(_num(p, "airWhip"), -1.4, 1.4) * air
	var tw_base: float = _pk_tyaw + float(sty.twist) + clampf(_num(p, "airSpin") * 0.07 + sm_turn * 0.13 * float(sty.turnTwist) + lead, -0.6, 0.6) + _num(p, "flipTwist")   # (a flip: the shoulders turn to spot the landing)
	var tw_air: float = -0.22 * tab - 0.85 * awhip
	var tw := Basis(tw_axis, tw_base + tw_air)
	# (2026-11-23, user: "the shoulder pops off") the shoulders' twist (a whip, a tabletop) is held to what both arms can
	# still reach the grips from: the arm-reach limit above works with untwisted shoulders, so a big twist left a shoulder
	# out of reach and the joint came apart. Never more twist than leaves both hands on (or within 1 % of) the grips
	var hl0 = p.get("handL"); var hr0 = p.get("handR")
	if absf(tw_air) > 1e-3 and hl0 is Vector3 and hr0 is Vector3 and not standing:
		var reach_max := (L_UARM + L_FARM) * 0.99
		for it in 6:
			var ok := true
			for sd2 in [[-1.0, hl0], [1.0, hr0]]:
				var so2 := Vector3(-0.03 + sty.shoulderFwd, -0.04 + sty.shoulderUp, float(sd2[0]) * sty.shoulders)
				var sh2: Vector3 = (chest + tw * so2).lerp(shoulder_at(pelvis, chest, tw, so2), air)
				if sh2.distance_to(sd2[1]) > reach_max: ok = false
			if ok: break
			tw_air *= 0.7
			tw = Basis(tw_axis, tw_base + tw_air)
	# pelvis: turn (yaw about up), roll (one hip drops, about forward), tilt (about the hip line)
	var pel_b := Basis(Vector3.UP, float(sty.pelvisYaw) + clampf(sm_turn * 0.07 * float(sty.turnHips), -0.4, 0.4) + 0.3 * tab - 0.4 * awhip) * Basis(Vector3.RIGHT, float(sty.pelvisRoll) - clampf(sm_turn * 0.04 * float(sty.turnHips), -0.25, 0.25) + hip_tilt)
	# (a straight back on a jump face / popped, video 2: the pelvis turns with the torso as it really stands, not 30 % of
	# the intended lean - the lower back bowed where the two met)
	var t_act: float = atan2(chest.x - pelvis.x, maxf(0.05, chest.y - pelvis.y))
	var p_tilt: float = lerpf(ang * 0.3, t_act * 0.85, _face_k)
	var pel_full := pel_b * Basis(Vector3.BACK, -p_tilt - float(sty.pelvisTilt))
	hip = pelvis + pel_full.y * Belt.HEM_Y   # the jersey's hem: inside the belt, level with it
	# pro flow (flowBend): the hips go over first and the chest follows, so through a lean change the spine curves
	# (a C bowed away from the way the chest still hangs) instead of moving as one stiff stick
	var bend: float = clampf((roll_c - roll_p) * 0.6, -0.2, 0.2) * float(sty.get("flowBend", 1.0)) * (1.0 - air)
	set_spine(hip, chest, pel_b * Vector3(0, 0, 1), tw * Vector3(0, 0, 1),
		float(sty.spineCurve) * (1.0 - 0.7 * relax) * (1.0 - _face_k) - FLIP_ARCH * clampf(_num(p, "flipArch"), 0.0, 1.0), float(sty.spineSide) + bend, float(sty.spineLow), pel_full)
	pelvis_mesh.transform = Transform3D(pel_full, pelvis)

	# neck / head
	var neck := chest
	var head_p := Vector3(neck.x + 0.05 + sty.lookAhead + 0.04 * aero + TUCK_HEAD.x * speed_tuck_k, neck.y + 0.2 + sty.neck + TUCK_HEAD.y * speed_tuck_k, neck.z)   # (forward: chin over the bars)
	# head stabilisation (see _hp_s): how much, and what the head follows
	var steady: float = clampf(float(sty.get("headSteady", 1.0)), 0.0, 2.0) * (0.0 if standing else 1.0)
	var flip_k: float = 1.0 - smoothstep(0.7, 1.3, absf(raw_p))   # mid-flip the head goes round with the body
	var hdt := clampf(dt, 0.0, 0.1)
	if not _hp_init:
		_hp_s = raw_p; _hp_v = 0.0; _yr_s = _num(p, "yawRate"); _yr_v = 0.0; _hy = 0.0
		_neck_d = Vector3.ZERO; _neck_v = Vector3.ZERO; _hp_init = true
	var hps := crit_spring(_hp_s, _hp_v, _hp_s + wrapf(raw_p - _hp_s, -PI, PI), HEAD_PITCH_HL, hdt)   # (goal unwrapped)
	_hp_s = wrapf(hps.x, -PI, PI); _hp_v = hps.y
	if absf(wrapf(raw_p - _hp_s, -PI, PI)) > 0.9: _hp_s = raw_p; _hp_v = 0.0   # (a flip / reset: catch up at once)
	var head_kick: float = clampf(wrapf(raw_p - _hp_s, -PI, PI), -0.45, 0.45) * flip_k * steady
	# quick yaw twitches: the bike's yaw rate minus its slow average, held against, let go again over HEAD_YAW_HL
	var yr := _num(p, "yawRate")
	var yrs := crit_spring(_yr_s, _yr_v, yr, HEAD_YAW_HL, hdt)
	_yr_s = yrs.x; _yr_v = yrs.y
	_hy -= (yr - _yr_s) * hdt
	_hy *= pow(0.5, hdt / HEAD_YAW_HL)
	_hy = clampf(_hy, -0.3, 0.3)
	var head_yaw_hold: float = _hy * steady * (1.0 - air)
	# the neck: the head rides a short spring on the chest, the frame's up / down kicks press it the other way (a free
	# mass in the bike's frame), so it lags the chest a little more than the chest lags the bike
	if hdt > 0.0:
		var nsub := int(ceil(hdt * 240.0))
		var nh := hdt / nsub
		for _i in nsub:
			_neck_v += (-_neck_d * NECK_W * NECK_W - _neck_v * 2.0 * NECK_Z * NECK_W) * nh
			_neck_v.y -= _facc * (1.0 - air) * nh
			_neck_d += _neck_v * nh
		_neck_d = _neck_d.clamp(-NECK_MAX, NECK_MAX)
	head_p += _neck_d * minf(steady, 1.0)
	J[0] = head_p
	J[1] = chest
	J[2] = pelvis
	# (+ the eyes lead into the turn with the shoulders, flowLead)
	var yaw: float = clampf((_num(p, "steer") * 1.2 + _num(p, "yawRate") * 0.15) * sty.headTurn + lead * 0.8, -0.8, 0.8) + sty.headYaw + _num(p, "lookYaw") - 0.95 * awhip + head_yaw_hold + _pk_hy
	# (+ the pedalling rock taken back out: the bike rocks under a level head)
	var rx: float = (_num(p, "headRoll") if p.get("headRoll") != null else _num(p, "lean") * 0.6) + sty.headRoll + _num(p, "rockRoll") * minf(steady, 1.0)
	var rz: float = -0.12 * (ang - 0.72) + 0.04 * sin(t * 3.3) * wig - sty.headTilt * (1.0 - 0.6 * relax) + 0.12 * tall + _num(p, "lookPitch") - head_kick - _pk_hp
	head.transform = Transform3D(GEAR.euler_xyz(rx, yaw, rz), head_p)
	_pose_neck()

	var right := Vector3(0, 0, 1)
	var max_turn := BEND_RATE * minf(dt, 0.1) if dt > 0.0 else PI
	# ankling: the foot pitches about the pedal axle (+ = toes up / heel down). Pedalling it swings with the stroke
	# (heel lowest just past the front, toes down at the back); standing hard on the pedals the toes point down more;
	# coasting in the attack position the heels drop (the DH stance), deeper when the legs soak a hit or reach for a
	# landing. The ankle (the leg's IK end) turns with the foot
	var bb := Vector2.ZERO
	var fL0 = p.get("footL"); var fR0 = p.get("footR")
	if fL0 is Vector3 and fR0 is Vector3: bb = Vector2((fL0.x + fR0.x) * 0.5, (fL0.y + fR0.y) * 0.5)
	pedal_top = clampf(_num(p, "pedalTop", 0.017), 0.0, 0.05)
	var ank_k: float = clampf(float(sty.get("ankling", 1.0)), 0.0, 2.5) * (0.0 if standing else 1.0)
	var heels: float = clampf(float(sty.get("heelsDown", 1.0)), 0.0, 2.5) * (0.0 if standing else 1.0)
	# (sprinting: more ankle swing, the feet work the whole stroke and pull up through recovery - Gregor 2000: competitive riders
	# keep pulling up on the pedal for sprints and climbs)
	var ank_swing: float = ANKLE_SWING * pedal * (1.0 - 0.7 * air) * ank_k * (1.0 + 0.5 * _spr_arm)
	var ank_bias: float = -0.07 * spr * pedal * ank_k \
		+ heels * (0.12 * stand * (1.0 - pedal) * (1.0 - air) + 0.15 * j_fold + 0.25 * clampf(comp, 0.0, 0.3) + 0.06 * sm_reach)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var foot: Vector3 = p.get("footL" if i == 0 else "footR", Vector3.ZERO)
		foot.z += side * float(sty.footSlide)   # slide the shoe outwards along the pedal axle
		var hand: Vector3 = p.get("handL" if i == 0 else "handR", Vector3.ZERO)
		# leg
		var hp: Vector3 = pelvis + pel_b * Vector3(0, -0.02, side * (0.11 + sty.stance))
		var phi := atan2(foot.y - bb.y, foot.x - bb.x)   # where on the stroke (0 = front, + up)
		var toe_up: float = clampf(ank_swing * cos(phi + ANKLE_PHASE) + ank_bias, -0.35, 0.35)
		# the shoe on its pedal: the ball of the foot (shoe x = BALL_X) over the axle, the sole resting on the pedal's top
		# (pedalTop above the axle), both turned by the foot's pitch about the axle (Game / the garage turn the pedal with
		# it: foot_pitch). The ankle hangs off the shoe. Standing on the floor (no pedal): the old placement
		var f_pitch: float = float(sty.footAngle) + toe_up
		foot_pitch[i] = f_pitch
		var pb := Basis(Vector3.BACK, f_pitch)
		var sb := Basis(Vector3.UP, -side * float(sty.footOut)) * pb
		var shoe_o: Vector3 = foot + Vector3(0.0, 0.03, 0.0) if standing \
			else foot + pb.y * pedal_top - sb.x * BALL_X
		var ankle: Vector3 = shoe_o + sb * Vector3(-0.04 + sty.heelFwd, ANKLE_UP + sty.heelUp, 0.0) if not standing \
			else Vector3(foot.x - 0.04 + sty.heelFwd, foot.y + 0.12 + sty.heelUp, foot.z)
		# turning: the inside knee opens out toward the turn, the outside leg drives down on its pedal
		var inside: float = clampf(-side * knee_lean * 1.6, 0.0, 0.9) * float(sty.kneeOpen) * (1.0 - air)
		var pole_l: Vector3 = (poles_leg[i] + Vector3(0, 0, side * (inside + _pk_ko))).normalized()
		# sprint knee lift: the foot pulling up through the top of the stroke brings that knee up and forward
		if _spr_arm > 0.01 and not standing and air < 0.3:
			pole_l = (pole_l + Vector3(0.25, 0.7, 0.0) * (_spr_arm * pow(clampf(sin(phi), 0.0, 1.0), 2.0) * lerpf(1.0, 0.6, cad_k))).normalized()
		var ik := limb_ik(hp, ankle, L_THIGH, L_SHIN, pole_l, Vector3.UP, KNEE_MIN, KNEE_MAX, _bd_prev[i], max_turn)
		_bd_prev[i] = ik[2]
		var ik_raw: Vector3 = ik[0]
		ik[0] = _knee_clear(hp, ankle, ik[0], side)
		# knees never into the chest / belly: folded right down they go out round it
		ik[0] = _swing_clear(hp, ik[1], ik[0], side, [pelvis.lerp(chest, 0.35), chest], LIMB_TORSO)
		# (in the air the knees come up over the top tube in a tabletop / whip: never through the handlebar)
		var hL = p.get("handL"); var hR = p.get("handR")
		if air > 0.3 and hL is Vector3 and hR is Vector3 and not _OLD_AIRBODY:
			ik[0] = _swing_clear(hp, ik[1], ik[0], side, [hL, hR], LIMB_BAR)
		if knee_dbg.size() < 40 and _KNEE_PROBE and knee[i].position.distance_to(ik[0]) > 0.08:
			knee_dbg.append([i, snappedf(_num(p, "pitch"), 0.01), knee[i].position.snapped(Vector3.ONE * 0.01), hp.snapped(Vector3.ONE * 0.01), ankle.snapped(Vector3.ONE * 0.01), ik_raw.snapped(Vector3.ONE * 0.01), (ik[0] as Vector3).snapped(Vector3.ONE * 0.01)])
		set_limb(thigh[i], hp, ik[0])
		set_limb(shin[i], ik[0], ik[1])
		knee[i].position = ik[0]
		knee_pad[i].pose(hp, ik[0], ik[0], ik[1], pole_l)
		# out of reach: the foot stays at the end of the leg (limbs never stretch)
		shoe_o += ik[1] - ankle
		shoe[i].position = shoe_o
		shoe[i].basis = sb
		J[9 + i * 3] = hp
		J[10 + i * 3] = ik[0]
		J[11 + i * 3] = shoe_o + Vector3(0.0, 0.05, 0.0)
		# arm
		var sh_off := Vector3(-0.03 + sty.shoulderFwd, -0.04 + sty.shoulderUp, side * sty.shoulders)
		var shp: Vector3 = chest + tw * sh_off
		# sprint arm pull (Stone & Hull 1993: the arms pull on the bars during the leg's power stroke, push on the upstroke,
		# and the peak comes late in the stroke): the shoulder on the pushing side is drawn forward and down toward the
		# grip, so that arm bends and the bar is hauled in; the other arm eases. Flip `side` if the wrong arm pulls.
		if _spr_arm > 0.01 and not standing and air < 0.3:
			var pull: float = pow(clampf(sin(crank - SPR_LAG) * side, 0.0, 1.0), 2.0) * _spr_arm * float(sty.sway) * lerpf(1.0, 0.6, cad_k)
			shp += Vector3(0.035 * pull, -0.02 * pull, 0.0)
		if not _OLD_AIRBODY and air > 0.0: shp = shp.lerp(shoulder_at(hip, chest, tw, sh_off), air)   # (in the air: on the torso's frame)
		shoulder_sph[i].position = shp
		# hand nearly on the elbow's pole line (deep turns, arms up in the air): elbow out and down
		var pole_a: Vector3 = poles_arm[i]
		if aero > 0.01: pole_a = pole_a.lerp(Vector3(-0.15, 0.15, side * 1.0).normalized(), 0.7 * aero).normalized()   # elbows up and out
		if back_k > 0.01: pole_a = pole_a.lerp(Vector3(-0.35, -0.85, side * 0.3).normalized(), 0.5 * back_k).normalized()
		# sprinting: elbows go wide and up, pulling the bars against each pedal stroke (a sprinter's leverage;
		# Gregor 2000 / Millet 2002: standing sprints are 25-30 % more powerful, the arms pull to counter the push)
		# (eased in and out; spinning fast the elbows tuck in a little and drop a touch: a quicker, tighter sprint pose)
		if _spr_arm > 0.01 and not standing and air < 0.3:
			var wide := Vector3(-0.1, 0.05, side * 1.0).normalized().lerp(Vector3(-0.25, -0.15, side * 0.7).normalized(), 0.8 * cad_k).normalized()
			pole_a = pole_a.lerp(wide, 0.85 * _spr_arm * (1.0 - 0.4 * fat)).normalized()
		if _inhale > 0.01 and not standing:
			# a deep breath is mostly rib flare: the ribcage widens, so the shoulders and elbows spread out a touch (not up)
			pole_a = pole_a.lerp(Vector3(pole_a.x, pole_a.y * 0.5, side * 1.1).normalized(), 0.12 * _inhale).normalized()
			shp.z += side * 0.008 * _inhale
			shp.y += 0.002 * _inhale
			shoulder_sph[i].position = shp   # (the shoulder ball goes with it: the arm's IK starts here)
		if standing: pole_a = Vector3(-1.0, 0.0, side * 0.25).normalized()   # arms hanging: elbows point back
		if _pk_eo != 0.0: pole_a = (pole_a + Vector3(0, 0, side * _pk_eo)).normalized()   # (Pose Lab: elbows out / in)
		var ika := limb_ik(shp, hand, L_UARM, L_FARM, pole_a, Vector3(0, -0.5, side), ELBOW_MIN, ELBOW_MAX, _bd_prev[2 + i], max_turn)
		_bd_prev[2 + i] = ika[2]
		# arms never through the leg on their side (a deep lean, braking hard into a turn): the elbow goes out round it
		ika[0] = _swing_clear(shp, ika[1], ika[0], side, [hp.lerp(ik[0], 0.3), ik[0], ik[0], ik[1]], LIMB_LIMB)
		# (... nor through the OTHER leg, which comes over to this side when the hips swing out in the air; last frame's)
		if air > 0.3 and not _OLD_AIRBODY and J.size() >= 15:
			var o := 1 - i
			ika[0] = _swing_clear(shp, ika[1], ika[0], side, [J[9 + o * 3].lerp(J[10 + o * 3], 0.3), J[10 + o * 3], J[10 + o * 3], J[11 + o * 3]], LIMB_LIMB)
		set_limb(upper_arm[i], shp, ika[0])
		elbow[i].position = ika[0]
		hand = ika[1]   # out of reach: the hand stays at the end of the arm
		glove[i].position = hand
		var gx_v = p.get("gripX_L" if i == 0 else "gripX_R")
		var gz_v = p.get("gripZ")
		if standing or not (gx_v is Vector3 and gz_v is Vector3):
			orient_hand(glove[i], ika[0], hand, right)
		else:   # on the bike: the hand follows the grip (steering turns it with the bar); Pose Lab / style offsets on top
			orient_grip(glove[i], ika[0], hand, gx_v, gz_v, float(sty.get("wristBend", WRIST_BEND)) + _pk_wb, _pk_wt * side)
		if sty.wristRoll != 0.0:
			glove[i].rotate_object_local(Vector3.RIGHT, side * float(sty.wristRoll))
		if sty.get("palmIn", 0.0) != 0.0:   # mirrored per hand (the hero shot: arms hanging, both palms to the thighs)
			glove[i].rotate_object_local(Vector3.RIGHT, float(sty.palmIn) * side * (float(Env.s("BMX_PALMSIDE")) if Env.s("BMX_PALMSIDE") != "" else 1.0))
		set_limb(fore_arm[i], ika[0], _wrist(i, ika[0]))
		_curl_to(i, GloveFingers.RELAXED if standing else 1.0, dt * 5.0)   # on the bike: wrapped round the grip
		_pose_fingers(i, standing, dt, p, sty)
		J[3 + i * 3] = shp
		J[4 + i * 3] = ika[0]
		J[5 + i * 3] = hand
		if limb_probe:
			_probe_limb("elbow%d" % i, shp, ika[0], hand, dt, air)
			_probe_limb("knee%d" % i, hp, ik[0], ik[1], dt, air)
	_sync_skeleton(J)
	if _CLIP_PROBE and not standing: _clip_probe(p)
	if _HEAD_PROBE and not standing and dt > 0.0 and is_inside_tree(): _head_probe(dt, air)
	if _POSE_PROBE and not standing:
		_pp_air = air
		_pp_why = "pre=%.2f ext=%.2f pop=%.2f sq=%.2f fold=%.2f reach=%.2f wheelie=%.2f absorb=%.3f v=%.1f init=%s kick=%.3f lip=%.2f" % [sm_pre, sm_ext, sm_popfx, sm_squash, sm_fold, sm_reach, sm_wheelie, _num(p, "absorb"), _num(p, "v"), spring_init, bump_pitch, sm_lip]
		_pp_joints()


# tests (BMX_POSE_PROBE=1): what the pose's corrections do and how rough the drawn joints move. Per correction step after
# the body springs (arm reach, hips box, bar, rear wheel, torso angle, torso length, saddle / tyre floor, motion cap):
# how often it moves the hips / chest more than 2 mm, its rms and biggest move; per joint (rider space): the second
# difference frame to frame (mm: a step / kink in the motion), rms, worst, frames over 3 mm. Run at a fixed frame rate
# (BMX_FPS=60) so the second differences compare. Printed every 4 s (cumulative) and at the end of a test
var _POSE_PROBE := Env.s("BMX_POSE_PROBE") != ""
const _PP_STAGES := ["reach", "hipbox", "bar", "wheel", "angle", "length", "floor", "cap"]
const _PP_JOINTS := [[2, "pelvis"], [1, "chest"], [0, "head"], [10, "kneeL"], [13, "kneeR"], [4, "elbowL"], [7, "elbowR"]]
const _PP_WORLD := [[2, "Wpelvis"], [1, "Wchest"], [0, "Whead"]]   # the same seen in the world (bike + body)
var _pp_ref := [Vector3.ZERO, Vector3.ZERO]
var _pp_st := {}   # stage -> [frames moved, sum sq, max]
var _pp_jt := {}   # joint -> [n, sum sq, max, over 3 mm, prev, prev2]
var _pp_t := 0
var _pp_jumps := 0; var _pp_air := 0.0; var _pp_why := ""; var _pp_frame := ""
func _pp_mark(k: int, pel: Vector3, ch: Vector3) -> void:
	if k > 0:
		var nm: String = _PP_STAGES[k - 1]
		var mv := maxf((pel - _pp_ref[0]).length(), (ch - _pp_ref[1]).length())
		var s: Array = _pp_st.get(nm, [0, 0.0, 0.0])
		if mv > 0.002: s[0] += 1
		if mv > 0.002: _pp_frame += " %s=%.0fmm" % [nm, mv * 1000.0]
		s[1] += mv * mv; s[2] = maxf(s[2], mv)
		_pp_st[nm] = s
	_pp_ref = [pel, ch]

func _pp_joints() -> void:
	for jn in _PP_JOINTS + _PP_WORLD:
		var x: Vector3 = J[jn[0]]
		if String(jn[1]).begins_with("W"):
			if not is_inside_tree(): continue
			x = to_global(x)
		var s: Array = _pp_jt.get(jn[1], [0, 0.0, 0.0, 0, Vector3.INF, Vector3.INF])
		if s[4] != Vector3.INF and s[5] != Vector3.INF:
			var a: float = (x - 2.0 * s[4] + s[5]).length()
			if a < 0.3:   # (a teleport / reset is not motion)
				s[0] += 1; s[1] += a * a; s[2] = maxf(s[2], a)
				if a > 0.003: s[3] += 1
				if a > 0.01 and jn[1] == "chest": print("POSETWITCH frame=%d chest 2nd diff=%.0fmm stages:%s | %s" % [_pp_t, a * 1000.0, _pp_frame, _pp_why])
				if a > 0.04 and jn[1] == "pelvis" and _pp_jumps < 30:
					_pp_jumps += 1
					print("POSEJUMP frame=%d pelvis 2nd diff=%.0fmm  air=%.2f pitch=%.2f %s" % [_pp_t, a * 1000.0, _pp_air, _probe_pitch, _pp_why])
		s[5] = s[4]; s[4] = x
		_pp_jt[jn[1]] = s
	_pp_t += 1
	_pp_frame = ""
	if _pp_t % 120 == 0: pose_probe_print()

func pose_probe_print() -> void:
	var n: int = maxi(_pp_t, 1)
	var line := "POSEPROBE frames=%d limits:" % _pp_t
	for nm in _PP_STAGES:
		var s: Array = _pp_st.get(nm, [0, 0.0, 0.0])
		line += " %s %.1f%% rms=%.1f max=%.0fmm |" % [nm, 100.0 * s[0] / n, sqrt(s[1] / n) * 1000.0, s[2] * 1000.0]
	print(line)
	line = "POSEPROBE joints (2nd diff mm):"
	for jn in _PP_JOINTS + _PP_WORLD:
		var s: Array = _pp_jt.get(jn[1], [0, 0.0, 0.0, 0])
		var m: int = maxi(s[0], 1)
		line += " %s rms=%.2f max=%.1f >3mm=%d |" % [jn[1], sqrt(s[1] / m) * 1000.0, s[2] * 1000.0, s[3]]
	print(line)


## The pose's corrections, in order: arms reach (the torso follows the hands), hips in their box, never through the
## handlebar, never into the rear wheel, the torso's angle and length, never into the saddle / rear tyre. Run on the
## TARGET before the body springs (so the springs follow a pose a body can take: nothing steps when a limit engages) and
## again after them as a safety net (it then only catches what the springs' lag leaves; `probe` measures that).
## Returns [pelvis, chest]
func _constrain(pelvis: Vector3, chest: Vector3, p: Dictionary, sty: Dictionary, standing: bool, aero: float, final: bool) -> Array:
	var probe := final and _POSE_PROBE
	var probe_bar := final and Env.s("BMX_BAR_PROBE") != ""
	var handL = p.get("handL")
	var handR = p.get("handR")
	if probe: _pp_mark(0, pelvis, chest)
	# arms only reach so far: the torso follows the hands so the elbows keep a bend
	if handL is Vector3 and handR is Vector3 and not standing:
		# Arm bend: how far the arms may straighten (more bend = chest closer to the bars)
		var reach := (L_UARM + L_FARM) * clampf(0.9 - 0.2 * float(sty.armBend), 0.55, 0.98)
		# (on a jump face / popped: arms nearly straight, video 2 - the elbows' usual bend folded the chest onto the bars)
		reach = lerpf(reach, (L_UARM + L_FARM) * FACE_REACH, maxf(_face_k, clampf(_num(p, "flipExt"), 0.0, 1.0)))   # (and hanging long off the bike mid-flip)
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
				# (continuous: no fixed minimum step, or a pose resting right at the reach limit - the title screen's - popped
				# 1 cm in and out every time it crossed it; 1.2 = the direction isn't exactly along the arm)
				d *= minf(worst * 1.2, len * 0.6) / len
				chest += d
				pelvis += d * 0.35

	if probe: _pp_mark(1, pelvis, chest)
	# ---- safety limits. Whatever stacks up (tuck + spin + counter-lean + landing + style sliders), the
	# skeleton stays humanly possible: hips in a box over the bike, the torso bends only so far from the
	# bike's up (back / forward, sideways) and never folds below the hips
	pelvis.x = clampf(pelvis.x, -0.6, 0.22)
	pelvis.y = clampf(pelvis.y, 0.42, 1.08)
	var z_cap: float = lerpf(0.22, AIR_HIP_SIDE, clampf(_num(p, "air"), 0.0, 1.0)) if not _OLD_AIRBODY else 0.22   # (air: an upright body over a laid-over bike)
	pelvis.z = clampf(pelvis.z, -z_cap, z_cap)
	if probe: _pp_mark(2, pelvis, chest)
	# ---- never through the handlebar. The chest and the helmet keep clear of the bar / stem (the middle of the two
	# grips), seen from the side: whatever leans the rider onto it (a sprint from a standstill, the tuck, a squash, a
	# hard landing, braking) the whole upper body moves back and a little up, hips and all: the arms get longer and
	# the back keeps its angle (pushing only the chest stood him bolt upright with his elbows folded under his chin).
	# The limits below (rear wheel, torso angle and length) still have the last word
	if handL is Vector3 and handR is Vector3 and not standing:
		var bar_c: Vector3 = (handL + handR) * 0.5
		var head_off := Vector2(0.05 + float(sty.lookAhead) + 0.04 * aero + TUCK_HEAD.x * speed_tuck_k, 0.2 + float(sty.neck) + TUCK_HEAD.y * speed_tuck_k)
		var push := Vector2.ZERO
		var deep := 0.0
		for pass_i in 2:
			for which in 2:
				var bar_r: float = BAR_HEAD if which == 1 else BAR_CHEST
				var d2b := Vector2(chest.x - bar_c.x, chest.y - bar_c.y) + push + (head_off if which == 1 else Vector2.ZERO)
				var dl2 := d2b.length()
				if dl2 >= bar_r: continue
				deep = maxf(deep, bar_r - dl2)
				# out along a line that is half "straight away from the bar", half "up and back" (never forward / down
				# round it), as far as it takes to be clear
				# (a point in front of / under the bar goes all "up and back": the two halves would cancel there and the
				# direction flip about, throwing the chest 60 cm in a frame)
				var ub := Vector2(-0.92, 0.39)
				var rad := d2b / dl2 if dl2 > 1e-3 else ub
				var rw := 0.5 * clampf(0.5 + 0.5 * rad.dot(ub), 0.0, 1.0)
				var dir := (rad * rw + ub * (1.0 - rw)).normalized()
				var bd := d2b.dot(dir)
				var tt := -bd + sqrt(maxf(0.0, bd * bd - (dl2 * dl2 - bar_r * bar_r)))
				if Env.s("BMX_NO_BARLIMIT") != "": continue   # tests: measure only
				push += dir * tt
		if push != Vector2.ZERO:
			chest.x += push.x; chest.y += push.y
			pelvis.x = maxf(-0.6, pelvis.x + push.x * 0.85); pelvis.y += push.y * 0.6
		if probe_bar:   # tests: how deep into the bar the chest / helmet would have been
			bar_stats[0] = maxf(bar_stats[0], deep); bar_stats[1] += 1.0 if deep > 0.0 else 0.0; bar_stats[2] += 1.0
			var d_c := Vector2(chest.x - bar_c.x, chest.y - bar_c.y)   # (before the limits below)
			bar_stats[3] = minf(bar_stats[3], d_c.length()); bar_stats[4] = minf(bar_stats[4], (d_c + head_off).length())
	if probe: _pp_mark(3, pelvis, chest)
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
	if probe: _pp_mark(4, pelvis, chest)
	var tv0 := chest - pelvis
	var tl0 := maxf(tv0.length(), 1e-4)
	# forward lean from upright. A chest at or below the hips counts as folded FORWARD whichever side of the
	# hips it is (atan2 there flips between +-180 deg as it crosses over: the torso snapped back and forth)
	var f_ang := 1.4 if tv0.y < 0.05 else clampf(atan2(tv0.x, tv0.y), -0.45, 1.4)
	var s_cap: float = lerpf(0.6, AIR_SIDE, clampf(_num(p, "air"), 0.0, 1.0)) if not _OLD_AIRBODY else 0.6
	var s_ang := clampf(asin(clampf(tv0.z / tl0, -1.0, 1.0)), -s_cap, s_cap)   # sideways (more in the air: the bike laid under him)
	chest = pelvis + Vector3(sin(f_ang) * cos(s_ang), cos(f_ang) * cos(s_ang), sin(s_ang)) * tl0
	if probe: _pp_mark(5, pelvis, chest)
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
	if probe: _pp_mark(6, pelvis, chest)
	# the hips once more, now that everything above has moved them (the bar limit, the torso's length): never into the
	# saddle, never into the rear tyre. The chest comes up with them
	var hip_lift := 0.0
	if sty.seatFloor and seat != null and not standing:
		var s_in: float = clampf((pelvis.x - (float(seat.rear) - 0.1)) / 0.08, 0.0, 1.0) * clampf((float(seat.front) + 0.1 - pelvis.x) / 0.08, 0.0, 1.0)
		hip_lift = maxf(0.0, (float(seat.top) + 0.078 - 0.3 * _sink - pelvis.y) * s_in)   # (soaking a landing: down onto it)
	if wr is Vector3 and not standing:
		var dw := Vector2(pelvis.x - wr.x, pelvis.y + hip_lift - wr.y)
		var cr2: float = _num(p, "wheelRR", 0.36) + 0.12
		if dw.length() < cr2 and dw.y > -0.1: hip_lift += sqrt(maxf(0.0, cr2 * cr2 - dw.x * dw.x)) - dw.y
	if hip_lift > 0.0:
		pelvis.y += hip_lift; chest.y += hip_lift
	if probe: _pp_mark(7, pelvis, chest)
	return [pelvis, chest]

# tests (BMX_HEAD_PROBE=1): how steady the head is in the world, on the ground: its angular speed (pitch / roll / yaw
# parts, rad/s rms), its acceleration (m/s^2 rms, 2nd difference) vs the chest's. Printed every 2 s, cumulative
var _HEAD_PROBE := Env.s("BMX_HEAD_PROBE") != ""
var _hpr := {n = 0, p = 0.0, r = 0.0, y = 0.0, ha = 0.0, ca = 0.0, t = 0.0, b0 = Basis(), h1 = Vector3.INF, h2 = Vector3.INF, c1 = Vector3.INF, c2 = Vector3.INF}
func _head_probe(dt: float, air: float) -> void:
	var gb: Basis = head.global_transform.basis.orthonormalized()
	var hp: Vector3 = head.global_position
	var cp: Vector3 = to_global(J[1])
	var s := _hpr
	if air < 0.05 and s.h2 != Vector3.INF:
		var d: Basis = (s.b0 as Basis).inverse() * gb   # the turn in the head's own frame this frame
		var e := d.get_euler()
		s.n += 1
		s.p += pow(e.z / dt, 2); s.r += pow(e.x / dt, 2); s.y += pow(e.y / dt, 2)
		s.ha += ((hp - 2.0 * s.h1 + s.h2) / (dt * dt)).length_squared()
		s.ca += ((cp - 2.0 * s.c1 + s.c2) / (dt * dt)).length_squared()
	s.b0 = gb; s.h2 = s.h1; s.h1 = hp; s.c2 = s.c1; s.c1 = cp
	s.t += dt
	if s.t >= 2.0 and s.n > 0:
		s.t = 0.0
		print("HEADPROBE n=%d ang_rms pitch=%.3f roll=%.3f yaw=%.3f rad/s  acc_rms head=%.2f chest=%.2f m/s2" % [s.n,
			sqrt(s.p / s.n), sqrt(s.r / s.n), sqrt(s.y / s.n), sqrt(s.ha / s.n), sqrt(s.ca / s.n)])
