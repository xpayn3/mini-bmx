class_name RopeBridge
extends Node3D
## A swinging rope bridge high over a crevasse (route feature "rope"): four ropes tied to two pairs of stout
## log posts, planks lashed across the two deck ropes, hangers from the hand ropes. Simulated in C#
## (RopeBridgeSim.cs) every physics tick: it sags into a V under the rider, rolls when the weight is off
## centre, swings in the wind and from the rider's own sideways push, and its sideways swing carries the bike.
## The deck is part of Terrain.height() / deck_height() while this node lives (Terrain keeps the bridges near
## the rider). The node sits at the feature's start, turned so local x = along (u), z = across (w).

const SIM := "res://scripts/world/RopeBridgeSim.cs"
const N := 64              # segments per rope (the bridge is 72 m long)
const DECK_HALF := 1.1     # the deck ropes, +- across (planks overhang them a little); 2026-11-23 doubled (was 0.55)
const HAND_HALF := 1.6     # (was 0.8)
const HAND_H := 1.25       # hand ropes above the deck ends
const TREE_U := 2.4        # trees this far in from each end of the feature
const TREE_W := 2.0        # and this far to each side (was 1.16: 2.3 m apart, now 4 m round the wider deck)
## the deck starts / ends right at the canyon's lip (TerrainField.CANYON_RIM, exact within 4 m of the trail), a
## hair onto the ground. It used to start 1.1 m before the lip: that metre of deck sagged ~20 cm under the rim's
## ground, so the bike rode the ground, dropped onto the deck at the lip (front wheel off, nose down) and hit a
## 20 cm step at the far end (launched)
const DECK_IN := TerrainField.CANYON_RIM - 0.05
const LANDING := 6         # deck segments (~0.95 m each) at each end on a fixed landing ramp (RopeBridgeSim.Landing)
const DECK_LIFT := 0.01    # the deck's ends sit this far over the ground (no step for the tyres)
const SAG := 0.8           # the deck's own sag in the middle (m); the rider adds to it
const PLANK_STEP := 0.31
const PLANK_LEN := 0.22
const PLANK_THICK := 0.045
const WOOD := [Color(0.42, 0.31, 0.21), Color(0.36, 0.27, 0.19), Color(0.47, 0.37, 0.26), Color(0.33, 0.29, 0.24), Color(0.5, 0.41, 0.3)]

var feat_s := 0.0
var length := 0.0
var _x0 := 0.0
var _z0 := 0.0
var _dx := 1.0
var _dz := 0.0
var _u0 := 0.0
var _u1 := 0.0
var _ymax := 0.0
var sim
var _mm: MultiMesh
var _ropes: MeshInstance3D
var _rope_mesh: ArrayMesh
## built in stages over a few frames (Terrain._build_ropes): all at once it froze the ride for ~0.24 s as a
## bridge came within reach. Until `built` it is hidden and not part of the ground
var built := false
var _stage := 0
var _settled := 0
var _field
var _gy: Callable
var _r: WorldRng
var _cl_ws := 0.0
var _cl_gb: GeoBuf
var _cl_n := 0
const CLIFF_FLUSH := 6     # columns of wall rocks per mesh (one mesh of them all took ~40 ms to make)
const SETTLE := 360        # sim ticks to hang the ropes into shape before anyone sees them
const SETTLE_STEP := 60

## the materials, shared by every bridge and made once (Terrain.set_seed calls warm() while the ride loads):
## made new per bridge, the first bridge compiled their shaders mid-ride (~75 ms)
static var _mats := {}


static func available() -> bool:
	return ResourceLoader.exists(SIM)


