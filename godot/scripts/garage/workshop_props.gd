class_name WorkshopProps
extends RefCounted
## The garage's workshop wall, a spare parts wall: hand tools hung on the pegboard (wrenches, screwdrivers,
## hex keys, hammer, pliers, tyre levers, a chain, tubes, a rotor, a chainring), our own parts lying on
## the bench (a fork, cranks, a saddle, a derailleur, a rotor), our framesets hung on the wall above
## it and on the right of the door, and spare wheels on hooks beside the door.
##
## Built after the garage is on screen, one piece a frame, the models loading on a worker thread
## (build_async), so opening the garage never waits for them.

const WALL := -4.075            # z of the back wall's inside face
const BENCH_TOP := 0.96         # y of the bench top
const PEG_Z := -4.04            # front face of the pegboard

## framesets on the wall: [glb, x, y, paint colour, finish]
const FRAMES := [   # two stacked like a shop rack between the pegboard and the door (in the showroom view)
	["res://assets/tues.glb", -2.72, 2.08, "#1f8a70", "metallic"],
	["res://assets/fuzz.glb", -2.72, 1.08, "#e8432e", "gloss"],
	["res://assets/seats/dh_frame.glb", 3.4, 2.15, "#f2f2ee", "gloss"],
]
const FRAMESET := ["frame", "swing", "seatstay", "rocker", "shock_body", "shock_spring", "shock_shaft"]

## parts on the bench: [glb, mesh names ([] = all), x, z, rotation (euler), extra lift]
const BENCH := [
	["res://assets/parts/tues_fork.glb", [], -5.55, -3.55, Vector3(0, 0.25, PI / 2), 0.0],
	["res://assets/parts/fuzz_cranks.glb", [], -4.75, -3.62, Vector3(PI / 2, 0.4, 0), 0.0],
	["res://assets/seats/saddle_fuzz.glb", [], -4.2, -3.75, Vector3(0, -0.5, 0), 0.0],
	["res://assets/parts/tues_derailleur.glb", [], -6.05, -3.75, Vector3(PI / 2, 0, 0.3), 0.0],
	["res://assets/forks/rotor_tues.glb", ["rotor_front"], -4.25, -3.38, Vector3(PI / 2, 0, 0), 0.0],
]

## on the pegboard: [glb, mesh names, x, y]
const PEG_PARTS := [
	["res://assets/forks/rotor_tues.glb", ["rotor_rear"], -5.62, 1.52],
]

static func build_async(garage: Node3D) -> void:
	var paths := {}
	for f in FRAMES: paths[f[0]] = true
	for b in BENCH: paths[b[0]] = true
	for p in PEG_PARTS: paths[p[0]] = true
	for p in paths: ResourceLoader.load_threaded_request(p)
	var tree := garage.get_tree()
	var root := Node3D.new()
	root.name = "Workshop"
	garage.add_child(root)
	_neon(root)
	_pegboard_tools(root)
	await tree.process_frame
	if not is_instance_valid(root): return
	_wheels(root)
	await tree.process_frame
	var jobs := []
	for f in FRAMES: jobs.append(["frame", f])
	for b in BENCH: jobs.append(["bench", b])
	for p in PEG_PARTS: jobs.append(["peg", p])
	var got := {}   # a threaded load can be collected once: files used twice come from here
	for j in jobs:
		var path: String = j[1][0]
		if not got.has(path):
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await tree.process_frame
				if not is_instance_valid(root): return
			got[path] = ResourceLoader.load_threaded_get(path)
		var res := got[path] as PackedScene
		if res == null or not is_instance_valid(root): continue
		match j[0]:
			"frame": _frame(root, res, j[1])
			"bench": _bench_part(root, res, j[1])
			"peg": _peg_part(root, res, j[1])
		await tree.process_frame

# ---------------------------------------------------------------- helpers
static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

