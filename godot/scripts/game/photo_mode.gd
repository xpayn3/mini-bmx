class_name PhotoMode
extends CanvasLayer
## Photo mode (O): time stands still and the camera comes loose. Fly it anywhere round the rider
## (within RANGE), look, orbit, pan, dolly, roll and zoom, with mouse, keys or a pad; a side card sets the
## lens (field of view, depth of field: auto focus on the rider / pick a spot, aperture, bokeh), the light
## (time of day, sun direction / strength, exposure, haze), the look (filters, white balance, saturation,
## contrast, fade, vignette, grain, lens fringing) and the frame (aspect bars, composition grid, hide the
## rider / bike). Enter / F12 / pad A saves the shot (UI hidden, cropped to the frame) to
## user://screenshots/photo_<date>.png. Game.toggle_photo opens / closes it, Game._process calls update().
##
## Mouse: right drag = look, left drag = orbit the rider, middle (or shift + left) drag = pan,
## wheel = dolly, ctrl + wheel = zoom. Keys: WASD fly, Q / E down / up, Shift fast, Alt slow, arrows look,
## Z / X roll, - / = zoom, F focus under the cursor, G grid, R back to the start view, Tab / H hide the card.
## Pad: left stick fly, right stick look, LT / RT down / up, LB / RB roll, D-pad zoom, A shoot, X grid,
## Y hide the card, B leave.
## Tests: BMX_PHOTO_SET=key=val,... sets card values on open; BMX_PHOTO_FLY=dx,dy,dz,yaw_deg,pitch_deg moves
## the camera from where it opened; BMX_PHOTO_SNAP=1 saves a photo 0.6 s after opening (prints PHOTO).

const RANGE := 70.0          # how far from the rider the camera may fly
const SAVE_PATH := "user://photo.cfg"
const TABS := ["Camera", "Focus", "Light", "Look", "Frame"]
const FILTERS := ["None", "Black & white", "Sepia", "Vintage", "Teal & orange", "Noir", "Golden", "Cross process", "Bleach bypass"]
const ASPECTS := [["Screen", 0.0], ["16:9", 16.0 / 9.0], ["21:9 cinema", 2.39], ["3:2", 1.5], ["4:3", 4.0 / 3.0], ["1:1", 1.0], ["4:5 portrait", 0.8], ["9:16 story", 9.0 / 16.0]]
const GRIDS := ["None", "Thirds", "Golden ratio", "Centre cross", "Diagonals"]
const BOKEH := ["Circle", "Hexagon", "Box"]

## [key, label, default (null = taken from the game on open), min, max, step, unit, tab, kind (s slider / t toggle / o option), saved]
const DEFS := [
	["speed", "Fly speed", 4.0, 0.5, 25.0, 0.1, " m/s", "Camera", "s", true],
	["fov", "Field of view", null, 8.0, 110.0, 0.5, "°", "Camera", "s", false],
	["roll", "Roll / dutch angle", 0.0, -45.0, 45.0, 0.5, "°", "Camera", "s", false],
	["sens", "Look sensitivity", 1.0, 0.2, 3.0, 0.05, "×", "Camera", "s", true],
	["smooth", "Smooth moves", 1.0, 0.0, 1.0, 1.0, "", "Camera", "t", true],
	["dof", "Depth of field", 1.0, 0.0, 1.0, 1.0, "", "Focus", "t", true],
	["autofocus", "Auto focus on the rider", 1.0, 0.0, 1.0, 1.0, "", "Focus", "t", true],
	["focus", "Focus distance", null, 0.3, 120.0, 0.1, " m", "Focus", "s", false],
	["aperture", "Aperture (blur)", 0.35, 0.0, 1.0, 0.01, "", "Focus", "s", true],
	["depth", "In-focus depth", 2.0, 0.1, 30.0, 0.1, " m", "Focus", "s", true],
	["near_blur", "Blur the foreground too", 1.0, 0.0, 1.0, 1.0, "", "Focus", "t", true],
	["bokeh", "Bokeh shape", 0.0, 0.0, 2.0, 1.0, "", "Focus", "o", true],
	["time", "Time of day", null, 0.0, 24.0, 0.05, "h", "Light", "s", false],
	["sun_turn", "Sun direction", null, -180.0, 180.0, 1.0, "°", "Light", "s", false],
	["sun", "Sun strength", null, 0.0, 2.5, 0.05, "×", "Light", "s", false],
	["exposure", "Exposure", 1.0, 0.3, 3.0, 0.02, "×", "Light", "s", false],
	["haze", "Haze / fog", null, 0.0, 3.0, 0.05, "×", "Light", "s", false],
	["filter", "Filter", 0.0, 0.0, 8.0, 1.0, "", "Look", "o", true],
	["filter_amt", "Filter strength", 1.0, 0.0, 1.0, 0.01, "", "Look", "s", true],
	["saturation", "Saturation", 1.0, 0.0, 2.0, 0.01, "×", "Look", "s", true],
	["contrast", "Contrast", 1.0, 0.6, 1.6, 0.01, "×", "Look", "s", true],
	["brightness", "Brightness", 1.0, 0.5, 1.6, 0.01, "×", "Look", "s", true],
	["temp", "Temperature", 0.0, -1.0, 1.0, 0.01, "", "Look", "s", true],
	["tint", "Tint", 0.0, -1.0, 1.0, 0.01, "", "Look", "s", true],
	["fade", "Fade", 0.0, 0.0, 1.0, 0.01, "", "Look", "s", true],
	["vignette", "Vignette", 0.35, 0.0, 1.5, 0.01, "", "Look", "s", true],
	["grain", "Film grain", 0.0, 0.0, 1.0, 0.01, "", "Look", "s", true],
	["ca", "Lens fringing", 0.0, 0.0, 1.0, 0.01, "", "Look", "s", true],
	["aspect", "Frame", 0.0, 0.0, 7.0, 1.0, "", "Frame", "o", true],
	["grid", "Grid", 1.0, 0.0, 4.0, 1.0, "", "Frame", "o", true],
	["show_rider", "Show the rider", 1.0, 0.0, 1.0, 1.0, "", "Frame", "t", false],
	["show_bike", "Show the bike", 1.0, 0.0, 1.0, 1.0, "", "Frame", "t", false],
]

