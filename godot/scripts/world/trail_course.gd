class_name TrailCourse
extends RefCounted
## Port of course.js: the long downhill course laid out by a "turtle" down the mountain -- and then on
## through the hills for ever: grown() continues the turtle into a NEW course (the old one stays
## untouched for threads still reading it); everything already laid out stays exactly as it was.
## query() lives in TerrainField (per-thread result cache); this holds the immutable layout.

const STEP := 2.0
enum { START = 0, ROAD = 1, SWITCH = 2, ESSES = 3, ROCKS = 4, JUMP = 5, FINISH = 6 }
const WIDTH := [3.0, 2.7, 1.35, 1.45, 1.7, 2.5, 3.0]
const BERM := [0.0, 0.45, 1.0, 0.9, 0.3, 0.0, 0.0]
const CELL := 16.0
const QR := 19.0
const D2R := PI / 180.0

# layout (centreline, every STEP m)
var X := PackedFloat64Array()
var Z := PackedFloat64Array()
var KD := PackedInt32Array()
var n: int = 0
# derived (Float32Array in the JS -> PackedFloat32Array here so the rounding matches)
var TX := PackedFloat32Array()
var TZ := PackedFloat32Array()
var KAP := PackedFloat32Array()
var W := PackedFloat32Array()
var BT := PackedFloat32Array()
var E := PackedFloat32Array()
var RD := PackedFloat32Array()
var RK := PackedFloat32Array()
## the racing line: where riders' tyres have worn the trail, in metres across from the centreline (+ = the side
## q_a is positive on). Wide into a turn, inside at the apex, wide out again.
var LN := PackedFloat32Array()
## run-offs: where a rider who braked too late went straight on at a corner. RO = that skid's place across the
## trail at each point, ROS = how strong (0 = none here)
var RO := PackedFloat32Array()
var ROS := PackedFloat32Array()
## the speed (m/s) a good rider arrives at each point: no brakes except what a bend's radius and bank make him
## (forward only from the start, so growing the trail never changes it). Banks are sized from it (_bank)
var VA := PackedFloat32Array()
const VA_START := 4.0       # m/s at the start
const VA_PEDAL := 0.6       # m/s^2 of pedalling below VA_PED_TOP (~30 km/h)
const VA_PED_TOP := 8.5
const VA_ROLL := 0.08       # m/s^2 rolling drag (measured on the trail: ~0.07)
const VA_DRAG := 0.0033     # air drag per v^2 (measured: ~0.5 m/s^2 at 45 km/h, an upright DH rider)
const VA_MAX := 17.5        # m/s (~63 km/h): riders roll off there
const A_RIDE := 6.0         # m/s^2 of side grip a good rider uses in a bend on the flat (the demo plans 7)
const A_COMF := 4.0         # m/s^2: a bend that asks more than this of the tyres at the arrival speed gets banked
const BANK_MAX := 0.70      # tan of the steepest berm (35 deg)
const BERM_LINE := 0.9      # m out from the centreline the line rides a berm (on its face: berm_shape rises from ~0)
const BERM_LINE_FROM := 0.08; const BERM_LINE_FULL := 0.22   # |BT| (tan of the bank) where the line moves onto the berm
var length: float = 0.0
var drops: Array = []   # [[i0, i1]] centreline index ranges of drop-offs / cliffs (no route features there)
# dense spatial hash of segments by midpoint
var gx0: int = 0
var gz0: int = 0
var gnx: int = 0
var gnz: int = 0
var cell_start := PackedInt32Array()
var cell_items := PackedInt32Array()
# marking
var fences: Array = []   # [{posts: Array[[x,z]], style}]
var stakes: Array = []   # [{x, z, s, side, caution, prev (index or -1)}]
# per terrain chunk (CHUNK m, keyed by chunk_key(cx, cz)): what the chunk builder needs there, so a
# chunk never scans the whole (very long) course
const CHUNK := 48.0
var chunk_rocks := {}    # key -> PackedInt32Array of ROCKS centreline indices
var chunk_stakes := {}   # key -> PackedInt32Array of stake indices
var chunk_fences := {}   # key -> PackedInt32Array of fence indices with a post in the chunk
var chunk_gates := {}    # key -> PackedInt32Array of centreline indices that carry a distance gate
const GATE_FIRST := 150    # centreline index of the first gate (300 m down the trail)
const GATE_EVERY := 150     # one every 300 m
var chunk_arches := {}   # key -> PackedInt32Array of (centreline index * 2 + TrailArch kind)
var chunk_boards := {}  # key -> PackedInt32Array of centreline indices with a roadside billboard
var chunk_signs := {}   # key -> PackedInt32Array of centreline indices with a distance table (small leaning sign)
const SIGN_FIRST := 500      # first sign at 1 km
const SIGN_EVERY := 2500   # one every 5 km (centreline points are ~2 m apart)
const BOARD_FIRST := 18
const BOARD_EVERY := 41     # one every ~80 m, alternating sides

# build state
var _M  # TerrainField (zc, landform, pitches, water)
var _r: WorldRng
var _x := 0.0
var _sps := PackedFloat64Array()   # (_finish) each point's s along the route spine
var _send := 0.0
## flow rules (2026-11-25, Phase B): while laying out, the turtle keeps an estimate of the speed a rider carries here (_v,
## from the land's fall: gravity in, rolling + air drag out, pedalling when slow, capped by every bend it lays) and sizes bends
## to it, eases into and out of every bend, alternates bends, spaces them by time, and only lays the tight sections on
## steep hillsides. BMX_OLD_FLOW=1 = the layout before (tests).
static var OLD_FLOW := OS.get_environment("BMX_OLD_FLOW") != ""
const A_BEND := 9.4      # m/s^2 a rider takes a bend with (A_RIDE + a modest berm's share of g)
const CLO_MAX := 6       # steps (12 m): the most an arc's curvature ramps in / out over
var _v := 4.0           # m/s: the speed estimate at the turtle
var _hv := NAN          # the land's height at the last point it laid
var _lt := 1.0          # the side of the last road bend (+1 / -1)   # the route spine's s at the course's last point (how far it is laid out: _L is in s)
var _z := 0.0
var _h := 0.0
var _cells := {}
var _L := 0.0      # course length along x (the trail runs on long past the mountain)
var _hill := 0.0   # where the mountain ends
var _corr := 0.0


static func smooth(a: float, b: float, x: float) -> float:
	var t := minf(1.0, maxf(0.0, (x - a) / (b - a)))
	return t * t * (3.0 - 2.0 * t)


