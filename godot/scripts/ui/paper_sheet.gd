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
@export var page_alpha := false               # the page is printed over a content layer (set_content): keep its alpha
@export var hold_roll := 0.0                  # held a little crooked (rad), for charm
@export var unfold := true                    # false: it comes up and stays folded, showing the cover (a pamphlet);
												# set_unfolded() opens / shuts it while it's up
@export var fold_style := "accordion"         # "letter": 3 panels rows 1, a roll-folded leaflet - the middle panel
												# stays, the right flap folds in, the left (its back = the cover) over it
@export var auto_close := true                # close_actions fold it away (false: just close_requested)
@export var dim := 1.0                        # how much the game behind is blurred / darkened
var close_actions: Array[StringName] = []     # actions that fold it away again (handled here, never reach the game)

var cover_col := 0                   # the panel whose back is the cover
var back_col := -1                   # a panel whose back carries the cover strip's second slot (the leaflet's back)
var spin := 0.0                      # the sheet turned round its upright (rad): PI = you see its back
var page: SubViewport                # what's printed: front (page_size) + cover strip below
var content: Control                 # add your print here (sized to the whole page viewport)
var page_size := Vector2i.ZERO
var cover_size := Vector2i.ZERO

var state := 0                       # 0 put away, 1 unfolding, 2 open, 3 folding
var k := 0.0                         # 0 put away .. 1 open
var shots := ""                      # tests: dir/prefix -> its own render while it unfolds
var freeze_at := float(OS.get_environment("BMX_PAPER_AT")) if OS.get_environment("BMX_PAPER_AT") != "" else -1.0   # tests: stop the animation at t s

const EPS_C := 0.09                 # the folds never shut completely: the stack fans a little (rad)
const EPS_R := 0.006

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
	assert(fold_style == "letter" and cols == 3 and rows == 1 or (cols % 2 == 0 or not unfold) and rows >= 1 and rows <= 2,
		"PaperSheet: cols even (or unfold off), rows 1 or 2; letter: 3 x 1")
	cover_col = 0 if fold_style == "letter" else cols - 1
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
	page.transparent_bg = page_alpha
	page.gui_embed_subwindows = true
	page.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(page)
	if not page_alpha:   # bare paper under whatever is printed (the viewport's clear colour showed through)
		var white := ColorRect.new()
		white.color = Color.WHITE
		white.size = Vector2(page.size)
		white.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(white)
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
			var x0 := -0.5 if (fold_style == "letter" and c == 0) else 0.5   # letter: the left flap hangs left of its hinge
			q.center_offset = Vector3(panel.x * x0, panel.y * y0, 0)
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
			mi.set_instance_shader_parameter("cell", Vector2(c, r))
			mi.set_instance_shader_parameter("cover", 1.0 if (c == cover_col and r == 0) else (2.0 if (c == back_col and r == 0) else 0.0))
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


## a second print under the page, seen through where the page is transparent, at rect (uv offset, uv size)
## of its own texture - scrolling = moving rect (the map's world)
func set_content(t: Texture2D, rect: Rect2) -> void:
	_mat.set_shader_parameter("content_tex", t)
	_mat.set_shader_parameter("use_content", 1.0)
	set_content_rect(rect)

