class_name TrailFeatures
extends RefCounted
## Port of features.js: hand-shaped trail feature profiles (cubic Hermite knots), wooden decks and digs.


class Profile:
	extends RefCounted
	var length: float = 0.0
	func ev(_u: float) -> float:
		return 0.0


class Hermite:
	extends Profile
	var ku := PackedFloat64Array()
	var kh := PackedFloat64Array()
	var ksi := PackedFloat64Array()
	var kso := PackedFloat64Array()
	# knots: Array of [u, h, slopeIn, (slopeOut)]
	func _init(knots: Array) -> void:
		for k in knots:
			ku.append(k[0]); kh.append(k[1]); ksi.append(k[2])
			kso.append(k[3] if k.size() > 3 else k[2])
		length = ku[ku.size() - 1]
	func ev(u: float) -> float:
		if u <= 0.0 or u >= length:
			return 0.0
		var i := 0
		while ku[i + 1] < u:
			i += 1
		var u0: float = ku[i]
		var h0: float = kh[i]
		var so0: float = kso[i]
		var u1: float = ku[i + 1]
		var h1: float = kh[i + 1]
		var si1: float = ksi[i + 1]
		var d := u1 - u0
		var t := (u - u0) / d
		var t2 := t * t
		var t3 := t2 * t
		return (2 * t3 - 3 * t2 + 1) * h0 + (t3 - 2 * t2 + t) * d * so0 + (-2 * t3 + 3 * t2) * h1 + (t3 - t2) * d * si1


class Rollers:
	extends Profile
	var w: Hermite
	var n: int
	func _init(count: int, amp: float) -> void:
		var ks := []
		for k in WHOOP:
			ks.append([k[0], k[1] * amp / 0.48, k[2] * amp / 0.48])
		w = Hermite.new(ks)
		n = count
		length = n * w.length
	func ev(u: float) -> float:
		if u <= 0.0 or u >= n * w.length:
			return 0.0
		return w.ev(fmod(u, w.length))


class Line:
	extends Profile
	var starts := PackedFloat64Array()
	var parts: Array = []
	func _init(items: Array) -> void:
		var at := 0.0
		for p in items:
			if p is float or p is int:
				at += float(p)
				continue
			starts.append(at)
			parts.append(p)
			at += p.length
		length = at
	func ev(u: float) -> float:
		for i in parts.size():
			var s: float = starts[i]
			var p: Profile = parts[i]
			if u > s and u < s + p.length:
				return p.ev(u - s)
		return 0.0


class Flat:
	extends Profile
	func _init(l: float) -> void:
		length = l


## wooden deck: top(u) above the flattened ground for u0 <= u <= u1, |w| <= half
## riding a deck: grace past the plank edge (m), side bevel slope, and the deck height below which the
## sides are bevelled (the ramp-up parts; bridge / skinny / kicker tops keep a real edge)
const WOOD_EDGE := 0.12
const WOOD_BEVEL := 1.2
const WOOD_BEVEL_MAX := 0.44

class Wood:
	extends RefCounted
	var kind: int   # 0 woodKicker, 1 skinny, 2 bridge
	var u0: float
	var u1: float
	var half: float
	var back_wall: bool
	var kick: Profile
	var skin: Profile
	func _init(k: int, a: float, b: float, hf: float, bw: bool, kk: Profile, sk: Profile) -> void:
		kind = k; u0 = a; u1 = b; half = hf; back_wall = bw; kick = kk; skin = sk
	func top(u: float) -> float:
		if kind == 0:
			return 0.95 if u >= 3.8 else kick.ev(u)
		elif kind == 1:
			if u < 4.0:
				return skin.ev(u)
			if u < 15.0:
				return 0.85
			return skin.ev(maxf(0.001, 19.0 - u))
		else:
			if u < 2.0:
				return _ramp(0.0, 2.0, 0.02, 0.45, u)
			if u < u1 - 2.0:
				return 0.45
			return _ramp(u1 - 2.0, u1, 0.45, 0.02, u)
	static func _ramp(a: float, b: float, h0: float, h1: float, u: float) -> float:
		return h0 + (h1 - h0) * minf(1.0, maxf(0.0, (u - a) / (b - a)))


