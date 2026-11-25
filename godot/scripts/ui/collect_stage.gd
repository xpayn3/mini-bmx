class_name CollectStage
extends SubViewportContainer
## A little 3D stage on the profile (BADGES and CARDS tabs): `show_badge(id, got)` = a metal medal you drag to spin (it carries on turning),
## `show_card(id, got)` = a holo card that tilts towards the mouse, foil rainbow + sparkle + glare moving with the tilt (drag to turn it further).
## One shared viewport, transparent background, the studio HDRI for reflections.

var vp := SubViewport.new()
var cam := Camera3D.new()
var holder := Node3D.new()
var _mode := ""
var _drag := false
var _spin := 0.0          # rad/s of the free spin (badge)
var _rx := 0.0
var _ry := 0.0
var _tilt_t := Vector2.ZERO   # card: target tilt from the mouse
var _t := 0.0
var _env: Environment
var _sky_studio: Sky
var _sky_rainbow: Sky
var _spot: OmniLight3D
var _free_spin := false   # the rider card: drag turns it all the way round (front / date back)
var _spin_y := 0.0
static var _rainbow: ImageTexture

const HOLO_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform sampler2D face : source_color, filter_linear_mipmap;
uniform sampler2D back_tex : source_color, filter_linear_mipmap;
uniform sampler2D mask : source_color, filter_linear_mipmap;
uniform float holo = 0.6;
uniform vec3 rcol : source_color = vec3(0.3);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 pal(float t) { return 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + t)); }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(0.692, 1.0);
	vec2 q = abs(p) - (vec2(0.346, 0.5) - vec2(0.05));
	float d = length(max(q, vec2(0.0))) - 0.05;
	if (d > 0.0) discard;
	vec4 base = FRONT_FACING ? texture(face, UV) : texture(back_tex, vec2(1.0 - UV.x, UV.y));
	float m = FRONT_FACING ? texture(mask, UV).r : 0.35;
	vec3 N = normalize(NORMAL);
	if (!FRONT_FACING) N = -N;
	vec2 tl = N.xy;
	float hue = UV.x * 0.8 + UV.y * 0.6 + tl.x * 1.6 - tl.y * 1.2;
	vec3 rainbow = pal(hue);
	float lines = 0.5 + 0.5 * sin((UV.x + UV.y * 0.7) * 90.0 + hue * 30.0);
	vec2 g = floor(UV * vec2(72.0, 104.0));
	float sp = step(0.985, hash(g)) * (0.5 + 0.5 * sin(TIME * 3.0 + hash(g + 3.0) * 30.0 + tl.x * 24.0)) * (0.3 + m);
	float glare = pow(max(0.0, 1.0 - length(UV - (vec2(0.5) - tl * 1.1)) * 1.7), 3.0);
	vec3 foil = rainbow * (0.35 + 0.65 * lines) * (0.05 + 1.5 * m) + vec3(sp) * (0.4 + m) + vec3(glare) * (0.08 + 0.9 * m);
	float tilt = clamp(length(tl) * 2.6, 0.0, 1.0);
	float amt = holo * (0.06 + 0.94 * tilt);
	ALBEDO = base.rgb;
	EMISSION = foil * amt * (FRONT_FACING ? 1.0 : 0.25);
	ALBEDO = mix(ALBEDO, rcol, smoothstep(-0.020, -0.008, d));
	ROUGHNESS = mix(0.7, 0.25, m);
	METALLIC = 0.0;
	SPECULAR = 0.08 + 0.5 * m;
}
"""

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
	_env = env
	_sky_studio = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.1; key.rotation_degrees = Vector3(-30, 25, 0)
	vp.add_child(key)
	_spot = OmniLight3D.new()   # the glare hot spot: it moves with the tilt
	_spot.light_energy = 0.0; _spot.omni_range = 9.0
	vp.add_child(_spot)
	cam.fov = 32.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 7.2), Vector3.ZERO)
	vp.add_child(holder)

## CycleIQ's reflection map: three cycles of spectrum over near-black, a bright studio hot spot, fine scanlines; made once
static func _rainbow_tex() -> ImageTexture:
	if _rainbow != null: return _rainbow
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color("080808"))
	var spec := [Color("ff2a6d"), Color("ff8c00"), Color("f5d300"), Color("01ff89"), Color("05d9e8"), Color("4a9eff"), Color("9b59ff"), Color("ff2a6d")]
	for x in w:
		var t := fmod(float(x) / w * 3.0, 1.0) * (spec.size() - 1)
		var i := mini(int(t), spec.size() - 2)
		var c: Color = (spec[i] as Color).lerp(spec[i + 1], t - i)
		img.fill_rect(Rect2i(x, 0, 1, h), Color("080808").lerp(c, 0.55))
	var cx := int(w * 0.43)
	var cy := int(h * 0.43)
	var rad := int(w * 0.16)
	for y in range(maxi(0, cy - rad), mini(h, cy + rad)):
		for x in range(maxi(0, cx - rad), mini(w, cx + rad)):
			var k := 1.0 - Vector2(x - cx, y - cy).length() / rad
			if k > 0.0: img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color.WHITE, k * k))
	for y in range(0, h, 4):
		for x in w:
			var c2 := img.get_pixel(x, y)
			img.set_pixel(x, y, c2.lerp(Color.BLACK if y % 8 == 0 else Color.WHITE, 0.10))
	_rainbow = ImageTexture.create_from_image(img)
	return _rainbow

func _use_rainbow(on: bool) -> void:
	if on and _sky_rainbow == null:
		_sky_rainbow = Sky.new()
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = _rainbow_tex()
		_sky_rainbow.sky_material = pm
	_env.sky = _sky_rainbow if on else _sky_studio
	_spot.light_energy = 3.5 if on else 0.0

## an extruded shape (front, back, walls) from an outline in card units
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

func _clear() -> void:
	for c in holder.get_children(): c.queue_free()
	holder.rotation = Vector3.ZERO
	_rx = 0.0; _ry = 0.0; _spin = 0.0

func _metal(col: Color, rough := 0.25, metal := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col; m.metallic = metal; m.roughness = rough
	return m

## a medal: metal disc + rim, an enamel face in the badge's colour and its glyph embossed on both sides
func show_badge(id: String, got: bool) -> void:
	_clear()
	_mode = "badge"
	_use_rainbow(false)
	var tier: Color = Collection.TIERS[Collection.badge_tier(id)][1]
	var enamel: Color = Collection.badge_colour(id)
	if not got:
		tier = Color("6b7280"); enamel = Color("2b303c")
	var coin := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 1.0; cm.bottom_radius = 1.0; cm.height = 0.16; cm.radial_segments = 96
	coin.mesh = cm; coin.material_override = _metal(tier, 0.22)
	coin.rotation_degrees.x = 90
	holder.add_child(coin)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.93; tm.outer_radius = 1.03; tm.rings = 96; tm.ring_segments = 16
	rim.mesh = tm; rim.material_override = _metal(tier.lightened(0.2), 0.15)
	rim.rotation_degrees.x = 90
	holder.add_child(rim)
	var face := MeshInstance3D.new()
	var fm := CylinderMesh.new(); fm.top_radius = 0.80; fm.bottom_radius = 0.80; fm.height = 0.19; fm.radial_segments = 96
	face.mesh = fm; face.material_override = _metal(enamel, 0.12, 0.35)
	face.rotation_degrees.x = 90
	holder.add_child(face)
	var glyph := Collection.badge_glyph(id) if got else "?"
	for side in [1.0, -1.0]:
		var t := MeshInstance3D.new()
		var tx := TextMesh.new()
		tx.text = glyph; tx.font = UITheme.font(true); tx.font_size = 220; tx.pixel_size = 0.0042; tx.depth = 0.05
		t.mesh = tx
		t.material_override = _metal(tier.lightened(0.35) if got else Color("464c5c"), 0.18)
		t.position = Vector3(0, 0, 0.1 * side)
		if side < 0: t.rotation_degrees.y = 180
		holder.add_child(t)
	holder.rotation_degrees = Vector3(-12, 28, 0)
	_spin = 1.4

## a card (CycleIQ style): the rendered face on a rounded slab with the holo-foil shader driven by the pattern mask, the real extruded shape
## floating over it, reflecting the rainbow environment; `look` = Collection.badge_look / card_look. spin_free = the rider card (drag it all the way round)
func show_card(look: Dictionary, got: bool, face: Texture2D, back: Texture2D, mask: Texture2D, spin_free := false) -> void:
	_clear()
	_mode = "card"
	_free_spin = spin_free
	_spin_y = 0.0
	_use_rainbow(true)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(1.8, 2.6)
	mi.mesh = q
	var sh := Shader.new(); sh.code = HOLO_SHADER
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("face", face)
	m.set_shader_parameter("back_tex", back)
	m.set_shader_parameter("mask", mask)
	m.set_shader_parameter("holo", float(look.get("strength", 0.8)) if got else 0.0)
	var col: Color = look.get("color", Color("4aa3ff"))
	m.set_shader_parameter("rcol", col.darkened(0.2) if got else Color("3a4156"))
	mi.material_override = m
	holder.add_child(mi)
	var pts := Collection.shape_points(String(look.get("shape", ""))) if look.has("shape") and look.shape != "" else PackedVector2Array()
	if pts.size() >= 3:
		var shape_col: Color = col if got else Color("4a5164")
		var base := MeshInstance3D.new()
		base.mesh = _extrude(pts, 0.10)
		var bm := _metal(shape_col.darkened(0.1), 0.28, 0.55)
		bm.emission_enabled = true
		bm.emission = shape_col
		bm.emission_energy_multiplier = 0.35
		base.material_override = bm
		base.position = Vector3(0, 0.18, 0.08)
		holder.add_child(base)
		var inner := PackedVector2Array()
		for p in pts: inner.append(p * 0.82)
		var glass := MeshInstance3D.new()
		glass.mesh = _extrude(inner, 0.02)
		var gm := _metal((look.get("accent", shape_col) as Color).lightened(0.2) if got else Color("6b7280"), 0.1, 0.5)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.albedo_color.a = 0.62
		gm.emission_enabled = true
		gm.emission = (look.get("accent", shape_col) as Color) if got else Color("6b7280")
		gm.emission_energy_multiplier = 0.25
		glass.material_override = gm
		glass.position = Vector3(0, 0.18, 0.145)
		holder.add_child(glass)
		if String(look.get("glyph", "")) != "":   # the symbol, raised on the shape
			var gl := MeshInstance3D.new()
			var gt := TextMesh.new()
			gt.text = String(look.glyph) if got else "?"
			gt.font = UITheme.font(true); gt.font_size = 200; gt.pixel_size = 0.0036; gt.depth = 0.03
			gl.mesh = gt
			var glm := _metal((look.get("accent", shape_col) as Color).lightened(0.5) if got else Color("464c5c"), 0.2, 0.6)
			glm.emission_enabled = true
			glm.emission = (look.get("accent", shape_col) as Color) if got else Color.BLACK
			glm.emission_energy_multiplier = 0.45
			gl.material_override = glm
			gl.position = Vector3(0, 0.18, 0.17)
			holder.add_child(gl)
	_tilt_t = Vector2.ZERO

func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	_t += dt
	if _mode == "badge":
		if not _drag:
			holder.rotation.y += _spin * dt
			_spin = lerpf(_spin, 0.55, minf(1.0, dt * 0.8))   # settles into a slow turn
			holder.rotation.x = lerpf(holder.rotation.x, deg_to_rad(-10.0 + sin(_t * 0.9) * 4.0), minf(1.0, dt * 3.0))
	elif _mode == "card":
		var yaw := _tilt_t.x * 0.7 + _ry + cos(_t * 0.55) * 0.08
		if _free_spin:
			if not _drag: _ry = lerpf(_ry, roundf(_ry / PI) * PI, minf(1.0, dt * 3.0))   # settles on a face
			yaw = _ry + _tilt_t.x * 0.25
		var want := Vector3(_tilt_t.y * 0.55 + sin(_t * 0.7) * 0.05, yaw, 0.0)
		holder.rotation = holder.rotation.lerp(want, minf(1.0, dt * 9.0))
		_spot.position = Vector3(-_tilt_t.x * 2.2, 1.0 - _tilt_t.y * 1.6, 3.2)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
		if not _drag and _mode == "card" and not _free_spin: _ry = 0.0
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _mode == "badge" and _drag:
			holder.rotation.y += mm.relative.x * 0.012
			holder.rotation.x = clampf(holder.rotation.x + mm.relative.y * 0.008, -0.9, 0.9)
			_spin = mm.relative.x * 0.012 * 60.0
		elif _mode == "card":
			var c := size * 0.5
			_tilt_t = Vector2(clampf((mm.position.x - c.x) / maxf(c.x, 1.0), -1.2, 1.2), clampf((mm.position.y - c.y) / maxf(c.y, 1.0), -1.2, 1.2))
			if _drag: _ry += mm.relative.x * (0.012 if _free_spin else 0.01)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT: _tilt_t = Vector2.ZERO
