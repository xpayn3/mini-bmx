@tool
class_name LevelBake
extends RefCounted
## The level builder's bake (step 3; dock: "Bake level"): everything a ride needs, worked out once and written next to
## the scene as <name>.bake (zstd): the LevelField's whole state (ground grid, trail, pieces, rocks, trees), each 48 m
## chunk's textures (LevelChunkData) and the light at the level's own time of day (C# LevelShadeBake: sun through the
## hills, ramps and tree crowns + sky openness). LevelTerrain loads it when its signature matches the scene (else it
## works the level out live, no baked light). Also runs the level's checks (what a rider will meet).

const VER := 2   # (2: real-size trees, 2026-11-26)


static func bake_path(scene_path: String) -> String:
	return scene_path.get_basename() + ".bake"


static func signature(lvl: BmxLevel) -> int:
	return hash(str([VER, lvl._signature(), lvl.hour, lvl.sun_turn]))


## towards the sun at this hour (Game._apply_light's sun)
## (Game.sun_elev_deg / SUN_AZ copied: Game can't load in the editor or a -s tool, it needs the autoloads)
const SUN_AZ := Vector2(-0.55, 0.42)
static func sun_elev_deg(h: float) -> float:
	var x := fposmod(h - 6.0, 24.0)
	return 62.0 * sin(PI * x / 14.0) if x <= 14.0 else -50.0 * sin(PI * (x - 14.0) / 10.0)

static func sun_dir(hour: float, turn_deg: float) -> Vector3:
	var el := deg_to_rad(maxf(sun_elev_deg(hour), 2.5))
	var x := fposmod(hour - 6.0, 24.0)
	var yaw := deg_to_rad(rad_to_deg(atan2(SUN_AZ.y, SUN_AZ.x)) + turn_deg + (x - 10.0) * (100.0 / 7.0))
	return Vector3(cos(yaw) * cos(el), sin(el), sin(yaw) * cos(el))


