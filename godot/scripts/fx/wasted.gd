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
const T_TEXT := 1.5         # s (real) the letters stay up (they show at once), then fade
const T_TEXT_FADE := 0.4    # s (real) the letters take to fade out
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
# rider + bike silhouette: a second camera renders only them (flat, unlit) while WASTED is up, and the
# word is cut out there, so the falling rider and the bike stay in front of the letters
const MASK_LAYER := 1 << 19
var mask_vp: SubViewport
var mask_cam: Camera3D
var _masked: Array = []       # GeometryInstance3Ds given MASK_LAYER (taken off again at the end)

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
	var wm := ShaderMaterial.new()
	var wsh := Shader.new()
	wsh.code = """
shader_type canvas_item;
uniform sampler2D mask : filter_linear;
void fragment() { COLOR.a *= 1.0 - texture(mask, SCREEN_UV).a; }
"""
	wm.shader = wsh
	title.material = wm
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
	_mask_on()

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
	_mask_off()

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
	var tk := (1.0 - clampf((t - T_TEXT) / T_TEXT_FADE, 0.0, 1.0)) * (1.0 - fade)   # on at once, off after T_TEXT
	_show(k, blur, tk)
	_mask_follow()
	if fading and fade >= 1.0:
		_set_speed(1.0)
		active = false
		visible = false
		_mask_off()

func _show(k: float, blur: float, tk: float) -> void:
	var m := rect.material as ShaderMaterial
	m.set_shader_parameter("k", k)
	m.set_shader_parameter("blur", blur)
	# letters: full size at once
	title.zoom = 1.0
	title.modulate.a = tk
	title.queue_redraw()
	sub.modulate.a = tk

func _mask_on() -> void:
	if game == null or game.cam == null: return
	if mask_vp == null:
		mask_vp = SubViewport.new()
		mask_vp.transparent_bg = true
		mask_vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
		mask_vp.msaa_3d = Viewport.MSAA_DISABLED
		mask_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		mask_vp.use_taa = false
		mask_vp.positional_shadow_atlas_size = 0
		mask_cam = Camera3D.new()
		mask_cam.cull_mask = MASK_LAYER
		var env := Environment.new()   # plain: no sky, fog, GI or glow to pay for
		env.background_mode = Environment.BG_CLEAR_COLOR
		mask_cam.environment = env
		mask_vp.add_child(mask_cam)
		add_child(mask_vp)
		(title.material as ShaderMaterial).set_shader_parameter("mask", mask_vp.get_texture())
	mask_vp.size = get_tree().root.size
	mask_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mask_cam.current = true
	_mask_off_layers()
	for root in [game.rider, game.rig]:
		if root == null: continue
		for n in root.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if gi.layers & MASK_LAYER == 0:
				gi.layers |= MASK_LAYER
				_masked.append(gi)
	_mask_follow()

func _mask_follow() -> void:
	if mask_vp == null or game == null: return
	var c: Camera3D = game.cam
	mask_cam.global_transform = c.global_transform
	mask_cam.fov = c.fov; mask_cam.near = c.near; mask_cam.far = c.far
	mask_cam.keep_aspect = c.keep_aspect
	mask_cam.h_offset = c.h_offset; mask_cam.v_offset = c.v_offset

func _mask_off() -> void:
	if mask_vp != null: mask_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mask_off_layers()

func _mask_off_layers() -> void:
	for gi in _masked:
		if is_instance_valid(gi): gi.layers &= ~MASK_LAYER
	_masked.clear()

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
