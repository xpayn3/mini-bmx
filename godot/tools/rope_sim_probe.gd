extends SceneTree
## RopeBridgeSim alone: sag, wind sway, a rider's weight walked across, stability
func _init() -> void:
	var s = load("res://scripts/world/RopeBridgeSim.cs").new()
	if OS.get_environment("HK") != "": s.HangerK = float(OS.get_environment("HK"))
	if OS.get_environment("DK") != "": s.DiagK = float(OS.get_environment("DK"))
	s.Setup(40, 3.1, 10.0, 42.9, 10.0, 0.55, 1.25, 2.6, 43.4, 1.25, 0.8, 1.3, 7.0, 0.9)
	var c: Vector3 = s.Centre(0.5)
	print("REST mid y=%.2f (sag %.2f)" % [c.y, 10.0 - c.y])
	for wind in [0.0, 5.0, 10.0, 20.0]:
		var mx := 0.0
		for k in 600:
			s.Step(1.0 / 120.0, 0.0, wind)
			mx = maxf(mx, absf(s.Centre(0.5).z))
		print("WIND %.0f m/s across: mid sway max %.2f m, now z=%.2f y=%.2f" % [wind, mx, s.Centre(0.5).z, s.Centre(0.5).y])
	for k in 600: s.Step(1.0 / 120.0, 0.0, 0.0)
	# 95 kg walking across at 3 m/s with a side push of 4 m/s² alternating every 0.5 s
	var u := 3.2
	var t := 0.0
	var mz := 0.0
	var mdip := 0.0
	while u < 42.8:
		var side := 95.0 * 4.0 * sin(t * TAU)
		s.AddLoad(u, 0.0, -95.0 * 9.81, side)
		s.Step(1.0 / 120.0, 0.0, 0.0)
		var h: float = s.Height(u, 0.0, 0.06)
		var rest_y := 10.0 - 4.0 * 1.95 * (u - 3.1) / 39.8 * (1.0 - (u - 3.1) / 39.8)
		mdip = maxf(mdip, rest_y - h)
		mz = maxf(mz, absf(s.Carry(u, 0.0).y) * 120.0)
		u += 3.0 / 120.0
		t += 1.0 / 120.0
	print("WALK max side speed of deck under rider %.2f m/s, mid now z=%.2f; finite=%s" % [mz, s.Centre(0.5).z, is_finite(s.Centre(0.5).y)])
	quit()