static func warm() -> void:
	if not _mats.is_empty():
		return
	# ropes: three-strand twisted hemp on the tubes' UVs (shaders/rope_fiber.gdshader)
	var rope := ShaderMaterial.new()
	rope.shader = preload("res://shaders/rope_fiber.gdshader")
	_mats["rope"] = rope
	# deck planks: the fences' Wood049 plank scan; posts / braces / logs: the sign posts' Wood035 scan
	var plank := ShaderMaterial.new()
	plank.shader = preload("res://shaders/rope_wood.gdshader")
	plank.set_shader_parameter("wood_col", load("res://assets/textures/wood_plank/wood_color.jpg"))
	plank.set_shader_parameter("wood_nrm", load("res://assets/textures/wood_plank/wood_normal.jpg"))
	plank.set_shader_parameter("wood_rgh", load("res://assets/textures/wood_plank/wood_rough.jpg"))
	plank.set_shader_parameter("tile", 1.1)
	_mats["plank"] = plank
	var logm := ShaderMaterial.new()
	logm.shader = plank.shader
	logm.set_shader_parameter("wood_col", load("res://assets/textures/wood_post/wood_color.jpg"))
	logm.set_shader_parameter("wood_nrm", load("res://assets/textures/wood_post/wood_normal.jpg"))
	logm.set_shader_parameter("wood_rgh", load("res://assets/textures/wood_post/wood_rough.jpg"))
	logm.set_shader_parameter("log_mode", true)
	logm.set_shader_parameter("log_r", POST_R)
	logm.set_shader_parameter("tile", 0.9)
	logm.set_shader_parameter("scan_mean", Vector3(0.1261, 0.0752, 0.0482))
	_mats["log"] = logm
	var bark := StandardMaterial3D.new()   # vertex-coloured (the old canyon-wall rocks, unused)
	bark.vertex_color_use_as_albedo = true
	bark.roughness = 0.95
	bark.vertex_color_is_srgb = true
	_mats["bark"] = bark
	# a material's shader is only generated when an instance first takes it (~80 ms for these): do that now
	var mi := MultiMeshInstance3D.new()
	for k in _mats:
		mi.material_override = _mats[k]
	mi.free()


## j: a TerrainField.Feat of type "rope"; terrain: for the ground at the trees / anchors. All at once (tests, or a
## bridge right where the rider is); Terrain otherwise calls begin() and then build_step() a little each frame
func setup(j, terrain) -> void:
	begin(j, terrain)
	while not build_step():
		pass


## one bounded piece of the build (a few ms at most); true once the bridge is complete, drawn and rideable
func build_step() -> bool:
	match _stage:
		1:
			sim.Settle(SETTLE_STEP)
			_settled += SETTLE_STEP
			if _settled >= SETTLE:
				_stage = 2
		2:
			_build_deck()
			_stage = 3
		3:
			_build_trees(_gy, _r)
			_stage = 5   # no stone walls any more: the canyon is a wide grassy valley (_cliff_column kept, unused)
		4:
			if not _cliff_column():
				_stage = 5
		5:
			_draw(1.0)
			visible = true
			built = true
			_stage = 6
	return built


func begin(j, terrain) -> void:
	warm()
	visible = false
	_field = terrain.field
	feat_s = j.s
	length = j.len
	_x0 = j.x; _z0 = j.z; _dx = j.dx; _dz = j.dz
	transform = Transform3D(Basis(Vector3(_dx, 0, _dz), Vector3.UP, Vector3(-_dz, 0, _dx)), Vector3(_x0, 0, _z0))
	var fld = terrain.field
	var gy := func(u: float, w: float) -> float:
		return fld.ground(_x0 + _dx * u - _dz * w, _z0 + _dz * u + _dx * w)
	_gy = gy
	_u0 = DECK_IN
	_u1 = length - DECK_IN
	var y0: float = gy.call(_u0, 0.0) + DECK_LIFT
	var y1: float = gy.call(_u1, 0.0) + DECK_LIFT
	_ymax = maxf(y0, y1) + HAND_H + 2.0
	sim = load(SIM).new()
	if Env.s("BMX_ROPE_BEND") != "": sim.BendK = float(Env.s("BMX_ROPE_BEND"))      # tests
	if Env.s("BMX_ROPE_ANCHOR") != "": sim.AnchorK = float(Env.s("BMX_ROPE_ANCHOR"))
	sim.Landing = int(Env.s("BMX_ROPE_LAND")) if Env.s("BMX_ROPE_LAND") != "" else LANDING
	var sag: float = float(Env.s("BMX_ROPE_SAG")) if Env.s("BMX_ROPE_SAG") != "" else SAG
	sim.EndSlope0 = gy.call(_u0, 0.0) - gy.call(_u0 - 1.0, 0.0)
	sim.EndSlope1 = gy.call(_u1 + 1.0, 0.0) - gy.call(_u1, 0.0)
	sim.SettleTicks = 0   # settled in build_step, a slice per frame
	sim.Setup(N, _u0, y0, _u1, y1, DECK_HALF, sag, TREE_U + 0.2, length - TREE_U - 0.2, HAND_H, HAND_HALF, sag * 1.05, 7.0, 0.9)
	_r = WorldRng.new(WorldRng.i32f(j.x * 1000) ^ WorldRng.i32f(j.z * 7919) ^ 0x5eed)
	_stage = 1


