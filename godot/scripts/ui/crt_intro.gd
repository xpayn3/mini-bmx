## Boot intro (plain launch; the boot splash itself is plain black; ~18 s, held on black while main builds the ride): a dark room at night, moonlight through
## broken blinds, an old CRT TV (world/crt_tv.gd) on a low cabinet. From black the TV switches on to the RUNOUT
## card and the camera does a slow Vertigo dolly zoom (moves in while the lens widens, so the TV keeps its size
## and the room stretches away behind it), the picture tears once, then the TV switches off, every light with it, and out of the dark the game fades in.
## Any key / click / pad button skips. Its own 3D world in a SubViewport over everything (layer 60).
## Tests: BMX_INTRO=1 plays it even with command-line flags, BMX_INTRO_AT=secs freezes it there,
## BMX_INTRO_SHOTS=dir/prefix saves a frame every 0.5 s.
class_name CrtIntro
extends CanvasLayer

signal finished

const T_ON := 1.8        # TV switches on
const T_GLITCH := 7.0    # the first big tear (the figure in the doorway is gone after it)
const T_LOSS := 10.6     # the signal drops out: snow over everything
const T_GLITCH2 := 13.2  # second tear: for a moment the figure stands inside the room
const T_OFF := 16.5      # TV switches off
const T_FADE := 1.3      # the picture and its hiss fade out together before the TV goes off
const T_END := 16.8      # all black -> finished (no long dark grain at the end: straight into the game)
# dolly zoom: distance from the glass and the frame height kept there (start wide / far, end close / wide lens)
const D0 := 5.2
const D1 := 0.62
const H0 := 0.95
const H1 := 0.40

var root: Control
var vp: SubViewport
var cam: Camera3D
var tv: CrtTv
var moon: SpotLight3D
var moon_fill: OmniLight3D
var env: Environment
var figure: Node3D
var figure2: Node3D
var hold := false        # true: stay on black (only the standby LED) while main loads the ride behind it
var still := false       # Settings › Intro off: one still frame of it (TV on, RUNOUT) while loading, then done
const STILL_T := 12.0    # the moment of the intro the still frame shows
const STILL_HOLD := 2.2  # s it stays up after loading
var _still_left := STILL_HOLD
var _still_frames := 0
var overlay: ColorRect
var t := 0.0
var _done := false
var _skip := -1.0
var _freeze := -1.0
var _shots := ""
var _next_shot := 0.0
var _glitched := false
var _lost := false
var _glitched2 := false
var _offed := false
var _born := 0
var _tv_at := Vector3.ZERO   # world point of the middle of the glass

func _ready() -> void:
	layer = 60
	_born = Time.get_ticks_msec()
	CrtTv.mute_world = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("BMX_INTRO_AT") != "": _freeze = float(OS.get_environment("BMX_INTRO_AT"))
	if still: _freeze = STILL_T
	_shots = OS.get_environment("BMX_INTRO_SHOTS")
	if OS.get_environment("BMX_INTRO_SHOT_FROM") != "": _next_shot = float(OS.get_environment("BMX_INTRO_SHOT_FROM"))
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.positional_shadow_atlas_size = 4096
	svc.add_child(vp)
	_build_room()
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = OVERLAY
	overlay.material = sm
	root.add_child(overlay)
	if still:   # pose the room at that moment, without replaying its tears into the picture
		t = STILL_T
		_glitched = true; _lost = true; _glitched2 = true
	_update(0.0)

func _input(e: InputEvent) -> void:
	if _done or _skip >= 0.0 or t < 0.3: return
	var hit: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventMouseButton and e.pressed) \
		or (e is InputEventJoypadButton and e.pressed)
	if hit:
		_skip = 0.0
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _done: return
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.05)
	if _freeze >= 0.0:
		t = _freeze
	elif not hold:
		t += dt
	if _skip >= 0.0: _skip += dt
	if _shots != "" and (t >= _next_shot or (still and _still_frames == 12)) and t < T_END:
		_next_shot += float(OS.get_environment("BMX_INTRO_SHOT_STEP")) if OS.get_environment("BMX_INTRO_SHOT_STEP") != "" else 0.5
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%04.1f.png" % [_shots, t])
		var voices := 0
		for v in tv._players:
			if v[0].playing: voices += 1
		print("INTROSHOT %.1f static_voices=%d hiss=%.2f" % [t, voices, tv._hiss])
	# watchdog (real time): whatever went wrong, the intro never sticks over the game
	var real := (Time.get_ticks_msec() - _born) / 1000.0
	if _freeze < 0.0 and (real > 90.0 or (not hold and real > T_END + 10.0)):
		t = T_END
	if still:   # draw the frame a few times (lights, fog settle), then freeze the picture
		_still_frames += 1
		if _still_frames == 8: vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if not hold: _still_left -= dt
		if _still_left <= 0.0 or _skip >= 0.0:
			_done = true
			CrtTv.mute_world = false
			finished.emit()
		return
	_update(dt)
	if t >= T_END or _skip >= 0.35:
		_done = true
		CrtTv.mute_world = false
		finished.emit()

