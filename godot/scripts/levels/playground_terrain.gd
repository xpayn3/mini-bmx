class_name PlaygroundTerrain
extends Terrain
## The test playground (LEVELS > TEST PLAYGROUND, BMX_LEVEL=playground) in the ride's Terrain slot: the same API
## the bike, rider, camera, fx and HUD use (height, deck_height, top_height, surface, jump_mask, trail, ...),
## answered from PlaygroundCourse instead of the procedural world. No chunks, trees, rocks, water, ropes, sheep or
## trail: the ground is built once (lane strips + bowls at fine resolution, the rest a coarse flat plane) with a
## measuring grid, plus a sign at every feature. The base Terrain still sets up its field (and keeps an EMPTY trail
## course in it), so code that looks at the trail finds none and falls back to the bike's heading.

const GRASS := Color(0.40, 0.47, 0.31)
const DIRT := Color(0.58, 0.45, 0.32)
const CLAY := Color(0.66, 0.46, 0.30)
const SURF_COL := [Color(0.36, 0.50, 0.28), Color(0.58, 0.45, 0.32), Color(0.30, 0.24, 0.18), Color(0.86, 0.76, 0.52)]   # grass, dirt, wet, sand
const FAR := 2400.0            # the flat plane goes out this far (the fog hides the edge)

var course: PlaygroundCourse
var _built := false
var _mat: ShaderMaterial


func _init(seed_in := 12345) -> void:
	course = PlaygroundCourse.new()
	if Env.s("BMX_PG_SUITE") == "": course.load_ramps()   # (the ramp editor's ramps; the baseline suite rides without them)
	super(seed_in)


func set_seed(seed_in: int) -> void:
	super(seed_in)
	field.course = TrailCourse.new()   # no trail: alerts, the trail camera and "back on the trail" find nothing
	field.route_feats = []
	water_enabled = false
	cs_tyres = false   # its own ground (top_height below): the drawn tyres sample it in GDScript


func update_stream(_px: float, _pz: float, _budget_ms: float = 4.0, _sync_r := -1) -> void:
	if _built: return
	_built = true
	var t0 := Time.get_ticks_msec()
	_build_ground()
	_build_rocks()
	_build_signs()
	for r in course.ramps: refresh_ramp(r)
	chunk_serial += 1
	print("PLAYGROUND built ms=", Time.get_ticks_msec() - t0, " lanes=", course.lanes.size(), " features=", course.feats.size())


func stream_complete() -> bool:
	return _built


func _update_ropes() -> void:
	pass


func update_water(_px: float, _pz: float, _t: float) -> void:
	pass


func water_near(_px: float, _pz: float, _reach: float) -> bool:
	return false


# ---- physics queries -------------------------------------------------------------------------------------
func _height0(x: float, z: float) -> float:
	return course.height(x, z)

func height(x: float, z: float) -> float:
	return course.height_rocks(x, z) - rut_at(x, z)   # (domes over the ROCKS lane's rocks, as in the world; ruts dug in)

func deck_height(x: float, z: float) -> float:
	return course.height(x, z) - rut_at(x, z)

func mesh_height(x: float, z: float) -> float:
	return course.height(x, z)

func top_height(x: float, z: float) -> float:
	return course.height_rocks(x, z) - rut_at(x, z)

func grid_height(x: float, z: float) -> float:
	return course.height(x, z)

## 1 (trail: hard-packed dirt, dust) on built ground, 0 (grass) on the plane
func surface(x: float, z: float) -> int:
	var sf := course.surface_at(x, z)   # (brake strips: grass / wet / sand)
	if sf >= 0: return sf
	return 1 if course.is_dirt(x, z) else 0

func jump(x: float, z: float) -> Array:
	var h := course.height(x, z)
	return [h, course.jump_mask(x, z), 0.0, 0.0, null]

func jump_mask(x: float, z: float) -> float:
	return course.jump_mask(x, z)

## the lane / bowl you are on: the HUD's area name and the area banner
func biome_name(x: float, z: float) -> String:
	var l = course.lane_at(x, z)
	if l != null: return "Playground · " + l.title.capitalize()
	var f = course.feature_at(x, z)
	if f != null and f.has("bowl"): return "Playground · Berms"
	return "Test Playground"

