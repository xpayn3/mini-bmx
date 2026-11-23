class_name RideDiag
extends CanvasLayer
## The test playground's developer view (only there: Game makes it for a PlaygroundTerrain, nowhere else):
## live graphs of everything the ride physics does (right, F4) + the tuning card with every slider docked on the
## left (P / ✕), the ride in between, for debugging riding code and trying ride feel. Recorded every physics step (120 Hz) into a 20 s ring
## (`buf`, one flat array: sample * C + channel), so the graphs show exactly what the physics computed, step by step.
## Pages (F5 / Shift+F5, or click a tab):
##   OVERVIEW    speed, both suspensions, tyre loads, steer / lean, sticks
##   SUSPENSION  fork + shock (the physics' two ends) and the rider's legs: travel gauges with sag line, an O-ring at
##               the deepest travel used, bottom-outs, damper blow-offs; travel / shock speed / force / tyre squash
##               / legs graphs; travel + shock-speed histograms (like a real suspension telemetry tool); the drawn
##               linkage (Suspension: fork lowers, four-bar, shock stroke) next to the physics
##   INPUT       both sticks raw from the pad (dot + 1 s trail) and what the game made of them (deadzone, axis fade,
##               square gate, steer curve), triggers raw vs used, every button / riding action lit, input graphs
##   TYRES       tyre loads + contact, rear grip / front use against their limits, slide, turn force, brakes and
##               locks, loose ground, the crash judge's trouble meters
##   BODY        lean (asked / bike / body counter), bars, pitch against the ground, body fore / aft, legs, manual
##   AIR         side view of the last jump (bike drawn every 0.1 s over the ground it flew over), height, vy,
##               pitch against the slope, spin, stick
## Keys while it's up: F4 size (panel / full screen / off), F5 page, F6 freeze, F7 time window (3 / 6 / 12 / 20 s),
## F9 reset the stats (O-rings, counters, histograms). The mouse over a graph reads every graph at that moment.
## Tests: BMX_DIAG=<page name or number> opens it (BMX_DIAG_FULL=1 full screen), BMX_DIAG_PROBE=1 prints DIAG
## summary lines at the end (suspension use, histograms, inputs).

const HZ := 120.0
const RING := 2400                 # 20 s
const PAGES := ["OVERVIEW", "SUSPENSION", "INPUT", "TYRES", "BODY", "AIR", "ENERGY"]
const WINDOWS := [3.0, 6.0, 12.0, 20.0]
const CH := [
	"v", "slope",
	"xF", "xR", "dxF", "dxR", "vF", "vR", "fF", "fR", "tyF", "tyR", "sqF", "sqR",
	"botF", "botR", "blowF", "blowR", "cF", "cR", "leg", "legf", "nF", "nR",
	"lx", "ly", "rx", "ry", "lt", "rt",
	"steer", "bfwd", "blean", "thr", "brk", "brkf", "brkr", "hop", "sprint",
	"steer_in", "bars", "flick",
	"grip_r", "front_use", "slip", "slip_w", "lat_a", "brake_f", "brake_r", "rlock", "flock", "loose", "risk",
	"lean", "bike_lean", "counter", "pitch", "g_pitch", "body_x", "hip", "compress", "man_a", "nose_a", "roll_hip", "roll_chest",
	"hgt", "vy", "air", "air_w", "air_tilt", "flip_in",
	"energy", "e_kin", "free",
]
const HB := 20                     # travel histogram bins (0..100 %)
const VB := 30                     # shock speed histogram bins (-3..3 m/s)

var game
var C := CH.size()
var ci := {}                       # channel name -> index
var buf := PackedFloat32Array()
var head := 0                      # next slot to write
var count := 0                     # samples in the ring
var serial := 0                    # samples ever recorded
var events: Array = []             # [serial, text, colour]
var page := 0
var size_mode := 0                 # 0 off, 1 panel, 2 full screen
var win := 6.0
var frozen := false
var view: DiagView

# stats since the last reset (F9)
var st := {}
var hist_xF := PackedFloat32Array(); var hist_xR := PackedFloat32Array()
var hist_vF := PackedFloat32Array(); var hist_vR := PackedFloat32Array()
var _prev := {}

# jumps (side view)
var jump_live: Array = []          # [dist, y, pitch, ground] per step of the jump in progress
var jump_last: Array = []
var jump_last_info := ""
var _j0 := Vector3.ZERO            # take-off point + heading
var _jh := 0.0
var _jt := 0.0
var _probe := Env.s("BMX_DIAG_PROBE") != ""
var _raw_dev := -1
var _stroke_full := -1.0          # the drawn linkage's full shock stroke (m), worked out once
var lab: PlaygroundLab
var always := false                # record while hidden too (playground, BMX_DIAG): stats + histograms from the start


func _init() -> void:
	for i in C: ci[CH[i]] = i
	buf.resize(RING * C)
	layer = 4
	reset_stats()


func setup(g) -> void:
	game = g
	view = DiagView.new()
	view.d = self
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	var e := Env.s("BMX_DIAG")
	if e == "off": size_mode = 0   # tests: graphs off (clean shots)
	elif e != "":
		size_mode = 2 if Env.s("BMX_DIAG_FULL") != "" else 1
		if e.is_valid_int(): page = clampi(int(e), 0, PAGES.size() - 1)
		else:
			for k in PAGES.size():
				if (PAGES[k] as String).begins_with(e.to_upper()): page = k; break
	else:
		size_mode = 1
	always = true
	# the Debug Draw 3D overlay (F3) on from the start here, without its text block (the graphs have all of it)
	if DebugOverlay.available() and Env.s("BMX_DEBUG_DRAW") != "0":
		DebugOverlay.on = true
	DebugOverlay.text_on = false
	lab = PlaygroundLab.new()
	lab.name = "Lab"
	add_child(lab)
	lab.setup(g, self)
	g.lab = lab
	if Env.s("BMX_PG_SUITE") != "":   # tests: the baseline suite (levels/playground_suite.gd)
		var su := PlaygroundSuite.new()
		su.name = "Suite"
		add_child(su)
		su.setup(g)
	_build_bar()
	_build_bar2()
	ramps = RampEditor.new()
	ramps.name = "RampEditor"
	ramps.visible = Env.s("BMX_PG_RAMPS_OPEN") != "" or Env.s("BMX_PG_RAMP_ADD") != ""
	add_child(ramps)
	ramps.setup(g, self)
	_ramps_b.set_pressed_no_signal(ramps.visible)
	_layout()
	if Env.s("BMX_PG_PILOT") != "":   # tests: the test rider starts on BMX_PG_AT (or the first feature)
		pilot_start.call_deferred(Env.s("BMX_PG_AT"))


func reset_stats() -> void:
	st = {"maxF": 0.0, "maxR": 0.0, "botF": 0, "botR": 0, "blowF": 0, "blowR": 0, "sumF": 0.0, "sumR": 0.0,
		"n": 0, "air_t": 0.0, "maxvF": 0.0, "maxvR": 0.0, "minvF": 0.0, "minvR": 0.0, "maxleg": 0.0, "minleg": 0.0,
		"maxload": 0.0, "t": 0.0, "dmaxF": 0.0, "dmaxR": 0.0}
	hist_xF.resize(HB); hist_xF.fill(0.0); hist_xR.resize(HB); hist_xR.fill(0.0)
	hist_vF.resize(VB); hist_vF.fill(0.0); hist_vR.resize(VB); hist_vR.fill(0.0)


func on() -> bool:
	return size_mode > 0


## raw pad: the first connected pad (test runs read it too; it's display only)
func _pad() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if pads.size() > 0 else -1


## after every physics step (Game._physics_process): inp = what the physics got this step
func record(dt: float, inp: Dictionary) -> void:
	if frozen or game == null or not (always or size_mode > 0): return
	var ph = game.phys
	var T: Dictionary = ph.T
	var G := 9.81
	var tr: float = maxf(0.01, ph.dg_travel)
	var su = game.susp
	var dxF := 0.0
	var dxR := 0.0
	if su != null:
		if su.has_f and su.F["max"] > su.F["min"]: dxF = (su.xF - su.F["min"]) / (su.F["max"] - su.F["min"])
		if su.has_r and su.R["max"] > su.R["min"]: dxR = (su.xR - su.R["min"]) / (su.R["max"] - su.R["min"])
	_raw_dev = _pad()
	var lx := 0.0; var ly := 0.0; var rx := 0.0; var ry := 0.0; var lt := 0.0; var rt := 0.0
	if _raw_dev >= 0:
		lx = Input.get_joy_axis(_raw_dev, JOY_AXIS_LEFT_X); ly = Input.get_joy_axis(_raw_dev, JOY_AXIS_LEFT_Y)
		rx = Input.get_joy_axis(_raw_dev, JOY_AXIS_RIGHT_X); ry = Input.get_joy_axis(_raw_dev, JOY_AXIS_RIGHT_Y)
		lt = Input.get_joy_axis(_raw_dev, JOY_AXIS_TRIGGER_LEFT); rt = Input.get_joy_axis(_raw_dev, JOY_AXIS_TRIGGER_RIGHT)
	else:   # no pad: the keys as a stick (what the actions read)
		lx = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		rx = Input.get_action_strength("body_right") - Input.get_action_strength("body_left")
		ry = Input.get_action_strength("body_back") - Input.get_action_strength("body_fwd")
		lt = Input.get_action_strength("brake"); rt = Input.get_action_strength("pedal")
	var gy: float = game.terrain.height(ph.x, ph.z)
	# energy per kg: ½ speed² (+ the climb speed in the air) + g height, from the last reset (the lab's e0)
	var vt: float = ph.v * ph.v + (ph.vy * ph.vy if ph.air else 0.0)
	var en: float = 0.5 * vt + 9.81 * ph.y
	var e0v: float = lab.e0 if lab != null and is_finite(lab.e0) else en
	var vals := [
		ph.v * 3.6, rad_to_deg(_f(ph._g_pitch)),
		ph.dg_xF / tr, ph.dg_xR / tr, dxF, dxR, ph.dg_vF, ph.dg_vR, ph.dg_fF / G, ph.dg_fR / G, ph.dg_tyF / G, ph.dg_tyR / G,
		ph.dg_sqF * 100.0, ph.dg_sqR * 100.0,
		_b(ph.dg_botF), _b(ph.dg_botR), _b(ph.dg_blowF), _b(ph.dg_blowR), _b(ph.dg_cF), _b(ph.dg_cR), ph.dg_leg, ph.dg_leg_f / G,
		_f(ph.n_f) / G, _f(ph.n_r) / G,
		lx, ly, rx, ry, lt, rt,
		_f(inp.get("steer", 0.0)), _f(inp.get("body_fwd", 0.0)), _f(inp.get("body_lean", 0.0)), _f(inp.get("throttle", 0.0)),
		_f(inp.get("brake", 0.0)), _f(inp.get("brake_front", 0.0)), _f(inp.get("brake_rear", 0.0)), _b(inp.get("hop", false)), _b(inp.get("sprint", false)),
		ph.steer_in, ph.steer, ph.flick,
		ph.grip_r, ph.front_use, rad_to_deg(ph.slip), ph.slip_w, ph.lat_a, ph.brake_f, ph.brake_r, ph.rear_lock, ph.front_lock, ph.loose, ph.risk,
		rad_to_deg(ph.lean), rad_to_deg(ph.bike_lean), rad_to_deg(ph.counter), rad_to_deg(ph.pitch), rad_to_deg(_f(ph._g_pitch)), ph.body_x, ph.hip_shift, ph.compress, rad_to_deg(ph.man_a), rad_to_deg(ph.nose_a),
		rad_to_deg(_f(game.rider.roll_p)) if game.rider != null else 0.0, rad_to_deg(_f(game.rider.roll_c)) if game.rider != null else 0.0,   # the rider's own roll (hips / chest follow the bike on springs)
		ph.y - gy, ph.vy, _b(ph.air), ph.air_w, rad_to_deg(ph.air_tilt), ph.flip_in,
		en - e0v, 0.5 * vt, _b(lab.free if lab != null else _free(inp, ph)),
	]
	var base := head * C
	for i in C:
		var x: float = vals[i]
		buf[base + i] = x if is_finite(x) else 0.0
	head = (head + 1) % RING
	count = mini(count + 1, RING)
	serial += 1
	_stats(dt, ph, tr)
	_events(ph)
	_jump(dt, ph, gy)


