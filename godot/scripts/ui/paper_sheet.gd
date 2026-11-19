class_name PaperSheet
extends CanvasLayer
## A folded sheet of paper that comes up in front of the camera and unfolds like a real map: first the half
## fold (rows = 2), then the accordion (cols, must be even), the panel nearest the cover first. Whatever is
## printed on it is a Control in `page` (a SubViewport): the front print fills page_size, the cover (printed on
## the back of the outermost panel, the one you see while it is folded) sits in a strip below it.
## Used by the trail map (ui/paper_map.gd) and meant for paper menus:
##   var s := PaperSheet.new(); s.cols = 2; s.rows = 1; s.live = true
##   add_child(s); s.setup(Vector2i(1400, 1000), Vector2i(700, 1000))
##   s.content.add_child(my_menu_control)          # front: Rect2(0, 0, page_size); cover: below it
##   s.close_actions = ["pause"]; s.closed.connect(...); s.open()
## live = true: the page re-renders every frame and mouse / keys / pad go to it (clicks are traced onto the
## folded paper, so buttons work wherever they are on the sheet); live = false: call `await bake()` after
## drawing and it is printed once, with mipmaps (sharpest, cheapest). Paper = a real scan (ambientCG
## Paper003, CC0, assets/textures/paper/). It renders in its own small 3D world (own light, no fog / blur /
## time of day) over everything, with the game behind it blurred and darkened. Times are real time, so it
## works with Engine.time_scale = 0.

signal opened
signal closed
signal close_requested               # one of close_actions was pressed


@export var cols := 4                # panels across (even for unfolding: the outer panel lies face down, its back = the cover)
@export var rows := 2                # 1 or 2
@export var panel := Vector2(0.21, 0.2625)   # one panel (m)
@export var open_t := 1.0            # by then it counts as open (the springs may still wobble)
@export var close_t := 0.45
@export var tempo := 1.0                      # < 1 = slower: every spring and the whole timeline (the map: 0.4)
@export var fill := Vector2(0.86, 0.84)       # share of the screen the open sheet may take
@export var tint := Color(1.02, 0.985, 0.92)  # the paper's colour (x the scan); kraft paper for menus etc.
@export var live := false
@export var hold_roll := 0.0                  # held a little crooked (rad), for charm
@export var unfold := true                    # false: it comes up and stays folded, showing the cover (a pamphlet)
@export var auto_close := true                # close_actions fold it away (false: just close_requested)
@export var dim := 1.0                        # how much the game behind is blurred / darkened
var close_actions: Array[StringName] = []     # actions that fold it away again (handled here, never reach the game)

var page: SubViewport                # what's printed: front (page_size) + cover strip below
var content: Control                 # add your print here (sized to the whole page viewport)
var page_size := Vector2i.ZERO
var cover_size := Vector2i.ZERO

var state := 0                       # 0 put away, 1 unfolding, 2 open, 3 folding
var k := 0.0                         # 0 put away .. 1 open
var shots := ""                      # tests: dir/prefix -> its own render while it unfolds
var freeze_at := float(OS.get_environment("BMX_PAPER_AT")) if OS.get_environment("BMX_PAPER_AT") != "" else -1.0   # tests: stop the animation at t s

const EPS_C := 0.055                 # the folds never shut completely: the stack fans a little (rad)
const EPS_R := 0.04

var _vp: SubViewport
var _cam: Camera3D
var _sheet: Node3D
var _panels := []                    # [col][row] MeshInstance3D
var _view: TextureRect
var _dim: ColorRect
var _mat: ShaderMaterial
var _tex: Texture2D
var _sound: AudioStreamPlayer
var sound_stream: AudioStream        # set before add_child: a recording to play slices of (null = the synthesised rustle)
var sound_db := -6.0
var _snd_t := -1.0                   # seconds into the current slice (-1 = silent)
var _snd_len := 0.0                  # how long this slice plays (it fades out over its last 40 %)
var _last_us := 0
var _idle := 0.0
var _shot_i := 0
var _shot_next := 0.0