var game
var active := false
var V := {}            # current values
var _init_v := {}      # what the null defaults were on open (reset goes back to these)
var _rows := {}        # key -> {slider / check / option, value label}

# camera
var pos := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var vel := Vector3.ZERO
var _look_v := Vector2.ZERO   # smoothed look rate (pad / arrows)
var _start := {}              # the view photo mode opened with (R)
var _drag := 0                # 0 none, 1 look, 2 orbit, 3 pan
var _light_dirty := true
var _busy := false
var _base := {}               # the light's exposure / saturation / contrast / brightness before the look sliders
var _saved_dof := {}

# UI
var _ui: Control
var _card: PanelContainer
var _help: PanelContainer
var _overlay: Control
var _flash: ColorRect
var _status: Label
var _pages := {}
var _tab_btns := {}
var _ui_hidden := false
var _shots := 0
var _edit := false            # pad: Menu puts the D-pad / stick on the card (camera held), B / Menu back to the camera
var _nav: PadNav
var _help_l: Label
var _cur_tab := "Camera"

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	for d in DEFS:
		if d[2] != null: V[d[0]] = float(d[2])
	_load()
	_build_ui()
	visible = false

# ---------------------------------------------------------------- open / close

func open() -> void:
	active = true
	visible = true
	var cam: Camera3D = game.cam
	pos = cam.global_position
	var f := -cam.global_transform.basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = asin(clampf(f.y, -1.0, 1.0))
	vel = Vector3.ZERO
	LightSettings.ensure_loaded()
	var L: Dictionary = LightSettings.current
	_init_v = {"fov": snappedf(cam.fov, 0.5), "focus": snappedf(pos.distance_to(pivot()), 0.1),
		"time": float(L.time), "sun_turn": float(L.sun_turn), "sun": float(L.sun), "haze": float(L.haze)}
	for k in _init_v: V[k] = _init_v[k]
	V.roll = 0.0; V.exposure = 1.0; V.show_rider = 1.0; V.show_bike = 1.0
	_start = {"pos": pos, "yaw": yaw, "pitch": pitch, "fov": V.fov}
	var env: Environment = game.env
	_base = {"exposure": env.tonemap_exposure, "saturation": env.adjustment_saturation, "contrast": env.adjustment_contrast, "brightness": env.adjustment_brightness}
	_saved_dof = {"shape": ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_shape", 1),
		"quality": ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_bokeh_quality", 1),
		"jitter": ProjectSettings.get_setting("rendering/camera/depth_of_field/depth_of_field_use_jitter", false)}
	if game.cam.osd: game.cam.osd.visible = false   # the drone OSD (comes back with the drone view)
	_light_dirty = false   # the light as it is; only changed when a Light slider moves
	_refresh_rows()
	_apply_all()
	_set_ui_hidden(false)
	_status.text = "Saved photos go to the screenshots folder"
	_test_hooks()

