class_name PadNav
extends Node
## Console-style menu navigation for one menu (a Control root), the Xbox way: D-pad / left stick move focus
## (held = repeats), A presses, B goes back (`back`), LB / RB switch tabs (a TabContainer, or `tabs`).
## Every ScrollContainer under the root follows focus, sliders step 1/20 of their range per press, and the
## focused row (a container with meta "nav_row", see MenuBase._row) gets a marker in the flat style:
## a wash + a bar on its left (`style` "paper" = highlighter + red ink, "card" = yellow tokens).
## Works inside a SubViewport (the paper sheets push pad / keys into their page).
## One cursor, console style: hovering a button with the mouse moves the focus there (the button's own hover
## look is turned off, so a mouse resting somewhere never leaves a second highlight); moving onto a pick in a
## ButtonGroup (bike, kit, time of day...) with the D-pad / stick / arrows picks it at once; a control with meta
## "nav_accept" (Callable) runs it on A (setup screens: A on the picked bike = next step).
##   PadNav.attach(menu, {"tabs": tab_container, "back": _close, "style": "paper"})

const REPEAT_DELAY := 0.38
const REPEAT_EVERY := 0.075
const DIRS := [&"ui_up", &"ui_down", &"ui_left", &"ui_right"]

var root: Control
var tab_container: TabContainer
var tabs := Callable()          # func(dir: int): switch tabs yourself (garage, tuning card)
var back := Callable()          # B / Esc
var first := Callable()         # func() -> Control: where focus lands when a page opens
var style := "card"
var enabled := true

var _row: Control
var _serial := 0
static var _count := 0
var _held := StringName()
var _held_t := 0.0
var _last_ms := 0


static func attach(r: Control, opts := {}) -> PadNav:
	var n := PadNav.new()
	n.root = r
	n.tab_container = opts.get("tab_container", null)
	n.tabs = opts.get("tabs", Callable())
	n.back = opts.get("back", Callable())
	n.first = opts.get("first", Callable())
	n.style = opts.get("style", "card")
	n.name = "PadNav"
	r.add_child(n)
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_count += 1; _serial = _count
	add_to_group(&"pad_nav")
	get_viewport().gui_focus_changed.connect(_on_focus)
	get_tree().node_added.connect(_prep)
	_prep_all(root)
	if tab_container: tab_container.tab_changed.connect(func(_i): if _pad_recent(): focus_first.call_deferred())
	_last_ms = Time.get_ticks_msec()
	_return_to = get_viewport().gui_get_focus_owner()
	if Settings.pad_active and not _owns_focus(): focus_first.call_deferred()   # on a pad: land on the first control


var _return_to: Control

func _exit_tree() -> void:
	if is_instance_valid(_row): _row.queue_redraw()
	# a window over another menu closes: focus goes back where it was (the title menu's SETTINGS)
	if is_instance_valid(_return_to) and not (_return_to == root or root.is_ancestor_of(_return_to)):
		_return_to.call_deferred(&"grab_focus")


# ------------------------------------------------------------------ preparing controls
func _prep_all(n: Node) -> void:
	_prep(n)
	for c in n.get_children(): _prep_all(c)

func _prep(n: Node) -> void:
	if not is_instance_valid(root) or not (n == root or root.is_ancestor_of(n)): return
	if n is ScrollContainer:
		(n as ScrollContainer).follow_focus = true
		SmoothScroll.attach(n)
	elif n is BaseButton and not n.has_meta(&"nav_prepped"):
		n.set_meta(&"nav_prepped", true)
		_prep_button.call_deferred(n)   # deferred: the button's own style overrides are set by then

## the mouse moves the one cursor: hover = focus, so the hover look goes (it would be a second highlight)
func _prep_button(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.focus_mode != Control.FOCUS_ALL: return
	if b is Button:
		b.add_theme_stylebox_override(&"hover", b.get_theme_stylebox(&"normal"))
		b.add_theme_stylebox_override(&"hover_pressed", b.get_theme_stylebox(&"pressed"))
		b.add_theme_color_override(&"font_hover_color", b.get_theme_color(&"font_color"))
		b.add_theme_color_override(&"font_hover_pressed_color", b.get_theme_color(&"font_pressed_color"))
	b.mouse_entered.connect(_hover.bind(b))

func _hover(b: BaseButton) -> void:
	if not _active() or _popup_up() or not is_instance_valid(b) or b.has_focus() or b.disabled: return
	if not b.is_visible_in_tree(): return
	var sc := _scroll_of(b)
	var follow := sc != null and sc.follow_focus
	if follow: sc.follow_focus = false   # hovering a half-hidden row must not scroll the list under the mouse
	_hovering = true
	b.grab_focus()
	_hovering = false
	if follow: sc.follow_focus = true

var _hovering := false
var _dir_ms := -10000   # when a D-pad / stick / arrow move came in (focus changes right after it = a pad move)


## focus the first control on the current page (or `first`)
func focus_first() -> void:
	if not is_instance_valid(root) or not root.is_visible_in_tree(): return
	var c: Control = null
	if first.is_valid(): c = first.call()
	if c == null:
		var area: Control = root
		if tab_container and tab_container.get_current_tab_control(): area = tab_container.get_current_tab_control()
		c = find_focusable(area)
	if c: c.grab_focus()
	var sc := _scroll_of(c)
	if sc and c and sc.get_global_rect().size.y > 0.0 and c.get_global_rect().position.y - sc.get_global_rect().position.y < 140.0:
		sc.scroll_vertical = 0   # the first control near the top: show the page from its top (headings)


static func find_focusable(n: Node) -> Control:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree() or c.is_queued_for_deletion(): return null
		if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled): return c
	for ch in n.get_children():
		var f := find_focusable(ch)
		if f: return f
	return null


