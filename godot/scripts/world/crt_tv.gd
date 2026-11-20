## The old CRT TV (assets/tv/tv.fbx, ~38 cm wide, its origin on the floor under it, the glass facing +Z) showing the
## RUNOUT lettering through live static (drawn once with the display font and baked, `_text_texture`).
## Used by the boot intro (ui/crt_intro.gd: a dark room, it switches on, the camera dolly-zooms in) and
## set on the ground beside the rider at the start of every world (Game.place_start_tv), where it switches on too.
## power_on() / power_off() / glitch() drive shaders/crt_screen.gdshader; a small light in front of the glass glows
## with the picture. Sound: the user's recording (assets/audio/tv_static.mp3, static + channel changes) with its
## near-silent stretches thrown away: only its four loud static bursts (STATIC_CUTS) are used, chopped into short
## random slices that overlap on several players (a dense hiss that never repeats); tears / power on / off play a
## louder slice on top. The hiss follows the picture (brightness + snow).
class_name CrtTv
extends Node3D

const SIZE := Vector3(0.379, 0.376, 0.559)   # model bounds, m
const GLASS := Vector3(0.0, 0.22, 0.21)      # middle of the glass, model space
const GLASS_H := 0.245                       # glass height, m

const LED_AT := Vector3(0.135, 0.045, 0.214)   # power LED on the front panel, model space

var mat: ShaderMaterial
var led: MeshInstance3D
var led_mat: StandardMaterial3D
var light: OmniLight3D
var light_energy := 1.2    # the glow light at full picture
var light_range := 3.0
var level := 0.0           # how bright the screen is now (0 off .. ~1.5 power flash): drives the light
var blips := true          # little random glitches while on
var positional := true     # world TV: 3D sound; the intro's TV (its own world) plays it flat
var sound_db := 0.0        # overall loudness of its hiss
var silent := false        # no sound at all (the intro's still frame)

# the loud parts of tv_static.mp3 (s): everything between them is near silence and is never played
const STATIC_CUTS := [Vector2(2.52, 2.98), Vector2(5.02, 5.46), Vector2(8.18, 8.70), Vector2(10.0, 11.2)]
const BED_LAYERS := 6
const BED_DB := -2.0       # each bed slice (3-5 play at once)
const BURST_DB := 7.0      # tears, power on / off
var _players: Array = []   # [player, t, len, gain] per voice; the last one is the burst voice
var _next_slice := 0.0
var _hiss := 0.0           # bed loudness now 0..1
static var mute_world := false   # the boot intro is playing: the world's TVs keep quiet

var _on_t := -1.0          # seconds since power_on (-1 = off)
var _on_delay := 0.0
var _off_t := -1.0         # seconds since power_off
var _glitch := 0.0
var _glitch_snow := 0.0
var _next_blip := 3.0
var _rng := RandomNumberGenerator.new()

const ASSETS := ["res://assets/tv/tv.fbx", "res://assets/tv/tv_albedo.jpg", "res://assets/tv/tv_normal.png", "res://assets/tv/tv_orm.png",
	"res://shaders/crt_screen.gdshader"]
static var _assets_ok := -1

## every file the TV needs is there and loads (a missing / half-imported asset would otherwise leave a broken TV or a full-screen
## noise picture): callers that cannot load it simply go without the TV
static func assets_ok() -> bool:
	if _assets_ok >= 0: return _assets_ok == 1
	var ok := true
	for p in ASSETS:
		if not ResourceLoader.exists(p) or load(p) == null:
			ok = false
			push_warning("CrtTv: cannot load " + p + ", the TV is left out")
	if ok:
		var m: Node = (load(ASSETS[0]) as PackedScene).instantiate()
		ok = m != null and not m.find_children("*", "MeshInstance3D", true, false).is_empty()
		if m: m.free()
	_assets_ok = 1 if ok else 0
	return ok

func _init() -> void:
	var model: Node3D = load("res://assets/tv/tv.fbx").instantiate()
	model.scale = Vector3.ONE * 0.01
	add_child(model)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/crt_screen.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/tv/tv_albedo.jpg"))
	mat.set_shader_parameter("normal_tex", load("res://assets/tv/tv_normal.png"))
	mat.set_shader_parameter("orm_tex", load("res://assets/tv/tv_orm.png"))
	mat.set_shader_parameter("text_tex", _text_texture())
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	light = OmniLight3D.new()
	light.position = GLASS + Vector3(0, 0, 0.12)
	light.light_color = Color(1.0, 0.52, 0.42)   # the card is mostly warm red / sand
	light.shadow_enabled = true
	light.light_specular = 0.0   # no hot spot reflected in its own glass
	light.light_energy = 0.0
	light.omni_attenuation = 1.6
	add_child(light)
	# power LED on the front panel: dim red on standby, blinks while warming up, green when on
	led = MeshInstance3D.new()
	var lm := SphereMesh.new(); lm.radius = 0.0028; lm.height = 0.0036; lm.radial_segments = 12; lm.rings = 6
	led.mesh = lm
	led_mat = StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.05, 0.0, 0.0)
	led_mat.emission_enabled = true
	led_mat.roughness = 0.2
	led.material_override = led_mat
	led.position = LED_AT
	add_child(led)
	_rng.randomize()
	_apply(0, 1, 0, 0, 0, 0, 0, 0)

