class_name SmoothScroll
extends Node
## Smooth, eased scrolling for a ScrollContainer: `SmoothScroll.attach(sc)`.
## The mouse wheel / touchpad move a target and the list glides to it (notches pile up while it moves);
## jumps from follow-focus (pad / keys) or code glide too. Dragging the scroll bar stays 1:1.
## Runs on real time, so it works in pause menus and photo mode (time scale 0).

const RATE := 15.0          # how quickly the list catches the target (1/s; higher = snappier)
const NOTCH := 0.2          # one wheel notch = this much of the visible height
const NOTCH_MIN := 60.0
const MAX_GLIDE := 2400.0   # a jump further than this snaps (a rebuilt page, not a scroll)

var sc: ScrollContainer
var pos := 0.0
var target := 0.0
var _setting := false
var _last_us := 0


static func attach(s: ScrollContainer) -> SmoothScroll:
	if s == null: return null
	if s.has_meta(&"smooth_scroll"):
		var old = s.get_meta(&"smooth_scroll")
		if is_instance_valid(old): return old
	var n := SmoothScroll.new()
	n.sc = s
	s.set_meta(&"smooth_scroll", n)
	s.add_child(n, false, Node.INTERNAL_MODE_BACK)   # internal: get_child(0) still finds the page
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pos = sc.scroll_vertical
	target = pos
	sc.gui_input.connect(_on_input.bind(sc))
	sc.get_v_scroll_bar().gui_input.connect(_on_input.bind(sc.get_v_scroll_bar()))
	sc.get_v_scroll_bar().value_changed.connect(_on_value)
	set_process(false)


func _max() -> float:
	var bar := sc.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)


func _on_input(e: InputEvent, from: Control) -> void:
	var dy := 0.0
	var step := maxf(NOTCH_MIN, sc.size.y * NOTCH)
	if e is InputEventMouseButton and e.pressed:
		var f: float = e.factor if e.factor > 0.0 else 1.0
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: dy = -step * f
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dy = step * f
	elif e is InputEventPanGesture:
		dy = e.delta.y * step * 0.5
	if dy == 0.0 or _max() <= 0.0: return
	from.accept_event()   # ours, not the container's own jumpy step
	# reversing direction mid-glide starts from where the list is, not from the far target
	if signf(dy) != signf(target - pos) and absf(target - pos) > 1.0: target = pos
	target = clampf(target + dy, 0.0, _max())
	_go()


## the value changed by someone else: follow-focus, code, the scroll bar
func _on_value(v: float) -> void:
	if _setting: return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or absf(v - pos) > MAX_GLIDE or not sc.is_visible_in_tree():
		pos = v; target = v   # dragging the bar / a rebuilt page: no glide
		set_process(false)
		return
	target = clampf(v, 0.0, _max())
	_put(pos)   # back to where it was this frame, then glide there (set before drawing: no flash)
	_go()


func _go() -> void:
	if not is_processing():
		_last_us = Time.get_ticks_usec()
		set_process(true)


func _put(p: float) -> void:
	_setting = true
	sc.scroll_vertical = roundi(p)
	_setting = false


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1e6, 0.0, 0.05)
	_last_us = now
	target = clampf(target, 0.0, _max())
	pos = lerpf(pos, target, 1.0 - exp(-RATE * dt))
	if absf(target - pos) < 0.5:
		pos = target
		set_process(false)
	_put(pos)
	if Env.s("BMX_SCROLL_PROBE") != "": print("SCROLL pos=%.1f target=%.1f shown=%d" % [pos, target, sc.scroll_vertical])
