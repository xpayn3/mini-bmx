class_name RollerDoor
extends RefCounted
## The garage's premium roller door: insulated aluminium slats with a rounded face and a V shadow groove
## at every joint, anthracite powder coat (RAL 7016 look, fine metallic, clear coat), a closed box hood
## with a rounded nose and brushed aluminium end plates, guide rails with black brush seals, a brushed
## aluminium bottom bar with a rubber bulb seal, and a wall key switch with its conduit up to the hood.
## Surfaces use the real scans already in the project: ambientCG Metal009 (brushed metal) and Rubber004
## (both CC0), laid along each part's length (brushing runs along the slats).
##
## Coordinates: x across the opening (centre 0), y up from the floor, z out of the wall into the room
## (0 = the wall's inside face). `build` puts everything under `parent` at (door_x, 0, wall_in).

const PITCH := 0.1        # slat height (one per 10 cm, like a real insulated shutter slat)
const SLAT_T := 0.022     # slat thickness
const SLAT_Z := 0.043     # slat centre, out from the wall
const BAR_TOP := 0.078    # bottom bar (rubber seal + aluminium bar) height
const HOOD_D := 0.36      # hood depth from the wall
const HOOD_H := 0.42
const TILE := 0.5         # metres of metal scan per texture tile

const METAL := "res://assets/textures/brushed_metal/metal_%s.jpg"
const RUBBER := "res://assets/textures/rubber/rubber_%s.jpg"
const GRIME := "res://assets/textures/grime/grime_%s.jpg"
const GRIME_TILE := 1.2   # metres of the grime scan per tile
const COLOR_MEAN := 0.58  # Metal009 colour / roughness means (see MetalFinish)
const ROUGH_MEAN := 0.47


static func _scan(c: Color, rough: float, metal: float, normal: float, streaks := true, triplanar := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = metal
	m.roughness = minf(rough / ROUGH_MEAN, 1.0)
	m.roughness_texture = load(METAL % "rough")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.normal_enabled = true
	m.normal_texture = load(METAL % "normal")
	m.normal_scale = normal
	if streaks:
		m.albedo_texture = load(METAL % "color")
		m.albedo_color = Color(c.r / COLOR_MEAN, c.g / COLOR_MEAN, c.b / COLOR_MEAN)
	else:
		m.albedo_color = c
	m.uv1_scale = Vector3.ONE / TILE
	if triplanar:   # box parts (no useful UVs): object-space triplanar, so it moves with the part
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _powder(triplanar := false) -> StandardMaterial3D:
	# traffic-white powder coat (RAL 9016 look), satin, under a light clear coat, a little grubby: the
	# ambientCG SurfaceImperfections008 scan multiplied over it (dust / smudges) and its relief in the normals
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.89, 0.88)
	m.roughness = 0.42
	m.detail_enabled = true
	m.detail_albedo = load(GRIME % "dirt")
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.normal_enabled = true
	m.normal_texture = load(GRIME % "normal")
	m.normal_scale = 0.2
	m.uv1_scale = Vector3.ONE / GRIME_TILE
	if triplanar:
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.clearcoat_enabled = true
	m.clearcoat = 0.3
	m.clearcoat_roughness = 0.4
	return m


static func _alu(triplanar := false) -> StandardMaterial3D:
	return _scan(Color(0.74, 0.75, 0.77), 0.3, 1.0, 0.45, true, triplanar)


