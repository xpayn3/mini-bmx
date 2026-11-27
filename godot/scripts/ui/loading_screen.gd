extends CanvasLayer
## The level's loading screen (main._race): the sky of the picked hour over mountain ridges sliding past
## (shaders/loading_screen.gdshader), the place and its trail's character, a ride tip and a progress bar.
## main drives it: await cover(), step(label, 0..1) / place(name) while it builds, await filled(), leave().

const TIPS_KEYS := [
	"HOLD SPACE INTO A LIP, LET GO AT THE EDGE TO POP",
	"HOLD ↓ WHILE ROLLING TO MANUAL",
	"CTRL IS THE FRONT BRAKE, ALT THE REAR",
	"HOLD ↓ INTO A LIP FOR A BACKFLIP",
	"PUMP THE ROLLERS: PRESS GOING OVER THE TOP, LET GO IN THE DIP",
	"PRESS I FOR THE INSTANT REPLAY",
]
const TIPS_PAD := [
	"PULL THE RIGHT STICK BACK, SNAP IT FORWARD AT THE LIP TO POP",
	"A QUICK PULL ON THE RIGHT STICK LIFTS A MANUAL",
	"HOLD THE RIGHT STICK BACK INTO A LIP FOR A BACKFLIP",
	"THROW THE RIGHT STICK WITH THE STEER FOR A CORNER WHIP",
	"PUMP THE ROLLERS: PRESS GOING OVER THE TOP, LET GO IN THE DIP",
	"PRESS THE LEFT STICK IN FOR THE INSTANT REPLAY",
]
const TIP_SECS := 3.2
const METERS := [["jumps", "JUMPS"], ["twist", "BENDS"], ["rolling", "ROLLING"], ["grade", "STEEPNESS"]]
const SEGS := 14

var root := Control.new()
var _bg := ColorRect.new()
var _fg: Face
var _mat := ShaderMaterial.new()
var _t := 0.0
var _last_us := 0
var _target := 0.02
var _shown := 0.0
var _label := "PACKING THE VAN"
var _place := ""
var _place_t := 0.0
var _alpha := 0.0          # cover() fades it in
var _leaving := -1.0
var _tips: Array = []
var _tip0 := 0
var _seed := 0
var _style := {}
var _bike := ""
var _hour := 19.3


func _init() -> void:
	layer = 55   # over the menus and the HUD


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_seed = GameState.seed
	_style = RouteStyle.snapshot()
	_bike = String(GameState.BIKES[GameState.bike_id].label).to_upper()
	_hour = LightSettings.get_value("time")
	_tips = TIPS_PAD if Settings.pad_active else TIPS_KEYS
	_tip0 = randi() % _tips.size()
	var biome := roundi(float(_style.get("biome", 0.0)))
	_place = String(RouteStyle.BIOMES[biome][0]) if biome > 0 else "THE DESCENT"
	if GameState.level != "": _place = GameState.level.get_file().get_basename().replace("_", " ").to_upper()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.modulate.a = 1.0
	add_child(root)
	_mat.shader = preload("res://shaders/loading_screen.gdshader")
	_mat.set_shader_parameter("seed", float(_seed % 997))
	_sky(_hour)
	_bg.material = _mat
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bg)
	_fg = Face.new()
	_fg.s = self
	_fg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fg)
	_last_us = Time.get_ticks_usec()
	_apply()
	if Env.s("BMX_LOAD_SHOTS") != "": _shots(Env.s("BMX_LOAD_SHOTS"))


## tests (BMX_LOAD_SHOTS=dir/prefix): a frame every 0.5 s while the screen is up, through its way out
func _shots(prefix: String) -> void:
	var i := 0
	while is_inside_tree():
		await get_tree().create_timer(0.5 if _leaving < 0.0 else 0.18, true, false, true).timeout
		await RenderingServer.frame_post_draw
		var path := "%s_%02d.png" % [prefix, i]
		get_viewport().get_texture().get_image().save_png(path)
		print("LOADSHOT %s at=%d ms frames=%d progress=%.2f '%s'" % [path.get_file(), Time.get_ticks_msec(), Engine.get_frames_drawn(), _shown, _label])
		i += 1


