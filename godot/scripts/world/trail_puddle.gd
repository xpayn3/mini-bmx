class_name TrailPuddle
## Where ground.gdshader draws puddles / damp soil on the trail, for the CPU (tyre dust, spray).
## The shader works the puddle out per pixel from the chunk's baked trail frame (TR / T2) + noise; this is the same
## formula at one point, so the dust stops exactly where the water is drawn.
## Light by design: the chunk worker keeps a table only for chunks with puddle-capable road (most chunks: none),
## and a lookup leaves early outside a puddle stretch (one noise) or where the noise can't reach a puddle (two).
## Keep in step with the puddle block in ground.gdshader (`m_wet` / `m_puddle`).

const STRIDE := 5   # per vertex: across, racing line, along, road, static mask (road x level x not dry x on trail x not a jump)

# the shader's ridden lines (ground.gdshader LG / LD / LW): only their place matters here
const LG := [1.0, 1.0, 1.0, 1.0, 0.9, 1.15, 0.8, 0.55, 1.35]
const LD := [0.0, 0.06, -0.07, 0.13, 0.22, 0.3, -0.28, -0.5, 0.55]
const LW := [0.9, 0.8, 0.8, 0.65, 0.5, 0.5, 0.5, 0.4, 0.35]


static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


## the chunk's puddle table (worker thread), or an empty array when nothing here can hold a puddle
static func table(TR: PackedFloat32Array, T2: PackedFloat32Array, TW: PackedFloat32Array, norms: PackedVector3Array, NV: int) -> PackedFloat32Array:
	var n := NV * NV
	var out := PackedFloat32Array()
	var any := false
	for o in n:
		var rd: float = T2[o * 4]
		if rd <= 0.0:
			continue
		var t := clampf(TW[o], 0.0, 1.0)
		var lvl := _ss(0.988, 0.998, norms[o].y)
		var pk := rd * lvl * (1.0 - _ss(0.3, 0.6, T2[o * 4 + 1])) * _ss(0.85, 1.0, t) * (1.0 - clampf(T2[o * 4 + 2], 0.0, 1.0))
		if pk <= 0.0:
			continue
		if not any:
			any = true
			out.resize(n * STRIDE)   # zero-filled: every other vertex = no puddle
		var j := o * STRIDE
		out[j] = TR[o * 4]; out[j + 1] = TR[o * 4 + 1]; out[j + 2] = TR[o * 4 + 2]; out[j + 3] = rd; out[j + 4] = pk
	return out


## x = damp soil round a puddle, y = standing water (0..1, as drawn), at world point p; tp = the shader's trail_puddles
static func at(tab: PackedFloat32Array, N: int, gx: float, gz: float, p: Vector3, tp: float) -> Vector2:
	var NV := N + 1
	gx = clampf(gx, 0.0, N - 0.0001)
	gz = clampf(gz, 0.0, N - 0.0001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var j00 := (iz * NV + ix) * STRIDE
	var j10 := j00 + STRIDE
	var j01 := j00 + NV * STRIDE
	var j11 := j01 + STRIDE
	var w00 := (1.0 - fx) * (1.0 - fz)
	var w10 := fx * (1.0 - fz)
	var w01 := (1.0 - fx) * fz
	var w11 := fx * fz
	var pk := tab[j00 + 4] * w00 + tab[j10 + 4] * w10 + tab[j01 + 4] * w01 + tab[j11 + 4] * w11
	if pk <= 0.0:
		return Vector2.ZERO
	var sl := tab[j00 + 2] * w00 + tab[j10 + 2] * w10 + tab[j01 + 2] * w01 + tab[j11 + 2] * w11
	# puddles come in stretches along the trail
	var zone := maxf(_ss(0.47, 0.62, noise3(Vector3(sl * 0.011, 21.0, 8.0))), tp - 1.0)
	pk *= zone * minf(tp, 1.0)
	if pk <= 0.0:
		return Vector2.ZERO
	var ac := tab[j00] * w00 + tab[j10] * w10 + tab[j01] * w01 + tab[j11] * w11
	var b := noise3(Vector3(ac * 1.5, sl * 0.21, 13.0))
	if b + 0.0375 < 0.44:   # the most the rest can add: never damp here
		return Vector2.ZERO
	var off := tab[j00 + 1] * w00 + tab[j10 + 1] * w10 + tab[j01 + 1] * w01 + tab[j11 + 1] * w11
	var rd := tab[j00 + 3] * w00 + tab[j10 + 3] * w10 + tab[j01 + 3] * w01 + tab[j11 + 3] * w11
	# in the worn lines (the lowest ground): the shader's ridden-line mask
	var line := 0.0
	var alt := 0.0
	for i in 9:
		var fi := float(i)
		var loose_k: float = absf(LD[i]) + absf(LG[i] - 1.0)
		var wob := (sin(sl * (0.047 + 0.011 * fi) + fi * 2.4) + sin(sl * (0.021 + 0.007 * fi) + fi * 5.1)) * (0.02 + 0.3 * loose_k)
		var c: float = off * LG[i] + LD[i] * (1.0 + 0.5 * rd) + wob
		var pres := 1.0 if i < 4 else _ss(-0.25, 0.25, sin(sl * (0.013 + 0.004 * fi) + fi * 1.7))
		var l: float = (1.0 - _ss(0.03, 0.11, absf(ac - c))) * LW[i] * pres
		if i < 4: line += l * (1.0 - line)
		else: alt += l * (1.0 - alt)
	line *= 0.6 + 0.4 * _ss(0.25, 0.6, noise3(Vector3(sl * 0.035, 7.0, 1.0)))
	line = line + alt * (1.0 - line)
	var inrut := maxf(1.0 - _ss(0.15, 0.8, absf(ac - off)), line)
	var n0 := noise3(p * 2.3 + Vector3(3.3, 3.3, 3.3))
	var n1 := noise3(p * 9.0)
	var pn := b * (0.62 + 0.38 * inrut) + (n0 - 0.5) * 0.05 + (n1 - 0.5) * 0.025
	return Vector2(_ss(0.44, 0.56, pn) * pk, _ss(0.565, 0.59, pn) * pk)


# ---- ground.gdshader's gd_hash / gd_noise3 (Vector3 is float32 like the GPU) ----
static func _hash(p: Vector3) -> float:
	p = p * 0.1031
	p -= p.floor()
	p += Vector3.ONE * p.dot(Vector3(p.z, p.y, p.x) + Vector3(31.32, 31.32, 31.32))
	var v := (p.x + p.y) * p.z
	return v - floorf(v)


static func noise3(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector3(3, 3, 3) - 2.0 * f)
	var a := lerpf(_hash(i), _hash(i + Vector3(1, 0, 0)), u.x)
	var b := lerpf(_hash(i + Vector3(0, 1, 0)), _hash(i + Vector3(1, 1, 0)), u.x)
	var c := lerpf(_hash(i + Vector3(0, 0, 1)), _hash(i + Vector3(1, 0, 1)), u.x)
	var d := lerpf(_hash(i + Vector3(0, 1, 1)), _hash(i + Vector3(1, 1, 1)), u.x)
	return lerpf(lerpf(a, b, u.y), lerpf(c, d, u.y), u.z)
