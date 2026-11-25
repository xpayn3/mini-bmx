class_name CollectStage
extends SubViewportContainer
## The 3D badge viewer on the profile's BADGES tab, after CycleIQ's badges: `show_badge(id, got)` = the badge's own shape (circle, hexagon, diamond, star or
## shield: `Collection.badge_look`) extruded in tier metal (bronze .. platinum), a glassy enamel inset in the badge's colour and its symbol raised on both
## faces, in a plain studio environment. Drag to spin it (it carries on turning, then settles
## into a slow turn). One shared viewport with a transparent background.

var vp := SubViewport.new()
var cam := Camera3D.new()
var holder := Node3D.new()
var _drag := false
var _spin := 0.0          # rad/s of the free spin
var _t := 0.0

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	add_child(vp)
	var sky := Sky.new()
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = BikeTurntable._studio_hdri()
	sky.sky_material = pm
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.1; key.rotation_degrees = Vector3(-30, 25, 0)
	vp.add_child(key)
	cam.fov = 32.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 6.2), Vector3.ZERO)
	vp.add_child(holder)

## an extruded shape (front, back, walls) from an outline
func _extrude(pts: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(pts)
	var n := pts.size()
	for i in range(0, idx.size(), 3):
		for k in 3: st.set_normal(Vector3(0, 0, 1)); st.add_vertex(Vector3(pts[idx[i + k]].x, pts[idx[i + k]].y, depth * 0.5))
		for k in [2, 1, 0]: st.set_normal(Vector3(0, 0, -1)); st.add_vertex(Vector3(pts[idx[i + k]].x, pts[idx[i + k]].y, -depth * 0.5))
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var nrm := Vector3(b.y - a.y, -(b.x - a.x), 0).normalized()
		for v in [Vector3(a.x, a.y, depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(a.x, a.y, depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(a.x, a.y, -depth * 0.5)]:
			st.set_normal(nrm); st.add_vertex(v)
	return st.commit()

func _metal(col: Color, rough := 0.25, metal := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.metallic = metal; m.roughness = rough
	return m

func show_badge(id: String, got: bool) -> void:
	for c in holder.get_children(): c.queue_free()
	holder.rotation = Vector3.ZERO
	var look := Collection.badge_look(id)
	var tier: Color = Collection.TIERS[Collection.badge_tier(id)][1]
	var enamel: Color = look.color
	var accent: Color = look.accent
	if not got:
		tier = Color("6b7280"); enamel = Color("2b303c"); accent = Color("464c5c")
	var k := 1.35   # the shape fills the stage
	var pts := Collection.shape_points(String(look.shape), k)
	# the body in tier metal, with a bright thin rim
	var body := MeshInstance3D.new()
	body.mesh = _extrude(pts, 0.22)
	var bm := _metal(tier, 0.22, 0.9)
	bm.emission_enabled = true; bm.emission = tier; bm.emission_energy_multiplier = 0.18
	body.material_override = bm
	holder.add_child(body)
	# the enamel: a smaller glassy copy on both faces
	var inner := PackedVector2Array()
	for p in pts: inner.append(p * 0.80)
	for side in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.mesh = _extrude(inner, 0.02)
		var em := _metal(enamel, 0.1, 0.45)
		em.emission_enabled = true; em.emission = enamel; em.emission_energy_multiplier = 0.28
		face.material_override = em
		face.position = Vector3(0, 0, 0.115 * side)
		holder.add_child(face)
		# the symbol, raised
		var g := MeshInstance3D.new()
		var tx := TextMesh.new()
		tx.text = String(look.glyph) if got else "?"
		tx.font = UITheme.font(true); tx.font_size = 220; tx.pixel_size = 0.0058; tx.depth = 0.04
		g.mesh = tx
		var gm := _metal(accent.lightened(0.45) if got else Color("464c5c"), 0.18, 0.6)
		gm.emission_enabled = true; gm.emission = accent if got else Color.BLACK; gm.emission_energy_multiplier = 0.45
		g.material_override = gm
		g.position = Vector3(0, 0, 0.16 * side)
		if side < 0: g.rotation_degrees.y = 180
		holder.add_child(g)
	holder.rotation_degrees = Vector3(-10, 30, 0)
	_spin = 1.6

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	_t += dt
	if not _drag:
		holder.rotation.y += _spin * dt
		_spin = lerpf(_spin, 0.55, minf(1.0, dt * 0.8))   # settles into a slow turn
		holder.rotation.x = lerpf(holder.rotation.x, deg_to_rad(-8.0 + sin(_t * 0.9) * 4.0), minf(1.0, dt * 3.0))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		holder.rotation.y += mm.relative.x * 0.012
		holder.rotation.x = clampf(holder.rotation.x + mm.relative.y * 0.008, -0.9, 0.9)
		_spin = mm.relative.x * 0.012 * 60.0
