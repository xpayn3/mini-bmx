class_name Tumbleweeds
extends Node3D
## Dry desert bushes that tear loose and roll over the land before the wind: a handful at a time, only in the dry
## biomes, upwind and ahead of the camera, on the same bush mesh the desert is planted with (TerrainGeo.MESH["weed"]).
## They hop over bumps, kick up a little dust and get knocked away by the bike. Visual only, a few dozen
## transforms a frame (no physics bodies), so it costs next to nothing.

const MAX_BALLS := 4
const DRY := ["Red Canyons", "Dune Sea", "Dry Plains"]
const SPAWN_EVERY := 5.0        # s between tries (random on top)
const GONE_DIST := 150.0        # m from the camera: rolled out of sight, freed
const GRAV := 9.8

static var _puff_tex: Texture2D
static var _puff_mat: StandardMaterial3D
static var _ball_mat: StandardMaterial3D

var enabled := true
var _balls: Array = []
var _spawn_t := 1.5
var _rng := RandomNumberGenerator.new()
var _mesh: Mesh


func _init() -> void:
	_rng.randomize()


## the shared dust sprite: a soft round blob, tinted warm sand
static func _puff() -> StandardMaterial3D:
	if _puff_mat != null:
		return _puff_mat
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	_puff_tex = gt
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = gt
	m.disable_receive_shadows = true
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	_puff_mat = m
	return m


static func _ball_material() -> StandardMaterial3D:
	if _ball_mat != null:
		return _ball_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.34, 0.2)   # dry, dead twigs: darker than the sand so the airy ball reads
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ball_mat = m
	return m


## a tumbleweed: a loose ball of dry twigs, ~14 wobbly rings round random axes, thin three-sided tubes (unit radius)
static func _wire_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var rings := 14
	var segs := 18
	for r in rings:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := axis.cross(u)
		var rad := rng.randf_range(0.7, 1.0)
		var ph := rng.randf() * TAU
		var arc := rng.randf_range(0.55, 1.0) * TAU     # some twigs are only part of a ring
		var a0 := rng.randf() * TAU
		var thick := rng.randf_range(0.018, 0.032)
		var pts: Array[Vector3] = []
		for i in segs + 1:
			var a := a0 + arc * float(i) / segs
			var wob := 1.0 + 0.16 * sin(a * 3.0 + ph) + 0.08 * sin(a * 7.0 + ph * 2.0)
			pts.append((u * cos(a) + w * sin(a)) * rad * wob + axis * 0.1 * sin(a * 2.0 + ph))
		for i in segs + 1:
			var p: Vector3 = pts[i]
			var t := (pts[mini(i + 1, segs)] - pts[maxi(i - 1, 0)]).normalized()
			var n1 := t.cross(p.normalized()).normalized()
			var n2 := t.cross(n1).normalized()
			for s in 3:
				var q := float(s) / 3.0 * TAU
				v.append(p + (n1 * cos(q) + n2 * sin(q)) * thick)
		var base := v.size() - (segs + 1) * 3
		for i in segs:
			for s in 3:
				var a1 := base + i * 3 + s
				var a2 := base + i * 3 + (s + 1) % 3
				var b1 := a1 + 3
				var b2 := a2 + 3
				idx.append_array([a1, b1, a2, a2, b1, b2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## a dust trail emitter: puffs of sand left behind, drifting downwind
static func make_dust(amount: int, life: float, size: float, alpha: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.7
	p.damping_min = 0.2
	p.damping_max = 0.6
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.45))
	grow.add_point(Vector2(1, 1.7))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.6, 0.42, 0.0))
	ramp.set_color(1, Color(0.78, 0.6, 0.42, 0.0))
	ramp.add_point(0.18, Color(0.78, 0.6, 0.42, alpha))
	p.color_ramp = ramp
	p.mesh = QuadMesh.new()
	(p.mesh as QuadMesh).size = Vector2(1, 1)
	p.material_override = _puff()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _terrain_ready(t) -> bool:
	return t != null and _mesh_ready()


func _mesh_ready() -> bool:
	if _mesh != null:
		return true
	_mesh = _wire_mesh()
	return _mesh != null


func clear() -> void:
	for b in _balls:
		b.node.queue_free()
		b.dust.queue_free()
	_balls.clear()


## cam = the view (balls are placed ahead of it, across what the player sees), wind = direction * strength
## (Atmos.wind, x / z), rider = the bike (it knocks them away), rv = its speed, density = effects slider
func update(dt: float, t, cam: Camera3D, wind: Vector2, rider: Vector3, rv: float, density := 1.0) -> void:
	if not enabled or dt <= 0.0 or cam == null or not _terrain_ready(t):
		if not _balls.is_empty() and not enabled:
			clear()
		return
	var ws := wind.length()
	var wd := (wind / ws) if ws > 0.01 else Vector2(0.8, 0.6)
	var cpos := cam.global_position
	var max_n := clampi(int(round(MAX_BALLS * clampf(density, 0.2, 1.5))), 1, MAX_BALLS + 2)
	_spawn_t -= dt
	if _spawn_t <= 0.0 and _balls.size() < max_n and ws > 0.05:
		_spawn_t = SPAWN_EVERY * (0.6 + _rng.randf())
		_try_spawn(t, cam, wd)
	var i := _balls.size() - 1
	while i >= 0:
		var b = _balls[i]
		if not _step(b, dt, t, cpos, wd, ws, rider, rv):
			b.node.queue_free()
			b.dust.queue_free()
			_balls.remove_at(i)
		i -= 1


