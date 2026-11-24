extends SceneTree
## writes res://levels/demo_descent.tscn (-s, headless): a slope, a trail with straights, and one of every piece
## (start gate, table, rock garden, gap, drop, kicker, finish gate) put on the straightest stretches
func _init() -> void:
	var lvl := BmxLevel.make_new("Demo Descent")
	var t := lvl.trail()
	var c := Curve3D.new()
	var P := [Vector2(5, 0), Vector2(75, 0), Vector2(105, 18), Vector2(160, 24), Vector2(186, 6), Vector2(196, -24),
		Vector2(245, -36), Vector2(300, -32), Vector2(330, -10), Vector2(342, 16), Vector2(392, 24), Vector2(415, 10)]
	for i in P.size():
		var a: Vector2 = P[maxi(0, i - 1)]; var b: Vector2 = P[mini(P.size() - 1, i + 1)]
		var h := (b - a) / 6.0
		c.add_point(Vector3(P[i].x, 0, P[i].y), Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, h.y))
	t.curve = c
	lvl.snap_trail_to_ground()
	# the straight stretches (|curvature| under 1/120 for 30 m+)
	var f := lvl.make_field()
	f.bake(1.0)
	var runs := []
	var i0 := -1
	for i in f.TK.size():
		var ok := absf(f.TK[i]) < 1.0 / 120.0
		if ok and i0 < 0: i0 = i
		if (not ok or i == f.TK.size() - 1) and i0 >= 0:
			if i - i0 >= 30: runs.append([i0, i])
			i0 = -1
	print("MAKELEVEL straights: ", runs)
	var plan := [["table", 0.55], ["rocks", 0.2], ["gap", 0.55], ["drop", 0.3], ["kicker", 0.6]]
	_add(lvl, BmxGate.new(), "StartGate", f, 4, {"gate": "start"})
	for k in mini(plan.size(), runs.size()):
		var r: Array = runs[k]
		var at := int(lerpf(r[0], r[1], plan[k][1]))
		match plan[k][0]:
			"table": _add(lvl, BmxJump.new(), "Table1", f, at, {"kind": "table"})
			"gap": _add(lvl, BmxJump.new(), "Gap1", f, at, {"kind": "gap", "lip_deg": 28.0, "speed_scale": 0.8, "fill": 1.5})
			"kicker": _add(lvl, BmxJump.new(), "Kicker1", f, at, {"kind": "kicker", "lip_deg": 22.0, "build": "wood", "width": 2.4})
			"drop": _add(lvl, BmxDrop.new(), "Drop1", f, at, {"height": 1.6})
			"rocks": _add(lvl, BmxRocks.new(), "Rocks1", f, at, {"length": 22.0})
	_add(lvl, BmxGate.new(), "FinishGate", f, f.TX.size() - 6, {"gate": "finish"})
	var ps := PackedScene.new()
	ps.pack(lvl)
	print("MAKELEVEL save=", ResourceSaver.save(ps, "res://levels/demo_descent.tscn"))
	var g := lvl.make_field()
	var t0 := Time.get_ticks_msec()
	g.bake(0.5)
	print("MAKELEVEL bake 0.5 ms=", Time.get_ticks_msec() - t0, " ", g.summary(), " structs=", g.structs.size(), " rocks=", g.rocks.size(), " gates=", g.gates.size())
	print(g.jump_report())
	lvl.free()
	_park()
	quit()


## res://levels/demo_park.tscn: flat ground, no trail, standalone ramps put down freely (a start gate, a dirt table,
## a wooden kicker, a gap, a drop) in a line along +x
func _park() -> void:
	var lvl := BmxLevel.new()
	lvl.name = "Level"
	lvl.title = "Demo Park"
	lvl.flat_ground = true
	lvl.rough = 0.0
	lvl.length = 300.0; lvl.width = 120.0
	var put := func(n: BmxPiece, nm: String, x: float, z: float, props: Dictionary) -> void:
		n.name = nm
		n.follow_trail = false
		if not (n is BmxGate): n.standalone = true
		for k in props: n.set(k, props[k])
		n.transform = Transform3D(Basis(), Vector3(x, 0, z))
		lvl.add_child(n)
		n.owner = lvl
	put.call(BmxGate.new(), "StartGate", 10.0, 0.0, {"gate": "start"})
	put.call(BmxJump.new(), "Table1", 60.0, 0.0, {"kind": "table", "auto_speed": false, "design_kmh": 32.0})
	put.call(BmxJump.new(), "Kicker1", 120.0, 0.0, {"kind": "kicker", "build": "wood", "auto_speed": false, "design_kmh": 30.0, "lip_deg": 24.0, "width": 2.4})
	put.call(BmxJump.new(), "Gap1", 60.0, 14.0, {"kind": "gap", "auto_speed": false, "design_kmh": 36.0, "lip_deg": 28.0})
	put.call(BmxDrop.new(), "Drop1", 120.0, 14.0, {"auto_speed": false, "design_kmh": 26.0, "height": 1.2, "build": "wood"})
	var ps := PackedScene.new()
	ps.pack(lvl)
	print("MAKELEVEL park save=", ResourceSaver.save(ps, "res://levels/demo_park.tscn"))
	var f := lvl.make_field()
	f.bake(0.5)
	print("MAKELEVEL park structs=", f.structs.size(), " gates=", f.gates.size())
	print(f.jump_report())
	lvl.free()


func _add(lvl: BmxLevel, n: BmxPiece, nm: String, f: LevelField, i: int, props: Dictionary) -> void:
	n.name = nm
	for k in props: n.set(k, props[k])
	n.transform = Transform3D(Basis(Vector3.UP, atan2(-f.DZ[i], f.DX[i])), Vector3(f.TX[i], f.TY[i], f.TZ[i]))
	lvl.add_child(n)
	n.owner = lvl
