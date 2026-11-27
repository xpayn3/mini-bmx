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
## the substep everything per-substep (damping, friction drag, joint tension) was tuned at: 120 Hz / SUB.
## Shorter substeps (crash slow motion: Engine.time_scale 0.22) scale those terms so the body behaves the
## same in game time (they used to act ~20x stronger in slow motion and set the body spinning).
const H0 := 1.0 / 360.0
var _no_lkeep := Env.raw("BMX_NO_LKEEP") != ""   # tests: compare without the spin fix
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
var _shape_src: Array = []   # the colliders _shapes were built from (cached per crash)
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
const SLIDE_MU := 1.1
const SLIDE_DRAG := 0.97
## CONTACT (2026-11-24, user: "the rider gets a weird ejection force, flies too much" + "slides on the floor
## too much"): a part pushed out of the ground / a rock used to keep the push-out as speed (Verlet: velocity =
## p - q), up to ~7 m/s upward from a 2 cm overlap at 360 substeps/s, so contacts kicked the body up and it
## spent half its slide in the air with no friction. Now the push-out moves the part only; its speed INTO the
## surface is taken out (a hard hit keeps BOUNCE of it), and friction is Coulomb on what the contact really
## pushed: mu x the normal speed taken out (gravity at rest, the whole impact on a hit), so a body that slams
## down grabs the ground, one lying on it slides at mu g. ROUGH_MU = the ground's grip in that model.
## `BMX_OLD_RAGCOL=1` = the old contacts.
const ROUGH_MU := 1.6 
const BOUNCE := 0.12           # of the speed into the ground given back on a hard hit
const BOUNCE_MIN := 3.0        # m/s into the ground before anything bounces
const ROCK_SLIDE := 0.98       # speed kept along a rock / trunk per contact (like the ground drag)
const MAX_V := 40.0            # m/s: no part ever moves faster (a solver blow-up can't launch the body)
var _old_col := Env.raw("BMX_OLD_RAGCOL") != ""
## the constraint solver in C# (RagdollSolverCs: ~half the ragdoll's cost); GDScript `_dist` / `_collide` stay the fallback
## (no C#, BMX_RAG_GD=1, or the old contact model)
var _cs = null
var _cs_try := false
var _CMP := Env.raw("BMX_RAG_CMP") != ""
var _cmp_max := 0.0
var _cmp_n := 0
var _cmp_near := 0
var _jn := PackedFloat32Array()    # normal speed the ground took out of each part this substep (per substep)
var _gn: Array = []                # ground normal under each part (this step)
var _near: Array = []              # the shapes near the body this step
var _gn_at := PackedVector2Array() # where each part's ground normal was read (x, z)
var probe_kick := 0.0              # tests: biggest upward speed a ground contact left a part with (m/s)
var probe_slide := 0.0             # tests: how far the pelvis went after the torso first touched (m)
var _slide_on := false
var _slide_last := Vector3.ZERO

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
var probe_rise := 0.0      # tests: highest the centre of mass got above where the crash started
var probe_vup := 0.0       # tests: fastest the centre of mass went up (m/s)
var _com0 := 0.0
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
	# the C# solver made and run once now (the ride loading), not on the first crash: its load + JIT cost ~2.8 ms
	if not _old_col and Env.raw("BMX_RAG_GD") == "":
		_cs_try = true
		var sc = load("res://scripts/rider/RagdollSolverCs.cs") if ClassDB.class_exists("CSharpScript") else null
		_cs = sc.new() if sc else null
		if _cs:
			_cs.Solve(PackedVector3Array([Vector3.ZERO, Vector3.UP]), PackedVector3Array([Vector3.ZERO, Vector3.UP]), PackedFloat32Array([-1.0, -1.0]),
				PackedVector3Array([Vector3.UP, Vector3.UP]), PackedFloat32Array([0.1, 0.1]), PackedInt32Array([0, 1]), PackedFloat32Array([1.0]),
				PackedFloat32Array([1.0]), PackedByteArray([0]), PackedFloat32Array([1.0, 3.0, 3.0, 0.0, 0.5, 0.5, 0.0, 3.0, 3.0, 0.0, 0.5, 0.0]), 0.003, 6, PackedFloat32Array([0.0, 0.0]))

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
	broken.clear()
	_jn.resize(RAD.size())
	_gn.resize(RAD.size())
	_gn.fill(Vector3.UP)
	_gn_at.resize(0)

