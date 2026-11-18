extends SceneTree
## Suspension on the real dh.glb: 200 updates with bumps / landings; the shock stroke must stay finite
## and inside the stroke range of the rear travel.
func _initialize() -> void:
	var root3d: Node3D = load("res://assets/dh.glb").instantiate()
	get_root().add_child(root3d)
	var bike := root3d.find_child("dh", true, false) as Node3D
	var data: Dictionary = bike.get_meta("extras")
	var susp := Suspension.new(bike, data)
	print("hasF=", susp.has_f, " hasR=", susp.has_r, " F=", susp.F, " R=", susp.R, " table rows=", susp.table.size())
	var full := susp.stroke()
	var top = susp.solve(susp.phi_for(susp.R["min"]), susp.C2)
	var s_min := susp.L0 - (top["D"] as Vector2).distance_to(susp.FE)
	print("stroke at full travel=%.4f  at top-out=%.4f  (L0=%.4f springLen=%.4f)" % [full, s_min, susp.L0, susp.spring_len])
	var lo := INF
	var hi := -INF
	var ok := true
	var dt := 1.0 / 120.0
	for i in 200:
		var air := (i >= 60 and i < 90)
		if i == 90:
			susp.land(4.0, false, false)
		if i == 150:
			susp.land(6.0, true, false)
		var bump := 0.08 * sin(i * 0.4) + (0.1 if i % 37 == 0 else 0.0)
		susp.update(dt, {"air": air, "load": 0.5 + 0.5 * sin(i * 0.1), "brake": 1 if i > 170 else 0,
			"bumpF": bump, "bumpR": 0.08 * cos(i * 0.33)})
		susp.apply()
		var s := susp.last_stroke
		if not is_finite(s) or not is_finite(susp.xF) or not is_finite(susp.xR) or not bike.position.is_finite():
			ok = false
		lo = minf(lo, s)
		hi = maxf(hi, s)
		if i % 25 == 0:
			print("i=%3d air=%s xF=%+.4f xR=%+.4f stroke=%.4f spring.y=%.3f bike.rot.z=%+.4f pos=%s" % [i, air, susp.xF, susp.xR, s, susp.n["shock_spring"].scale.y, bike.rotation.z, bike.position])
	var eps := 1e-4
	var in_travel := lo >= minf(s_min, full) - eps and hi <= maxf(s_min, full) + eps
	print("stroke range over run: [%.4f, %.4f]  finite=%s  in_travel=%s" % [lo, hi, ok, in_travel])
	print("SUSP_TEST ", "PASS" if ok and in_travel else "FAIL")
	root3d.queue_free()
	quit(0 if ok and in_travel else 1)
