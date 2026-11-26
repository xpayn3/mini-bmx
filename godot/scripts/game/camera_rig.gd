class_name CameraRig
extends Camera3D
## The ride cameras: trail (default) / helmet + bike POV / chase / drone / side /
## trackside... Orbit with Z / X or a mouse drag (or the right stick), zoom with the wheel or + / -.

## C / pad Y cycle in this order (the most used first, so the default is never far away)
const PRESETS := {
	# default: high drone-like view a little off to the side, turning with the trail AHEAD (not the bike)
	# and aiming past the rider so the rider sits low in the frame and you see what's coming
	"trail":     {"label": "Trail",      "dist": 10.5, "pitch": 18.0, "follow": true,  "fov": 52.0, "orbit": 0.2, "rate": 2.6, "ahead": true, "occ_max": 16.0},
	# POV from the action cam on top of the helmet (Rider.action_cam): wide lens, lightly stabilised
	"helmet":    {"label": "Helmet",  "mode": "helmet", "fov": 88.0},
	# POV from the action cam on the bike (BikeRig.action_cam: handlebar / fork leg), only in the cycle when one is mounted
	"bikecam":   {"label": "Bike", "mode": "helmet", "src": "bike", "fov": 92.0},
	# (2026-11-26, user: "our chase camera the same setup as Project X: zoom, FOV, framing, how it travels". Measured off their
	# footage: right behind, the rider centred and ~1/3 of the frame's height, ~1.7 m up looking ~12 deg down, ~78 deg wide (50
	# vertical at 16:9), swinging round with the bike quickly. Was 7 m / 16 deg / FOV 42 / rate 3.2)
	"chase":     {"label": "Chase",      "dist": 4.2,  "pitch": 17.0, "follow": true,  "fov": 50.0, "rate": 4.5},
	# a camera drone: slow + floaty, banks into turns, pitches with speed, hovers in the wind, OSD overlay
	"drone":     {"label": "Drone",      "dist": 22.0, "pitch": 36.0, "follow": true,  "fov": 34.0, "rate": 0.55, "lag": 1.4, "drift": true, "drone": true},
	"side":      {"label": "Side",       "dist": 14.0, "pitch": 10.0, "follow": true,  "fov": 28.0, "orbit": PI / 2, "rate": 2.5},
	"trackside": {"label": "Trackside",  "mode": "trackside", "fov": 14.0},
}
## the test playground only (levels): side-on views locked square to the lanes (they all run along +x: `follow`
## false + cam_yaw 0, `orbit` PI/2 puts the camera on the +z side looking -z, the bike crossing left to right). Picked
## from the dev view's camera dropdown or C (they come first there); "pg_side" is the playground's default
const LEVEL_PRESETS := {
	# (square: a reference side view: a FIXED angle a few degrees down (dead level, the jumps' near side batters hid the
	# wheels), never tilting after the rider, no bank, shake or speed zoom - side-on comparison shots. User, 2026-11-23)
	"pg_side":   {"label": "Side",       "dist": 12.0, "pitch": 8.0,  "follow": false, "fov": 42.0, "orbit": PI / 2, "lag": 4.0, "square": true},
	"pg_wide":   {"label": "Side wide",  "dist": 13.0, "pitch": 8.0,  "follow": false, "fov": 66.0, "orbit": PI / 2, "lag": 3.0, "square": true},
	"pg_low":    {"label": "Side low",   "dist": 6.5,  "pitch": 4.0,  "follow": false, "fov": 48.0, "orbit": PI / 2, "lag": 6.0, "square": true},
	"pg_front":  {"label": "Front 3/4",  "dist": 9.0,  "pitch": 10.0, "follow": false, "fov": 44.0, "orbit": PI * 0.78, "lag": 5.0},
}

