extends RefCounted
## Goggle lenses = colour grades. The player picks a lens on the ride setup page (GameState.goggle_lens) and the
## whole ride view is graded by it, like a LUT: `lut(id)` builds a 3D colour lookup (Texture3D) for
## `Environment.adjustment_color_correction` (needs `adjustment_enabled = true`). "neutral" = no LUT at all (null).
## No class_name on purpose: `const GoggleLens = preload("res://scripts/rider/goggle_lens.gd")`.
##
## How Godot reads it (tonemap shader): after tonemapping + linear -> sRGB, the colour is clamped to 0..1 and used
## straight as the 3D texture coordinate (`textureLod(lut, color, 0)`, no half-texel remap, linear filtering).
## So texel i along an axis sits at coordinate (i + 0.5) / N and is baked with f((i + 0.5) / N); the end texels hold
## f(0) / f(1). The identity LUT gives the image back (tools/lens_lut_probe.gd: IDENTITY max_err <= ~3/255, only
## in the darkest / brightest 1 % of a channel, mean ~0.1).

const DEFAULT := "neutral"
const N := 33   # LUT size per axis (the colourist's standard: 33^3 RGBA8, cached; ~3x quicker to build than 48 with the hue work)

## Each lens: made-up name, a line about it, the lens film colour (UI swatch / goggle tint) and its grade.
## 2026-11-26 (user: "lenses that mimic colour grading, like the artsy downhill films"): the lenses are film grades now,
## the way action-sport edits are graded: a filmic tone curve (matte, slightly lifted blacks, a soft highlight shoulder),
## hue-selective moves (greens toward olive / emerald, skies toward teal, earth + skin kept warm so the rider pops),
## saturation that falls away in deep shadow and bright highlights like film, and split toning (cool shade, warm light).
## Grade keys (display sRGB 0..1, applied in this order):
##   gain, tint (white balance, luma kept), black (lifted black: matte), lift, gamma (< 1 brighter mids),
##   contrast (S-curve round `pivot`, default 0.5)
##   bands: [{hue (deg), width (deg), shift (deg), sat (x), val (x)}]  hue-selective moves (red 0, yellow 60, green 120, cyan
##          180, blue 240, magenta 300); weights fade over `width` either side and with how colourful the pixel is
##   sat, sat_fall (0..1: less colour in shadows / highlights), shadow / hi (colour pushed into each end), roll (shoulder)
const LENSES := {
	"neutral": {"name": "Clear", "desc": "No tint. The world as it is.", "color": Color(0.86, 0.9, 0.93, 0.35),
		"grade": {}},
	"cine": {"name": "Red Line", "desc": "The edit look: rich contrast, deep teal skies, warm dirt and skin, olive greens.", "color": Color(0.82, 0.2, 0.16),
		"grade": {"black": 0.025, "contrast": 0.5, "pivot": 0.45, "gamma": 1.04, "sat": 1.12, "sat_fall": 0.55, "roll": 0.5,
			"shadow": Color(-0.02, 0.006, 0.03), "hi": Color(0.03, 0.012, -0.03),
			"bands": [{"hue": 110, "width": 55, "shift": -12, "sat": 0.78, "val": 0.92},
				{"hue": 72, "width": 30, "shift": -4, "sat": 0.82, "val": 0.96},
				{"hue": 215, "width": 45, "shift": -14, "sat": 1.12, "val": 0.9},
				{"hue": 25, "width": 30, "shift": 3, "sat": 1.12, "val": 1.03}]}},
	"amber": {"name": "Ember", "desc": "Golden hour, bottled: warm light, teal shade, punchy contrast.", "color": Color(0.93, 0.55, 0.12),
		"grade": {"tint": Color(1.06, 1.0, 0.86), "black": 0.02, "contrast": 0.45, "gamma": 1.05, "sat": 1.06, "sat_fall": 0.5, "roll": 0.45,
			"shadow": Color(-0.03, 0.01, 0.035), "hi": Color(0.04, 0.015, -0.035),
			"bands": [{"hue": 110, "width": 50, "shift": -18, "sat": 0.8, "val": 0.95},
				{"hue": 72, "width": 30, "shift": -4, "sat": 0.85, "val": 0.97},
				{"hue": 210, "width": 50, "shift": -18, "sat": 0.95, "val": 0.92},
				{"hue": 30, "width": 30, "shift": 0, "sat": 1.15, "val": 1.04}]}},
	"rose": {"name": "Rosé", "desc": "Soft pastel film: lifted blacks, gentle contrast, pink highlights.", "color": Color(0.92, 0.5, 0.58),
		"grade": {"tint": Color(1.04, 0.97, 0.99), "black": 0.06, "contrast": 0.18, "gamma": 0.96, "sat": 0.9, "sat_fall": 0.6, "roll": 0.6,
			"shadow": Color(0.0, 0.006, 0.02), "hi": Color(0.035, 0.0, 0.015),
			"bands": [{"hue": 115, "width": 55, "shift": -8, "sat": 0.75, "val": 1.0},
				{"hue": 220, "width": 50, "shift": 8, "sat": 0.85, "val": 1.04}]}},
	"smoke": {"name": "Smoke", "desc": "Bleach bypass: silvery, hard, colour held back. Bright sun tamed.", "color": Color(0.28, 0.3, 0.33),
		"grade": {"gain": 0.9, "tint": Color(0.98, 1.0, 1.03), "black": 0.012, "contrast": 0.6, "gamma": 1.06, "sat": 0.62, "sat_fall": 0.4, "roll": 0.65,
			"shadow": Color(-0.008, 0.0, 0.012),
			"bands": [{"hue": 25, "width": 30, "shift": 0, "sat": 1.3, "val": 1.0}]}},
	"ice": {"name": "Glacier", "desc": "Cold and crisp: teal shade, steel-blue skies, clean whites.", "color": Color(0.22, 0.6, 0.85),
		"grade": {"tint": Color(0.93, 1.0, 1.08), "black": 0.015, "contrast": 0.4, "gamma": 1.02, "sat": 0.96, "sat_fall": 0.5, "roll": 0.4,
			"shadow": Color(-0.02, 0.012, 0.03), "hi": Color(-0.005, 0.005, 0.01),
			"bands": [{"hue": 115, "width": 55, "shift": 22, "sat": 0.8, "val": 0.94},
				{"hue": 220, "width": 50, "shift": -10, "sat": 1.1, "val": 0.88},
				{"hue": 25, "width": 30, "shift": 0, "sat": 1.1, "val": 1.0}]}},
	"yellow": {"name": "Dusk Yellow", "desc": "Faded 16 mm: warm, milky blacks, yellow-green highlights. Brighter in low light.", "color": Color(0.98, 0.84, 0.15),
		"grade": {"gain": 1.05, "tint": Color(1.05, 1.03, 0.86), "black": 0.07, "gamma": 0.9, "contrast": 0.25, "sat": 0.92, "sat_fall": 0.6, "roll": 0.55,
			"shadow": Color(0.0, 0.012, 0.025), "hi": Color(0.02, 0.025, -0.03),
			"bands": [{"hue": 115, "width": 50, "shift": -16, "sat": 0.85, "val": 1.0},
				{"hue": 210, "width": 50, "shift": 10, "sat": 0.8, "val": 1.05}]}},
	"green": {"name": "Moss", "desc": "Deep forest: emerald greens, moody shade, warm skin.", "color": Color(0.3, 0.62, 0.32),
		"grade": {"tint": Color(0.97, 1.03, 0.98), "black": 0.02, "contrast": 0.45, "pivot": 0.42, "gamma": 1.08, "sat": 1.04, "sat_fall": 0.55, "roll": 0.45,
			"shadow": Color(-0.015, 0.012, 0.01), "hi": Color(0.02, 0.01, -0.02),
			"bands": [{"hue": 105, "width": 50, "shift": 14, "sat": 1.1, "val": 0.85},
				{"hue": 215, "width": 45, "shift": -8, "sat": 0.9, "val": 0.9},
				{"hue": 25, "width": 30, "shift": 2, "sat": 1.1, "val": 1.04}]}},
}

