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
const HAND_FLING := 1.3    # m/s up (+ out) given to the hands / elbows as the fall starts
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

## BEHAVIOURS (2026-11-27, user: "a lifeless puppet, no muscles or joints that stop it; can he try to roll or land on his
## feet?"). On top of the tone above, what a falling rider does (the Euphoria idea, small), each a weight that eases in /
## out (no snapping) and drives the muscles harder toward its own pose (torso frame, right side; the left mirrors x):
##  * TUCK + ROLL: thrown fast (> TUCK_V) or tumbling (spine turning > TUCK_SPIN rad/s), in the air or sliding: chin in,
##    knees to the chest, arms round the head. Angular momentum is kept (_keep_ang_mom), so the compact body spins
##    faster and rolls along the ground instead of flopping.
##  * LAND (the old agency): a slower fall from height: legs reach down, arms out for balance.
##  * BRACE: about to hit (chest < BRACE_T s from the ground) and not tucking: arms reach for the ground, elbows soft.
##  * PAIN: stopped for PAIN_FROM s: curls up, a hand to the body, squirms; fades out over PAIN_T, then he lies still.
##  * KNOCKED OUT: a head hit harder than KO_HIT m/s: every behaviour stops and the tone drops to KO_TONE (limp).
## Knees bend the way knees do (_hinges: the hip rotation is limited, never backwards); elbows have no rule.
## BMX_OLD_RAGBEH=1 = none of this. Probe BMX_RAGBEH=1 (RAGBEH lines: weights, speed, spin).
const TUCK_V := 5.5
## the tuck only lasts TUCK_MAX s of contact: tucked on a slope he rolled down it like a ball for good (F8 2026-11-27:
## 35 m and still rolling). After it, still sliding / rolling, he SPREADS out (arms and legs wide) to stop himself.
const TUCK_MAX := 1.2
## ROCKING IN PAIN (rigid bodies, user: "rolling side to side on his back a few times, curled up, then slowing down"):
## lying hurt, both curled knees swing to one side then the other at ROCK_HZ (slowing to 55 %), driven ROCK_DRIVE x
## harder, the arms hug them; it is the legs' weight shifting that rolls the body (no outside push). ROCK_T s, then it
## settles over 1.5 s
const ROCK_HZ := 0.7
const ROCK_T := 4.0
const ROCK_DRIVE := 3.0
const SPREAD_DRIVE := 2.5
const SPREAD := {
	0: Vector3(0.0, 0.85, 0.5),
	1: Vector3(0.9, 0.1, 0.4),       # arms out
	2: Vector3(0.8, 0.1, 0.55),
	3: Vector3(0.45, -0.85, 0.25),   # legs apart
	4: Vector3(0.1, -0.97, -0.1),
}
const TUCK_SPIN := 3.5
const TUCK_DRIVE := 4.5
const BRACE_T := 0.3
const BRACE_DRIVE := 3.5
const PAIN_FROM := 0.6
const PAIN_T := 3.5
const PAIN_DRIVE := 1.6
const KO_HIT := 8.0
const KO_TONE := 0.35
const HINGE_K := 0.35         # share of a wrong-way bend undone per substep
## joint ranges (2026-11-27, user: "in the air his limbs rotate and fling like crazy, no limits"): shoulders, hips and the
## neck are ball joints; each limb may turn at most this far (rad) from its neutral direction (torso frame), pushed back
## equal and opposite (the limb and its root)
const CONES := {0: 0.8, 1: 2.0, 5: 2.0, 3: 1.3, 7: 1.3}   # NEUTRAL index -> max angle
const CONE_K := 0.4
## a falling person holds the limbs against the trunk (co-contraction): their swing against the parent is damped this
## much per substep (TONE_DAMP alone let the spin fling them round); knocked out = TONE_DAMP
const LIMB_DAMP := 0.018
## WINDMILL (GTA-style falling): high in the air with time before he hits, he fights for balance: arms circle (opposite
## phase), legs cycle like running, driven MILL_DRIVE x the tone. Off when tucking / bracing / held to the bike.
const MILL_DRIVE := 2.5
const MILL_HZ := 1.4
## HURT: the part that hit the ground hardest (> HURT_MIN m/s) is held by the other hand while he lies in pain
const HURT_MIN := 4.0
## SELF-COLLISION: hands, elbows, knees, feet are kept out of the trunk (a capsule pelvis -> chest) and the head
const TRUNK_R := 0.11
const SELF_LIMBS := [EL_L, HA_L, EL_R, HA_R, KN_L, FT_L, KN_R, FT_R]
const TUCK := {               # NEUTRAL index -> direction in the torso frame (right side)
	0: Vector3(0.0, 0.5, 0.87),        # chin in
	1: Vector3(0.25, 0.4, 0.88),       # upper arms up in front of the face
	2: Vector3(-0.5, 0.78, 0.1),       # forearms round the head
	3: Vector3(0.12, 0.55, 0.83),      # knees to the chest
	4: Vector3(0.0, -0.8, -0.6),       # heels in
}
const PAIN := {
	0: Vector3(0.0, 0.7, 0.71),
	1: Vector3(0.15, -0.35, 0.92),
	2: Vector3(-0.65, 0.45, 0.6),      # a hand to the stomach
	3: Vector3(0.15, -0.05, 0.98),     # knees drawn up
	4: Vector3(0.0, -0.85, -0.5),
}
var _OLD_BEH := Env.raw("BMX_OLD_RAGBEH") != ""
var _BEH_PROBE := Env.raw("BMX_RAGBEH") != ""
var ko := false
var w_tuck := 0.0
var w_brace := 0.0
var w_pain := 0.0
var _rest_t := 0.0
var _u_prev := Vector3.ZERO
var _spin := 0.0
var _beh_said := -1
var w_mill := 0.0
var _rock_ph := 0.0
var _rock_dt := 1.0 / 120.0
## RIGID BODIES (RagdollRbCs, 2026-11-27, user: "make the ragdoll like GTA", "joint sockets limit this"): the body is 11
## solid parts joined by real joints (swing / twist / hinge limits on every axis), the muscles are joint motors that the
## behaviours above aim (_neutral_pull in target mode). The 15 points are read off the bodies every step, so everything
## that reads p / q (blood, get-up, camera, the drawing, the bike's contacts) is unchanged. No C# or BMX_OLD_RAGDOLL=1 =
## the point ragdoll below.
var _rb = null
var _RB_OFF := Env.raw("BMX_OLD_RAGDOLL") != ""
const RB_JOINT := {HEAD: 1, EL_L: 2, EL_R: 3, KN_L: 4, KN_R: 5, HA_L: 6, HA_R: 7, FT_L: 8, FT_R: 9}   # child point -> joint (motor) index
const RB_LIMB_JOINT := {SH_L: 2, EL_L: 6, SH_R: 3, EL_R: 7, HIP_L: 4, KN_L: 8, HIP_R: 5, KN_R: 9}   # sever / break at point -> joint
var _rb_dir := PackedVector3Array()
var _rb_k := PackedFloat32Array()
const RB_PUSH_DV := 3.0   # m/s a step at most from the bike's pushes / holds
const RB_SQUIRM := 9.0     # N m of the chest / pelvis couple at full squirm
var w_spread := 0.0
var _tuck_gnd := 0.0   # s tucked while touching
var _OFF: PackedStringArray = Env.raw("BMX_RAG_OFF").split(",", false)   # tests: hinge, cone, cross, self, pain, damp
var contact_ext := 9.0   # s since the body last touched something outside the terrain (the bike: BikePhysics)
var _NOSELF := Env.raw("BMX_RAG_NOSELF") != ""   # tests
var _NOMILL := Env.raw("BMX_RAG_NOMILL") != ""   # tests
var _mill_ph := 0.0
var _air_t := 0.0
var hurt := -1
var _hurt_v := 0.0
var _head_was := false
var _fl_prev := []
var _bd_prev := []
var _bd_a := 0.0; var _bd_t := 0.0
var _fl_a := 0.0; var _fl_at := 0.0; var _fl_g := 0.0; var _fl_gt := 0.0
var _head_vy := 0.0


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
	if not _RB_OFF and ClassDB.class_exists("CSharpScript"):
		var rsc = load("res://scripts/rider/RagdollRbCs.cs")
		if rsc:
			var w = rsc.new()
			w.Warm()   # (its JIT at the ride loading, not the first crash)
			_rb = rsc.new()
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
	if _rb != null and active:
		_rb.BreakJoint(int(RB_LIMB_JOINT[j]))
		_rb.PushPoint(c, Vector3.ZERO, kick)
		return true
	q[c] = (q[c] as Vector3) - kick * (last_h if last_h > 0.0 else 1.0 / 360.0)
	return true