func ground_color(x: float, z: float, _ny: float = 1.0) -> Color:
	var sf := course.surface_at(x, z)
	if sf >= 0: return SURF_COL[sf]
	return DIRT if course.is_dirt(x, z) else GRASS

func trail(x: float, z: float) -> float:
	return 1.0 if course.is_dirt(x, z) else 0.0

func colliders_near(x: float, z: float) -> Array:
	return course.rocks_near(x, z)

func take_pack(_x: float, _y: float, _z: float, _r: float = 1.6):
	return null

## the start (BMX_PG_AT=<feature id or lane id> picks another): (x, heading, z) as Game.respawn takes it
func level_spawn() -> Vector3:
	var at := Env.s("BMX_PG_AT")
	if at != "":
		var f = course.feature_by_id(at)
		if f == null:
			var l = course.lane_by_id(at)
			if l != null: return Vector3(PlaygroundCourse.X0 + 4.0, 0.0, l.z)
			push_warning("BMX_PG_AT: no feature / lane '%s'" % at)
		else:
			return course.spawn_for(f, float(Env.s("BMX_PG_BACK")) if Env.s("BMX_PG_BACK") != "" else 25.0)
	return course.default_spawn()

## the bail tap ("back on the trail"): on a lane, 25 m before the feature you are at (try it again); else the start
func level_reset(x: float, z: float) -> Vector3:
	var f = course.feature_at(x, z)
	if f == null:
		var l = course.lane_at(x, z)
		if l != null:   # between features: the next one along
			for g in l.feats:
				if g.u0 > x - PlaygroundCourse.X0: f = g; break
	if f != null: return course.spawn_for(f)
	return course.default_spawn()


# ---- the drawn ground ---------------------------------------------------------------------------------------
func _build_ground() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/playground_ground.gdshader")
	for l in course.lanes:
		_add_mesh(_lane_mesh(l), "Lane_" + l.id)
	for b in course.bowls:
		_add_mesh(_grid_mesh(b.rect, 0.4, 0.4), "Bowl_" + b.id)
	_add_mesh(_plane_mesh(), "Plane")


## the ROCKS lane: the world's own rock / pebble meshes, placed as TerrainChunkBuilder places a rock garden's
func _build_rocks() -> void:
	TerrainGeo.ensure()
	var root := Node3D.new()
	root.name = "Rocks"
	add_child(root)
	for c in course.rocks:
		var mi := MeshInstance3D.new()
		var nm := "pebble" if c.sc < 0.2 else "rock"
		mi.mesh = TerrainGeo.MESH[nm]
		mi.material_override = TerrainGeo.MAT.get("rock_plain", TerrainGeo.MAT["rock"])
		mi.transform = Transform3D(Basis(Vector3.UP, c.yaw).scaled_local(Vector3(c.sx, c.sy, c.sc)), Vector3(c.x, -c.sc * 0.3, c.z))
		root.add_child(mi)


