extends SceneTree
## -s res://tools/jump_design_probe.gd --headless [-- v=12 lip_deg=26 kind=gap ...]: JumpDesign's numbers for a few
## jumps (or one, from the arguments): lip, radius, g, deck, landing, and where riders at 85 / 100 / 115 % land + EFH


func _init() -> void:
	var p := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2: p[kv[0]] = kv[1] if kv[0] == "kind" else float(kv[1])
	var sets := [p] if not p.is_empty() else [
		{"v": 9.0, "lip_deg": 24.0}, {"v": 12.0, "lip_deg": 26.0}, {"v": 13.5, "lip_deg": 26.0},
		{"v": 12.0, "lip_deg": 30.0, "kind": "gap"}, {"v": 12.0, "lip_deg": 26.0, "height": 2.0}]
	for s in sets:
		var t0 := Time.get_ticks_usec()
		var d := JumpDesign.build(s)
		var us := Time.get_ticks_usec() - t0
		print("JD %s  len=%.1f knots=%d  %d us" % [str(s), d.length, d.knots.size(), us])
		print("   ", JumpDesign.describe(d), "  v_lip=%.1f land0=%.1f land1=%.1f rb=%.1f" % [d.v_lip, d.land0, d.land1, d.rb])
		for k in [0.7, 0.8, 0.9, 1.0, 1.1, 1.2]:
			var pr := JumpDesign.predict(d, float(d.p.v) * k)
			print("   %3d%% v=%4.1f km/h  lands %5.1f m out (%s)  air %.2f s  apex %.2f  EFH %.2f m" % [int(k * 100), pr.v * 3.6, pr.dist, pr.spot, pr.air, pr.apex, pr.efh])
	quit()
