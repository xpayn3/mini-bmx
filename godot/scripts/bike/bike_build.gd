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
	"metallic": {"label": "Metallic", "metallic": 0.55, "roughness": 0.34, "clearcoat": 1.0, "cc_rough": 0.03, "sparkle": 0.22, "flip": 0.0},
	"pearl":    {"label": "Pearl shift", "metallic": 0.45, "roughness": 0.3, "clearcoat": 1.0, "cc_rough": 0.03, "sparkle": 0.12, "flip": 0.85},
	"candy":    {"label": "Candy",    "metallic": 0.85, "roughness": 0.18, "clearcoat": 1.0, "cc_rough": 0.02, "sparkle": 0.3,  "flip": 0.0, "deep": 0.55},
	"satin":    {"label": "Satin",    "metallic": 0.2,  "roughness": 0.55, "clearcoat": 0.3, "cc_rough": 0.4,  "sparkle": 0.05, "flip": 0.0},
	"matte":    {"label": "Matte",    "metallic": 0.0,  "roughness": 0.88, "clearcoat": 0.0, "cc_rough": 1.0,  "sparkle": 0.0,  "flip": 0.0},
	"chrome":   {"label": "Chrome",   "metallic": 1.0,  "roughness": 0.06, "clearcoat": 0.0, "cc_rough": 0.0,  "sparkle": 0.0,  "flip": 0.0},
	"anodized": {"label": "Anodized", "metallic": 0.9,  "roughness": 0.3,  "clearcoat": 0.0, "cc_rough": 0.0,  "sparkle": 0.06, "flip": 0.0},
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
	"downtube":  {"label": "Down tube",  "tmpl": {"mesh": "frame", "surface": "paint", "from": [0.168, 0.486], "to": [0.404, 0.809], "length": 0.2, "height": 0.0627}},
	"toptube":   {"label": "Top tube",   "tmpl": {"mesh": "frame", "surface": "paint", "from": [0.05, 0.74], "to": [0.30, 0.86], "length": 0.19, "height": 0.032}},
	"chainstay": {"label": "Chainstays", "tmpl": {"mesh": "swing", "surface": "paint", "from": [-0.44, -0.025], "to": [-0.25, 0.03], "length": 0.09, "height": 0.0282, "z": 0.075, "depth": 0.06}},
	"forklegs":  {"label": "Fork legs",  "tmpl": {"mesh": "fork_lower", "surface": "black", "from": [-0.03, 0.07], "to": [-0.165, 0.335], "upright": true, "length": 0.078, "height": 0.15, "z": 0.085, "depth": 0.05}},   # Fox 40 size: ~15 cm, wrapped round the leg
}

## the logo library. Images that come with the game, plus text logos (our own wordmarks)
const LOGOS := {
	"none":    {"label": "None"},
	"cinelli": {"label": "Cinelli", "image": "res://assets/decals/cinelli.png"},
	"fox":     {"label": "Fox", "image": "res://assets/decals/fox_right.png", "imageMinus": "res://assets/decals/fox_left.png"},
	"glory":   {"label": "GLORY", "text": "GLORY"},
	"minibmx": {"label": "MINI BMX", "text": "MINI BMX"},
	"gravity": {"label": "GRAVITY", "text": "GRAVITY"},
	"text":    {"label": "Custom text…"},
}

const WHEEL_SIZES := {"26": 559, "27.5": 584, "29": 622}

