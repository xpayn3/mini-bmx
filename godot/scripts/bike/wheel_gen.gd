class_name WheelGen
extends RefCounted
## Procedural bicycle wheel: tyre (real raised knobs), rim, laced spokes + nipples, hub with a disc-rotor
## mount, and (rear) a cassette. Built to drop into the dh.glb wheel nodes: wheel plane = local XY,
## axle = local Z, spins about Z. The brake disc is NOT part of the mesh (BikeFX.find_rotor splits the
## stock disc out into a "rotor" child first; the hub here has a mount boss that ends at that disc's face).
##
## WheelGen.build(spec) -> ArrayMesh, cached by spec. Surfaces (material resource_name):
##   "rubber" tyre (vertex colours: tan-wall option), "rim", "spokes" (vertex colours: nipples),
##   "hub", "chrome" (cassette + lockring, rear only).
##
## Stock dh.glb measurements this is fitted to (metres, wheel-local):
##   front 29" (BSD 622): tyre r 0.3743, flanges z -0.024 / +0.0385, rotor plate z -0.0466..-0.0448
##     (r 0.1015), axle ends z -0.050 / +0.0445
##   rear 27.5" (BSD 584): tyre r 0.3553, flanges z -0.040 / +0.021, rotor plate z -0.0570..-0.0552
##     (r 0.100), axle ends z -0.060 / +0.064, 7-speed cassette z 0.040..0.064 (r <= 0.053)
##   rim: 36.6 mm wide outside, 24.5 mm deep below the bead seat, hooks 5 mm above it
##   tyre: 2.5" casing 63 mm wide, widest ~24 mm above the bead

## hub layouts measured from the stock wheels. z: flange planes, rotor face (inboard face of the
## disc), axle ends, cassette span.
const HUB_FRONT := {"zl": -0.024, "zr": 0.0385, "rot": -0.0448, "endm": -0.050, "endp": 0.0445}
const HUB_REAR := {"zl": -0.040, "zr": 0.021, "rot": -0.0552, "endm": -0.060, "endp": 0.064,
	"cas0": 0.0405, "cas1": 0.0625}

const DEFAULTS := {
	"rear": false,
	"bsd_mm": 0,               # 0 -> 622 front / 584 rear
	"tyre_w_in": 2.5,
	"tread": "knobby",         # knobby | semi | slick
	"rim_depth_mm": 25.0,
	"rim_width_mm": 36.5,
	"rim_color": Color(0.17, 0.17, 0.18),
	"rim_finish": "matte",     # matte | gloss | chrome
	"rim_profile": "hooked",   # hooked | hookless | box | vee | round (see RIM_PROFILES)
	"rim_material": "alloy",   # alloy | carbon
	"pattern": "",             # tread pattern (PATTERNS); "" -> the tread's default
	"casing": "round",         # round | square (tyre shoulder shape)
	"spokes": 32,
	"lacing": 3,
	"spoke_gauge": 1,          # 0 thin | 1 normal | 2 thick
	"spoke_color": Color(0.13, 0.13, 0.14),
	"nipple_color": Color(0.62, 0.62, 0.66),
	"hub_color": Color(0.78, 0.78, 0.8),
	"hub_width_mm": 0.0,       # flange spacing; 0 -> stock (62.5 front / 61 rear)
	"cogs": [11, 12, 14, 16, 18, 21, 24],
	"cas_cols": [],            # anodized colour per cog, small cog first (cycled); [] = plain silver
	"cas_rough": 0.2,
	"tyre_color": Color(0.20, 0.20, 0.205),   # (white when the scanned rubber is used: see Rubber.use_scan)
	"sidewall": "black",       # black | tan
	"detail": 1.0,             # segment multiplier (0.5 = a cheaper wheel)
}

const TAN := Color(0.66, 0.47, 0.28)
const KNOB_H := {"knobby": 0.0055, "semi": 0.0042, "slick": 0.0}
const RIM_PROFILES := ["hooked", "hookless", "box", "vee", "round"]
const CASING_EXP := {"round": 1.0, "square": 0.62}   # superellipse exponent of the tyre profile