## BROKEN BONES (fx/blood.gd on a very hard hit): an elbow / knee whose bone broke has no muscle tension
## and no fold limit left: the forearm / shin flops and can bend the wrong way. `kick` throws it the
## wrong way at once. Returns false if already broken / torn off.
var broken := {}              # elbow / knee index -> true
const LIM_MID := {0: EL_L, 1: EL_R, 2: KN_L, 3: KN_R}   # LIMITS index -> the joint between its ends
func break_joint(j: int, kick: Vector3) -> bool:
	if broken.has(j) or free_pt[j] == 1 or not LIMB_NEXT.has(j): return false
	broken[j] = true
	var c: int = LIMB_NEXT[j]
	q[c] = (q[c] as Vector3) - kick * (last_h if last_h > 0.0 else 1.0 / 360.0)
	return true

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
	_touch.fill(0)   # nothing on the ground yet (the last crash's contacts must not carry over)
	_shape_src = []; _shapes.clear()
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
	# (2026-11-24) a crash can start with joints in the ground: HEAD HIT upside down in a flip had up to 12
	# joints as deep as 0.83 m, and digging them out (+ the bones pulling back to length) threw the body
	# 10-14 m up. Now the buried joints are set on the ground and the bones settle round them first, every
	# move made to the last position too: the body crumples onto the ground with no speed from it.
	if not _old_col: _unbury()
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
	# the startle is the body's own muscles: it moves the limbs against the trunk, it can't lift the body.
	# Take its net push back out evenly (it added ~0.7 m/s upward to the whole body = a little launch).
	if not _old_col:
		var mean := Vector3.ZERO
		for i in p.size():
			mean += (p[i] as Vector3) - (q[i] as Vector3)
		mean /= float(p.size())
		var v_body := Vector3.ZERO
		for i in p.size():
			var pt: Vector3 = pts[i]
			var h := pt.y - pel.y
			v_body += (vel + spin * h) * hs   # (p may have been lifted out of the ground: the same speeds)
		v_body /= float(p.size())
		var extra := mean - v_body   # what the startle (+ the jitter) added to the whole body
		for i in p.size():
			q[i] = (q[i] as Vector3) + extra
	t_fall = 0.0
	probe_kick = 0.0; probe_slide = 0.0; _slide_on = false; _rest_said = false
	_com0 = _com().y
	if Env.raw("BMX_RAGDOLL_PROBE") != "":
		var deep := 0.0
		var nb := 0
		for i in RAD.size():
			var pp: Vector3 = p[i]
			var dg: float = terrain.height(pp.x, pp.z) + float(RAD[i]) - pp.y
			if dg > 0.0: nb += 1; deep = maxf(deep, dg)
		var v0 := Vector3.ZERO
		for i in RAD.size(): v0 += (p[i] as Vector3) - (q[i] as Vector3)
		print("RAGSTART buried=%d deepest=%.2f com_v=%s" % [nb, deep, str(v0 / RAD.size() / (dt / SUB))])
	probe_rise = 0.0
	probe_vup = 0.0
	_sq_ph = Vector3(randf(), randf(), randf()) * 10.0
	active = true
	last_h = dt / SUB


## buried joints onto the ground, the bones settled round them; p and q move together (no speed)
func _unbury() -> void:
	var np := p.size()
	var g := PackedFloat32Array()
	g.resize(np)
	var any := false
	for i in np:
		var pt: Vector3 = p[i]
		g[i] = terrain.height(pt.x, pt.z) + float(rad[i])
		if pt.y < g[i]: any = true
	if not any: return
	var p0 := p.duplicate()
	for it in 12:
		for i in np:
			var pt: Vector3 = p[i]
			if pt.y < g[i]: p[i] = Vector3(pt.x, g[i], pt.z)
		for j in BONES.size():
			_dist(BONES[j][0], BONES[j][1], rest[j], BONES[j][2], false)
	for i in np:
		var pt: Vector3 = p[i]
		if pt.y < g[i]: p[i] = Vector3(pt.x, g[i], pt.z)
		q[i] = (q[i] as Vector3) + ((p[i] as Vector3) - (p0[i] as Vector3))

