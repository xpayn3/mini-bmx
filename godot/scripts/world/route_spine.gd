class_name RouteSpine
extends RefCounted
## The world's route (2026-11-25, user: "use the landscape, really wavy, the map is square, aware of how the land
## tilts"): a 2D line the whole world is laid out along. The mountains, their pitches and ranges and the trail's
## corridor are measured along it (s) and across it (d) instead of along x / across zc(x), so the trail can swing
## any way and even head back. Immutable once built: grown() returns a NEW spine laid out further (the old one stays
## for threads still reading it), continuing the walker's saved state, so a grown spine == one built in one go.
##
## Laid out by a walker every STEP m: it heads for random waypoints scattered over a wide square (1.5-5.5 km apart, often
## off to a side, now and then back the way it came), wobbling on the way, and each step picks among a
## few headings the one that best fits the land (no climbing into hills, around lakes and cliffs, away from its own
## earlier legs). The land it reads is the bare land, without the mountains it carries (TerrainField.bare).
## Mirrored in TerrainFieldCs (the query only: C# copies the arrays).

const STEP := 20.0
const R := 450.0           # the query's reach (m): the widest band any land mask uses (hill: MTN_W + 260 = 410)
const CELL := 160.0
const S0 := -636.0         # the spine starts here, on +x; s = x along its first straight (to the trail's start at -36)
const STRAIGHT_TO := 150.0 # straight +x up to this s, then the walker
const DH := 0.0262         # rad: one turning notch per step (1.5 deg); it may take up to TURN_N of them (6 deg / 20 m: radius ~190 m)
const TURN_N := 4
const GAP := 1100.0        # m: kept from its own legs further back than GAP_BACK along it
const GAP_BACK := 1600.0
const LOOK := 80.0         # m ahead it reads the land

var X := PackedFloat64Array()
var Z := PackedFloat64Array()
var S := PackedFloat64Array()
var n: int = 0
# grid: cells of CELL m over the spine's box +- R; each lists every segment (i -> i + 1) that comes within R + the
# cell's half diagonal of the cell's middle (ascending, so the query sums in the same order on both sides)
var gx0: int = 0
var gz0: int = 0
var gnx: int = 0
var gnz: int = 0
var cell_start := PackedInt32Array()
var cell_items := PackedInt32Array()

# walker state (saved: grown() carries on from it)
var _rng := WorldRng.new()
var _x := 0.0
var _z := 0.0
var _h := 0.0
var _s := 0.0
var _wx := 0.0     # the waypoint it is heading for
var _wz := 0.0
var _wob := 0.0    # a slow random wobble on the way there (rad)
var _maxx := 0.0   # the furthest east it has been (it may head back, not far)
var _amp_k := 1.0  # RouteStyle twist: how far it roams


static func make(field, seed_v: int, to_s: float) -> RouteSpine:
	var sp := RouteSpine.new()
	sp._rng = WorldRng.new(seed_v * 7243 + 11)
	sp._amp_k = clampf(sqrt(float(field.style.get("twist", 1.0))), 0.6, 1.3)
	sp._x = S0; sp._z = 0.0; sp._h = 0.0; sp._s = S0
	sp.X.append(sp._x); sp.Z.append(sp._z); sp.S.append(sp._s)
	sp._wx = 900.0; sp._wz = 0.0
	sp._extend(field, to_s)
	return sp


func grown(field, to_s: float) -> RouteSpine:
	var sp := RouteSpine.new()
	sp.X = X.duplicate(); sp.Z = Z.duplicate(); sp.S = S.duplicate()
	sp._rng = WorldRng.new(); sp._rng.a = _rng.a
	sp._x = _x; sp._z = _z; sp._h = _h; sp._s = _s; sp._wx = _wx; sp._wz = _wz; sp._wob = _wob; sp._maxx = _maxx
	sp._amp_k = _amp_k
	sp._extend(field, to_s)
	return sp


func end_s() -> float:
	return _s


