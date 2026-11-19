extends CanvasLayer
## A small fullscreen toggle in the bottom-right corner, on every screen (menu, ride, garage, pause).
## Click it (or press F11) to switch between a window and borderless fullscreen; it saves the choice as
## Settings › Display › window mode. The icon follows the real window mode, so changes made in Settings show too.

const SIZE := 30.0
const MARGIN := 14.0
var btn: Btn

func _ready() -> void:
	layer = 60   # over the HUD, menus and the fade
	process_mode = Node.PROCESS_MODE_ALWAYS   # works while paused
	btn = Btn.new()
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_place(0.0)
	btn.focus_mode = Control.FOCUS_NONE   # keys / pad never land on it
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(toggle)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(btn)

## offsets from the bottom-right anchor
func _place(lift: float) -> void:
	btn.offset_right = -MARGIN; btn.offset_left = -MARGIN - SIZE
	btn.offset_bottom = -MARGIN - lift; btn.offset_top = -MARGIN - lift - SIZE

static func is_full() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

static func toggle() -> void:
	Settings.set_v("window_mode", 0 if is_full() else 1)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		toggle()
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	# in the garage its Save / Save & ride buttons sit in that corner: go up over them
	var lift := 56.0 if is_instance_valid(get_parent().get("garage")) else 0.0
	_place(lift)
	btn.tooltip_text = "Exit fullscreen (F11)" if is_full() else "Fullscreen (F11)"
	btn.queue_redraw()

class Btn extends Button:
	## four corner brackets: pointing out = go fullscreen, pointing in = leave it
	func _draw() -> void:
		var hot := is_hovered()
		var down := is_pressed() or button_pressed
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UITheme.box(Color(0, 0, 0, 0.55 if hot else 0.32), 7, 0, Color(1, 1, 1, 0.25 if hot else 0.1), 1), r)
		var c := Color(1, 1, 1, 1.0 if hot else 0.7)
		var wm := DisplayServer.window_get_mode()
		var full := wm == DisplayServer.WINDOW_MODE_FULLSCREEN or wm == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		var m := 8.0 + (1.0 if down else 0.0)
		var l := 6.0
		var w := 2.0
		var corners := [Vector2(m, m), Vector2(size.x - m, m), Vector2(m, size.y - m), Vector2(size.x - m, size.y - m)]
		for p: Vector2 in corners:
			var sx := 1.0 if p.x < size.x / 2 else -1.0   # +1 = left corner: arms go right
			var sy := 1.0 if p.y < size.y / 2 else -1.0
			if full:   # brackets turned inward: the corner point sits inside, arms reach out to the edge
				var q := p + Vector2(sx, sy) * l * 0.85
				draw_line(q, q - Vector2(sx * l, 0), c, w)
				draw_line(q, q - Vector2(0, sy * l), c, w)
			else:
				draw_line(p, p + Vector2(sx * l, 0), c, w)
				draw_line(p, p + Vector2(0, sy * l), c, w)
