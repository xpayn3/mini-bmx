@tool
class_name LevelChunkData
extends RefCounted
## A built level's ground as the world's chunks (48 m, Terrain.SIZE): per chunk the textures a world chunk bakes
## (TerrainChunkBuilder) worked out from a baked LevelField, plus the baked light (sun + sky, LevelBake). Pure data:
## the editor's Bake button writes it into the level's .bake file, LevelTerrain turns it into meshes + materials
## (and makes it live when there is no bake).
##   land  RGBA8 land colour (sRGB) + trail weight      dirt  RGBA8 trail / clay colour + rock weight
##   tr    RGBAF metres across / -, metres along / -     tr2   RGBA8 -, -, built jump, -
##   tr3   RG8 air, corner load                          grass RGBA8 colour + grass density   gh  RF heights
##   light RG8 sun, sky (only with a bake)

const SIZE := 48.0
const NV := 97   # texels per side (0.5 m), as the world's (GrassField.SEG + 1)


## the chunk keys covering the level's grid, and the rectangle they cover: [Array[Vector2i], Rect2]
static func cover(lf: LevelField) -> Array:
	var gx1 := lf.x0 + (lf.nx - 1) * lf.step; var gz1 := lf.z0 + (lf.nz - 1) * lf.step
	var kx0 := int(ceil((lf.x0 + SIZE * 0.5) / SIZE)); var kx1 := int(floor((gx1 - SIZE * 0.5) / SIZE))
	var kz0 := int(ceil((lf.z0 + SIZE * 0.5) / SIZE)); var kz1 := int(floor((gz1 - SIZE * 0.5) / SIZE))
	var keys: Array = []
	for kz in range(kz0, kz1 + 1):
		for kx in range(kx0, kx1 + 1): keys.append(Vector2i(kx, kz))
	return [keys, Rect2(kx0 * SIZE - SIZE * 0.5, kz0 * SIZE - SIZE * 0.5, (kx1 - kx0 + 1) * SIZE, (kz1 - kz0 + 1) * SIZE)]


static func _enc(v: float) -> int:
	v = clampf(v, 0.0, 1.0)
	return roundi(255 * (v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1 / 2.4) - 0.055))


## the light grid (RG bytes at `light_step` m from the field's x0, z0) at a world point: (sun, sky)
static func _light_at(light: PackedByteArray, lnx: int, lnz: int, lstep: float, lf: LevelField, x: float, z: float) -> Vector2:
	var fx := clampf((x - lf.x0) / lstep, 0.0, lnx - 1.001); var fz := clampf((z - lf.z0) / lstep, 0.0, lnz - 1.001)
	var i := int(fx); var j := int(fz)
	var u := fx - i; var w := fz - j
	var k := (j * lnx + i) * 2
	var k2 := k + lnx * 2
	var s := lerpf(lerpf(light[k], light[k + 2], u), lerpf(light[k2], light[k2 + 2], u), w)
	var a := lerpf(lerpf(light[k + 1], light[k + 3], u), lerpf(light[k2 + 1], light[k2 + 3], u), w)
	return Vector2(s, a) / 255.0


static func build(lf: LevelField, k: Vector2i, light := PackedByteArray(), lnx := 0, lnz := 0, lstep := 1.0) -> Dictionary:
	var ox := k.x * SIZE; var oz := k.y * SIZE
	var gs := lf.step
	var hw := lf.trail_width * 0.5
	var pG := PackedByteArray(); pG.resize(NV * NV * 4)
	var pD := PackedByteArray(); pD.resize(NV * NV * 4)
	var TR := PackedFloat32Array(); TR.resize(NV * NV * 4)
	var pT2 := PackedByteArray(); pT2.resize(NV * NV * 4)
	var pA := PackedByteArray(); pA.resize(NV * NV * 2)
	var pK := PackedByteArray(); pK.resize(NV * NV * 4)
	var gh := PackedFloat32Array(); gh.resize(NV * NV)
	var pL := PackedByteArray()
	if not light.is_empty(): pL.resize(NV * NV * 2)
	var dirt := LevelField.DIRT.srgb_to_linear(); var clay := LevelField.CLAY.srgb_to_linear()
	for j in NV:
		for i in NV:
			var o := j * NV + i
			var x := ox - SIZE * 0.5 + i * 0.5; var z := oz - SIZE * 0.5 + j * 0.5
			var gi := clampi(int(round((x - lf.x0) / gs)), 1, lf.nx - 2); var gj := clampi(int(round((z - lf.z0) / gs)), 1, lf.nz - 2)
			var idx := gj * lf.nx + gi
			var h := lf.H[idx]
			gh[o] = h
			var ny := Vector3(-(lf.H[idx + 1] - lf.H[idx - 1]) / (2.0 * gs), 1.0, -(lf.H[idx + lf.nx] - lf.H[idx - lf.nx]) / (2.0 * gs)).normalized().y
			var sf := lf.S[idx]
			var dt := lf.DT[idx]
			var tw := 0.0
			if sf == 1: tw = 1.0
			elif sf == 2: tw = 0.75
			elif dt < INF: tw = 1.0 - smoothstep(hw, hw + 0.9, dt)
			var rockw := 0.0 if sf != 0 else smoothstep(0.80, 0.68, ny)
			var g := lf._land_color(x, z, ny).srgb_to_linear()
			var dc := clay if sf == 2 else dirt
			pG[o * 4] = _enc(g.r); pG[o * 4 + 1] = _enc(g.g); pG[o * 4 + 2] = _enc(g.b); pG[o * 4 + 3] = roundi(clampf(tw, 0, 1) * 255)
			pD[o * 4] = _enc(dc.r); pD[o * 4 + 1] = _enc(dc.g); pD[o * 4 + 2] = _enc(dc.b); pD[o * 4 + 3] = roundi(clampf(rockw, 0, 1) * 255)
			if dt < INF:
				TR[o * 4] = lf.TSA[idx]; TR[o * 4 + 2] = lf.TAL[idx]
			var jmk := lf.JM[idx] == 1
			pT2[o * 4 + 2] = 255 if jmk else 0
			pA[o * 2] = roundi((lf.air_at(x, z) if jmk else 0.0) * 255)
			pA[o * 2 + 1] = roundi(smoothstep(1.0 / 80.0, 1.0 / 12.0, absf(lf.TKC[idx])) * 255)
			var den := (1.0 - smoothstep(0.04, 0.4, tw)) * (1.0 - smoothstep(0.1, 0.6, rockw)) * (0.0 if jmk else 1.0)
			if den > 0.0:
				for c in lf.rocks_near(x, z):
					if c.has("top") and Vector2(c.x - x, c.z - z).length() < float(c.r) + 0.15: den = 0.0
			pK[o * 4] = pG[o * 4]; pK[o * 4 + 1] = pG[o * 4 + 1]; pK[o * 4 + 2] = pG[o * 4 + 2]; pK[o * 4 + 3] = roundi(clampf(den, 0, 1) * 255)
			if not pL.is_empty():
				var l := _light_at(light, lnx, lnz, lstep, lf, x, z)
				pL[o * 2] = roundi(l.x * 255); pL[o * 2 + 1] = roundi(l.y * 255)
	return {"land": pG, "dirt": pD, "tr": TR, "tr2": pT2, "tr3": pA, "grass": pK, "gh": gh, "light": pL}
