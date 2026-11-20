class_name ActionCam
## Helmet-top action camera (GoPro-sized, no branding; other models + add-ons via `gear`, see MODELS / GEAR_ROWS): curved adhesive base, quick-release buckle,
## three-finger hinge with a thumb screw, then the camera body (71 x 51 x 34 mm) with its square lens
## block, front screen, shutter button and record LED. Built in head space: origin = where the base
## touches the shell, +X = forward (the lens), +Y = up. The "Lens" child marks the lens front: the
## Helmet camera view looks out from there.
##
## Mounts (`build(kind)`): "top" = the helmet-top buckle + hinge above; every other kind is built by
## `build_arm(normal, body_at)`: the adhesive pad / clamp faces along `normal` and an arm holds the camera
## UPRIGHT (lens +X, the picture never rolls) at `body_at` -- helmet side / chin, handlebar, fork leg.
## The camera itself is always the "Body" child (Rider.break_action_cam tears it off).

## where the rider's action cam can sit (look.camMount); "none" = no camera on the helmet
const HELMET_MOUNTS := [["top", "Helmet top"], ["side", "Helmet side"], ["chin", "Chin bar"], ["none", "None"]]
## where the bike's action cam can sit (build.camera.mount); "none" = no camera on the bike
const BIKE_MOUNTS := [["none", "None"], ["bars", "Handlebar"], ["fork", "Fork leg"]]

const G := preload("res://scripts/rider/rider_geo.gd")

## the camera itself + its add-ons ("gear"): a dictionary {model, lens, housing, mic, acc}. The helmet camera keeps
## it in the rider look (GEAR_LOOK keys), the bike camera in build.camera. Shapes are procedural, after the real
## cameras (no logos). W / H / D = width (Z), height (Y), depth (X) in m; fov = the POV view's vertical FOV.
const MODELS := {
	"hero": {label = "GoPro HERO13 Black", W = 0.071, H = 0.051, D = 0.034, body = "#17181b", trim = "#3b3e44", lens = "square", screen = "front", fov = 88.0},
	"max":  {label = "GoPro MAX", W = 0.0695, H = 0.064, D = 0.025, body = "#1b1c1f", trim = "#44474d", lens = "dual", screen = "back", fov = 96.0},
	"osmo": {label = "DJI Osmo Action 5 Pro", W = 0.070, H = 0.044, D = 0.033, body = "#2b2d31", trim = "#6b6f77", lens = "round", screen = "front_big", fov = 90.0},
	"x4":   {label = "Insta360 X4", W = 0.046, H = 0.124, D = 0.038, body = "#141516", trim = "#3a3c40", lens = "dual_top", screen = "back", fov = 96.0},
	"go":   {label = "Insta360 GO 3S", W = 0.026, H = 0.054, D = 0.025, body = "#ecece6", trim = "#c9ccd1", lens = "pill", screen = "", fov = 82.0},
}
const MODEL_LIST := [["hero", "GoPro HERO13"], ["max", "GoPro MAX"], ["osmo", "DJI Osmo Action 5"], ["x4", "Insta360 X4"], ["go", "Insta360 GO 3S"]]
const LENSES := [["stock", "Stock"], ["ultra", "Max Lens Mod"], ["nd", "ND filter"], ["guard", "Clear guard"]]
const HOUSINGS := [["none", "None"], ["frame", "Frame"], ["sleeve", "Silicone sleeve"], ["dive", "Dive housing"]]
const MICS := [["none", "None"], ["mediamod", "Media Mod"], ["shotgun", "Shotgun mic"], ["deadcat", "Furry windshield"]]
const ACCS := [["none", "None"], ["light", "Light Mod"], ["display", "Display Mod"]]
## [gear key, row label, options] for the menus
const GEAR_ROWS := [["model", "Camera", MODEL_LIST], ["lens", "Lens", LENSES], ["housing", "Housing", HOUSINGS],
	["mic", "Mic", MICS], ["acc", "Top accessory", ACCS]]
const GEAR_DEFAULT := {model = "hero", lens = "stock", housing = "none", mic = "none", acc = "none"}
## the rider look's keys for the helmet camera's gear
const GEAR_LOOK := {model = "camModel", lens = "camLens", housing = "camHousing", mic = "camMic", acc = "camAcc"}
## lens mod "ultra" (Max Lens Mod) widens the POV view by this many degrees
const ULTRA_FOV := 14.0
const FUR_SHELLS := 7

