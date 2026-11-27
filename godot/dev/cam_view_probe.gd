extends RefCounted
## BMX_CAMVIEW=1: can the player SEE where they are going? Judged from outside the camera's own code, so any camera
## (and BMX_OLD_TRAILCAM) is measured the same way.
##  - trail: points 6 / 10 / 15 / 20 / 25 m up the trail, each in frame, not behind the ground and not behind the rider.
##    Split into all riding / bends (the next 30 m turn 90 deg or more) / air / drops (3 m+ down within 25 m)
##  - landing: for every flight over 0.35 s, the share of its frames that showed the spot it really came down on
##  - calm: how fast the view turns (deg/s, 95th percentile and worst) and where the rider sits in the frame
## Prints CAMVIEW lines when the ride ends. CAMVIEWSHOT=prefix saves shots in bends and mid-air.

const AHEAD := [6.0, 10.0, 15.0, 20.0, 25.0, 35.0]

var cam            # CameraRig
var _i := -1
var _sum := {}     # name -> [seen, total]
var _flight: Array = []   # [[transform, fov, rider pos]] of the current flight
var _air_t := 0.0
var _land := []    # per flight: share of its frames that showed the touch-down spot
var _land_late := []   # the same, the second half of the flight only
var _rates: Array = []
var _last_dir := Vector3.ZERO
var _rider_y: Array = []
var _t := 0.0
# shake (on the ground at speed): how abruptly the view's turning / moving changes
var _w := Vector3.ZERO      # the view's turn rate (rad/s)
var _pv := Vector3.ZERO     # the camera's velocity
var _pp := Vector3.ZERO
var _bp := Basis()
var _sn := 0
var _rot_acc: Array = []    # deg/s^2
var _pos_acc: Array = []    # m/s^2
var _vert_acc: Array = []
var _shot := OS.get_environment("CAMVIEWSHOT")
var _shot_n := {"bend": 0, "air": 0, "drop": 0}
var _shot_wait := 0.0

func _init(c) -> void:
	cam = c
	c.tree_exiting.connect(_report)

var _why := ""     # why the last _visible said no: frame / ground / rider
var _whys := {}    # kind -> {why: n}

func _tally(kind: String) -> void:
	var d: Dictionary = _whys.get(kind, {})
	d[_why] = d.get(_why, 0) + 1
	_whys[kind] = d

func _visible(xf: Transform3D, fov: float, p: Vector3, rider: Vector3) -> bool:
	_why = "frame"
	var l := xf.affine_inverse() * p
	if l.z > -0.2: return false
	var th := tan(deg_to_rad(fov) * 0.5)
	var vs: Vector2 = cam.get_viewport().get_visible_rect().size
	if absf(l.y / -l.z) > th * 0.96 or absf(l.x / -l.z) > th * (vs.x / vs.y) * 0.96: return false
	_why = "ground"
	var e := xf.origin
	var terr = cam.game.terrain
	for k in range(1, 32):
		var u := k / 32.0
		var q := e.lerp(p, u)
		if e.distance_to(p) * (1.0 - u) < 0.6: break
		if terr.deck_height(q.x, q.z) > q.y + 0.05: return false
	# behind the rider: the line of sight passes within 0.35 m of the body (bars .. helmet)
	var near := Geometry3D.get_closest_points_between_segments(e, p, rider + Vector3(0, 0.3, 0), rider + Vector3(0, 1.55, 0))
	_why = "rider"
	if near[0].distance_to(near[1]) < 0.35 and near[0].distance_to(p) > 1.0: return false
	return true

func _count(k: String, ok: bool) -> void:
	var a: Array = _sum.get(k, [0, 0])
	a[0] += 1 if ok else 0
	a[1] += 1
	_sum[k] = a

