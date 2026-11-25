class_name SignTex
## Printed sign faces, made once per look and cached: the distance sign's plate (Figma "table sign" layout: blue field
## with the number in Barlow Condensed Black, white strip with DISTANCE in tracked-out Barlow Black), the roadside
## billboards' and the gantries' sponsor boards (sponsor colour + name). Drawn into a SubViewport, read back once,
## mipmapped and block-compressed (DXT1: ~1/6 of the raw size), worn by shaders/sign_board.gdshader. A sign is then one
## textured box: no text nodes. Each call returns its material at once (blank print) and the print lands a frame or two later.

const BLUE := Color8(0, 4, 255)
const INK := Color8(49, 49, 49)
const STRIP := 762.0 / 1024.0   # where the distance plate's white strip starts (of the height)

static var _mats := {}


## the distance sign: 0.8 m square aluminium plate, reflective sheeting, mud from the trail
static func material(km: int) -> ShaderMaterial:
	return _make("km%d" % km, Vector2i(512, 512), _draw_km.bind("%dKM" % km),
		{"plate_m": Vector2(0.8, 0.8), "retro": 6.0, "wood_mix": 0.0, "planks": 0.0, "mud_amt": 1.0, "both_sides": false})


## a roadside billboard: painted wooden planks with the sponsor's name, both sides, mud low down
static func billboard(sp: Array, size: Vector2, planks: int) -> ShaderMaterial:
	return _make("bb_%s_%.1f" % [sp[0], size.x], _px(size), _draw_name.bind(sp),
		{"plate_m": size, "retro": 0.0, "wood_mix": 1.0, "planks": float(planks), "mud_amt": 1.0, "both_sides": true})


## a gantry banner high over the trail: printed panel, both sides, weathered, no mud up there
static func banner(sp: Array, size: Vector2) -> ShaderMaterial:
	return _make("gb_%s_%.1f" % [sp[0], size.x], _px(size), _draw_name.bind(sp),
		{"plate_m": size, "retro": 0.0, "wood_mix": 0.0, "planks": 0.0, "mud_amt": 0.0, "both_sides": true, "wear": 0.7})


static func _px(size: Vector2) -> Vector2i:
	var w := 1024
	return Vector2i(w, clampi(int(round(w * size.y / size.x / 4.0)) * 4, 64, 1024))


static func _make(key: String, px: Vector2i, draw: Callable, params: Dictionary) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := TerrainGeo.MAT["signboard"].duplicate() as ShaderMaterial
	for k in params:
		m.set_shader_parameter(k, params[k])
	_mats[key] = m
	_print.call_deferred(px, draw, m)
	return m


static func _print(px: Vector2i, draw: Callable, m: ShaderMaterial) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Control.new()
	c.size = Vector2(px)
	c.draw.connect(draw.bind(c))
	vp.add_child(c)
	tree.root.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.convert(Image.FORMAT_RGB8)
	if Env.s("BMX_SIGN_DUMP") != "":   # test: the printed faces as PNGs (dir)
		img.save_png("%s/sign_%d.png" % [Env.s("BMX_SIGN_DUMP"), _mats.size()])
	img.generate_mipmaps()
	if Env.s("BMX_SIGN_RAW") == "":
		img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
	m.set_shader_parameter("board_tex", ImageTexture.create_from_image(img))


## text placed by cap height (caps = 0.7 em in Barlow), centred on x / cy, shrunk to fit its width
static func _text(c: Control, font: Font, text: String, cy: float, cap: float, max_w: float, col: Color) -> void:
	var fs := int(cap / 0.7)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > max_w:
		fs = int(fs * max_w / w)
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, Vector2((c.size.x - w) / 2.0, cy + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _label_font(track: int) -> Font:
	var lab := FontVariation.new()
	lab.base_font = UITheme.font(true)
	lab.spacing_glyph = track
	return lab


static func _draw_km(c: Control, num: String) -> void:   # (bound args come after the control)
	var s := c.size.x
	c.draw_rect(Rect2(0, 0, s, s * STRIP), BLUE)
	c.draw_rect(Rect2(0, s * STRIP, s, s * (1.0 - STRIP)), Color.WHITE)
	_text(c, UITheme.display_font(900), num, s * 0.373, s * 0.26, s * 0.9, Color.WHITE)
	_text(c, _label_font(12), "DISTANCE", s * 0.872, s * 0.1, s * 0.8, INK)


## a sponsor board: its colour, its name big in Barlow Condensed Black, a thin rule above and below
static func _draw_name(c: Control, sp: Array) -> void:
	var w := c.size.x
	var h := c.size.y
	var bg := Color.html("#%06x" % sp[1])
	var fg := Color.html("#%06x" % sp[2])
	c.draw_rect(Rect2(Vector2.ZERO, c.size), bg)
	var r := h * 0.06
	c.draw_rect(Rect2(w * 0.04, h * 0.1, w * 0.92, r * 0.5), fg)
	c.draw_rect(Rect2(w * 0.04, h * 0.9 - r * 0.5, w * 0.92, r * 0.5), fg)
	_text(c, UITheme.display_font(900), String(sp[0]), h * 0.5, h * 0.5, w * 0.86, fg)


## the material for a chunk panel's printed plate (Terrain._panel_labels, the smash debris): {km} or {sp, size, planks}
static func for_plate(p: Dictionary) -> ShaderMaterial:
	if p.has("km"):
		return material(p["km"])
	return billboard(p["sp"], p["size"], p["planks"])
