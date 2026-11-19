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
var length: float = 0.0
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

# build state
var _M  # TerrainField (zc, landform, pitches, water)
var _r: WorldRng
var _x := 0.0
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
	return c


## the furthest x laid out so far
func end_x() -> float:
	return _x


## a copy of this course laid out on to x = to_x (field: the TerrainField to read the land from; call
## plan_marking(field) on the result once the field queries it). This course is not changed.
func grown(field, to_x: float) -> TrailCourse:
	var c := TrailCourse.new()
	c._M = field
	c._r = WorldRng.new()
	c._r.a = _r.a
	c._hill = _hill
	c._L = to_x
	c._corr = _corr
	c._mark_seed = _mark_seed
	c._x = _x; c._z = _z; c._h = _h
	c.X = X.duplicate(); c.Z = Z.duplicate(); c.KD = KD.duplicate()
	c._cells = _cells.duplicate()
	c._build()
	c._finish()
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
		if absf(Z[i] - _M.zc(X[i])) > _corr + 15:
			return true
	return false


func _emit(kind: int) -> void:
	_x += cos(_h) * STEP
	_z += sin(_h) * STEP
	X.append(_x); Z.append(_z); KD.append(kind)


func _straight(len: float, kind: int, wob: float = 0.0) -> void:
	var cnt: int = maxi(1, WorldRng.jround(len / STEP))
	var ph := _r.next() * 6.28
	for i in cnt:
		_h += wob * cos(ph + i * 0.35) * 0.06
		_emit(kind)


func _arc(ang: float, R: float, kind: int) -> void:
	var cnt: int = maxi(1, WorldRng.jround(absf(ang) * R / STEP))
	var dh := ang / cnt
	for i in cnt:
		_h += dh / 2
		_emit(kind)
		_h += dh / 2


func _turn_to(target: float, R: float, kind: int) -> void:
	_arc(wrap_angle(target - _h), R, kind)


func _off() -> float:
	return _z - _M.zc(_x)


func _next_pitch() -> int:
	var P: PackedFloat64Array = _M.pitches
	for k in range(0, P.size(), 3):
		if P[k] + P[k + 1] / 2 > _x:
			return k
	return -1


func _snap() -> Array:
	return [_x, _z, _h, X.size()]


func _undo(s: Array) -> void:
	_x = s[0]; _z = s[1]; _h = s[2]
	X.resize(s[3]); Z.resize(s[3]); KD.resize(s[3])


# sections: [code, arg]  code 0 road(maxLen) 1 switchbacks(endX) 2 esses(endX) 3 chute(endX) 4 jumpLine 5 esses(x+50)
func _run(sec: Array) -> void:
	match sec[0]:
		0: _road(sec[1])
		1: _switchbacks(sec[1])
		2: _esses(sec[1])
		3: _chute(sec[1])
		4: _jump_line()
		5: _esses(_x + 50)


func _attempt(fns: Array) -> bool:
	for t in 6:
		var s := _snap()
		_run(fns[t % fns.size()])
		if not _clashes(s[3]):
			_commit(s[3])
			return true
		_undo(s)
	var s2 := _snap()
	_turn_to(0, 30, ROAD)
	_straight(24, ROAD)
	_commit(s2[3])
	return false


func _road(max_len: float) -> void:
	var len := minf(max_len, 90 + _r.next() * 150)
	var done := 0.0
	while done < len:
		var o := _off()
		var lim := _corr - 30
		var tgt := (_r.next() * 2 - 1) * 52 * D2R
		if absf(o) > lim * 0.5:
			tgt = -signf(o) * (18 + _r.next() * 34) * D2R
		var seg := minf(len - done, 26 + _r.next() * 44)
		# now and then a tight bend instead of a sweeper
		var R := (16 + _r.next() * 18) if _r.next() < 0.3 else (38 + _r.next() * 60)
		var n0 := X.size()
		_turn_to(tgt, R, ROAD)
		var used := (X.size() - n0) * STEP
		if used < seg:
			_straight(seg - used, ROAD)
		done += maxf(seg, used)
		if _x > _L - 70:
			break


func _switchbacks(end_x: float) -> void:
	var first := -1 if _off() > 0 else 1
	var alpha := (12 + _r.next() * 10) * D2R
	var R := 7 + _r.next() * 2.5
	var dir := first
	var k := 0
	_turn_to(dir * (PI / 2 - alpha), 11 + _r.next() * 4, SWITCH)
	while k < 6:
		var room := (_corr - 12 - dir * _off()) / cos(alpha)
		_straight(maxf(14, minf(26 + _r.next() * 20, room)), SWITCH, 0.4)
		if _x > end_x and k >= 2:
			break
		dir = -dir
		k += 1
		_turn_to(dir * (PI / 2 - alpha), R, SWITCH)
	_turn_to(0, 12 + _r.next() * 4, SWITCH)
	_straight(8, SWITCH)


