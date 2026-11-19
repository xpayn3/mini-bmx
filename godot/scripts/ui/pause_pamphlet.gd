class_name PausePamphlet
extends PaperSheet
## The pause menu (Esc) as a folded downhill-park leaflet held up in front of you: a real DL tri-fold (three
## 99 x 210 mm panels, letter-folded: the right flap folds in, the cover flap over it). A photo of the spot you
## stopped at on the cover (the last frame of the ride, grabbed before anything is drawn over it), the park's
## name over it, and the menu printed underneath - live buttons: mouse (traced onto the paper), keys and pad.
## Hover / focus = a highlighter swipe. Settings / Controls open the leaflet (open_inside): the flaps swing open
## and the menu is printed across the three inside panels, live; "Fold up" / Esc / B shuts it again.
## Built on PaperSheet (fold_style "letter", starts shut).
## Use: var p := PausePamphlet.new(); p.photo = <Image>; add_child(p); p.add_item("Resume", cb) ...; p.open()

const CW := 600                      # one panel (px): DL, 99 x 210 mm
const CH := 1273
const PHOTO_H := 640
const COVER_Y := CH                  # the cover: the strip under the inside spread (printed on the cover flap's back)
const INSIDE_SCALE := 1.3            # the inside menu, drawn this much bigger than its own pixels (readable)
const INK := Color("1d1f22")
const RED := Color("d22b25")

var photo: Image                     # the ride's last frame
var place := ""                      # the biome under the rider
var sheet_no := 0
var _list: VBoxContainer
var _items := 0
var _font: Font
var _font_b: Font


func _ready() -> void:
	super._ready()
	cols = 3; rows = 1
	panel = Vector2(0.099, 0.21)
	unfold = false
	fold_style = "letter"
	live = true
	auto_close = false
	hold_roll = -0.035
	fill = Vector2(0.9, 0.8)
	open_t = 0.7
	close_t = 0.3
	close_actions = [&"pause", &"ui_cancel"]
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI", "Arial"])
	_font.font_weight = 500
	_font_b = SystemFont.new()
	_font_b.font_names = _font.font_names
	_font_b.font_weight = 800
	setup(Vector2i(CW * 3, CH), Vector2i(CW, CH))   # inside spread + the cover strip under it
	_inside = Control.new()                         # the inside: a menu printed across the three panels
	_inside.scale = Vector2.ONE * INSIDE_SCALE
	_inside.size = Vector2(CW * 3, CH) / INSIDE_SCALE
	content.add_child(_inside)
	var cover := Cover.new()
	cover.owner_p = self
	cover.position = Vector2(0, COVER_Y)
	cover.size = Vector2(CW, CH)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cover)
	_list = VBoxContainer.new()
	_list.position = Vector2(40, COVER_Y + PHOTO_H + 34)
	_list.size = Vector2(CW - 80, CH - PHOTO_H - 120)
	_list.add_theme_constant_override("separation", 2)
	content.add_child(_list)


## a menu line: "01  Resume"
func add_item(text: String, cb: Callable) -> Button:
	_items += 1
	var b := Button.new()
	b.text = "%02d   %s" % [_items, text.to_upper()]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 62)
	b.clip_text = true
	b.add_theme_font_override("font", _font_b)
	b.add_theme_font_size_override("font_size", 33)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_pressed_color", RED)
	b.add_theme_color_override("font_hover_pressed_color", RED)
	var none := StyleBoxEmpty.new()
	none.content_margin_left = 14
	var hi := StyleBoxFlat.new()          # a yellow highlighter swipe
	hi.bg_color = Color(1.0, 0.86, 0.18, 0.75)
	hi.skew = Vector2(-0.18, 0)
	hi.content_margin_left = 14
	hi.set_corner_radius_all(3)
	hi.expand_margin_left = 6
	hi.expand_margin_right = 10
	for st in ["normal", "disabled"]: b.add_theme_stylebox_override(st, none)
	for st in ["hover", "focus", "pressed", "hover_pressed"]: b.add_theme_stylebox_override(st, hi)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): b.grab_focus())   # mouse and pad share one highlight
	_list.add_child(b)
	return b