func close() -> void:
	if not active: return
	_set_edit(false)
	active = false
	visible = false
	_drag = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.rider.visible = true
	game.rig.fit_g.visible = true
	var gm := game.grade_rect.material as ShaderMaterial
	gm.set_shader_parameter("photo", 0.0)
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(int(_saved_dof.get("shape", 1)))
	RenderingServer.camera_attributes_set_dof_blur_quality(int(_saved_dof.get("quality", 1)), bool(_saved_dof.get("jitter", false)))
	var env: Environment = game.env
	for k in _base: env.set("tonemap_exposure" if k == "exposure" else "adjustment_" + k, _base[k])
	_save()
	# the game re-applies its settings + the level light (Game.toggle_photo)

## what the camera orbits round and auto focuses on: the rider (the ragdoll after a crash)
func pivot() -> Vector3:
	if game.phys.crash_on and game.ragdoll and game.ragdoll.p.size() > 0:
		var s := Vector3.ZERO
		for p in game.ragdoll.p: s += p
		return s / game.ragdoll.p.size()
	return game.rig.global_position + Vector3(0, 1.05, 0)

# ---------------------------------------------------------------- per frame (real time)

func update(dt: float) -> void:
	if not active: return
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var fwd := -b.z
	var right := b.x
	# fly: keys + left stick, up / down on Q / E + triggers
	var mv := Vector3.ZERO
	var keys_ok := not _text_focus()
	if keys_ok:
		mv.z += _k(KEY_W) - _k(KEY_S)
		mv.x += _k(KEY_D) - _k(KEY_A)
		mv.y += _k(KEY_E) - _k(KEY_Q)
	var look := Vector2.ZERO
	if keys_ok:
		look.x += _k(KEY_LEFT) - _k(KEY_RIGHT)
		look.y += _k(KEY_UP) - _k(KEY_DOWN)
		V.roll = clampf(V.roll + (_k(KEY_X) - _k(KEY_Z)) * 40.0 * dt, -45.0, 45.0)
		if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD): _zoom(pow(0.4, dt))
		if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT): _zoom(pow(2.5, dt))
	if not Settings._test_run and not _edit:
		var lx := _axis(JOY_AXIS_LEFT_X); var ly := _axis(JOY_AXIS_LEFT_Y)
		mv.x += lx; mv.z -= ly
		mv.y += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
		look.x -= _axis(JOY_AXIS_RIGHT_X)
		look.y -= _axis(JOY_AXIS_RIGHT_Y) * (-1.0 if Settings.get_v("invert_y") else 1.0)
		V.roll = clampf(V.roll + (float(Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)) - float(Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER))) * 40.0 * dt, -45.0, 45.0)
		if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP): _zoom(pow(0.5, dt))
		if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN): _zoom(pow(2.0, dt))
	var sp: float = V.speed
	if Input.is_physical_key_pressed(KEY_SHIFT): sp *= 4.0
	if Input.is_physical_key_pressed(KEY_ALT): sp *= 0.25
	var want := (right * mv.x + fwd * mv.z + Vector3.UP * mv.y)
	if want.length() > 1.0: want = want.normalized()
	want *= sp
	var smooth: bool = V.smooth > 0.5
	vel = vel.lerp(want, 1.0 - exp(-dt * (9.0 if smooth else 60.0)))
	pos += vel * dt
	# look: arrows / right stick, eased; slower when zoomed in
	var zk: float = clampf(V.fov / 60.0, 0.2, 1.5) * V.sens
	_look_v = _look_v.lerp(look, 1.0 - exp(-dt * (10.0 if smooth else 60.0)))
	yaw += _look_v.x * 1.8 * zk * dt
	pitch = clampf(pitch + _look_v.y * 1.4 * zk * dt, -1.55, 1.55)
	_limit()
	_place()
	if V.autofocus > 0.5:
		V.focus = clampf(game.cam.global_position.distance_to(pivot()), 0.3, 120.0)
		_show_value("focus")
	_apply_dof()
	_show_value("roll"); _show_value("fov")
	_overlay.queue_redraw()

func _k(key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) else 0.0

func _axis(a: JoyAxis) -> float:
	var v := Input.get_joy_axis(0, a)
	return 0.0 if absf(v) < 0.15 else signf(v) * (absf(v) - 0.15) / 0.85

func _zoom(f: float) -> void:
	V.fov = clampf(V.fov * f, 8.0, 110.0)

## stay near the rider (the world is only built round them) and above the ground
func _limit() -> void:
	var pv := pivot()
	var d := pos - pv
	if d.length() > RANGE:
		pos = pv + d.normalized() * RANGE
		vel = Vector3.ZERO
	var gy: float = game.terrain.top_height(pos.x, pos.z) + 0.15
	if pos.y < gy:
		pos.y = gy
		vel.y = maxf(vel.y, 0.0)

func _place() -> void:
	var cam: Camera3D = game.cam
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, deg_to_rad(V.roll))), pos)
	cam.fov = V.fov

