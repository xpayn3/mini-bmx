## New area banner: the biome name in the WASTED type (same condensed red display face, flat, no stroke),
## smaller, at the top of the screen. In: the letters stamp down one after another from big + see-through,
## each with a little squash overshoot and a white-hot flash cooling to red; a thin red rule draws out from
## the middle under them and "ENTERING" fades in above. Out: the letters spread apart and fade.
## Runs on real time (works through the crash slow-mo).
class_name AreaTitle
extends CanvasLayer

const T_STAGGER := 0.055     # s between letters
const T_LETTER := 0.42       # s one letter takes to land
const T_HOLD := 2.6          # s fully up after the last letter landed
const T_OUT := 0.7           # s spreading + fading out
const CAP_H := 0.085         # cap height, of the screen height
const TOP := 0.115           # cap centre, of the screen height
const RED := Color("b3201b")

var view: View
var _last := 0

func _init() -> void:
	layer = 5                 # with the HUD (under WASTED, paper sheets, menus)
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = View.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	visible = false

## show a new area's name (after `delay` real seconds)
func show_area(name: String, delay := 0.0) -> void:
	view.word = name.to_upper()
	view.t = -delay
	_last = Time.get_ticks_usec()
	visible = true
	view.queue_redraw()

func hide_now() -> void:
	visible = false

func _process(_dt: float) -> void:
	if not visible: return
	var now := Time.get_ticks_usec()
	var rdt := minf((now - _last) / 1e6, 0.1)
	_last = now
	if OS.get_environment("BMX_AREA_AT") != "":   # tests: freeze the animation at that time
		view.t = float(OS.get_environment("BMX_AREA_AT"))
	else:
		view.t += rdt
	if view.t > view.total(): visible = false
	view.queue_redraw()


class View extends Control:
	var word := ""
	var t := 0.0
	var font: SystemFont

	func _init() -> void:
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Haettenschweiler", "Impact", "Bahnschrift", "Arial Black"])
		font.font_weight = 900
		font.multichannel_signed_distance_field = true

	func t_in() -> float:
		return T_STAGGER * maxi(word.length() - 1, 0) + T_LETTER

	func total() -> float:
		return t_in() + T_HOLD + T_OUT

	static func _back(x: float) -> float:   # ease out with a small overshoot
		var c := 1.9
		x -= 1.0
		return 1.0 + (c + 1.0) * x * x * x + c * x * x

	func _draw() -> void:
		if word == "" or t < 0.0: return
		var fs := 200
		var cap := font.get_ascent(fs) * 0.74
		var sy := size.y * CAP_H / cap
		# the same squeeze as WASTED: its letters are stretched to fill 94 % of the width at 62 % cap height
		var ww := font.get_string_size("WASTED", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var squeeze := (size.x * 0.94 / ww) / (size.y * 0.62 / cap)
		var sx := sy * squeeze
		var track := fs * 0.03                       # a hair of letter spacing
		var widths: Array[float] = []
		var w := 0.0
		for ch in word:
			var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			widths.append(cw); w += cw + track
		w -= track
		if w * sx > size.x * 0.9:                    # very long names: narrower still
			sx = size.x * 0.9 / w
		var out := clampf((t - t_in() - T_HOLD) / T_OUT, 0.0, 1.0)
		var oe := out * out * (3.0 - 2.0 * out)
		var spread := 1.0 + oe * 0.35                 # letters drift apart as they go
		var cy := size.y * TOP
		var cx := size.x * 0.5
		# "ENTERING" above, small, in the same face
		var lead_a := clampf((t - 0.15) / 0.4, 0.0, 1.0) * (1.0 - oe)
		if lead_a > 0.0:
			var lw := font.get_string_size("ENTERING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var ls := sy * 0.28
			draw_set_transform(Vector2(cx, cy - cap * sy * 0.5 - size.y * 0.022), 0.0, Vector2(ls * squeeze * 1.6, ls))
			draw_string(font, Vector2(-lw * 0.5, 0), "ENTERING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(RED, lead_a))
		# the rule under the word draws out from the middle
		var rk := clampf((t - 0.1) / 0.6, 0.0, 1.0)
		rk = 1.0 - pow(1.0 - rk, 3.0)
		var rw := w * sx * spread * 0.5 * rk
		var ry := cy + cap * sy * 0.5 + size.y * 0.012
		if rk > 0.0:
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(cx - rw, ry, rw * 2.0, maxf(2.0, size.y * 0.004)), Color(RED, 1.0 - oe))
		# the letters
		var x := -w * 0.5
		for i in word.length():
			var ch := word[i]
			var lt := clampf((t - i * T_STAGGER) / T_LETTER, 0.0, 1.0)
			var mid := x + widths[i] * 0.5
			x += widths[i] + track
			if lt <= 0.0: continue
			var e := _back(lt)
			var sc := lerpf(2.4, 1.0, e)                         # stamps down from big
			var a := clampf(lt * 2.5, 0.0, 1.0) * (1.0 - oe)
			var hot := clampf(1.0 - (lt - 0.35) / 0.5, 0.0, 1.0)  # white-hot as it lands, cools to red
			var col := RED.lerp(Color(1.0, 0.92, 0.82), hot * 0.85)
			col.a = a
			var drop := (1.0 - e) * -cap * 0.6                    # falls in from a little above
			var pos := Vector2(cx + mid * sx * spread, cy + drop * sy)
			draw_set_transform(pos, 0.0, Vector2(sx * sc, sy * sc))
			draw_string(font, Vector2(-widths[i] * 0.5, cap * 0.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_set_transform(Vector2.ZERO)
