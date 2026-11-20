extends Control
## A goggle lens swatch for the ride setup's GOGGLES picks: the goggle outline (RiderGear.goggle_outline) filled with
## the lens film colour, a mirror sheen across the top and a dark frame. A clear lens (alpha < 1) shows a faint
## landscape through it. No class_name: preload("res://scripts/ui/lens_icon.gd").

var tint := Color(0.86, 0.9, 0.93, 0.35)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 40)

func _draw() -> void:
	var gw := 0.2; var gh := 0.09   # outline units (metres on the real goggles)
	var k := minf(size.x * 0.9 / gw, size.y * 0.9 / gh)
	var mid := size * 0.5
	var outer := RiderGear.goggle_outline(gw, gh, 0.0, 12)
	var inner := RiderGear.goggle_outline(gw, gh, 0.007, 12)
	var po := PackedVector2Array(); var pi := PackedVector2Array()
	for p in outer: po.append(mid + Vector2(p.x, -p.y) * k)
	for p in inner: pi.append(mid + Vector2(p.x, -p.y) * k)
	draw_colored_polygon(po, Color("23262c"))   # frame
	# the lens: film colour, darker at the bottom, a light streak (mirror) at the top
	var top := tint.lightened(0.35); var bot := tint.darkened(0.25)
	if tint.a < 1.0:   # clear: a pale sky over a faint hill line
		top = Color("d9ecf7"); bot = Color("eef3f0")
	var cols := PackedColorArray()
	var y0 := mid.y - gh * 0.5 * k; var y1 := mid.y + gh * 0.5 * k
	for p in pi:
		cols.append(top.lerp(bot, clampf((p.y - y0) / (y1 - y0), 0.0, 1.0)))
	draw_polygon(pi, cols)
	if tint.a < 1.0:
		draw_line(Vector2(mid.x - gw * 0.4 * k, mid.y + gh * 0.12 * k), Vector2(mid.x + gw * 0.4 * k, mid.y - gh * 0.02 * k), Color(0.55, 0.65, 0.55, 0.5), 2.0, true)
	var sheen := Color(1, 1, 1, 0.35)
	draw_line(Vector2(mid.x - gw * 0.36 * k, mid.y - gh * 0.22 * k), Vector2(mid.x - gw * 0.1 * k, mid.y - gh * 0.3 * k), sheen, maxf(2.0, k * 0.006), true)
