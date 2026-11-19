class_name TimeIcon
extends Control
## A little landscape picture for a time of day: sky gradient, sun or moon (and stars), two hill ridges.
## The ride setup's time-of-day cards use it. `hour` = the clock (0-24); `cycle` shows day and night side by side.

var hour := 13.0
var cycle := false

## [hour, sky top, sky bottom] keyframes round the clock
const SKY := [
	[0.0,  Color("0b1230"), Color("1d2b57")],
	[5.0,  Color("0f1a40"), Color("2c3b72")],
	[6.7,  Color("5a6fa8"), Color("ffb27a")],
	[9.0,  Color("5aa0e0"), Color("bfe0f5")],
	[13.0, Color("3f8fe0"), Color("a9d6f7")],
	[16.0, Color("5a9ee0"), Color("f2dcae")],
	[19.3, Color("6b6fb0"), Color("ffb15a")],
	[20.2, Color("2c3a78"), Color("e0705a")],
	[22.0, Color("141c44"), Color("263566")],
	[24.0, Color("0b1230"), Color("1d2b57")],
]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 64)
	clip_contents = true


static func _sky(h: float) -> Array:
	h = fposmod(h, 24.0)
	for i in SKY.size() - 1:
		var a: Array = SKY[i]; var b: Array = SKY[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / (b[0] - a[0])
			return [(a[1] as Color).lerp(b[1], t), (a[2] as Color).lerp(b[2], t)]
	return [SKY[0][1], SKY[0][2]]


func _draw() -> void:
	if cycle:
		_scene(Rect2(0, 0, size.x * 0.5, size.y), 13.0)
		_scene(Rect2(size.x * 0.5, 0, size.x * 0.5, size.y), 23.5)
		return
	_scene(Rect2(Vector2.ZERO, size), hour)


func _scene(r: Rect2, h: float) -> void:
	var sk := _sky(h)
	var top: Color = sk[0]; var bot: Color = sk[1]
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([top, top, bot, bot]))
	var night := h < 5.8 or h > 21.0
	var hz := r.position.y + r.size.y * 0.66   # the horizon the hills sit on
	if night:
		# stars, then the moon
		for i in 14:
			var sx := r.position.x + fposmod(sin(i * 12.9898) * 43758.5453, 1.0) * r.size.x
			var sy := r.position.y + fposmod(sin(i * 78.233) * 12543.123, 1.0) * r.size.y * 0.55
			draw_circle(Vector2(sx, sy), 0.9, Color(1, 1, 1, 0.8))
		var mc := Vector2(r.position.x + r.size.x * 0.7, r.position.y + r.size.y * 0.28)
		draw_circle(mc, r.size.y * 0.2, Color(0.95, 0.95, 0.88, 0.18))
		draw_circle(mc, r.size.y * 0.12, Color(0.96, 0.96, 0.9))
		draw_circle(mc + Vector2(r.size.y * 0.05, -r.size.y * 0.02), r.size.y * 0.1, top.lerp(bot, 0.35))   # a bite out of it: a crescent
	else:
		# the sun runs over the sky between 6:00 and 20:00
		var u := clampf((h - 6.0) / 14.0, 0.0, 1.0)
		var sx := r.position.x + r.size.x * (0.12 + 0.76 * u)
		var sy := hz - sin(u * PI) * r.size.y * 0.62 - r.size.y * 0.02
		var warm := 1.0 - clampf(sin(u * PI) * 1.6, 0.0, 1.0)   # low sun = orange
		var col := Color(1.0, 0.97, 0.85).lerp(Color(1.0, 0.62, 0.25), warm)
		draw_circle(Vector2(sx, sy), r.size.y * 0.30, Color(col.r, col.g, col.b, 0.16))
		draw_circle(Vector2(sx, sy), r.size.y * 0.19, Color(col.r, col.g, col.b, 0.28))
		draw_circle(Vector2(sx, sy), r.size.y * 0.11, col)
	# two hill ridges, tinted by the light of the hour
	var tint := bot.lerp(Color(0.05, 0.07, 0.14), 0.62 if not night else 0.8)
	var far := bot.lerp(tint, 0.5)
	for layer in 2:
		var pts := PackedVector2Array()
		var base := hz + layer * r.size.y * 0.1
		var amp := r.size.y * (0.16 - layer * 0.05)
		var steps := 24
		for i in steps + 1:
			var fx := float(i) / steps
			var y := base - (sin(fx * 5.0 + layer * 2.1) * 0.5 + sin(fx * 11.0 + layer) * 0.25 + 0.5) * amp
			pts.append(Vector2(r.position.x + fx * r.size.x, y))
		pts.append(Vector2(r.end.x, r.end.y)); pts.append(Vector2(r.position.x, r.end.y))
		draw_colored_polygon(pts, far if layer == 0 else tint)