## tear off the limb below joint a (shoulder / elbow / hip / knee): its bone a-b goes, b and below fly free
## on their own root point. Returns the root's index (-1: already off / not a limb joint).
const LIMB_NEXT := {SH_L: EL_L, EL_L: HA_L, SH_R: EL_R, EL_R: HA_R, HIP_L: KN_L, KN_L: FT_L, HIP_R: KN_R, KN_R: FT_R}
func sever(a: int, kick := Vector3.ZERO) -> int:
	if not LIMB_NEXT.has(a): return -1
	var b: int = LIMB_NEXT[a]
	if free_pt[a] == 1 or free_pt[b] == 1: return -1
	if _rb != null and active:
		var ri: int = _rb.Sever(int(RB_LIMB_JOINT[a]))
		if ri >= 0: _rb.PushPoint(b, Vector3.ZERO, kick)
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
	_bal_try = false
	if _rb != null and not _OLD_BAL:
		var up_s: Vector3 = ((pts[CHEST] as Vector3) - (pts[PELVIS] as Vector3)).normalized()
		var pe_s: Vector3 = pts[PELVIS]
		var fl_s: Vector3 = pts[FT_L]
		var fr_s: Vector3 = pts[FT_R]
		var low: float = minf(fl_s.y - terrain.height(fl_s.x, fl_s.z), fr_s.y - terrain.height(fr_s.x, fr_s.z))
		_bal_try = Vector2(vel.x, vel.z).length() < BAL_V and acos(clampf(up_s.y, -1.0, 1.0)) < BAL_TILT_START \
			and pe_s.y - terrain.height(pe_s.x, pe_s.z) > 0.6 and low < 0.5
	if _bal_try: spin = Vector3.ZERO   # (catching himself at walking pace: no hard-crash throw of the trunk)
	_reset_points()
	_touch.fill(0)   # nothing on the ground yet (the last crash's contacts must not carry over)
	_shape_src = []; _shapes.clear()
	var pel: Vector3 = pts[PELVIS]
	for i in p.size():
		var pt: Vector3 = pts[i]
		p[i] = pt
		var h := pt.y - pel.y
		var d := vel + spin * h + Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * (0.6 if _OLD_BEH else 0.2)
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
	for side in ([] if _bal_try else [[EL_L, HA_L, -1.0], [EL_R, HA_R, 1.0]]):
		var fling: Vector3 = (fr.y * HAND_FLING + fr.x * (side[2] * HAND_FLING * 0.35)) * (0.8 + randf() * 0.4)
		q[side[1]] = (q[side[1]] as Vector3) - fling * hs
		q[side[0]] = (q[side[0]] as Vector3) - fling * 0.6 * hs
	for j in ([] if _bal_try else [KN_L, FT_L, KN_R, FT_R]):
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
	if _rb != null:
		var pv := PackedVector3Array()
		var hs0 := dt / SUB
		for i in RAD.size(): pv.append(((p[i] as Vector3) - (q[i] as Vector3)) / hs0)
		var sh: Array = shoes_in if shoes_in.size() == 2 else [Transform3D(Basis(), p[FT_L]), Transform3D(Basis(), p[FT_R])]
		_rb.Begin(PackedVector3Array(p.slice(0, RAD.size())), pv, _fsign, NEUTRAL[1][2], NEUTRAL[3][2], sh[0], sh[1], shoe_box.position, shoe_box.end)
		if Env.raw("BMX_RB_DBG") != "": _rb.Dbg = int(Env.raw("BMX_RB_DBG"))   # tests: solver parts off (RagdollRbCs.Dbg)
		if Env.raw("BMX_RB_DBGJ") != "": _rb.DbgJ = int(Env.raw("BMX_RB_DBGJ"))
		if _BEH_PROBE: print("RBFEET box=%s shoeL=%s ft=%s" % [str(shoe_box), str(sh[0]), str(p[FT_L])])
		shoe_xf = [_rb.ShoeXf(0), _rb.ShoeXf(1)]
		_rb_dir.resize(10); _rb_k.resize(10); _rb_k.fill(0.0)
		_rb_trunk_src = []
	t_fall = 0.0
	ko = false; w_tuck = 0.0; w_brace = 0.0; w_pain = 0.0; _rest_t = 0.0; _u_prev = Vector3.ZERO; _spin = 0.0; _beh_said = -1; _head_was = false; _head_vy = 0.0; contact_ext = 0.0; _rock_ph = 0.0; w_spread = 0.0; _tuck_gnd = 0.0; _knee_way = [0.0, 0.0, 0.0, 0.0]; w_mill = 0.0; _mill_ph = randf() * TAU; _air_t = 0.0; hurt = -1; _hurt_v = 0.0; _fl_prev = []; _bd_prev = []; _bd_a = 0.0; _bd_t = 0.0; _fl_a = 0.0; _fl_at = 0.0; _fl_g = 0.0; _fl_gt = 0.0
	probe_kick = 0.0; probe_slide = 0.0; _slide_on = false; _rest_said = false
	bal_on = false; bal_failed = false; stood = false; _bal_t = 0.0; _bal_still = 0.0; _bal_ph = 1.0; _bal_steps = 0; _bal_down = false
	if _rb != null and not _OLD_BAL:
		var hv := Vector2(vel.x, vel.z).length()
		var up0: Vector3 = _frame().y
		var pe0: Vector3 = p[PELVIS]
		var fl: Vector3 = p[FT_L]
		var frr: Vector3 = p[FT_R]
		var hl: float = fl.y - terrain.height(fl.x, fl.z)
		var hr: float = frr.y - terrain.height(frr.x, frr.z)
		if _bal_try:
			bal_on = true
			_bal_up_prev = up0
			_bal_com_prev = _com()
			_bal_v = Vector3(vel.x, 0.0, vel.z)
			_bal_stance = 0 if hl <= hr else 1   # the lower foot takes the weight, the other steps at once
			_bal_ph = 0.0
		if _BAL_PROBE: print("BAL start on=%s v=%.1f tilt=%.2f feet=%.2f/%.2f spin=%s vel=%s" % [bal_on, hv, acos(clampf(up0.y, -1.0, 1.0)), hl, hr, str(spin.snapped(Vector3.ONE * 0.01)), str(vel.snapped(Vector3.ONE * 0.01))])
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
	if _rb != null:
		_step_rb(dt, colliders)
		return
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
		if not _OLD_BEH: _behave(h)
		if _BEH_PROBE:
			_flail_probe(h)
			if _RAGDUMP != "" and t_fall < 8.0: _dump_row()
			if _OLD_BEH and floori(t_fall / 0.25) != _beh_said:
				_beh_said = floori(t_fall / 0.25)
				print("RAGBEH flail_air=%.1f flail_ground=%.1f bend_rate=%.1f t=%.2f (old)" % [_fl_a / maxf(_fl_at, 1e-3), _fl_g / maxf(_fl_gt, 1e-3), _bd_a / maxf(_bd_t, 1e-3), t_fall])
		_neutral_pull(kt)
		if not _OLD_BEH:
			if not _OFF.has("hinge"): _hinges()
			if not _OFF.has("cone"): _cones()
			if not _OFF.has("cross"): _no_cross()
			if not _NOSELF and not _OFF.has("self"): _self_collide()
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