func set_content_rect(rect: Rect2) -> void:
	_mat.set_shader_parameter("content_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))


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
	if state == 1 and k == 0.0: _centre_s = Vector3(INF, INF, INF); _relax = 0.0
	_show_hint()
	visible = true
	_fit_camera()
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if live: page.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_last_us = Time.get_ticks_usec()
	_shot_i = 0; _shot_next = _idle
	_play_slice(1.15, 1.1 / tempo)
	_pose()


## open / shut a sheet that is up (the leaflet: Settings opens it, Done shuts it)
func set_unfolded(on: bool) -> void:
	if unfold == on: return
	unfold = on
	if state == 1 or state == 2: _play_slice(1.2, 0.7)


func is_unfolded() -> bool:
	return unfold


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
	if fold_style == "letter":
		# a leaflet: up it comes shut (cover to you); opened, the cover flap swings open, then the inner flap;
		# shut again (or put away) the other way round, then down it goes
		var open := (state == 1 or state == 2) and unfold
		_row.target = 1.0
		_acc[1].target = 1.0
		_acc[0].target = 1.0 if open else (0.0 if _acc[2].x < 0.45 else 1.0)
		_acc[2].target = 1.0 if (open and _acc[0].x > 0.55) else (_acc[2].target if open else 0.0)
		_lift.target = 1.0 if state != 3 else (0.0 if _acc[0].x < 0.1 else 1.0)
	elif (state == 1 or state == 2) and not unfold:
		_lift.target = 1.0
		_row.target = 1.0 if rows == 1 else 0.0
	elif state == 1 or state == 2:
		# like opening a real map: up it comes (cover to you), held at both ends and pulled apart - every crease
		# of the accordion opens together, like bellows - then the bottom half (folded over the map face) drops
		_lift.target = 1.0
		if tl < 0.05: _row.target = 0.0
		var t0 := 0.16
		var step := 0.0
		for c in range(1, cols):
			_acc[c].target = 1.0 if tl > t0 + 0.02 * absf(c - cols * 0.5) else 0.0
		# the flap waits until every panel has come to rest (a still-swinging one opened a wedge)
		if rows == 1 or (tl > t0 + step * (cols - 2) + 0.2 and accordion_calm() and not hold_flap): _row.target = 1.0
	else:
		# folding away: the other way round - bottom half up, the accordion shut from the inside, down it goes
		var r0 := 0.12 if rows == 2 else 0.0
		_row.target = 0.0 if rows == 2 else 1.0
		for c in range(1, cols):
			_acc[c].target = 0.0 if tl > r0 + 0.06 * (c - 1) else 1.0
		_lift.target = 0.0 if tl > r0 + 0.06 * (cols - 1) + 0.05 else 1.0


func _process(_dt: float) -> void:
	if state == 0: return
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_us) / 1e6, 0.05)
	_last_us = now
	if freeze_at >= 0.0 and _tl + dt > freeze_at: dt = maxf(0.0, freeze_at - _tl)   # tests: hold that moment
	_idle += dt
	_tl += dt
	_pose_dt = dt
	_hint_tick(dt)
	_sound_fade(dt)
	_drive()
	var opening := state != 3
	# opening: lively (overshoot ~10 % = a flap swings ~20 deg past flat and back); closing: firmer
	_lift.step(dt, (2.8 if opening else 3.4) * tempo, 0.62 if opening else 0.85, false)
	var shut_k := 1.0 if opening else 1.9   # folding away is quicker than opening
	_row.step(dt, 3.0 * tempo * shut_k, 0.68 if opening else 0.75, not opening)   # the flap drops with one small bounce
	for c in range(0 if fold_style == "letter" else 1, cols):
		_acc[c].step(dt, 3.0 * tempo * shut_k, 0.78 if opening else 0.85, not opening or fold_style == "letter")   # paper: soft
	k = clampf(_lift.x, 0.0, 1.0)
	if state == 1 and _tl * tempo > open_t:
		state = 2; opened.emit()
	elif state == 3 and _tl * tempo > close_t and _lift.x < 0.03:
		_put_away(); return
	if _vp.size != Vector2i(get_window().size): _fit_camera()
	_pose()
	if handheld: _hand_controls(dt)
	if shots != "" and state != 3 and _idle >= _shot_next and _shot_i < 34:
		_shot_next = _idle + 0.15
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shots, _shot_i])   # the last frame on screen (BMX_OFFSCREEN: minimised windows draw late)
		print("PAPERSHOT %s_%d.png t=%.2f lift=%.2f row=%.2f" % [shots, _shot_i, _tl, _lift.x, _row.x])
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
			var u := h.x / panel.x + (1.0 if (fold_style == "letter" and c == 0) else 0.0)
			var v := 0.5 - (h.y / panel.y - y0)
			if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0: continue
			best = t
			if ld.z > 0.0:   # its back: only the cover is printed there (mirrored, as the shader draws it)
				out = Vector2((1.0 - u) * cover_size.x, page_size.y + v * cover_size.y) if (c == cover_col and r == 0 and cover_size.y > 0) else Vector2(-1, -1)
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
	# the controls row at the bottom (prompt_items) gets its own strip: the sheet fits above it, never over it
	_reserve = HINT_RESERVE if not prompt_items().is_empty() else 0.0
	var avail := 1.0 - _reserve
	var fit := func(sz: Vector2) -> float:
		return maxf((sz.x / fill.x) * 0.5 / (th * asp), (sz.y / (fill.y * avail)) * 0.5 / th)
	_cam_open = fit.call(Vector2(cols * panel.x, rows * panel.y))
	_cam_fold = fit.call(panel)
	_cam_d = _cam_open if unfold and fold_style != "letter" else _cam_fold   # (a leaflet eases between the two)
	_cam_th = th
	_cam.position = Vector3(0, _cam_y(_cam_d), _cam_d)
	_cam.rotation = Vector3.ZERO


