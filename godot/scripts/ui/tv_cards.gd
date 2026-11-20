## What the old CRT TV shows before the game's name: the studio card (SMOKE DESIGN: a smoke plume in a ring, the name fading in) and the
## mature-content notice (the crashes are graphic: blood, torn-off limbs). A 4:3 picture drawn in code into a SubViewport the TV's glass
## samples (ui/crt_intro.gd; the shader draws it in these colours, `card_color`). kind 0 = studio, 1 = mature; `ct` = seconds into the card.
class_name TvCards
extends Control

const FADE := 0.5
var kind := 0
var ct := 0.0
var dur := 3.2

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if kind == 0: _studio(Rect2(Vector2.ZERO, size))
	else: _mature(Rect2(Vector2.ZERO, size))

func _alpha(d: float) -> float:
	return clampf(minf(ct / FADE, (d - ct) / FADE), 0.0, 1.0)

# ---------------------------------------------------------------- SMOKE
func _studio(r: Rect2) -> void:
	var a := _alpha(dur)
	var c := r.size * 0.5 + Vector2(0.0, -r.size.y * 0.1)
	var u := minf(r.size.x, r.size.y * 1.6) / 1600.0 * 1.4   # scale to the screen
	var ring_r := 86.0 * u * 1.35
	var ink := Color(0.93, 0.92, 0.88)
	var tt := ct
	# the ring draws itself round
	var sweep := clampf(tt / 1.1, 0.0, 1.0)
	sweep = 1.0 - pow(1.0 - sweep, 3.0)
	draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * sweep, 96, Color(ink, 0.9 * a), maxf(2.0, 3.0 * u * 1.3), true)
	# the plume: three strands rising out of one point at the bottom of the ring, swaying and thinning as they climb
	var base := c + Vector2(0.0, ring_r * 0.62)
	for s in 3:
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var steps := 46
		for i in steps + 1:
			var k := float(i) / steps
			var rise := k * ring_r * 1.55 * clampf(tt / 1.3, 0.0, 1.0)
			var sway := sin(k * 5.2 + tt * 1.25 + s * 2.1) * (6.0 + 26.0 * k) * u * 1.35 + (s - 1) * k * 20.0 * u * 1.35
			pts.append(base + Vector2(sway, -rise))
			cols.append(Color(ink, a * (1.0 - k * k) * (0.9 if s == 1 else 0.55)))
		draw_polyline_colors(pts, cols, (4.2 if s == 1 else 2.6) * u * 1.3, true)
	# soft puffs drifting up and spreading behind the strands
	for p in 9:
		var ph := fposmod(tt * 0.32 + p * 0.111, 1.0)
		var pos := base + Vector2(sin(p * 2.3 + tt * 0.8) * (10.0 + 40.0 * ph) * u * 1.3, -ph * ring_r * 1.5)
		var rad := (7.0 + 40.0 * ph) * u * 1.3
		draw_circle(pos, rad, Color(ink, a * 0.08 * (1.0 - ph) * clampf(tt / 0.8, 0.0, 1.0)))
	# the name: spaced capitals, fades in under the mark
	var f := UITheme.display_font(800, 0.0)
	var fs := int(round(74.0 * u * 1.3))
	var word := "SMOKE"
	var gap := 26.0 * u * 1.3
	var wid := 0.0
	for ch in word: wid += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap
	wid -= gap
	var x := c.x - wid * 0.5
	var y := c.y + ring_r + 112.0 * u * 1.3
	var na := clampf((tt - 0.9) / 0.9, 0.0, 1.0) * a
	for i in word.length():
		var ch := word[i]
		var la := clampf((tt - 0.9 - i * 0.07) / 0.5, 0.0, 1.0) * a
		draw_string(f, Vector2(x, y + (1.0 - la) * 12.0 * u), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, la))
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap
	# a thin rule and the line under it
	var lw := wid * 0.5 * clampf((tt - 1.3) / 0.8, 0.0, 1.0)
	draw_line(Vector2(c.x - lw, y + 26.0 * u * 1.3), Vector2(c.x + lw, y + 26.0 * u * 1.3), Color(ink, 0.5 * a), 1.5)
	var f2 := UITheme.display_font(500, 0.0)
	var sub := "DESIGN STUDIO"
	var fs2 := int(round(22.0 * u * 1.3))
	var w2 := f2.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	draw_string(f2, Vector2(c.x - w2 * 0.5, y + 66.0 * u * 1.3), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(ink, 0.65 * na))

# ---------------------------------------------------------------- mature content
func _mature(r: Rect2) -> void:
	var a := _alpha(dur)
	var c := r.size * 0.5
	var u := minf(r.size.x, r.size.y * 1.6) / 1600.0 * 1.4
	var red := Color(0.86, 0.12, 0.1)
	var ink := Color(0.93, 0.92, 0.88)
	# a warning triangle with a blood drop, centred above the text
	var tc := c + Vector2(0.0, -150.0 * u * 1.3)
	var h := 118.0 * u * 1.3
	var tri := PackedVector2Array([tc + Vector2(0, -h * 0.62), tc + Vector2(h * 0.7, h * 0.46), tc + Vector2(-h * 0.7, h * 0.46), tc + Vector2(0, -h * 0.62)])
	draw_polyline(tri, Color(red, a), 5.0 * u * 1.3, true)
	var d0 := tc + Vector2(0.0, h * 0.12)
	var dr := h * 0.17
	draw_colored_polygon(PackedVector2Array([d0 + Vector2(0, -h * 0.34), d0 + Vector2(dr * 0.95, -h * 0.02), d0 + Vector2(0, h * 0.2), d0 + Vector2(-dr * 0.95, -h * 0.02)]), Color(red, a))
	draw_circle(d0 + Vector2(0, h * 0.045), dr * 1.0, Color(red, a))
	# text
	var f := UITheme.display_font(800, 0.0)
	var f2 := UITheme.display_font(500, 0.0)
	var heading := "MATURE CONTENT"
	var fs := int(round(64.0 * u * 1.3))
	var hw := f.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := c.y + 20.0 * u * 1.3
	draw_string(f, Vector2(c.x - hw * 0.5, y), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, a))
	draw_line(Vector2(c.x - hw * 0.5, y + 22.0 * u * 1.3), Vector2(c.x + hw * 0.5, y + 22.0 * u * 1.3), Color(red, 0.9 * a), 3.0)
	var lines := ["Contains graphic violence and gore:", "bloody crashes and torn-off limbs.", "Player discretion is advised."]
	var fs2 := int(round(30.0 * u * 1.3))
	var yy := y + 78.0 * u * 1.3
	for i in lines.size():
		var lw := f2.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var la := clampf((ct - 0.4 - i * 0.25) / 0.5, 0.0, 1.0) * a
		draw_string(f2, Vector2(c.x - lw * 0.5, yy + i * 44.0 * u * 1.3), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(ink, (0.85 if i < 2 else 0.6) * la))
