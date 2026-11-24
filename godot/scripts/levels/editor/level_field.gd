@tool
class_name LevelField
extends RefCounted
## A built level's ground (the level builder, scripts/levels/editor): a downhill slope with bumps, and a trail
## cut into it along the designer's spline, banked in its bends to the speed a rider gets there. Pure data: the
## same code gives the editor preview (BmxLevel) and the ride (LevelTerrain), so what you see is what you ride.
## The slope runs down along +x from x = 0 to x = length, centred on z = 0 across. bake() works out a height
## grid once; height() reads it (bilinear), so the physics is cheap.

const G := 9.81

# ---- the slope ---------------------------------------------------------------------------------------------
var length := 420.0        # m along +x
var width := 180.0         # m across (z = -width / 2 .. +width / 2)
var drop := 70.0           # m from the top (x = 0) to the bottom (x = length)
var steep_top := 0.3       # -1 steep at the bottom .. +1 steep at the top
var side_rise := 18.0      # m the edges rise above the middle (the slope is a shallow valley)
var rough := 3.0           # m of rolling bumps
var rough_scale := 45.0    # m between bumps
var noise_seed := 1
var trees := 1.0           # tree density (0 none .. 2 a forest)
var tree_clear := 4.0      # m kept clear of trees either side of the trail's edge
var tree_seed := 1
var layers := {}           # height layers on top of the land (imported world land, sculpting): see step 4
var flat := false          # flat ground (a park / jump spot): no slope, no valley; only the bumps (rough) if any

# ---- the trail ----------------------------------------------------------------------------------------------
var trail_in := PackedVector2Array()   # (x, z) points along the designer's spline, any spacing
var alts_in: Array = []    # other lines (BmxTrail after the first): [{pts: PackedVector2Array}]; the first is the main line
var ALT: Array = []        # baked other lines: [{TX, TZ, DX, DZ, TY, TK, TV, TB}]
var trail_width := 3.6     # m of ridden dirt
var blend := 6.0           # m either side over which the cut / berm meets the land
var berms := 1.0           # 0 flat bends .. 1 banked to the speed
var bank_max_deg := 35.0
var start_speed := 3.0     # m/s at the top
var smooth_len := 14.0     # m: the trail's height is the land's, smoothed this much along it
var follow := 0.0          # 0 the trail sits on the land .. 1 it is cut into it (cut / fill deeper)

# ---- baked --------------------------------------------------------------------------------------------------
const DS := 1.0            # trail sample spacing (m)
var TX := PackedFloat32Array(); var TZ := PackedFloat32Array()     # samples
var DX := PackedFloat32Array(); var DZ := PackedFloat32Array()     # unit direction
var TY := PackedFloat32Array()     # trail height (centre)
var TK := PackedFloat32Array()     # curvature (1/m, + = turning left, towards (DZ, -DX)... see _left)
var TV := PackedFloat32Array()     # speed a rider carries (m/s)
var TB := PackedFloat32Array()     # bank (rad, signed like TK)
var trail_len := 0.0

var step := 0.5            # height grid spacing (m)
var x0 := 0.0; var z0 := 0.0
var nx := 0; var nz := 0
var H := PackedFloat32Array()      # heights
var S := PackedByteArray()         # 1 = trail dirt, 2 = berm face (clay), 0 = land
var DT := PackedFloat32Array()     # per grid cell: distance to the trail's centreline (INF = far)
var TSA := PackedFloat32Array()    # per grid cell: signed metres across the trail (+ = left) where near it
var TAL := PackedFloat32Array()    # per grid cell: metres along the trail there
var TKC := PackedFloat32Array()    # per grid cell: the trail's curvature there (1/m, signed)
var JM := PackedByteArray()        # 1 = under a built structure (jump / drop): its own exact shape + fine mesh there

# ---- pieces (BmxPiece.piece() dictionaries in; resolved by bake) -------------------------------------------------
var pieces: Array = []
var structs: Array = []            # jumps + drops: {name, kind, o, dir, side, L, hs, width, wood, y0, grade, reach, rect, d?, flights?}
var rocks: Array = []              # rock colliders {x, z, r, base, top, sink, sx, sy, sc, yaw} (Terrain's dome formula)
var _rock_cells := {}
const ROCK_CELL := 2.0
var gates: Array = []              # {gate, pos, dir, span, i}
var route: Array = []              # TrailCourse route features for the demo AI / HUD alerts: {s, len, type, x, z, dx, dz, v, vmin}
var rock_runs: Array = []          # [i0, i1] trail sample ranges with a rock garden
const SIDE := 1.0                  # side batter of built dirt (m down per m out), as the playground's
var _noise: FastNoiseLite


func _init() -> void:
	_noise = FastNoiseLite.new()


## the left of a direction (x, z): turning left = towards it
static func _left(dx: float, dz: float) -> Vector2:
	return Vector2(dz, -dx)


# ---- the land ----------------------------------------------------------------------------------------------
func _prep_noise() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.frequency = 1.0 / maxf(5.0, rough_scale)


## the slope's height along it (t = x / length), straight on past either end at the end's own grade
func _profile(x: float) -> float:
	var L := maxf(10.0, length)
	var s := clampf(steep_top, -1.0, 1.0)
	var t := x / L
	if t < 0.0: return -drop * (1.0 + s) * t          # (d/dt of t + s t (1 - t) at 0 = 1 + s)
	if t > 1.0: return -drop - drop * (1.0 - s) * (t - 1.0)
	return -drop * (t + s * t * (1.0 - t))


func base(x: float, z: float) -> float:
	return land(x, z) + _grid(layers.get("sculpt", PackedFloat32Array()), x, z)


## 1 m layer grids (LevelLayers): bilinear, 0 off the grid (the imported land: clamped to its edge)
func _grid(a: PackedFloat32Array, x: float, z: float, imported := false) -> float:
	if a.is_empty(): return 0.0
	var gx0: float = layers.import_x0 if imported else layers.grid_x0
	var gz0: float = layers.import_z0 if imported else layers.grid_z0
	var gnx: int = layers.import_nx if imported else layers.grid_nx
	var gnz: int = layers.import_nz if imported else layers.grid_nz
	var fx := x - gx0; var fz := z - gz0
	if not imported and (fx < 0.0 or fz < 0.0 or fx >= gnx - 1 or fz >= gnz - 1): return 0.0
	fx = clampf(fx, 0.0, gnx - 1.001); fz = clampf(fz, 0.0, gnz - 1.001)
	var i := int(fx); var j := int(fz)
	var u := fx - i; var w := fz - j
	var k := j * gnx + i
	return lerpf(lerpf(a[k], a[k + 1], u), lerpf(a[k + gnx], a[k + gnx + 1], u), w)


## the surface painted at a point (0 none, 1 dirt, 2 sand, 3 rock)
func paint_at(x: float, z: float) -> int:
	var p: PackedByteArray = layers.get("paint", PackedByteArray())
	if p.is_empty(): return 0
	var i := int(round(x - float(layers.grid_x0))); var j := int(round(z - float(layers.grid_z0)))
	if i < 0 or j < 0 or i >= int(layers.grid_nx) or j >= int(layers.grid_nz): return 0
	return p[j * int(layers.grid_nx) + i]


## the land before sculpting: the imported world land, a flat spot, or the slope
func land(x: float, z: float) -> float:
	var imp: PackedFloat32Array = layers.get("import_h", PackedFloat32Array())
	if not imp.is_empty(): return _grid(imp, x, z, true)
	if flat: return rough * _noise.get_noise_2d(x, z)
	var hw := maxf(10.0, width * 0.5)
	var q := z / hw
	var side := side_rise * minf(q * q, 4.0 + absf(q))   # (a valley; keeps rising gently past the edges)
	return _profile(x) + side + rough * _noise.get_noise_2d(x, z)


