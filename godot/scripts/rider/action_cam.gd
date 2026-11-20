class_name ActionCam
## Helmet-top action camera (GoPro-sized, no branding): curved adhesive base, quick-release buckle,
## three-finger hinge with a thumb screw, then the camera body (71 x 51 x 34 mm) with its square lens
## block, front screen, shutter button and record LED. Built in head space: origin = where the base
## touches the shell, +X = forward (the lens), +Y = up. The "Lens" child marks the lens front: the
## Helmet camera view looks out from there.
##
## Mounts (`build(kind)`): "top" = the helmet-top buckle + hinge above; every other kind is built by
## `build_arm(normal, body_at)`: the adhesive pad / clamp faces along `normal` and an arm holds the camera
## UPRIGHT (lens +X, the picture never rolls) at `body_at` -- helmet side / chin, handlebar, fork leg.
## The camera itself is always the "Body" child (Rider.break_action_cam tears it off).

## where the rider's action cam can sit (look.camMount); "none" = no camera on the helmet
const HELMET_MOUNTS := [["top", "Helmet top"], ["side", "Helmet side"], ["chin", "Chin bar"], ["none", "None"]]
## where the bike's action cam can sit (build.camera.mount); "none" = no camera on the bike
const BIKE_MOUNTS := [["none", "None"], ["bars", "Handlebar"], ["fork", "Fork leg"]]

const G := preload("res://scripts/rider/rider_geo.gd")

static func _mat(c: String, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c)
	m.roughness = rough
	m.metallic = metal
	return m