func sample(dt: float) -> void:
	var st = cam.game.phys
	var c = cam.game.terrain.field.course
	_shake(dt, st)
	_t += dt
	_shot_wait -= dt
	if st.crash_on or _t < 1.5:
		_flight.clear(); _air_t = 0.0; _last_dir = Vector3.ZERO
		return
	var drawn: Vector3 = cam.game.drawn_pos
	var xf: Transform3D = cam.global_transform
	var fwd := -xf.basis.z
	if _last_dir != Vector3.ZERO and dt > 0.0: _rates.append(rad_to_deg(_last_dir.angle_to(fwd)) / dt)
	_last_dir = fwd
	var rl := xf.affine_inverse() * (drawn + Vector3(0, 0.9, 0))
	if rl.z < 0.0: _rider_y.append((rl.y / -rl.z) / tan(deg_to_rad(cam.fov) * 0.5))
	if st.air:
		_air_t += dt
		_flight.append([xf, cam.fov, drawn])
	else:
		if _air_t > 0.35 and _flight.size() > 4:
			var land := drawn + Vector3(0, 0.15, 0)
			var n := 0
			var n2 := 0
			for k in _flight.size():
				var fr: Array = _flight[k]
				var ok2 := _visible(fr[0], fr[1], land, fr[2])
				if not ok2: _tally("landing")
				if ok2:
					n += 1
					if k >= _flight.size() / 2: n2 += 1
			_land.append(float(n) / _flight.size())
			_land_late.append(float(n2) / (_flight.size() - _flight.size() / 2))
		_flight.clear(); _air_t = 0.0
	if c == null or c.n < 3 or absf(st.v) < 2.0: return
	var lo := 0 if _i < 0 else maxi(0, _i - 8)
	var hi: int = c.n - 1 if _i < 0 else mini(c.n - 1, _i + 8)
	var best := 1e18
	for i in range(lo, hi + 1):
		var d2: float = (c.X[i] - st.x) * (c.X[i] - st.x) + (c.Z[i] - st.z) * (c.Z[i] - st.z)
		if d2 < best: best = d2; _i = i
	if best > 64.0:
		if best > 400.0: _i = -1
		return
	var sgn := 1 if c.TX[_i] * cos(st.heading) - c.TZ[_i] * sin(st.heading) >= 0.0 else -1
	var turn := 0.0
	var pa := Vector2(c.TX[_i], c.TZ[_i])
	for k in range(1, 16):
		var j := clampi(_i + sgn * k, 0, c.n - 1)
		var pb := Vector2(c.TX[j], c.TZ[j])
		turn += pa.angle_to(pb); pa = pb
	var bend := absf(turn) > PI * 0.5
	var drop := false
	var pts: Array = []
	for s in AHEAD:
		var j := clampi(_i + sgn * int(s / TrailCourse.STEP), 0, c.n - 1)
		var p := Vector3(c.X[j], 0, c.Z[j])
		p.y = cam.game.terrain.deck_height(p.x, p.z) + 0.3
		pts.append(p)
		if p.y < drawn.y - 3.0: drop = true
	var seen := 0
	for k in pts.size():
		var ok := _visible(xf, cam.fov, pts[k], drawn)
		if ok: seen += 1
		else: _tally("ahead@%d" % int(AHEAD[k]))
		_count("all", ok); _count("all@%d" % int(AHEAD[k]), ok)
		if bend: _count("bend", ok); _count("bend@%d" % int(AHEAD[k]), ok)
		if st.air: _count("air", ok)
		if drop: _count("drop", ok)
	if _shot != "" and _shot_wait <= 0.0:
		var kind := "air" if (st.air and _air_t > 0.4) else ("drop" if drop else ("bend" if absf(turn) > PI * 0.75 else ""))
		if kind != "" and _shot_n[kind] < 5:
			cam.get_viewport().get_texture().get_image().save_png("%s_%s%d.png" % [_shot, kind, _shot_n[kind]])
			print("CAMVIEWSHOT %s%d t=%.1f seen=%d/6 v=%.1f" % [kind, _shot_n[kind], _t, seen, st.v])
			_shot_n[kind] += 1; _shot_wait = 1.2

func _shake(dt: float, st) -> void:
	var b: Basis = cam.global_transform.basis.orthonormalized()
	var p: Vector3 = cam.global_position
	if st.crash_on or _t < 2.0 or dt <= 0.0: _sn = 0
	if _sn > 0:
		var q := (b * _bp.inverse()).get_rotation_quaternion()
		var w: Vector3 = Vector3(q.x, q.y, q.z) * 2.0 * signf(q.w) / dt
		var v: Vector3 = (p - _pp) / dt
		if _sn > 1 and absf(st.v) > 5.0 and not st.air:
			_rot_acc.append(rad_to_deg((w - _w).length()) / dt)
			_pos_acc.append((v - _pv).length() / dt)
			_vert_acc.append(absf(v.y - _pv.y) / dt)
		_w = w; _pv = v
	_bp = b; _pp = p; _sn += 1

func _rms(a: Array) -> float:
	var m := 0.0
	for v in a: m += v * v
	return sqrt(m / maxf(1.0, a.size()))

func _pct(a: Array, q: float) -> float:
	if a.is_empty(): return 0.0
	var s := a.duplicate(); s.sort()
	return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]

func _mean(a: Array) -> float:
	var m := 0.0
	for v in a: m += v
	return m / maxf(1.0, a.size())

func _report() -> void:
	var keys := _sum.keys(); keys.sort()
	for k in keys:
		print("CAMVIEW %-9s seen=%5.1f%%  n=%d" % [k, 100.0 * _sum[k][0] / maxf(1.0, _sum[k][1]), _sum[k][1]])
	print("CAMVIEW why ", _whys)
	var none := 0
	for v in _land_late:
		if v < 0.5: none += 1
	print("CAMVIEW landing flights=%d seen=%.1f%% late_half=%.1f%% hidden_flights=%d" % [_land.size(), 100.0 * _mean(_land), 100.0 * _mean(_land_late), none])
	print("CAMVIEW shake rot_acc rms=%.0f p99=%.0f max=%.0f deg/s2   pos_acc rms=%.1f p99=%.1f   vert rms=%.1f p99=%.1f m/s2  n=%d" % [_rms(_rot_acc), _pct(_rot_acc, 0.99), _pct(_rot_acc, 1.0), _rms(_pos_acc), _pct(_pos_acc, 0.99), _rms(_vert_acc), _pct(_vert_acc, 0.99), _rot_acc.size()])
	print("CAMVIEW calm turn_p50=%.1f turn_p95=%.1f turn_max=%.1f deg/s  rider_y p05=%.2f p50=%.2f p95=%.2f (-1 bottom .. 1 top)" % [_pct(_rates, 0.5), _pct(_rates, 0.95), _pct(_rates, 1.0), _pct(_rider_y, 0.05), _pct(_rider_y, 0.5), _pct(_rider_y, 0.95)])