## one step of the rigid-body ragdoll (see RIGID BODIES): behaviours on last step's points -> motor targets -> the bodies

## BALANCE (2026-11-27, user: "balance controller: stumble / run out slow crashes"). A crash that starts slow (under
## BAL_V) and upright with the feet near the ground: the rider tries to stay on his feet, the way SIMBICON-style physics
## characters stand and walk. Real motors only, no outside force: the STANCE leg's hip motor is aimed so that, with the
## foot planted (friction), its reaction turns the pelvis + torso back upright (PD on the torso's tilt); its knee
## straight. The SWING leg steps toward the capture point (the centre of mass + its velocity x sqrt(h / g)): the knee
## lifts mid-swing. Spine and neck held upright, arms a little out. A new step whenever the capture point leaves the
## stance foot. Gives up (into the normal ragdoll behaviours) when anything but a foot touches the ground, the torso
## tilts past BAL_TILT_FAIL, the centre of mass drops under BAL_COM_MIN or after BAL_T; standing still for BAL_STILL =
## stood (Game puts him back on the bike). BMX_OLD_BALANCE=1 = off, BMX_BAL_PROBE=1 = BAL lines
const BAL_V := 4.5           # m/s: faster than this and he doesn't try
const BAL_TILT_START := 0.95 # rad: the torso at least this upright at the crash (the riding crouch leans ~0.75)
const BAL_TILT_FAIL := 1.15
const BAL_COM_MIN := 0.55    # m over the ground
const BAL_COM_MAX := 1.15
const BAL_T := 5.0
const BAL_STILL := 0.7
const BAL_SWING_T := 0.22     # s a step takes
const BAL_KD := 0.12         # s: the tilt's damping (PD)
const BAL_STRIDE := 0.5      # m: the longest step, hip to foot (flat)
const BAL_CP_K := 1.6        # steps this far past the capture point (x): further = braking
const BAL_LEAN_BACK := 0.12  # rad per m/s: the trunk leans back against the speed
const BAL_K_STANCE := 400.0  # motor strengths (x the tone): a standing leg holds the body's weight
const BAL_K_SWING := 30.0
const BAL_K_KNEE := 160.0
const BAL_LEG_DAMP := 6.0    # the leg joints' damping x while balancing
const BAL_K_ANKLE := 12.0
const BAL_KNEE := 0.3       # rad: the stance knee's bend
const BAL_DROP_T := 0.45     # s: at most this long getting the feet down off the pedals
const BAL_K_SPINE := 35.0
var bal_on := false
var bal_failed := false
var stood := false
var _bal_t := 0.0
var _bal_still := 0.0
var _bal_stance := 0         # 0 left, 1 right
var _bal_ph := 1.0           # swing phase 0..1 (1 = both feet down)
var _bal_up_prev := Vector3.UP
var _bal_com_prev := Vector3.ZERO
var _bal_v := Vector3.ZERO
var _bal_steps := 0
var _bal_down := false        # a foot on the ground yet
var _bal_try := false
var _OLD_BAL := Env.raw("BMX_BALANCE") == ""   # off: slow crashes fall like any other (GTA-style ragdoll). BMX_BALANCE=1 = the experimental controller
var _BAL_PROBE := Env.raw("BMX_BAL_PROBE") != ""

## step -> the points (and their velocities as q = p - v dt) read back
var _rb_trunk_src: Array = []
## the feet (rigid bodies): the shoes' world transforms + their mesh box at the crash start (Game.start_crash sets them
## before start()); shoe_xf = where the shoes are drawn now (Rider.pose_ragdoll)
var shoes_in: Array = []
var shoe_box := AABB(Vector3(-0.11, 0.0, -0.05), Vector3(0.28, 0.1, 0.1))
var shoe_xf: Array = []
func _step_rb(dt: float, colliders: Array) -> void:
	last_h = dt
	if colliders != _rb_trunk_src:
		_rb_trunk_src = colliders
		var cyl := PackedFloat32Array()
		for c in colliders:
			if c.get("tape") or c.get("top") != null: continue   # (rocks / logs are domes in the ground's height)
			cyl.append(float(c.x)); cyl.append(float(c.z)); cyl.append(maxf(0.08, (float(c.r) - 0.1) * 0.6)); cyl.append(1e6)
		_rb.SetTrunks(cyl)
	if t_fall == 0.0:
		var own: bool = terrain.get_script() != null and terrain.get_script().resource_path == "res://scripts/world/terrain.gd"
		var fld = terrain.fcs if own and terrain.fcs != null and terrain.cs_tyres and terrain.ropes.is_empty() else null
		_rb.SetGround(fld, Callable(terrain, "top_height"), WATER)
	_agency_update(dt)
	if not _OLD_BEH: _behave(dt)
	if _BEH_PROBE:
		_flail_probe(dt)
		if _RAGDUMP != "" and t_fall < 8.0: _dump_row()
	_rock_dt = dt
	_neutral_pull(1.0, true)   # -> _rb_dir / _rb_k
	if bal_on: _balance(dt)
	_rb.AnkleMax = BAL_K_ANKLE if bal_on else 1e9
	_rb.LegDampMul = BAL_LEG_DAMP if bal_on else 1.0
	_rb.SetMotors(_rb_dir, _rb_k)
	# the squirm: a slow wandering twist of the chest against the pelvis (more while lying hurt), none knocked out
	if not ko:
		var amp := maxf(exp(-t_fall / SQUIRM_T), 0.5 * w_pain) * tone_k
		if amp > 0.01 and t_fall < SQUIRM_T * 1.5 + 6.0:
			var b := _frame()
			if b.x.is_finite():
				var tq: Vector3 = b.y * sin(t_fall * 2.3 + _sq_ph.x) + b.z * 0.5 * sin(t_fall * 1.7 + _sq_ph.y)
				_rb.Couple(RagdollRbCs_B_CHEST, RagdollRbCs_B_PELVIS, tq * RB_SQUIRM * amp * dt)
	if prof != null: _rp("muscles")
	_rb.Step(dt)
	if _BEH_PROBE and t_fall < 0.35:
		var bs: PackedFloat32Array = _rb.BodySpeeds()
		var line := "RBSTEP t=%.3f" % t_fall
		for i in 13: line += " %s=%.1f/%.0f" % [["pel", "che", "hea", "uaL", "faL", "uaR", "faR", "thL", "shL", "thR", "shR", "ftL", "ftR"][i], bs[2 * i], bs[2 * i + 1]]
		print(line)
	if prof != null: _rp("solver")
	var P: PackedVector3Array = _rb.Points()
	# velocities = the real move this step (q = last step's points): the bodies' own spin carries tiny solver noise that,
	# times an offset, read as a limb moving 3 m/s on a body lying still
	var V := PackedVector3Array(); V.resize(P.size())
	while p.size() < P.size():   # (a torn-off piece's root point appears)
		p.append(P[p.size()]); q.append(P[q.size()])
	for i in P.size():
		V[i] = (P[i] - (p[i] as Vector3)) / dt
		q[i] = p[i]; p[i] = P[i]
	shoe_xf = [_rb.ShoeXf(0), _rb.ShoeXf(1)]
	var tch: PackedByteArray = _rb.Touch()
	var hit: PackedFloat32Array = _rb.Hit()
	for i in RAD.size():
		_touch[i] = tch[i]
		_jn[i] = hit[i] * dt
	t_fall += dt
	var c := _com()
	probe_rise = maxf(probe_rise, c.y - _com0)
	var cv := Vector3.ZERO
	for i in RAD.size(): cv += V[i]
	probe_vup = maxf(probe_vup, cv.y / RAD.size())
	var sp := 0.0
	for i in mini(V.size(), p.size()): sp = maxf(sp, V[i].length())
	speed = sp
	if _BEH_PROBE and floori(t_fall / 0.5) != floori((t_fall - dt) / 0.5):
		print("RAGRB t=%.2f speed=%.2f worst_limit=%.3f" % [t_fall, speed, _rb.WorstLimit()])
	if _BEH_PROBE and w_pain > 0.01 and floori(t_fall / 0.1) != floori((t_fall - dt) / 0.1):
		var bb := _frame()
		print("ROCK t=%.1f pain=%.2f roll_deg=%.0f" % [t_fall, w_pain, rad_to_deg(asin(clampf(bb.x.y, -1.0, 1.0)))])
