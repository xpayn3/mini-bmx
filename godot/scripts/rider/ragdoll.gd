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
var _touch := PackedByteArray()
var rad: Array = []     # collision radius per point (RAD + the roots of torn-off limbs)
## torn-off limbs (fx/blood.gd): cutting the bone a-b frees b and everything below it; the free piece gets
## its own root point (a copy of a, appended to p) so it keeps its shape and the rider can draw it.
var cut: Dictionary = {}  # b -> index of the free piece's root point
var free_pt := PackedByteArray()   # 1 = on a torn-off piece
var _xbones: Array = []   # [a, b, len] extra bones (root - b)
var _xlims: Array = []    # [a, b, min len] extra limits (root - grandchild)
## sliding on the ground: friction coefficient and a per-substep drag (the old per-pass friction stopped a
## body dead in ~0.1 s, so it never slid)
const SLIDE_MU := 0.75
const SLIDE_DRAG := 0.985

## NEUTRAL BODY POSTURE: the pose a relaxed body floats into with no load (NASA's microgravity studies):
## head tipped ~24° forward, upper arms forward / a little out, elbows bent ~90° (hands in front of the
## chest), hips bent ~50°, knees bent ~50° (shins hang straight down). Each part is pulled toward it in
## the torso's own frame (r = right, u = up the spine, f = forward), the way muscle tone does:
##  * TENSION: a gentle pull once a joint leaves its natural range (none within DEAD of neutral),
##  * SOFT LIMIT: past LIMIT of the bone's length off neutral (~30°) the pull grows steeply, so a limb can
##    be forced far but resists more and more, never a hard stop.
## The pull acts between the part and its parent, equal and opposite, so the body can't push itself along. [child, parent, direction (right side; left mirrors r)]
const NEUTRAL := [
	[HEAD, CHEST, Vector3(0.0, 0.91, 0.41)],
	[EL_R, SH_R, Vector3(0.25, -0.68, 0.69)],
	[HA_R, EL_R, Vector3(-0.18, 0.45, 0.87)],
	[KN_R, HIP_R, Vector3(0.1, -0.64, 0.76)],
	[FT_R, KN_R, Vector3(0.04, -0.97, -0.22)],
	[EL_L, SH_L, Vector3(-0.25, -0.68, 0.69)],
	[HA_L, EL_L, Vector3(0.18, 0.45, 0.87)],
	[KN_L, HIP_L, Vector3(-0.1, -0.64, 0.76)],
	[FT_L, KN_L, Vector3(-0.04, -0.97, -0.22)],
]
## (a pull of f per substep is a spring of f / h² per second²: at 360 substeps / s, 2.5e-4 ≈ 0.9 Hz, so
## a limb sags well under gravity on the ground but drifts back toward neutral when the body is airborne)
## Inside DEAD of neutral (~15°) nothing pulls: a joint at rest in its natural range is left alone.
const DEAD := 0.25         # no pull within this x bone length of neutral
const TONE := 0.00025      # tension: pull per substep for each bone length past DEAD (~0.9 Hz, loose)
const LIMIT := 0.6         # soft limit: off neutral by this x bone length (~35°)
const LIMIT_K := 0.004     # how fast the resistance grows past it
const TONE_DAMP := 0.006   # joint damping: the relative swing of a part and its parent, per substep
var _nlen := PackedFloat32Array()

