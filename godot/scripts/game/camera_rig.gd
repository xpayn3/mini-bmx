class_name CameraRig
extends Camera3D
## Port of updateCamera() + the camera presets from src/main.js: diorama / chase / side / drone /
## trackside... Orbit with Z / X or a mouse drag (or the right stick), zoom with the wheel or + / -.

const PRESETS := {
	# default: high drone-like view a little off to the side, turning with the trail AHEAD (not the bike)
	# and aiming past the rider so the rider sits low in the frame and you see what's coming
	"trail":     {"label": "Trail",      "dist": 10.5, "pitch": 18.0, "follow": true,  "fov": 52.0, "orbit": 0.2, "rate": 2.6, "ahead": true, "occ_max": 16.0},
	"diorama":   {"label": "Diorama",    "dist": 38.0, "pitch": 46.0, "follow": true,  "fov": 30.0},
	"close":     {"label": "Close",      "dist": 16.0, "pitch": 40.0, "follow": true,  "fov": 30.0},
	"chase":     {"label": "Chase",      "dist": 7.0,  "pitch": 16.0, "follow": true,  "fov": 42.0, "rate": 3.2},
	"side":      {"label": "Side",       "dist": 14.0, "pitch": 10.0, "follow": true,  "fov": 28.0, "orbit": PI / 2, "rate": 2.5},
	"iso":       {"label": "Isometric",  "dist": 34.0, "pitch": 35.0, "follow": false, "fov": 28.0, "orbit": PI / 4},
	"top":       {"label": "Top-down",   "dist": 34.0, "pitch": 84.0, "follow": false, "fov": 30.0},
	"orbitcam":  {"label": "Slow orbit", "dist": 12.0, "pitch": 20.0, "follow": true,  "fov": 32.0, "spin": 0.2},
	"drone":     {"label": "Drone",      "dist": 22.0, "pitch": 36.0, "follow": true,  "fov": 34.0, "rate": 0.55, "lag": 1.4, "drift": true},
	"trackside": {"label": "Trackside",  "mode": "trackside", "fov": 14.0},
	"dolly":     {"label": "Low dolly",  "dist": 5.0,  "pitch": 5.0,  "follow": true,  "fov": 24.0, "orbit": PI * 0.42, "rate": 2.8},
}
## title screen only (not in the C cycle): behind and above the rider, looking out over the landscape
const VISTA := {"label": "Lookout", "mode": "vista", "fov": 42.0, "back": 19.0, "up": 5.0, "side": -4.4, "look": 160.0, "drop": 0.128}
var vista_yaw := 0.0

var game
var mode := "trail"
var trail_i := -1            # nearest trail centreline point (search hint)
var trail_dir := Vector3.ZERO  # smoothed direction to the trail ahead (Trail camera)
var trail_course = null
var dist := 22.0
var orbit := 0.0
var orbit_t := 0.0
var cam_pitch := 36.0
var cam_pitch_t := 36.0
var cam_yaw := 0.0
var cam_fov := 34.0
var occ := 0.0
var track_pos = null
var target := Vector3.ZERO
var anchor := Vector3.ZERO   # what the camera is placed from (the rider); target = where it looks
var pos_s := Vector3.ZERO
var pos_v := Vector3.ZERO
var pos_init := false
var t := 0.0
var dragging := false
var fov_boost := 0.0   # degrees added at speed (game.gd speed feel)
var pan_t := -100.0    # when the user last turned the camera (drag, Z / X, stick): re-centre waits for it
var follow_k := 1.0    # Settings "cam_follow": how quickly the camera turns after the rider

func _ready() -> void:
	near = 0.1
	far = 400.0
	fov = cam_fov

func preset() -> Dictionary:
	return VISTA if mode == "vista" else PRESETS[mode]