## every view this ride can use: the level's own first (C cycles them in this order)
## (the merged level list is made once: this is read every frame)
var _presets_lv: Dictionary = {}
func presets() -> Dictionary:
	if game == null or str(game.get("level")) == "": return PRESETS
	if _presets_lv.is_empty():
		_presets_lv = LEVEL_PRESETS.duplicate()
		_presets_lv.merge(PRESETS)
	return _presets_lv

## title screen only (not in the C cycle): behind and above the rider, looking out over the landscape
const VISTA := {"label": "Lookout", "mode": "vista", "fov": 18.0, "back": 10.5, "up": 0.5, "side": -0.8, "look": 160.0, "drop": -0.03, "yaw_off": -1.95}
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
static var _OLD_CAMHEAD := OS.get_environment("BMX_OLD_CAMHEAD") != ""
var _hd_s := NAN   # the view's heading, turned at most camHeadingRate rad/s (smooths the air -> ground switch)
var _cy_prev := NAN; var _cy_max := 0.0   # tests: BMX_CAMYAW_PROBE
var cam_fov := 34.0
var occ := 0.0
var track_pos = null
var target := Vector3.ZERO
var _probe_on := Env.s("BMX_CAM_PROBE") != ""
const SHAKE_YAW := 0.026     # rad at full trauma (~1.5 deg)
const SHAKE_PITCH := 0.026
const SHAKE_ROLL := 0.044    # (~2.5 deg)
const SHAKE_RATE := 14.0     # noise per second: a quick shudder, not a wobble
var _shake_n: FastNoiseLite = null
var _OLD_SHAKE := Env.s("BMX_OLD_SHAKE") != ""
var _pp1 := Vector3.ZERO; var _pp2 := Vector3.ZERO; var _pa1 := Vector3.ZERO; var _pa2 := Vector3.ZERO
var _pn := 0; var _pj := 0.0; var _pk := 0; var _paj := 0.0; var _psh := 0
var _pw1 := 0.0; var _pw2 := 0.0; var _pwj := 0.0; var _pwmax := 0.0   # the camera's own height in the world (2nd difference)
var anchor := Vector3.ZERO   # what the camera is placed from (the rider); target = where it looks
var pos_s := Vector3.ZERO
var pos_v := Vector3.ZERO
var pos_init := false
var t := 0.0
var dragging := false
var fov_boost := 0.0   # degrees added at speed (game.gd speed feel)
var speed_feel := 0.0  # 0..1 how fast it feels (game.gd): the camera pulls in (dolly-zoom with the wider FOV),
                       # drops a little and banks into turns (no rumble: the user wants no shakes at speed)
var bank_s := 0.0
var pan_t := -100.0    # when the user last turned the camera (drag, Z / X, stick): re-centre waits for it
var follow_k := 1.0    # Settings "cam_follow": how quickly the camera turns after the rider
# drone feel: the airframe's own velocity / tilt (bank into turns, nose down with speed), wind noise
var dr_prev := Vector3.ZERO
var dr_vel := Vector3.ZERO
var dr_acc := Vector3.ZERO
var dr_roll := 0.0
var dr_tilt := 0.0
var dr_init := false
var osd: Control = null      # drone OSD overlay (DroneOSD), shown only in the Drone view
var helm_basis := Basis()    # Helmet cam: lightly stabilised orientation
var helm_init := false

func _ready() -> void:
	near = 0.1
	far = 400.0
	fov = cam_fov
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	osd = DroneOSD.new()
	osd.rig = self
	osd.visible = false
	layer.add_child(osd)

func preset() -> Dictionary:
	return VISTA if mode == "vista" else presets()[mode]

