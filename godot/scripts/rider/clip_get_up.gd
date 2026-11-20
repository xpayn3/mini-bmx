class_name ClipGetUp
extends RefCounted

## Getting up after a light crash with animation clips (Mixamo downloads): the clip in GETUP_DIR whose first frame
## lies most like the ragdoll (face down / on the back / on a side: `_lie` compares the body's front and right)
## plays where the body lies, turned so its head end points the same way, every point over the ground under it
## (slopes ok). It starts from the ragdoll's own pose (blended over BLEND). Standing, the rider then plays the
## dizzy clip (DIZZY_DIR) on a loop until `release()` (the player presses hop again) -> Game puts them on the bike.
## Same interface as GetUpAnim (step / last_world), which stays the fallback when there are no clips.

const GETUP_DIR := "res://assets/anim/getup/"
const DIZZY_DIR := "res://assets/anim/dizzy/"
const BLEND := 0.45     # s: ragdoll pose -> the clip's first frame
const FADE := 0.5       # s: end of the get-up -> dizzy
const CUT_END := 0.15   # s left off the get-up clip's end (Mixamo clips often hold their last frame)
const SPEED := 1.4      # get-up clips play this much faster (Mixamo's run 5-11 s: too long to wait in a ride)
## after the dizzy loop (hop pressed) the rider limps to the fallen bike with the clip in WALK_DIR (turning towards it,
## the stride following the speed) and Game puts them on it when they arrive
const WALK_DIR := "res://assets/anim/walk/"
const ARRIVE := 0.45        # m from the bike's origin: close enough to climb on
const WALK_MAX := 25.0      # m: further than this (a long slide) they just get on
const WALK_TIMEOUT := 14.0  # s
const WALK_TURN := 3.0      # rad/s the body turns towards the bike

static func available() -> bool:
	return not RiderAnim.clip_files(GETUP_DIR).is_empty()

## start loading the clips on a worker thread (at ride start), so the first crash doesn't wait on the import
static func warm() -> void:
	for p in RiderAnim.clip_files(GETUP_DIR) + RiderAnim.clip_files(DIZZY_DIR) + RiderAnim.clip_files(WALK_DIR):
		ResourceLoader.load_threaded_request(p)

var rider: Rider
var terrain
var up: RiderAnim
var dz: RiderAnim = null
var dzi := 0               # which dizzy clip (random each crash)
var wk: RiderAnim = null
var target := Vector3.ZERO # the bike (world): where the walk ends
var has_target := false
var skipped := false
var _wpos := Vector2.ZERO  # the walking pelvis, world x / z
var _wyaw := 0.0           # its heading (atan2(-z, x), like _align's)
var _whc := 0.0            # the walk clip's own heading
var _wv := 1.0             # m/s the clip's stride covers
var _wt := 0.0             # the walk clip's time
var clip := 0
var t := 0.0
var phase := "up"          # up -> dizzy -> walk -> done
var released := false
var last_world: Array = []
var _rag: Array = []       # the ragdoll's points (world) at the start
var _xf := Transform3D()   # get-up clip frame -> world (heights then over the ground)
var _dz_xf := Transform3D()
var _fade_from := {}
var _fade_t := 1.0
var name := ""


func _init(r: Rider, terr, P: Array) -> void:
	rider = r
	terrain = terr
	_rag = P.duplicate()
	up = RiderAnim.new(r, GETUP_DIR)
	if not up.ok(): return
	if not RiderAnim.clip_files(DIZZY_DIR).is_empty():
		dz = RiderAnim.new(r, DIZZY_DIR)
		if not dz.ok(): dz = null
	if dz != null:
		dzi = randi() % dz.clips.size()
		var fd := Env.s("BMX_DIZZY_CLIP")   # tests: this dizzy clip (part of its name)
		if fd != "":
			for i in dz.clips.size():
				if str(dz.clips[i].name).contains(fd): dzi = i
	if not RiderAnim.clip_files(WALK_DIR).is_empty():
		wk = RiderAnim.new(r, WALK_DIR)
		if not wk.ok(): wk = null
	# the clip that starts lying most like the body does (several close ones: any of them)
	var lie_r := _lie(P)
	var scores := []
	var best := INF
	for i in up.clips.size():
		var p0: Array = up.pose_at(i, 0.0, true).P
		var s := (_lie(p0) - lie_r).length()
		scores.append(s); best = minf(best, s)
	var pick := []
	for i in scores.size():
		if scores[i] <= best + 0.25: pick.append(i)
	clip = pick[randi() % pick.size()]
	var forced := Env.s("BMX_GETUP_CLIP")   # tests: this clip (part of its name)
	if forced != "":
		for i in up.clips.size():
			if str(up.clips[i].name).contains(forced): clip = i
	name = str(up.clips[clip].name)
	_xf = _align(up.pose_at(clip, 0.0, true).P, P)
	if Env.s("BMX_GETUP_PROBE") != "":
		print("GETUP clip=%s lie=%s scores=%s" % [name, str(lie_r.snapped(Vector2.ONE * 0.01)), str(scores.map(func(s): return snappedf(s, 0.01)))])


