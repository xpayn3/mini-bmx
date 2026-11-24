class_name RopeBridge
extends Node3D
## A swinging rope bridge high over a crevasse (route feature "rope"): four ropes tied round two pairs of big
## trees, planks lashed across the two deck ropes, hangers from the hand ropes. Simulated in C#
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
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.58, 0.48, 0.33)
	rope.roughness = 0.95
	rope.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["rope"] = rope
	for kv in [["plank", 0.9, false], ["bark", 0.95, false], ["leaves", 0.85, false], ["ties", 0.95, true]]:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = kv[1]
		if kv[2]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[kv[0]] = m
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
	_mm.mesh = BoxMesh.new()
	(_mm.mesh as BoxMesh).size = Vector3.ONE
	_mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.material_override = _mats["plank"]
	add_child(mi)


## four big pines the ropes are tied round, a rope lashing at each tie, and the short ropes from the
## deck ends down to the trunks' feet
func _build_trees(gy: Callable, r: WorldRng) -> void:
	var bark := GeoBuf.new()
	var leaves := GeoBuf.new()
	var ties := GeoBuf.new()
	var rope_c: Color = _mats["rope"].albedo_color
	for end in [0, 1]:
		for side in [-1.0, 1.0]:
			var u: float = TREE_U if end == 0 else length - TREE_U
			var w: float = side * TREE_W
			var g: float = gy.call(u, w)
			var h := 13.0 + r.next() * 4.0
			var lean := Vector3((r.next() - 0.5) * 0.04, 1, side * 0.03).normalized()
			var trunk := GeoBuf.cylinder(0.11, 0.36, h, 10, 6).translate(0, h * 0.5 - 0.3, 0)
			var roots := GeoBuf.new()
			for k in 5:
				var a := k * TAU / 5 + r.next()
				roots.append(GeoBuf.cone(0.16, 0.9, 5).rot_z(PI * 0.62).translate(0.32, 0.15, 0).rot_y(a))
			bark.append(GeoBuf.merge([trunk, roots]).paint(Color(0.17, 0.12, 0.09)).xform(Basis(Quaternion(Vector3.UP, lean)), Vector3(u, g, w)))
			var crown := GeoBuf.new()
			var tiers := 6
			for k in tiers:
				var f := float(k) / tiers
				var cr := lerpf(2.2, 0.6, f) * (0.9 + r.next() * 0.2)   # high and slim: the ride cameras look past it
				crown.append(GeoBuf.cone(cr, 2.2, 8).rot_y(r.next() * TAU).translate(0, lerpf(h * 0.6, h * 0.95, f), 0))
			var green := Color(0.05, 0.2, 0.09).lerp(Color(0.09, 0.26, 0.1), r.next())
			leaves.append(crown.paint(green).xform(Basis(Quaternion(Vector3.UP, lean)), Vector3(u, g, w)))
			# lashings: the hand rope wrapped round at hand height, the deck rope round the foot
			var du0: float = _u0 if end == 0 else _u1
			var hy: float = gy.call(du0, 0.0) + DECK_LIFT + HAND_H
			for wy in [hy, g + 0.35]:
				var tr: float = 0.36 - 0.25 * (wy - g + 0.3) / h + 0.025
				for k in 3:
					ties.append(_ring(tr, 0.026).paint(rope_c).translate(u + lean.x * (wy - g), wy + (k - 1) * 0.055, w + lean.z * (wy - g)))
			# the hand rope's end runs into its lashing round the trunk
			var hu: float = TREE_U + 0.2 if end == 0 else length - TREE_U - 0.2
			ties.append(_rod(Vector3(hu, hy, side * HAND_HALF), Vector3(u + lean.x * (hy - g), hy, w + lean.z * (hy - g)), 0.022).paint(rope_c))
			# the deck rope's tail from its pinned end down to the trunk's foot
			var du: float = _u0 if end == 0 else _u1
			var a := Vector3(du, gy.call(du, 0.0) + 0.0, side * DECK_HALF)
			var b := Vector3(u, g + 0.35, w - side * 0.3)
			ties.append(_rod(a, b, 0.026).paint(rope_c))
	# a log under each deck end the planks sit on
	for end in [0, 1]:
		var du: float = _u0 if end == 0 else _u1
		bark.append(GeoBuf.cylinder(0.13, 0.13, DECK_HALF * 2 + 0.7, 8).rot_x(PI / 2).paint(Color(0.34, 0.25, 0.17))
			.translate(du, gy.call(du, 0.0) - 0.12, 0))
	for gb in [[bark, "bark"], [leaves, "leaves"], [ties, "ties"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (gb[0] as GeoBuf).to_mesh(gb[0] == bark)
		mi.material_override = _mats[gb[1]]
		add_child(mi)


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
	_rope_mesh.clear_surfaces()
	_rope_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arr)
