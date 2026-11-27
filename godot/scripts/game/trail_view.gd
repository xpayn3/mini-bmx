class_name TrailView
extends RefCounted
## The Trail camera's director (2026-11-27, user: "show us the trail on a 180 turn, we can't see what's next, and when
## jumping or falling we don't see where we land"). Before, the camera looked at ONE point 10-26 m up the trail, at a
## fixed low angle: in a hairpin that point lies behind you (it fell back to the bike's heading), and over a lip or a
## drop the ground you were about to land on was hidden behind the edge. Now it works from the things that must be SEEN:
##  - points up the trail (5 .. 39 m, more at speed) and, in a flight, the spot you will come down on (ballistic)
##  - yaw: toward the middle of all of them, never more than YAW_MAX off the way you ride (the steering stays natural)
##  - height: raised just enough that the ground doesn't hide them (nor the rider), and a bit more for a sharp bend
##  - distance: pulled back for a bend, a big flight, or whenever they don't fit the frame
##  - aim: the rider low in the frame, the view tipped / turned so the trail and the landing are inside it
## Everything is eased (no snapping between points). BMX_OLD_TRAILCAM=1 = the old camera.

const S := [5.0, 9.0, 13.0, 18.0, 24.0, 31.0, 39.0]   # m up the trail
const W_YAW := [0.5, 0.9, 1.0, 1.0, 0.9, 0.65, 0.4]    # their pull on the view's direction
const W_SEE := [0.8, 1.0, 1.0, 1.0, 0.9, 0.6, 0.0]     # how hard the camera works to see them
const YAW_MAX := 1.3          # rad off the travel heading
const YAW_W := 3.6            # the yaw spring (critically damped)
const YAW_RATE := 2.4         # rad/s at most
const EXTRA_MAX := 30.0       # deg of extra pitch at most
const BEND_PITCH := 9.0       # deg more from above in a sharp bend
const BEND_ZOOM := 0.22       # ... and that much further back
const AIR_ZOOM := 0.25        # further back in a big flight
const ZOOM_MAX := 1.6
const NEAR_SIDE := 0.07       # rad the camera sits further to the side always: the metres just ahead are past the shoulder
const AIR_SIDE := 0.22        # ... and more in a flight, so the rider doesn't cover the landing
const HEAD := 2.0             # m over the bike's point the line of sight clears the rider's head by
const RIDER_LOW := 0.36       # the rider sits this far under the middle (share of the half view)

var yaw := 0.0                # the view's direction (rad, like heading), without the user's drag
var from_yaw := NAN           # starting up: ease round from this direction (NAN = take the new one at once: a teleport)
var extra := 0.0              # deg added to the camera's pitch
var zoom := 1.0               # x the camera's distance
var side := NEAR_SIDE         # rad the camera swings further round to the side

var _yv := 0.0
var _ev := 0.0
var _zv := 0.0
var _fit := 0.0               # extra distance because things didn't fit the frame
var _over := 0.0
var _el := 0.0                # aim: elevation over the rider's, azimuth off the view
var _az := 0.0
var _aim_init := false
var _started := false
var _i := -1                  # nearest course point (search hint)
var _course = null
var _pts: Array = []          # the points up the trail (world)
var _h := PackedFloat32Array()   # each point's height over the rider, eased (a point sliding over bumps jumped the frame)
var _bend := 0.0              # 0..1 how sharply the trail ahead turns
var _land := Vector3.ZERO
var _land_w := 0.0            # 0..1: a flight's landing spot counts this much

func reset() -> void:
	_started = false; _aim_init = false; _i = -1; _pts.clear(); _h.clear()
	_land_w = 0.0; _fit = 0.0; _over = 0.0; _bend = 0.0