## bakes the level and writes the file; returns {ok, ms, size, checks: Array[String], path}
static func bake(lvl: BmxLevel, scene_path: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var f := lvl.make_field()
	f.bake(0.5)
	var t1 := Time.get_ticks_msec()
	var light := _light(f, sun_dir(lvl.hour, lvl.sun_turn))
	var lnx := (f.nx - 1) / 2 + 1; var lnz := (f.nz - 1) / 2 + 1
	var t2 := Time.get_ticks_msec()
	var chunks := {}
	for k in LevelChunkData.cover(f)[0]:
		chunks[k] = LevelChunkData.build(f, k, light, lnx, lnz, 1.0)
	var t3 := Time.get_ticks_msec()
	var data := {"ver": VER, "sig": signature(lvl), "hour": lvl.hour, "sun_turn": lvl.sun_turn, "field": f.state(),
		"light": light, "lnx": lnx, "lnz": lnz, "chunks": chunks}
	var path := bake_path(scene_path)
	var fa := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if fa == null: return {"ok": false, "path": path, "checks": ["could not write " + path]}
	fa.store_var(data)
	fa.close()
	var size := FileAccess.get_file_as_bytes(path).size()
	print("LEVELBAKE %s field=%d ms light=%d ms chunks=%d ms (%d) size=%.1f MB" % [path, t1 - t0, t2 - t1, t3 - t2, chunks.size(), size / 1048576.0])
	return {"ok": true, "path": path, "ms": Time.get_ticks_msec() - t0, "size": size, "checks": checks(f), "field": f}


## the baked light (RG per 1 m: sun, sky) from C#; empty without C#
static func _light(f: LevelField, to_sun: Vector3) -> PackedByteArray:
	var cs = null
	if ResourceLoader.exists("res://scripts/levels/editor/LevelShadeBake.cs"):
		var scr = load("res://scripts/levels/editor/LevelShadeBake.cs")
		if scr and scr.can_instantiate(): cs = scr.new()
	if cs == null: return PackedByteArray()
	var crowns := PackedFloat32Array()
	for t in f.tree_list:
		var sc := float(t.sc); var h := float(t.h)
		match str(t.kind):
			"pine", "leafy":   # (real-size crowns: CardTree.dims, as LevelVisuals draws them)
				var dm := CardTree.dims_at(str(t.kind), t.x, t.z)
				crowns.append_array([t.x, t.z, float(dm.R), h + float(dm.cb), h + float(dm.H)])
			_: crowns.append_array([t.x, t.z, sc * 0.8, h, h + sc * 0.9])
	return cs.Bake(f.H, f.nx, f.nz, f.x0, f.z0, f.step, to_sun, crowns, 2)


## the bake file if it is there and still matches the scene (else {})
static func load_bake(scene_path: String, sig: int) -> Dictionary:
	var path := bake_path(scene_path)
	if not FileAccess.file_exists(path): return {}
	var fa := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if fa == null: return {}
	var d = fa.get_var()
	fa.close()
	if not (d is Dictionary) or int(d.get("ver", 0)) != VER: return {}
	if int(d.get("sig", 0)) != sig:
		push_warning("LevelBake: %s is out of date (the level changed since it was baked): working it out live" % path)
		return {}
	return d


## what a rider will meet, as text lines (the dock / a bake)
static func checks(f: LevelField) -> Array:
	var out: Array = []
	for m in marks(f): out.append(("⚠ " if m.warn else "• ") + str(m.msg))
	if out.is_empty(): out.append("✓ no problems found")
	return out


## the same, each with where it is (level space; drawn as a post in the editor's 3D view): [{msg, pos, warn}]
## jumps that case / overshoot at their design speed or land hard, a slow rider dropping into a gap, pieces
## overlapping, no start / finish, bends that make riders brake hard, the trail leaving the level's ground
static func marks(f: LevelField) -> Array:
	var out: Array = []
	var at := func(p2: Vector2) -> Vector3: return Vector3(p2.x, f.height(p2.x, p2.y), p2.y)
	for st in f.structs:
		if not st.has("flights"): continue
		var fl: Dictionary = st.flights[1]
		var kind := str(st.d.kind)
		var lip: Vector2 = st.get("lip", st.o)
		if kind != "kicker" and str(fl.spot) != "landing":
			out.append({"warn": true, "pos": at.call(lip), "msg": "%s: at its design speed (%.0f km/h) it lands on the %s" % [st.name, float(st.v) * 3.6, fl.spot]})
		if float(fl.efh) > JumpDesign.EFH_MAX:
			out.append({"warn": true, "pos": at.call(lip), "msg": "%s: hard landing at design speed (EFH %.1f m, keep under %.1f)" % [st.name, float(fl.efh), JumpDesign.EFH_MAX]})
		var slow: Dictionary = st.flights[0]
		if float(slow.efh) > 3.0 and kind == "gap":
			out.append({"warn": false, "pos": at.call(lip), "msg": "%s: a rider 15 %% slow drops into the gap (EFH %.1f m): add fill" % [st.name, float(slow.efh)]})
	for i in f.structs.size():
		for j in range(i + 1, f.structs.size()):
			var ra := (f.structs[i].rect as Rect2).grow(-3.0); var rb := (f.structs[j].rect as Rect2).grow(-3.0)
			if ra.intersects(rb):
				out.append({"warn": true, "pos": at.call(ra.intersection(rb).get_center()), "msg": "%s and %s overlap" % [f.structs[i].name, f.structs[j].name]})
	var kinds := {}
	for g in f.gates: kinds[g.gate] = true
	var n := f.TV.size()
	if n > 1:
		if not kinds.has("start"): out.append({"warn": false, "pos": at.call(Vector2(f.TX[0], f.TZ[0])), "msg": "no start gate: the clock runs from the trail's start"})
		if not kinds.has("finish"): out.append({"warn": false, "pos": at.call(Vector2(f.TX[n - 1], f.TZ[n - 1])), "msg": "no finish gate: a run never ends"})
	var i2 := 1
	while i2 < n:
		if f.TV[i2 - 1] - f.TV[i2] > 0.0:
			var a := i2 - 1
			while i2 < n and f.TV[i2] < f.TV[i2 - 1]: i2 += 1
			var e := mini(i2, n - 1)
			if f.TV[a] - f.TV[e] > 5.0:
				out.append({"warn": false, "pos": at.call(Vector2(f.TX[e], f.TZ[e])), "msg": "%.0f m: riders brake from %.0f to %.0f km/h for this bend" % [a * f.DS, f.TV[a] * 3.6, f.TV[e] * 3.6]})
		i2 += 1
	var gx1 := f.x0 + (f.nx - 1) * f.step; var gz1 := f.z0 + (f.nz - 1) * f.step
	for q in range(0, n, 10):
		if f.TX[q] < f.x0 + 5.0 or f.TX[q] > gx1 - 5.0 or f.TZ[q] < f.z0 + 5.0 or f.TZ[q] > gz1 - 5.0:
			out.append({"warn": true, "pos": at.call(Vector2(f.TX[q], f.TZ[q])), "msg": "the trail leaves the level's ground (make the slope longer / wider)"}); break
	return out
