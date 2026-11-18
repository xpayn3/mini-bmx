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


## fences.js breakFence: pieces near the hit take most of it, rails often snap in two
func smash_fence(panel: Dictionary, vel: Vector3, hit: Vector2) -> void:
	var sp := Vector2(vel.x, vel.z).length()
	for part in panel["parts"]:
		var xf: Transform3D = part["xform"]
		var kind: String = part["kind"]
		var scl: Vector3 = part["scale"]
		var rot := xf.basis.orthonormalized()
		var mp := xf.origin
		var near := 1.0 / (1.0 + Vector2(mp.x - hit.x, mp.z - hit.y).length() * 0.8)
		var fling := (0.45 + 0.6 * near) * (0.75 + randf() * 0.35)
		var pieces := 2 if kind == "rail" and randf() < 0.65 else 1
		var ax := rot.x
		var base_size: Vector3 = TerrainGeo.FENCE_SIZE[kind]
		for k in pieces:
			var off := (0.25 if k else -0.25) * scl.x if pieces == 2 else 0.0
			var sc := Vector3(scl.x * (0.5 - 0.02), scl.y, scl.z) if pieces == 2 else scl
			var p := mp + ax * off
			var v := Vector3(vel.x * fling + _rs() * 1.2, maxf(0, vel.y) * 0.4 + 0.8 + randf() * (1 + sp * 0.18) * near, vel.z * fling + _rs() * 1.2)
			var spin := 2 + sp * 0.9 * near
			var w := Vector3(_rs() * spin, _rs() * spin, _rs() * spin)
			if pieces == 2:
				w += ax.cross(v).normalized() * ((1.0 if k else -1.0) * spin * 0.5)
			spawn(TerrainGeo.MESH[kind], sc, part["col"], Transform3D(rot, p), base_size * sc, v, w, 0.6)


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
