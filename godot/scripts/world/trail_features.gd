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
		elif kind == 3:
			# wavy bridge: the deck rolls over normal ground (two humps), ramps on / off like the flat one
			var t := fposmod((u - 2.0) / 5.5, 1.0)
			var base := 0.3 + 0.32 * 16.0 * t * t * (1.0 - t) * (1.0 - t)   # polynomial hump (no sin: C# must match exactly)
			if u < 2.0:
				return _ramp(0.0, 2.0, 0.02, 0.3, u)
			if u < u1 - 2.0:
				return base
			return _ramp(u1 - 2.0, u1, 0.3, 0.02, u)
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
# overshot at trail speed.) DOUBLE / DOUBLE_S too since 2026-11-24 (gaps with a raised floor, `fill`).
const TABLE := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0004, 0.0016, 0.0016], [2.6, 0.0033, 0.0063, 0.0063], [3.4, 0.0113, 0.0141, 0.0141], [4.25, 0.028, 0.0258, 0.0258], [5.05, 0.0541, 0.0401, 0.0401], [5.9, 0.0959, 0.0588, 0.0588], [6.75, 0.155, 0.081, 0.081], [7.55, 0.2294, 0.1054, 0.1054], [8.4, 0.3313, 0.135, 0.135], [9.2, 0.4517, 0.1666, 0.1666], [10.05, 0.6091, 0.2044, 0.2044], [10.85, 0.7883, 0.2444, 0.2444], [11.7, 1.0159, 0.292, 0.292], [12.55, 1.2865, 0.346, 0.346], [13.35, 1.5858, 0.4035, 0.4035], [13.4, 1.606, 0.404, 0.404], [15.85, 2.5774, 0.404, 0.0], [27.6, 2.5774, 0.0, 0.0], [28.4, 2.4377, -0.3371, -0.3371], [28.6, 2.3584, -0.4291, -0.4291], [31.7, 1.031, -0.4291, -0.4291], [32.55, 0.7039, -0.3466, -0.3466], [33.4, 0.4441, -0.27, -0.27], [34.2, 0.2574, -0.2017, -0.2017], [35.05, 0.1175, -0.132, -0.132], [35.9, 0.0359, -0.0642, -0.0642], [36.7, 0.0113, -0.0012, -0.0012], [36.75, 0.0, 0.0, 0.0], [37.75, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const DOUBLE := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0004, 0.0016, 0.0016], [2.6, 0.0033, 0.0063, 0.0063], [3.4, 0.0113, 0.0141, 0.0141], [4.25, 0.028, 0.0258, 0.0258], [5.05, 0.0541, 0.0401, 0.0401], [5.9, 0.0959, 0.0588, 0.0588], [6.75, 0.155, 0.081, 0.081], [7.55, 0.2294, 0.1054, 0.1054], [8.4, 0.3313, 0.135, 0.135], [9.2, 0.4517, 0.1666, 0.1666], [10.05, 0.6091, 0.2044, 0.2044], [10.85, 0.7883, 0.2444, 0.2444], [11.7, 1.0159, 0.292, 0.292], [12.55, 1.2865, 0.346, 0.346], [13.35, 1.5858, 0.4035, 0.4035], [13.4, 1.606, 0.404, 0.404], [15.85, 2.5774, 0.404, -1.1918], [16.2, 2.2, -1.1918, 0.0], [26.45, 2.2, 0.0, 0.7002], [27.0, 2.5774, 0.7002, 0.0], [27.6, 2.5774, 0.0, 0.0], [28.4, 2.4377, -0.3371, -0.3371], [28.6, 2.3584, -0.4291, -0.4291], [31.7, 1.031, -0.4291, -0.4291], [32.55, 0.7039, -0.3466, -0.3466], [33.4, 0.4441, -0.27, -0.27], [34.2, 0.2574, -0.2017, -0.2017], [35.05, 0.1175, -0.132, -0.132], [35.9, 0.0359, -0.0642, -0.0642], [36.7, 0.0113, -0.0012, -0.0012], [36.75, 0.0, 0.0, 0.0], [37.75, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const KICKER := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0007, 0.0026, 0.0026], [2.6, 0.0056, 0.0105, 0.0105], [3.4, 0.0189, 0.0236, 0.0236], [4.25, 0.0469, 0.0434, 0.0434], [5.05, 0.0909, 0.0674, 0.0674], [5.9, 0.1612, 0.099, 0.099], [6.75, 0.2609, 0.1369, 0.1369], [7.55, 0.3868, 0.1789, 0.1789], [8.4, 0.5604, 0.2308, 0.2308], [9.2, 0.7671, 0.2876, 0.2876], [9.45, 0.8415, 0.3057, 0.3057], [11.45, 1.438, 0.3057, 0.0], [21.7, 1.438, 0.0, 0.0], [22.45, 1.3155, -0.3064, -0.3064], [25.0, 0.5381, -0.3064, -0.3064], [25.8, 0.3241, -0.2338, -0.2338], [26.6, 0.1666, -0.1646, -0.1646], [27.4, 0.0635, -0.0976, -0.0976], [28.2, 0.0133, -0.032, -0.032], [28.6, 0.0, 0.0, 0.0], [29.6, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
# the same three at their old size: the free-ride jumps out in the land (TerrainField.jump_at), which are found through
# 34 m cells and sit close to each other and to wooden features - bigger, they overlapped (walls at their edges)
const TABLE_S := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0023, 0.0087, 0.0087], [2.6, 0.0186, 0.0349, 0.0349], [3.4, 0.0628, 0.0786, 0.0786], [4.25, 0.1564, 0.1453, 0.1453], [5.05, 0.3047, 0.2293, 0.2293], [5.9, 0.5471, 0.3468, 0.3468], [6.05, 0.6008, 0.364, 0.364], [7.4, 1.0847, 0.364, 0.0], [13.1, 1.0847, 0.0, 0.0], [13.95, 0.9269, -0.3608, -0.3608], [14.05, 0.888, -0.3943, -0.3943], [15.3, 0.4134, -0.3943, -0.3943], [16.1, 0.1657, -0.2382, -0.2382], [16.9, 0.0357, -0.0972, -0.0972], [17.5, 0.0, 0.0, 0.0], [18.5, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const DOUBLE_S := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0026, 0.0098, 0.0098], [2.6, 0.0209, 0.0392, 0.0392], [3.4, 0.0707, 0.0885, 0.0885], [4.25, 0.1762, 0.164, 0.164], [5.05, 0.344, 0.2599, 0.2599], [5.9, 0.6201, 0.3971, 0.3971], [6.15, 0.7255, 0.4452, 0.4452], [7.15, 1.1651, 0.4452, -1.1918], [7.3, 1.0, -1.1918, 0.0], [12.0, 1.0, 0.0, 0.7002], [12.25, 1.1651, 0.7002, 0.0], [12.85, 1.1651, 0.0, 0.0], [13.7, 1.0073, -0.3608, -0.3608], [13.95, 0.8984, -0.4865, -0.4865], [14.8, 0.4925, -0.4865, -0.4865], [15.6, 0.192, -0.2843, -0.2843], [16.4, 0.0397, -0.1103, -0.1103], [16.95, 0.0, 0.0, 0.0], [17.95, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const KICKER_S := [[0.0, 0.0, 0.0, 0.0], [1.8, 0.0058, 0.0219, 0.0219], [2.6, 0.0469, 0.0881, 0.0881], [3.4, 0.1593, 0.2016, 0.2016], [3.85, 0.2692, 0.2867, 0.2867], [4.85, 0.5551, 0.2867, 0.0], [8.6, 0.5551, 0.0, 0.0], [9.35, 0.4325, -0.3082, -0.3082], [10.2, 0.1813, -0.3082, -0.3082], [11.05, 0.021, -0.0866, -0.0866], [11.45, 0.0, 0.0, 0.0], [12.45, 0.0, 0.0, 0.0]]   # baked: tools/bake_jumps.gd
const WHOOP := [[0, 0, 0], [1.6, 0.3, 0.3], [2.6, 0.48, 0], [8.6, 0.08, -0.09], [10, 0, 0]]


## where riders are in the air over each feature: [from, to, ...] along it (m), the lip to about where they come
## down. The ground shader draws no ridden lines there (ground.gdshader, via TerrainField.fo_air; mirrored in C#)
const AIR := {"table": [15.85, 31.99], "double": [15.85, 31.99], "kicker": [11.45, 25.63], "woodKicker": [3.8, 9.0],
	"tableLine": [15.85, 31.99, 52.2, 66.38], "flow": [11.45, 25.63], "doubleLine": [15.85, 31.99, 52.2, 66.38]}
const AIR_S := {"table": [7.4, 16.88], "double": [7.15, 16.39], "kicker": [4.85, 11.45],
	"tableLine": [7.4, 16.88, 26.35, 32.95], "flow": [4.85, 11.45], "doubleLine": [7.15, 16.39, 25.8, 32.4]}


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
		"rope": Flat.new(72.0),
	}
	var kick := Hermite.new([[0, 0, 0.1], [3.8, 0.95, 0.4]])
	var skin := Hermite.new([[0, 0.02, 0.05], [2, 0.42, 0.3], [4, 0.85, 0]])
	var wood := {
		"woodKicker": Wood.new(0, 0.0, 3.8, 0.85, true, kick, skin),
		"skinny": Wood.new(1, 0.0, 19.0, 0.33, false, kick, skin),
		"bridge": Wood.new(2, 0.0, 15.0, 1.0, false, kick, skin),
		"bridgeW": Wood.new(3, 0.0, 15.0, 1.0, false, kick, skin),   # picked for some bridges by TerrainField.make_feat
		"gorge": Wood.new(2, 0.0, 36.0, 1.4, false, kick, skin),
	}
	var dig := {"gorge": Hermite.new([[0, 0, 0], [3.0, 0, 0], [4.6, -9.0, 0], [31.4, -9.0, 0], [33.0, 0, 0], [36, 0, 0]])}
	var table_s := Hermite.new(TABLE_S)
	var dbl_s := Hermite.new(DOUBLE_S)
	var kicker_s := Hermite.new(KICKER_S)
	var small := {"table": table_s, "double": dbl_s, "kicker": kicker_s, "tableLine": Line.new([table_s, 3.0, kicker_s]),
		"flow": Line.new([kicker_s, 3.0, Rollers.new(3, 0.45)]), "doubleLine": Line.new([dbl_s, 3.0, kicker_s])}
	return {"profiles": profiles, "wood": wood, "dig": dig, "small": small}