static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


var _mark_seed: int = 0


## a new course: the mountain, then on to x = course_len
static func make(rnd: WorldRng, field, hill_len: float, corridor: float, course_len: float, mark_seed: int) -> TrailCourse:
	var c := TrailCourse.new()
	c._M = field
	c._r = rnd
	c._hill = hill_len
	c._L = course_len
	c._corr = corridor
	c._mark_seed = mark_seed
	c._x = -36; c._z = 0; c._h = 0
	c._straight(76, START)
	c._commit(0)
	c._build()
	c._finish()
	c._M = null   # only needed for the layout; kept, field.course <-> course._M was a cycle (never freed)
	return c


## the furthest x laid out so far
func end_s() -> float:
	return _send


## a copy of this course laid out on to x = to_x (field: the TerrainField to read the land from; call
## plan_marking(field) on the result once the field queries it). This course is not changed.
func grown(field, to_s: float) -> TrailCourse:
	var c := TrailCourse.new()
	c._M = field
	c._r = WorldRng.new()
	c._r.a = _r.a
	c._hill = _hill
	c._L = to_s
	c._corr = _corr
	c._mark_seed = _mark_seed
	c._x = _x; c._z = _z; c._h = _h; c._v = _v; c._hv = _hv; c._lt = _lt
	c.X = X.duplicate(); c.Z = Z.duplicate(); c.KD = KD.duplicate()
	c._cells = _cells.duplicate()
	c._build()
	c._finish()
	c._M = null   # only needed for the layout; kept, field.course <-> course._M was a cycle (never freed)
	return c


# ---------------- layout ----------------
func _key(gx: int, gz: int) -> int:
	return gx * 100003 + gz


func _commit(from: int) -> void:
	for i in range(from, X.size()):
		var k := _key(floori(X[i] / CELL), floori(Z[i] / CELL))
		if not _cells.has(k):
			_cells[k] = PackedInt32Array()
		var l: PackedInt32Array = _cells[k]
		l.append(i)
		_cells[k] = l


func _clashes(from: int, gap: float = 19.0) -> bool:
	for i in range(from, X.size()):
		var gx := floori(X[i] / CELL)
		var gz := floori(Z[i] / CELL)
		for a in range(-2, 3):
			for b in range(-2, 3):
				var l = _cells.get(_key(gx + a, gz + b))
				if l == null:
					continue
				for j in l:
					if (i - j) * STEP > 70:
						var ddx := X[i] - X[j]
						var ddz := Z[i] - Z[j]
						if sqrt(ddx * ddx + ddz * ddz) < gap:
							return true
		if (i - from) % 2 == 0:
			_M.spine_near(X[i], Z[i])
			if _M.sp_ad > _corr + 15:
				return true
	return false


func _emit(kind: int, dh: float = 0.0) -> void:
	_x += cos(_h) * STEP
	_z += sin(_h) * STEP
	X.append(_x); Z.append(_z); KD.append(kind)
	if OLD_FLOW:
		return
	var h: float = _M.landform(_x, _z)
	var v2 := _v * _v
	if not is_nan(_hv):
		v2 += 2.0 * 9.81 * (_hv - h)
	v2 -= 2.0 * STEP * (VA_ROLL + VA_DRAG * v2)
	if _v < VA_PED_TOP:
		v2 += 2.0 * VA_PEDAL * STEP
	if absf(dh) > 1e-6:
		v2 = minf(v2, A_BEND * STEP / absf(dh))   # a bend of radius STEP / dh: no faster than its grip allows
	_v = clampf(sqrt(maxf(v2, 0.0)), VA_START, VA_MAX)
	_hv = h


func _straight(len: float, kind: int, wob: float = 0.0) -> void:
	var cnt: int = maxi(1, WorldRng.jround(len / STEP))
	var ph := _r.next() * 6.28
	for i in cnt:
		_h += wob * cos(ph + i * 0.35) * 0.06
		_emit(kind)


func _arc(ang: float, R: float, kind: int) -> void:
	var cnt0: int = maxi(1, WorldRng.jround(absf(ang) * R / STEP))
	if OLD_FLOW or cnt0 < 4:
		var dh := ang / cnt0
		for i in cnt0:
			_h += dh / 2
			_emit(kind, dh)
			_h += dh / 2
		return
	# eased: the curvature ramps up over m steps, holds (at radius R), ramps down (a clothoid-like entry / exit:
	# no straight-to-arc corner the bars have to snap into). The ramps add m steps, so the peak radius stays R
	var m := mini(CLO_MAX, maxi(1, WorldRng.jround(cnt0 * 0.25)))
	var cnt := cnt0 + m
	var wsum := 0.0
	for i in cnt:
		wsum += minf(1.0, minf((i + 0.5) / m, (cnt - i - 0.5) / m))
	for i in cnt:
		var dh := ang * minf(1.0, minf((i + 0.5) / m, (cnt - i - 0.5) / m)) / wsum
		_h += dh / 2
		_emit(kind, dh)
		_h += dh / 2


func _turn_to(target: float, R: float, kind: int) -> void:
	_arc(wrap_angle(target - _h), R, kind)


## how steep the land is here across the way the trail runs (rise over run, 40 m each side, the land with its mountains)
func _side_slope() -> float:
	var nx := -sin(_h)
	var nz := cos(_h)
	return absf(_M.landform(_x + nx * 40.0, _z + nz * 40.0) - _M.landform(_x - nx * 40.0, _z - nz * 40.0)) / 80.0


## how far along the route spine the turtle is (m: TerrainField.spine_near)
func _sp() -> float:
	_M.spine_near(_x, _z)
	return _M.sp_s


## a heading relative to the route spine's direction here (the trail follows its swings, whichever way it runs)
func _rel(a: float) -> float:
	_M.spine_near(_x, _z)
	return _M.sp_dir + a


## how far off the corridor's middle (the spine), square to it (+ = left of the way it runs)
func _off() -> float:
	_M.spine_near(_x, _z)
	return _M.sp_d


func _next_pitch() -> int:
	var P: PackedFloat64Array = _M.pitches
	for k in range(0, P.size(), 3):
		if P[k] + P[k + 1] / 2 > _sp():
			return k
	return -1


func _snap() -> Array:
	return [_x, _z, _h, X.size(), _v, _hv, _lt]


func _undo(s: Array) -> void:
	_x = s[0]; _z = s[1]; _h = s[2]; _v = s[4]; _hv = s[5]; _lt = s[6]
	X.resize(s[3]); Z.resize(s[3]); KD.resize(s[3])


