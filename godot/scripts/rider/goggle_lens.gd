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
const N := 48   # LUT size per axis (48^3 RGBA8 = 0.4 MB each, 30-70 ms to build, cached)

## Each lens: made-up name, a line about it, the lens film colour (UI swatch / goggle tint) and the grade.
## Grade keys (all in display sRGB 0..1): gain (exposure), tint (white balance, luma kept), lift (raises blacks),
## gamma (< 1 brighter mids), contrast (S-curve round 0.5), sat, shadow / hi (colour pushed into the shadows /
## highlights), roll (soft highlight shoulder: calmer bright sky).
const LENSES := {
	"neutral": {"name": "Clear", "desc": "No tint. The world as it is.", "color": Color(0.86, 0.9, 0.93, 0.35),
		"grade": {}},
	"amber": {"name": "Ember", "desc": "Warm amber. More contrast, sharper shadows: reads ruts and roots.", "color": Color(0.93, 0.55, 0.12),
		"grade": {"tint": Color(1.08, 0.99, 0.82), "contrast": 0.42, "gamma": 1.06, "sat": 1.08, "shadow": Color(0.035, 0.012, -0.02), "hi": Color(0.02, 0.01, -0.03)}},
	"rose": {"name": "Rosé", "desc": "Soft pink. Lifts contrast in flat, grey light.", "color": Color(0.92, 0.5, 0.58),
		"grade": {"tint": Color(1.055, 0.96, 0.98), "contrast": 0.36, "sat": 1.06, "shadow": Color(0.012, -0.006, 0.006), "hi": Color(0.03, 0.0, 0.015)}},
	"smoke": {"name": "Smoke", "desc": "Grey tint for bright sun. Darker, a touch cool, calm highlights.", "color": Color(0.28, 0.3, 0.33),
		"grade": {"gain": 0.86, "tint": Color(0.97, 1.0, 1.04), "contrast": 0.12, "sat": 0.9, "roll": 0.55}},
	"ice": {"name": "Glacier", "desc": "Blue iridium. Cool teal and crisp.", "color": Color(0.22, 0.6, 0.85),
		"grade": {"gain": 0.96, "tint": Color(0.91, 1.0, 1.09), "contrast": 0.32, "sat": 1.04, "shadow": Color(-0.02, 0.012, 0.03), "roll": 0.3}},
	"yellow": {"name": "Dusk Yellow", "desc": "Low-light yellow. Brighter, lifts the shadows.", "color": Color(0.98, 0.84, 0.15),
		"grade": {"gain": 1.04, "tint": Color(1.06, 1.04, 0.8), "lift": 0.035, "gamma": 0.86, "contrast": 0.08, "sat": 1.02}},
	"green": {"name": "Moss", "desc": "Green mirror. A green cast and a bit more bite.", "color": Color(0.3, 0.62, 0.32),
		"grade": {"tint": Color(0.95, 1.06, 0.94), "contrast": 0.32, "sat": 1.02, "shadow": Color(-0.008, 0.015, -0.004)}},
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

## builds a LUT from a grade dictionary (an empty one = the identity LUT, used by the probe). 30-70 ms.
## Texel i along an axis is read at coordinate (i + 0.5) / N; the two end texels hold the exact 0 / 1 values
## instead, so pure black, white and saturated colours come through exactly (measured: tools/lens_lut_probe.gd).
static func make_lut(g: Dictionary) -> ImageTexture3D:
	# the per-channel part (gain, white balance, lift, gamma, S-curve) as three tables
	var tab: Array[PackedFloat32Array] = []
	for ch in 3:
		var t := PackedFloat32Array()
		t.resize(N)
		for i in N: t[i] = _chan(_at(i), ch, g)
		tab.append(t)
	var sat := float(g.get("sat", 1.0))
	var sh: Color = g.get("shadow", Color(0, 0, 0))
	var hi: Color = g.get("hi", Color(0, 0, 0))
	var roll := float(g.get("roll", 0.0))
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
				var r := tr[ri]
				var l := r * 0.2126 + gg * 0.7152 + b * 0.0722
				var lc := clampf(l, 0.0, 1.0)
				var ws := (1.0 - lc) * (1.0 - lc); var wh := lc * lc
				var o_r := l + (r - l) * sat + sh.r * ws + hi.r * wh
				var o_g := l + (gg - l) * sat + sh.g * ws + hi.g * wh
				var o_b := l + (b - l) * sat + sh.b * ws + hi.b * wh
				if roll > 0.0:
					o_r = _roll(o_r, roll); o_g = _roll(o_g, roll); o_b = _roll(o_b, roll)
				row[i] = clampi(roundi(o_r * 255.0), 0, 255)
				row[i + 1] = clampi(roundi(o_g * 255.0), 0, 255)
				row[i + 2] = clampi(roundi(o_b * 255.0), 0, 255)
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
	var lift := float(g.get("lift", 0.0))
	x = lift + x * (1.0 - lift)
	x = pow(maxf(x, 0.0), float(g.get("gamma", 1.0)))
	return _s(x, float(g.get("contrast", 0.0)))

## one colour (display sRGB 0..1) through a lens grade (the CPU reference of the LUT)
static func grade(c: Color, g: Dictionary) -> Color:
	var r := _chan(c.r, 0, g); var gg := _chan(c.g, 1, g); var b := _chan(c.b, 2, g)
	var l := r * 0.2126 + gg * 0.7152 + b * 0.0722
	var lc := clampf(l, 0.0, 1.0)
	var ws := (1.0 - lc) * (1.0 - lc); var wh := lc * lc
	var sat := float(g.get("sat", 1.0))
	var sh: Color = g.get("shadow", Color(0, 0, 0))
	var hi: Color = g.get("hi", Color(0, 0, 0))
	var v := Vector3(l + (r - l) * sat + sh.r * ws + hi.r * wh, l + (gg - l) * sat + sh.g * ws + hi.g * wh, l + (b - l) * sat + sh.b * ws + hi.b * wh)
	var roll := float(g.get("roll", 0.0))
	if roll > 0.0:
		v = Vector3(_roll(v.x, roll), _roll(v.y, roll), _roll(v.z, roll))
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))

static func _luma(v: Vector3) -> float:
	return v.x * 0.2126 + v.y * 0.7152 + v.z * 0.0722

## S-curve round 0.5 (k 0..1: 0 = straight, monotonic up to 1); ends stay at 0 and 1
static func _s(x: float, k: float) -> float:
	var y := clampf(x, 0.0, 1.0)
	return x + k * 2.0 * (y - 0.5) * y * (1.0 - y)

## soft highlight shoulder above 0.6: amount 0..1 squeezes the top towards a gentler white
static func _roll(x: float, amt: float) -> float:
	const KNEE := 0.6
	if x <= KNEE: return x
	var t := (x - KNEE) / (1.0 - KNEE)
	return KNEE + (1.0 - KNEE) * (t - amt * 0.35 * t * t)
