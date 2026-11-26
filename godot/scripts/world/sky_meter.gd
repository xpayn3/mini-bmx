class_name SkyMeter
extends SubViewport
## A light meter for the sky (2026-11-26). The sky shader draws photographs / procedural skies whose brightness has no
## physical scale, but the sky is what lights the shade (ambient), the reflections and the fog. This measures what the sky
## really gives: a 2 x 1 pixel view, in a world of its own, of a flat white card lit by the same sky material (left pixel)
## and an unlit stamp card (right) that says which request a render belongs to. Game scales the sky (light_energy / energy)
## so its light on flat ground is what SunSky says a real clear sky gives next to that sun.
## Rendered only when asked (a light change, at most a few times a second, ~4 tiny frames each).
## The sun copy is at ~zero energy: the sky shader only needs its direction (LIGHT0), its light must not reach the card.
## Check: -s res://tools/sky_meter_probe.gd (the card follows the sky's light_energy 1:1).

var sky_env := Environment.new()
var cam := Camera3D.new()
var key := DirectionalLight3D.new()
var _wait := -1
var _cb: Callable
var _stamp := 0
var _stamp_mat := StandardMaterial3D.new()
const MAX_WAIT := 14   # frames to wait for the render that carries this request's stamp
const SETTLE := 3      # frames rendered before the first read (the sky's radiance is redone on them)

func _init(sky_material: Material) -> void:
	size = Vector2i(2, 1)
	own_world_3d = true
	use_hdr_2d = true
	transparent_bg = false
	msaa_3d = Viewport.MSAA_DISABLED
	screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	positional_shadow_atlas_size = 0
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var sky := Sky.new()
	sky.sky_material = sky_material   # the very material the game's sky uses: same uniforms, same picture
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky_env.sky = sky
	sky_env.background_mode = Environment.BG_COLOR
	sky_env.background_color = Color.BLACK
	sky_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	sky_env.ambient_light_sky_contribution = 1.0
	sky_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	sky_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = sky_env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 5, 0)
	cam.rotation = Vector3(-PI * 0.5, 0, 0)
	add_child(cam)
	for i in 2:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.2)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.WHITE
		m.roughness = 1.0
		m.metallic_specular = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.disable_receive_shadows = true
		if i == 1:   # the stamp: an unlit card whose colour says which request this render is for
			m = _stamp_mat
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.material = m
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(-0.5 + i, 0, 0)
		add_child(mi)
	key.shadow_enabled = false
	key.light_energy = 0.0001   # its direction is the sky shader's LIGHT0 (sun / moon); its light must not touch the card
	add_child(key)

## measure the sky with the key light pointing this way (dir = toward the sun / moon); cb(sky: Color) gets the white card's
## linear colour in the shade (engine units), or Color(-1, -1, -1) if no fresh render came back
func measure(dir: Vector3, cb: Callable) -> void:
	key.look_at_from_position(dir, Vector3.ZERO, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
	_stamp = _stamp % 60 + 1
	_stamp_mat.albedo_color = Color(float(_stamp) / 64.0, 0.0, 0.0)
	_cb = cb
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_wait = MAX_WAIT

func busy() -> bool:
	return _wait >= 0

func _decode(c: Color, hdr: bool) -> Color:
	return c if hdr else c.srgb_to_linear()   # the float buffer holds linear values

func _process(_dt: float) -> void:
	if _wait < 0: return
	_wait -= 1
	if _wait < MAX_WAIT - SETTLE:
		var img := get_texture().get_image()
		if img != null and img.get_width() >= 2:
			var hdr := img.get_format() >= Image.FORMAT_RF and img.get_format() <= Image.FORMAT_RGBE9995   # float formats (RGBH here)
			var a := _decode(img.get_pixel(0, 0), hdr)
			var st := _decode(img.get_pixel(1, 0), hdr)
			var want := Color(float(_stamp) / 64.0, 0.0, 0.0).srgb_to_linear().r
			if absf(st.r - want) < 0.003 + 0.01 * want:   # this request's render
				_finish(Color(a.r, a.g, a.b))
				return
	if _wait == 0: _finish(Color(-1, -1, -1))   # gave up: no fresh render

func _finish(c: Color) -> void:
	_wait = -1
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _cb.is_valid(): _cb.call(c)
