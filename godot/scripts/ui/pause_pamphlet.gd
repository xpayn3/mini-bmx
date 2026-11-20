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
	sound_stream = load("res://assets/audio/paper_unfold.mp3")   # the user's crumpling paper recording (same as the map): opening, unfolding, folding, turning over
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
	back_col = 1                                    # the middle panel's back faces out behind: the tips
	setup(Vector2i(CW * 3, CH), Vector2i(CW, CH))   # inside spread + the cover strip under it (cover, back)
	_inside = Control.new()                         # the inside: a menu printed across the three panels
	_inside.scale = Vector2.ONE * INSIDE_SCALE
	_inside.size = Vector2(CW * 3, CH) / INSIDE_SCALE
	content.add_child(_inside)
	var tips := TipsBack.new()   # the back: hand-drawn ride tips (turn the leaflet over with the right stick)
	tips.position = Vector2(CW, COVER_Y)
	tips.size = Vector2(CW, CH)
	tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(tips)
	_tips = tips
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
	b.custom_minimum_size = Vector2(0, 55)   # nine lines fit the list
	b.clip_text = true
	b.add_theme_font_override("font", _font_b)
	b.add_theme_font_size_override("font_size", 31)
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
	b.mouse_entered.connect(func(): if b.focus_mode != Control.FOCUS_NONE: b.grab_focus())   # mouse and pad share one highlight
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
	menu.tree_exiting.connect(func():
		if _inside_menu == menu:
			_inside_menu = null; _cover_focus(true); set_unfolded(false); focus_first.call_deferred())
	_cover_focus(false)   # the cover's lines sit under the spread: the D-pad must not wander onto them
	set_unfolded(true)
	_show_hint()


func _cover_focus(on: bool) -> void:
	for c in _list.get_children():
		(c as Control).focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	var f := page.gui_get_focus_owner()
	if not on and f and _list.is_ancestor_of(f): page.gui_release_focus()


## shut the leaflet again (back to the cover)
func fold_inside() -> void:
	if is_instance_valid(_inside_menu): _inside_menu.queue_free()   # (its tree_exiting shuts the flaps)
	else: set_unfolded(false)


func prompt_items() -> Array:
	if Settings.pad_active:
		var it := [[["A"], "Select"], [["B"], "Fold up" if is_unfolded() else "Resume"]]
		if not is_unfolded(): it.insert(1, [["RS"], "Turn over"])
		else: it.insert(1, [["LB", "RB"], "Tabs"])
		return it
	var k := [[["K:Enter"], "Select"], [["MOUSE"], "Click"], [["K:Esc"], "Fold up" if is_unfolded() else "Resume"]]
	if not is_unfolded(): k.insert(2, [[PadGlyph.glyph_for("body_left", false), PadGlyph.glyph_for("body_right", false)], "Turn over"])
	return k


# ---- turning it over (right stick / body keys): the stick turns it, let go and it settles face or back on
var _tips: Control
var _spin_t := 0.0
var _spin_v := 0.0
var _spin_side := 0            # which face is toward you (roundf(_spin_t / PI)): a change = turned over