## the same collider entries (by identity, in order) as the shapes were built from
func _same_colliders(cols: Array) -> bool:
	if cols.size() != _shape_src.size(): return false
	for i in cols.size():
		if not is_same(cols[i], _shape_src[i]): return false
	return true


## the frame profiler (F10): while it records, Game sets this to its per-frame dict ("rag.*" phases of step)
var prof = null
var _pt := 0
func _rp(k: String) -> void:
	var now := Time.get_ticks_usec()
	prof["rag." + k] = prof.get("rag." + k, 0) + (now - _pt)
	_pt = now

func step(dt: float, colliders: Array) -> void:
	if prof != null: _pt = Time.get_ticks_usec()
	var n := SUB
	var h := dt / n
	# time-corrected Verlet: rescale the previous substep's displacement to this substep's length
	var ratio := h / (last_h if last_h > 0.0 else h)
	last_h = h
	# collision shapes that match what you see: rocks = domes, trunks / cacti = thin cylinders
	# (rebuilt only when the colliders near the body change; the list is new each step, its entries are not)
	if not _same_colliders(colliders):
		_shape_src = colliders
		_shapes.clear()
		for c in colliders:
			if c.get("tape"):
				continue
			if c.get("top") != null:
				var base: float = terrain.height(c.x, c.z) - 0.15
				_shapes.append({rock = true, x = c.x, z = c.z, y = base, R = c.r * 0.9, H = maxf(0.1, c.top - base)})
			else:
				_shapes.append({rock = false, x = c.x, z = c.z, R = maxf(0.08, (c.r - 0.1) * 0.6)})
	var kt := h / H0
	var air_damp := pow(0.998, kt)
	var wet_damp := pow(0.94, kt)
	var drag := pow(SLIDE_DRAG, kt)
	var np := p.size()
	if _jn.size() != np: _jn.resize(np)
	if _gn.size() != np:
		var o := _gn.size()
		_gn.resize(np)
		for i in range(o, np): _gn[i] = Vector3.UP
	# a good copy to fall back on if anything goes non-finite this step
	var p_ok := p.duplicate()
	var q_ok := q.duplicate()
	# only the shapes the body can reach this step are tested (the list round the pelvis can hold dozens of
	# trunks / rocks, tested 15 parts x 6 passes x 3 substeps)
	var cen := Vector3.ZERO
	var vmax := 0.0
	for i in np:
		cen += p[i]
		vmax = maxf(vmax, ((p[i] as Vector3) - (q[i] as Vector3)).length())
	cen /= float(np)
	var reach := 0.0
	for i in np: reach = maxf(reach, Vector2((p[i] as Vector3).x - cen.x, (p[i] as Vector3).z - cen.z).length())
	reach += 0.25 + vmax * ratio * n
	_near.clear()
	for c in _shapes:
		if Vector2(cen.x - c.x, cen.z - c.z).length() < reach + float(c.R): _near.append(c)
	# the ground's tilt under each part near it (3 height reads), read again only once the part has moved
	# 10 cm from where it was last read: a body lying still costs nothing
	if not _old_col:
		if _gn_at.size() != np:
			_gn_at.resize(np)
			_gn_at.fill(Vector2(INF, INF))
		for i in np:
			var gp: Vector3 = p[i]
			var at := Vector2(gp.x, gp.z)
			if at.distance_squared_to(_gn_at[i]) < 0.01: continue
			var g0: float = terrain.height(gp.x, gp.z)
			if gp.y - g0 > float(rad[i]) + 0.5:
				_gn[i] = Vector3.UP   # well off the ground: read again when it comes down
				_gn_at[i] = Vector2(INF, INF)
				continue
			_gn_at[i] = at
			var e := 0.15
			var gx: float = terrain.height(gp.x + e, gp.z) - g0
			var gz: float = terrain.height(gp.x, gp.z + e) - g0
			var nn := Vector3(-gx, e, -gz).normalized()
			_gn[i] = nn if nn.is_finite() else Vector3.UP
	var vcap := MAX_V * h
	if prof != null: _rp("setup")
	for s in n:
		for i in np:
			var pp: Vector3 = p[i]
			var qq: Vector3 = q[i]
			var wet := pp.y < WATER
			var damp := (wet_damp if wet else air_damp) * (ratio if s == 0 else 1.0)
			var vel := (pp - qq) * damp
			if not _old_col:
				var vl := vel.length()
				if vl > vcap: vel *= vcap / vl
			q[i] = pp
			pp += vel
			pp.y -= (2.0 if wet else 9.81) * h * h
			p[i] = pp
		t_fall += h
		if prof != null: _rp("integrate")
		# the body's own muscles (reaching, tension, squirming) can bend it but can't spin it: whatever
		# whole-body spin they add is taken back (only the ground / things it hits can turn it)
		var L0 := _ang_mom()
		_agency_update(h)
		_neutral_pull(kt)
		_squirm(h)
		if not _no_lkeep: _keep_ang_mom(L0)
		if prof != null: _rp("muscles")
		_touch.fill(0)
		_jn.fill(0.0)
		# ground under each part once per substep (a C# call each); the 6 solver passes move parts by mm only
		_gh.resize(p.size())
		for i in p.size():
			var gp: Vector3 = p[i]
			_gh[i] = terrain.height(gp.x, gp.z)
		if prof != null: _rp("ground")
		if not _solver_cs():   # the 6 passes in C# when it's there (RagdollSolverCs), else here
			for it in 6:
				for j in BONES.size():
					var bb: int = BONES[j][1]
					if not cut.is_empty() and cut.has(bb) and BONES[j][0] != bb and LIMB_NEXT.get(BONES[j][0], -1) == bb: continue   # torn off
					_dist(BONES[j][0], bb, rest[j], BONES[j][2], false)
				for xb in _xbones:
					_dist(xb[0], xb[1], xb[2], 1.0, false)
				for j in LIMITS.size():
					if not cut.is_empty() and free_pt[LIMITS[j][0]] != free_pt[LIMITS[j][1]]: continue
					if not broken.is_empty() and broken.has(LIM_MID.get(j, -1)): continue   # broken: folds any way
					_dist(LIMITS[j][0], LIMITS[j][1], lim[j], 1.0, true)
				for xl in _xlims:
					_dist(xl[0], xl[1], xl[2], 1.0, true)
				for i in p.size():
					_collide(i)
		if prof != null: _rp("solver")
		# ground friction, once per substep for every part that touched: sliding friction (a body slides
		# a few metres off a fast crash, the blood smears it, fx/blood.gd) + a little drag so it settles
		for i in p.size():
			if _touch[i] == 0: continue
			var pp: Vector3 = p[i]
			var qq: Vector3 = q[i]
			if _old_col:
				var dx := pp.x - qq.x
				var dz := pp.z - qq.z
				var d := sqrt(dx * dx + dz * dz)
				if d < 1e-7: continue
				var fric := minf(d, SLIDE_MU * 9.81 * h * h)   # Coulomb: speed drops by mu*g*h per substep
				var k := (d - fric) / d * drag
				qq.x = pp.x - dx * k
				qq.z = pp.z - dz * k
				q[i] = qq
				continue
			# Coulomb on the real contact push (see CONTACT): along the ground the speed drops by mu x the speed
			# the ground took out of it square to it (at rest that is g h per substep; on a slam the whole hit)
			var nrm: Vector3 = _gn[i]
			var v := pp - qq
			var vn := v.dot(nrm)
			var vt := v - nrm * vn
			var d := vt.length()
			if d < 1e-7: continue
			var push := maxf(_jn[i], 9.81 * h * h * nrm.y)
			var k := maxf(0.0, d - ROUGH_MU * push) / d * drag
			q[i] = pp - (nrm * vn + vt * k)
		if prof != null: _rp("friction")
	var c := _com()
	# a step that went non-finite (a solver blow-up) is thrown away: back to the last good state, at rest
	if not c.is_finite():
		p = p_ok; q = q_ok
		for i in p.size():
			if not (p[i] as Vector3).is_finite(): p[i] = cen if cen.is_finite() else Vector3.ZERO
			q[i] = p[i]
		c = _com()
	if not _slide_on and (_touch[PELVIS] == 1 or _touch[CHEST] == 1):
		_slide_on = true; _slide_last = p[PELVIS]
	if _slide_on:
		var pv: Vector3 = p[PELVIS]
		probe_slide += Vector2(pv.x - _slide_last.x, pv.z - _slide_last.z).length()
		_slide_last = pv
	probe_rise = maxf(probe_rise, c.y - _com0)
	var cq := Vector3.ZERO
	for i in RAD.size(): cq += q[i]
	probe_vup = maxf(probe_vup, (c.y - cq.y / RAD.size()) / h)
	var sp := 0.0
	for i in p.size():
		sp = maxf(sp, (p[i] as Vector3).distance_to(q[i]) / h)
	speed = sp
	if _col_probe and floori((t_fall - h * n) / 0.5) != floori(t_fall / 0.5):
		var cv := Vector3.ZERO
		for i in RAD.size(): cv += (p[i] as Vector3) - (q[i] as Vector3)
		cv /= RAD.size() * h
		var pe: Vector3 = p[PELVIS]
		print("RAGCOL t=%.1f com_v=%.1f up=%.1f pelvis_h=%.2f slide=%.2f kick=%.1f rise=%.2f" % [t_fall, Vector2(cv.x, cv.z).length(), cv.y, pe.y - terrain.height(pe.x, pe.z), probe_slide, probe_kick, probe_rise])
	if _col_probe and not _rest_said and t_fall > 0.3 and sp < 0.6:
		_rest_said = true
		print("RAGCOL rest t=%.2f slide=%.2f rise=%.2f vup=%.1f kick=%.1f shapes=%d near=%d" % [t_fall, probe_slide, probe_rise, probe_vup, probe_kick, _shapes.size(), _near.size()])