func _build_deck() -> void:
	var r := _r
	# planks: a few gone, a few snapped (only half of it left), the rest a little skewed / uneven
	var pl := PackedFloat32Array()
	var u := _u0 + 0.15
	while u < _u1 - 0.1:
		var s := (u - _u0) / (_u1 - _u0) * N
		var roll := r.next()
		var c: Color = WOOD[int(r.next() * WOOD.size())].darkened(r.next() * 0.15)
		var over := 0.06 + r.next() * 0.05
		if roll < 0.035:
			pass   # missing (a tyre still rolls over a one-plank gap)
		elif roll < 0.07:
			if r.next() < 0.5:
				pl.append_array([s, -over, 0.35 + r.next() * 0.15, c.r, c.g, c.b])
			else:
				pl.append_array([s, 0.5 + r.next() * 0.15, 1.0 + over, c.r, c.g, c.b])
		else:
			pl.append_array([s + (r.next() - 0.5) * 0.03, -over, 1.0 + 0.06 + r.next() * 0.05, c.r, c.g, c.b])
		u += PLANK_STEP + (r.next() - 0.5) * 0.04
	sim.SetPlanks(pl, PLANK_LEN, PLANK_THICK)
	_build_planks(pl.size() / 6)
	_rope_mesh = ArrayMesh.new()
	_ropes = MeshInstance3D.new()
	_ropes.mesh = _rope_mesh
	_ropes.material_override = _mats["rope"]
	add_child(_ropes)


func _build_planks(count: int) -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = _plank_mesh()
	_mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.material_override = _mats["plank"]
	add_child(mi)


## one plank with rounded (bevelled) edges, made once: built at a plank's real size (PLANK_LEN x PLANK_THICK x
## PLANK_NOM) with its normals in metres, then the positions divided down to a unit box, because the MultiMesh scales
## each instance to its plank (RopeBridgeSim.PlankBuffer). shaders/rope_wood.gdshader divides the normal by the scale
## again in vertex(), so the edges stay round after the uneven stretch. Rounded box: each face a 3 x 3 grid whose
## outer rows sit on the edge and are pushed round it (q + r n); ~108 triangles
const PLANK_NOM := 2.35      # a plank's usual length across the deck (m)
const PLANK_BEVEL := 0.012   # edge radius (m)
static var _plank: ArrayMesh

static func _plank_mesh() -> ArrayMesh:
	if _plank != null:
		return _plank
	var hs := Vector3(PLANK_LEN, PLANK_THICK, PLANK_NOM) * 0.5
	var rr := minf(PLANK_BEVEL, hs.y * 0.6)
	var inner := hs - Vector3(rr, rr, rr)
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var a1 := (ax + 1) % 3
			var a2 := (ax + 2) % 3
			var s1 := [-hs[a1], -inner[a1], inner[a1], hs[a1]]
			var s2 := [-hs[a2], -inner[a2], inner[a2], hs[a2]]
			var base := v.size()
			for i in 4:
				for j in 4:
					var p := Vector3()
					p[ax] = sg * hs[ax]
					p[a1] = s1[i]
					p[a2] = s2[j]
					var q := p.clamp(-inner, inner)
					var nn := (p - q).normalized()
					v.append((q + nn * rr) / (hs * 2.0))
					n.append(nn)
			var fn := Vector3()
			fn[ax] = sg
			for i in 3:
				for j in 3:
					var a := base + i * 4 + j
					var b := a + 4
					var tri := [a, b, a + 1, a + 1, b, b + 1]
					# Godot's front faces are clockwise seen from outside: flip the quad if it isn't
					var e := ((v[b] - v[a]) * hs).cross((v[a + 1] - v[a]) * hs)
					if e.dot(fn) > 0.0:
						tri = [a, a + 1, b, a + 1, b + 1, b]
					idx.append_array(tri)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	_plank = ArrayMesh.new()
	_plank.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _plank