## nothing put energy in this step (no pedal, sprint, hop / pump, body stick forward)
static func _free(inp: Dictionary, ph) -> bool:
	return not ph.crash_on and _f(inp.get("throttle", 0.0)) < 0.02 and not inp.get("sprint", false) \
		and not inp.get("hop", false) and absf(_f(inp.get("body_fwd", 0.0))) < 0.05


static func _f(x) -> float:
	if x == null: return 0.0
	var f := float(x)
	return f if is_finite(f) else 0.0

static func _b(x) -> float:
	return 1.0 if x else 0.0


func _stats(dt: float, ph, tr: float) -> void:
	st.t += dt
	var xF: float = ph.dg_xF / tr
	var xR: float = ph.dg_xR / tr
	if ph.air:
		st.air_t += dt
	else:
		st.maxF = maxf(st.maxF, xF); st.maxR = maxf(st.maxR, xR)
		st.sumF += xF; st.sumR += xR; st.n += 1
		hist_xF[clampi(int(xF * HB), 0, HB - 1)] += dt
		hist_xR[clampi(int(xR * HB), 0, HB - 1)] += dt
		hist_vF[clampi(int((ph.dg_vF + 3.0) / 6.0 * VB), 0, VB - 1)] += dt
		hist_vR[clampi(int((ph.dg_vR + 3.0) / 6.0 * VB), 0, VB - 1)] += dt
		st.maxvF = maxf(st.maxvF, ph.dg_vF); st.minvF = minf(st.minvF, ph.dg_vF)
		st.maxvR = maxf(st.maxvR, ph.dg_vR); st.minvR = minf(st.minvR, ph.dg_vR)
		st.maxleg = maxf(st.maxleg, ph.dg_leg); st.minleg = minf(st.minleg, ph.dg_leg)
		st.maxload = maxf(st.maxload, (ph.dg_tyF + ph.dg_tyR) / 9.81)
	var su = game.susp
	if su != null:
		st.dmaxF = maxf(st.dmaxF, val(ci.dxF)); st.dmaxR = maxf(st.dmaxR, val(ci.dxR))
	for k in ["botF", "botR", "blowF", "blowR"]:
		var now: bool = ph.get("dg_" + k)
		if now and not _prev.get(k, false): st[k] += 1
		_prev[k] = now


func _event(text: String, col: Color) -> void:
	events.append([serial, text, col])
	if events.size() > 60: events.pop_front()


func _events(ph) -> void:
	var a: bool = ph.air
	if a and not _prev.get("air", false): _event("TAKE-OFF", Color(0.6, 0.9, 1.0))
	if not a and _prev.get("air", false): _event("LAND", Color(0.6, 1.0, 0.6))
	if ph.dg_botF and not _prev.get("ebF", false): _event("BOTTOM F", Color(1, 0.3, 0.2))
	if ph.dg_botR and not _prev.get("ebR", false): _event("BOTTOM R", Color(1, 0.3, 0.2))
	_prev.air = a; _prev.ebF = ph.dg_botF; _prev.ebR = ph.dg_botR


func on_crash(reason: String) -> void:
	_event("CRASH " + reason, Color(1, 0.2, 0.6))
	if not jump_live.is_empty():
		jump_last = jump_live; jump_live = []
		jump_last_info = "crashed: " + reason


func _jump(dt: float, ph, gy: float) -> void:
	if ph.air and jump_live.is_empty():
		_j0 = Vector3(ph.x, ph.y, ph.z); _jh = ph.heading; _jt = 0.0
	var fw := Vector2(cos(_jh), -sin(_jh))
	if ph.air or (not jump_live.is_empty() and _jt < 0.6):
		var d := Vector2(ph.x - _j0.x, ph.z - _j0.z).dot(fw)
		jump_live.append([d, ph.y, ph.pitch, gy])
		_jt = _jt + dt if not ph.air else 0.0
		if not ph.air and _jt >= 0.6 or jump_live.size() > 1500:
			_close_jump(ph)
	elif not ph.air:
		_jt = 0.0


func _close_jump(ph) -> void:
	var n := jump_live.size()
	var air_n := 0
	for p in jump_live:
		if p[1] - p[3] > 0.02: air_n += 1
	if n > 20:
		jump_last = jump_live
		var j0: Array = jump_live[0]
		var top := -INF
		for p in jump_live: top = maxf(top, p[1])
		jump_last_info = "%.1f m · air %.2f s · peak +%.2f m over take-off" % [jump_live[air_n - 1][0] if air_n > 0 else 0.0, air_n / HZ, top - j0[1]]
	jump_live = []


## value of channel ch, k samples back from the newest (0 = newest)
func val(ch: int, k := 0) -> float:
	if count == 0: return 0.0
	k = clampi(k, 0, count - 1)
	return buf[((head - 1 - k + RING) % RING) * C + ch]


func _layout() -> void:
	_lay = ""   # (re-done next frame by _dev_layout)
	if view: view.visible = size_mode > 0


# ---- the test rider bar: RIDE / STOP, which feature (dropdown), speed, pump, runs ---------------------------------
var bar: HBoxContainer
var _ride_b: Button
var _pick: OptionButton
var _kmh_l: Label
var _pump_c: Button
var _runs_l: Label
var _picks: Array = []             # per dropdown item: ["lane", lane id] / ["feature", feature id] / null (separator)
var _kmh := 30.0
var _cam_pick: OptionButton
var _auto_c: Button
var _cam_keys: Array = []

## the dev view's own small flat controls (the game's big menu buttons covered the graphs)
static func _dev_theme() -> Theme:
	var th := Theme.new()
	var mk := func(c: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new(); sb.bg_color = c
		sb.content_margin_left = 7; sb.content_margin_right = 7; sb.content_margin_top = 2; sb.content_margin_bottom = 2
		return sb
	for t in ["Button", "OptionButton", "CheckBox"]:
		th.set_stylebox("normal", t, mk.call(Color(1, 1, 1, 0.08)))
		th.set_stylebox("hover", t, mk.call(Color(1, 1, 1, 0.16)))
		th.set_stylebox("pressed", t, mk.call(Color(1.0, 0.88, 0.3, 0.9)))
		th.set_stylebox("hover_pressed", t, mk.call(Color(1.0, 0.92, 0.45, 0.95)))
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_stylebox("disabled", t, mk.call(Color(1, 1, 1, 0.04)))
		th.set_font_size("font_size", t, 12)
		th.set_color("font_color", t, Color(0.86, 0.9, 0.95))
		th.set_color("font_hover_color", t, Color(1, 1, 1))
		th.set_color("font_pressed_color", t, Color(0.05, 0.05, 0.05))
		th.set_color("font_hover_pressed_color", t, Color(0.05, 0.05, 0.05))
	th.set_font_size("font_size", "Label", 12)
	th.set_color("font_color", "Label", Color(0.86, 0.9, 0.95))
	th.set_font_size("font_size", "PopupMenu", 13)
	th.set_constant("h_separation", "CheckBox", 4)
	return th


func _dev_btn(parent: Control, text: String, cb: Callable, tip := "", toggle := false) -> Button:
	var b := Button.new()
	b.text = text; b.tooltip_text = tip; b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 22)
	if toggle: b.toggled.connect(func(_on): cb.call())
	else: b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_bar() -> void:
	bar = HBoxContainer.new()
	bar.theme = _dev_theme()
	bar.add_theme_constant_override("separation", 3)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)
	var t := Label.new(); t.text = "RIDER"; t.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	bar.add_child(t)
	_ride_b = _dev_btn(bar, "RIDE", func(): pilot_toggle(), "F2: the test rider rides the picked feature / lane on repeat")
	_ride_b.custom_minimum_size = Vector2(46, 22)
	_pick = OptionButton.new()
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.custom_minimum_size = Vector2(110, 22)
	_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pick.clip_text = true
	_pick.fit_to_longest_item = false   # (else it grows to its longest line and pushes the bar off the panel)
	var course: PlaygroundCourse = game.terrain.course
	for l in course.lanes:
		_pick.add_separator(l.title)
		_picks.append(null)
		_pick.add_item("%s · whole lane, on repeat" % l.title.capitalize())
		_picks.append(["lane", l.id])
		for f in l.feats:
			if str(f.id).begins_with("rollin"): continue
			_pick.add_item("   %s  [%s]" % [f.name, f.id])
			_picks.append(["feature", f.id])
	var first := Env.s("BMX_PG_AT") if Env.s("BMX_PG_AT") != "" else "table_1.5"
	_select(first)
	_pick.item_selected.connect(func(_i): pilot_start(""))   # picking a feature sends him to it at once
	bar.add_child(_pick)
	_dev_btn(bar, "-", func(): _set_kmh(_kmh - 2.0), "slower").custom_minimum_size = Vector2(22, 22)
	_kmh_l = Label.new()
	_kmh_l.custom_minimum_size = Vector2(62, 0)
	_kmh_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_kmh_l)
	_dev_btn(bar, "+", func(): _set_kmh(_kmh + 2.0), "faster").custom_minimum_size = Vector2(22, 22)
	_pump_c = _dev_btn(bar, "pump", func(): if game.demo is PlaygroundPilot: game.demo.pump = _pump_c.button_pressed,
		"he pumps the lips (hop held into them)", true)
	_pump_c.set_pressed_no_signal(Env.s("BMX_PG_PILOT_PUMP") != "0")
	_auto_c = _dev_btn(bar, "auto", func(): if game.demo is PlaygroundPilot: game.demo.auto = _auto_c.button_pressed,
		"jumps: ride at the speed the jump needs (learned run by run)", true)
	_auto_c.set_pressed_no_signal(Env.s("BMX_PG_PILOT_AUTO") != "0")
	_runs_l = Label.new()
	_runs_l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	bar.add_child(_runs_l)
	if Env.s("BMX_PG_PILOT_KMH") != "": _kmh = float(Env.s("BMX_PG_PILOT_KMH"))
	_set_kmh(_kmh)
	pilot_changed()