func _update(_dt: float) -> void:
	# TV timeline
	if t >= T_ON and not tv.is_on() and not _offed: tv.power_on()
	if t >= T_GLITCH and not _glitched:
		_glitched = true
		tv.glitch(0.42, 1.0)
	if t >= T_LOSS and not _lost:
		_lost = true
		tv.glitch(0.75, 2.0)
	if t >= T_GLITCH2 and not _glitched2:
		_glitched2 = true
		tv.glitch(0.4, 1.2)
	if t >= T_OFF and not _offed:
		_offed = true
		tv.power_off(true)   # (already faded to black and silent: no burst)
	# the figure in the doorway is only there until the tear
	figure.visible = t < T_GLITCH + 0.36
	figure2.visible = t > T_GLITCH2 + 0.05 and t < T_GLITCH2 + 0.38
	# moonlight: the eyes adjust after the TV comes on; when the TV goes off every light goes with it (pitch dark,
	# only the standby LED)
	var moon_k := smoothstep(T_ON + 0.2, T_ON + 2.6, t) * (0.0 if t >= T_OFF else 1.0)
	# the haze goes too: its temporal blend kept the TV's red glow hanging in the air for ~0.7 s after the cut
	env.volumetric_fog_enabled = t < T_OFF
	moon.light_energy = 7.0 * moon_k
	moon_fill.light_energy = 0.08 * moon_k
	# Vertigo: dolly in, lens widens so the frame height at the TV goes H0 -> H1 (the TV grows a little)
	var s := _smoother(clampf(t / (T_OFF + 0.6), 0.0, 1.0))
	var d := lerpf(D0, D1, s)
	var h := lerpf(H0, H1, s)
	var sway := Vector3(sin(t * 0.61) * 0.012, sin(t * 0.83 + 1.3) * 0.008, 0.0) * (0.4 + 0.6 * (1.0 - s))
	cam.position = _tv_at + Vector3(0.0, -0.05 + 0.04 * s, d) + sway
	cam.fov = rad_to_deg(2.0 * atan(h * 0.5 / d))
	cam.look_at(_tv_at + Vector3(0.0, 0.01, 0.0) + sway * 0.3, Vector3.UP)
	cam.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(sin(t * 0.37) * 0.6))   # a slow uneasy roll
	# fade: in from black at the start is the TV itself; out on skip / at the end
	var k := 0.0
	if _skip >= 0.0: k = clampf(_skip / 0.3, 0.0, 1.0)
	k = maxf(k, smoothstep(T_OFF - T_FADE, T_OFF, t))
	tv.sound_db = -60.0 * k   # the hiss goes down with the picture
	(overlay.material as ShaderMaterial).set_shader_parameter("black", k)
	(overlay.material as ShaderMaterial).set_shader_parameter("grain", 1.0 - k)   # the film noise goes with the fade

static func _smoother(x: float) -> float:
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

