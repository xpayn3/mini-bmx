class_name PlaygroundSuite
extends Node
## The playground's baseline suite (tests): the test rider rides a fixed list of features at fixed speeds (pump and
## AUTO off: the physics alone, the same inputs every time), one run each, and every result is written down:
## jumps (lip speed / angle, air, distance, where it landed, pitch at touch-down, result), brake strips (stopping
## distance, decel, locks), the slalom (time, cones), and for every run the suspension (deepest travel, bottom-outs)
## and the lab's physics checks.
##   BMX_PG_SUITE=save     writes it to godot/tools/pg_baseline.json (keep it in git: it is the reference)
##   BMX_PG_SUITE=compare  rides the same list and prints every number that moved past its tolerance against the
##                         saved one (`PGBASE` lines, ⚠ on results that got worse), then `PGBASE SUMMARY`
## Run (minimised, ~3 min): BMX_MIN=1 BMX_LEVEL=playground BMX_STRAIGHT=1 BMX_PG_SUITE=compare + --autotest=400
## Quits by itself when done. BMX_PG_SUITE_ONLY=<part of an id> rides only the matching runs.

const FILE := "res://tools/pg_baseline.json"
const RUNS := [
	["table_1", 30], ["table_1.5", 34], ["table_2", 36], ["gap_5", 34], ["gap_7", 38],
	["hop_0.4", 24], ["hop_0.8", 30], ["drop_1", 24], ["drop_2", 28], ["stepup_1", 30],
	["roller_0.6", 26], ["pump_0.8", 24], ["curb_0.2", 20], ["slope_20", 25], ["camber_20", 20],
	["stepdown_1", 30], ["dropland_1.5", 26], ["hip_20", 32],
	["brake_dirt", 30], ["brake_dirt_front", 30], ["brake_dirt_rear", 30], ["brake_wet", 30], ["brake_sand", 30],
	["slalom_8", 22],
]
## how far a number may move before it's reported (anything not listed: 2 %)
const TOL := {"lip": 1.0, "ang": 1.5, "air": 0.05, "dist": 0.3, "pitch_err": 3.0, "maxF": 5.0, "maxR": 5.0,
	"bot": 0.5, "brake_dist": 0.3, "decel": 0.3, "time": 0.1, "checks": 0.5, "v_out": 1.0, "v_min": 1.0}

var game
var mode := ""
var list: Array = []
var i := -1
var results := {}
var _runs0 := 0
var _jumps0 := 0
var _tests0 := 0
var _checks0 := {}
var _wait := 0.0
var _started := false


func setup(g) -> void:
	game = g
	mode = Env.s("BMX_PG_SUITE")
	var only := Env.s("BMX_PG_SUITE_ONLY")
	for r in RUNS:
		if only == "" or str(r[0]).contains(only): list.append(r)
	print("PGSUITE %s: %d runs" % [mode, list.size()])


func _process(dt: float) -> void:
	if game == null or game.level_probe == null: return
	_wait += dt
	if not _started:
		if _wait < 1.0: return   # (the world settles)
		_started = true
		_next()
		return
	var pl = game.demo
	if not (pl is PlaygroundPilot): return
	if pl.runs != _runs0 or _wait > 40.0:   # it was put back = that run is over (or it never finished)
		_collect(_wait > 40.0)
		_next()


func _next() -> void:
	i += 1
	if i >= list.size():
		_finish(); return
	var r: Array = list[i]
	var f = game.level_probe.course.feature_by_id(r[0])
	if f == null:
		print("PGSUITE no feature %s" % r[0]); _next(); return
	if not (game.demo is PlaygroundPilot): game.set_demo(true)
	var pl: PlaygroundPilot = game.demo
	pl.auto = false; pl.pump = false; pl.mode = "feature"; pl.target = f
	pl.speed = float(r[1]) / 3.6
	game.diag.reset_stats()
	pl.restart(game)
	_runs0 = pl.runs
	_jumps0 = game.level_probe.jumps.size()
	_tests0 = game.level_probe.tests.size()
	_checks0 = game.lab.counts.duplicate() if game.lab else {}
	_wait = 0.0


