class_name ComputerPreview
extends Control
## A close-up 3D product shot of a bike computer (see ComputerUnits), floating on its own (no handlebar):
## rounded graphite shell, black glass front with the live 2D screen, brand under it, side button, and the
## quarter-turn mount with its contacts on the back. Drag to turn it (it glides and coasts after you let go),
## wheel to zoom, double click to reset. Sizes are to scale between models.

const SCR := Vector2(136, 174)    # the screen in HUD pixels = the face's drawing space
const PX := 0.01                  # metres per face pixel
const TEX_K := 4.0                # texture pixels per face pixel (high res: the dot-matrix text stays crisp up close)
const HudScript := preload("res://scripts/ui/hud.gd")
const DIST0 := 4.3
const FOLLOW := 16.0              # how quickly the view follows the drag (1 / s)
const COAST := 3.2                # how fast a flung turn dies away (1 / s)

var unit_id := ""
var yaw := 0.0
var pitch := 0.08
var dist := DIST0
var dist_goal := DIST0
var _home := DIST0               # the framing that fits this model
var _yaw_t := 0.0
var _pitch_t := 0.08
var _vel := Vector2.ZERO          # turn speed (rad/s) carried after a drag
var _drag := false
var _moved := 0.0
var _beep
var _idle := 0.0
var _t := 0.0
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _model: Node3D
var _face_vp: SubViewport
var _face: Face

func _ready() -> void:
	clip_contents = true
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	svc.add_child(_vp)
	# a small studio sky: the glass and shell pick up soft boxes from it
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.62, 0.66, 0.72)
	sky_mat.sky_horizon_color = Color(0.95, 0.95, 0.96)
	sky_mat.ground_horizon_color = Color(0.8, 0.8, 0.82)
	sky_mat.ground_bottom_color = Color(0.25, 0.26, 0.28)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.0
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -150, 0)
	rim.light_energy = 0.45
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.position = Vector3(0, 0, dist)
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	# the screen texture's own little 2D world
	_face_vp = SubViewport.new()
	_face_vp.transparent_bg = true
	_face_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_face_vp.size = Vector2i(SCR * TEX_K)
	_face_vp.msaa_2d = Viewport.MSAA_4X
	add_child(_face_vp)
	_face = Face.new()
	_face.size = SCR * TEX_K
	_face_vp.add_child(_face)
	_beep = preload("res://scripts/ui/garmin_beep.gd").new()
	add_child(_beep)
	if unit_id != "": set_unit(unit_id)

# ---------------------------------------------------------------- the model

## A rounded-rectangle slab: `profile` = [inset, z] rings from back to front (inset shrinks the outline
## inwards, so the edge can be rounded off), flat caps at both ends. Corner radius r.
static func _slab(w: float, h: float, r: float, profile: Array, seg := 9) -> ArrayMesh:
	var rings: Array = []
	for pr in profile:
		var ins: float = pr[0]
		var rr := maxf(r - ins, 0.002)
		var pts: Array = []
		var centres := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		for c in 4:
			var cc: Vector2 = centres[c] * Vector2(w * 0.5 - r, h * 0.5 - r)
			for i in seg + 1:
				var a := (c + float(i) / seg) * PI * 0.5
				pts.append(Vector3(cc.x + cos(a) * rr, cc.y + sin(a) * rr, pr[1]))
		rings.append(pts)
	var n: int = rings[0].size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for k in rings.size() - 1:
		var a: Array = rings[k]
		var b: Array = rings[k + 1]
		for i in n:
			var j := (i + 1) % n
			for v in [a[i], b[j], a[j], a[i], b[i], b[j]]:
				st.add_vertex(v)
	st.set_smooth_group(-1)
	var front: Array = rings[rings.size() - 1]
	var back: Array = rings[0]
	var fc := Vector3(0, 0, front[0].z)
	var bc := Vector3(0, 0, back[0].z)
	for i in n:
		var j := (i + 1) % n
		for v in [fc, front[j], front[i]]: st.add_vertex(v)
		for v in [bc, back[i], back[j]]: st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