const HINT_RESERVE := 0.1            # share of the screen height under the sheet for the controls row
var _reserve := 0.0
var _cam_th := 0.3

## the camera moves down so the sheet sits in the middle of the space above the controls row
func _cam_y(d: float) -> float:
	return -d * _cam_th * _reserve


# ------------------------------------------------------------------ held in the hands (handheld = true)
## pad: right stick tilts the sheet a little, RT / LT zoom in / out, left stick scrolls the print (_scroll);
## keys: WASD / arrows scroll, Q / E zoom, numpad tilts; mouse: wheel zooms, drag scrolls. Reset on opening.
@export var handheld := false
const TILT_MAX := 0.3                # rad
const ZOOM_MAX := 2.5                # zoom = the print's scale (the sheet itself always stays fully in view)
const ZOOM_MIN := 0.5
var _cam_d := 1.0                    # camera distance that fits the sheet
var _cam_open := 1.0
var _cam_fold := 1.0
var _zoom := 1.0
var _zoom_t := 1.0
var _tilt := Vector2.ZERO
var _drag := false

var _hint: PadGlyph.PromptBar
var _hint_pad := false

## what the prompt bar at the bottom says: [[icons], label] items (PadGlyph). Override per sheet.
func prompt_items() -> Array:
	if not handheld: return []
	if Settings.pad_active:
		return [[["LS"], "Travel"], [["RT", "LT"], "Zoom"], [["RS"], "Tilt"], [[PadGlyph.glyph_for("map")], "Close"]]
	return [[["K:W", "K:A", "K:S", "K:D"], "Travel"], [["K:Q", "K:E", "WHEEL"], "Zoom"], [["MOUSE"], "Drag"], [[PadGlyph.glyph_for("map")], "Close"]]

## the controls at the bottom of the screen, as button icons (pad or keys, whichever is in use)
func _show_hint() -> void:
	var it := prompt_items()
	if it.is_empty(): return
	if _hint == null:
		_hint = PadGlyph.PromptBar.new()
		_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_hint.anchor_top = 1.0 - HINT_RESERVE * 0.92; _hint.offset_top = 0; _hint.offset_bottom = -6
		add_child(_hint)
	_hint_pad = Settings.pad_active
	_hint.set_items(it)
	_hint.a = 0.0


## fade the bar in once open, out while folding; follow a switch between pad and keys
func _hint_tick(dt: float) -> void:
	if _hint == null: return
	if _hint_pad != Settings.pad_active:
		_hint_pad = Settings.pad_active; _hint.set_items(prompt_items())
	var t := 1.0 if (state == 2 or (state == 1 and _lift.x > 0.9)) else 0.0
	if not is_equal_approx(_hint.a, t):
		_hint.a = move_toward(_hint.a, t, dt * 3.0)
		_hint.queue_redraw()


func _reset_view() -> void:
	_zoom = 1.0; _zoom_t = 1.0; _tilt = Vector2.ZERO; _drag = false


