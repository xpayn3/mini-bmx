extends SceneTree
## -s res://tools/bake_jumps.gd --headless: the trail's built jumps from JumpDesign (TRAIL_JUMPS below) as Hermite
## knots + AIR spans, printed as JSON (BAKE {...}). tools/bake_jumps.py writes them into trail_features.gd and
## TerrainFieldCs.cs (both must hold the same numbers: terrain_cs_cmp). Change a design here, re-run both.

const TRAIL_JUMPS := {
	# the trail's riders arrive at ~45-60 km/h; the physics loses ~7 % more on a face than the formula, so these land
	# on the sweet spot at ~60 km/h for real; slower riders case the deck (EFH < ~1 m: safe), never the flat
	"table": {"v": 15.5, "lip_deg": 22.0, "aim": 0.3, "land_g": 1.8, "lip_t": 0.2},
	"kicker": {"v": 15.0, "lip_deg": 17.0, "lip_g": 1.6, "aim": 0.3, "land_g": 1.8, "lip_t": 0.15},
}


func _init() -> void:
	var out := {}
	for k in TRAIL_JUMPS:
		var d := JumpDesign.build(TRAIL_JUMPS[k])
		out[k] = {"knots": JumpDesign.knots(d), "air": JumpDesign.air_span(d), "length": d.length, "desc": JumpDesign.describe(d)}
	print("BAKE " + JSON.stringify(out))
	quit()