## tread patterns. h: knob height, pitch: row spacing round the tyre (m), rows: alternating rows of
## knobs [t offset from the crown (rad of the casing curve), half width, half length, height scale]
const PATTERNS := {
	"knobby": {"h": 0.0055, "pitch": 0.0185, "rows": [
		[[-0.18, 0.0046, 0.0046, 1.0], [0.18, 0.0046, 0.0046, 1.0], [-0.90, 0.0056, 0.0066, 1.1], [0.90, 0.0056, 0.0066, 1.1]],
		[[0.0, 0.0070, 0.0040, 1.0], [-0.54, 0.0042, 0.0050, 1.0], [0.54, 0.0042, 0.0050, 1.0], [-1.0, 0.0040, 0.0044, 0.95], [1.0, 0.0040, 0.0044, 0.95]]]},
	"paddle": {"h": 0.0058, "pitch": 0.0205, "rows": [   # wide ramped paddles down the middle (rear tyres)
		[[0.0, 0.0088, 0.0030, 1.0], [-0.93, 0.0056, 0.0068, 1.1], [0.93, 0.0056, 0.0068, 1.1]],
		[[-0.24, 0.0040, 0.0038, 0.95], [0.24, 0.0040, 0.0038, 0.95], [-0.64, 0.0040, 0.0046, 1.0], [0.64, 0.0040, 0.0046, 1.0]]]},
	"dense": {"h": 0.0056, "pitch": 0.0172, "rows": [    # three knobs across, big shoulders (wet-ish all-rounder)
		[[-0.32, 0.0040, 0.0040, 1.0], [0.0, 0.0040, 0.0040, 1.0], [0.32, 0.0040, 0.0040, 1.0], [-0.96, 0.0056, 0.0064, 1.1], [0.96, 0.0056, 0.0064, 1.1]],
		[[-0.16, 0.0044, 0.0036, 1.0], [0.16, 0.0044, 0.0036, 1.0], [-0.64, 0.0042, 0.0046, 1.0], [0.64, 0.0042, 0.0046, 1.0]]]},
	"stagger": {"h": 0.0060, "pitch": 0.0192, "rows": [  # open staggered knobs (soft / loose ground)
		[[-0.26, 0.0042, 0.0040, 1.0], [0.26, 0.0042, 0.0040, 1.0], [-0.95, 0.0050, 0.0062, 1.05], [0.95, 0.0050, 0.0062, 1.05]],
		[[0.0, 0.0050, 0.0036, 1.0], [-0.60, 0.0040, 0.0048, 1.0], [0.60, 0.0040, 0.0048, 1.0]]]},
	"block": {"h": 0.0050, "pitch": 0.0170, "rows": [    # squat square blocks (hardpack, long-lasting)
		[[-0.2, 0.0050, 0.0034, 1.0], [0.2, 0.0050, 0.0034, 1.0], [-0.92, 0.0060, 0.0056, 1.05], [0.92, 0.0060, 0.0056, 1.05]],
		[[0.0, 0.0034, 0.0050, 1.0], [-0.56, 0.0046, 0.0036, 1.0], [0.56, 0.0046, 0.0036, 1.0]]]},
	"spike": {"h": 0.0078, "pitch": 0.0260, "rows": [    # tall widely spaced spikes (mud)
		[[-0.30, 0.0034, 0.0034, 1.0], [0.30, 0.0034, 0.0034, 1.0], [-0.98, 0.0038, 0.0042, 1.0], [0.98, 0.0038, 0.0042, 1.0]],
		[[0.0, 0.0034, 0.0034, 1.0], [-0.66, 0.0036, 0.0038, 1.0], [0.66, 0.0036, 0.0038, 1.0]]]},
	"semi": {"h": 0.0042, "pitch": 0.0125, "rows": [
		[[-0.13, 0.0026, 0.0022, 0.55], [0.13, 0.0026, 0.0022, 0.55], [-0.9, 0.0046, 0.0050, 1.0], [0.9, 0.0046, 0.0050, 1.0]],
		[[0.0, 0.0026, 0.0022, 0.55], [-0.36, 0.0026, 0.0024, 0.6], [0.36, 0.0026, 0.0024, 0.6]]]},
	"slick": {"h": 0.0, "pitch": 0.02, "rows": [[], []]},
}
const SPOKE_R := [0.0011, 0.0015, 0.0020]   # tube radius by gauge (real 2 mm spoke = r 1 mm)
const FLANGE_R := 0.0285
const HOLE_R := 0.0245
const FLANGE_T := 0.0032

static var _cache := {}


## Outer radius of the tyre (m): half the bead seat diameter plus the tyre height. Tyre height is the
## nominal width * 0.997 (fits the stock 2.5" tyres: 0.3743 m on 622, 0.3553 m on 584).
static func tyre_radius(spec: Dictionary = {}) -> float:
	var s := _norm(spec)
	return float(s["bsd_mm"]) / 2000.0 + float(s["tyre_w_in"]) * 0.0254 * 0.997


## Drops the cached meshes (e.g. after changing defaults while iterating).
static func clear_cache() -> void:
	_cache.clear()


static func build(spec: Dictionary = {}) -> ArrayMesh:
	var s := _norm(spec)
	var key := var_to_str(s)
	if _cache.has(key):
		return _cache[key]
	var mesh := _build(s)
	_cache[key] = mesh
	return mesh


# ---------------------------------------------------------------- spec