const RagdollRbCs_B_CHEST := 1
const RagdollRbCs_B_PELVIS := 0

## one step of the balance controller (see BALANCE): writes the motors' aims / strengths over the behaviours'
func _balance(dt: float) -> void:
	var c := _com()
	var vel := (c - _bal_com_prev) / maxf(dt, 1e-4)
	_bal_com_prev = c
	_bal_v = _bal_v.lerp(Vector3(vel.x, 0.0, vel.z), minf(1.0, dt * 20.0))
	var fr := _frame()
	if not fr.x.is_finite():
		bal_on = false
		return
	var up: Vector3 = fr.y
	var tilt := acos(clampf(up.y, -1.0, 1.0))
	var gc: float = terrain.height(c.x, c.z)
	# give up: anything but the feet on the ground, too far over, too low, too long
	var why := ""
	for i in [HEAD, CHEST, PELVIS, EL_L, EL_R, HA_L, HA_R, KN_L, KN_R]:
		if _touch[i] == 1:
			why = "touch %d" % i
			break
	if why == "" and tilt > BAL_TILT_FAIL: why = "tilt %.2f" % tilt
	if why == "" and c.y - gc < BAL_COM_MIN: why = "low %.2f" % (c.y - gc)
	if why == "" and c.y - gc > BAL_COM_MAX: why = "lifted %.2f" % (c.y - gc)   # (stood on the bike under him)
	if why == "" and _bal_t > BAL_T: why = "time"
	if why != "":
		bal_on = false
		bal_failed = true
		if _BAL_PROBE: print("BAL gave up t=%.2f steps=%d (%s)" % [_bal_t, _bal_steps, why])
		return
	_bal_t += dt
	if _bal_v.length() < 0.35 and tilt < 0.3 and _bal_ph >= 1.0: _bal_still += dt
	else: _bal_still = 0.0
	if _bal_still > BAL_STILL:
		stood = true
		bal_on = false
		if _BAL_PROBE: print("BAL stood t=%.2f steps=%d" % [_bal_t, _bal_steps])
		return
	var fwd := Vector3(fr.z.x, 0.0, fr.z.z).normalized()
	var rgt := Vector3(fr.x.x, 0.0, fr.x.z).normalized()
	# the capture point: where the centre of mass would come to rest stepping there
	var hcom: float = maxf(0.3, c.y - gc)
	var cp := Vector3(c.x, 0.0, c.z) + _bal_v * sqrt(hcom / 9.81) * BAL_CP_K
	var feet := [FT_L, FT_R]
	var hips := [HIP_L, HIP_R]
	var knees := [KN_L, KN_R]
	var st_f: Vector3 = p[feet[_bal_stance]]
	var sw := 1 - _bal_stance
	if _BAL_PROBE and _bal_t < 0.03: print("BALLIM ", Array(_rb.LimitEach()).map(func(x): return snappedf(x, 0.01)))
	if _BAL_PROBE and _bal_t < 0.25:
		print("BALSTEP t=%.3f tilt=%.2f up=%s com_h=%.2f feet_touch=%d/%d" % [_bal_t, tilt, str(up.snapped(Vector3.ONE * 0.01)), c.y - gc, _touch[FT_L], _touch[FT_R]])
	if not _bal_down:
		# FEET DOWN: off the pedals both legs reach for the ground, the lower foot under the hips, the other toward the
		# capture point; the trunk held up by the spine. The first foot to touch takes the weight.
		if _touch[FT_L] == 1 or _touch[FT_R] == 1:
			_bal_down = true
			_bal_stance = 0 if _touch[FT_L] == 1 else 1
			_bal_ph = 0.0
		elif _bal_t > BAL_DROP_T:
			bal_on = false
			bal_failed = true
			if _BAL_PROBE: print("BAL gave up t=%.2f (no foot down)" % _bal_t)
			return
		else:
			for leg in 2:
				var hp0: Vector3 = p[hips[leg]]
				var sd0 := -1.0 if leg == 0 else 1.0
				var goal: Vector3 = (cp if leg != _bal_stance else Vector3(hp0.x, 0.0, hp0.z)) + rgt * sd0 * 0.08
				goal.y = terrain.height(goal.x, goal.z)
				var kg0: Vector3 = hp0 + ((goal - hp0).normalized() + fwd * 0.15).normalized() * 0.44
				_rb_dir[4 + leg] = (kg0 - hp0).normalized()
				_rb_k[4 + leg] = BAL_K_SWING
				_rb_dir[8 + leg] = (goal - kg0).normalized()
				_rb_k[8 + leg] = BAL_K_SWING
			_rb_dir[0] = Vector3.UP
			_rb_k[0] = BAL_K_SPINE
			_rb_dir[1] = Vector3.UP
			_rb_k[1] = 10.0
			return
	if _bal_ph >= 1.0:   # a new step when the capture point has left the feet
		var other: Vector3 = p[feet[sw]]
		var off := Vector2(cp.x - st_f.x, cp.z - st_f.z)
		var mid := Vector2((st_f.x + other.x) * 0.5 - cp.x, (st_f.z + other.z) * 0.5 - cp.z)
		if off.length() > 0.16 and mid.length() > 0.12: _bal_ph = 0.0
		# nearly stopped with the feet far apart: a small step to bring them together (standing, not a split)
		elif _bal_v.length() < 0.6 and Vector2(other.x - st_f.x, other.z - st_f.z).length() > 0.42: _bal_ph = 0.0
	if _bal_ph < 1.0:
		_bal_ph = minf(1.0, _bal_ph + dt / BAL_SWING_T)
		if _bal_ph > 0.55 and _touch[feet[sw]] == 1: _bal_ph = 1.0
		if _bal_ph >= 1.0:   # landed: the swing foot takes the weight
			_bal_steps += 1
			_bal_stance = sw
			sw = 1 - _bal_stance
	# torso uprighting (PD): the turn that brings the spine to vertical, minus its turning speed
	var w_up := _bal_up_prev.cross(up) / maxf(dt, 1e-4)
	_bal_up_prev = up
	# the trunk aims a little back against the speed (braking, the way people stop a stumble), not dead upright
	var des := (Vector3.UP - _bal_v * BAL_LEAN_BACK).normalized()
	var ang := acos(clampf(up.dot(des), -1.0, 1.0))
	var corr := up.cross(des) * (ang / maxf(sin(ang), 1e-3)) - w_up * BAL_KD
	var both := _bal_ph >= 1.0
	for leg in 2:
		var hp: Vector3 = p[hips[leg]]
		var kn: Vector3 = p[knees[leg]]
		var th_axis := (kn - hp).normalized()
		var hip_j: int = 4 + leg
		var knee_j: int = 8 + leg
		if leg == _bal_stance or both:
			# the stance leg: its hip motor aimed so the reaction turns the trunk upright (foot planted), knee straight
			var share := 0.5 if both else 1.0
			var cl := corr.length() * share
			var tgt := th_axis
			if cl > 1e-4: tgt = th_axis.rotated(corr.normalized(), -minf(cl, 0.8))
			_rb_dir[hip_j] = tgt
			_rb_k[hip_j] = BAL_K_STANCE
			# a soft knee (BAL_KNEE bent: the shin back from the thigh's line). Aimed straight (or past it) the stiff
			# spring snapped the leg out and launched him off the ground
			var fp := fwd - th_axis * fwd.dot(th_axis)
			fp = fp.normalized() if fp.length() > 1e-3 else fwd
			_rb_dir[knee_j] = (th_axis * cos(BAL_KNEE) - fp * sin(BAL_KNEE)).normalized()
			_rb_k[knee_j] = BAL_K_KNEE
		else:
			# the swing leg: the foot toward the capture point (its own side of it), the knee lifted mid-swing
			var side := -1.0 if leg == 0 else 1.0
			var tgt_f := cp + rgt * side * 0.1
			# nearly stopped: under the hips; never a stride longer than BAL_STRIDE from the hip
			var hxz := Vector3(hp.x, 0.0, hp.z)
			if _bal_v.length() < 0.6: tgt_f = hxz + rgt * side * 0.06 + fwd * 0.05
			var st := Vector3(tgt_f.x - hxz.x, 0.0, tgt_f.z - hxz.z)
			if st.length() > BAL_STRIDE: tgt_f = hxz + st.normalized() * BAL_STRIDE
			tgt_f.y = terrain.height(tgt_f.x, tgt_f.z) + 0.04
			var lift := sin(PI * _bal_ph)
			var to_f := tgt_f - hp
			var kg: Vector3 = hp + (to_f.normalized() + Vector3.UP * 0.45 * lift + fwd * 0.3 * lift).normalized() * 0.44
			_rb_dir[hip_j] = (kg - hp).normalized()
			_rb_k[hip_j] = BAL_K_SWING
			_rb_dir[knee_j] = (tgt_f + Vector3.UP * 0.1 * lift - kg).normalized()
			_rb_k[knee_j] = BAL_K_SWING
	# spine and head up, arms a little out (balance)
	_rb_dir[0] = Vector3.UP
	_rb_k[0] = BAL_K_SPINE
	_rb_dir[1] = Vector3.UP
	_rb_k[1] = 10.0
	for arm in 2:
		var sd := -1.0 if arm == 0 else 1.0
		_rb_dir[2 + arm] = (Vector3.DOWN + rgt * sd * 0.7 + fwd * 0.25).normalized()
		_rb_k[2 + arm] = 4.0
		_rb_dir[6 + arm] = (Vector3.DOWN * 0.6 + rgt * sd * 0.5 + fwd * 0.6).normalized()
		_rb_k[6 + arm] = 3.0
	if _BAL_PROBE and floori(_bal_t / 0.1) != floori((_bal_t - dt) / 0.1):
		print("BAL t=%.2f tilt=%.2f com_h=%.2f v=%.2f stance=%d ph=%.2f steps=%d cp_off=%.2f knee_deg=%.0f/%.0f feet=%d/%d" % [_bal_t, tilt, c.y - gc, _bal_v.length(), _bal_stance, _bal_ph, _bal_steps, Vector2(cp.x - st_f.x, cp.z - st_f.z).length(), rad_to_deg(((p[KN_L] as Vector3) - (p[HIP_L] as Vector3)).angle_to((p[FT_L] as Vector3) - (p[KN_L] as Vector3))), rad_to_deg(((p[KN_R] as Vector3) - (p[HIP_R] as Vector3)).angle_to((p[FT_R] as Vector3) - (p[KN_R] as Vector3))), _touch[FT_L], _touch[FT_R]])

