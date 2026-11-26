class_name BikeBuild
extends RefCounted
## The player's downhill bike build: paint + finishes per part, logos, wheels (size, tyres, rims,
## spokes), fork / shock, gearing. Saved in user://garage.json. `apply_look` paints a BikeRig,
## `ride_mods` turns the parts into ride-feel multipliers / geometry for the physics, `stats` gives
## the 0..1 bars the garage shows.

const PATH := "user://garage.json"
const LOGO_DIR := "user://logos"

const FINISHES := {
	"gloss":    {"label": "Gloss",    "metallic": 0.0,  "roughness": 0.32, "clearcoat": 1.0, "cc_rough": 0.03, "sparkle": 0.0,  "flip": 0.0},
	"metallic": {"label": "Metallic", "metallic": 0.55, "roughness": 0.34, "clearcoat": 1.0, "cc_rough": 0.03, "sparkle": 0.22, "flip": 0.0, "flake": 0.00025},
	"pearl":    {"label": "Pearl shift", "metallic": 0.45, "roughness": 0.3, "clearcoat": 1.0, "cc_rough": 0.03, "sparkle": 0.12, "flip": 0.85, "flake": 0.00015},
	"candy":    {"label": "Candy",    "metallic": 0.85, "roughness": 0.18, "clearcoat": 1.0, "cc_rough": 0.02, "sparkle": 0.3,  "flip": 0.0, "deep": 0.55, "flake": 0.0003},
	"satin":    {"label": "Satin",    "metallic": 0.2,  "roughness": 0.55, "clearcoat": 0.3, "cc_rough": 0.4,  "sparkle": 0.05, "flip": 0.0, "flake": 0.0002},
	"matte":    {"label": "Matte",    "metallic": 0.0,  "roughness": 0.88, "clearcoat": 0.0, "cc_rough": 1.0,  "sparkle": 0.0,  "flip": 0.0},
	"chrome":   {"label": "Chrome",   "metallic": 1.0,  "roughness": 0.06, "clearcoat": 0.0, "cc_rough": 0.0,  "sparkle": 0.0,  "flip": 0.0},
	"anodized": {"label": "Anodized", "metallic": 0.9,  "roughness": 0.3,  "clearcoat": 0.0, "cc_rough": 0.0,  "sparkle": 0.06, "flip": 0.0, "flake": 0.00015},
}

## paintable parts: [label, [[node, surface material name], ...]]
const PARTS := {
	"frame":      ["Front triangle",   [["frame", "paint"]]],
	"rear":       ["Rear triangle",    [["swing", "paint"], ["seatstay", "paint"]]],
	"linkage":    ["Rocker link",      [["rocker", "chrome"]]],
	"fork":       ["Fork lowers",      [["fork_lower", "black"]]],
	"stanchions": ["Stanchions",       [["steer", "gold"]]],
	"crown":      ["Bars, stem & crown", [["steer", "black"]]],
	"spring":     ["Shock spring",     [["shock_spring", "gold"]]],
	"shock":      ["Shock body",       [["shock_body", "black"], ["shock_shaft", "black"]]],
	"grips":      ["Grips",            [["steer", "rubber"]]],
	"saddle":     ["Saddle & pedals",  [["frame", "plastic"], ["steer", "plastic"]]],
	"crank":      ["Cranks",           [["crank", "black"]]],
}

## logo slots (decals.gd label templates); "logo" picks one of LOGOS or "text" / "file:<path>" / "none"
const SLOTS := {
	"downtube":  {"label": "Down tube",  "tmpl": {"slot": "downtube", "mesh": "frame", "surface": "paint", "from": [0.168, 0.486], "to": [0.404, 0.809], "length": 0.2, "height": 0.0627}},
	"toptube":   {"label": "Top tube",   "tmpl": {"slot": "toptube", "mesh": "frame", "surface": "paint", "from": [0.05, 0.74], "to": [0.30, 0.86], "length": 0.19, "height": 0.032}},
	"chainstay": {"label": "Chainstays", "tmpl": {"slot": "chainstay", "mesh": "swing", "surface": "paint", "from": [-0.44, -0.025], "to": [-0.25, 0.03], "length": 0.09, "height": 0.0282, "z": 0.075, "depth": 0.06}},
	"forklegs":  {"label": "Fork legs",  "tmpl": {"slot": "forklegs", "mesh": "fork_lower", "surface": "black", "from": [-0.03, 0.07], "to": [-0.165, 0.335], "upright": true, "length": 0.078, "height": 0.15, "z": 0.085, "depth": 0.05}},   # Fox 40 size: ~15 cm, wrapped round the leg
	"bars":      {"label": "Handlebar",  "tmpl": {"mesh": "steer", "surface": "bar", "bar": true, "length": 0.07, "height": 0.04, "depth": 0.05}},   # a sticker on each side of the stem
}

## the logo library. Images that come with the game, plus text logos (our own wordmarks)
const LOGOS := {
	"none":    {"label": "None"},
	"cinelli": {"label": "MONTELLI", "text": "MONTELLI"},   # key kept for saves (was the Cinelli PNG, assets/decals/cinelli.png, now unused)
	"fox":     {"label": "KOMODO", "text": "KOMODO"},   # key kept for saves (was the Fox PNGs, assets/decals/fox_*.png, now unused)
	"glory":   {"label": "RUNOUT", "text": "RUNOUT"},
	"minibmx": {"label": "MINI BMX", "text": "MINI BMX"},
	"gravity": {"label": "FREEFALL", "text": "FREEFALL"},
	"text":    {"label": "Custom text…"},
}

const WHEEL_SIZES := {"20": 406, "26": 559, "27.5": 584, "29": 622}

## tyre models (popular DH tyres, our own approximation of each tread). Picking one sets the tread,
## casing, width and the sidewall lettering; touching any of those turns the model back to "custom".
const TYRE_MODELS := {
	"custom":          {"label": "Custom"},
	"minion_dhf":      {"label": "Gripwell Raptor DHF",  "brand": "GRIPWELL",    "tread": "knobby", "pattern": "knobby",  "casing": "round",  "tyre_w": 2.5},
	"minion_dhr":      {"label": "Gripwell Raptor DHR II","brand": "GRIPWELL",   "tread": "knobby", "pattern": "paddle",  "casing": "square", "tyre_w": 2.4},
	"assegai":         {"label": "Gripwell Kraken",      "brand": "GRIPWELL",    "tread": "knobby", "pattern": "dense",   "casing": "square", "tyre_w": 2.5},
	"shorty":          {"label": "Gripwell Stubby (mud)","brand": "GRIPWELL",    "tread": "knobby", "pattern": "spike",   "casing": "round",  "tyre_w": 2.4},
	"minion_ss":       {"label": "Gripwell Raptor SS",   "brand": "GRIPWELL",    "tread": "semi",   "pattern": "semi",    "casing": "square", "tyre_w": 2.3},
	"magic_mary":      {"label": "Trakka Mad Molly",     "brand": "TRAKKA",      "tread": "knobby", "pattern": "stagger", "casing": "round",  "tyre_w": 2.4},
	"big_betty":       {"label": "Trakka Big Brenda",    "brand": "TRAKKA",      "tread": "knobby", "pattern": "block",   "casing": "round",  "tyre_w": 2.4},
	"dh22":            {"label": "Morvan GR22",          "brand": "MORVAN",      "tread": "knobby", "pattern": "dense",   "casing": "square", "tyre_w": 2.4},
	"dh_slick":        {"label": "Morvan GR Slick",      "brand": "MORVAN",      "tread": "slick",  "pattern": "slick",   "casing": "round",  "tyre_w": 2.4},
	"kryptotal":       {"label": "Kontour Terratrax",    "brand": "KONTOUR",     "tread": "knobby", "pattern": "block",   "casing": "square", "tyre_w": 2.4},
	"butcher":         {"label": "Ridgeform Cleaver",    "brand": "RIDGEFORM",   "tread": "knobby", "pattern": "paddle",  "casing": "round",  "tyre_w": 2.6},
}
const PATTERN_NAMES := [["knobby", "Classic knobs"], ["paddle", "Paddle centre"], ["dense", "Dense 3-across"],
	["stagger", "Open stagger"], ["block", "Square blocks"], ["spike", "Mud spikes"], ["semi", "Semi-slick"], ["slick", "Slick"]]

## rim models (popular DH rims: profile shape, material, depth / outer width in mm, rim lettering)
const RIM_MODELS := {
	"custom":       {"label": "Custom"},
	"fr560":        {"label": "Alpwerk AR 560",       "brand": "ALPWERK",       "profile": "hooked",   "material": "alloy",  "depth": 24, "width": 36},
	"deemax":       {"label": "Castel Dropmax",       "brand": "CASTEL",        "profile": "vee",      "material": "alloy",  "depth": 28, "width": 35},
	"arc30":        {"label": "Raw Edge Ridge 30",    "brand": "RAW EDGE",      "profile": "hooked",   "material": "alloy",  "depth": 21, "width": 35},
	"oozy":         {"label": "Smack Goopy 350",      "brand": "SMACK",         "profile": "box",      "material": "alloy",  "depth": 26, "width": 35},
	"flow":         {"label": "Sealco Glide MK4",     "brand": "SEALCO",       "profile": "hookless", "material": "alloy",  "depth": 21, "width": 35},
	"lg1":          {"label": "Q*seven QG1",          "brand": "Q*SEVEN",       "profile": "hooked",   "material": "alloy",  "depth": 24, "width": 35},
	"fuse":         {"label": "Hivemind Weld",        "brand": "HIVEMIND",      "profile": "round",    "material": "carbon", "depth": 25, "width": 36},
	"reserve30":    {"label": "Stockpile 30 HD",      "brand": "STOCKPILE",     "profile": "hookless", "material": "carbon", "depth": 28, "width": 37},
	"synthesis":    {"label": "Cogsmith Synapse",     "brand": "COGSMITH",     "profile": "vee",      "material": "carbon", "depth": 26, "width": 36},
	"moto":         {"label": "Whizz Zero-G Moto",    "brand": "WHIZZ",         "profile": "round",    "material": "carbon", "depth": 20, "width": 36},
}
const RIM_PROFILE_NAMES := [["hooked", "Hooked (classic)"], ["hookless", "Hookless"], ["box", "Box section"],
	["vee", "Deep V"], ["round", "Round tube"]]

