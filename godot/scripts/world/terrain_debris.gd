class_name TerrainDebris
extends Node3D
## Rigid-body debris for smashed fences and cacti (replaces the JS debris.js; torn tape is TapeSim):
## Godot physics bodies on layer 4 that only collide with the chunk ground (layer 2). Once a piece has
## come to rest it becomes a plain mesh lying where it fell (the broken fence stays broken), freed
## with its chunk (a reloaded chunk builds the fence whole again) or on respawn / new world.
## Bulletproof against vanishing: thin pieces used to tunnel through the chunk collision and fall for
## ever (then got "laid to rest" 100 m underground). Now every physics tick each piece is held above the
## real terrain height (its rotated box's lowest corner), it never rests below the ground, and when
## too many fly at once the oldest is laid down where it is instead of deleted.

const LAYER := 1 << 3
const MASK := 1 << 1
const LIFE := 8.0         # a piece still moving after this long is laid to rest where it is
const SETTLE := 1.2       # pieces can come to rest after this long
const MAX := 160          # moving pieces
const MAX_WRECK := 2500   # pieces lying on the ground

var _items: Array = []   # [{body, t, chunk, half}]
var _wrecks: Array = []  # [{node, chunk}] pieces at rest (no physics)
var _mats := {}
var _tag := Vector2i(1 << 30, 0)   # chunk of the thing being smashed (set by smash_*)
var _hit := Vector2.ZERO           # where it was hit (probe)
var _spawned := 0                  # pieces made so far (smash_fence reports how many it made)


var _probe_t := 0.0
func _process(delta: float) -> void:
	if Env.s("BMX_DEBRIS_PROBE") != "":
		_probe_t += delta
		if _probe_t > 0.25 and (_items.size() > 0 or _wrecks.size() > 0):
			_probe_t = 0.0
			var lo := 1e9
			for it in _items:
				if is_instance_valid(it["body"]): lo = minf(lo, it["body"].global_position.y)
			print("DEBRIS moving=%d resting=%d lowest_y=%.1f" % [_items.size(), _wrecks.size(), lo])
	var keep := []
	for it in _items:
		it["t"] += delta
		var b: RigidBody3D = it["body"]
		if not is_instance_valid(b):
			continue
		var still := b.sleeping or (b.linear_velocity.length_squared() < 0.02 and b.angular_velocity.length_squared() < 0.05)
		if it["t"] > LIFE or (it["t"] > SETTLE and still):
			_lay_down(it)
		else:
			keep.append(it)
	_items = keep


func _ground(x: float, z: float) -> float:
	var t = get_parent()
	return t.height(x, z) if t != null and t.has_method("height") else -1e9

## how far the rotated box reaches below its centre
static func _reach_down(basis: Basis, half: Vector3) -> float:
	var b := basis.orthonormalized()
	return absf(b.x.y) * half.x + absf(b.y.y) * half.y + absf(b.z.y) * half.z

## the same for a piece with a convex hull: its lowest hull point
static func _reach(it: Dictionary, basis: Basis) -> float:
	var pts = it.get("pts")
	if pts == null:
		return _reach_down(basis, it["half"])
	var b := basis.orthonormalized()
	var lo := 0.0
	for p in pts:
		lo = maxf(lo, -(b * p).y)
	return lo

## the ground guard: no piece ever ends up inside / under the terrain
func _physics_process(_delta: float) -> void:
	for it in _items:
		var b: RigidBody3D = it["body"]
		if not is_instance_valid(b): continue
		var p := b.global_position
		var low := p.y - _reach(it, b.global_basis)
		var g := _ground(p.x, p.z)
		if low < g - 0.005:
			b.global_position = Vector3(p.x, p.y + (g - low), p.z)
			var v := b.linear_velocity
			if v.y < 0.0: v.y = -v.y * 0.2
			v.x *= 0.85; v.z *= 0.85
			b.linear_velocity = v
			b.angular_velocity *= 0.9