func _try_spawn(t, cam: Camera3D, wd: Vector2) -> void:
	var fwd3 := -cam.global_transform.basis.z
	var fwd := Vector2(fwd3.x, fwd3.z)
	if fwd.length() < 0.2:
		fwd = wd
	fwd = fwd.normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	for attempt in 6:
		# ahead of the camera, a long way upwind of where it should cross the view
		var p := c + fwd * _rng.randf_range(18.0, 70.0) + side * _rng.randf_range(-30.0, 30.0) - wd * _rng.randf_range(30.0, 55.0)
		if t.biome_name(p.x, p.y) not in DRY:
			continue
		var r := _rng.randf_range(0.17, 0.3)
		var node := MeshInstance3D.new()
		node.mesh = _mesh
		node.material_override = _ball_material()
		node.scale = Vector3.ONE * r
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		var dust := make_dust(10, 1.6, 0.3, 0.22)
		add_child(dust)
		var gy: float = t.top_height(p.x, p.y)
		node.global_position = Vector3(p.x, gy + r, p.y)
		_balls.append({
			"node": node, "dust": dust, "r": r, "pos": Vector3(p.x, gy + r, p.y), "vel": wd * 1.0, "vy": 0.0,
			"basis": Basis(Vector3.UP, _rng.randf() * TAU), "air": false, "dry_t": 0.0, "age": 0.0,
			"hop_t": _rng.randf_range(2.0, 6.0), "grow": 0.0, "seed": _rng.randf() * 100.0,
		})
		return


func _step(b: Dictionary, dt: float, t, cpos: Vector3, wd: Vector2, ws: float, rider: Vector3, rv: float) -> bool:
	var r: float = b.r
	var pos: Vector3 = b.pos
	b.age += dt
	# the wind carries it: gusts swell and fade, it also wanders a little to either side
	var gust := 0.55 + 0.45 * sin(b.age * 0.7 + b.seed) * sin(b.age * 0.23 + b.seed * 2.0)
	var want := wd.rotated(sin(b.age * 0.31 + b.seed) * 0.35) * (1.6 + 6.5 * ws) * gust
	var v := Vector2(b.vel.x, b.vel.y)
	v = v.lerp(want, clampf(dt * 0.9, 0.0, 1.0))
	var gy: float = t.top_height(pos.x, pos.z)
	# rolling downhill on top of the wind; uphill slows it
	var gx: float = t.top_height(pos.x + 0.6, pos.z) - gy
	var gz: float = t.top_height(pos.x, pos.z + 0.6) - gy
	v -= Vector2(gx, gz) * (3.0 * dt)
	var floor_y := gy + r * 0.85
	b.vy -= GRAV * dt
	# a gust now and then throws it up
	b.hop_t -= dt
	if b.hop_t <= 0.0 and not b.air and v.length() > 2.0:
		b.hop_t = _rng.randf_range(2.5, 7.0)
		b.vy = _rng.randf_range(1.8, 3.6)
		b.air = true
	pos.y += b.vy * dt
	if pos.y <= floor_y:
		pos.y = floor_y
		if b.vy < -1.2:
			b.vy = -b.vy * 0.42      # bounce
			b.air = true
		else:
			b.vy = 0.0
			b.air = false
	else:
		b.air = true
	# the bike knocks it away
	var to := Vector2(pos.x - rider.x, pos.z - rider.z)
	var dh := to.length()
	if dh < r + 0.75 and absf(pos.y - rider.y) < 1.6:
		var away := (to / dh) if dh > 0.01 else wd
		v = away * (3.0 + absf(rv) * 0.7)
		b.vy = maxf(b.vy, 2.2 + absf(rv) * 0.12)
		b.air = true
	pos.x += v.x * dt
	pos.z += v.y * dt
	b.vel = v
	b.pos = pos
	# rolling: it turns about the horizontal axis across its motion, a little faster when it is flying
	var sp := v.length()
	if sp > 0.01:
		var axis := Vector3(v.y, 0.0, -v.x).normalized()
		b.basis = (Basis(axis, sp / r * dt * (1.0 if not b.air else 0.6)) * b.basis).orthonormalized()
	# grows in over its first second so it never pops into view; shrinks when it leaves the dry land
	if int(b.age * 2.0) != int((b.age - dt) * 2.0):
		if t.biome_name(pos.x, pos.z) in DRY:
			b.dry_t = 0.0
		else:
			b.dry_t += 0.5
	var k := minf(b.age * 1.2, 1.0) * clampf(1.0 - (b.dry_t - 1.0) * 0.5, 0.0, 1.0)
	var node: MeshInstance3D = b.node
	node.global_transform = Transform3D(b.basis.scaled(Vector3.ONE * r * k), pos)
	# a dust trail while it touches the ground
	var dust: CPUParticles3D = b.dust
	dust.global_position = Vector3(pos.x, gy + 0.12, pos.z)
	dust.gravity = Vector3(wd.x * 0.9, 0.12, wd.y * 0.9)
	dust.emitting = not b.air and sp > 1.8 and k > 0.9
	var dxz := Vector2(pos.x - cpos.x, pos.z - cpos.z).length()
	return dxz < GONE_DIST and b.dry_t < 3.0 and b.age < 90.0