# ---- the trail ---------------------------------------------------------------------------------------------
func _bake_trail() -> void:
	TX.clear(); TZ.clear(); DX.clear(); DZ.clear(); TY.clear(); TK.clear(); TV.clear(); TB.clear()
	trail_len = 0.0
	if trail_in.size() < 2: return
	# resample every DS m along the polyline
	var pts := trail_in
	var acc := 0.0
	var want := 0.0
	TX.append(pts[0].x); TZ.append(pts[0].y)
	for i in range(1, pts.size()):
		var a := pts[i - 1]; var b := pts[i]
		var seg := a.distance_to(b)
		if seg < 1e-5: continue
		while want + DS <= acc + seg:
			want += DS
			var p := a.lerp(b, (want - acc) / seg)
			TX.append(p.x); TZ.append(p.y)
		acc += seg
	var n := TX.size()
	if n < 3: TX.clear(); TZ.clear(); return
	trail_len = (n - 1) * DS
	DX.resize(n); DZ.resize(n); TY.resize(n); TK.resize(n); TV.resize(n); TB.resize(n)
	for i in n:
		var i0 := maxi(0, i - 1); var i1 := mini(n - 1, i + 1)
		var d := Vector2(TX[i1] - TX[i0], TZ[i1] - TZ[i0]).normalized()
		DX[i] = d.x; DZ[i] = d.y
	# curvature: the turn of the direction over +-3 m, + = left
	var raw := PackedFloat32Array(); raw.resize(n)
	for i in n:
		var i0 := maxi(0, i - 3); var i1 := mini(n - 1, i + 3)
		var a0 := atan2(DZ[i0], DX[i0]); var a1 := atan2(DZ[i1], DX[i1])
		# (x, z) angle grows towards +z; left of (dx, dz) is (dz, -dx), i.e. towards -z when heading +x: left = angle down
		raw[i] = -wrapf(a1 - a0, -PI, PI) / maxf(DS, (i1 - i0) * DS)
	TK = _smooth(raw, 4)
	# height: the land under it, smoothed along it; `follow` digs it towards a straight grade
	for i in n: TY[i] = base(TX[i], TZ[i])
	TY = _smooth(TY, int(maxf(1.0, smooth_len / DS * 0.5)))
	if follow > 0.0:
		var even := _smooth(TY, int(maxf(1.0, smooth_len * 3.0 / DS * 0.5)))
		for i in n: TY[i] = lerpf(TY[i], even[i], clampf(follow, 0.0, 1.0))
	# speed: gravity down, rolling + air drag, capped by what each bend can hold (forward), braking room (backward)
	var tb := tan(deg_to_rad(bank_max_deg))
	TV[0] = maxf(1.0, start_speed)
	for i in range(1, n):
		var v := TV[i - 1]
		var v2 := v * v + 2.0 * G * (TY[i - 1] - TY[i]) - 2.0 * (0.012 * G + 0.0045 * v * v) * DS
		var cap := sqrt(G * (0.85 + tb * berms) / maxf(absf(TK[i]), 1e-4))
		TV[i] = clampf(sqrt(maxf(v2, 1.0)), 1.0, cap)
	for i in range(n - 2, -1, -1):
		TV[i] = minf(TV[i], sqrt(TV[i + 1] * TV[i + 1] + 2.0 * 4.5 * DS))   # (a rider brakes at ~0.45 g into a bend)
	# bank: what the speed in the bend needs, from ~80 m radius, up to the max
	var bmax := deg_to_rad(bank_max_deg)
	var bk := PackedFloat32Array(); bk.resize(n)
	for i in n:
		var k := TK[i]
		var need := atan(TV[i] * TV[i] * absf(k) / G)
		var on := smoothstep(1.0 / 90.0, 1.0 / 35.0, absf(k))
		bk[i] = signf(k) * minf(need, bmax) * on * clampf(berms, 0.0, 1.5)
	TB = _smooth(bk, 4)