## a push from outside on the points (the crashed bike: CrashBikeCs.CollideBody / HoldBody): the new points and their
## last positions (np, nq, the ragdoll's own convention q = p - v last_h). Point ragdoll: taken as they are; rigid
## bodies: each moved point becomes a push + a velocity change on its body.
func external_push(np: PackedVector3Array, nq: PackedVector3Array) -> void:
	var n := mini(np.size(), p.size())
	if _rb == null:
		for i in n:
			p[i] = np[i]; q[i] = nq[i]
		return
	var h := maxf(last_h, 1e-5)
	for i in n:
		var dp: Vector3 = np[i] - (p[i] as Vector3)
		var dv: Vector3 = ((np[i] - nq[i]) - ((p[i] as Vector3) - (q[i] as Vector3))) / h
		# at most RB_PUSH_DV a step: a hand held to the grip of a tumbling bike was matched to its speed and the whole
		# body yanked 10 m into the air
		if dv.length() > RB_PUSH_DV: dv = dv.normalized() * RB_PUSH_DV
		if dp.length_squared() < 1e-12 and dv.length_squared() < 1e-8: continue
		_rb.PushPoint(i, dp, dv)
		p[i] = np[i]; q[i] = nq[i]

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
	if _rb != null: return   # (rigid bodies: the legs / arms reach through the motors; no point push)
	# the righting twist: turn the spine toward world up (equal and opposite on chest / pelvis)
	var u: Vector3 = ((p[CHEST] as Vector3) - pe).normalized()
	var want := Vector3.UP - u * u.dot(Vector3.UP)   # sideways push on the chest that turns u toward up
	var d := want * RIGHT_ACC * agency * h * h
	p[CHEST] = (p[CHEST] as Vector3) + d
	p[HEAD] = (p[HEAD] as Vector3) + d * 0.6
	p[PELVIS] = pe - d * 1.6   # balanced: it turns the body, never lifts or pushes it