## where the trail goes: S metres up it from the rider (along the heading off the trail / without a course)
func _path(dt: float, terrain, st, f: Vector3, ys: float, reach: float) -> void:
	var c = terrain.field.course if terrain.field else null
	var k := 0.0      # 0 = follow the heading, 1 = follow the trail
	var u := 0.0      # the rider's place along the course, in points
	var sgn := 1
	var turn := 0.0
	if c != null and c.n > 2:
		if c != _course: _course = c   # (a grown course keeps every old point: the hint stays good)
		var best := 1e18
		if _i < 0 or _i >= c.n:
			for i in range(0, c.n, 4):
				var d2: float = (c.X[i] - st.x) * (c.X[i] - st.x) + (c.Z[i] - st.z) * (c.Z[i] - st.z)
				if d2 < best: best = d2; _i = i
		# (a short window first: the next leg of a hairpin can lie nearer than your own once you run wide)
		for win in [8, 30]:
			best = 1e18
			var at := _i
			for i in range(maxi(0, at - win), mini(c.n - 1, at + win) + 1):
				var d2: float = (c.X[i] - st.x) * (c.X[i] - st.x) + (c.Z[i] - st.z) * (c.Z[i] - st.z)
				if d2 < best: best = d2; _i = i
			if best < 64.0: break
		var off := sqrt(best)
		if off < 14.0:
			var along: float = c.TX[_i] * f.x + c.TZ[_i] * f.z
			sgn = 1 if along >= 0.0 else -1
			k = (1.0 - clampf((off - 4.0) / 8.0, 0.0, 1.0)) * smoothstep(0.05, 0.55, absf(along))
			var pr: float = (st.x - c.X[_i]) * c.TX[_i] + (st.z - c.Z[_i]) * c.TZ[_i]
			u = float(_i) + clampf(pr / TrailCourse.STEP, -0.5, 0.5)
			var j_end := clampi(_i + sgn * int(reach / TrailCourse.STEP), 0, c.n - 1)
			var prev := Vector2(c.TX[_i], c.TZ[_i])
			for j in range(_i, j_end, sgn):
				var t := Vector2(c.TX[j], c.TZ[j])
				turn += prev.angle_to(t); prev = t
	else:
		_i = -1
	_bend = k * smoothstep(0.7, 2.4, absf(turn))
	var scale_s := reach / float(S[S.size() - 1])
	_pts.resize(S.size())
	var fresh := _h.size() != S.size()
	if fresh: _h.resize(S.size())
	for n in S.size():
		var s: float = float(S[n]) * scale_s
		var p := Vector3(st.x + f.x * s, 0.0, st.z + f.z * s)
		if k > 0.0:
			var uu := clampf(u + sgn * s / TrailCourse.STEP, 0.0, float(c.n - 1))
			var i0 := mini(int(uu), c.n - 2)
			var t := uu - i0
			p.x = lerpf(p.x, lerpf(c.X[i0], c.X[i0 + 1], t), k)
			p.z = lerpf(p.z, lerpf(c.Z[i0], c.Z[i0 + 1], t), k)
		# on / coming up to a rope bridge: along the bridge (the trail's line bows ~2 m off the deck)
		var ra = terrain.rope_aim(st.x, st.z, s)
		var gy := 0.0
		if ra != null and Vector2(ra.x - st.x, ra.y - st.z).dot(Vector2(f.x, f.z)) > 0.0:
			p.x = ra.x; p.z = ra.y
			gy = maxf(terrain.deck_height(p.x, p.z), ys - 1.5)   # (the canyon floor is not the trail)
		else:
			gy = terrain.deck_height(p.x, p.z)
		_h[n] = gy - ys if fresh else lerpf(_h[n], gy - ys, 1.0 - exp(-dt * 5.0))
		p.y = ys + _h[n] + 0.3
		_pts[n] = p

## the spot this flight comes down on (the physics' own predictor sets state the ride reads: this one only looks)
func _landing(terrain, st, dt: float) -> void:
	var w := 0.0
	if st.air and not is_nan(st.course):
		var vx: float = cos(st.course) * st.v
		var vz: float = -sin(st.course) * st.v
		var p := Vector3(st.x, st.y, st.z)
		var vy: float = st.vy
		for i in 60:
			const H := 0.07
			vy -= BikePhysics.G * H
			p += Vector3(vx * H, vy * H, vz * H)
			var gh: float = terrain.deck_height(p.x, p.z)
			if p.y <= gh and vy < 0.0:
				w = smoothstep(0.35, 0.75, st.air_time + (i + 1) * H)   # (little skips don't move the camera)
				p.y = gh + 0.2
				if _land_w < 0.05: _land = p
				else: _land = _land.lerp(p, minf(1.0, dt * 8.0))
				break
	_land_w += (w - _land_w) * minf(1.0, dt * (7.0 if w > _land_w else 2.5))