static func _norm(spec: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in spec:
		s[k] = spec[k]
	var rear := bool(s["rear"])
	s["rear"] = rear
	if int(s["bsd_mm"]) <= 0:
		s["bsd_mm"] = 584 if rear else 622
	s["bsd_mm"] = int(s["bsd_mm"])
	s["tyre_w_in"] = clampf(float(s["tyre_w_in"]), 1.8, 3.0)
	s["rim_depth_mm"] = clampf(float(s["rim_depth_mm"]), 15.0, 45.0)
	s["rim_width_mm"] = clampf(float(s["rim_width_mm"]), 22.0, 42.0)
	var n := int(s["spokes"])
	n = clampi(n + (n & 1), 12, 48)
	s["spokes"] = n
	s["lacing"] = clampi(int(s["lacing"]), 0, 4)
	s["spoke_gauge"] = clampi(int(s["spoke_gauge"]), 0, 2)
	if float(s["hub_width_mm"]) <= 0.0:
		s["hub_width_mm"] = 61.0 if rear else 62.5
	s["hub_width_mm"] = float(s["hub_width_mm"])
	if not rear:
		s["cogs"] = []
	s["detail"] = clampf(float(s["detail"]), 0.25, 2.0)
	if not KNOB_H.has(s["tread"]):
		s["tread"] = "knobby"
	if not PATTERNS.has(s["pattern"]):
		s["pattern"] = s["tread"]
	if s["tread"] == "slick":
		s["pattern"] = "slick"
	if not CASING_EXP.has(s["casing"]):
		s["casing"] = "round"
	if not (s["rim_profile"] in RIM_PROFILES):
		s["rim_profile"] = "hooked"
	if s["rim_material"] != "carbon":
		s["rim_material"] = "alloy"
	return s


# ---------------------------------------------------------------- geometry buffers

class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func add(p: Vector3, nn: Vector3, t: Vector2, col: Color) -> int:
		v.append(p)
		n.append(nn)
		uv.append(t)
		c.append(col)
		return v.size() - 1

	## Quads over a row-major (rows x cols) block of vertices starting at `base`. The winding is picked
	## from the vertex normals so faces always point out (Godot: clockwise = front).
	func grid(base: int, rows: int, cols: int) -> void:
		var flip := false
		var found := false
		for i in rows - 1:
			for j in cols - 1:
				var a := base + i * cols + j
				var area := (v[a + cols + 1] - v[a]).cross(v[a + cols] - v[a + 1])
				if area.length_squared() > 1e-18:
					flip = area.dot(n[a] + n[a + cols + 1]) > 0.0
					found = true
					break
			if found:
				break
		var k := idx.size()
		idx.resize(k + (rows - 1) * (cols - 1) * 6)
		for i in rows - 1:
			for j in cols - 1:
				var a := base + i * cols + j
				var b := a + 1
				var cc := a + cols + 1
				var d := a + cols
				if flip:
					idx[k] = a; idx[k + 1] = cc; idx[k + 2] = b
					idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = cc
				else:
					idx[k] = a; idx[k + 1] = b; idx[k + 2] = cc
					idx[k + 3] = a; idx[k + 4] = cc; idx[k + 5] = d
				k += 6

	## One flat quad facing `out` (its 4 corners in order round the face, either direction).
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, out: Vector3, col: Color) -> void:
		var fn := (p2 - p0).cross(p3 - p1)
		var ccw := fn.dot(out) > 0.0
		var nn := fn.normalized() if ccw else -fn.normalized()
		var a := add(p0, nn, Vector2(0, 0), col)
		add(p1, nn, Vector2(1, 0), col)
		add(p2, nn, Vector2(1, 1), col)
		add(p3, nn, Vector2(0, 1), col)
		if ccw:
			idx.append_array(PackedInt32Array([a, a + 2, a + 1, a, a + 3, a + 2]))
		else:
			idx.append_array(PackedInt32Array([a, a + 1, a + 2, a, a + 2, a + 3]))

	func tri_count() -> int:
		return idx.size() / 3

	func commit(mesh: ArrayMesh, mat: Material, name: String) -> void:
		if idx.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var si := mesh.get_surface_count() - 1
		mesh.surface_set_material(si, mat)
		mesh.surface_set_name(si, name)


## Revolves a profile about Z. pts: Vector2(r, z), traversed so the outside is on the left of the
## direction of travel in (r, z) (i.e. from +z over the outside to -z). sharp[i]: hard edge at point i.
## cols: per-point vertex colour. Every smooth run of points becomes one grid.
static func _lathe(s: Surf, pts: PackedVector2Array, sharp: Array, cols: PackedColorArray, segs: int, uv_rep: float = 1.0) -> void:
	var np := pts.size()
	# segment normals: outward = (-dz, dr)
	var segn := PackedVector2Array()
	for i in np - 1:
		var d := pts[i + 1] - pts[i]
		segn.append(Vector2(-d.y, d.x).normalized())
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	for j in segs + 1:
		var th := TAU * float(j) / float(segs)
		cs.append(cos(th))
		sn.append(sin(th))
	# arc length for v
	var vlen := PackedFloat32Array([0.0])
	for i in range(1, np):
		vlen.append(vlen[i - 1] + pts[i].distance_to(pts[i - 1]))
	var tot := maxf(vlen[np - 1], 1e-6)
	var run_start := 0
	while run_start < np - 1:
		var run_end := run_start + 1
		while run_end < np - 1 and not sharp[run_end]:
			run_end += 1
		# run covers points run_start..run_end; normals smooth inside, segment normal at the ends
		var rows := run_end - run_start + 1
		var base := s.v.size()
		for i in range(run_start, run_end + 1):
			var nn: Vector2
			if i == run_start:
				nn = segn[i]
			elif i == run_end:
				nn = segn[i - 1]
			else:
				nn = (segn[i - 1] + segn[i]).normalized()
			var p := pts[i]
			var col := cols[i]
			var vv := vlen[i] / tot
			for j in segs + 1:
				s.add(Vector3(p.x * cs[j], p.x * sn[j], p.y), Vector3(nn.x * cs[j], nn.x * sn[j], nn.y),
					Vector2(float(j) / float(segs) * uv_rep, vv), col)
		s.grid(base, rows, segs + 1)
		run_start = run_end