func ok() -> bool:
	return up != null and up.ok()


## how a body lies: (front.y, right.y) - face down (-1, 0), on the back (1, 0), on its right side (0, -1)...
static func _lie(P: Array) -> Vector2:
	var upv: Vector3 = (P[1] as Vector3) - (P[2] as Vector3)
	var rt: Vector3 = (P[12] as Vector3) - (P[9] as Vector3)
	var b := Rider._basis_from(upv, rt)
	return Vector2(b.x.normalized().y, b.z.normalized().y)


## the turn about Y + shift that puts pose A's pelvis on B's and A's head end (or front, upright) the way B's points
static func _align(A: Array, B: Array) -> Transform3D:
	var dir := func(P: Array) -> Vector3:
		var d: Vector3 = (P[1] as Vector3) - (P[2] as Vector3)
		d.y = 0.0
		if d.length_squared() < 0.01:   # sitting / standing up straight: the way it faces
			var b := Rider._basis_from((P[1] as Vector3) - (P[2] as Vector3), (P[12] as Vector3) - (P[9] as Vector3))
			d = b.x; d.y = 0.0
		return d.normalized() if d.length_squared() > 1e-8 else Vector3(1, 0, 0)
	var da: Vector3 = dir.call(A)
	var db: Vector3 = dir.call(B)
	var yaw := atan2(-db.z, db.x) - atan2(-da.z, da.x)
	var bas := Basis(Vector3.UP, yaw)
	var pa: Vector3 = A[2]; var pb: Vector3 = B[2]
	return Transform3D(bas, Vector3(pb.x, 0, pb.z) - bas * Vector3(pa.x, 0, pa.z))


## a clip pose -> world: turned / moved by xf, every point at its clip height over the ground under it
func _place(pose: Dictionary, xf: Transform3D) -> Dictionary:
	var P := []
	for v in pose.P:
		var w: Vector3 = xf * Vector3((v as Vector3).x, 0.0, (v as Vector3).z)
		w.y = _ground(w) + (v as Vector3).y
		P.append(w)
	var o := {}
	for k in pose.o:
		o[k] = xf.basis * (pose.o[k] as Basis) if pose.o[k] is Basis else pose.o[k]
	return {P = P, o = o}

func _ground(w: Vector3) -> float:
	return terrain.top_height(w.x, w.z) if terrain else 0.0


## the player pressed hop while standing dizzy: get back on the bike
func release() -> void:
	released = true


func dizzy() -> bool:
	return phase == "dizzy"


func walking() -> bool:
	return phase == "walk"


## a press while limping to the bike: get on now
func skip() -> void:
	skipped = true


## the way a body faces, in _align's heading convention (atan2(-z, x))
static func _heading(P: Array) -> float:
	var d: Vector3 = Rider._basis_from((P[1] as Vector3) - (P[2] as Vector3), (P[12] as Vector3) - (P[9] as Vector3)).x
	return atan2(-d.z, d.x)