const ZMAX := 7000.0       # m: it roams within +- this of z = 0 (the whole "square", not a band)
const WP_NEAR := 1200.0    # waypoint distance range (m)
const WP_FAR := 4000.0
const WP_TURN := 1.95      # rad: the most a new waypoint may lie off the current heading (~112 deg: no hairpin U-turns)
const BACK_MAX := 3500.0   # m: how far back west of its furthest east it may go

## the next waypoint: somewhere 1.2-4 km away in a random direction (often well off to a side, now and then back),
## inside the square, with a straight line to it that keeps clear of its own earlier legs. Of the free ones it takes
## the one with the most open land round it (furthest from its old legs), so it never curls in on itself
func _new_wp() -> void:
	var best := -INF
	var found := false
	for tries in 24:
		var ang := _h + (_rng.next() * 2.0 - 1.0) * WP_TURN
		var l := (WP_NEAR + _rng.next() * (WP_FAR - WP_NEAR)) * _amp_k
		var wx := _x + cos(ang) * l
		var wz := _z + sin(ang) * l
		var r := _rng.next()
		if absf(wz) > ZMAX or wx < _maxx - BACK_MAX:
			continue
		if not _clear_line(wx, wz):
			continue
		var score := minf(_open(wx, wz), 4000.0) + r * 1500.0
		if score > best:
			best = score; _wx = wx; _wz = wz; found = true
	if not found:
		_wx = _x + 3000.0; _wz = _z * 0.5   # nowhere free: on east, back towards the middle


## how far (m) the nearest of its own points is from (x, z)
func _open(x: float, z: float) -> float:
	var m := INF
	for j in range(0, S.size(), 4):
		var ddx := X[j] - x
		var ddz := Z[j] - z
		m = minf(m, ddx * ddx + ddz * ddz)
	return sqrt(m)

func _clear_line(wx: float, wz: float) -> bool:
	var lim := _s - GAP_BACK
	var steps := int(Vector2(wx - _x, wz - _z).length() / 250.0) + 1
	for k in range(1, steps + 1):
		var px := _x + (wx - _x) * k / steps
		var pz := _z + (wz - _z) * k / steps
		var j := 0
		while j < S.size() and S[j] < lim + 250.0 * k:
			var ddx := X[j] - px
			var ddz := Z[j] - pz
			if ddx * ddx + ddz * ddz < GAP * GAP:
				return false
			j += 3
	return true


func _extend(field, to_s: float) -> void:
	var was_bare: bool = field.bare
	field.bare = true
	field._reset_caches()
	while _s < to_s:
		_step(field)
	field.bare = was_bare
	field._reset_caches()
	n = X.size()
	_build_grid()


func _step(field) -> void:
	if _s >= STRAIGHT_TO:
		if Vector2(_wx - _x, _wz - _z).length() < 400.0:
			_new_wp()
		_wob = clampf(_wob * 0.97 + (_rng.next() - 0.5) * 0.16, -0.8, 0.8)
		var fade := TerrainField.sm(STRAIGHT_TO, 900.0, _s)
		var hw := atan2(_wz - _z, _wx - _x) + _wob * fade
		var best := INF
		var bh := _h
		for k in range(-TURN_N, TURN_N + 1):
			var th := _h + k * DH
			var c := _cost(field, th, hw)
			if c < best:
				best = c; bh = th
		_h = bh
	_x += cos(_h) * STEP
	_z += sin(_h) * STEP
	_s += STEP
	_maxx = maxf(_maxx, _x)
	X.append(_x); Z.append(_z); S.append(_s)


