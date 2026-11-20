class_name PicStrip
extends ScrollContainer
## A horizontal, slidable strip of picture cards (menus / garage): drag it sideways with the mouse, turn the wheel
## over it, or move the focus along it (pad). A drag never presses the card it started on (`dragged`).

const DRAG_FROM := 8.0   # px the mouse must move before a press turns into a slide

var row := HBoxContainer.new()
var dragged := false     # true from the moment a press became a slide until just after its release
var _down := false
var _from := Vector2.ZERO
var _start := 0
var _vel := 0.0          # px/s at release: the strip glides on a little
var _last_x := 0.0
var _last_t := 0
var square := 0.0         # > 0: the cards are this wide per pixel of the strip's height (they grow with free height)


func _init(gap := 8) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", gap)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	resized.connect(_fit)


## cards as wide as the strip is tall (x `square`), never narrower than they were made
func _fit() -> void:
	if square <= 0.0: return
	for c in row.get_children():
		var cc := c as Control
		if cc == null: continue
		if not cc.has_meta("w0"): cc.set_meta("w0", cc.custom_minimum_size.x)
		cc.custom_minimum_size.x = maxf(float(cc.get_meta("w0")), (size.y - 12.0) * square)


func add(c: Control, picked := false) -> void:
	row.add_child(c)
	if picked: _reveal.call_deferred(c)


## the picked card in view when the strip opens (after layout; also after a page's focus moved it)
func _reveal(c: Control) -> void:
	for i in 2:
		await get_tree().process_frame
		if not is_instance_valid(c) or not is_inside_tree(): return
		var x := c.position.x
		if x < scroll_horizontal or x + c.size.x > scroll_horizontal + size.x:
			scroll_horizontal = int(maxf(0.0, x - Tokens.S3))


## wraps a card's action so a slide that ends on it doesn't press it
func guard(cb: Callable) -> Callable:
	return func():
		if not dragged: cb.call()


func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			_down = get_global_rect().has_point(get_global_mouse_position())
			_from = get_global_mouse_position()
			_start = scroll_horizontal
			_vel = 0.0
			dragged = false
		elif _down:
			_down = false
			if dragged:
				_release_after.call_deferred()
	elif e is InputEventMouseMotion and _down:
		var dx := get_global_mouse_position().x - _from.x
		if not dragged and absf(dx) > DRAG_FROM:
			dragged = true
		if dragged:
			scroll_horizontal = _start - int(dx)
			var now := Time.get_ticks_msec()
			var dt := maxf(0.001, (now - _last_t) / 1000.0)
			_vel = lerpf(_vel, -(get_global_mouse_position().x - _last_x) / dt, 0.4)
			_last_t = now
			_last_x = get_global_mouse_position().x
			return
	if e is InputEventMouseMotion:
		_last_x = get_global_mouse_position().x
		_last_t = Time.get_ticks_msec()


func _release_after() -> void:
	await get_tree().process_frame   # the card's pressed signal (on release) has seen `dragged` by now
	dragged = false


func _process(dt: float) -> void:
	if _down or absf(_vel) < 20.0:
		return
	scroll_horizontal += int(_vel * dt)
	_vel *= pow(0.02, dt)   # glides to a stop in about a second