# sections: [code, arg]  code 0 road(maxLen) 1 switchbacks(endX) 2 esses(endX) 3 chute(endX) 4 jumpLine 5 esses(x+50)
func _run(sec: Array) -> void:
	match sec[0]:
		0: _road(sec[1])
		1: _switchbacks(sec[1])
		2: _esses(sec[1])
		3: _chute(sec[1])
		4: _jump_line()
		5: _esses(_sp() + 50)
		6: _tech(sec[1])


func _attempt(fns: Array) -> bool:
	for t in 6:
		var s := _snap()
		_run(fns[t % fns.size()])
		if not _clashes(s[3]):
			_commit(s[3])
			return true
		_undo(s)
	var s2 := _snap()
	_turn_to(_rel(0.0), 30, ROAD)
	_straight(24, ROAD)
	_commit(s2[3])
	return false


## one RouteStyle value (jumps / twist / rolling); 1.0 when the field has none (the original layout)
func _sv(k: String) -> float:
	if _M == null: return 1.0
	return float(_M.style.get(k, 1.0))


## RouteStyle.jumps: the chance band [0, 0.3) of "a jump line" in _build grows / shrinks to [0, 0.3 x j), the rest of the
## picks keep their proportions (j = 1 returns p itself: the original layout)
static func _jump_remap(p: float, j: float, old_band: float) -> float:
	if j == 1.0: return p
	var nb := minf(old_band * j, 0.9)
	if p < nb: return p / maxf(nb, 1e-6) * old_band
	return old_band + (p - nb) / (1.0 - nb) * (1.0 - old_band)


## a section of the course; swap = a plain stretch of road instead of the tight sections (RouteStyle.twist below 1)
func _section(fns: Array, swap: bool) -> void:
	# switchbacks / hairpin stacks exist because a hillside is too steep to ride straight down: on gentle land they
	# make no sense, a flowing road does instead
	if not OLD_FLOW and (fns[0][0] == 1 or fns[0][0] == 6) and _side_slope() < 0.10:
		swap = true
	if swap: _attempt([[0, 50.0 + fposmod(_x * 0.37, 1.0) * 80.0]])
	else: _attempt(fns)


func _road(max_len: float) -> void:
	var len := minf(max_len, 90 + _r.next() * 150)
	var done := 0.0
	var tw := _sv("twist")   # RouteStyle.twist: 1 = as before
	while done < len:
		var o := _off()
		var lim := _corr - 30
		var tgt := (_r.next() * 2 - 1) * 72 * D2R * sqrt(tw)
		if not OLD_FLOW:   # rhythm: mostly the other way from the last bend (left-right-left), now and then the same way again
			var mag := absf(tgt)
			_lt = -_lt if _r.next() < 0.75 else _lt
			tgt = _lt * maxf(mag, 18.0 * D2R)
		if absf(o) > lim * (0.5 if TerrainField.OLD_ROUTE else 0.75):   # (new: the trail uses more of the corridor's width)
			tgt = -signf(o) * (22 + _r.next() * 44) * D2R
			_lt = signf(tgt)
		tgt = _rel(tgt)
		var seg := minf(len - done, 18 + _r.next() * 40)
		if not OLD_FLOW:   # the next bend 1.5-3 s on at the speed riders carry here
			seg = minf(len - done, clampf(_v * (1.5 + _r.next() * 1.5), 15.0, 70.0))
		# often a tight bend instead of a sweeper
		var R := (13 + _r.next() * 16) if _r.next() < minf(0.42 * tw, 0.95) else (34 + _r.next() * 56) / maxf(0.6, sqrt(tw))
		if not OLD_FLOW:   # never tighter than the speed riders arrive at can take (a tight one waits for a slow stretch)
			R = maxf(R, _v * _v / A_BEND)
		var n0 := X.size()
		_turn_to(tgt, R, ROAD)
		var used := (X.size() - n0) * STEP
		if used < seg:
			_straight(seg - used, ROAD)
		done += maxf(seg, used)
		if _sp() > _L - 70:
			break


func _switchbacks(end_x: float) -> void:
	var first := -1 if _off() > 0 else 1
	var alpha := (12 + _r.next() * 10) * D2R
	var R := 7 + _r.next() * 2.5
	var dir := first
	var k := 0
	_turn_to(_rel(dir * (PI / 2 - alpha)), 11 + _r.next() * 4, SWITCH)
	while k < 6:
		var room := (_corr - 12 - dir * _off()) / cos(alpha)
		_straight(maxf(14, minf(26 + _r.next() * 20, room)), SWITCH, 0.4)
		if _sp() > end_x and k >= 2:
			break
		dir = -dir
		k += 1
		_turn_to(_rel(dir * (PI / 2 - alpha)), R, SWITCH)
	_turn_to(_rel(0.0), 12 + _r.next() * 4, SWITCH)
	_straight(8, SWITCH)


func _esses(end_x: float, kind: int = ESSES) -> void:
	var dir := 1 if _r.next() < 0.5 else -1
	var k := 0
	if absf(_off()) > 30:
		dir = -int(signf(_off()))
	while k < 9:
		var ang := (38 + _r.next() * 34) * D2R
		var R := 10 + _r.next() * 8
		_turn_to(_rel(dir * ang), R, kind)
		_straight(3 + _r.next() * 6, kind)
		dir = -dir
		k += 1
		if _sp() > end_x and k >= 3:
			break
	_turn_to(_rel(0.0), 14, kind)


## a slow technical section: a stack of tight hairpins (5-6.5 m radius, about walking-to-jogging pace on a bike),
## short legs between them, now and then a quick flick left-right in a leg
func _tech(end_x: float) -> void:
	var dir := 1 if _r.next() < 0.5 else -1
	if absf(_off()) > 25:
		dir = -int(signf(_off()))
	var alpha := (14 + _r.next() * 16) * D2R
	var R := 5.0 + _r.next() * 1.5
	var k := 0
	_turn_to(_rel(dir * (PI / 2 - alpha)), 8 + _r.next() * 3, SWITCH)
	while k < 7:
		var leg := 8 + _r.next() * 9
		if _r.next() < 0.35:
			_straight(leg * 0.4, SWITCH)
			_arc(-dir * 0.7, 6.5, SWITCH)
			_arc(dir * 0.7, 6.5, SWITCH)
			_straight(leg * 0.3, SWITCH)
		else:
			_straight(leg, SWITCH, 0.3)
		if _sp() > end_x and k >= 3:
			break
		dir = -dir
		k += 1
		_turn_to(_rel(dir * (PI / 2 - alpha)), R, SWITCH)
	_turn_to(_rel(0.0), 9, SWITCH)
	_straight(6, SWITCH)