func set_mode(m: String) -> void:
	if m == "vista":
		mode = m; orbit = 0.0; orbit_t = 0.0; cam_pitch_t = 0.0; cam_pitch = 0.0
		return
	if not PRESETS.has(m): return
	var P: Dictionary = PRESETS[m]
	mode = m
	track_pos = null
	if P.get("mode", "") != "trackside":
		dist = P.dist; cam_pitch_t = P.pitch
		orbit_t = P.get("orbit", 0.0); orbit = orbit_t
	if not P.get("follow", false) and P.get("mode", "") != "trackside":
		cam_yaw = 0.0

func next_mode() -> String:
	var ks := PRESETS.keys()
	if not PRESETS.has(mode): mode = ks[ks.size() - 1]
	set_mode(ks[(ks.find(mode) + 1) % ks.size()])
	return PRESETS[mode].label

func snap_to(p: Vector3) -> void:
	target = p; anchor = p
	pos_init = false
	trail_i = -1; trail_dir = Vector3.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused: return
	var sens: float = Settings.get_v("mouse_sens")
	var inv := -1.0 if Settings.get_v("invert_y") else 1.0
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: dist = clampf(dist * 0.9, 4, 80)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: dist = clampf(dist * 1.1, 4, 80)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: dragging = e.pressed
	elif e is InputEventMouseMotion and dragging:
		pan_t = t
		orbit_t -=e.relative.x * 0.008 * sens   # grab the world: drag right turns the scene right (as in the garage)
		cam_pitch_t = clampf(cam_pitch_t + e.relative.y * 0.25 * sens * inv, 4, 85)
	elif e.is_action_pressed("cam_left") and e is InputEventKey: orbit_t -= PI / 4; pan_t = t
	elif e.is_action_pressed("cam_right") and e is InputEventKey: orbit_t += PI / 4; pan_t = t

