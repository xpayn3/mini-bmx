extends SceneTree
## -s res://tools/bake_jumps.gd --headless: the trail's built jumps from JumpDesign (TRAIL_JUMPS below) as Hermite
## knots + AIR spans, printed as JSON (BAKE {...}). tools/bake_jumps.py writes them into trail_features.gd and
## TerrainFieldCs.cs (both must hold the same numbers: terrain_cs_cmp). Change a design here, re-run both.

const TRAIL_JUMPS := {
	# the trail's riders arrive at ~45-60 km/h; the physics loses ~7 % more on a face than the formula, so these land
	# on the sweet spot at ~60 km/h for real; slower riders case the deck (EFH < ~1 m: safe), never the flat
	"table": {"v": 15.5, "lip_deg": 22.0, "aim": 0.3, "land_g": 1.8, "lip_t": 0.2},
	"kicker": {"v": 15.0, "lip_deg": 17.0, "lip_g": 1.6, "aim": 0.3, "land_g": 1.8, "lip_t": 0.15},
	# the small free-ride jumps out in the land (TerrainField.jump_at): within their old footprints (21 / 14 m: they sit
	# close to each other and to wooden features), sized for ~40 / 35 km/h
	"table_s": {"v": 11.0, "lip_deg": 20.0, "lip_g": 1.7, "lip_t": 0.15, "aim": 0.3, "land_g": 2.0},
	"kicker_s": {"v": 9.5, "lip_deg": 16.0, "lip_g": 1.8, "lip_t": 0.12, "aim": 0.3, "land_g": 2.2},
	# doubles (2026-11-24): a gap whose floor is filled to ~85 % of the lip (`fill`), so a rider short of it drops a little
	# into a dip instead of into the landing's face. The big one sized like the table, the small (free ride) within the
	# old 23 m footprint for ~38 km/h
	"double": {"kind": "gap", "v": 15.5, "lip_deg": 22.0, "aim": 0.3, "land_g": 1.8, "lip_t": 0.2, "fill": 2.2},
	"double_s": {"kind": "gap", "v": 10.5, "lip_deg": 24.0, "lip_g": 1.8, "lip_t": 0.12, "fill": 1.0, "aim": 0.3, "land_g": 2.2},
}


## m/s the smaller route jump sizes are designed for (size 3 = TRAIL_JUMPS' own v)
const SIZE_V := [8.5, 11.0, 13.5]


func _init() -> void:
	var out := {}
	for k in TRAIL_JUMPS:
		var d := JumpDesign.build(TRAIL_JUMPS[k])
		out[k] = {"knots": JumpDesign.knots(d), "air": JumpDesign.air_span(d), "length": d.length, "desc": JumpDesign.describe(d)}
	# the route's table + kicker at smaller speed sizes (TrailJumpSizes, 2026-11-24): the route picks the size that fits the
	# speed riders really arrive at (TrailCourse.VA). Size 3 is the design above (TABLE / KICKER)
	var sized := {}
	for k in ["table", "kicker"]:
		var arr := []
		for v in SIZE_V:
			var prm: Dictionary = TRAIL_JUMPS[k].duplicate()
			prm.v = v
			var d := JumpDesign.build(prm)
			arr.append({"knots": JumpDesign.knots(d), "air": JumpDesign.air_span(d), "length": d.length, "desc": JumpDesign.describe(d)})
		sized[k] = arr
	out["sized"] = sized
	out["size_v"] = SIZE_V
	print("BAKE " + JSON.stringify(out))
	quit()
