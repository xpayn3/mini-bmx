extends SceneTree
# tests: the rigid-body ragdoll alone (RagdollRbCs.SelfTest): dropped from rest, each constraint kind on / off
func _init() -> void:
	var rb = load("res://scripts/rider/RagdollRbCs.cs").new()
	for m in [[31, "nothing (anchors off too)"], [15, "anchors only"], [13, "anchors + motors"], [14, "anchors + limits"], [12, "anchors + limits + motors"], [8, "all but self"], [0, "all"]]:
		var r = rb.SelfTest(m[0] | 4, int(OS.get_environment("RB_N")) if OS.get_environment("RB_N") != "" else 240, 1.0)
		print("RBSELF %-28s max spin %.2f rad/s  joint gap %.4f m  limit over %.3f" % [m[1], r[0], r[1], r[2]])
	quit()