func _chute(end_x: float) -> void:
	_turn_to(_rel((_r.next() - .5) * 16 * D2R), 18, ROCKS)
	_straight(maxf(26, end_x - _sp() + 6), ROCKS, 0.25)


func _jump_line() -> void:
	_turn_to(_rel((_r.next() - .5) * 14 * D2R), 40, ROAD)
	_straight(10, ROAD)
	_straight(80 + _r.next() * 50, JUMP)
	_straight(8, ROAD)


func _build() -> void:
	var guard := 0
	var P: PackedFloat64Array = _M.pitches
	while _sp() < _L - 80 and guard < 4000:
		guard += 1
		var sh := _sp()
		var pk := _next_pitch()
		var to_pitch := (P[pk] - P[pk + 1] / 2 - sh) if pk >= 0 else INF
		if to_pitch < 30:
			var end_x: float = P[pk] + P[pk + 1] / 2 + 6
			var pick := _r.next()
			if pick < 0.45:   # (the mountain's pitches: technical sections whatever the style)
				_attempt([[1, end_x], [2, end_x], [3, end_x]])
			elif pick < 0.75:
				_attempt([[3, end_x], [2, end_x], [1, end_x]])
			else:
				_attempt([[2, end_x], [1, end_x], [3, end_x]])
			continue
		var room := minf(to_pitch, _L - 80 - sh)
		var pick2 := _r.next()
		var jst := _sv("jumps")
		var tst := _sv("twist")
		if pk < 0 and sh > _hill - 80:
			# past the mountain: the trail runs on through the hills, never long without a twist
			_attempt([[0, 40 + _r.next() * 90]])
			sh = _sp()
			var end_x := sh + 50 + _r.next() * 70
			# what comes next depends on the mountain under it (TerrainField.range_at): its descent is where the slow
			# technical riding is (tight hairpin stacks, switchbacks, rock chutes); no jump lines up a climb
			_M.range_at(sh + 30.0)
			var down: bool = _M.rg_down > 0.5
			var climbing: bool = _M.hill_top(sh + 60.0) > _M.hill_top(sh) + 1.5
			# the style's twist: fewer / more of the tight sections (a low twist turns some of them into plain road, a high one
			# adds hairpin sections); the jump-line pick follows the jumps style. twist 1 / jumps 1 = the original picks.
			var swap := tst < 1.0 and fposmod(pick2 * 977.0, 1.0) < (1.0 - tst) * 0.9
			var jcut := 0.92 if jst == 1.0 else clampf(1.0 - 0.08 * jst, 0.81, 1.0)
			var did_jump := false
			if down:
				if pick2 < 0.4:
					_section([[6, end_x], [1, end_x], [2, end_x]], swap)
				elif pick2 < 0.62:
					_section([[1, end_x], [6, end_x], [2, end_x]], swap)
				elif pick2 < 0.8:
					_section([[2, end_x], [1, end_x], [3, end_x]], swap)
				elif pick2 < jcut:
					_section([[3, end_x], [2, end_x], [1, end_x]], swap)
				else:
					_attempt([[4, 0.0]])
					did_jump = true
			else:
				var q := _jump_remap(pick2, jst, 0.3)
				if q < 0.3 and not climbing:
					_attempt([[4, 0.0]])
					did_jump = true
				elif q < 0.55:
					_section([[2, end_x], [1, end_x], [3, end_x]], swap)
				elif q < 0.68:
					_section([[6, end_x], [1, end_x], [2, end_x]], swap)
				elif q < 0.84:
					_section([[1, end_x], [2, end_x], [3, end_x]], swap)
				else:
					_section([[3, end_x], [2, end_x], [1, end_x]], swap)
			if tst > 1.0 and not did_jump and fposmod(pick2 * 613.0, 1.0) < (tst - 1.0) * 0.7:
				_attempt([[6, end_x], [1, end_x], [2, end_x]])
			continue
		if room > 230 and pick2 < 0.7 * clampf(jst, 0.0, 1.35):
			_attempt([[0, maxf(50, room - 190)]])
			_attempt([[4, 0.0]] if jst > 0.05 else [[5, 0.0]])
		elif room > 150 and pick2 < 0.85:
			_attempt([[0, maxf(50, room - 110)]])
			_attempt([[5, 0.0]])
		else:
			_attempt([[0, maxf(40, to_pitch - 20)]])
	n = X.size()
	_send = _sp()