# ---------------------------------------------------------------- the room
func _build_room() -> void:
	var w := Node3D.new()
	vp.add_child(w)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.018, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.03, 0.04, 0.07)
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.014
	env.volumetric_fog_albedo = Color(0.55, 0.6, 0.7)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 24.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.82
	env.adjustment_contrast = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	cam = Camera3D.new()
	cam.near = 0.03
	cam.far = 60.0
	w.add_child(cam)
	cam.current = true

	var wall := _mat(0, Color(0.30, 0.33, 0.30))
	var floor_m := _mat(1, Color(0.30, 0.22, 0.15))
	var wood := _mat(2, Color(0.20, 0.13, 0.08))
	var black := StandardMaterial3D.new(); black.albedo_color = Color(0.0, 0.0, 0.0); black.roughness = 1.0
	# room: x -2.2..2.2, y 0..2.6, back wall z -2.5 (door + window in it), front wall z 7
	_box(w, Vector3(4.4, 0.1, 9.5), Vector3(0, -0.05, 2.25), floor_m)
	_box(w, Vector3(4.4, 0.1, 9.5), Vector3(0, 2.65, 2.25), wall)
	_box(w, Vector3(0.1, 2.6, 9.5), Vector3(-2.25, 1.3, 2.25), wall)
	_box(w, Vector3(0.1, 2.6, 9.5), Vector3(2.25, 1.3, 2.25), wall)
	_box(w, Vector3(4.4, 2.6, 0.1), Vector3(0, 1.3, 7.05), wall)
	var bz := -2.55
	# back wall pieces around the door (x -1.85..-1.0, y 0..2.05) and the window (x 0.45..1.45, y 0.95..2.05)
	_box(w, Vector3(0.35, 2.6, 0.1), Vector3(-2.025, 1.3, bz), wall)
	_box(w, Vector3(0.85, 0.55, 0.1), Vector3(-1.425, 2.325, bz), wall)
	_box(w, Vector3(1.45, 2.6, 0.1), Vector3(-0.275, 1.3, bz), wall)
	_box(w, Vector3(1.0, 0.95, 0.1), Vector3(0.95, 0.475, bz), wall)
	_box(w, Vector3(1.0, 0.55, 0.1), Vector3(0.95, 2.325, bz), wall)
	_box(w, Vector3(0.75, 2.6, 0.1), Vector3(1.825, 1.3, bz), wall)
	# skirting + window frame + sill
	_box(w, Vector3(4.4, 0.09, 0.03), Vector3(0, 0.045, bz + 0.065), wood)
	for f in [[Vector3(1.06, 0.05, 0.12), Vector3(0.95, 0.925, bz + 0.03)], [Vector3(1.06, 0.05, 0.08), Vector3(0.95, 2.075, bz)],
			[Vector3(0.05, 1.15, 0.08), Vector3(0.425, 1.5, bz)], [Vector3(0.05, 1.15, 0.08), Vector3(1.475, 1.5, bz)],
			[Vector3(1.0, 0.035, 0.05), Vector3(0.95, 1.5, bz - 0.02)], [Vector3(0.035, 1.1, 0.05), Vector3(0.95, 1.5, bz - 0.02)]]:
		_box(w, f[0], f[1], wood)
	# blinds: tilted slats, a few missing, one hanging off
	var slat := StandardMaterial3D.new(); slat.albedo_color = Color(0.55, 0.53, 0.48); slat.roughness = 0.7
	for i in 15:
		if i in [4, 9, 10]: continue
		var s := _box(w, Vector3(0.98, 0.006, 0.05), Vector3(0.95, 2.0 - i * 0.068, bz + 0.09), slat)
		s.rotation.x = deg_to_rad(38.0)
		if i == 12:
			s.rotation.z = deg_to_rad(-24.0); s.position += Vector3(0.12, -0.12, 0.0)
	# the doorway: a dark hall behind, the door half open into the room
	_box(w, Vector3(1.2, 2.3, 0.1), Vector3(-1.425, 1.15, bz - 1.4), black)
	_box(w, Vector3(0.1, 2.3, 1.4), Vector3(-2.0, 1.15, bz - 0.7), black)
	_box(w, Vector3(0.1, 2.3, 1.4), Vector3(-0.85, 1.15, bz - 0.7), black)
	var hinge := Node3D.new(); hinge.position = Vector3(-1.85, 0.0, bz + 0.04); hinge.rotation.y = deg_to_rad(-38.0); w.add_child(hinge)
	_box(hinge, Vector3(0.84, 2.03, 0.04), Vector3(0.42, 1.02, 0.0), wood)
	var knob := MeshInstance3D.new(); var km := SphereMesh.new(); km.radius = 0.025; km.height = 0.05; knob.mesh = km
	var brass := StandardMaterial3D.new(); brass.albedo_color = Color(0.6, 0.45, 0.2); brass.metallic = 1.0; brass.roughness = 0.35
	knob.material_override = brass; knob.position = Vector3(0.76, 0.98, 0.04); hinge.add_child(knob)
	# someone standing in the hall, only a silhouette (gone after the tear)
	figure = Node3D.new(); figure.position = Vector3(-1.32, 0.0, bz - 0.55); w.add_child(figure)
	var body := MeshInstance3D.new(); var cm := CapsuleMesh.new(); cm.radius = 0.2; cm.height = 1.5; body.mesh = cm
	body.position.y = 0.8; body.scale = Vector3(1.0, 1.0, 0.6); body.material_override = black; figure.add_child(body)
	var head := MeshInstance3D.new(); var hm := SphereMesh.new(); hm.radius = 0.11; hm.height = 0.24; head.mesh = hm
	head.position.y = 1.68; head.material_override = black; figure.add_child(head)
	figure2 = figure.duplicate()   # the same shape inside the room, by the door
	figure2.position = Vector3(-1.05, 0.0, bz + 1.1)
	figure2.rotation.y = deg_to_rad(25.0)
	figure2.visible = false
	w.add_child(figure2)
	# low cabinet + the TV, a rug, VHS tapes
	_box(w, Vector3(1.0, 0.5, 0.48), Vector3(0, 0.25, -1.6), wood)
	_box(w, Vector3(0.96, 0.02, 0.44), Vector3(0, 0.12, -1.6 + 0.01), _mat(2, Color(0.12, 0.08, 0.05)))
	var rug := StandardMaterial3D.new(); rug.albedo_color = Color(0.22, 0.05, 0.05); rug.roughness = 1.0
	_box(w, Vector3(2.0, 0.012, 1.5), Vector3(0.1, 0.006, -0.3), rug)
	var vhs := StandardMaterial3D.new(); vhs.albedo_color = Color(0.03, 0.03, 0.03); vhs.roughness = 0.5
	for i in 3:
		var tp := _box(w, Vector3(0.19, 0.025, 0.105), Vector3(0.33 + i * 0.01, 0.513 + i * 0.026, -1.48), vhs)
		tp.rotation.y = deg_to_rad(8.0 - i * 9.0)
	tv = CrtTv.new()
	tv.positional = false   # its own world: no listener there, play it flat
	tv.silent = still
	tv.position = Vector3(-0.08, 0.5, -1.72)
	tv.rotation.y = deg_to_rad(4.0)
	tv.light_energy = 1.1
	tv.light_range = 6.0
	tv.blips = false
	w.add_child(tv)
	_tv_at = tv.position + tv.basis * CrtTv.GLASS
	if still: tv.settle_on()
	# a moon outside, its light through the blinds into the fog
	var moon_disc := MeshInstance3D.new(); var md := SphereMesh.new(); md.radius = 0.9; md.height = 1.8; moon_disc.mesh = md
	var mm := StandardMaterial3D.new(); mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mm.albedo_color = Color(0.75, 0.82, 1.0)
	moon_disc.material_override = mm; moon_disc.position = Vector3(5.0, 5.5, -26.0); w.add_child(moon_disc)
	moon = SpotLight3D.new()
	moon.position = Vector3(2.4, 3.7, -7.5)
	w.add_child(moon)
	moon.look_at(Vector3(0.1, 0.0, 0.8), Vector3.UP)
	moon.light_color = Color(0.5, 0.62, 1.0)
	moon.spot_range = 16.0
	moon.spot_angle = 11.0
	moon.spot_attenuation = 0.4
	moon.shadow_enabled = true
	moon.shadow_blur = 0.6
	moon.light_volumetric_fog_energy = 1.4
	moon_fill = OmniLight3D.new()   # a faint cold bounce so the room's shape reads
	moon_fill.position = Vector3(0.6, 1.4, 1.5)
	moon_fill.light_color = Color(0.45, 0.55, 0.9)
	moon_fill.omni_range = 7.0
	moon_fill.light_volumetric_fog_energy = 0.0
	w.add_child(moon_fill)
	# dust in the air, lit only where light falls
	var dust := CPUParticles3D.new()
	var dq := QuadMesh.new(); dq.size = Vector2(0.0025, 0.0025)
	var dm := StandardMaterial3D.new(); dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; dm.albedo_color = Color(0.9, 0.9, 0.85)
	dm.roughness = 1.0
	dq.material = dm
	dust.mesh = dq
	dust.amount = 160
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.6, 0.6, 1.6)
	dust.position = Vector3(0.7, 1.0, -1.0)
	dust.gravity = Vector3(0, -0.004, 0)
	dust.initial_velocity_min = 0.005; dust.initial_velocity_max = 0.03
	dust.direction = Vector3(1, 0.2, 0); dust.spread = 180.0
	w.add_child(dust)

