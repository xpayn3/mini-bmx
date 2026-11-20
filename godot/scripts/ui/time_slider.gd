extends Control
## Time-of-day slider (ride setup page, RACE step): the whole day as a strip of sky, each moment in its own colours, with the
## sun's path drawn over it as a curve (Game.sun_elev_deg): it rises at sunrise, arcs over noon and sets at sunset; under
## the horizon the curve dims (the moon's half). Drag / click / wheel picks the hour; the handle is the sun (or the moon),
## the time and the part of the day ride above it. Pad: left / right = -/+ 15 min (PadNav `nav_step`). Snaps to 5 min.
## No class_name (loaded with preload): a new class_name needs a re-import.

signal changed(hour: float)      # every move (live)
signal committed(hour: float)    # let go / a key step: the moment to save

const RISE := 6.0
const SET := 20.0
const STEP := 0.25               # pad / wheel step (h)
const SNAP := 5.0 / 60.0

var hour := 19.33
var cycle := false               # the day / night cycle is on: an AUTO badge, the hour = where it starts
var _drag := false
var _hover := -1.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 230)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta(&"nav_step", func(d: int): _set_hour(hour + d * STEP, true))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_exited.connect(func(): _hover = -1.0; queue_redraw())


static func elev(h: float) -> float:
	var x := fposmod(h - 6.0, 24.0)
	return 62.0 * sin(PI * x / 14.0) if x <= 14.0 else -50.0 * sin(PI * (x - 14.0) / 10.0)


## the period of the day for a label
static func period(h: float) -> String:
	var e := elev(h)
	var morning := fposmod(h, 24.0) < 13.0
	if e < -8.0: return "NIGHT"
	if e < 0.0: return "DAWN" if morning else "DUSK"
	if e < 4.0: return "SUNRISE" if morning else "SUNSET"
	if e < 14.0: return "MORNING GOLD" if morning else "GOLDEN HOUR"
	if e > 55.0: return "MIDDAY"
	return "MORNING" if morning else "AFTERNOON"


# ---- layout
func _plot() -> Rect2:
	return Rect2(Vector2(8, 34), Vector2(size.x - 16, size.y - 34 - 22))

func _hz(p: Rect2) -> float:
	return p.position.y + p.size.y * 0.62

func _pt(p: Rect2, h: float) -> Vector2:
	var e := elev(h)
	var hz := _hz(p)
	var up := hz - p.position.y - 10.0
	var dn := p.end.y - hz - 6.0
	var y := hz - (e / 62.0) * up if e >= 0.0 else hz - (e / 50.0) * dn
	return Vector2(p.position.x + p.size.x * h / 24.0, y)

func _hour_at(x: float) -> float:
	var p := _plot()
	return clampf((x - p.position.x) / p.size.x * 24.0, 0.0, 24.0)


func _set_hour(h: float, commit: bool) -> void:
	h = clampf(snappedf(h, SNAP), 0.0, 23.99)
	var moved := absf(h - hour) > 0.001
	hour = h
	queue_redraw()
	if moved: changed.emit(hour)
	if commit: committed.emit(hour)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				grab_focus()
				_set_hour(_hour_at(mb.position.x), false)
			elif _drag:
				_drag = false
				_set_hour(_hour_at(mb.position.x), true)
			accept_event()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_set_hour(hour + (STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -STEP), true)
			accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_hover = _hour_at(mm.position.x)
		if _drag: _set_hour(_hover, false)
		queue_redraw()
	elif ev is InputEventKey and ev.pressed and has_focus():
		var k := (ev as InputEventKey).keycode
		if k == KEY_LEFT or k == KEY_RIGHT:
			_set_hour(hour + (STEP if k == KEY_RIGHT else -STEP), true)
			accept_event()


