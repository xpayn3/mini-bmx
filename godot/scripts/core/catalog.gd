class_name Catalog
## Everything the SHOP sells (garage mode "shop", garage/store_page.gd), per category, worst -> best.
## A product: {key "kind:id", kind, id, brand, name, tier 1..5, price, spec, look (the 3D model it shows as),
## thumb / make / view (its card picture)}. Kinds that already had several branded models (frames, complete
## bikes, forks, shocks, rims, tyres, bars, cassettes, lights) sell those; the small parts that only had 2-3 looks
## (rotors, calipers, levers, stems, saddles, seat posts, pedals) are VARIANTS here: several brands and tiers on
## the same looks, told apart by name, price and what they do on the trail (PERF: a few % on a ride key per tier
## step, through BikeBuild.ride_mods -> Catalog.ride_perf, read from build.sku[kind]).
## Prices are today's market (Shop): variants carry their own, the rest come from Shop.price.

const TIER_NAMES := ["", "BUDGET", "SPORT", "EXPERT", "PRO", "FACTORY"]

## store tabs: [id, label, [kinds shown, in that order]]
const TABS := [
	["bikes", "BIKES", ["edition"]],
	["frames", "FRAMES", ["frame"]],
	["susp", "SUSPENSION", ["fork", "shock"]],
	["wheels", "WHEELS", ["rim", "tyre"]],
	["cockpit", "COCKPIT", ["bar", "stem", "levers"]],
	["brakes", "BRAKES", ["rotor", "caliper"]],
	["drive", "DRIVE", ["cassette", "pedal"]],
	["seat", "SEAT", ["saddle", "post"]],
	["lights", "LIGHTS", ["light"]],
]
const KIND_LABEL := {"edition": "Complete bike", "frame": "Frameset", "fork": "Fork", "shock": "Rear shock",
	"rim": "Wheelset", "tyre": "Tyres (pair)", "bar": "Handlebar", "stem": "Stem", "levers": "Brake levers",
	"rotor": "Brake rotors (pair)", "caliper": "Brake calipers", "cassette": "Cassette", "pedal": "Pedals",
	"saddle": "Saddle", "post": "Seat post", "light": "Light set"}

## variants: [id, brand, name, tier, price, look, spec]
const VARIANTS := {
	"rotor": [
		["r_steel", "STOPLINE", "Steel 180", 1, 60, "stock", "180 mm  ·  one-piece steel"],
		["r_hw2", "HALTWORKS", "HW Two-Piece 200", 2, 140, "fuzz", "200 mm  ·  alloy carrier"],
		["r_cool", "NORDLUND", "NL Cooler 203", 3, 210, "fuzz", "203 mm  ·  cooling fins"],
		["r_float", "KOMODO", "K-Floating 220", 4, 290, "tues", "220 mm  ·  floating"],
		["r_race", "YONDER", "Tusk Race 223", 5, 380, "tues", "223 mm  ·  floating, ice-tech"],
	],
	"caliper": [
		["c_two", "STOPLINE", "Duo 2-piston", 1, 70, "stock", "2-piston  ·  organic pads"],
		["c_hw4", "HALTWORKS", "HW4", 2, 160, "fuzz", "4-piston  ·  semi-metal pads"],
		["c_code", "NORDLUND", "Coder RSC", 3, 240, "fuzz", "4-piston  ·  sintered pads"],
		["c_dom", "KOMODO", "Dominator", 4, 330, "tues", "4-piston  ·  finned pads"],
		["c_race", "YONDER", "Tusk Race", 5, 420, "tues", "4-piston  ·  race compound"],
	],
	"levers": [
		["l_basic", "STOPLINE", "Basic", 1, 50, "stock", "Fixed reach"],
		["l_reach", "HALTWORKS", "Reach", 2, 110, "fuzz", "Tool-free reach"],
		["l_fizz", "NEXO", "Fizz Pro", 3, 180, "fuzz", "Reach + bite point"],
		["l_dom", "KOMODO", "Dominator", 4, 240, "tues", "Bite point  ·  bearing pivot"],
		["l_carbon", "YONDER", "Tusk Carbon", 5, 320, "tues", "Carbon blade  ·  bearing pivot"],
	],
	"stem": [
		["s_basic", "RUNOUT", "DM Basic", 1, 45, "stock", "Direct mount  ·  50 mm"],
		["s_direct", "SMACK", "Direct 50", 2, 95, "fuzz", "Direct mount  ·  forged"],
		["s_summit", "RAW EDGE", "Summit DM", 3, 140, "fuzz", "Direct mount  ·  CNC"],
		["s_pro", "UPSHOT", "DM Pro", 4, 190, "tues", "Direct mount  ·  CNC, ti bolts"],
		["s_a9", "ARCUS", "A9 DM", 5, 260, "tues", "Direct mount  ·  stiffest"],
	],
	"saddle": [
		["sa_comfort", "RUNOUT", "Comfort", 1, 30, "stock", "Steel rails"],
		["sa_flat", "PERCH", "DH Flat", 2, 60, "fuzz", "Cro-mo rails  ·  kevlar corners"],
		["sa_tough", "IDOL", "Tough", 3, 95, "fuzz", "Cro-mo rails  ·  armoured"],
		["sa_ti", "VERDELLI", "Race Ti", 4, 150, "tues", "Titanium rails"],
		["sa_carbon", "PERCH", "Carbon SL", 5, 230, "tues", "Carbon rails  ·  featherweight"],
	],
	"post": [
		["p_rigid", "RUNOUT", "Rigid alloy", 1, 40, "stock", "Slammed for DH"],
		["p_drop", "UPSHOT", "Dropper 150", 3, 380, "dropper", "150 mm drop"],
		["p_transfer", "KOMODO", "Transfer Factory", 5, 560, "dropper", "175 mm drop  ·  Kashima-style"],
	],
	"pedal": [
		["pe_nylon", "RUNOUT", "Nylon flats", 1, 30, "dh", "Composite  ·  moulded pins"],
		["pe_alu", "SMACK", "Grip Alu", 2, 70, "fuzz", "Alloy  ·  10 pins a side"],
		["pe_deck", "IRONCLAD", "Deck Pro", 3, 120, "fuzz", "Alloy  ·  concave, 12 pins"],
		["pe_mag", "GRIPDECK", "Thin Mag", 4, 170, "tues", "Magnesium  ·  thin"],
		["pe_ti", "IDOL", "Ti Spindle", 5, 240, "tues", "Titanium axle  ·  thin, grippy"],
	],
}
## where each variant kind's look goes in a build, and its picture spot
const LOOK_PATH := {"rotor": "suspension.rotor", "caliper": "suspension.rear_caliper", "levers": "bars.levers",
	"stem": "bars.stem", "saddle": "seat.model", "post": "seat.post", "pedal": "drive.pedals"}
