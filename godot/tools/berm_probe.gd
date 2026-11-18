extends SceneTree
## Banked-turn transitions: walks the course and prints, per turn, the bank height on its outside wall
## and the worst change in that height per metre along the trail (a step shows up as a big jump).
## godot --headless --path godot -s res://tools/berm_probe.gd   (seed: env BMX_SEED, default 4242)


func _init() -> void:
	var seed := int(OS.get_environment("BMX_SEED")) if OS.get_environment("BMX_SEED") != "" else 4242
	var t := Terrain.new()
	t.use_cs = false
	t.set_seed(seed)
	var f: TerrainField = t.field
	var C := f.course
	var prev := [0.0, 0.0]
	var worst := 0.0
	var worst_s := 0.0
	var worst2 := 0.0
	var peaks := []
	var s := 0.0
	var hl := []
	while s < minf(C.length, 1500.0):
		var p: Array = C.at(s)
		var nx: float = -p[3]
		var nz: float = p[2]
		var h := [0.0, 0.0]
		for side in 2:
			var sg := 1.0 if side == 0 else -1.0
			h[side] = f.berm(p[0] + nx * 3.0 * sg, p[1] + nz * 3.0 * sg)
		hl.append(maxf(h[0], h[1]))
		if s > 0.0:
			for side in 2:
				var d := absf(h[side] - prev[side]) / 0.5
				if d > worst:
					worst = d; worst_s = s
		prev = h
		s += 0.5
	for i in range(1, hl.size() - 1):
		var c2: float = absf(hl[i + 1] - 2 * hl[i] + hl[i - 1]) / 0.25
		worst2 = maxf(worst2, c2)
		if hl[i] > 0.6 and hl[i] >= hl[i - 1] and hl[i] > hl[i + 1]:
			peaks.append("s=%.0f h=%.2f" % [i * 0.5, hl[i]])
	print("BERM seed %d: worst slope along trail %.3f m/m at s=%.1f, worst curvature %.3f" % [seed, worst, worst_s, worst2])
	print("BERM peaks: ", ", ".join(peaks))
	quit()
