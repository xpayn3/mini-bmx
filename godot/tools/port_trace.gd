extends Node
## Reference traces for the Unity port (unity/PORTING.md): rides the Godot BikePhysics through fixed scripted runs on
## slope_stress's synthetic ground and writes every step's state, so the C# port (unity/SimTests) can ride the same
## runs and compare step by step.
##   ..._console.exe --headless --path godot res://tools/port_trace.tscn -- out=<dir>
## Writes <dir>/config.json (the effective Tune values, the DH's geometry + build config) and <dir>/<run>.csv.
## The Godot-only randomness (FastNoiseLite loose patches, the RNG's grip bumps) is switched off in both
## (TRACE_TUNE), so a difference is a porting difference.

const SS := preload("res://tools/slope_stress.gd")
const DT := 1.0 / 120.0
const TRACE_TUNE := {"gripLoose": 0.0, "gripBumps": 0.0, "brakeLoose": 0.0, "brakeRough": 0.0}
const COLS := ["t", "x", "y", "z", "v", "vy", "heading", "pitch", "bike_lean", "lean", "steer", "air", "body_y", "y_draw", "pitch_draw", "slip", "crank", "man_a", "crash"]

## run: [name, ground kind, a, b, x0, start speed m/s, seconds, input script]
const RUNS := [
	["flat_pedal", "flat", 0.0, 0.0, 20.0, 0.0, 8.0, "pedal"],
	["coast_down", "grade", -0.2, 0.0, 5.0, 8.0, 8.0, "none"],
	["climb", "grade", 0.12, 0.0, 10.0, 6.0, 8.0, "pedal"],
	["brake_stop", "flat", 0.0, 0.0, 20.0, 12.0, 5.0, "brake"],
	["turn", "flat", 0.0, 0.0, 20.0, 8.0, 6.0, "turn"],
	["swaps", "flat", 0.0, 0.0, 20.0, 10.0, 6.0, "swaps"],
	["camber", "camber", 0.2, 0.0, 20.0, 8.0, 5.0, "none"],
	["crest_jump", "crest", 1.2, 8.0, 15.0, 13.0, 5.0, "none"],
	["rollers", "rollers", 0.5, 9.0, 10.0, 9.0, 8.0, "pump"],
	["drop", "step", 0.0, -1.0, 15.0, 9.0, 4.0, "none"],
	["washboard", "washboard", 0.06, 1.3, 10.0, 11.0, 5.0, "none"],
	["hop", "flat", 0.0, 0.0, 20.0, 7.0, 4.0, "hop"],
	["manual", "flat", 0.0, 0.0, 20.0, 7.0, 4.0, "manual"],
	["sprint", "flat", 0.0, 0.0, 20.0, 2.0, 6.0, "sprint"],
]