func _apply_dof() -> void:
	var ca: CameraAttributesPractical = game.cam_attr
	var on: bool = V.dof > 0.5 and V.aperture > 0.001
	var fd: float = V.focus
	var half: float = V.depth * 0.5
	ca.dof_blur_far_enabled = on
	ca.dof_blur_near_enabled = on and V.near_blur > 0.5
	ca.dof_blur_amount = V.aperture * 0.5
	ca.dof_blur_far_distance = fd + half
	ca.dof_blur_far_transition = maxf(0.5, fd * 0.6)
	ca.dof_blur_near_distance = maxf(0.05, fd - half)
	ca.dof_blur_near_transition = maxf(0.2, minf(fd - half, fd * 0.5))

func _apply_all() -> void:
	game.rider.visible = V.show_rider > 0.5
	game.rig.fit_g.visible = V.show_bike > 0.5   # the bike model only: the riding rider is a child of the rig too
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape([RenderingServer.DOF_BOKEH_CIRCLE, RenderingServer.DOF_BOKEH_HEXAGON, RenderingServer.DOF_BOKEH_BOX][int(V.bokeh)])
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_HIGH, true)
	if _light_dirty:
		_light_dirty = false
		var L: Dictionary = LightSettings.current.duplicate()
		for k in ["time", "sun_turn", "sun", "haze"]: L[k] = V[k]
		game._apply_light(V.time, L)
		var env0: Environment = game.env
		_base.exposure = env0.tonemap_exposure
		_base.saturation = env0.adjustment_saturation
		_base.contrast = env0.adjustment_contrast
	var env: Environment = game.env
	env.adjustment_enabled = true
	env.tonemap_exposure = _base.exposure * V.exposure
	env.adjustment_saturation = _base.saturation * V.saturation
	env.adjustment_contrast = _base.contrast * V.contrast
	env.adjustment_brightness = _base.brightness * V.brightness
	game.grade_rect.visible = true
	var gm := game.grade_rect.material as ShaderMaterial
	gm.set_shader_parameter("photo", 1.0)
	gm.set_shader_parameter("blur", 0.0)
	gm.set_shader_parameter("speed", 0.0)
	gm.set_shader_parameter("p_filter", int(V.filter))
	for k in ["filter_amt", "temp", "tint", "fade", "vignette", "grain", "ca"]:
		gm.set_shader_parameter("p_" + k, V[k])
	gm.set_shader_parameter("p_aspect", ASPECTS[int(V.aspect)][1])
	_place()
	_apply_dof()
	_overlay.queue_redraw()

# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if not active or _busy: return
	var handled := true
	if e is InputEventMouseButton and e.pressed:
		var mb := e as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT: _start_drag(1)
			MOUSE_BUTTON_LEFT: _start_drag(3 if mb.shift_pressed else 2)
			MOUSE_BUTTON_MIDDLE: _start_drag(3)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var s := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if mb.ctrl_pressed: _zoom(pow(1.08, s))
				else: _dolly(-s)
			_: handled = false
	elif e is InputEventKey and e.pressed and not e.echo:
		match (e as InputEventKey).physical_keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_F12: capture()
			KEY_TAB, KEY_H, KEY_F1: _set_ui_hidden(not _ui_hidden)
			KEY_F: _focus_at(_overlay.get_local_mouse_position())
			KEY_G: _set_value("grid", float((int(V.grid) + 1) % GRIDS.size()))
			KEY_R: _reset_view()
			KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_Z, KEY_X, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT, KEY_ALT, KEY_EQUAL, KEY_MINUS: pass
			_: handled = false
	elif e is InputEventKey:
		handled = false
	elif e is InputEventJoypadButton and e.pressed and (not Settings._test_run or Env.s("BMX_PAD") != ""):
		var bi := (e as InputEventJoypadButton).button_index
		if bi == JOY_BUTTON_START: _set_edit(not _edit)
		elif _edit: handled = false   # the card has the pad (PadNav: B = back to the camera)
		else: match bi:
				JOY_BUTTON_A: capture()
				JOY_BUTTON_B: game.toggle_photo()
				JOY_BUTTON_Y: _set_ui_hidden(not _ui_hidden)
				JOY_BUTTON_X: _set_value("grid", float((int(V.grid) + 1) % GRIDS.size()))
				_: handled = false
	else:
		handled = false
	if handled: get_viewport().set_input_as_handled()