static func _smooth(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array(); out.resize(n)
	if n == 0: return out
	var pre := PackedFloat64Array(); pre.resize(n + 1)
	pre[0] = 0.0
	for i in n: pre[i + 1] = pre[i] + a[i]
	for i in n:
		var i0 := maxi(0, i - r); var i1 := mini(n - 1, i + r)
		out[i] = (pre[i1 + 1] - pre[i0]) / float(i1 - i0 + 1)
	return out


## the trail's own shape at signed distance s from its centre (+ = left), at sample height y, bank b
func _trail_shape(y: float, b: float, s: float) -> float:
	# outside of a left bend (k > 0) is the right (s < 0), which rises: y - tan(b) s
	return y - tan(b) * s


# ---- bake ----------------------------------------------------------------------------------------------------
## works out the trail and the height grid. grid_step 0.5 for riding, 1 for a quick editor preview.
func bake(grid_step := 0.5) -> void:
	_prep_noise()
	_bake_trail()
	_bake_alts()
	step = grid_step
	var margin := 40.0
	x0 = -margin; z0 = -width * 0.5 - 10.0
	nx = int(ceil((length + 2.0 * margin) / step)) + 1
	nz = int(ceil((width + 20.0) / step)) + 1
	H.resize(nx * nz); S.resize(nx * nz); S.fill(0); JM.resize(nx * nz); JM.fill(0)
	DT.resize(nx * nz); DT.fill(INF); TSA.resize(nx * nz); TSA.fill(0.0); TAL.resize(nx * nz); TAL.fill(0.0); TKC.resize(nx * nz); TKC.fill(0.0)
	structs = []; rocks = []; _rock_cells = {}; gates = []; route = []; rock_runs = []
	for j in nz:
		var z := z0 + j * step
		var row := j * nx
		for i in nx:
			H[row + i] = base(x0 + i * step, z)
	var n := TX.size()
	if n < 2:
		_paint_surface()
		_bake_pieces()   # (no trail: a flat park / free pieces only)
		return
	# the trail: every grid point within reach of a segment takes the nearest segment's cross section
	var hw := trail_width * 0.5
	var R := hw + blend
	var best := PackedFloat32Array(); best.resize(nx * nz); best.fill(INF)
	var cut := PackedFloat32Array(); cut.resize(nx * nz)   # the trail's shape height there
	var sd := PackedFloat32Array(); sd.resize(nx * nz)     # |s| there
	var rb := absf(tan(deg_to_rad(bank_max_deg))) * R
	var lines: Array = [{"TX": TX, "TZ": TZ, "TY": TY, "TB": TB, "TK": TK}]
	lines.append_array(ALT)
	for ln in lines:
		var LX: PackedFloat32Array = ln.TX; var LZ: PackedFloat32Array = ln.TZ; var LY: PackedFloat32Array = ln.TY
		var LB: PackedFloat32Array = ln.TB; var LK: PackedFloat32Array = ln.TK
		for k in LX.size() - 1:
			var ax := LX[k]; var az := LZ[k]
			var ex := LX[k + 1] - ax; var ez := LZ[k + 1] - az
			var l2 := ex * ex + ez * ez
			if l2 < 1e-8: continue
			var i0 := maxi(0, int(floor((minf(ax, ax + ex) - R - x0) / step)))
			var i1 := mini(nx - 1, int(ceil((maxf(ax, ax + ex) + R - x0) / step)))
			var j0 := maxi(0, int(floor((minf(az, az + ez) - R - z0) / step)))
			var j1 := mini(nz - 1, int(ceil((maxf(az, az + ez) + R - z0) / step)))
			var inv := 1.0 / sqrt(l2)
			var lx := ez * inv; var lz := -ex * inv     # left of the segment
			for j in range(j0, j1 + 1):
				var z := z0 + j * step
				var row := j * nx
				for i in range(i0, i1 + 1):
					var x := x0 + i * step
					var px := x - ax; var pz := z - az
					var a := clampf((px * ex + pz * ez) / l2, 0.0, 1.0)
					var qx := px - ex * a; var qz := pz - ez * a
					var d2 := qx * qx + qz * qz
					var idx := row + i
					if d2 >= R * R or d2 >= best[idx]: continue
					best[idx] = d2
					var s := qx * lx + qz * lz
					var y := lerpf(LY[k], LY[k + 1], a)
					var b := lerpf(LB[k], LB[k + 1], a)
					cut[idx] = _trail_shape(y, b, clampf(s, -hw, hw))
					sd[idx] = absf(s)
					DT[idx] = sqrt(d2); TSA[idx] = s; TAL[idx] = (k + a) * DS; TKC[idx] = lerpf(LK[k], LK[k + 1], a)
	for idx in nx * nz:
		if best[idx] == INF: continue
		var s := sd[idx]
		if s <= hw:
			H[idx] = cut[idx]; S[idx] = 1
		else:
			var t := (s - hw) / blend
			t = t * t * (3.0 - 2.0 * t)
			var land := H[idx]
			H[idx] = lerpf(cut[idx], land, t)
			if s < hw + 1.6 and absf(cut[idx] - land) > 0.45: S[idx] = 2   # (a built-up berm / dug cut face right beside it: bare clay)
	_paint_surface()
	_bake_pieces()


## height anywhere: a structure's own exact shape where one stands, else the grid (bilinear), the land past it
func height(x: float, z: float) -> float:
	var g := NAN
	for st in structs:
		if (st.rect as Rect2).has_point(Vector2(x, z)):
			var e := _struct_at(st, x, z)
			if is_nan(e): continue
			if st.standalone:   # (on the ground as it is: the ramp where it stands, else the ground)
				if is_nan(g): g = grid_height(x, z)
				g = maxf(g, e)
			else:
				return e
	return g if not is_nan(g) else grid_height(x, z)


## the height with a dome over every rock (Terrain.height()'s formula): what the tyres ride
func height_rocks(x: float, z: float) -> float:
	var g := height(x, z)
	for c in rocks_near(x, z):
		if not c.has("top"): continue   # (a tree trunk: a wall, not a dome)
		var dx: float = x - c.x
		var dz: float = z - c.z
		var q: float = (dx * dx + dz * dz) / (c.r * c.r)
		if q < 1.0:
			var hh: float = Terrain.dome_h(c.base, c.top, c.sink, q)
			if hh > g: g = hh
	return g


func rocks_near(x: float, z: float) -> Array:
	return _rock_cells.get(Vector2i(floori(x / ROCK_CELL), floori(z / ROCK_CELL)), [])


func jump_mask(x: float, z: float) -> float:
	for st in structs:
		if (st.rect as Rect2).has_point(Vector2(x, z)):
			var l := _local(st, x, z)   # (the whole feature, run-out included: as the world's features)
			if l.x >= 0.0 and l.x <= float(st.L) and absf(l.y) <= float(st.reach): return 1.0
	return 0.0


func grid_height(x: float, z: float) -> float:
	var fx := (x - x0) / step; var fz := (z - z0) / step
	if fx < 0.0 or fz < 0.0 or fx >= nx - 1 or fz >= nz - 1 or H.is_empty(): return base(x, z)
	var i := int(fx); var j := int(fz)
	var u := fx - i; var w := fz - j
	var k := j * nx + i
	var a := lerpf(H[k], H[k + 1], u)
	var b := lerpf(H[k + nx], H[k + nx + 1], u)
	return lerpf(a, b, w)


func surface_at(x: float, z: float) -> int:
	var i := int(round((x - x0) / step)); var j := int(round((z - z0) / step))
	if i < 0 or j < 0 or i >= nx or j >= nz or S.is_empty(): return 0
	return S[j * nx + i]


## nearest trail sample to (x, z) (-1 if there is no trail)
func nearest(x: float, z: float) -> int:
	var bi := -1
	var bd := INF
	for i in TX.size():
		var d := (TX[i] - x) * (TX[i] - x) + (TZ[i] - z) * (TZ[i] - z)
		if d < bd: bd = d; bi = i
	return bi


## (x, heading, z) standing on sample i, facing down the trail (the bike's heading: direction (cos h, -sin h))
func stand_at(i: int) -> Vector3:
	if TX.is_empty(): return Vector3(5.0, 0.0, 0.0)
	i = clampi(i, 0, TX.size() - 1)
	return Vector3(TX[i], atan2(-DZ[i], DX[i]), TZ[i])


func summary() -> String:
	if TX.is_empty(): return "no trail (add points to the BmxTrail)"
	var vmax := 0.0; var bmax := 0.0
	for i in TV.size(): vmax = maxf(vmax, TV[i]); bmax = maxf(bmax, absf(TB[i]))
	return "trail %.0f m · drop %.0f m · top speed ~%.0f km/h · steepest berm %.0f°" % [trail_len, TY[0] - TY[TY.size() - 1], vmax * 3.6, rad_to_deg(bmax)]


# ---- drawing (editor preview + the ride) ----------------------------------------------------------------------
const GRASS := Color(0.40, 0.47, 0.31)
const GRASS_DRY := Color(0.52, 0.52, 0.34)
const DIRT := Color(0.58, 0.45, 0.32)
const CLAY := Color(0.66, 0.46, 0.30)
const ROCK := Color(0.52, 0.50, 0.47)
const SAND := Color(0.86, 0.76, 0.52)


func _land_color(x: float, z: float, ny: float) -> Color:
	var c := GRASS.lerp(GRASS_DRY, clampf(0.5 + 0.9 * _noise.get_noise_2d(x * 3.1 + 500.0, z * 3.1), 0.0, 1.0) * 0.6)
	return c.lerp(ROCK, smoothstep(0.80, 0.68, ny))   # steeper than ~40 deg: bare rock


## the baked grid as a mesh, every `every`-th grid point (2 at 0.5 m = a 1 m mesh)
func ground_mesh(every := 2) -> ArrayMesh:
	var cx := int((nx - 1) / every) + 1
	var cz := int((nz - 1) / every) + 1
	var V := PackedVector3Array(); V.resize(cx * cz)
	var N := PackedVector3Array(); N.resize(cx * cz)
	var C := PackedColorArray(); C.resize(cx * cz)
	var d := step * every
	for j in cz:
		for i in cx:
			var gi := mini(i * every, nx - 1); var gj := mini(j * every, nz - 1)
			var k := gj * nx + gi
			var x := x0 + gi * step; var z := z0 + gj * step
			V[j * cx + i] = Vector3(x, H[k] - (0.14 if JM[k] == 1 else 0.0), z)   # (a structure's own fine mesh covers it)
	for j in cz:
		for i in cx:
			var k := j * cx + i
			var a := V[j * cx + maxi(0, i - 1)]; var b := V[j * cx + mini(cx - 1, i + 1)]
			var c := V[maxi(0, j - 1) * cx + i]; var e := V[mini(cz - 1, j + 1) * cx + i]
			var n := Vector3(-(b.y - a.y) / maxf(1e-4, b.x - a.x), 1.0, -(e.y - c.y) / maxf(1e-4, e.z - c.z)).normalized()
			N[k] = n
			var gi := mini(i * every, nx - 1); var gj := mini(j * every, nz - 1)
			var sf := S[gj * nx + gi]
			var col := DIRT if sf == 1 else (CLAY if sf == 2 else (SAND if sf == 3 else (ROCK if sf == 4 else _land_color(V[k].x, V[k].z, n.y))))
			C[k] = col.srgb_to_linear()
	var I := PackedInt32Array(); I.resize((cx - 1) * (cz - 1) * 6)
	var p := 0
	for j in cz - 1:
		for i in cx - 1:
			var a := j * cx + i
			I[p] = a; I[p + 1] = a + 1; I[p + 2] = a + cx
			I[p + 3] = a + 1; I[p + 4] = a + cx + 1; I[p + 5] = a + cx
			p += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## the land round the grid out to `reach` m, coarse (it sits a little low under the grid's edge so no gap shows)
func far_mesh(reach := 900.0, cell := 12.0, hole := Rect2()) -> ArrayMesh:
	var gx0 := x0 + cell; var gx1 := x0 + (nx - 1) * step - cell
	var gz0 := z0 + cell; var gz1 := z0 + (nz - 1) * step - cell
	if hole.has_area():   # (the ride's chunks cover exactly this)
		gx0 = hole.position.x + cell; gx1 = hole.end.x - cell; gz0 = hole.position.y + cell; gz1 = hole.end.y - cell
	var mx := length * 0.5
	var n := int(ceil(reach * 2.0 / cell)) + 1
	var V := PackedVector3Array(); V.resize(n * n)
	var N := PackedVector3Array(); N.resize(n * n)
	var C := PackedColorArray(); C.resize(n * n)
	for j in n:
		for i in n:
			var x := mx - reach + i * cell; var z := -reach + j * cell
			var inside := x > gx0 - cell and x < gx1 + cell and z > gz0 - cell and z < gz1 + cell
			V[j * n + i] = Vector3(x, base(x, z) - (0.8 if inside else 0.0), z)
	for j in n:
		for i in n:
			var k := j * n + i
			var a := V[j * n + maxi(0, i - 1)]; var b := V[j * n + mini(n - 1, i + 1)]
			var c := V[maxi(0, j - 1) * n + i]; var e := V[mini(n - 1, j + 1) * n + i]
			var nn := Vector3(-(b.y - a.y) / maxf(1e-4, b.x - a.x), 1.0, -(e.y - c.y) / maxf(1e-4, e.z - c.z)).normalized()
			N[k] = nn
			C[k] = _land_color(V[k].x, V[k].z, nn.y).srgb_to_linear()
	var I := PackedInt32Array()
	for j in n - 1:
		for i in n - 1:
			var x := mx - reach + (i + 0.5) * cell; var z := -reach + (j + 0.5) * cell
			if x > gx0 and x < gx1 and z > gz0 and z < gz1: continue   # (the fine grid is there)
			var a := j * n + i
			I.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_COLOR] = C; arr[Mesh.ARRAY_INDEX] = I
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## the trail as a TrailCourse (2 m steps), so what reads the world's trail works on a level too: the demo AI (F2),
## the follow test rider, the trail camera, HUD bend alerts, "back on the trail"
func to_course() -> TrailCourse:
	var tc := TrailCourse.new()
	var every := int(round(TrailCourse.STEP / DS))
	var m := int((TX.size() - 1) / every) + 1 if TX.size() > 1 else 0
	if m < 2: return tc
	for a in [tc.X, tc.Z]: a.resize(m)
	for a in [tc.TX, tc.TZ, tc.KAP, tc.W, tc.BT, tc.E, tc.RD, tc.RK, tc.LN, tc.RO, tc.ROS, tc.VA]: a.resize(m)
	tc.KD.resize(m)
	for q in m:
		var i := mini(q * every, TX.size() - 1)
		tc.X[q] = TX[i]; tc.Z[q] = TZ[i]
		tc.TX[q] = DX[i]; tc.TZ[q] = DZ[i]
		tc.KAP[q] = -TK[i]               # (the course's bends: + = right)
		tc.W[q] = trail_width * 0.5
		tc.BT[q] = -tan(TB[i])
		tc.E[q] = TY[i]
		tc.VA[q] = TV[i]
		tc.KD[q] = TrailCourse.ROAD
	for rr in rock_runs:
		for q in range(int(rr[0] / every), mini(m, int(rr[1] / every) + 1)): tc.KD[q] = TrailCourse.ROCKS
	tc.KD[0] = TrailCourse.START; tc.KD[m - 1] = TrailCourse.FINISH
	tc.n = m
	tc.length = (m - 1) * TrailCourse.STEP
	return tc