## which behaviour (see BEHAVIOURS): sets w_tuck / w_brace / w_pain, ko, and turns the reach-for-the-ground (agency) down
## while tucked
func _behave(h: float) -> void:
	var c := _com()
	var cq := Vector3.ZERO
	for i in RAD.size(): cq += q[i]
	cq /= RAD.size()
	var v := (c - cq) / maxf(h, 1e-5)
	var hs := Vector2(v.x, v.z).length()
	var u: Vector3 = ((p[CHEST] as Vector3) - (p[PELVIS] as Vector3)).normalized()
	if _u_prev != Vector3.ZERO and u.is_finite():
		var a := acos(clampf(u.dot(_u_prev), -1.0, 1.0)) / maxf(h, 1e-5)
		_spin = lerpf(_spin, a, minf(1.0, h * 12.0))
	_u_prev = u
	var pe: Vector3 = p[PELVIS]
	# in the air = touching nothing (ground, rocks, the bike) for a moment; anything else counts as on the ground (lying
	# propped up on the bike or a slope used to read as flying: he windmilled lying on his back)
	var any_touch := contact_ext < 0.1
	if not any_touch:
		for i in RAD.size():
			if _touch[i] == 1: any_touch = true; break
	_air_t = 0.0 if any_touch else _air_t + h
	var gnd: bool = _air_t < 0.1
	# knocked out: the head's own speed into the ground as it first touches (not the muscles pressing it there)
	var hv: Vector3 = ((p[HEAD] as Vector3) - (q[HEAD] as Vector3)) / maxf(h, 1e-5)
	if not ko and _touch[HEAD] == 1 and not _head_was and -_head_vy > KO_HIT:
		ko = true
		if _BEH_PROBE: print("RAGBEH knocked out t=%.2f head_hit=%.1f" % [t_fall, -_head_vy])
	_head_was = _touch[HEAD] == 1
	_head_vy = hv.y
	# the hardest hit so far (the part he'll hold while lying in pain)
	for i in RAD.size():
		if _touch[i] == 1 and i != HEAD:
			var hit: float = _jn[i] / maxf(h, 1e-5)
			if hit > HURT_MIN and hit > _hurt_v: _hurt_v = hit; hurt = i
	var t_tuck := 0.0; var t_brace := 0.0; var t_pain := 0.0; var t_mill := 0.0; var t_spread := 0.0
	_mill_ph += h * TAU * MILL_HZ
	if not ko:
		# tumbling = the spine turning while the body is really travelling (curling up in place turns it too)
		var tumbling := _spin > TUCK_SPIN and v.length() > 2.0
		if gnd:
			if (hs > 3.0 or tumbling) and _tuck_gnd < TUCK_MAX: t_tuck = 1.0
			elif hs > 1.2 or tumbling: t_spread = 1.0   # still going after the roll: spread out to stop
			if w_tuck > 0.5: _tuck_gnd += h
			# (once the pain has begun it runs its course: the rocking moves him; only sliding off again stops it)
			var calm: bool = v.length() < 0.5 or (_rest_t > PAIN_FROM and v.length() < 2.0)
			_rest_t = _rest_t + h if calm else maxf(0.0, _rest_t - h * 2.0)
			var pain_len: float = PAIN_T if _rb == null else maxf(PAIN_T, ROCK_T + 1.8)
			if _rest_t > PAIN_FROM and not _OFF.has("pain"): t_pain = clampf(1.0 - (_rest_t - PAIN_FROM - pain_len * 0.7) / (pain_len * 0.3), 0.0, 1.0)
		else:
			# in the air: tucking would only spin him faster (momentum is kept); he tucks just before he hits, to roll
			var ch: Vector3 = p[CHEST]
			var up_c: float = ch.y - terrain.height(ch.x, ch.z)
			var t_hit: float = up_c / maxf(-v.y, 0.5)
			if (hs > TUCK_V or tumbling) and t_hit < 0.35: t_tuck = 1.0
			if t_tuck < 0.5 and v.y < -0.5 and t_hit < BRACE_T: t_brace = 1.0
			if t_tuck < 0.5 and t_brace < 0.5 and _air_t > 0.15 and t_hit > 0.35 and v.length() > 2.5: t_mill = 1.0
	w_tuck = move_toward(w_tuck, t_tuck, h * (6.0 if t_tuck > w_tuck else 2.5))
	w_brace = move_toward(w_brace, t_brace, h * 8.0)
	w_pain = move_toward(w_pain, t_pain, h * 2.0)
	w_mill = move_toward(w_mill, t_mill, h * (5.0 if t_mill > w_mill else 6.0))
	w_spread = move_toward(w_spread, t_spread, h * (4.0 if t_spread > w_spread else 1.5))
	agency *= 1.0 - w_tuck
	if bal_on:   # balancing on his feet: none of the falling / lying behaviours
		w_tuck = 0.0; w_brace = 0.0; w_pain = 0.0; w_mill = 0.0; w_spread = 0.0; _rest_t = 0.0; agency = 0.0
	if _BEH_PROBE and floori(t_fall / 0.25) != _beh_said:
		_beh_said = floori(t_fall / 0.25)
		print("RAGBEH flail_air=%.1f flail_ground=%.1f bend_rate=%.1f t=%.2f mill=%.2f spread=%.2f hurt=%d tuck=%.2f brace=%.2f pain=%.2f land=%.2f ko=%s v=%.1f spin=%.1f ground=%s" % [_fl_a / maxf(_fl_at, 1e-3), _fl_g / maxf(_fl_gt, 1e-3), _bd_a / maxf(_bd_t, 1e-3), t_fall, w_mill, w_spread, hurt, w_tuck, w_brace, w_pain, agency, ko, hs, _spin, gnd])

## tests (BMX_RAGDUMP=file.csv, with BMX_RAGBEH): every substep of the first crash: t, touches, every point (world)
var _RAGDUMP := Env.raw("BMX_RAGDUMP")
var _dumpf: FileAccess = null
var _dump_done := false
func _dump_row() -> void:
	if _dump_done: return
	if _dumpf == null:
		_dumpf = FileAccess.open(_RAGDUMP, FileAccess.WRITE)
		if _dumpf == null: _dump_done = true; return
	var row := PackedStringArray(["%.5f" % t_fall, str(w_tuck).pad_decimals(2), str(w_pain).pad_decimals(2), str(int(ko))])
	for i in RAD.size():
		var v: Vector3 = p[i]
		row.append("%.4f" % v.x); row.append("%.4f" % v.y); row.append("%.4f" % v.z); row.append(str(_touch[i]))
	_dumpf.store_line(",".join(row))
	if t_fall > 7.9: _dumpf.close(); _dump_done = true

## tests (BMX_RAGBEH): flail = how fast the limbs turn against the torso frame, bend = against the spine (rad/s, mean of 8)
func _flail_probe(h: float) -> void:
	var pe: Vector3 = p[PELVIS]
	var gnd: bool = _touch[PELVIS] == 1 or _touch[CHEST] == 1 or _touch[HEAD] == 1 or pe.y - terrain.height(pe.x, pe.z) < 0.45
	var bf := _frame()
	var cur := []
	for k in NEUTRAL.size():
		if k == 0: continue
		var d: Vector3 = ((p[NEUTRAL[k][0]] as Vector3) - (p[NEUTRAL[k][1]] as Vector3)).normalized()
		cur.append(bf.inverse() * d)
	# frame-free check: the angle between each limb and the spine (a jittery torso frame can't fake it)
	var sp_u: Vector3 = ((p[CHEST] as Vector3) - (p[PELVIS] as Vector3)).normalized()
	var bend := []
	for k in NEUTRAL.size():
		if k == 0: continue
		bend.append(acos(clampf(((p[NEUTRAL[k][0]] as Vector3) - (p[NEUTRAL[k][1]] as Vector3)).normalized().dot(sp_u), -1.0, 1.0)))
	if _bd_prev.size() == bend.size():
		var bsum := 0.0
		for j in bend.size(): bsum += absf(float(bend[j]) - float(_bd_prev[j]))
		_bd_a += bsum / bend.size(); _bd_t += h
	_bd_prev = bend
	if _fl_prev.size() == cur.size():
		var a := 0.0
		for j in cur.size(): a += acos(clampf((cur[j] as Vector3).dot(_fl_prev[j]), -1.0, 1.0))
		a /= cur.size() * maxf(h, 1e-5)
		if gnd: _fl_g += a * h; _fl_gt += h
		else: _fl_a += a * h; _fl_at += h
	_fl_prev = cur