## at each end two stout log posts the ropes are tied to (no trees: strong sticks dug in, leaning back against the
## pull, user 2026-11-27): each post has a guy rope from its top back to a stake, a side brace, stones packed round its
## foot, the hand rope lashed round it at hand height and the deck rope's tail lashed round its foot. A log under each
## deck end carries the planks
const POST_R := 0.15
const POST_LEAN := 0.13     # rad, back away from the canyon
const ROPE_R := 0.017       # lashing / guy rope radius

func _build_trees(gy: Callable, r: WorldRng) -> void:
	var stones: Array = []   # [Transform3D, brightness] for each rock, all of one type (the world's own, RockGen)
	var rope := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	for end in [0, 1]:
		var back := -1.0 if end == 0 else 1.0   # away from the canyon
		for side in [-1.0, 1.0]:
			var u: float = TREE_U if end == 0 else length - TREE_U
			var w: float = side * TREE_W
			var g: float = gy.call(u, w)
			var du0: float = _u0 if end == 0 else _u1
			var hy: float = gy.call(du0, 0.0) + DECK_LIFT + HAND_H
			var ax := Vector3(back * sin(POST_LEAN + (r.next() - 0.5) * 0.04), 1.0, side * (0.03 + r.next() * 0.03)).normalized()
			var foot := Vector3(u, g, w)
			var top_h := maxf(hy - g, 1.0) + 0.5 + r.next() * 0.25   # height of its top above the ground
			var plen := top_h / ax.y
			_add_log(foot - ax * 0.6, ax, plen + 0.6, POST_R * (1.05 + r.next() * 0.1), POST_R * 0.85, r, 1.0)
			# side brace: from two thirds up the post down to the ground outside
			var bt := foot + ax * plen * 0.62
			var bf := Vector3(u + back * 0.3, 0.0, w + side * 1.35)
			bf.y = gy.call(bf.x, bf.z) - 0.25
			_add_log(bf, (bt - bf).normalized(), (bt - bf).length() + 0.05, 0.085, 0.07, r, 1.0)
			_coil(rope, bt - ax * 0.05, ax, POST_R + ROPE_R, 3.0)
			# guy rope from the post's top back to a stake
			var top := foot + ax * (plen - 0.12)
			var sx: float = u + back * (3.0 + r.next() * 0.6)
			var sz: float = w + side * (0.8 + r.next() * 0.5)
			var sg: float = gy.call(sx, sz)
			var sax := Vector3(back * 0.35, 1.0, side * 0.15).normalized()
			_add_log(Vector3(sx, sg - 0.35, sz), sax, 0.8, 0.055, 0.045, r, 1.0)
			var stake_tie := Vector3(sx, sg, sz) + sax * 0.28
			_coil(rope, top, ax, POST_R * 0.9 + ROPE_R, 3.0)
			_coil(rope, stake_tie, sax, 0.05 + ROPE_R, 2.5)
			_rope_line(rope, top + Vector3(back * POST_R, 0, 0), stake_tie - Vector3(back * 0.05, 0, 0), 0.04, ROPE_R)
			# hand rope lashed round the post at hand height, its end running into the lashing
			var hc := foot + ax * ((hy - g) / ax.y)
			_coil(rope, hc, ax, POST_R + ROPE_R, 4.0)
			var hu: float = TREE_U + 0.2 if end == 0 else length - TREE_U - 0.2
			_rope_line(rope, Vector3(hu, hy, side * HAND_HALF), hc - Vector3(0, 0, side * POST_R * 0.6), 0.0, 0.022)
			# the deck rope's tail from its pinned end to a lashing round the foot
			var fc := foot + ax * (0.35 / ax.y)
			_coil(rope, fc, ax, POST_R * 1.08 + ROPE_R, 4.0)
			var a := Vector3(du0, gy.call(du0, 0.0), side * DECK_HALF)
			_rope_line(rope, a, fc - Vector3(back * POST_R * 0.5, 0, side * POST_R * 0.7), 0.02, 0.026)
			# stones packed round the foot (half sunk), turned and squashed so no two look alike
			for k in 4 + int(r.next() * 3):
				var ang := r.next() * TAU
				var d: float = POST_R + 0.14 + r.next() * 0.2
				var at := Vector3(u + cos(ang) * d, 0.0, w + sin(ang) * d)
				var sc := 0.11 + r.next() * 0.11
				at.y = gy.call(at.x, at.z) - sc * 0.25
				var bs := Basis(Vector3.UP, r.next() * TAU).rotated(Vector3.RIGHT, (r.next() - 0.5) * 0.4)
				stones.append([Transform3D(bs.scaled(Vector3(sc, sc * (0.6 + r.next() * 0.3), sc * (0.9 + r.next() * 0.3))), at), 0.88 + r.next() * 0.24])
	# a log under each deck end the planks sit on
	for end in [0, 1]:
		var du: float = _u0 if end == 0 else _u1
		var hl := DECK_HALF + 0.35
		_add_log(Vector3(du, gy.call(du, 0.0) - 0.12, -hl), Vector3(0, 0, 1), hl * 2.0, 0.13, 0.12, r, 0.0)
	_add_stones(stones, r)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = rope.v
	arr[Mesh.ARRAY_NORMAL] = rope.n
	arr[Mesh.ARRAY_TEX_UV] = rope.uv
	arr[Mesh.ARRAY_INDEX] = rope.i
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var rmi := MeshInstance3D.new()
	rmi.mesh = am
	rmi.material_override = _mats["rope"]
	add_child(rmi)


