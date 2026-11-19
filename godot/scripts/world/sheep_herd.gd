class_name SheepHerd
extends Node3D
## Cute woolly sheep that roam in small flocks around the rider: they graze, wander slowly after their
## flock, and bolt away (hopping, legs bounding) when the bike comes close. Flocks that fall far behind
## are re-placed ahead of the rider, off the trail, so the hills always have a few. Purely visual:
## no physics, drawn from procedural primitives (one shared sphere mesh, a few shared materials).
## Env: BMX_NOSHEEP=1 turns them off, BMX_SHEEP_NEAR=1 puts a flock right beside the start (tests).

const FLOCKS := 3
const FLOCK_MIN := 2
const FLOCK_MAX := 4
const SPAWN_MIN := 70.0      # new flocks appear this far ahead (m) ...
const SPAWN_MAX := 135.0
const SIDE_MIN := 7.0        # ... and this far to the side of the rider's line
const SIDE_MAX := 45.0
const DESPAWN := 160.0       # a flock whose nearest sheep is further than this is re-placed
const SCARE := 15.0          # the bike scares them inside this (+ speed bonus)
const CALM := 32.0           # alarm ends once the rider is further than this
const WALK := 0.85
const RUN := 7.6
const WATER_MARGIN := 0.5
const GRASS := "Green Hills"   # the biome sheep stay in

class Lamb:
	var node: Node3D
	var legs: Array = []        # 0 FL, 1 FR, 2 BL, 3 BR (hip pivots)
	var head: Node3D
	var tail: Node3D
	var ears: Array = []
	var p := Vector2.ZERO
	var off := Vector2.ZERO     # spot in the flock, relative to its anchor
	var theta := 0.0            # heading: forward = (sin, cos) in (x, z)
	var sp := 0.0
	var phase := 0.0
	var seed := 0.0
	var y := 0.0
	var bob := 0.0
	var graze := 0.0
	var spawn_k := 0.0
	var spread := 0.0           # individual angle off the straight-away flee line
	var turn_dir := 1.0
	var pitch := 0.0
	var roll := 0.0
	var size := 1.0

class Flock:
	var c := Vector2.ZERO       # anchor the sheep drift around
	var tgt := Vector2.ZERO
	var t := 0.0
	var alarm := 0.0
	var road_pref := false      # this flock likes to stand on the trail ahead of you
	var lambs: Array = []

var terrain
var rng := RandomNumberGenerator.new()
var flocks: Array = []
var enabled := true
var _unit: SphereMesh
var _puff: SphereMesh
var _noise: NoiseTexture2D
var _capsule: CapsuleMesh
var _wools: Array = []
var _faces: Array = []
var _hoof: StandardMaterial3D
var _eye: StandardMaterial3D
var _nose: StandardMaterial3D
var _time := 0.0
var _first := true


func setup(t) -> void:
	terrain = t
	enabled = OS.get_environment("BMX_NOSHEEP") == ""
	rng.seed = 7741
	_unit = SphereMesh.new()
	_unit.radius = 0.5
	_unit.height = 1.0
	_unit.radial_segments = 16
	_unit.rings = 8
	_puff = SphereMesh.new()
	_puff.radius = 0.5
	_puff.height = 1.0
	_puff.radial_segments = 9
	_puff.rings = 5
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.frequency = 0.06
	_noise = NoiseTexture2D.new()
	_noise.width = 128
	_noise.height = 128
	_noise.seamless = true
	_noise.noise = fn
	_capsule = CapsuleMesh.new()
	_capsule.radius = 0.5
	_capsule.height = 2.0
	_capsule.radial_segments = 8
	_capsule.rings = 3
	for col in [Color(0.95, 0.93, 0.86), Color(0.90, 0.89, 0.86), Color(0.93, 0.88, 0.78), Color(0.97, 0.96, 0.93)]:
		_wools.append(_wool_mat(col))
	for col in [Color(0.20, 0.17, 0.16), Color(0.33, 0.26, 0.21), Color(0.13, 0.12, 0.12)]:
		_faces.append(_mat(col, 0.85))
	_hoof = _mat(Color(0.12, 0.11, 0.11), 0.8)
	_eye = _mat(Color(0.02, 0.02, 0.02), 0.3)
	_nose = _mat(Color(0.55, 0.38, 0.38), 0.8)
	if enabled:
		for i in FLOCKS:
			var fl := _make_flock()
			fl.road_pref = flocks.size() == 0
			flocks.append(fl)
		reset()


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## fuzzy wool: soft noise for clumpy colour + a fine bump, light bleeding through the edges
## (subsurface + backlight) and a faint fuzz rim. Four shared materials for every sheep.
func _wool_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = _noise
	m.uv1_scale = Vector3(3, 3, 3)
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = _noise
	m.normal_scale = 0.6
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.7
	m.backlight_enabled = true
	m.backlight = Color(0.55, 0.4, 0.28)
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