## knees bend the way knees do (2026-11-27, user: "an impossible pose", both knees folded in across the body; "jerks"):
## a bent knee's bend axis (hip -> knee -> foot) stays within KNEE_TURN of the body's left-right axis, i.e. the hip's
## rotation is limited and a knee never bends backwards. The knee is turned about the hip-foot line by KNEE_K of the
## excess a substep (lengths unchanged), balanced on hip and foot. The first version pushed the joint across its line
## plus a fixed 1 cm every substep, also for elbows: near-straight limbs were shoved to and fro (~700 m/s2 jitter lying
## still, the old ragdoll ~60)
const KNEE_TURN := 0.8
const KNEE_K := 0.1   # share of the turn back into the range per substep (a soft limit)
var _KNEE_WAY := Env.raw("BMX_KNEE_WAY") != ""   # tests
var _knee_way := [0.0, 0.0, 0.0, 0.0]
const ELBOW_TURN := 1.3   # the way each knee is being turned back (+1 / -1, 0 = within range)
func _hinges() -> void:
	var b := _frame()
	if not b.x.is_finite() or b.x.length_squared() < 0.5: return
	# [root, joint, end, max turn of the bend axis from the body's own, sign]: knees bend with the axis up x forward (the
	# body's left), elbows the other way (a hanging arm folds the hand forward: down x forward = the body's right); elbows
	# get more room (the upper arm turns a lot in its socket)
	for leg in [[HIP_R, KN_R, FT_R, KNEE_TURN, 1.0], [HIP_L, KN_L, FT_L, KNEE_TURN, 1.0], [SH_R, EL_R, HA_R, ELBOW_TURN, -1.0], [SH_L, EL_L, HA_L, ELBOW_TURN, -1.0]]:
		var a: int = leg[0]; var m: int = leg[1]; var e: int = leg[2]
		var lim: float = leg[3]
		if free_pt[m] == 1 or free_pt[e] == 1: continue
		if not broken.is_empty() and broken.has(m): continue   # broken: folds any way
		var A: Vector3 = p[a]; var M: Vector3 = p[m]; var E: Vector3 = p[e]
		var ae := E - A
		var al := ae.length()
		if al < 1e-4: continue
		var ax := ae / al
		var u := M - A; var w := E - M
		var n := u.cross(w)
		if n.length() < 0.25 * u.length() * w.length(): continue   # nearly straight: no clear bend axis
		n = (n - ax * n.dot(ax)).normalized()
		# a knee bending forward has its bend axis (thigh x shin) along up x forward of the body: the body's left in
		# Godot's right-handed axes (the first version used +right: it turned every knee toward bending backwards, the
		# muscles pulled back, the leg shook and folded into impossible poses)
		var want: Vector3 = b.y.cross(b.z).normalized() * float(leg[4])
		var r: Vector3 = want - ax * want.dot(ax)
		if r.length() < 0.6: continue   # (leg along the body's left-right axis: no clear side round it)
		r = r.normalized()
		var ang := atan2(ax.dot(n.cross(r)), n.dot(r))   # turn about the hip-foot line that brings the bend axis to r
		var li: int = [HIP_R, HIP_L, SH_R, SH_L].find(a)
		# bent nearly backwards the shortest way flips between left and right every substep (the knee shook in place):
		# from far out it keeps the way it started turning
		if _KNEE_WAY and absf(ang) > 2.4 and _knee_way[li] != 0.0 and signf(ang) != _knee_way[li]:
			ang = ang + TAU * _knee_way[li]
		var over := absf(ang) - lim
		if over <= 0.0:
			_knee_way[li] = 0.0
			continue
		_knee_way[li] = signf(ang)
		var c: Vector3 = A + ax * (M - A).dot(ax)
		var nm: Vector3 = c + (M - c).rotated(ax, signf(ang) * over * KNEE_K)
		var d := nm - M
		# never into the ground (it pushes back: jitter), balanced on the foot only (moving the hips turned the very axis
		# this measures against)
		if (_touch[m] == 1 and d.y < 0.0) or (_touch[e] == 1 and d.y > 0.0): d.y = 0.0
		# a soft spring (like the muscle tone), not a hard correction: hard ones, with or without speed, fought the ground
		# and the bones and shook the leg (up to 8000 m/s2 lying still)
		p[m] = M + d * 0.5
		p[e] = E - d * 0.5

## shoulders / hips / neck kept within their range (see CONES)
func _cones() -> void:
	var b := _frame()
	if not b.x.is_finite() or b.x.length_squared() < 0.5: return
	for k in CONES:
		var c: int = NEUTRAL[k][0]; var par: int = NEUTRAL[k][1]
		if free_pt[c] == 1: continue
		var cur: Vector3 = (p[c] as Vector3) - (p[par] as Vector3)
		var L := cur.length()
		if L < 1e-4: continue
		var d := cur / L
		var centre: Vector3 = (b * (NEUTRAL[k][2] as Vector3)).normalized()
		var ang := acos(clampf(d.dot(centre), -1.0, 1.0))
		var mx: float = CONES[k]
		if broken.has(c) or broken.has(LIMB_NEXT.get(c, -1)): mx *= 1.6   # a broken limb: its range is gone too
		if ang <= mx: continue
		var axis := d.cross(centre)
		if axis.length_squared() < 1e-8: axis = b.x
		var nd := d.rotated(axis.normalized(), ang - mx)
		var corr := ((p[par] as Vector3) + nd * L - (p[c] as Vector3)) * CONE_K
		p[c] = (p[c] as Vector3) + corr * 0.5
		p[par] = (p[par] as Vector3) - corr * 0.5

## legs never cross into an X (user, 2026-11-27): along the body's own left-right axis the right knee / foot stay at
## least NO_CROSS m to the right of the left ones (pushed apart equal and opposite; lying on the side that axis is
## vertical, so stacked legs are fine)
const NO_CROSS := {KN_R: [KN_L, 0.1], FT_R: [FT_L, 0.08]}
func _no_cross() -> void:
	var b := _frame()
	if not b.x.is_finite() or b.x.length_squared() < 0.5: return
	var rx := b.x.normalized()
	for r in NO_CROSS:
		var l: int = NO_CROSS[r][0]
		if free_pt[r] == 1 or free_pt[l] == 1: continue
		if broken.has(KN_L) or broken.has(KN_R): continue   # a broken leg flops anywhere (user: "unless we broke a joint")
		var gap: float = ((p[r] as Vector3) - (p[l] as Vector3)).dot(rx)
		var want: float = NO_CROSS[r][1]
		if gap >= want: continue
		var d := rx * ((want - gap) * 0.5)
		p[r] = (p[r] as Vector3) + d
		p[l] = (p[l] as Vector3) - d

## windmill pose for NEUTRAL index k (torso frame, see WINDMILL): arms circle in opposite phase, legs cycle
func _mill_dir(k: int) -> Vector3:
	var left := k >= 5
	var kr: int = k - 4 if left else k
	var ph: float = _mill_ph + (PI if left else 0.0)
	var d := Vector3.ZERO
	match kr:
		0: return NEUTRAL[0][2]
		1: d = Vector3(0.45, cos(ph), sin(ph))
		2: d = Vector3(0.25, cos(ph + 0.7), sin(ph + 0.7))
		3: d = Vector3(0.1, -0.85 * cos(ph * 0.8), 0.3 + 0.6 * sin(ph * 0.8))
		4: d = Vector3(0.0, -0.9, -0.25 - 0.45 * maxf(0.0, sin(ph * 0.8)))
	if left: d.x = -d.x
	return d.normalized()

## hands / elbows / knees / feet out of the trunk and the head (equal and opposite)
func _self_collide() -> void:
	var A: Vector3 = p[PELVIS]; var B: Vector3 = p[CHEST]
	var ab := B - A
	var l2 := ab.length_squared()
	if l2 < 1e-6: return
	for i in SELF_LIMBS:
		if free_pt[i] == 1: continue
		var P: Vector3 = p[i]
		var t := clampf((P - A).dot(ab) / l2, 0.0, 1.0)
		var C := A + ab * t
		var d := P - C
		var dl := d.length()
		var want: float = TRUNK_R + float(rad[i])
		if dl < want and dl > 1e-5:
			var push := d / dl * (want - dl)
			p[i] = P + push * 0.5
			p[PELVIS] = (p[PELVIS] as Vector3) - push * 0.5 * (1.0 - t)
			p[CHEST] = (p[CHEST] as Vector3) - push * 0.5 * t
			P = p[i]
		var hd := P - (p[HEAD] as Vector3)
		var hl := hd.length()
		var hw: float = float(rad[HEAD]) * 0.7 + float(rad[i])
		if hl < hw and hl > 1e-5:
			var push2 := hd / hl * (hw - hl)
			p[i] = P + push2 * 0.5
			p[HEAD] = (p[HEAD] as Vector3) - push2 * 0.5