static var _cache := {}

static func ids() -> Array:
	return LENSES.keys()

static func has(id: String) -> bool:
	return LENSES.has(id)

static func display_name(id: String) -> String:
	return String(LENSES.get(id, LENSES[DEFAULT]).name)

static func description(id: String) -> String:
	return String(LENSES.get(id, LENSES[DEFAULT]).desc)

## the lens film colour (UI swatch; alpha < 1 = clear)
static func tint(id: String) -> Color:
	return LENSES.get(id, LENSES[DEFAULT]).color

## the 3D LUT for Environment.adjustment_color_correction, or null (neutral / unknown id = leave the image alone)
static func lut(id: String) -> Texture3D:
	if not LENSES.has(id) or (LENSES[id].grade as Dictionary).is_empty(): return null
	if _cache.has(id): return _cache[id]
	var t := make_lut(LENSES[id].grade)
	_cache[id] = t
	return t

## builds a LUT from a grade dictionary (an empty one = the identity LUT, used by the probe).
## Texel i along an axis is read at coordinate (i + 0.5) / N; the two end texels hold the exact 0 / 1 values
## instead, so pure black, white and saturated colours come through exactly (measured: tools/lens_lut_probe.gd).
static func make_lut(g: Dictionary) -> ImageTexture3D:
	# the per-channel part (gain, white balance, black, lift, gamma, S-curve) as three tables
	var tab: Array[PackedFloat32Array] = []
	for ch in 3:
		var t := PackedFloat32Array()
		t.resize(N)
		for i in N: t[i] = _chan(_at(i), ch, g)
		tab.append(t)
	var P := _prep(g)
	var layers: Array[Image] = []
	var row := PackedByteArray()
	row.resize(N * N * 4)
	var tr := tab[0]; var tg := tab[1]; var tb := tab[2]
	for bi in N:
		var b := tb[bi]
		var i := 0
		for gi in N:
			var gg := tg[gi]
			for ri in N:
				var v := _colour(Vector3(tr[ri], gg, b), P)
				row[i] = clampi(roundi(v.x * 255.0), 0, 255)
				row[i + 1] = clampi(roundi(v.y * 255.0), 0, 255)
				row[i + 2] = clampi(roundi(v.z * 255.0), 0, 255)
				row[i + 3] = 255
				i += 4
		layers.append(Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, row))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGBA8, N, N, N, false, layers)
	return tex