func _box(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _mat(kind: int, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _room_shader()
	m.set_shader_parameter("kind", kind)
	m.set_shader_parameter("tint", tint)
	return m

static var _rs: Shader
static func _room_shader() -> Shader:
	if _rs == null:
		_rs = Shader.new()
		_rs.code = ROOM
	return _rs

# walls: faded striped wallpaper with damp stains; floor: varnished boards; wood: grain
const ROOM := """
shader_type spatial;
uniform int kind = 0;
uniform vec3 tint : source_color = vec3(0.3);
varying vec3 wp;
varying vec3 wn;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + 1.0), f.x), f.y); }
float fbm(vec2 p) { return vn(p) * 0.5 + vn(p * 2.1) * 0.25 + vn(p * 4.3) * 0.125 + vn(p * 8.7) * 0.0625; }
void fragment() {
	vec3 c = tint; float r = 0.85;
	vec2 wall_uv = abs(wn.x) > 0.5 ? wp.zy : wp.xy;
	if (kind == 0) {
		float st = smoothstep(0.35, 0.65, sin(wall_uv.x * 3.14159 * 9.0) * 0.5 + 0.5);
		float motif = smoothstep(0.75, 0.9, vn(vec2(wall_uv.x * 18.0, wall_uv.y * 9.0)));
		c *= 0.86 + 0.1 * st + 0.06 * motif;
		float damp = fbm(wall_uv * vec2(1.3, 0.8) + 3.0);
		c *= mix(0.55, 1.0, smoothstep(0.25, 0.65, damp + wall_uv.y * 0.12));
		if (abs(wn.y) > 0.5) c = tint * mix(0.6, 0.9, fbm(wp.xz * 1.5));
	} else if (kind == 1) {
		float bw = 0.13; float board = floor(wp.x / bw);
		float off = h(vec2(board, 1.0)) * 3.0;
		float seg = floor((wp.z + off) / 1.6);
		float grain = fbm(vec2(board * 7.0 + seg * 3.0, (wp.z + off) * 1.2)) ;
		c *= 0.7 + 0.45 * grain;
		c *= 0.8 + 0.4 * h(vec2(board, seg));
		float seam = smoothstep(0.0, 0.006, fract(wp.x / bw) * bw) * smoothstep(0.0, 0.006, fract((wp.z + off) / 1.6) * 1.6);
		c *= mix(0.25, 1.0, seam);
		r = mix(0.28, 0.6, fbm(wp.xz * 3.0));
	} else {
		vec2 g = abs(wn.y) > 0.5 ? wp.xz : (abs(wn.x) > 0.5 ? wp.zy : wp.xy);
		float grain = fbm(vec2(g.x * 2.0, g.y * 40.0));
		c *= 0.75 + 0.4 * grain;
		r = 0.55;
	}
	ALBEDO = c; ROUGHNESS = r;
}
"""

# film grain, vignette, letterbox, the fade to black
const OVERLAY := """
shader_type canvas_item;
uniform float black = 0.0;
uniform float grain = 1.0;
uniform float bars = 0.085;
void fragment() {
	vec2 uv = UV;
	float g = fract(sin(dot(floor(uv * vec2(800.0, 450.0)) + fract(TIME * 7.13) * vec2(37.0, 91.0), vec2(12.9898, 78.233))) * 43758.5453);
	float vig = smoothstep(0.35, 0.95, length((uv - 0.5) * vec2(1.3, 1.05)));
	float a = vig * 0.72 * (1.0 - black);
	vec3 col = vec3(0.0);
	// grain: dark and light specks at low opacity
	col = mix(col, vec3(g), grain * 0.06 / max(a + 0.06, 0.001));
	a = max(a, 0.06 * grain * (1.0 - black));
	if (uv.y < bars || uv.y > 1.0 - bars) { col = vec3(0.0); a = 1.0; }
	col = mix(col, vec3(0.0), black); a = mix(a, 1.0, black);
	COLOR = vec4(col, a);
}
"""