func _part(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_model.add_child(mi)
	return mi

func set_unit(id: String) -> void:
	unit_id = id
	if _pivot == null: return
	if _model: _model.queue_free()
	var u := ComputerUnits.get_unit(id)
	_face.unit = u
	_face.uid = id
	_face.k = TEX_K
	_face.page_i = 0
	var s: float = u.scale
	_home = DIST0 * s * 1.25   # a little further out so the whole device shows
	dist_goal = _home
	var w := 1.50 * s
	var h := 2.24 * s
	var d := 0.30 * s
	var r := 0.24 * s
	var body_col := Color(u.body).darkened(0.25)
	_model = Node3D.new()
	_pivot.add_child(_model)
	# shell: eased edges, slightly satin
	var shell := _slab(w, h, r, [[0.05 * s, -d * 0.5], [0.0, -d * 0.5 + 0.07 * s], [0.0, d * 0.5 - 0.10 * s], [0.035 * s, d * 0.5 - 0.02 * s]])
	_part(shell, _mat(body_col.lightened(0.05), 0.25, 0.5))
	# glass front, a hair proud of the shell, with a gloss that catches the sky
	var gm := _mat(Color(0.015, 0.016, 0.02), 0.0, 0.06)
	gm.clearcoat_enabled = true
	gm.clearcoat = 1.0
	gm.clearcoat_roughness = 0.04
	var gw := w - 0.10 * s
	var gh := h - 0.10 * s
	var glass := _slab(gw, gh, r - 0.05 * s, [[0.0, d * 0.5 - 0.03 * s], [0.0, d * 0.5 + 0.004 * s], [0.03 * s, d * 0.5 + 0.012 * s]], 8)
	_part(glass, gm)
	# the live screen
	var sw := SCR.x * PX * s
	var sh := SCR.y * PX * s
	var qm := QuadMesh.new()
	qm.size = Vector2(sw, sh)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_texture = _face_vp.get_texture()
	fmat.emission_enabled = true
	fmat.emission_texture = _face_vp.get_texture()
	fmat.emission_energy_multiplier = 0.6
	fmat.roughness = 0.2
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fmat.alpha_scissor_threshold = 0.5
	var sy := h * 0.5 - 0.2 * s - sh * 0.5
	_part(qm, fmat, Vector3(0, sy, d * 0.5 + 0.02 * s))
	# the model colour: a thin light line above the screen
	var led := BoxMesh.new()
	led.size = Vector3(w * 0.34, 0.03 * s, 0.02 * s)
	var lm := _mat(u.accent, 0.0, 0.3)
	lm.emission_enabled = true
	lm.emission = u.accent
	lm.emission_energy_multiplier = 1.4
	_part(led, lm, Vector3(0, h * 0.5 - 0.1 * s, d * 0.5 + 0.02 * s))
	# brand under the screen
	var lab := Label3D.new()
	lab.text = "CHARMIN"
	lab.font = UITheme.display_font(700)
	lab.font_size = 64
	lab.pixel_size = 0.0022 * s
	lab.modulate = Color(0.86, 0.87, 0.9)
	lab.shaded = false
	lab.double_sided = false
	lab.position = Vector3(0, -h * 0.5 + 0.17 * s, d * 0.5 + 0.02 * s)
	_model.add_child(lab)
	# side buttons: one in the model colour on the right, two small ones on the left
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06 * s, 0.34 * s, 0.1 * s)
	_part(bm, lm, Vector3(w * 0.5 + 0.006 * s, h * 0.17, 0.0))
	var bs := BoxMesh.new()
	bs.size = Vector3(0.05 * s, 0.2 * s, 0.09 * s)
	var bmat := _mat(body_col.lightened(0.18), 0.3, 0.45)
	_part(bs, bmat, Vector3(-w * 0.5 - 0.004 * s, h * 0.2, 0.0))
	_part(bs, bmat, Vector3(-w * 0.5 - 0.004 * s, -h * 0.02, 0.0))
	# the back: a raised round mount with the quarter-turn ears and the contacts
	var alu := _mat(Color("2a2c30"), 0.7, 0.4)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.42 * s; disc.bottom_radius = 0.44 * s; disc.height = 0.05 * s
	disc.radial_segments = 48
	var dm := _part(disc, alu, Vector3(0, -h * 0.06, -d * 0.5 - 0.02 * s))
	dm.rotation_degrees.x = 90
	var ear := BoxMesh.new()
	ear.size = Vector3(0.9 * s, 0.14 * s, 0.07 * s)
	_part(ear, alu, Vector3(0, -h * 0.06, -d * 0.5 - 0.05 * s))
	var gold := _mat(Color("d9b25a"), 1.0, 0.25)
	var pin := CylinderMesh.new()
	pin.top_radius = 0.025 * s; pin.bottom_radius = 0.025 * s; pin.height = 0.03 * s
	for i in 5:
		var p := Vector2.ZERO
		if i > 0: p = Vector2.from_angle(TAU * (i - 1) / 4.0 + PI * 0.25) * 0.17 * s
		var pm := _part(pin, gold, Vector3(p.x, -h * 0.06 + p.y, -d * 0.5 - 0.075 * s))
		pm.rotation_degrees.x = 90
	var lab2 := Label3D.new()
	lab2.text = u.name
	lab2.font = UITheme.display_font(600)
	lab2.font_size = 40
	lab2.pixel_size = 0.0016 * s
	lab2.modulate = Color(0.7, 0.72, 0.75)
	lab2.shaded = false
	lab2.double_sided = false
	lab2.rotation_degrees.y = 180
	lab2.position = Vector3(0, h * 0.28, -d * 0.5 - 0.012 * s)
	_model.add_child(lab2)