## tyre models (popular DH tyres, our own approximation of each tread). Picking one sets the tread,
## casing, width and the sidewall lettering; touching any of those turns the model back to "custom".
const TYRE_MODELS := {
	"custom":          {"label": "Custom"},
	"minion_dhf":      {"label": "Maxxis Minion DHF",     "brand": "MAXXIS",      "tread": "knobby", "pattern": "knobby",  "casing": "round",  "tyre_w": 2.5},
	"minion_dhr":      {"label": "Maxxis Minion DHR II",  "brand": "MAXXIS",      "tread": "knobby", "pattern": "paddle",  "casing": "square", "tyre_w": 2.4},
	"assegai":         {"label": "Maxxis Assegai",        "brand": "MAXXIS",      "tread": "knobby", "pattern": "dense",   "casing": "square", "tyre_w": 2.5},
	"shorty":          {"label": "Maxxis Shorty (mud)",   "brand": "MAXXIS",      "tread": "knobby", "pattern": "spike",   "casing": "round",  "tyre_w": 2.4},
	"minion_ss":       {"label": "Maxxis Minion SS",      "brand": "MAXXIS",      "tread": "semi",   "pattern": "semi",    "casing": "square", "tyre_w": 2.3},
	"magic_mary":      {"label": "Schwalbe Magic Mary",   "brand": "SCHWALBE",    "tread": "knobby", "pattern": "stagger", "casing": "round",  "tyre_w": 2.4},
	"big_betty":       {"label": "Schwalbe Big Betty",    "brand": "SCHWALBE",    "tread": "knobby", "pattern": "block",   "casing": "round",  "tyre_w": 2.4},
	"dh22":            {"label": "Michelin DH22",         "brand": "MICHELIN",    "tread": "knobby", "pattern": "dense",   "casing": "square", "tyre_w": 2.4},
	"dh_slick":        {"label": "Michelin DH Slick",     "brand": "MICHELIN",    "tread": "slick",  "pattern": "slick",   "casing": "round",  "tyre_w": 2.4},
	"kryptotal":       {"label": "Continental Kryptotal", "brand": "CONTINENTAL", "tread": "knobby", "pattern": "block",   "casing": "square", "tyre_w": 2.4},
	"butcher":         {"label": "Specialized Butcher",   "brand": "SPECIALIZED", "tread": "knobby", "pattern": "paddle",  "casing": "round",  "tyre_w": 2.6},
}
const PATTERN_NAMES := [["knobby", "Classic knobs"], ["paddle", "Paddle centre"], ["dense", "Dense 3-across"],
	["stagger", "Open stagger"], ["block", "Square blocks"], ["spike", "Mud spikes"], ["semi", "Semi-slick"], ["slick", "Slick"]]