## the stones as the world's rocks: RockGen's LOD0 mesh of the type that grows here (biome), its scan material
## (TerrainGeo "rock_<type>", MultiMesh custom data = brightness, moss)
func _add_stones(stones: Array, r: WorldRng) -> void:
	if stones.is_empty():
		return
	TerrainGeo.ensure()
	var c := world(TREE_U, 0.0)
	var t := _rock_here(c.x, c.y)
	var moss := 0.0 if t == "desert" else 0.25
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = RockGen.mesh(t, int(r.next() * RockGen.VARIANTS), 0)
	mm.instance_count = stones.size()
	for i in stones.size():
		mm.set_instance_transform(i, stones[i][0])
		var b: float = stones[i][1]
		mm.set_instance_custom_data(i, Color(b, b, b, moss))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = TerrainGeo.MAT.get("rock_" + t, TerrainGeo.MAT["rock"])
	add_child(mi)


## the rock type the biome grows at (x, z), as TerrainChunkBuilder._rock_type picks it (its strongest weight)
func _rock_here(x: float, z: float) -> String:
	var f = _field
	var keep := [f.b_dry, f.b_rug, f.b_cold, f.b_wet, f.b_forest, f.b_sav, f.b_ash, f._bi_x, f._bi_z]
	f.biome(x, z)
	var wt := {"basalt": f.b_ash * 1.6, "desert": f.b_dry * 1.3 + f.b_sav * 0.5,
		"tundra": f.b_cold * 1.4 + f.b_rug * 0.35 * (1.0 - f.b_dry), "granite": 0.35 + f.b_forest * 0.6 + f.b_wet * 0.4}
	f.b_dry = keep[0]; f.b_rug = keep[1]; f.b_cold = keep[2]; f.b_wet = keep[3]; f.b_forest = keep[4]
	f.b_sav = keep[5]; f.b_ash = keep[6]; f._bi_x = keep[7]; f._bi_z = keep[8]
	var best := "granite"
	for k in wt:
		if wt[k] > wt[best]:
			best = k
	return best


