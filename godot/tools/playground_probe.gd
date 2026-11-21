extends SceneTree
## Headless check of the test playground's ground (PlaygroundCourse): every feature's span, top height, lip, the
## profile's lowest point (built features must never dig below the plane), and the steepest step between samples.
## Usage: ..._console.exe --headless --path godot -s res://tools/playground_probe.gd [-- verbose=1]
func _init() -> void:
	var c := PlaygroundCourse.new()
	var bad := 0
	for l in c.lanes:
		print("LANE %s z=%.0f length=%.0f m features=%d" % [l.id, l.z, l.length(), l.feats.size()])
		for f in l.feats:
			var lo := INF; var steep := 0.0
			var i0 := int(f.u0 / PlaygroundCourse.DU); var i1 := mini(l.h.size() - 1, int(f.u1 / PlaygroundCourse.DU))
			for i in range(i0, i1 + 1):
				lo = minf(lo, l.h[i])
				if i > i0: steep = maxf(steep, absf(l.h[i] - l.h[i - 1]) / PlaygroundCourse.DU)
			var dig: bool = str(f.id).begins_with("hole")
			var ok: bool = lo > -0.005 or dig
			if not ok: bad += 1
			print("  %-14s u %6.1f-%6.1f top=%.2f lip=%s low=%.3f steep=%.0f deg %s" % [f.id, f.u0, f.u1, f.top, ("%.1f" % f.lip) if f.lip >= 0 else "-", lo, rad_to_deg(atan(steep)), "" if ok else "DIGS BELOW 0"])
	for b in c.bowls:
		print("BOWL %s c=%s R=%.0f top=%.2f" % [b.id, b.c, b.R, b.W * b.tn])
	print("PLAYGROUND_PROBE ", "PASS" if bad == 0 else "FAIL %d" % bad)
	quit(bad)