static func _box(p: Node3D, size: Vector3, at: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = size
	var mi := MeshInstance3D.new(); mi.mesh = b; mi.material_override = m
	mi.position = at; mi.rotation = rot
	p.add_child(mi)
	return mi

static func _cyl(p: Node3D, r: float, h: float, at: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new(); c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = 16
	var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = m
	mi.position = at; mi.rotation = rot
	p.add_child(mi)
	return mi

static func _ring(p: Node3D, r_in: float, r_out: float, at: Vector3, m: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var t := TorusMesh.new(); t.inner_radius = r_in; t.outer_radius = r_out; t.rings = 32; t.ring_segments = 8
	var mi := MeshInstance3D.new(); mi.mesh = t; mi.material_override = m
	mi.position = at; mi.rotation = Vector3(PI / 2, 0, 0); mi.scale = scale   # lying flat on the wall
	p.add_child(mi)
	return mi

## a peg sticking out of the board (what each tool hangs on)
static func _peg(p: Node3D, x: float, y: float, steel: Material) -> void:
	_cyl(p, 0.003, 0.05, Vector3(x, y, PEG_Z + 0.025), steel, Vector3(PI / 2, 0, 0))

## an instanced glb with only `keep` meshes shown, turned by `rot`, as one node; its world box
static func _instance(root: Node3D, res: PackedScene, keep: Array, rot: Vector3) -> Array:
	var holder := Node3D.new()
	root.add_child(holder)
	var n: Node3D = res.instantiate()
	holder.add_child(n)
	holder.rotation = rot
	var box := AABB(); var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not keep.is_empty() and not keep.has(String(m.name)):
			m.visible = false
			continue
		var bb := m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	return [holder, box]

# ---------------------------------------------------------------- pegboard
static func _pegboard_tools(root: Node3D) -> void:
	var chrome := _mat(Color(0.78, 0.8, 0.83), 0.18, 1.0)
	var steel := _mat(Color(0.32, 0.33, 0.36), 0.35, 1.0)
	var black := _mat(Color(0.05, 0.05, 0.055), 0.6)
	var red := _mat(Color("c0392b"), 0.4)
	var yellow := _mat(Color("f2b705"), 0.45)
	var blue := _mat(Color("2f7de1"), 0.45)
	var wood := _mat(Color("8a5a32"), 0.6)
	# the board's holes: a dark dot every 25 mm
	_box(root, Vector3(2.6, 1.3, 0.004), Vector3(-5.0, 1.8, PEG_Z + 0.002), _holes_mat())
	# combination wrenches, 8 to 19 mm, smallest left
	for i in 8:
		var x := -6.15 + i * 0.065
		var L := 0.13 + i * 0.018
		var top := 2.36
		_peg(root, x, top + 0.01, steel)
		_box(root, Vector3(0.012 + i * 0.0012, L, 0.005), Vector3(x, top - L * 0.5, PEG_Z + 0.008), chrome)
		_ring(root, 0.007 + i * 0.0007, 0.012 + i * 0.001, Vector3(x, top - 0.004, PEG_Z + 0.008), chrome)
		_box(root, Vector3(0.022 + i * 0.0015, 0.016, 0.006), Vector3(x, top - L, PEG_Z + 0.008), chrome)   # open end
	# screwdrivers, handle up
	var handles := [red, yellow, black, blue, red]
	for i in 5:
		var x := -5.52 + i * 0.065
		var sl := 0.1 + (i % 3) * 0.035
		_peg(root, x, 2.37, steel)
		_cyl(root, 0.015, 0.1, Vector3(x, 2.31, PEG_Z + 0.02), handles[i])
		_cyl(root, 0.0035, sl, Vector3(x, 2.26 - sl * 0.5, PEG_Z + 0.02), chrome)
	# hammer: head across the top of its handle
	_peg(root, -5.12, 2.36, steel)
	_box(root, Vector3(0.024, 0.3, 0.02), Vector3(-5.12, 2.17, PEG_Z + 0.014), wood)
	_box(root, Vector3(0.12, 0.034, 0.03), Vector3(-5.12, 2.33, PEG_Z + 0.02), steel)
	# pliers: two arms, red grips
	for s in [-1.0, 1.0]:
		var arm := _box(root, Vector3(0.016, 0.2, 0.008), Vector3(-4.86 + s * 0.012, 2.2, PEG_Z + 0.01), steel, Vector3(0, 0, s * 0.09))
		_box(root, Vector3(0.022, 0.11, 0.012), Vector3(-4.86 + s * 0.022, 2.13, PEG_Z + 0.012), red, Vector3(0, 0, s * 0.09))
		arm.name = "plier"
	_peg(root, -4.86, 2.34, steel)
	# hex keys (L), biggest right
	for i in 7:
		var x := -4.66 + i * 0.03
		var r := 0.0022 + i * 0.0005
		var L := 0.08 + i * 0.013
		_cyl(root, r, L, Vector3(x, 2.33 - L * 0.5, PEG_Z + 0.01), black)
		_cyl(root, r, 0.035 + i * 0.003, Vector3(x + 0.016, 2.33, PEG_Z + 0.01), black, Vector3(0, 0, PI / 2))
	_box(root, Vector3(0.24, 0.012, 0.03), Vector3(-4.57, 2.345, PEG_Z + 0.015), black)   # the key holder
	# tyre levers
	for i in 3:
		_box(root, Vector3(0.022, 0.11, 0.006), Vector3(-4.2 + i * 0.03, 2.27, PEG_Z + 0.008), [yellow, blue, black][i], Vector3(0, 0, -0.08 + i * 0.08))
	_peg(root, -4.17, 2.34, steel)
	# lower row: spare tubes (hung loops), a chain, the chainring, a cable coil
	for i in 2:
		_peg(root, -5.42 + i * 0.12, 1.86, steel)
		_ring(root, 0.17, 0.185, Vector3(-5.42 + i * 0.12, 1.68 - i * 0.02, PEG_Z + 0.02 + i * 0.012), black, Vector3(0.62, 1, 1.15))
	_peg(root, -4.8, 1.86, steel)
	_ring(root, 0.118, 0.128, Vector3(-4.8, 1.62, PEG_Z + 0.015), steel, Vector3(0.55, 1, 1.9))   # a chain hung on a peg
	# chainrings: flat rings (a torus squashed to 4 mm)
	for i in 2:
		var cr := 0.105 - i * 0.02
		_peg(root, -4.12 + i * 0.06, 1.62 + cr + 0.006 - i * 0.04, steel)
		_ring(root, cr - 0.02, cr, Vector3(-4.12 + i * 0.06, 1.62 - i * 0.04, PEG_Z + 0.008 + i * 0.006),
			chrome if i == 0 else _mat(Color("1b1b1d"), 0.35, 0.8), Vector3(1, 0.12, 1))
	_ring(root, 0.07, 0.085, Vector3(-3.92, 1.3, PEG_Z + 0.02), _mat(Color(0.12, 0.12, 0.13), 0.5))   # brake hose coil
	# a spare cassette on its own peg
	var cas := MeshInstance3D.new()
	cas.mesh = WheelGen.build_cassette([11, 13, 15, 17, 19, 21, 24, 28, 32, 36, 42, 50], [], 0.2)
	cas.position = Vector3(-5.95, 1.5, PEG_Z + 0.03)
	root.add_child(cas)
	_peg(root, -5.95, 1.5, steel)

static func _holes_mat() -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length()
			var a := clampf(5.5 - d, 0.0, 1.0)   # a soft-edged hole, ~6 mm across at 25 mm spacing
			img.set_pixel(x, y, Color(0.08, 0.06, 0.04, a * 0.85))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 0.025
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 1.0
	return m

# ---------------------------------------------------------------- the shop's neon sign
## GNARWHAL CYCLES (a made-up shop), all bent glass tube: a neon wheel (rim, hub, eight spokes) as the
## logo, the name in blue tube capitals (NeonText), "cycles . est. 2026" in a pink tube line under it,
## dark electrode caps where the tubes go back into the sign, on clear acrylic on standoffs, on the brick
## right of the door. Glows through the garage's HDR glow, washes the wall blue, and now and then
## flickers like an old transformer.
const NEON_AT := Vector3(3.55, 3.4, WALL)
const NEON_BLUE := Color(0.2, 0.62, 1.0)
const NEON_PINK := Color(1.0, 0.3, 0.75)

static func _neon_mat(core: Color, glow: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()   # glass tube: near-white core, coloured glow
	m.albedo_color = core
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = 7.0
	m.roughness = 0.2
	return m

static func _neon(root: Node3D) -> void:
	var neon := Node3D.new()
	neon.name = "NeonSign"
	neon.position = NEON_AT + Vector3(0, 0, 0.05)
	root.add_child(neon)
	var blue := _neon_mat(Color(0.75, 0.92, 1.0), NEON_BLUE)
	var pink := _neon_mat(Color(1.0, 0.8, 0.95), NEON_PINK)
	var cap_mat := _mat(Color(0.05, 0.05, 0.06), 0.4, 0.3)
	# the logo: a wheel, rim + hub + eight spokes
	var icon := Node3D.new()
	icon.position = Vector3(-1.0, 0.0, 0)
	neon.add_child(icon)
	var rim := TorusMesh.new(); rim.inner_radius = 0.17; rim.outer_radius = 0.19; rim.rings = 64; rim.ring_segments = 10
	var rmi := MeshInstance3D.new(); rmi.mesh = rim; rmi.material_override = blue; rmi.rotation.x = PI / 2
	icon.add_child(rmi)
	var hub := TorusMesh.new(); hub.inner_radius = 0.018; hub.outer_radius = 0.036; hub.rings = 24; hub.ring_segments = 8
	var hmi := MeshInstance3D.new(); hmi.mesh = hub; hmi.material_override = blue; hmi.rotation.x = PI / 2
	icon.add_child(hmi)
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		var sp := CylinderMesh.new(); sp.top_radius = 0.006; sp.bottom_radius = 0.006; sp.height = 0.14
		var smi := MeshInstance3D.new(); smi.mesh = sp; smi.material_override = blue
		smi.position = Vector3(cos(a), sin(a), 0) * 0.105
		smi.rotation.z = a - PI / 2
		icon.add_child(smi)
	# the name and the line under it, bent from tube
	var t1 := NeonText.build("GNARWHAL", 0.3, 0.011)
	var t2 := NeonText.build("cycles · est. 2026", 0.13, 0.008, 0.16)
	var x0 := -0.7
	for part in [[t1, blue, Vector3(x0, -0.02, 0)], [t2, pink, Vector3(x0 + 0.05, -0.27, 0)]]:
		var g := MeshInstance3D.new(); g.mesh = part[0].mesh; g.material_override = part[1]; g.position = part[2]
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		neon.add_child(g)
		var c := MeshInstance3D.new(); c.mesh = part[0].caps; c.material_override = cap_mat; c.position = part[2]
		neon.add_child(c)
	var right: float = x0 + maxf(t1.width, t2.width)
	# clear acrylic backing on four steel standoffs
	var acr := StandardMaterial3D.new()
	acr.albedo_color = Color(0.8, 0.9, 1.0, 0.08)
	acr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	acr.roughness = 0.05
	var left := -1.27
	var back := BoxMesh.new(); back.size = Vector3(right - left + 0.12, 0.8, 0.008)
	var bmi := MeshInstance3D.new(); bmi.mesh = back; bmi.material_override = acr
	bmi.position = Vector3((left + right) * 0.5, -0.03, -0.05)
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	neon.add_child(bmi)
	var steel := _mat(Color(0.7, 0.72, 0.75), 0.25, 1.0)
	for sx in [left, right + 0.04]:
		for sy in [-0.38, 0.32]:
			_cyl(neon, 0.008, 0.05, Vector3(sx, sy, -0.075), steel, Vector3(PI / 2, 0, 0))
	# the light it throws on the brick and round the corner of the door
	var glow := OmniLight3D.new()
	glow.light_color = NEON_BLUE
	glow.light_energy = 1.6
	glow.omni_range = 3.2
	glow.omni_attenuation = 1.6
	glow.light_volumetric_fog_energy = 0.4
	glow.position = Vector3((left + right) * 0.5, 0.0, 0.35)
	neon.add_child(glow)
	# now and then a flicker, like an old neon transformer (the blue tubes)
	var tw := neon.create_tween().set_loops()
	tw.tween_interval(6.5)
	for step in [[0.25, 0.05], [1.0, 0.06], [0.15, 0.04], [1.0, 0.0]]:
		tw.tween_callback(func():
			if not is_instance_valid(neon): return
			blue.emission_energy_multiplier = 7.0 * step[0]
			glow.light_energy = 1.6 * step[0])
		if step[1] > 0.0: tw.tween_interval(step[1])

# ---------------------------------------------------------------- wheels by the door
static func _wheels(root: Node3D) -> void:
	var hook := _mat(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	var specs := [   # above the pegboard
		[{"rim_color": Color(0.17, 0.17, 0.18)}, -5.75, 3.08],
		[{"rim_color": Color("2f7de1"), "rim_finish": "gloss", "sidewall": "tan", "rear": true}, -4.95, 3.06],
		[{"rim_color": Color("d4a017"), "rim_finish": "gloss"}, -4.15, 3.08],
	]
	for s in specs:
		var mesh := WheelGen.build(s[0])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var r := WheelGen.tyre_radius(s[0])
		mi.position = Vector3(s[1], s[2], WALL + 0.09)
		mi.rotation.z = randf() * TAU
		root.add_child(mi)
		# the hook it hangs from, through the top of the rim
		_cyl(root, 0.008, 0.11, Vector3(s[1], s[2] + r - 0.035, WALL + 0.055), hook, Vector3(PI / 2, 0, 0))

# ---------------------------------------------------------------- framesets on the wall
static func _frame(root: Node3D, res: PackedScene, f: Array) -> void:
	# hung level: the line through its (hidden) axles horizontal, as the bike stands
	var tmp: Node3D = res.instantiate()
	root.add_child(tmp)
	var wf := tmp.find_child("wheel_front", true, false) as Node3D
	var wr := tmp.find_child("wheel_rear", true, false) as Node3D
	var level := 0.0
	if wf and wr:
		var a := wf.global_position - wr.global_position
		level = -atan2(a.y, a.x)
	tmp.queue_free()
	var r := _instance(root, res, FRAMESET, Vector3(0, 0, level))
	var holder: Node3D = r[0]
	var box: AABB = r[1]
	var paint := BikeBuild.paint_material({"color": f[3], "color2": f[3], "finish": f[4]})
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null: continue
		for i in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(i)
			if sm and sm.resource_name == "paint": m.set_surface_override_material(i, paint)
	# centred on its spot, its back side just off the wall
	var c := box.get_center()
	holder.position += Vector3(f[1] - c.x, f[2] - c.y, WALL + 0.06 + box.size.z * 0.5 - c.z)
	# two black wall hooks under the top tube
	var hook := _mat(Color(0.08, 0.08, 0.09), 0.5, 0.5)
	for dx in [-0.18, 0.18]:
		_cyl(root, 0.012, 0.12, Vector3(f[1] + dx, f[2] + box.size.y * 0.3, WALL + 0.06), hook, Vector3(PI / 2, 0, 0))

# ---------------------------------------------------------------- parts
static func _bench_part(root: Node3D, res: PackedScene, b: Array) -> void:
	var r := _instance(root, res, b[1], b[4])
	var holder: Node3D = r[0]
	var box: AABB = r[1]
	var c := box.get_center()
	holder.position += Vector3(b[2] - c.x, BENCH_TOP + b[5] - box.position.y, b[3] - c.z)

static func _peg_part(root: Node3D, res: PackedScene, p: Array) -> void:
	var r := _instance(root, res, p[1], Vector3.ZERO)
	var holder: Node3D = r[0]
	var box: AABB = r[1]
	var c := box.get_center()
	holder.position += Vector3(p[2] - c.x, p[3] - c.y, PEG_Z + 0.02 - c.z)
	_peg(root, p[2], p[3] + box.size.y * 0.5 - 0.01, _mat(Color(0.32, 0.33, 0.36), 0.35, 1.0))