## STILL ALIVE: a falling person isn't limp yet. For the first moments the joints are held much firmer
## (ALIVE_K x the tension, a smaller dead zone), easing to the relaxed tone over ALIVE_T seconds, so the
## body falls with bent joints. The startle reflex: the arms fly up ("whoa!", REFLEX dirs, blending back to
## neutral over REFLEX_T) and the feet kick a little up and forward. Then SQUIRM: a small wandering twist
## on the chest against the pelvis (a couple: it rolls and shifts the body, stronger on the ground),
## fading over SQUIRM_T.
const ALIVE_K := 1.8
const ALIVE_T := 1.4
const REFLEX_T := 0.9
const REFLEX := {   # NEUTRAL index -> direction while startled (right side; left mirrors r)
	1: Vector3(0.45, 0.72, 0.53), 2: Vector3(0.1, 0.95, 0.3),
	5: Vector3(-0.45, 0.72, 0.53), 6: Vector3(-0.1, 0.95, 0.3),
}
const HAND_FLING := 2.6    # m/s up (+ out) given to the hands / elbows as the fall starts
const FEET_KICK := 0.8     # m/s up + forward given to the feet / knees
const SQUIRM := 3.0        # m/s² of the chest / pelvis couple
const SQUIRM_T := 4.0
var t_fall := 0.0
## SELF-PRESERVATION: while airborne the rider tries to save himself: the torso is twisted toward upright
## (RIGHT_ACC, a couple on chest / pelvis), the legs reach straight down to land on the feet (a little
## toward where he's going), the arms brace down and ahead to catch himself (after the startle).
## Strength = AGENCY: fades over AGENCY_T, and only while the pelvis is well off the ground.
const AGENCY_T := 2.5
const RIGHT_ACC := 20.0       # m/s² of the righting couple at full agency
const LEG_REACH := 0.85      # how far the legs' targets turn from the body pose toward "down"
const ARM_BRACE := 0.7
const LEGS := [3, 4, 7, 8]   # NEUTRAL indices: thighs, shins
const ARMS := [1, 2, 5, 6]   # upper arms, forearms
var agency := 0.0
var _down := Vector3.DOWN    # where the legs reach (down + a little the way he's going)
var _brace := Vector3.DOWN   # where the arms reach
var _sq_ph := Vector3.ZERO
var _fsign := 1.0          # which way is "forward" for this rider (from the riding pose)


func _init(t) -> void:
	terrain = t
	for i in RAD.size():
		p.append(Vector3.ZERO)
		q.append(Vector3.ZERO)
	rest.resize(BONES.size())
	rest.fill(0.0)
	lim.resize(LIMITS.size())
	lim.fill(0.0)
	_reset_points()

## back to the 15 body points, nothing torn off
func _reset_points() -> void:
	p.resize(RAD.size())
	q.resize(RAD.size())
	rad = RAD.duplicate()
	cut.clear()
	_xbones.clear()
	_xlims.clear()
	free_pt.resize(RAD.size())
	free_pt.fill(0)
	_touch.resize(RAD.size())

## tear off the limb below joint a (shoulder / elbow / hip / knee): its bone a-b goes, b and below fly free
## on their own root point. Returns the root's index (-1: already off / not a limb joint).
const LIMB_NEXT := {SH_L: EL_L, EL_L: HA_L, SH_R: EL_R, EL_R: HA_R, HIP_L: KN_L, KN_L: FT_L, HIP_R: KN_R, KN_R: FT_R}
func sever(a: int, kick := Vector3.ZERO) -> int:
	if not LIMB_NEXT.has(a): return -1
	var b: int = LIMB_NEXT[a]
	if free_pt[a] == 1 or free_pt[b] == 1: return -1
	var r := p.size()
	var pa: Vector3 = p[a]
	var va: Vector3 = pa - (q[a] as Vector3)
	p.append(pa)
	q.append(pa - va - kick * last_h)
	rad.append(minf(float(RAD[a]), 0.07))
	_touch.resize(p.size())
	free_pt.resize(p.size())
	free_pt[r] = 1
	cut[b] = r
	_xbones.append([r, b, pa.distance_to(p[b])])
	var c: int = LIMB_NEXT.get(b, -1)
	if c >= 0:   # keep the free piece's own joint from folding flat
		_xlims.append([r, c, pa.distance_to(p[c]) * 0.45])
	var j := b
	while j >= 0:
		free_pt[j] = 1
		j = LIMB_NEXT.get(j, -1)
	return r


