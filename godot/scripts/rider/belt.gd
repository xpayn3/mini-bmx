class_name Belt
extends Node3D
## The belt round the rider's waist (a child of the pelvis mesh, pelvis space: +x = front, +y = up).
## It hides where the jersey's hem meets the trousers' top: the jersey's bottom bone is locked to the hips
## (Rider.set_spine `base`), its hem sits at HEM_Y, and every style's band covers HEM_Y and the trousers' top.
##
## STYLES (look.beltStyle, Kit > Belt; colours look.belt = band, look.buckle = buckle / stripe / stitching):
##   webbing  nylon webbing (fine lengthwise weave, selvage edges), metal cam buckle
##   leather  grained leather, stitched edges, punched holes, frame buckle with prong + keeper loop
##   ratchet  ribbed ratchet strap (teeth across), chunky plastic ratchet buckle with a lever
##   elastic  wide woven waistband with two stripes, a woven label at the back, no buckle
## Each style's band texture (albedo + normal map) is baked once per style + colours and cached.

const G := preload("res://scripts/rider/rider_geo.gd")

## the hips' rounded box seen from above (superellipse |x/A|^4 + |z/B|^4 = 1, just outside it)
const A := 0.106
const B := 0.156
const HEM_Y := 0.05   # where the jersey's hem sits in pelvis space (Rider: hip = pelvis + up * HEM_Y)
const TILE := 0.06    # metres of band per texture repeat

## id -> [label, band bottom y, band top y, thickness]
const STYLES := {
	"webbing": ["Webbing", 0.034, 0.082, 0.006],
	"leather": ["Leather", 0.036, 0.081, 0.007],
	"ratchet": ["Ratchet", 0.032, 0.084, 0.008],
	"elastic": ["Waistband", 0.022, 0.086, 0.005],
}
const ORDER := ["webbing", "leather", "ratchet", "elastic"]

static var _tex_cache := {}   # "style/band/accent" -> [albedo, normal]

var style := ""
var band_col := Color("#151517")
var accent_col := Color("#9aa0a8")
var _band: MeshInstance3D
var _band_mat := StandardMaterial3D.new()
var _metal := StandardMaterial3D.new()
var _label := StandardMaterial3D.new()   # the waistband's woven label
var _parts: Array[Node3D] = []


func _init() -> void:
	name = "Belt"
	_band_mat.roughness = 0.7
	_band_mat.normal_enabled = true
	_band_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_band = MeshInstance3D.new()
	_band.name = "Band"
	_band.material_override = _band_mat
	add_child(_band)


func set_look(style_id: String, band: Color, accent: Color) -> void:
	if not STYLES.has(style_id): style_id = "webbing"
	var restyle := style_id != style
	var recolour := restyle or band != band_col or accent != accent_col
	style = style_id
	band_col = band
	accent_col = accent
	if restyle:
		var s: Array = STYLES[style]
		_band.mesh = _band_mesh(s[1], s[2], s[3])
		_build_parts()
	if recolour:
		var tex: Array = _textures(style, band, accent)
		_band_mat.albedo_texture = tex[0]
		_band_mat.normal_texture = tex[1]
		_band_mat.normal_scale = {"webbing": 0.8, "leather": 0.6, "ratchet": 1.4, "elastic": 0.7}[style]
		_band_mat.roughness = {"webbing": 0.62, "leather": 0.42, "ratchet": 0.55, "elastic": 0.8}[style]
		_band_mat.clearcoat_enabled = style == "leather"
		_band_mat.clearcoat = 0.25
		_band_mat.clearcoat_roughness = 0.5
		_metal.albedo_color = accent
		_label.albedo_color = accent
		_label.roughness = 0.85
		if style == "ratchet":   # moulded plastic
			_metal.metallic = 0.0; _metal.roughness = 0.45
		else:
			_metal.metallic = 0.9; _metal.roughness = 0.28


# ---------------------------------------------------------------- band

## a point on the superellipse round the hips at angle u (0 = front), and its outward normal
static func ring_point(u: float) -> Vector3:
	var cu := cos(u)
	var su := sin(u)
	return Vector3(A * signf(cu) * sqrt(absf(cu)), 0.0, B * signf(su) * sqrt(absf(su)))

## where the band's outside is at sideways offset z on the front (x > 0), `t` thick
static func front_x(z: float, t: float) -> float:
	var q := clampf(absf(z) / B, 0.0, 0.999)
	return A * pow(1.0 - pow(q, 4.0), 0.25) + t


