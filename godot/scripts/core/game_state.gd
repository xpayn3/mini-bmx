extends Node
## Session + save data: which bike, which world seed, and the player's records.
## Records persist in user://save.cfg.

const SAVE := "user://save.cfg"

## Bikes. `ride` multiplies the tuning values (see Tune); `pose` is handed to the rider.
## the GLORY DH rider pose / ride feel, shared by the downhill frames
const DH_POSE := {"hipX": -0.07, "hipY": 0.075, "lean": 0.22, "elbowsOut": 0.0, "shoulders": 0.19, "torso": 0.5, "hipSway": 0.035, "kneesOut": 0.25, "stance": -0.035, "seatFloor": true,
	"headTilt": 0.12, "headTurn": 1.05, "hipZ": 0.005, "spineCurve": 0.24, "spineLow": 0.31,
	"chestUp": -0.005, "chestSide": 0.005, "headRoll": -0.01, "shoulderFwd": 0.005,
	"wristRoll": 0.02, "kneesFwd": 0.05, "footAngle": 0.01}
const DH_RIDE := {
	"steerRate": 0.9, "steerRelease": 0.9, "barSpeed": 0.9, "steerMax": 0.9, "counter": 0.6,
	"leanMax": 1.1, "leanIn": 0.8, "leanOut": 0.8, "leanDamp": 1.2,
	"legStiff": 0.6, "legDamp": 1.2, "legComp": 1.3, "legExt": 1.3, "attackDrop": 1.3,
	"pedalLaunch": 0.75, "pedalPower": 0.85, "pedalTop": 1.35, "airDrag": 0.85, "brakeForce": 1.3, "popPower": 0.9,
	"grip": 1.15, "oversteer": 0.7,
	"tyreHz": 0.75, "tyreDamp": 1.3, "travel": 2.2,
}