var _col_probe := Env.raw("BMX_RAGCOL_PROBE") != ""   # tests: RAGCOL line when the body comes to rest
var _rest_said := false


## the body's spin (angular momentum about its centre, equal masses, velocity = p - q); torn-off pieces
## are their own bodies and left out
func _ang_mom() -> Vector3:
	var c := Vector3.ZERO
	var m := 0
	for i in p.size():
		if i < free_pt.size() and free_pt[i] == 1: continue
		c += p[i]
		m += 1
	c /= maxf(1.0, m)
	var L := Vector3.ZERO
	for i in p.size():
		if i < free_pt.size() and free_pt[i] == 1: continue
		var pp: Vector3 = p[i]
		L += (pp - c).cross(pp - (q[i] as Vector3))
	return L

## put the body's spin back to L0: a rigid turn of every velocity by w = I^-1 (L - L0)
func _keep_ang_mom(L0: Vector3) -> void:
	var c := Vector3.ZERO
	var m := 0
	for i in p.size():
		if i < free_pt.size() and free_pt[i] == 1: continue
		c += p[i]
		m += 1
	c /= maxf(1.0, m)
	var L := Vector3.ZERO
	var xx := 0.0; var yy := 0.0; var zz := 0.0; var xy := 0.0; var xz := 0.0; var yz := 0.0
	for i in p.size():
		if i < free_pt.size() and free_pt[i] == 1: continue
		var pp: Vector3 = p[i]
		var r := pp - c
		L += r.cross(pp - (q[i] as Vector3))
		xx += r.x * r.x; yy += r.y * r.y; zz += r.z * r.z
		xy += r.x * r.y; xz += r.x * r.z; yz += r.y * r.z
	var dL := L - L0
	if dL.length_squared() < 1e-14: return
	var I := Basis(Vector3(yy + zz, -xy, -xz), Vector3(-xy, xx + zz, -yz), Vector3(-xz, -yz, xx + yy))
	if absf(I.determinant()) < 1e-9: return
	var w: Vector3 = I.inverse() * dL
	for i in p.size():
		if i < free_pt.size() and free_pt[i] == 1: continue
		var r: Vector3 = (p[i] as Vector3) - c
		q[i] = (q[i] as Vector3) + w.cross(r)