func _ready() -> void:
	layer = 7                         # over the HUD and the WASTED screen
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## build it (once): page_size = the front print in pixels (keep its aspect = the sheet's), cover_size = the
## cover's pixels (aspect = one panel's), drawn in a strip under the front
func setup(p_size: Vector2i, c_size := Vector2i.ZERO) -> void:
	# (cols even: the outer panel lies face down and carries the cover on its back; odd cols only for a sheet
	# that stays folded - its outer panel faces you, so print the cover on the front, in that panel's part)
	assert((cols % 2 == 0 or not unfold) and rows >= 1 and rows <= 2, "PaperSheet: cols even (or unfold off), rows 1 or 2")
	page_size = p_size
	cover_size = c_size
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = _blur_shader()
	_dim.material = dm
	add_child(_dim)
	# the page
	page = SubViewport.new()
	page.size = Vector2i(p_size.x, p_size.y + c_size.y)
	page.disable_3d = true
	page.transparent_bg = false
	page.gui_embed_subwindows = true
	page.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(page)
	content = Control.new()
	content.size = Vector2(page.size)
	content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	page.add_child(content)
	# the 3D world it unfolds in
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()   # soft warm light from the upper left: the folds shade each other
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	key.shadow_bias = 0.01
	key.shadow_normal_bias = 0.5
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 4.0
	_vp.add_child(key)
	key.look_at_from_position(Vector3(-0.9, 1.4, 1.3), Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.near = 0.02
	_vp.add_child(_cam)
	_sheet = Node3D.new()
	_vp.add_child(_sheet)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/paper_sheet.gdshader")
	_mat.set_shader_parameter("paper_tex", load("res://assets/textures/paper/paper_color.jpg"))
	_mat.set_shader_parameter("paper_nrm", load("res://assets/textures/paper/paper_normal.jpg"))
	_mat.set_shader_parameter("paper_rough", load("res://assets/textures/paper/paper_rough.jpg"))
	_mat.set_shader_parameter("sheet_cells", Vector2(cols, rows))
	_mat.set_shader_parameter("panel_aspect", panel.x / panel.y)
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	var ph := float(page.size.y)
	_mat.set_shader_parameter("page_v", p_size.y / ph)
	_mat.set_shader_parameter("cover_rect", Vector4(0, p_size.y / ph, float(c_size.x) / p_size.x, c_size.y / ph))
	_mat.set_shader_parameter("has_cover", 1.0 if c_size.y > 0 else 0.0)
	for c in cols:
		var col := []
		for r in rows:
			var q := QuadMesh.new()   # hinged at its left edge; top row above y = 0, bottom row below
			q.size = panel
			q.subdivide_width = 10
			q.subdivide_depth = 12
			var y0 := 0.0 if rows == 1 else (0.5 if r == 0 else -0.5)
			q.center_offset = Vector3(panel.x * 0.5, panel.y * y0, 0)
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			mi.set_instance_shader_parameter("cell", Vector2(c, r))
			mi.set_instance_shader_parameter("cover", 1.0 if (c == cols - 1 and r == 0) else 0.0)
			mi.set_instance_shader_parameter("pillow", 0.0)
			_sheet.add_child(mi)
			col.append(mi)
		_panels.append(col)
	_view = TextureRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture = _vp.get_texture()
	add_child(_view)
	_sound = AudioStreamPlayer.new()
	_sound.stream = sound_stream if sound_stream else rustle_sound()
	_sound.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_sound.volume_db = sound_db
	add_child(_sound)
	if live: _use_texture(page.get_texture())


## print the page once (live = false): renders it, keeps it with mipmaps
func bake() -> void:
	page.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := page.get_texture().get_image()
	img.generate_mipmaps()
	_use_texture(ImageTexture.create_from_image(img))


func _use_texture(t: Texture2D) -> void:
	_tex = t
	_mat.set_shader_parameter("print_tex", t)


func is_open() -> bool:
	return state == 1 or state == 2


func busy() -> bool:
	return state != 0


func open() -> void:
	if state == 1 or state == 2: return
	if state == 0:
		for sp in _springs(): sp.x = 0.0; sp.v = 0.0
	state = 1
	_tl = 0.0
	_reset_view()
	visible = true
	_fit_camera()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if live: page.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_last_us = Time.get_ticks_usec()
	_shot_i = 0; _shot_next = _idle
	_play_slice(1.15, 1.1 / tempo)
	_pose()


func close(now := false) -> void:
	if state == 0: return
	if now:
		_put_away(); return
	if state == 3: return
	state = 3
	_tl = 0.0
	_play_slice(1.4, 0.55 / tempo)


## a slice of the sound: a recording plays from a random spot (no two unfolds sound the same), faded out
## by the end; the synthesised rustle plays from its start
func _play_slice(pitch: float, secs: float) -> void:
	_sound.pitch_scale = pitch
	var from := 0.0
	var total := _sound.stream.get_length()
	if sound_stream and total > secs * pitch + 0.2:
		from = randf() * (total - secs * pitch - 0.1)
	elif not sound_stream and secs < 1.0:
		from = 0.3
	_snd_len = secs
	_snd_t = 0.0
	_sound.volume_db = sound_db
	_sound.play(from)


func _sound_fade(dt: float) -> void:
	if _snd_t < 0.0: return
	_snd_t += dt
	var tail := clampf((_snd_len - _snd_t) / (_snd_len * 0.4), 0.0, 1.0)
	_sound.volume_db = sound_db + linear_to_db(maxf(tail, 0.001))
	if _snd_t >= _snd_len:
		_sound.stop(); _snd_t = -1.0


func _put_away() -> void:
	state = 0; k = 0.0
	visible = false
	_sound.stop(); _snd_t = -1.0
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	page.render_target_update_mode = SubViewport.UPDATE_DISABLED
	closed.emit()


## every move is a little spring (lift, the half fold, each accordion crease): a target 0 / 1 set on a
## timeline, underdamped so it overshoots past flat and wobbles to rest - snappy, not eased
class Spring:
	var x := 0.0
	var v := 0.0
	var target := 0.0
	func step(dt: float, hz: float, zeta: float, floor_bounce: bool) -> void:
		var w := TAU * hz
		var n := 4                                 # substeps: stiff springs at 30 fps stay stable
		var h := dt / n
		for i in n:
			v += (w * w * (target - x) - 2.0 * zeta * w * v) * h
			x += v * h
			if floor_bounce and x < 0.0:           # folding shut: paper stops on paper, a small bounce
				x = 0.0; v = -v * 0.25

var _lift := Spring.new()
var _row := Spring.new()
var _acc := []                       # one Spring per column (index 0 unused: no crease left of it)
var _tl := 0.0                       # seconds since open / close started

func _springs() -> Array:
	if _acc.is_empty():
		for c in cols: _acc.append(Spring.new())
	return [_lift, _row] + _acc


## the timeline: when each spring is told to go (opening: lift, half fold, then the accordion from the
## outer panel in; closing: the other way round)
func _drive() -> void:
	_springs()
	var tl := _tl * tempo
	if (state == 1 or state == 2) and not unfold:
		_lift.target = 1.0
		_row.target = 1.0 if rows == 1 else 0.0
	elif state == 1 or state == 2:
		_lift.target = 1.0
		_row.target = 1.0 if (rows == 1 or tl > 0.1) else 0.0
		var t0 := 0.26 if rows == 2 else 0.12
		for c in range(1, cols):
			_acc[c].target = 1.0 if tl > t0 + 0.085 * (cols - 1 - c) else 0.0
	else:
		for c in range(1, cols):
			_acc[c].target = 0.0 if tl > 0.05 * (c - 1) else 1.0
		var tr := 0.05 * (cols - 1)
		_row.target = 0.0 if (rows == 2 and tl > tr) else 1.0
		_lift.target = 0.0 if tl > tr + (0.12 if rows == 2 else 0.0) else 1.0


func _process(_dt: float) -> void:
	if state == 0: return
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_us) / 1e6, 0.05)
	_last_us = now
	if freeze_at >= 0.0 and _tl + dt > freeze_at: dt = maxf(0.0, freeze_at - _tl)   # tests: hold that moment
	_idle += dt
	_tl += dt
	_sound_fade(dt)
	_drive()
	var opening := state != 3
	# opening: lively (overshoot ~10 % = a flap swings ~20 deg past flat and back); closing: firmer
	_lift.step(dt, (2.8 if opening else 3.4) * tempo, 0.62 if opening else 0.85, false)
	_row.step(dt, 3.6 * tempo, 0.55 if opening else 0.75, not opening)
	for c in range(1, cols):
		_acc[c].step(dt, (3.3 + 0.2 * c) * tempo, 0.52 if opening else 0.75, not opening)
	k = clampf(_lift.x, 0.0, 1.0)
	if state == 1 and _tl * tempo > open_t:
		state = 2; opened.emit()
	elif state == 3 and _tl * tempo > close_t and _lift.x < 0.03:
		_put_away(); return
	if _vp.size != Vector2i(get_window().size): _fit_camera()
	_pose()
	if handheld: _hand_controls(dt)
	if shots != "" and state != 3 and _idle >= _shot_next and _shot_i < 20:
		_shot_next = _idle + 0.1
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shots, _shot_i])   # the last frame on screen (BMX_OFFSCREEN: minimised windows draw late)
		print("PAPERSHOT %s_%d.png t=%.2f lift=%.2f" % [shots, _shot_i, _tl, _lift.x])
		_shot_i += 1


