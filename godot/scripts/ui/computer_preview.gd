class_name ComputerPreview
extends Control
## A close-up 3D model of a bike computer (see ComputerUnits) on a handlebar piece: drag to turn it, wheel to
## zoom in / out, double click to reset. The screen is a live 2D face (RIDE / TRIP / MAP pages, whatever the
## model has) drawn into a texture on the front. Sizes are to scale between models.

const BASE := Vector2(150, 224)   # the HUD unit in pixels = the face's drawing space
const PX := 0.01                  # metres per face pixel
const TEX_K := 2.0                # texture pixels per face pixel
const HudScript := preload("res://scripts/ui/hud.gd")

var unit_id := ""
var yaw := 0.0
var pitch := 0.0
var dist := 5.6
var dist_goal := 5.6
var _drag := false
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
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.88)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -150, 0)
	rim.light_energy = 0.5
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.position = Vector3(0, 0, dist)
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	# the face texture's own little 2D world
	_face_vp = SubViewport.new()
	_face_vp.transparent_bg = true
	_face_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_face_vp.size = Vector2i(BASE * TEX_K)
	add_child(_face_vp)
	_face = Face.new()
	_face.size = BASE * TEX_K
	_face_vp.add_child(_face)
	if unit_id != "": set_unit(unit_id)

func set_unit(id: String) -> void:
	unit_id = id
	if _pivot == null: return
	if _model: _model.queue_free()
	var u := ComputerUnits.get_unit(id)
	_face.unit = u
	_face.k = TEX_K
	_face.page_i = 0
	var s: float = u.scale
	var w := BASE.x * PX * s
	var h := BASE.y * PX * s
	var d := 0.36 * s
	_model = Node3D.new()
	_pivot.add_child(_model)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w - 0.12 * s, h - 0.12 * s, d)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(u.body).lightened(0.06)
	bmat.metallic = 0.35
	bmat.roughness = 0.42
	body.material_override = bmat
	_model.add_child(body)
	var front := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	front.mesh = qm
	front.position.z = d * 0.5 + 0.004
	var fmat := StandardMaterial3D.new()
	fmat.albedo_texture = _face_vp.get_texture()
	fmat.emission_enabled = true
	fmat.emission_texture = _face_vp.get_texture()
	fmat.emission_energy_multiplier = 0.55
	fmat.roughness = 0.3
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fmat.alpha_scissor_threshold = 0.5
	front.material_override = fmat
	_model.add_child(front)
	# the back plate with the quarter-turn mount, and the handlebar it clamps to
	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color("9a9ea4")
	alu.metallic = 0.9
	alu.roughness = 0.32
	var mount := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.5 * s + 0.2, 0.36 * s + 0.1, 0.16)
	mount.mesh = mm
	mount.position.z = -d * 0.5 - 0.08
	mount.material_override = alu
	_model.add_child(mount)
	var bar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12; cm.bottom_radius = 0.12; cm.height = 3.0
	bar.mesh = cm
	bar.rotation_degrees.z = 90
	bar.position.z = -d * 0.5 - 0.32
	var barmat := StandardMaterial3D.new()
	barmat.albedo_color = Color("26282b")
	barmat.metallic = 0.6
	barmat.roughness = 0.4
	bar.material_override = barmat
	_model.add_child(bar)
	# the mount sits below the unit's centre of mass so it reads as clamped on: centre the whole thing
	_model.position.y = 0.0

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			_idle = 0.0
			if e.pressed and e.double_click:
				yaw = 0.0; pitch = 0.0; dist_goal = 5.6
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist_goal = clampf(dist_goal - 0.5, 2.6, 8.0)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist_goal = clampf(dist_goal + 0.5, 2.6, 8.0)
	elif e is InputEventMouseMotion and _drag:
		yaw += e.relative.x * 0.012
		pitch = clampf(pitch + e.relative.y * 0.008, -0.9, 0.9)
		_idle = 0.0

func _process(dt: float) -> void:
	if _pivot == null: return
	_t += dt
	_idle += dt
	if not _drag and _idle > 1.5:   # left alone: a slow turn, easing the tilt level
		yaw = lerpf(yaw, sin(_t * 0.6) * 0.55, 1.0 - exp(-dt * 0.8))
		pitch = lerpf(pitch, 0.08, 1.0 - exp(-dt * 1.5))
	_pivot.rotation = Vector3(pitch, yaw, 0)
	dist = lerpf(dist, dist_goal, 1.0 - exp(-dt * 8.0))
	_cam.position = Vector3(0, 0, dist)