func _add_mesh(m: ArrayMesh, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	mi.material_override = _mat
	mi.layers = 1 | GROUND_LAYER
	add_child(mi)


## rows along x: fine (0.1 m) wherever the profile is not flat, coarse (2 m) on the flat run-ins
func _lane_mesh(l) -> ArrayMesh:
	var r: Rect2 = l.rect
	var xs := PackedFloat64Array()
	var x := r.position.x
	var x_end := r.end.x
	while x < x_end - 1e-6:
		xs.append(x)
		var uu: float = x - PlaygroundCourse.X0
		var busy := false
		for k in range(-6, 7):   # anything non-flat within 0.6 m (incl. camber)
			var q: float = uu + k * 0.1
			if absf(l.profile(q)) > 1e-4 or (not l.camber.is_empty() and l.tilt_at(q) != 0.0) or absf(l.profile(q) - l.profile(q + 0.05)) > 1e-5:
				busy = true; break
		for sk in l.skews:   # a hip's shape reaches up to (half width + batter) x tan along u at the edges
			if uu > sk[0] - 7.0 and uu < sk[1] + 7.0: busy = true
		x += 0.1 if busy else 2.0
	xs.append(x_end)
	var zs := PackedFloat64Array()
	var z := r.position.y
	while z < r.end.y - 1e-6:
		zs.append(z)
		z += 0.5
	zs.append(r.end.y)
	return _mesh_from(xs, zs)


func _grid_mesh(r: Rect2, dx: float, dz: float) -> ArrayMesh:
	var xs := PackedFloat64Array(); var zs := PackedFloat64Array()
	var x := r.position.x
	while x < r.end.x - 1e-6: xs.append(x); x += dx
	xs.append(r.end.x)
	var z := r.position.y
	while z < r.end.y - 1e-6: zs.append(z); z += dz
	zs.append(r.end.y)
	return _mesh_from(xs, zs)


func _mesh_from(xs: PackedFloat64Array, zs: PackedFloat64Array) -> ArrayMesh:
	var nx := xs.size(); var nz := zs.size()
	var H := PackedFloat32Array(); H.resize(nx * nz)
	for j in nz:
		for i in nx:
			H[j * nx + i] = course.height(xs[i], zs[j])
	var V := PackedVector3Array(); V.resize(nx * nz)
	var N := PackedVector3Array(); N.resize(nx * nz)
	var C := PackedColorArray(); C.resize(nx * nz)
	var grass := GRASS.srgb_to_linear(); var dirt := DIRT.srgb_to_linear(); var clay := CLAY.srgb_to_linear()
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var h := H[k]
			V[k] = Vector3(xs[i], h, zs[j])
			var i0 := maxi(0, i - 1); var i1 := mini(nx - 1, i + 1)
			var j0 := maxi(0, j - 1); var j1 := mini(nz - 1, j + 1)
			var gx := (H[j * nx + i1] - H[j * nx + i0]) / maxf(1e-4, xs[i1] - xs[i0])
			var gz := (H[j1 * nx + i] - H[j0 * nx + i]) / maxf(1e-4, zs[j1] - zs[j0])
			N[k] = Vector3(-gx, 1.0, -gz).normalized()
			var sf := course.surface_at(xs[i], zs[j])
			if sf >= 0: C[k] = (SURF_COL[sf] as Color).srgb_to_linear()
			elif absf(h) > 0.02: C[k] = clay
			elif course.is_dirt(xs[i], zs[j]): C[k] = dirt
			else: C[k] = grass
	var I := PackedInt32Array(); I.resize((nx - 1) * (nz - 1) * 6)
	var p := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			I[p] = a; I[p + 1] = a + 1; I[p + 2] = a + nx
			I[p + 3] = a + 1; I[p + 4] = a + nx + 1; I[p + 5] = a + nx
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## the flat: 4 m cells over the playground except where a lane / bowl strip lies, then four big quads out to FAR
func _plane_mesh() -> ArrayMesh:
	var holes: Array = []
	for l in course.lanes: holes.append(l.rect)
	for b in course.bowls: holes.append(b.rect)
	var B := course.bounds
	var V := PackedVector3Array(); var I := PackedInt32Array()
	var s := PlaygroundCourse.SNAP
	var cz := B.position.y
	while cz < B.end.y - 1e-6:
		var cx := B.position.x
		while cx < B.end.x - 1e-6:
			var cell := Rect2(cx + 0.01, cz + 0.01, s - 0.02, s - 0.02)
			var hole := false
			for hr in holes:
				if (hr as Rect2).intersects(cell): hole = true; break
			if not hole: _quad(V, I, cx, cz, cx + s, cz + s)
			cx += s
		cz += s
	_quad(V, I, -FAR, -FAR, FAR, B.position.y)
	_quad(V, I, -FAR, B.end.y, FAR, FAR)
	_quad(V, I, -FAR, B.position.y, B.position.x, B.end.y)
	_quad(V, I, B.end.x, B.position.y, FAR, B.end.y)
	var N := PackedVector3Array(); N.resize(V.size()); N.fill(Vector3.UP)
	var C := PackedColorArray(); C.resize(V.size()); C.fill(GRASS.srgb_to_linear())
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _quad(V: PackedVector3Array, I: PackedInt32Array, x0: float, z0: float, x1: float, z1: float) -> void:
	var b := V.size()
	V.append(Vector3(x0, 0, z0)); V.append(Vector3(x1, 0, z0)); V.append(Vector3(x0, 0, z1)); V.append(Vector3(x1, 0, z1))
	I.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])