# The trail's built jumps are laid out by JumpDesign (scripts/world/jump_design.gd: clothoid take-off at <= 1.5 g, a
# straight lip 0.15-0.2 s long, a deck as long as the flight, a landing matched to it) and baked into these knots by
# tools/bake_jumps.gd (+ bake_jumps.py writes them here and into TerrainFieldCs.cs: never edit them by hand). Sized so a
# rider at ~60 km/h comes down on the landing's sweet spot and anyone slower cases the deck (EFH < ~1 m), never the
# flat. (2026-11-23; before: hand-shaped Hermites whose face kept curving to the lip's edge = a kicky lip, the landing
# overshot at trail speed.) DOUBLE (free ride only) is still the hand-shaped one.
const TABLE := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0004, 0.0016, 0.0016], [2.6, 0.0033, 0.0063, 0.0063], [3.4, 0.0113, 0.0141, 0.0141], [4.25, 0.028, 0.0258, 0.0258], [5.05, 0.0541, 0.0401, 0.0401], [5.9, 0.0959, 0.0588, 0.0588], [6.75, 0.155, 0.081, 0.081], [7.55, 0.2294, 0.1054, 0.1054], [8.4, 0.3313, 0.135, 0.135], [9.2, 0.4517, 0.1666, 0.1666], [10.05, 0.6091, 0.2044, 0.2044], [10.85, 0.7883, 0.2444, 0.2444], [11.7, 1.0159, 0.292, 0.292], [12.55, 1.2865, 0.346, 0.346], [13.35, 1.5858, 0.4035, 0.4035], [13.4, 1.606, 0.404, 0.404], [15.95, 2.6179, 0.404, 0.0], [28.75, 2.6179, 0.0, 0.0], [29.55, 2.4782, -0.3371, -0.3371], [29.75, 2.3993, -0.4225, -0.4225], [32.9, 1.0729, -0.4225, -0.4225], [33.7, 0.7661, -0.35, -0.35], [34.55, 0.5012, -0.278, -0.278], [35.4, 0.2958, -0.2098, -0.2098], [36.2, 0.1543, -0.1482, -0.1482], [37.05, 0.0572, -0.0844, -0.0844], [37.9, 0.0138, -0.0216, -0.0216], [38.2, 0.0, 0.0, 0.0], [39.2, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const DOUBLE := [[0, 0, 0], [8.0, 2.16, 0.58, -1.6], [9.6, 0.56, 0, 0], [12.0, 0.56, 0, 1.4],
	[14.72, 1.92, 0, 0], [16.32, 1.92, 0, 0], [20.0, 1.36, -0.34], [30.4, 0.24, -0.16], [36.8, 0, 0]]
const KICKER := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0007, 0.0026, 0.0026], [2.6, 0.0056, 0.0105, 0.0105], [3.4, 0.0189, 0.0236, 0.0236], [4.25, 0.0469, 0.0434, 0.0434], [5.05, 0.0909, 0.0674, 0.0674], [5.9, 0.1612, 0.099, 0.099], [6.75, 0.2609, 0.1369, 0.1369], [7.55, 0.3868, 0.1789, 0.1789], [8.4, 0.5604, 0.2308, 0.2308], [9.2, 0.7671, 0.2876, 0.2876], [9.45, 0.8415, 0.3057, 0.3057], [11.45, 1.4508, 0.3057, 0.0], [22.2, 1.4508, 0.0, 0.0], [22.95, 1.3284, -0.304, -0.304], [25.55, 0.551, -0.304, -0.304], [26.35, 0.3377, -0.2342, -0.2342], [27.15, 0.1788, -0.1676, -0.1676], [27.95, 0.0723, -0.103, -0.103], [28.8, 0.0151, -0.0358, -0.0358], [29.3, 0.0, 0.0, 0.0], [30.3, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
# the same three at their old size: the free-ride jumps out in the land (TerrainField.jump_at), which are found through
# 34 m cells and sit close to each other and to wooden features - bigger, they overlapped (walls at their edges)
const TABLE_S := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0023, 0.0087, 0.0087], [2.6, 0.0186, 0.0349, 0.0349], [3.4, 0.0628, 0.0786, 0.0786], [4.25, 0.1564, 0.1453, 0.1453], [5.05, 0.3047, 0.2293, 0.2293], [5.9, 0.5471, 0.3468, 0.3468], [6.05, 0.6008, 0.364, 0.364], [7.45, 1.0961, 0.364, 0.0], [13.45, 1.0961, 0.0, 0.0], [14.3, 0.9383, -0.3608, -0.3608], [14.4, 0.8995, -0.3904, -0.3904], [15.65, 0.4223, -0.3904, -0.3904], [16.5, 0.1634, -0.2317, -0.2317], [17.3, 0.0362, -0.0963, -0.0963], [17.9, 0.0, 0.0, 0.0], [18.9, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const DOUBLE_S := [[0, 0, 0], [5, 1.35, 0.58, -1.6], [6.0, 0.35, 0, 0], [7.5, 0.35, 0, 1.4],
	[9.2, 1.2, 0, 0], [10.2, 1.2, 0, 0], [12.5, 0.85, -0.34], [19, 0.15, -0.16], [23, 0, 0]]
const KICKER_S := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0058, 0.0219, 0.0219], [2.6, 0.0469, 0.0881, 0.0881], [3.4, 0.1593, 0.2016, 0.2016], [3.85, 0.2692, 0.2867, 0.2867], [4.9, 0.5588, 0.2867, 0.0], [8.75, 0.5588, 0.0, 0.0], [9.5, 0.4363, -0.3063, -0.3063], [10.35, 0.1834, -0.3063, -0.3063], [11.2, 0.0224, -0.0898, -0.0898], [11.6, 0.0, 0.0, 0.0], [12.6, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const WHOOP := [[0, 0, 0], [1.6, 0.3, 0.3], [2.6, 0.48, 0], [8.6, 0.08, -0.09], [10, 0, 0]]


## where riders are in the air over each feature: [from, to, ...] along it (m), the lip to about where they come
## down. The ground shader draws no ridden lines there (ground.gdshader, via TerrainField.fo_air; mirrored in C#)
const AIR := {"table": [15.95, 33.09], "double": [8.0, 17.6], "kicker": [11.45, 25.94], "woodKicker": [3.8, 9.0],
	"tableLine": [15.95, 33.09, 53.65, 68.14], "flow": [11.45, 25.94], "doubleLine": [8.0, 17.6, 51.25, 65.74]}
const AIR_S := {"table": [7.45, 17.17], "double": [5.0, 11.0], "kicker": [4.9, 11.6],
	"tableLine": [7.45, 17.17, 26.8, 33.5], "flow": [4.9, 11.6], "doubleLine": [5.0, 11.0, 30.9, 37.6]}


const FEATURE_TYPES := ["table", "table", "double", "kicker", "rhythm", "tableLine", "flow", "doubleLine",
	"woodKicker", "woodKicker", "skinny", "bridge"]
const ROUTE_TYPES := ["table", "table", "kicker", "rhythm", "tableLine", "flow", "woodKicker", "bridge"]

static var PROFILES: Dictionary = {}
static var WOOD: Dictionary = {}
static var DIG: Dictionary = {}


static func ensure() -> void:
	if not PROFILES.is_empty():
		return
	var st := make_set()
	PROFILES = st["profiles"]
	WOOD = st["wood"]
	DIG = st["dig"]


## a fresh, independent set of profile objects (each worker thread gets its own: no shared refcounts)
static func make_set() -> Dictionary:
	var table := Hermite.new(TABLE)
	var dbl := Hermite.new(DOUBLE)
	var kicker := Hermite.new(KICKER)
	var profiles := {
		"table": table, "double": dbl, "kicker": kicker,
		"rhythm": Rollers.new(4, 0.5),
		"tableLine": Line.new([table, 3.0, kicker]),
		"flow": Line.new([kicker, 3.0, Rollers.new(3, 0.45)]),
		"doubleLine": Line.new([dbl, 3.0, kicker]),
		"woodKicker": Hermite.new([[0, 0, 0], [4.6, 0, 0], [6.4, 0.9, 0.1, 0], [7.4, 0.9, 0, 0], [10, 0.72, -0.17], [20, 0.14, -0.08], [26, 0, 0]]),
		"skinny": Flat.new(19.0),
		"bridge": Flat.new(15.0),
		"gorge": Flat.new(36.0),
		"rope": Flat.new(46.0),
	}
	var kick := Hermite.new([[0, 0, 0.1], [3.8, 0.95, 0.4]])
	var skin := Hermite.new([[0, 0.02, 0.05], [2, 0.42, 0.3], [4, 0.85, 0]])
	var wood := {
		"woodKicker": Wood.new(0, 0.0, 3.8, 0.85, true, kick, skin),
		"skinny": Wood.new(1, 0.0, 19.0, 0.33, false, kick, skin),
		"bridge": Wood.new(2, 0.0, 15.0, 1.0, false, kick, skin),
		"gorge": Wood.new(2, 0.0, 36.0, 1.4, false, kick, skin),
	}
	var dig := {"bridge": Hermite.new([[0, 0, 0], [1.6, 0, 0], [3.4, -1.9, 0], [11.6, -1.9, 0], [13.4, 0, 0], [15, 0, 0]]),
		"gorge": Hermite.new([[0, 0, 0], [3.0, 0, 0], [4.6, -9.0, 0], [31.4, -9.0, 0], [33.0, 0, 0], [36, 0, 0]])}
	var table_s := Hermite.new(TABLE_S)
	var dbl_s := Hermite.new(DOUBLE_S)
	var kicker_s := Hermite.new(KICKER_S)
	var small := {"table": table_s, "double": dbl_s, "kicker": kicker_s, "tableLine": Line.new([table_s, 3.0, kicker_s]),
		"flow": Line.new([kicker_s, 3.0, Rollers.new(3, 0.45)]), "doubleLine": Line.new([dbl_s, 3.0, kicker_s])}
	return {"profiles": profiles, "wood": wood, "dig": dig, "small": small}