# ---------------------------------------------------------------- input / motion

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			_idle = 0.0
			if e.pressed:
				_vel = Vector2.ZERO
				_moved = 0.0
			elif _moved < 5.0 and not e.double_click:
				_press_device(e.position.x < size.x * 0.5)   # a click, not a drag: the left / right half is the key
			if e.pressed:
				if e.double_click:
					_yaw_t = fposmod(_yaw_t + PI, TAU) - PI
					yaw = _yaw_t
					_yaw_t = 0.0; _pitch_t = 0.08
					dist_goal = _home
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_goal = clampf(dist_goal * 0.88, 2.2, 14.0)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_goal = clampf(dist_goal / 0.88, 2.6, 14.0)
	elif e is InputEventMouseMotion and _drag:
		_moved += e.relative.length()
		var dy: float = e.relative.x * 0.0105
		var dp: float = e.relative.y * 0.0075
		_yaw_t += dy
		_pitch_t = clampf(_pitch_t + dp, -1.0, 1.0)
		# remember the hand's speed so a flick keeps turning
		var dt := maxf(get_process_delta_time(), 0.001)
		_vel = _vel.lerp(Vector2(dy, dp) / dt, 0.5)
		_idle = 0.0

## click the device: previous / next page, with the key beep and the backlight
func _press_device(left: bool) -> void:
	_face.step(-1 if left else 1)
	_beep.key()

## the settings card changed something: redraw with the new page list
func refresh() -> void:
	if _face: _face.refresh()

func _process(dt: float) -> void:
	if _pivot == null: return
	dt = minf(dt, 0.05)
	_t += dt
	if _drag:
		pass
	else:
		_idle += dt
		# coast on the flick, then a very gentle sway once left alone
		_yaw_t += _vel.x * dt
		_pitch_t = clampf(_pitch_t + _vel.y * dt, -1.0, 1.0)
		_vel *= exp(-dt * COAST)
		if _vel.length() < 0.05: _vel = Vector2.ZERO
		if _idle > 2.0 and _vel == Vector2.ZERO:
			var w := minf((_idle - 2.0) / 2.0, 1.0)
			_yaw_t = fposmod(_yaw_t + PI, TAU) - PI
			if absf(yaw - _yaw_t) > PI: yaw += signf(_yaw_t - yaw) * TAU
			_yaw_t = lerpf(_yaw_t, sin(_t * 0.45) * 0.5, 1.0 - exp(-dt * 0.9 * w))
			_pitch_t = lerpf(_pitch_t, 0.08, 1.0 - exp(-dt * 1.2 * w))
	yaw = lerpf(yaw, _yaw_t, 1.0 - exp(-dt * FOLLOW))
	pitch = lerpf(pitch, _pitch_t, 1.0 - exp(-dt * FOLLOW))
	_pivot.rotation = Vector3(pitch, yaw, 0)
	dist = lerpf(dist, dist_goal, 1.0 - exp(-dt * 9.0))
	_cam.position = Vector3(0, 0, dist)

# ---------------------------------------------------------------- the screen