# ---- placed ramps (the ramp editor) ---------------------------------------------------------------------------
var _ramp_nodes := {}   # ramp id -> Node3D

## (re)draws a placed ramp: its ground mesh on its own grid (fine along it where it isn't flat), a post at the lip,
## a label with its numbers
func refresh_ramp(r) -> void:
	drop_ramp_node(r.id)
	if _mat == null: return
	var root := Node3D.new()
	root.name = "Ramp_" + r.id
	add_child(root)
	_ramp_nodes[r.id] = root
	if r.wood(): _wood_ramp(r, root)
	else: _dirt_ramp(r, root)
	var sd: Vector2 = r.side()
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.08, 1.0, 0.08)
	var pm := StandardMaterial3D.new(); pm.albedo_color = Color(1.0, 0.35, 0.2); bm.material = pm
	post.mesh = bm
	var lp: Vector2 = r.pos + sd * (r.reach + 0.6)
	post.position = Vector3(lp.x, float(r.d.lip_h) * 0.5, lp.y)
	post.scale = Vector3(1, maxf(0.3, float(r.d.lip_h) + 0.5), 1)
	root.add_child(post)
	var pr: Dictionary = r.d.pred[1]
	_label(root, Vector3(lp.x, float(r.d.lip_h) + 1.6, lp.y), "%s · %.0f km/h\n%s\nlands %.1f m out (%s), EFH %.2f m" % [
		r.feat.name, float(r.prm.v) * 3.6, JumpDesign.describe(r.d), float(pr.dist), pr.spot, float(pr.efh)], 30, Color(1, 0.86, 0.2))
	chunk_serial += 1


## a wooden ramp like a home-built one: slats across the face (2 cm gaps), plywood sides following the profile down to
## the ground, a back board where it ends square (a kicker's open back)
const WOOD_SLAT := 0.14
const WOOD_GAP := 0.02
func _wood_ramp(r, root: Node3D) -> void:
	var w: float = float(r.prm.get("width", 3.0))
	var hs: PackedFloat32Array = r.d.h
	var L: float = r.d.length
	var o: Vector2 = r.origin(); var dx: Vector2 = r.dir(); var sd: Vector2 = r.side()
	var S := Vector3(sd.x, 0.0, sd.y)
	# slats (a MultiMesh of boards, each lying on the surface at its middle, a touch of colour per board)
	var xs: Array = []
	var uu := 0.0
	while uu < L:
		var hh := JumpDesign.sample(hs, uu + WOOD_SLAT * 0.5)
		if hh > 0.01: xs.append(uu)
		uu += WOOD_SLAT + WOOD_GAP
	var board := BoxMesh.new(); board.size = Vector3(WOOD_SLAT, 0.025, w)
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.albedo_color = Color(1, 1, 1); bmat.roughness = 0.85
	board.material = bmat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
	mm.mesh = board; mm.instance_count = xs.size()
	var rng := RandomNumberGenerator.new(); rng.seed = hash(r.id)
	for i in xs.size():
		var uc: float = xs[i] + WOOD_SLAT * 0.5
		var hh := JumpDesign.sample(hs, uc)
		var sl := (JumpDesign.sample(hs, uc + 0.05) - JumpDesign.sample(hs, uc - 0.05)) / 0.1
		var a := atan(sl)
		var F := Vector3(dx.x * cos(a), sin(a), dx.y * cos(a))
		var N := S.cross(F).normalized()
		var p2: Vector2 = o + dx * uc
		mm.set_instance_transform(i, Transform3D(Basis(F, N, S), Vector3(p2.x, hh, p2.y) - N * 0.0125))
		var k := rng.randf_range(0.8, 1.08)
		mm.set_instance_color(i, Color(0.55 * k, 0.4 * k, 0.24 * k))
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm
	root.add_child(mmi)
	# plywood sides (+ under them nothing: the sides reach the ground)
	var ply := StandardMaterial3D.new()
	ply.albedo_color = Color(0.72, 0.52, 0.33); ply.roughness = 0.8
	ply.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var off: Vector2 = sd * (float(side) * (w * 0.5 + 0.01))
		var nrm: Vector3 = S * float(side)
		var i := 0
		while i < hs.size() - 2:
			var u0 := i * JumpDesign.DS; var u1 := (i + 2) * JumpDesign.DS
			var h0 := hs[i] - 0.03; var h1 := hs[mini(i + 2, hs.size() - 1)] - 0.03
			if h0 > 0.0 or h1 > 0.0:
				var a0: Vector2 = o + dx * u0 + off; var a1: Vector2 = o + dx * u1 + off
				var q: Array = [Vector3(a0.x, maxf(0.0, h0), a0.y), Vector3(a1.x, maxf(0.0, h1), a1.y), Vector3(a1.x, 0.0, a1.y), Vector3(a0.x, 0.0, a0.y)]
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_normal(nrm); st.add_vertex(q[k])
			i += 2
	# a back board wherever the profile ends square (a drop of more than 20 cm between two samples)
	for i in range(1, hs.size()):
		if hs[i - 1] - hs[i] > 0.2:
			var ub := i * JumpDesign.DS
			var c: Vector2 = o + dx * ub
			var a0: Vector2 = c - sd * (w * 0.5); var a1: Vector2 = c + sd * (w * 0.5)
			var hb := hs[i - 1]
			var q: Array = [Vector3(a0.x, hb, a0.y), Vector3(a1.x, hb, a1.y), Vector3(a1.x, 0.0, a1.y), Vector3(a0.x, 0.0, a0.y)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(dx.x, 0, dx.y)); st.add_vertex(q[k])
	var sm := st.commit()
	if sm.get_surface_count() > 0:
		var smi := MeshInstance3D.new(); smi.mesh = sm; smi.material_override = ply
		root.add_child(smi)