## what a tier step does on the trail: [ride key, per step from tier 3] (multipliers on the Tune values)
const PERF := {
	"rotor": ["brakeGrip", 0.02], "caliper": ["brakeGrip", 0.015], "levers": ["brakeGrip", 0.01],
	"stem": ["steerRate", 0.015], "pedal": ["popPower", 0.015], "post": ["popPower", 0.01],
}
## what a new player owns (the stock bike's small parts)
const STARTER := ["rotor:r_steel", "caliper:c_two", "levers:l_basic", "stem:s_basic", "saddle:sa_comfort",
	"post:p_rigid", "pedal:pe_nylon"]

## the multipliers the build's bought small parts give (BikeBuild.ride_mods multiplies them into its ride)
static func ride_perf(b: Dictionary) -> Dictionary:
	var out := {}
	var sku: Dictionary = b.get("sku", {})
	for kind in sku:
		if not PERF.has(kind): continue
		var v := variant(kind, str(sku[kind]))
		if v.is_empty(): continue
		var k: String = PERF[kind][0]
		out[k] = float(out.get(k, 1.0)) * (1.0 + (int(v[3]) - 3) * float(PERF[kind][1]))
	return out

static func variant(kind: String, id: String) -> Array:
	for v in VARIANTS.get(kind, []):
		if v[0] == id: return v
	return []

## fits a product to a build (the look it shows as + build.sku for what it does)
static func apply(b: Dictionary, p: Dictionary) -> void:
	var kind: String = p.kind
	var id: String = p.id
	match kind:
		"fork": BikeBuild.apply_fork_model(b, id)
		"rim": BikeBuild.apply_rim_model(b, id)
		"tyre": BikeBuild.apply_tyre_model(b, id)
		"shock": b.suspension.shock_model = id
		"cassette": b.drive.cassette = id
		"light":
			if not b.has("lights"): b.lights = {}
			b.lights.model = id
		"bar":
			var m: Dictionary = Handlebar.MODELS[id]
			b.bars.model = id; b.bars.width = m.width; b.bars.rise = m.rise; b.bars.material = m.material
		_:
			if LOOK_PATH.has(kind):
				var path: PackedStringArray = LOOK_PATH[kind].split(".")
				if not b.has(path[0]): b[path[0]] = {}
				b[path[0]][path[1]] = p.look
				if kind == "post" and p.look == "dropper": b.seat.post_h = 0.1
	if not b.has("sku"): b.sku = {}
	b.sku[kind] = id

## the products of a store tab, worst -> best within each kind. g = the garage (its card picture helpers)
static func items(tab: String, g) -> Array:
	var kinds: Array = []
	for t in TABS:
		if t[0] == tab: kinds = t[2]
	var out := []
	for kind in kinds:
		var list := _kind_items(kind, g)
		list.sort_custom(func(a, b): return a.tier < b.tier or (a.tier == b.tier and a.price < b.price))
		out.append_array(list)
	return out