func _make_lamb() -> Lamb:
	var l := Lamb.new()
	l.seed = rng.randf() * 10.0
	var big := rng.randf_range(0.88, 1.12)
	var wool: Material = _wools[rng.randi() % _wools.size()]
	var face: Material = _faces[rng.randi() % _faces.size()]
	var n := Node3D.new()
	l.size = big
	add_child(n)
	l.node = n
	# fluffy body: a big oval with puffs of wool stuck on
	_part(n, _unit, wool, Vector3(0, 0.62, 0), Vector3(0.82, 0.78, 1.08))
	# ~18 small low-poly puffs scattered over the top and sides of the body (cheap: one shared mesh)
	for k in 18:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.25, 1.0), rng.randf_range(-1, 1)).normalized()
		var pp := Vector3(0, 0.62, 0) + d * Vector3(0.36, 0.36, 0.5)
		var sz := rng.randf_range(0.26, 0.36)
		_part(n, _puff, wool, pp, Vector3(sz, sz * 0.92, sz))
	# head on a neck pivot (it lowers to graze)
	var h := Node3D.new()
	h.position = Vector3(0, 0.82, 0.5)
	n.add_child(h)
	l.head = h
	_part(h, _unit, face, Vector3(0, -0.02, 0.17), Vector3(0.3, 0.32, 0.4))
	_part(h, _unit, wool, Vector3(0, 0.13, 0.08), Vector3(0.24, 0.17, 0.26))      # fringe on the forehead
	_part(h, _unit, _nose, Vector3(0, -0.05, 0.36), Vector3(0.1, 0.08, 0.09))
	for sx in [-1.0, 1.0]:
		_part(h, _unit, _eye, Vector3(0.095 * sx, 0.03, 0.27), Vector3(0.05, 0.06, 0.05))
		var ear := _part(h, _unit, face, Vector3(0.17 * sx, 0.06, 0.04), Vector3(0.19, 0.06, 0.1))
		ear.rotation.z = -0.5 * sx
		l.ears.append(ear)
	# four short legs, pivoting at the hips
	var legpos := [Vector3(0.2, 0.4, 0.28), Vector3(-0.2, 0.4, 0.28), Vector3(0.2, 0.4, -0.3), Vector3(-0.2, 0.4, -0.3)]
	for lp in legpos:
		var hip := Node3D.new()
		hip.position = lp
		n.add_child(hip)
		_part(hip, _capsule, _hoof, Vector3(0, -0.19, 0), Vector3(0.085, 0.2, 0.085))
		l.legs.append(hip)
	# little woolly tail
	var tl := Node3D.new()
	tl.position = Vector3(0, 0.7, -0.52)
	n.add_child(tl)
	_part(tl, _unit, wool, Vector3(0, -0.04, -0.05), Vector3(0.2, 0.2, 0.2))
	l.tail = tl
	return l


func _make_flock() -> Flock:
	var f := Flock.new()
	var cnt := rng.randi_range(FLOCK_MIN, FLOCK_MAX)
	for i in cnt:
		var l := _make_lamb()
		f.lambs.append(l)
	return f


## restart: every flock gets a new spot (new world / respawn)
func reset() -> void:
	if not enabled:
		return
	_first = true
	for f in flocks:
		for l in f.lambs:
			l.node.visible = false
		f.alarm = 0.0
		f.c = Vector2(1e9, 1e9)   # far: placed on the next follow()


func _ground_ok(x: float, z: float) -> bool:
	var h: float = terrain.height(x, z)
	if h < Terrain.WATER + WATER_MARGIN + 0.6:
		return false
	if terrain.biome_name(x, z) != GRASS:   # sheep only live on the green grass
		return false
	# not on a slope that's too steep to graze
	var dh: float = absf(terrain.height(x + 4.0, z) - h) + absf(terrain.height(x, z + 4.0) - h)
	return dh < 2.6