## where texel i is read (see make_lut)
static func _at(i: int) -> float:
	if i == 0: return 0.0
	if i == N - 1: return 1.0
	return (i + 0.5) / N

## one channel (ch 0..2) through the per-channel part of a grade
static func _chan(x: float, ch: int, g: Dictionary) -> float:
	x *= float(g.get("gain", 1.0))
	if g.has("tint"):
		var t: Color = g.tint
		x *= t[ch] / (t.r * 0.2126 + t.g * 0.7152 + t.b * 0.0722)   # white balance, brightness kept
	var blk := float(g.get("black", 0.0))
	var lift := float(g.get("lift", 0.0))
	x = pow(maxf(x, 0.0), float(g.get("gamma", 1.0)))
	x = _s(x, float(g.get("contrast", 0.0)), float(g.get("pivot", 0.5)))
	x = lift + x * (1.0 - lift)
	return blk + x * (1.0 - blk)   # matte: the darkest black is lifted a touch (film never reaches true black)

## the parts after the curves, unpacked once per LUT
static func _prep(g: Dictionary) -> Dictionary:
	return {"sat": float(g.get("sat", 1.0)), "fall": float(g.get("sat_fall", 0.0)),
		"sh": g.get("shadow", Color(0, 0, 0)), "hi": g.get("hi", Color(0, 0, 0)), "roll": float(g.get("roll", 0.0)),
		"bands": g.get("bands", [])}

## one colour after the per-channel curves: hue bands, film saturation, split toning, shoulder
static func _colour(v: Vector3, P: Dictionary) -> Vector3:
	var bands: Array = P.bands
	if not bands.is_empty():
		var hsv := _hsv(v)
		var h := hsv.x; var s := hsv.y; var val := hsv.z
		if s > 0.001:
			var dh := 0.0; var ms := 1.0; var mv := 1.0
			var on := smoothstep(0.03, 0.25, s)   # greys stay grey
			for bd in bands:
				var d := absf(fposmod(h - float(bd.hue) + 180.0, 360.0) - 180.0)
				var w := 1.0 - smoothstep(0.0, float(bd.width), d)
				if w <= 0.0: continue
				w *= on
				dh += float(bd.get("shift", 0.0)) * w
				ms *= lerpf(1.0, float(bd.get("sat", 1.0)), w)
				mv *= lerpf(1.0, float(bd.get("val", 1.0)), w)
			v = _rgb(Vector3(fposmod(h + dh, 360.0), clampf(s * ms, 0.0, 1.0), val * mv))
	var l := v.x * 0.2126 + v.y * 0.7152 + v.z * 0.0722
	var lc := clampf(l, 0.0, 1.0)
	var e := 2.0 * lc - 1.0
	var sat: float = P.sat * (1.0 - P.fall * e * e * e * e)   # film: rich mids, colour fades into deep shade and highlights
	var ws := (1.0 - lc) * (1.0 - lc); var wh := lc * lc
	var sh: Color = P.sh; var hi: Color = P.hi
	v = Vector3(l + (v.x - l) * sat + sh.r * ws + hi.r * wh, l + (v.y - l) * sat + sh.g * ws + hi.g * wh, l + (v.z - l) * sat + sh.b * ws + hi.b * wh)
	var roll: float = P.roll
	if roll > 0.0:
		v = Vector3(_roll(v.x, roll), _roll(v.y, roll), _roll(v.z, roll))
	return v