func _com() -> Vector3:
	var c := Vector3.ZERO
	for i in RAD.size(): c += p[i]
	return c / RAD.size()

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
	# a foot / knee / hand down: he's landed, stop reaching (reaching on into the ground = jumping off it)
	for j in [FT_L, FT_R, KN_L, KN_R, HA_L, HA_R]:
		if _touch[j] == 1:
			agency = 0.0
			break
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
	p[PELVIS] = pe - d * 1.6   # balanced: it turns the body, never lifts or pushes it

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
	# sideways it's not quite balanced (the centre of mass drifts a little); up / down it is, so it never lifts
	var dp := Vector3(d.x * 0.8, d.y * 1.5, d.z * 0.8)
	p[CHEST] = (p[CHEST] as Vector3) + d
	p[PELVIS] = (p[PELVIS] as Vector3) - dp
	p[HEAD] = (p[HEAD] as Vector3) + d * 0.5

## tension toward the neutral posture + a soft limit (see NEUTRAL)
var tone_k := float(Env.raw("BMX_RAGDOLL_TONE")) if Env.raw("BMX_RAGDOLL_TONE") != "" else 1.0   # tests: x the tension / soft limit
var nb_off := 0.0          # tests: summed neutral offsets (BMX_RAGDOLL_PROBE)
func _neutral_pull(kt := 1.0) -> void:
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
		if not broken.is_empty() and broken.has(NEUTRAL[k][1]): continue   # broken bone: nothing holds it
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
		var corr := d / dl * minf(f * L, (dl - dead * L) * 0.06) * (kt * kt)   # a spring: per substep ~ h^2
		# never press a part that's on the ground down into it: the ground would push the body up (a jump)
		if (_touch[c] == 1 and corr.y < 0.0) or (_touch[par] == 1 and corr.y > 0.0): corr.y = 0.0
		# equal and opposite on the part and its parent: the body can't push itself along
		p[c] = cp + corr * 0.5
		p[par] = pc - corr * 0.5
		# damping: bleed off the part's swing relative to its parent (muscles don't ring like springs)
		var vrel: Vector3 = (cp - (q[c] as Vector3)) - (pc - (q[par] as Vector3))
		var dv := vrel * minf(0.5, TONE_DAMP * kt)
		q[c] = (q[c] as Vector3) + dv * 0.5
		q[par] = (q[par] as Vector3) - dv * 0.5