func _hand_controls(dt: float) -> void:
	var tilt_t := Vector2.ZERO
	var scroll := Vector2.ZERO
	if state == 1 or state == 2:
		tilt_t = Vector2(Input.get_action_strength("body_right") - Input.get_action_strength("body_left"),
			Input.get_action_strength("body_fwd") - Input.get_action_strength("body_back")).limit_length(1.0) * TILT_MAX
		# zoom: the pad's triggers (read straight, whatever pedal / brake are bound to), Q / E, the wheel
		var zi := Input.get_action_strength("gear_harder") if not Settings.pad_active else 0.0
		var zo := Input.get_action_strength("gear_easier") if not Settings.pad_active else 0.0
		# scroll: the left stick, WASD / arrows (x = right, y = up the sheet)
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): scroll.x += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): scroll.x -= 1
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): scroll.y += 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): scroll.y -= 1
		if not Settings._test_run:
			for d in Input.get_connected_joypads():
				var st := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), -Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
				if st.length() > 0.18: scroll += st * ((st.length() - 0.18) / 0.82) / st.length()
				var rt := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT)
				var lt := Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT)
				if rt > 0.08: zi = maxf(zi, rt)
				if lt > 0.08: zo = maxf(zo, lt)
		scroll += test_scroll
		_zoom_t = clampf(_zoom_t * exp((zi - zo) * 1.5 * dt), zoom_min, ZOOM_MAX)
	else:   # folding away: back to the whole sheet
		_zoom_t = 1.0
	var e := 1.0 - exp(-dt * 9.0)
	_tilt = _tilt.lerp(tilt_t, 1.0 - exp(-dt * 6.0))
	_zoom = lerpf(_zoom, _zoom_t, e)
	_sheet.transform.basis = Basis.from_euler(Vector3(-_tilt.y, _tilt.x, 0.0)) * _sheet.transform.basis
	if scroll != Vector2.ZERO: _scroll(scroll.limit_length(1.0) * dt / _zoom, false)


## the print scrolls under the paper (the map: travel the world on it). amount: stick / keys x seconds
## (drag = false) or metres on the sheet (drag = true). Override; the base sheet doesn't scroll.
func _scroll(_amount: Vector2, _drag_m: bool) -> void:
	pass

## every accordion panel open and at rest
func accordion_calm() -> bool:
	if _acc.is_empty(): return false
	for c in range(1, cols):
		if absf(_acc[c].x - 1.0) > 0.012 or absf(_acc[c].v) > 0.1: return false
	return true

var test_scroll := Vector2.ZERO      # tests: as if the left stick were held
var hold_flap := false               # the bottom half waits (the map: its print isn't ready yet)
var zoom_min := ZOOM_MIN