const BIKES := {
	"dh": {
		"label": "Downhill", "file": "res://assets/dh.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE,
		"land": 1.45, "geared": true, "decals": true, "garage": true,
	},
	# the YT Tues frame with its own fork, bars, brakes and cranks (tools/export_tues.py)
	"tues": {"label": "Yonder Tusk", "file": "res://assets/tues.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE, "land": 1.45, "geared": true, "garage": true},
	# the Sketchfab "DH bike frame" (CC-BY, assets/dhframe_LICENSE.txt) on our fork / bars / cranks (tools/export_dhframe.py)
	"goat": {"label": "Goat DH", "file": "res://assets/dhframe.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE, "land": 1.45, "geared": true, "garage": true,
		"chain": {"ring_r": 0.0688, "ring_teeth": 34, "ring_z": 0.056, "follow": true},   # our crank (34T ring), not the glb's 92 mm
		"head": {"top": [0.4804, 0.9279], "bottom": [0.5261, 0.8191]}},   # its head tube (67.3 deg, measured off the mesh): our fork sits on it
	# the NS Bikes Fuzz frame with its own fork, bars, brakes, cranks and derailleur (tools/export_fuzz.py)
	"fuzz": {"label": "Nexo Fizz", "file": "res://assets/fuzz.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE, "land": 1.45, "geared": true, "garage": true},
	"bmx": {"label": "BMX", "file": "res://assets/bmx.glb", "root": "bmx", "pose": {}, "ride": {}, "land": 1.0, "geared": false},
}

const _GoggleLens = preload("res://scripts/rider/goggle_lens.gd")

var bike_id := "dh"   # the downhill bike is the main bike: every launch starts on it (B / title screen switch)
var computer_id := "classic"   # the bike computer mounted for every ride (ComputerUnits, chosen on the ride setup page)
var computer_cfg := {}   # per bike computer: switched-off pages, alerts, beep, backlight (ComputerUnits.opt)
var goggle_lens := "neutral"   # goggle lens = the ride's colour grade (scripts/rider/goggle_lens.gd), picked on the ride setup page
var _lens_saved := "neutral"   # what save.cfg holds (a BMX_LENS test override is never written)
var bmx_tyre := ""   # tyre model on the BMX ("" = the stock wheels); the DH frames take theirs from the garage build
var seed := 0
var level := ""   # "" = the procedural world; "playground" = the test playground (LEVELS menu, --level=, BMX_LEVEL). Not saved
var records := {"longest": 0.0, "highest": 0.0, "air": 0.0, "top_speed": 0.0, "jumps": 0, "distance": 0.0}

func _ready() -> void:
	randomize()
	seed = randi() % 1000000
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		for k in records:
			records[k] = cf.get_value("records", k, records[k])
		if cf.has_section("days"):
			for k in cf.get_section_keys("days"):
				var e = cf.get_value("days", k, null)
				if k.is_valid_int() and e is Array and e.size() == 2: days[int(k)] = [float(e[0]), int(e[1])]
		computer_id = String(cf.get_value("game", "computer", computer_id))
		goggle_lens = String(cf.get_value("game", "lens", goggle_lens))
		if not _GoggleLens.has(goggle_lens): goggle_lens = _GoggleLens.DEFAULT
		_lens_saved = goggle_lens
		bmx_tyre = String(cf.get_value("game", "bmx_tyre", ""))
		if not BikeBuild.TYRE_MODELS.has(bmx_tyre): bmx_tyre = ""
		if not ComputerUnits.UNITS.has(computer_id): computer_id = ComputerUnits.DEFAULT
		for id in ComputerUnits.UNITS:
			var c = cf.get_value("computer_" + id, "cfg", {})
			if c is Dictionary: computer_cfg[id] = c
	if BIKES.has(OS.get_environment("BMX_BIKE")): bike_id = OS.get_environment("BMX_BIKE")   # tests: ride this frame
	if BikeBuild.TYRE_MODELS.has(OS.get_environment("BMX_TYRE")): bmx_tyre = OS.get_environment("BMX_TYRE")   # tests: this tyre on the BMX
	if _GoggleLens.has(OS.get_environment("BMX_LENS")): goggle_lens = OS.get_environment("BMX_LENS")   # tests: ride with this lens
	if OS.get_environment("BMX_COMPUTER") != "": computer_id = OS.get_environment("BMX_COMPUTER")   # tests: mount this unit

## the bike to ride: the downhill bike carries the player's garage build (parts change the ride)
func bike_config() -> Dictionary:
	return bike_config_for(bike_id)

func bike_config_for(id: String) -> Dictionary:
	var cfg: Dictionary = BIKES[id].duplicate(true)
	if cfg.get("garage", false):
		var b := BikeBuild.load_build(id)
		var mods := BikeBuild.ride_mods(b)
		cfg.build = b
		cfg.mods = mods
		for k in mods.ride:
			cfg.ride[k] = float(cfg.ride.get(k, 1.0)) * float(mods.ride[k])
		# the frame's own character: geometry, weight, suspension design, class (BikeBuild.frame_mods)
		var fm := BikeBuild.frame_mods(id, b)
		for k in fm:
			cfg.ride[k] = float(cfg.ride.get(k, 1.0)) * float(fm[k])
		cfg.kg = BikeBuild.bike_kg(id, b)
	elif bmx_tyre != "":
		cfg.tyre_build = BikeBuild.bmx_build(bmx_tyre)
	return cfg

func save() -> void:
	if OS.get_environment("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
	var cf := ConfigFile.new()
	cf.set_value("game", "bike", bike_id)
	cf.set_value("game", "computer", computer_id)
	if OS.get_environment("BMX_LENS") == "": _lens_saved = goggle_lens
	cf.set_value("game", "lens", _lens_saved)
	cf.set_value("game", "bmx_tyre", bmx_tyre)
	for id in computer_cfg:
		cf.set_value("computer_" + id, "cfg", computer_cfg[id])
	for k in records:
		cf.set_value("records", k, records[k])
	var oldest := today() - KEEP_DAYS
	for d in days:
		if int(d) >= oldest: cf.set_value("days", str(d), days[d])
	cf.save(SAVE)

# ---------------------------------------------------------------- activity log (title card: this week + streak)
## per day ridden (key = days since 1970, local date): [metres, rides]. A ride counts as an activity once it
## has covered ACTIVITY_M; the streak is Zwift-style: weeks in a row (Monday to Sunday) with at least one.
const ACTIVITY_M := 200.0
const KEEP_DAYS := 800
var days := {}
var _ride_m := 0.0          # this ride so far
var _live := false          # a ride of the player's (not the demo AI, the menu backdrop or a test run)
var _ride_counted := true   # this ride is already an activity

## a new ride starts (RIDE / GO): its distance is logged, and it becomes an activity after ACTIVITY_M
func begin_ride() -> void:
	_live = not Settings._test_run
	_ride_m = 0.0
	_ride_counted = false

func end_ride() -> void:
	_live = false   # nothing more is logged until the next begin_ride
	flush_records()

## called by the HUD with the metres ridden this step
func add_distance(ds: float) -> void:
	records.distance = float(records.distance) + ds
	touch_records()
	if not _live: return
	var d := today()
	var e: Array = days.get(d, [0.0, 0])
	e[0] = float(e[0]) + ds
	_ride_m += ds
	if not _ride_counted and _ride_m >= ACTIVITY_M:
		_ride_counted = true
		e[1] = int(e[1]) + 1
	days[d] = e

static func today() -> int:
	var t := Time.get_datetime_dict_from_system()   # local date
	t.hour = 12; t.minute = 0; t.second = 0
	return floori(Time.get_unix_time_from_datetime_dict(t) / 86400.0)

## Monday-based week number (1970-01-01 was a Thursday)
static func week_of(day: int) -> int:
	return floori((day + 3) / 7.0)

## {metres, rides} ridden in the week holding `day` (default this week)
func week_totals(day := -1) -> Dictionary:
	if day < 0: day = today()
	var w := week_of(day)
	var m := 0.0; var n := 0
	for d in days:
		if week_of(int(d)) == w:
			m += float(days[d][0]); n += int(days[d][1])
	return {"metres": m, "rides": n}

## weeks in a row with an activity, ending this week (or last week while this one has none yet: still alive)
func week_streak() -> int:
	var weeks := {}
	for d in days:
		if int(days[d][1]) > 0: weeks[week_of(int(d))] = true
	var w := week_of(today())
	if not weeks.has(w): w -= 1
	var n := 0
	while weeks.has(w):
		n += 1; w -= 1
	return n

func new_seed() -> int:
	seed = randi() % 1000000
	return seed

## Returns true when `val` beat the record (and stores it).
func submit(k: String, val: float) -> bool:
	if val > float(records.get(k, 0.0)) + 1e-6:
		records[k] = val
		save()
		return true
	return false


## quit the game: first let C# collect + finalize its garbage while the engine is still up (CsGc.cs) - the
## terrain's leftovers finalized after shutdown crashed the quit. Use instead of get_tree().quit().
func quit(code := 0) -> void:
	flush_records()
	cs_gc()
	get_tree().quit(code)


static func cs_gc() -> void:
	var gc = CrashLog.cs_new("res://scripts/core/CsGc.cs")   # (ClassDB never finds C# classes: this never ran before)
	if gc: gc.collect()


## records changed (top speed, distance): saved at most every SAVE_EVERY seconds while riding, and always on
## close / quit, so closing the window no longer loses them
const SAVE_EVERY := 15.0
var _rec_dirty := false
var _rec_saved_at := 0.0
func touch_records() -> void:
	if Settings._test_run: return
	_rec_dirty = true
	var now := Time.get_ticks_msec() / 1000.0
	if now - _rec_saved_at >= SAVE_EVERY: flush_records()

func flush_records() -> void:
	if not _rec_dirty: return
	_rec_dirty = false
	_rec_saved_at = Time.get_ticks_msec() / 1000.0
	save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_records()
		cs_gc()   # the window's close button (auto-accepted right after)