## a debarked log from `base` along `axis` (its own node: the wood shader maps the scan round its local y); foot_k 1 =
## darker and damp at the foot (dug-in posts), 0 = none (lying logs)
func _add_log(base: Vector3, axis: Vector3, ln: float, r0: float, r1: float, r: WorldRng, foot_k: float) -> void:
	var seg := 12
	var rows := 6
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var tone := Color(0.4, 0.33, 0.26).lerp(Color(0.5, 0.42, 0.33), r.next())
	tone.a = foot_k
	var wob := r.next() * TAU
	for iy in rows + 1:
		var t := float(iy) / rows
		var rad := lerpf(r0, r1, t) * (1.0 + 0.04 * sin(t * 9.0 + wob))
		for k in seg + 1:
			var a := float(k) / seg * TAU
			var d := Vector3(cos(a), 0, sin(a))
			v.append(d * rad + Vector3(0, t * ln, 0))
			n.append(d)
			c.append(tone)
	for iy in rows:
		for k in seg:
			var a0 := iy * (seg + 1) + k
			var b0 := a0 + seg + 1
			idx.append_array([a0, a0 + 1, b0, a0 + 1, b0 + 1, b0])
	# end caps (end grain)
	for cap in [0, 1]:
		var y := 0.0 if cap == 0 else ln
		var rad := r0 if cap == 0 else r1
		var up := Vector3(0, -1 if cap == 0 else 1, 0)
		var ci := v.size()
		v.append(Vector3(0, y, 0)); n.append(up); c.append(tone)
		for k in seg + 1:
			var a := float(k) / seg * TAU
			v.append(Vector3(cos(a) * rad, y, sin(a) * rad)); n.append(up); c.append(tone)
		for k in seg:
			if cap == 1:
				idx.append_array([ci, ci + 1 + k + 1, ci + 1 + k])
			else:
				idx.append_array([ci, ci + 1 + k, ci + 1 + k + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = _mats["log"]
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z).rotated(y, r.next() * TAU), base)
	add_child(mi)


## a rope tube through pts (UV.x = metres along / circumference, as RopeBridgeSim.Tube)
static func _tube(arr: Dictionary, pts: PackedVector3Array, rad: float, sides: int = 7) -> void:
	var start: int = arr.v.size()
	var along := 0.0
	var circ := TAU * rad
	var nprev := Vector3.ZERO
	for i in pts.size():
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		var t := (pts[mini(pts.size() - 1, i + 1)] - pts[maxi(0, i - 1)]).normalized()
		var nn := t.cross(Vector3.UP) if nprev == Vector3.ZERO else nprev - t * t.dot(nprev)
		if nn.length_squared() < 1e-6:
			nn = t.cross(Vector3.RIGHT)
		nn = nn.normalized()
		nprev = nn
		var b := t.cross(nn)
		for k in sides + 1:
			var a := float(k) / sides * TAU
			var d := nn * cos(a) + b * sin(a)
			arr.v.append(pts[i] + d * rad)
			arr.n.append(d)
			arr.uv.append(Vector2(along / circ, float(k) / sides))
	var row := sides + 1
	for i in pts.size() - 1:
		for k in sides:
			var a0 := start + i * row + k
			var b0 := a0 + row
			arr.i.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])


## a rope wound `turns` times round an axis (a lashing), a little helix climbing ~2 rope widths a turn
static func _coil(arr: Dictionary, centre: Vector3, axis: Vector3, radius: float, turns: float) -> void:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	var pts := PackedVector3Array()
	var steps := int(turns * 20)
	var rise := ROPE_R * 2.1
	for k in steps + 1:
		var t := float(k) / steps * turns
		var a := t * TAU
		pts.append(centre + (x * cos(a) + z * sin(a)) * radius + y * (t - turns * 0.5) * rise)
	_tube(arr, pts, ROPE_R)


## a rope from a to b hanging `sag` m in the middle
static func _rope_line(arr: Dictionary, a: Vector3, b: Vector3, sag: float, rad: float) -> void:
	var pts := PackedVector3Array()
	var n := maxi(2, int(a.distance_to(b) / 0.25))
	for k in n + 1:
		var t := float(k) / n
		pts.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))
	_tube(arr, pts, rad)


## the canyon's walls (TerrainField.canyon_rims) faced with layered rock: flattened boulders stacked down each
## wall, banded in sandstone tones by height like rock strata, a lip of them along the rims, some fallen on the floor
const STRATA := [Color(0.56, 0.33, 0.2), Color(0.47, 0.29, 0.19), Color(0.62, 0.42, 0.27), Color(0.4, 0.27, 0.2), Color(0.52, 0.38, 0.28)]
static var _rocks: Array = []

