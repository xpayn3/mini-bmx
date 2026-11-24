extends Node
## Crash / error reports (autoload `CrashLog`, loaded first so it sees everything).
##
## Every print, warning and error of the session goes to `user://crashlogs/run_<pid>.log` (written as it happens,
## flushed on every error), next to a `run_<pid>.lock` that only a clean quit removes. So:
## - **Hard crash / killed window**: the next launch finds a lock whose process is gone and turns its log into
##   `crashlogs/crash_<date>/` (report.txt + that session's log + Godot's own log of it, which has the native
##   backtrace + `csharp.txt` if C# died on an unhandled exception). The title menu says so (`notice`).
## - **Script / engine error while playing**: `crashlogs/error_<date>/` (report.txt with the error, its script
##   backtrace, the last 400 log lines, + `ride_log.csv` = the last 60 s of the ride). At most 3 per session, one per
##   file:line.
## - **F8 / R3** (save_log): the same as a "manual" report, for anything that looked wrong.
## - **Freeze**: a watchdog thread notes in the log when the main thread hasn't finished a frame for `HANG_S`.
## Finished sessions' logs are kept in `crashlogs/sessions/` (last `KEEP_SESSIONS`). Test runs (autotest, shots,
## probes, headless tools) use `crashlogs/tests/` so they never push the player's out. Nothing leaves the PC.

const ROOT := "user://crashlogs"
const KEEP_SESSIONS := 20
const KEEP_REPORTS := 20
const MAX_ERROR_REPORTS := 3
const RING := 400           # log lines kept in memory for reports
const MAX_LOG_BYTES := 8 << 20   # past this the session log keeps only warnings / errors
const HANG_S := 10.0

var dir := ROOT
var test_run := false
var last_crash := ""        # folder of the crash found at start ("" = none)
var game: WeakRef            # the ride's Game (set by Game._ready), for its ride log
var errors := 0
var warnings := 0

var _logger: _Sink
var _pid := 0
var _lock_path := ""
var _started := ""
var _reported := {}          # "file:line" -> true
var _n_reports := 0
var _flush_t := 0.0
var _beat := 0               # Time.get_ticks_msec() of the last main-thread frame
var _wd: Thread
var _wd_run := false
var _notice_shown := false