## the lab row: pause / one step / slow motion, record / replay / ghost, what the lab is doing
var bar2: HBoxContainer
var _pause_b: Button
var _slow_b: Button
var _rec_b: Button
var _ghost_c: Button
var _lab_l: Label
var _ramps_b: Button
var _air_b: Button
var ramps: RampEditor

func _build_bar2() -> void:
	bar2 = HBoxContainer.new()
	bar2.theme = _dev_theme()
	bar2.add_theme_constant_override("separation", 3)
	bar2.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar2)
	var t := Label.new(); t.text = "LAB"; t.add_theme_color_override("font_color", Color(1.0, 0.88, 0.3))
	bar2.add_child(t)
	_pause_b = _small("PAUSE", func(): lab.toggle_pause(), "G: pause / resume the physics")
	_small("STEP", func(): lab.step_once(), "N: one physics step (1/120 s)")
	_slow_b = _small("1x", func(): lab.cycle_slow(), "T: slow motion 1 / ½ / ¼ / ⅒")
	_rec_b = _small("REC", func(): lab.toggle_record(), "V: record the next run (inputs, path, graphs)")
	_small("REPLAY", func(): lab.start_replay(), "J: replay the saved run with its ghost")
	_air_b = _dev_btn(bar2, "AIR", func(): lab.toggle_air_hold(), "hold the bike in the air (gravity off): try the air controls / rotation as long as you like", true)
	_air_b.set_pressed_no_signal(lab.air_hold)
	_ramps_b = _dev_btn(bar2, "RAMPS", func(): ramps.visible = _ramps_b.button_pressed, "the ramp editor: jumps from the formula, put anywhere, every number a slider", true)
	_ghost_c = _dev_btn(bar2, "ghost", func(): lab.ghost = _ghost_c.button_pressed, "draw the replayed recording (bike + graphs)", true)
	_ghost_c.set_pressed_no_signal(true)
	_lab_l = Label.new()
	_lab_l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	_lab_l.clip_text = true
	_lab_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar2.add_child(_lab_l)


func _small(text: String, cb: Callable, tip: String) -> Button:
	return _dev_btn(bar2, text, cb, tip)


## the camera: the playground's side views first (CameraRig.LEVEL_PRESETS), then the normal ones (made on the first
## frame: Game makes its camera after this node)
func _build_cam_pick() -> void:
	_cam_pick = OptionButton.new()
	_cam_pick.theme = _dev_theme()
	_cam_pick.focus_mode = Control.FOCUS_NONE
	_cam_pick.fit_to_longest_item = false
	_cam_pick.tooltip_text = "Camera (C cycles)"
	for k in game.cam.presets().keys():
		_cam_pick.add_item("CAM  " + str(game.cam.presets()[k].label))
		_cam_keys.append(k)
	_cam_pick.item_selected.connect(func(i): game.cam.set_mode(_cam_keys[i]))
	add_child(_cam_pick)
	_lay = ""


func _select(id: String) -> void:
	for i in _picks.size():
		var p = _picks[i]
		if p != null and p[1] == id:
			_pick.select(i); return
	for i in _picks.size():
		if _picks[i] != null: _pick.select(i); return


func _set_kmh(k: float) -> void:
	if game.demo is PlaygroundPilot:   # (auto: nudges the learned speed of the jump he's on)
		var pl: PlaygroundPilot = game.demo
		pl.set_kmh(pl.kmh() + (k - _kmh) if pl._auto_on(pl.cur) else k)
		if not pl._auto_on(pl.cur): _kmh = clampf(k, 6.0, 70.0)
	else:
		_kmh = clampf(k, 6.0, 70.0)
	_kmh_l.text = "%.0f km/h" % _kmh


## RIDE / STOP
func pilot_toggle() -> void:
	if game.demo is PlaygroundPilot: game.set_demo(false)
	else: pilot_start("")


## the test rider on the picked feature / lane (id = pick that one first), from the start of it
func pilot_start(id: String) -> void:
	if id != "": _select(id)
	var p = _picks[_pick.selected] if _pick.selected >= 0 else null
	if p == null: return
	if not (game.demo is PlaygroundPilot):
		game.set_demo(false)
		game.set_demo(true)
	var pl: PlaygroundPilot = game.demo
	pl.speed = _kmh / 3.6
	pl.auto = _auto_c.button_pressed
	pl.pump = _pump_c.button_pressed
	var course: PlaygroundCourse = game.terrain.course
	if p[0] == "lane":
		pl.mode = "lane"; pl._lane = course.lane_by_id(p[1]); pl.target = null
	else:
		pl.mode = "feature"; pl.target = course.feature_by_id(p[1])
	pl.restart(game)
	pl.runs = 0
	pilot_changed()


## the test rider on a ramp placed with the ramp editor (on repeat, from 30 m before it)
func pilot_ramp(id: String) -> void:
	if not (game.demo is PlaygroundPilot):
		game.set_demo(false)
		game.set_demo(true)
	var pl: PlaygroundPilot = game.demo
	pl.speed = _kmh / 3.6
	pl.auto = _auto_c.button_pressed
	pl.pump = _pump_c.button_pressed
	pl.mode = "feature"; pl.target = game.terrain.course.feature_by_id(id)
	pl.restart(game)
	pl.runs = 0
	pilot_changed()


## Game.set_demo calls this: the bar follows
func pilot_changed() -> void:
	if _ride_b == null: return
	var on: bool = game.demo is PlaygroundPilot
	_ride_b.text = "STOP" if on else "RIDE"
	_ride_b.modulate = Color(1, 0.55, 0.5) if on else Color(0.6, 1, 0.6)


## the dev view's screen: tuning card left (when open), graphs right (panel) or everything right of the card (full),
## the HUD squeezed in between (its left items right of the card, its right column left of the graphs)
const BAND := 0.46                 # the graph band's share of the screen height (panel mode)
var ride_rect := Rect2()           # the screen left for the ride (the camera frames the bike in it)
var _dev_on := false
var _lay := ""
var _card_opened := false
var _full_on := false
var left_w := 0.0

func _dev_layout() -> void:
	var hud = game.hud if game else null
	if hud == null or not hud.has_method("dev_mode"): return
	if not _card_opened:   # the sliders come up with the level (BMX_DEV_CARD=0: not)
		_card_opened = true
		hud.card_left = true
		if Env.s("BMX_DEV_CARD") != "0": hud._toggle_side("tune")
	var card_on: bool = hud.card != null and hud.card.visible
	var vp := view.get_viewport_rect().size   # the real canvas: wider than 1600 when the window isn't 16:9
	var key := "%d %s %s" % [size_mode, card_on, vp]
	if key == _lay: return
	_lay = key
	if not _dev_on:
		hud.dev_mode(true); _dev_on = true
		for fb in get_tree().get_nodes_in_group(&"fullscreen_button"): fb.set("visible", false)   # (a CanvasLayer; F11 still works)
	left_w = hud.dev_card_w() + (4.0 if card_on else 0.0)
	# the graphs: a band along the bottom (panel) or everything beside the tuning column (full screen); the ride above
	if size_mode == 2:
		view.position = Vector2(left_w + 4, 4); view.size = Vector2(vp.x - left_w - 8, vp.y - 8)
	else:
		var bh := roundf(vp.y * BAND)
		view.position = Vector2(left_w + 4, vp.y - bh - 4); view.size = Vector2(vp.x - left_w - 8, bh)
	ride_rect = Rect2(left_w, 0, vp.x - left_w, (view.position.y if size_mode == 1 else vp.y))
	view.queue_redraw()
	if _cam_pick == null: _lay = ""; return
	# the header: tabs + hints + camera on the first line, the RIDER and LAB rows side by side on the second
	var hx: float = view.position.x + 8
	var hw: float = view.size.x - 16
	if size_mode > 0:
		var half := (hw - 8) * 0.5
		bar.position = Vector2(hx, view.position.y + 28); bar.size = Vector2(half, 24)
		bar2.position = Vector2(hx + half + 8, view.position.y + 28); bar2.size = Vector2(half, 24)
		_cam_pick.position = Vector2(view.position.x + view.size.x - 178, view.position.y + 3); _cam_pick.size = Vector2(170, 22)
	else:
		bar.position = Vector2(left_w + 12, vp.y - 32); bar.size = Vector2(minf(620, vp.x - left_w - 24), 24)
		bar2.position = Vector2(left_w + 12, vp.y - 60); bar2.size = Vector2(minf(620, vp.x - left_w - 24), 24)
		_cam_pick.position = Vector2(left_w + 12, vp.y - 88); _cam_pick.size = Vector2(170, 22)
	if ramps:
		var rw := 560.0
		ramps.size = Vector2(rw, 0)
		ramps.position = Vector2(ride_rect.end.x - rw - 8.0, 8.0)
	var full := size_mode == 2
	hud.dev_bars((view.size.y + 8.0) if size_mode == 1 else 0.0, ride_rect.position.x, ride_rect.end.x)
	if full != _full_on:
		hud.dev_full(full); _full_on = full
	var pr = game.level_probe
	if pr and pr._label:   # the playground's own readout: small, top left of the ride
		pr._label.position = Vector2(left_w + 14.0, 10.0)
		pr._label.add_theme_font_size_override("font_size", 12)
		pr._label.add_theme_constant_override("outline_size", 4)
		pr._layer.visible = not full


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("diag") and not e.is_echo():
		size_mode = (size_mode + 1) % 3
		_layout()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo and lab != null:   # the lab keys (with the graphs off too)
		var done := true
		match e.keycode:
			KEY_G: lab.toggle_pause()
			KEY_N: lab.step_once()
			KEY_T: lab.cycle_slow()
			KEY_V: lab.toggle_record()
			KEY_J: lab.start_replay()
			_: done = false
		if done:
			get_viewport().set_input_as_handled()
			return
	if size_mode == 0 or not (e is InputEventKey) or not e.pressed or e.echo: return
	match e.keycode:
		KEY_F5:
			page = (page + (PAGES.size() - 1 if e.shift_pressed else 1)) % PAGES.size()
		KEY_F6:
			frozen = not frozen
		KEY_F7:
			win = WINDOWS[(WINDOWS.find(win) + 1) % WINDOWS.size()]
		KEY_F9:
			reset_stats()
		_:
			return
	get_viewport().set_input_as_handled()


