class_name ActionCam
## Helmet-top action camera (GoPro-sized, no branding): curved adhesive base, quick-release buckle,
## three-finger hinge with a thumb screw, then the camera body (71 x 51 x 34 mm) with its square lens
## block, front screen, shutter button and record LED. Built in head space: origin = where the base
## touches the shell, +X = forward (the lens), +Y = up. The "Lens" child marks the lens front: the
## Helmet camera view looks out from there.

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

static func build() -> Node3D:
	var body_m := _mat("#17181b", 0.55)              # rubbery black body
	var plast := _mat("#232529", 0.4)                # mount plastic
	var trim := _mat("#3b3e44", 0.35, 0.3)
	var screw := _mat("#9aa0a8", 0.3, 0.9)
	var glass := _mat("#05070a", 0.04, 0.2)
	glass.clearcoat_enabled = true
	glass.clearcoat_roughness = 0.02
	var ring := _mat("#2b2d31", 0.25, 0.6)
	var screen := _mat("#0b1220", 0.1)
	screen.emission_enabled = true
	screen.emission = Color("#1d3550")
	screen.emission_energy_multiplier = 0.6
	var led := _mat("#ff2a1a", 0.3)
	led.emission_enabled = true
	led.emission = Color("#ff2a1a")
	led.emission_energy_multiplier = 2.5
	var btn := _mat("#c8352b", 0.45)

	var root := Node3D.new()
	root.name = "ActionCam"
	# curved adhesive base: a flat rounded pad, then the buckle on it
	_add(root, G.rounded_box(0.042, 0.005, 0.040, 2, 0.002), plast, Transform3D(Basis(), Vector3(0, 0.0025, 0)))
	_add(root, G.rounded_box(0.034, 0.008, 0.030, 2, 0.003), plast, Transform3D(Basis(), Vector3(0, 0.009, 0)))
	# buckle release tabs at the sides
	for s in [-1.0, 1.0]:
		_add(root, G.box(0.010, 0.006, 0.004), trim, Transform3D(Basis(), Vector3(-0.006, 0.009, s * 0.017)))
	# three-finger hinge (fingers lie in the X-Y plane, stacked along Z), thumb screw through them along Z
	var hinge_y := 0.026
	for z in [-0.0085, 0.0, 0.0085]:
		_add(root, G.rounded_box(0.014, 0.022, 0.0032, 1, 0.0012), plast, Transform3D(Basis(), Vector3(0, 0.020, z)))
	var along_z := Basis(Vector3.RIGHT, PI / 2)
	_add(root, _cyl(0.0035, 0.024, 10), screw, Transform3D(along_z, Vector3(0, hinge_y, 0)))
	var knob: MeshInstance3D = _add(root, _cyl(0.0085, 0.008, 12), plast, Transform3D(along_z, Vector3(0, hinge_y, 0.017)))
	knob.name = "ThumbScrew"
	# the camera's own folding fingers + body, hinged slightly back so it sits level over the crown
	var cam := Node3D.new()
	cam.name = "Body"
	cam.position = Vector3(0, hinge_y + 0.006, 0)
	cam.rotation.z = 0.14   # tipped up on the hinge (~8°), as riders set it: less visor in the shot
	root.add_child(cam)
	var W := 0.071; var H := 0.051; var D := 0.034    # width (Z), height (Y), depth (X)
	var by := H * 0.5 + 0.006
	_add(cam, G.rounded_box(D, H, W, 3, 0.006), body_m, Transform3D(Basis(), Vector3(0, by, 0)))
	# grippy side panels + a lighter trim band round the middle
	_add(cam, G.rounded_box(D * 1.02, H * 0.18, W * 1.01, 2, 0.003), trim, Transform3D(Basis(), Vector3(0, by + H * 0.22, 0)))
	# square lens block on the front, off to one side (as on the real thing)
	var lz := W * 0.5 - 0.019
	var ly := by + H * 0.12
	_add(cam, G.rounded_box(0.008, 0.027, 0.027, 2, 0.004), body_m, Transform3D(Basis(), Vector3(D * 0.5 + 0.004, ly, lz)))
	var along_x := Basis(Vector3.BACK, PI / 2)
	_add(cam, _cyl(0.0105, 0.004, 20), ring, Transform3D(along_x, Vector3(D * 0.5 + 0.009, ly, lz)))
	_add(cam, _cyl(0.0078, 0.0045, 20), glass, Transform3D(along_x, Vector3(D * 0.5 + 0.0095, ly, lz)))
	# small front screen beside the lens
	_add(cam, G.box(0.002, 0.020, 0.024), screen, Transform3D(Basis(), Vector3(D * 0.5 + 0.0005, ly, -W * 0.5 + 0.022)))
	# record LED on the front + shutter button on top
	_add(cam, _cyl(0.0016, 0.002, 8), led, Transform3D(along_x, Vector3(D * 0.5 + 0.001, by + H * 0.38, -W * 0.5 + 0.008)))
	_add(cam, _cyl(0.0055, 0.0035, 14), btn, Transform3D(Basis(), Vector3(0.002, by + H * 0.5 + 0.0012, -W * 0.5 + 0.017)))
	# the mounting fingers folded down under the body
	for z in [-0.0043, 0.0043]:
		_add(cam, G.rounded_box(0.012, 0.012, 0.003, 1, 0.001), plast, Transform3D(Basis(), Vector3(0, 0.002, z)))
	var lens := Marker3D.new()
	lens.name = "Lens"
	lens.position = Vector3(D * 0.5 + 0.02, ly, lz)
	cam.add_child(lens)
	return root