static func _band_mesh(y0: float, y1: float, t: float, n := 72) -> ArrayMesh:
	var ring: Array[Vector3] = []
	for i in n:
		ring.append(ring_point(TAU * i / n))
	var outs: Array[Vector3] = []
	var arc := PackedFloat32Array([0.0])
	for i in n:
		var tang: Vector3 = (ring[(i + 1) % n] - ring[(i - 1 + n) % n]).normalized()
		var o := Vector3(tang.z, 0.0, -tang.x)
		if o.dot(ring[i]) < 0.0: o = -o
		outs.append(o)
		arc.append(arc[i] + ring[i].distance_to(ring[(i + 1) % n]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# four faces round the ring: outside, top edge, inside (a sliver, so the back of the band is never see-through), bottom edge
	for i in n + 1:
		var k := i % n
		var q: Vector3 = ring[k]
		var o: Vector3 = outs[k]
		var u := arc[i] / TILE
		var ins := q - o * 0.004
		var out := q + o * t
		for v in [[out + Vector3(0, y0, 0), o, 0.0], [out + Vector3(0, y1, 0), o, 1.0],
				[out + Vector3(0, y1, 0), Vector3.UP, 1.0], [ins + Vector3(0, y1, 0), Vector3.UP, 1.0],
				[ins + Vector3(0, y1, 0), -o, 1.0], [ins + Vector3(0, y0, 0), -o, 0.0],
				[ins + Vector3(0, y0, 0), Vector3.DOWN, 0.0], [out + Vector3(0, y0, 0), Vector3.DOWN, 0.0]]:
			st.set_normal(v[1])
			st.set_uv(Vector2(u, 1.0 - float(v[2])) if v[1] == o or v[1] == -o else Vector2(u, 0.02 if float(v[2]) > 0.5 else 0.98))
			st.add_vertex(v[0])
	for i in n:
		var a0 := i * 8
		var b0 := (i + 1) * 8
		for f in 4:
			var c0 := f * 2
			st.add_index(a0 + c0); st.add_index(b0 + c0); st.add_index(b0 + c0 + 1)
			st.add_index(a0 + c0); st.add_index(b0 + c0 + 1); st.add_index(a0 + c0 + 1)
	st.generate_tangents()
	return st.commit()


# ---------------------------------------------------------------- buckles and bits

func _box(size: Vector3, pos: Vector3, m: Material, rot := Basis(), r := 0.002) -> MeshInstance3D:
	var mi := G.inst(G.rounded_box(size.x, size.y, size.z, 1, minf(r, minf(size.x, minf(size.y, size.z)) * 0.45)), m)
	mi.transform = Transform3D(rot, pos)
	add_child(mi)
	_parts.append(mi)
	return mi


func _build_parts() -> void:
	for p in _parts:
		p.queue_free()
	_parts.clear()
	var s: Array = STYLES[style]
	var y0: float = s[1]
	var y1: float = s[2]
	var t: float = s[3]
	var ym := (y0 + y1) * 0.5
	var h := y1 - y0
	var fx := front_x(0.0, t)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.03, 0.035)
	dark.roughness = 0.8
	match style:
		"webbing":   # cam buckle: a plate, a raised hinged cam across it, the strap's end tucked under on the right
			_box(Vector3(0.006, h + 0.01, 0.058), Vector3(fx + 0.002, ym, 0.0), _metal, Basis(), 0.003)
			_box(Vector3(0.007, h * 0.42, 0.05), Vector3(fx + 0.007, ym + h * 0.12, 0.0), _metal, Basis(Vector3.BACK, 0.25), 0.003)
			_box(Vector3(0.004, 0.006, 0.062), Vector3(fx + 0.006, ym - h * 0.38, 0.0), _metal)
		"leather":   # frame buckle: open rectangle, prong across, keeper loop, punched holes to the right
			var w := 0.046
			var fh := h + 0.012
			var bar := 0.0055
			_box(Vector3(0.004, bar, w), Vector3(fx + 0.003, ym + fh * 0.5 - bar * 0.5, 0.0), _metal)
			_box(Vector3(0.004, bar, w), Vector3(fx + 0.003, ym - fh * 0.5 + bar * 0.5, 0.0), _metal)
			_box(Vector3(0.004, fh, bar), Vector3(fx + 0.003, ym, -w * 0.5 + bar * 0.5), _metal)
			_box(Vector3(0.004, fh, bar), Vector3(fx + 0.003, ym, w * 0.5 - bar * 0.5), _metal)
			_box(Vector3(0.003, 0.003, w * 0.62), Vector3(fx + 0.005, ym, 0.004), _metal)   # the prong over the strap
			# the strap's end runs on past the buckle to the right (over the band) and through the keeper
			var tip_l := 0.07
			var zc := w * 0.5 + tip_l * 0.5
			var fz := front_x(zc, t + 0.004)
			var slope := atan2(front_x(zc - 0.01, t) - front_x(zc + 0.01, t), 0.02)   # follow the band round the hip
			_box(Vector3(0.004, h * 0.9, tip_l), Vector3(fz, ym, zc), _band_mat, Basis(Vector3.UP, -slope), 0.0015)
			var kz := w * 0.5 + 0.016
			_box(Vector3(0.0035, h + 0.004, 0.011), Vector3(front_x(kz, t + 0.007), ym, kz), _band_mat, Basis(), 0.0015)
			for j in 3:   # punched holes in the strap end
				var hz := w * 0.5 + 0.032 + j * 0.016
				var hole := MeshInstance3D.new()
				var c := CylinderMesh.new()
				c.top_radius = 0.0024; c.bottom_radius = 0.0024; c.height = 0.0012; c.radial_segments = 10; c.rings = 1
				hole.mesh = c
				hole.material_override = dark
				hole.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(front_x(hz, t + 0.0062), ym, hz))
				add_child(hole)
				_parts.append(hole)
		"ratchet":   # chunky moulded ratchet buckle with a lever over the teeth
			_box(Vector3(0.014, h + 0.012, 0.072), Vector3(fx + 0.004, ym, 0.0), _metal, Basis(), 0.005)
			_box(Vector3(0.006, h * 0.55, 0.03), Vector3(fx + 0.012, ym + h * 0.05, 0.026), _metal, Basis(Vector3.BACK, 0.18), 0.0025)
			_box(Vector3(0.003, h * 0.5, 0.028), Vector3(fx + 0.0115, ym, -0.014), dark, Basis(), 0.001)   # the logo window
		"elastic":   # no buckle: a woven label sewn on at the back
			_box(Vector3(0.002, 0.026, 0.04), Vector3(-front_x(0.0, t) - 0.001, ym, 0.0), _label, Basis(), 0.0008)