## A tube from a to b (open ends), radius r, `sides` sides; optional flat cap at b.
static func _tube(s: Surf, a: Vector3, b: Vector3, r: float, sides: int, col: Color, cap_b: bool = false, r_b: float = -1.0) -> void:
	var d := (b - a).normalized()
	var u := d.cross(Vector3.FORWARD)
	if u.length_squared() < 1e-6:
		u = d.cross(Vector3.RIGHT)
	u = u.normalized()
	var w := d.cross(u)
	if r_b < 0.0:
		r_b = r
	var base := s.v.size()
	for row in 2:
		var cen := a if row == 0 else b
		var rr := r if row == 0 else r_b
		for k in sides + 1:
			var al := TAU * float(k) / float(sides)
			var o := u * cos(al) + w * sin(al)
			s.add(cen + o * rr, o, Vector2(float(k) / sides, row), col)
	s.grid(base, 2, sides + 1)
	if cap_b:
		# flat fan facing d (u x w = d, so the ring runs counter-clockwise seen from outside)
		var cb := s.add(b, d, Vector2.ZERO, col)
		for k in sides:
			var al := TAU * float(k) / float(sides)
			s.add(b + (u * cos(al) + w * sin(al)) * r_b, d, Vector2.ZERO, col)
		for k in sides:
			s.idx.append(cb)
			s.idx.append(cb + 1 + (k + 1) % sides)
			s.idx.append(cb + 1 + k)


# ---------------------------------------------------------------- materials