# ---- pieces --------------------------------------------------------------------------------------------------
static func _side(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)   # (right of the way it is ridden: the playground ramps' side())


func _local(st: Dictionary, x: float, z: float) -> Vector2:
	var q := Vector2(x, z) - (st.o as Vector2)
	return Vector2(q.dot(st.dir), q.dot(st.side))


## a structure's height over its plane at (u along, v across); 0 off it
func _at_local(st: Dictionary, uu: float, vv: float) -> float:
	if uu <= 0.0 or uu >= float(st.L): return 0.0
	var hh := JumpDesign.sample(st.hs, uu)
	var hw := float(st.width) * 0.5
	if st.wood: return hh if absf(vv) <= hw else 0.0
	return maxf(0.0, hh - maxf(0.0, absf(vv) - hw) * SIDE)


## the exact ground on a structure's levelled footprint (NAN outside it: the grid there)
func _struct_at(st: Dictionary, x: float, z: float) -> float:
	var l := _local(st, x, z)
	if l.x < -0.5 or l.x > float(st.L) + 0.5 or absf(l.y) > float(st.reach): return NAN
	var jh := _at_local(st, l.x, l.y)
	if st.standalone and jh <= 0.002: return NAN
	return float(st.y0) + float(st.grade) * l.x + jh


## where a piece goes: on the trail (follow) or where it was put; -> [pos, dir, trail index]
func _place(p: Dictionary) -> Array:
	var pos: Vector2 = p.pos
	var dir: Vector2 = p.dir
	var i := nearest(pos.x, pos.y)
	var v := TV[i] if i >= 0 else 0.0
	if p.follow and i >= 0:
		pos = Vector2(TX[i], TZ[i]); dir = Vector2(DX[i], DZ[i])
		var bd := Vector2(TX[i], TZ[i]).distance_to(p.pos)
		for a in ALT:   # (an alternative line nearer: on it; it has no main-line index for the AI / timing)
			var ai := _nearest_in(a.TX, a.TZ, p.pos.x, p.pos.y)
			if ai >= 0 and Vector2(a.TX[ai], a.TZ[ai]).distance_to(p.pos) < bd:
				bd = Vector2(a.TX[ai], a.TZ[ai]).distance_to(p.pos)
				pos = Vector2(a.TX[ai], a.TZ[ai]); dir = Vector2(a.DX[ai], a.DZ[ai])
				i = -1; v = a.TV[ai]
	return [pos, dir, i, v]


func _speed_at(i: int, p: Dictionary, line_v := 0.0) -> float:
	if p.get("auto_v", false) and line_v > 0.0: return clampf(line_v * float(p.get("v_k", 1.0)), 4.0, 30.0)
	if p.get("auto_v", false) and i >= 0: return clampf(TV[i] * float(p.get("v_k", 1.0)), 4.0, 30.0)
	return float(p.get("v", 12.0))