# ---- drawing
func _draw() -> void:
	var p := _plot()
	var hz := _hz(p)
	var font := UITheme.display_font(600, 0.0)
	var small := UITheme.display_font(500, 0.0)
	# the day's sky, column by column (TimeIcon's sky colours round the clock), darker under the horizon
	var cols := 96
	for i in cols:
		var h0 := 24.0 * i / cols
		var h1 := 24.0 * (i + 1) / cols
		var sk := TimeIcon._sky((h0 + h1) * 0.5)
		var x0 := p.position.x + p.size.x * h0 / 24.0
		var x1 := p.position.x + p.size.x * h1 / 24.0 + 0.6
		var top: Color = sk[0]; var bot: Color = sk[1]
		draw_polygon(PackedVector2Array([Vector2(x0, p.position.y), Vector2(x1, p.position.y), Vector2(x1, hz), Vector2(x0, hz)]),
			PackedColorArray([top, top, bot, bot]))
		var ground := bot.lerp(Color(0.05, 0.06, 0.1), 0.72)
		draw_polygon(PackedVector2Array([Vector2(x0, hz), Vector2(x1, hz), Vector2(x1, p.end.y), Vector2(x0, p.end.y)]),
			PackedColorArray([ground, ground, ground.darkened(0.35), ground.darkened(0.35)]))
	# stars over the night ends
	for i in 40:
		var sx := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var sh := sx * 24.0
		if elev(sh) > -4.0: continue
		var sy := p.position.y + 4.0 + fposmod(sin(i * 78.233) * 12543.123, 1.0) * (hz - p.position.y - 14.0)
		draw_circle(Vector2(p.position.x + sx * p.size.x, sy), 0.9 + fposmod(i * 0.37, 0.8), Color(1, 1, 1, 0.75))
	# golden hours: a warm glow band on the sky where the sun is low
	for gh in [[RISE, RISE + 1.6], [SET - 1.6, SET]]:
		var xa := p.position.x + p.size.x * float(gh[0]) / 24.0
		var xb := p.position.x + p.size.x * float(gh[1]) / 24.0
		draw_rect(Rect2(xa, p.position.y, xb - xa, hz - p.position.y), Color(1.0, 0.7, 0.3, 0.13))
	# the horizon
	draw_line(Vector2(p.position.x, hz), Vector2(p.end.x, hz), Color(1, 1, 1, 0.45), 1.0)
	# the sun's path: a soft fill under the day arc, the curve warm-white over the horizon, dotted under it
	var n := 160
	var fill := PackedVector2Array()
	for i in n + 1:
		var h := 24.0 * i / n
		if elev(h) >= 0.0: fill.append(_pt(p, h))
	if fill.size() > 2:
		fill.append(Vector2(fill[fill.size() - 1].x, hz)); fill.append(Vector2(fill[0].x, hz))
		draw_colored_polygon(fill, Color(1.0, 0.95, 0.8, 0.1))
	for i in n:
		var ha := 24.0 * i / n
		var hb := 24.0 * (i + 1) / n
		var a := _pt(p, ha); var b := _pt(p, hb)
		var e := elev((ha + hb) * 0.5)
		if e >= 0.0:
			var warm := 1.0 - clampf(e / 25.0, 0.0, 1.0)
			draw_line(a, b, Color(1.0, 0.96, 0.82).lerp(Color(1.0, 0.62, 0.26), warm), 3.0, true)
		elif i % 3 == 0:
			draw_line(a, b, Color(0.75, 0.82, 1.0, 0.45), 1.5, true)
	# sunrise / sunset marks on the horizon
	for m in [[RISE, "SUNRISE", true], [SET, "SUNSET", false]]:
		var x := p.position.x + p.size.x * float(m[0]) / 24.0
		var up: bool = m[2]
		var tri := PackedVector2Array([Vector2(x - 5, hz + (4 if up else -4) + 0), Vector2(x + 5, hz + (4 if up else -4)), Vector2(x, hz + (-5 if up else 5))])
		draw_colored_polygon(tri, Color(1.0, 0.72, 0.35))
		var t := "%s  %s" % [m[1], LightSettings.clock(float(m[0]))]
		var w := small.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(small, Vector2(clampf(x - w * 0.5, p.position.x + 2, p.end.x - w - 2), hz + 18), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.65, 0.9))
	# hour ticks under the strip
	for th: int in [0, 3, 6, 9, 12, 15, 18, 21, 24]:
		var x := p.position.x + p.size.x * float(th) / 24.0
		draw_line(Vector2(x, p.end.y), Vector2(x, p.end.y + 4), Tokens.INK_SOFT, 1.0)
		var t := "%02d" % (th % 24 if th < 24 else 24)
		var w := small.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(small, Vector2(clampf(x - w * 0.5, 0, size.x - w), p.end.y + 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Tokens.INK_SOFT)
	# hover ghost
	if _hover >= 0.0 and not _drag:
		var gp := _pt(p, _hover)
		draw_circle(gp, 5.0, Color(1, 1, 1, 0.35))
	# the handle: a line down through the strip, the sun (or moon) on the curve
	var hp := _pt(p, hour)
	draw_line(Vector2(hp.x, p.position.y), Vector2(hp.x, p.end.y), Color(1, 1, 1, 0.55), 1.0)
	var e0 := elev(hour)
	if e0 >= -1.0:
		var warm := 1.0 - clampf(e0 / 25.0, 0.0, 1.0)
		var c := Color(1.0, 0.97, 0.86).lerp(Color(1.0, 0.6, 0.24), warm)
		draw_circle(hp, 19.0, Color(c.r, c.g, c.b, 0.14))
		draw_circle(hp, 13.0, Color(c.r, c.g, c.b, 0.3))
		draw_circle(hp, 8.5, c)
	else:
		draw_circle(hp, 15.0, Color(0.85, 0.9, 1.0, 0.12))
		draw_circle(hp, 8.5, Color(0.95, 0.96, 0.9))
		var sk := TimeIcon._sky(hour)
		draw_circle(hp + Vector2(3.5, -2.0), 7.2, (sk[0] as Color).lerp(sk[1], 0.3).lerp(Color(0.05, 0.06, 0.1), 0.6))
	# the time + the part of the day, over the handle (kept inside the strip)
	var tt := LightSettings.clock(hour)
	var pt := period(hour) + ("  ·  AUTO" if cycle else "")
	var tw := font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var pw := small.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var bw := tw + 10.0 + pw + 20.0
	var bx := clampf(hp.x - bw * 0.5, 0.0, size.x - bw)
	var box := Rect2(bx, 2, bw, 28)
	draw_rect(box, Tokens.INK if not has_focus() else Tokens.ACCENT)
	var ink := Color.WHITE if not has_focus() else Tokens.INK
	draw_string(font, Vector2(bx + 10, 24), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_string(small, Vector2(bx + 10 + tw + 10, 21), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(ink, 0.8))
	# a pointer from the label to the handle
	draw_colored_polygon(PackedVector2Array([Vector2(clampf(hp.x, bx + 6, bx + bw - 6) - 5, 30), Vector2(clampf(hp.x, bx + 6, bx + bw - 6) + 5, 30), Vector2(clampf(hp.x, bx + 6, bx + bw - 6), 35)]),
		Tokens.INK if not has_focus() else Tokens.ACCENT)