## the camera height needed to see p over the ground from straight back at `eye` (x, z)
func _need_height(terrain, p: Vector3, eye: Vector2) -> float:
	var need := -1e9
	for t in [0.12, 0.2, 0.3, 0.42, 0.55, 0.7, 0.85]:
		var qx: float = lerpf(p.x, eye.x, t)
		var qz: float = lerpf(p.z, eye.y, t)
		need = maxf(need, p.y + (terrain.deck_height(qx, qz) + 0.2 - p.y) / t)
	return need

## yaw, extra pitch and zoom for this frame. `dist` / `pitch` = the camera's own (before ours), `orbit` = the user's drag
func update(dt: float, terrain, st, f: Vector3, drawn: Vector3, ys: float, dist: float, pitch: float, orbit: float, ahead_k: float, follow_k: float) -> void:
	var reach := clampf(22.0 + absf(st.v) * 1.2, 24.0, 42.0) * clampf(ahead_k, 0.4, 2.0)
	_path(dt, terrain, st, f, ys, reach)
	_landing(terrain, st, dt)
	# --- yaw: the middle of what lies ahead ---
	var hd := atan2(-f.z, f.x)
	var sum := Vector2.ZERO
	var tot := 0.0
	for n in S.size():
		var d := Vector2(_pts[n].x - st.x, _pts[n].z - st.z)
		var l := d.length()
		if l < 0.5: continue
		sum += d / l * float(W_YAW[n]) * minf(1.0, l / 8.0)
		tot += float(W_YAW[n])
	if _land_w > 0.01:
		var d := Vector2(_land.x - st.x, _land.z - st.z)
		if d.length() > 1.0:
			sum += d.normalized() * 3.0 * _land_w
			tot += 3.0 * _land_w
	var want := hd
	if tot > 0.0 and sum.length() > 0.05:
		var a := atan2(-sum.y, sum.x)
		# (a trail that doubles right back cancels itself out: then keep more of the heading)
		var sure := smoothstep(0.08, 0.35, sum.length() / tot)
		want = hd + clampf(BikePhysics.ang_diff(a, hd), -YAW_MAX, YAW_MAX) * sure
	if not _started:
		yaw = want if is_nan(from_yaw) else from_yaw; _yv = 0.0; extra = 0.0; _ev = 0.0; zoom = 1.0; _zv = 0.0
		_started = true
	elif absf(st.v) > 0.5:
		var w := YAW_W * clampf(follow_k, 0.4, 2.5) * clampf(0.35 + absf(st.v) / 7.0, 0.35, 1.0)
		var x := BikePhysics.ang_diff(yaw, want)
		var e := exp(-w * dt)
		var b := _yv + w * x
		var nx := (x + b * dt) * e
		_yv = clampf((_yv - w * b * dt) * e, -YAW_RATE, YAW_RATE)
		yaw += clampf(nx - x, -YAW_RATE * dt, YAW_RATE * dt)
	side += (NEAR_SIDE + AIR_SIDE * _land_w - side) * (1.0 - exp(-dt * 3.0))
	# --- height: enough to see over the ground (and over the rider) ---
	var ly := yaw + orbit + side
	var back := Vector2(cos(ly), -sin(ly))
	var d_eff := dist * zoom
	var p_now := deg_to_rad(clampf(pitch + extra, 2.0, 75.0))
	var rider := Vector3(drawn.x, ys + 1.0, drawn.z)
	var eye := Vector2(rider.x, rider.z) - back * d_eff * cos(p_now)
	var need := 0.0
	var n_pts := S.size() + 1
	for n in n_pts:
		var w: float = W_SEE[n] if n < S.size() else _land_w * 1.2
		if w <= 0.01: continue
		var p: Vector3 = _pts[n] if n < S.size() else _land
		var to_p := Vector2(p.x - eye.x, p.z - eye.y)
		if to_p.dot(back) < 1.0: continue   # (behind the camera: height won't bring it into view)
		var hy := _need_height(terrain, p, eye)
		var pit := rad_to_deg(asin(clampf((hy - rider.y) / d_eff, -1.0, 1.0)))
		need = maxf(need, minf(pit - pitch, EXTRA_MAX) * minf(w, 1.0))
		# hidden behind the rider: look over their head (only worth it a good way past them)
		var rp := Vector2(rider.x - eye.x, rider.z - eye.y)
		var past := to_p.length() - rp.length()
		if past > 2.0 and absf(rp.angle_to(to_p)) * rp.length() < 0.7:
			var t := past / to_p.length()
			var over := p.y + (drawn.y + HEAD - p.y) / maxf(t, 0.25)
			var pit_r := rad_to_deg(asin(clampf((over - rider.y) / d_eff, -1.0, 1.0)))
			need = maxf(need, minf(pit_r - pitch, 22.0 if n >= S.size() else 15.0) * minf(w, 1.0))
	need = clampf(maxf(need, BEND_PITCH * _bend), 0.0, EXTRA_MAX)
	# (up quickly, down gently: a crest coming and going mustn't pump the view)
	var we := 3.0 if need > extra else 1.3
	var ex := extra - need
	var ee := exp(-we * dt)
	var eb := _ev + we * ex
	extra = need + (ex + eb * dt) * ee
	_ev = (_ev - we * eb * dt) * ee
	# --- distance ---
	_fit = clampf(_fit + (_over * 0.9 if _over > 0.0 else -0.18) * dt, 0.0, 0.4)
	var air_h := _land_w * smoothstep(1.5, 7.0, drawn.y - _land.y)
	var z_t := minf(ZOOM_MAX, 1.0 + BEND_ZOOM * _bend + AIR_ZOOM * air_h + _fit)
	var wz := 2.4 if z_t > zoom else 1.3
	var zx := zoom - z_t
	var ze := exp(-wz * dt)
	var zb := _zv + wz * zx
	zoom = z_t + (zx + zb * dt) * ze
	_zv = (_zv - wz * zb * dt) * ze