## the logger the engine calls (any thread): appends to the session log + an in-memory ring
class _Sink extends Logger:
	var mutex := Mutex.new()
	var file: FileAccess
	var ring := PackedStringArray()
	var head := 0
	var bytes := 0
	var errors := 0
	var warnings := 0
	var pending: Array = []   # errors waiting for a report (handled on the main thread)
	var closed := false

	func _put(s: String, important: bool) -> void:
		mutex.lock()
		if ring.size() < RING: ring.append(s)
		else:
			ring[head] = s
			head = (head + 1) % RING
		if file and not closed and (important or bytes < MAX_LOG_BYTES):
			file.store_string(s if s.ends_with("\n") else s + "\n")
			bytes += s.length() + 1
			if important: file.flush()
		mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		_put(message.trim_suffix("\n"), error)

	func _log_error(function: String, file_: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var msg := rationale if rationale != "" else code
		var s := "%s: %s\n   at: %s (%s:%d)" % [kind, msg, function, file_, line]
		for bt in script_backtraces:
			if bt and not bt.is_empty(): s += "\n" + bt.format(3)
		_put(s, true)
		mutex.lock()
		if error_type == ERROR_TYPE_WARNING: warnings += 1
		else:
			errors += 1
			if pending.size() < 16: pending.append({"key": "%s:%d" % [file_, line], "text": s})
		mutex.unlock()

	func lines() -> PackedStringArray:
		mutex.lock()
		var out := PackedStringArray()
		for i in ring.size(): out.append(ring[(head + i) % ring.size()])
		mutex.unlock()
		return out

	func close() -> void:
		mutex.lock()
		closed = true
		if file:
			file.flush()
			file.close()
			file = null
		mutex.unlock()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	test_run = DisplayServer.get_name() == "headless" or args.has("-s") or args.has("--script") \
		or OS.get_environment("BMX_PADSEQ") != "" or OS.get_environment("BMX_MIN") != "" or OS.get_environment("BMX_OFFSCREEN") != "" \
		or Array(args).any(func(a): return a.begins_with("--autotest") or a.begins_with("--bench") or a.begins_with("--hitch") \
			or a.begins_with("--showcase") or a.begins_with("--shot"))
	dir = ROOT + ("/tests" if test_run else "")
	_pid = OS.get_process_id()
	_started = _stamp()
	DirAccess.make_dir_recursive_absolute(dir + "/sessions")
	_collect_old_runs()
	_logger = _Sink.new()
	_logger.file = FileAccess.open("%s/run_%d.log" % [dir, _pid], FileAccess.WRITE)
	_lock_path = "%s/run_%d.lock" % [dir, _pid]
	var lk := FileAccess.open(_lock_path, FileAccess.WRITE)
	if lk:
		lk.store_line("pid=%d started=%s version=%s" % [_pid, _started, _version()])
		lk.close()
	OS.add_logger(_logger)
	_logger._put(_header("session"), true)
	var hook = cs_new("res://scripts/core/CrashHook.cs")
	if hook:   # C#: unhandled exceptions on any thread -> csharp.txt beside the log
		hook.install(ProjectSettings.globalize_path("%s/run_%d.csharp.txt" % [dir, _pid]))


func _ready() -> void:
	_logger._put("GPU: %s (%s) · driver %s · screen %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(), DisplayServer.screen_get_size()], true)
	if last_crash != "": print("CRASHLOG previous session crashed: ", ProjectSettings.globalize_path(last_crash))
	_beat = Time.get_ticks_msec()
	if DisplayServer.get_name() != "headless":
		_wd_run = true
		_wd = Thread.new()
		_wd.start(_watchdog)


func _process(dt: float) -> void:
	_beat = Time.get_ticks_msec()
	_crash_test()
	_flush_t += dt if dt > 0.0 else 0.016
	if _flush_t > 0.5:
		_flush_t = 0.0
		_logger.mutex.lock()
		if _logger.file: _logger.file.flush()
		var todo: Array = _logger.pending.duplicate()
		_logger.pending.clear()
		errors = _logger.errors
		warnings = _logger.warnings
		_logger.mutex.unlock()
		for e in todo:
			if _reported.has(e.key) or _n_reports >= MAX_ERROR_REPORTS: continue
			_reported[e.key] = true
			_n_reports += 1
			report("error", e.text)


## tests: BMX_CRASHTEST=error|hard|cs|hang[@secs] (default 5 s in) makes that happen once
var _ct_done := false
func _crash_test() -> void:
	if _ct_done or not test_run: return
	var spec := OS.get_environment("BMX_CRASHTEST")
	if spec == "":
		_ct_done = true
		return
	var parts := spec.split("@")
	if Time.get_ticks_msec() / 1000.0 < (float(parts[1]) if parts.size() > 1 else 5.0): return
	_ct_done = true
	_logger._put("CRASHTEST " + parts[0], true)
	match parts[0]:
		"error": _ct_null_call(null)
		"hard": OS.crash("BMX_CRASHTEST hard crash")
		"cs":
			var h = cs_new("res://scripts/core/CrashHook.cs")
			if h: h.test_throw()
		"hang": OS.delay_msec(int((HANG_S + 2.0) * 1000))


func _ct_null_call(o) -> void:
	o.no_such_method()   # a real runtime script error, with its backtrace


## writes a report folder now ("error" / "manual"), returns its full path
func report(kind: String, detail := "") -> String:
	var d := _unique_dir("%s/%s_%s" % [dir, kind, _stamp()])
	DirAccess.make_dir_recursive_absolute(d)
	var txt := _header(kind)
	txt += "\nuptime: %.1f s · errors: %d · warnings: %d\n" % [Time.get_ticks_msec() / 1000.0, _logger.errors, _logger.warnings]
	txt += _context()
	if detail != "": txt += "\n=== %s ===\n%s\n" % ["error" if kind == "error" else "note", detail]
	txt += "\n=== last %d log lines ===\n%s\n" % [RING, "\n".join(_logger.lines())]
	_write(d + "/report.txt", txt)
	var g = game.get_ref() if game else null
	if g and is_instance_valid(g) and g.get("ride_log") != null:
		g.ride_log.save(d + "/ride_log.csv")
	_prune("%s_" % kind)
	var full := ProjectSettings.globalize_path(d)
	print("CRASHLOG %s report %s" % [kind, full])
	return full


## a line in the session log (shows in every later report)
## a line for the session log (crash reports / F8 show it). Straight into the log, not printed: a print to stdout cost 7-14 ms
## through a console pipe, inside the physics step on every crash (found with the frame profiler, 2026-11-24)
func note(s: String) -> void:
	if _logger != null and not _logger.closed: _logger._put("[note] " + s, false)
	else: print("[note] ", s)


## the title menu calls this: a small card saying the last session crashed, once per launch
func notice(parent: Control) -> void:
	if _notice_shown or last_crash == "" or parent == null or (test_run and OS.get_environment("BMX_CRASH_NOTICE") == ""): return
	_notice_shown = true
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UITheme.card_style(Tokens.PAPER, Tokens.R_XL, Tokens.S4))
	card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.offset_top = Tokens.S6
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", Tokens.S2)
	card.add_child(vb)
	vb.add_child(UITheme.heading("The game closed unexpectedly last time"))
	vb.add_child(UITheme.text("A crash report was saved. Tell Claude \"it crashed\" and it can read it."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Tokens.S2)
	vb.add_child(row)
	var path := ProjectSettings.globalize_path(last_crash)
	row.add_child(UITheme.make_button("OPEN FOLDER", func(): OS.shell_open(path), "secondary"))
	row.add_child(UITheme.make_button("OK", func(): card.queue_free(), "chip"))
	parent.add_child(card)
	get_tree().create_timer(20.0, true, false, true).timeout.connect(func(): if is_instance_valid(card): card.queue_free())


func _exit_tree() -> void:
	_wd_run = false
	if _wd and _wd.is_started(): _wd.wait_to_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _logger:   # the very end of a clean quit
		_logger._put("clean exit at %s (errors %d, warnings %d)" % [_stamp(), _logger.errors, _logger.warnings], true)
		OS.remove_logger(_logger)
		_logger.close()
		DirAccess.remove_absolute(_lock_path)


func _watchdog() -> void:
	var noted := false
	var n := 0
	while _wd_run:
		OS.delay_msec(250)
		n += 1
		if n % 2 == 0:   # flush twice a second from here too: a hard crash loses at most ~0.5 s of log
			_logger.mutex.lock()
			if _logger.file and not _logger.closed: _logger.file.flush()
			_logger.mutex.unlock()
		var stuck := (Time.get_ticks_msec() - _beat) / 1000.0
		if stuck > HANG_S and not noted:
			noted = true
			_logger._put("HANG? the main thread hasn't finished a frame for %.0f s (at %s)" % [stuck, _stamp()], true)
		elif stuck < 1.0 and noted:
			noted = false
			_logger._put("main thread running again", true)


## old runs in this folder: a lock whose process is gone = it crashed; a log without a lock = it quit cleanly
func _collect_old_runs() -> void:
	for f in DirAccess.get_files_at(dir):
		if not (f.begins_with("run_") and f.ends_with(".log")): continue
		var pid := f.trim_prefix("run_").trim_suffix(".log").to_int()
		if pid == _pid: continue
		var lock := "%s/run_%d.lock" % [dir, pid]
		var log_path := "%s/%s" % [dir, f]
		var cs := "%s/run_%d.csharp.txt" % [dir, pid]
		if FileAccess.file_exists(lock):
			if OS.is_process_running(pid): continue   # another copy of the game is running
			var when := _local(FileAccess.get_modified_time(log_path))
			var d := _unique_dir("%s/crash_%s" % [dir, when])
			DirAccess.make_dir_recursive_absolute(d)
			var tail := _tail(log_path, 400)
			var txt := "RUNOUT crash report: the session below never reached a clean quit (crash, freeze + killed, or power loss).\n"
			txt += "found at: %s · its log last written: %s\n" % [_stamp(), when]
			var hang := tail.find("HANG?") >= 0
			if hang: txt += "the watchdog saw the main thread freeze (see HANG? in the log)\n"
			if FileAccess.file_exists(cs): txt += "C# died on an unhandled exception: see csharp.txt\n"
			txt += "Godot's own log of it (native backtrace if the engine crashed): godot.log\n"
			txt += "\n=== last 400 log lines ===\n" + tail
			_write(d + "/report.txt", txt)
			DirAccess.rename_absolute(log_path, d + "/session.log")
			if FileAccess.file_exists(cs): DirAccess.rename_absolute(cs, d + "/csharp.txt")
			_copy_godot_log(FileAccess.get_modified_time(d + "/session.log"), d + "/godot.log")
			DirAccess.remove_absolute(lock)
			last_crash = d
		else:
			DirAccess.rename_absolute(log_path, "%s/sessions/session_%s.log" % [dir,
				_local(FileAccess.get_modified_time(log_path))])
			if FileAccess.file_exists(cs): DirAccess.rename_absolute(cs, "%s/sessions/csharp_%d.txt" % [dir, pid])
	for f in DirAccess.get_files_at(dir):   # a lock left without its log
		if f.begins_with("run_") and f.ends_with(".lock") and not OS.is_process_running(f.trim_prefix("run_").trim_suffix(".lock").to_int()):
			DirAccess.remove_absolute(dir + "/" + f)
	var olds := Array(DirAccess.get_files_at(dir + "/sessions"))
	olds.sort()
	while olds.size() > KEEP_SESSIONS:
		DirAccess.remove_absolute(dir + "/sessions/" + olds.pop_front())
	_prune("crash_")


## Godot keeps its own log (user://logs, rotated): copy the crashed session's = the first one last written at or after
## our session log was (the run before it ended earlier)
func _copy_godot_log(t: int, to: String) -> void:
	var ld := "user://logs"
	var best := ""
	var best_dt := 1 << 30
	for f in DirAccess.get_files_at(ld):
		if not f.begins_with("godot") or f == "godot.log": continue
		var dt := FileAccess.get_modified_time(ld + "/" + f) - t
		if dt >= 0 and dt < best_dt:
			best_dt = dt
			best = f
	if best != "" and best_dt < 600:
		_write(to, _tail(ld + "/" + best, 3000))


func _prune(prefix: String) -> void:
	var ds := Array(DirAccess.get_directories_at(dir)).filter(func(n): return n.begins_with(prefix))
	ds.sort()
	while ds.size() > KEEP_REPORTS:
		var d: String = dir + "/" + ds.pop_front()
		for f in DirAccess.get_files_at(d): DirAccess.remove_absolute(d + "/" + f)
		DirAccess.remove_absolute(d)


func _header(kind: String) -> String:
	return "RUNOUT %s · %s · version %s · Godot %s · %s %s · %s · %d threads · test run: %s" % [kind, _stamp(), _version(),
		Engine.get_version_info().string, OS.get_name(), OS.get_version(), OS.get_processor_name(), OS.get_processor_count(), test_run]


func _context() -> String:
	var s := ""
	var gs := get_node_or_null("/root/GameState")
	if gs: s += "seed: %s · bike: %s\n" % [gs.get("seed"), gs.get("bike_id")]
	s += "window: %s · time scale: %s · paused: %s\n" % [DisplayServer.window_get_size(), Engine.time_scale, get_tree().paused if get_tree() else "?"]
	var g = game.get_ref() if game else null
	if g and is_instance_valid(g) and g.get("phys"):
		var p = g.phys
		s += "ride: pos (%.1f, %.1f, %.1f) · v %.2f · air %s · crashed %s\n" % [p.x, p.y, p.z, p.v, p.air, p.crash_on]
	return s


## a new object of a C# class (null on the plain Godot build). C# [GlobalClass]es are script classes:
## ClassDB.class_exists() never finds them
static func cs_new(path: String) -> Object:
	if not ClassDB.class_exists("CSharpScript"): return null
	var sc = load(path)
	return sc.new() if sc else null


static func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


## a file time (UTC unix) as local "YYYY-MM-DD_HH-MM-SS", like _stamp()
static func _local(t: int) -> String:
	return Time.get_datetime_string_from_unix_time(t + int(Time.get_time_zone_from_system().bias) * 60).replace(":", "-").replace("T", "_")


static func _stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")


## a folder name nothing has yet: several reports in the same second get _2, _3... (sorts after the first)
static func _unique_dir(base: String) -> String:
	if not DirAccess.dir_exists_absolute(base): return base
	var n := 2
	while DirAccess.dir_exists_absolute("%s_%d" % [base, n]): n += 1
	return "%s_%d" % [base, n]

static func _write(path: String, txt: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()


static func _tail(path: String, n: int) -> String:
	var t := FileAccess.get_file_as_string(path)
	var ls := t.split("\n")
	return "\n".join(ls.slice(maxi(0, ls.size() - n)))
