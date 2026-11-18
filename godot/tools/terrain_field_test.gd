extends SceneTree
func _init():
	var t0 := Time.get_ticks_usec()
	var f := TerrainField.new()
	f.setup(12345)
	print("setup ms ", (Time.get_ticks_usec() - t0) / 1000.0, " course n=", f.course.n, " fences=", f.course.fences.size(), " stakes=", f.course.stakes.size(), " route=", f.route_feats.size())
	var pts = [[0,0],[10,5],[37.5,-12.25],[100,20],[250,-40],[-80,60],[500,0],[-300,-300],[800,120],[1200,-50],[60,200],[-500,400]]
	for p in pts:
		print("P ", p[0], " ", p[1], " ground=", "%.10f" % f.ground(p[0], p[1]), " deck=", "%.10f" % f.deck(p[0], p[1]), " biome=", f.biome_name(p[0], p[1]), " jump=", f.jump(p[0], p[1]))
	var r := WorldRng.new(99)
	var xs := PackedFloat64Array(); var zs := PackedFloat64Array()
	for i in 20000:
		xs.append(-400 + r.next() * 1800); zs.append(-300 + r.next() * 600)
	t0 = Time.get_ticks_usec()
	var s := 0.0
	for i in 20000:
		s += f.deck(xs[i], zs[i])
	print("20k random deck() us/call ", (Time.get_ticks_usec() - t0) / 20000.0, " sum ", s)
	t0 = Time.get_ticks_usec()
	for i in 20000:
		s += f.deck(500 + i * 0.001, 3.0 + i * 0.0007)
	print("20k local deck() us/call ", (Time.get_ticks_usec() - t0) / 20000.0)
	t0 = Time.get_ticks_usec()
	for i in 100000:
		s += f.noise(i * 0.013, i * 0.007)
	print("noise us/call ", (Time.get_ticks_usec() - t0) / 100000.0)
	quit()