## drags are started off the card (unhandled) but followed everywhere, also over the card
func _input(e: InputEvent) -> void:
	if not active or _drag == 0: return
	if e is InputEventMouseButton and not e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if _drag == 1: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_drag = 0
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		var r: Vector2 = e.relative
		var sens: float = float(Settings.get_v("mouse_sens")) * V.sens
		var inv := -1.0 if Settings.get_v("invert_y") else 1.0
		match _drag:
			1:   # look
				var zk: float = clampf(V.fov / 60.0, 0.2, 1.5)
				yaw -= r.x * 0.0028 * sens * zk
				pitch = clampf(pitch - r.y * 0.0028 * sens * zk * inv, -1.55, 1.55)
			2: _orbit(Vector2(r.x, r.y * inv) * sens)
			3: _pan(r)
		_limit()
		_place()
		get_viewport().set_input_as_handled()

func _start_drag(kind: int) -> void:
	_drag = kind
	if kind == 1: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## turn round the rider: drag right swings the camera left round them (grab the world)
func _orbit(r: Vector2) -> void:
	var pv := pivot()
	var off := pos - pv
	off = off.rotated(Vector3.UP, -r.x * 0.006)
	var right := Vector3.UP.cross(off).normalized()
	if right.length() > 0.5:
		var o2 := off.rotated(right, r.y * 0.005)
		var el := asin(clampf(o2.normalized().y, -1.0, 1.0))
		if el > -1.2 and el < 1.45: off = o2
	pos = pv + off
	var f := (pv - pos).normalized()
	yaw = atan2(-f.x, -f.z)
	pitch = asin(clampf(f.y, -1.0, 1.0))

## slide the camera sideways / up, more the further it is from what it looks at
func _pan(r: Vector2) -> void:
	var b: Basis = Basis.from_euler(Vector3(pitch, yaw, deg_to_rad(V.roll)))
	var k: float = maxf(0.6, pos.distance_to(pivot())) * 0.0016 * tan(deg_to_rad(V.fov) * 0.5) / tan(deg_to_rad(30.0))
	pos += (-b.x * r.x + b.y * r.y) * k

## the wheel: towards / away from what's ahead, in bigger steps further out
func _dolly(dir: float) -> void:
	var f := -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z
	pos += f * dir * clampf(pos.distance_to(pivot()) * 0.12, 0.15, 6.0)
	_limit()

func _reset_view() -> void:
	pos = _start.pos; yaw = _start.yaw; pitch = _start.pitch
	V.fov = _start.fov; V.roll = 0.0
	vel = Vector3.ZERO
	_place()

## F: focus on whatever is under the cursor (the rider if the ray passes them, else the ground)
func _focus_at(mp: Vector2) -> void:
	var cam: Camera3D = game.cam
	var vp_pos := mp * (Vector2(get_viewport().get_visible_rect().size) / _overlay.size) if _overlay.size.x > 0 else mp
	var o := cam.project_ray_origin(vp_pos)
	var d := cam.project_ray_normal(vp_pos)
	var pv := pivot()
	var tr := (pv - o).dot(d)
	var hit := -1.0
	if tr > 0.0 and (o + d * tr).distance_to(pv) < 0.9: hit = tr
	else:
		var s := 0.2
		while s < 160.0:
			var p := o + d * s
			if p.y <= game.terrain.top_height(p.x, p.z):
				hit = s; break
			s += maxf(0.1, s * 0.03)
	if hit < 0.0:
		_status.text = "Nothing to focus on there"
		return
	_set_value("autofocus", 0.0)
	_set_value("focus", clampf(hit, 0.3, 120.0))
	_status.text = "Focused at %.1f m" % hit

func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit

# ---------------------------------------------------------------- capture

func capture() -> void:
	if _busy or not active: return
	_busy = true
	var was_hidden := _ui_hidden
	_ui.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var a: float = ASPECTS[int(V.aspect)][1]
	if a > 0.01:
		var w := img.get_width(); var h := img.get_height()
		var r := Rect2i(0, 0, w, h)
		if a < float(w) / h:
			r.size.x = int(round(h * a)); r.position.x = (w - r.size.x) / 2
		else:
			r.size.y = int(round(w / a)); r.position.y = (h - r.size.y) / 2
		img = img.get_region(r)
	var dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(dir)
	var p := "%s/photo_%s.png" % [dir, Time.get_datetime_string_from_system().replace(":", "-")]
	if FileAccess.file_exists(p): p = p.replace(".png", "_%d.png" % _shots)
	var err := img.save_png(p)
	_shots += 1
	print("PHOTO ", ProjectSettings.globalize_path(p), " ", img.get_width(), "x", img.get_height(), " err=", err)
	_ui.visible = true
	_set_ui_hidden(was_hidden)
	_status.text = ("Saved %s" % p.get_file()) if err == OK else "Couldn't save the photo"
	# shutter flash
	_flash.color = Color(1, 1, 1, 0.75)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_flash, "color:a", 0.0, 0.35)
	_busy = false

