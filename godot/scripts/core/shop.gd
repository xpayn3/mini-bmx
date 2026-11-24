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
## Prices are today's (2026) bike market, in dollars: a complete entry DH bike ~$5k, mid ~$9k, a race bike
## ~$14k, a flagship built up with carbon wheels and the top suspension $20k+ (car money, really).
const FRAME_BY_CLASS := {"freeride": 1600, "allround": 2900, "race": 4600, "speed": 9500}
## the rest of a complete bike that has no part card (drivetrain, brakes, cockpit, headset, hubs...), by class
const KIT_BY_CLASS := {"freeride": 1500, "allround": 2600, "race": 4000, "speed": 7000}
## the same model made by a frame's makers: parts that exist on several frames are priced by the model
const MODEL := {
	"rotor":   {"stock": 0, "tues": 95, "fuzz": 75},
	"saddle":  {"stock": 0, "tues": 140, "fuzz": 95},
	"levers":  {"stock": 0, "tues": 260, "fuzz": 180},
	"stem":    {"stock": 0, "tues": 180, "fuzz": 140},
	"post":    {"stock": 0, "dropper": 480},
	"pedal":   {"stock": 0, "dh": 90, "tues": 180, "fuzz": 140},
	"caliper": {"stock": 0, "tues": 320, "fuzz": 260},
	"light":   {"none": 0, "glint": 60, "luma": 140, "nocta": 260, "duskbane": 420, "sundowner": 560},
	"fork":    {"fox40f": 2600, "fox40p": 1750, "boxxer_u": 2300, "boxxer_s": 1500, "dh38": 2700, "bomber58": 1900,
		"onyx": 1800, "dorado": 2800, "era": 2500, "tues_fork": 1900, "fuzz_fork": 1400},
	"shock":   {"coil_basic": 450, "air_trail": 650, "coil_dh": 950, "air_dh": 1150, "hydro_pro": 1350},
	"bar":     {},   # handlebars: by material (BAR_ALLOY / BAR_CARBON) unless listed
	"cassette": {"single": 40, "dh7": 110, "dh7w": 140, "mtb9": 150, "mtb11": 260, "eagle": 480, "rainbow": 650},
}
const BAR_ALLOY := 120
const BAR_CARBON := 220
const CASSETTE_DEFAULT := 180

## price of one part: kind is "tyre" "rim" "fork" "cassette" "rotor" "saddle" "levers" "stem" "post" "pedal"
## "caliper" "light" "bar" "frame" "edition"; 0 = free / unknown (no tag shown)
static func price(kind: String, id: String) -> int:
	match kind:
		"tyre":
			var m: Dictionary = BikeBuild.TYRE_MODELS.get(id, {})
			if not m.has("brand"): return 0
			var p := 75
			if m.get("casing", "round") == "square": p += 20     # tougher casing
			if m.get("tread", "knobby") == "slick": p -= 10
			p += int(round((float(m.get("tyre_w", 2.4)) - 2.4) * 50.0))   # wider = more rubber
			return p
		"rim":
			var m: Dictionary = BikeBuild.RIM_MODELS.get(id, {})
			if not m.has("brand"): return 0
			var p := 300 if m.get("material", "alloy") == "alloy" else 1500   # one built wheel (hub, spokes); carbon is the money
			if m.get("profile", "") == "hookless": p += 30
			return p
		"frame":
			var f: Dictionary = BikeBuild.FRAMES.get(id, {})
			return int(FRAME_BY_CLASS.get(str(f.get("class", "")), 0))
		"kit":
			var fk: Dictionary = BikeBuild.FRAMES.get(id, {})
			return int(KIT_BY_CLASS.get(str(fk.get("class", "")), 0))
		"edition":
			# a complete showroom bike = frame + kit + the fork / shock / bar / tyres / wheels it comes with
			var ed: Dictionary = BikeBuild.EDITIONS.get(id, {})
			if ed.is_empty(): return 0
			var fr := str(ed.get("frame", ""))
			var t := price("frame", fr) + price("kit", fr) + price("fork", str(ed.get("fork", "")))
			t += price("shock", str(ed.get("shock", SuspSetup.DEFAULT_SHOCK))) + price("bar", str(ed.get("bar", "stock")))
			return t + price("tyre", str(ed.get("tyre", ""))) * 2 + price("rim", str(ed.get("rim", ""))) * 2
		"cassette":
			return int(MODEL.cassette.get(id, CASSETTE_DEFAULT))
		"bar":
			if id == "stock" or id == "custom": return 0
			if MODEL.bar.has(id): return int(MODEL.bar[id])
			var hb: Dictionary = Handlebar.MODELS.get(id, {})
			return BAR_CARBON if str(hb.get("material", "alloy")).begins_with("carbon") else BAR_ALLOY
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

## total price of a complete bike: frame + kit + the model parts it carries (paint, logos and sliders are free)
static func build_price(b: Dictionary, frame: String) -> int:
	var t := price("frame", frame) + price("kit", frame)
	var W: Dictionary = b.get("wheels", {})
	t += price("tyre", str(W.get("tyre_model", ""))) * 2 + price("rim", str(W.get("rim_model", ""))) * 2
	var S: Dictionary = b.get("suspension", {})
	t += price("shock", str(SuspSetup.val(S, "shock_model")))
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
