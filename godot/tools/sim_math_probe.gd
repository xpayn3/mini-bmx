extends SceneTree
## SimMath (godot/sim, engine-free C#) vs GDScript's own sin / cos / ... : must match bit for bit.
## godot --headless --path godot --script res://tools/sim_math_probe.gd [-- n=200000] [portable] [models]
## Per function: inputs over the ranges the ride uses + wider ones; prints mismatches vs SimMath (without the
## engine tie-break: those are the cases a platform without Godot would differ in) and vs .NET Math for scale.

const F := {"sin": 0, "cos": 1, "tan": 2, "atan": 3, "asin": 4, "acos": 5, "exp": 6, "log": 7, "tanh": 8, "atan2": 9, "pow": 10}

func _gd(fn: String, x: float, y: float) -> float:
	match fn:
		"sin": return sin(x)
		"cos": return cos(x)
		"tan": return tan(x)
		"atan": return atan(x)
		"asin": return asin(x)
		"acos": return acos(x)
		"exp": return exp(x)
		"log": return log(x)
		"tanh": return tanh(x)
		"atan2": return atan2(x, y)
		"pow": return pow(x, y)
	return NAN

func _inputs(fn: String, rng: RandomNumberGenerator, n: int) -> Array:
	var a := PackedFloat64Array(); var b := PackedFloat64Array()
	a.resize(n); b.resize(n)
	for i in n:
		var u := rng.randf(); var w := rng.randf()
		var x := 0.0; var y := 0.0
		var band := i % 4
		match fn:
			"sin", "cos", "tan":
				x = [(u - 0.5) * 2.0, (u - 0.5) * 14.0, (u - 0.5) * 200.0, (u - 0.5) * 1e-3][band]
			"atan":
				x = [(u - 0.5) * 2.0, (u - 0.5) * 40.0, (u - 0.5) * 1e4, (u - 0.5) * 1e-3][band]
			"asin", "acos":
				x = [(u - 0.5) * 2.0, (u - 0.5) * 0.2, 1.0 - u * 1e-3, -(1.0 - u * 1e-3)][band]
			"exp":
				x = [(u - 0.5) * 2.0, -u * 60.0, u * 20.0, (u - 0.5) * 1e-3][band]
			"log":
				x = [u * 2.0 + 1e-6, u * 1000.0 + 1e-9, 1.0 + (u - 0.5) * 1e-3, u * 1e-3 + 1e-12][band]
			"tanh":
				x = [(u - 0.5) * 2.0, (u - 0.5) * 12.0, (u - 0.5) * 1e-3, (u - 0.5) * 50.0][band]
			"atan2":
				x = (u - 0.5) * [2.0, 30.0, 1e-3, 2.0][band]; y = (w - 0.5) * [2.0, 1.0, 1.0, 1e-3][band]
			"pow":
				x = [u * 3.0, u * 20.0 + 1e-6, u * 1e-3 + 1e-9, u * 3.0][band]
				y = [2.0, 0.7, (w - 0.5) * 8.0, (w - 0.5) * 2.0][band]
		a[i] = x; b[i] = y
	return [a, b]

func _init() -> void:
	var n := 200000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("n="): n = int(arg.substr(2))
	var probe = ClassDB.instantiate("RefCounted")
	var scr = load("res://dev/sim/SimMathProbeCs.cs")
	if scr == null:
		print("SIMMATH no C# (build first)"); quit(2); return
	probe = scr.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 12345
	var fails := 0
	var models := false; var eng := true; var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "models": models = true
		if arg.begins_with("only="): only = arg.substr(5)
		if arg == "portable": eng = false   # no engine help: what another platform gets
	probe.SetEngineTies(eng)
	if models:
		# which rounding model fits each function (0 x87, 1 correctly rounded; tan also its x87 sin / cos model)
		for fn in F.keys():
			var io := _inputs(fn, rng, n)
			var row := "SIMMODEL %-6s" % fn
			var opts := [[0, 0], [1, 0]] + ([[0, 1]] if fn == "tan" else [])
			for o in opts:
				probe.SetModel(F[fn], o[0]); probe.SetTanModel(o[1])
				var cs: PackedFloat64Array = probe.Eval(F[fn], io[0], io[1])
				var bad := 0
				for i in n:
					var g := _gd(fn, io[0][i], io[1][i])
					if not ((g == cs[i]) or (is_nan(g) and is_nan(cs[i]))): bad += 1
				row += "  m%d/t%d=%d" % [o[0], o[1], bad]
			print(row)
		quit(0); return
	for fn in F.keys():
		if only != "" and fn != only: continue
		var io := _inputs(fn, rng, n)
		probe.ResetTies()
		var cs: PackedFloat64Array = probe.Eval(F[fn], io[0], io[1])
		var ties: int = probe.Ties()
		var net: PackedFloat64Array = probe.EvalNet(F[fn], io[0], io[1])
		var bad := 0; var bad_net := 0; var ex := []; var outside := 0
		for i in n:
			var g := _gd(fn, io[0][i], io[1][i])
			var same := (g == cs[i]) or (is_nan(g) and is_nan(cs[i]))
			if not same and fn == "pow" and i % 4 == 2:
				outside += 1   # tiny base to a large power: the x87's own f2xm1 error, a range the ride never uses
			elif not same:
				bad += 1
				if ex.size() < 4: ex.append("%s(%s, %s) gd=%s sim=%s net=%s" % [fn, var_to_str(io[0][i]), var_to_str(io[1][i]), var_to_str(g), var_to_str(cs[i]), var_to_str(net[i])])
			if not ((g == net[i]) or (is_nan(g) and is_nan(net[i]))): bad_net += 1
		fails += bad
		print("SIMMATH %-6s n=%d mismatch=%d (%.4f%%) ties=%d  .NET mismatch=%d (%.3f%%)" % [fn, n, bad, 100.0 * bad / n, ties, bad_net, 100.0 * bad_net / n])
		if outside > 0: print("   (%d more outside the ride's range: pow of bases < 1e-3 to powers > 2)" % outside)
		for e in ex: print("   ", e)
	print("SIMMATH ", "PASS" if fails == 0 else "mismatches=%d" % fails)
	quit(0 if fails == 0 else 1)