# ---------------------------------------------------------------- values

func _set_value(k: String, v: float) -> void:
	V[k] = v
	var row: Dictionary = _rows.get(k, {})
	if row.has("slider"): (row.slider as HSlider).set_value_no_signal(v)
	if row.has("check"): (row.check as CheckButton).set_pressed_no_signal(v > 0.5)
	if row.has("option"): (row.option as OptionButton).select(int(v))
	_show_value(k)
	_changed(k)

func _changed(k: String) -> void:
	if k in ["time", "sun_turn", "sun", "haze"]: _light_dirty = true
	_apply_all()

func _show_value(k: String) -> void:
	var row: Dictionary = _rows.get(k, {})
	if not row.has("value"): return
	var d: Array = _def(k)
	var v: float = V[k]
	var txt := ""
	if k == "time": txt = LightSettings.clock(v)
	elif d[5] >= 1.0: txt = "%d%s" % [int(round(v)), d[6]]
	elif d[5] >= 0.1: txt = "%.1f%s" % [v, d[6]]
	else: txt = "%.2f%s" % [v, d[6]]
	(row.value as Label).text = txt
	if row.has("slider") and not (row.slider as HSlider).has_focus():
		(row.slider as HSlider).set_value_no_signal(v)

func _def(k: String) -> Array:
	for d in DEFS:
		if d[0] == k: return d
	return []

func _default(k: String) -> float:
	var d := _def(k)
	return float(_init_v.get(k, 0.0)) if d[2] == null else float(d[2])

func _refresh_rows() -> void:
	for k in _rows:
		var row: Dictionary = _rows[k]
		if row.has("slider"): (row.slider as HSlider).set_value_no_signal(V[k])
		if row.has("check"): (row.check as CheckButton).set_pressed_no_signal(V[k] > 0.5)
		if row.has("option"): (row.option as OptionButton).select(int(V[k]))
		_show_value(k)

func _reset_tab(tab: String) -> void:
	for d in DEFS:
		if d[7] == tab:
			V[d[0]] = _default(d[0])
			if d[0] in ["time", "sun_turn", "sun", "haze"]: _light_dirty = true
	if tab == "Camera": _reset_view()
	_refresh_rows()
	_apply_all()

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK: return
	for d in DEFS:
		if d[9] and cf.has_section_key("photo", d[0]):
			V[d[0]] = clampf(float(cf.get_value("photo", d[0])), d[3], d[4])

func _save() -> void:
	if Settings._test_run: return   # tests never change the player's photo settings
	var cf := ConfigFile.new()
	for d in DEFS:
		if d[9]: cf.set_value("photo", d[0], V[d[0]])
	cf.save(SAVE_PATH)

# ---------------------------------------------------------------- UI

func _set_ui_hidden(h: bool) -> void:
	_ui_hidden = h
	_card.visible = not h
	_help.visible = not h
	_help_text()

## pad: Menu = edit the card's settings (D-pad / stick rows, left / right change, LB / RB tabs, A press),
## B / Menu = back to flying the camera
func _set_edit(on: bool) -> void:
	_edit = on
	if not _nav: return
	_nav.enabled = on
	if on:
		if _ui_hidden: _set_ui_hidden(false)
		_nav.focus_first()
	else:
		var f := _card.get_viewport().gui_get_focus_owner()
		if f and _card.is_ancestor_of(f): f.release_focus()
	_help_text()

func _help_text() -> void:
	if not _help_l: return
	if Settings.pad_active or _edit:
		_help_l.text = ("D-pad / stick choose · ◀ ▶ change · LB / RB tab · A press · B / Menu done" if _edit else
			"LS fly · RS look · LT / RT down / up · LB / RB roll · D-pad zoom · A shoot · X grid · Y hide · Menu settings · B leave")
	else:
		_help_l.text = "WASD fly · Q/E down/up · Shift fast · right drag look · left drag orbit · middle drag pan · wheel dolly · Z/X roll · F focus · Enter shoot · Tab hide · O leave"