func _input(e: InputEvent) -> void:   # click a page tab; the wheel over the graphs / bars isn't the camera's zoom
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var gm: Vector2 = view.get_global_mouse_position()
		for c in [view, bar, bar2, ramps]:
			if c != null and c.is_visible_in_tree() and (c as Control).get_global_rect().has_point(gm):
				get_viewport().set_input_as_handled(); return
		return
	if size_mode == 0 or not (e is InputEventMouseButton) or not e.pressed or e.button_index != MOUSE_BUTTON_LEFT: return
	var p: Vector2 = view.get_local_mouse_position()
	for i in view.tab_rects.size():
		if (view.tab_rects[i] as Rect2).has_point(p):
			page = i
			get_viewport().set_input_as_handled()
			return


var draw_us := 0.0                 # tests: time spent drawing the panel
var draw_n := 0

func _process(_dt: float) -> void:
	if size_mode > 0 and view: view.queue_redraw()
	if _cam_pick == null and game.cam: _build_cam_pick()
	_dev_layout()
	_frame_bike()
	if _cam_pick and game.cam and _cam_keys.find(game.cam.mode) != _cam_pick.selected and _cam_keys.find(game.cam.mode) >= 0:
		_cam_pick.select(_cam_keys.find(game.cam.mode))   # (C changed it)
	if _lab_l:
		_pause_b.text = "RUN" if lab.paused else "PAUSE"
		_slow_b.text = ({0.5: "½x", 0.25: "¼x", 0.1: "⅒x"}.get(lab.slow, "%.2fx" % lab.slow)) if lab.slow < 1.0 else "1x"
		_rec_b.text = "STOP" if lab.recording else "REC"
		_rec_b.modulate = Color(1, 0.45, 0.4) if lab.recording or lab._rec_armed else Color.WHITE
		var nchk := 0
		for k in lab.counts: nchk += int(lab.counts[k])
		_lab_l.text = lab.status + (("   checks %d" % nchk) if nchk > 0 else "")
	if _runs_l:
		var pl = game.demo
		_runs_l.text = "run %d" % (pl.runs + 1) if pl is PlaygroundPilot else ""
		if pl is PlaygroundPilot:   # the speed he rides at now (auto: what this jump needs)
			_kmh_l.text = ("%.1f km/h" if pl._auto_on(pl.cur) else "%.0f km/h") % pl.kmh()
		if pl is PlaygroundPilot and pl.mode == "feature" and pl.target != null and not pl.target.has("ramp") and _picks[_pick.selected] != null 				and _picks[_pick.selected][1] != pl.target.id:
			_select(pl.target.id)   # (F2 started it on the feature ahead: the dropdown shows which)


## the camera slides sideways (Camera3D.h_offset) so the bike sits in the middle of the free space between the
## sliders and the graphs, not at the screen's centre behind the graphs
func _frame_bike() -> void:
	var c = game.cam
	if c == null: return
	var vp := view.get_viewport_rect().size
	if size_mode == 2 or c.preset().get("mode", "") == "helmet" or ride_rect.size.x < 10.0:
		c.h_offset = 0.0; c.v_offset = 0.0; return
	var mid := ride_rect.get_center()
	var d: float = c.global_position.distance_to(game.drawn_pos)
	var hgt := 2.0 * d * tan(deg_to_rad(c.fov) * 0.5)   # (keep-height: fov is vertical)
	c.h_offset = (vp.x * 0.5 - mid.x) / vp.x * hgt * vp.x / vp.y
	# (down slides the camera down: never under the ground, it showed the underside of the level)
	var cp: Vector3 = c.global_position
	var gh: float = game.terrain.height(cp.x, cp.z)
	c.v_offset = maxf(-(vp.y * 0.5 - mid.y) / vp.y * hgt, gh + 0.4 - cp.y)


func _exit_tree() -> void:
	DebugOverlay.text_on = true   # (static: a normal ride after this one gets its text block back)
	if not _probe or st.t < 1.0: return
	var nn := maxi(1, int(st.n))
	print("DIAG SUSP F max=%.0f%% avg=%.0f%% bottom=%d blow=%d speed %+.2f..%+.2f m/s | R max=%.0f%% avg=%.0f%% bottom=%d blow=%d speed %+.2f..%+.2f m/s | sag=%.0f%% travel=%.3f m" % [
		st.maxF * 100, st.sumF / nn * 100, st.botF, st.blowF, st.minvF, st.maxvF, st.maxR * 100, st.sumR / nn * 100, st.botR, st.blowR, st.minvR, st.maxvR,
		game.phys.dg_sag / maxf(0.01, game.phys.dg_travel) * 100 if game else 0.0, game.phys.dg_travel if game else 0.0])
	print("DIAG LEGS min=%+.3f max=%+.3f m  peak tyre load %.2f g  air %.1f s of %.1f s  drawn max F %.0f%% R %.0f%%" % [st.minleg, st.maxleg, st.maxload, st.air_t, st.t, st.dmaxF * 100, st.dmaxR * 100])
	for e in [["F", hist_xF], ["R", hist_xR]]:
		var tot := 0.0
		for x in e[1]: tot += x
		var s := ""
		for x in e[1]: s += " %2.0f" % (x / maxf(tot, 1e-6) * 100)
		print("DIAG HIST %s travel %% of ground time per 5 %% band:%s" % [e[0], s])
	if _raw_dev >= 0: print("DIAG PAD %s" % Input.get_joy_name(_raw_dev))
	if draw_n > 0: print("DIAG DRAW avg %.2f ms over %d frames" % [draw_us / draw_n / 1000.0, draw_n])


# ------------------------------------------------------------------------------------------------ drawing

