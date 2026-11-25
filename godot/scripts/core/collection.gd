class_name Collection
extends RefCounted
## What the BADGES tab needs to draw an achievement: its tier (metal), colour, symbol and shape (after CycleIQ's badges: circle / hexagon / diamond /
## star / shield, extruded in 3D by ui/collect_stage.gd). Badges = performance milestones (Steam.ACHIEVEMENTS).
## Also keeps the list of trick families landed (GameState.tricks_seen: the profile's STYLE rating reads it).

## trick-name fragments (the HUD's trick names, upper case) -> the trick key they count for
const TRICK_KEYS := {"BACKFLIP": "back", "FRONTFLIP": "front", "FLIP": "flip", "360": "360", "720": "720", "WHIP": "whip", "TABLETOP": "table", "SCRUB": "scrub"}

static func note_trick(name: String) -> void:
	var up := name.to_upper()
	for frag in TRICK_KEYS:
		if up.contains(frag): GameState.tricks_seen[TRICK_KEYS[frag]] = true

const TIERS := [["BRONZE", Color("8a6a48")], ["SILVER", Color("a3a8af")], ["GOLD", Color("b39a52")], ["PLATINUM", Color("c4ccd2")]]

static func badge_tier(id: String) -> int:
	var cash := Steam.reward(id)
	if cash < 250: return 0
	if cash < 500: return 1
	if cash < 1000: return 2
	return 3

## enamel colour by what it is for
static func badge_colour(id: String) -> Color:
	return _raw_colour(id).lerp(Color("23262c"), 0.52)   # muted: dark enamel, not toy colours

static func _raw_colour(id: String) -> Color:
	var a: Array = Steam.ACHIEVEMENTS[id]
	if a[2] == "rec":
		match String(a[3]):
			"top_speed": return Color("e5352b")
			"air", "highest", "longest": return Color("2f7bff")
			"distance": return Color("1fb36b")
			"jumps": return Color("ff8a1f")
	if a[2] == "trick": return Color("a24bff")
	return Color("14b8c4")

static func badge_glyph(id: String) -> String:
	var a: Array = Steam.ACHIEVEMENTS[id]
	if a[2] == "rec":
		match String(a[3]):
			"top_speed": return "▶"
			"air", "highest": return "▲"
			"longest": return "◀"
			"distance": return "●"
			"jumps": return "▼"
	if a[2] == "trick": return "★"
	return "✓"

## shape, colours and symbol of a badge
static func badge_look(id: String) -> Dictionary:
	var a: Array = Steam.ACHIEVEMENTS[id]
	var shape := "shield"
	if a[2] == "rec":
		match String(a[3]):
			"top_speed": shape = "hexagon"
			"air", "highest", "longest": shape = "diamond"
			"distance": shape = "circle"
			"jumps": shape = "shield"
	elif a[2] == "trick":
		shape = "star"
	var col := badge_colour(id)
	return {"shape": shape, "color": col, "accent": col.lightened(0.4), "label": String(a[0]).to_upper(), "glyph": badge_glyph(id), "desc": String(a[1])}

## outline of a badge shape (about 1.2 across at k = 1)
static func shape_points(shape: String, k := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		"circle":
			for i in 48: pts.append(Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * 0.62)
		"hexagon":
			for i in 6: pts.append(Vector2(cos(TAU * i / 6.0 - PI / 6.0), sin(TAU * i / 6.0 - PI / 6.0)) * 0.62)
		"diamond":
			pts = PackedVector2Array([Vector2(0, 0.72), Vector2(0.56, 0), Vector2(0, -0.72), Vector2(-0.56, 0)])
		"star":
			for i in 10:
				var r := 0.68 if i % 2 == 0 else 0.29
				var a := TAU * i / 10.0 - PI / 2.0
				pts.append(Vector2(cos(a), -sin(a)) * r)
			pts.reverse()
		_:   # shield
			pts = PackedVector2Array([Vector2(0, 0.7), Vector2(0.55, 0.52), Vector2(0.58, -0.05), Vector2(0.4, -0.45), Vector2(0, -0.72),
				Vector2(-0.4, -0.45), Vector2(-0.58, -0.05), Vector2(-0.55, 0.52)])
	if k != 1.0:
		for i in pts.size(): pts[i] *= k
	return pts