func _bake_pieces() -> void:
	for p in pieces:
		match str(p.get("kind", "")):
			"jump": _add_jump(p)
			"line": _add_line(p)
			"drop": _add_drop(p)
			"rocks": _add_rocks(p)
			"gate": _add_gate(p)
	route.sort_custom(func(a, b): return a.s < b.s)
	_bake_trees()


## a structure's frame from where it starts, levelled to the ground's grade along it, stamped into the grid
func _structure(p: Dictionary, start: Vector2, dir: Vector2, hs: PackedFloat32Array, width_m: float, wood: bool, trial := false) -> Dictionary:
	var L := (hs.size() - 1) * JumpDesign.DS
	var st := {"name": p.get("name", ""), "kind": p.kind, "o": start, "dir": dir, "side": _side(dir), "L": L, "hs": hs,
		"width": width_m, "wood": wood, "standalone": bool(p.get("standalone", false))}
	var top := 0.0
	for hh in hs: top = maxf(top, hh)
	st["reach"] = width_m * 0.5 + (0.0 if wood else top * SIDE) + 0.3
	var y0 := grid_height(start.x, start.y)
	var e := start + dir * L
	st["y0"] = y0
	st["grade"] = (grid_height(e.x, e.y) - y0) / maxf(1.0, L)
	var R := float(st.reach) + 3.0
	var sd: Vector2 = st.side
	var a := start - sd * R - dir * 4.0
	var rect := Rect2(a, Vector2.ZERO)
	for c in [start + sd * R - dir * 4.0, start - sd * R + dir * (L + 4.0), start + sd * R + dir * (L + 4.0)]: rect = rect.expand(c)
	st["rect"] = rect.grow(0.5)
	if trial or st.standalone:   # (a trial fit: nothing stamped; standalone: a ramp on the ground, the ground left as it is)
		if not trial: structs.append(st)
		return st
	# the grid: levelled to the plane under the footprint (blended out over 3-4 m), the shape on top
	var i0 := maxi(0, int(floor((rect.position.x - x0) / step))); var i1 := mini(nx - 1, int(ceil((rect.end.x - x0) / step)))
	var j0 := maxi(0, int(floor((rect.position.y - z0) / step))); var j1 := mini(nz - 1, int(ceil((rect.end.y - z0) / step)))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var x := x0 + i * step; var z := z0 + j * step
			var l := _local(st, x, z)
			var fu := smoothstep(-4.0, 0.0, l.x) * (1.0 - smoothstep(L, L + 4.0, l.x))
			var fv := 1.0 - smoothstep(float(st.reach), float(st.reach) + 3.0, absf(l.y))
			var w := fu * fv
			if w <= 0.0: continue
			var idx := j * nx + i
			var plane := y0 + float(st.grade) * l.x
			H[idx] = lerpf(H[idx], plane, w)
			var jh := _at_local(st, l.x, l.y)
			if jh > 0.002:
				H[idx] = plane + jh; S[idx] = 1
			if l.x > -0.4 and l.x < L + 0.4 and absf(l.y) < float(st.reach): JM[idx] = 1
	structs.append(st)
	return st


func _add_jump(p: Dictionary) -> void:
	var pl := _place(p)
	var lip: Vector2 = pl[0]; var dir: Vector2 = pl[1]; var i: int = pl[2]
	var prm: Dictionary = (p.prm as Dictionary).duplicate()
	if p.get("auto_v", false): prm["v"] = _speed_at(i, p, float(pl[3]))
	var d := JumpDesign.build(prm)
	var start := lip - dir * float(d.lip_u)
	var wood := str(prm.get("build", "dirt")) == "wood"
	var wdt := float(prm.get("width", 3.0))
	# JumpDesign sizes the deck / gap and the landing for flat ground. On a grade the ground falls away (or rises)
	# under the flight: fit what was left on auto to the flight over THIS ground (a trial structure, not stamped)
	var auto_len := float(prm.get("deck" if str(prm.kind) == "table" else "gap", 0.0)) <= 0.0 and str(prm.kind) != "kicker"
	var auto_ang := float(prm.get("land_deg", 0.0)) <= 0.0 and str(prm.kind) != "kicker"
	if auto_len or auto_ang:
		var key := "deck" if str(prm.kind) == "table" else "gap"
		for round in 2:
			if auto_len:   # bisection: a longer deck / gap moves the aim point further, the flight stays where it is
				var lo := 0.5; var hi := 45.0
				for it in 16:
					var mid := (lo + hi) * 0.5
					prm[key] = mid
					d = JumpDesign.build(prm)
					start = lip - dir * float(d.lip_u)
					var fl := _flight(_trial(p, start, dir, d, wdt, wood), float(prm.v))
					var u_aim := float(d.land0) + clampf(float(prm.get("aim", 0.2)), 0.0, 1.0) * (float(d.land1) - float(d.land0))
					var u_got := float(d.lip_u) + float(fl.dist)
					if not is_finite(u_got) or u_got > u_aim: lo = mid
					else: hi = mid
				prm[key] = (lo + hi) * 0.5
				d = JumpDesign.build(prm)
				start = lip - dir * float(d.lip_u)
			if auto_ang and round == 0:   # the landing's angle: the flight's there, relative to the plane it sits on
				var tr := _trial(p, start, dir, d, wdt, wood)
				var fl := _flight(tr, float(prm.v))
				if fl.has("angle"):
					prm["land_deg"] = clampf(float(fl.angle) - JumpDesign.LAND_SOFT + rad_to_deg(atan(float(tr.grade))), 12.0, JumpDesign.LAND_MAX_DEG)
					d = JumpDesign.build(prm)
					start = lip - dir * float(d.lip_u)
	var st := _structure(p, start, dir, d.h, wdt, wood)
	st["d"] = d
	st["v"] = float(prm.v)
	st["lip"] = lip
	st["flights"] = [_flight(st, float(prm.v) * 0.85), _flight(st, float(prm.v)), _flight(st, float(prm.v) * 1.15)]
	var kind := str(prm.get("kind", "table"))
	var si := nearest(start.x, start.y)
	if si >= 0:
		route.append({"s": si * DS, "len": float(st.L), "type": kind if kind != "gap" else "gap", "x": start.x, "z": start.y,
			"dx": dir.x, "dz": dir.y, "v": float(prm.v), "vmin": float(prm.v) * 0.95 if kind != "kicker" else 0.0})


func _trial(p: Dictionary, start: Vector2, dir: Vector2, d: Dictionary, wdt: float, wood: bool) -> Dictionary:
	var tr := _structure(p, start, dir, d.h, wdt, wood, true)
	tr["d"] = d
	return tr