func _dirt_ramp(r, root: Node3D) -> void:
	var L: float = r.d.length
	var us := PackedFloat64Array()
	var uu := -0.5
	while uu < L + 0.5:
		us.append(uu)
		var busy := JumpDesign.sample(r.d.h, uu) > 1e-4 or JumpDesign.sample(r.d.h, uu + 0.3) > 1e-4 or JumpDesign.sample(r.d.h, uu - 0.3) > 1e-4
		uu += 0.1 if busy else 0.5
	us.append(L + 0.5)
	var vs := PackedFloat64Array()
	var vv: float = -r.reach - 0.3
	while vv < r.reach + 0.3:
		vs.append(vv); vv += 0.25
	vs.append(r.reach + 0.3)
	var nu := us.size(); var nv := vs.size()
	var H := PackedFloat32Array(); H.resize(nu * nv)
	for j in nv:
		for i in nu:
			var hh: float = r.at_local(us[i], vs[j])
			H[j * nu + i] = hh if hh > 0.002 else -0.03   # (flat edges just under the plane: no z-fighting)
	var o: Vector2 = r.origin(); var dx: Vector2 = r.dir(); var sd: Vector2 = r.side()
	var V := PackedVector3Array(); V.resize(nu * nv)
	var N := PackedVector3Array(); N.resize(nu * nv)
	var C := PackedColorArray(); C.resize(nu * nv)
	var clay := CLAY.srgb_to_linear(); var dirt := DIRT.srgb_to_linear()
	for j in nv:
		for i in nu:
			var k := j * nu + i
			var w: Vector2 = o + dx * us[i] + sd * vs[j]
			V[k] = Vector3(w.x, H[k], w.y)
			var i0 := maxi(0, i - 1); var i1 := mini(nu - 1, i + 1)
			var j0 := maxi(0, j - 1); var j1 := mini(nv - 1, j + 1)
			var gu := (H[j * nu + i1] - H[j * nu + i0]) / maxf(1e-4, us[i1] - us[i0])
			var gv := (H[j1 * nu + i] - H[j0 * nu + i]) / maxf(1e-4, vs[j1] - vs[j0])
			var g2: Vector2 = dx * gu + sd * gv
			N[k] = Vector3(-g2.x, 1.0, -g2.y).normalized()
			C[k] = clay if H[k] > 0.02 else dirt
	var I := PackedInt32Array(); I.resize((nu - 1) * (nv - 1) * 6)
	var p := 0
	# (winding: the grid's u / v axes are turned; pick the order that faces up)
	var flip := dx.x * sd.y - dx.y * sd.x < 0.0   # (dir x side = +1 here: the lanes' order)
	for j in nv - 1:
		for i in nu - 1:
			var a := j * nu + i
			if flip:
				I[p] = a; I[p + 1] = a + nu; I[p + 2] = a + 1
				I[p + 3] = a + 1; I[p + 4] = a + nu; I[p + 5] = a + nu + 1
			else:
				I[p] = a; I[p + 1] = a + 1; I[p + 2] = a + nu
				I[p + 3] = a + 1; I[p + 4] = a + nu + 1; I[p + 5] = a + nu
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = m; mi.material_override = _mat; mi.layers = 1 | GROUND_LAYER
	root.add_child(mi)