func set_mode(m: String) -> void:
	if m == "vista":
		mode = m; orbit = 0.0; orbit_t = 0.0; cam_pitch_t = 0.0; cam_pitch = 0.0
		return
	var all := presets()
	if not all.has(m): return
	var P: Dictionary = all[m]
	mode = m
	track_pos = null
	dr_init = false; helm_init = false
	if P.get("mode", "") == "helmet":   # crashed: the chase view takes over (PRESETS.chase), ready here
		dist = PRESETS.chase.dist; cam_pitch_t = PRESETS.chase.pitch; orbit_t = 0.0; orbit = 0.0
		return
	if P.get("mode", "") != "trackside":
		dist = P.dist; cam_pitch_t = P.pitch
		orbit_t = P.get("orbit", 0.0); orbit = orbit_t
	if not P.get("follow", false) and P.get("mode", "") != "trackside":
		cam_yaw = 0.0

func next_mode() -> String:
	var all := presets()
	var ks := all.keys()
	if not all.has(mode): mode = ks[ks.size() - 1]
	var i := ks.find(mode)
	for k in ks.size():   # skip the action cam views whose camera isn't mounted
		i = (i + 1) % ks.size()
		if _pov_lens(all[ks[i]]) != null or all[ks[i]].get("mode", "") != "helmet":
			break
	set_mode(ks[i])
	return all[mode].label + (" (default)" if mode == default_mode() else "")

## the view a ride starts in: the playground's side view, else the player's setting
func default_mode() -> String:
	if game != null and str(game.get("level")) != "": return "pg_side"
	return str(Settings.get_v("camera"))

## a respawn / teleport: drop every smoothed follow state so nothing glides over from the old spot
func snap_to(p: Vector3) -> void:
	target = p; anchor = p
	_ys_init = false
	pos_init = false
	trail_i = -1; trail_dir = Vector3.ZERO


## The bike's height as the camera follows it: bumps and impacts taken out, slopes and jumps kept. Two low-passes in a
## row (Y_TAU each), read as 2 * first - second: no lag on a steady climb / descent / flight, while a rock's 80 ms kick
## or a landing's compression comes through at about a sixth. The cameras used to ride the bike's own height (side /
## chase 0.2 s behind, trail 0.08 s): every bump moved the whole view, the bike stayed put in the frame and the world
## jumped instead - impacts looked harsher than they were, and glitchy
const Y_TAU := 0.28
var _ys1 := 0.0; var _ys2 := 0.0; var _ys_init := false
func _smooth_y(y: float, dt: float) -> float:
	if not _ys_init or absf(y - (2.0 * _ys1 - _ys2)) > 4.0:
		_ys1 = y; _ys2 = y; _ys_init = true
	var k := 1.0 - exp(-dt / Y_TAU)
	_ys1 += (y - _ys1) * k
	_ys2 += (_ys1 - _ys2) * k
	return 2.0 * _ys1 - _ys2

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused or (game and (game.photo or game.replay_on)): return   # photo mode drives the camera itself
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

const CRASH_ZOOM := 0.45     # how much closer the camera gets to a crashed rider (fraction of the distance)
const CRASH_ZOOM_T := 3.5    # real seconds the zoom-in takes
var crash_cam_t := 0.0       # real seconds since the crash began
var _crash_probe := Env.s("BMX_CRASHCAM") != ""
var crash_zoom := 0.0       # the current zoom-in on a crashed rider (0 = normal distance)