# ------------------------------------------------------------------ input

func _input(e: InputEvent) -> void:
	if state == 0 or state == 3 or not visible: return   # folding away: the game has its input back
	for a in close_actions:
		if e.is_action_pressed(a) and not e.is_echo():
			get_viewport().set_input_as_handled()
			close_requested.emit()
			if auto_close: close()
			return
	if handheld and (state == 1 or state == 2) and e is InputEventMouse:
		_hand_mouse(e)
	if live and (state == 2 or (state == 1 and _lift.x > 0.85)):
		if e is InputEventMouse:
			var at := page_point(_screen_px(e.position))
			if at.x < 0.0: return   # off the paper: let it through
			var fe: InputEventMouse = e.duplicate()
			fe.position = at; fe.global_position = at
			page.push_input(fe, true)
		else:
			page.push_input(e)
	get_viewport().set_input_as_handled()   # nothing reaches the game while the paper is up


## the root viewport's (stretched) coordinates -> window pixels (= the 3D view's)
func _screen_px(p: Vector2) -> Vector2:
	var vr := get_viewport().get_visible_rect().size
	return p * Vector2(get_window().size) / vr


## where a screen pixel lands on the printed page (px), or (-1, -1) off the paper. Traced onto every panel
## as it lies now (folds, tilt), the nearest one wins.
func page_point(sp: Vector2) -> Vector2:
	var o := _cam.project_ray_origin(sp)
	var d := _cam.project_ray_normal(sp)
	var best := INF
	var out := Vector2(-1, -1)
	for c in cols:
		for r in rows:
			var mi: MeshInstance3D = _panels[c][r]
			var inv := mi.global_transform.affine_inverse()
			var lo: Vector3 = inv * o
			var ld: Vector3 = inv.basis * d
			if absf(ld.z) < 1e-6: continue
			var t := -lo.z / ld.z
			if t <= 0.0 or t >= best: continue
			var h := lo + ld * t
			var y0 := 0.0 if rows == 1 else (0.5 if r == 0 else -0.5)
			var u := h.x / panel.x
			var v := 0.5 - (h.y / panel.y - y0)
			if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0: continue
			best = t
			if ld.z > 0.0:   # its back: only the cover is printed there (mirrored, as the shader draws it)
				out = Vector2((1.0 - u) * cover_size.x, page_size.y + v * cover_size.y) if (c == cols - 1 and r == 0 and cover_size.y > 0) else Vector2(-1, -1)
			else:
				out = Vector2((c + u) / cols * page_size.x, (r + v) / rows * page_size.y)
	return out