static func _hsv(c: Vector3) -> Vector3:
	var mx := maxf(c.x, maxf(c.y, c.z)); var mn := minf(c.x, minf(c.y, c.z))
	var d := mx - mn
	var h := 0.0
	if d > 1e-6:
		if mx == c.x: h = 60.0 * fposmod((c.y - c.z) / d, 6.0)
		elif mx == c.y: h = 60.0 * ((c.z - c.x) / d + 2.0)
		else: h = 60.0 * ((c.x - c.y) / d + 4.0)
	return Vector3(h, 0.0 if mx <= 1e-6 else d / mx, mx)

static func _rgb(hsv: Vector3) -> Vector3:
	var c := hsv.z * hsv.y
	var hp := hsv.x / 60.0
	var x := c * (1.0 - absf(fposmod(hp, 2.0) - 1.0))
	var m := hsv.z - c
	var r := Vector3(c, x, 0.0)
	if hp < 1.0: r = Vector3(c, x, 0.0)
	elif hp < 2.0: r = Vector3(x, c, 0.0)
	elif hp < 3.0: r = Vector3(0.0, c, x)
	elif hp < 4.0: r = Vector3(0.0, x, c)
	elif hp < 5.0: r = Vector3(x, 0.0, c)
	else: r = Vector3(c, 0.0, x)
	return r + Vector3(m, m, m)

## one colour (display sRGB 0..1) through a lens grade (the CPU reference of the LUT)
static func grade(c: Color, g: Dictionary) -> Color:
	var v := _colour(Vector3(_chan(c.r, 0, g), _chan(c.g, 1, g), _chan(c.b, 2, g)), _prep(g))
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))

static func _luma(v: Vector3) -> float:
	return v.x * 0.2126 + v.y * 0.7152 + v.z * 0.0722

## S-curve round a pivot (k 0..1: 0 = straight, monotonic up to 1); ends stay at 0 and 1
static func _s(x: float, k: float, pivot := 0.5) -> float:
	var y := clampf(x, 0.0, 1.0)
	return x + k * 2.0 * (y - pivot) * y * (1.0 - y)

## soft highlight shoulder above 0.6: amount 0..1 squeezes the top towards a gentler white
static func _roll(x: float, amt: float) -> float:
	const KNEE := 0.6
	if x <= KNEE: return x
	var t := (x - KNEE) / (1.0 - KNEE)
	return KNEE + (1.0 - KNEE) * (t - amt * 0.35 * t * t)


## the lens cards' picture: the newest helmets' own goggle model (helmet_goggles in helmet_tld.glb) with its lens in this
## lens's colour (shaders/goggle_lens.gdshader); rendered by PartThumbs (main.gd `bike_thumbs`)
const GOGGLE_GLB := "res://assets/helmets/helmet_tld.glb"
static func make_goggles(id: String) -> Node3D:
	var src: Node = (load(GOGGLE_GLB) as PackedScene).instantiate()
	var g := src.find_child("helmet_goggles", true, false) as MeshInstance3D
	var root := Node3D.new()
	if g == null:
		src.free()
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = g.mesh
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/goggle_lens.gdshader")
	var om := g.mesh.surface_get_material(0) as StandardMaterial3D
	if om: sm.set_shader_parameter("albedo_tex", om.albedo_texture)
	sm.set_shader_parameter("lens_tint", tint(id))
	mi.material_override = sm
	root.add_child(mi)
	src.free()
	return root
