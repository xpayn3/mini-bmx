## The game's logo, the same one the old CRT TV shows (world/crt_tv.gd `_Lettering`): RUNOUT in the display face, the letters spread
## evenly across the width, white-hot at the top fading to deep red at the bottom, a short rule and the spaced tagline under it.
## `on_dark` = the TV's own colours (cream-hot to red); otherwise the page ink (no red).
## Used by the title menu (and anywhere the game's name is shown, so it reads the same everywhere).
class_name GameLogo
extends Control

const WORD := "RUNOUT"
const TAG := "D O W N H I L L    &    B M X"
var on_dark := false
var show_tag := true
var _mat: ShaderMaterial

const SHADER := """
shader_type canvas_item;
uniform vec4 top : source_color = vec4(1.0, 0.3, 0.12, 1.0);
uniform vec4 bottom : source_color = vec4(0.62, 0.03, 0.03, 1.0);
uniform float y0 = 0.0;
uniform float h = 100.0;
varying float vy;
void vertex() { vy = VERTEX.y; }
void fragment() {
	float k = smoothstep(0.1, 0.9, (vy - y0) / h);
	COLOR.rgb = mix(top.rgb, bottom.rgb, k);
}
"""

func _init() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SHADER

func _draw() -> void:
	var f := UITheme.display_font(700)
	var fs := int(size.y * (0.78 if show_tag else 0.95))
	var cap := fs * 0.70   # Barlow Condensed's cap height (em): placed by it, not by the font's ascent
	var area := size.y * (0.80 if show_tag else 1.0)   # the tag + rule take the bottom
	var base := (area + cap) * 0.5
	var gap := size.x / WORD.length()
	if on_dark:
		_mat.set_shader_parameter("top", Color(1.0, 0.82, 0.74)); _mat.set_shader_parameter("bottom", Color(0.85, 0.06, 0.04))
	else:
		_mat.set_shader_parameter("top", Tokens.INK); _mat.set_shader_parameter("bottom", Tokens.INK)   # on the light page: the page ink, not red
	_mat.set_shader_parameter("y0", base - cap)
	_mat.set_shader_parameter("h", cap)
	material = _mat
	for i in WORD.length():
		var ch := WORD[i]
		var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(gap * (i + 0.5) - w * 0.5, base), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if show_tag:
		var tf := UITheme.display_font(600)
		var tfs := int(size.y * 0.15)
		var tw := tf.get_string_size(TAG, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var ink := Color(1, 1, 1, 0.85) if on_dark else Tokens.INK_SOFT
		var ry := size.y - tfs - 8.0
		draw_rect(Rect2(size.x * 0.5 - 45.0, ry, 90.0, 3.0), Color(1, 1, 1, 0.8) if on_dark else Tokens.ACCENT)
		draw_string(tf, Vector2((size.x - tw) * 0.5, size.y - 2.0), TAG, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, ink)
