class_name SignTex
## The distance sign's plate texture, printed once per distance (Figma "table sign" layout: blue field with the
## number in Barlow Condensed Black, white strip with DISTANCE in tracked-out Barlow Black). Drawn into a 512 px
## SubViewport, read back once with mipmaps, cached: a sign costs one textured box, no text nodes.
## material(km) returns at once (blank plate) and gets its texture a frame or two later.

const SIZE := 512
const BLUE := Color8(0, 4, 255)
const INK := Color8(49, 49, 49)
const STRIP := 762.0 / 1024.0   # where the white strip starts (of the height)

static var _mats := {}


static func material(km: int) -> ShaderMaterial:
	if _mats.has(km):
		return _mats[km]
	var m := TerrainGeo.MAT["signboard"].duplicate() as ShaderMaterial
	_mats[km] = m
	_print.call_deferred(km, m)
	return m


static func _print(km: int, m: ShaderMaterial) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Control.new()
	c.size = Vector2(SIZE, SIZE)
	c.draw.connect(_draw.bind(c, "%dKM" % km))
	vp.add_child(c)
	tree.root.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if is_instance_valid(vp):
		var img := vp.get_texture().get_image()
		img.generate_mipmaps()
		m.set_shader_parameter("board_tex", ImageTexture.create_from_image(img))
		vp.queue_free()


## text placed by cap height (caps = 0.7 em in Barlow), centred, shrunk to fit its width
static func _text(c: Control, font: Font, text: String, cy: float, cap: float, max_w: float, col: Color) -> void:
	var fs := int(cap / 0.7)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > max_w:
		fs = int(fs * max_w / w)
		w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, Vector2((SIZE - w) / 2.0, cy + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _draw(c: Control, num: String) -> void:
	var s := float(SIZE)
	c.draw_rect(Rect2(0, 0, s, s * STRIP), BLUE)
	c.draw_rect(Rect2(0, s * STRIP, s, s * (1.0 - STRIP)), Color.WHITE)
	_text(c, UITheme.display_font(900), num, s * 0.373, s * 0.26, s * 0.9, Color.WHITE)
	var lab := FontVariation.new()
	lab.base_font = UITheme.font(true)
	lab.spacing_glyph = 12
	_text(c, lab, "DISTANCE", s * 0.872, s * 0.1, s * 0.8, INK)