## the 2D screen of the unit, in HUD pixels (scaled up by `k` into the texture)
class Face extends Control:
	var unit := ComputerUnits.get_unit("classic")
	var k := 2.0
	var page_i := 0
	var _t := 0.0
	const LCD := Color("eceee8")
	const SHOW := [0, 1, 5]   # the pages this mock-up can draw
	func _process(dt: float) -> void:
		_t += dt
		var pages: Array = []
		for p in unit.order:
			if p in SHOW: pages.append(p)
		if pages.is_empty(): pages = [0]
		page_i = int(_t / 3.0) % pages.size()
		queue_redraw()
	func _page() -> int:
		var pages: Array = []
		for p in unit.order:
			if p in SHOW: pages.append(p)
		if pages.is_empty(): pages = [0]
		return pages[page_i % pages.size()]
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
		var f := UITheme.lcd_font()
		var sz := BASE
		var ink := Color("111417")
		draw_style_box(UITheme.box(unit.body, 16, 0), Rect2(Vector2.ZERO, sz))
		# a thin accent line along the top: the model's colour
		draw_rect(Rect2(34, 5, sz.x - 68, 2), unit.accent)
		var scr := Rect2(7, 20, sz.x - 14, sz.y - 50)
		draw_style_box(UITheme.box(LCD, 6, 0), scr)
		var x0 := scr.position.x + 6
		var w := scr.size.x - 12
		var titles := {0: "RIDE", 1: "TRIP", 5: "MAP"}
		var pg := _page()
		draw_rect(Rect2(scr.position.x, scr.position.y, sz.x - 14, 14), ink)
		draw_string(f, Vector2(x0, scr.position.y + 11), "12:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f2f3ef"))
		draw_string(f, Vector2(x0, scr.position.y + 11), titles[pg], HORIZONTAL_ALIGNMENT_CENTER, w, 9, Color(0.95, 0.95, 0.94, 0.75))
		var br := Rect2(scr.end.x - 22, scr.position.y + 4, 14, 7)
		draw_rect(br, Color(0.95, 0.95, 0.94, 0.8), false, 1.0)
		draw_rect(Rect2(br.position.x + 1.5, br.position.y + 1.5, (br.size.x - 3) * 0.8, br.size.y - 3), Color("8be36a"))
		var y := scr.position.y + 28
		match pg:
			0:
				var v := 38.0 + sin(_t * 1.3) * 6.0
				draw_string(f, Vector2(x0, y), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0, y), "km/h", HORIZONTAL_ALIGNMENT_RIGHT, w, 9, Color(ink, 0.7))
				draw_string(f, Vector2(x0, y + 36), "%.1f" % v, HORIZONTAL_ALIGNMENT_RIGHT, w, 38 if v < 100 else 30, ink)
				y += 46
				draw_line(Vector2(scr.position.x, y), Vector2(scr.end.x, y), Color(ink, 0.22))
				draw_string(f, Vector2(x0, y + 12), "SLOPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 12), "GRADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0, y + 32), "-9°", HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
				draw_string(f, Vector2(x0 + w * 0.5 + 4, y + 32), "-16%", HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 4, 18, ink)
				draw_line(Vector2(scr.position.x + scr.size.x * 0.5, y), Vector2(scr.position.x + scr.size.x * 0.5, y + 40), Color(ink, 0.22))
				if unit.nav:   # the trail alert drops over the lower half
					var top := scr.position.y + 76
					var bx := Rect2(scr.position.x + 3, top, scr.size.x - 6, scr.end.y - top - 3)
					HudScript.GaugeView.draw_alert(self, bx, {"kind": "HR", "text": "HAIRPIN RIGHT", "d": 120.0 - fmod(_t * 12.0, 100.0)}, f)
			1:
				draw_string(f, Vector2(x0, y), "RIDE TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
				draw_string(f, Vector2(x0, y + 36), "%d:%02d" % [int(_t * 7.0) / 60, int(_t * 7.0) % 60], HORIZONTAL_ALIGNMENT_RIGHT, w, 38, ink)
				y += 46
				for row in 2:
					draw_line(Vector2(scr.position.x, y), Vector2(scr.end.x, y), Color(ink, 0.22))
					draw_string(f, Vector2(x0, y + 12), ["DIST km", "MAX"][row], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(ink, 0.6))
					draw_string(f, Vector2(x0, y + 32), ["3.42", "61.8"][row], HORIZONTAL_ALIGNMENT_RIGHT, w, 18, ink)
					y += 40
			_:   # MAP: contours, the trail, you
				var c := scr.position + Vector2(0, 14)
				var r := Rect2(c, Vector2(scr.size.x, scr.size.y - 14))
				for i in 5:
					var rad := 12.0 + i * 15.0
					draw_arc(r.get_center() + Vector2(14, 20), rad, 0.0, TAU, 40, Color(ink, 0.18 if i % 2 else 0.3), 1.0)
				var pts := PackedVector2Array()
				for i in 14:
					var tt := i / 13.0
					pts.append(Vector2(r.position.x + 20 + sin(tt * 5.0) * 22 + tt * 36, r.end.y - 8 - tt * (r.size.y - 16)))
				draw_polyline(pts, Color("d8344a"), 2.0)
				var me := pts[4 + int(_t) % 6]
				draw_circle(me, 3.5, ink)
				draw_arc(me, 7.0, 0, TAU, 20, Color(ink, 0.5), 1.0)
		# bezel: page buttons + dots under the screen
		for i in 2:
			var b := Rect2(12 if i == 0 else sz.x - 46, sz.y - 23, 34, 14)
			draw_style_box(UITheme.box(Color("2b2e32"), 7, 0, Color(1, 1, 1, 0.1), 1), b)
			var cc := b.get_center()
			var sg := 1.0 if i == 1 else -1.0
			draw_colored_polygon(PackedVector2Array([cc + Vector2(-3 * sg, -4), cc + Vector2(-3 * sg, 4), cc + Vector2(3 * sg, 0)]), Color("b8bcc0"))
		var np: int = unit.order.size()
		for j in np:
			draw_circle(Vector2(sz.x / 2 + (j - (np - 1) / 2.0) * 8, sz.y - 16), 2.2, Color("d8dbd6") if j == 0 else Color("3a3d41"))