## pts: world joints; vel: body velocity; spin: extra velocity per metre above the pelvis
func start(pts: Array, vel: Vector3, spin: Vector3, dt := 1.0 / 60) -> void:
	_reset_points()
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
	_nlen.resize(NEUTRAL.size())
	for k in NEUTRAL.size():
		_nlen[k] = (pts[NEUTRAL[k][0]] as Vector3).distance_to(pts[NEUTRAL[k][1]])
	# forward = the side the knees are on in the riding pose
	_fsign = 1.0
	var fr := _frame()
	var kn: Vector3 = ((pts[KN_L] as Vector3) + (pts[KN_R] as Vector3)) * 0.5 - ((pts[HIP_L] as Vector3) + (pts[HIP_R] as Vector3)) * 0.5
	_fsign = -1.0 if kn.dot(fr.z) < 0.0 else 1.0
	# the startle: hands thrown up and out, feet a little up and forward (velocity = p - q per substep)
	fr = _frame()
	var hs := dt / SUB
	for side in [[EL_L, HA_L, -1.0], [EL_R, HA_R, 1.0]]:
		var fling: Vector3 = (fr.y * HAND_FLING + fr.x * (side[2] * HAND_FLING * 0.35)) * (0.8 + randf() * 0.4)
		q[side[1]] = (q[side[1]] as Vector3) - fling * hs
		q[side[0]] = (q[side[0]] as Vector3) - fling * 0.6 * hs
	for j in [KN_L, FT_L, KN_R, FT_R]:
		var kick: Vector3 = (fr.y + fr.z) * FEET_KICK * (1.0 if j == FT_L or j == FT_R else 0.6) * (0.8 + randf() * 0.4)
		q[j] = (q[j] as Vector3) - kick * hs
	t_fall = 0.0
	_sq_ph = Vector3(randf(), randf(), randf()) * 10.0
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
		t_fall += h
		_agency_update(h)
		_neutral_pull()
		_squirm(h)
		_touch.fill(0)
		for it in 6:
			for j in BONES.size():
				var bb: int = BONES[j][1]
				if not cut.is_empty() and cut.has(bb) and BONES[j][0] != bb and LIMB_NEXT.get(BONES[j][0], -1) == bb: continue   # torn off
				_dist(BONES[j][0], bb, rest[j], BONES[j][2], false)
			for xb in _xbones:
				_dist(xb[0], xb[1], xb[2], 1.0, false)
			for j in LIMITS.size():
				if not cut.is_empty() and free_pt[LIMITS[j][0]] != free_pt[LIMITS[j][1]]: continue
				_dist(LIMITS[j][0], LIMITS[j][1], lim[j], 1.0, true)
			for xl in _xlims:
				_dist(xl[0], xl[1], xl[2], 1.0, true)
			for i in p.size():
				_collide(i)
		# ground friction, once per substep for every part that touched: sliding friction (a body slides
		# a few metres off a fast crash, the blood smears it, fx/blood.gd) + a little drag so it settles
		for i in p.size():
			if _touch[i] == 0: continue
			var pp: Vector3 = p[i]
			var qq: Vector3 = q[i]
			var dx := pp.x - qq.x
			var dz := pp.z - qq.z
			var d := sqrt(dx * dx + dz * dz)
			if d < 1e-7: continue
			var cut := minf(d, SLIDE_MU * 9.81 * h * h)   # Coulomb: speed drops by mu*g*h per substep
			var k := (d - cut) / d * SLIDE_DRAG
			qq.x = pp.x - dx * k
			qq.z = pp.z - dz * k
			q[i] = qq
	var sp := 0.0
	for i in p.size():
		sp = maxf(sp, (p[i] as Vector3).distance_to(q[i]) / h)
	speed = sp


## the torso's frame: x = right (hip to hip), y = up the spine, z = forward
func _frame() -> Basis:
	var u: Vector3 = ((p[CHEST] as Vector3) - (p[PELVIS] as Vector3)).normalized()
	var r: Vector3 = (p[HIP_R] as Vector3) - (p[HIP_L] as Vector3) + (p[SH_R] as Vector3) - (p[SH_L] as Vector3)
	r = (r - u * r.dot(u)).normalized()
	return Basis(r, u, u.cross(r) * _fsign)

## how much he's still trying (see SELF-PRESERVATION) + the righting twist on the torso
func _agency_update(h: float) -> void:
	var pe: Vector3 = p[PELVIS]
	var up_h: float = pe.y - terrain.height(pe.x, pe.z)
	var x := clampf((up_h - 0.35) / 0.55, 0.0, 1.0)
	agency = exp(-t_fall / AGENCY_T) * x * x * (3.0 - 2.0 * x) * tone_k
	if agency < 0.01: return
	var v: Vector3 = (pe - (q[PELVIS] as Vector3)) / maxf(h, 1e-5)
	var hv := Vector3(v.x, 0, v.z)
	var lead := hv.normalized() * clampf(hv.length() / 10.0, 0.0, 0.5) if hv.length() > 0.2 else Vector3.ZERO
	_down = (Vector3.DOWN + lead * 0.6).normalized()
	_brace = (Vector3.DOWN * 0.75 + lead * 1.4 + Vector3(0, 0, 0)).normalized()
	# the righting twist: turn the spine toward world up (equal and opposite on chest / pelvis)
	var u: Vector3 = ((p[CHEST] as Vector3) - pe).normalized()
	var want := Vector3.UP - u * u.dot(Vector3.UP)   # sideways push on the chest that turns u toward up
	var d := want * RIGHT_ACC * agency * h * h
	p[CHEST] = (p[CHEST] as Vector3) + d
	p[HEAD] = (p[HEAD] as Vector3) + d * 0.6
	p[PELVIS] = pe - d * 0.8

