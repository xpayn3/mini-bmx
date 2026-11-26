extends SceneTree
## grass density beside the trail and under built jumps, from real chunk bakes: -- seed [jumps]
## Picks the first built jumps in green land (not dry / ash). VERGE = grass density (0..1) every 0.25 m out from the trail's
## centre, 25 m before the jump; JUMPLINE = density + riders-in-the-air every 2 m along it. Compare with BMX_OLD_VERGE=1.
var t: Terrain
var built := {}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	t = Terrain.new(int(a[0]))
	var want := int(a[1]) if a.size() > 1 else 2
	var f = t.field
	var done := 0
	for rf in f.route_feats:
		if done >= want:
			break
		if not TerrainField.AIR_TYPES.has(rf.type):
			continue
		f.biome(rf.x, rf.z)
		if f.b_dry > 0.25 or f.b_ash > 0.2:
			continue
		done += 1
		var dir := Vector2(rf.dx, rf.dz).normalized()
		var side := Vector2(-dir.y, dir.x)
		print("JUMP %s s=%.0f at=%.1f,%.1f" % [rf.type, rf.s, rf.x, rf.z])
		var c := Vector2(rf.x, rf.z) - dir * float(OS.get_environment("VP_BACK") if OS.get_environment("VP_BACK") != "" else "25")
		# a 24 m patch round c, every texel binned by its distance past the trail's edge (q_d - q_w), 0.25 m bins
		var sum := PackedFloat32Array(); sum.resize(16)
		var cnt := PackedInt32Array(); cnt.resize(16)
		for jz in 96:
			for jx in 96:
				var p := c + Vector2(jx - 48, jz - 48) * 0.25
				f.query(p.x, p.y)
				var b := floori((f.q_d - f.q_w + 0.5) / 0.25)
				if b < 0 or b >= 16 or f.jump_mask(p.x, p.y) > 0.0:
					continue
				sum[b] += _den(p)[0]; cnt[b] += 1
		var line := "VERGE past edge (m) = mean grass:"
		for b in 16:
			if cnt[b] > 0:
				line += " %.2f=%.2f" % [b * 0.25 - 0.5, sum[b] / cnt[b]]
		print(line)
		for i in range(-5, 21):
			var r := _den(Vector2(rf.x, rf.z) + dir * (i * 2.0))
			print("JUMPLINE u=%5.1f grass=%.2f air=%.2f" % [i * 2.0, r[0], r[1]])
	print("VERGEPROBE jumps=", done, " feats=", f.route_feats.size())
	t.free(); quit()


func _den(p: Vector2) -> Array:
	var S := TerrainChunkBuilder.S
	var cx := roundi(p.x / S)
	var cz := roundi(p.y / S)
	var k := Vector2i(cx, cz)
	if not built.has(k):
		var b := TerrainChunkBuilder.new(t.fcs.fork() if t.fcs != null else t.field.fork(), cx, cz, t.seg, 0)
		b.run()
		built[k] = b.out
	var o: Dictionary = built[k]
	var gi: Image = o["grass_img"]
	var ai: Image = o["trail3_img"]
	var n := gi.get_width() - 1
	var ix := clampi(roundi((p.x - cx * S + S / 2) / S * n), 0, n)
	var iz := clampi(roundi((p.y - cz * S + S / 2) / S * n), 0, n)
	return [gi.get_pixel(ix, iz).a, ai.get_pixel(ix, iz).r]