func _pad_tab(d: int) -> void:
	var i := wrapi(TABS.find(_cur_tab) + d, 0, TABS.size())
	(_tab_btns[TABS[i]] as Button).button_pressed = true
	_show_tab(TABS[i])

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UITheme.get_theme()
	add_child(_ui)
	_overlay = Overlay.new()
	_overlay.pm = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_overlay)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.08, 0.1, 0.86), 14, 14))
	_card.anchor_left = 1.0; _card.anchor_right = 1.0; _card.anchor_top = 0.0; _card.anchor_bottom = 1.0
	_card.offset_left = -376; _card.offset_right = -16; _card.offset_top = 16; _card.offset_bottom = -16
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_card.add_child(col)
	var head := HBoxContainer.new()
	var title := UITheme.label("PHOTO MODE", 20, UITheme.ACCENT, true)
	head.add_child(title)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UITheme.close_button(func(): game.toggle_photo()))
	col.add_child(head)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	var grp := ButtonGroup.new()
	for tname in TABS:
		var b := Button.new()
		b.text = tname
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(_show_tab.bind(tname))
		tabs.add_child(b)
		_tab_btns[tname] = b
	col.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	for tname in TABS:
		var pg := VBoxContainer.new()
		pg.add_theme_constant_override("separation", 6)
		pg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(pg)
		_pages[tname] = pg
	for d in DEFS:
		_add_row(_pages[d[7]], d)
	for tname in TABS:
		var pg: VBoxContainer = _pages[tname]
		var tip := ""
		match tname:
			"Camera": tip = "Right drag look · left drag orbit the rider · middle drag pan · wheel dolly · ctrl + wheel zoom · WASD fly, Q / E down / up · Z / X roll · R back to the start view"
			"Focus": tip = "F focuses on what's under the cursor (turns auto focus off)."
			"Light": tip = "Only for this photo: the ride's own light comes back when you leave."
			"Frame": tip = "Saved photos are cropped to the frame. G cycles the grid (never in the photo)."
		if tip != "":
			var l := UITheme.label(tip, 13, UITheme.MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(290, 0)
			pg.add_child(l)
		var rb := UITheme.button("Reset %s" % tname.to_lower(), _reset_tab.bind(tname), 14)
		rb.custom_minimum_size = Vector2(0, 32)
		pg.add_child(rb)

	var shoot := UITheme.button("Take photo  (Enter)", capture, 18)
	shoot.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
	shoot.add_theme_color_override("font_hover_color", Color(0, 0, 0))
	shoot.add_theme_color_override("font_pressed_color", Color(0, 0, 0))
	shoot.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT, 10, 10))
	shoot.add_theme_stylebox_override("hover", UITheme.box(UITheme.ACCENT.lightened(0.2), 10, 10))
	shoot.add_theme_stylebox_override("pressed", UITheme.box(UITheme.ACCENT.darkened(0.15), 10, 10))
	col.add_child(shoot)
	var row := HBoxContainer.new()
	var of := UITheme.button("Open folder", func():
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		OS.shell_open(ProjectSettings.globalize_path("user://screenshots")), 14)
	of.size_flags_horizontal = Control.SIZE_EXPAND_FILL; of.custom_minimum_size = Vector2(0, 34)
	row.add_child(of)
	var lv := UITheme.button("Leave  (O)", func(): game.toggle_photo(), 14)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lv.custom_minimum_size = Vector2(0, 34)
	row.add_child(lv)
	col.add_child(row)
	_status = UITheme.label("", 13, UITheme.MUTED)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_status)

	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.08, 0.1, 0.72), 10, 10))
	_help.anchor_top = 1.0; _help.anchor_bottom = 1.0
	_help.offset_left = 16; _help.offset_top = -44; _help.offset_bottom = -16
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := UITheme.label("", 13, Color(1, 1, 1, 0.8))
	_help.add_child(hl)
	_help_l = hl
	_help_text()
	_ui.add_child(_help)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	(_tab_btns["Camera"] as Button).button_pressed = true
	_show_tab("Camera")
	_nav = PadNav.attach(_card, {"tabs": _pad_tab, "back": _set_edit.bind(false), "style": "dark",
		"first": func(): return PadNav.find_focusable(_pages[_cur_tab])})
	_nav.enabled = false
	_card.get_viewport().gui_focus_changed.connect(func(c):   # flying, nothing on the card keeps focus (arrows / stick)
		if c and _card.is_ancestor_of(c) and not _edit: c.release_focus.call_deferred())

func _show_tab(tname: String) -> void:
	_cur_tab = tname
	for k in _pages: (_pages[k] as Control).visible = k == tname