func update_cam(dt: float) -> void:
	t += dt
	var st: BikePhysics = game.phys
	var P: Dictionary = preset()
	if osd:
		osd.visible = P.get("drone", false) and game.hud != null and game.hud.visible
	if P.get("mode", "") == "vista":
		RenderingServer.global_shader_parameter_set("cam_see", Vector4.ZERO)
		_vista(dt, P)
		return
	if P.get("mode", "") == "helmet":
		if not (st.crash_on and game.ragdoll) and _helmet(dt, P):
			return
		P = PRESETS.chase   # crashed (or no rider yet): watch from behind
		helm_init = false
	# analog camera from the rebindable cam_* actions (the gamepad right stick moves the rider's body now)
	var pads := not Input.get_connected_joypads().is_empty()   # (allocates an array: once a frame)
	var ax := Input.get_axis("cam_left", "cam_right") if pads else 0.0
	var ay := Input.get_axis("cam_up", "cam_down")   # (also on keys: a rebound tilt key used to do nothing without a pad)
	follow_k = float(Settings.get_v("cam_follow"))
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_X): ax = 0.0   # keys turn in 45° steps (_unhandled_input)
	if absf(ax) > 0.2 or absf(ay) > 0.2: pan_t = t
	if absf(ax) > 0.2: orbit_t += ax * dt * 2.2
	if absf(ay) > 0.2: cam_pitch_t = clampf(cam_pitch_t + ay * dt * 60 * (-1.0 if Settings.get_v("invert_y") else 1.0), 4, 85)
	if Input.is_action_pressed("zoom_in"): dist = clampf(dist * (1 - dt * 1.2), 4, 80)
	if Input.is_action_pressed("zoom_out"): dist = clampf(dist * (1 + dt * 1.2), 4, 80)

	# in the air the camera goes the way the rider is flying (course), never the way the bike points:
	# a flat 180 / 360 spin turns the bike, not the view
	var hd: float = st.course if st.air and not is_nan(st.course) else st.heading
	# (2026-11-26, F8 seed 876814: "the last landing was a weird jolt": steer held in the air turned the bike 19 deg off its travel,
	# the view followed the travel, and at touch-down (the landing carve) it swung the 19 deg in ~0.1 s. A steered offset is the
	# rider's turn, not a spin: the view leans into it in the air (fading out past ~0.5 rad of slip and while a spin is held), so
	# there's nothing left to swing on landing. BMX_OLD_CAMHEAD=1 = before)
	if st.air and not is_nan(st.course) and not _OLD_CAMHEAD:
		var sl: float = BikePhysics.ang_diff(st.heading, st.course)
		var w_s: float = (1.0 - smoothstep(0.45, 0.8, absf(sl))) * (1.0 - clampf(absf(st.stick_yaw), 0.0, 1.0))
		hd = st.course + sl * w_s
	# (the switch between "the way he flies" in the air and "the way the bike points" on the ground used to jump by the whole
	# slip at touch-down: with steering in the air that is up to ~35 deg in one frame. Now the view's heading turns at most
	# camHeadingRate rad/s; 0 = the old jump. A jump past ~90 deg (respawn, a fakie landing) is taken at once)
	var hd_rate: float = float(Tune.v.get("camHeadingRate", 3.0))
	if hd_rate > 0.0 and not st.crash_on and Env.s("BMX_OLD_AIRSTEER") == "":
		if is_nan(_hd_s) or absf(BikePhysics.ang_diff(hd, _hd_s)) > 1.6: _hd_s = hd
		var hd_d: float = BikePhysics.ang_diff(hd, _hd_s)
		if not _OLD_CAMHEAD: hd_d *= 1.0 - exp(-10.0 * dt)   # (eased in, settles instead of stopping dead at the cap)
		_hd_s += clampf(hd_d, -hd_rate * dt, hd_rate * dt)
		hd = _hd_s
	else:
		_hd_s = hd
	var f := Vector3(cos(hd), 0, -sin(hd))
	var drawn: Vector3 = game.drawn_pos
	var ys := _smooth_y(drawn.y, dt)   # the bike's height without its bumps (see _smooth_y)
	var want: Vector3
	if st.crash_on and game.ragdoll:
		want = (game.ragdoll.p[Ragdoll.PELVIS] as Vector3) + Vector3(0, 0.3, 0)   # the body itself (the bike slides off on its own)
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
		var gy: float = game.terrain.deck_height(ap.x, ap.z)   # (the land: not the rocks lying on it)
		# never aim down into a hole beside / under the line: on a rope bridge the look point off the deck is the
		# canyon floor 16 m down (the view dived into the canyon); a real drop ahead still tips it down 3 m
		gy = maxf(gy, ys - 3.0)
		want = Vector3(ap.x, lerpf(ys, gy, 0.6) + 1.0, ap.z)
	else:
		var k := 0.05 if P.get("mode", "") == "trackside" else (0.1 if P.get("drift", false) else 0.25)
		want = Vector3(drawn.x, ys + 0.5, drawn.z) + f * clampf(st.v, -1, 10) * k
	# a crash: the view locks onto the ragdoll at once (real time: the slow motion shrinks dt ~5x), then
	# slowly closes in on the body
	var crashed: bool = st.crash_on and game.ragdoll != null
	var rdt: float = dt / clampf(Engine.time_scale, 0.1, 1.0)
	if crashed:
		crash_cam_t += rdt
		crash_zoom = CRASH_ZOOM * smoothstep(0.0, CRASH_ZOOM_T, crash_cam_t)
	else:   # up again / reset: ease back out to the normal distance
		crash_cam_t = 0.0
		crash_zoom += (0.0 - crash_zoom) * minf(1.0, rdt * 2.5)
	target = target.lerp(want, minf(1.0, (rdt * 18.0) if crashed else dt * (7.0 if P.get("drift", false) else P.get("lag", 5.0))))
	if P.get("ahead", false) and not (st.crash_on and game.ragdoll):
		# placed behind the RIDER (not behind the look point, which runs up to 14 m ahead)
		anchor = anchor.lerp(Vector3(drawn.x, ys + 1.0, drawn.z), minf(1.0, dt * 12.0)) if pos_init else Vector3(drawn.x, ys + 1.0, drawn.z)
	elif P.get("ahead", false):
		anchor = anchor.lerp(target, minf(1.0, rdt * 12.0))   # crash: straight over to the ragdoll
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
		elif bool(Settings.get_v("cam_recenter")) and t - pan_t > 2.5 and not dragging:
			# swing back to the preset angle a moment after the last drag / Z X / stick turn
			var k := minf(1.0, dt * 1.2)
			orbit_t += BikePhysics.ang_diff(float(P.get("orbit", 0.0)), orbit_t) * k
			cam_pitch_t += (float(P.pitch) - cam_pitch_t) * k
		orbit += (orbit_t - orbit) * minf(1.0, dt * 8)
		cam_pitch += (cam_pitch_t - cam_pitch) * minf(1.0, dt * 8)
		var yaw := cam_yaw + orbit + deg_to_rad(float(Settings.get_v("cam_side")))
		if Env.s("BMX_CAMYAW_PROBE") != "":
			if not is_nan(_cy_prev): _cy_max = maxf(_cy_max, absf(BikePhysics.ang_diff(yaw, _cy_prev)))
			_cy_prev = yaw
			if int(t) != int(t - dt):
				print("CAMYAW max_step_deg=%.2f" % rad_to_deg(_cy_max)); _cy_max = 0.0
		var pit := clampf(cam_pitch + float(Settings.get_v("cam_height")) - 4.0 * speed_feel, 2.0, 84.0)
		if P.get("square", false): pit = cam_pitch   # (level: no Settings height, no speed dip)
		var dist0 := dist
		# speed: in closer while the FOV widens (the rider stays the same size, the world rushes past)
		dist = dist0 * float(Settings.get_v("cam_dist")) * (1.0 - 0.3 * float(Settings.get_v("sfx_pull")) * speed_feel)   # the zoom the user set × the Settings distance
		if P.get("square", false): dist = dist0 * float(Settings.get_v("cam_dist"))
		dist *= 1.0 - crash_zoom   # crashed: slowly zooming in on the body (eases back out after a reset)
		if P.get("drift", false):
			yaw += sin(t * 0.13) * 0.3; pit += sin(t * 0.09) * 4
		var back := Vector3(cos(yaw), 0, -sin(yaw))
		var need := 0.0
		var occ_max: float = P.get("occ_max", 46.0)
		while not P.get("square", false) and need < occ_max and pit + need < 84 and _blocked(pit + need, back, ys, anchor):   # (the smoothed height: the bike's bumps flipped this on and off)
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
	if crashed and _crash_probe and int(crash_cam_t * 4.0) != int((crash_cam_t - rdt) * 4.0):   # BMX_CRASHCAM tests
		var pv: Vector3 = game.ragdoll.p[Ragdoll.PELVIS]
		print("CRASHCAM t=%.2f aim_to_pelvis=%.2f cam_to_pelvis=%.2f zoom=%.2f" % [crash_cam_t, target.distance_to(pv), global_position.distance_to(pv), crash_zoom])
	cam_fov += (fov_t - cam_fov) * minf(1.0, dt * (6.0 if P.get("mode", "") == "trackside" else 3.0))
	fov = clampf(cam_fov * (1.0 + fov_boost * float(Settings.get_v("cam_speed_fov")) / 34.0) + float(Settings.get_v("fov")), 5, 110)
	if P.get("square", false): fov = clampf(cam_fov + float(Settings.get_v("fov")), 5, 110)
	# impact shake (Eiserloh, "Juicing Your Cameras With Math", GDC 2016): the hit is "trauma" 0..1 (the physics' shake,
	# 0.45 = a full BONK), the shake is trauma^2 (small knocks all but vanish, big ones punch) and it TURNS the camera
	# (yaw / pitch / roll on smooth noise) instead of moving it: two sines moving the camera read as a glitch, and a
	# moved camera can end up in the ground. Applied after look_at below. BMX_OLD_SHAKE=1 = the old one
	var sk: float = st.shake * float(Settings.get_v("cam_shake"))
	if sk > 0 and _OLD_SHAKE:
		global_position += Vector3(sin(t * 37) * sk * 0.06, sin(t * 29 + 1) * sk * 0.06, 0)
	var trauma := clampf(sk / 0.45, 0.0, 1.0)
	st.shake = maxf(0.0, st.shake - dt * 1.2)
	if _probe_on:   # BMX_CAM_PROBE: how much the camera rattles (2nd difference per frame: position, aim)
		var po: Vector3 = global_position - game.drawn_pos
		var d2: Vector3 = po - 2.0 * _pp1 + _pp2
		var a2: Vector3 = target - 2.0 * _pa1 + _pa2
		var w2: float = global_position.y - 2.0 * _pw1 + _pw2
		if _pn > 2 and st.v > 8.0:
			_pwj += w2 * w2; _pwmax = maxf(_pwmax, absf(w2))
		_pw2 = _pw1; _pw1 = global_position.y
		if _pn > 2 and st.v > 8.0 and not st.air:
			_pj += d2.length_squared(); _pk += 1; _paj += (a2 / maxf(1.0, global_position.distance_to(target))).length_squared()
			if st.shake > 0.0: _psh += 1
		_pp2 = _pp1; _pp1 = po; _pa2 = _pa1; _pa1 = target; _pn += 1
	var aim := target
	if bool(Settings.get_v("cam_keep")) and not (st.crash_on and game.ragdoll):
		aim = _keep_rider_in_view(target, drawn + Vector3(0, 0.9, 0))
	if P.get("square", false) and not st.crash_on:
		# the same angle down whatever the rider does: towards him across, the preset's pitch down
		var hz := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		if hz.length_squared() > 1e-4:
			var pd := deg_to_rad(cam_pitch)
			look_at(global_position + hz.normalized() * cos(pd) - Vector3(0, sin(pd), 0), Vector3.UP)
	elif global_position.distance_to(aim) > 0.01:
		look_at(aim, Vector3.UP)
		# bank into the turn a little with speed (the horizon tips the way the rider leans)
		bank_s += (-st.bike_lean * 0.13 * speed_feel - bank_s) * minf(1.0, dt * 3.0)
		rotate_object_local(Vector3.BACK, bank_s)
		if trauma > 0.0 and not _OLD_SHAKE:
			if _shake_n == null:
				_shake_n = FastNoiseLite.new(); _shake_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; _shake_n.frequency = 1.0
			var amt := trauma * trauma
			var ts := t * SHAKE_RATE
			rotate_object_local(Vector3.UP, amt * SHAKE_YAW * _shake_n.get_noise_2d(ts, 11.0))
			rotate_object_local(Vector3.RIGHT, amt * SHAKE_PITCH * _shake_n.get_noise_2d(ts, 37.0))
			rotate_object_local(Vector3.BACK, amt * SHAKE_ROLL * _shake_n.get_noise_2d(ts, 73.0))
	if P.get("drone", false):
		_drone_feel(dt)
	# trees / rocks between the camera and the rider dissolve (deco.gdshader)
	var see: Vector3 = target if (st.crash_on and game.ragdoll) else drawn + Vector3(0, 0.9, 0)
	RenderingServer.global_shader_parameter_set("cam_see", Vector4(see.x, see.y, see.z, 1.0 if bool(Settings.get_v("cam_fade")) else 0.0))
	RenderingServer.global_shader_parameter_set("cam_eye", Vector4(global_position.x, global_position.y, global_position.z, 0.0))