func _ready() -> void:
	var out := "user://port_trace"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var tune = get_node("/root/Tune")
	var cfg: Dictionary = get_node("/root/GameState").bike_config_for("dh")
	tune.set_ride(cfg.ride)
	# ride_out=<file>: the DH as the game rides it (effective Tune values = the player's sliders x the bike's multipliers,
	# and the bike config), plain key=value lines for the Unity port's RideBootstrap. No test overrides. Then quit
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ride_out="):
			_write_ride(a.substr(9), tune, cfg)
			get_tree().quit(0)
			return
	for k in TRACE_TUNE: tune.v[k] = TRACE_TUNE[k]
	var extras: Dictionary = SS.DH_EXTRAS
	var sc: Node = load(cfg.file).instantiate()
	var m: Node = sc.find_child(cfg.root, true, false)
	if m and m.has_meta("extras"): extras = (m.get_meta("extras") as Dictionary).duplicate(true)
	sc.free()
	var mods: Dictionary = cfg.get("mods", {})
	var conf := {
		"tune": tune.v,
		"extras": {"wheelbase": extras.get("wheelbase", 0.8985), "wheelRadius": extras.get("wheelRadius", 0.261),
			"wheelRadiusRear": extras.get("wheelRadiusRear", extras.get("wheelRadius", 0.261)), "bbToRearAxle": extras.get("bbToRearAxle", 0.3331)},
		"land": cfg.get("land", 1.0), "geared": cfg.get("geared", false),
		"cogs": mods.get("cogs", []), "ring_k": mods.get("ring_k", 1.0), "mods_land": mods.get("land", 1.0),
		"susp": mods.get("susp", {}),
		"runs": RUNS, "cols": COLS, "dt": DT,
	}
	var f := FileAccess.open(out.path_join("config.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(conf, "  ", false, true))
	f.close()
	for r in RUNS:
		_run(r, cfg, extras, out)
	print("PORT_TRACE wrote %d runs to %s" % [RUNS.size(), ProjectSettings.globalize_path(out)])
	get_tree().quit(0)

## a float as text that reads back exactly (GDScript has no %g)
static func _num(v) -> String:
	return JSON.stringify(float(v), "", false, true)

func _write_ride(path: String, tune, cfg: Dictionary) -> void:
	var lines := PackedStringArray()
	lines.append("bike=dh")
	lines.append("land=" + _num(cfg.get("land", 1.0)))
	lines.append("geared=%d" % (1 if cfg.get("geared", false) else 0))
	var mods: Dictionary = cfg.get("mods", {})
	if mods.has("cogs"):
		var cs := PackedStringArray()
		for c in mods.cogs: cs.append(_num(c))
		lines.append("cogs=" + ",".join(cs))
		lines.append("ring_k=" + _num(mods.get("ring_k", 1.0)))
		lines.append("mods_land=" + _num(mods.get("land", 1.0)))
	var su: Dictionary = mods.get("susp", {})
	for e in ["f", "r"]:
		if su.has(e):
			for k in ["travel", "sag", "prog", "zc", "zr", "hs", "fric", "bump"]:
				lines.append("susp.%s.%s=" % [e, k] + _num(su[e][k]))
	for k in ["psi_f", "psi_r"]:
		if su.has(k): lines.append("susp.%s=" % k + _num(su[k]))
	var keys: Array = tune.v.keys()
	keys.sort()
	for k in keys: lines.append("tune.%s=" % k + _num(tune.v[k]))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("PORT_TRACE ride config: %d lines -> %s" % [lines.size(), path])

func _inp(script: String, t: float) -> Dictionary:
	var i := {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false, "body_fwd": 0.0, "body_lean": 0.0, "pad": false}
	match script:
		"pedal": i.throttle = 1.0
		"brake": i.brake = 1.0 if t > 1.0 else 0.0
		"turn": i.throttle = 0.4; i.steer = 0.5 if t > 1.0 else 0.0
		"swaps": i.throttle = 0.3; i.steer = 0.7 * sin(TAU * t / 1.6) if t > 0.5 else 0.0
		"pump": i.hop = fmod(t, 1.0) < 0.45
		"hop": i.hop = (t > 1.0 and t < 1.35) or (t > 2.5 and t < 2.8)
		"manual": i.body_fwd = -0.75 if (t > 1.0 and t < 3.0) else 0.0; i.pad = true
		"sprint": i.throttle = 1.0; i.sprint = t > 0.5
	return i

func _run(r: Array, cfg: Dictionary, extras: Dictionary, out: String) -> void:
	var h = SS.Host.new()
	h.terrain.kind = r[1]; h.terrain.a = r[2]; h.terrain.b = r[3]; h.terrain.x0 = r[4]
	var p := BikePhysics.new(h); h.phys = p
	p.T = get_node("/root/Tune").v
	p.setup(extras, cfg)
	p.reset_at(0.0, 0.0, 0.0)
	p.v = r[5]
	var f := FileAccess.open(out.path_join(str(r[0]) + ".csv"), FileAccess.WRITE)
	f.store_line(",".join(COLS))
	var n := int(float(r[6]) / DT)
	for i in n:
		var t := i * DT
		p.step(DT, _inp(r[7], t))
		var row := PackedStringArray()
		for c in COLS:
			match c:
				"t": row.append("%.5f" % (t + DT))
				"air": row.append("1" if p.air else "0")
				"crash": row.append("1" if p.crash_on else "0")
				_: row.append("%.10f" % float(p.get(c)))
		f.store_line(",".join(row))
		if not p.is_sane(): break
	f.close()