class DiagView extends Control:
	var d: RideDiag
	var font: Font
	var tab_rects: Array = []
	var _charts: Array = []        # Rect2 of every time graph drawn this frame (mouse readout)
	var _hover := -1.0             # 0..1 across the time window (1 = now), -1 none
	const BG := Color(0.04, 0.05, 0.07, 0.86)
	const PANE := Color(1, 1, 1, 0.045)
	const GRID := Color(1, 1, 1, 0.09)
	const TXT := Color(0.86, 0.9, 0.95)
	const DIM := Color(0.55, 0.6, 0.68)
	const FC := Color(1.0, 0.58, 0.18)     # front / fork
	const RC := Color(0.3, 0.78, 1.0)      # rear / shock
	const LC := Color(0.95, 0.4, 0.85)     # legs / rider
	const GC := Color(0.55, 0.95, 0.45)
	const YC := Color(1.0, 0.88, 0.3)
	const WC := Color(0.92, 0.92, 0.92)
	const RED := Color(1.0, 0.3, 0.25)

	func _init() -> void:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Lucida Console", "Courier New"])
		font = f

	func _t(p: Vector2, s: String, c := TXT, fs := 12, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
		if align == HORIZONTAL_ALIGNMENT_RIGHT and w <= 0.0:   # right edge at p.x (draw_string only aligns inside a width)
			p.x -= font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			align = HORIZONTAL_ALIGNMENT_LEFT
		draw_string(font, p, s, align, w, fs, c)

	func _draw() -> void:
		if d == null or d.size_mode == 0 or size.x < 300.0: return   # (not laid out yet: the HUD isn't up)
		var t0 := Time.get_ticks_usec()
		_draw_all()
		d.draw_us += Time.get_ticks_usec() - t0; d.draw_n += 1

	func _draw_all() -> void:
		_charts.clear()
		var R := Rect2(Vector2.ZERO, size)
		draw_rect(R, BG if d.size_mode == 1 else Color(BG, 0.94))
		# header: title, page tabs, keys, (the camera pick sits at the right end); the RIDER / LAB rows under it
		_t(Vector2(8, 17), "DEV", YC, 13)
		var hint := "F4 size  F5 page  F6 %s  F7 %.0f s  F9 reset  G pause  N step  T slow  V rec  J replay" % ["RUN" if d.frozen else "freeze", d.win]
		_t(Vector2(size.x - 186, 17), hint, DIM, 10, HORIZONTAL_ALIGNMENT_RIGHT, 0)
		tab_rects.clear()
		var x := 42.0
		if d.frozen:
			_t(Vector2(x, 17), "FROZEN", RED, 12); x += 60.0
		for i in RideDiag.PAGES.size():
			var nm: String = RideDiag.PAGES[i]
			var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
			var tr := Rect2(x, 4, w, 18)
			tab_rects.append(tr)
			draw_rect(tr, YC if i == d.page else Color(1, 1, 1, 0.08))
			_t(tr.position + Vector2(6, 13), nm, Color(0.05, 0.05, 0.05) if i == d.page else TXT, 11)
			x += w + 3
		# hover across the time window
		_hover = -1.0
		var m := get_local_mouse_position()
		for r in _last_charts:
			if (r as Rect2).has_point(m): _hover = clampf((m.x - r.position.x) / r.size.x, 0.0, 1.0)
		var body := Rect2(8, 58, size.x - 16, size.y - 64)   # (the RIDER / LAB rows sit at 28..52)
		_body = body
		_two = size.x > 900.0   # a wide band: the page's rows go into two columns
		match d.page:
			0: _p_overview(body)
			1: _p_susp(body)
			2: _p_input(body)
			3: _p_tyres(body)
			4: _p_body(body)
			5: _p_air(body)
			6: _p_energy(body)
		_last_charts = _charts.duplicate()

	var _last_charts: Array = []

	# ---- building blocks

	func _n() -> int:   # samples in the window
		return mini(d.count, int(d.win * RideDiag.HZ))

	func _k_at(frac: float) -> int:   # samples back for a spot across the window (1 = now)
		var n := int(d.win * RideDiag.HZ)
		return int(round((1.0 - frac) * (n - 1)))

	## a time graph. series: [[channel, colour, label, mul]], refs: [[value, colour, label]],
	## flags: [[channel, colour, label]] drawn as ticks along the bottom
	func chart(r: Rect2, title: String, series: Array, lo: float, hi: float, refs := [], flags := [], unit := "") -> void:
		draw_rect(r, PANE)
		_charts.append(r)
		var nwin := int(d.win * RideDiag.HZ)
		var n := _n()
		var fy := func(v: float) -> float: return r.end.y - 4.0 - (clampf(v, lo, hi) - lo) / maxf(hi - lo, 1e-6) * (r.size.y - 8.0 - (8.0 if flags.size() > 0 else 0.0))
		# grid: zero + refs + seconds
		if lo < 0.0 and hi > 0.0: draw_line(Vector2(r.position.x, fy.call(0.0)), Vector2(r.end.x, fy.call(0.0)), GRID, 1.0)
		for s in range(1, int(d.win)):
			var gx := r.end.x - s * RideDiag.HZ / nwin * r.size.x
			draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), Color(1, 1, 1, 0.035), 1.0)
		for rf in refs:
			var yy: float = fy.call(rf[0])
			_dash(Vector2(r.position.x, yy), Vector2(r.end.x, yy), rf[1])
			if rf.size() > 2: _t(Vector2(r.position.x + 3, yy - 2), rf[2], rf[1], 10)
		# events
		for ev in d.events:
			var back: int = d.serial - 1 - int(ev[0])
			if back < 0 or back >= n: continue
			var ex := r.end.x - float(back) / (nwin - 1) * r.size.x
			draw_line(Vector2(ex, r.position.y), Vector2(ex, r.end.y), Color(ev[2], 0.35), 1.0)
		# the replayed recording's own values, faint, under the live ones (lined up on the replay's first step)
		var lab = d.lab
		if lab != null and lab.ghost and lab._rp_serial >= 0 and lab._ghost_i >= 0 and not lab.rec.is_empty():
			var gch: PackedFloat32Array = lab.rec.chans
			var chs: Array = lab.rec.channels
			var gn := int(lab.rec.n)
			var gys := (r.size.y - 8.0 - (8.0 if flags.size() > 0 else 0.0)) / maxf(hi - lo, 1e-6)
			for s in series:
				var gc := chs.find(s[0])
				if gc < 0: continue
				var mul: float = s[3] if s.size() > 3 else 1.0
				var gp := PackedVector2Array()
				for k in n:
					var gi: int = d.serial - 1 - k - lab._rp_serial
					if gi < 0 or gi >= gn: continue
					var v: float = clampf(gch[gi * chs.size() + gc] * mul, lo, hi)
					gp.append(Vector2(r.end.x - float(k) / (nwin - 1) * r.size.x, r.end.y - 4.0 - (v - lo) * gys))
				if gp.size() >= 2: draw_polyline(gp, Color(s[1], 0.3), 3.0, true)
		# series: min / max per pixel column so a one-step spike never hides (inlined: this runs for every sample)
		var cols := maxi(2, int(r.size.x))
		var per := float(nwin) / cols
		var buf: PackedFloat32Array = d.buf
		var CC: int = d.C
		var hd: int = d.head
		var RG := RideDiag.RING
		var y0 := r.end.y - 4.0
		var ys := (r.size.y - 8.0 - (8.0 if flags.size() > 0 else 0.0)) / maxf(hi - lo, 1e-6)
		var cw := r.size.x / cols
		for s in series:
			var ch: int = d.ci[s[0]]
			var mul: float = s[3] if s.size() > 3 else 1.0
			var pts := PackedVector2Array()
			if per < 2.0:   # about a sample per pixel: plot every sample, no envelope needed
				pts.resize(n)
				var dx := r.size.x / (nwin - 1)
				var ex := r.end.x
				var i0 := (hd - 1 + RG) % RG
				for k in n:
					var idx := i0 - k
					if idx < 0: idx += RG
					var v: float = clampf(buf[idx * CC + ch] * mul, lo, hi)
					pts[k] = Vector2(ex - k * dx, y0 - (v - lo) * ys)
				if n >= 2: draw_polyline(pts, s[1], 1.4, true)
				continue
			for c in cols:
				var k1 := int(nwin - 1 - c * per)
				var k0 := maxi(int(nwin - 1 - (c + 1) * per) + 1, 0)
				if k1 < 0 or k0 >= n: continue
				k1 = mini(k1, n - 1)
				var mn := INF
				var mx := -INF
				for k in range(k0, k1 + 1):
					var v: float = buf[((hd - 1 - k + RG) % RG) * CC + ch] * mul
					if v < mn: mn = v
					if v > mx: mx = v
				var px := r.position.x + (c + 0.5) * cw
				var ya := y0 - (clampf(mn, lo, hi) - lo) * ys
				var yb := y0 - (clampf(mx, lo, hi) - lo) * ys
				if c % 2 == 0:
					pts.append(Vector2(px, ya)); pts.append(Vector2(px, yb))
				else:
					pts.append(Vector2(px, yb)); pts.append(Vector2(px, ya))
			if pts.size() >= 2: draw_polyline(pts, s[1], 1.4, true)
		# flags: one tick per run of steps it was on
		var fi := 0
		for fl in flags:
			var ch: int = d.ci[fl[0]]
			var yb := r.end.y - 3.0 - fi * 3.0
			var run0 := -1
			for k in n + 1:
				var on := k < n and buf[((hd - 1 - k + RG) % RG) * CC + ch] > 0.5
				if on and run0 < 0: run0 = k
				elif not on and run0 >= 0:
					var xa := r.end.x - float(run0) / (nwin - 1) * r.size.x
					var xb := r.end.x - float(k - 1) / (nwin - 1) * r.size.x
					draw_rect(Rect2(xb - 0.5, yb - 2.0, maxf(1.0, xa - xb + 1.0), 2.0), fl[1])
					run0 = -1
			fi += 1
		# title + legend (value now, or under the mouse)
		var kk := 0 if _hover < 0.0 else _k_at(_hover)
		_t(r.position + Vector2(4, 12), title, DIM, 11)
		# legend items right to left; one that would run into the title goes on a second line
		var items := []
		for i in range(series.size() - 1, -1, -1):
			var s: Array = series[i]
			var v: float = d.val(d.ci[s[0]], kk) * (s[3] if s.size() > 3 else 1.0)
			items.append(["%s %s%s" % [s[2], _num(v), unit], s[1]])
		for fl in flags:
			if d.val(d.ci[fl[0]], kk) > 0.5: items.append([fl[2], fl[1]])
		var t_end := r.position.x + 14.0 + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var lx := r.end.x - 4.0
		var ly := r.position.y + 12.0
		for it in items:
			var w := font.get_string_size(it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			if lx - w < t_end and ly < r.position.y + 20.0:
				lx = r.end.x - 4.0; ly += 13.0; t_end = r.position.x
			_t(Vector2(lx, ly), it[0], it[1], 11, HORIZONTAL_ALIGNMENT_RIGHT, 0)
			lx -= w + 10
		_t(Vector2(r.position.x + 4, r.end.y - 3), _num(lo), Color(DIM, 0.6), 9)
		_t(Vector2(r.position.x + 4, r.position.y + 22), _num(hi), Color(DIM, 0.6), 9)
		if _hover >= 0.0:
			var hx := r.position.x + _hover * r.size.x
			draw_line(Vector2(hx, r.position.y), Vector2(hx, r.end.y), Color(1, 1, 1, 0.5), 1.0)

	static func _num(v: float) -> String:
		var a := absf(v)
		if a >= 100.0: return "%.0f" % v
		if a >= 10.0: return "%.1f" % v
		return "%.2f" % v

	func _dash(a: Vector2, b: Vector2, c: Color) -> void:
		draw_dashed_line(a, b, Color(c, 0.6), 1.0, 5.0)

	func label_value(p: Vector2, name: String, value: String, c := TXT) -> void:
		_t(p, name, DIM, 11)
		_t(p + Vector2(0, 14), value, c, 13)

	## a suspension end drawn as a stanchion: fill = travel used now, white dash = sag, orange ring = deepest
	func travel_gauge(r: Rect2, title: String, x: float, sag: float, oring: float, col: Color, bottoms: int, blows: int, drawn := -1.0, extra := "") -> void:
		draw_rect(r, PANE)
		_t(r.position + Vector2(4, 12), title, col, 12)
		var tube := Rect2(r.position.x + 12, r.position.y + 20, 26, r.size.y - 40)
		draw_rect(tube, Color(1, 1, 1, 0.07))
		draw_rect(Rect2(tube.position, Vector2(tube.size.x, tube.size.y * clampf(x, 0, 1))), Color(col, 0.85))
		var sy := tube.position.y + tube.size.y * clampf(sag, 0, 1)
		_dash(Vector2(tube.position.x - 4, sy), Vector2(tube.end.x + 4, sy), WC)
		var oy := tube.position.y + tube.size.y * clampf(oring, 0, 1)
		draw_rect(Rect2(tube.position.x - 3, oy - 1.5, tube.size.x + 6, 3), YC)
		if drawn >= 0.0:
			var dy := tube.position.y + tube.size.y * clampf(drawn, 0, 1)
			draw_line(Vector2(tube.end.x + 2, dy), Vector2(tube.end.x + 10, dy), Color(WC, 0.8), 2.0)
		draw_rect(tube, Color(1, 1, 1, 0.25), false, 1.0)
		if x >= 0.995: draw_rect(tube.grow(2), RED, false, 2.0)
		var tx := tube.end.x + 14
		var ty := r.position.y + 30
		var items := [["travel", "%3.0f %%" % (x * 100), col], ["sag", "%3.0f %%" % (sag * 100), TXT], ["O-ring", "%3.0f %%" % (oring * 100), YC],
			["bottom-outs", "%d" % bottoms, RED if bottoms > 0 else TXT], ["blow-offs", "%d" % blows, TXT]]
		if drawn >= 0.0: items.append(["drawn", "%3.0f %%" % (drawn * 100), WC])
		# as many rows as fit (34 px each), then the next column
		var per := maxi(1, int((r.size.y - 44.0) / 34.0))
		for k in items.size():
			label_value(Vector2(tx + (k / per) * 84.0, ty + (k % per) * 34.0), items[k][0], items[k][1], items[k][2])
		if extra != "": _t(Vector2(r.position.x + 6, r.end.y - 6), extra, DIM, 10)

	func hist(r: Rect2, title: String, a: PackedFloat32Array, col: Color, lo: float, hi: float, unit: String, split := false) -> void:
		draw_rect(r, PANE)
		_t(r.position + Vector2(4, 12), title, DIM, 11)
		var tot := 0.0
		var mx := 0.0
		for v in a: tot += v; mx = maxf(mx, v)
		if tot <= 0.0: return
		var n := a.size()
		var bw := (r.size.x - 8) / n
		var hh := r.size.y - 34
		for i in n:
			var hgt := a[i] / mx * hh
			var c := col
			if split: c = FC if (i + 0.5) / n > 0.5 else RC
			draw_rect(Rect2(r.position.x + 4 + i * bw + 1, r.end.y - 16 - hgt, bw - 2, hgt), Color(c, 0.85))
			var pc := a[i] / tot * 100.0
			if pc >= 8.0 and bw > 18: _t(Vector2(r.position.x + 4 + i * bw, r.end.y - 18 - hgt), "%.0f" % pc, TXT, 9, HORIZONTAL_ALIGNMENT_CENTER, bw)
		_t(Vector2(r.position.x + 4, r.end.y - 3), "%s%s" % [_num(lo), unit], DIM, 9)
		_t(Vector2(r.end.x - 4, r.end.y - 3), "%s%s" % [_num(hi), unit], DIM, 9, HORIZONTAL_ALIGNMENT_RIGHT, 0)
		if split: _t(Vector2(r.position.x + r.size.x / 2, r.end.y - 3), "rebound | compression", DIM, 9, HORIZONTAL_ALIGNMENT_CENTER, 0)

	## a horizontal meter: value against a limit line
	func meter(r: Rect2, title: String, v: float, lo: float, hi: float, col: Color, limit := INF, txt := "") -> void:
		draw_rect(r, PANE)
		var bar := Rect2(r.position.x + 120, r.position.y + 4, r.size.x - 190, r.size.y - 8)
		draw_rect(bar, Color(1, 1, 1, 0.06))
		var z := clampf((0.0 - lo) / (hi - lo), 0, 1) if lo < 0 else 0.0
		var f := clampf((v - lo) / (hi - lo), 0, 1)
		var a := minf(z, f); var b := maxf(z, f)
		draw_rect(Rect2(bar.position.x + bar.size.x * a, bar.position.y, bar.size.x * (b - a), bar.size.y), col)
		if is_finite(limit):
			var lx := bar.position.x + bar.size.x * clampf((limit - lo) / (hi - lo), 0, 1)
			draw_line(Vector2(lx, r.position.y), Vector2(lx, r.end.y), RED, 2.0)
		_t(r.position + Vector2(4, r.size.y * 0.5 + 4), title, DIM, 11)
		_t(Vector2(r.end.x - 4, r.position.y + r.size.y * 0.5 + 4), txt if txt != "" else _num(v), col, 12, HORIZONTAL_ALIGNMENT_RIGHT, 0)

	## a stick: round gate, raw dot (white) + 1 s trail, what the game used (colour)
	func stick(r: Rect2, title: String, raw: Vector2, used: Vector2, col: Color, ch_x: String, ch_y: String, dead := 0.0, fade := false) -> void:
		draw_rect(r, PANE)
		_t(r.position + Vector2(4, 12), title, DIM, 11)
		var c := r.get_center() + Vector2(0, 6)
		var rad := minf(r.size.x, r.size.y) * 0.5 - 16
		draw_arc(c, rad, 0, TAU, 64, Color(1, 1, 1, 0.3), 1.0, true)
		draw_rect(Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2), Color(1, 1, 1, 0.08), false, 1.0)
		draw_line(c - Vector2(rad, 0), c + Vector2(rad, 0), GRID); draw_line(c - Vector2(0, rad), c + Vector2(0, rad), GRID)
		if dead > 0.0: draw_arc(c, rad * dead, 0, TAU, 32, Color(RED, 0.5), 1.0, true)
		if fade:   # the axis-fade bands (Game._read_input): within 15..35 deg of an axis the other axis fades in
			for q in 4:
				var a0 := q * PI / 2
				for sgn in [-1.0, 1.0]:
					var pts := PackedVector2Array([c])
					for i in 7:
						var a: float = a0 + sgn * deg_to_rad(15.0 + i * 20.0 / 6.0)
						pts.append(c + Vector2(cos(a), sin(a)) * rad)
					draw_colored_polygon(pts, Color(1, 1, 1, 0.04))
		# trail (the last second of raw positions)
		var cx: int = d.ci.get(ch_x, -1)
		var cy: int = d.ci.get(ch_y, -1)
		if cx >= 0:
			var n := mini(d.count, 120)
			var prev := Vector2.INF
			for k in range(n - 1, -1, -1):
				var p := c + Vector2(d.val(cx, k), d.val(cy, k) if cy >= 0 else 0.0).limit_length(1.5) * rad
				if prev != Vector2.INF: draw_line(prev, p, Color(1, 1, 1, 0.5 * (1.0 - k / 120.0)), 1.5)
				prev = p
		draw_circle(c + raw.limit_length(1.5) * rad, 5.0, WC)
		draw_circle(c + used.limit_length(1.5) * rad, 4.0, col)
		draw_arc(c + used.limit_length(1.5) * rad, 7.0, 0, TAU, 16, col, 1.5)
		_t(Vector2(r.position.x + 4, r.end.y - 18), "raw %+.2f %+.2f" % [raw.x, raw.y], WC, 11)
		_t(Vector2(r.position.x + 4, r.end.y - 4), "used %+.2f %+.2f" % [used.x, used.y], col, 11)

	func trig(r: Rect2, title: String, raw: float, used: float, col: Color) -> void:
		draw_rect(r, PANE)
		_t(r.position + Vector2(4, 12), title, DIM, 11)
		var bar := Rect2(r.position.x + 8, r.position.y + 18, (r.size.x - 24) * 0.5, r.size.y - 40)
		var bar2 := Rect2(bar.end.x + 8, bar.position.y, bar.size.x, bar.size.y)
		for pair in [[bar, raw, WC], [bar2, used, col]]:
			var b: Rect2 = pair[0]
			draw_rect(b, Color(1, 1, 1, 0.06))
			var hh: float = b.size.y * clampf(pair[1], 0, 1)
			draw_rect(Rect2(b.position.x, b.end.y - hh, b.size.x, hh), pair[2])
		_t(Vector2(r.position.x + 4, r.end.y - 4), "raw %.2f  used %.2f" % [raw, used], TXT, 11)

	func button(r: Rect2, name: String, on: bool) -> void:
		draw_rect(r, Color(YC, 0.85) if on else Color(1, 1, 1, 0.06))
		_t(r.position + Vector2(0, r.size.y * 0.5 + 4), name, Color(0.05, 0.05, 0.05) if on else DIM, 10, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

	# ---- layout helpers

	var _body := Rect2()
	var _two := false

	## a page's rows; on a wide band the body's rows are split over two columns (first half left)
	func rows(r: Rect2, weights: Array, gap := 6.0) -> Array:
		if _two and r == _body and weights.size() >= 2:
			var h := ceili(weights.size() / 2.0)
			var cw := (r.size.x - gap * 2.0) * 0.5
			var a := _rows1(Rect2(r.position, Vector2(cw, r.size.y)), weights.slice(0, h), gap)
			var b := _rows1(Rect2(r.position + Vector2(cw + gap * 2.0, 0), Vector2(cw, r.size.y)), weights.slice(h), gap)
			return a + b
		return _rows1(r, weights, gap)

	static func _rows1(r: Rect2, weights: Array, gap := 6.0) -> Array:
		var tot := 0.0
		for w in weights: tot += w
		var hh := r.size.y - gap * (weights.size() - 1)
		var out := []
		var y := r.position.y
		for w in weights:
			var h: float = hh * w / tot
			out.append(Rect2(r.position.x, y, r.size.x, h))
			y += h + gap
		return out

	static func cols(r: Rect2, weights: Array, gap := 6.0) -> Array:
		var tot := 0.0
		for w in weights: tot += w
		var ww := r.size.x - gap * (weights.size() - 1)
		var out := []
		var x := r.position.x
		for w in weights:
			var wd: float = ww * w / tot
			out.append(Rect2(x, r.position.y, wd, r.size.y))
			x += wd + gap
		return out

	func _ph():
		return d.game.phys

	# ---- pages

	func _p_overview(b: Rect2) -> void:
		var ph = _ph()
		var R := rows(b, [0.9, 1.4, 1.4, 1.2, 1.2, 1.6])
		var top := cols(R[0], [1, 1, 1, 1, 1, 1])
		label_value(top[0].position + Vector2(6, 16), "speed", "%.1f km/h" % (ph.v * 3.6), YC)
		label_value(top[1].position + Vector2(6, 16), "ground", "%+.1f°" % rad_to_deg(RideDiag._f(ph._g_pitch)))
		label_value(top[2].position + Vector2(6, 16), "state", "AIR %.2fs" % ph.air_time if ph.air else ("CRASH" if ph.crash_on else "ground"), RED if ph.crash_on else TXT)
		label_value(top[3].position + Vector2(6, 16), "gear", "%d" % (ph.gear + 1) if ph.geared else "-")
		label_value(top[4].position + Vector2(6, 16), "risk", "%.0f %%" % (ph.risk * 100), RED if ph.risk > 0.5 else TXT)
		label_value(top[5].position + Vector2(6, 16), "surface", "%d / %d" % [ph.surf_f, ph.surf_r])
		var sag: float = ph.dg_sag / maxf(0.01, ph.dg_travel)
		chart(R[1], "SUSPENSION travel", [["xF", FC, "fork", 100.0], ["xR", RC, "shock", 100.0]], 0, 110, [[sag * 100, WC, "sag"], [100, RED, "bottom"]], [["botF", RED, "BOT F"], ["botR", RED, "BOT R"], ["air", Color(0.6, 0.9, 1), "AIR"]], "%")
		chart(R[2], "TYRE LOAD (g of the whole weight)", [["tyF", FC, "front"], ["tyR", RC, "rear"]], 0, 2.5, [[1.0, WC, "1 g"]], [["cF", FC, "F down"], ["cR", RC, "R down"]])
		chart(R[3], "STEER in / bars (rad)", [["steer", WC, "input"], ["steer_in", YC, "eased"], ["bars", FC, "bars"]], -1, 1)
		chart(R[4], "LEAN (deg)", [["lean", WC, "lean"], ["bike_lean", FC, "bike"], ["counter", LC, "body"]], -70, 70)
		var bot := cols(R[5], [1, 1, 1.2])
		stick(bot[0], "LEFT STICK", Vector2(ph_v("lx"), ph_v("ly")), Vector2(-ph_v("steer"), ph_v("ly")), FC, "lx", "ly")
		stick(bot[1], "RIGHT STICK (body)", Vector2(ph_v("rx"), ph_v("ry")), Vector2(-ph_v("blean"), -ph_v("bfwd")), LC, "rx", "ry", 0.1, true)
		chart(bot[2], "SPEED km/h", [["v", YC, "v"]], 0, maxf(10.0, ceilf(_maxv("v") / 10.0) * 10.0))

	func ph_v(name: String, k := 0) -> float:
		return d.val(d.ci[name], k)

	func _maxv(name: String) -> float:
		var ch: int = d.ci[name]
		var m := 0.0
		var buf: PackedFloat32Array = d.buf
		for k in _n(): m = maxf(m, absf(buf[((d.head - 1 - k + RideDiag.RING) % RideDiag.RING) * d.C + ch]))
		return m

	func _p_susp(b: Rect2) -> void:
		var ph = _ph()
		var s: Dictionary = d.st
		var tr: float = maxf(0.01, ph.dg_travel)
		var sag: float = ph.dg_sag / tr
		var full: bool = d.size_mode == 2 or size.x > 1100.0   # (room for the histograms: full screen or a wide band)
		var main := cols(b, [0.62, 1.38] if not full else ([0.7, 1.2, 0.7] if b.size.y < 420.0 else [0.45, 1.2, 0.8]))
		var left: Array
		if b.size.y < 420.0:   # a short band: fork + shock side by side, the legs under them
			var lr := _rows1(main[0], [2.2, 1.0])
			left = cols(lr[0], [1, 1]) + [lr[1]]
			main[0] = main[0]
		else:
			left = _rows1(main[0], [1.5, 1.5, 1.0])
		var dr = d.game.susp
		var sx := ""
		if dr != null and dr.has_r:
			if d._stroke_full < 0.0: d._stroke_full = dr.stroke()
			sx = "linkage: shock %.0f / %.0f mm · wheel %.0f mm" % [dr.last_stroke * 1000.0, d._stroke_full * 1000.0, (dr.R["max"] - dr.R["min"]) * 1000.0]
		var fx_ := "linkage: fork %.0f mm travel" % ((dr.F["max"] - dr.F["min"]) * 1000.0) if dr != null and dr.has_f else ""
		travel_gauge(left[0], "FORK", ph_v("xF"), sag, s.maxF, FC, s.botF, s.blowF, ph_v("dxF") if dr != null and dr.has_f else -1.0, fx_)
		travel_gauge(left[1], "SHOCK", ph_v("xR"), sag, s.maxR, RC, s.botR, s.blowR, ph_v("dxR") if dr != null and dr.has_r else -1.0, sx)
		# legs (the rider's own suspension)
		var lg: Rect2 = left[2]
		draw_rect(lg, PANE)
		_t(lg.position + Vector2(4, 12), "LEGS (body - bike)", LC, 12)
		var lc: float = float(ph.T.get("legComp", 0.2))
		var le: float = float(ph.T.get("legExt", 0.13))
		var bar := Rect2(lg.position.x + 10, lg.position.y + 24, lg.size.x - 20, 14)
		draw_rect(bar, Color(1, 1, 1, 0.06))
		var fx := func(v: float) -> float: return bar.position.x + (clampf(v, -lc, le) + lc) / (lc + le) * bar.size.x
		draw_line(Vector2(fx.call(0.0), bar.position.y - 3), Vector2(fx.call(0.0), bar.end.y + 3), WC, 1.0)
		draw_rect(Rect2(minf(fx.call(0.0), fx.call(ph.dg_leg)), bar.position.y, absf(fx.call(ph.dg_leg) - fx.call(0.0)), bar.size.y), LC)
		draw_rect(Rect2(fx.call(s.minleg) - 1, bar.position.y - 2, 2, bar.size.y + 4), YC)
		draw_rect(Rect2(fx.call(s.maxleg) - 1, bar.position.y - 2, 2, bar.size.y + 4), YC)
		_t(Vector2(bar.position.x, bar.end.y + 14), "bent -%.2f" % lc, DIM, 10)
		_t(Vector2(bar.end.x, bar.end.y + 14), "+%.2f straight" % le, DIM, 10, HORIZONTAL_ALIGNMENT_RIGHT, 0)
		_t(Vector2(lg.position.x + 6, bar.end.y + 32), "now %+.3f m  range %+.3f..%+.3f" % [ph.dg_leg, s.minleg, s.maxleg], LC, 11)
		_t(Vector2(lg.position.x + 6, bar.end.y + 48), "travel %.3f m · knee %.2f m/s" % [tr, ph.dg_knee], DIM, 11)
		var nn := maxi(1, int(s.n))
		_t(Vector2(lg.position.x + 6, bar.end.y + 64), "avg F %.0f %%  R %.0f %%  air %.0f %%" % [s.sumF / nn * 100, s.sumR / nn * 100, s.air_t / maxf(s.t, 1e-3) * 100], DIM, 11)
		var gr := rows(main[1], [1.25, 1.1, 1.1, 0.9, 1.0] if not full else [1.2, 1, 1, 1, 1])
		var bflags := [["botF", RED, "BOT F"], ["botR", Color(1, 0.55, 0.5), "BOT R"], ["air", Color(0.6, 0.9, 1), "AIR"]]
		chart(gr[0], "TRAVEL % (physics; grey = drawn linkage)", [["dxF", Color(FC, 0.35), "drawn F", 100.0], ["dxR", Color(RC, 0.35), "drawn R", 100.0], ["xF", FC, "fork", 100.0], ["xR", RC, "shock", 100.0]], 0, 110, [[sag * 100, WC, "sag"], [100, RED, ""]], bflags, "%")
		chart(gr[1], "SHOCK SPEED m/s (+ compression)", [["vF", FC, "fork"], ["vR", RC, "shock"]], -3, 3, [[ph.dg_knee, YC, "blow-off knee"]], [["blowF", YC, "BLOW F"], ["blowR", Color(1, 0.95, 0.6), "BLOW R"]])
		chart(gr[2], "FORCE g (spring + damper; tyre dim)", [["tyF", Color(FC, 0.4), "tyre F"], ["tyR", Color(RC, 0.4), "tyre R"], ["fF", FC, "fork"], ["fR", RC, "shock"]], 0, 3, [[1.0, WC, "1 g"]])
		chart(gr[3], "TYRE SQUASH cm", [["sqF", FC, "front"], ["sqR", RC, "rear"]], 0, maxf(2.0, ceilf(maxf(_maxv("sqF"), _maxv("sqR")))), [[float(ph.T.get("tyreSquash", 1.2)) * 2.0, WC, "2x static"]])
		chart(gr[4], "LEGS m (body over bike) / leg push g", [["leg", LC, "legs"], ["legf", Color(LC, 0.45), "push", 0.1]], -lc, le, [[0.0, WC, ""]])
		if full:
			var hr := rows(main[2], [1, 1, 1, 1])
			hist(hr[0], "FORK travel use (% of ground time)", d.hist_xF, FC, 0, 100, "%")
			hist(hr[1], "SHOCK travel use", d.hist_xR, RC, 0, 100, "%")
			hist(hr[2], "FORK shock speed", d.hist_vF, FC, -3, 3, "", true)
			hist(hr[3], "SHOCK shock speed", d.hist_vR, RC, -3, 3, "", true)

	func _p_input(b: Rect2) -> void:
		var ph = _ph()
		var R := rows(b, [2.2, 0.9, 1.3, 1.3, 1.1, 1.0])
		var top := cols(R[0], [1, 1, 0.55, 0.55])
		var pad: bool = d._raw_dev >= 0
		stick(top[0], "LEFT STICK  steer" + ("" if pad else " (keys)"), Vector2(ph_v("lx"), ph_v("ly")), Vector2(-ph_v("steer"), ph_v("ly")), FC, "lx", "ly")
		stick(top[1], "RIGHT STICK  body" + ("" if pad else " (numpad)"), Vector2(ph_v("rx"), ph_v("ry")), Vector2(-ph_v("blean"), -ph_v("bfwd")), LC, "rx", "ry", 0.1, true)
		trig(top[2], "LT brake", ph_v("lt"), ph_v("brk"), RC)
		trig(top[3], "RT pedal", ph_v("rt"), ph_v("thr"), GC)
		# steer curve (pad expo / steer response) with the current point
		var cv := cols(R[1], [0.8, 2.2])
		var cr: Rect2 = cv[0]
		draw_rect(cr, PANE)
		_t(cr.position + Vector2(4, 12), "STEER CURVE", DIM, 11)
		var expo: float = float(Settings.get_v("pad_expo")) if Settings.pad_active else 1.0
		var pw := expo / maxf(0.3, float(Settings.get_v("steer_sens")))
		var org := Vector2(cr.position.x + 8, cr.end.y - 6)
		var sz := Vector2(cr.size.x - 16, cr.size.y - 24)
		var pts := PackedVector2Array()
		for i in 21:
			var u := i / 20.0
			pts.append(org + Vector2(u * sz.x, -pow(u, pw) * sz.y))
		draw_polyline(pts, FC, 1.5, true)
		var raw_s := absf(ph_v("lx"))
		draw_circle(org + Vector2(raw_s * sz.x, -absf(ph_v("steer")) * sz.y), 4, WC)
		_t(Vector2(cr.end.x - 4, cr.position.y + 12), "^%.2f" % pw, FC, 11, HORIZONTAL_ALIGNMENT_RIGHT, 0)
		# buttons / actions
		var br: Rect2 = cv[1]
		draw_rect(br, PANE)
		var names := ["pedal", "brake", "brake_front", "brake_rear", "steer_left", "steer_right", "hop", "sprint", "body_fwd", "body_back", "body_left", "body_right", "gear_easier", "gear_harder", "bail", "camera_next"]
		var bw := (br.size.x - 12) / 8.0
		for i in names.size():
			var nm: String = names[i]
			var on := InputMap.has_action(nm) and Input.is_action_pressed(nm)
			button(Rect2(br.position.x + 4 + (i % 8) * bw, br.position.y + 4 + (i / 8) * (br.size.y * 0.5 - 2), bw - 4, br.size.y * 0.5 - 6), nm.replace("_", " "), on)
		var who := "pad: %s" % Input.get_joy_name(d._raw_dev) if pad else "no pad connected: keys"
		_t(Vector2(b.position.x, b.end.y + 6), "%s · pad_active=%s · %s" % [who, str(Settings.pad_active), "demo rider" if d.game.demo != null else "player"], DIM, 10)
		chart(R[2], "STEER  input / eased / bars (rad)", [["steer", WC, "input"], ["steer_in", YC, "eased"], ["bars", FC, "bars"]], -1, 1)
		chart(R[3], "BODY STICK  raw y / used fwd · raw x / used lean", [["ry", Color(WC, 0.4), "raw y", -1.0], ["bfwd", LC, "fwd"], ["rx", Color(YC, 0.4), "raw x", -1.0], ["blean", YC, "lean"], ["flick", RC, "flick"]], -1.1, 1.1)
		chart(R[4], "PEDAL / BRAKES", [["thr", GC, "pedal"], ["brk", RC, "brake"], ["brkf", FC, "front"], ["brkr", Color(0.5, 0.6, 1), "rear"]], 0, 1.05, [], [["hop", YC, "HOP"], ["sprint", GC, "SPRINT"]])
		chart(R[5], "RAW TRIGGERS", [["lt", RC, "LT"], ["rt", GC, "RT"]], 0, 1.05)

	func _p_tyres(b: Rect2) -> void:
		var ph = _ph()
		var R := rows(b, [1.2, 1.2, 1.0, 1.0, 1.0, 1.5])
		chart(R[0], "TYRE LOAD g (eased for grip) + contact", [["nF", FC, "front"], ["nR", RC, "rear"]], 0, 2.5, [[1.0, WC, "1 g"]], [["cF", FC, "F down"], ["cR", RC, "R down"]])
		chart(R[1], "GRIP  rear grip left / front use (1 = at the limit)", [["grip_r", RC, "rear grip"], ["front_use", FC, "front use"]], 0, 1.6, [[1.0, RED, "limit"]])
		chart(R[2], "SLIDE deg / slide rate rad/s", [["slip", YC, "slip"], ["slip_w", Color(YC, 0.45), "rate", 10.0]], -30, 30)
		chart(R[3], "TURN FORCE m/s²", [["lat_a", GC, "lat"]], -15, 15)
		chart(R[4], "BRAKES  + locks", [["brake_f", FC, "front"], ["brake_r", RC, "rear"]], 0, maxf(1.0, maxf(_maxv("brake_f"), _maxv("brake_r"))), [], [["flock", FC, "F LOCK"], ["rlock", RC, "R LOCK"]])
		# trouble meters (crash judge)
		var mr := rows(R[5], [1, 1, 1, 1, 1])
		meter(mr[0], "risk (fullest)", ph.risk, 0, 1, RED if ph.risk > 0.5 else YC, 1.0, "%.0f %%" % (ph.risk * 100))
		var i := 1
		for k in ph._risk.keys():
			if i >= mr.size(): break
			meter(mr[i], str(k), float(ph._risk[k]), 0, 1, Color(1, 0.5, 0.3), 1.0)
			i += 1
		while i < mr.size():
			match i:
				1: meter(mr[i], "loose ground", ph.loose, 0, 1, Color(0.85, 0.6, 0.3))
				2: meter(mr[i], "grip mu F / R", RideDiag._f(ph._mu_f), 0, 1.5, FC, INF, "%.2f / %.2f" % [RideDiag._f(ph._mu_f), RideDiag._f(ph._mu_r)])
				3: meter(mr[i], "weight in", ph.weight_in, -1, 1, LC)
				4: meter(mr[i], "corner g", ph.corner_g / 9.81, 0, 1.5, GC)
			i += 1

	func _p_body(b: Rect2) -> void:
		var ph = _ph()
		var R := rows(b, [1.2, 1.0, 1.2, 1.0, 1.0, 1.0])
		chart(R[0], "LEAN deg  asked / bike / body counter / rider hips, chest", [["lean", WC, "lean"], ["bike_lean", FC, "bike"], ["counter", LC, "counter"], ["roll_hip", YC, "hips"], ["roll_chest", GC, "chest"]], -70, 70)
		chart(R[1], "BARS rad / flick", [["bars", FC, "bars"], ["flick", LC, "flick"]], -1, 1)
		chart(R[2], "PITCH deg  bike / ground", [["pitch", FC, "bike"], ["g_pitch", WC, "ground"]], -45, 45)
		chart(R[3], "BODY fore / aft m (+ back) / hips", [["body_x", LC, "body x"], ["hip", YC, "hips"]], -0.4, 0.4)
		chart(R[4], "LEGS compress m / legs (body - bike)", [["compress", RC, "compress"], ["leg", LC, "legs"]], -0.3, 0.15)
		chart(R[5], "MANUAL / NOSE MANUAL angle deg", [["man_a", GC, "manual"], ["nose_a", RC, "nose"]], -5, 45, [[rad_to_deg(float(ph.T.get("manBalance", 0.5))), YC, "balance"]])

	func _p_air(b: Rect2) -> void:
		var ph = _ph()
		var R := rows(b, [2.4, 1.0, 1.0, 1.0, 0.9])
		_side_view(R[0])
		chart(R[1], "HEIGHT over ground m / vy m/s", [["hgt", YC, "height"], ["vy", RC, "vy", 0.25]], -1, 4, [[0.0, WC, ""]], [["air", Color(0.6, 0.9, 1), "AIR"]])
		chart(R[2], "PITCH vs slope deg", [["pitch", FC, "bike"], ["g_pitch", WC, "ground"]], -90, 90)
		chart(R[3], "SPIN rad/s / tilt deg", [["air_w", LC, "spin"], ["air_tilt", YC, "tilt", 0.1]], -8, 8)
		chart(R[4], "STICK  flip in / body fwd", [["flip_in", GC, "flip"], ["bfwd", LC, "fwd"]], -1.1, 1.1)
		var pr = d.game.level_probe
		if pr != null:
			_t(Vector2(R[0].position.x + 6, R[0].end.y - 6), str(pr._last).replace("\n", "  ·  "), DIM, 10)

	func _p_energy(b: Rect2) -> void:
		var ph = _ph()
		var lab = d.lab
		var R := rows(b, [1.4, 1.0, 0.8, 1.6])
		chart(R[0], "ENERGY J/kg since the last reset (½v² + g·h): coasting it may only fall", [["energy", YC, "E"]], -60, 20, [[0.0, WC, "start"]], [["free", Color(0.6, 0.9, 1), "COASTING"], ["air", Color(0.6, 1, 0.6), "AIR"]])
		chart(R[1], "KINETIC ½v² J/kg / speed", [["e_kin", GC, "½v²"], ["v", FC, "km/h"]], 0, 120)
		chart(R[2], "INPUTS THAT ADD ENERGY", [["thr", GC, "pedal"], ["bfwd", LC, "stick fwd"]], -0.1, 1.05, [], [["hop", YC, "HOP / PUMP"], ["sprint", GC, "SPRINT"]])
		var cr: Rect2 = R[3]
		draw_rect(cr, PANE)
		_t(cr.position + Vector2(4, 12), "PHYSICS CHECKS (things a real bike can't do)", DIM, 11)
		if lab == null: return
		var x := cr.position.x + 6.0
		var kinds := ["energy_gain", "rim_strike", "accel", "sunk", "jump_step", "non_finite"]
		for k in kinds:
			var c := int(lab.counts.get(k, 0))
			var txt := "%s %d" % [k.replace("_", " "), c]
			_t(Vector2(x, cr.position.y + 30), txt, RED if c > 0 else GC, 12)
			x += font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 18
		var y := cr.position.y + 50.0
		for i in range(lab.checks.size() - 1, -1, -1):
			if y > cr.end.y - 6: break
			var c: Dictionary = lab.checks[i]
			_t(Vector2(cr.position.x + 6, y), "%6.1f s  %-12s %s  · %s" % [float(c.t), c.kind, c.text, c.where], TXT, 11)
			y += 15.0
		if lab.checks.is_empty():
			_t(Vector2(cr.position.x + 6, y), "none so far", DIM, 11)

	## the last jump from the side: ground under the take-off line, the bike every 0.1 s (stroboscope)
	func _side_view(r: Rect2) -> void:
		draw_rect(r, PANE)
		var j: Array = d.jump_live if not d.jump_live.is_empty() else d.jump_last
		_t(r.position + Vector2(4, 12), "JUMP SIDE VIEW " + ("(in the air)" if not d.jump_live.is_empty() else d.jump_last_info), DIM, 11)
		if j.size() < 2: return
		var ph = _ph()
		var x0: float = j[0][0] - 3.0
		var x1: float = j[j.size() - 1][0] + 3.0
		var ylo := INF; var yhi := -INF
		for p in j:
			ylo = minf(ylo, minf(p[1], p[3])); yhi = maxf(yhi, maxf(p[1], p[3]))
		# ground along the take-off line, a little either side
		var fw := Vector2(cos(d._jh), -sin(d._jh))
		var gpts := []
		var nseg := 80
		for i in nseg + 1:
			var xx := x0 + (x1 - x0) * i / nseg
			var gp := Vector2(d._j0.x, d._j0.z) + fw * xx
			var gh: float = d.game.terrain.height(gp.x, gp.y)
			gpts.append(Vector2(xx, gh)); ylo = minf(ylo, gh); yhi = maxf(yhi, gh)
		yhi += 1.0; ylo -= 0.3
		var inner := r.grow_individual(-8, -20, -8, -18)
		var sc := minf(inner.size.x / (x1 - x0), inner.size.y / (yhi - ylo))
		var to := func(p: Vector2) -> Vector2: return Vector2(inner.position.x + (p.x - x0) * sc, inner.end.y - (p.y - ylo) * sc)
		# metres grid
		for m in range(int(floor(x0)), int(ceil(x1)) + 1):
			var gx: float = to.call(Vector2(m, 0)).x
			draw_line(Vector2(gx, inner.position.y), Vector2(gx, inner.end.y), Color(1, 1, 1, 0.07 if m % 5 else 0.16), 1.0)
		for m in range(int(floor(ylo)), int(ceil(yhi)) + 1):
			var gy: float = to.call(Vector2(0, m)).y
			draw_line(Vector2(inner.position.x, gy), Vector2(inner.end.x, gy), Color(1, 1, 1, 0.07), 1.0)
		var poly := PackedVector2Array()
		for g in gpts: poly.append(to.call(g))
		var fill := poly.duplicate()
		fill.append(Vector2(inner.end.x, inner.end.y)); fill.append(Vector2(inner.position.x, inner.end.y))
		draw_colored_polygon(fill, Color(0.45, 0.35, 0.22, 0.5))
		draw_polyline(poly, Color(0.85, 0.7, 0.45), 2.0, true)
		# path of the bike's centre + the bike every 12 steps
		var path := PackedVector2Array()
		for p in j: path.append(to.call(Vector2(p[0], p[1])))
		draw_polyline(path, Color(YC, 0.7), 1.5, true)
		var L: float = ph.L
		var br: float = ph.BB_REAR
		var rw: float = ph.RWF
		for i in range(0, j.size(), 12):
			var p: Array = j[i]
			var c := Vector2(p[0], p[1])
			var dir := Vector2(cos(p[2]), sin(p[2]))
			var up := Vector2(-dir.y, dir.x)
			var rear := c - dir * br + up * rw   # axles a wheel radius over the contact line the physics rides
			var front := c + dir * (L - br) + up * rw
			var a := float(i) / maxf(1, j.size() - 1)
			var col := Color(RC.lerp(FC, a), 0.85)
			draw_line(to.call(rear), to.call(front), col, 2.0)
			draw_arc(to.call(rear), rw * sc, 0, TAU, 20, col, 1.2)
			draw_arc(to.call(front), rw * sc, 0, TAU, 20, col, 1.2)
		_t(Vector2(inner.end.x, inner.position.y + 4), "1 m grid", DIM, 9, HORIZONTAL_ALIGNMENT_RIGHT, 0)
