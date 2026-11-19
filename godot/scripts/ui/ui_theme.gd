class_name UITheme
extends RefCounted
## The game's look: dark translucent glass panels, bold rounded type, yellow accent (from index.html).

const ACCENT := Tokens.ACCENT
const NAVY := Color("1d2b64")
const PANEL := Color(0.08, 0.15, 0.2, 0.82)
const PANEL_LIGHT := Color(1, 1, 1, 0.10)
const TEXT := Tokens.ON_SCENE
const MUTED := Tokens.ON_SCENE_SOFT

static var _theme: Theme
static var _font: Font
static var _font_black: Font

static func font(black := false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "Noto Sans"])
		f.font_weight = 700
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
		var b := SystemFont.new()
		b.font_names = f.font_names
		b.font_weight = 900
		_font_black = b
	return _font_black if black else _font

static var _display := {}

## sporty display type for titles / big menu buttons: Bahnschrift (DIN-style, ships with Windows 10/11),
## condensed + bold; `slant` leans it forward like a race number. Falls back to the UI font elsewhere.
static func display_font(weight := 700, slant := 0.0) -> Font:
	var key := "%d_%.2f" % [weight, slant]
	if _display.has(key): return _display[key]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "DIN Alternate", "Roboto Condensed", "Arial Narrow", "Segoe UI"])
	f.font_weight = weight
	f.font_stretch = 75
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.fallbacks = [font(weight >= 800)]
	var out: Font = f
	if slant != 0.0:
		var v := FontVariation.new()
		v.base_font = f
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(-slant, 1), Vector2.ZERO)
		out = v
	_display[key] = out
	return out

static var _lcd: Font

## dot-matrix LCD type for the bike computer: Doto (OFL, assets/fonts/), heavy round dots;
## glyphs Doto lacks (°, …) fall back to the UI font
static func lcd_font() -> Font:
	if _lcd == null:
		var ff: FontFile = load("res://assets/fonts/Doto.ttf")
		var ts := TextServerManager.get_primary_interface()
		var v := FontVariation.new()
		v.base_font = ff
		v.variation_opentype = {ts.name_to_tag("wght"): 900, ts.name_to_tag("ROND"): 100}
		v.fallbacks = [font(true)]
		_lcd = v
	return _lcd

static func box(bg: Color, radius := Tokens.R_LG, pad := Tokens.S4, border := Tokens.CLEAR, bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad; s.content_margin_right = pad
	s.content_margin_top = pad * 0.6; s.content_margin_bottom = pad * 0.6
	if bw > 0:
		s.border_color = border; s.set_border_width_all(bw)
	s.anti_aliasing = true
	return s

static func get_theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 18, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, 18, 18))
	# buttons
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 10, 16))
	t.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.22), 10, 16))
	t.set_stylebox("pressed", "Button", box(ACCENT, 10, 16))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 10, 16, ACCENT, 2))
	t.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.05), 10, 16))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", NAVY)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_hover_pressed_color", "Button", NAVY)
	t.set_stylebox("hover_pressed", "Button", box(ACCENT, 10, 16))
	# option / check / spin / line edit
	for c in ["OptionButton", "LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, box(Color(1, 1, 1, 0.12), 8, 10))
		t.set_stylebox("hover", c, box(Color(1, 1, 1, 0.2), 8, 10))
		t.set_stylebox("focus", c, box(Color(0, 0, 0, 0), 8, 10, ACCENT, 2))
		t.set_stylebox("pressed", c, box(Color(1, 1, 1, 0.25), 8, 10))
		t.set_color("font_color", c, TEXT)
	t.set_stylebox("read_only", "LineEdit", box(Color(1, 1, 1, 0.06), 8, 10))
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_color("font_hover_pressed_color", "CheckButton", TEXT)
	t.set_color("font_focus_color", "CheckButton", TEXT)
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", box(Color(0, 0, 0, 0), 8, 6))
	t.set_stylebox("focus", "CheckButton", box(Color(0, 0, 0, 0), 8, 6, ACCENT, 2))
	# sliders
	var groove := box(Color(1, 1, 1, 0.18), 4, 0); groove.content_margin_top = 3; groove.content_margin_bottom = 3
	var fill := box(ACCENT, 4, 0); fill.content_margin_top = 3; fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# tabs
	t.set_stylebox("tab_selected", "TabContainer", box(ACCENT, 10, 16))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL_LIGHT, 10, 16))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(1, 1, 1, 0.22), 10, 16))
	t.set_stylebox("tab_focus", "TabContainer", box(Color(0, 0, 0, 0), 10, 16, ACCENT, 2))
	t.set_stylebox("panel", "TabContainer", box(Color(0, 0, 0, 0), 0, 4))
	t.set_color("font_selected_color", "TabContainer", NAVY)
	t.set_color("font_unselected_color", "TabContainer", TEXT)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 0)
	# popup menus (option buttons)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.14, 0.19, 0.97), 10, 8))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT, 6, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", NAVY)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.06, 0.1, 0.14, 0.95), 8, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# scrollbars
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.06), 4, 2))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.3), 4, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.45), 4, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 4, 2))
	_theme = t
	return t

