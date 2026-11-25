extends SceneTree
## Tape stakes standing beside a course fence (fence + tape both along the road look wrong): per seed, the share of stakes within
## 4 m of any course fence post, and how many are in a fence's gate gap. -s res://tools/tape_fence_probe.gd [-- seed ...]
func _init() -> void:
	var seeds: Array = [4242, 5, 7, 12, 99, 1]
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seeds = []
		for a in args: seeds.append(int(a))
	var tot := 0; var near := 0
	for sd in seeds:
		var f := TerrainField.new()
		f.setup(sd, {})
		var C: TrailCourse = f.course
		var n_s := 0; var n_near := 0
		for st in C.stakes:
			n_s += 1
			var hit := false
			for fc in C.fences:
				for p in fc["posts"]:
					if absf(p[0] - st["x"]) < 4.0 and absf(p[1] - st["z"]) < 4.0 and Vector2(p[0] - st["x"], p[1] - st["z"]).length() < 4.0:
						hit = true; break
				if hit: break
			if hit: n_near += 1
		print("TAPEFENCE seed=%d stakes=%d fences=%d stakes_within_4m_of_a_fence_post=%d" % [sd, n_s, C.fences.size(), n_near])
		tot += n_s; near += n_near
	print("TAPEFENCE TOTAL stakes=%d near_fence=%d" % [tot, near])
	quit()