func _ready() -> void:
	if not silent: _build_sound()

## switch on after `delay` s: a white line, it opens up, the picture rolls in out of the snow and settles
## already on and settled (no switch-on), for a still picture
func settle_on() -> void:
	_on_delay = 0.0; _on_t = 5.0; _off_t = -1.0; _powered_sound = true; blips = false

func power_on(delay := 0.0) -> void:
	_on_delay = delay; _on_t = 0.0; _off_t = -1.0
	_powered_sound = false

## off: the picture cuts out at once (a burst of static with it), the LED goes back to standby red
func power_off() -> void:
	if _on_t >= 0.0:
		_off_t = 0.0
		_burst(0.22, 0.8)

## a hard tear + snow burst for `secs`
func glitch(secs := 0.3, amount := 1.0) -> void:
	_glitch = maxf(_glitch, amount)
	_glitch_snow = maxf(_glitch_snow, 0.45 * amount)
	_burst(secs + 0.12, clampf(amount, 0.3, 1.0))
	get_tree().create_timer(secs, true, false, true).timeout.connect(func(): _glitch = 0.0; _glitch_snow = 0.0)

func is_on() -> bool:
	return _on_t >= 0.0 and _off_t < 0.0

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05) / maxf(Engine.time_scale, 0.001)   # real time (photo mode / slow motion freeze nothing here)
	dt = minf(dt, 0.05)
	_sound(dt)
	if _on_t < 0.0:
		_led(0.0)
		return
	if _on_delay > 0.0:
		_on_delay -= dt
		return
	if not _powered_sound:   # the click-on: a burst with the white line
		_powered_sound = true
		_burst(0.5, 1.0)
	_on_t += dt
	var a := _on_t
	var vopen := 0.006 if a < 0.07 else lerpf(0.006, 1.0, _ease_out_back(clampf((a - 0.07) / 0.3, 0.0, 1.0)))
	var flash := 1.2 * exp(-a * 7.0)
	var bright := smoothstep(0.1, 0.8, a)
	var snow := 0.55 * exp(-a * 1.6) + 0.035 + _glitch_snow
	var roll := 0.5 * pow(1.0 - clampf((a - 0.15) / 1.3, 0.0, 1.0), 2.0)
	var hopen := 1.0
	var after := 0.0
	var gl := _glitch
	if blips and _off_t < 0.0 and a > 2.0:
		_next_blip -= dt
		if _next_blip <= 0.0:
			_next_blip = _rng.randf_range(1.6, 4.5)
			glitch(_rng.randf_range(0.05, 0.14), _rng.randf_range(0.25, 0.6))
	if _off_t >= 0.0:   # switched off: the picture just goes (no squeeze to a line / dot)
		_off_t = -1.0
		_on_t = -1.0
		vopen = 0.0; flash = 0.0; bright = 0.0; snow = 0.0; gl = 0.0; roll = 0.0
	_apply(vopen, hopen, bright, flash, snow, gl, roll, after)

func _apply(vopen: float, hopen: float, bright: float, flash: float, snow: float, gl: float, roll: float, after: float) -> void:
	mat.set_shader_parameter("vopen", vopen)
	mat.set_shader_parameter("hopen", hopen)
	mat.set_shader_parameter("bright", bright)
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("snow", snow)
	mat.set_shader_parameter("glitch", gl)
	mat.set_shader_parameter("roll", roll)
	mat.set_shader_parameter("afterglow", after)
	_led(bright)
	_hiss = clampf(bright * hopen * (0.55 + snow * 0.9) + flash * vopen * 0.6, 0.0, 1.0)
	level = bright * 0.6 * hopen + flash * 1.4 * vopen + after * 0.15 + snow * bright * 0.3
	if light:
		var flicker := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.031) * sin(Time.get_ticks_msec() * 0.017)
		light.light_energy = light_energy * level * flicker
		light.omni_range = light_range
		light.visible = level > 0.002
		light.light_color = Color(1.0, 0.52, 0.42).lerp(Color(0.8, 0.88, 1.0), clampf(flash + snow, 0.0, 1.0))

var _powered_sound := false

func _build_sound() -> void:
	var stream = load("res://assets/audio/tv_static.mp3")
	if stream == null: return
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in BED_LAYERS + 1:
		var p: Node
		if positional:
			var p3 := AudioStreamPlayer3D.new()
			p3.unit_size = 2.5
			p3.max_distance = 40.0
			p3.position = GLASS
			p = p3
		else:
			p = AudioStreamPlayer.new()
		p.set("stream", stream)
		p.set("bus", bus)
		p.set("volume_db", -80.0)
		add_child(p)
		_players.append([p, 0.0, 0.0, 0.0])