## one substep's 6 solver passes in C# (RagdollSolverCs). Returns false when it can't (no C#, BMX_RAG_GD, old contacts)
func _solver_cs() -> bool:
	if _old_col: return false
	if not _cs_try:
		_cs_try = true
		if Env.raw("BMX_RAG_GD") == "":
			var sc = load("res://scripts/rider/RagdollSolverCs.cs") if ClassDB.class_exists("CSharpScript") else null
			_cs = sc.new() if sc else null
	if _cs == null: return false
	# the constraint list in the GDScript order: bones, extra bones, limits, extra limits (torn-off / broken left out)
	var cons := PackedInt32Array(); var clen := PackedFloat32Array(); var ck := PackedFloat32Array(); var cmin := PackedByteArray()
	for j in BONES.size():
		var bb: int = BONES[j][1]
		if not cut.is_empty() and cut.has(bb) and BONES[j][0] != bb and LIMB_NEXT.get(BONES[j][0], -1) == bb: continue
		cons.append_array([BONES[j][0], bb]); clen.append(rest[j]); ck.append(BONES[j][2]); cmin.append(0)
	for xb in _xbones:
		cons.append_array([xb[0], xb[1]]); clen.append(xb[2]); ck.append(1.0); cmin.append(0)
	for j in LIMITS.size():
		if not cut.is_empty() and free_pt[LIMITS[j][0]] != free_pt[LIMITS[j][1]]: continue
		if not broken.is_empty() and broken.has(LIM_MID.get(j, -1)): continue
		cons.append_array([LIMITS[j][0], LIMITS[j][1]]); clen.append(lim[j]); ck.append(1.0); cmin.append(1)
	for xl in _xlims:
		cons.append_array([xl[0], xl[1]]); clen.append(xl[2]); ck.append(1.0); cmin.append(1)
	var sh := PackedFloat32Array()
	for c in _near:
		if c.rock: sh.append_array([1.0, c.x, c.z, c.y, c.R, c.H])
		else: sh.append_array([0.0, c.x, c.z, 0.0, c.R, 0.0])
	var gn := PackedVector3Array(_gn)
	var radf := PackedFloat32Array(rad)
	_cs.Solve(PackedVector3Array(p), PackedVector3Array(q), _gh, gn, radf, cons, clen, ck, cmin, sh, last_h, 6, _jn.duplicate())
	var P2: PackedVector3Array = _cs.GetP()
	var Q2: PackedVector3Array = _cs.GetQ()
	if _CMP:   # tests (BMX_RAG_CMP=1): the GDScript passes from the same state, compared with C#'s
		var pb := p.duplicate(); var qb := q.duplicate()
		_touch.fill(0)
		for it in 6:
			for j in BONES.size():
				var bb: int = BONES[j][1]
				if not cut.is_empty() and cut.has(bb) and BONES[j][0] != bb and LIMB_NEXT.get(BONES[j][0], -1) == bb: continue
				_dist(BONES[j][0], bb, rest[j], BONES[j][2], false)
			for xb in _xbones: _dist(xb[0], xb[1], xb[2], 1.0, false)
			for j in LIMITS.size():
				if not cut.is_empty() and free_pt[LIMITS[j][0]] != free_pt[LIMITS[j][1]]: continue
				if not broken.is_empty() and broken.has(LIM_MID.get(j, -1)): continue
				_dist(LIMITS[j][0], LIMITS[j][1], lim[j], 1.0, true)
			for xl in _xlims: _dist(xl[0], xl[1], xl[2], 1.0, true)
			for i in p.size(): _collide(i)
		var dm := 0.0
		for i in p.size(): dm = maxf(dm, maxf((p[i] as Vector3).distance_to(P2[i]), (q[i] as Vector3).distance_to(Q2[i])))
		_cmp_max = maxf(_cmp_max, dm); _cmp_n += 1
		if not _near.is_empty(): _cmp_near = maxi(_cmp_near, _near.size())
		if _cmp_n % 360 == 0: print("RAGCMP substeps=%d max_diff_mm=%.4f most_shapes_near=%d" % [_cmp_n, _cmp_max * 1000.0, _cmp_near])
		p = pb; q = qb
	for i in p.size():
		p[i] = P2[i]; q[i] = Q2[i]
	_touch = _cs.GetTouch()
	_jn = _cs.GetJn()
	probe_kick = maxf(probe_kick, _cs.GetKick())
	return true


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