# ------------------------------------------------------------------ the fold

## the camera sees the open sheet with a margin, whatever the window shape
func _fit_camera() -> void:
	var vs := Vector2i(get_window().size)
	_vp.size = vs
	var asp := float(vs.x) / maxf(1.0, vs.y)
	var th := tan(deg_to_rad(_cam.fov) * 0.5)
	var sz := Vector2(cols * panel.x, rows * panel.y) if unfold else panel   # folded: one panel
	var dw := (sz.x / fill.x) * 0.5 / (th * asp)
	var dh := (sz.y / fill.y) * 0.5 / th
	_cam_d = maxf(dw, dh)
	_cam.position = Vector3(_pan.x, _pan.y, _cam_d / _zoom)
	_cam.rotation = Vector3.ZERO


# ------------------------------------------------------------------ held in the hands (handheld = true)
## pad: right stick tilts the sheet a little, RT / LT zoom in / out, left stick pans while zoomed;
## keys: W / S zoom, A / D pan; mouse: wheel zooms, drag pans. All eased; reset each time it opens.
@export var handheld := false
const TILT_MAX := 0.3                # rad
const ZOOM_MAX := 3.0
var _cam_d := 1.0                    # camera distance that fits the sheet
var _zoom := 1.0
var _zoom_t := 1.0
var _pan := Vector2.ZERO
var _pan_t := Vector2.ZERO
var _tilt := Vector2.ZERO
var _drag := false