static func _p(kind: String, id: String, brand: String, name: String, tier: int, price: int, spec: String) -> Dictionary:
	return {"key": "%s:%s" % [kind, id], "kind": kind, "id": id, "brand": brand, "name": name, "tier": clampi(tier, 1, 5),
		"price": price, "spec": spec, "look": id}

static func _rank(n: int, i: int) -> int:   # i-th of n (cheapest first) -> tier 1..5
	return 1 if n <= 1 else 1 + roundi(float(i) / float(n - 1) * 4.0)

static func _kind_items(kind: String, g) -> Array:
	var out := []
	var P := Garage.PRODUCT
	match kind:
		"edition":
			for e in BikeBuild.EDITIONS:
				var ed: Dictionary = BikeBuild.EDITIONS[e]
				var eb := BikeBuild.edition_build(e)
				var style := String(BikeBuild.STYLES[ed.get("style", "allround")].label).to_upper()
				var it := _p(kind, e, "%s  ·  %s" % [style, String(GameState.BIKES[ed.frame].label).to_upper()], ed.label,
					BikeBuild.stars(eb, ed.frame), Shop.price("edition", e), g._bike_line(ed.frame, eb))
				it.frame = ed.frame; it.build = eb
				it.thumb = PartThumbs.build_key(ed.frame, eb); it.make = PartThumbs.make_bike_build.bind(ed.frame, eb)
				it.view = Vector3(0.45, 0.2, 1.0)
				out.append(it)
		"frame":
			for id in GameState.BIKES:
				if not GameState.BIKES[id].get("garage", false): continue
				var fb := BikeBuild.default_build()   # the frameset in its factory colours, stock parts
				var saved := BikeBuild.load_build(id)
				fb.paint = saved.paint
				var it := _p(kind, id, "FRAMESET  ·  " + String(BikeBuild.CLASSES[BikeBuild.FRAMES[id].class].label).to_upper(),
					String(GameState.BIKES[id].label), BikeBuild.stars(fb, id), Shop.price("frame", id), g._bike_line(id, fb))
				it.frame = id; it.build = fb
				it.thumb = "alone2|frame|%s|%s" % [id, JSON.stringify(fb.paint).hash()]; it.make = PartThumbs.make_part_alone.bind("frame", id)
				it.view = Vector3(0.45, 0.2, 1.0)
				out.append(it)
		"fork":
			for k in BikeBuild.FORK_MODELS:
				var m: Dictionary = BikeBuild.FORK_MODELS[k]
				var it := _p(kind, k, m.brand, m.label, BikeBuild.part_stars("fork", k), Shop.price("fork", k),
					"%d mm  ·  %s  ·  %s stanchions" % [m.travel, m.spring, m.coat])
				it.thumb = "fork|%s|%s" % [k, P]
				it.make = PartThumbs.make_fork.bind(m.lowers, BikeBuild.stanchion_paint(m.stanchions), Garage._product_paint("crown"), str(m.get("glb", "")))
				it.view = Vector3(0.35, 0.22, 1.0)
				out.append(it)
		"shock":
			var ids: Array = SuspSetup.SHOCK_MODELS.keys()
			ids.sort_custom(func(a, b): return Shop.price("shock", a) < Shop.price("shock", b))
			for i in ids.size():
				var k: String = ids[i]
				var m: Dictionary = SuspSetup.SHOCK_MODELS[k]
				var it := _p(kind, k, m.brand, m.label, _rank(ids.size(), i), Shop.price("shock", k),
					"%s  ·  adjust %s" % [String(m.spring).capitalize(), " / ".join((m.adj as Array).map(func(a): return String(a).to_upper()))])
				it.thumb = "alone2|shock|%s" % k; it.make = PartThumbs.make_part_alone.bind("shock", k)
				it.view = Vector3(0.25, 0.2, 1.0)
				out.append(it)
		"rim", "tyre":
			var models: Dictionary = BikeBuild.RIM_MODELS if kind == "rim" else BikeBuild.TYRE_MODELS
			for k in models:
				var m: Dictionary = models[k]
				if not m.has("brand"): continue
				var tmp := BikeBuild.default_build()
				if kind == "rim": BikeBuild.apply_rim_model(tmp, k)
				else: BikeBuild.apply_tyre_model(tmp, k)
				var spec := BikeBuild.wheel_spec(tmp, false)
				var line := ("%s  ·  %d mm wide" % [String(m.material).capitalize(), m.width]) if kind == "rim" \
					else ("%s  ·  %.1f in" % [String(m.get("tread", "knobby")).capitalize(), float(m.get("tyre_w", 2.4))])
				var it := _p(kind, k, m.brand, Garage._model_name(m.label, m.brand), BikeBuild.part_stars(kind, k),
					Shop.price(kind, k) * 2, line)
				it.thumb = "%s|%s|%s" % [kind, k, JSON.stringify(spec)]
				it.make = PartThumbs.make_wheel.bind(spec, 0.3) if kind == "tyre" else PartThumbs.make_wheelset.bind(spec)
				it.view = Vector3(0.25, 0.75, 1.0) if kind == "tyre" else Vector3(0.05, 0.12, 1.0)
				out.append(it)
		"bar":
			for k in Handlebar.MODELS:
				var m: Dictionary = Handlebar.MODELS[k]
				if k == "stock" or m.has("glb"): continue   # (the frame models' own bars come with those bikes)
				var carbon := String(m.material).begins_with("carbon")
				var tier := (4 if m.width >= 800 else 3) + (1 if carbon and m.width >= 800 else 0) if carbon else (2 if m.width >= 780 else 1)
				var it := _p(kind, k, m.brand, m.label, tier, Shop.price("bar", k),
					"%d mm  ·  %s  ·  %s" % [m.width, ("%d mm rise" % m.rise) if m.rise > 0 else "flat", Handlebar.MATERIAL_SHORT[m.material]])
				it.thumb = "bar|%s|%s" % [k, P]
				it.make = PartThumbs.make_bars.bind(m, Garage._product_paint("crown"), Garage._product_paint("grips"))
				it.view = Vector3(1.0, 0.75, 0.55)
				out.append(it)
		"cassette":
			var ids: Array = BikeBuild.CASSETTES.keys()
			ids.sort_custom(func(a, b): return Shop.price("cassette", a) < Shop.price("cassette", b))
			for i in ids.size():
				var k: String = ids[i]
				var m: Dictionary = BikeBuild.CASSETTES[k]
				var cg: Array = m.cogs
				var spec := "%d-speed  ·  %d–%dT" % [cg.size(), cg[0], cg[cg.size() - 1]] if cg.size() > 1 else "Single speed  ·  %dT" % cg[0]
				var it := _p(kind, k, m.brand, m.name, _rank(ids.size(), i), Shop.price("cassette", k), spec)
				it.thumb = "cassette|%s" % k; it.make = PartThumbs.make_cassette.bind(k); it.view = Vector3(0.45, 0.35, 1.0)
				out.append(it)
		"light":
			var n: int = BikeLight.ORDER.size()
			for i in n:
				var id: String = BikeLight.ORDER[i]
				var lm: Dictionary = BikeLight.MODELS[id]
				var it := _p(kind, id, lm.brand, lm.label, _rank(n, i), Shop.price("light", id), BikeLight.spec_line(id))
				it.thumb = "alone2|light|%s" % id; it.make = PartThumbs.make_part_alone.bind("light", id)
				it.view = Vector3(0.9, 0.45, 0.6)
				out.append(it)
		_:
			for v in VARIANTS.get(kind, []):
				var it := _p(kind, v[0], v[1], v[2], v[3], v[4], v[6])
				it.look = v[5]
				var views := {"rotor": Vector3(0.12, 0.18, 1.0), "caliper": Vector3(0.3, 0.3, 1.0),
					"levers": Vector3(0.35, 0.9, 0.5), "stem": Vector3(0.7, 0.6, 0.7)}
				if views.has(kind):   # the part alone, as it comes out of the box
					it.thumb = "alone2|%s|%s" % [kind, v[5]]; it.make = PartThumbs.make_part_alone.bind(kind, v[5])
					it.view = views[kind]
				elif kind == "saddle":
					it.thumb = "saddle|%s" % v[5]; it.make = PartThumbs.make_saddle.bind(v[5]); it.view = Vector3(0.6, 0.5, 1.0)
				elif kind == "pedal":
					it.thumb = "pedal|%s|dh" % v[5]; it.make = PartThumbs.make_pedal.bind(v[5], "res://assets/dh.glb")
					it.view = Vector3(0.5, 0.6, 1.0)
				else:   # seat post: drawn on its own (the frame's own is part of its mesh)
					var coat := "gold" if int(v[3]) >= 5 else ""
					it.thumb = "alone2|post|%s|%s" % [v[5], coat]; it.make = PartThumbs.make_part_alone.bind("post", v[5], coat)
					it.view = Vector3(1.0, 0.25, 0.45)
				out.append(it)
	return out

## a product shot of a part on the stock bike (Garage._spot_make, static here)
static func spot_make(id: String, path: String, spot: String) -> Node3D:
	var tmp: Dictionary = BikeBuild.default_build()
	var k := path.split(".")
	if not tmp.has(k[0]): tmp[k[0]] = {}
	tmp[k[0]][k[1]] = id
	return PartThumbs.make_bike_spot(tmp, spot)
