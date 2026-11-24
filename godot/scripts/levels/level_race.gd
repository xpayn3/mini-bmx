class_name LevelRace
extends CanvasLayer
## Race timing on a built level (LevelTerrain, its BmxGate pieces): the clock starts as the rider goes through the
## start gate (or at the start when the level has none), every checkpoint gives a split against the best run's, the
## finish stops it and keeps the best time + splits per level and bike (user://level_times.cfg; never in test runs).
## A small timer shows top centre while a run is on. Back to start (Backspace) resets it; the bail tap doesn't.
## Test: BMX_RACE_PROBE=1 prints RACE lines.

const FILE := "user://level_times.cfg"

var game
var lf: LevelField
var key := ""
var running := false
var done := false
var t := 0.0
var _gates: Array = []         # [{gate, pos, dir, span, i}] sorted down the trail: start?, checkpoints, finish?
var _next := 0                 # index of the next gate to pass
var _prev := Vector2(INF, INF)
var _splits := PackedFloat32Array()
var _missed := 0               # checkpoints skipped this run (no best time then)
var _best := INF
var _best_splits := PackedFloat32Array()
var _label: Label
var _probe := false


func setup(g, field: LevelField, level_path: String) -> void:
	game = g
	lf = field
	_probe = Env.s("BMX_RACE_PROBE") != ""
	key = "%s|%s" % [level_path, str(GameState.bike_id)]
	_gates = lf.gates.duplicate()
	_gates.sort_custom(func(a, b): return _order(a) < _order(b))
	var cf := ConfigFile.new()
	if cf.load(FILE) == OK:
		_best = float(cf.get_value("best", key, INF))
		_best_splits = PackedFloat32Array(cf.get_value("splits", key, []))
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-120, 18)
	_label.size = Vector2(240, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UITheme.lcd_font())
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 8)
	add_child(_label)
	reset()


## start < checkpoints (by where they are down the trail) < finish
func _order(g: Dictionary) -> float:
	var base := float(g.i) if int(g.i) >= 0 else 0.0
	if g.gate == "start": return -1e9 + base
	if g.gate == "finish": return 1e9 + base
	return base


var practice := false   # started mid-level (the editor's "Ride from selected"): no timing

func reset() -> void:
	running = false; done = false; t = 0.0; _splits = PackedFloat32Array(); _prev = Vector2(INF, INF); _missed = 0
	_next = 0
	practice = game.terrain is LevelTerrain and game.terrain.practice_at.x != INF
	if practice:
		_show(); return
	if _gates.is_empty() or _gates[0].gate != "start":
		running = true   # (no start gate: the clock runs from the start)
	_show()


func _physics_process(dt: float) -> void:
	if game == null or game.phys == null: return
	var ph = game.phys
	var p := Vector2(ph.x, ph.z)
	if running and not done: t += dt   # (a crash costs time: the clock runs on)
	if not practice and _prev.x != INF and _next < _gates.size():
		# the next gate, or any later one (a checkpoint ridden past outside its span, or on a line that doesn't go
		# through it, mustn't stop the finish from counting): the ones jumped over are missed
		for gi in range(_next, _gates.size()):
			var g: Dictionary = _gates[gi]
			if g.gate == "start" and gi != _next: continue
			if _crossed(g, _prev, p):
				for q in range(_next, gi):
					if _gates[q].gate == "checkpoint": _missed += 1
				_next = gi
				_pass(g)
				break
	_prev = p
	_show()


func _crossed(g: Dictionary, a: Vector2, b: Vector2) -> bool:
	var pos: Vector2 = g.pos; var dir: Vector2 = g.dir
	var da := (a - pos).dot(dir); var db := (b - pos).dot(dir)
	if not (da < 0.0 and db >= 0.0): return false
	var side := Vector2(-dir.y, dir.x)
	return absf((b - pos).dot(side)) <= float(g.span) * 0.5 + 0.5


func _pass(g: Dictionary) -> void:
	_next += 1
	match str(g.gate):
		"start":
			running = true; t = 0.0
			_say("GO!")
		"checkpoint":
			var n := _splits.size()
			_splits.append(t)
			var msg := "CHECKPOINT %d  %s" % [n + 1, _fmt(t)]
			if n < _best_splits.size(): msg += "  (%s)" % _diff(t - _best_splits[n])
			_say(msg)
		"finish":
			done = true
			var msg := "FINISH  %s" % _fmt(t)
			if _missed > 0:
				msg += "  (%d checkpoint%s missed: no best time)" % [_missed, "" if _missed == 1 else "s"]
			elif t < _best:
				if _best < INF: msg += "  NEW BEST (%s)" % _diff(t - _best)
				else: msg += "  NEW BEST"
				_best = t; _best_splits = _splits.duplicate()
				_save()
			else:
				msg += "  (best %s, %s)" % [_fmt(_best), _diff(t - _best)]
			_say(msg)
	if _probe: print("RACE %s t=%.2f next=%d" % [g.gate, t, _next])


func _save() -> void:
	var st = get_node_or_null("/root/Settings")
	if st != null and st._no_save: return
	var cf := ConfigFile.new()
	cf.load(FILE)
	cf.set_value("best", key, _best)
	cf.set_value("splits", key, Array(_best_splits))
	cf.save(FILE)


func _say(s: String) -> void:
	if game.has_method("flash"): game.flash(s)


func _show() -> void:
	if _label == null: return
	var hud_on: bool = game.hud == null or game.hud.visible
	_label.visible = hud_on and (practice or running or done or not _gates.is_empty())
	_label.text = "PRACTICE" if practice else (_fmt(t) if (running or done) else "START AT THE GATE")
	_label.modulate = Color(0.55, 1.0, 0.55) if done else Color(1, 1, 1)


static func _fmt(s: float) -> String:
	var m := int(s / 60.0)
	return "%d:%05.2f" % [m, s - m * 60.0]


static func _diff(d: float) -> String:
	return ("+" if d >= 0.0 else "-") + "%.2f" % absf(d)
