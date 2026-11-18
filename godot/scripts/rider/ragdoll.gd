class_name Ragdoll
extends RefCounted
## Port of src/ragdoll.js: Verlet-particle ragdoll for the rider, in world space.
## Joint order matches Rider.J / Rider.joints_world().

const HEAD := 0
const CHEST := 1
const PELVIS := 2
const SH_L := 3
const EL_L := 4
const HA_L := 5
const SH_R := 6
const EL_R := 7
const HA_R := 8
const HIP_L := 9
const KN_L := 10
const FT_L := 11
const HIP_R := 12
const KN_R := 13
const FT_R := 14

const WATER := -2.2   # terrain.js WATER: below it the body floats and drags
const SUB := 3        # substeps per frame
const RAD := [0.2, 0.15, 0.12, 0.08, 0.06, 0.06, 0.08, 0.06, 0.06, 0.08, 0.07, 0.07, 0.08, 0.07, 0.07]

## [a, b, stiffness] rigid-ish bones; the torso is cross-braced so it keeps its shape
const BONES := [
	[HEAD, CHEST, 1.0], [HEAD, SH_L, 0.6], [HEAD, SH_R, 0.6], [HEAD, PELVIS, 0.4],
	[CHEST, PELVIS, 1.0], [CHEST, SH_L, 1.0], [CHEST, SH_R, 1.0], [SH_L, SH_R, 1.0],
	[PELVIS, HIP_L, 1.0], [PELVIS, HIP_R, 1.0], [HIP_L, HIP_R, 1.0],
	[SH_L, HIP_L, 1.0], [SH_R, HIP_R, 1.0], [SH_L, HIP_R, 0.8], [SH_R, HIP_L, 0.8],
	[SH_L, EL_L, 1.0], [EL_L, HA_L, 1.0], [SH_R, EL_R, 1.0], [EL_R, HA_R, 1.0],
	[HIP_L, KN_L, 1.0], [KN_L, FT_L, 1.0], [HIP_R, KN_R, 1.0], [KN_R, FT_R, 1.0],
]
## [a, b, minFraction of rest length] soft joint limits: stop limbs folding flat onto themselves
const LIMITS := [
	[SH_L, HA_L, 0.45], [SH_R, HA_R, 0.45], [HIP_L, FT_L, 0.5], [HIP_R, FT_R, 0.5],
	[KN_L, CHEST, 0.6], [KN_R, CHEST, 0.6], [HA_L, HA_R, 0.15], [KN_L, KN_R, 0.15], [FT_L, FT_R, 0.15],
]

var terrain
var p: Array = []      # current points (Vector3)
var q: Array = []      # previous points
var rest: Array = []
var lim: Array = []
var active := false
var speed := 0.0
var last_h := 0.0      # substep the current displacements (p - q) were made with
var _shapes: Array = []


func _init(t) -> void:
	terrain = t
	for i in RAD.size():
		p.append(Vector3.ZERO)
		q.append(Vector3.ZERO)
	rest.resize(BONES.size())
	rest.fill(0.0)
	lim.resize(LIMITS.size())
	lim.fill(0.0)


## pts: world joints; vel: body velocity; spin: extra velocity per metre above the pelvis
func start(pts: Array, vel: Vector3, spin: Vector3, dt := 1.0 / 60) -> void:
	var pel: Vector3 = pts[PELVIS]
	for i in p.size():
		var pt: Vector3 = pts[i]
		p[i] = pt
		var h := pt.y - pel.y
		var d := vel + spin * h + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.6
		q[i] = pt - d * (dt / SUB)   # Verlet velocity is per substep
	for k in BONES.size():
		rest[k] = (pts[BONES[k][0]] as Vector3).distance_to(pts[BONES[k][1]])
	for k in LIMITS.size():
		lim[k] = (pts[LIMITS[k][0]] as Vector3).distance_to(pts[LIMITS[k][1]]) * LIMITS[k][2]
	# knees / hands keep some spacing even if they started touching
	lim[6] = maxf(lim[6], 0.12)
	lim[7] = maxf(lim[7], 0.14)
	lim[8] = maxf(lim[8], 0.14)
	active = true
	last_h = dt / SUB