var _gh := PackedFloat32Array()   # ground height under each part this substep (step)

func _collide(i: int) -> void:
	var pp: Vector3 = p[i]
	var qq: Vector3 = q[i]
	var r: float = rad[i]
	var g: float = _gh[i] + r
	if pp.y < g:
		_touch[i] = 1   # ground friction after the solver passes (step)
		if _old_col:
			pp.y = g
			if qq.y < pp.y - 0.02:
				qq.y = pp.y - (pp.y - qq.y) * 0.3   # small bounce
			if pp.y > qq.y: probe_kick = maxf(probe_kick, (pp.y - qq.y) / maxf(last_h, 1e-6))
		else:
			# out of the ground (straight up: the ground is a height field), keeping the part's own speed;
			# then its speed into the ground (along the ground's normal) is taken out: see CONTACT
			var v := pp - qq
			pp.y = g
			var nrm: Vector3 = _gn[i]
			var vn := v.dot(nrm)
			if vn < 0.0:
				var out := -vn * BOUNCE if -vn > BOUNCE_MIN * last_h else 0.0
				v += nrm * (-vn + out)
				_jn[i] += -vn
			qq = pp - v
			if v.y > 0.0: probe_kick = maxf(probe_kick, v.y / maxf(last_h, 1e-6))
	var shapes: Array = _shapes if _old_col else _near
	for c in shapes:
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
			var vr := pp - qq
			pp = Vector3(c.x + dx / k, c.y + dy / k, c.z + dz / k)
			if _old_col:
				qq.x += (pp.x - qq.x) * 0.1
				qq.z += (pp.z - qq.z) * 0.1
			else:
				qq = pp - _surface_v(vr, Vector3(dx / (R * R), dy / (H * H), dz / (R * R)).normalized())
		else:
			var d := sqrt(dx * dx + dz * dz)
			var m: float = c.R + r * 0.6
			if d < m and d > 1e-4:
				var vc := pp - qq
				pp.x = c.x + dx / d * m
				pp.z = c.z + dz / d * m
				if not _old_col: qq = pp - _surface_v(vc, Vector3(dx / d, 0.0, dz / d))
	p[i] = pp
	q[i] = qq

## a part's velocity after touching a rock / trunk with normal n: nothing into it (no bounce, and the
## push-out gives no speed), the slide along it a little slowed
func _surface_v(v: Vector3, n: Vector3) -> Vector3:
	if not n.is_finite(): return v
	var vn := v.dot(n)
	if vn < 0.0: v -= n * vn
	var vt := v - n * v.dot(n)
	return v - vt * (1.0 - ROCK_SLIDE)