func update_cam(dt: float) -> void:
	t += dt
	var st: BikePhysics = game.phys
	var P: Dictionary = preset()
	if P.get("mode", "") == "vista":
		RenderingServer.global_shader_parameter_set("cam_see", Vector4.ZERO)
		_vista(dt, P)
		return
	# analog camera (gamepad right stick) + zoom keys
	var ax := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ay := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	follow_k = float(Settings.get_v("cam_follow"))
	if absf(ax) > 0.2 or absf(ay) > 0.2: pan_t = t
	if absf(ax) > 0.2: orbit_t += ax * dt * 2.2
	if absf(ay) > 0.2: cam_pitch_t = clampf(cam_pitch_t + ay * dt * 60 * (-1.0 if Settings.get_v("invert_y") else 1.0), 4, 85)
	if Input.is_action_pressed("zoom_in"): dist = clampf(dist * (1 - dt * 1.2), 4, 80)
	if Input.is_action_pressed("zoom_out"): dist = clampf(dist * (1 + dt * 1.2), 4, 80)

	var f := Vector3(cos(st.heading), 0, -sin(st.heading))
	var drawn: Vector3 = game.drawn_pos
	var want: Vector3
	if st.crash_on and game.ragdoll:
		want = (game.ragdoll.p[Ragdoll.PELVIS] as Vector3).lerp(Vector3(st.x, st.y, st.z), 0.3) + Vector3(0, 0.3, 0)
	elif P.get("ahead", false):
		# aim a few metres up the trail (more at speed): the rider sits in the lower part of the frame
		_look_dir(st, f, dt)   # steers cam_yaw toward the trail ahead (below)
		# aim straight out along the camera's own heading from the rider: the rider always stays framed,
		# even when the camera lags in a tight turn
		# + the user's drag (orbit): look the way the camera points, so a pan swings the view round the rider
		var ly := cam_yaw + orbit + deg_to_rad(float(Settings.get_v("cam_side")))
		var look := Vector3(cos(ly), 0, -sin(ly))
		if not pos_init:
			look = trail_dir if trail_dir.length_squared() > 0.01 else f
			cam_yaw = atan2(-look.z, look.x)
		var lead := clampf(5.0 + absf(st.v) * 0.6, 5.0, 14.0) * float(Settings.get_v("cam_ahead"))
		# aim at the ground up ahead (+ a little): on a descent the view tips down the slope with you
		var ap: Vector3 = Vector3(drawn.x, 0, drawn.z) + look * lead
		var gy: float = game.terrain.height(ap.x, ap.z)
		want = Vector3(ap.x, lerpf(drawn.y, gy, 0.6) + 1.0, ap.z)
	else:
		var k := 0.05 if P.get("mode", "") == "trackside" else (0.1 if P.get("drift", false) else 0.25)
		want = Vector3(drawn.x, drawn.y + 0.5, drawn.z) + f * clampf(st.v, -1, 10) * k
	target = target.lerp(want, minf(1.0, dt * (7.0 if P.get("drift", false) else P.get("lag", 5.0))))
	if P.get("ahead", false) and not (st.crash_on and game.ragdoll):
		# placed behind the RIDER (not behind the look point, which runs up to 14 m ahead)
		anchor = anchor.lerp(Vector3(drawn.x, drawn.y + 1.0, drawn.z), minf(1.0, dt * 12.0)) if pos_init else Vector3(drawn.x, drawn.y + 1.0, drawn.z)
	elif P.get("ahead", false):
		anchor = anchor.lerp(target, minf(1.0, dt * 5.0))   # crash: glide over to the rider, no jump
	else:
		anchor = target
	var fov_t: float = P.fov
	var terrain = game.terrain
	if P.get("mode", "") == "trackside":
		var side := Vector3(-f.z, 0, f.x)
		var rel := 0.0
		var far_d := 1e9
		if track_pos != null:
			rel = (st.x - track_pos.x) * f.x + (st.z - track_pos.z) * f.z
			far_d = Vector2(st.x - track_pos.x, st.z - track_pos.z).length()
		if track_pos == null or rel > 9 or far_d > 38:
			var sgn := -1.0 if randf() < 0.5 else 1.0
			var ahead := 18 + randf() * 8
			var off := 5 + randf() * 5
			var px := st.x + f.x * ahead + side.x * off * sgn
			var pz := st.z + f.z * ahead + side.z * off * sgn
			track_pos = Vector3(px, terrain.height(px, pz) + 1.2 + randf() * 1.6, pz)
		global_position = track_pos
		var d := global_position.distance_to(target)
		fov_t = clampf(rad_to_deg(2 * atan(2.2 / d)), 7, 40)
		dist = d
	else:
		if P.get("follow", false) and absf(st.v) > 0.5:
			# in the air follow the travel direction, not the bike (it may be spinning a 360)
			var dir_h: float = st.course if st.air and not is_nan(st.course) else st.heading
			if P.get("ahead", false) and trail_dir.length_squared() > 0.01:
				dir_h = atan2(-trail_dir.z, trail_dir.x)
			cam_yaw += BikePhysics.ang_diff(dir_h, cam_yaw) * minf(1.0, dt * P.get("rate", 1.4) * follow_k * minf(1.0, absf(st.v) / 4))
		if P.has("spin"): orbit_t += P.spin * dt
		elif bool(Settings.get_v("cam_recenter")) and t - pan_t > 2.5 and not dragging:
			# swing back to the preset angle a moment after the last drag / Z X / stick turn
			var k := minf(1.0, dt * 1.2)
			orbit_t += BikePhysics.ang_diff(float(P.get("orbit", 0.0)), orbit_t) * k
			cam_pitch_t += (float(P.pitch) - cam_pitch_t) * k
		orbit += (orbit_t - orbit) * minf(1.0, dt * 8)
		cam_pitch += (cam_pitch_t - cam_pitch) * minf(1.0, dt * 8)
		var yaw := cam_yaw + orbit + deg_to_rad(float(Settings.get_v("cam_side")))
		var pit := clampf(cam_pitch + float(Settings.get_v("cam_height")), 2.0, 84.0)
		var dist0 := dist
		dist = dist0 * float(Settings.get_v("cam_dist"))   # the zoom the user set × the Settings distance
		if P.get("drift", false):
			yaw += sin(t * 0.13) * 0.3; pit += sin(t * 0.09) * 4
		var back := Vector3(cos(yaw), 0, -sin(yaw))
		var need := 0.0
		var occ_max: float = P.get("occ_max", 46.0)
		while need < occ_max and pit + need < 84 and _blocked(pit + need, back, drawn.y, anchor):
			need += 4 if P.get("ahead", false) else 6
		occ += (need - occ) * minf(1.0, dt * (2.0 if need > occ else 0.7))   # rise gently: no hops at some angles
		pit = minf(84, pit + occ)
		var pr := deg_to_rad(pit)
		var want_pos := anchor - back * dist * cos(pr) + Vector3(0, dist * sin(pr), 0)
		if P.get("drift", false) or P.get("ahead", false):
			# the drone floats on a spring, but on its OFFSET from the rider (pos_s), not its world
			# position: a world-space spring trailed ~10 m behind at speed, and when zoomed in that lag
			# crossed the snap-back limit, so the camera kept jumping
			var off_want := want_pos - anchor
			if not pos_init:
				pos_s = off_want; pos_v = Vector3.ZERO; pos_init = true
			var w := (3.2 if P.get("ahead", false) else 2.4) * clampf(follow_k, 0.4, 2.5)
			pos_v = (pos_v + (off_want - pos_s) * w * w * dt) * exp(-2 * w * dt)
			pos_s += pos_v * dt
			global_position = anchor + pos_s
		else:
			global_position = want_pos; pos_init = false
		var gh: float = terrain.height(global_position.x, global_position.z) + 0.35
		if global_position.y < gh:
			global_position.y = gh
			if P.get("drift", false) or P.get("ahead", false): pos_s.y = maxf(pos_s.y, gh - anchor.y); pos_v.y = maxf(pos_v.y, 0.0)
		dist = dist0
	cam_fov += (fov_t - cam_fov) * minf(1.0, dt * (6.0 if P.get("mode", "") == "trackside" else 3.0))
	fov = clampf(cam_fov * (1.0 + fov_boost * float(Settings.get_v("cam_speed_fov")) / 34.0) + float(Settings.get_v("fov")), 5, 110)
	var sk: float = st.shake * float(Settings.get_v("cam_shake"))
	if sk > 0:
		global_position += Vector3(sin(t * 37) * sk * 0.12, sin(t * 29 + 1) * sk * 0.12, 0)
	st.shake = maxf(0.0, st.shake - dt * 1.2)
	var aim := target
	if bool(Settings.get_v("cam_keep")) and not (st.crash_on and game.ragdoll):
		aim = _keep_rider_in_view(target, drawn + Vector3(0, 0.9, 0))
	if global_position.distance_to(aim) > 0.01:
		look_at(aim, Vector3.UP)
	# trees / rocks between the camera and the rider dissolve (deco.gdshader)
	var see: Vector3 = target if (st.crash_on and game.ragdoll) else drawn + Vector3(0, 0.9, 0)
	RenderingServer.global_shader_parameter_set("cam_see", Vector4(see.x, see.y, see.z, 1.0 if bool(Settings.get_v("cam_fade")) else 0.0))
	RenderingServer.global_shader_parameter_set("cam_eye", Vector4(global_position.x, global_position.y, global_position.z, 0.0))

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("cam_see", Vector4.ZERO)