## gear with every key filled in (unknown ids fall back to the defaults)
static func gear_of(d: Dictionary) -> Dictionary:
	var g := GEAR_DEFAULT.duplicate()
	for r in GEAR_ROWS:
		var v := str(d.get(r[0], g[r[0]]))
		for o in r[2]:
			if o[0] == v: g[r[0]] = v
	return g

## the helmet camera's gear out of a rider look
static func gear_from_look(look: Dictionary) -> Dictionary:
	var d := {}
	for k in GEAR_LOOK: d[k] = look.get(GEAR_LOOK[k], GEAR_DEFAULT[k])
	return gear_of(d)

## the POV view's vertical FOV for this gear
static func fov_of(gear: Dictionary) -> float:
	var g := gear_of(gear)
	return float(MODELS[g.model].fov) + (ULTRA_FOV if g.lens == "ultra" else 0.0)

static func gear_sig(gear: Dictionary) -> String:
	var g := gear_of(gear)
	return "%s/%s/%s/%s/%s" % [g.model, g.lens, g.housing, g.mic, g.acc]

static func _mat(c: String, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c)
	m.roughness = rough
	m.metallic = metal
	return m

static func _cyl(r: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r; c.bottom_radius = r; c.height = h
	c.radial_segments = segs; c.rings = 1
	return c

static func _add(parent: Node3D, mesh: Variant, m: Material, xf := Transform3D()) -> MeshInstance3D:
	var mi: MeshInstance3D
	if mesh is Dictionary:
		mi = G.inst(mesh, m)
	else:
		mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

## recording light: blinks red, on for 0.3 s of every second (every camera in step)
const BLINK := """
float blink() {
	float t = fract(TIME);
	return smoothstep(0.0, 0.03, t) * (1.0 - smoothstep(0.28, 0.33, t));
}
"""
static var _led_sh: Shader
static var _glow_sh: Shader
static var _fur_sh: Shader

static func _led_shader() -> Shader:
	if _led_sh == null:
		_led_sh = Shader.new()
		_led_sh.code = "shader_type spatial;
" + BLINK + """
void fragment() {
	float b = blink();
	ALBEDO = mix(vec3(0.16, 0.02, 0.015), vec3(1.0, 0.16, 0.1), b);
	ROUGHNESS = 0.3;
	EMISSION = vec3(1.0, 0.12, 0.06) * 6.0 * b;
}
"""
	return _led_sh

## a small soft halo round the LED, facing the camera, so the flash reads from a distance too
static func _glow_shader() -> Shader:
	if _glow_sh == null:
		_glow_sh = Shader.new()
		_glow_sh.code = "shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
" + BLINK + """
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = pow(max(1.0 - r, 0.0), 2.5) * blink();
	ALBEDO = vec3(1.0, 0.1, 0.05) * a * 1.6;
}
"""
	return _glow_sh

## fur shells for the furry mic windshield: shell `layer` (0 = the solid core, up to ~0.9 at the tips)
## keeps only the hair cells taller than it
static func _fur_shader() -> Shader:
	if _fur_sh == null:
		_fur_sh = Shader.new()
		_fur_sh.code = """shader_type spatial;
