class_name ProfileIcon
extends Control
## A rider avatar: head + shoulders on a round plate. The profile button (top right of the title menu) and the profile page's header.

var plate := Tokens.ACCENT
var ink := Tokens.INK
var badge := false   # a red dot: something to claim

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, plate)
	# shoulders: a half-ellipse cut off by the plate's lower edge, then the head above it
	var pts := PackedVector2Array()
	for i in 25:
		var a := PI + PI * i / 24.0
		pts.append(c + Vector2(cos(a) * r * 0.62, sin(a) * r * 0.42 + r * 0.80))
	var clipped := PackedVector2Array()
	for p in pts:
		var v := p - c
		if v.length() > r * 0.98: v = v.normalized() * r * 0.98   # stays inside the plate
		clipped.append(c + v)
	draw_colored_polygon(clipped, ink)
	draw_circle(c + Vector2(0, -r * 0.22), r * 0.30, ink)
	draw_arc(c, r - 0.5, 0.0, TAU, 48, Color(ink, 0.18), 1.0, true)
	if badge:
		draw_circle(c + Vector2(r * 0.78, -r * 0.78), r * 0.30, Color.WHITE)
		draw_circle(c + Vector2(r * 0.78, -r * 0.78), r * 0.22, Color("e5352b"))