## the chest twisting against the pelvis (see SQUIRM): two slow wandering sines, more while lying on the ground
func _squirm(h: float) -> void:
	if t_fall > SQUIRM_T * 1.5 and w_pain < 0.01: return
	var b := _frame()
	if not b.x.is_finite(): return
	var on_ground := _touch[CHEST] == 1 or _touch[PELVIS] == 1
	var amp := SQUIRM * maxf(exp(-t_fall / SQUIRM_T), 0.5 * w_pain) * (1.0 if on_ground else 0.35) * tone_k
	if ko: return
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
func _neutral_pull(kt := 1.0, rb_mode := false) -> void:
	var b := _frame()
	if not b.x.is_finite() or b.x.length_squared() < 0.5: return
	if rb_mode:
		_rb_k.fill(0.0)
		# the spine: straight on the pelvis, hunched forward tucking / hurt (chest's up toward the torso's forward)
		var hunch := 0.55 * w_tuck + 0.3 * w_pain
		_rb_dir[0] = (b.y * cos(hunch) + b.z * sin(hunch)).normalized()
		_rb_k[0] = (1.0 + (ALIVE_K - 1.0) * exp(-t_fall / ALIVE_T)) * (KO_TONE if ko else 1.0) * tone_k * (1.0 + 2.0 * w_tuck)
	var alive := exp(-t_fall / ALIVE_T)              # 1 at the start of the fall -> 0
	var firm := 1.0 + (ALIVE_K - 1.0) * maxf(alive, agency)
	if ko:
		alive = 0.0; firm = KO_TONE
	# a behaviour drives the muscles harder toward its pose (see BEHAVIOURS)
	firm *= 1.0 + (TUCK_DRIVE - 1.0) * w_tuck + (BRACE_DRIVE - 1.0) * w_brace + (PAIN_DRIVE - 1.0) * w_pain + (MILL_DRIVE - 1.0) * (0.0 if _NOMILL else w_mill) + (SPREAD_DRIVE - 1.0) * w_spread
	# rocking in pain (see ROCK_*): a slowing swing while the pain lasts, none knocked out / in the point ragdoll
	var rock := 0.0
	var rock_w := 0.0
	if rb_mode and w_pain > 0.01 and not ko and not _OFF.has("rock"):
		var pt: float = maxf(0.0, _rest_t - PAIN_FROM)
		rock_w = w_pain * clampf(1.0 - (pt - ROCK_T) / 1.5, 0.0, 1.0)   # rocks ROCK_T s, then settles over 1.5 s
		_rock_ph += _rock_dt * TAU * ROCK_HZ * lerpf(1.0, 0.55, clampf(pt / (ROCK_T + 1.5), 0.0, 1.0))   # slowing down
		rock = sin(_rock_ph) * rock_w
	# the hand that holds the hurt part: the other side's (head / trunk: the right)
	var hold_arm := -1
	var hold_pt := Vector3.ZERO
	if w_pain > 0.01 and hurt >= 0 and not ko and rock_w < 0.3:
		var right_side := hurt in [SH_R, EL_R, HA_R, HIP_R, KN_R, FT_R]
		hold_arm = 5 if right_side else 1   # NEUTRAL index of that upper arm (left / right)
		hold_pt = p[hurt]
		if hurt == HA_L or hurt == HA_R: hold_pt = ((p[hurt] as Vector3) + (p[EL_L if hurt == HA_L else EL_R] as Vector3)) * 0.5
	var dead := DEAD * (1.0 - 0.7 * maxf(alive, maxf(w_tuck, maxf(w_brace, w_pain))))
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
		if not _OLD_BEH and w_mill > 0.01 and not _NOMILL:
			dir = dir.lerp(_mill_dir(k), w_mill)
		if not _OLD_BEH and w_spread > 0.01:
			var kr2: int = k if k < 5 else k - 4
			var sd: Vector3 = SPREAD[kr2]
			if k >= 5: sd.x = -sd.x
			dir = dir.lerp(sd, w_spread)
		if not _OLD_BEH and (w_tuck > 0.01 or w_pain > 0.01):
			var kr: int = k if k < 5 else k - 4
			var bd: Vector3 = (TUCK[kr] as Vector3).lerp(PAIN[kr], w_pain / maxf(w_tuck + w_pain, 1e-4))
			if k >= 5: bd.x = -bd.x
			dir = dir.lerp(bd, clampf(w_tuck + w_pain, 0.0, 1.0))
		if rock != 0.0:
			# ROCKING IN PAIN: both curled-up knees swing to the same side (torso frame x is the same side for both legs),
			# the shins follow; the arms hug the knees. The legs' weight tips the body onto that side and back
			if k == 3 or k == 7: dir = (dir + Vector3(rock * 1.6, 0.2, 0.0)).normalized()
			elif k == 4 or k == 8: dir = (dir + Vector3(rock * 0.9, 0.0, 0.0)).normalized()
			elif k == 1 or k == 5: dir = dir.lerp(Vector3(0.15 * (1.0 if k == 1 else -1.0), -0.3, 0.95), rock_w).normalized()
			elif k == 2 or k == 6: dir = dir.lerp(Vector3(-0.7 * (1.0 if k == 2 else -1.0), -0.2, 0.7), rock_w).normalized()
			elif k == 0: dir = (dir + Vector3(-rock * 0.4, 0.0, 0.0)).normalized()   # the head turns away from the knees
		var wdir: Vector3 = (b * dir).normalized()
		if agency > 0.01:
			# trying to land on the feet / catch himself: the target turns toward the ground (world space)
			if k in LEGS: wdir = wdir.lerp(_down, agency * LEG_REACH).normalized()
			elif k in ARMS: wdir = wdir.lerp(_brace, agency * ARM_BRACE * (1.0 - startle)).normalized()
		if hold_arm >= 0 and (k == hold_arm or k == hold_arm + 1):   # a hand to where it hurts
			var tw: Vector3 = (hold_pt - pc)
			if tw.length_squared() > 1e-6: wdir = wdir.lerp(tw.normalized(), w_pain * 0.9).normalized()
		if w_brace > 0.01 and k in ARMS:   # about to hit: hands out to the ground, elbows soft
			wdir = wdir.lerp(_brace, w_brace * (0.85 if (k == 1 or k == 5) else 0.6)).normalized()
		if rb_mode:   # the joint motor that moves this part: aim + strength (the tone x the behaviours' drive)
			var ji: int = RB_JOINT[c]
			_rb_dir[ji] = wdir
			_rb_k[ji] = firm * tone_k * (1.0 + ROCK_DRIVE * rock_w if (k == 3 or k == 7 or k == 4 or k == 8) else 1.0)
			continue
		var target: Vector3 = pc + wdir * L
		var cp: Vector3 = p[c]
		var d := target - cp
		var dl := d.length()
		var off := dl / maxf(L, 1e-3)
		nb_off += off
		if not _OLD_BEH:
			# damping first, in or out of the natural range: the limb swings with the trunk, not round it
			var vr0: Vector3 = (cp - (q[c] as Vector3)) - (pc - (q[par] as Vector3))
			var dv0 := vr0 * minf(0.5, (TONE_DAMP if (ko or _OFF.has("damp")) else LIMB_DAMP) * kt)
			q[c] = (q[c] as Vector3) + dv0 * 0.5
			q[par] = (q[par] as Vector3) - dv0 * 0.5
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
		if not _OLD_BEH: continue   # (done above)
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