## a rider at run-in speed vr over a jump on its real ground (the plane's grade and what is past it): the path flown
## and where / how hard he lands. Point mass, no pop, no drag (like JumpDesign.predict)
func _flight(st: Dictionary, vr: float) -> Dictionary:
	var d: Dictionary = st.d
	var H0 := float(d.lip_h)
	var lu := float(d.lip_u)
	var grade := float(st.grade)
	var a := atan(tan(deg_to_rad(float(d.lip_deg))) + grade)
	var v2 := vr * vr - 2.0 * G * H0 - JumpDesign.FACE_LOSS * H0 * vr - 2.0 * G * grade * lu
	var vl := sqrt(maxf(0.1, v2))
	var dir: Vector2 = st.dir
	var p0: Vector2 = (st.o as Vector2) + dir * lu
	var y0 := float(st.y0) + grade * lu + H0
	var vx := vl * cos(a); var vy := vl * sin(a)
	var pts := PackedVector3Array()
	var t := 0.0
	var dt := 0.01
	while t < 6.0:
		t += dt
		var q := p0 + dir * (vx * t)
		var y := y0 + vy * t - 0.5 * G * t * t
		pts.append(Vector3(q.x, y, q.y))
		var g := height(q.x, q.y)
		if not structs.has(st):
			var e := _struct_at(st, q.x, q.y)
			if not is_nan(e): g = maxf(g, e) if st.standalone else e
		if vx * t > 0.3 and y <= g:
			var l := _local(st, q.x, q.y)
			var spot := "past it"
			if str(d.kind) != "kicker":
				if l.x < float(d.land0) - 0.05: spot = "deck" if str(d.kind) == "table" else "gap"
				elif l.x <= float(d.land1): spot = "landing"
			# speed into the ground, square to it -> equivalent fall height
			var gx := (height(q.x + 0.1, q.y) - height(q.x - 0.1, q.y)) / 0.2
			var gz := (height(q.x, q.y + 0.1) - height(q.x, q.y - 0.1)) / 0.2
			var n := Vector3(-gx, 1.0, -gz).normalized()
			var vel := Vector3(dir.x * vx, vy - G * t, dir.y * vx)
			var vn := -vel.dot(n)
			return {"v": vr, "pts": pts, "dist": vx * t, "air": t, "spot": spot, "efh": vn * vn / (2.0 * G),
				"angle": rad_to_deg(atan2(G * t - vy, vx))}
	return {"v": vr, "pts": pts, "dist": INF, "air": t, "spot": "?", "efh": INF}


func _add_drop(p: Dictionary) -> void:
	var pl := _place(p)
	var start: Vector2 = pl[0]; var dir: Vector2 = pl[1]; var i: int = pl[2]
	var v := _speed_at(i, p, float(pl[3]))
	var hh := float(p.height)
	var hs := PackedFloat32Array()
	var ds := JumpDesign.DS
	# the climb onto the deck (eased), the deck
	var up := hh / maxf(0.02, float(p.climb))
	var u := 0.0
	while u < up:
		var t := u / up
		hs.append(hh * t * t * (3.0 - 2.0 * t)); u += ds
	var deck_n := int(float(p.deck) / ds)
	for k in deck_n: hs.append(hh)
	# the edge: a square step, then the face following a flight at v (slope g x / v^2, capped), the bottom bend
	var edge := clampf(float(p.edge), 0.0, hh * 0.8)
	var y := hh - edge
	hs.append(y)
	var smax := tan(deg_to_rad(float(p.face_deg)))
	var vb := sqrt(v * v + 2.0 * G * hh)
	var rb := vb * vb / (2.5 * G)
	var x := 0.0; var sl := 0.0; var bending := false
	var guard := 0
	while y > 0.0 and guard < 8000:
		guard += 1
		x += ds
		var a := atan(sl)
		if not bending and y <= rb * (1.0 - cos(a)) and sl > 0.0: bending = true
		if bending:
			a = maxf(0.0, a - ds / (rb * maxf(0.3, cos(a)))); sl = tan(a)
			if sl < 1e-3: break
		else:
			sl = minf(smax, G * x / (v * v))
		y -= sl * ds
		hs.append(maxf(0.0, y))
	hs.append(0.0); hs.append(0.0)
	var st := _structure(p, start, dir, hs, float(p.width), str(p.get("build", "dirt")) == "wood")
	st["v"] = v
	if i >= 0:
		route.append({"s": i * DS, "len": float(st.L), "type": "drop", "x": start.x, "z": start.y, "dx": dir.x, "dz": dir.y, "v": v, "vmin": 0.0})


func _add_rocks(p: Dictionary) -> void:
	var pl := _place(p)
	var i0: int = pl[2]
	var rng := RandomNumberGenerator.new(); rng.seed = int(p.get("seed", 1)) * 7919 + 17
	var L := float(p.length)
	var hw := trail_width * 0.5 + float(p.get("spread", 0.0))
	var smin := float(p.size_min); var smax := maxf(smin, float(p.size_max))
	var per := 4.0 * float(p.get("density", 1.0))
	var start: Vector2 = pl[0]; var dir: Vector2 = pl[1]
	for k in int(L / 2.0):
		var along := k * 2.0
		var c: Vector2; var dd: Vector2
		if p.follow and i0 >= 0 and TX.size() > 0:
			var ti := mini(i0 + int(along / DS), TX.size() - 1)
			c = Vector2(TX[ti], TZ[ti]); dd = Vector2(DX[ti], DZ[ti])
		else:
			c = start + dir * along; dd = dir
		var sd := _side(dd)
		var line_a := sin(k * 0.23) * hw * 0.55
		var cnt := int(per) + (1 if rng.randf() < per - int(per) else 0)
		for q in cnt:
			var a := (rng.randf() * 2.0 - 1.0) * (hw - 0.15)
			var du := rng.randf() * 2.0
			if p.get("clean", true) and absf(a - line_a) < 0.45 and rng.randf() < 0.8: continue
			var r1 := rng.randf()
			var sc := lerpf(smin, smax, r1 * r1)
			var sx := sc * (1.0 + rng.randf() * 0.5); var sy := sc * (0.5 + rng.randf() * 0.35)
			var w := c + dd * du + sd * a
			var base_h := height(w.x, w.y)
			var rk := {"x": w.x, "z": w.y, "r": (sx + sc) * 0.45, "base": base_h, "top": base_h - sc * 0.3 + sy * 0.9, "sink": sc * 0.3,
				"sx": sx, "sy": sy, "sc": sc, "yaw": rng.randf() * TAU}
			rocks.append(rk)
			for gx in range(floori((w.x - rk.r) / ROCK_CELL), floori((w.x + rk.r) / ROCK_CELL) + 1):
				for gz in range(floori((w.y - rk.r) / ROCK_CELL), floori((w.y + rk.r) / ROCK_CELL) + 1):
					var key := Vector2i(gx, gz)
					if not _rock_cells.has(key): _rock_cells[key] = []
					_rock_cells[key].append(rk)
	if i0 >= 0: rock_runs.append([i0, mini(TX.size() - 1, i0 + int(L / DS))])


func _add_gate(p: Dictionary) -> void:
	var pl := _place(p)
	gates.append({"gate": str(p.gate), "pos": pl[0], "dir": pl[1], "i": pl[2], "span": float(p.span), "name": p.get("name", "")})


## the start: a start gate's spot if there is one, else the trail's first metres
func start_stand() -> Vector3:
	for g in gates:
		if g.gate == "start":
			if g.i >= 0: return stand_at(maxi(0, g.i - 3))   # (3 m behind its line: riding through it starts the clock)
			var b: Vector2 = g.pos - g.dir * 3.0
			return Vector3(b.x, atan2(-g.dir.y, g.dir.x), b.y)
	return stand_at(2)


## one line per jump for the editor: design speed, where 85 / 100 / 115 % land
func jump_report() -> String:
	var out := []
	for st in structs:
		if not st.has("flights"): continue
		var f: Array = st.flights
		var parts := []
		for fl in f: parts.append("%s %.1f m (EFH %.1f)" % [fl.spot, fl.dist, fl.efh])
		out.append("%s · %.0f km/h · %s\n   85%%: %s\n  100%%: %s\n  115%%: %s" % [st.name, float(st.v) * 3.6, JumpDesign.describe(st.d), parts[0], parts[1], parts[2]])
	return "\n".join(out)


