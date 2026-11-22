class_name TuneSlider
extends VBoxContainer
## The tuning card's own slider: name + value on top, a drawn track with words at both ends ("Loose ◂ ▸ Grippy"),
## a tick where the preset has it and a fill from that tick to the value (so you see at a glance which way and how
## far you've moved it from the preset), a one-line hint under it. Double-click the track or ↺ = back to the
## preset. It is an HSlider underneath (themed invisible, drawn by _Track), so the pad / keys / PadNav work as on
## any slider. big = the Feel page's macro sliders (taller, value shown as a % change).

signal changed(v: float)

var slider: HSlider
var _val_l: Label
var _reset: Button
var _def := 0.0
var _fmt: Callable
var _big := false

## label, [lo, hi, step], value, preset value, fmt(v) -> String, ends ["", ""], hint, pin (Button or null)
static func make(label: String, rng: Array, val: float, def: float, fmt: Callable, ends: Array = [], hint := "",
		pin: Button = null, big := false) -> TuneSlider:
	var t := TuneSlider.new()
	t._build(label, rng, val, def, fmt, ends, hint, pin, big)
	return t


func _build(label: String, rng: Array, val: float, def: float, fmt: Callable, ends: Array, hint: String,
		pin: Button, big: bool) -> void:
	_def = def; _fmt = fmt; _big = big
	add_theme_constant_override("separation", 0)
	set_meta("nav_row", true)   # the pad's focus marker goes on the whole row
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	if pin: top.add_child(pin)
	var l := UITheme.label(label, 15 if big else 13, Color.WHITE, big)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true; l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(l)
	_val_l = UITheme.label("", 13 if big else 12, UITheme.MUTED, big)
	_val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_val_l.custom_minimum_size.x = 64
	top.add_child(_val_l)
	_reset = Button.new()
	_reset.text = "↺"; _reset.flat = true; _reset.focus_mode = Control.FOCUS_NONE
	_reset.tooltip_text = "Back to the preset"
	_reset.add_theme_font_size_override("font_size", 13)
	_reset.add_theme_color_override("font_color", UITheme.ACCENT)
	_reset.custom_minimum_size = Vector2(22, 0)
	_reset.pressed.connect(func(): slider.value = _def)
	top.add_child(_reset)
	add_child(top)
	slider = HSlider.new()
	slider.scrollable = false   # (the wheel scrolls the card, never moves a value)
	slider.min_value = rng[0]; slider.max_value = rng[1]; slider.step = rng[2]
	slider.value = val
	slider.custom_minimum_size.y = 26 if big else 20
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the stock look off: _Track draws everything
	var none := StyleBoxEmpty.new()
	for s in ["slider", "grabber_area", "grabber_area_highlight"]: slider.add_theme_stylebox_override(s, none)
	var blank := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for s in ["grabber", "grabber_highlight", "grabber_disabled"]: slider.add_theme_icon_override(s, blank)
	slider.add_theme_stylebox_override("focus", none)
	var tr := _Track.new()
	tr.owner_s = self
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slider.add_child(tr)
	slider.value_changed.connect(func(v): _sync(); tr.queue_redraw(); changed.emit(v))
	slider.focus_entered.connect(tr.queue_redraw); slider.focus_exited.connect(tr.queue_redraw)
	slider.mouse_entered.connect(func(): tr.hot = true; tr.queue_redraw())
	slider.mouse_exited.connect(func(): tr.hot = false; tr.queue_redraw())
	slider.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			slider.value = _def; slider.accept_event())
	# the end words sit either side of the track: "Loose ━━━●━━ Grippy"
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 6)
	var has_ends := ends.size() == 2 and (str(ends[0]) != "" or str(ends[1]) != "")
	if has_ends:
		var a := UITheme.label(str(ends[0]), 11, UITheme.MUTED)
		a.custom_minimum_size.x = 62; a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		a.clip_text = true; a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mid.add_child(a)
	mid.add_child(slider)
	if has_ends:
		var b := UITheme.label(str(ends[1]), 11, UITheme.MUTED)
		b.custom_minimum_size.x = 62
		b.clip_text = true; b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		mid.add_child(b)
	add_child(mid)
	if hint != "":
		var h := UITheme.label(hint, 11, Color(1, 1, 1, 0.5))
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(h)
	var gap := Control.new(); gap.custom_minimum_size.y = 8 if big else 5
	add_child(gap)
	_sync()


func set_value_quiet(v: float) -> void:
	slider.set_value_no_signal(v); _sync()
	for c in slider.get_children(): (c as Control).queue_redraw()


func _sync() -> void:
	var moved := absf(slider.value - _def) > slider.step * 0.5
	_val_l.text = _fmt.call(slider.value)
	_val_l.add_theme_color_override("font_color", UITheme.ACCENT if moved else UITheme.MUTED)
	_reset.modulate.a = 1.0 if moved else 0.0
	_reset.disabled = not moved


## draws the track, the fill from the preset tick to the value, the tick and the knob
class _Track extends Control:
	var owner_s: TuneSlider
	var hot := false

	func _draw() -> void:
		var s: HSlider = owner_s.slider
		var big := owner_s._big
		var h: float = size.y
		var r := 9.0 if big else 7.0   # knob radius
		var x0 := r; var x1 := size.x - r
		var span := maxf(1e-6, s.max_value - s.min_value)
		var px := func(v: float) -> float: return x0 + (x1 - x0) * clampf((v - s.min_value) / span, 0.0, 1.0)
		var cy := h * 0.5
		var th := 6.0 if big else 4.0
		draw_rect(Rect2(x0, cy - th * 0.5, x1 - x0, th), Color(1, 1, 1, 0.16))
		var pd: float = px.call(owner_s._def)
		var pv: float = px.call(s.value)
		var moved := absf(s.value - owner_s._def) > s.step * 0.5
		if moved:
			draw_rect(Rect2(minf(pd, pv), cy - th * 0.5, absf(pv - pd), th), UITheme.ACCENT)
		# the preset's tick
		draw_rect(Rect2(pd - 1.0, cy - th - 3.0, 2.0, th * 2.0 + 6.0), Color(1, 1, 1, 0.55))
		var focus := s.has_focus()
		var kr := r + (1.5 if (hot or focus) else 0.0)
		if focus: draw_circle(Vector2(pv, cy), kr + 4.0, Color(UITheme.ACCENT, 0.3))
		draw_circle(Vector2(pv, cy), kr, UITheme.ACCENT if moved else Color(0.92, 0.94, 0.96))
		draw_circle(Vector2(pv, cy), kr * 0.38, Color(0.08, 0.12, 0.15))