func _process(dt: float) -> void:
	super._process(dt)
	if state == 0: return
	var rdt := minf(dt if dt > 0.0 else 0.016, 0.05)
	if Engine.time_scale > 0.0: rdt = minf(dt / Engine.time_scale, 0.05)   # (the tree may be paused, not slowed)
	var x := Input.get_action_strength("body_right") - Input.get_action_strength("body_left")
	if OS.get_environment("BMX_LEAFLET_SPIN") != "": _spin_t = float(OS.get_environment("BMX_LEAFLET_SPIN")); x = 0.0   # tests: turned to this angle
	if is_unfolded() or state != 2: x = 0.0
	if absf(x) > 0.15:
		_spin_t += x * 3.2 * rdt
	elif OS.get_environment("BMX_LEAFLET_SPIN") == "":   # let go: settle on whichever side is nearer (face or back)
		_spin_t = lerpf(_spin_t, roundf(_spin_t / PI) * PI, 1.0 - exp(-rdt * 6.0))
	if is_unfolded(): _spin_t = roundf(_spin_t / TAU) * TAU   # opening: face on
	# turning it over (face <-> back) rustles like any paper move: the same recording, a short slice
	var side := int(roundf(_spin_t / PI))
	if side != _spin_side:
		_spin_side = side
		if state == 2 and not is_unfolded() and OS.get_environment("BMX_LEAFLET_SPIN") == "": _play_slice(1.25, 0.5)
	# a soft spring follows the target (a sheet of paper has a little lag and overshoot)
	_spin_v += ((_spin_t - spin) * 60.0 - _spin_v * 11.0) * rdt
	spin += _spin_v * rdt


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
		draw_string(p._font_b, Vector2(38, PHOTO_H - 84), "RUNOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 92, Color(0.98, 0.97, 0.92))
		draw_string(p._font, Vector2(42, PHOTO_H - 36), (p.place.to_upper() + "  ·  TRAIL GUIDE") if p.place != "" else "TRAIL GUIDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 0.84, 0.5))
		draw_rect(Rect2(0, PHOTO_H, W, 14), RED)
		# the list's frame: a heading rule and a footer
		draw_line(Vector2(48, H - 92), Vector2(W - 48, H - 92), Color(INK, 0.5), 2)
		draw_string(p._font, Vector2(48, H - 56), "Ride safe  ·  Wear a helmet", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.7))
		draw_string(p._font, Vector2(48, H - 26), "Leave no trace", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.7))
		draw_string(p._font_b, Vector2(0, H - 26), "No. %d" % p.sheet_no, HORIZONTAL_ALIGNMENT_RIGHT, W - 48, 22, RED)