## a piece at rest: keep its mesh where it lies, drop the physics body
func _lay_down(it: Dictionary) -> void:
	var b: RigidBody3D = it["body"]
	var mi: MeshInstance3D = null
	for ch in b.get_children():
		if ch is MeshInstance3D: mi = ch
	if Env.s("BMX_DEBRIS_PROBE") != "":
		var pp := b.global_position
		var tr = get_parent()
		var lo := pp.y - _reach(it, b.global_basis)
		print("DEBRIS lay_down y=%.2f t=%.1f low_vs_field=%.3f low_vs_drawn=%.3f from_hit=%.1f m vis=%s" % [pp.y, it["t"], lo - tr.height(pp.x, pp.z), lo - tr.top_height(pp.x, pp.z), Vector2(pp.x - it.get("hx", pp.x), pp.z - it.get("hz", pp.z)).length(), str(b.is_visible_in_tree())])
	if mi != null:
		var xf := mi.global_transform
		# never left inside / under the ground
		var g := _ground(xf.origin.x, xf.origin.z)
		var low := b.global_position.y - _reach(it, b.global_basis)
		if low < g: xf.origin.y += g - low
		b.remove_child(mi)
		add_child(mi)
		mi.global_transform = xf
		while _wrecks.size() >= MAX_WRECK:
			var old = _wrecks.pop_front()
			if is_instance_valid(old["node"]): old["node"].queue_free()
		_wrecks.append({"node": mi, "chunk": it["chunk"]})
	b.queue_free()


## the chunk was unloaded: its fences come back whole when it is built again
func drop_chunk(k: Vector2i) -> void:
	var keep := []
	for w in _wrecks:
		if w["chunk"] == k:
			if is_instance_valid(w["node"]): w["node"].queue_free()
		else:
			keep.append(w)
	_wrecks = keep
	var keep2 := []
	for it in _items:
		if it["chunk"] == k:
			if is_instance_valid(it["body"]): it["body"].queue_free()
		else:
			keep2.append(it)
	_items = keep2


func clear() -> void:
	for it in _items:
		if is_instance_valid(it["body"]):
			it["body"].queue_free()
	_items.clear()
	for w in _wrecks:
		if is_instance_valid(w["node"]):
			w["node"].queue_free()
	_wrecks.clear()


func _material(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b).linear_to_srgb()
	m.roughness = 0.9
	_mats[key] = m
	return m


func spawn(mesh: Mesh, mesh_scale: Vector3, col: Color, xf: Transform3D, size: Vector3, v: Vector3, w: Vector3, mass: float = 1.0,
		damp: float = 0.05, grav: float = 1.0, shape: Shape3D = null, mat: Material = null, mask: int = MASK) -> RigidBody3D:
	while _items.size() >= MAX:   # too many flying: the oldest lies down where it is (never just vanishes)
		var old = _items.pop_front()
		if is_instance_valid(old["body"]):
			_lay_down(old)
	var b := RigidBody3D.new()
	b.collision_layer = LAYER
	b.collision_mask = mask
	b.mass = mass
	b.linear_damp = damp
	b.angular_damp = 0.3
	b.gravity_scale = grav
	b.continuous_cd = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = mesh_scale
	mi.material_override = mat if mat != null else _material(col)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	if shape != null:
		cs.shape = shape
	else:
		var bs := BoxShape3D.new()
		bs.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
		cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf
	b.linear_velocity = v
	b.angular_velocity = w
	var half := Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02)) * 0.5
	var it := {"body": b, "t": 0.0, "chunk": _tag, "half": half, "hx": _hit.x, "hz": _hit.y}
	if shape is ConvexPolygonShape3D:
		it["pts"] = shape.points
	_items.append(it)
	_spawned += 1
	return b


## one loose piece (a tape stake knocked out): a thin box body with its own mesh + material
func fling(mesh: Mesh, mat: Material, xf: Transform3D, size: Vector3, v: Vector3, w: Vector3, chunk = null) -> RigidBody3D:
	_tag = chunk if chunk is Vector2i else Vector2i(1 << 30, 0)
	_hit = Vector2(xf.origin.x, xf.origin.z)
	return spawn(mesh, Vector3.ONE, Color.WHITE, xf, size, v, w, 0.3, 0.05, 1.0, null, mat)