## Drone: the camera hangs under a quadcopter. It hovers (slow bob + gusts), the airframe banks into
## its sideways acceleration and noses down as it speeds up; the gimbal only half cancels that, so the
## horizon leans in turns and the view dips on a chase. A little prop buzz on top.
func _drone_feel(dt: float) -> void:
	var p := global_position
	if not dr_init or dt <= 0.0:
		dr_prev = p; dr_vel = Vector3.ZERO; dr_acc = Vector3.ZERO; dr_roll = 0.0; dr_tilt = 0.0; dr_init = true
		return
	var v := (p - dr_prev) / dt
	dr_prev = p
	dr_acc = dr_acc.lerp((v - dr_vel) / dt, minf(1.0, dt * 3.0))
	dr_vel = dr_vel.lerp(v, minf(1.0, dt * 6.0))
	var right := global_basis.x
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	# bank: roll toward the sideways acceleration (+ a little toward the sideways speed), capped ~14°
	var lat := dr_acc.dot(right) * 0.022 + dr_vel.dot(right) * 0.006
	dr_roll += (clampf(lat, -0.25, 0.25) - dr_roll) * minf(1.0, dt * 2.5)
	# nose: down when speeding up / flying forward, up when braking
	var lon := dr_acc.dot(fwd) * 0.010 + dr_vel.dot(fwd) * 0.004
	dr_tilt += (clampf(lon, -0.12, 0.12) - dr_tilt) * minf(1.0, dt * 2.0)
	# hover: slow bob + wind gusts (sums of incommensurate sines = no visible loop)
	var gust := sin(t * 0.37) * sin(t * 0.23 + 1.3)
	global_position += Vector3(sin(t * 0.71) * 0.10 + gust * 0.18, sin(t * 0.9) * 0.12 + sin(t * 2.3) * 0.03, cos(t * 0.53) * 0.10)
	# prop buzz: tiny fast jitter, more in gusts
	var buzz := 0.0015 + absf(gust) * 0.002
	var jr := sin(t * 23.0) * buzz + sin(t * 31.7 + 2.0) * buzz * 0.6
	var jp := sin(t * 19.3 + 1.0) * buzz + sin(t * 27.1) * buzz * 0.5
	rotate_object_local(Vector3.FORWARD, dr_roll * 0.55 + gust * 0.03 + jr)
	rotate_object_local(Vector3.RIGHT, -dr_tilt * 0.5 + jp)