instance uniform float layer = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = UV * vec2(110.0, 55.0);
	float n = h(floor(g));
	if (layer > 0.0 && n < layer) discard;
	vec3 tip = vec3(0.74, 0.72, 0.68) * (0.85 + 0.3 * h(floor(g) + 7.0));
	ALBEDO = mix(tip * 0.35, tip, layer);
	ROUGHNESS = 1.0;
}
"""
	return _fur_sh

static func _mats() -> Dictionary:
	var glass := _mat("#05070a", 0.04, 0.2)
	glass.clearcoat_enabled = true
	glass.clearcoat_roughness = 0.02
	var screen := _mat("#0b1220", 0.1)
	screen.emission_enabled = true
	screen.emission = Color("#12243a")
	screen.emission_energy_multiplier = 0.4
	var led := ShaderMaterial.new()
	led.shader = _led_shader()
	var glow := ShaderMaterial.new()
	glow.shader = _glow_shader()
	var clear := _mat("#dfe8ee", 0.05)
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.albedo_color.a = 0.16
	clear.clearcoat_enabled = true
	clear.clearcoat_roughness = 0.02
	var nd := _mat("#24121c", 0.05, 0.6)
	nd.clearcoat_enabled = true
	var lamp := _mat("#fffbe8", 0.2)
	lamp.emission_enabled = true
	lamp.emission = Color("#fff6dc")
	lamp.emission_energy_multiplier = 5.0
	var fur := ShaderMaterial.new()
	fur.shader = _fur_shader()
	return {
		clear = clear, nd = nd, lamp = lamp, fur = fur,
		sleeve = _mat("#ff6a1a", 0.8),
		grill = _mat("#3a3c40", 0.6, 0.5),
		foam = _mat("#2a2b2e", 1.0),
		body = _mat("#17181b", 0.55),        # rubbery black body
		plast = _mat("#232529", 0.4),        # mount plastic
		trim = _mat("#3b3e44", 0.35, 0.3),
		screw = _mat("#9aa0a8", 0.3, 0.9),
		glass = glass,
		ring = _mat("#2b2d31", 0.25, 0.6),
		screen = screen, led = led, glow = glow,
		btn = _mat("#c8352b", 0.45),
	}

## the adhesive pad + quick-release buckle, built with +Y = out of the surface (root origin = the surface)
static func _base(root: Node3D, M: Dictionary, b := Basis()) -> void:
	_add(root, G.rounded_box(0.042, 0.005, 0.040, 2, 0.002), M.plast, Transform3D(b, b * Vector3(0, 0.0025, 0)))
	_add(root, G.rounded_box(0.034, 0.008, 0.030, 2, 0.003), M.plast, Transform3D(b, b * Vector3(0, 0.009, 0)))
	for s in [-1.0, 1.0]:   # buckle release tabs at the sides
		_add(root, G.box(0.010, 0.006, 0.004), M.trim, Transform3D(b, b * Vector3(-0.006, 0.009, s * 0.017)))

## the LCD's print at `at` (the screen's middle), facing +X (or -X when `back`): a red "● REC" over the
## recording time (CamRecLabel), both in the bike computer's dot-matrix font; `s` scales it (1 = a 24 x 20 mm screen)
static func _screen_text(cam: Node3D, at: Vector3, back := false, s := 1.0) -> void:
	var face := Basis(Vector3.UP, -PI / 2 if back else PI / 2)    # Label3D reads towards +Z: turn it to face out
	var rec := Label3D.new()
	rec.text = "● REC"
	rec.font_size = 32
	rec.pixel_size = 0.00013 * s
	rec.modulate = Color(1.0, 0.22, 0.16)
	var t := Label3D.new()
	t.set_script(preload("res://scripts/rider/cam_rec_label.gd"))
	t.font_size = 48
	t.pixel_size = 0.000165 * s
	t.modulate = Color(0.78, 0.92, 1.0)
	for l: Label3D in [rec, t]:
		l.font = UITheme.lcd_font()
		l.outline_size = 0
		l.shaded = false
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cam.add_child(l)
	rec.transform = Transform3D(face, at + Vector3(0, 0.0058 * s, 0))
	t.transform = Transform3D(face, at + Vector3(0, -0.0022 * s, 0))

## a screen panel (`h` x `w`, on the face +X / -X at `at`) with the REC print on it
static func _screen(cam: Node3D, M: Dictionary, at: Vector3, h: float, w: float, back := false) -> void:
	var sx := -1.0 if back else 1.0
	_add(cam, G.box(0.002, h, w), M.screen, Transform3D(Basis(), at - Vector3(sx * 0.0005, 0, 0)))
	_screen_text(cam, at + Vector3(sx * 0.0008, 0, 0), back, minf(h / 0.020, w / 0.024))

## a blinking LED dot (+ its halo) at `at`, the dot's axis along `axis`
static func _led(cam: Node3D, M: Dictionary, at: Vector3, axis: Basis, out: Vector3) -> void:
	_add(cam, _cyl(0.0022, 0.0024, 10), M.led, Transform3D(axis, at))
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var h := _add(cam, q, M.glow, Transform3D(Basis(), at + out * 0.002))
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## the camera body (lens +X, up +Y) into `cam` (origin = the bottom of its folding fingers) + its "Lens" marker,
## built as gear.model with the add-ons gear asks for (see GEAR_ROWS)
static func _camera(cam: Node3D, M: Dictionary, gear := {}) -> void:
	var g := gear_of(gear)
	var md: Dictionary = MODELS.get(g.model, MODELS.hero)
	var W: float = md.W; var H: float = md.H; var D: float = md.D    # width (Z), height (Y), depth (X)
	var kind: String = md.lens
	var bodym := _mat(md.body, 0.55)
	var trimm := _mat(md.trim, 0.35, 0.3)
	var by := H * 0.5 + 0.006
	var pill := kind == "pill"
	_add(cam, G.rounded_box(D, H, W, 3, 0.011 if pill else 0.006), bodym, Transform3D(Basis(), Vector3(0, by, 0)))
	if not pill:   # a lighter trim band round the middle
		_add(cam, G.rounded_box(D * 1.02, minf(H * 0.18, 0.010), W * 1.01, 2, 0.003), trimm, Transform3D(Basis(), Vector3(0, by + H * 0.22, 0)))
	var along_x := Basis(Vector3.BACK, PI / 2)
	var dome_f := Basis(Vector3.BACK, -PI / 2)   # a hemisphere's +Y turned to +X
	# ---- the lens (lz / ly = its centre on the front, lr = its radius, fx = the x of its front face)
	var lz := 0.0; var ly := by; var lr := 0.0105; var fx := D * 0.5
	match kind:
		"square":   # square block on the front, off to one side (HERO)
			lz = W * 0.5 - 0.019; ly = by + H * 0.12
			_add(cam, G.rounded_box(0.008, 0.027, 0.027, 2, 0.004), bodym, Transform3D(Basis(), Vector3(D * 0.5 + 0.004, ly, lz)))
			_add(cam, _cyl(0.0105, 0.004, 20), M.ring, Transform3D(along_x, Vector3(D * 0.5 + 0.009, ly, lz)))
			_add(cam, _cyl(0.0078, 0.0045, 20), M.glass, Transform3D(along_x, Vector3(D * 0.5 + 0.0095, ly, lz)))
			fx = D * 0.5 + 0.0115
		"round":    # big round lens ring at one side, the screen beside it (Osmo Action)
			lz = W * 0.5 - 0.019; lr = 0.013
			_add(cam, _cyl(0.0135, 0.004, 24), trimm, Transform3D(along_x, Vector3(D * 0.5 + 0.002, ly, lz)))
			_add(cam, _cyl(0.0105, 0.003, 24), M.ring, Transform3D(along_x, Vector3(D * 0.5 + 0.004, ly, lz)))
			_add(cam, _cyl(0.0085, 0.0035, 24), M.glass, Transform3D(along_x, Vector3(D * 0.5 + 0.0045, ly, lz)))
			fx = D * 0.5 + 0.006
		"dual", "dual_top":   # two bulging fisheyes, front and back (360 cameras)
			ly = by + (H * 0.36 if kind == "dual_top" else H * 0.06); lr = 0.0135
			for sx in [1.0, -1.0]:
				var hb := dome_f if sx > 0 else along_x
				_add(cam, _cyl(0.0155, 0.004, 24), M.ring, Transform3D(along_x, Vector3(sx * (D * 0.5 + 0.0015), ly, 0)))
				var dome := SphereMesh.new()
				dome.radius = 0.0125; dome.height = 0.0125; dome.is_hemisphere = true
				dome.radial_segments = 24; dome.rings = 8
				_add(cam, dome, M.glass, Transform3D(hb.scaled(Vector3(1, 0.8, 1)), Vector3(sx * (D * 0.5 + 0.003), ly, 0)))
			fx = D * 0.5 + 0.013
		"pill":     # tiny thumb camera: the lens near the top of the front
			ly = by + H * 0.27; lr = 0.0075
			_add(cam, _cyl(0.0078, 0.002, 20), M.ring, Transform3D(along_x, Vector3(D * 0.5, ly, 0)))
			_add(cam, _cyl(0.0055, 0.0024, 20), M.glass, Transform3D(along_x, Vector3(D * 0.5 + 0.0005, ly, 0)))
			fx = D * 0.5 + 0.0015
	# ---- lens mods over the front lens
	match g.lens:
		"ultra":    # Max Lens Mod: a big fisheye dome in a thick ring
			_add(cam, _cyl(lr * 1.3, 0.006, 24), M.ring, Transform3D(along_x, Vector3(fx + 0.002, ly, lz)))
			var big := SphereMesh.new()
			big.radius = lr * 1.12; big.height = lr * 1.12; big.is_hemisphere = true
			big.radial_segments = 24; big.rings = 8
			_add(cam, big, M.glass, Transform3D(dome_f, Vector3(fx + 0.004, ly, lz)))
			fx += 0.004 + lr * 1.12
		"nd":       # screw-on ND filter: metal ring + dark mirrored glass
			_add(cam, _cyl(lr * 1.2, 0.005, 24), M.screw, Transform3D(along_x, Vector3(fx + 0.0025, ly, lz)))
			_add(cam, _cyl(lr * 1.02, 0.0055, 24), M.nd, Transform3D(along_x, Vector3(fx + 0.0028, ly, lz)))
			fx += 0.0055
		"guard":    # clear protective cover
			_add(cam, _cyl(lr * 1.18, 0.0035, 24), M.clear, Transform3D(along_x, Vector3(fx + 0.0018, ly, lz)))
			fx += 0.0035
	# ---- screens with the REC time
	match md.screen:
		"front":     _screen(cam, M, Vector3(D * 0.5 + 0.0015, ly, -W * 0.5 + 0.022), 0.020, 0.024)
		"front_big": _screen(cam, M, Vector3(D * 0.5 + 0.0015, by, -W * 0.5 + 0.0195), 0.031, 0.031)
		"back":
			var sh := minf(H * 0.62, 0.046) if kind == "dual_top" else H * 0.62
			_screen(cam, M, Vector3(-D * 0.5 - 0.0015, by - (H * 0.14 if kind == "dual_top" else 0.0), 0), sh, W * 0.78, true)
	# ---- blinking record LEDs (front + top) and the shutter button
	if pill:
		_led(cam, M, Vector3(D * 0.5 + 0.0008, by - H * 0.28, 0), along_x, Vector3.RIGHT)
	else:
		_led(cam, M, Vector3(D * 0.5 + 0.0012, by + H * 0.5 - 0.007, -W * 0.5 + 0.008), along_x, Vector3.RIGHT)
		_led(cam, M, Vector3(-D * 0.25, by + H * 0.5 + 0.0008, W * 0.5 - 0.008), Basis(), Vector3.UP)
		if kind == "dual_top":
			_add(cam, _cyl(0.0065, 0.0025, 14), M.btn, Transform3D(along_x, Vector3(D * 0.5 + 0.001, by - H * 0.2, 0)))
		else:
			_add(cam, _cyl(0.0055, 0.0035, 14), M.btn, Transform3D(Basis(), Vector3(0.002, by + H * 0.5 + 0.0012, -W * 0.5 + 0.017)))
	# the mounting fingers folded down under the body
	for z in [-0.0043, 0.0043]:
		_add(cam, G.rounded_box(0.012, 0.012, 0.003, 1, 0.001), M.plast, Transform3D(Basis(), Vector3(0, 0.002, z)))
	# ---- housing round the body
	var top := by + H * 0.5   # the top surface add-ons sit on
	match g.housing:
		"frame", "sleeve":   # open frame (hard plastic, latch) / silicone sleeve (soft, coloured): bands round the sides
			var sl: bool = g.housing == "sleeve"
			var t := 0.0035 if sl else 0.0045
			var dd := D * (0.9 if sl else 0.6)
			var fm: Material = M.sleeve if sl else M.plast
			var rr := 0.0015
			_add(cam, G.rounded_box(dd, t, W + 2 * t, 1, rr), fm, Transform3D(Basis(), Vector3(0, top + t * 0.5, 0)))
			_add(cam, G.rounded_box(dd, t, W + 2 * t, 1, rr), fm, Transform3D(Basis(), Vector3(0, by - H * 0.5 - t * 0.5, 0)))
			for s in [-1.0, 1.0]:
				_add(cam, G.rounded_box(dd, H + 2 * t, t, 1, rr), fm, Transform3D(Basis(), Vector3(0, by, s * (W * 0.5 + t * 0.5))))
			if not sl:   # the frame's latch on the side
				_add(cam, G.rounded_box(0.012, 0.018, 0.005, 1, 0.0015), M.trim, Transform3D(Basis(), Vector3(0, by, W * 0.5 + t + 0.0025)))
			top += t
		"dive":     # clear waterproof box with a flat front port and a latch on the back
			_add(cam, G.rounded_box(D + 0.016, H + 0.016, W + 0.014, 3, 0.005), M.clear, Transform3D(Basis(), Vector3(0.002, by, 0)))
			_add(cam, _cyl(lr * 1.5, 0.004, 24), M.plast, Transform3D(along_x, Vector3(maxf(fx, D * 0.5 + 0.008) + 0.003, ly, lz)))
			_add(cam, _cyl(lr * 1.3, 0.0045, 24), M.glass, Transform3D(along_x, Vector3(maxf(fx, D * 0.5 + 0.008) + 0.0032, ly, lz)))
			_add(cam, G.rounded_box(0.010, 0.012, W * 0.5, 1, 0.002), M.plast, Transform3D(Basis(), Vector3(-D * 0.5 - 0.012, top, 0)))
			fx = maxf(fx, D * 0.5 + 0.008) + 0.006
			top += 0.008
	# ---- media mod, mic and top accessory
	var mz := 0.0; var az := 0.0
	var two: bool = g.mic != "none" and g.acc != "none"
	if two:
		mz = -maxf(W * 0.24, 0.012); az = maxf(W * 0.24, 0.012)
	if g.mic == "mediamod":   # a cage round the sides + top with a built-in mic and two cold shoes
		var mt := 0.007
		_add(cam, G.rounded_box(D * 0.95, mt, W + 0.016, 2, 0.003), M.plast, Transform3D(Basis(), Vector3(-0.001, top + mt * 0.5, 0)))
		for s in [-1.0, 1.0]:
			_add(cam, G.rounded_box(D * 0.95, H + 0.006, mt, 2, 0.003), M.plast, Transform3D(Basis(), Vector3(-0.001, by + 0.003, s * (W * 0.5 + 0.008 + mt * 0.5 - 0.004))))
		_add(cam, _cyl(0.0048, 0.020, 14), M.grill, Transform3D(along_x, Vector3(D * 0.25, top + mt + 0.004, -W * 0.5 + 0.004)))
		top += mt
		az = maxf(W * 0.28, 0.012)
		for s in [-1.0, 1.0]:
			_add(cam, G.box(0.018, 0.0035, 0.016), M.trim, Transform3D(Basis(), Vector3(-0.004, top + 0.00175, s * az)))
		top += 0.0035
	elif g.mic != "none":
		_shoe(cam, M, top, mz)
	if g.acc != "none" and g.mic != "mediamod":
		_shoe(cam, M, top, az)
	var shoe_top := top + (0.0 if g.mic == "mediamod" else 0.004)
	match g.mic:
		"shotgun", "deadcat":
			_add(cam, G.rounded_box(0.008, 0.012, 0.008, 1, 0.002), M.plast, Transform3D(Basis(), Vector3(-0.004, shoe_top + 0.006, mz)))
			var cy := shoe_top + 0.012 + 0.009
			if g.mic == "shotgun":   # foam-covered stick mic pointing ahead
				var foam := CapsuleMesh.new()
				foam.radius = 0.0095; foam.height = 0.075; foam.radial_segments = 16; foam.rings = 4
				_add(cam, foam, M.foam, Transform3D(dome_f, Vector3(0.012, cy, mz)))
			else:                   # the same mic in a furry windshield ("dead cat"): shell fur
				var cyf := cy + 0.004
				for k in FUR_SHELLS:
					var cap := CapsuleMesh.new()
					var f := float(k) / float(FUR_SHELLS - 1)
					cap.radius = 0.013 + f * 0.006; cap.height = 0.085 + f * 0.012
					cap.radial_segments = 20; cap.rings = 6
					var mi := _add(cam, cap, M.fur, Transform3D(dome_f, Vector3(0.012, cyf, mz)))
					mi.set_instance_shader_parameter("layer", f * 0.92)
					if k > 0: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match g.acc:
		"light":    # Light Mod: a small LED lamp that really lights the way ahead
			_add(cam, G.rounded_box(0.026, 0.020, 0.022, 2, 0.004), M.body, Transform3D(Basis(), Vector3(0.0, shoe_top + 0.010, az)))
			_add(cam, _cyl(0.0085, 0.002, 18), M.lamp, Transform3D(along_x, Vector3(0.0132, shoe_top + 0.010, az)))
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.97, 0.9)
			sp.light_energy = 3.0
			sp.spot_range = 14.0
			sp.spot_angle = 34.0
			sp.shadow_enabled = false
			sp.transform = Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(0.016, shoe_top + 0.010, az))
			cam.add_child(sp)
		"display":  # Display Mod: a flip-up screen facing forward (selfie), the REC time on it too
			_add(cam, G.rounded_box(0.010, 0.006, 0.016, 1, 0.002), M.plast, Transform3D(Basis(), Vector3(-0.004, shoe_top + 0.003, az)))
			var pv := Node3D.new()
			pv.position = Vector3(-0.004, shoe_top + 0.006, az)
			pv.rotation.z = 0.25   # tipped back a little
			cam.add_child(pv)
			_add(pv, G.rounded_box(0.006, 0.034, 0.042, 2, 0.003), M.body, Transform3D(Basis(), Vector3(0, 0.017, 0)))
			_screen(pv, M, Vector3(0.0035, 0.017, 0), 0.026, 0.036)
	var lens := Marker3D.new()
	lens.name = "Lens"
	lens.position = Vector3(fx + 0.012, ly, lz)
	lens.set_meta("fov", fov_of(g))
	cam.add_child(lens)

## a cold-shoe adapter plate on the top at z
static func _shoe(cam: Node3D, M: Dictionary, top: float, z: float) -> void:
	_add(cam, G.box(0.020, 0.004, 0.018), M.trim, Transform3D(Basis(), Vector3(-0.004, top + 0.002, z)))

## kind "top" (default): the helmet-top mount; the others: build_arm with the mount's own geometry
static func build(kind := "top", gear := {}) -> Node3D:
	match kind:
		"side":   # stuck on the left of the shell, the camera upright beside it, lens level with the eyes
			return build_arm(Vector3(0, 0, -1), Vector3(0.0, -0.03, -0.052), 0.0, gear)
		"chin":   # on the front of the chin bar, the camera hanging just ahead of it
			return build_arm(Vector3(1, 0, 0), Vector3(0.034, -0.03, 0.0), 0.0, gear)
	var M := _mats()
	var root := Node3D.new()
	root.name = "ActionCam"
	root.set_meta("kind", "top")
	_base(root, M)
	# three-finger hinge (fingers lie in the X-Y plane, stacked along Z), thumb screw through them along Z
	var hinge_y := 0.026
	for z in [-0.0085, 0.0, 0.0085]:
		_add(root, G.rounded_box(0.014, 0.022, 0.0032, 1, 0.0012), M.plast, Transform3D(Basis(), Vector3(0, 0.020, z)))
	var along_z := Basis(Vector3.RIGHT, PI / 2)
	_add(root, _cyl(0.0035, 0.024, 10), M.screw, Transform3D(along_z, Vector3(0, hinge_y, 0)))
	var knob: MeshInstance3D = _add(root, _cyl(0.0085, 0.008, 12), M.plast, Transform3D(along_z, Vector3(0, hinge_y, 0.017)))
	knob.name = "ThumbScrew"
	# the camera's own folding fingers + body, hinged slightly back so it sits level over the crown
	var cam := Node3D.new()
	cam.name = "Body"
	cam.position = Vector3(0, hinge_y + 0.006, 0)
	cam.rotation.z = 0.14   # tipped up on the hinge (~8°), as riders set it: less visor in the shot
	root.add_child(cam)
	_camera(cam, M, gear)
	return root

## pad / buckle facing `normal` at the origin, an arm out to `body_at` (the camera body's origin = the bottom
## of its fingers), the camera upright there (lens +X). Arm = a stack of rounded links with a thumb screw at each joint.
static func build_arm(normal: Vector3, body_at: Vector3, tilt := 0.0, gear := {}) -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "ActionCam"
	root.set_meta("kind", "arm")
	var n := normal.normalized()
	var ref := Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.UP
	var bz := ref.cross(n).normalized()
	var bx := n.cross(bz).normalized()
	var b := Basis(bx, n, bz)   # +Y of the pad = the normal
	_base(root, M, b)
	# the arm: from the top of the buckle to the camera's hinge (just under the body)
	var a0 := n * 0.014
	var a1 := body_at + Vector3(0, 0.004, 0)
	var mid := a0.lerp(a1, 0.5)
	var seg := a1 - a0
	var L := seg.length()
	if L > 0.004:
		var y := seg / L
		var r2 := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
		var z := r2.cross(y).normalized()
		var x := y.cross(z).normalized()
		var ab := Basis(x, y, z)
		# two parallel links (fingers) either side of the arm's plane, as on the real extension arms
		for o in [-0.0045, 0.0045]:
			_add(root, G.rounded_box(0.012, L + 0.012, 0.0032, 1, 0.0012), M.plast, Transform3D(ab, mid + ab * Vector3(0, 0, o)))
		var along := Basis(x, z, -y)   # cylinder axis (Y) along the arm's z
		for p in [a0, a1]:
			_add(root, _cyl(0.0035, 0.016, 10), M.screw, Transform3D(along, p))
		var knob: MeshInstance3D = _add(root, _cyl(0.0075, 0.007, 12), M.plast, Transform3D(along, a1 + ab * Vector3(0, 0, 0.011)))
		knob.name = "ThumbScrew"
	var cam := Node3D.new()
	cam.name = "Body"
	cam.position = body_at
	cam.rotation.z = tilt
	root.add_child(cam)
	_camera(cam, M, gear)
	return root

## a bar / tube clamp (handlebar, fork leg): a ring of radius `r` round the tube along `axis` at the origin,
## the arm out to the camera at `body_at` (camera upright, lens +X). Root origin = the tube's centre.
static func build_clamp(axis: Vector3, r: float, out: Vector3, body_at: Vector3, tilt := 0.0, gear := {}) -> Node3D:
	var M := _mats()
	var root := Node3D.new()
	root.name = "ActionCam"
	root.set_meta("kind", "clamp")
	var y := axis.normalized()
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP
	var z := ref.cross(y).normalized()
	var x := y.cross(z).normalized()
	var ring := CylinderMesh.new()
	ring.top_radius = r + 0.004; ring.bottom_radius = r + 0.004; ring.height = 0.018
	ring.radial_segments = 20; ring.rings = 1
	_add(root, ring, M.plast, Transform3D(Basis(x, y, z), Vector3.ZERO))
	# the clamp's screw block on the outside, toward the camera
	var o := out.normalized()
	var ob_ref := y if absf(o.dot(y)) < 0.9 else x
	var oz := ob_ref.cross(o).normalized()
	var ob := Basis(o.cross(oz).normalized(), o, oz)
	_add(root, G.rounded_box(0.020, 0.010, 0.020, 1, 0.002), M.plast, Transform3D(ob, o * (r + 0.008)))
	_add(root, _cyl(0.0032, 0.024, 10), M.screw, Transform3D(Basis(x, y, z), o * (r + 0.008)))
	var arm := build_arm(o, body_at - o * (r + 0.006), tilt, gear)
	# keep only the arm + camera (the clamp replaces the adhesive pad): drop the pad's three meshes + tabs
	var k := 0
	for c in arm.get_children():
		if c is MeshInstance3D and k < 4:
			arm.remove_child(c); c.queue_free(); k += 1
	arm.position = o * (r + 0.006)
	arm.name = "Arm"
	root.add_child(arm)
	# the camera body must be a direct child named Body (break_action_cam / the views look for "Body/Lens")
	var bd := arm.get_node("Body") as Node3D
	var bx := bd.transform
	arm.remove_child(bd)
	bd.transform = arm.transform * bx
	root.add_child(bd)
	return root