static func _rs() -> float:
	return randf() - 0.5


## the debris piece's material: printed plates / the sign stick keep their look (null = a plain colour material;
## fence pieces fly in their own colour: their wood shader reads its tint from the MultiMesh)
static func _part_mat(panel: Dictionary, kind: String) -> Material:
	match kind:
		"signboard": return SignTex.for_plate(panel["plate"])
		"pole": return TerrainGeo.MAT["signpole"]
	return null


## a smashed fence span: rails and pickets go, a post only when the hit was right at it
static func fence_part_goes(part: Dictionary, hit: Vector2) -> bool:
	if part["kind"] != "post":
		return true
	var o: Vector3 = part["xform"].origin
	return Vector2(o.x - hit.x, o.z - hit.y).length() < 0.7


## fences.js breakFence, reworked: rails snap AT the hit (two real-length halves that swing away
## from the break, plus a few splinters), pickets near the hit fly, far ones topple; untouched
## posts stay in the ground
func smash_fence(panel: Dictionary, vel: Vector3, hit: Vector2, chunk = null) -> int:
	_tag = chunk if chunk is Vector2i else Vector2i(1 << 30, 0)
	_hit = hit
	var sp := Vector2(vel.x, vel.z).length()
	var dir := Vector3(vel.x, 0, vel.z).normalized() if sp > 0.1 else Vector3.ZERO
	var n0 := _spawned
	for part in panel["parts"]:
		if not fence_part_goes(part, hit):
			continue
		var xf: Transform3D = part["xform"]
		var kind: String = part["kind"]
		var scl: Vector3 = part["scale"]
		var rot := xf.basis.orthonormalized()
		var mp := xf.origin
		var base_size: Vector3 = TerrainGeo.FENCE_SIZE[kind]
		var near := 1.0 / (1.0 + Vector2(mp.x - hit.x, mp.z - hit.y).length() * 0.8)
		if kind == "rail":
			var ax := rot.x
			var L := scl.x
			# where along the rail the bike went through
			var edge := minf(0.25, L * 0.3)   # short rails too: never a half with no length
			var t := clampf((hit.x - mp.x) * ax.x + (hit.y - mp.z) * ax.z, -L / 2 + edge, L / 2 - edge)
			for k in 2:
				var a := -L / 2 if k == 0 else t
				var b := t if k == 0 else L / 2
				var len := maxf(0.05, b - a - 0.03)
				var c := mp + ax * ((a + b) / 2)
				var side := -1.0 if k == 0 else 1.0
				# the broken end is pushed along with the bike, the far end lags: a swing about the far end
				var v := dir * sp * (0.35 + randf() * 0.2) + Vector3(_rs() * 0.6, 0.6 + randf() * (0.6 + sp * 0.08), _rs() * 0.6)
				var swing := ax.cross(dir).normalized() * side * (1.5 + sp * 0.35) if dir != Vector3.ZERO else Vector3.ZERO
				var w := swing + Vector3(_rs(), _rs(), _rs()) * (1.0 + sp * 0.2)
				spawn(TerrainGeo.MESH[kind], Vector3(len, scl.y, scl.z), part["col"], Transform3D(rot, c), base_size * Vector3(len, scl.y, scl.z), v, w, 0.6)
			# splinters from the break
			var bp := mp + ax * t
			for k in 3:
				var ss := Vector3(0.12 + randf() * 0.18, scl.y * (0.25 + randf() * 0.3), scl.z * 0.6)
				var v2 := dir * sp * (0.5 + randf() * 0.4) + Vector3(_rs() * 2.5, 1.0 + randf() * 2.0, _rs() * 2.5)
				var w2 := Vector3(_rs(), _rs(), _rs()) * (6 + sp)
				spawn(TerrainGeo.MESH[kind], ss, part["col"], Transform3D(rot, bp + Vector3(_rs() * 0.1, _rs() * 0.06, _rs() * 0.1)), base_size * ss, v2, w2, 0.15)
			continue
		var fling := (0.45 + 0.6 * near) * (0.75 + randf() * 0.35)
		var v := Vector3(vel.x * fling + _rs() * 1.2, maxf(0, vel.y) * 0.4 + 0.8 + randf() * (1 + sp * 0.18) * near, vel.z * fling + _rs() * 1.2)
		var spin := 2 + sp * 0.9 * near
		var w := Vector3(_rs() * spin, _rs() * spin, _rs() * spin)
		spawn(TerrainGeo.MESH[kind], scl, part["col"], Transform3D(rot, mp), base_size * scl, v, w, 0.6, 0.05, 1.0, null,
			_part_mat(panel, kind))
	return _spawned - n0