## the backdrop's colours for the hour: night, dawn / dusk, golden, day (blended by the sun's height)
func _sky(h: float) -> void:
	var el := Game.sun_elev_deg(h)
	var night := [Color("050814"), Color("1b2a4d"), Color("1a2442"), Color("020308"), Color("dfe8ff")]
	var dusk := [Color("1c1d4a"), Color("f0705a"), Color("7a3f63"), Color("0d0a18"), Color("ffb070")]
	var gold := [Color("23386a"), Color("ffa54a"), Color("a8584a"), Color("150d12"), Color("ffe2a0")]
	var day := [Color("2f6fc4"), Color("bfe0f2"), Color("6f93ad"), Color("0f2224"), Color("fff6d8")]
	var a: Array = night
	var b: Array = dusk
	var k := smoothstep(-10.0, 0.0, el)
	if el > 0.0:
		a = dusk; b = gold; k = smoothstep(0.0, 9.0, el)
	if el > 9.0:
		a = gold; b = day; k = smoothstep(12.0, 32.0, el)
	var names := ["sky_top", "sky_low", "ridge_far", "ridge_near", "sun_col"]
	for i in names.size():
		_mat.set_shader_parameter(names[i], (a[i] as Color).lerp(b[i], k))
	_mat.set_shader_parameter("stars", 1.0 - smoothstep(-8.0, 2.0, el))
	_mat.set_shader_parameter("sun_pos", Vector2(0.72, lerpf(0.5, 0.17, clampf(el / 60.0, 0.0, 1.0))) if el > -3.0 else Vector2(0.78, 0.2))


## fade in over whatever is on screen; returns once it covers it
func cover() -> void:
	while _alpha < 1.0:
		await get_tree().process_frame
	await get_tree().process_frame


func step(label: String, progress: float) -> void:
	_label = label
	_target = maxf(_target, progress)


func place(name: String) -> void:
	var n := name.to_upper()
	if n == "" or n == _place: return
	_place = n
	_place_t = _t


## returns once the bar has visibly reached the end
func filled() -> void:
	_target = 1.0
	while _shown < 0.995:
		await get_tree().process_frame
	await get_tree().create_timer(0.25, true, false, true).timeout


## sweep the cover away and free it
func leave() -> void:
	_leaving = 0.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_us) / 1e6, 1.0 / 30.0)   # real time; a build hitch doesn't jump the picture
	_last_us = now
	_t += dt
	_alpha = minf(1.0, _alpha + dt / 0.28)
	# the bar eases to where the build is, and creeps a little ahead so it never stands still
	var goal := _target if _target >= 1.0 else minf(_target + 0.03, 0.99)
	var rate := 5.0 if _target >= 1.0 or _shown < _target else 0.35
	_shown += (goal - _shown) * (1.0 - exp(-rate * dt))
	if _leaving >= 0.0:
		_leaving += dt / 0.55
		if _leaving >= 1.0:
			queue_free()
			return
	_apply()


func _apply() -> void:
	var sz := root.size
	_mat.set_shader_parameter("t", _t)
	_mat.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	var out := clampf(_leaving, 0.0, 1.0)
	_mat.set_shader_parameter("reveal", 1.0 - out * out * (3.0 - 2.0 * out))
	_bg.modulate.a = 1.0
	root.modulate.a = smoothstep(0.0, 1.0, _alpha)
	_fg.modulate.a = clampf(1.0 - out * 3.0, 0.0, 1.0)
	_fg.position.x = -out * 140.0
	_fg.queue_redraw()