static func _rubber() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(RUBBER % "color")
	m.albedo_color = Color(0.55, 0.55, 0.55)
	m.normal_enabled = true
	m.normal_texture = load(RUBBER % "normal")
	m.normal_scale = 0.6
	m.roughness_texture = load(RUBBER % "rough")
	m.roughness = 1.0
	m.uv1_scale = Vector3.ONE / 0.08
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## A 2D profile (Vector2(z, y), counter-clockwise with z to the right and y up) extruded along x over
## width w, centred. Smooth normals where the profile bends less than 30 deg, a hard edge otherwise.
## UVs: u = x, v = arc length (metres). `closed` joins the last point to the first; `caps` closes the ends.
static func extrude(pts: PackedVector2Array, w: float, closed := true, caps := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var segs := n if closed else n - 1
	var nrm: Array[Vector2] = []
	for i in segs:
		var d := (pts[(i + 1) % n] - pts[i]).normalized()
		nrm.append(Vector2(d.y, -d.x))
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var v := 0.0
	var cos_hard := cos(deg_to_rad(30.0))
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var na := nrm[i]
		var nb := nrm[i]
		if closed or i > 0:
			var p := nrm[(i - 1 + segs) % segs]
			if p.dot(nrm[i]) > cos_hard: na = (p + nrm[i]).normalized()
		if closed or i < segs - 1:
			var q := nrm[(i + 1) % segs]
			if q.dot(nrm[i]) > cos_hard: nb = (q + nrm[i]).normalized()
		var seg_len := a.distance_to(b)
		var quad := [[x0, a, na, v], [x0, b, nb, v + seg_len], [x1, b, nb, v + seg_len], [x0, a, na, v], [x1, b, nb, v + seg_len], [x1, a, na, v]]
		for q in quad:
			var p2: Vector2 = q[1]
			var n2: Vector2 = q[2]
			st.set_normal(Vector3(0, n2.y, n2.x))
			st.set_uv(Vector2(q[0], q[3]))
			st.add_vertex(Vector3(q[0], p2.y, p2.x))
		v += seg_len
	if caps:
		var tri := Geometry2D.triangulate_polygon(pts)
		for side in [1.0, -1.0]:
			var x: float = side * w / 2.0
			for t in range(0, tri.size(), 3):
				var ids := [tri[t], tri[t + 1], tri[t + 2]]
				if side < 0: ids.reverse()
				for id in ids:
					var p3 := pts[id]
					st.set_normal(Vector3(side, 0, 0))
					st.set_uv(Vector2(p3.x, p3.y))
					st.add_vertex(Vector3(x, p3.y, p3.x))
	st.generate_tangents()
	return st.commit()


## points along an arc (centre c, radius r) from angle a0 to a1 (radians, in the z-y plane)
static func _arc(c: Vector2, r: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in steps + 1:
		var a := lerpf(a0, a1, float(k) / steps)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## one slat, centred on y = 0: a slightly domed face with a chamfer top and bottom, so neighbours meet in a V groove
static func slat_profile() -> PackedVector2Array:
	var t := SLAT_T / 2.0
	var h := PITCH / 2.0
	var g := 0.007     # groove height
	var gd := 0.005    # groove depth
	var p := PackedVector2Array()
	p.append(Vector2(SLAT_Z - t, -h))
	p.append(Vector2(SLAT_Z + t - gd, -h))
	for k in 9:   # the face, domed 3 mm
		var f := float(k) / 8.0
		p.append(Vector2(SLAT_Z + t + 0.003 * sin(PI * f), lerpf(-h + g, h - g, f)))
	p.append(Vector2(SLAT_Z + t - gd, h))
	p.append(Vector2(SLAT_Z - t, h))
	return p


static func _part(parent: Node, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size
	return _part(parent, b, mat, pos)


static func _cyl(parent: Node, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h
	c.radial_segments = 24
	return _part(parent, c, mat, pos, rot)


## Builds the frame (hood, guides, switch) under `parent` and returns the curtain: a Node3D whose children
## (bottom bar + slats) each carry meta "y0"; the garage sets child.y = y0 + lift to roll it up.
static func build(parent: Node3D, door_x: float, w: float, h: float, wall_in: float) -> Node3D:
	var root := Node3D.new()
	root.name = "RollerDoor"
	root.position = Vector3(door_x, 0, wall_in)
	parent.add_child(root)
	var powder := _powder()
	var powder_box := _powder(true)
	var alu := _alu()
	var alu_box := _alu(true)
	var seal := StandardMaterial3D.new()   # brush seal: dense black nylon bristles
	seal.albedo_color = Color(0.025, 0.025, 0.03)
	seal.roughness = 0.95
	var hw := w / 2.0

	# --- hood: a closed box over the rolled-up curtain, rounded nose, aluminium end plates
	var h0 := h + 0.02
	var h1 := h0 + HOOD_H
	var hood := PackedVector2Array([Vector2(0.11, h0)])
	hood.append_array(_arc(Vector2(HOOD_D - 0.07, h0 + 0.07), 0.07, -PI / 2, 0.0, 8))
	hood.append_array(_arc(Vector2(HOOD_D - 0.015, h1 - 0.015), 0.015, 0.0, PI / 2, 3))
	hood.append(Vector2(0.004, h1))
	var hood_w := w + 0.26
	_part(root, extrude(hood, hood_w, false, false), powder)
	var cap := PackedVector2Array([Vector2(0.004, h0)])
	cap.append_array(hood)
	for sx in [-1.0, 1.0]:
		_part(root, extrude(cap, 0.008), alu, Vector3(sx * (hood_w / 2.0 + 0.004), 0, 0))
	# a dark liner inside the hood (seen through the curtain slot from below)
	_box(root, Vector3(hood_w, 0.004, 0.1), Vector3(0, h0 + 0.03, 0.06), seal)
	# a shadow-gap reveal line along the hood's face
	_box(root, Vector3(hood_w + 0.002, 0.004, 0.003), Vector3(0, h0 + HOOD_H * 0.62, HOOD_D + 0.0005), seal)

	# --- guide rails: anthracite channels standing a little into the opening, black brush seals
	var gh := h0 + 0.01
	for sx in [-1.0, 1.0]:
		var gx: float = sx * (hw + 0.036)
		_box(root, Vector3(0.096, gh, 0.01), Vector3(gx, gh / 2.0, 0.075), powder_box)                  # front face
		_box(root, Vector3(0.008, gh, 0.07), Vector3(sx * (hw + 0.08), gh / 2.0, 0.037), powder_box)    # outer side
		_box(root, Vector3(0.096, gh, 0.008), Vector3(gx, gh / 2.0, 0.008), powder_box)                 # back flange
		_box(root, Vector3(0.012, gh, 0.012), Vector3(sx * (hw - 0.006), gh / 2.0, 0.064), seal)        # front brush seal
		_box(root, Vector3(0.012, gh, 0.012), Vector3(sx * (hw - 0.006), gh / 2.0, 0.022), seal)        # back brush seal
		_box(root, Vector3(0.1, 0.012, 0.086), Vector3(gx, 0.006, 0.042), alu_box)                     # floor shoe

	# --- the curtain
	var curtain := Node3D.new()
	curtain.name = "DoorSlats"
	root.add_child(curtain)
	var cw := w + 0.1   # runs into the guides
	var bar := PackedVector2Array([Vector2(0.026, 0.016)])
	bar.append_array(_arc(Vector2(0.054, 0.028), 0.012, -PI / 2, 0.0, 5))
	bar.append_array(PackedVector2Array([Vector2(0.066, 0.046), Vector2(0.0625, 0.049), Vector2(0.0625, 0.054),
		Vector2(0.066, 0.057), Vector2(0.066, BAR_TOP), Vector2(0.026, BAR_TOP)]))
	var bar_mi := _part(curtain, extrude(bar, cw), alu)
	bar_mi.set_meta("y0", 0.0)
	var bulb := _arc(Vector2(0.046, 0.018), 0.016, PI, TAU, 10)
	for i in bulb.size():   # squash the half-round into a flatter bulb (18 mm tall)
		bulb[i].y = 0.018 - (0.018 - bulb[i].y) * 1.1
	var rub := _part(curtain, extrude(bulb, cw), _rubber())
	rub.set_meta("y0", 0.0)
	var slat_mesh := extrude(slat_profile(), cw)
	var n := ceili((h - BAR_TOP) / PITCH) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 9016
	for i in n:
		# every slat its own patch of the grime scan (they share one mesh / UVs), a touch dustier low down
		var sm: StandardMaterial3D = powder.duplicate()
		sm.uv1_offset = Vector3(rng.randf(), rng.randf(), 0)
		sm.albedo_color = powder.albedo_color.darkened(0.08 * (1.0 - float(i) / n))
		var s := _part(curtain, slat_mesh, sm)
		s.set_meta("y0", BAR_TOP + PITCH * (i + 0.5))

	# --- wall key switch to the right of the door, conduit up and into the hood's end plate
	var bx := hw + 0.32
	_box(root, Vector3(0.11, 0.18, 0.045), Vector3(bx, 1.35, 0.0245), powder_box)
	_cyl(root, 0.017, 0.012, Vector3(bx, 1.39, 0.052), alu, Vector3(PI / 2, 0, 0))            # key cylinder
	_box(root, Vector3(0.006, 0.016, 0.004), Vector3(bx, 1.39, 0.059), seal)                  # its key slot
	for k in [0, 1]:   # up / down buttons
		_cyl(root, 0.011, 0.01, Vector3(bx, 1.31 - k * 0.035, 0.051), alu, Vector3(PI / 2, 0, 0))
	var led := StandardMaterial3D.new()
	led.albedo_color = Color(0.2, 1.0, 0.35)
	led.emission_enabled = true
	led.emission = Color(0.2, 1.0, 0.35)
	led.emission_energy_multiplier = 1.2
	_cyl(root, 0.003, 0.004, Vector3(bx + 0.035, 1.42, 0.048), led, Vector3(PI / 2, 0, 0))
	var grey := _scan(Color(0.5, 0.51, 0.52), 0.55, 0.0, 0.05, false, true)
	var cy := h0 + 0.2
	_cyl(root, 0.011, cy - 1.44, Vector3(bx, (1.44 + cy) / 2.0, 0.025), grey)                 # conduit up
	var run := bx - (hood_w / 2.0 + 0.008)
	_cyl(root, 0.011, run, Vector3(bx - run / 2.0, cy, 0.025), grey, Vector3(0, 0, PI / 2))   # and across
	_part(root, SphereMesh.new(), grey, Vector3(bx, cy, 0.025)).scale = Vector3.ONE * 0.022   # the elbow
	for y in [1.7, 2.4, 3.0]:   # saddle clips
		_box(root, Vector3(0.03, 0.012, 0.03), Vector3(bx, y, 0.02), alu_box)
	return curtain
