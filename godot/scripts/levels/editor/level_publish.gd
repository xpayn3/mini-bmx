@tool
class_name LevelPublish
extends RefCounted
## Publishing a built level (the dock's "Publish"): the level must have an up-to-date bake; its medal times (from the
## speed profile between the start and finish gates, unless set by hand), difficulty (1-5 stars, unless set) and a
## picture (the map: land, trail, pieces) are worked out, and it goes into the registry res://levels/levels.cfg that
## the game's LEVELS menu lists. Unpublish takes it out.

const REGISTRY := "res://levels/levels.cfg"
const SILVER_K := 1.15
const BRONZE_K := 1.35


## seconds a clean fast rider takes between two trail samples at the speeds the trail allows (LevelField.TV)
static func ideal_time(f: LevelField, i0: int, i1: int) -> float:
	var t := 0.0
	for i in range(maxi(1, i0 + 1), mini(i1 + 1, f.TV.size())):
		t += f.DS / maxf(1.0, 0.5 * (f.TV[i - 1] + f.TV[i]))
	return t


## the timed stretch: start gate (or the trail's start) .. finish gate (or its end), as trail sample indices
static func timed_span(f: LevelField) -> Vector2i:
	var a := 0; var b := f.TX.size() - 1
	for g in f.gates:
		if int(g.i) < 0: continue
		if g.gate == "start": a = int(g.i)
		elif g.gate == "finish": b = int(g.i)
	return Vector2i(a, b)


## 1 (easy) .. 5 (pro): the biggest jump / drop, the top speed, the steepest stretch, the hard braking
static func auto_difficulty(f: LevelField) -> int:
	var big := 0.0
	for st in f.structs:
		var top := 0.0
		for h in st.hs: top = maxf(top, h)
		big = maxf(big, top)
	var vmax := 0.0
	for v in f.TV: vmax = maxf(vmax, v)
	var steep := 0.0
	for i in range(10, f.TY.size(), 5): steep = maxf(steep, (f.TY[i - 10] - f.TY[i]) / (10.0 * f.DS))
	var score := big / 1.0 + vmax / 8.0 + steep * 6.0
	for m in LevelBake.marks(f):
		if str(m.msg).contains("brake from"): score += 0.3
	return clampi(int(round(score * 0.5)), 1, 5)


## the level's map as a picture (2 m a pixel, up to 512 wide): land shaded, trail, structures, rocks, gates
static func picture(f: LevelField) -> Image:
	var e := maxi(4, int(ceil(float(f.nx) / 512.0)))
	var w := int((f.nx - 1) / e); var h := int((f.nz - 1) / e)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		for i in w:
			var k := (j * e) * f.nx + i * e
			var k2 := mini(k + f.nx * e + e, f.H.size() - 1)
			var sh := clampf(0.62 + (f.H[k] - f.H[k2]) * 0.3, 0.3, 1.1)
			var sf := f.S[k]
			var c := LevelField.GRASS
			if sf == 1 or sf == 2: c = LevelField.DIRT.lightened(0.15)
			elif sf == 3: c = LevelField.SAND
			elif sf == 4: c = LevelField.ROCK
			if f.JM[k] == 1: c = Color(0.95, 0.78, 0.35)
			img.set_pixel(i, j, (c * sh).clamp())
	for t in f.tree_list:   # (trees as dark dots)
		var px := int((float(t.x) - f.x0) / (f.step * e)); var pz := int((float(t.z) - f.z0) / (f.step * e))
		if px >= 0 and pz >= 0 and px < w and pz < h and t.kind != "bush": img.set_pixel(px, pz, Color(0.16, 0.3, 0.18))
	for g in f.gates:
		var gp: Vector2 = g.pos
		var px := int((gp.x - f.x0) / (f.step * e)); var pz := int((gp.y - f.z0) / (f.step * e))
		var col: Color = LevelVisuals.GATE_COL.get(g.gate, Color.WHITE)
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if px + dx >= 0 and pz + dz >= 0 and px + dx < w and pz + dz < h: img.set_pixel(px + dx, pz + dz, col)
	return img