func _reset_view() -> void:
	_zoom = 1.0; _zoom_t = 1.0; _pan = Vector2.ZERO; _pan_t = Vector2.ZERO; _tilt = Vector2.ZERO; _drag = false


func _hand_controls(dt: float) -> void:
	var tilt_t := Vector2.ZERO
	if state == 1 or state == 2:
		tilt_t = Vector2(Input.get_action_strength("body_right") - Input.get_action_strength("body_left"),
			Input.get_action_strength("body_fwd") - Input.get_action_strength("body_back")).limit_length(1.0) * TILT_MAX
		var zin := Input.get_action_strength("pedal") - Input.get_action_strength("brake")
		_zoom_t = clampf(_zoom_t * exp(zin * 1.5 * dt), 1.0, ZOOM_MAX)
		var py := 0.0
		if not Settings._test_run:
			for d in Input.get_connected_joypads():
				var ay := Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)
				if absf(ay) > 0.2: py -= ay
		var pin := Vector2(Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"), clampf(py, -1, 1))
		_pan_t += pin * dt * 0.4 / _zoom
	else:   # folding away: back to the whole sheet
		_zoom_t = 1.0; _pan_t = Vector2.ZERO
	var lim := Vector2(cols * panel.x, rows * panel.y) * 0.5 * (1.0 - 1.0 / _zoom_t)
	_pan_t = _pan_t.clamp(-lim, lim)
	var e := 1.0 - exp(-dt * 9.0)
	_tilt = _tilt.lerp(tilt_t, 1.0 - exp(-dt * 6.0))
	_zoom = lerpf(_zoom, _zoom_t, e)
	_pan = _pan.lerp(_pan_t, e)
	_cam.position = Vector3(_pan.x, _pan.y, _cam_d / _zoom)
	_sheet.transform.basis = Basis.from_euler(Vector3(-_tilt.y, _tilt.x, 0.0)) * _sheet.transform.basis


func _hand_mouse(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _zoom_t = minf(_zoom_t * 1.15, ZOOM_MAX)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _zoom_t = maxf(_zoom_t / 1.15, 1.0)
		elif e.button_index == MOUSE_BUTTON_LEFT: _drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		# metres on the sheet per screen pixel at this zoom
		var mpp := 2.0 * _cam.position.z * tan(deg_to_rad(_cam.fov) * 0.5) / get_viewport().get_visible_rect().size.y
		_pan_t -= Vector2(e.relative.x, -e.relative.y) * mpp


static func ease_in_out(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## the fold angles and where the sheet is held, from k (0 put away .. 1 open)
func _pose() -> void:
	var PW := panel.x; var PH := panel.y
	var lift := _lift.x                                                    # comes up from below
	var row_open := _row.x if rows == 2 else 1.0                           # the half fold opens
	var acc := []                                                          # then the accordion, outer panel first
	for c in cols: acc.append(_acc[c].x if c > 0 else clampf(_acc[mini(1, cols - 1)].x, 0.0, 1.0))
	var breathe := sin(_idle * 1.3) * 0.5 + 0.5
	var tr := []                                                           # each column in sheet space
	var t := Transform3D.IDENTITY
	for c in cols:
		if c > 0:
			var s := -1.0 if c % 2 == 1 else 1.0
			var ang: float = s * lerpf(PI - EPS_C, 0.05 + 0.015 * breathe, acc[c])   # a few degrees stay in every crease
			t = t * Transform3D(Basis(), Vector3(PW, 0, 0)) * Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO)
		tr.append(t)
	var brest := 0.025 + 0.01 * breathe
	var xs := []
	var lo := Vector3(INF, INF, INF); var hi := -lo
	for c in cols:
		var pair := [tr[c]]
		var top_lo := 0.0 if rows == 2 else -0.5 * PH
		var top_hi := PH if rows == 2 else 0.5 * PH
		for corner in [Vector3(0, top_hi, 0), Vector3(PW, top_hi, 0), Vector3(0, top_lo, 0), Vector3(PW, top_lo, 0)]:
			var p: Vector3 = tr[c] * corner
			lo = lo.min(p); hi = hi.max(p)
		if rows == 2:
			# odd columns lie flipped while the accordion is shut (local X = world -X): the half fold turns the
			# other way in their space; the few degrees left when it's open turn the same way for all
			var flip := -1.0 if c % 2 == 1 else 1.0
			var tb: Transform3D = tr[c] * Transform3D(Basis(Vector3.RIGHT, flip * (PI - EPS_R) * (1.0 - row_open) + brest * row_open), Vector3.ZERO)
			pair.append(tb)
			for corner in [Vector3(0, -PH, 0), Vector3(PW, -PH, 0)]:
				var p: Vector3 = tb * corner
				lo = lo.min(p); hi = hi.max(p)
		xs.append(pair)
	var centre := (lo + hi) * 0.5
	centre.z = lerpf(hi.z, centre.z, acc[0])                               # folded: the front layer stays put
	var off := Transform3D(Basis(), -centre)
	for c in cols:
		var pil: float = 0.004 * acc[c] * (0.7 + 0.3 * breathe) * (1.0 if c % 2 == 0 else -1.0)
		for r in rows:
			_panels[c][r].transform = off * xs[c][r]
			_panels[c][r].set_instance_shader_parameter("pillow", pil)
	# held in the hands: brought up from below, tilted back a little, a slow sway (calmer for live menus)
	var sw := 0.4 if live else 1.0
	var sway := Vector2(sin(_idle * 0.9) * 0.012, sin(_idle * 0.7 + 1.0) * 0.015) * sw
	var basis := Basis.from_euler(Vector3(lerpf(-0.9, -0.12 * sw, lift) + sway.x, lerpf(0.35, 0.0, lift) + sway.y, lerpf(-0.25, hold_roll, lift)))
	var depth := lerpf(0.18 if unfold else 0.0, 0.0, clampf(acc[0], 0.0, 1.0))   # a map is held closer while folded
	_sheet.transform = Transform3D(basis, Vector3(0, lerpf(-0.75, -0.012, lift), depth))
	(_dim.material as ShaderMaterial).set_shader_parameter("k", clampf(lift * 1.3, 0.0, 1.0) * dim)


# ------------------------------------------------------------------ bits

static func _blur_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, k * 3.0).rgb;
	float v = 1.0 - 0.55 * length(SCREEN_UV - 0.5);
	COLOR = vec4(mix(c, c * 0.45 * v, k), 1.0);
}
"""
	return s


## paper being unfolded: filtered noise in crackly bursts (rendered once, shared)
static var _rustle: AudioStreamWAV
static func rustle_sound() -> AudioStreamWAV:
	if _rustle: return _rustle
	var rate := 22050
	var n := int(rate * 1.1)
	var data := PackedByteArray(); data.resize(n * 2)
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var lp := 0.0; var prev := 0.0
	var burst := 0.0
	for i in n:
		var t := float(i) / rate
		if rng.randf() < 0.0035: burst = rng.randf_range(0.4, 1.0)   # a crinkle
		burst *= 0.9975
		var env := minf(1.0, t / 0.05) * clampf((1.1 - t) / 0.4, 0.0, 1.0)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.55
		var hp := lp - prev; prev = lp
		data.encode_s16(i * 2, clampi(int(hp * (0.12 + burst) * env * 0.7 * 32767.0), -32768, 32767))
	_rustle = AudioStreamWAV.new()
	_rustle.format = AudioStreamWAV.FORMAT_16_BITS
	_rustle.mix_rate = rate
	_rustle.stereo = false
	_rustle.data = data
	return _rustle