func _add_row(parent: VBoxContainer, d: Array) -> void:
	var k: String = d[0]
	var row := {}
	match d[8]:
		"t":
			var c := CheckButton.new()
			c.text = d[1]
			c.add_theme_font_size_override("font_size", 15)
			c.toggled.connect(func(on: bool):
				V[k] = 1.0 if on else 0.0
				_changed(k))
			parent.add_child(c)
			row.check = c
		"o":
			var h := HBoxContainer.new()
			var l := UITheme.label(d[1], 15, UITheme.MUTED)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			var ob := OptionButton.new()
			ob.add_theme_font_size_override("font_size", 15)
			var items: Array = FILTERS if k == "filter" else (GRIDS if k == "grid" else (BOKEH if k == "bokeh" else ASPECTS.map(func(a): return a[0])))
			for it in items: ob.add_item(it)
			ob.custom_minimum_size = Vector2(170, 0)
			ob.item_selected.connect(func(i: int):
				V[k] = float(i)
				_changed(k))
			h.add_child(ob)
			h.set_meta("nav_row", true)
			parent.add_child(h)
			row.option = ob
		_:
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 0)
			var h := HBoxContainer.new()
			var l := UITheme.label(d[1], 15, UITheme.MUTED)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			h.add_child(l)
			var vl := UITheme.label("", 15)
			h.add_child(vl)
			var s := HSlider.new()
			s.min_value = d[3]; s.max_value = d[4]; s.step = d[5]
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.value_changed.connect(func(v: float):
				V[k] = v
				if k == "focus" and V.autofocus > 0.5: _set_value("autofocus", 0.0)
				_show_value(k)
				_changed(k))
			var rb := UITheme.reset_button(null, 0.0)
			rb.pressed.connect(func(): _set_value(k, _default(k)))
			h.add_child(rb)
			box.add_child(h)
			box.add_child(s)
			box.set_meta("nav_row", true)
			parent.add_child(box)
			row.slider = s
			row.value = vl
	_rows[k] = row

# ---------------------------------------------------------------- tests

func _test_hooks() -> void:
	var set_s := Env.s("BMX_PHOTO_SET")
	if set_s != "":
		for kv in set_s.split(","):
			var p := kv.split("=")
			if p.size() == 2 and V.has(p[0]): _set_value(p[0], float(p[1]))
	var fly := Env.s("BMX_PHOTO_FLY")
	if fly != "":
		var f := fly.split(",")
		pos += Vector3(float(f[0]), float(f[1]), float(f[2]))
		if f.size() > 3: yaw += deg_to_rad(float(f[3]))
		if f.size() > 4: pitch = clampf(pitch + deg_to_rad(float(f[4])), -1.55, 1.55)
		_limit(); _place()
	if Env.s("BMX_PHOTO_ORBIT") != "":   # tests: swing round the rider like a left drag
		_orbit(Vector2(float(Env.s("BMX_PHOTO_ORBIT")), 0.0)); _limit(); _place()
	if Env.s("BMX_PHOTO_TAB") != "":
		(_tab_btns[Env.s("BMX_PHOTO_TAB")] as Button).button_pressed = true
		_show_tab(Env.s("BMX_PHOTO_TAB"))
	if Env.s("BMX_PHOTO_SNAP") != "":
		await get_tree().create_timer(0.6, true, false, true).timeout
		capture()

# ---------------------------------------------------------------- overlay: grid + focus mark (never in the photo)

class Overlay extends Control:
	var pm

	func _frame() -> Rect2:
		var s := size
		var a: float = PhotoMode.ASPECTS[int(pm.V.aspect)][1]
		if a <= 0.01: return Rect2(Vector2.ZERO, s)
		if a < s.x / s.y:
			var w := s.y * a
			return Rect2((s.x - w) * 0.5, 0, w, s.y)
		var h := s.x / a
		return Rect2(0, (s.y - h) * 0.5, s.x, h)

	func _draw() -> void:
		if pm == null or not pm.active: return
		var r := _frame()
		var c := Color(1, 1, 1, 0.35)
		match int(pm.V.grid):
			1:
				for i in [1, 2]:
					var x: float = r.position.x + r.size.x * i / 3.0
					var y: float = r.position.y + r.size.y * i / 3.0
					draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), c, 1.0)
					draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), c, 1.0)
			2:
				for f in [0.382, 0.618]:
					var x: float = r.position.x + r.size.x * f
					var y: float = r.position.y + r.size.y * f
					draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), c, 1.0)
					draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), c, 1.0)
			3:
				var m := r.get_center()
				draw_line(m - Vector2(24, 0), m + Vector2(24, 0), c, 1.5)
				draw_line(m - Vector2(0, 24), m + Vector2(0, 24), c, 1.5)
			4:
				draw_line(r.position, r.end, c, 1.0)
				draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), c, 1.0)
		# auto focus: brackets round the rider
		if pm.V.autofocus > 0.5 and pm.V.dof > 0.5:
			var cam: Camera3D = pm.game.cam
			var pv: Vector3 = pm.pivot()
			if not cam.is_position_behind(pv):
				var sp := cam.unproject_position(pv) * (size / Vector2(get_viewport().get_visible_rect().size))
				var hs := 26.0
				var bc := Color(UITheme.ACCENT, 0.85)
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						var cn := sp + Vector2(sx, sy) * hs
						draw_line(cn, cn - Vector2(sx * 9, 0), bc, 2.0)
						draw_line(cn, cn - Vector2(0, sy * 9), bc, 2.0)