## publishes the level open in the editor: -> {ok, msg}
static func publish(lvl: BmxLevel) -> Dictionary:
	var path := lvl.scene_file_path
	if path == "": return {"ok": false, "msg": "Save the level first."}
	var bk := LevelBake.load_bake(path, LevelBake.signature(lvl))
	if bk.is_empty(): return {"ok": false, "msg": "Bake the level first (its bake is missing or out of date)."}
	var f := LevelField.new()
	f.load_state(bk.field)
	var span := timed_span(f)
	var ideal := ideal_time(f, span.x, span.y)
	var length := (span.y - span.x) * f.DS
	var drop := f.TY[span.x] - f.TY[span.y] if f.TY.size() > 0 else 0.0
	if f.TX.size() < 2:   # (no trail: a park; start gate -> finish gate in a line at a park pace, ~29 km/h)
		var a := Vector2.INF; var b := Vector2.INF
		for g in f.gates:
			if g.gate == "start": a = g.pos
			elif g.gate == "finish": b = g.pos
		length = a.distance_to(b) if a.x != INF and b.x != INF else 0.0
		ideal = length / 8.0
		drop = f.height(a.x, a.y) - f.height(b.x, b.y) if length > 0.0 else 0.0
	if ideal <= 0.0 and lvl.medal_gold <= 0.0: return {"ok": false, "msg": "Nothing to time: give the level a trail, or a start and a finish gate."}
	var gold := lvl.medal_gold if lvl.medal_gold > 0.0 else snappedf(ideal * 1.02, 0.1)
	var silver := lvl.medal_silver if lvl.medal_silver > 0.0 else snappedf(gold * SILVER_K, 0.1)
	var bronze := lvl.medal_bronze if lvl.medal_bronze > 0.0 else snappedf(gold * BRONZE_K, 0.1)
	var diff := lvl.difficulty if lvl.difficulty > 0 else auto_difficulty(f)
	var pic_path := path.get_basename() + "_map.png"
	picture(f).save_png(pic_path)
	var jumps := 0
	for st in f.structs: if st.has("d"): jumps += 1
	var cf := ConfigFile.new()
	cf.load(REGISTRY)
	cf.set_value(path, "title", lvl.title)
	cf.set_value(path, "description", lvl.description)
	cf.set_value(path, "difficulty", diff)
	cf.set_value(path, "medals", [gold, silver, bronze])
	cf.set_value(path, "length", snappedf(length, 1.0))
	cf.set_value(path, "drop", snappedf(drop, 1.0))
	cf.set_value(path, "jumps", jumps)
	cf.set_value(path, "picture", pic_path)
	cf.set_value(path, "order", cf.get_value(path, "order", cf.get_sections().size()))
	cf.save(REGISTRY)
	lvl.published = true
	var msg := "PUBLISHED %s\n%s · %.0f m · %.0f m drop · %d jumps\nmedals  gold %s · silver %s · bronze %s" % [
		lvl.title, "★".repeat(diff) + "☆".repeat(5 - diff), length, drop, jumps,
		fmt(gold), fmt(silver), fmt(bronze)]
	var warns := 0
	for m in LevelBake.marks(f): if m.warn: warns += 1
	if warns > 0: msg += "\n⚠ %d problem(s) found by the checks: see the red posts" % warns
	return {"ok": true, "msg": msg}


static func unpublish(lvl: BmxLevel) -> void:
	var cf := ConfigFile.new()
	if cf.load(REGISTRY) == OK and cf.has_section(lvl.scene_file_path):
		cf.erase_section(lvl.scene_file_path)
		cf.save(REGISTRY)
	lvl.published = false


## what the game's LEVELS menu lists: [{path, title, description, difficulty, medals, length, drop, jumps, picture}]
static func list() -> Array:
	var out: Array = []
	var cf := ConfigFile.new()
	if cf.load(REGISTRY) != OK: return out
	for p in cf.get_sections():
		if not ResourceLoader.exists(p): continue
		var e := {"path": p}
		for k in cf.get_section_keys(p): e[k] = cf.get_value(p, k)
		out.append(e)
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out



## m:ss.cc (LevelRace's own copy: that one needs the game's autoloads, this runs in the editor)
static func fmt(secs: float) -> String:
	var m := int(secs / 60.0)
	return "%d:%05.2f" % [m, secs - m * 60.0]