## a smashed cactus breaks along its precomputed Voronoi cells (CactusGeo): the chunks round the hit
## are flung with the bike and burst outward, the ones above lose their support and topple / tumble
## down; the chunks knock into each other (convex hulls), spines and flowers go with their chunk.
func smash_cactus(rec: Dictionary, vel: Vector3, hit: Vector3, chunk = null) -> void:
	_tag = chunk if chunk is Vector2i else Vector2i(1 << 30, 0)
	var xf: Transform3D = rec["xform"]
	var rot := xf.basis.orthonormalized()
	var scl := xf.basis.get_scale()
	var sp := Vector2(vel.x, vel.z).length()
	var dir := Vector3(vel.x, 0, vel.z) / sp if sp > 0.1 else Vector3.ZERO
	var mat := _cactus_material(rec["col"])
	# a cactus is a plant, not a rock: the arms (pads, pipes) snap off and the trunk falls; the harder the hit, the more
	# often the trunk breaks across too, leaving the rooted lower part standing
	var half := randf() < clampf(0.12 + sp * 0.035, 0.12, 0.6) or Env.s("BMX_CACTUS_HALF") != ""
	for pc in CactusGeo.pieces(rec.get("kind", 0), "half" if half else "arms"):
		var c: Vector3 = xf * pc["at"]
		var size: Vector3 = pc["size"] * scl
		var rel := c - hit
		var near := exp(-rel.length() / 0.45)       # 1 at the hit, ~0 a metre away
		var out := Vector3(rel.x, 0, rel.z).normalized() if Vector2(rel.x, rel.z).length() > 0.01 else Vector3(_rs(), 0, _rs()).normalized()
		var v := dir * sp * (0.12 + 0.62 * near) + out * (0.4 + sp * 0.22) * near 			+ Vector3(_rs() * 0.5, (0.3 + randf() * 1.6) * near + 0.15, _rs() * 0.5)
		# the top falls the way the bike pushed the bottom out: a tip-over spin
		var tip := Vector3.UP.cross(dir) * (-0.6 - sp * 0.08) * (1.0 - near) if dir != Vector3.ZERO else Vector3.ZERO
		var spin := 1.0 + sp * 0.8 * near
		var w := tip + Vector3(_rs(), _rs(), _rs()) * spin
		if pc.get("stump", false):   # the rooted lower part stays where it grew
			v = dir * sp * 0.04
			w = Vector3.ZERO
		var hull := ConvexPolygonShape3D.new()
		var pts: PackedVector3Array = pc["pts"]
		var sp_pts := PackedVector3Array()
		sp_pts.resize(pts.size())
		for k in pts.size():
			sp_pts[k] = pts[k] * scl
		hull.points = sp_pts
		var m := clampf(size.x * size.y * size.z * 350.0, 0.08, 6.0)
		spawn(pc["mesh"], scl, rec["col"], Transform3D(rot, c), size, v, w, m, 0.08, 1.0, hull, mat, MASK | LAYER)


var _cmats := {}
func _cactus_material(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if _cmats.has(key):
		return _cmats[key]
	var m: ShaderMaterial = TerrainGeo.MAT["cactus"].duplicate()
	m.set_shader_parameter("use_instance", false)
	m.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("sway", 0.0)
	_cmats[key] = m
	return m
