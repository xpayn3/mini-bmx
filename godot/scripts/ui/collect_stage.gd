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

const HOLO_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
uniform sampler2D face : source_color, filter_linear_mipmap;
uniform sampler2D back_tex : source_color, filter_linear_mipmap;
uniform float holo = 0.6;
uniform vec3 rcol : source_color = vec3(0.3);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 pal(float t) { return 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + t)); }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(0.714, 1.0);
	vec2 q = abs(p) - (vec2(0.357, 0.5) - vec2(0.055));
	float d = length(max(q, vec2(0.0))) - 0.055;
	if (d > 0.0) discard;
	vec4 base = FRONT_FACING ? texture(face, UV) : texture(back_tex, vec2(1.0 - UV.x, UV.y));
	vec3 N = normalize(NORMAL);
	if (!FRONT_FACING) N = -N;
	vec2 tl = N.xy;
	float hue = UV.x * 0.7 + UV.y * 0.5 + tl.x * 1.4 - tl.y * 1.1;
	vec3 rainbow = pal(hue);
	float lines = 0.5 + 0.5 * sin((UV.x + UV.y * 0.7) * 80.0 + hue * 28.0);
	vec2 g = floor(UV * vec2(70.0, 98.0));
	float sp = step(0.982, hash(g)) * (0.5 + 0.5 * sin(TIME * 3.0 + hash(g + 3.0) * 30.0 + tl.x * 24.0));
	float glare = pow(max(0.0, 1.0 - length(UV - (vec2(0.5) - tl * 1.0)) * 1.5), 3.0);
	vec3 foil = rainbow * (0.30 + 0.70 * lines) + vec3(sp) + vec3(glare) * 0.55;
	float amt = holo * (0.22 + 0.78 * clamp(length(tl) * 2.4, 0.0, 1.0));
	ALBEDO = base.rgb;
	EMISSION = foil * amt * (FRONT_FACING ? 1.0 : 0.0) * (0.35 + 0.65 * (1.0 - base.a * 0.0));
	ALBEDO = mix(ALBEDO, rcol, smoothstep(-0.022, -0.010, d));
	ROUGHNESS = 0.32;
	SPECULAR = 0.6;
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
	cam.look_at_from_position(Vector3(0, 0, 8.4), Vector3.ZERO)
	vp.add_child(holder)

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

## a card: the rendered face on a rounded quad with the holo foil shader
func show_card(id: String, got: bool, face: Texture2D, back: Texture2D) -> void:
	_clear()
	_mode = "card"
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(2.5, 3.5)
	mi.mesh = q
	var sh := Shader.new(); sh.code = HOLO_SHADER
	var m := ShaderMaterial.new(); m.shader = sh
	var info: Dictionary = Collection.CARDS[id]
	var rar: Dictionary = Collection.RARITY[info.rarity]
	m.set_shader_parameter("face", face)
	m.set_shader_parameter("back_tex", back)
	m.set_shader_parameter("holo", float(rar.holo) if got else 0.0)
	m.set_shader_parameter("rcol", (rar.col as Color).darkened(0.15) if got else Color("3a4156"))
	mi.material_override = m
	holder.add_child(mi)
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
		var want := Vector3(_tilt_t.y * 0.55 + sin(_t * 0.7) * 0.05, _tilt_t.x * 0.7 + _ry + cos(_t * 0.55) * 0.08, 0.0)
		holder.rotation = holder.rotation.lerp(want, minf(1.0, dt * 9.0))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
		if not _drag and _mode == "card": _ry = 0.0
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _mode == "badge" and _drag:
			holder.rotation.y += mm.relative.x * 0.012
			holder.rotation.x = clampf(holder.rotation.x + mm.relative.y * 0.008, -0.9, 0.9)
			_spin = mm.relative.x * 0.012 * 60.0
		elif _mode == "card":
			var c := size * 0.5
			_tilt_t = Vector2(clampf((mm.position.x - c.x) / maxf(c.x, 1.0), -1.2, 1.2), clampf((mm.position.y - c.y) / maxf(c.y, 1.0), -1.2, 1.2))
			if _drag: _ry += mm.relative.x * 0.01

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT: _tilt_t = Vector2.ZERO