func _hand_mouse(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _zoom_t = minf(_zoom_t * 1.15, ZOOM_MAX)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _zoom_t = maxf(_zoom_t / 1.15, zoom_min)
		elif e.button_index == MOUSE_BUTTON_LEFT: _drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		# metres on the sheet per screen pixel at this zoom; the print follows the hand
		var mpp := 2.0 * _cam.position.z * tan(deg_to_rad(_cam.fov) * 0.5) / get_viewport().get_visible_rect().size.y
		_scroll(Vector2(-e.relative.x, e.relative.y) * mpp, true)


static func ease_in_out(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## the fold angles and where the sheet is held, from k (0 put away .. 1 open)
var _centre_s := Vector3(INF, INF, INF)
var _relax := 0.0                    # 0 = creases held flat (the bottom half still swinging), 1 = relaxed
var _pose_dt := 0.0

func _pose() -> void:
	var PW := panel.x; var PH := panel.y
	var lift := _lift.x                                                    # comes up from below
	var row_open := _row.x if rows == 2 else 1.0                           # the half fold opens
	var acc := []                                                          # then the accordion, outer panel first
	for c in cols: acc.append(_acc[c].x if (c > 0 or fold_style == "letter") else clampf(_acc[mini(1, cols - 1)].x, 0.0, 1.0))
	var breathe := sin(_idle * 1.3) * 0.5 + 0.5
	# the creases relax into their few degrees only once the bottom half is down (bent creases while it swings
	# opened slits between the bottom panels)
	var settled := 1.0 if rows == 1 or (absf(_row.x - 1.0) < 0.03 and absf(_row.v) < 0.3) else 0.0
	_relax = move_toward(_relax, settled, _pose_dt * 1.5)
	var relax := _relax
	if fold_style == "letter":
		_pose_letter(lift, acc, breathe)
		return
	var tr := []                                                           # each column in sheet space
	var t := Transform3D.IDENTITY
	for c in cols:
		if c > 0:
			var s := -1.0 if c % 2 == 1 else 1.0
			var ang: float = s * lerpf(PI - EPS_C, (0.035 + 0.01 * breathe) * relax, acc[c])   # a few degrees stay in every crease
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
			# the bottom half folded up over the map face (the paper's own front), the same in every column: it
			# rides along while the accordion opens, then flips down
			var tb: Transform3D = tr[c] * Transform3D(Basis(), Vector3(0, 0, 0.0012 * clampf(1.0 - row_open, 0.0, 1.0))) 				* Transform3D(Basis(Vector3.RIGHT, -(PI - EPS_R) * (1.0 - row_open) + brest * row_open), Vector3.ZERO)   # a hair in front: no z-fight
			pair.append(tb)
			for corner in [Vector3(0, -PH, 0), Vector3(PW, -PH, 0)]:
				var p: Vector3 = tb * corner
				lo = lo.min(p); hi = hi.max(p)
		xs.append(pair)
	var centre := (lo + hi) * 0.5
	centre.z = lerpf(hi.z, centre.z, acc[0])                               # folded: the front layer stays put
	# the held point drifts after the paper's middle instead of jumping with every flap
	if _centre_s.x == INF or _pose_dt <= 0.0: _centre_s = centre
	else: _centre_s = _centre_s.lerp(centre, 1.0 - exp(-_pose_dt * 7.0))
	var off := Transform3D(Basis(), -_centre_s)
	for c in cols:
		# the bulge between creases only once a panel lies open (with the half folded over it, it pushed through)
		var pil: float = 0.004 * clampf(acc[c], 0.0, 1.0) * clampf(row_open, 0.0, 1.0) * (0.7 + 0.3 * breathe) * (1.0 if c % 2 == 0 else -1.0)
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


## the leaflet (fold_style "letter"): the middle panel stays put; the right flap swings in on its hinge, the left
## (cover) flap over it - each a hair further out so they never cut through each other. Open, they cup a little.
func _pose_letter(lift: float, acc: Array, breathe: float) -> void:
	var PW := panel.x; var PH := panel.y
	var o0 := clampf(acc[0], 0.0, 1.2); var o2 := clampf(acc[2], 0.0, 1.2)
	var cup := 0.05 + 0.01 * breathe
	# shut, the flaps lie almost flat on each other (a real leaflet is a few tenths of a mm thick)
	var a0: float = lerpf(PI - 0.005, cup, o0)
	var a2: float = lerpf(PI - 0.0025, cup, o2)
	var t0 := Transform3D(Basis(), Vector3(0, 0, 0.0009 * clampf(1.0 - o0, 0.0, 1.0))) * Transform3D(Basis(Vector3.UP, a0), Vector3.ZERO)
	var t1 := Transform3D.IDENTITY
	var t2 := Transform3D(Basis(), Vector3(PW, 0, 0.00045 * clampf(1.0 - o2, 0.0, 1.0))) * Transform3D(Basis(Vector3.UP, -a2), Vector3.ZERO)
	var xs := [t0, t1, t2]
	var lo := Vector3(INF, INF, INF); var hi := -lo
	for c in 3:
		var x0 := -PW if c == 0 else 0.0
		for corner in [Vector3(x0, PH * 0.5, 0), Vector3(x0 + PW, PH * 0.5, 0), Vector3(x0, -PH * 0.5, 0), Vector3(x0 + PW, -PH * 0.5, 0)]:
			var p: Vector3 = xs[c] * corner
			lo = lo.min(p); hi = hi.max(p)
	var centre := (lo + hi) * 0.5
	centre.z = hi.z
	if _centre_s.x == INF or _pose_dt <= 0.0: _centre_s = centre
	else: _centre_s = _centre_s.lerp(centre, 1.0 - exp(-_pose_dt * 7.0))
	var off := Transform3D(Basis(), -_centre_s)
	for c in 3:
		_panels[c][0].transform = off * xs[c]
		_panels[c][0].set_instance_shader_parameter("pillow", 0.0)
	# the camera eases from fitting the shut leaflet to fitting it open
	var open_k := clampf((o0 + o2) * 0.5, 0.0, 1.0)
	_cam.position.z = lerpf(_cam_fold, _cam_open, open_k)
	_cam.position.y = _cam_y(_cam.position.z)
	var sw := 0.4 if live else 1.0
	var sway := Vector2(sin(_idle * 0.9) * 0.012, sin(_idle * 0.7 + 1.0) * 0.015) * sw
	var basis := Basis.from_euler(Vector3(lerpf(-0.9, -0.12 * sw, lift) + sway.x, lerpf(0.35, 0.0, lift) + sway.y, lerpf(-0.25, hold_roll * (1.0 - open_k), lift)))
	basis = basis * Basis(Vector3.UP, spin)   # turned over (round its own upright)
	_sheet.transform = Transform3D(basis, Vector3(0, lerpf(-0.75, -0.012, lift) * _cam.position.z / maxf(_cam_open, 0.01), 0))
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