var _inside: Control
var _inside_menu: Control

## open the leaflet on a menu (Settings / Controls, a MenuBase): printed across the inside, live
func open_inside(menu: Control) -> void:
	if is_instance_valid(_inside_menu): _inside_menu.queue_free()
	menu.paper = true
	var m := 26.0
	menu.paper_size = _inside.size - Vector2(m, m) * 2.0
	menu.position = Vector2(m, m)
	_inside.add_child(menu)
	_inside_menu = menu
	menu.tree_exiting.connect(func(): if _inside_menu == menu: _inside_menu = null; set_unfolded(false); focus_first.call_deferred())
	set_unfolded(true)
	_show_hint()


## shut the leaflet again (back to the cover)
func fold_inside() -> void:
	if is_instance_valid(_inside_menu): _inside_menu.queue_free()   # (its tree_exiting shuts the flaps)
	else: set_unfolded(false)


func prompt_items() -> Array:
	if Settings.pad_active:
		return [[["A"], "Select"], [["B"], "Fold up" if is_unfolded() else "Resume"]]
	return [[["K:Enter"], "Select"], [["MOUSE"], "Click"], [["K:Esc"], "Fold up" if is_unfolded() else "Resume"]]


func set_unfolded(on: bool) -> void:
	super.set_unfolded(on)
	if _hint: _hint.set_items(prompt_items())


func focus_first() -> void:
	if _list.get_child_count() > 0:
		(_list.get_child(0) as Control).grab_focus()


class Cover extends Control:
	var owner_p
	var _photo_tex: ImageTexture
	func _draw() -> void:
		var p = owner_p
		var W := size.x; var H := size.y
		draw_rect(Rect2(0, 0, W, H), Color.WHITE)
		# the photo: the middle of the ride's last frame (the corners hold the HUD), cropped to fill
		if p.photo and _photo_tex == null:
			var im: Image = p.photo
			var want := W / PHOTO_H
			var ch := int(im.get_height() * 0.74)
			var cw := mini(int(ch * want), im.get_width())
			ch = int(cw / want)
			var cx := (im.get_width() - cw) / 2
			var cy := int((im.get_height() - ch) * 0.42)
			var crop := im.get_region(Rect2i(cx, cy, cw, ch))
			crop.resize(int(W), PHOTO_H, Image.INTERPOLATE_LANCZOS)
			_photo_tex = ImageTexture.create_from_image(crop)
		if _photo_tex:
			draw_texture_rect(_photo_tex, Rect2(0, 0, W, PHOTO_H), false, Color(1.04, 1.0, 0.94))
		else:
			draw_rect(Rect2(0, 0, W, PHOTO_H), Color("3d6b54"))
		# a dark fade under the title
		for i in 40:
			var a := float(i) / 40.0
			draw_rect(Rect2(0, PHOTO_H - 260 + i * 6.5, W, 6.5), Color(0.05, 0.06, 0.05, a * a * 0.8))
		# the name tag top left
		draw_rect(Rect2(36, 40, 262, 46), RED)
		draw_string(p._font_b, Vector2(52, 74), "DOWNHILL PARK", HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color.WHITE)
		draw_string(p._font_b, Vector2(38, PHOTO_H - 84), "MINI BMX", HORIZONTAL_ALIGNMENT_LEFT, -1, 92, Color(0.98, 0.97, 0.92))
		draw_string(p._font, Vector2(42, PHOTO_H - 36), (p.place.to_upper() + "  ·  TRAIL GUIDE") if p.place != "" else "TRAIL GUIDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.84, 0.5))
		draw_rect(Rect2(0, PHOTO_H, W, 14), RED)
		# the list's frame: a heading rule and a footer
		draw_line(Vector2(48, H - 92), Vector2(W - 48, H - 92), Color(INK, 0.5), 2)
		draw_string(p._font, Vector2(48, H - 56), "Ride safe  ·  Wear a helmet", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.7))
		draw_string(p._font, Vector2(48, H - 26), "Leave no trace", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.7))
		draw_string(p._font_b, Vector2(0, H - 26), "No. %d" % p.sheet_no, HORIZONTAL_ALIGNMENT_RIGHT, W - 48, 22, RED)