## one column of the walls across the canyon (at _cl_ws) into _cl_gb; false (and the mesh made) when all are done
func _cliff_column() -> bool:
	if _rocks.is_empty():
		for k in 4:
			_rocks.append(TerrainGeo._boulder(31 + k * 7, 1))
	var field = _field
	var r := _r
	var gb := _cl_gb
	var gy := _gy
	var ws := _cl_ws
	if ws < TerrainField.CANYON_W - 2.0:
		var cr: PackedFloat64Array = field.canyon_rims(feat_s, length, ws)
		var dep: float = cr[3]
		if dep > 1.2:
			for wall in [0, 1]:
				var dir := 1.0 if wall == 0 else -1.0       # which way the wall faces (into the canyon)
				var rim: float = cr[0] if wall == 0 else cr[1]
				var ww: float = cr[2]
				var top: float = gy.call(rim - dir * 0.3, ws)
				var bot: float = gy.call(rim + dir * (ww + 1.5), ws)
				var n := maxi(2, ceili((top - bot) / 1.25))
				for k in range(1, n + 1):
					var t := float(k) / n
					if absf(ws) < 2.2 and t < 0.3:
						continue   # under the bridge deck's ends: keep the rim clear
					var sz := 0.8 + r.next() * 0.8 + (0.5 if k == n else 0.0)
					# set into the wall, never standing above the rim
					var u := rim + dir * (ww * t - sz * 0.4)
					var y := minf(lerpf(top, bot, t), top - sz * 0.45)
					var band: Color = STRATA[posmod(floori(y / 1.3) + int(feat_s), STRATA.size())]
					_rock(gb, Vector3(u, y, ws + (r.next() - 0.5) * 0.8), Vector3(sz * 1.5, sz * 0.75, sz * 1.4), r, band.darkened(r.next() * 0.12))
				# a lip along the rim
				if absf(ws) > 5.0 and r.next() < 0.5:
					var lsz := 0.35 + r.next() * 0.4
					_rock(gb, Vector3(rim + dir * 0.1, gy.call(rim + dir * 0.1, ws) - lsz * 0.35, ws), Vector3(lsz * 1.4, lsz * 0.6, lsz * 1.4), r, STRATA[2])
			# fallen rocks on the floor
			if r.next() < 0.45:
				var fu := lerpf(cr[0] + cr[2], cr[1] - cr[2], r.next())
				var fsz := 0.4 + r.next() * 1.1
				_rock(gb, Vector3(fu, gy.call(fu, ws) + fsz * 0.2, ws), Vector3(fsz, fsz * 0.75, fsz), r, STRATA[int(r.next() * STRATA.size())].darkened(0.1))
		_cl_ws = ws + 1.9 + r.next() * 0.5
		_cl_n += 1
		if _cl_n % CLIFF_FLUSH == 0:
			_flush_cliffs()
		return true
	_flush_cliffs()
	return false


func _flush_cliffs() -> void:
	if _cl_gb.pos.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _cl_gb.to_mesh()
	mi.material_override = _mats["bark"]   # (the same vertex-colour, rough material)
	add_child(mi)
	_cl_gb = GeoBuf.new()


func _rock(gb: GeoBuf, at: Vector3, sc: Vector3, r: WorldRng, tint: Color) -> void:
	var g: GeoBuf = (_rocks[int(r.next() * _rocks.size())] as GeoBuf).copy()
	var bs := Basis(Vector3.UP, r.next() * TAU).rotated(Vector3.RIGHT, (r.next() - 0.5) * 0.3).scaled(sc)
	g.xform(bs, at)
	for i in g.col.size():
		var c := g.col[i]
		g.col[i] = Color(c.r * tint.r, c.g * tint.g, c.b * tint.b)
	gb.append(g)


static func _ring(radius: float, thick: float) -> GeoBuf:
	var g := GeoBuf.new()
	var seg := 14
	for k in seg:
		var a0 := k * TAU / seg
		var a1 := (k + 1) * TAU / seg
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		g.append(_rod(p0, p1, thick))
	return g


static func _rod(a: Vector3, b: Vector3, rad: float) -> GeoBuf:
	var d := b - a
	var l := d.length()
	var c := GeoBuf.cylinder(rad, rad, l, 6)
	var up := d / l
	var axis := Vector3.UP.cross(up)
	var bs := Basis()
	if axis.length() > 1e-4:
		bs = Basis(axis.normalized(), acos(clampf(Vector3.UP.dot(up), -1, 1)))
	elif up.y < 0:
		bs = Basis(Vector3.RIGHT, PI)
	return c.xform(bs, (a + b) * 0.5)


