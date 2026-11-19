class_name HealthPack
extends Node3D
## A GTA-style pickup: a backpack with a white first-aid cross that floats, bobs and spins above the ground
## with a soft glowing ring under it. Ride through it (Terrain.take_pack) and it heals.
## Placed beside the roadside sheds (TerrainChunkBuilder._sheds -> out["packs"]).

const HOVER := 1.05       # m above the ground (the bike's front wheel / bars pass under it)
const SPIN := 1.6         # rad/s
const HEAL := 0.45        # life given back (0..1)

static var _mats := {}
var _pivot: Node3D
var _ring: MeshInstance3D
var _t := 0.0


static func _mat(key: String, col: Color, emissive := 0.0, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = 0.65
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emissive
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(r: float, h: float, pos: Vector3, mat: Material, parent: Node3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _init() -> void:
	var red := _mat("red", Color("c8282d"))
	var red_d := _mat("red_d", Color("8f1c21"))
	var strap := _mat("strap", Color("2b2b2e"))
	var white := _mat("white", Color("f6f6f2"), 0.35)
	var metal := _mat("metal", Color("b9bcc0"))
	_pivot = Node3D.new()
	add_child(_pivot)
	# the pack (about 0.42 tall, 0.30 wide, 0.17 deep), +Z = the back of the pack, the cross faces -Z... spun anyway
	var body := Node3D.new()
	body.scale = Vector3.ONE * 2.2
	_pivot.add_child(body)
	_box(Vector3(0.30, 0.30, 0.17), Vector3(0, 0.0, 0), red, body)
	_cyl(0.085, 0.30, Vector3(0, 0.15, 0), red, body, Vector3(PI / 2, 0, 0))   # rounded top (a half-barrel along the depth)
	_box(Vector3(0.26, 0.15, 0.07), Vector3(0, -0.06, -0.11), red_d, body)      # front pocket
	_box(Vector3(0.27, 0.025, 0.075), Vector3(0, 0.02, -0.11), strap, body)     # pocket flap strap
	_box(Vector3(0.03, 0.03, 0.02), Vector3(0, 0.02, -0.15), metal, body)       # buckle
	for sx in [-1, 1]:
		_box(Vector3(0.04, 0.34, 0.025), Vector3(sx * 0.09, 0.0, 0.095), strap, body)   # shoulder straps (back)
		_box(Vector3(0.03, 0.03, 0.035), Vector3(sx * 0.15, -0.12, 0.0), strap, body)   # side compression strap
	_cyl(0.015, 0.09, Vector3(0, 0.255, 0), strap, body, Vector3(0, 0, PI / 2))    # carry handle
	# the white first-aid cross on the front of the pack, above the pocket
	_box(Vector3(0.115, 0.032, 0.012), Vector3(0, 0.115, -0.088), white, body)
	_box(Vector3(0.032, 0.115, 0.012), Vector3(0, 0.115, -0.088), white, body)
	# soft glow ring on the ground (additive, unshaded)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.62
	tm.rings = 24
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.scale = Vector3(1, 0.05, 1)
	_ring.material_override = _mat("ring", Color("ff4048"), 2.0, true, 0.75)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.position = Vector3(0, 0.06, 0)
	_t = randf() * TAU


## floats and spins; `dt` real seconds (called by Terrain._process)
func tick(dt: float) -> void:
	_t += dt
	_pivot.rotation.y += SPIN * dt
	_pivot.position.y = HOVER + sin(_t * 2.2) * 0.07
	var s := 1.0 + sin(_t * 3.0) * 0.06
	_ring.scale = Vector3(s, 0.05, s)