# ---------------------------------------------------------------- textures

static func _textures(st: String, band: Color, accent: Color) -> Array:
	var key := "%s/%s/%s" % [st, band.to_html(false), accent.to_html(false)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var W := 256
	var H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var bump := Image.create(W, H, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	var cell := FastNoiseLite.new()
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.seed = 3
	cell.frequency = 0.16
	var thread := band.lerp(Color(0.92, 0.9, 0.84), 0.75) if band.get_luminance() < 0.5 else band.darkened(0.45)
	for y in H:
		var v := (float(y) + 0.5) / H   # 0 top .. 1 bottom
		var edge := minf(v, 1.0 - v)    # 0 at either edge
		for x in W:
			var u := (float(x) + 0.5) / W
			var ox := cos(TAU * u) * W / TAU   # noise sampled round a circle: the texture tiles with no seam
			var oz := sin(TAU * u) * W / TAU
			var c := band
			var hgt := 0.5
			match st:
				"webbing":
					var weave := 0.5 + 0.5 * sin(TAU * (v * 18.0))
					var twill := 0.5 + 0.5 * sin(TAU * (u * 64.0 + v * 18.0))
					hgt = 0.35 + 0.4 * weave + 0.25 * twill
					c = band.lerp(Color.WHITE, 0.06 * weave).darkened(0.12 * twill)
					if edge < 0.09:   # selvage: a tighter, darker edge
						hgt = 0.75 + 0.2 * sin(TAU * u * 96.0)
						c = band.darkened(0.18)
				"leather":
					var g := cell.get_noise_3d(ox, y * 0.6, oz) * 0.5 + 0.5
					var n := noise.get_noise_3d(ox * 2.0, y * 2.0, oz * 2.0) * 0.5 + 0.5
					hgt = 0.55 + 0.25 * g + 0.1 * n
					c = band.lerp(band.darkened(0.35), g * 0.35 + n * 0.12)
					if edge < 0.06:   # rolled, darker edges
						hgt = 0.3 + edge * 4.0
						c = band.darkened(0.3)
					var sv := absf(edge - 0.16)
					if sv < 0.035 and fmod(u * 22.0, 1.0) < 0.62:   # stitches along both edges
						hgt = 0.95
						c = thread
					elif sv < 0.05:
						hgt = 0.4   # the stitch groove
				"ratchet":
					var mid := edge > 0.18
					if mid:   # the teeth: a sawtooth across the strap
						var saw := fmod(u * 40.0, 1.0)
						hgt = 0.2 + 0.8 * saw
						c = band.darkened(0.25 * (1.0 - saw))
					else:
						hgt = 0.7 + 0.1 * noise.get_noise_3d(ox * 3.0, y * 3.0, oz * 3.0)
						c = band.lightened(0.04)
					if absf(edge - 0.18) < 0.02:
						hgt = 0.1
						c = band.darkened(0.3)
				"elastic":
					var rib := 0.5 + 0.5 * sin(TAU * u * 40.0)
					hgt = 0.4 + 0.5 * rib
					c = band.darkened(0.1 * rib)
					var stripe := absf(v - 0.33) < 0.06 or absf(v - 0.67) < 0.06   # two woven stripes
					if stripe:
						c = accent.darkened(0.08 * rib)
					if edge < 0.05:
						hgt = 0.85
						c = band.darkened(0.2)
			img.set_pixel(x, y, c)
			bump.set_pixel(x, y, Color(hgt, hgt, hgt))
	img.generate_mipmaps()
	bump.bump_map_to_normal_map(6.0)
	bump.generate_mipmaps()
	var out := [ImageTexture.create_from_image(img), ImageTexture.create_from_image(bump)]
	_tex_cache[key] = out
	return out