func drop_ramp_node(id: String) -> void:
	if _ramp_nodes.has(id):
		var n: Node = _ramp_nodes[id]
		if is_instance_valid(n): n.queue_free()
		_ramp_nodes.erase(id)


# ---- signs ---------------------------------------------------------------------------------------------------
## a post + a billboard label at every feature (name, numbers, id for BMX_PG_AT), the lane name at its roll-in,
## and distance marks every 50 m along each lane
func _build_signs() -> void:
	var root := Node3D.new()
	root.name = "Signs"
	add_child(root)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.95, 0.55, 0.1)
	var post := BoxMesh.new()
	post.size = Vector3(0.08, 1.2, 0.08)
	post.material = post_mat
	for l in course.lanes:
		var side: float = l.z - l.hw - 2.2
		_label(root, Vector3(PlaygroundCourse.X0 + 2.0, PlaygroundCourse.ROLLIN_H + 3.2, l.z), l.title, 160, Color(1, 0.86, 0.2))
		for f in l.feats:
			if str(f.id).begins_with("rollin"): continue
			var x0: float = PlaygroundCourse.X0 + f.u0
			var pm := MeshInstance3D.new(); pm.mesh = post
			pm.position = Vector3(x0, 0.6, side)
			root.add_child(pm)
			_label(root, Vector3(x0, 2.6, side), "%s\n%s\n[%s]" % [f.name, f.desc, f.id], 64, Color.WHITE)
			if f.lip >= 0.0:   # a small mark where the lip is
				var lm := MeshInstance3D.new(); lm.mesh = post
				var lx: float = PlaygroundCourse.X0 + f.lip
				lm.position = Vector3(lx, l.profile(f.lip) + 0.6, side + 0.6)
				lm.scale = Vector3(1, 0.6, 1)
				root.add_child(lm)
		var d := 50.0
		while d < l.length():
			_label(root, Vector3(PlaygroundCourse.X0 + ROLL_X + d, 0.35, l.z + l.hw + 1.4), "%.0f m" % d, 48, Color(1, 1, 1, 0.75))
			d += 50.0
	# slalom cones
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02; cone.bottom_radius = 0.16; cone.height = 0.45
	var cm := StandardMaterial3D.new(); cm.albedo_color = Color(1.0, 0.42, 0.08)
	cone.material = cm
	for l in course.lanes:
		for c in l.cones:
			var mi := MeshInstance3D.new(); mi.mesh = cone
			mi.position = Vector3(PlaygroundCourse.X0 + c[0], 0.225, l.z + c[1])
			root.add_child(mi)
	for b in course.bowls:
		_label(root, Vector3(b.c.x, b.W * b.tn + 2.5, b.c.y), "%s\n[%s]" % [b.title, b.id], 96, Color(1, 0.86, 0.2))
	_label(root, Vector3(PlaygroundCourse.X0 - 12.0, 3.0, -20.0), "TEST PLAYGROUND\nopen flat for turns, brakes, sprints", 120, Color(1, 0.86, 0.2))

const ROLL_X := 0.0


static func _label(parent: Node3D, at: Vector3, text: String, size: int, col: Color) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.pixel_size = 0.004
	lb.modulate = col
	lb.outline_size = 12
	lb.outline_modulate = Color(0, 0, 0, 0.8)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = false
	lb.fixed_size = false
	lb.position = at
	parent.add_child(lb)