func _collect(timed_out: bool) -> void:
	var r: Array = list[i]
	var key := "%s@%d" % [r[0], int(r[1])]
	var pr = game.level_probe
	var out := {}
	# the longest jump on this feature this run
	var best = null
	for k in range(_jumps0, pr.jumps.size()):
		var j: Dictionary = pr.jumps[k]
		if j.feat == r[0] and (best == null or float(j.t) > float(best.t)): best = j
	if best != null:
		out.lip = best.lip; out.ang = best.ang; out.air = best.t; out.dist = best.get("dist", 0.0)
		out.land = best.get("spot", "?"); out.pitch_err = best.get("pitch_err", 0.0); out.result = best.result
	for k in range(_tests0, pr.tests.size()):
		var t: Dictionary = pr.tests[k]
		if t.feat != r[0]: continue
		if t.has("dist"):
			out.brake_dist = t.dist; out.decel = t.v / maxf(float(t.t), 0.01); out.result = t.result
			out.lock_f = t.lock_f; out.lock_r = t.lock_r
		else:
			out.time = t.t; out.v_min = t.vmin * 3.6; out.v_out = t.v_out * 3.6; out.cones_ok = t.ok; out.result = "DONE"
	var st: Dictionary = game.diag.st
	out.maxF = st.maxF * 100.0; out.maxR = st.maxR * 100.0; out.bot = st.botF + st.botR
	var checks := 0
	var lab = game.lab
	if lab:
		for k in lab.counts: checks += int(lab.counts[k]) - int(_checks0.get(k, 0))
	out.checks = checks
	if not out.has("result"): out.result = "TIMEOUT" if timed_out else game.demo.ended if game.demo is PlaygroundPilot and game.demo.ended != "" else "NO_JUMP"
	if game.demo is PlaygroundPilot: out.ended = game.demo.ended
	if game.demo is PlaygroundPilot: game.demo.ended = ""
	results[key] = out
	print("PGSUITE run %s %s" % [key, JSON.stringify(out)])


func _finish() -> void:
	var path := ProjectSettings.globalize_path(FILE)
	if mode == "save":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"saved": Time.get_datetime_string_from_system(), "runs": results}, "\t"))
			f.close()
		print("PGSUITE saved %d runs to %s" % [results.size(), path])
	else:
		_compare(path)
	GameState.quit()


func _compare(path: String) -> void:
	if not FileAccess.file_exists(path):
		print("PGBASE no baseline at %s (run BMX_PG_SUITE=save first)" % path); return
	var base = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (base is Dictionary) or not base.has("runs"):
		print("PGBASE baseline unreadable"); return
	var b: Dictionary = base.runs
	var changed := 0
	var worse := 0
	for key in results:
		if not b.has(key):
			print("PGBASE %s new run (not in the baseline)" % key); continue
		var o: Dictionary = b[key]
		var n: Dictionary = results[key]
		var line := ""
		for m in n:
			if not o.has(m): continue
			var a = o[m]; var c = n[m]
			if typeof(c) == TYPE_STRING or typeof(a) == TYPE_STRING:
				if str(a) != str(c):
					var bad: bool = _good(str(a)) and not _good(str(c))
					line += "  %s %s -> %s%s" % [m, str(a), str(c), " ⚠" if bad else ""]
					if bad: worse += 1
			else:
				var tol: float = TOL.get(m, absf(float(a)) * 0.02 + 0.01)
				if absf(float(c) - float(a)) > tol:
					var bad: bool = m in ["bot", "checks"] and float(c) > float(a)
					line += "  %s %.2f -> %.2f (%+.2f)%s" % [m, float(a), float(c), float(c) - float(a), " ⚠" if bad else ""]
					if bad: worse += 1
		if line != "":
			changed += 1
			print("PGBASE %s%s" % [key, line])
	print("PGBASE SUMMARY runs=%d changed=%d worse=%d (baseline %s)" % [results.size(), changed, worse, str(base.get("saved", "?"))])


static func _good(result: String) -> bool:
	return result in ["CLEAN", "PERFECT", "STOP", "DONE", "OVER", "STOPPED"]