## where to look from `cam`: `ly` = the view's yaw incl. the drag, `fov` vertical (deg), `centred` 0..1 = how much the
## aim may turn sideways (less while the user has swung the camera round)
func aim(dt: float, cam: Vector3, ly: float, fov: float, aspect: float, rider: Vector3, centred: float) -> Vector3:
	var hv := deg_to_rad(fov) * 0.5
	var hh := atan(tan(hv) * aspect)
	var to_r := rider - cam
	var el_r := atan2(to_r.y, Vector2(to_r.x, to_r.z).length())
	var az_r := BikePhysics.ang_diff(atan2(-to_r.z, to_r.x), ly)
	var lo := 1e9
	var hi := -1e9
	var az_lo := 0.0
	var az_hi := 0.0
	var n_pts := _pts.size() + 1
	for n in n_pts:
		var w: float = (W_SEE[n] if n < _pts.size() else _land_w)
		if w < 0.5: continue
		var d: Vector3 = (_pts[n] if n < _pts.size() else _land) - cam
		var az := BikePhysics.ang_diff(atan2(-d.z, d.x), ly)
		if absf(az) > 1.7: continue
		var el := atan2(d.y, Vector2(d.x, d.z).length())
		# (the landing fades in: its pull on the frame grows with its weight)
		if n >= _pts.size(): el = lerpf(el_r, el, _land_w); az = az * _land_w
		lo = minf(lo, el); hi = maxf(hi, el)
		az_lo = minf(az_lo, az); az_hi = maxf(az_hi, az)
	var el_c := el_r + hv * RIDER_LOW
	var az_c := 0.0
	_over = 0.0
	if hi > -1e8:
		el_c = minf(el_c, lo + hv * 0.72)      # what lies below (a drop, a landing) comes into the frame ...
		el_c = maxf(el_c, el_r - hv * 0.3)     # ... but the rider never goes past the upper third
		az_c = clampf((az_lo + az_hi) * 0.5, -hh * 0.4, hh * 0.4) * centred
		var spread_v := maxf(hi, el_r) - minf(lo, el_r)
		var spread_h := maxf(az_hi - az_c, az_c - az_lo)
		_over = clampf(maxf(spread_v / (hv * 1.55), spread_h / (hh * 0.88)) - 1.0, 0.0, 0.5)
	# the rider stays in the frame sideways too
	az_c = clampf(az_c, az_r - hh * 0.5, az_r + hh * 0.5)
	if not _aim_init:
		_el = el_c - el_r; _az = az_c; _aim_init = true
	else:
		_el += (el_c - el_r - _el) * (1.0 - exp(-dt * 4.0))
		_az += (az_c - _az) * (1.0 - exp(-dt * 3.0))
	var e := clampf(el_r + _el, -1.35, 0.8)
	var a := ly + _az
	var reach := maxf(4.0, to_r.length())
	return cam + Vector3(cos(a) * cos(e), sin(e), -sin(a) * cos(e)) * reach
