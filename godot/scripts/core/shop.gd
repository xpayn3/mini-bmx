class_name Shop
## Prices for every garage part, and the one switch that decides whether they matter.
##
## UNLOCK_ALL = true (the game is still being made): everything is usable, prices are only shown on the
## cards. Flip it to false once there is a wallet (ride distance / style / challenges paying out) and
## `unlocked()` starts asking `owned`. Nothing here is saved yet; the wallet + owned set belong in GameState.
## Made-up currency symbol, whole numbers.

const UNLOCK_ALL := true
const SYMBOL := "$"

## frame price by class (BikeBuild.FRAMES.<id>.class)
const FRAME_BY_CLASS := {"freeride": 900, "allround": 1400, "race": 2200, "speed": 3200}
## the same model made by a frame's makers: parts that exist on several frames are priced by the model
const MODEL := {
	"rotor":   {"stock": 0, "tues": 140, "fuzz": 110},
	"saddle":  {"stock": 0, "tues": 120, "fuzz": 90},
	"levers":  {"stock": 0, "tues": 130, "fuzz": 100},
	"stem":    {"stock": 0, "tues": 150, "fuzz": 120},
	"post":    {"stock": 0, "dropper": 280},
	"pedal":   {"stock": 0, "dh": 60, "tues": 110, "fuzz": 90},
	"caliper": {"stock": 0, "tues": 120, "fuzz": 100},
	"light":   {"none": 0, "glint": 40, "luma": 90, "nocta": 160, "duskbane": 260, "sundowner": 340},
	"fork":    {"fox40f": 1100, "fox40p": 750, "boxxer_u": 1050, "boxxer_s": 700, "dh38": 1250, "bomber58": 950,
		"onyx": 780, "dorado": 1200, "era": 900, "tues_fork": 800, "fuzz_fork": 700},
	"bar":     {},   # handlebars: BAR_DEFAULT unless listed
	"cassette": {"single": 25, "dh7": 70, "dh7w": 85, "mtb9": 110, "mtb11": 200, "eagle": 320, "rainbow": 400},
}
const BAR_DEFAULT := 90
const CASSETTE_DEFAULT := 150

## price of one part: kind is "tyre" "rim" "fork" "cassette" "rotor" "saddle" "levers" "stem" "post" "pedal"
## "caliper" "light" "bar" "frame" "edition"; 0 = free / unknown (no tag shown)
static func price(kind: String, id: String) -> int:
	match kind:
		"tyre":
			var m: Dictionary = BikeBuild.TYRE_MODELS.get(id, {})
			if not m.has("brand"): return 0
			var p := 45
			if m.get("casing", "round") == "square": p += 25     # tougher casing
			if m.get("tread", "knobby") == "slick": p -= 10
			p += int(round((float(m.get("tyre_w", 2.4)) - 2.4) * 50.0))   # wider = more rubber
			return p
		"rim":
			var m: Dictionary = BikeBuild.RIM_MODELS.get(id, {})
			if not m.has("brand"): return 0
			var p := 140 if m.get("material", "alloy") == "alloy" else 520   # carbon is the money
			if m.get("profile", "") == "hookless": p += 30
			return p
		"frame":
			var f: Dictionary = BikeBuild.FRAMES.get(id, {})
			return int(FRAME_BY_CLASS.get(str(f.get("class", "")), 0))
		"edition":
			# a showroom bike = its frame + the fork / tyres / rims it comes with
			var ed: Dictionary = BikeBuild.EDITIONS.get(id, {})
			if ed.is_empty(): return 0
			return price("frame", str(ed.get("frame", ""))) + price("fork", str(ed.get("fork", ""))) \
				+ price("tyre", str(ed.get("tyre", ""))) * 2 + price("rim", str(ed.get("rim", ""))) * 2
		"cassette":
			return int(MODEL.cassette.get(id, CASSETTE_DEFAULT))
		"bar":
			return int(MODEL.bar.get(id, BAR_DEFAULT)) if id != "stock" and id != "custom" else 0
	return int(MODEL.get(kind, {}).get(id, 0))

## `owned` is the future wallet's set; until then UNLOCK_ALL makes everything usable
static func unlocked(kind: String, id: String, owned := {}) -> bool:
	if UNLOCK_ALL: return true
	if price(kind, id) <= 0: return true
	return owned.has(kind + ":" + id)

static func fmt(p: int) -> String:
	var s := str(p)
	if p >= 1000: s = "%s,%s" % [s.substr(0, s.length() - 3), s.substr(s.length() - 3)]
	return SYMBOL + s

## total price of a build: frame + the model parts it carries (paint, logos and sliders are free)
static func build_price(b: Dictionary, frame: String) -> int:
	var t := price("frame", frame)
	var W: Dictionary = b.get("wheels", {})
	t += price("tyre", str(W.get("tyre_model", ""))) * 2 + price("rim", str(W.get("rim_model", ""))) * 2
	var S: Dictionary = b.get("suspension", {})
	t += price("fork", str(S.get("fork_model", ""))) + price("rotor", str(S.get("rotor", "stock"))) * 2 \
		+ price("caliper", str(S.get("rear_caliper", "stock")))
	var D: Dictionary = b.get("drive", {})
	t += price("cassette", str(D.get("cassette", ""))) + price("pedal", str(D.get("pedals", "stock")))
	t += price("saddle", str(b.get("seat", {}).get("model", "stock"))) + price("post", str(b.get("seat", {}).get("post", "stock")))
	var B: Dictionary = b.get("bars", {})
	t += price("levers", str(B.get("levers", "stock"))) + price("stem", str(B.get("stem", "stock"))) \
		+ price("bar", str(B.get("model", "stock")))
	t += price("light", str(b.get("lights", {}).get("model", "none")))
	return t
