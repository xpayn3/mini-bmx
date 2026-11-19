class_name StrapLogo
extends Node
## Bakes a brand wordmark (white lettering on transparent) into the texture of the goggle-strap logo material.
## The lettering is drawn once by a throw-away SubViewport and then copied into an ImageTexture (with mipmaps),
## after which this node and the viewport free themselves. The material's albedo_color tints it (white / black).

const PX_W := 700               # texture size: matches the printed stretch of strap (0.27 m x ~0.039 m)
const PX_H := 100

var mat: StandardMaterial3D
var text := "GIANT"
var _vp: SubViewport
var _frames := 0


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(PX_W, PX_H)
	_vp.disable_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := Control.new()
	root.size = Vector2(PX_W, PX_H)
	_vp.add_child(root)
	var fv := FontVariation.new()
	fv.base_font = UITheme.font(true)
	fv.spacing_glyph = 14
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = fv
	ls.font_size = 90
	ls.font_color = Color.WHITE
	l.label_settings = ls
	l.text = text
	l.size = Vector2(PX_W, PX_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(l)
	add_child(_vp)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames < 5:
		return
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(img)
	queue_free()
