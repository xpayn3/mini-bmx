extends CanvasLayer
## Controller plugged in / unplugged notice (top centre, over everything: menus, rides, pause, garage).
## Made by Settings._ready. Listens to Input.joy_connection_changed; test runs stay silent
## (BMX_PADTOAST=connect|disconnect shows one for a screenshot).

const SHOW_T := 3.0      ## seconds on screen
const IN_T := 0.25
const OUT_T := 0.4
const STARTUP_QUIET := 4.0   ## s: pads already plugged in at launch report themselves, not news

var _names := {}   ## device -> name, kept so a disconnect can still say which one
var _view: Control
var _text := ""
var _sub := ""
var _on := false   ## true = connected
var _t := -1.0     ## time since the toast began; < 0 = hidden

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	for j in Input.get_connected_joypads(): _names[j] = Input.get_joy_name(j)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.draw.connect(_draw_toast)
	add_child(_view)
	Input.joy_connection_changed.connect(_on_change)
	var t := Env.raw("BMX_PADTOAST")
	if t != "":
		_hold = true
		_show.call_deferred(t == "connect", "Xbox Series Controller")

func _on_change(device: int, connected: bool) -> void:
	if connected: _names[device] = Input.get_joy_name(device)
	var nm: String = _names.get(device, "")
	if not connected: _names.erase(device)
	if Settings._test_run and Env.raw("BMX_PADTOAST") == "": return
	if Time.get_ticks_msec() < STARTUP_QUIET * 1000.0: return
	_show(connected, nm)

func _show(connected: bool, nm: String) -> void:
	_on = connected
	_text = "CONTROLLER CONNECTED" if connected else "CONTROLLER DISCONNECTED"
	var low := nm.to_lower()
	_sub = "Xbox controller" if (low.contains("xbox") or low.contains("x-box")) else nm
	_t = 0.0
	if connected: Settings.pad_active = true   # prompts switch to its button names (the next real input would anyway)
	_view.queue_redraw()

const PHOTO := "res://assets/ui/xbox_pad.png"
var _tex: Texture2D
var _last_us := 0
var _hold := false

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_us) / 1e6, 0.1)   # real time: crash slow motion / photo mode (time_scale 0) don't stretch it
	_last_us = now
	if _t < 0.0: return
	_t += dt
	if _hold and _t > IN_T + 0.5: _t = IN_T + 0.5   # test: keep it up for a screenshot
	if _t > IN_T + SHOW_T + OUT_T: _t = -1.0
	_view.queue_redraw()

func _draw_toast() -> void:
	if _t < 0.0: return
	var k := minf(_t / IN_T, 1.0)
	k = 1.0 - pow(1.0 - k, 3.0)
	var out := clampf((_t - IN_T - SHOW_T) / OUT_T, 0.0, 1.0)
	var a := k * (1.0 - out)
	var f := UITheme.display_font(800)
	var fs := 20
	var sfs := 14
	var w1 := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w2 := f.get_string_size(_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x if _sub != "" else 0.0
	var h := 64.0
	var icon_w := 64.0
	var w := icon_w + maxf(w1, w2) + 34.0   # right end rounds off the pill
	var vw := _view.size.x
	var x := (vw - w) * 0.5
	var y := 22.0 - (1.0 - k) * 30.0
	var accent := Color("#3ecf5a") if _on else Color("#ff4b3e")
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Tokens.PAPER, a)   # white paper pill, like the menu cards (no outline)
	box.set_corner_radius_all(int(h * 0.5))
	box.set_corner_detail(16)
	_view.draw_style_box(box, Rect2(x, y, w, h))
	# round dark badge (the white pad photo needs it on white paper) with a status dot
	var c := Vector2(x + 8 + icon_w * 0.5, y + h * 0.5)
	var br := h * 0.5 - 6.0
	_disc(c, br, Color(Tokens.INK, a))
	if _tex == null and ResourceLoader.exists(PHOTO):
		_tex = load(PHOTO)
	if _tex != null:
		var iw := 38.0
		var ih := iw * _tex.get_height() / _tex.get_width()
		var bump := 1.0 + 0.12 * (1.0 - k) + (0.05 * sin(_t * 18.0) * exp(-_t * 5.0) if _on else 0.0)   # little pop on connect
		var r := Rect2(c - Vector2(iw, ih) * 0.5 * bump, Vector2(iw, ih) * bump)
		var tint := Color(1, 1, 1, a) if _on else Color(0.5, 0.5, 0.54, a)
		_view.draw_texture_rect(_tex, r, false, tint)
	if not _on:
		_view.draw_line(c + Vector2(-15, -11), c + Vector2(15, 11), Color(accent, a), 3.0, true)
	var dot := c + Vector2(br * 0.72, br * 0.72)
	_disc(dot, 6.5, Color(Tokens.PAPER, a))
	_disc(dot, 4.5, Color(accent, a))
	var tx := x + 8 + icon_w
	var top := y + (28.0 if _sub != "" else 38.0)
	_view.draw_string(f, Vector2(tx, top), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Tokens.INK, a))
	if _sub != "":
		_view.draw_string(f, Vector2(tx, y + 49.0), _sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(Tokens.INK_SOFT, a))

## anti-aliased disc (plain draw_circle is jagged): a rounded box with radius = half its size
func _disc(c: Vector2, r: float, col: Color) -> void:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(int(ceil(r)))
	b.set_corner_detail(24)
	b.anti_aliasing = true
	_view.draw_style_box(b, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