static func _cyl(r: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r; c.bottom_radius = r; c.height = h
	c.radial_segments = segs; c.rings = 1
	return c

static func _add(parent: Node3D, mesh: Variant, m: Material, xf := Transform3D()) -> MeshInstance3D:
	var mi: MeshInstance3D
	if mesh is Dictionary:
		mi = G.inst(mesh, m)
	else:
		mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

static func _mats() -> Dictionary:
	var glass := _mat("#05070a", 0.04, 0.2)
	glass.clearcoat_enabled = true
	glass.clearcoat_roughness = 0.02
	var screen := _mat("#0b1220", 0.1)
	screen.emission_enabled = true
	screen.emission = Color("#1d3550")
	screen.emission_energy_multiplier = 0.6
	var led := _mat("#ff2a1a", 0.3)
	led.emission_enabled = true
	led.emission = Color("#ff2a1a")
	led.emission_energy_multiplier = 2.5
	return {
		body = _mat("#17181b", 0.55),        # rubbery black body
		plast = _mat("#232529", 0.4),        # mount plastic
		trim = _mat("#3b3e44", 0.35, 0.3),
		screw = _mat("#9aa0a8", 0.3, 0.9),
		glass = glass,
		ring = _mat("#2b2d31", 0.25, 0.6),
		screen = screen, led = led,
		btn = _mat("#c8352b", 0.45),
	}

## the adhesive pad + quick-release buckle, built with +Y = out of the surface (root origin = the surface)
static func _base(root: Node3D, M: Dictionary, b := Basis()) -> void:
	_add(root, G.rounded_box(0.042, 0.005, 0.040, 2, 0.002), M.plast, Transform3D(b, b * Vector3(0, 0.0025, 0)))
	_add(root, G.rounded_box(0.034, 0.008, 0.030, 2, 0.003), M.plast, Transform3D(b, b * Vector3(0, 0.009, 0)))
	for s in [-1.0, 1.0]:   # buckle release tabs at the sides
		_add(root, G.box(0.010, 0.006, 0.004), M.trim, Transform3D(b, b * Vector3(-0.006, 0.009, s * 0.017)))

## the camera body (lens +X, up +Y) into `cam` (origin = the bottom of its folding fingers) + its "Lens" marker
static func _camera(cam: Node3D, M: Dictionary) -> void:
	var W := 0.071; var H := 0.051; var D := 0.034    # width (Z), height (Y), depth (X)
	var by := H * 0.5 + 0.006
	_add(cam, G.rounded_box(D, H, W, 3, 0.006), M.body, Transform3D(Basis(), Vector3(0, by, 0)))
	# grippy side panels + a lighter trim band round the middle
	_add(cam, G.rounded_box(D * 1.02, H * 0.18, W * 1.01, 2, 0.003), M.trim, Transform3D(Basis(), Vector3(0, by + H * 0.22, 0)))
	# square lens block on the front, off to one side (as on the real thing)
	var lz := W * 0.5 - 0.019
	var ly := by + H * 0.12
	_add(cam, G.rounded_box(0.008, 0.027, 0.027, 2, 0.004), M.body, Transform3D(Basis(), Vector3(D * 0.5 + 0.004, ly, lz)))
	var along_x := Basis(Vector3.BACK, PI / 2)
	_add(cam, _cyl(0.0105, 0.004, 20), M.ring, Transform3D(along_x, Vector3(D * 0.5 + 0.009, ly, lz)))
	_add(cam, _cyl(0.0078, 0.0045, 20), M.glass, Transform3D(along_x, Vector3(D * 0.5 + 0.0095, ly, lz)))
	# small front screen beside the lens
	_add(cam, G.box(0.002, 0.020, 0.024), M.screen, Transform3D(Basis(), Vector3(D * 0.5 + 0.0005, ly, -W * 0.5 + 0.022)))
	# record LED on the front + shutter button on top
	_add(cam, _cyl(0.0016, 0.002, 8), M.led, Transform3D(along_x, Vector3(D * 0.5 + 0.001, by + H * 0.38, -W * 0.5 + 0.008)))
	_add(cam, _cyl(0.0055, 0.0035, 14), M.btn, Transform3D(Basis(), Vector3(0.002, by + H * 0.5 + 0.0012, -W * 0.5 + 0.017)))
	# the mounting fingers folded down under the body
	for z in [-0.0043, 0.0043]:
		_add(cam, G.rounded_box(0.012, 0.012, 0.003, 1, 0.001), M.plast, Transform3D(Basis(), Vector3(0, 0.002, z)))
	var lens := Marker3D.new()
	lens.name = "Lens"
	lens.position = Vector3(D * 0.5 + 0.02, ly, lz)
	cam.add_child(lens)

## kind "top" (default): the helmet-top mount; the others: build_arm with the mount's own geometry
static func build(kind := "top") -> Node3D:
	match kind:
		"side":   # stuck on the left of the shell, the camera upright beside it, lens level with the eyes
			return build_arm(Vector3(0, 0, -1), Vector3(0.0, -0.03, -0.052))
		"chin":   # on the front of the chin bar, the camera hanging just ahead of it
			return build_arm(Vector3(1, 0, 0), Vector3(0.034, -0.03, 0.0))
	var M := _mats()
	var root := Node3D.new()
	root.name = "ActionCam"
	root.set_meta("kind", "top")
	_base(root, M)
	# three-finger hinge (fingers lie in the X-Y plane, stacked along Z), thumb screw through them along Z
	var hinge_y := 0.026
	for z in [-0.0085, 0.0, 0.0085]:
		_add(root, G.rounded_box(0.014, 0.022, 0.0032, 1, 0.0012), M.plast, Transform3D(Basis(), Vector3(0, 0.020, z)))
	var along_z := Basis(Vector3.RIGHT, PI / 2)
	_add(root, _cyl(0.0035, 0.024, 10), M.screw, Transform3D(along_z, Vector3(0, hinge_y, 0)))
	var knob: MeshInstance3D = _add(root, _cyl(0.0085, 0.008, 12), M.plast, Transform3D(along_z, Vector3(0, hinge_y, 0.017)))
	knob.name = "ThumbScrew"
	# the camera's own folding fingers + body, hinged slightly back so it sits level over the crown
	var cam := Node3D.new()
	cam.name = "Body"
	cam.position = Vector3(0, hinge_y + 0.006, 0)
	cam.rotation.z = 0.14   # tipped up on the hinge (~8°), as riders set it: less visor in the shot
	root.add_child(cam)
	_camera(cam, M)
	return root

## pad / buckle facing `normal` at the origin, an arm out to `body_at` (the camera body's origin = the bottom
## of its fingers), the camera upright there (lens +X). Arm = a stack of rounded links with a thumb screw at each joint.
static func build_arm(normal: Vector3, body_at: Vector3, tilt := 0.0) -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "ActionCam"
	root.set_meta("kind", "arm")
	var n := normal.normalized()
	var ref := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP
	var bz := ref.cross(n).normalized()
	var bx := n.cross(bz).normalized()
	var b := Basis(bx, n, bz)   # +Y of the pad = the normal
	_base(root, M, b)
	# the arm: from the top of the buckle to the camera's hinge (just under the body)
	var a0 := n * 0.014
	var a1 := body_at + Vector3(0, 0.004, 0)
	var mid := a0.lerp(a1, 0.5)
	var seg := a1 - a0
	var L := seg.length()
	if L > 0.004:
		var y := seg / L
		var r2 := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
		var z := r2.cross(y).normalized()
		var x := y.cross(z).normalized()
		var ab := Basis(x, y, z)
		# two parallel links (fingers) either side of the arm's plane, as on the real extension arms
		for o in [-0.0045, 0.0045]:
			_add(root, G.rounded_box(0.012, L + 0.012, 0.0032, 1, 0.0012), M.plast, Transform3D(ab, mid + ab * Vector3(0, 0, o)))
		var along := Basis(x, z, -y)   # cylinder axis (Y) along the arm's z
		for p in [a0, a1]:
			_add(root, _cyl(0.0035, 0.016, 10), M.screw, Transform3D(along, p))
		var knob: MeshInstance3D = _add(root, _cyl(0.0075, 0.007, 12), M.plast, Transform3D(along, a1 + ab * Vector3(0, 0, 0.011)))
		knob.name = "ThumbScrew"
	var cam := Node3D.new()
	cam.name = "Body"
	cam.position = body_at
	cam.rotation.z = tilt
	root.add_child(cam)
	_camera(cam, M)
	return root

## a bar / tube clamp (handlebar, fork leg): a ring of radius `r` round the tube along `axis` at the origin,
## the arm out to the camera at `body_at` (camera upright, lens +X). Root origin = the tube's centre.
static func build_clamp(axis: Vector3, r: float, out: Vector3, body_at: Vector3, tilt := 0.0) -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "ActionCam"
	root.set_meta("kind", "clamp")
	var y := axis.normalized()
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP
	var z := ref.cross(y).normalized()
	var x := y.cross(z).normalized()
	var ring := CylinderMesh.new()
	ring.top_radius = r + 0.004; ring.bottom_radius = r + 0.004; ring.height = 0.018
	ring.radial_segments = 20; ring.rings = 1
	_add(root, ring, M.plast, Transform3D(Basis(x, y, z), Vector3.ZERO))
	# the clamp's screw block on the outside, toward the camera
	var o := out.normalized()
	var ob_ref := y if absf(o.dot(y)) < 0.9 else x
	var oz := ob_ref.cross(o).normalized()
	var ob := Basis(o.cross(oz).normalized(), o, oz)
	_add(root, G.rounded_box(0.020, 0.010, 0.020, 1, 0.002), M.plast, Transform3D(ob, o * (r + 0.008)))
	_add(root, _cyl(0.0032, 0.024, 10), M.screw, Transform3D(Basis(x, y, z), o * (r + 0.008)))
	var arm := build_arm(o, body_at - o * (r + 0.006), tilt)
	# keep only the arm + camera (the clamp replaces the adhesive pad): drop the pad's three meshes + tabs
	var k := 0
	for c in arm.get_children():
		if c is MeshInstance3D and k < 4:
			arm.remove_child(c); c.queue_free(); k += 1
	arm.position = o * (r + 0.006)
	arm.name = "Arm"
	root.add_child(arm)
	# the camera body must be a direct child named Body (break_action_cam / the views look for "Body/Lens")
	var bd := arm.get_node("Body") as Node3D
	var bx := bd.transform
	arm.remove_child(bd)
	bd.transform = arm.transform * bx
	root.add_child(bd)
	return root