## a structure's own mesh (0.1 m along where it isn't flat, 0.25 m across): dirt (dirt / clay on the faces) or wood
## (plank stripes on top, plywood sides straight down)
func struct_mesh(st: Dictionary) -> ArrayMesh:
	var L := float(st.L)
	var us := PackedFloat64Array()
	var uu := -0.5
	while uu < L + 0.5:
		us.append(uu)
		var busy := JumpDesign.sample(st.hs, uu) > 1e-4 or JumpDesign.sample(st.hs, uu + 0.3) > 1e-4 or JumpDesign.sample(st.hs, uu - 0.3) > 1e-4
		uu += 0.1 if busy else 0.5
	us.append(L + 0.5)
	var R := float(st.reach) + 0.3
	var vs := PackedFloat64Array()
	var vv := -R
	while vv < R:
		vs.append(vv); vv += 0.25
	vs.append(R)
	var o: Vector2 = st.o; var dx: Vector2 = st.dir; var sd: Vector2 = st.side
	var nu := us.size(); var nv := vs.size()
	var V := PackedVector3Array(); V.resize(nu * nv)
	var C := PackedColorArray(); C.resize(nu * nv)
	var wood: bool = st.wood
	var hw := float(st.width) * 0.5
	var plank := Color(0.55, 0.40, 0.24).srgb_to_linear(); var plank2 := Color(0.47, 0.34, 0.2).srgb_to_linear()
	for j in nv:
		for i in nu:
			var p := o + dx * us[i] + sd * vs[j]
			var jh := _at_local(st, us[i], vs[j])
			var yy := float(st.y0) + float(st.grade) * us[i] + jh
			if jh <= 0.002: yy = grid_height(p.x, p.y) - (0.25 if st.standalone else 0.0)   # (the edge: the ground round it; standalone: tucked under it)
			V[j * nu + i] = Vector3(p.x, yy + (0.004 if jh > 0.002 else 0.0), p.y)
			var col := DIRT
			if wood and jh > 0.002 and absf(vs[j]) <= hw: C[j * nu + i] = plank if int(us[i] / 0.16) % 2 == 0 else plank2; continue
			if jh > 0.002:
				var slope := absf(JumpDesign.sample(st.hs, us[i] + 0.05) - JumpDesign.sample(st.hs, us[i] - 0.05)) / 0.1
				col = DIRT.lerp(CLAY, clampf(slope * 0.8, 0.0, 0.6))
				if absf(vs[j]) > hw: col = CLAY
			C[j * nu + i] = col.srgb_to_linear()
	var I := PackedInt32Array()
	for j in nv - 1:
		for i in nu - 1:
			var a := j * nu + i
			I.append_array([a, a + 1, a + nu, a + 1, a + nu + 1, a + nu])   # (clockwise from above: Godot's front)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in I:
		st2.set_color(C[k]); st2.add_vertex(V[k])
	if wood:   # plywood sides
		var ply := Color(0.72, 0.52, 0.33).srgb_to_linear()
		for sgn: float in [-1.0, 1.0]:
			var off := sd * (sgn * (hw + 0.01))
			var i := 0
			var hs: PackedFloat32Array = st.hs
			while i < hs.size() - 2:
				var u0 := i * JumpDesign.DS; var u1 := (i + 2) * JumpDesign.DS
				if hs[i] > 0.01 or hs[i + 2] > 0.01:
					var a0 := o + dx * u0 + off; var a1 := o + dx * u1 + off
					var g0 := float(st.y0) + float(st.grade) * u0; var g1 := float(st.y0) + float(st.grade) * u1
					var q := [Vector3(a0.x, g0 + hs[i], a0.y), Vector3(a1.x, g1 + hs[i + 2], a1.y), Vector3(a1.x, g1 - 0.2, a1.y), Vector3(a0.x, g0 - 0.2, a0.y)]
					for k in [0, 1, 2, 0, 2, 3]:
						st2.set_color(ply); st2.add_vertex(q[k])
				i += 2
	st2.generate_normals()
	return st2.commit()


# ---- trees -------------------------------------------------------------------------------------------------------
var tree_list: Array = []          # {x, z, h, kind ("pine" | "leafy" | "bush"), sc, py, yaw, ci}
const TREE_CELL := 9.0


## trees on a jittered grid over the land: none on / near the trail, on structures, rocks, gates, steep rock faces;
## pines more on the steep and high, leafy trees lower, bushes at the forest's edge. Trunks are colliders (as the world's)
func _bake_trees() -> void:
	tree_list = []
	if trees <= 0.0: return
	var rng := RandomNumberGenerator.new(); rng.seed = tree_seed * 104729 + noise_seed
	var cell := TREE_CELL / sqrt(maxf(0.05, trees))
	var xe := x0 + (nx - 1) * step; var ze := z0 + (nz - 1) * step
	var hw := trail_width * 0.5
	var z := z0 + cell * 0.5
	while z < ze:
		var x := x0 + cell * 0.5
		while x < xe:
			var px := x + (rng.randf() - 0.5) * cell * 0.9
			var pz := z + (rng.randf() - 0.5) * cell * 0.9
			x += cell
			var clump := 0.5 + 0.5 * _noise.get_noise_2d(px * 0.6 + 900.0, pz * 0.6)   # (woods and clearings)
			if rng.randf() > clump * 1.3: continue
			var i := clampi(int(round((px - x0) / step)), 0, nx - 1); var j := clampi(int(round((pz - z0) / step)), 0, nz - 1)
			var dt := DT[j * nx + i]
			var edge := dt - hw
			if edge < tree_clear: continue
			if JM[j * nx + i] == 1 or S[j * nx + i] != 0: continue
			if _near_piece(px, pz, 6.0): continue
			var h := grid_height(px, pz)
			var gx := grid_height(px + 1.0, pz) - grid_height(px - 1.0, pz)
			var gz := grid_height(px, pz + 1.0) - grid_height(px, pz - 1.0)
			var steep := sqrt(gx * gx + gz * gz) * 0.5
			if steep > 0.9: continue
			var sc := (0.7 + rng.randf() * 0.8) * 1.4   # (the world's sizes: TerrainChunkBuilder TREE_K)
			var kind := "pine" if rng.randf() < 0.45 + steep * 0.6 else "leafy"
			if edge < tree_clear + 3.0 and rng.randf() < 0.6: kind = "bush"
			tree_list.append({"x": px, "z": pz, "h": h, "kind": kind, "sc": sc, "py": sc * (1.5 + rng.randf() * 0.7 + pow(rng.randf(), 4.0) * 0.9),
				"yaw": rng.randf() * TAU, "ci": rng.randi() % 3})
		z += cell
	_index_colliders()


func _near_piece(x: float, z: float, r: float) -> bool:
	var p := Vector2(x, z)
	for st in structs:
		if (st.rect as Rect2).grow(r).has_point(p): return true
	for g in gates:
		if (g.pos as Vector2).distance_to(p) < float(g.span) * 0.5 + r: return true
	for c in rocks:
		if Vector2(c.x, c.z).distance_to(p) < r * 0.5: return true
	return false


## the collider lookup (2 m cells): every rock (a dome) and every tree trunk (a wall, as the world's)
func _index_colliders() -> void:
	_rock_cells = {}
	var all: Array = rocks.duplicate()
	for t in tree_list:
		if t.kind != "bush": all.append({"x": t.x, "z": t.z, "r": 0.16 * float(t.sc) + 0.02, "ceil": float(t.h) + 6.0 * float(t.sc)})
	for c in all:
		for gx in range(floori((c.x - c.r) / ROCK_CELL), floori((c.x + c.r) / ROCK_CELL) + 1):
			for gz in range(floori((c.z - c.r) / ROCK_CELL), floori((c.z + c.r) / ROCK_CELL) + 1):
				var key := Vector2i(gx, gz)
				if not _rock_cells.has(key): _rock_cells[key] = []
				_rock_cells[key].append(c)


