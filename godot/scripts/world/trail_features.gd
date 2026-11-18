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
			if u < 13.0:
				return 0.45
			return _ramp(13.0, 15.0, 0.45, 0.02, u)
	static func _ramp(a: float, b: float, h0: float, h1: float, u: float) -> float:
		return h0 + (h1 - h0) * minf(1.0, maxf(0.0, (u - a) / (b - a)))


const TABLE := [[0, 0, 0], [5.5, 1.25, 0.5, 0], [9.5, 1.25, 0, 0], [11.5, 0.95, -0.36], [17, 0.18, -0.2], [21, 0, 0]]
const DOUBLE := [[0, 0, 0], [5, 1.35, 0.58, -1.6], [6.0, 0.35, 0, 0], [7.5, 0.35, 0, 1.4],
	[9.2, 1.2, 0, 0], [10.2, 1.2, 0, 0], [12.5, 0.85, -0.34], [19, 0.15, -0.16], [23, 0, 0]]
const KICKER := [[0, 0, 0], [3.2, 0.7, 0.42, 0], [4.0, 0.7, 0, 0], [6.5, 0.48, -0.2], [14, 0, 0]]
const WHOOP := [[0, 0, 0], [1.6, 0.3, 0.3], [2.6, 0.48, 0], [8.6, 0.08, -0.09], [10, 0, 0]]


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
	}
	var kick := Hermite.new([[0, 0, 0.1], [3.8, 0.95, 0.4]])
	var skin := Hermite.new([[0, 0.02, 0.05], [2, 0.42, 0.3], [4, 0.85, 0]])
	var wood := {
		"woodKicker": Wood.new(0, 0.0, 3.8, 0.85, true, kick, skin),
		"skinny": Wood.new(1, 0.0, 19.0, 0.33, false, kick, skin),
		"bridge": Wood.new(2, 0.0, 15.0, 1.0, false, kick, skin),
	}
	var dig := {"bridge": Hermite.new([[0, 0, 0], [1.6, 0, 0], [3.4, -1.9, 0], [11.6, -1.9, 0], [13.4, 0, 0], [15, 0, 0]])}
	return {"profiles": profiles, "wood": wood, "dig": dig}