## rim models (popular DH rims: profile shape, material, depth / outer width in mm, rim lettering)
const RIM_MODELS := {
	"custom":       {"label": "Custom"},
	"fr560":        {"label": "DT Swiss FR 560",       "brand": "DT SWISS",      "profile": "hooked",   "material": "alloy",  "depth": 24, "width": 36},
	"deemax":       {"label": "Mavic Deemax",          "brand": "MAVIC",         "profile": "vee",      "material": "alloy",  "depth": 28, "width": 35},
	"arc30":        {"label": "Race Face ARC 30",      "brand": "RACE FACE",     "profile": "hooked",   "material": "alloy",  "depth": 21, "width": 35},
	"oozy":         {"label": "Spank Oozy 350",        "brand": "SPANK",         "profile": "box",      "material": "alloy",  "depth": 26, "width": 35},
	"flow":         {"label": "Stan's Flow MK4",       "brand": "STAN'S NOTUBES","profile": "hookless", "material": "alloy",  "depth": 21, "width": 35},
	"lg1":          {"label": "e*thirteen LG1",        "brand": "E*THIRTEEN",    "profile": "hooked",   "material": "alloy",  "depth": 24, "width": 35},
	"fuse":         {"label": "We Are One Fuse",       "brand": "WE ARE ONE",    "profile": "round",    "material": "carbon", "depth": 25, "width": 36},
	"reserve30":    {"label": "Reserve 30 HD",         "brand": "RESERVE",       "profile": "hookless", "material": "carbon", "depth": 28, "width": 37},
	"synthesis":    {"label": "Crankbrothers Synthesis","brand": "CRANKBROTHERS","profile": "vee",      "material": "carbon", "depth": 26, "width": 36},
	"moto":         {"label": "Zipp 3Zero Moto",       "brand": "ZIPP",          "profile": "round",    "material": "carbon", "depth": 20, "width": 36},
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
	"fox40f":   {"brand": "FOX",        "label": "40 Factory",       "travel": 200, "spring": "Air",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c8a24a", "color2": "ffffff", "finish": "anodized"}, "coat": "Kashima"},
	"fox40p":   {"brand": "FOX",        "label": "40 Performance",   "travel": 200, "spring": "Air",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"}, "stanchions": {"color": "202024", "color2": "ffffff", "finish": "anodized"}, "coat": "Black"},
	"boxxer_u": {"brand": "ROCKSHOX",   "label": "BoXXer Ultimate",  "travel": 200, "spring": "Air",
		"lowers": {"color": "c4161c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c9cdd2", "color2": "ffffff", "finish": "chrome"}, "coat": "Silver"},
	"boxxer_s": {"brand": "ROCKSHOX",   "label": "BoXXer Select",    "travel": 190, "spring": "Air",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "matte"}, "stanchions": {"color": "202024", "color2": "ffffff", "finish": "anodized"}, "coat": "Black"},
	"dh38":     {"brand": "ÖHLINS",     "label": "DH38 m.1",         "travel": 200, "spring": "Coil",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "d9b347", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
	"bomber58": {"brand": "MARZOCCHI",  "label": "Bomber 58",        "travel": 200, "spring": "Coil",
		"lowers": {"color": "d12b1f", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "202024", "color2": "ffffff", "finish": "anodized"}, "coat": "Black"},
	"onyx":     {"brand": "DVO",        "label": "Onyx DH",          "travel": 200, "spring": "Coil",
		"lowers": {"color": "5fbf3f", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "202024", "color2": "ffffff", "finish": "anodized"}, "coat": "Black"},
	"dorado":   {"brand": "MANITOU",    "label": "Dorado Pro",       "travel": 200, "spring": "Air",
		"lowers": {"color": "e9eaec", "color2": "ffffff", "finish": "gloss"}, "stanchions": {"color": "c9cdd2", "color2": "ffffff", "finish": "chrome"}, "coat": "Silver"},
	"era":      {"brand": "EXT",        "label": "Era V2.1",         "travel": 180, "spring": "Coil",
		"lowers": {"color": "1a1a1c", "color2": "ffffff", "finish": "satin"}, "stanchions": {"color": "e0b545", "color2": "ffffff", "finish": "anodized"}, "coat": "Gold"},
}

static func apply_fork_model(b: Dictionary, key: String) -> void:
	b.suspension.fork_model = key
	var m: Dictionary = FORK_MODELS.get(key, {})
	if not m.has("brand"): return
	b.suspension.fork_travel = m.travel
	b.paint.fork = (m.lowers as Dictionary).duplicate()
	b.paint.stanchions = (m.stanchions as Dictionary).duplicate()

const CASSETTES := {
	"dh7":   {"label": "7-speed DH 11–24", "cogs": [11, 12, 14, 16, 18, 21, 24]},
	"dh7w":  {"label": "7-speed wide 11–28", "cogs": [11, 13, 15, 17, 20, 24, 28]},
	"mtb9":  {"label": "9-speed 11–32", "cogs": [11, 12, 14, 16, 18, 21, 24, 28, 32]},
	"mtb11": {"label": "11-speed 10–42", "cogs": [10, 12, 14, 16, 18, 21, 24, 28, 32, 36, 42]},
	"single":{"label": "Single speed 16T", "cogs": [16]},
}

static func default_build() -> Dictionary:
	return {
		"name": "GLORY DH",
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
			"downtube": {"logo": "cinelli", "text": "", "fill": "f4f4f0", "stroke": "141418"},
			"toptube": {"logo": "glory", "text": "", "fill": "f4f4f0", "stroke": "141418"},
			"chainstay": {"logo": "cinelli", "text": "", "fill": "f4f4f0", "stroke": "141418"},
			"forklegs": {"logo": "fox", "text": "", "fill": "f4f4f0", "stroke": "141418"},
			"tyres": {"logo": "text", "text": "MAXXIS", "fill": "f4f4f0", "stroke": "141418"},
			"rims": {"logo": "text", "text": "GRAVITY", "fill": "f4f4f0", "stroke": "141418", "count": 2},
		},
		"wheels": {
			"front": "29", "rear": "27.5", "tyre_w": 2.5, "tread": "knobby", "sidewall": "black",
			"tyre_model": "custom", "pattern": "knobby", "casing": "round",
			"rim_model": "custom", "rim_profile": "hooked", "rim_material": "alloy",
			"rim_color": "1a1a1c", "rim_finish": "matte", "rim_depth": 28, "rim_width": 30,
			"spokes": 32, "lacing": 3, "gauge": 1, "spoke_color": "b8bcc0", "nipple_color": "e8432e", "hub_color": "1a1a1c",
		},
		"bars": {"width": 780, "rise": 30, "material": "alloy"},
		"suspension": {"fork_travel": 200, "shock_travel": 200, "fork_spring": 1, "shock_spring": 1, "rebound": 1},
		"drive": {"ring": 34, "cassette": "dh7"},
	}

static func load_build() -> Dictionary:
	var b := default_build()
	if FileAccess.file_exists(PATH):
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if j is Dictionary:
			_merge(b, j)
	# tests: BMX_BUILD="wheels.rim_model=deemax;bars.width=820;..." (models applied through their presets)
	for kv in OS.get_environment("BMX_BUILD").split(";", false):
		var p := kv.split("=")
		if p.size() != 2: continue
		var path := p[0].split(".")
		var d = b
		for i in path.size() - 1:
			d = d.get(path[i]) if d is Dictionary else null
		var key: String = path[path.size() - 1]
		if not (d is Dictionary) or not d.has(key) or d[key] is Dictionary: continue
		if key == "tyre_model": apply_tyre_model(b, p[1]); continue
		if key == "rim_model": apply_rim_model(b, p[1]); continue
		d[key] = float(p[1]) if typeof(d[key]) in [TYPE_INT, TYPE_FLOAT] else p[1]
	return b

static func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		elif dst.has(k) and typeof(dst[k]) in [TYPE_FLOAT, TYPE_INT] and typeof(src[k]) in [TYPE_FLOAT, TYPE_INT]:
			dst[k] = src[k]
		elif dst.has(k) and typeof(dst[k]) == typeof(src[k]):
			dst[k] = src[k]

static func save_build(b: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(b, "\t"))

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

static func paint_material(p: Dictionary) -> ShaderMaterial:
	var key := "%s|%s|%s" % [p.color, p.color2, p.finish]
	if _mat_cache.has(key): return _mat_cache[key]
	var F: Dictionary = FINISHES.get(p.finish, FINISHES.gloss)
	var col := Color(p.color)
	if F.has("deep"): col = col.darkened(0.15)
	var m := BikeFX.car_paint(null, {"color": col, "metallic": F.metallic, "roughness": F.roughness,
		"sparkle": F.sparkle, "clearcoat_roughness": F.cc_rough})
	m.set_shader_parameter("clearcoat", F.clearcoat)
	m.set_shader_parameter("color2", Color(p.color2))
	m.set_shader_parameter("flip", F.flip)
	m.set_shader_parameter("deep", F.get("deep", 0.0))
	_mat_cache[key] = m
	return m

## paint every part of a rig's bike model
static func apply_paint(model: Node3D, b: Dictionary) -> void:
	for part in PARTS:
		var mat := paint_material(b.paint[part])
		for target in PARTS[part][1]:
			var mi := model.find_child(target[0], true, false) as MeshInstance3D
			if mi == null or mi.mesh == null: continue
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
		if e.get("upright", false) and not e.has("image"):
			continue   # fork legs take artwork only
		e.fill = Color(L.fill); e.stroke = Color(L.stroke, 0.85)
		labels.append(e)
	var cfg := {"labels": labels}
	var tl: Dictionary = b.logos.tyres
	if tl.logo != "none" and tl.text.strip_edges() != "":
		cfg.tyres = {"text": tl.text, "meshes": [["wheel_front", "rubber"], ["wheel_rear", "rubber"]]}
	var rl: Dictionary = b.logos.rims
	var rim := {"fill": Color(rl.fill), "depth": float(b.wheels.rim_depth) / 1000.0, "count": int(rl.get("count", 2)),
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
	if rear: spec.cogs = CASSETTES[b.drive.cassette].cogs
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
	var spring_k: float = [0.88, 1.0, 1.14][int(s.fork_spring)] * 0.5 + [0.88, 1.0, 1.14][int(s.shock_spring)] * 0.5
	var reb: float = [1.25, 1.0, 0.8][int(s.rebound)]            # slow rebound = more damping
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
		"tyreHz": spring_k, "tyreDamp": reb,
		"grip": tread_grip * width_grip, "rollRes": tread_roll * size_roll * (1.0 + (float(w.tyre_w) - 2.5) * 0.2),
		# wider bars: slower, steadier steering (780 mm = 1)
		"pedalLaunch": 1.0 / spoke_w, "steerRate": 1.0 / sqrt(spoke_w) * (1.0 - (rf - 0.374) * 1.2) * (1.0 - (float(b.bars.width) - 780.0) * 0.0015),
	}
	var cogs: Array = CASSETTES[b.drive.cassette].cogs
	return {"ride": ride, "wheel_f": rf, "wheel_r": rr, "cogs": cogs, "ring_k": float(b.drive.ring) / 34.0,
		"fork_travel": float(s.fork_travel) / 1000.0, "shock_travel": float(s.shock_travel) / 1000.0,
		"land": 0.85 + 0.15 * trav}

## the garage's bars, 0..1
static func stats(b: Dictionary) -> Dictionary:
	var m := ride_mods(b)
	var r: Dictionary = m.ride
	var cogs: Array = m.cogs
	var top: float = m.ring_k * 16.0 / float(cogs[0])            # top-gear speed vs. stock 16T
	var low: float = m.ring_k * 16.0 / float(cogs[cogs.size() - 1])
	return {
		"Top speed": clampf(0.35 + (top - 1.0) * 0.5 - (r.rollRes - 1.0) * 0.4, 0, 1),
		"Acceleration": clampf(0.6 + (1.0 - low) * 0.6 + (r.pedalLaunch - 1.0) * 2.0 - (r.rollRes - 1.0) * 0.3, 0, 1),
		"Handling": clampf(0.55 + (r.steerRate - 1.0) * 2.5 + (r.grip - 1.0) * 0.8, 0, 1),
		"Grip": clampf(0.55 + (r.grip - 1.0) * 1.8, 0, 1),
		"Landing": clampf(0.3 + (r.travel - 0.8) * 1.2 + (r.tyreDamp - 1.0) * 0.4, 0, 1),
	}
