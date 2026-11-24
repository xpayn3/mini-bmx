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

# ---- the trail ----------------------------------------------------------------------------------------------
var trail_in := PackedVector2Array()   # (x, z) points along the designer's spline, any spacing
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
	step = grid_step
	var margin := 40.0
	x0 = -margin; z0 = -width * 0.5 - 10.0
	nx = int(ceil((length + 2.0 * margin) / step)) + 1
	nz = int(ceil((width + 20.0) / step)) + 1
	H.resize(nx * nz); S.resize(nx * nz); S.fill(0)
	for j in nz:
		var z := z0 + j * step
		var row := j * nx
		for i in nx:
			H[row + i] = base(x0 + i * step, z)
	var n := TX.size()
	if n < 2: return
	# the trail: every grid point within reach of a segment takes the nearest segment's cross section
	var hw := trail_width * 0.5
	var R := hw + blend
	var best := PackedFloat32Array(); best.resize(nx * nz); best.fill(INF)
	var cut := PackedFloat32Array(); cut.resize(nx * nz)   # the trail's shape height there
	var sd := PackedFloat32Array(); sd.resize(nx * nz)     # |s| there
	var rb := absf(tan(deg_to_rad(bank_max_deg))) * R
	for k in n - 1:
		var ax := TX[k]; var az := TZ[k]
		var ex := TX[k + 1] - ax; var ez := TZ[k + 1] - az
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
				var y := lerpf(TY[k], TY[k + 1], a)
				var b := lerpf(TB[k], TB[k + 1], a)
				cut[idx] = _trail_shape(y, b, clampf(s, -hw, hw))
				sd[idx] = absf(s)
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


## height anywhere (bilinear in the grid; the land past it)
func height(x: float, z: float) -> float:
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
			V[j * cx + i] = Vector3(x, H[k], z)
	for j in cz:
		for i in cx:
			var k := j * cx + i
			var a := V[j * cx + maxi(0, i - 1)]; var b := V[j * cx + mini(cx - 1, i + 1)]
			var c := V[maxi(0, j - 1) * cx + i]; var e := V[mini(cz - 1, j + 1) * cx + i]
			var n := Vector3(-(b.y - a.y) / maxf(1e-4, b.x - a.x), 1.0, -(e.y - c.y) / maxf(1e-4, e.z - c.z)).normalized()
			N[k] = n
			var gi := mini(i * every, nx - 1); var gj := mini(j * every, nz - 1)
			var sf := S[gj * nx + gi]
			var col := DIRT if sf == 1 else (CLAY if sf == 2 else _land_color(V[k].x, V[k].z, n.y))
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
func far_mesh(reach := 900.0, cell := 12.0) -> ArrayMesh:
	var gx0 := x0 + cell; var gx1 := x0 + (nx - 1) * step - cell
	var gz0 := z0 + cell; var gz1 := z0 + (nz - 1) * step - cell
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
	tc.KD[0] = TrailCourse.START; tc.KD[m - 1] = TrailCourse.FINISH
	tc.n = m
	tc.length = (m - 1) * TrailCourse.STEP
	return tc