func step(dt: float, colliders: Array) -> void:
	var n := SUB
	var h := dt / n
	# time-corrected Verlet: rescale the previous substep's displacement to this substep's length
	var ratio := h / (last_h if last_h > 0.0 else h)
	last_h = h
	# collision shapes that match what you see: rocks = domes, trunks / cacti = thin cylinders
	_shapes.clear()
	for c in colliders:
		if c.get("tape"):
			continue
		if c.get("top") != null:
			var base: float = terrain.height(c.x, c.z) - 0.15
			_shapes.append({rock = true, x = c.x, z = c.z, y = base, R = c.r * 0.9, H = maxf(0.1, c.top - base)})
		else:
			_shapes.append({rock = false, x = c.x, z = c.z, R = maxf(0.08, (c.r - 0.1) * 0.6)})
	for s in n:
		for i in p.size():
			var pp: Vector3 = p[i]
			var qq: Vector3 = q[i]
			var wet := pp.y < WATER
			var damp := (0.94 if wet else 0.998) * (ratio if s == 0 else 1.0)
			var vel := (pp - qq) * damp
			q[i] = pp
			pp += vel
			pp.y -= (2.0 if wet else 9.81) * h * h
			p[i] = pp
		for it in 6:
			for j in BONES.size():
				_dist(BONES[j][0], BONES[j][1], rest[j], BONES[j][2], false)
			for j in LIMITS.size():
				_dist(LIMITS[j][0], LIMITS[j][1], lim[j], 1.0, true)
			for i in p.size():
				_collide(i)
	var sp := 0.0
	for i in p.size():
		sp = maxf(sp, (p[i] as Vector3).distance_to(q[i]) / h)
	speed = sp


func _dist(a: int, b: int, len: float, k: float, min_only: bool) -> void:
	var A: Vector3 = p[a]
	var B: Vector3 = p[b]
	var d := B - A
	var l := d.length()
	if l < 1e-6 or (min_only and l >= len):
		return
	var c := (l - len) / l * 0.5 * k
	p[a] = A + d * c
	p[b] = B - d * c


func _collide(i: int) -> void:
	var pp: Vector3 = p[i]
	var qq: Vector3 = q[i]
	var r: float = RAD[i]
	var g: float = terrain.height(pp.x, pp.z) + r
	if pp.y < g:
		pp.y = g
		# ground friction: kill most of the sliding velocity
		var f := 0.12
		qq.x += (pp.x - qq.x) * f
		qq.z += (pp.z - qq.z) * f
		if qq.y < pp.y - 0.02:
			qq.y = pp.y - (pp.y - qq.y) * 0.3   # small bounce
	for c in _shapes:
		var dx: float = pp.x - c.x
		var dz: float = pp.z - c.z
		if c.rock:
			var R: float = c.R + r
			var H: float = c.H + r
			var dy: float = pp.y - c.y
			if dy < -r:
				continue
			var k := sqrt((dx / R) * (dx / R) + (dy / H) * (dy / H) + (dz / R) * (dz / R))
			if k >= 1.0 or k < 1e-4:
				continue
			pp = Vector3(c.x + dx / k, c.y + dy / k, c.z + dz / k)
			qq.x += (pp.x - qq.x) * 0.1
			qq.z += (pp.z - qq.z) * 0.1
		else:
			var d := sqrt(dx * dx + dz * dz)
			var m: float = c.R + r * 0.6
			if d < m and d > 1e-4:
				pp.x = c.x + dx / d * m
				pp.z = c.z + dz / d * m
	p[i] = pp
	q[i] = qq