## never lose the rider: if the look point would put them more than ~70% of the way to the frame edge
## (dragging the camera round, tight turns, look-ahead), turn the aim toward them until they sit at that edge
func _keep_rider_in_view(aim: Vector3, rider: Vector3) -> Vector3:
	var to_t := aim - global_position
	var to_r := rider - global_position
	if to_t.length_squared() < 0.0001 or to_r.length_squared() < 0.0001:
		return aim
	var ang := to_t.angle_to(to_r)
	var lim := deg_to_rad(fov) * 0.5 * 0.7   # vertical half-FOV (the narrower one) with a margin
	if ang <= lim:
		return aim
	var d := to_t.normalized().slerp(to_r.normalized(), 1.0 - lim / ang)
	return global_position + d * to_t.length()

## lookout: a slow sway left/right over the view; a mouse drag turns it, the rider stays in the frame
func _vista(dt: float, P: Dictionary) -> void:
	orbit += (orbit_t - orbit) * minf(1.0, dt * 4)
	var yaw := vista_yaw + orbit + sin(t * 0.05) * 0.22
	var dir := Vector3(cos(yaw), 0, -sin(yaw))
	var right := Vector3(-dir.z, 0, dir.x)
	var base: Vector3 = game.drawn_pos
	var pos: Vector3 = base - dir * P.back + right * P.side + Vector3(0, P.up + sin(t * 0.21) * 0.25, 0)
	var gh: float = game.terrain.height(pos.x, pos.z) + 1.2
	pos.y = maxf(pos.y, gh)
	global_position = pos
	var aim: Vector3 = pos + dir * P.look
	aim.y = pos.y - P.look * float(P.drop)
	look_at(aim, Vector3.UP)
	cam_fov += (float(P.fov) - cam_fov) * minf(1.0, dt * 3.0)
	fov = clampf(cam_fov + float(Settings.get_v("fov")), 5, 110)