## the dizzy loop ended and the bike is some way off: start the walk (false = just get on)
func _start_walk(pose: Dictionary) -> bool:
	if wk == null or not has_target: return false
	var p: Vector3 = pose.P[2]
	var d := Vector2(target.x - p.x, target.z - p.z).length()
	if d < ARRIVE + 0.35 or d > WALK_MAX: return false
	phase = "walk"; t = 0.0; _wt = 0.0
	_wpos = Vector2(p.x, p.z)
	_wyaw = _heading(pose.P)
	var c0: Dictionary = wk.pose_at(0, 0.0, false)
	_whc = _heading(c0.P)
	# the stride's speed from the clip's own travel (in-place clips: a slow walk)
	var ln: float = float(wk.clips[0].len)
	var p1: Vector3 = wk.pose_at(0, maxf(ln - 0.03, 0.1), false).P[2]
	var p0: Vector3 = c0.P[2]
	var v := Vector2(p1.x - p0.x, p1.z - p0.z).length() / maxf(ln - 0.03, 0.1)
	_wv = clampf(v, 0.5, 2.0) if v > 0.3 else 1.0
	_fade_from = pose; _fade_t = 0.0
	if Env.s("BMX_GETUP_PROBE") != "": print("WALK start dist=%.2f stride=%.2f m/s" % [d, _wv])
	return true


## one step of the walk: the clip played in place, the body moved + turned towards the bike
func _walk_pose(dt: float) -> Dictionary:
	var to := Vector2(target.x, target.z) - _wpos
	var dist := to.length()
	_wyaw += clampf(angle_difference(_wyaw, atan2(-to.y, to.x)), -WALK_TURN * dt, WALK_TURN * dt)
	var v := _wv * smoothstep(0.0, 1.0, t / 0.6) * clampf(dist, 0.35, 1.0)   # eases in, slows into the bike
	if dist > 1e-4: _wpos += to / dist * minf(v * dt, dist)
	_wt += dt * v / _wv
	var raw: Dictionary = wk.pose_at(0, _wt, false)
	var pel: Vector3 = raw.P[2]
	var bas := Basis(Vector3.UP, _wyaw - _whc)
	return _place(raw, Transform3D(bas, Vector3(_wpos.x, 0, _wpos.y) - bas * Vector3(pel.x, 0, pel.z)))


## advance and draw; true while it's still going
func step(dt: float) -> bool:
	t += dt
	var pose: Dictionary
	if phase == "up":
		var ln: float = maxf(float(up.clips[clip].len) - CUT_END, 0.2) / SPEED
		pose = _place(up.pose_at(clip, minf(t, ln) * SPEED, true), _xf)
		if t < BLEND:   # out of the ragdoll's pose into the clip
			var w := smoothstep(0.0, 1.0, t / BLEND)
			for k in 15: pose.P[k] = (_rag[k] as Vector3).lerp(pose.P[k], w)
			if w < 0.5: pose.o = {"shoe_drop": 0.05}
		if t >= ln:
			if dz == null: return _finish(pose)
			# standing: on into the dizzy loop, turned / placed where the get-up ended
			phase = "dizzy"; t = 0.0
			_dz_xf = _align_dz(pose.P)
			_fade_from = pose; _fade_t = 0.0
	if phase == "dizzy":
		pose = _place(dz.pose_at(dzi, t, false), _dz_xf)
		if _fade_t < 1.0:
			_fade_t = minf(_fade_t + dt / FADE, 1.0)
			pose = RiderAnim._blend(_fade_from, pose, smoothstep(0.0, 1.0, _fade_t))
		if released and _fade_t >= 1.0 and not _start_walk(pose): return _finish(pose)
	if phase == "walk":
		pose = _walk_pose(dt)
		if _fade_t < 1.0:   # out of the dizzy pose into the walk
			_fade_t = minf(_fade_t + dt / FADE, 1.0)
			pose = RiderAnim._blend(_fade_from, pose, smoothstep(0.0, 1.0, _fade_t))
		if skipped or t > WALK_TIMEOUT or Vector2(target.x - _wpos.x, target.z - _wpos.y).length() <= ARRIVE:
			return _finish(pose)
	last_world = pose.P
	rider.pose_points(pose.P, pose.o)
	return true


func _align_dz(stand_P: Array) -> Transform3D:
	var a: Array = dz.pose_at(dzi, 0.0, false).P
	return _align(a, stand_P)


func _finish(pose: Dictionary) -> bool:
	phase = "done"
	last_world = pose.P
	rider.pose_points(pose.P, pose.o)
	free_clips()
	return false


func free_clips() -> void:
	if up: up.free_clips()
	if dz: dz.free_clips()
	if wk: wk.free_clips()