## how badly heading th fits: off its way to the waypoint, climbing into a hill, into a lake / over a cliff, near its old legs
func _cost(field, th: float, hw: float) -> float:
	var dh := atan2(sin(th - hw), cos(th - hw))
	var c := 3.0 * dh * dh
	var cx := cos(th)
	var cz := sin(th)
	var h0: float = field.landform(_x, _z)
	var h1: float = field.landform(_x + cx * LOOK * 0.5, _z + cz * LOOK * 0.5)
	var h2: float = field.landform(_x + cx * LOOK, _z + cz * LOOK)
	var g := (h2 - h0) / LOOK
	if g > 0.0:
		c += 40.0 * g * g          # climbing into the land's own hills
	if g < -0.12:
		c += 20.0 * (g + 0.12) * (g + 0.12)   # straight down a steep fall line
	var lx := _x + cx * LOOK * 0.5 - cz * 30.0
	var lz := _z + cz * LOOK * 0.5 + cx * 30.0
	var rx := _x + cx * LOOK * 0.5 + cz * 30.0
	var rz := _z + cz * LOOK * 0.5 - cx * 30.0
	var side := absf(field.landform(lx, lz) - field.landform(rx, rz)) / 60.0
	if side > 0.45:
		c += 4.0 * (side - 0.45) * (side - 0.45)   # across a cliff
	if minf(h1, h2) < TerrainField.WATER + 0.5:
		c += 0.6                     # into a lake
	# its own earlier legs
	var qx := _x + cx * LOOK
	var qz := _z + cz * LOOK
	var lim := _s - GAP_BACK
	var j := 0
	while j < S.size() and S[j] < lim:
		var ddx := X[j] - qx
		var ddz := Z[j] - qz
		var dd := ddx * ddx + ddz * ddz
		if dd < GAP * GAP:
			var d := sqrt(dd)
			c += 6.0 * (1.0 - d / GAP) * (1.0 - d / GAP)
			if d < GAP * 0.6:
				c += 50.0
		j += 3
	return c


func _build_grid() -> void:
	var minx := INF; var maxx := -INF; var minz := INF; var maxz := -INF
	for i in n:
		minx = minf(minx, X[i]); maxx = maxf(maxx, X[i]); minz = minf(minz, Z[i]); maxz = maxf(maxz, Z[i])
	gx0 = floori((minx - R - CELL) / CELL)
	gz0 = floori((minz - R - CELL) / CELL)
	gnx = floori((maxx + R + CELL) / CELL) - gx0 + 1
	gnz = floori((maxz + R + CELL) / CELL) - gz0 + 1
	var reach := R + CELL * 0.7072   # + half the cell's diagonal
	var counts := PackedInt32Array(); counts.resize(gnx * gnz)
	var lists: Array = []
	for pass_i in 2:
		if pass_i == 1:
			cell_start = PackedInt32Array(); cell_start.resize(gnx * gnz + 1)
			var acc := 0
			for c in gnx * gnz:
				cell_start[c] = acc
				acc += counts[c]
				counts[c] = 0
			cell_start[gnx * gnz] = acc
			cell_items = PackedInt32Array(); cell_items.resize(acc)
		for i in n - 1:
			var ax := X[i]; var az := Z[i]; var bx := X[i + 1]; var bz := Z[i + 1]
			var cx0 := floori((minf(ax, bx) - reach) / CELL) - gx0
			var cx1 := floori((maxf(ax, bx) + reach) / CELL) - gx0
			var cz0 := floori((minf(az, bz) - reach) / CELL) - gz0
			var cz1 := floori((maxf(az, bz) + reach) / CELL) - gz0
			for cz in range(maxi(cz0, 0), mini(cz1, gnz - 1) + 1):
				for cx in range(maxi(cx0, 0), mini(cx1, gnx - 1) + 1):
					# the cell's middle within reach of the segment?
					var mx := (gx0 + cx + 0.5) * CELL
					var mz := (gz0 + cz + 0.5) * CELL
					var sx := bx - ax; var sz := bz - az
					var l2 := sx * sx + sz * sz
					var t := ((mx - ax) * sx + (mz - az) * sz) / l2
					t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
					var ex := ax + sx * t - mx; var ez := az + sz * t - mz
					if ex * ex + ez * ez > reach * reach:
						continue
					var ci := cz * gnx + cx
					if pass_i == 0:
						counts[ci] += 1
					else:
						cell_items[cell_start[ci] + counts[ci]] = i
						counts[ci] += 1