# ---------------------------------------------------------------- world <-> bridge frame

func local(x: float, z: float) -> Vector2:
	var rx := x - _x0
	var rz := z - _z0
	return Vector2(rx * _dx + rz * _dz, -rx * _dz + rz * _dx)


## the world (x, z) of a point in the bridge's frame
func world(u: float, w: float) -> Vector2:
	return Vector2(_x0 + _dx * u - _dz * w, _z0 + _dz * u + _dx * w)


## the deck's top under (x, z), -INF off it (a tyre's half width past the ropes still counts)
func deck_at(x: float, z: float) -> float:
	var rx := x - _x0
	var rz := z - _z0
	var u := rx * _dx + rz * _dz
	if u < _u0 - 0.5 or u > _u1 + 0.5:
		return -INF
	var w := -rx * _dz + rz * _dx
	if absf(w) > DECK_HALF + 1.5:
		return -INF
	var h: float = sim.HeightLevel(u, w, 0.06)   # level across: its roll is not a bank to the bike (RopeBridgeSim)
	return -INF if is_nan(h) else h


## (x, z) is just beside the swinging part of the deck (past the plank ends, within ~1.5 m) at about its height y
func off_side(x: float, z: float, y: float) -> bool:
	var l := local(x, z)
	if l.x < _u0 + 0.5 or l.x > _u1 - 0.5 or absf(l.y) > DECK_HALF + 1.5:
		return false
	if deck_at(x, z) > -INF:
		return false
	var c: float = sim.Height(l.x, 0.0, DECK_HALF + 1.5)
	return not is_nan(c) and absf(c - y) < 0.6


## (x, z) at about height y is between this bridge's ends, over its deck or just beside it (where the hangers +
## hand ropes fence it in): the bike is kept inside them (Game._rope_rail)
func fenced(x: float, z: float, y: float) -> bool:
	var l := local(x, z)
	# from a little before the deck starts (the hand ropes start at the trees): a bike rolling on at an angle has
	# its front over the drop while its middle is still on the rim
	if l.x < _u0 - 1.5 or l.x > _u1 + 1.5 or absf(l.y) > HAND_HALF + 0.6:
		return false
	var c: float = sim.Height(clampf(l.x, _u0 + 0.05, _u1 - 0.05), 0.0, DECK_HALF + 1.5)
	return not is_nan(c) and y > c - 0.6 and y < c + 1.2


## the bridge's own heading in the ride physics' convention (travel = (cos, -sin))
func axis_angle() -> float:
	return atan2(-_dz, _dx)


## the rider's weight + sideways push on the deck (world N): fy up, f_side a horizontal world vector
func push(x: float, z: float, fy: float, f_side: Vector3) -> void:
	var l := local(x, z)
	sim.AddLoad(l.x, l.y, fy, -f_side.x * _dz + f_side.z * _dx)


## world (dx, dz) the deck under (x, z) moved in the last tick
func carry(x: float, z: float) -> Vector2:
	var l := local(x, z)
	var c: Vector2 = sim.Carry(l.x, l.y)
	return Vector2(c.x * _dx - c.y * _dz, c.x * _dz + c.y * _dx)


func step(dt: float, wind: Vector3) -> void:
	sim.Step(dt, wind.x * _dx + wind.z * _dz, -wind.x * _dz + wind.z * _dx)


func _process(_dt: float) -> void:
	if built:
		_draw(Engine.get_physics_interpolation_fraction())


func _draw(a: float) -> void:
	_mm.buffer = sim.PlankBuffer(a)
	var arr: Array = sim.RopeMesh(a)
	var mesh_arr := []
	mesh_arr.resize(Mesh.ARRAY_MAX)
	mesh_arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(arr[0])
	mesh_arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(arr[1])
	mesh_arr[Mesh.ARRAY_INDEX] = PackedInt32Array(arr[2])
	mesh_arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(arr[3])
	_rope_mesh.clear_surfaces()
	_rope_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arr)