func _blocked(p_deg: float, back: Vector3, dy: float, from: Vector3) -> bool:
	var pr := deg_to_rad(p_deg)
	var hx := -back.x * dist * cos(pr)
	var hz := -back.z * dist * cos(pr)
	var hy := dist * sin(pr)
	var y0 := dy + 0.6
	for i in range(1, 21):
		var u := i / 21.0
		var px := from.x + hx * u
		var pz := from.z + hz * u
		if game.terrain.height(px, pz) + 0.6 > y0 + (from.y + hy - y0) * u:
			return true
	return false

## Trail camera: smoothed horizontal direction from the rider to the trail ~10-25 m ahead (in the way
## the rider is going), so the view turns INTO a bend before the bike does. Off the trail: the heading.
func _look_dir(st: BikePhysics, f: Vector3, dt: float) -> Vector3:
	var want := f
	var c = null
	if game.terrain and game.terrain.field:
		c = game.terrain.field.course
	if c != null and c.n > 2:
		var n: int = c.n
		if c != trail_course:
			trail_course = c   # a grown course keeps every old point, so the hint stays good
		var best := 1e18
		if trail_i < 0 or trail_i >= n:
			for i in range(0, n, 4):   # cold start: coarse scan of the whole course
				var dx: float = c.X[i] - st.x
				var dz: float = c.Z[i] - st.z
				var d2 := dx * dx + dz * dz
				if d2 < best: best = d2; trail_i = i
		var lo := maxi(0, trail_i - 30)
		var hi := mini(n - 1, trail_i + 30)
		best = 1e18
		for i in range(lo, hi + 1):
			var dx: float = c.X[i] - st.x
			var dz: float = c.Z[i] - st.z
			var d2 := dx * dx + dz * dz
			if d2 < best: best = d2; trail_i = i
		var off := sqrt(best)
		if off < 14.0:
			var i0 := clampi(trail_i, 1, n - 2)
			var tx: float = c.X[i0 + 1] - c.X[i0 - 1]
			var tz: float = c.Z[i0 + 1] - c.Z[i0 - 1]
			var sgn := 1 if tx * f.x + tz * f.z >= 0.0 else -1   # riding up or down the course
			var steps := int(clampf(10.0 + absf(st.v) * 0.9, 10.0, 26.0) / TrailCourse.STEP)
			var j := clampi(trail_i + sgn * steps, 0, n - 1)
			var a := Vector3(c.X[j] - st.x, 0, c.Z[j] - st.z)
			if a.length_squared() > 1.0:
				a = a.normalized()
				# fade back to the heading as the rider wanders off the trail
				# trust the trail only while on it and riding along it; else follow the bike
				var k := (1.0 - clampf((off - 4.0) / 6.0, 0.0, 1.0)) * clampf((a.dot(f) - 0.3) / 0.5, 0.0, 1.0)
				want = f.lerp(a, k).normalized()
	else:
		trail_i = -1
	if trail_dir.length_squared() < 0.01:
		trail_dir = want
	else:
		trail_dir = trail_dir.slerp(want, minf(1.0, dt * 3.0)).normalized()
	return trail_dir