# ---------------------------------------------------------------- light (white, opaque) window theme
# Used by the Settings / Controls windows (MenuBase): a solid white card, ink text, yellow accent.
const L_INK := Tokens.INK
const L_MUTED := Tokens.INK_SOFT
const L_PAGE := Tokens.PAGE
const L_LINE := Tokens.LINE
const L_BTN := Tokens.FILL
const L_BTN_HOT := Tokens.FILL_HOT

static var _light: Theme

static func _blend(img: Image, x: int, y: int, c: Color, cov: float) -> void:
	if cov <= 0.0: return
	var o := img.get_pixel(x, y)
	var a := c.a * cov
	var oa := o.a * (1.0 - a)
	var na := a + oa
	if na <= 0.0: return
	var rgb := (Vector3(c.r, c.g, c.b) * a + Vector3(o.r, o.g, o.b) * oa) / na
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, na))

static func _disc(img: Image, cx: float, cy: float, r: float, fill: Color, ring: Color, ring_w: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5 - cx, y + 0.5 - cy).length()
			var outer := clampf(r - d + 0.5, 0.0, 1.0)
			if outer <= 0.0: continue
			var inner := clampf(r - ring_w - d + 0.5, 0.0, 1.0) if ring_w > 0.0 else 1.0
			_blend(img, x, y, ring.lerp(fill, inner) if ring_w > 0.0 else fill, outer)

static func tex_disc(d: int, fill: Color, ring: Color, ring_w: float) -> ImageTexture:
	var img := Image.create_empty(d, d, false, Image.FORMAT_RGBA8)
	_disc(img, d * 0.5, d * 0.5, d * 0.5, fill, ring, ring_w)
	return ImageTexture.create_from_image(img)

static func tex_toggle(on: bool) -> ImageTexture:
	var w := 46; var h := 26
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var track := L_INK if on else Color("c6cdda")
	for y in h:
		for x in w:
			var px := clampf(x + 0.5, 13.0, 33.0)
			var d := Vector2(x + 0.5 - px, y + 0.5 - 13.0).length()
			_blend(img, x, y, track, clampf(13.0 - d + 0.5, 0.0, 1.0))
	_disc(img, 33.0 if on else 13.0, 13.0, 9.0, ACCENT if on else Color.WHITE, Color.WHITE, 0.0)
	return ImageTexture.create_from_image(img)

static func tex_chevron(col: Color) -> ImageTexture:
	var img := Image.create_empty(14, 14, false, Image.FORMAT_RGBA8)
	var pts := [Vector2(2.5, 4.5), Vector2(7, 9.5), Vector2(11.5, 4.5)]
	for y in 14:
		for x in 14:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := minf(_seg_dist(p, pts[0], pts[1]), _seg_dist(p, pts[1], pts[2]))
			_blend(img, x, y, col, clampf(1.0 - d + 0.5, 0.0, 1.0))
	return ImageTexture.create_from_image(img)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static var _print_t: Theme
const P_INK := Color("1d1f22")
const P_RED := Color("d22b25")