static func _mat(name: String, col: Color, metallic: float, rough: float, vcol: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_color = Color.WHITE if vcol else col
	m.metallic = metallic
	m.roughness = rough
	if vcol:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	return m


static var _carbon: ImageTexture

## A tileable 2x2 twill carbon weave (one tile = 4 tows each way), dark with a light sheen across each tow.
static func carbon_texture() -> ImageTexture:
	if _carbon != null:
		return _carbon
	var N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var cell := N / 4
	for y in N:
		for x in N:
			var i := x / cell
			var j := y / cell
			var warp := ((i + j) & 3) < 2          # twill: the over/under steps one tow per row
			var u := float(x % cell) / cell
			var v := float(y % cell) / cell
			var across := v if warp else u         # position across the tow
			var along := u if warp else v
			var sheen := pow(sin(across * PI), 0.6) * (0.75 + 0.25 * sin(along * PI))
			var g := 0.035 + 0.11 * sheen * (1.0 if warp else 0.72)
			img.set_pixel(x, y, Color(g, g, g * 1.04))
	img.generate_mipmaps()
	_carbon = ImageTexture.create_from_image(img)
	return _carbon


## A carbon material for any part (rims, bars). uv_scale: weave repeats over the part's UVs.
static func carbon_material(name: String, gloss: bool, uv_scale: Vector3, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name
	m.albedo_texture = carbon_texture()
	m.albedo_color = tint
	m.uv1_scale = uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.metallic = 0.15
	m.roughness = 0.35 if gloss else 0.62
	if gloss:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.04
	return m


static func _rim_mat(s: Dictionary) -> StandardMaterial3D:
	var col: Color = s["rim_color"]
	if s["rim_material"] == "carbon":
		# rim colour tints the weave a little (raw carbon stays near black)
		return carbon_material("rim", s["rim_finish"] != "matte", Vector3(150, 8, 1), Color.WHITE.lerp(Color(col.r * 3.0, col.g * 3.0, col.b * 3.0), 0.25))
	match String(s["rim_finish"]):
		"chrome":
			return _mat("rim", col, 1.0, 0.12)
		"gloss":
			var m := _mat("rim", col, 0.35, 0.18)
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.05
			return m
		_:
			return _mat("rim", col, 0.55, 0.45)


# ---------------------------------------------------------------- build

static func _build(s: Dictionary) -> ArrayMesh:
	var rear: bool = s["rear"]
	var det: float = s["detail"]
	var rb: float = float(s["bsd_mm"]) / 2000.0                  # bead seat radius
	var R := tyre_radius(s)
	var rim_d: float = float(s["rim_depth_mm"]) / 1000.0
	var rim_w: float = float(s["rim_width_mm"]) / 1000.0
	var segs := maxi(24, int(round(96.0 * det)))

	var tyre := Surf.new()
	var rim := Surf.new()
	var spokes := Surf.new()
	var hub := Surf.new()
	var chrome := Surf.new()

	_build_tyre(tyre, s, rb, R, rim_w, segs)
	_build_rim(rim, s, rb, rim_d, rim_w, maxi(24, int(round(segs * 0.84))))
	var H: Dictionary = (HUB_REAR if rear else HUB_FRONT).duplicate()
	# flange spacing about the stock centre, kept clear of the rotor mount and the cassette
	var zc: float = (H["zl"] + H["zr"]) * 0.5
	var hw: float = clampf(float(s["hub_width_mm"]) / 1000.0, 0.035, 0.09) * 0.5
	H["zl"] = maxf(zc - hw, H["rot"] + 0.009)
	H["zr"] = minf(zc + hw, (H["cas0"] if H.has("cas0") else H["endp"]) - 0.006)
	_build_hub(hub, s, H, maxi(16, int(round(32.0 * det))))
	_build_spokes(spokes, s, H, rb - rim_d, det)
	if rear and not (s["cogs"] as Array).is_empty():
		_build_cassette(chrome, s, H, det)

	var mesh := ArrayMesh.new()
	var rubber := _mat("rubber", Color.WHITE, 0.0, 0.92, true)
	Rubber.apply(rubber)   # a real compound: grain, bloom, matte with a soft sheen
	tyre.commit(mesh, rubber, "rubber")
	rim.commit(mesh, _rim_mat(s), "rim")
	spokes.commit(mesh, _mat("spokes", Color.WHITE, 0.6, 0.32, true), "spokes")
	hub.commit(mesh, _mat("hub", s["hub_color"], 0.8, 0.26), "hub")
	chrome.commit(mesh, _cas_mat(s), "chrome")
	return mesh


## the cassette's material: anodized colours ride in the vertex colours (one per cog)
static func _cas_mat(s: Dictionary) -> StandardMaterial3D:
	if (s["cas_cols"] as Array).is_empty():
		return _mat("chrome", Color(0.86, 0.86, 0.88), 1.0, 0.2)
	# anodized: a dyed oxide over the metal -- less mirror than chrome so the colour reads
	return _mat("chrome", Color.WHITE, 0.7, float(s["cas_rough"]) + 0.08, true)


## the cassette alone (cogs + lockring + a stub of freehub), for the garage's part cards
static func build_cassette(cogs: Array, cols: Array, rough: float) -> ArrayMesh:
	var s := DEFAULTS.duplicate(true)
	s["rear"] = true; s["cogs"] = cogs; s["cas_cols"] = cols; s["cas_rough"] = rough
	var chrome := Surf.new()
	_build_cassette(chrome, s, HUB_REAR, 1.5)
	var hub := Surf.new()
	var z0: float = HUB_REAR["cas0"] - 0.004
	var pts := PackedVector2Array([Vector2(0.006, z0), Vector2(0.0174, z0), Vector2(0.0174, HUB_REAR["cas1"] + 0.002), Vector2(0.006, HUB_REAR["cas1"] + 0.002)])
	var c := Color(0.12, 0.12, 0.13)
	_lathe(hub, pts, [false, true, false, true], PackedColorArray([c, c, c, c]), 32)
	var mesh := ArrayMesh.new()
	chrome.commit(mesh, _cas_mat(s), "chrome")
	hub.commit(mesh, _mat("hub", Color.WHITE, 0.6, 0.4, true), "hub")
	return mesh


# ---------------------------------------------------------------- tyre

## signed power: the superellipse helper
static func _spow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


static func _build_tyre(s: Surf, sp: Dictionary, rb: float, R: float, rim_w: float, segs: int) -> void:
	var PT: Dictionary = PATTERNS[sp["pattern"]]
	var kh: float = PT["h"]
	var e: float = CASING_EXP[sp["casing"]]                       # 1 = ellipse, < 1 = squarer shoulders
	var a: float = float(sp["tyre_w_in"]) * 0.0254 * 0.5         # casing half width
	var zb := minf(rim_w * 0.5 - 0.0035, a * 0.8)                # bead (inside the rim hooks)
	var top := R - kh                                             # casing crown
	var tb := acos(pow(zb / a, 1.0 / e))
	var sb := pow(sin(tb), e)
	var b := (top - rb) / (1.0 + sb)                              # radial semi-axis
	var rc := top - b                                             # radius of the widest point
	var t0 := -tb
	var t1 := PI + tb
	# casing point (r, z) at parameter t (t = PI/2 is the crown)
	var cas := func(t: float) -> Vector2:
		return Vector2(rc + b * _spow(sin(t), e), a * _spow(cos(t), e))
	var tcol: Color = sp["tyre_color"]
	if Rubber.use_scan(): tcol = Color.WHITE   # the scan holds the colour
	var tan_wall := String(sp["sidewall"]) == "tan"
	var np := maxi(12, int(round(26.0 * float(sp["detail"]))))
	var pts := PackedVector2Array()
	var sharp := []
	var cols := PackedColorArray()
	# a bead lip tucked under the rim hook, then the casing over the crown
	for i in np + 1:
		var t := lerpf(t0, t1, float(i) / float(np))
		pts.append(cas.call(t))
		sharp.append(false)
		var col := tcol
		if tan_wall:
			var off := absf(t - PI * 0.5)
			col = tcol.lerp(TAN, smoothstep(0.98, 1.12, off))
		cols.append(col)
	var csegs := segs if kh > 0.0 else int(segs * 1.5)
	_lathe(s, pts, sharp, cols, csegs, 6.0)
	if kh <= 0.0:
		return

	# knobs. t offset from the crown (rad of the casing ellipse), half width along the profile (m),
	# half length round the tyre (m), height scale, row phase
	var circ := TAU * top
	var pitch: float = PT["pitch"]
	var rows := int(round(circ / pitch / 2.0)) * 2
	var pattern: Array = PT["rows"]
	for q in rows:
		var th := TAU * float(q) / float(rows)
		var ct := cos(th)
		var st := sin(th)
		var tc := Vector3(-st, ct, 0.0)
		for kn in pattern[q & 1]:
			var t: float = PI * 0.5 + float(kn[0])
			var pr: Vector2 = cas.call(t)
			var t2: Vector2 = (cas.call(t + 0.002) - cas.call(t - 0.002)).normalized()   # profile tangent (r, z)
			var n2 := Vector2(-t2.y, t2.x)                                             # outward normal (r, z)
			var P := Vector3(pr.x * ct, pr.x * st, pr.y)
			var nn := Vector3(n2.x * ct, n2.x * st, n2.y)
			var tp := Vector3(t2.x * ct, t2.x * st, t2.y)
			var hw: float = kn[1]
			var hl: float = kn[2]
			var h: float = kh * float(kn[3])
			# sink the base below the curved casing so no gap shows under the knob edges
			var sink := 0.0012 + hw * hw / (2.0 * minf(a, b))
			var base := P - nn * sink
			var tip := P + nn * h
			var tk := 0.84
			var b0 := base - tp * hw - tc * hl
			var b1 := base + tp * hw - tc * hl
			var b2 := base + tp * hw + tc * hl
			var b3 := base - tp * hw + tc * hl
			var u0 := tip - tp * hw * tk - tc * hl * tk
			var u1 := tip + tp * hw * tk - tc * hl * tk
			var u2 := tip + tp * hw * tk + tc * hl * tk
			var u3 := tip - tp * hw * tk + tc * hl * tk
			s.quad(u0, u1, u2, u3, nn, tcol)
			s.quad(b0, b1, u1, u0, -tc, tcol)
			s.quad(b1, b2, u2, u1, tp, tcol)
			s.quad(b2, b3, u3, u2, tc, tcol)
			s.quad(b3, b0, u0, u3, -tp, tcol)


# ---------------------------------------------------------------- rim

static func _build_rim(s: Surf, sp: Dictionary, rb: float, D: float, W: float, segs: int) -> void:
	var h := W * 0.5
	var col := Color.WHITE
	var profile: String = sp["rim_profile"]
	# +z half, from the spoke bed centre out along the side wall (the body differs per profile) ...
	var body: Array
	match profile:
		"box":       # square box section: near-vertical walls, tight corners (Spank / Sun-style)
			body = [[-D, 0.0, false], [-D + 0.0002, h * 0.55, false], [-D + 0.0009, h * 0.86, false],
				[-D + 0.0026, h, false], [-D * 0.5, h, false]]
		"vee":       # deep V: walls taper steadily to a narrow spoke bed (Deemax / aero-style)
			body = [[-D, 0.0, false], [-D + 0.0006, h * 0.20, false], [-D * 0.80, h * 0.52, false],
				[-D * 0.48, h * 0.84, false], [-D * 0.20, h * 0.985, false]]
		"round":     # carbon tube: one big rounded curve from the bed to the wall
			body = [[-D, 0.0, false], [-D + 0.0012, h * 0.34, false], [-D * 0.78, h * 0.66, false],
				[-D * 0.55, h * 0.87, false], [-D * 0.30, h * 0.98, false]]
		_:           # hooked / hookless alloy double wall: flat bed, rounded shoulder (DT / Race Face-style)
			body = [[-D, 0.0, false], [-D + 0.0005, h * 0.17, false], [-D + 0.0017, h * 0.29, false],
				[-D + 0.0032, h * 0.36, false], [-D * 0.50, h * 0.93, false], [-D * 0.40, h * 0.985, false],
				[-D * 0.28, h, false]]
	# ... then the bead wall: a flared hook, or a thicker flat-topped hookless wall
	var top: Array
	if profile == "hooked" or profile == "box":
		top = [[0.0, h, false], [0.0042, h, false], [0.0051, h - 0.0005, false], [0.0055, h - 0.0016, false],
			[0.0051, h - 0.0028, false], [0.0040, h - 0.0034, true]]
	else:
		top = [[0.0, h, false], [0.0034, h, false], [0.0043, h - 0.0007, false], [0.0046, h - 0.0019, false],
			[0.0042, h - 0.0033, true]]
	var half: Array = body + top + [[0.0008, h - 0.0034, true], [-0.0030, h - 0.0060, false]]
	var pts := PackedVector2Array()
	var sharp := []
	var cols := PackedColorArray()
	for e in half:
		pts.append(Vector2(rb + float(e[0]), float(e[1])))
		sharp.append(e[2])
		cols.append(col)
	for i in range(half.size() - 1, -1, -1):
		var e = half[i]
		pts.append(Vector2(rb + float(e[0]), -float(e[1])))
		sharp.append(e[2])
		cols.append(col)
	# closed loop: the last point repeats the first (bed centre)
	_lathe(s, pts, sharp, cols, segs)


# ---------------------------------------------------------------- hub

static func _build_hub(s: Surf, sp: Dictionary, H: Dictionary, segs: int) -> void:
	var zl: float = H["zl"]
	var zr: float = H["zr"]
	var rot: float = H["rot"]
	var endm: float = H["endm"]
	var endp: float = H["endp"]
	var rear := H.has("cas0")
	var shell := 0.0195
	var fr := FLANGE_R
	var ft := FLANGE_T * 0.5
	var P := []   # [r, z, sharp]
	P.append([0.0, endp, true])
	P.append([0.0128, endp, true])
	P.append([0.0145, endp - 0.0008, false])
	if rear:
		var cas1: float = H["cas1"]
		P.append([0.0145, cas1 + 0.0002, true])
		P.append([0.0175, cas1 + 0.0002, true])          # freehub body under the cassette
		P.append([0.0175, zr + 0.0055, true])
		P.append([shell, zr + 0.0055, true])
	else:
		var zs := maxf(zr + ft + 0.0025, endp - 0.0025)
		P.append([0.0145, zs, true])
		P.append([shell, zs, true])
	# drive / right flange
	P.append([shell + 0.0005, zr + ft + 0.0012, false])
	P.append([fr - 0.0009, zr + ft, false])
	P.append([fr, zr + ft - 0.0008, false])
	P.append([fr, zr - ft + 0.0008, false])
	P.append([fr - 0.0009, zr - ft, false])
	P.append([shell + 0.0005, zr - ft - 0.0012, false])
	# barrel with a waist
	var span := zr - zl
	P.append([shell - 0.0018, zr - span * 0.2, false])
	P.append([shell - 0.0028, zr - span * 0.5, false])
	P.append([shell - 0.0018, zl + span * 0.2, false])
	# left (rotor side) flange
	P.append([shell + 0.0005, zl + ft + 0.0012, false])
	P.append([fr - 0.0009, zl + ft, false])
	P.append([fr, zl + ft - 0.0008, false])
	P.append([fr, zl - ft + 0.0008, false])
	P.append([fr - 0.0009, zl - ft, false])
	P.append([0.0215, zl - ft - 0.0015, false])
	# rotor mount boss up to the disc's inner face, then the end cap through the disc's centre
	P.append([0.0235, zl - ft - 0.004, true])
	P.append([0.0235, rot, true])
	P.append([0.0155, rot, true])
	P.append([0.0155, endm + 0.0008, false])
	P.append([0.0128, endm, true])
	P.append([0.0, endm, true])
	var pts := PackedVector2Array()
	var sharp := []
	var cols := PackedColorArray()
	for e in P:
		pts.append(Vector2(e[0], e[1]))
		sharp.append(e[2])
		cols.append(Color.WHITE)
	_lathe(s, pts, sharp, cols, segs)
	# six rotor bolts heads on the mount (outboard of the disc they would hide; these sit on the boss face
	# ring, visible between the disc spider arms)
	for k in 6:
		var a := TAU * (float(k) + 0.5) / 6.0
		var c := Vector3(cos(a), sin(a), 0.0) * 0.0222
		_tube(s, Vector3(c.x, c.y, rot - 0.0019), Vector3(c.x, c.y, rot - 0.0042), 0.0024, 6, Color.WHITE, true)


# ---------------------------------------------------------------- spokes

static func _build_spokes(s: Surf, sp: Dictionary, H: Dictionary, r_bed: float, det: float) -> void:
	var n: int = sp["spokes"]
	var k: int = sp["lacing"]
	var r: float = SPOKE_R[int(sp["spoke_gauge"])]
	var scol: Color = sp["spoke_color"]
	var ncol: Color = sp["nipple_color"]
	var sides := 6 if det >= 0.75 else 4
	var half := n >> 1
	var step := TAU * 2.0 / float(n)          # hole spacing on one flange
	var ft := FLANGE_T * 0.5
	var r_nip := maxf(0.0021, r + 0.0008)
	for side in 2:
		var zf: float = H["zl"] if side == 0 else H["zr"]
		var outward := -1.0 if side == 0 else 1.0
		var phase := 0.0 if side == 0 else TAU / float(n)
		for j in half:
			var phi := phase + step * float(j)
			var lead := (j & 1) == 0
			var th := phi + (step * k if lead else -step * k)
			# heads out on the leading spokes, heads in on the trailing ones
			var head_z := zf + outward * ft if lead else zf - outward * ft
			var body_z := zf - outward * ft if lead else zf + outward * ft
			var hp := Vector2(cos(phi), sin(phi)) * HOLE_R
			var head := Vector3(hp.x, hp.y, head_z)
			var start := Vector3(hp.x, hp.y, body_z)
			var hole := Vector3(cos(th) * (r_bed + 0.0022), sin(th) * (r_bed + 0.0022), 0.0)
			var dir := (hole - start).normalized()
			var ntip := hole - dir * 0.0125
			# head (a flat disc on the far face of the flange), the elbow through the flange, the spoke
			var hz := Vector3(0, 0, -outward if lead else outward) * 0.0011
			_tube(s, head, head + hz, r * 1.9, sides, scol, true)
			_tube(s, head, start - dir * 0.0004, r, sides, scol)
			_tube(s, start - Vector3(0, 0, body_z - head_z) * 0.1, ntip + dir * 0.004, r, sides, scol)
			# nipple: from inside the rim bed down the spoke, a tapered nose with a flat end
			_tube(s, hole, ntip + dir * 0.0025, r_nip, sides, ncol)
			_tube(s, ntip + dir * 0.0025, ntip, r_nip, sides, ncol, true, r_nip * 0.72)


# ---------------------------------------------------------------- cassette

static func _build_cassette(s: Surf, sp: Dictionary, H: Dictionary, det: float) -> void:
	var cogs: Array = (sp["cogs"] as Array).duplicate()
	cogs.sort()
	cogs.reverse()                          # biggest inboard (next to the spokes)
	var nc := cogs.size()
	var z0: float = H["cas0"]
	var z1: float = H["cas1"] - 0.0018      # leave room for the lockring
	var t := 0.0019
	var pitch := 0.0039
	if nc > 1:
		pitch = minf(0.0039, (z1 - z0 - t) / float(nc - 1))
		t = minf(t, pitch * 0.6)
	var r_in := 0.0178
	var cc: Array = sp.get("cas_cols", [])   # small cog first
	var col := Color.WHITE if cc.is_empty() else Color(cc[0])
	var zlast := z0
	for ci in nc:
		var teeth: int = maxi(9, int(cogs[ci]))
		var za := z0 + pitch * float(ci)
		zlast = za + t
		var cogc := Color.WHITE if cc.is_empty() else Color(cc[(nc - 1 - ci) % cc.size()])
		_cog(s, teeth, za, za + t, r_in, cogc, ci == 0)
	# lockring
	var pts := PackedVector2Array([Vector2(0.0176, zlast + 0.0016), Vector2(0.0205, zlast + 0.0016),
		Vector2(0.0212, zlast + 0.0009), Vector2(0.0212, zlast), Vector2(0.0176, zlast)])
	var cols := PackedColorArray([col, col, col, col, col])
	_lathe(s, pts, [false, true, false, true, false], cols, maxi(16, int(round(32.0 * det))))


static func _cog(s: Surf, teeth: int, za: float, zb: float, r_in: float, col: Color, inboard: bool) -> void:
	var rp := 0.0127 / (2.0 * sin(PI / float(teeth)))   # pitch radius (1/2" chain)
	var r_tip := rp + 0.0030
	var r_root := rp - 0.0039
	var fr := [-0.15, 0.15, 0.37, 0.63]
	var rr := [r_tip, r_tip, r_root, r_root]
	var outl := PackedVector2Array()
	for k in teeth:
		for f in 4:
			var a := TAU * (float(k) + float(fr[f])) / float(teeth)
			outl.append(Vector2(cos(a), sin(a)) * float(rr[f]))
	outl.append(outl[0])
	var m := outl.size()
	# faces (inner ring -> outline); the inboard face only on the biggest cog (the others face a bigger one)
	for side in (2 if inboard else 1):
		var z := zb if side == 0 else za
		var nz := Vector3(0, 0, 1.0 if side == 0 else -1.0)
		var base := s.v.size()
		for row in 2:
			for i in m:
				var o := outl[i]
				var p := o if row == 1 else o.normalized() * r_in
				s.add(Vector3(p.x, p.y, z), nz, Vector2.ZERO, col)
		s.grid(base, 2, m)
	# outer wall: per-vertex normal from the neighbouring edges
	var base2 := s.v.size()
	for row in 2:
		var z := zb if row == 0 else za
		for i in m:
			var prv := outl[(i - 1 + m - 1) % (m - 1)]
			var nxt := outl[(i + 1) % (m - 1)]
			var tg := nxt - prv
			var nn := Vector2(tg.y, -tg.x).normalized()
			if nn.dot(outl[i]) < 0.0:
				nn = -nn
			s.add(Vector3(outl[i].x, outl[i].y, z), Vector3(nn.x, nn.y, 0.0), Vector2.ZERO, col)
	s.grid(base2, 2, m)