# ---------------- derived data ----------------
func _avg(src: PackedFloat32Array, rad: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(maxi(0, i - rad), mini(n - 1, i + rad) + 1):
			s += src[k]
			c += 1
		out[i] = s / c
	return out


func _finish() -> void:
	# each point's place along the route spine (the mountain's end and the rolling land are measured along it)
	_sps = PackedFloat64Array(); _sps.resize(n)
	for i in n:
		_M.spine_near(X[i], Z[i])
		_sps[i] = _M.sp_s
	TX.resize(n); TZ.resize(n)
	var th := PackedFloat32Array(); th.resize(n)
	for i in n:
		var a := maxi(0, i - 1)
		var b := mini(n - 1, i + 1)
		var dx := X[b] - X[a]
		var dz := Z[b] - Z[a]
		var l := sqrt(dx * dx + dz * dz)
		if l == 0.0:
			l = 1.0
		TX[i] = dx / l; TZ[i] = dz / l; th[i] = atan2(dz, dx)
	var kap := PackedFloat32Array(); kap.resize(n)
	for i in range(1, n - 1):
		kap[i] = wrap_angle(th[i + 1] - th[i - 1]) / (2 * STEP)
	KAP = _avg(kap, 2)
	var wsrc := PackedFloat32Array(); wsrc.resize(n)
	for i in n:
		wsrc[i] = WIDTH[KD[i]]
	W = _avg(wsrc, 5)
	# the height first (the banks are sized from the speed it gives)
	var raw := PackedFloat32Array(); raw.resize(n)
	for i in n:
		raw[i] = maxf(TerrainField.WATER + 0.7, _M.landform(X[i], Z[i]))
	var sm := _avg(raw, 5)
	for i in range(1, n):
		sm[i] = minf(sm[i], sm[i - 1])
	E = _avg(sm, 2)
	if _L > _hill + 1.0:
		# past the mountain the trail follows the rolling land (smoothed hard, so climbs stay gentle)
		var fr := _avg(_avg(_avg(raw, 10), 10), 10)
		for i in n:
			var w := smooth(_hill + 60, _hill + 360, _sps[i])
			if w > 0.0:
				E[i] = E[i] + (fr[i] - E[i]) * w
	_shape_profile()
	# BT is SIGNED: > 0 = berm on the left (turning left), < 0 = on the right. Each turn's bank is
	# held a little past its ends (keeps the peak) and then smoothed three times (≈ a gaussian,
	# ~20 m each way) so it builds up into the turn and unwinds out of it with no corner or step.
	var bsrc := PackedFloat32Array(); bsrc.resize(n)
	for i in n:
		var k: float = KAP[i]
		bsrc[i] = signf(k) * minf(0.6, 17 * absf(k)) * smooth(0.012, 0.03, absf(k)) * BERM[KD[i]]
	# ...and a bend that can carry a berm gets at least the bank the speed riders arrive at needs (up to BANK_MAX), so
	# it can be ridden without braking it all away (docs/research/ride_feel.md, change 1)
	if OS.get_environment("BMX_OLD_BANK") == "":
		var need := _bank_need(bsrc)
		for i in n:
			if absf(need[i]) > absf(bsrc[i]): bsrc[i] = need[i]
	var held := PackedFloat32Array(); held.resize(n)
	for i in n:
		var best := 0.0
		for k in range(maxi(0, i - 6), mini(n - 1, i + 6) + 1):
			if absf(bsrc[k]) > absf(best):
				best = bsrc[k]
		held[i] = best
	BT = _avg(_avg(_avg(held, 5), 5), 5)
	_racing_line()   # (after BT: on a berm the line rides the berm)
	var rd := PackedFloat32Array(); rd.resize(n)
	var rk := PackedFloat32Array(); rk.resize(n)
	for i in n:
		var k: int = KD[i]
		rd[i] = 1.0 if (k == ROAD or k == START or k == FINISH) else 0.0
		rk[i] = 1.0 if k == ROCKS else 0.0
	RD = _avg(rd, 4)
	RK = _avg(rk, 4)
	_speed_profile()
	length = (n - 1) * STEP
	# dense spatial hash
	var mins := Vector2i(1 << 30, 1 << 30)
	var maxs := Vector2i(-(1 << 30), -(1 << 30))
	var keys := PackedInt32Array(); keys.resize(maxi(0, n - 1) * 2)
	for i in n - 1:
		var gx := floori((X[i] + X[i + 1]) / 2 / CELL)
		var gz := floori((Z[i] + Z[i + 1]) / 2 / CELL)
		keys[i * 2] = gx; keys[i * 2 + 1] = gz
		mins = Vector2i(mini(mins.x, gx), mini(mins.y, gz))
		maxs = Vector2i(maxi(maxs.x, gx), maxi(maxs.y, gz))
	gx0 = mins.x; gz0 = mins.y
	gnx = maxs.x - mins.x + 1; gnz = maxs.y - mins.y + 1
	var counts := PackedInt32Array(); counts.resize(gnx * gnz + 1)
	for i in n - 1:
		counts[(keys[i * 2] - gx0) * gnz + keys[i * 2 + 1] - gz0 + 1] += 1
	for c in range(1, counts.size()):
		counts[c] += counts[c - 1]
	cell_start = counts.duplicate()
	cell_items.resize(n - 1)
	var fill := counts.duplicate()
	for i in n - 1:
		var c := (keys[i * 2] - gx0) * gnz + keys[i * 2 + 1] - gz0
		cell_items[fill[c]] = i
		fill[c] += 1


## the line a good rider takes, from the curvature alone: a short average of it minus a long one is positive at
## an apex (-> the inside) and negative just before and after the turn (-> the outside); straights sit in the middle.
## Then the run-offs: at some sharp corners one rider's skid leaves the line before the apex and carries straight on
## off the outside. Both depend only on the layout near them, so growing the trail leaves the ridden part alone.
func _racing_line() -> void:
	var kn := _avg(KAP, 4)
	var kw := _avg(_avg(KAP, 14), 14)
	var ln := PackedFloat32Array(); ln.resize(n)
	for i in n:
		ln[i] = clampf(37.0 * (kn[i] - kw[i]), -1.0, 1.0) * maxf(0.0, W[i] - 0.6)
	# on a banked bend the line rides the berm: up its face on the outside (berm_shape's bank is there, from the
	# centreline out), not on the flat inside of it - cutting to the inside missed the bank (the bike felt 4-10 deg on
	# berms built at 20-31 deg) and threw away the corner speed it is there to hold (docs/research/ride_feel.md)
	var old_line := OS.get_environment("BMX_OLD_LINE") != ""   # (tests: the line cutting inside, as before)
	for i in n:
		var bw := 0.0 if old_line else smooth(BERM_LINE_FROM, BERM_LINE_FULL, absf(BT[i]))
		if bw > 0.0:
			ln[i] = lerpf(ln[i], -signf(BT[i]) * minf(BERM_LINE, maxf(0.0, W[i] - 0.9)), bw)
	LN = _avg(ln, 3)
	RO = PackedFloat32Array(); RO.resize(n)
	ROS = PackedFloat32Array(); ROS.resize(n)
	var seed_i: int = _mark_seed % 9973
	var i := 12
	while i < n - 60:
		var k := absf(KAP[i])
		if k < 0.035 or k < absf(KAP[i - 1]) or k <= absf(KAP[i + 1]) or _hash(i, seed_i + 77) > 0.4:
			i += 1
			continue
		var i0 := i - 3 - int(_hash(i, seed_i + 78) * 5.0)
		# the skid starts on the line and keeps the heading it had there
		var p0x := X[i0] - TZ[i0] * LN[i0]
		var p0z := Z[i0] + TX[i0] * LN[i0]
		var dx: float = TX[i0]
		var dz: float = TZ[i0]
		var j := i0
		var last := 0.0
		while j < n - 2 and j < i0 + 40:
			var den: float = dx * TX[j] + dz * TZ[j]
			if den < 0.3:
				break
			var tt: float = ((X[j] - p0x) * TX[j] + (Z[j] - p0z) * TZ[j]) / den
			last = -(p0x + dx * tt - X[j]) * TZ[j] + (p0z + dz * tt - Z[j]) * TX[j]
			RO[j] = last
			ROS[j] = minf(1.0, 0.35 + 0.35 * (j - i0))
			j += 1
			if absf(last) > W[j] + 2.4:
				break
		# either side of it the place is held (strength 0) so the ends fade instead of sweeping across the trail
		for q in range(maxi(0, i0 - 2), i0):
			if ROS[q] == 0.0: RO[q] = RO[i0]
		for q in range(j, mini(n, j + 2)):
			if ROS[q] == 0.0: RO[q] = last
		i = j + 20


static func _hash(k: int, salt: int) -> float:
	var v := sin(float(k) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return v - floor(v)


## makes the trail height livelier: rolling dips, drop-offs, and (very rarely) a huge cliff to launch off.
## Everything depends only on position along the trail (and the seed), and events near the laid-out end are
## skipped, so growing the trail never changes what the rider has already seen.
func _shape_profile() -> void:
	var seed_i: int = _mark_seed % 9973
	var roll := _sv("rolling")   # RouteStyle.rolling: how much the trail rolls (dips) and how many cliff drops
	# rolling dips on the open trail (not in the mountain's steep section)
	for i in n:
		var w := smooth(_hill + 60, _hill + 360, _sps[i])
		if w <= 0.0 or KD[i] != ROAD:
			continue
		var s := i * STEP
		var amp := (0.3 + 1.5 * (0.5 + 0.5 * sin(s / 310.0 + seed_i))) * roll
		E[i] += w * amp * sin(s * TAU / 60.0 + 0.7 * sin(s / 140.0))
	if not OLD_FLOW:
		# grade reversals: on a descent, a gentle dip-and-rise every 25-45 m (a 0.3-0.6 m wave on top of the fall). Where trail
		# builders put them for drainage riders pump them; the trail never just runs one straight slope down. Phase summed
		# from the start, so growing the trail never changes the part already laid out
		var e0 := E.duplicate()
		var ph := 0.0
		for i in n:
			var s := i * STEP
			ph += TAU * STEP / (35.0 + 10.0 * sin(s / 170.0 + seed_i * 0.37))
			if i < 10 or i >= n - 10 or KD[i] == JUMP or KD[i] == ROCKS or KD[i] == START or KD[i] == FINISH:
				continue
			var gr := (e0[i + 10] - e0[i - 10]) / (20.0 * STEP)
			var w := smooth(0.03, 0.07, -gr)
			if w > 0.0:
				E[i] += w * (0.45 + 0.15 * sin(s / 230.0 + seed_i)) * sin(ph)
	drops = []
	var last_end := 0
	var SLOT := 80
	var k := 1
	while k * SLOT + 20 < n - 80:
		var kk := k
		k += 1
		var r := _hash(kk, seed_i)
		var big := r < 0.02 * roll
		if not big and r > 0.16 * roll:
			continue
		var hh := (12.0 + _hash(kk, seed_i + 1) * 10.0) if big else (3.0 + _hash(kk, seed_i + 1) * 3.5)
		# the trail climbs on to a ridge (gently: ~4 %), runs level a moment, then falls away in a cliff
		var ramp := int(hh / 0.04 / STEP)
		var hold := 6 + int(_hash(kk, seed_i + 2) * 6.0)
		var prof := _drop_shape(hh, big) if not OLD_DROPS else PackedFloat32Array()
		var dl := int(ceil(((prof.size() - 1) * DROP_DX if not OLD_DROPS else 5.0 + hh * 0.4) / STEP))
		var a := -1
		var e := 0
		for off in range(0, SLOT, 4):
			var a0 := kk * SLOT + off + ramp
			var e0 := a0 + hold + dl
			if a0 - ramp < last_end + 10 or e0 + 8 >= n - 80:
				continue
			var ok := true
			for q in range(a0 + hold - 14, e0 + 8):
				if KD[q] != ROAD or absf(KAP[q]) > 0.012:
					ok = false
					break
			if ok:
				a = a0
				e = e0
				break
		if a < 0:
			continue
		for q in range(a - ramp, e + 1):
			var lift := hh
			if q < a:
				lift = hh * smooth(0.0, 1.0, float(q - (a - ramp)) / ramp)
			elif q > a + hold:
				if OLD_DROPS: lift = hh * (1.0 - smooth(0.0, 1.0, float(q - (a + hold)) / dl))
				else: lift = hh - _drop_at(prof, (q - (a + hold)) * STEP)
			E[q] += lift
		drops.append([a - ramp, e])
		last_end = e


## The drop-offs used to fall their 3-6.5 m (12-22 m cliffs) over 5 + 0.4 x height metres on a smoothstep: a 1.6 m
## radius crest into a ~47-65 deg face. At trail speed the crest threw the rider off flat and he came down on the
## flat at the bottom from the whole height (EFH = the height: a slam every time; user: "nobody would build this
## step, it wipes people off the track"). Now the face is laid out from the flight: off the level top it falls along
## the path a rider at DROP_V flies (depth = g x^2 / 2 v^2, so anyone up to that speed floats down onto it or rolls it,
## slower riders simply ride it, the curve presses them less than g), at most DROP_SMAX (35 deg, big cliffs 38) as a
## straight, then a bottom transition of DROP_RB (2 g at ~70 km/h). BMX_OLD_DROPS=1 = the old ones.
const DROP_V := 16.0          # m/s (~58 km/h): the fastest a rider rolls off; faster still lands on the transition
const DROP_SMAX := 0.70       # tan: steepest straight face (35 deg)
const DROP_SMAX_BIG := 0.78
const DROP_RB := 22.0         # m: the bottom transition's radius
const DROP_DX := 0.25         # m: the shape's sampling
static var OLD_DROPS := OS.get_environment("BMX_OLD_DROPS") != ""

## depth below the lip every DROP_DX m from it, ending at exactly hh
static func _drop_shape(hh: float, big: bool) -> PackedFloat32Array:
	var smax := DROP_SMAX_BIG if big else DROP_SMAX
	var out := PackedFloat32Array([0.0])
	var d := 0.0
	var x := 0.0
	var s := 0.0
	var bending := false
	var guard := 0
	while guard < 4000:
		guard += 1
		x += DROP_DX
		var a := atan(s)
		if not bending and hh - d <= DROP_RB * (1.0 - cos(a)) and s > 0.0:
			bending = true
		if bending:
			a = maxf(0.0, a - DROP_DX / (DROP_RB * maxf(0.3, cos(a))))
			s = tan(a)
		else:
			s = minf(smax, 9.81 * x / (DROP_V * DROP_V))
		d += s * DROP_DX
		out.append(d)
		if bending and s <= 1e-4: break
	var k := hh / maxf(1e-3, d)
	for i in out.size(): out[i] *= k
	return out

static func _drop_at(prof: PackedFloat32Array, x: float) -> float:
	var f := x / DROP_DX
	var i := int(f)
	if i >= prof.size() - 1: return prof[prof.size() - 1]
	return lerpf(prof[i], prof[i + 1], f - i)


## the bank (signed tan, like BT) each point of a bend needs for the speed a rider rolls into it at (VA's model, no
## brakes since the last bend), on bends whose kind carries berms; base = the shape-only bank (signed). A bend still too
## tight at BANK_MAX slows the rider to what it allows (he brakes) before the next one is judged
func _bank_need(base: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n)
	var v2 := VA_START * VA_START
	for i in range(1, n):
		var v := sqrt(v2)
		var a := -VA_ROLL - VA_DRAG * v2 + (VA_PEDAL if v < VA_PED_TOP else 0.0)
		v2 = clampf(v2 + 2.0 * (9.81 * (E[i - 1] - E[i]) + a * STEP), 4.0, VA_MAX * VA_MAX)
		var k := absf(KAP[i])
		if k > 0.004:
			var t := 0.0
			if BERM[KD[i]] >= 0.4:
				t = clampf((v2 * k - A_RIDE) / 9.81, 0.0, BANK_MAX)
				out[i] = signf(KAP[i]) * t
			v2 = minf(v2, (A_RIDE + 9.81 * maxf(t, absf(base[i]))) / k)
	return out


## VA: the arrival speed along the trail (see VA_*): gravity down the trail's height E, rolling + air drag, pedalling
## when slow; in a bend no more than its radius and bank allow (the rider brakes for it, before or in it)
func _speed_profile() -> void:
	VA.resize(n)
	var v2 := VA_START * VA_START
	VA[0] = VA_START
	for i in range(1, n):
		var v := sqrt(v2)
		var a := -VA_ROLL - VA_DRAG * v2 + (VA_PEDAL if v < VA_PED_TOP else 0.0)
		v2 = clampf(v2 + 2.0 * (9.81 * (E[i - 1] - E[i]) + a * STEP), 4.0, VA_MAX * VA_MAX)
		var k := absf(KAP[i])
		if k > 0.004:
			var bank := absf(BT[i]) if BT.size() == n else 0.0
			v2 = minf(v2, (A_RIDE + 9.81 * bank) / k)
		VA[i] = sqrt(v2)


## point on the centreline at arc length s -> [x, z, tx, tz, i]
func at(s: float) -> Array:
	var f := minf(n - 1.001, maxf(0.0, s / STEP))
	var i := floori(f)
	var t := f - i
	return [X[i] + (X[i + 1] - X[i]) * t, Z[i] + (Z[i + 1] - Z[i]) * t, float(TX[i]), float(TZ[i]), i]


func runs() -> Array:
	var out := []
	var s := 0
	for i in range(1, n + 1):
		if i == n or KD[i] != KD[s]:
			out.append([s, i - 1, KD[s]])
			s = i
	return out


# ---------------- fences and tape ----------------
## BMX_OLD_MARKING=1 = tape also beside the start / finish picket fences and in a ranch fence's gate gaps (before 2026-11-25)
static var OLD_MARKING := OS.get_environment("BMX_OLD_MARKING") != ""

func plan_marking(field) -> void:
	var r := WorldRng.new(_mark_seed)
	var rr := runs()
	var tape0 := PackedByteArray(); tape0.resize(n)
	var tape1 := PackedByteArray(); tape1.resize(n)
	var caution := PackedByteArray(); caution.resize(n)
	var lead := WorldRng.jround(22 / STEP)
	for run in rr:
		var i0: int = run[0]
		var i1: int = run[1]
		var k: int = run[2]
		for i in range(i0, i1 + 1):
			if k != ROAD:
				tape0[i] = 1; tape1[i] = 1
			else:
				var near_end := i - i0 < lead or i1 - i < lead
				if near_end:
					tape0[i] = 1; tape1[i] = 1
				elif absf(KAP[i]) > 1.0 / 75:
					if KAP[i] > 0:
						tape1[i] = 1
					else:
						tape0[i] = 1
			if k == ROCKS or k == SWITCH:
				caution[i] = 1
		if k == ROCKS or k == SWITCH:
			for i in range(maxi(0, i0 - lead), i0):
				caution[i] = 1
	var fs0 := PackedByteArray(); fs0.resize(n)
	var fs1 := PackedByteArray(); fs1.resize(n)
	fences = []
	for run in rr:
		var i0: int = run[0]
		var i1: int = run[1]
		var k: int = run[2]
		if k != ROAD or (i1 - i0) * STEP < 50 or r.next() < 0.2:
			continue
		var sides := []
		if r.next() < 0.35:
			sides = [0, 1]
		else:
			sides = [0 if r.next() < 0.5 else 1]
		for sd in sides:
			var sgn := -1.0 if sd else 1.0
			var posts := []
			var s := (i0 + lead + 2) * STEP
			var gate_in: int = 8 + int(r.next() * 16)
			var s_end := (i1 - lead - 2) * STEP
			while s < s_end:
				var p := at(s)
				var i: int = p[4]
				var o: float = W[i] + 2.8
				posts.append([p[0] - p[3] * o * sgn, p[1] + p[2] * o * sgn])
				for j in range(maxi(0, i - 1), mini(n - 1, i + 1) + 1):
					if sd: fs1[j] = 1
					else: fs0[j] = 1
				var kk: float = KAP[i] * sgn
				s += 2.4 / maxf(0.6, 1 - kk * o)
				gate_in -= 1
				if gate_in <= 0:
					if posts.size() >= 3:
						fences.append({"posts": posts, "style": "ranch"})
					posts = []
					s += 2.4 * (1 + int(r.next() * 2))
					gate_in = 8 + int(r.next() * 18)
					# (the gate's gap is no place for a bit of tape: fence + tape side by side looked wrong)
					if not OLD_MARKING:
						var ge: int = at(minf(s, s_end))[4]
						for j in range(maxi(0, i - 1), mini(n - 1, ge + 1) + 1):
							if sd: fs1[j] = 1
							else: fs0[j] = 1
			if posts.size() >= 3:
				fences.append({"posts": posts, "style": "ranch"})
	for run in rr:
		var i0: int = run[0]
		var i1: int = run[1]
		var k: int = run[2]
		if k != START and k != FINISH:
			continue
		for sgn in [1.0, -1.0]:
			var posts := []
			var s := i0 * STEP + (4.0 if k == START else 10.0)
			while s < i1 * STEP - 4:
				var p := at(s)
				var o: float = W[p[4]] + 3.2
				posts.append([p[0] - p[3] * o * sgn, p[1] + p[2] * o * sgn])
				if not OLD_MARKING:
					var pi: int = p[4]
					for j in range(maxi(0, pi - 1), mini(n - 1, pi + 1) + 1):
						if sgn < 0.0: fs1[j] = 1
						else: fs0[j] = 1
				s += 2.4
			if posts.size() >= 3:
				fences.append({"posts": posts, "style": "picket"})
	stakes = []
	for sd in [0, 1]:
		var sgn := -1.0 if sd else 1.0
		var s := 0.0
		var last := -1
		while s < length:
			var p := at(s)
			var i: int = p[4]
			var k: float = KAP[i]
			var o: float = W[i] + 1.7
			var inside := k * sgn > 0
			var R := 1.0 / maxf(1e-4, absf(k))
			var tside: int = tape1[i] if sd else tape0[i]
			var fside: int = fs1[i] if sd else fs0[i]
			var want := tside != 0 and not (fside != 0 and (KD[i] == ROAD or not OLD_MARKING)) and not (inside and R < o + 2.2)
			if want:
				var st := {"x": p[0] - p[3] * o * sgn, "z": p[1] + p[2] * o * sgn, "s": s, "side": sgn,
					"caution": caution[i] != 0, "prev": -1}
				if last >= 0 and s - stakes[last]["s"] < 9:
					var lst: Dictionary = stakes[last]
					var mx: float = (st["x"] + lst["x"]) / 2
					var mz: float = (st["z"] + lst["z"]) / 2
					field.query(mx, mz)
					if field.q_d > field.q_w + 0.4:
						st["prev"] = last
				stakes.append(st)
				last = stakes.size() - 1
			else:
				last = -1
			var step := minf(7.5, maxf(3.0, 0.32 / maxf(1e-4, absf(k))))
			if inside:
				# the stake line is shorter than the centreline on the inside of a bend: keep the sticks >= 3.6 m apart
				step = maxf(step, 3.6 / maxf(0.25, 1.0 - o * absf(k)))
			s += step
	# both sides merged in course order, so a stake keeps its index when the course grows
	var order := range(stakes.size())
	order.sort_custom(func(a, b): return stakes[a]["s"] < stakes[b]["s"] or (stakes[a]["s"] == stakes[b]["s"] and a < b))
	var remap := PackedInt32Array(); remap.resize(stakes.size())
	for j in order.size():
		remap[order[j]] = j
	var merged := []
	for j in order:
		var st: Dictionary = stakes[j]
		if st["prev"] >= 0:
			st["prev"] = remap[st["prev"]]
		merged.append(st)
	stakes = merged
	# the START / FINISH picket fences were appended after the course fences: move them to the front
	var pick := []
	var rest := []
	for fc in fences:
		(pick if fc["style"] == "picket" else rest).append(fc)
	fences = pick + rest
	_bucket()


static func chunk_key(cx: int, cz: int) -> int:
	return cx * 1048576 + cz


func _chunk_of(x: float, z: float) -> int:
	return chunk_key(WorldRng.jround(x / CHUNK), WorldRng.jround(z / CHUNK))


static func _add(d: Dictionary, k: int, v: int) -> void:
	if not d.has(k):
		d[k] = PackedInt32Array()
	var l: PackedInt32Array = d[k]
	if l.is_empty() or l[l.size() - 1] != v:
		l.append(v)
	d[k] = l


func _bucket() -> void:
	chunk_rocks = {}; chunk_stakes = {}; chunk_fences = {}; chunk_gates = {}; chunk_boards = {}; chunk_arches = {}; chunk_signs = {}
	var sign_every := SIGN_EVERY
	if OS.get_environment("BMX_SIGN_EVERY") != "":
		sign_every = maxi(20, int(OS.get_environment("BMX_SIGN_EVERY")))   # test: signs closer together
	if sign_every == SIGN_EVERY and SIGN_FIRST < n - 2:
		_add(chunk_signs, _chunk_of(X[SIGN_FIRST], Z[SIGN_FIRST]), SIGN_FIRST)   # an early one at 1 km, then every 5 km
	for i in range(sign_every, n - 2, sign_every):
		_add(chunk_signs, _chunk_of(X[i], Z[i]), i)
	for i in range(BOARD_FIRST, n - 2, BOARD_EVERY):
		var gd := posmod(i - GATE_FIRST, GATE_EVERY)
		if gd < 8 or gd > GATE_EVERY - 8:
			continue   # not right under a gate
		var kb := KD[i]
		if kb == ROAD or kb == START or kb == FINISH:
			_add(chunk_boards, _chunk_of(X[i], Z[i]), i)
	for i in n - 1:
		if KD[i] == ROCKS:
			_add(chunk_rocks, _chunk_of(X[i], Z[i]), i)
	# sponsor gates: fixed spacing by index, so growing the course never moves one
	for i in range(GATE_FIRST, n - 2, GATE_EVERY):
		var kd := KD[i]
		if kd == ROAD or kd == START or kd == ESSES or kd == FINISH:
			_add(chunk_gates, _chunk_of(X[i], Z[i]), i)
	# rare rock tunnels / overhangs on straight bits of road, one candidate per 200 m slot
	var seed_i: int = _mark_seed % 9973
	for k in range(2, n / 100):
		var kind := TrailArch.kind_for(k, seed_i)
		if kind < 0:
			continue
		var ci := -1
		for off in range(10, 90, 4):
			var c0 := k * 100 + off
			if c0 + 20 >= n - 2:
				break
			var okc := true
			for q in range(c0 - 12, c0 + 13):
				if KD[q] != ROAD or (absi(q - c0) <= 8 and absf(KAP[q]) > 0.012):
					okc = false
					break
			for dr in drops:
				if c0 + 20 > dr[0] and c0 - 20 < dr[1]:
					okc = false
			var gd2 := posmod(c0 - GATE_FIRST, GATE_EVERY)
			if gd2 < 14 or gd2 > GATE_EVERY - 14:
				okc = false
			if okc:
				ci = c0
				break
		if ci < 0:
			continue
		_add(chunk_arches, _chunk_of(X[ci], Z[ci]), ci * 2 + kind)
	for k in stakes.size():
		_add(chunk_stakes, _chunk_of(stakes[k]["x"], stakes[k]["z"]), k)
	for fi in fences.size():
		for p in fences[fi]["posts"]:
			_add(chunk_fences, _chunk_of(p[0], p[1]), fi)