## the back of the leaflet: ride tips sketched by hand - wobbly pen lines, a handwriting font, the right button
## icons for the device in use (redrawn when it changes)
class TipsBack extends Control:
	const PEN := Color("27313f")
	const RED := Color("d22b25")
	var _hand: Font
	var _pad := false
	var _rng := RandomNumberGenerator.new()

	func _init() -> void:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Ink Free", "Segoe Print", "Comic Sans MS", "Bahnschrift"])
		f.font_weight = 600
		_hand = f

	func _process(_dt: float) -> void:
		if _pad != Settings.pad_active:
			_pad = Settings.pad_active; queue_redraw()

	## a hand-drawn line: two slightly different wobbly strokes
	func _pen(a: Vector2, b: Vector2, w := 4.0, c := PEN) -> void:
		for k in 2:
			var pts := PackedVector2Array()
			var n := maxi(3, int(a.distance_to(b) / 18.0))
			var nrm := (b - a).orthogonal().normalized()
			for i in n + 1:
				var t := float(i) / n
				pts.append(a.lerp(b, t) + nrm * _rng.randf_range(-1.6, 1.6) + Vector2(k * 0.8, k * 0.6))
			draw_polyline(pts, Color(c, 0.85 if k == 0 else 0.45), w * (1.0 if k == 0 else 0.6), true)

	func _ring(c: Vector2, r: float, w := 4.0, col := PEN, a0 := 0.0, a1 := TAU) -> void:
		for k in 2:
			var pts := PackedVector2Array()
			var n := maxi(10, int(r * absf(a1 - a0) / 9.0))
			for i in n + 1:
				var a := lerpf(a0, a1, float(i) / n)
				pts.append(c + Vector2(cos(a), sin(a)) * (r + _rng.randf_range(-1.5, 1.5)) + Vector2(k * 0.8, k * 0.6))
			draw_polyline(pts, Color(col, 0.85 if k == 0 else 0.45), w * (1.0 if k == 0 else 0.6), true)

	func _arrow(a: Vector2, b: Vector2, col := RED) -> void:
		_pen(a, b, 4.5, col)
		var d := (b - a).normalized()
		_pen(b, b - d.rotated(0.5) * 22.0, 4.5, col)
		_pen(b, b - d.rotated(-0.5) * 22.0, 4.5, col)

	## a sketched bike + rider: rear wheel at p, pitched `ang` (rad, nose up +), s = wheel radius
	func _bike(p: Vector2, ang: float, s := 34.0, lean := 0.0) -> void:
		var R := Transform2D(-ang, p)
		var q := func(x: float, y: float) -> Vector2: return R * Vector2(x * s, y * s * (1.0 - absf(lean) * 0.3))
		_ring(q.call(0, 0), s)
		_ring(q.call(3.0, 0), s)
		var bb: Vector2 = q.call(1.3, 0.25)
		_pen(q.call(0, 0), bb); _pen(bb, q.call(2.2, -1.25)); _pen(q.call(0, 0), q.call(1.1, -1.2))
		_pen(q.call(1.1, -1.2), q.call(2.2, -1.25)); _pen(q.call(2.2, -1.25), q.call(3.0, 0))
		_pen(q.call(2.1, -1.5), q.call(2.5, -1.6))   # bars
		# the rider: stick figure standing on the pedals, round head
		var hip: Vector2 = q.call(1.1, -2.1)
		var sh: Vector2 = q.call(1.9, -3.0)
		_pen(bb, hip, 5.0); _pen(hip, sh, 5.0); _pen(sh, q.call(2.3, -1.6), 4.0)
		_ring(q.call(2.25, -3.55), s * 0.38, 4.5)

	func _tip(y: float, title: String, glyphs: Array, line: String, sketch: Callable) -> void:
		var x0 := 46.0
		draw_string(_hand, Vector2(x0, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, RED)
		sketch.call(Vector2(x0 + 20, y + 18))
		var gx := x0
		var ty := y + 212.0
		for g in glyphs:
			var gw := PadGlyph.width(g, 34.0)
			PadGlyph.draw(self, g, Vector2(gx + gw * 0.5, ty - 10), 34.0)
			gx += gw + 8
		draw_string(_hand, Vector2(gx + 6, ty), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - gx - 50, 27, PEN)

	func _draw() -> void:
		_rng.seed = 7
		draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)
		var W := size.x
		draw_string(_hand, Vector2(46, 92), "Ride tips", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, PEN)
		_pen(Vector2(46, 110), Vector2(W - 70, 104), 5.0, RED)
		var pad := Settings.pad_active
		var g := func(a: String) -> String: return PadGlyph.glyph_for(a, pad)
		_tip(180, "Pump & pop", [g.call("hop")], "hold it into the lip, let go on top", func(o: Vector2):
			_pen(o + Vector2(0, 150), o + Vector2(250, 150)); _pen(o + Vector2(250, 150), o + Vector2(420, 60))
			_bike(o + Vector2(250, 112), 0.42, 26.0)
			_arrow(o + Vector2(470, 80), o + Vector2(500, 0)))
		_tip(450, "Flips", [g.call("body_back"), g.call("body_fwd")], "yank it as you leave the lip", func(o: Vector2):
			_bike(o + Vector2(160, 120), 0.0, 26.0)
			_ring(o + Vector2(225, 78), 92, 4.5, RED, -2.6, 1.3)
			_arrow(o + Vector2(250, 166), o + Vector2(205, 172)))
		_tip(720, "Manual", [g.call("body_back")], "pull back while you roll", func(o: Vector2):
			_pen(o + Vector2(0, 160), o + Vector2(470, 160))
			_bike(o + Vector2(150, 126), 0.45, 28.0)
			_arrow(o + Vector2(360, 30), o + Vector2(300, 70)))
		_tip(985, "Carve", [g.call("steer_left"), g.call("body_left")], "lean the bike with the steer", func(o: Vector2):
			_bike(o + Vector2(120, 120), 0.0, 26.0, 0.6)
			for i in 3: _pen(o + Vector2(20 + i * 8, 170 + i * 6), o + Vector2(470, 120 - i * 10), 3.0, Color(PEN, 0.5))
			_arrow(o + Vector2(330, 40), o + Vector2(450, 90)))
		draw_string(_hand, Vector2(46, size.y - 22), "turn me back over to ride", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(PEN, 0.6))