## the light theme PRINTED on paper (the pause leaflet's inside, paper menus): no fills - ink lines on the
## sheet, form fields as underlines, tabs as printed headings with a red rule, red-ink sliders, a highlighter
## for hover / focus
static func print_theme() -> Theme:
	if _print_t: return _print_t
	var t: Theme = light_theme().duplicate(true)
	var pf := SystemFont.new()
	pf.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Segoe UI", "Arial"])
	pf.font_weight = 600
	var pfb := SystemFont.new()
	pfb.font_names = pf.font_names
	pfb.font_weight = 800
	t.default_font = pf
	t.default_font_size = 19
	var clear := Color(0, 0, 0, 0)
	var hl := Color(1.0, 0.86, 0.18, 0.55)   # highlighter
	var line := func(col: Color, bottom: int, all := 0) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = clear
		sb.border_color = col
		sb.set_border_width_all(all)
		sb.border_width_bottom = bottom
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 6; sb.content_margin_bottom = 6
		return sb
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	# buttons: a stamped outline; hover = highlighter
	t.set_stylebox("normal", "Button", box(clear, 4, 14, P_INK, 2))
	t.set_stylebox("hover", "Button", box(hl, 4, 14, P_INK, 2))
	t.set_stylebox("pressed", "Button", box(ACCENT, 4, 14, P_INK, 2))
	t.set_stylebox("hover_pressed", "Button", box(ACCENT, 4, 14, P_INK, 2))
	t.set_stylebox("focus", "Button", box(clear, 4, 14, P_RED, 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", P_INK)
	t.set_font("font", "Button", pfb)
	# form fields: fill-in lines
	for c in ["OptionButton", "LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, line.call(Color(P_INK, 0.55), 2))
		t.set_stylebox("hover", c, line.call(P_INK, 2))
		t.get_stylebox("hover", c).bg_color = Color(hl, 0.35)
		t.set_stylebox("pressed", c, line.call(P_RED, 3))
		t.set_stylebox("focus", c, line.call(P_RED, 3))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(fc, c, P_INK)
	t.set_icon("arrow", "OptionButton", tex_chevron(P_INK))
	# toggles: ink
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", box(clear, 4, 6))
	t.set_stylebox("hover", "CheckButton", box(Color(hl, 0.35), 4, 6))
	t.set_stylebox("focus", "CheckButton", box(clear, 4, 6, P_RED, 2))
	# sliders: a printed rule, red ink filled
	var groove := box(Color(P_INK, 0.25), 1, 0); groove.content_margin_top = 2; groove.content_margin_bottom = 2
	var fill := box(P_RED, 1, 0); fill.content_margin_top = 2; fill.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var g := tex_disc(22, Color("fbfaf5"), P_INK, 3.0)
	for n in ["grabber", "grabber_highlight", "grabber_disabled"]: t.set_icon(n, "HSlider", g)
	# tabs: printed headings, the open one with a red rule under it
	var tsel: StyleBoxFlat = line.call(P_RED, 4)
	t.set_stylebox("tab_selected", "TabContainer", tsel)
	t.set_stylebox("tab_unselected", "TabContainer", line.call(clear, 4))
	var thov: StyleBoxFlat = line.call(Color(P_INK, 0.4), 4)
	thov.bg_color = Color(hl, 0.35)
	t.set_stylebox("tab_hovered", "TabContainer", thov)
	t.set_stylebox("tab_focus", "TabContainer", line.call(P_RED, 0, 2))
	var page: StyleBoxFlat = line.call(Color(P_INK, 0.35), 0)
	page.border_width_top = 2
	page.content_margin_left = 6; page.content_margin_right = 6; page.content_margin_top = 14
	t.set_stylebox("panel", "TabContainer", page)
	t.set_color("font_selected_color", "TabContainer", P_INK)
	t.set_color("font_unselected_color", "TabContainer", Color(P_INK, 0.55))
	t.set_color("font_hovered_color", "TabContainer", P_INK)
	t.set_font("font", "TabContainer", pfb)
	t.set_font_size("font_size", "TabContainer", 19)
	# lists dropping out of a field: a slip of paper
	t.set_stylebox("panel", "PopupMenu", box(Color("fbfaf5"), 2, 8, P_INK, 2))
	t.set_stylebox("hover", "PopupMenu", box(hl, 2, 8))
	t.set_color("font_color", "PopupMenu", P_INK)
	t.set_color("font_hover_color", "PopupMenu", P_INK)
	t.set_stylebox("scroll", "VScrollBar", box(Color(P_INK, 0.08), 2, 3))
	t.set_stylebox("grabber", "VScrollBar", box(Color(P_INK, 0.35), 2, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(P_INK, 0.55), 2, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(P_RED, 2, 3))
	t.set_color("font_color", "Label", P_INK)
	_print_t = t
	return t


static func light_theme() -> Theme:
	if _light: return _light
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", L_INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("shadow_offset_y", "Label", 0)
	t.set_stylebox("panel", "PanelContainer", box(Tokens.PAPER, Tokens.R_XL, Tokens.S5))
	# buttons
	t.set_stylebox("normal", "Button", box(Tokens.FILL, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("hover", "Button", box(Tokens.FILL_HOT, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("pressed", "Button", box(Tokens.ACCENT, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("hover_pressed", "Button", box(Tokens.ACCENT, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("focus", "Button", marked(Tokens.CLEAR, Tokens.INK, SIDE_BOTTOM, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("disabled", "Button", box(Tokens.PAGE, Tokens.R_LG, Tokens.S5))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", L_INK)
	t.set_color("font_disabled_color", "Button", Tokens.INK_FAINT)
	# fields
	for c in ["OptionButton", "LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, box(Tokens.FILL, Tokens.R_LG, Tokens.S4))
		t.set_stylebox("hover", c, box(Tokens.FILL_HOT, Tokens.R_LG, Tokens.S4))
		t.set_stylebox("pressed", c, box(Tokens.ACCENT_TINT, Tokens.R_LG, Tokens.S4))
		t.set_stylebox("focus", c, marked(Tokens.CLEAR, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, Tokens.S4))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(fc, c, L_INK)
	t.set_stylebox("read_only", "LineEdit", box(Tokens.PAGE, Tokens.R_LG, Tokens.S4))
	t.set_icon("arrow", "OptionButton", tex_chevron(L_INK))
	t.set_constant("arrow_margin", "OptionButton", 8)
	# toggles
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", box(Tokens.CLEAR, Tokens.R_MD, Tokens.S2))
	t.set_stylebox("focus", "CheckButton", marked(Tokens.CLEAR, Tokens.INK, SIDE_BOTTOM, Tokens.R_MD, Tokens.S2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", L_INK)
	var on := tex_toggle(true); var off := tex_toggle(false)
	for n in ["checked", "checked_mirrored", "checked_disabled", "checked_disabled_mirrored"]: t.set_icon(n, "CheckButton", on)
	for n in ["unchecked", "unchecked_mirrored", "unchecked_disabled", "unchecked_disabled_mirrored"]: t.set_icon(n, "CheckButton", off)
	# sliders
	var groove := box(Color("d9dee8"), 4, 0); groove.content_margin_top = 4; groove.content_margin_bottom = 4
	var fill := box(ACCENT, 4, 0); fill.content_margin_top = 4; fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var g := tex_disc(Tokens.S6, Tokens.ACCENT, Tokens.ACCENT_DOWN, Tokens.B_BOLD)
	for n in ["grabber", "grabber_highlight", "grabber_disabled"]: t.set_icon(n, "HSlider", g)
	# tabs: pills; the open one is yellow with an ink outline
	t.set_stylebox("tab_selected", "TabContainer", marked(Tokens.PAGE, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("tab_unselected", "TabContainer", btn_box(Tokens.CLEAR, Tokens.CLEAR, 0, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("tab_hovered", "TabContainer", marked(Tokens.FILL, Tokens.LINE, SIDE_BOTTOM, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("tab_focus", "TabContainer", marked(Tokens.CLEAR, Tokens.INK, SIDE_BOTTOM, Tokens.R_LG, Tokens.S5))
	t.set_stylebox("panel", "TabContainer", box(L_PAGE, 16, 14))
	for c in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		t.set_color(c, "TabContainer", L_INK)
	t.set_constant("side_margin", "TabContainer", 0)
	t.set_font("font", "TabContainer", display_font(Tokens.W_BOLD, Tokens.SLANT))
	t.set_font_size("font_size", "TabContainer", Tokens.T_LG)
	# popups (option lists, the pad remap menu)
	t.set_stylebox("panel", "PopupMenu", box(Tokens.PAPER, Tokens.R_LG, Tokens.S3))
	t.set_stylebox("hover", "PopupMenu", box(Tokens.ACCENT, Tokens.R_MD, Tokens.S3))
	t.set_color("font_color", "PopupMenu", L_INK)
	t.set_color("font_hover_color", "PopupMenu", L_INK)
	t.set_constant("v_separation", "PopupMenu", 6)
	var rc := tex_disc(Tokens.S5, Tokens.ACCENT, Tokens.ACCENT_DOWN, Tokens.B_BOLD); var ru := tex_disc(Tokens.S5, Tokens.PAPER, Tokens.LINE, Tokens.B)
	t.set_icon("radio_checked", "PopupMenu", rc); t.set_icon("checked", "PopupMenu", rc)
	t.set_icon("radio_unchecked", "PopupMenu", ru); t.set_icon("unchecked", "PopupMenu", ru)
	t.set_stylebox("panel", "TooltipPanel", box(Tokens.INK, Tokens.R_MD, Tokens.S3))
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	# scrollbars
	t.set_stylebox("scroll", "VScrollBar", box(Tokens.CLEAR, Tokens.R_SM, Tokens.SCROLL_W))
	t.set_stylebox("grabber", "VScrollBar", box(Tokens.THUMB, Tokens.R_SM, Tokens.SCROLL_W))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Tokens.THUMB_HOT, Tokens.R_SM, Tokens.SCROLL_W))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Tokens.INK, Tokens.R_SM, Tokens.SCROLL_W))
	_light = t
	return t

static func label(text: String, size := 17, color := TEXT, black := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if black: l.add_theme_font_override("font", font(true))
	return l

static func button(text: String, cb: Callable, size := 19) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(0, 44)
	return b


## a small ✕ for a panel's title row
static func close_button(cb: Callable) -> Button:
	var b := button("✕", cb, 15)
	b.custom_minimum_size = Vector2(34, 30)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Close"
	return b


## a small ↺ next to a slider: puts it back to its default (and fires value_changed like a drag would)
static func reset_button(s: Range, default_value: float, muted := MUTED, hot := ACCENT) -> Button:
	var b := Button.new()
	b.text = "↺"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", muted)
	b.add_theme_color_override("font_hover_color", hot)
	if s != null: bind_reset(b, s, default_value)
	return b

static func bind_reset(b: Button, s: Range, default_value: float) -> void:
	b.tooltip_text = "Reset to default (%s)" % str(snappedf(default_value, 0.0001))
	b.pressed.connect(func(): s.value = default_value)


## Keep a panel centred on screen whatever its size (grows out from the middle).
static func centre(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


# ================================================================ components (built only from Tokens)
## a card: paper with an ink outline and a soft drop shadow
## a card: flat paper, no outline, no shadow
static func card_style(fill := Tokens.PAPER, radius := Tokens.R_XL, pad := Tokens.S5) -> StyleBoxFlat:
	var s := box(fill, radius, pad)
	s.content_margin_top = pad; s.content_margin_bottom = pad
	return s

## a flat fill with a coloured bar along one edge (selected / focused) instead of an outline
static func marked(fill: Color, mark := Tokens.ACCENT, side := SIDE_BOTTOM, radius := Tokens.R_MD, pad := Tokens.S4) -> StyleBoxFlat:
	var s := btn_box(fill, Tokens.CLEAR, 0, radius, pad)
	s.border_color = mark
	match side:
		SIDE_LEFT: s.border_width_left = Tokens.MARK
		SIDE_TOP: s.border_width_top = Tokens.MARK
		SIDE_RIGHT: s.border_width_right = Tokens.MARK
		_: s.border_width_bottom = Tokens.MARK
	return s

## a button-sized box: `pad` left / right, a fixed smaller pad top / bottom
static func btn_box(fill: Color, border := Tokens.CLEAR, bw := 0, radius := Tokens.R_MD, pad := Tokens.S4) -> StyleBoxFlat:
	var s := box(fill, radius, pad, border, bw)
	s.content_margin_top = Tokens.S2; s.content_margin_bottom = Tokens.S2
	return s

## the button looks, one per role:
##  primary   - yellow, bold outline (RIDE, GO, SAVE & RIDE)
##  secondary - paper with an ink outline (BACK, SAVE)
##  chip      - grey, yellow when picked (bike, time of day, finishes, parts)
##  link      - bare text, a yellow bar + light wash on hover / focus (SETTINGS, QUIT)
##  tab       - bare text, a yellow underline when open (the garage's categories)
static func style_button(b: Button, kind := "chip", size := Tokens.T_MD) -> Button:
	var pad := Tokens.S4
	var weight := Tokens.W_BOLD
	var slant := 0.0
	match kind:
		"primary":
			pad = Tokens.S6; weight = Tokens.W_BLACK; slant = Tokens.SLANT
			b.add_theme_stylebox_override("normal", btn_box(Tokens.ACCENT, Tokens.CLEAR, 0, Tokens.R_LG, pad))
			b.add_theme_stylebox_override("hover", btn_box(Tokens.ACCENT_HOT, Tokens.CLEAR, 0, Tokens.R_LG, pad))
			b.add_theme_stylebox_override("pressed", btn_box(Tokens.ACCENT_DOWN, Tokens.CLEAR, 0, Tokens.R_LG, pad))
			b.add_theme_stylebox_override("focus", marked(Tokens.CLEAR, Tokens.INK, SIDE_BOTTOM, Tokens.R_LG, pad))
		"secondary":
			pad = Tokens.S5; weight = Tokens.W_BLACK; slant = Tokens.SLANT
			b.add_theme_stylebox_override("normal", btn_box(Tokens.PAPER, Tokens.CLEAR, 0, Tokens.R_LG, pad))
			b.add_theme_stylebox_override("hover", btn_box(Tokens.FILL, Tokens.CLEAR, 0, Tokens.R_LG, pad))
			b.add_theme_stylebox_override("pressed", btn_box(Tokens.ACCENT, Tokens.CLEAR, 0, Tokens.R_LG, pad))
			b.add_theme_stylebox_override("focus", marked(Tokens.CLEAR, Tokens.ACCENT, SIDE_BOTTOM, Tokens.R_LG, pad))
		"chip":
			b.add_theme_stylebox_override("normal", btn_box(Tokens.FILL))
			b.add_theme_stylebox_override("hover", btn_box(Tokens.FILL_HOT))
			b.add_theme_stylebox_override("pressed", btn_box(Tokens.ACCENT))
			b.add_theme_stylebox_override("hover_pressed", btn_box(Tokens.ACCENT_HOT))
			b.add_theme_stylebox_override("focus", marked(Tokens.CLEAR, Tokens.INK))
		"link":
			var clear := btn_box(Tokens.CLEAR, Tokens.CLEAR, 0, Tokens.R_SM, Tokens.S5)
			var hot := marked(Tokens.PAGE, Tokens.ACCENT, SIDE_LEFT, Tokens.R_SM, Tokens.S5)
			b.add_theme_stylebox_override("normal", clear)
			b.add_theme_stylebox_override("hover", hot)
			b.add_theme_stylebox_override("pressed", hot)
			b.add_theme_stylebox_override("focus", hot)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		"tab":
			slant = Tokens.SLANT
			var off := btn_box(Tokens.CLEAR, Tokens.CLEAR, 0, 0, Tokens.S4)
			off.content_margin_bottom = Tokens.S3
			var on := off.duplicate(); on.border_color = Tokens.ACCENT; on.border_width_bottom = Tokens.MARK
			var hov := off.duplicate(); hov.border_color = Tokens.LINE; hov.border_width_bottom = Tokens.MARK
			b.add_theme_stylebox_override("normal", off)
			b.add_theme_stylebox_override("hover", hov)
			b.add_theme_stylebox_override("pressed", on)
			b.add_theme_stylebox_override("hover_pressed", on)
			b.add_theme_stylebox_override("focus", off)
			b.add_theme_color_override("font_color", Tokens.INK_SOFT)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Tokens.INK)
	if kind != "tab": b.add_theme_color_override("font_color", Tokens.INK)
	b.add_theme_font_override("font", display_font(weight, slant))
	b.add_theme_font_size_override("font_size", size)
	return b

static func make_button(text: String, cb: Callable, kind := "chip", size := Tokens.T_MD) -> Button:
	var b := Button.new()
	b.text = text
	if cb.is_valid(): b.pressed.connect(cb)
	b.custom_minimum_size.y = Tokens.H_CHIP
	return style_button(b, kind, size)

## big display type (titles, names): condensed, leaning forward, no shadow (it sits on paper)
static func display(text: String, size := Tokens.T_3XL, col := Tokens.INK, slant := Tokens.SLANT, weight := Tokens.W_BLACK) -> Label:
	var l := label(text, size, col)
	l.add_theme_font_override("font", display_font(weight, slant))
	l.add_theme_color_override("font_shadow_color", Tokens.CLEAR)
	return l

static var _caption_font: FontVariation
## small letter-spaced caps (section names, specs, hints)
static func caption(text: String, col := Tokens.INK_SOFT, size := Tokens.T_SM) -> Label:
	if _caption_font == null:
		_caption_font = FontVariation.new()
		_caption_font.base_font = display_font(Tokens.W_BOLD)
		_caption_font.spacing_glyph = Tokens.TRACKING
	var l := label(text, size, col)
	l.add_theme_font_override("font", _caption_font)
	l.add_theme_color_override("font_shadow_color", Tokens.CLEAR)
	return l

## body text on paper (rows, notes)
static func text(t: String, col := Tokens.INK, size := Tokens.T_MD) -> Label:
	var l := label(t, size, col)
	l.add_theme_color_override("font_shadow_color", Tokens.CLEAR)
	return l

## a section heading: yellow mark, the name, a hairline to the edge
static func heading(t: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Tokens.S3)
	var slab := ColorRect.new()
	slab.color = Tokens.ACCENT
	slab.custom_minimum_size = Tokens.SLAB
	slab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(slab)
	hb.add_child(display(t, Tokens.T_LG))
	var line := ColorRect.new()
	line.color = Tokens.LINE
	line.custom_minimum_size.y = Tokens.B_HAIR
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(line)
	return hb

## a key cap ("Q", "ESC") for hints
static func key_cap(k: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Tokens.FILL, Tokens.R_SM, Tokens.S3)
	s.content_margin_top = Tokens.B_HAIR; s.content_margin_bottom = Tokens.B_HAIR
	p.add_theme_stylebox_override("panel", s)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := display(k, Tokens.T_SM, Tokens.INK, 0.0, Tokens.W_BOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

static func spacer(h := Tokens.S3) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

static var _paper: Theme
## the paper theme for whole screens (title menu, garage): the light theme + display type on buttons and
## fields, chip buttons, a slim scrollbar
static func paper_theme() -> Theme:
	if _paper: return _paper
	var t: Theme = light_theme().duplicate()
	t.default_font_size = Tokens.T_MD
	t.set_stylebox("panel", "PanelContainer", card_style())
	t.set_stylebox("normal", "Button", btn_box(Tokens.FILL))
	t.set_stylebox("hover", "Button", btn_box(Tokens.FILL_HOT))
	t.set_stylebox("pressed", "Button", btn_box(Tokens.ACCENT))
	t.set_stylebox("hover_pressed", "Button", btn_box(Tokens.ACCENT_HOT))
	t.set_stylebox("focus", "Button", marked(Tokens.CLEAR, Tokens.INK))
	# fields: flat grey, a yellow bar under the one being typed in
	for st in ["normal", "read_only"]:
		t.set_stylebox(st, "LineEdit", btn_box(Tokens.FILL))
	t.set_stylebox("focus", "LineEdit", marked(Tokens.CLEAR, Tokens.ACCENT))
	t.set_font("font", "Button", display_font(Tokens.W_BOLD))
	t.set_font_size("font_size", "Button", Tokens.T_MD)
	t.set_font("font", "LineEdit", display_font(Tokens.W_MEDIUM))
	t.set_font_size("font_size", "LineEdit", Tokens.T_LG)
	# slim scrollbar: no track, a thin round thumb that darkens on hover
	var track := box(Tokens.CLEAR, Tokens.R_SM, Tokens.SCROLL_W)
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("scroll_focus", "VScrollBar", track)
	for g in [["grabber", Tokens.THUMB], ["grabber_highlight", Tokens.THUMB_HOT], ["grabber_pressed", Tokens.INK]]:
		t.set_stylebox(g[0], "VScrollBar", box(g[1], Tokens.R_SM, Tokens.SCROLL_W))
	for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		t.set_icon(ic, "VScrollBar", ImageTexture.new())
	t.set_constant("scrollbar_h_separation", "ScrollContainer", Tokens.S2)
	t.set_constant("scrollbar_v_separation", "ScrollContainer", Tokens.S2)
	_paper = t
	return t