## a jump's air (riders fly over it: the worn lines stop there): from the lip to where the design speed lands
func air_at(x: float, z: float) -> float:
	for st in structs:
		if not st.has("d") or not (st.rect as Rect2).has_point(Vector2(x, z)): continue
		var l := _local(st, x, z)
		var d: Dictionary = st.d
		var fd := float(st.flights[1].dist)
		var u_end: float = float(d.lip_u) + fd if is_finite(fd) else float(d.land1)
		return smoothstep(float(d.lip_u) - 0.3, float(d.lip_u) + 0.5, l.x) * (1.0 - smoothstep(u_end - 2.0, u_end + 0.5, l.x))
	return 0.0


# ---- the bake file -----------------------------------------------------------------------------------------------
const STATE_KEYS := ["length", "width", "drop", "steep_top", "side_rise", "rough", "rough_scale", "noise_seed", "flat",
	"trees", "tree_clear", "tree_seed", "trail_width", "blend", "berms", "bank_max_deg", "start_speed", "smooth_len", "follow",
	"TX", "TZ", "DX", "DZ", "TY", "TK", "TV", "TB", "trail_len", "step", "x0", "z0", "nx", "nz", "H", "S", "JM", "DT", "TSA",
	"TAL", "TKC", "ALT", "structs", "rocks", "gates", "route", "rock_runs", "tree_list", "layers"]


## everything bake() worked out, as plain data (LevelBake writes it into the level's .bake file)
func state() -> Dictionary:
	var out := {}
	for k in STATE_KEYS: out[k] = get(k)
	return out


## back from state(): no baking needed
func load_state(d: Dictionary) -> void:
	for k in STATE_KEYS:
		if d.has(k): set(k, d[k])
	_prep_noise()
	_index_colliders()


## painted surfaces into S (off the trail): 1 dirt, 3 sand, 4 rock
func _paint_surface() -> void:
	var p: PackedByteArray = layers.get("paint", PackedByteArray())
	if p.is_empty(): return
	for j in nz:
		for i in nx:
			var idx := j * nx + i
			if S[idx] != 0: continue
			var c := paint_at(x0 + i * step, z0 + j * step)
			if c == 1: S[idx] = 1
			elif c == 2: S[idx] = 3
			elif c == 3: S[idx] = 4



## a jump line (BmxJumpLine): jumps one after another down the trail, the next lip one roll-out after a landing
func _add_line(p: Dictionary) -> void:
	if TX.size() < 2: return
	var i := nearest(p.pos.x, p.pos.y)
	var free_from := -1.0   # m along the trail where the next jump may start (the last landing + a roll-out)
	for n in int(p.get("count", 3)):
		if i < 0 or i >= TX.size() - 20: break
		var q: Dictionary = p.duplicate(true)
		q.kind = "jump"; q.follow = true; q.name = "%s_%d" % [p.name, n + 1]
		var st: Dictionary = {}
		for attempt in 4:   # (a faster jump has a longer run-in: push its lip on until its start clears the last landing)
			if i >= TX.size() - 20: break
			q.pos = Vector2(TX[i], TZ[i]); q.dir = Vector2(DX[i], DZ[i])
			var before := structs.size()
			var r_before := route.size()
			var snap := [H.duplicate(), S.duplicate(), JM.duplicate()]   # (a rejected try must not stay stamped in the ground)
			_add_jump(q)
			if structs.size() == before: break
			st = structs[structs.size() - 1]
			var s_start := nearest(st.o.x, st.o.y) * DS
			if free_from < 0.0 or s_start >= free_from - 0.5: break
			structs.pop_back(); route.resize(r_before)   # (too early: undo it, try further on)
			H = snap[0]; S = snap[1]; JM = snap[2]
			i += int((free_from - s_start) / DS) + 1
			st = {}
		if st.is_empty(): break
		var d: Dictionary = st.d
		var land_end: Vector2 = (st.o as Vector2) + (st.dir as Vector2) * float(d.land1 if str(d.kind) != "kicker" else float(d.lip_u) + 6.0)
		var ie := nearest(land_end.x, land_end.y)
		var roll := clampf(TV[ie] * float(p.get("rollout", 0.75)), 6.0, 14.0)
		free_from = ie * DS + roll
		i = ie + int((roll + float(d.lip_u)) / DS)



## the other lines (BmxTrail after the first): each baked like the main one (resampled, curvature, height, speed,
## bank); its speed starts from the main line's where it branches off, and its ends ease onto the main line's height
## over 15 m where they meet it, so the junctions are one surface
func _bake_alts() -> void:
	ALT = []
	if alts_in.is_empty() or TX.size() < 2: return
	# (packed arrays are shared: _bake_trail clears + refills the members, so keep real copies)
	var m := {"TX": TX.duplicate(), "TZ": TZ.duplicate(), "DX": DX.duplicate(), "DZ": DZ.duplicate(), "TY": TY.duplicate(),
		"TK": TK.duplicate(), "TV": TV.duplicate(), "TB": TB.duplicate(), "len": trail_len, "in": trail_in.duplicate(), "v0": start_speed}
	for a in alts_in:
		var pts: PackedVector2Array = a.pts
		if pts.size() < 2: continue
		var i0 := _nearest_in(m.TX, m.TZ, pts[0].x, pts[0].y)
		trail_in = pts
		start_speed = (m.TV as PackedFloat32Array)[i0] if i0 >= 0 else start_speed
		_bake_trail()
		var n := TX.size()
		if n < 3: continue
		for end in 2:
			var ie := 0 if end == 0 else n - 1
			var mi := _nearest_in(m.TX, m.TZ, TX[ie], TZ[ie])
			if mi < 0 or Vector2(m.TX[mi] - TX[ie], m.TZ[mi] - TZ[ie]).length() > 8.0: continue
			# over its last 20 m the alt line takes the main line's own height + bank where they run side by side (sample by
			# sample, not one point's): where the two cross sections meet there is no step
			for q in mini(20, n):
				var ii := q if end == 0 else n - 1 - q
				var mj := _nearest_in(m.TX, m.TZ, TX[ii], TZ[ii])
				var k := smoothstep(0.0, 20.0, float(q))
				TY[ii] = lerpf((m.TY as PackedFloat32Array)[mj], TY[ii], k)
				TB[ii] = lerpf((m.TB as PackedFloat32Array)[mj], TB[ii], k)
		ALT.append({"TX": TX.duplicate(), "TZ": TZ.duplicate(), "DX": DX.duplicate(), "DZ": DZ.duplicate(), "TY": TY.duplicate(),
			"TK": TK.duplicate(), "TV": TV.duplicate(), "TB": TB.duplicate()})
	TX = m.TX; TZ = m.TZ; DX = m.DX; DZ = m.DZ; TY = m.TY; TK = m.TK; TV = m.TV; TB = m.TB
	trail_len = m.len; trail_in = m.in; start_speed = m.v0


static func _nearest_in(ax: PackedFloat32Array, az: PackedFloat32Array, x: float, z: float) -> int:
	var bi := -1
	var bd := INF
	for i in ax.size():
		var d := (ax[i] - x) * (ax[i] - x) + (az[i] - z) * (az[i] - z)
		if d < bd: bd = d; bi = i
	return bi
