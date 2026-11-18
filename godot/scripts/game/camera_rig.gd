class_name CameraRig
extends Camera3D
## Port of updateCamera() + the camera presets from src/main.js: diorama / chase / side / drone /
## trackside... Orbit with Z / X or a mouse drag (or the right stick), zoom with the wheel or + / -.

const PRESETS := {
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

var game
var mode := "drone"
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
var pos_s := Vector3.ZERO
var pos_v := Vector3.ZERO
var pos_init := false
var t := 0.0
var dragging := false
var fov_boost := 0.0   # degrees added at speed (game.gd speed feel)

func _ready() -> void:
	near = 0.1
	far = 400.0
	fov = cam_fov

func set_mode(m: String) -> void:
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
	set_mode(ks[(ks.find(mode) + 1) % ks.size()])
	return PRESETS[mode].label

func snap_to(p: Vector3) -> void:
	target = p
	pos_init = false

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused: return
	var sens: float = Settings.get_v("mouse_sens")
	var inv := -1.0 if Settings.get_v("invert_y") else 1.0
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: dist = clampf(dist * 0.9, 4, 80)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: dist = clampf(dist * 1.1, 4, 80)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: dragging = e.pressed
	elif e is InputEventMouseMotion and dragging:
		orbit_t -= e.relative.x * 0.008 * sens   # grab the world: drag right turns the scene right (as in the garage)
		cam_pitch_t = clampf(cam_pitch_t + e.relative.y * 0.25 * sens * inv, 4, 85)
	elif e.is_action_pressed("cam_left") and e is InputEventKey: orbit_t -= PI / 4
	elif e.is_action_pressed("cam_right") and e is InputEventKey: orbit_t += PI / 4

func update_cam(dt: float) -> void:
	t += dt
	var st: BikePhysics = game.phys
	var P: Dictionary = PRESETS[mode]
	# analog camera (gamepad right stick) + zoom keys
	var ax := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ay := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(ax) > 0.2: orbit_t += ax * dt * 2.2
	if absf(ay) > 0.2: cam_pitch_t = clampf(cam_pitch_t + ay * dt * 60 * (-1.0 if Settings.get_v("invert_y") else 1.0), 4, 85)
	if Input.is_action_pressed("zoom_in"): dist = clampf(dist * (1 - dt * 1.2), 4, 80)
	if Input.is_action_pressed("zoom_out"): dist = clampf(dist * (1 + dt * 1.2), 4, 80)

	var f := Vector3(cos(st.heading), 0, -sin(st.heading))
	var drawn: Vector3 = game.drawn_pos
	var want: Vector3
	if st.crash_on and game.ragdoll:
		want = (game.ragdoll.p[Ragdoll.PELVIS] as Vector3).lerp(Vector3(st.x, st.y, st.z), 0.3) + Vector3(0, 0.3, 0)
	else:
		var k := 0.05 if P.get("mode", "") == "trackside" else (0.1 if P.get("drift", false) else 0.25)
		want = Vector3(drawn.x, drawn.y + 0.5, drawn.z) + f * clampf(st.v, -1, 10) * k
	target = target.lerp(want, minf(1.0, dt * (7.0 if P.get("drift", false) else P.get("lag", 5.0))))
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
			cam_yaw += BikePhysics.ang_diff(st.heading, cam_yaw) * minf(1.0, dt * P.get("rate", 1.4) * minf(1.0, absf(st.v) / 4))
		if P.has("spin"): orbit_t += P.spin * dt
		orbit += (orbit_t - orbit) * minf(1.0, dt * 8)
		cam_pitch += (cam_pitch_t - cam_pitch) * minf(1.0, dt * 8)
		var yaw := cam_yaw + orbit
		var pit := cam_pitch
		if P.get("drift", false):
			yaw += sin(t * 0.13) * 0.3; pit += sin(t * 0.09) * 4
		var back := Vector3(cos(yaw), 0, -sin(yaw))
		var need := 0.0
		while need < 46 and pit + need < 84 and _blocked(pit + need, back, drawn.y):
			need += 6
		occ += (need - occ) * minf(1.0, dt * (5.0 if need > occ else 0.7))
		pit = minf(84, pit + occ)
		var pr := deg_to_rad(pit)
		var want_pos := target - back * dist * cos(pr) + Vector3(0, dist * sin(pr), 0)
		if P.get("drift", false):
			if not pos_init:
				pos_s = want_pos; pos_v = Vector3.ZERO; pos_init = true
			var w := 2.4
			pos_v = (pos_v + (want_pos - pos_s) * w * w * dt) * exp(-2 * w * dt)
			pos_s += pos_v * dt
			if pos_s.distance_to(want_pos) > dist * 1.5: pos_s = want_pos
			global_position = pos_s
		else:
			global_position = want_pos; pos_init = false
		var gh: float = terrain.height(global_position.x, global_position.z) + 0.35
		if global_position.y < gh: global_position.y = gh
	cam_fov += (fov_t - cam_fov) * minf(1.0, dt * (6.0 if P.get("mode", "") == "trackside" else 3.0))
	fov = clampf(cam_fov * (1.0 + fov_boost / 34.0) + float(Settings.get_v("fov")), 5, 110)
	var sk: float = st.shake * float(Settings.get_v("cam_shake"))
	if sk > 0:
		global_position += Vector3(sin(t * 37) * sk * 0.12, sin(t * 29 + 1) * sk * 0.12, 0)
	st.shake = maxf(0.0, st.shake - dt * 1.2)
	if global_position.distance_to(target) > 0.01:
		look_at(target, Vector3.UP)

func _blocked(p_deg: float, back: Vector3, dy: float) -> bool:
	var pr := deg_to_rad(p_deg)
	var hx := -back.x * dist * cos(pr)
	var hz := -back.z * dist * cos(pr)
	var hy := dist * sin(pr)
	var y0 := dy + 0.6
	for i in range(1, 21):
		var u := i / 21.0
		var px := target.x + hx * u
		var pz := target.z + hz * u
		if game.terrain.height(px, pz) + 0.6 > y0 + (target.y + hy - y0) * u:
			return true
	return false