## a slice of one of the loud parts on voice i: `len` s with soft ends, at `gain` (0..1)
func _slice(i: int, len: float, gain: float) -> void:
	var v: Array = _players[i]
	var cut: Vector2 = STATIC_CUTS[_rng.randi() % STATIC_CUTS.size()]
	len = minf(len, cut.y - cut.x)
	var from := _rng.randf_range(cut.x, cut.y - len)
	v[0].call("play", from)
	v[0].set("pitch_scale", _rng.randf_range(0.9, 1.12))
	v[1] = 0.0; v[2] = len; v[3] = gain

func _burst(len: float, gain: float) -> void:
	if _players.is_empty() or not is_inside_tree(): return
	_slice(_players.size() - 1, len, gain)

## the bed: a new short slice every 0.07-0.16 s on the freest bed voice, so 3-5 always overlap
func _sound(dt: float) -> void:
	if _players.is_empty(): return
	var on := _on_t >= 0.0 and _on_delay <= 0.0
	if on and _hiss > 0.02:
		_next_slice -= dt
		if _next_slice <= 0.0:
			_next_slice = _rng.randf_range(0.07, 0.16)
			var best := 0
			for i in BED_LAYERS:
				if _players[i][1] >= _players[i][2]: best = i; break
				if _players[i][2] - _players[i][1] < _players[best][2] - _players[best][1]: best = i
			_slice(best, _rng.randf_range(0.3, 0.6), 1.0)
	for i in _players.size():
		var v: Array = _players[i]
		v[1] += dt
		var t: float = v[1]
		var len: float = v[2]
		var env := 0.0
		if t < len:
			env = minf(1.0, minf(t / 0.06, (len - t) / 0.08))   # soft in / out: the slices blend into one hiss
		var is_burst := i == _players.size() - 1
		var g: float = env * v[3] * (1.0 if is_burst else _hiss) * (0.0 if positional and mute_world else 1.0)
		var base := (BURST_DB if is_burst else BED_DB) + sound_db
		v[0].set("volume_db", base + linear_to_db(g) if g > 0.001 else -80.0)
		if t >= len and v[0].get("playing"): v[0].call("stop")

func _led(bright: float) -> void:
	if led_mat == null: return
	var on := _on_t >= 0.0 and _off_t < 0.0
	var warming := on and (_on_delay > 0.0 or _on_t < 1.2)
	var c := Color(1.0, 0.06, 0.03)
	var e := 1.6
	if on and not warming:
		c = Color(0.25, 1.0, 0.3); e = 2.2
	elif warming:
		var blink := fmod(Time.get_ticks_msec() * 0.001, 0.32) < 0.16
		c = Color(1.0, 0.55, 0.05) if blink else Color(1.0, 0.06, 0.03)
		e = 2.6 if blink else 0.6
	led_mat.emission = c
	led_mat.emission_energy_multiplier = e
	led_mat.albedo_color = c * 0.3

## RUNOUT + tagline, white on black, drawn once in an off-screen viewport and baked with mipmaps (shared by all TVs)
static var _text: Texture2D
static var _waiting: Array = []   # TVs made while the lettering bakes get the baked texture too
func _text_texture() -> Texture2D:
	if _text is ImageTexture: return _text
	_waiting.append(mat)
	if _text: return _text
	var vp := SubViewport.new()
	vp.size = Vector2i(1024, 300)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lay := _Lettering.new()
	lay.size = Vector2(1024, 300)
	vp.add_child(lay)
	add_child(vp)
	_text = vp.get_texture()
	_bake.call_deferred(vp)
	return _text

func _bake(vp: SubViewport) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_text = tex
	for m in _waiting:
		if is_instance_valid(m): (m as ShaderMaterial).set_shader_parameter("text_tex", tex)
	_waiting.clear()
	vp.queue_free()

class _Lettering extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		var f := UITheme.display_font(700)
		var word := "RUNOUT"
		var fs := 250
		var asc := f.get_ascent(fs)
		var gap := (size.x - 40.0) / word.length()
		for i in word.length():
			var ch := word[i]
			var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(20.0 + gap * (i + 0.5) - w * 0.5, asc * 0.86), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var tag := "D O W N H I L L    &    B M X"
		var tf := UITheme.display_font(600)
		var tw := tf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_rect(Rect2(size.x * 0.5 - 90.0, 252.0, 180.0, 3.0), Color(1, 1, 1, 0.8))
		draw_string(tf, Vector2((size.x - tw) * 0.5, 290.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.85))

static func _ease_out_back(x: float) -> float:
	var c1 := 1.4
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