func _scroll_of(c: Node) -> ScrollContainer:
	while c and c != root:
		if c is ScrollContainer: return c
		c = c.get_parent()
	return null


func _owns_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f != null and (f == root or root.is_ancestor_of(f))


func _popup_up() -> bool:
	for w in get_viewport().get_embedded_subwindows():
		if is_real_popup(w): return true
	return false

## an open dropdown / picker takes the pad itself; a mouse tooltip (also an embedded window) must not
static func is_real_popup(w: Window) -> bool:
	return w.visible and not w.get_flag(Window.FLAG_NO_FOCUS)   # (tooltips are no-focus windows)


## only the newest menu that's up in this viewport navigates (a Settings window over the title menu)
func _active() -> bool:
	if not enabled or not is_instance_valid(root) or not root.is_visible_in_tree(): return false
	for n in get_tree().get_nodes_in_group(&"pad_nav"):
		if n != self and n._serial > _serial and n.enabled and is_instance_valid(n.root) and n.root.is_visible_in_tree() 				and n.get_viewport() == get_viewport():
			return false
	return true


func _pad_recent() -> bool:
	return Settings.pad_active or Time.get_ticks_msec() - _last_ms < 2000


# ------------------------------------------------------------------ input
func _input(e: InputEvent) -> void:
	if not _active(): return
	if e is InputEventMouseButton or e is InputEventMouseMotion: return
	if _popup_up(): return   # an open dropdown takes the stick / A / B itself
	if e is InputEventJoypadButton or e is InputEventKey: _last_ms = Time.get_ticks_msec()
	if e is InputEventJoypadButton and e.pressed and (e.button_index == JOY_BUTTON_LEFT_SHOULDER or e.button_index == JOY_BUTTON_RIGHT_SHOULDER):
		switch_tab(-1 if e.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
		get_viewport().set_input_as_handled()
		return
	if back.is_valid() and e.is_action_pressed(&"ui_cancel") and not e.is_echo():
		back.call()
		get_viewport().set_input_as_handled()
		return
	if (e.is_action_pressed(&"ui_left", true) or e.is_action_pressed(&"ui_right", true)) and _owns_focus():
		if _step(get_viewport().gui_get_focus_owner(), -1 if e.is_action_pressed(&"ui_left", true) else 1):
			if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and not e.is_echo():
				_held = &"ui_left" if e.is_action_pressed(&"ui_left", true) else &"ui_right"; _held_t = 0.0
			get_viewport().set_input_as_handled()
			return
	if e.is_action_pressed(&"ui_accept") and not e.is_echo() and not _owns_focus() and get_viewport().gui_get_focus_owner() == null:
		_dir_ms = -10000
		focus_first()   # nothing focused yet (opened with the mouse): the first A lands the cursor
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed(&"ui_accept") and not e.is_echo() and _owns_focus():
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit and e is InputEventJoypadButton and (f as LineEdit).editable:   # A on a text box = the on-screen keyboard
			PadKeyboard.open(f)
			get_viewport().set_input_as_handled()
			return
		if f.has_meta(&"nav_step"):   # A on a stepper = the next option
			(f.get_meta(&"nav_step") as Callable).call(1)
			get_viewport().set_input_as_handled()
			return
		if f.has_meta(&"nav_accept"):   # A on a pick that follows the cursor = confirm (next step)
			if f is BaseButton and (f as BaseButton).toggle_mode and not (f as BaseButton).button_pressed:
				(f as BaseButton).button_pressed = true; (f as BaseButton).pressed.emit()
			(f.get_meta(&"nav_accept") as Callable).call()
			get_viewport().set_input_as_handled()
			return
	for a in DIRS:
		if e.is_action_pressed(a, true):
			_dir_ms = Time.get_ticks_msec()
			if (e is InputEventJoypadButton or e is InputEventJoypadMotion) and not e.is_echo():
				_held = a; _held_t = 0.0
			if not _owns_focus():   # nothing focused yet (mouse user, page just built): land first, don't move
				_dir_ms = -10000   # (landing is not a move: it picks nothing)
				focus_first()
				get_viewport().set_input_as_handled()
			return


## held D-pad / stick: repeat the move like a console menu
func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf((now - _last_tick) / 1000.0, 0.0, 0.1)
	_last_tick = now
	if not _path.is_empty() and _active() and get_viewport().gui_get_focus_owner() == null and _pad_recent():
		_refocus()
	if _held == &"" : return
	if not _active() or not Input.is_action_pressed(_held) or _popup_up():
		_held = &""; return
	_held_t += dt
	if _held_t >= REPEAT_DELAY:
		_held_t -= REPEAT_EVERY
		var ev := InputEventAction.new()
		ev.action = _held; ev.pressed = true
		get_viewport().push_input(ev)
		var up := InputEventAction.new()
		up.action = _held; up.pressed = false
		get_viewport().push_input(up)

var _last_tick := 0
var _path: Array = []

## the focused control was freed (a page rebuilt after a change): focus whatever now sits at the same place,
## else the nearest focusable after it, else the page's first
func _refocus() -> void:
	var n: Node = root
	for i in _path:
		if i >= n.get_child_count(): break
		n = n.get_child(i)
	var c: Control = null
	if n is Control and (n as Control).focus_mode == Control.FOCUS_ALL and (n as Control).is_visible_in_tree(): c = n
	if c == null:
		while n and n != root and c == null:
			c = find_focusable(n); n = n.get_parent()
	if c: c.grab_focus()
	else: focus_first()


## left / right on a row's control changes it in place, like a console menu: a slider moves 1/20 of its range,
## a dropdown steps to the next / previous option, a toggle goes off / on. false = not a steppable control.
func _step(c: Control, dir: int) -> bool:
	if c.has_meta(&"nav_step"):   # a custom stepper (the garage's ◀ VALUE ▶)
		(c.get_meta(&"nav_step") as Callable).call(dir)
		return true
	if c is Slider:
		var s := c as Slider
		var st := (s.max_value - s.min_value) / 20.0
		if s.step > 0.0: st = maxf(s.step, snappedf(st, s.step))
		s.value = clampf(s.value + st * dir, s.min_value, s.max_value)
		return true
	if c is OptionButton:
		var ob := c as OptionButton
		var i := clampi(ob.selected + dir, 0, ob.item_count - 1)
		if i != ob.selected:
			ob.select(i)
			ob.item_selected.emit(i)
		return true
	if c is CheckButton:
		var cb := c as CheckButton
		if cb.button_pressed != (dir > 0): cb.button_pressed = dir > 0   # (emits toggled)
		return true
	return false


func switch_tab(dir: int) -> void:
	if tabs.is_valid():
		tabs.call(dir)
		focus_first.call_deferred()
		return
	if not tab_container: return
	var n := tab_container.get_tab_count()
	var i := tab_container.current_tab
	for k in n:
		i = wrapi(i + dir, 0, n)
		if not tab_container.is_tab_hidden(i) and not tab_container.is_tab_disabled(i): break
	tab_container.current_tab = i
	focus_first.call_deferred()


# ------------------------------------------------------------------ the focus marker
func _on_focus(c: Control) -> void:
	if not is_instance_valid(root): return
	if c and root.is_ancestor_of(c):
		_path = []
		var n: Node = c
		while n and n != root:
			_path.push_front(n.get_index()); n = n.get_parent()
	var r: Control = null
	if c and (c == root or root.is_ancestor_of(c)):
		var p: Node = c
		for i in 4:
			if p == null or p == root: break
			if p is Control and p.has_meta("nav_row"): r = p; break
			p = p.get_parent()
		if r == null and (c is Slider or c is PadMap): r = c
		_follow_pick(c)
	if r == _row: return
	if is_instance_valid(_row): _row.queue_redraw()
	_row = r
	if r:
		if not r.draw.is_connected(_draw_mark.bind(r)): r.draw.connect(_draw_mark.bind(r))
		r.queue_redraw()


## the cursor moved onto an unpicked option of a ButtonGroup with the D-pad / stick: pick it (console carousel)
func _follow_pick(c: Control) -> void:
	if _hovering or not (c is BaseButton) or c.has_meta(&"nav_no_follow"): return
	var b := c as BaseButton
	if not b.toggle_mode or b.button_group == null or b.button_pressed or b.disabled: return
	if Time.get_ticks_msec() - _dir_ms > 120: return   # not a pad move (page built, tab switched, mouse)
	b.button_pressed = true
	b.pressed.emit()   # (setting button_pressed only emits toggled; the picks listen to pressed)


func _draw_mark(r: Control) -> void:
	if r != _row or not is_instance_valid(r): return
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not (f == r or r.is_ancestor_of(f)): return
	if r is PadMap: return   # draws its own selection
	var rc := Rect2(Vector2.ZERO, r.size)
	if style == "paper":
		r.draw_rect(rc, Color(1.0, 0.86, 0.18, 0.42))   # a highlighter swipe
		r.draw_rect(Rect2(rc.position, Vector2(Tokens.MARK + 1, rc.size.y)), UITheme.P_RED)
	elif style == "dark":   # the dark in-ride cards
		r.draw_rect(rc, Color(1, 1, 1, 0.1))
		r.draw_rect(Rect2(rc.position, Vector2(Tokens.MARK, rc.size.y)), UITheme.ACCENT)
	else:
		r.draw_rect(rc, Tokens.ACCENT_TINT)
		r.draw_rect(Rect2(rc.position, Vector2(Tokens.MARK, rc.size.y)), Tokens.ACCENT)
