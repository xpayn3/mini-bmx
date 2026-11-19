class_name MenuBase
extends PanelContainer
## A full window (Settings, Controls): solid white card, heavy slanted title with a yellow slab, pill tabs,
## grey page with ink text. Subclasses give `_title()` and `_pages()`; the helpers below build the rows.

signal closed

const INK := UITheme.L_INK
const MUTED := UITheme.L_MUTED

func _title() -> String: return ""
func _pages() -> Array: return []   # ScrollContainers from _page()

func _ready() -> void:
	theme = UITheme.light_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport_rect().size
	custom_minimum_size = Vector2(minf(880.0, vp.x - 60.0), minf(660.0, vp.y - 60.0))
	var st := UITheme.box(Color.WHITE, 22, 22, INK, 3)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 30
	st.shadow_offset = Vector2(0, 10)
	add_theme_stylebox_override("panel", st)
	UITheme.centre.call_deferred(self)
	_build(0)

## (Re)build the contents in place. The node itself is never replaced: whoever opened it keeps
## its connection to `closed`.
func _build(tab: int) -> void:
	for c in get_children():
		remove_child(c); c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var slab := ColorRect.new()
	slab.color = UITheme.ACCENT
	slab.custom_minimum_size = Vector2(10, 36)
	slab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(slab)
	var title := _lbl(_title(), 30, INK, true)
	var slant := FontVariation.new()
	slant.base_font = UITheme.font(true)
	slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	title.add_theme_font_override("font", slant)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var done := UITheme.button("Done", _close, 17)
	done.custom_minimum_size = Vector2(110, 44)
	done.add_theme_stylebox_override("normal", UITheme.box(INK, 12, 18))
	done.add_theme_stylebox_override("hover", UITheme.box(Color("2d3647"), 12, 18))
	done.add_theme_stylebox_override("pressed", UITheme.box(UITheme.ACCENT, 12, 18, INK, 2))
	done.add_theme_stylebox_override("focus", UITheme.box(INK, 12, 18, UITheme.ACCENT, 3))
	done.add_theme_color_override("font_color", Color.WHITE)
	done.add_theme_color_override("font_hover_color", Color.WHITE)
	done.add_theme_color_override("font_focus_color", Color.WHITE)
	head.add_child(done)
	vb.add_child(head)
	var bar := ColorRect.new()
	bar.color = UITheme.ACCENT
	bar.custom_minimum_size.y = 4
	vb.add_child(bar)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	for page in _pages():
		tabs.add_child(page.get_parent())   # the page's ScrollContainer
	tabs.get_tab_bar().add_theme_constant_override("h_separation", 6)
	tabs.current_tab = tab

func _close() -> void:
	closed.emit()
	queue_free()

func _reopen(tab: int) -> void:
	_build.call_deferred(tab)   # deferred: the button that asked is still mid-signal

# ---------------------------------------------------------------- building blocks
func _lbl(text: String, size := 16, color := INK, black := false) -> Label:
	return UITheme.label(text, size, color, black)

func _page(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	return vb

## small caps heading with a yellow tick
func _section(parent: Control, text: String) -> void:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 10 if parent.get_child_count() > 0 else 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var tick := ColorRect.new()
	tick.color = UITheme.ACCENT
	tick.custom_minimum_size = Vector2(5, 16)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tick)
	hb.add_child(_lbl(text, 13, INK, true))
	m.add_child(hb)
	parent.add_child(m)

func _hint(parent: Control, text: String) -> void:
	var l := _lbl(text, 13, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)

func _row(parent: Control, text: String, ctl: Control, tip := "") -> void:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size.y = 38
	var l := _lbl(text, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	ctl.custom_minimum_size.x = 260
	hb.add_child(l); hb.add_child(ctl)
	parent.add_child(hb)

func _option(parent: Control, text: String, key: String, items: Array, tip := "") -> void:
	var ob := OptionButton.new()
	for it in items: ob.add_item(it)
	ob.selected = int(Settings.get_v(key))
	ob.item_selected.connect(func(i): Settings.set_v(key, i))
	_row(parent, text, ob, tip)

func _check(parent: Control, text: String, key: String, tip := "") -> void:
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get_v(key)
	cb.toggled.connect(func(on): Settings.set_v(key, on))
	_row(parent, text, cb, tip)

## slider + value + reset arrow. `apply` is called with the value (once on release while dragging).
func _slider_row(parent: Control, text: String, lo: float, hi: float, stepv: float, start: float, dflt: float, fmt: String, tip: String, apply: Callable) -> void:
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = stepv
	s.value = start
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := _lbl(fmt % s.value, 15, MUTED)
	vl.custom_minimum_size.x = 56
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# while dragging only the label follows: applying a setting re-sets the window, viewport, shadows,
	# audio and bindings and writes the file, so it happens once on release (keys / wheel / reset: at once)
	var drag := [false]
	s.drag_started.connect(func(): drag[0] = true)
	s.drag_ended.connect(func(changed):
		drag[0] = false
		if changed: apply.call(s.value))
	s.value_changed.connect(func(v):
		vl.text = fmt % v
		if not drag[0]: apply.call(v))
	hb.add_child(s); hb.add_child(vl)
	hb.add_child(UITheme.reset_button(s, dflt, MUTED, INK))
	_row(parent, text, hb, tip)

func _slider(parent: Control, text: String, key: String, lo: float, hi: float, stepv: float, fmt := "%.2f", tip := "") -> void:
	_slider_row(parent, text, lo, hi, stepv, float(Settings.get_v(key)), float(Settings.DEFAULTS.get(key, Settings.get_v(key))),
		fmt, tip, func(v): Settings.set_v(key, v))

## a slider for a ride tuning value (Tune, saved in tune.cfg), range and default from Tune.DEFS
func _tune_slider(parent: Control, text: String, key: String, fmt: String, tip := "") -> void:
	var row: Array = []
	for g in Tune.DEFS:
		for r in g[1]:
			if r[0] == key: row = r
	if row.is_empty(): return
	_slider_row(parent, text, row[3], row[4], row[5], float(Tune.base.get(key, row[2])), float(row[2]),
		fmt, tip, func(v): Tune.set_value(key, v))
