class_name Collection
extends RefCounted
## The two things a rider collects besides cash (profile tabs BADGES and CARDS).
## BADGES = performance milestones (Steam.ACHIEVEMENTS: speed, air, distance, jumps, first tricks): earned by hitting a number, drawn as 3D medals.
## CARDS = collectibles for VARIETY and identity: every bike you ride, every trick family you land, streaks, and one legendary for finishing the badges.
## Each card has a rarity (common / rare / epic / legendary: its holo foil grows with it) and pays cash when it is collected.
## Collected cards live in GameState.cards (id -> unix time). `check()` runs once a second (Steam._check_records) and on opening the profile.

const RARITY := {
	"common":    {"name": "COMMON",    "col": Color("8fa3b8"), "cash": 150,  "holo": 0.30},
	"rare":      {"name": "RARE",      "col": Color("4aa3ff"), "cash": 400,  "holo": 0.55},
	"epic":      {"name": "EPIC",      "col": Color("b45cff"), "cash": 900,  "holo": 0.80},
	"legendary": {"name": "LEGENDARY", "col": Color("ffb81f"), "cash": 3000, "holo": 1.00},
}

## id -> name, kind, rarity, glyph (drawn in the Symbols font), a line of flavour, and what it takes
const CARDS := {
	"bike_dh":    {"name": "RUNOUT DH",   "kind": "BIKE",   "rarity": "common", "glyph": "▲", "text": "The one that started it all.", "need": "Ride the Runout DH."},
	"bike_bmx":   {"name": "BMX",         "kind": "BIKE",   "rarity": "common", "glyph": "●", "text": "Small wheels, big attitude.", "need": "Ride the BMX."},
	"bike_tues":  {"name": "YONDER TUSK", "kind": "BIKE",   "rarity": "rare",   "glyph": "▲", "text": "Race geometry, no excuses.", "need": "Ride the Yonder Tusk."},
	"bike_goat":  {"name": "GOAT DH",     "kind": "BIKE",   "rarity": "rare",   "glyph": "▲", "text": "Single pivot, all character.", "need": "Ride the Goat DH."},
	"bike_fuzz":  {"name": "NEXO FIZZ",   "kind": "BIKE",   "rarity": "rare",   "glyph": "▲", "text": "Freeride muscle.", "need": "Ride the Nexo Fizz."},
	"trick_back":    {"name": "BACKFLIP",  "kind": "TRICK", "rarity": "rare",   "glyph": "▼", "text": "Over the top and home again.", "need": "Land a backflip."},
	"trick_front":   {"name": "FRONTFLIP", "kind": "TRICK", "rarity": "rare",   "glyph": "▲", "text": "Nose first into the sky.", "need": "Land a frontflip."},
	"trick_360":     {"name": "THREE-SIXTY", "kind": "TRICK", "rarity": "rare", "glyph": "●", "text": "One full lap in mid-air.", "need": "Land a 360."},
	"trick_720":     {"name": "SEVEN-TWENTY", "kind": "TRICK", "rarity": "epic", "glyph": "●", "text": "Twice round, still smiling.", "need": "Land a 720."},
	"trick_whip":    {"name": "WHIP",      "kind": "TRICK", "rarity": "rare",   "glyph": "▶", "text": "Lay it down, bring it back.", "need": "Land a whip."},
	"trick_table":   {"name": "TABLETOP",  "kind": "TRICK", "rarity": "rare",   "glyph": "◀", "text": "Flat as a kitchen table.", "need": "Land a tabletop."},
	"trick_scrub":   {"name": "SCRUB",     "kind": "TRICK", "rarity": "rare",   "glyph": "▼", "text": "Stay low, go far.", "need": "Land a scrub."},
	"streak_d3":     {"name": "THREE IN A ROW", "kind": "STREAK", "rarity": "common", "glyph": "★", "text": "Habit forming.", "need": "Ride 3 days in a row."},
	"streak_d7":     {"name": "WEEK ON FIRE", "kind": "STREAK", "rarity": "rare", "glyph": "★", "text": "Seven days, no rest.", "need": "Ride 7 days in a row."},
	"streak_d14":    {"name": "FORTNIGHT",  "kind": "STREAK", "rarity": "epic",  "glyph": "★", "text": "Two weeks of dirt.", "need": "Ride 14 days in a row."},
	"streak_w4":     {"name": "MONTHLY RHYTHM", "kind": "STREAK", "rarity": "epic", "glyph": "★", "text": "A ride every week for a month.", "need": "Ride in 4 weeks in a row."},
	"streak_w12":    {"name": "SEASON PASS", "kind": "STREAK", "rarity": "legendary", "glyph": "★", "text": "Twelve weeks. Respect.", "need": "Ride in 12 weeks in a row."},
	"legend_all":    {"name": "COMPLETIONIST", "kind": "LEGEND", "rarity": "legendary", "glyph": "🏆", "text": "Every badge on the wall.", "need": "Earn every badge."},
}

## trick-name fragments (the HUD's trick names, upper case) -> the trick key they count for
const TRICK_KEYS := {"BACKFLIP": "back", "FRONTFLIP": "front", "FLIP": "flip", "360": "360", "720": "720", "WHIP": "whip", "TABLETOP": "table", "SCRUB": "scrub"}

static func note_trick(name: String) -> void:
	var up := name.to_upper()
	for frag in TRICK_KEYS:
		if up.contains(frag): GameState.tricks_seen[TRICK_KEYS[frag]] = true

static func owned(id: String) -> bool:
	return GameState.cards.has(id)

static func _met(id: String) -> bool:
	if id.begins_with("bike_"): return int(GameState.bikes_ridden.get(id.substr(5), 0)) > 0
	if id.begins_with("trick_"):
		return GameState.tricks_seen.has(id.substr(6)) or (id == "trick_back" and GameState.tricks_seen.has("back"))
	match id:
		"streak_d3": return int(GameState.records.best_streak) >= 3
		"streak_d7": return int(GameState.records.best_streak) >= 7
		"streak_d14": return int(GameState.records.best_streak) >= 14
		"streak_w4": return int(GameState.records.best_wstreak) >= 4
		"streak_w12": return int(GameState.records.best_wstreak) >= 12
		"legend_all": return GameState.achieved.size() >= Steam.ACHIEVEMENTS.size()
	return false

## collect every card whose condition is met; returns the ids that are new
static func check() -> Array:
	GameState.records.best_streak = maxi(int(GameState.records.best_streak), GameState.day_streak())
	GameState.records.best_wstreak = maxi(int(GameState.records.best_wstreak), GameState.week_streak())
	var fresh: Array = []
	for id in CARDS:
		if GameState.cards.has(id) or not _met(id): continue
		GameState.cards[id] = int(Time.get_unix_time_from_system())
		var c: Dictionary = CARDS[id]
		GameState.earn(int(RARITY[c.rarity].cash), "Card: " + String(c.name).capitalize())
		fresh.append(id)
	return fresh

static func label(id: String) -> String:
	return String(CARDS[id].name)

# ---------------------------------------------------------------- badges: a tier (metal) + a colour + a glyph per achievement
const TIERS := [["BRONZE", Color("c98a4a")], ["SILVER", Color("cfd6df")], ["GOLD", Color("ffc83a")], ["PLATINUM", Color("9be8ff")]]

static func badge_tier(id: String) -> int:
	var cash := Steam.reward(id)
	if cash < 250: return 0
	if cash < 500: return 1
	if cash < 1000: return 2
	return 3

## enamel colour by what it is for
static func badge_colour(id: String) -> Color:
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
