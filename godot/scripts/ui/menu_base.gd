class_name MenuBase
extends PanelContainer
## A full window (Settings, Controls): solid white card, heavy slanted title with a yellow slab, pill tabs,
## grey page with ink text. Subclasses give `_title()` and `_pages()`; the helpers below build the rows.

signal closed

const INK := UITheme.L_INK
const MUTED := UITheme.L_MUTED

## paper = true: printed on a sheet (the pause leaflet's inside): no card, UITheme.print_theme(), it fills
## paper_size (set both before adding it)
var paper := false
var paper_size := Vector2.ZERO
## type scale: printed on the leaflet the page has room, so everything is drawn bigger
var fs := 1.0
var nav: PadNav
var _tabs: TabContainer

func _f(n: float) -> int: return int(round(n * fs))

func _title() -> String: return ""
func _pages() -> Array: return []   # ScrollContainers from _page()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if paper:
		fs = 1.45
		var t: Theme = UITheme.print_theme().duplicate()
		t.default_font_size = _f(19)
		for c in ["Button", "OptionButton", "CheckButton", "PopupMenu", "TabContainer", "TabBar", "LineEdit"]:
			t.set_font_size("font_size", c, _f(19))
		t.set_font_size("font_size", "TabContainer", _f(20))
		theme = t
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		size = paper_size
		custom_minimum_size = paper_size
		_build(0)
		return
	theme = UITheme.paper_theme()
	var vp := get_viewport_rect().size
	custom_minimum_size = Vector2(minf(880.0, vp.x - 60.0), minf(660.0, vp.y - 60.0))
	add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S6))
	UITheme.centre.call_deferred(self)
	_build(0)

## (Re)build the contents in place. The node itself is never replaced: whoever opened it keeps
## its connection to `closed`.
func _build(tab: int) -> void:
	for c in get_children():
		if c == nav: continue
		remove_child(c); c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", Tokens.S4)
	add_child(vb)
	move_child(vb, 0)   # (before PadNav: a rebuild keeps the focused row's place in the tree)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Tokens.S4)
	var title := UITheme.display(_title().to_upper(), _f(Tokens.T_3XL), INK, Tokens.SLANT_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var done: Button
	if paper:   # printed: the print theme's stamped button, a red rule under the heading
		done = UITheme.button("Fold up", _close, _f(17))
		done.custom_minimum_size = Vector2(_f(110), _f(44))
	else:
		done = UITheme.make_button("DONE", _close, "primary", Tokens.T_XL)
		done.custom_minimum_size.y = Tokens.H_BTN
	head.add_child(done)
	vb.add_child(head)
	if paper:
		var bar := ColorRect.new()
		bar.color = UITheme.P_RED
		bar.custom_minimum_size.y = 3
		vb.add_child(bar)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	for page in _pages():
		tabs.add_child(page.get_parent())   # the page's ScrollContainer
	tabs.get_tab_bar().add_theme_constant_override("h_separation", Tokens.S2)
	tabs.current_tab = tab
	_tabs = tabs
	# a tab opens at its top (pages built while hidden came up scrolled), the cursor's row kept in view
	tabs.tab_changed.connect(func(i: int):
		var sc := tabs.get_tab_control(i) as ScrollContainer
		if sc == null: return
		await get_tree().process_frame
		if not is_instance_valid(sc): return
		var f := get_viewport().gui_get_focus_owner()
		sc.scroll_vertical = 0
		if f and sc.is_ancestor_of(f): sc.ensure_control_visible(f))
	if not nav:   # D-pad / stick between rows, A press, B back (on paper the leaflet's B folds it), LB / RB tabs
		nav = PadNav.attach(self, {"tab_container": tabs, "back": Callable() if paper else _close, "style": "paper" if paper else "card"})
	else:
		nav.root = self; nav.tab_container = tabs
		tabs.tab_changed.connect(func(_i): if nav._pad_recent(): nav.focus_first.call_deferred())
		nav._prep_all(self)
		return   # rebuilt after a change: PadNav puts focus back on the same row
	_first_focus.call_deferred()

## focus the page's first control (rebuilt / opened); keeps the row it was on after a rebuild if it can
func _first_focus() -> void:
	if is_instance_valid(nav): nav.focus_first()

func _close() -> void:
	closed.emit()
	queue_free()

func _reopen(tab: int) -> void:
	_build.call_deferred(tab)   # deferred: the button that asked is still mid-signal

# ---------------------------------------------------------------- building blocks
func _lbl(text: String, size := 16, color := INK, black := false) -> Label:
	return UITheme.label(text, _f(size), color, black)

func _page(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	SmoothScroll.attach(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", _f(10))
	sc.follow_focus = true
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
	tick.custom_minimum_size = Vector2(5, _f(16))
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
	hb.custom_minimum_size.y = _f(38)
	hb.set_meta("nav_row", true)   # PadNav marks the whole row when its control has focus
	var l := _lbl("  " + text, 16)   # (room for the focus marker's bar)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	ctl.custom_minimum_size.x = _f(260)
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
	s.scrollable = false   # (the wheel scrolls the list; it never changes a value by accident)
	s.min_value = lo; s.max_value = hi; s.step = stepv
	s.value = start
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var vl := _lbl(fmt % s.value, 15, MUTED)
	vl.custom_minimum_size.x = _f(56)
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
