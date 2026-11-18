class_name TerrainDebris
extends Node3D
## Rigid-body debris for smashed fences and cacti (replaces the JS debris.js; torn tape is TapeSim):
## Godot physics bodies on layer 4 that only collide with the chunk ground (layer 2), auto-freed.

const LAYER := 1 << 3
const MASK := 1 << 1
const LIFE := 8.0
const MAX := 160

var _items: Array = []   # [{body, t}]
var _mats := {}


func _process(delta: float) -> void:
	var keep := []
	for it in _items:
		it["t"] += delta
		var b: RigidBody3D = it["body"]
		if not is_instance_valid(b):
			continue
		if it["t"] > LIFE:
			b.queue_free()
		else:
			keep.append(it)
	_items = keep


func clear() -> void:
	for it in _items:
		if is_instance_valid(it["body"]):
			it["body"].queue_free()
	_items.clear()


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
		damp: float = 0.05, grav: float = 1.0) -> RigidBody3D:
	while _items.size() >= MAX:
		var old = _items.pop_front()
		if is_instance_valid(old["body"]):
			old["body"].queue_free()
	var b := RigidBody3D.new()
	b.collision_layer = LAYER
	b.collision_mask = MASK
	b.mass = mass
	b.linear_damp = damp
	b.angular_damp = 0.3
	b.gravity_scale = grav
	b.continuous_cd = false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = mesh_scale
	mi.material_override = _material(col)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_transform = xf
	b.linear_velocity = v
	b.angular_velocity = w
	_items.append({"body": b, "t": 0.0})
	return b


static func _rs() -> float:
	return randf() - 0.5


## a smashed fence span: rails and pickets go, a post only when the hit was right at it
static func fence_part_goes(part: Dictionary, hit: Vector2) -> bool:
	if part["kind"] != "post":
		return true
	var o: Vector3 = part["xform"].origin
	return Vector2(o.x - hit.x, o.z - hit.y).length() < 0.7


## fences.js breakFence, reworked: rails snap AT the hit (two real-length halves that swing away
## from the break, plus a few splinters), pickets near the hit fly, far ones topple; untouched
## posts stay in the ground
func smash_fence(panel: Dictionary, vel: Vector3, hit: Vector2) -> void:
	var sp := Vector2(vel.x, vel.z).length()
	var dir := Vector3(vel.x, 0, vel.z).normalized() if sp > 0.1 else Vector3.ZERO
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
			var t := clampf((hit.x - mp.x) * ax.x + (hit.y - mp.z) * ax.z, -L / 2 + 0.25, L / 2 - 0.25)
			for k in 2:
				var a := -L / 2 if k == 0 else t
				var b := t if k == 0 else L / 2
				var len := b - a - 0.03
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
		spawn(TerrainGeo.MESH[kind], scl, part["col"], Transform3D(rot, mp), base_size * scl, v, w, 0.6)


## cactus.js breakCactus: the base topples, the top and arms go flying
func smash_cactus(rec: Dictionary, vel: Vector3) -> void:
	var xf: Transform3D = rec["xform"]
	var rot := xf.basis.orthonormalized()
	var scl := xf.basis.get_scale()
	var sp := Vector2(vel.x, vel.z).length()
	for n in TerrainGeo.CACTUS_PIECES.size():
		var pc: Dictionary = TerrainGeo.CACTUS_PIECES[n]
		var c: Vector3 = xf * pc["at"]
		var up := 0.3 if n == 0 else 1.0
		var v := Vector3(vel.x * (0.35 + 0.4 * up) + _rs() * 1.5, maxf(0, vel.y) * 0.3 + (0.8 + randf() * 1.8) * up, vel.z * (0.35 + 0.4 * up) + _rs() * 1.5)
		var spin := 2 + sp * 0.7 * up
		spawn(pc["mesh"], scl, rec["col"], Transform3D(rot, c), pc["size"] * scl, v, Vector3(_rs() * spin, _rs() * spin, _rs() * spin), 2.0)