## the 2D screen of the unit, in HUD pixels (scaled up by `k` into the texture)
class Face extends Control:
	var unit := ComputerUnits.get_unit("classic")
	var uid := "classic"
	var k := 2.0
	var page_i := 0
	var _t := 0.0
	var _auto := 0.0       # seconds until the pages turn by themselves again after a click
	var _flash := 0.0      # backlight after a click
	const LCD := Color("eceee8")
	const SHOW := [0, 1, 5]   # the pages this mock-up can draw
	func _pages() -> Array:
		var pages: Array = []
		for p in ComputerUnits.pages(uid):
			if p in SHOW: pages.append(p)
		if pages.is_empty(): pages = [0]
		return pages
	func step(d: int) -> void:
		var n := _pages().size()
		page_i = posmod(page_i + d, n)
		_auto = 8.0
		_flash = 2.0
	func refresh() -> void:
		page_i = 0
	func _process(dt: float) -> void:
		_t += dt
		_flash = maxf(0.0, _flash - dt)
		if _auto > 0.0: _auto -= dt
		else: page_i = (int(_t / 3.0)) % _pages().size()
		queue_redraw()
	func _page() -> int:
		var pages := _pages()
		return pages[page_i % pages.size()]
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		var f := UITheme.lcd_font()
		var sz := SCR
		var ink := Color("111417")
		var scr := Rect2(Vector2.ZERO, sz)
		var lit := int(ComputerUnits.opt(uid, "light")) == 1 or _flash > 0.0
		draw_style_box(UITheme.box(LCD.lerp(Color("f2fbff"), 1.0 if lit else 0.0), 7, 0), scr)
		var x0 := 7.0
		var w := sz.x - 14.0
		var titles := {0: "RIDE", 1: "TRIP", 5: "MAP"}
		var pg := _page()
		var head := StyleBoxFlat.new()
		head.bg_color = ink
		head.corner_radius_top_left = 7
		head.corner_radius_top_right = 7
		draw_style_box(head, Rect2(0, 0, sz.x, 15))
		draw_string(f, Vector2(x0, 11), "12:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f2f3ef"))
		draw_string(f, Vector2(x0, 11), titles[pg], HORIZONTAL_ALIGNMENT_CENTER, w, 9, Color(0.95, 0.95, 0.94, 0.75))
		var br := Rect2(sz.x - 22, 4, 14, 7)
		draw_rect(br, Color(0.95, 0.95, 0.94, 0.8), false, 1.0)
		draw_rect(Rect2(br.position.x + 1.5, br.position.y + 1.5, (br.size.x - 3) * 0.8, br.size.y - 3), Color("8be36a"))
		var y := 29.0
		match pg:
			0:
				var v := 38.0 + sin(_t * 1.3) * 6.0
				draw_string(f, Vector2(x0, y), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0, y), "km/h", HORIZONTAL_ALIGNMENT_RIGHT, w, 9, Color(ink, 0.7))
				draw_string(f, Vector2(x0, y + 36), "%.1f" % v, HORIZONTAL_ALIGNMENT_RIGHT, w, 38 if v < 100 else 30, ink)
				y += 46
				draw_line(Vector2(0, y), Vector2(sz.x, y), Color(ink, 0.22))
				draw_string(f, Vector2(x0, y + 12), "SLOPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 12), "GRADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0, y + 32), "-9°", HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
				draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 32), "-16%", HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
				draw_line(Vector2(sz.x * 0.5, y), Vector2(sz.x * 0.5, y + 40), Color(ink, 0.22))
				if unit.nav:   # the trail alert drops over the lower half
					var top := 76.0
					var bx := Rect2(3, top, sz.x - 6, sz.y - top - 14)
					HudScript.GaugeView.draw_alert(self, bx, {"kind": "HR", "text": "HAIRPIN RIGHT", "d": 120.0 - fmod(_t * 12.0, 100.0)}, f)
			1:
				draw_string(f, Vector2(x0, y), "RIDE TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0, y + 36), "%d:%02d" % [int(_t * 7.0) / 60, int(_t * 7.0) % 60], HORIZONTAL_ALIGNMENT_RIGHT, w, 38, ink)
				y += 46
				for row in 2:
					draw_line(Vector2(0, y), Vector2(sz.x, y), Color(ink, 0.22))
					draw_string(f, Vector2(x0, y + 12), ["DIST km", "MAX"][row], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
					draw_string(f, Vector2(x0, y + 32), ["3.42", "61.8"][row], HORIZONTAL_ALIGNMENT_RIGHT, w, 18, ink)
					y += 38
			_:   # MAP: contours, the trail, you
				var r := Rect2(0, 15, sz.x, sz.y - 15)
				for i in 5:
					var rad := 12.0 + i * 15.0
					draw_arc(r.get_center() + Vector2(14, 20), rad, 0.0, TAU, 40, Color(ink, 0.18 if i % 2 else 0.3), 1.0)
				var pts := PackedVector2Array()
				for i in 14:
					var tt := i / 13.0
					pts.append(Vector2(r.position.x + 20 + sin(tt * 5.0) * 22 + tt * 36, r.end.y - 14 - tt * (r.size.y - 28)))
				draw_polyline(pts, Color("d8344a"), 2.0)
				var me := pts[4 + int(_t) % 6]
				draw_circle(me, 3.5, ink)
				draw_arc(me, 7.0, 0, TAU, 20, Color(ink, 0.5), 1.0)
		# page dots along the bottom edge
		var np: int = ComputerUnits.pages(uid).size()
		var cur := ComputerUnits.pages(uid).find(pg)
		for j in np:
			draw_circle(Vector2(sz.x / 2 + (j - (np - 1) / 2.0) * 8, sz.y - 6), 2.0, Color(ink, 0.75) if j == cur else Color(ink, 0.22))