## a tyre / rim model's numbers into the build (and its brand onto the lettering)
static func apply_tyre_model(b: Dictionary, key: String) -> void:
	b.wheels.tyre_model = key
	var m: Dictionary = TYRE_MODELS.get(key, {})
	if not m.has("brand"): return
	for k in ["tread", "pattern", "casing", "tyre_w"]: b.wheels[k] = m[k]
	b.logos.tyres.logo = "text"; b.logos.tyres.text = m.brand

static func apply_rim_model(b: Dictionary, key: String) -> void:
	b.wheels.rim_model = key
	var m: Dictionary = RIM_MODELS.get(key, {})
	if not m.has("brand"): return
	b.wheels.rim_profile = m.profile; b.wheels.rim_material = m.material
	b.wheels.rim_depth = m.depth; b.wheels.rim_width = m.width
	b.logos.rims.logo = "text"; b.logos.rims.text = m.brand
## DH forks (our approximation): travel, the lowers' paint and the stanchions' coating. Picking one sets
## the fork travel and paints the Fork lowers / Stanchions parts; moving the travel slider makes it "custom".
const FORK_MODELS := {
	"fox40f":   {"brand": "KOMODO",     "label": "K40 Factory",      "travel": 200, "spring": "Air",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c8a24a", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
	"fox40p":   {"brand": "KOMODO",     "label": "K40 Performance",   "travel": 200, "spring": "Air",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"}, "stanchions": {"color": "9c6b3c", "color2": "ffffff", "finish": "anodized"}, "coat": "Bronze"},
	"boxxer_u": {"brand": "STONEWALL",  "label": "Brawler Ultimate",  "travel": 200, "spring": "Air",
		"lowers": {"color": "c4161c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c9cdd2", "color2": "ffffff", "finish": "chrome"}, "coat": "Silver"},
	"boxxer_s": {"brand": "STONEWALL",  "label": "Brawler Select",   "travel": 190, "spring": "Air",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "matte"}, "stanchions": {"color": "c9cdd2", "color2": "ffffff", "finish": "chrome"}, "coat": "Silver"},
	"dh38":     {"brand": "NORDLUND",   "label": "NL38 m.1",         "travel": 200, "spring": "Coil",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "d9b347", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
	"bomber58": {"brand": "VERDELLI",   "label": "Bruiser 58",       "travel": 200, "spring": "Coil",
		"lowers": {"color": "d12b1f", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "9c6b3c", "color2": "ffffff", "finish": "anodized"}, "coat": "Bronze"},
	"onyx":     {"brand": "QVX",        "label": "Obsidian DH",       "travel": 200, "spring": "Coil",
		"lowers": {"color": "5fbf3f", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c9cdd2", "color2": "ffffff", "finish": "chrome"}, "coat": "Silver"},
	"dorado":   {"brand": "MIRAGE",     "label": "Gilded Pro",       "travel": 200, "spring": "Air",
		"lowers": {"color": "e9eaec", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c9cdd2", "color2": "ffffff", "finish": "chrome"}, "coat": "Silver"},
	"era":      {"brand": "AXT",        "label": "Epoch V2.1",       "travel": 180, "spring": "Coil",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"}, "stanchions": {"color": "e0b545", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
	# the forks of the YT Tues / NS Fuzz models (assets/forks/<glb>.glb, tools/make_forks.py): their own crowns, stanchions,
	# lowers and front caliper, fitted to the stock frame. The glb limits the travel (the lowers stop at the crown).
	"tues_fork": {"brand": "YONDER",     "label": "Tusk fork",        "travel": 180, "spring": "Air", "glb": "tues",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c8a24a", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
	"fuzz_fork": {"brand": "NEXO",       "label": "Fizz fork",        "travel": 170, "spring": "Air", "glb": "fuzz",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"}, "stanchions": {"color": "d9b347", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
}

## Stanchions are always a coating (hard-anodised / Kashima-style gold, bronze, or chrome silver), never paint:
## whatever colour a build holds, they are drawn as the nearest of these.
const STANCHION_COATS := [
	{"color": "c9cdd2", "finish": "chrome"},     # silver
	{"color": "c8a24a", "finish": "anodized"},   # gold
	{"color": "9c6b3c", "finish": "anodized"},   # bronze
]
static func stanchion_paint(pp: Dictionary) -> Dictionary:
	var c := Color(String(pp.get("color", "c8a24a")))
	var best: Dictionary = STANCHION_COATS[1]
	var bd := INF
	for coat in STANCHION_COATS:
		var k := Color(String(coat.color))
		var d := Vector3(c.r - k.r, c.g - k.g, c.b - k.b).length() + absf(c.s - k.s) * 0.6
		if c.get_luminance() < 0.3: d = 0.0 if coat == STANCHION_COATS[2] else 1.0   # black / near black: bronze
		if d < bd:
			bd = d
			best = coat
	var out := pp.duplicate()
	out.color = best.color
	out.finish = best.finish
	return out

static func apply_fork_model(b: Dictionary, key: String) -> void:
	b.suspension.fork_model = key
	var m: Dictionary = FORK_MODELS.get(key, {})
	if not m.has("brand"): return
	b.suspension.fork_travel = m.travel
	b.paint.fork = (m.lowers as Dictionary).duplicate()
	b.paint.stanchions = (m.stanchions as Dictionary).duplicate()

## brake rotors (assets/forks/rotor_<id>.glb, tools/export_rotors.py); "stock" = the generated wheels' own
const ROTORS := [["stock", "RUNOUT stock"], ["tues", "Yonder Tusk 203 mm"], ["fuzz", "Nexo Fizz 190 mm"]]
## saddles (assets/seats/saddle_dh.glb + parts/<id>_saddle.glb) and seat post: "stock" = the stock frame's slammed post; "dropper" = a post
## that stands up to build.seat.post_h metres (0 - 0.2) along the seat tube (BikeRig._swap_seat)
const SADDLES := [["stock", "RUNOUT stock"], ["tues", "Yonder Tusk"], ["fuzz", "Nexo Fizz"]]
const LEVERS := [["stock", "RUNOUT stock"], ["tues", "Yonder Tusk"], ["fuzz", "Nexo Fizz"]]
## direct-mount stems for the stock frame (assets/forks/stem_<id>.glb, tools/make_forks.py; BikeRig._swap_cockpit): the bar rides in its clamp
const STEMS := [["stock", "RUNOUT stock"], ["tues", "Yonder Tusk"], ["fuzz", "Nexo Fizz"]]
const POSTS := [["stock", "Slammed (stock)"], ["dropper", "Dropper"]]
## pedals: the pedal pair out of a frame model's crank (BikeRig.pedal_set), fitted on any frame's own pedal spots;
## "stock" = the frame's own. PEDAL_GLB: where each pair comes from.
const PEDALS := [["stock", "Frame's own"], ["dh", "RUNOUT flats"], ["tues", "Yonder Tusk"], ["fuzz", "Nexo Fizz"]]
const PEDAL_GLB := {"dh": "res://assets/dh.glb", "tues": "res://assets/tues.glb", "fuzz": "res://assets/fuzz.glb"}
## rear brake calipers for the stock frame (assets/forks/caliper_<id>.glb, tools/make_forks.py); "stock" = the GLORY's own
const REAR_CALIPERS := [["stock", "RUNOUT stock"], ["tues", "Yonder Tusk"], ["fuzz", "Nexo Fizz"]]

## the fork model's glb id (FORK_MODELS.*.glb) of a build, or "" for the frame's own fork
static func fork_glb(b: Dictionary) -> String:
	var m: Dictionary = FORK_MODELS.get(str(b.get("suspension", {}).get("fork_model", "")), {})
	return str(m.get("glb", ""))

## cassettes: brand / name for the part cards, cogs (teeth, small to big), finish: "cols" = anodized colour per
## cog (cycled; "rainbow" = oil-slick fade small -> big cog), "rough" = how matte. The big-range ones
## (52T+) are granny gears for climbing: the biggest cog gives the most push at walking pace.
const CASSETTES := {
	"dh7":    {"label": "7-speed DH 11–24", "brand": "SPROKK", "name": "SK1 DH", "cogs": [11, 12, 14, 16, 18, 21, 24],
		"cols": ["c9ccd1"], "rough": 0.18},
	"dh7w":   {"label": "7-speed wide 11–28", "brand": "CRATE", "name": "Seven Wide", "cogs": [11, 13, 15, 17, 20, 24, 28],
		"cols": ["202124"], "rough": 0.38},
	"mtb9":   {"label": "9-speed 11–32", "brand": "HIKARI", "name": "Trail 9", "cogs": [11, 12, 14, 16, 18, 21, 24, 28, 32],
		"cols": ["aeb2b8"], "rough": 0.3},
	"mtb11":  {"label": "11-speed 10–42", "brand": "HIKARI", "name": "Pro 11", "cogs": [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42],
		"cols": ["d4d6da", "34363a"], "rough": 0.22},
	"single": {"label": "Single speed 16T", "brand": "KOG", "name": "Single cog 16T", "cogs": [16],
		"cols": ["c8202a"], "rough": 0.3},
	"eagle":  {"label": "12-speed 10–52", "brand": "SPROKK", "name": "SK2 Condor Gold", "cogs": [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42, 52],
		"cols": ["d9a43c"], "rough": 0.16},
	"rainbow":{"label": "12-speed 10–52 rainbow", "brand": "SPROKK", "name": "SK2 Condor Rainbow", "cogs": [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42, 52],
		"cols": ["rainbow"], "rough": 0.12},
	"xtr":    {"label": "12-speed 10–51", "brand": "HIKARI", "name": "Elite 12", "cogs": [10, 12, 14, 16, 18, 21, 24, 28, 33, 39, 45, 51],
		"cols": ["dfe1e4", "5a5d63"], "rough": 0.2},
	"helix":  {"label": "12-speed 9–50", "brand": "Q*SEVEN", "name": "Spiral Race", "cogs": [9, 10, 12, 14, 16, 19, 22, 26, 30, 35, 42, 50],
		"cols": ["1f6fe0", "16171a"], "rough": 0.28},
	"summit": {"label": "12-speed 11–56", "brand": "GOATWORKS", "name": "Summit 56", "cogs": [11, 13, 15, 17, 19, 22, 25, 29, 34, 40, 47, 56],
		"cols": ["ff6a13", "1a1a1c"], "rough": 0.26},
	"everest":{"label": "13-speed 10–60", "brand": "GOATWORKS", "name": "Everest 60", "cogs": [10, 11, 13, 15, 17, 19, 22, 25, 29, 34, 41, 50, 60],
		"cols": ["7b2fd0", "c9ccd1"], "rough": 0.2},
}

## the cassette's per-cog colours (small cog first) for the wheel generator
static func cassette_cols(k: String) -> Array:
	var c: Dictionary = CASSETTES[k]
	var n: int = c.cogs.size()
	var out := []
	for i in n:
		var h: String = c.cols[i % c.cols.size()]
		if h == "rainbow":   # oil slick: blue -> purple -> magenta -> gold -> green over the stack
			var t := float(i) / maxf(1.0, n - 1.0)
			out.append(Color.from_hsv(fposmod(0.58 - t * 0.95, 1.0), 0.75, 0.95))
		else:
			out.append(Color(h))
	return out

static func default_build() -> Dictionary:
	return {
		"name": "RUNOUT DH",
		"paint": {
			"frame": {"color": "e8432e", "color2": "ffb000", "finish": "metallic"},
			"rear": {"color": "e8432e", "color2": "ffb000", "finish": "metallic"},
			"linkage": {"color": "c8ccd0", "color2": "ffffff", "finish": "chrome"},
			"fork": {"color": "1a1a1c", "color2": "ffffff", "finish": "gloss"},
			"stanchions": {"color": "c8a24a", "color2": "ffffff", "finish": "anodized"},
			"crown": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"},
			"spring": {"color": "e8b030", "color2": "ffffff", "finish": "gloss"},
			"shock": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"},
			"grips": {"color": "1c1c1c", "color2": "ffffff", "finish": "matte"},
			"saddle": {"color": "1c1c1c", "color2": "ffffff", "finish": "satin"},
			"crank": {"color": "1a1a1c", "color2": "ffffff", "finish": "anodized"},
		},
		"logos": {
			"downtube": {"logo": "cinelli", "text": "", "fill": "f4f4f0", "stroke": "141418", "pos": 0.5, "scale": 1.0, "rot": 0.0},
			"toptube": {"logo": "glory", "text": "", "fill": "f4f4f0", "stroke": "141418", "pos": 0.5, "scale": 1.0, "rot": 0.0},
			"chainstay": {"logo": "cinelli", "text": "", "fill": "f4f4f0", "stroke": "141418", "pos": 0.5, "scale": 1.0, "rot": 0.0},
			"forklegs": {"logo": "fox", "text": "", "fill": "f4f4f0", "stroke": "141418", "pos": 0.5, "scale": 1.0, "rot": 0.0},
			"bars": {"logo": "none", "text": "", "fill": "f4f4f0", "stroke": "141418", "pos": 0.5, "scale": 1.0, "rot": 0.0},
			"tyres": {"logo": "text", "text": "GRIPWELL", "fill": "f4f4f0", "stroke": "141418", "pos": 0.5, "scale": 1.0, "rot": 0.0},
			"rims": {"logo": "text", "text": "FREEFALL", "fill": "f4f4f0", "stroke": "141418", "count": 2, "pos": 0.5, "scale": 1.0, "rot": 0.0},
		},
		"wheels": {
			"front": "29", "rear": "27.5", "tyre_w": 2.5, "tread": "knobby", "sidewall": "black",
			"tyre_model": "custom", "pattern": "knobby", "casing": "round",
			"rim_model": "custom", "rim_profile": "hooked", "rim_material": "alloy",
			"rim_color": "1a1a1c", "rim_finish": "matte", "rim_depth": 28, "rim_width": 30,
			"spokes": 32, "lacing": 3, "gauge": 1, "spoke_color": "b8bcc0", "nipple_color": "e8432e", "hub_color": "1a1a1c",
		},
		"bars": {"width": 780, "rise": 30, "material": "alloy", "levers": "stock", "stem": "stock"},
		"seat": {"model": "stock", "post": "stock", "post_h": 0.0},
		"suspension": {"fork_model": "custom", "fork_travel": 200, "shock_travel": 200, "fork_spring": 1, "shock_spring": 1, "rebound": 1, "rear_caliper": "stock", "rotor": "stock"},
		"drive": {"ring": 34, "cassette": "dh7", "pedals": "stock"},
		# the bike's action cam: mount = ActionCam.BIKE_MOUNTS (none / bars / fork), the rest = the camera + add-ons (ActionCam.GEAR_ROWS)
		"camera": {"mount": "none", "model": "hero", "lens": "stock", "housing": "none", "mic": "none", "acc": "none"},
		# bike lights: model = BikeLight.MODELS (none / glint / luma / nocta / duskbane / sundowner), on when it's dark
		"lights": {"model": "luma"},
	}

## Showroom editions: ready-made bikes on the garage frames, each its own colourway + mix of parts (made-up names).
## frame = GameState.BIKES id; fork / tyre / rim / bar = model keys (applied through their presets, so the fork's
## colours, the tyre lettering etc. come along); set = anything else, merged over the stock build (keys that exist).
## Picking one in the garage loads it as the build to ride / edit (saved with SAVE like any change).
const EDITIONS := {
	"ghost_pepper": {"label": "Ghost Pepper", "style": "allround", "frame": "dh", "fork": "fox40p", "tyre": "assegai", "rim": "deemax", "bar": "fatbar_c",
		"set": {"paint": {"frame": {"color": "111214", "finish": "matte"}, "rear": {"color": "111214", "finish": "matte"},
			"linkage": {"color": "e8432e", "finish": "anodized"}, "spring": {"color": "e8432e", "finish": "gloss"},
			"grips": {"color": "e8432e", "finish": "matte"}, "crank": {"color": "111214", "finish": "anodized"}},
			"wheels": {"rim_color": "111214", "nipple_color": "e8432e", "hub_color": "e8432e", "sidewall": "tan"},
			"logos": {"downtube": {"fill": "e8432e"}, "toptube": {"fill": "e8432e"}},
			"drive": {"cassette": "helix"}, "suspension": {"rotor": "tues"}}},
	"lime_slime": {"label": "Lime Slime", "style": "speed", "frame": "tues", "fork": "dorado", "tyre": "kryptotal", "rim": "fr560",
		"set": {"paint": {"frame": {"color": "c6ff1a", "finish": "gloss"}, "rear": {"color": "c6ff1a", "finish": "gloss"},
			"spring": {"color": "111214", "finish": "gloss"}, "grips": {"color": "c6ff1a", "finish": "matte"}},
			"wheels": {"rim_color": "b8bcc0", "rim_finish": "chrome", "nipple_color": "c6ff1a"}, "drive": {"cassette": "mtb11"}}},
	"mango_tango": {"label": "Mango Tango", "style": "freeride", "frame": "goat", "fork": "bomber58", "tyre": "dh22", "rim": "arc30",
		"set": {"paint": {"frame": {"color": "ff6a00", "color2": "ffd21f", "finish": "pearl"}, "rear": {"color": "ff6a00", "color2": "ffd21f", "finish": "pearl"},
			"spring": {"color": "ffd21f", "finish": "gloss"}, "grips": {"color": "ff6a00", "finish": "matte"}},
			"wheels": {"rim_color": "2b2d31", "nipple_color": "ffb000", "sidewall": "tan"}, "drive": {"cassette": "summit"}}},
	"midnight_owl": {"label": "Midnight Owl", "style": "freeride", "frame": "fuzz", "fork": "fuzz_fork", "tyre": "magic_mary", "rim": "flow",
		"set": {"paint": {"frame": {"color": "1d2b64", "finish": "candy"}, "rear": {"color": "1d2b64", "finish": "candy"},
			"spring": {"color": "c8a24a", "finish": "gloss"}, "grips": {"color": "111214", "finish": "matte"}},
			"wheels": {"rim_color": "c8a24a", "rim_finish": "gloss", "nipple_color": "c8a24a", "sidewall": "tan"},
			"drive": {"cassette": "eagle"}, "suspension": {"rotor": "fuzz"}}},
	"bubblegum_bandit": {"label": "Bubblegum Bandit", "style": "park", "frame": "dh", "fork": "dorado", "tyre": "minion_dhf", "rim": "lg1", "bar": "atlas",
		"set": {"paint": {"frame": {"color": "ff4f9a", "finish": "gloss"}, "rear": {"color": "ff4f9a", "finish": "gloss"},
			"linkage": {"color": "f4f4f0", "finish": "gloss"}, "spring": {"color": "f4f4f0", "finish": "gloss"},
			"grips": {"color": "f4f4f0", "finish": "matte"}, "saddle": {"color": "f4f4f0", "finish": "satin"}},
			"wheels": {"rim_color": "f4f4f0", "rim_finish": "gloss", "spoke_color": "f4f4f0", "nipple_color": "ff4f9a"},
			"drive": {"cassette": "rainbow"}, "bars": {"levers": "fuzz"}, "seat": {"model": "fuzz"}}},
	"rusty_nail": {"label": "Rusty Nail", "style": "allround", "frame": "goat", "fork": "era", "tyre": "butcher", "rim": "reserve30",
		"set": {"paint": {"frame": {"color": "8a5a2b", "finish": "satin"}, "rear": {"color": "8a5a2b", "finish": "satin"},
			"spring": {"color": "e0d3b8", "finish": "gloss"}, "grips": {"color": "e0d3b8", "finish": "matte"}},
			"wheels": {"rim_color": "6b6f75", "nipple_color": "c8a24a", "sidewall": "tan"}, "drive": {"cassette": "dh7w"}}},
	"frosty_gnar": {"label": "Frosty Gnar", "style": "race", "frame": "tues", "fork": "fox40f", "tyre": "minion_dhr", "rim": "synthesis",
		"set": {"paint": {"frame": {"color": "f4f4f0", "finish": "gloss"}, "rear": {"color": "f4f4f0", "finish": "gloss"},
			"spring": {"color": "2f7de1", "finish": "gloss"}, "grips": {"color": "2f7de1", "finish": "matte"}},
			"wheels": {"rim_color": "2f7de1", "rim_finish": "gloss", "nipple_color": "f4f4f0"},
			"drive": {"cassette": "xtr"}, "suspension": {"rotor": "tues"}}},
	"hot_lava": {"label": "Hot Lava", "style": "park", "frame": "fuzz", "fork": "boxxer_u", "tyre": "big_betty", "rim": "oozy",
		"set": {"paint": {"frame": {"color": "e8432e", "color2": "ffb000", "finish": "candy"}, "rear": {"color": "e8432e", "color2": "ffb000", "finish": "candy"},
			"spring": {"color": "111214", "finish": "gloss"}, "grips": {"color": "ffb000", "finish": "matte"}},
			"wheels": {"rim_color": "111214", "nipple_color": "ffb000"}, "drive": {"cassette": "dh7"}}},
	"stealth_mode": {"label": "Stealth Mode", "style": "race", "frame": "dh", "fork": "boxxer_s", "tyre": "shorty", "rim": "moto", "bar": "m9",
		"set": {"paint": {"frame": {"color": "2b2d31", "finish": "matte"}, "rear": {"color": "2b2d31", "finish": "matte"},
			"linkage": {"color": "111214", "finish": "anodized"}, "spring": {"color": "2b2d31", "finish": "satin"},
			"grips": {"color": "111214", "finish": "matte"}, "crank": {"color": "111214", "finish": "anodized"}},
			"wheels": {"rim_color": "111214", "spoke_color": "2b2d31", "nipple_color": "111214", "hub_color": "111214"},
			"logos": {"downtube": {"fill": "6b6f75"}, "toptube": {"fill": "6b6f75"}, "chainstay": {"fill": "6b6f75"}},
			"drive": {"cassette": "dh7w"}, "bars": {"levers": "tues", "stem": "tues"}, "suspension": {"rear_caliper": "tues"}}},
	"toxic_waste": {"label": "Toxic Waste", "style": "speed", "frame": "goat", "fork": "onyx", "tyre": "minion_ss", "rim": "fuse",
		"set": {"paint": {"frame": {"color": "35d04a", "color2": "7b3fe4", "finish": "pearl"}, "rear": {"color": "7b3fe4", "finish": "metallic"},
			"spring": {"color": "c6ff1a", "finish": "gloss"}, "grips": {"color": "7b3fe4", "finish": "matte"}},
			"wheels": {"rim_color": "7b3fe4", "rim_finish": "gloss", "nipple_color": "c6ff1a"}, "drive": {"cassette": "everest"}}},
}

## riding styles: the parts that make a bike ride for it (wheels, travel, springs, gearing), laid over an edition's
## own set (its colours and the rest stay). Park = small, firm, light: pops and spins; speed = big wheels, tall gears.
const STYLES := {
	"park":     {"label": "Park", "set": {"wheels": {"front": "27.5", "rear": "27.5", "tyre_w": 2.35},
		"suspension": {"fork_travel": 160, "shock_travel": 160, "fork_spring": 2, "shock_spring": 2, "rebound": 2},
		"drive": {"ring": 32, "cassette": "single"}}},
	"freeride": {"label": "Freeride", "set": {"wheels": {"front": "27.5", "rear": "27.5", "tyre_w": 2.6},
		"suspension": {"fork_travel": 180, "shock_travel": 180, "fork_spring": 1, "shock_spring": 1, "rebound": 1},
		"drive": {"ring": 32}}},
	"allround": {"label": "All-round", "set": {}},
	"race":     {"label": "Race", "set": {"wheels": {"front": "29", "rear": "29"},
		"suspension": {"fork_travel": 200, "shock_travel": 200, "rebound": 0},
		"drive": {"ring": 36, "cassette": "dh7"}}},
	"speed":    {"label": "Speed", "set": {"wheels": {"front": "29", "rear": "29", "tyre_w": 2.4, "rim_material": "carbon"},
		"suspension": {"fork_travel": 200, "shock_travel": 200, "fork_spring": 2, "shock_spring": 2, "rebound": 1},
		"drive": {"ring": 38, "cassette": "dh7"}}},
}

## the build of a showroom edition (EDITIONS)
static func edition_build(id: String) -> Dictionary:
	var e: Dictionary = EDITIONS[id]
	var b := default_build()
	b.name = String(e.label).to_upper()
	if e.has("fork"): apply_fork_model(b, e.fork)
	if e.has("tyre"): apply_tyre_model(b, e.tyre)
	if e.has("rim"): apply_rim_model(b, e.rim)
	if e.has("bar") and Handlebar.MODELS.has(e.bar):
		var m: Dictionary = Handlebar.MODELS[e.bar]
		b.bars.model = e.bar
		for k in ["width", "rise", "material"]:
			if m.has(k): b.bars[k] = m[k]
	_merge(b, e.get("set", {}))
	_merge(b, STYLES.get(str(e.get("style", "allround")), STYLES.allround).set)   # the style's riding parts on top
	return b

## the BMX only takes tyres: stock 20" wheels with this tyre model on them (single speed, no cassette)
static func bmx_build(tyre_key: String) -> Dictionary:
	var b := default_build()
	b.wheels.front = "20"; b.wheels.rear = "20"
	b.single_speed = true
	apply_tyre_model(b, tyre_key)
	return b

## each frame's own factory colours (paint parts laid over default_build's), so the frames don't all come out alike.
## The parts of a build are shared by every frame; the paint is kept per frame (garage.json "paints": {frame: paint}).
## A frame not painted yet gets a factory colourway picked at random once, the same every launch (fixed seed, frames
## in GameState.BIKES order): a plain frame colour from a list of real-looking bike paints, a matching spring / linkage /
## grips, black or tan-wall tyres. Change FACTORY_SEED for a different set.
const FACTORY_COLORS := ["1e9bd7", "1d2b64", "2f7de1", "1a1c1f", "2e7d32", "4a5d3a", "8a5a2b", "ff6a00",
	"ffd21f", "7b3fe4", "0f8f8a", "b3122e", "e8432e"]
const FACTORY_FINISHES := ["gloss", "gloss", "metallic", "metallic", "matte", "satin", "pearl"]
const FACTORY_ACCENTS := ["111214", "f4f4f0", "e8b030", "c8ccd0", "e8432e", "ff6a00"]
const FACTORY_SEED := 20261120
static var _factory := {}   # frame -> {"paint", "sidewall"}

static func _factory_look(frame: String) -> Dictionary:
	if _factory.is_empty():   # every garage frame at once, in a fixed order, so no two share a colour
		var rng := RandomNumberGenerator.new()
		rng.seed = FACTORY_SEED
		for id in GameState.BIKES:
			if GameState.BIKES[id].get("garage", false): _factory[id] = _make_factory(rng)
	if not _factory.has(frame):
		var rng := RandomNumberGenerator.new()
		rng.seed = FACTORY_SEED + hash(frame)
		_factory[frame] = _make_factory(rng)
	return _factory[frame]

static func _make_factory(rng: RandomNumberGenerator) -> Dictionary:
	var used := []
	for f in _factory: used.append(_factory[f].paint.frame.color)
	var cols := FACTORY_COLORS.filter(func(c): return not used.has(c))
	var col: String = cols[rng.randi() % cols.size()]
	var fin: String = FACTORY_FINISHES[rng.randi() % FACTORY_FINISHES.size()]
	var acc: String = FACTORY_ACCENTS[rng.randi() % FACTORY_ACCENTS.size()]
	if acc == col: acc = "111214" if col != "111214" else "f4f4f0"
	var p: Dictionary = default_build().paint
	_merge(p, {"frame": {"color": col, "color2": col, "finish": fin}, "rear": {"color": col, "color2": col, "finish": fin},
		"spring": {"color": acc, "finish": "gloss"},
		"linkage": {"color": ["111214", "c8ccd0", col][rng.randi() % 3], "finish": ["anodized", "chrome", fin][rng.randi() % 3]},
		"grips": {"color": acc if rng.randf() < 0.4 else "1c1c1c", "finish": "matte"}})
	return {"paint": p, "sidewall": "tan" if rng.randf() < 0.45 else "black"}

## an old file's paint that is just the stock red default (never painted)
static func _is_stock_paint(p) -> bool:
	if not (p is Dictionary): return false
	var d: Dictionary = default_build().paint
	for k in ["frame", "rear"]:
		if not (p.get(k) is Dictionary) or String(p[k].get("color", "")) != String(d[k].color): return false
	return true

## the factory paint of a frame
static func frame_paint(frame: String) -> Dictionary:
	return _factory_look(frame).paint.duplicate(true)

## the saved build with `frame`'s paint on it ("" = the frame in use)
static func load_build(frame := "") -> Dictionary:
	if frame == "": frame = GameState.bike_id
	var b := default_build()
	b.paint = frame_paint(frame)
	var painted := false   # this frame has a paint of the player's (else its factory look, tyres too)
	if FileAccess.file_exists(PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if j is Dictionary:
			var paints = j.get("paints", {})
			if paints is Dictionary and paints.get(frame) is Dictionary: j.paint = paints[frame]; painted = true
			elif paints is Dictionary and not paints.is_empty() or frame != "dh" or _is_stock_paint(j.get("paint")): j.erase("paint")   # (an old file's one paint = the stock frame's; the untouched stock red counts as none)
			else: painted = true
			_merge(b, j)
			rebrand(b)
	if not painted: b.wheels.sidewall = _factory_look(frame).sidewall
	# tests: BMX_BUILD="wheels.rim_model=deemax;bars.width=820;..." (models applied through their presets)
	for kv in Env.raw("BMX_BUILD").split(";", false):
		var p := kv.split("=")
		if p.size() != 2: continue
		var path := p[0].split(".")
		var d = b
		for i in path.size() - 1:
			d = d.get(path[i]) if d is Dictionary else null
		var key: String = path[path.size() - 1]
		if key == "fork_model" and d is Dictionary: apply_fork_model(b, p[1]); continue
		if d is Dictionary and SuspSetup.DEFAULTS.has(key):   # (the suspension setup: its keys are only in a build once set)
			d[key] = p[1] if SuspSetup.DEFAULTS[key] is String else float(p[1]); continue
		if not (d is Dictionary) or not d.has(key) or d[key] is Dictionary: continue
		if key == "tyre_model": apply_tyre_model(b, p[1]); continue
		if key == "rim_model": apply_rim_model(b, p[1]); continue
		d[key] = float(p[1]) if typeof(d[key]) in [TYPE_INT, TYPE_FLOAT] else p[1]
	return b

## lettering saved by older versions (real brand names) -> the game's own made-up brands
const OLD_BRANDS := {
	"MAXXIS": "GRIPWELL", "SCHWALBE": "TRAKKA", "MICHELIN": "MORVAN", "CONTINENTAL": "KONTOUR", "SPECIALIZED": "RIDGEFORM",
	"DT SWISS": "ALPWERK", "MAVIC": "CASTEL", "RACE FACE": "RAW EDGE", "SPANK": "SMACK", "STAN'S NOTUBES": "SEALCO",
	"E*THIRTEEN": "Q*SEVEN", "WE ARE ONE": "HIVEMIND", "RESERVE": "STOCKPILE", "CRANKBROTHERS": "COGSMITH", "ZIPP": "WHIZZ",
	"GRAVITY": "FREEFALL", "GLORY": "RUNOUT", "GLORY DH": "RUNOUT DH", "FOX": "KOMODO", "CINELLI": "MONTELLI",
}

## a loaded build: real brand names it still carries (tyre / rim lettering, the bike's name) -> ours
static func rebrand(b: Dictionary) -> void:
	if OLD_BRANDS.has(str(b.get("name", "")).to_upper()):
		b.name = OLD_BRANDS[str(b.name).to_upper()]
	var logos: Dictionary = b.get("logos", {})
	for slot in logos:
		var L = logos[slot]
		if L is Dictionary and OLD_BRANDS.has(str(L.get("text", "")).to_upper()):
			L.text = OLD_BRANDS[str(L.text).to_upper()]

static func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if k in ["livery", "lcolor"] and src[k] is String:   # (only in a paint that has one: not in the defaults)
			dst[k] = src[k]
		elif dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		elif dst.has(k) and typeof(dst[k]) in [TYPE_FLOAT, TYPE_INT] and typeof(src[k]) in [TYPE_FLOAT, TYPE_INT]:
			dst[k] = src[k]
		elif dst.has(k) and typeof(dst[k]) == typeof(src[k]):
			dst[k] = src[k]

## save a build; its paint is kept as `frame`'s ("" = the frame in use), the other frames' paints stay
static func save_build(b: Dictionary, frame := "") -> void:
	if Env.raw("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
	if frame == "": frame = GameState.bike_id
	var paints := {}
	if FileAccess.file_exists(PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if j is Dictionary and j.get("paints") is Dictionary: paints = j.paints
		elif j is Dictionary and j.get("paint") is Dictionary: paints = {"dh": j.paint}   # an old file: its paint was the stock frame's
	var out := b.duplicate(true)
	out.erase("paints")
	paints[frame] = b.paint.duplicate(true)
	out.paints = paints
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(out, "\t"))
	Steam.event("GARAGE")

## copy a PNG the player picked into user://logos and return its new path
static func import_logo(src: String) -> String:
	DirAccess.make_dir_recursive_absolute(LOGO_DIR)
	var img := Image.load_from_file(src)
	if img == null or img.is_empty(): return ""
	if img.get_width() > 1024: img.resize(1024, int(1024.0 * img.get_height() / img.get_width()))
	var dst := "%s/%s.png" % [LOGO_DIR, src.get_file().get_basename().validate_filename()]
	img.save_png(dst)
	return dst

static func imported_logos() -> Array:
	var out := []
	var d := DirAccess.open(LOGO_DIR)
	if d:
		for f in d.get_files():
			if f.get_extension().to_lower() == "png": out.append("%s/%s" % [LOGO_DIR, f])
	return out

# ---------------------------------------------------------------- materials
static var _mat_cache := {}

const BLACK_FLOOR := 0.15   # the darkest a paint's brightest channel may be (sRGB); a "black" swatch of 0.07 shaded to a flat hole
## Nothing real is 0 % black: lifts very dark paint to a deep charcoal, keeping its hue, so the lighting still shapes it
static func lift_black(c: Color) -> Color:
	var f := float(Env.raw("BMX_BLACK_FLOOR")) if Env.raw("BMX_BLACK_FLOOR") != "" else BLACK_FLOOR
	var mx := maxf(c.r, maxf(c.g, c.b))
	if mx >= f: return c
	if mx < 0.005: return Color(f, f, f * 1.03, c.a)
	var k := lerpf(1.0, f / mx, 0.85)
	return Color(c.r * k, c.g * k, c.b * k, c.a)

## Liveries: a second colour (paint.lcolor) laid over the frame paint in a pattern (shader `livery` = the index).
## Only the frame triangles offer them in the garage; any part's paint may carry one.
const LIVERIES := {
	"none":    {"label": "Solid",       "id": 0},
	"fade_x":  {"label": "Fade",        "id": 1},
	"fade_y":  {"label": "Fade up",     "id": 2},
	"split":   {"label": "Two-tone",    "id": 3},
	"stripe":  {"label": "Stripe",      "id": 4},
	"bands":   {"label": "Bands",       "id": 5},
	"speed":   {"label": "Speed",       "id": 6},
	"camo":    {"label": "Camo",        "id": 7},
	"splat":   {"label": "Splatter",    "id": 8},
	"check":   {"label": "Checkers",    "id": 9},
	"sunset":  {"label": "Sunset",      "id": 10},
}

static func paint_material(p: Dictionary) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [p.color, p.color2, p.finish, p.get("livery", "none"), p.get("lcolor", "ffffff")]
	if _mat_cache.has(key): return _mat_cache[key]
	var F: Dictionary = FINISHES.get(p.finish, FINISHES.gloss)
	var col := Color(p.color)
	if F.has("deep"): col = col.darkened(0.15)
	col = lift_black(col)
	var m := BikeFX.car_paint(null, {"color": col, "metallic": F.metallic, "roughness": F.roughness,
		"sparkle": F.sparkle, "clearcoat_roughness": F.cc_rough, "flake": F.get("flake", 0.00025)})
	m.set_shader_parameter("clearcoat", F.clearcoat)
	m.set_shader_parameter("color2", Color(p.color2))
	m.set_shader_parameter("flip", F.flip)
	m.set_shader_parameter("deep", F.get("deep", 0.0))
	m.set_shader_parameter("livery", int(LIVERIES.get(String(p.get("livery", "none")), LIVERIES.none).id))
	m.set_shader_parameter("lcolor", lift_black(Color(String(p.get("lcolor", "ffffff")))))
	_mat_cache[key] = m
	return m

## Where the bike's frame sits in the model and how big it is (model units): the livery's pattern is laid
## across this box, so both triangles carry one design. Returns {min, ext} (Vector3s), or {} with no frame.
static func _frame_box(model: Node3D) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for n in ["frame", "swing", "seatstay"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null: continue
		var off := _model_off(model, mi)
		var bb := mi.mesh.get_aabb()
		lo = lo.min(bb.position + off)
		hi = hi.max(bb.end + off)
	if lo.x == INF: return {}
	return {"min": lo, "ext": hi - lo}

## the mesh's origin in the model's space (translation only: the frame's nodes are not rotated or scaled at rest)
static func _model_off(model: Node3D, mi: Node3D) -> Vector3:
	var off := Vector3.ZERO
	var n: Node = mi
	while n != null and n != model:
		if n is Node3D: off += (n as Node3D).position
		n = n.get_parent()
	return off

## paint every part of a rig's bike model
static func apply_paint(model: Node3D, b: Dictionary) -> void:
	var box := _frame_box(model)
	var test_lv := Env.raw("BMX_LIVERY")   # test: "fade_x:1a1a1c" = that livery + colour on the frame
	for part in PARTS:
		var pp: Dictionary = b.paint[part]
		if part == "stanchions": pp = stanchion_paint(pp)
		if test_lv != "" and part in ["frame", "rear"]:
			pp = pp.duplicate()
			pp.livery = test_lv.get_slice(":", 0)
			if ":" in test_lv: pp.lcolor = test_lv.get_slice(":", 1)
		var mat := paint_material(pp)
		var lv := String(pp.get("livery", "none")) != "none" and not box.is_empty()
		for target in PARTS[part][1]:
			var mi := model.find_child(target[0], true, false) as MeshInstance3D
			if mi == null or mi.mesh == null: continue
			if lv:
				mi.set_instance_shader_parameter("liv_off", _model_off(model, mi))
				mi.set_instance_shader_parameter("liv_min", box.min)
				mi.set_instance_shader_parameter("liv_ext", box.ext)
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				if sm and sm.resource_name == target[1]:
					mi.set_surface_override_material(i, mat)
	# the split-off pedals carry the crank's plastic material: paint them with the saddle
	var crank := model.find_child("crank", true, false)
	if crank:
		var pm := paint_material(b.paint.saddle)
		for pivot in crank.get_children():
			for c in pivot.get_children():
				if c is MeshInstance3D and c.name != "rotor": c.material_override = pm
	# a fork model's crowns + stanchions are their own mesh on the steer node (BikeRig._swap_fork)
	var fc := model.find_child("fork_crown", true, false) as MeshInstance3D
	if fc and fc.mesh:
		for i in fc.mesh.get_surface_count():
			var nm := fc.mesh.surface_get_material(i).resource_name
			if nm == "gold": fc.set_surface_override_material(i, paint_material(stanchion_paint(b.paint.stanchions)))
			elif nm == "black": fc.set_surface_override_material(i, paint_material(b.paint.crown))

## decals.gd config from the logo slots
static func decal_config(b: Dictionary) -> Dictionary:
	var labels := []
	for slot in SLOTS:
		var L: Dictionary = b.logos[slot]
		var e: Dictionary = SLOTS[slot].tmpl.duplicate(true)
		var logo: String = L.logo
		if logo == "none": continue
		if logo.begins_with("file:"):
			e.image = logo.substr(5)
		elif logo == "text":
			if L.text.strip_edges() == "": continue
			e.text = L.text
		elif LOGOS.has(logo):
			var lg: Dictionary = LOGOS[logo]
			if lg.has("image"): e.image = lg.image
			if lg.has("imageMinus"): e.imageMinus = lg.imageMinus
			if lg.has("text"): e.text = lg.text
		else:
			continue
		e.fill = Color(L.fill); e.stroke = Color(L.stroke, 0.85)
		e.pos = float(L.get("pos", 0.5)); e.scale = float(L.get("scale", 1.0)); e.rot = float(L.get("rot", 0.0))
		if e.get("bar", false):   # the bar's grip end moves with its width
			e.grip_z = Handlebar.GRIP + (float(b.bars.width) - Handlebar.STOCK_WIDTH) / 2000.0
		labels.append(e)
	var cfg := {"labels": labels}
	var tl: Dictionary = b.logos.tyres
	if tl.logo != "none" and tl.text.strip_edges() != "":
		cfg.tyres = {"text": tl.text, "scale": float(tl.get("scale", 1.0)), "rot": float(tl.get("rot", 0.0)), "lift": float(tl.get("lift", 0.1)), "fill": Color(String(tl.get("fill", "f4f4f0"))), "meshes": [["wheel_front", "rubber"], ["wheel_rear", "rubber"]]}
	var rl: Dictionary = b.logos.rims
	var rim := {"fill": Color(rl.fill), "depth": float(b.wheels.rim_depth) / 1000.0, "count": int(rl.get("count", 2)), "scale": float(rl.get("scale", 1.0)), "rot": float(rl.get("rot", 0.0)),
		"meshes": [["wheel_front", "rim"], ["wheel_rear", "rim"]]}
	var rlogo: String = rl.logo
	if rlogo.begins_with("file:"):
		rim.image = rlogo.substr(5)
	elif rlogo == "text":
		if rl.text.strip_edges() != "": rim.text = rl.text
	elif LOGOS.has(rlogo):
		var lg: Dictionary = LOGOS[rlogo]
		if lg.has("image"): rim.image = lg.image
		if lg.has("text"): rim.text = lg.text
	if rim.has("text") or rim.has("image"):
		cfg.rims = rim
	return cfg

static func wheel_spec(b: Dictionary, rear: bool) -> Dictionary:
	var w: Dictionary = b.wheels
	var spec := {
		"bsd_mm": WHEEL_SIZES[w.rear if rear else w.front], "tyre_w_in": w.tyre_w, "tread": w.tread, "sidewall": w.sidewall,
		"rim_color": Color(w.rim_color), "rim_finish": w.rim_finish, "rim_depth_mm": w.rim_depth, "rim_width_mm": w.rim_width,
		"rim_profile": w.rim_profile, "rim_material": w.rim_material, "pattern": w.pattern, "casing": w.casing,
		"spokes": int(w.spokes), "lacing": int(w.lacing), "spoke_gauge": int(w.gauge), "spoke_color": Color(w.spoke_color),
		"nipple_color": Color(w.nipple_color), "hub_color": Color(w.hub_color), "rear": rear,
	}
	if rear and not b.get("single_speed", false):
		spec.cogs = CASSETTES[b.drive.cassette].cogs
		spec.cas_cols = cassette_cols(b.drive.cassette)
		spec.cas_rough = CASSETTES[b.drive.cassette].rough
	return spec

## tyre radius without the wheel generator (bead seat + tyre height, matched to the stock 29 / 27.5 x 2.5)
static func tyre_radius(bsd: float, tyre_w: float) -> float:
	return (bsd / 2.0 + tyre_w * 25.4 * 0.998) / 1000.0

# ---------------------------------------------------------------- ride effects
## -> {ride: {tune key: multiplier}, wheel_f, wheel_r (radii), cogs, ring_k, fork_travel, shock_travel}
static func ride_mods(b: Dictionary) -> Dictionary:
	var w: Dictionary = b.wheels
	var s: Dictionary = b.suspension
	var rf := tyre_radius(WHEEL_SIZES[w.front], w.tyre_w)
	var rr := tyre_radius(WHEEL_SIZES[w.rear], w.tyre_w)
	var trav := (float(s.fork_travel) + float(s.shock_travel)) / 400.0     # 1 = stock 200 / 200
	# (springs, damping and tyre pressure are the suspension setup now: SuspSetup, read by the ride physics as it is)
	var susp := SuspSetup.resolve(b)
	var psi: float = (float(susp.psi_f) + float(susp.psi_r)) * 0.5
	var psi_grip := 1.0 + 0.006 * (24.5 - psi)    # softer tyres: a bigger patch, more grip ...
	var psi_roll := 1.0 + 0.012 * (24.5 - psi)    # ... and more drag
	var tread_grip: float = {"knobby": 1.0, "semi": 0.94, "slick": 0.82}.get(w.tread, 1.0)
	var tread_roll: float = {"knobby": 1.0, "semi": 0.85, "slick": 0.7}.get(w.tread, 1.0)
	# the knob layout on top: dense / open knobs bite more and drag more, blocks roll fast
	tread_grip *= {"dense": 1.03, "stagger": 1.02, "spike": 1.01, "block": 0.98}.get(w.pattern, 1.0)
	tread_roll *= {"paddle": 1.02, "dense": 1.05, "stagger": 1.05, "spike": 1.12, "block": 0.94}.get(w.pattern, 1.0)
	if w.casing == "square": tread_grip *= 1.02   # square shoulders hold an edge in turns
	var width_grip := 1.0 + (float(w.tyre_w) - 2.5) * 0.25
	var size_roll := 1.0 - ((rf + rr) / 2.0 - 0.3645) * 1.6         # bigger wheels roll over stuff easier
	var spoke_w := 1.0 + (int(w.spokes) - 32) * 0.004 + (int(w.gauge) - 1) * 0.02 + (float(w.rim_depth) - 28) * 0.002
	if w.rim_material == "carbon": spoke_w *= 0.97   # lighter, stiffer wheels
	var ride := {
		"travel": trav, "legComp": 0.9 + 0.1 * trav,
		"grip": tread_grip * width_grip * psi_grip, "rollRes": tread_roll * size_roll * (1.0 + (float(w.tyre_w) - 2.5) * 0.2) * psi_roll,
		# wider bars: slower, steadier steering (780 mm = 1)
		"pedalLaunch": 1.0 / spoke_w, "steerRate": 1.0 / sqrt(spoke_w) * (1.0 - (rf - 0.374) * 1.2) * (1.0 - (float(b.bars.width) - 780.0) * 0.0015),
	}
	var perf := Catalog.ride_perf(b)   # the bought small parts' tiers (brakes, stem, pedals, post: store/catalog.gd)
	for k in perf: ride[k] = float(ride.get(k, 1.0)) * float(perf[k])
	var cogs: Array = CASSETTES[b.drive.cassette].cogs
	return {"ride": ride, "wheel_f": rf, "wheel_r": rr, "cogs": cogs, "ring_k": float(b.drive.ring) / 34.0,
		"fork_travel": float(s.fork_travel) / 1000.0, "shock_travel": float(s.shock_travel) / 1000.0,
		"land": 0.85 + 0.15 * trav, "susp": susp}

# ---------------------------------------------------------------- frame character
## Every garage frame rides differently, from what it is: its geometry (measured off its glb by
## tools/frame_geo_probe.gd), its weight and its suspension design. The RUNOUT DH ("dh") is the reference: with
## stock parts all its multipliers are 1 (the tuned feel). The physics already turns on the real wheelbase
## (yaw = v tan(steer) / L); frame_mods adds what the sim had no notion of:
##   wheelbase  longer = calmer at speed (bumps knock the rear less, slides caught easier, less twitch) but slower
##              to flick side to side, harder to whip
##   head angle slacker (deg) = steadier, a steep drop takes more to nose-dive; lazier steering when slow
##   chainstay  shorter = easier to manual / wheelie / pop / whip; longer = steadier, less wheelspin climbing
##   bb_drop    lower bottom bracket (more drop) = more planted, grippier carving; higher = quicker to flick over
##   kg         frame weight (with shock): the whole bike's weight (bike_kg) vs. the rider: heavier keeps its speed
##              (air drag hurts less), stays planted on bumps; lighter accelerates, brakes and pops quicker
##   progression rear suspension ramp-up: more = takes bigger hits (landings) and pumps / pops harder
##   anti_squat pedalling efficiency (the suspension doesn't bob): more = more drive from each stroke
##   stiff      frame / front end stiffness: sharper steering, less tyre squirm
##   class      what it's built for (CLASSES): slow -> fast; sets the gear-limited top speed
const FRAMES := {
	"fuzz": {"class": "freeride", "wheelbase": 1.254, "head": 62.0, "chainstay": 0.449, "bb_drop": 0.017, "kg": 4.0,
		"progression": 0.85, "anti_squat": 0.35, "stiff": 0.95},
	"dh":   {"class": "allround", "wheelbase": 1.256, "head": 62.8, "chainstay": 0.442, "bb_drop": 0.035, "kg": 4.6,
		"progression": 0.6, "anti_squat": 0.5, "stiff": 1.0},
	"tues": {"class": "race", "wheelbase": 1.273, "head": 63.2, "chainstay": 0.451, "bb_drop": 0.0, "kg": 4.9,
		"progression": 0.5, "anti_squat": 0.7, "stiff": 1.1},
	"goat": {"class": "speed", "wheelbase": 1.380, "head": 62.8, "chainstay": 0.504, "bb_drop": 0.034, "kg": 5.6,
		"progression": 0.45, "anti_squat": 0.6, "stiff": 1.15},
}
## the frame classes, slow -> fast. top = gear-limited top speed (topSpeed, pedalTop); the rest multiply on top of
## the geometry (a park bike flips and spins a little quicker, a speed bike a little slower)
const CLASSES := {
	"freeride": {"label": "Freeride", "top": 0.93, "extra": {"flipRate": 1.06, "stickSpinMax": 1.06, "flickSpeed": 1.05, "leanRate": 1.08}},
	"allround": {"label": "All-round", "top": 1.0, "extra": {}},
	"race":     {"label": "Race", "top": 1.06, "extra": {"flipRate": 0.97}},
	"speed":    {"label": "Speed", "top": 1.12, "extra": {"flipRate": 0.94, "stickSpinMax": 0.94, "flickSpeed": 0.95, "leanRate": 0.94}},
}
const RIDER_KG := 75.0
const PEDAL_KG := {"dh": 0.36, "tues": 0.42, "fuzz": 0.38}

## the bike's weight by part (kg): frame (with shock), wheels (rims, spokes, tyres; both), fork, cassette, pedals,
## cockpit (bars, stem, grips), rest (brakes, cranks, chain, seat: the same on every build)
static func kg_parts(frame: String, b: Dictionary) -> Dictionary:
	var F: Dictionary = FRAMES.get(frame, FRAMES.dh)
	var w: Dictionary = b.wheels
	var s: Dictionary = b.suspension
	var wheels := 0.0
	for size in [w.front, w.rear]:
		wheels += {"20": 1.5, "26": 1.9, "27.5": 2.0, "29": 2.15}.get(str(size), 2.0)
		wheels += (float(w.tyre_w) - 2.5) * 0.5 + (int(w.spokes) - 32) * 0.006 - (0.25 if w.rim_material == "carbon" else 0.0)
	var fm: Dictionary = FORK_MODELS.get(str(s.get("fork_model", "")), {})
	var fork := 2.7 + (0.35 if str(fm.get("spring", "Air")) == "Coil" else 0.0) + (float(s.fork_travel) - 200.0) * 0.005
	# (the rear shock against the stock coil one: an air shock saves ~0.4 kg)
	fork += float(SuspSetup.SHOCK_MODELS.get(str(SuspSetup.val(s, "shock_model")), SuspSetup.SHOCK_MODELS[SuspSetup.DEFAULT_SHOCK]).kg) - 0.95
	var cogs: Array = CASSETTES[b.drive.cassette].cogs
	return {
		"Frame": float(F.kg),
		"Wheels": wheels,
		"Fork": fork,
		"Cassette": cogs.size() * 0.03 + float(cogs[cogs.size() - 1]) * 0.004,
		"Pedals": float(PEDAL_KG.get(str(b.drive.get("pedals", "stock")), 0.38)),
		"Cockpit": 0.9 - (0.1 if str(b.bars.get("material", "alloy")).begins_with("carbon") else 0.0),
		"Rest": 4.4,
	}

## the whole bike's weight (kg): frame + the parts the build fits
static func bike_kg(frame: String, b: Dictionary) -> float:
	var kg := 0.0
	for v in kg_parts(frame, b).values(): kg += float(v)
	return kg

static func _opt_label(list: Array, id: String) -> String:
	for o in list:
		if str(o[0]) == id: return String(o[1])
	return id

## everything about a build, as [label, value] rows (garage part info): what the bike is fitted with
static func props(b: Dictionary) -> Array:
	var w: Dictionary = b.wheels
	var s: Dictionary = b.suspension
	var d: Dictionary = b.drive
	var fm: Dictionary = FORK_MODELS.get(str(s.get("fork_model", "")), {})
	var cogs: Array = CASSETTES[d.cassette].cogs
	var rate := ["soft", "medium", "firm"]
	var tm: Dictionary = TYRE_MODELS.get(str(w.get("tyre_model", "")), {})
	var rm: Dictionary = RIM_MODELS.get(str(w.get("rim_model", "")), {})
	return [
		["Fork", "%s  ·  %d mm  ·  %s  ·  %s" % [String(fm.get("label", "Custom")), int(s.fork_travel), String(fm.get("spring", "Air")), rate[int(s.fork_spring)]]],
		["Rear shock", "%d mm  ·  %s  ·  rebound %s" % [int(s.shock_travel), rate[int(s.shock_spring)], ["slow", "medium", "fast"][int(s.rebound)]]],
		["Wheels", "%s\" front  ·  %s\" rear  ·  %d spokes" % [w.front, w.rear, int(w.spokes)]],
		["Tyres", "%s  ·  %.1f\"  ·  %s  ·  %s casing" % [String(tm.get("label", "Custom")), float(w.tyre_w), String(w.pattern), String(w.casing)]],
		["Rims", "%s  ·  %s  ·  %s" % [String(rm.get("label", "Custom")), String(w.rim_material), String(w.rim_profile)]],
		["Bars", "%d mm  ·  %d mm rise  ·  %s" % [int(b.bars.width), int(b.bars.rise), String(b.bars.material)]],
		["Gearing", "%dT ring  ·  %d-speed %d–%dT" % [int(d.ring), cogs.size(), cogs[0], cogs[cogs.size() - 1]]],
		["Brakes", "%s rotors  ·  %s rear caliper  ·  %s levers" % [_opt_label(ROTORS, str(s.get("rotor", "stock"))),
			_opt_label(REAR_CALIPERS, str(s.get("rear_caliper", "stock"))), _opt_label(LEVERS, str(b.bars.get("levers", "stock")))]],
		["Pedals", _opt_label(PEDALS, str(d.get("pedals", "stock")))],
	]

## the frame's ride multipliers (Tune keys) for a build on it: geometry + weight + suspension design + class
static func frame_mods(frame: String, b: Dictionary) -> Dictionary:
	if not FRAMES.has(frame): return {}
	var F: Dictionary = FRAMES[frame]
	var R: Dictionary = FRAMES.dh
	var d := float(F.wheelbase) / float(R.wheelbase) - 1.0   # wheelbase, fraction longer
	var h := float(R.head) - float(F.head)                   # degrees slacker
	var c := float(F.chainstay) - float(R.chainstay)         # m longer
	var bb := float(F.bb_drop) - float(R.bb_drop)            # m lower
	var pr := float(F.progression) - float(R.progression)
	var aq := float(F.anti_squat) - float(R.anti_squat)
	var st := float(F.stiff)
	var kg := bike_kg(frame, b)
	var kg_ref := bike_kg("dh", default_build())
	var k := (RIDER_KG + kg) / (RIDER_KG + kg_ref)   # the whole system's mass vs. the reference
	var kb := kg / kg_ref                            # the bike alone
	var cl: Dictionary = CLASSES[F["class"]]
	var m := {}
	var mul := func(key: String, f: float) -> void: m[key] = float(m.get(key, 1.0)) * f
	# class: the gear-limited top speed
	mul.call("topSpeed", cl.top); mul.call("pedalTop", cl.top)
	for key in cl.extra: mul.call(key, cl.extra[key])
	# weight: forces stay, mass changes -> the same push / brake / drag moves a heavier bike less
	mul.call("airDrag", 1.0 / k)
	for key in ["pedalLaunch", "pedalPower", "sprintKick", "brakeForce"]: mul.call(key, 1.0 / k)
	mul.call("popPower", 1.0 / sqrt(kb))
	mul.call("gripBumps", 1.0 / kb)       # a heavy bike isn't knocked about as much
	mul.call("flickSpeed", 1.0 / sqrt(kb))
	# wheelbase
	mul.call("leanRate", 1.0 - 3.0 * d)
	mul.call("flickKick", 1.0 - 3.0 * d)
	mul.call("whipSnap", 1.0 - 2.0 * d)
	mul.call("counter", 1.0 - 2.0 * d)
	mul.call("gripBumps", 1.0 - 2.5 * d)
	mul.call("oversteer", 1.0 - 2.0 * d)
	mul.call("slipRecover", 1.0 + 1.5 * d)
	# head angle
	mul.call("noseDive", 1.0 + 0.06 * h)
	mul.call("steerRate", 1.0 - 0.04 * h)
	mul.call("slowSteer", 1.0 - 0.04 * h)
	mul.call("counter", 1.0 - 0.04 * h)
	# chainstay
	# (the balance manual: a short back end lifts easily, tips over sooner, pops a sprint wheelie more easily)
	mul.call("manLift", 1.0 - 3.0 * c)
	mul.call("manGravity", 1.0 - 3.0 * c)
	mul.call("manSprintLift", 1.0 - 3.0 * c)
	mul.call("whipSnap", 1.0 - 3.0 * c)
	mul.call("gripPower", 1.0 - 4.0 * c)
	mul.call("popPower", 1.0 - 2.0 * c)
	# bottom bracket height
	mul.call("grip", 1.0 + 1.0 * bb)
	mul.call("carveGrip", 1.0 + 3.0 * bb)
	mul.call("leanRate", 1.0 - 3.0 * bb)
	# suspension design
	mul.call("shockProg", maxf(0.2, 1.0 + 1.2 * pr))   # the linkage's ramp-up, into the rear spring's curve
	mul.call("slamJolt", 1.0 + 0.5 * pr)
	mul.call("popPower", 1.0 + 0.4 * pr)
	mul.call("pumpLegs", 1.0 + 0.4 * pr)
	mul.call("antiSquat", clampf(1.0 + aq / 0.9, 0.5, 1.5))   # (0.4 + the frame's figure: this frame squats / stands up under power)
	mul.call("pedalPower", 1.0 + 0.3 * aq)
	mul.call("sprintPower", 1.0 + 0.3 * aq)
	mul.call("steerEase", st)
	mul.call("gripSquirm", 2.0 - st)
	for key in m: m[key] = clampf(m[key], 0.6, 1.5)
	return m

## how well a suspension setup takes a big landing, 1 = the stock one: more high-speed compression, more ramp-up at
## the end and less sag all keep it off its stops (measured on the playground's drop: each of those alone turns a rim
## strike into none)
static func _land_k(su: Dictionary) -> float:
	var k := 0.0
	for e in ["f", "r"]:
		var u: Dictionary = su[e]
		k += 0.5 * (1.0 + (float(u.hs) - 0.495) * 0.9 + (float(u.prog) - (0.62 if u.air else 0.07)) * 0.25 + (0.29 - float(u.sag)) * 1.5 + (float(u.zc) - 0.35) * 0.4)
	return k

## the garage's bars, 0..1 (the build on `frame`)
static func stats(b: Dictionary, frame := "dh") -> Dictionary:
	var m := ride_mods(b)
	var r: Dictionary = m.ride
	var fm := frame_mods(frame, b)
	var g := func(key: String) -> float: return float(fm.get(key, 1.0))
	var cogs: Array = m.cogs
	var top: float = m.ring_k * 16.0 / float(cogs[0])            # top-gear speed vs. stock 16T
	var low: float = m.ring_k * 16.0 / float(cogs[cogs.size() - 1])
	return {
		"Top speed": clampf(0.35 + (top - 1.0) * 0.5 - (r.rollRes - 1.0) * 0.4 + (g.call("topSpeed") - 1.0) * 3.0
			+ (1.0 / g.call("airDrag") - 1.0) * 1.5, 0, 1),
		"Acceleration": clampf(0.6 + (1.0 - low) * 0.6 + (r.pedalLaunch - 1.0) * 2.0 - (r.rollRes - 1.0) * 0.3
			+ (g.call("pedalPower") - 1.0) * 2.0, 0, 1),
		"Handling": clampf(0.55 + (r.steerRate - 1.0) * 2.5 + (r.grip - 1.0) * 0.8 + (g.call("leanRate") - 1.0) * 2.0
			+ (g.call("steerRate") - 1.0) * 1.5, 0, 1),
		"Grip": clampf(0.55 + (r.grip - 1.0) * 1.8 + (g.call("grip") - 1.0) * 1.8 + (g.call("carveGrip") - 1.0) * 0.5, 0, 1),
		"Landing": clampf(0.3 + (r.travel - 0.8) * 1.2 + (_land_k(m.susp) - 1.0) * 0.6 + (g.call("slamJolt") - 1.0) * 1.5, 0, 1),
		"Pop": clampf(0.5 + (g.call("popPower") - 1.0) * 2.5 + (g.call("manLift") - 1.0) * 1.0 + (r.travel - 1.0) * -0.4, 0, 1),
	}

## speed class in stars, 1 (slow) .. 5 (fast): the top-speed bar of this build on this frame
static func stars(b: Dictionary, frame := "dh") -> int:
	return clampi(roundi(stats(b, frame)["Top speed"] * 5.0 + 1.2), 1, 5)

## "★★★☆☆" for a star count
static func star_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(5 - n)

## Part stars (tyres, rims, forks): the same stats as the frames' (stats()), measured with this part
## fitted on the stock build. Each kind is scored on the bars it really changes, then ranked against
## its own models so a kind uses the whole 1..5 range (the best tyre is 5, the weakest 1).
const PART_FOCUS := {
	"tyre": ["Grip", "Handling", "Top speed"],
	"rim":  ["Top speed", "Acceleration", "Handling"],
	"fork": ["Landing", "Grip", "Handling"],
}
static var _part_stars := {}

static func _part_models(kind: String) -> Dictionary:
	return {"tyre": TYRE_MODELS, "rim": RIM_MODELS, "fork": FORK_MODELS}.get(kind, {})

static func _part_score(kind: String, key: String) -> float:
	var b := default_build()
	match kind:
		"tyre": apply_tyre_model(b, key)
		"rim": apply_rim_model(b, key)
		"fork": apply_fork_model(b, key)
	var s := stats(b, "dh")
	var t := 0.0
	for k in PART_FOCUS[kind]: t += float(s[k])
	return t / float(PART_FOCUS[kind].size())

## 1..5 stars for a tyre / rim / fork model key (0 = unknown or "custom")
static func part_stars(kind: String, key: String) -> int:
	if not PART_FOCUS.has(kind): return 0
	if not _part_stars.has(kind):
		var scores := {}
		var lo := INF
		var hi := -INF
		for k in _part_models(kind):
			if not _part_models(kind)[k].has("brand"): continue
			var sc := _part_score(kind, k)
			scores[k] = sc; lo = minf(lo, sc); hi = maxf(hi, sc)
		var out := {}
		for k in scores:
			out[k] = 3 if hi - lo < 0.001 else clampi(1 + roundi((scores[k] - lo) / (hi - lo) * 4.0), 1, 5)
		_part_stars[kind] = out
	return int(_part_stars[kind].get(key, 0))