func _place(f: Flock, rider: Vector2, fwd: Vector2, near: bool) -> void:
	var spot := Vector2.ZERO
	var ok := false
	var side := Vector2(-fwd.y, fwd.x)
	for attempt in 24:
		var r := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var s := rng.randf_range(SIDE_MIN, SIDE_MAX) * (1.0 if rng.randf() < 0.5 else -1.0)
		if f.road_pref:
			s = rng.randf_range(0.0, 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		if near:
			r = 24.0 + rng.randf() * 10.0
			s = (9.0 + rng.randf() * 8.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		spot = rider + fwd * r + side * s
		if _ground_ok(spot.x, spot.y):
			ok = true
			break
	if not ok:
		f.c = Vector2(1e9, 1e9)   # no good ground right now: try again next frame
		for l in f.lambs:
			l.node.visible = false
		return
	f.c = spot
	f.tgt = spot
	f.alarm = 0.0
	f.t = rng.randf_range(2.0, 8.0)
	var i := 0
	for l in f.lambs:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(1.0, 5.0)
		l.off = Vector2(cos(a), sin(a)) * rr
		l.p = spot + l.off
		l.theta = rng.randf() * TAU
		l.sp = 0.0
		l.y = terrain.height(l.p.x, l.p.y)
		l.spawn_k = 0.0
		l.spread = rng.randf_range(-0.6, 0.6)
		l.turn_dir = 1.0 if rng.randf() < 0.5 else -1.0
		l.graze = 1.0
		l.node.visible = true
		i += 1


func follow(dt: float, rider_pos: Vector3, rider_v: float, fwd3: Vector3) -> void:
	if not enabled or terrain == null or dt <= 0.0:
		return
	dt = minf(dt, 0.05)
	_time += dt
	var rider := Vector2(rider_pos.x, rider_pos.z)
	var fwd := Vector2(fwd3.x, fwd3.z)
	if fwd.length() < 0.01:
		fwd = Vector2(1, 0)
	fwd = fwd.normalized()
	var vabs := absf(rider_v)
	var scare := SCARE + minf(vabs * 0.7, 10.0)
	var first_near := _first and OS.get_environment("BMX_SHEEP_NEAR") != ""
	var placed_this_frame := 0
	for f in flocks:
		# (re)place a flock that has no spot, or has been left far behind
		var nearest := 1e9
		for l in f.lambs:
			nearest = minf(nearest, l.p.distance_to(rider))
		if f.c.x > 1e8 or nearest > DESPAWN:
			if placed_this_frame < 2:
				_place(f, rider, fwd, first_near and placed_this_frame == 0)
				placed_this_frame += 1
			if f.c.x > 1e8:
				continue
		_update_flock(f, dt, rider, vabs, scare)
	_first = false


func _update_flock(f: Flock, dt: float, rider: Vector2, vabs: float, scare: float) -> void:
	var closest := 1e9
	var mean := Vector2.ZERO
	for l in f.lambs:
		closest = minf(closest, l.p.distance_to(rider))
		mean += l.p
	mean /= float(f.lambs.size())
	var on_road := false
	for l in f.lambs:
		if terrain.field.trail(l.p.x, l.p.y) > 0.05:
			on_road = true
			break
	if on_road:
		scare = maxf(scare, 38.0 + vabs * 1.3)   # sheep on the road clear off well before you arrive
	if closest < scare:
		f.alarm = 3.5
	elif closest > CALM:
		f.alarm = maxf(0.0, f.alarm - dt)
	else:
		f.alarm = maxf(0.0, f.alarm - dt * 0.4)
	var fleeing: bool = f.alarm > 0.0
	if fleeing:
		f.c = mean   # after the scare they settle where they ended up
		f.tgt = mean
	else:
		# the anchor wanders: pick a spot nearby now and then, drift toward it
		f.t -= dt
		if f.t <= 0.0:
			f.t = rng.randf_range(8.0, 20.0)
			var a := rng.randf() * TAU
			f.tgt = f.c + Vector2(cos(a), sin(a)) * rng.randf_range(4.0, 14.0)
		var to: Vector2 = f.tgt - f.c
		if to.length() > 0.3:
			var nc: Vector2 = f.c + to.normalized() * 0.4 * dt
			if _ground_ok(nc.x, nc.y):
				f.c = nc
			else:
				f.tgt = f.c
	for l in f.lambs:
		_update_lamb(l, f, dt, rider, fleeing)


func _update_lamb(l: Lamb, f: Flock, dt: float, rider: Vector2, fleeing: bool) -> void:
	l.spawn_k = minf(1.0, l.spawn_k + dt * 0.8)
	var want_theta := l.theta
	var want_sp := 0.0
	var turn_rate := 2.4
	if fleeing:
		var away := l.p - rider
		if away.length() < 0.5:
			away = Vector2(cos(l.theta), sin(l.theta))
		away = away.normalized()
		if terrain.field.trail(l.p.x, l.p.y) > 0.02:
			# on the road: dash sideways off it (down the trail gradient), a little away from the bike
			var tx: float = terrain.field.trail(l.p.x + 1.5, l.p.y) - terrain.field.trail(l.p.x - 1.5, l.p.y)
			var tz: float = terrain.field.trail(l.p.x, l.p.y + 1.5) - terrain.field.trail(l.p.x, l.p.y - 1.5)
			var g := Vector2(-tx, -tz)
			if g.length() < 0.01:
				g = away.rotated(PI * 0.5 * l.turn_dir)
			away = (g.normalized() + away * 0.35).normalized()
		away = away.rotated(l.spread * 0.5)
		want_theta = atan2(away.x, away.y)
		want_sp = RUN * (0.9 + 0.2 * fposmod(l.seed, 1.0))
		turn_rate = 9.0
	else:
		var goal: Vector2 = f.c + l.off
		var dd := goal - l.p
		if dd.length() > 2.2:
			want_theta = atan2(dd.x, dd.y)
			want_sp = WALK * (0.75 + 0.5 * fposmod(l.seed * 3.1, 1.0))
	# smooth speed and turning
	l.sp += (want_sp - l.sp) * minf(1.0, dt * (7.0 if fleeing else 2.0))
	if l.sp > 0.05 or fleeing:
		l.theta = lerp_angle(l.theta, want_theta, minf(1.0, dt * turn_rate))
	# move: stop for water / steep ground, turning away while it lasts
	if l.sp > 0.02:
		var dir := Vector2(sin(l.theta), cos(l.theta))
		var np := l.p + dir * l.sp * dt
		var nh: float = terrain.height(np.x, np.y)
		var blocked: bool = nh < Terrain.WATER + WATER_MARGIN or absf(nh - l.y) > maxf(0.06, l.sp * dt * 1.4)
		if not blocked:
			if terrain.biome_name(np.x, np.y) != GRASS and terrain.biome_name(l.p.x, l.p.y) == GRASS:
				blocked = true   # stop at the edge of the grass (sand, rock, canyon)
		if blocked:
			l.theta += l.turn_dir * dt * 4.0
			l.sp *= 0.85
		else:
			l.p = np
	var gy: float = terrain.height(l.p.x, l.p.y)
	l.y += (gy - l.y) * minf(1.0, dt * 14.0)
	# slope pose
	var dirv := Vector2(sin(l.theta), cos(l.theta))
	var hf: float = terrain.height(l.p.x + dirv.x * 0.45, l.p.y + dirv.y * 0.45)
	var hb: float = terrain.height(l.p.x - dirv.x * 0.45, l.p.y - dirv.y * 0.45)
	var leftv := Vector2(dirv.y, -dirv.x)   # local +X in world (x, z)
	var hl: float = terrain.height(l.p.x + leftv.x * 0.3, l.p.y + leftv.y * 0.3)
	var hr: float = terrain.height(l.p.x - leftv.x * 0.3, l.p.y - leftv.y * 0.3)
	l.pitch += (-atan2(hf - hb, 0.9) - l.pitch) * minf(1.0, dt * 8.0)
	l.roll += (atan2(hl - hr, 0.6) - l.roll) * minf(1.0, dt * 8.0)
	# gait
	var run_k := clampf((l.sp - 2.0) / 4.0, 0.0, 1.0)
	l.phase += l.sp * dt * lerpf(3.2, 2.1, run_k)
	var amp := clampf(l.sp / 2.5, 0.0, 1.0) * lerpf(0.5, 0.95, run_k)
	var hop := 0.0
	if l.sp > 0.1:
		var w := absf(sin(l.phase * lerpf(1.0, 0.5, run_k) * 2.0))
		hop = w * lerpf(0.02, 0.2, run_k)
	l.bob += (hop - l.bob) * minf(1.0, dt * 20.0)
	var offs_walk := [0.0, PI, PI, 0.0]
	var offs_run := [0.0, 0.25, PI * 0.85, PI * 0.95]
	for i in 4:
		var o: float = lerpf(offs_walk[i], offs_run[i], run_k)
		(l.legs[i] as Node3D).rotation.x = sin(l.phase + o) * amp
	# head: grazes when standing, now and then looks up; up and alert when running
	var look_up: bool = sin(_time * 0.35 + l.seed * 7.0) > 0.78
	var gt := 0.0
	if l.sp < 0.3 and not look_up and not fleeing:
		gt = 1.0
	l.graze += (gt - l.graze) * minf(1.0, dt * 3.0)
	var nod := sin(_time * 5.0 + l.seed) * 0.05 * l.graze
	l.head.rotation.x = l.graze * 0.95 + nod - run_k * 0.25
	l.head.position.y = 0.82 - l.graze * 0.12
	l.tail.rotation.z = sin(_time * (3.0 + l.sp * 2.0) + l.seed) * (0.12 + 0.25 * run_k)
	for i in l.ears.size():
		var side := 1.0 if i == 1 else -1.0
		(l.ears[i] as Node3D).rotation.z = -0.5 * (-side) * (1.0 - 0.7 * run_k) + sin(_time * 1.3 + l.seed + i) * 0.04
	# put it in the world
	var b := Basis(Vector3.UP, l.theta) * Basis(Vector3.RIGHT, l.pitch) * Basis(Vector3.BACK, l.roll)
	l.node.transform = Transform3D(b, Vector3(l.p.x, l.y + l.bob, l.p.y))
	l.node.scale = Vector3.ONE * (l.size * l.spawn_k)