## the chest twisting against the pelvis (see SQUIRM): two slow wandering sines, more while lying on the ground
func _squirm(h: float) -> void:
	if t_fall > SQUIRM_T * 1.5: return
	var b := _frame()
	if not b.x.is_finite(): return
	var on_ground := _touch[CHEST] == 1 or _touch[PELVIS] == 1
	var amp := SQUIRM * exp(-t_fall / SQUIRM_T) * (1.0 if on_ground else 0.35) * tone_k
	var t := t_fall
	var f: Vector3 = b.x * sin(t * 2.3 + _sq_ph.x) * (0.7 + 0.3 * sin(t * 0.7 + _sq_ph.z)) + b.z * 0.6 * sin(t * 1.7 + _sq_ph.y)
	var d := f * amp * h * h
	p[CHEST] = (p[CHEST] as Vector3) + d
	p[PELVIS] = (p[PELVIS] as Vector3) - d * 0.8   # not quite balanced: the centre of mass drifts a little
	p[HEAD] = (p[HEAD] as Vector3) + d * 0.5

## tension toward the neutral posture + a soft limit (see NEUTRAL)
var tone_k := float(OS.get_environment("BMX_RAGDOLL_TONE")) if OS.get_environment("BMX_RAGDOLL_TONE") != "" else 1.0   # tests: x the tension / soft limit
var nb_off := 0.0          # tests: summed neutral offsets (BMX_RAGDOLL_PROBE)
func _neutral_pull() -> void:
	var b := _frame()
	if not b.x.is_finite() or b.x.length_squared() < 0.5: return
	var alive := exp(-t_fall / ALIVE_T)              # 1 at the start of the fall -> 0
	var firm := 1.0 + (ALIVE_K - 1.0) * maxf(alive, agency)
	var dead := DEAD * (1.0 - 0.7 * alive)
	var startle := clampf(1.0 - t_fall / REFLEX_T, 0.0, 1.0)
	startle = startle * startle * (3.0 - 2.0 * startle)
	for k in NEUTRAL.size():
		var c: int = NEUTRAL[k][0]
		if free_pt[c] == 1: continue   # torn off: no muscles left to hold it
		var par: int = NEUTRAL[k][1]
		var L: float = _nlen[k]
		var pc: Vector3 = p[par]
		var dir: Vector3 = NEUTRAL[k][2]
		if startle > 0.0 and REFLEX.has(k): dir = dir.lerp(REFLEX[k], startle)
		var wdir: Vector3 = (b * dir).normalized()
		if agency > 0.01:
			# trying to land on the feet / catch himself: the target turns toward the ground (world space)
			if k in LEGS: wdir = wdir.lerp(_down, agency * LEG_REACH).normalized()
			elif k in ARMS: wdir = wdir.lerp(_brace, agency * ARM_BRACE * (1.0 - startle)).normalized()
		var target: Vector3 = pc + wdir * L
		var cp: Vector3 = p[c]
		var d := target - cp
		var dl := d.length()
		var off := dl / maxf(L, 1e-3)
		nb_off += off
		if off <= dead: continue   # in its natural range: no pull
		var ex := off - dead
		var lx := maxf(0.0, off - LIMIT * (1.0 - 0.4 * alive))
		# pull by how far it is past the dead zone; past the soft limit the resistance climbs steeply
		var f := (TONE * ex + LIMIT_K * lx * (1.0 + 2.0 * lx)) * tone_k * firm
		var corr := d / dl * minf(f * L, (dl - dead * L) * 0.06)
		# equal and opposite on the part and its parent: the body can't push itself along
		p[c] = cp + corr * 0.5
		p[par] = pc - corr * 0.5
		# damping: bleed off the part's swing relative to its parent (muscles don't ring like springs)
		var vrel: Vector3 = (cp - (q[c] as Vector3)) - (pc - (q[par] as Vector3))
		var dv := vrel * TONE_DAMP
		q[c] = (q[c] as Vector3) + dv * 0.5
		q[par] = (q[par] as Vector3) - dv * 0.5

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
	var r: float = rad[i]
	var g: float = terrain.height(pp.x, pp.z) + r
	if pp.y < g:
		pp.y = g
		_touch[i] = 1   # ground friction after the solver passes (step)
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