## all the type and the bar, drawn in one go
class Face extends Control:
	var s

	func _txt(f: Font, at: Vector2, text: String, size: int, col: Color) -> float:
		draw_string(f, at + Vector2(0, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.35 * col.a))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	## a bar leaning like the type
	func _slab(x: float, y: float, w: float, h: float, col: Color) -> void:
		var l := h * 0.28
		draw_colored_polygon(PackedVector2Array([Vector2(x + l, y), Vector2(x + w + l, y), Vector2(x + w, y + h), Vector2(x, y + h)]), col)

	func _in(delay: float) -> float:   # 0..1 slide-in of a line
		var k := clampf((s._t - delay) / 0.5, 0.0, 1.0)
		return 1.0 - pow(1.0 - k, 3.0)

	func _draw() -> void:
		var sz := size
		var m := 84.0
		var black := UITheme.display_font(900, Tokens.SLANT_TITLE)
		var bold := UITheme.display_font(700, Tokens.SLANT)
		var ui := UITheme.font(false)
		var yellow := Tokens.ACCENT
		var white := Color.WHITE
		# header: what is loading, then the place stamped in
		var k := _in(0.05)
		var y := 128.0
		_slab(m - (1.0 - k) * 60.0, y - 22.0, 46.0, 22.0, Color(yellow, k))
		_txt(bold, Vector2(m + 66.0 - (1.0 - k) * 60.0, y - 2.0), "NOW LOADING" if s._shown < 0.995 else "READY", 26, Color(white, k))
		var pk := clampf((s._t - maxf(s._place_t, 0.12)) / 0.45, 0.0, 1.0)
		var pe := 1.0 - pow(1.0 - pk, 3.0)
		var size_p := 132
		var wide := black.get_string_size(s._place, HORIZONTAL_ALIGNMENT_LEFT, -1, size_p).x
		if wide > sz.x - m * 2.0: size_p = int(size_p * (sz.x - m * 2.0) / wide)
		_txt(black, Vector2(m - 6.0 - (1.0 - pe) * 90.0, y + 128.0), s._place, size_p, Color(white, pe))
		k = _in(0.28)
		var sub := "WORLD %d" % s._seed if GameState.level == "" else "LEVEL"
		sub += "   ·   %s   ·   %02d:%02d" % [s._bike, int(s._hour), int(fposmod(s._hour, 1.0) * 60.0)]
		_txt(bold, Vector2(m - (1.0 - k) * 60.0, y + 178.0), sub, 30, Color(yellow, k))
		# the trail's character, a meter per slider
		if GameState.level == "":
			for i in METERS.size():
				var key: String = METERS[i][0]
				k = _in(0.42 + i * 0.09)
				var yy := y + 244.0 + i * 38.0
				var x := m - (1.0 - k) * 50.0
				_txt(bold, Vector2(x, yy + 16.0), METERS[i][1], 21, Color(white, 0.9 * k))
				var lim: Array = RouteStyle.LIMITS[key]
				var v := clampf((float(s._style[key]) - float(lim[0])) / (float(lim[1]) - float(lim[0])), 0.0, 1.0)
				var lit := v * SEGS * _in(0.6 + i * 0.1)
				for j in SEGS:
					var on := clampf(lit - j, 0.0, 1.0)
					_slab(x + 150.0 + j * 17.0, yy, 11.0, 17.0, Color(white, 0.16 * k).lerp(Color(yellow, k), on))
		# the tip, changing every few seconds
		var n: int = s._tips.size()
		var ti := int(s._t / TIP_SECS)
		var frac: float = s._t / TIP_SECS - ti
		var ta := clampf(minf(frac, 1.0 - frac) * TIP_SECS / 0.3, 0.0, 1.0)
		var tip_y := sz.y - 158.0
		var tw := _txt(bold, Vector2(m, tip_y), "TIP", 20, yellow)
		_txt(ui, Vector2(m + tw + 18.0 + (1.0 - ta) * 14.0, tip_y), s._tips[(s._tip0 + ti) % n], 20, Color(white, ta))
		# the bar: slanted blocks, the lit edge pulsing; the percentage in the big numbers
		var punch := UITheme.punch_font()
		var pct := "%d%%" % int(floorf(s._shown * 100.0 + 0.5))
		var pw := punch.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 92).x
		_txt(punch, Vector2(sz.x - m - pw, sz.y - 66.0), pct, 92, white)
		var bx := m
		var bw := sz.x - m * 2.0 - 250.0
		var count := 48
		var cw := bw / count
		var by := sz.y - 96.0
		var head: float = s._shown * count
		for j in count:
			var on := clampf(head - j, 0.0, 1.0)
			var col := Color(white, 0.16).lerp(yellow, on)
			var near := clampf(1.0 - absf(head - j - 0.5) / 2.5, 0.0, 1.0)
			col = col.lerp(white, near * on * (0.55 + 0.45 * sin(s._t * 9.0)))
			var flow := pow(maxf(0.0, sin(j * 0.28 - s._t * 5.0)), 8.0) * on
			col = col.lerp(white, flow * 0.5)
			_slab(bx + j * cw, by, cw - 4.0, 30.0, col)
		var dots := ".".repeat(int(s._t * 3.0) % 4) if s._shown < 0.995 else ""
		_txt(bold, Vector2(bx, by + 62.0), s._label + dots, 24, Color(white, 0.92))
