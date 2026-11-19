## "WASTED": the crash moment. Time drops into slow motion (sound pitched down with it), the picture drains
## to grey with a dark vignette and a little shake of blur, and big red letters punch in once the rider
## is going down. Then time eases back to normal and the look fades out (or at once on getting up).
## Everything runs on real time (Engine.time_scale slows the game's own delta).
class_name Wasted
extends CanvasLayer

const SLOW := 0.22          # time scale at the bottom of the slow-mo
const T_IN := 0.18          # s (real) to drop into slow motion
const T_HOLD := 2.4         # s (real) held slow
const T_OUT := 0.9          # s (real) back to normal speed
const T_TEXT := 0.75        # s (real) after the crash the letters punch in
const T_FADE := 5.0         # s (real) the look starts fading if the rider is still down
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;        // 0..1 how much of the effect
uniform float blur = 0.0;     // soft double-vision at the moment of impact
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, blur * 2.5).rgb;
	vec2 d = (uv - 0.5) * vec2(0.012, 0.0) * blur;
	c = mix(c, vec3(textureLod(screen_tex, uv + d, 1.0).r, c.g, textureLod(screen_tex, uv - d, 1.0).b), blur);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = vec3(l) * vec3(1.02, 0.99, 0.95);                 // grey, a touch warm
	g = clamp((g - 0.5) * 1.18 + 0.47, 0.0, 1.0);              // punchier, a bit darker
	vec2 v = uv - 0.5; v.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float vig = smoothstep(0.85, 0.25, length(v));
	g *= mix(0.45, 1.0, vig);
	COLOR = vec4(mix(c, g, k), 1.0);
}
"""

var game                     # Game (time scale is not touched in photo mode)
var active := false
var t := 0.0                 # real seconds since the crash
var fade := 0.0              # 0..1 fading out
var fading := false
var _last := 0
var rect: ColorRect
var title: WordView
var sub: Label

func _init(g) -> void:
	game = g
	layer = 6               # over the HUD: it greys out too
	process_mode = Node.PROCESS_MODE_PAUSABLE
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var sh := Shader.new(); sh.code = SHADER
	m.shader = sh
	rect.material = m
	add_child(rect)
	# the word: drawn huge and squeezed narrow (WordView), no band behind it
	title = WordView.new()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	sub = Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_left = 0; sub.anchor_right = 1; sub.anchor_top = 1; sub.anchor_bottom = 1
	sub.offset_top = -64; sub.offset_bottom = -28
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_font_override("font", UITheme.font(true))
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.92, 0.9, 0.86))
	add_child(sub)
	_show(0.0, 0.0, 0.0)

## the crash started
func start(reason: String) -> void:
	active = true
	fading = false
	fade = 0.0
	t = 0.0
	_last = Time.get_ticks_usec()
	var r := reason.strip_edges().trim_suffix("!")
	sub.text = "" if r == "" else r.to_upper()
	visible = true

## the rider got up (or the ride was reset): ease out now
func finish() -> void:
	if active and not fading:
		fading = true
		fade = 0.0

## straight back to normal (leaving the ride, respawn)
func stop() -> void:
	if active: _set_speed(1.0)
	active = false
	visible = false

func _process(_dt: float) -> void:
	if not active: return
	var now := Time.get_ticks_usec()
	var rdt := minf((now - _last) / 1e6, 0.1)   # real time; clamped (after a pause)
	_last = now
	t += rdt
	if t > T_FADE and not fading: finish()
	if fading: fade = minf(1.0, fade + rdt / 0.7)
	# time: drop fast, hold, ease back
	var sp := 1.0
	if t < T_IN: sp = lerpf(1.0, SLOW, _ease(t / T_IN))
	elif t < T_IN + T_HOLD: sp = SLOW
	else: sp = lerpf(SLOW, 1.0, _ease(minf(1.0, (t - T_IN - T_HOLD) / T_OUT)))
	if fading: sp = lerpf(sp, 1.0, fade)
	_set_speed(sp)
	# look
	var k := smoothstep(0.0, 0.6, t) * (1.0 - fade)
	var blur := clampf(1.0 - t / 0.35, 0.0, 1.0) * (1.0 - fade)
	var tk := clampf((t - T_TEXT) / 0.22, 0.0, 1.0) * (1.0 - fade)
	_show(k, blur, tk)
	if fading and fade >= 1.0:
		_set_speed(1.0)
		active = false
		visible = false

func _show(k: float, blur: float, tk: float) -> void:
	var m := rect.material as ShaderMaterial
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("blur", blur)
	# letters: punch in from bigger, settle with a tiny overshoot
	title.zoom = 1.0 + 0.25 * pow(1.0 - tk, 3.0) - 0.015 * sin(tk * PI)
	title.modulate.a = tk
	title.queue_redraw()
	sub.modulate.a = clampf(tk * 2.0 - 1.0, 0.0, 1.0)

func _set_speed(sp: float) -> void:
	if game and game.photo: return
	Engine.time_scale = sp
	AudioServer.playback_speed_scale = lerpf(0.55, 1.0, (sp - SLOW) / (1.0 - SLOW))   # sound slows / drops in pitch too

func _exit_tree() -> void:
	if active:
		Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0

static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## WASTED in caps, as big as the screen allows: the font is squeezed sideways (very condensed) so the
## letters can be ~60 % of the screen tall and still fit its width
class WordView extends Control:
	const WORD := "WASTED"
	const FILL_W := 0.94      # of the screen width
	const CAP_H := 0.62       # cap height, of the screen height
	var zoom := 1.0
	var font: SystemFont
	func _init() -> void:
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Haettenschweiler", "Impact", "Bahnschrift", "Arial Black"])
		font.font_weight = 900
		font.multichannel_signed_distance_field = true   # stays sharp scaled up this much
	func _draw() -> void:
		if modulate.a <= 0.0: return
		var fs := 200
		var w := font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cap := font.get_ascent(fs) * 0.74            # cap height ~ 0.74 of the ascent (condensed display faces)
		var sy := size.y * CAP_H / cap * zoom
		var sx := size.x * FILL_W / w * zoom
		var c := size * 0.5
		var base := Vector2(-w * 0.5, cap * 0.5)          # centred on the caps, in font units
		draw_set_transform(c, 0.0, Vector2(sx, sy))   # flat: no stroke, no shadow
		draw_string(font, base, WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("b3201b"))
		draw_set_transform(Vector2.ZERO)
