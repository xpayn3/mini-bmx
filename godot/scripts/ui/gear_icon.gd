class_name GearIcon
extends Control
## A settings cog drawn in code (teeth round a ring with a hole), centred in the control, in the ink colour.

var color := Tokens.INK
var teeth := 8

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var r_out := r            # tooth tips
	var r_body := r * 0.72    # the ring's outside
	var r_hole := r * 0.32    # the hole (left empty, so it shows the button's own fill in every state)
	draw_arc(c, (r_body + r_hole) * 0.5, 0.0, TAU, 48, color, r_body - r_hole, true)
	for i in teeth:   # each tooth: a trapezoid, wider at the root
		var a := TAU * float(i) / float(teeth) - PI * 0.5
		var d := Vector2(cos(a), sin(a))
		var s := Vector2(-d.y, d.x)
		var root := r * 0.2; var tip := r * 0.14
		draw_colored_polygon(PackedVector2Array([
			c + d * (r_body - r * 0.06) - s * root, c + d * r_out - s * tip,
			c + d * r_out + s * tip, c + d * (r_body - r * 0.06) + s * root]), color)