func _esses(end_x: float, kind: int = ESSES) -> void:
	var dir := 1 if _r.next() < 0.5 else -1
	var k := 0
	if absf(_off()) > 30:
		dir = -int(signf(_off()))
	while k < 9:
		var ang := (38 + _r.next() * 34) * D2R
		var R := 10 + _r.next() * 8
		_turn_to(dir * ang, R, kind)
		_straight(3 + _r.next() * 6, kind)
		dir = -dir
		k += 1
		if _x > end_x and k >= 3:
			break
	_turn_to(0, 14, kind)


func _chute(end_x: float) -> void:
	_turn_to((_r.next() - .5) * 16 * D2R, 18, ROCKS)
	_straight(maxf(26, end_x - _x + 6), ROCKS, 0.25)


func _jump_line() -> void:
	_turn_to((_r.next() - .5) * 14 * D2R, 40, ROAD)
	_straight(10, ROAD)
	_straight(80 + _r.next() * 50, JUMP)
	_straight(8, ROAD)


func _build() -> void:
	var guard := 0
	var P: PackedFloat64Array = _M.pitches
	while _x < _L - 80 and guard < 4000:
		guard += 1
		var pk := _next_pitch()
		var to_pitch := (P[pk] - P[pk + 1] / 2 - _x) if pk >= 0 else INF
		if to_pitch < 30:
			var end_x: float = P[pk] + P[pk + 1] / 2 + 6
			var pick := _r.next()
			if pick < 0.45:
				_attempt([[1, end_x], [2, end_x], [3, end_x]])
			elif pick < 0.75:
				_attempt([[3, end_x], [2, end_x], [1, end_x]])
			else:
				_attempt([[2, end_x], [1, end_x], [3, end_x]])
			continue
		var room := minf(to_pitch, _L - 80 - _x)
		var pick2 := _r.next()
		if pk < 0 and _x > _hill - 80:
			# past the mountain: the trail runs on through the hills, never long without a twist
			_attempt([[0, 60 + _r.next() * 120]])
			var end_x := _x + 50 + _r.next() * 70
			if pick2 < 0.3:
				_attempt([[4, 0.0]])
			elif pick2 < 0.6:
				_attempt([[2, end_x], [1, end_x], [3, end_x]])
			elif pick2 < 0.8:
				_attempt([[1, end_x], [2, end_x], [3, end_x]])
			else:
				_attempt([[3, end_x], [2, end_x], [1, end_x]])
			continue
		if room > 230 and pick2 < 0.7:
			_attempt([[0, maxf(50, room - 190)]])
			_attempt([[4, 0.0]])
		elif room > 150 and pick2 < 0.85:
			_attempt([[0, maxf(50, room - 110)]])
			_attempt([[5, 0.0]])
		else:
			_attempt([[0, maxf(40, to_pitch - 20)]])
	n = X.size()


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
	# BT is SIGNED: > 0 = berm on the left (turning left), < 0 = on the right. Each turn's bank is
	# held a little past its ends (keeps the peak) and then smoothed three times (≈ a gaussian,
	# ~20 m each way) so it builds up into the turn and unwinds out of it with no corner or step.
	var bsrc := PackedFloat32Array(); bsrc.resize(n)
	for i in n:
		var k: float = KAP[i]
		bsrc[i] = signf(k) * minf(0.6, 17 * absf(k)) * smooth(0.012, 0.03, absf(k)) * BERM[KD[i]]
	var held := PackedFloat32Array(); held.resize(n)
	for i in n:
		var best := 0.0
		for k in range(maxi(0, i - 6), mini(n - 1, i + 6) + 1):
			if absf(bsrc[k]) > absf(best):
				best = bsrc[k]
		held[i] = best
	BT = _avg(_avg(_avg(held, 5), 5), 5)
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
			var w := smooth(_hill + 60, _hill + 360, X[i])
			if w > 0.0:
				E[i] = E[i] + (fr[i] - E[i]) * w
	var rd := PackedFloat32Array(); rd.resize(n)
	var rk := PackedFloat32Array(); rk.resize(n)
	for i in n:
		var k: int = KD[i]
		rd[i] = 1.0 if (k == ROAD or k == START or k == FINISH) else 0.0
		rk[i] = 1.0 if k == ROCKS else 0.0
	RD = _avg(rd, 4)
	RK = _avg(rk, 4)
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
			var want := tside != 0 and not (fside != 0 and KD[i] == ROAD) and not (inside and R < o + 2.2)
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
			s += minf(7.5, maxf(3.0, 0.32 / maxf(1e-4, absf(k))))
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
	chunk_rocks = {}; chunk_stakes = {}; chunk_fences = {}; chunk_gates = {}
	for i in n - 1:
		if KD[i] == ROCKS:
			_add(chunk_rocks, _chunk_of(X[i], Z[i]), i)
	# sponsor gates: fixed spacing by index, so growing the course never moves one
	for i in range(GATE_FIRST, n - 2, GATE_EVERY):
		var kd := KD[i]
		if kd == ROAD or kd == START or kd == ESSES or kd == FINISH:
			_add(chunk_gates, _chunk_of(X[i], Z[i]), i)
	for k in stakes.size():
		_add(chunk_stakes, _chunk_of(stakes[k]["x"], stakes[k]["z"]), k)
	for fi in fences.size():
		for p in fences[fi]["posts"]:
			_add(chunk_fences, _chunk_of(p[0], p[1]), fi)
