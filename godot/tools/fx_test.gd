extends SceneTree
## FX: 500 puffs + 500 chunks on a bumpy terrain, 300 frames (tyre tracks are in the ground now: world/ruts.gd).
class Terrain:
	func height(x: float, z: float) -> float:
		return 0.3 * sin(x * 0.5) + 0.2 * cos(z * 0.7)

func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	var fx := FX.new(Terrain.new())
	get_root().add_child(fx)
	print("fx built in %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	var dust := Color8(0xc8, 0xa8, 0x7a)
	var rock := Color8(0x80, 0x78, 0x70)
	for i in 500:
		var p := Vector3(randf_range(-5, 5), 1.0, randf_range(-5, 5))
		fx.puff(p, Vector3(randf() - 0.5, 0.5, randf() - 0.5), dust, 0.3, 1.4 + randf() * 3.0, 0.45)
		fx.chunk(p, Vector3(randf_range(-2, 2), 1.5 + randf() * 2.0, randf_range(-2, 2)), rock, 0.03, 2.2)
	print("after spawn live=", fx.live_counts())
	var worst := 0.0
	var tsum := 0.0
	var x := 0.0
	for f in 300:
		x += 0.2
		if f % 10 == 0:
			fx.puff(Vector3(x, 0.2, 0), Vector3(0, 0.5, 0), dust)
			fx.chunk(Vector3(x, 0.3, 0), Vector3(0.5, 2.0, 0.3), rock)
		var a := Time.get_ticks_usec()
		fx.update(1.0 / 60.0, null)
		var us := float(Time.get_ticks_usec() - a)
		tsum += us
		worst = maxf(worst, us)
		if f == 299 or f % 100 == 0:
			print("frame %d live=%s" % [f, fx.live_counts()])
	# chunks must not sink into the ground
	var below := 0
	for i in FX.CHUNK_MAX:
		if fx.c_age[i] < fx.c_life[i]:
			var j := i * 3
			if fx.c_pos[j + 1] < fx.terrain.height(fx.c_pos[j], fx.c_pos[j + 2]) - 1e-3:
				below += 1
	var finite := true
	for v in fx.d_pos:
		if not is_finite(v): finite = false
	print("update avg %.3f ms, worst %.3f ms; chunks below ground=%d finite=%s" % [tsum / 300000.0, worst / 1000.0, below, finite])
	var ok := below == 0 and finite
	print("FX_TEST ", "PASS" if ok else "FAIL")
	fx.queue_free()
	quit(0 if ok else 1)