## Helmet cam: looks out of the action cam's lens on the rider's helmet, its orientation lightly
## stabilised (the head's jolts are softened, not removed). false = no rider / cam yet (orbit instead).
## the lens an action-cam view looks out of (P.src "bike" = the bike's, else the helmet's), null = none mounted
func _pov_lens(P: Dictionary) -> Node3D:
	if game == null: return null
	var owner_n = game.rig if P.get("src", "") == "bike" else game.rider
	if owner_n == null or not is_instance_valid(owner_n): return null
	var ac = owner_n.action_cam
	if ac == null or not is_instance_valid(ac): return null
	var lens: Node3D = ac.get_node_or_null("Body/Lens")
	return lens if lens != null and lens.is_inside_tree() else null

func _helmet(dt: float, P: Dictionary) -> bool:
	var lens := _pov_lens(P)
	if lens == null:
		return false
	var xf: Transform3D = lens.global_transform
	# head space +X = forward; a camera looks down -Z: camera z = -X, y = Y, x = y × z = +Z
	var b := Basis(xf.basis.z, xf.basis.y, -xf.basis.x).orthonormalized()
	if not helm_init:
		helm_basis = b; helm_init = true
	else:
		helm_basis = helm_basis.slerp(b, minf(1.0, dt * 14.0)).orthonormalized()
	global_transform = Transform3D(helm_basis, xf.origin)
	cam_fov += (float(lens.get_meta("fov", P.fov)) - cam_fov) * minf(1.0, dt * 3.0)   # the camera model / lens mod sets it
	fov = clampf(cam_fov * (1.0 + fov_boost * float(Settings.get_v("cam_speed_fov")) / 68.0) + float(Settings.get_v("fov")), 5, 120)
	var st: BikePhysics = game.phys
	st.shake = maxf(0.0, st.shake - dt * 1.2)
	RenderingServer.global_shader_parameter_set("cam_see", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("cam_eye", Vector4(xf.origin.x, xf.origin.y, xf.origin.z, 0.0))
	return true


func _exit_tree() -> void:
	if _probe_on and _pk > 0: print("CAMPROBE pos_jerk_mm=%.2f aim_jerk_mrad=%.2f shaking_frames=%d frames=%d  world_y_jerk_mm=%.2f worst_mm=%.1f" % [sqrt(_pj / _pk) * 1000.0, sqrt(_paj / _pk) * 1000.0, _psh, _pk, sqrt(_pwj / _pk) * 1000.0, _pwmax * 1000.0])
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
	# yaw_off turns the camera side-on: the bike points to the left of the frame, like a photo from a ridge
	var yaw := vista_yaw + float(P.get("yaw_off", 0.0)) + orbit + sin(t * 0.05) * 0.03
	var dir := Vector3(cos(yaw), 0, -sin(yaw))
	var right := Vector3(-dir.z, 0, dir.x)
	var base: Vector3 = game.drawn_pos
	var pos: Vector3 = base - dir * P.back + right * P.side + Vector3(0, P.up + sin(t * 0.21) * 0.25, 0)
	var gh: float = game.terrain.height(pos.x, pos.z) + (0.5 if game.scenic else 1.2)   # the title shot sits low: a hero angle
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
		# the LAND only (deck_height): a rock by the trail is no hill in the way (and it dissolves at the lens anyway).
		# With the rocks in, the side camera hopped a few cm a frame all through a rock garden
		# (0.4, not the 0.6 of y0: on flat ground the two were equal, and a suspension dip of 1 cm tripped it)
		if game.terrain.deck_height(px, pz) + 0.4 > y0 + (from.y + hy - y0) * u:
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
	# on / coming up to a rope bridge: look along the bridge, not the trail's line (it bows ~2 m off the deck)
	var ra = game.terrain.rope_aim(st.x, st.z, clampf(8.0 + absf(st.v) * 0.6, 8.0, 18.0)) if game.terrain else null
	if ra != null:
		var a := Vector3(ra.x - st.x, 0, ra.y - st.z)
		if a.length_squared() > 1.0 and a.normalized().dot(f) > 0.3:
			want = a.normalized()
	if trail_dir.length_squared() < 0.01:
		trail_dir = want
	else:
		trail_dir = trail_dir.slerp(want, minf(1.0, dt * 3.0)).normalized()
	return trail_dir
