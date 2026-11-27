extends Node
## Session + save data: which bike, which world seed, and the player's records.
## Records persist in user://save.cfg.

const SAVE := "user://save.cfg"

## Bikes. `ride` multiplies the tuning values (see Tune); `pose` is handed to the rider.
## the GLORY DH rider pose / ride feel, shared by the downhill frames
const DH_POSE := {"hipX": -0.07, "hipY": 0.075, "lean": 0.22, "elbowsOut": 0.0, "shoulders": 0.19, "torso": 0.52, "hipSway": 0.035, "kneesOut": 0.25, "stance": -0.035, "seatFloor": true,
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
## a saved replay being watched (ReplayMode header: seed, bike, build, look, pose): the ride is built from it, not
## from the garage / rider files. Empty = a normal ride
var view := {}
var level := ""   # "" = the procedural world; "playground" = the test playground (LEVELS menu, --level=, BMX_LEVEL). Not saved
var records := {"longest": 0.0, "highest": 0.0, "air": 0.0, "top_speed": 0.0, "jumps": 0, "distance": 0.0, "earned": 0.0, "best_streak": 0, "best_wstreak": 0}
## The wallet + what the player owns (the SHOP, garage mode "shop"). owned: "kind:id" keys (Shop.price kinds:
## "edition:ghost_pepper", "frame:goat", "fork:dh38"...). A new save starts with STARTING_MONEY and the stock
## RUNOUT DH with the parts it is built with. Saved in save.cfg [shop]. Shop.UNLOCK_ALL still lets the garage use
## everything; ownership shows as OWNED in the shop. Tests: BMX_MONEY=n starts with that much (not saved).
const STARTING_MONEY := 15000
var money := STARTING_MONEY
var owned := {}
## the wallet's ledger, newest last: [unix time, amount (+ earned / - spent), what for]; kept to LEDGER_MAX
var wallet_log: Array = []
const LEDGER_MAX := 60
var claimed := {}   # goals already paid (Goals keys)

## cash in: logged, counted in the lifetime total
func earn(amount: int, reason: String) -> void:
	if amount <= 0: return
	money += amount
	records.earned = float(records.earned) + amount
	_log(amount, reason)
	touch_records()

## cash out (the shop pays through buy()); false when it can't be afforded
func spend(amount: int, reason: String) -> bool:
	if amount > money: return false
	money -= amount
	_log(-amount, reason)
	touch_records()
	return true

func _log(amount: int, reason: String) -> void:
	wallet_log.append([int(Time.get_unix_time_from_system()), amount, reason])
	while wallet_log.size() > LEDGER_MAX: wallet_log.pop_front()
	_ride_log_idx = -1

## earned in the last `days` days (from the ledger)
func earned_since(days: int) -> int:
	var t0 := int(Time.get_unix_time_from_system()) - days * 86400
	var n := 0
	for e in wallet_log:
		if int(e[0]) >= t0 and int(e[1]) > 0: n += int(e[1])
	return n

func owns(key: String) -> bool:
	return owned.has(key)

## pays and takes it home. False when it can't be afforded (or is owned already)
func buy(key: String, price: int) -> bool:
	if owned.has(key) or price > money: return false
	spend(price, "Bought " + key.replace(":", " ").capitalize())
	owned[key] = Time.get_unix_time_from_system()
	save()
	return true

## the parts a build carries, as owned keys (the starter bike, a bought complete bike)
static func build_keys(frame: String, b: Dictionary) -> Array:
	var out := ["frame:" + frame]
	var W: Dictionary = b.get("wheels", {})
	var S: Dictionary = b.get("suspension", {})
	for kv in [["tyre", W.get("tyre_model", "")], ["rim", W.get("rim_model", "")], ["fork", S.get("fork_model", "")],
			["shock", S.get("shock_model", "")], ["bar", b.get("bars", {}).get("model", "")],
			["cassette", b.get("drive", {}).get("cassette", "")], ["light", b.get("lights", {}).get("model", "")]]:
		if str(kv[1]) != "" and str(kv[1]) != "custom": out.append("%s:%s" % [kv[0], kv[1]])
	return out

func _ready() -> void:
	randomize()
	seed = randi() % 1000000
	var cf := ConfigFile.new()
	var loaded := cf.load(SAVE) == OK
	if loaded and cf.has_section("shop"):
		money = int(cf.get_value("shop", "money", STARTING_MONEY))
		var o = cf.get_value("shop", "owned", {})
		if o is Dictionary: owned = o
	else:   # a new player (or a save from before the shop): the stock RUNOUT DH as it is built
		for k in build_keys("dh", BikeBuild.load_build("dh")): owned[k] = 0
		for k in Catalog.STARTER: owned[k] = 0
	if Env.raw("BMX_MONEY") != "": money = int(Env.raw("BMX_MONEY"))
	if loaded:
		for k in records:
			records[k] = cf.get_value("records", k, records[k])
		if cf.has_section("days"):
			for k in cf.get_section_keys("days"):
				var e = cf.get_value("days", k, null)
				if k.is_valid_int() and e is Array and e.size() == 2: days[int(k)] = [float(e[0]), int(e[1])]
		computer_id = String(cf.get_value("game", "computer", computer_id))
		rider_name = String(cf.get_value("game", "name", rider_name))
		var wl = cf.get_value("shop", "log", [])
		if wl is Array: wallet_log = wl
		var cl = cf.get_value("shop", "claimed", {})
		if cl is Dictionary: claimed = cl
		var ts = cf.get_value("game", "tricks", {})
		if ts is Dictionary: tricks_seen = ts
		var br = cf.get_value("game", "bikes", {})
		if br is Dictionary: bikes_ridden = br
		if cf.has_section("achievements"):
			for k in cf.get_section_keys("achievements"): achieved[k] = int(cf.get_value("achievements", k, 0))
		if cf.has_section("skills"):
			for k in cf.get_section_keys("skills"): skill_xp[k] = float(cf.get_value("skills", k, 0.0))
		else:   # a save from before the XP system: what the records had earned becomes the starting XP
			skill_xp = Skills.seed_from_records(records, tricks_seen.size(), maxi(int(records.best_streak), day_streak()))
		if Env.raw("BMX_SKILLS") == "fresh": skill_xp = {}   # tests: every skill from level 1
		goggle_lens = String(cf.get_value("game", "lens", goggle_lens))
		if not _GoggleLens.has(goggle_lens): goggle_lens = _GoggleLens.DEFAULT
		_lens_saved = goggle_lens
		bmx_tyre = String(cf.get_value("game", "bmx_tyre", ""))
		if not BikeBuild.TYRE_MODELS.has(bmx_tyre): bmx_tyre = ""
		if not ComputerUnits.UNITS.has(computer_id): computer_id = ComputerUnits.DEFAULT
		for id in ComputerUnits.UNITS:
			var c = cf.get_value("computer_" + id, "cfg", {})
			if c is Dictionary: computer_cfg[id] = c
	if BIKES.has(Env.raw("BMX_BIKE")): bike_id = Env.raw("BMX_BIKE")   # tests: ride this frame
	if BikeBuild.TYRE_MODELS.has(Env.raw("BMX_TYRE")): bmx_tyre = Env.raw("BMX_TYRE")   # tests: this tyre on the BMX
	if _GoggleLens.has(Env.raw("BMX_LENS")): goggle_lens = Env.raw("BMX_LENS")   # tests: ride with this lens
	if Env.raw("BMX_COMPUTER") != "": computer_id = Env.raw("BMX_COMPUTER")   # tests: mount this unit

## the bike to ride: the downhill bike carries the player's garage build (parts change the ride)
func bike_config() -> Dictionary:
	return bike_config_for(bike_id)

func bike_config_for(id: String) -> Dictionary:
	var cfg: Dictionary = BIKES[id].duplicate(true)
	if cfg.get("garage", false):
		var b: Dictionary = view.build if (not view.is_empty() and view.get("bike", "") == id and view.get("build") is Dictionary and not (view.build as Dictionary).is_empty()) else BikeBuild.load_build(id)
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
	if Settings._no_save: return   # test runs (autotest, PADSEQ, bench, shots...): never into the player's files
	var cf := ConfigFile.new()
	cf.set_value("game", "bike", bike_id)
	cf.set_value("game", "computer", computer_id)
	cf.set_value("game", "name", rider_name)
	cf.set_value("game", "tricks", tricks_seen)
	cf.set_value("game", "bikes", bikes_ridden)
	for id in achieved: cf.set_value("achievements", id, achieved[id])
	for id in skill_xp: cf.set_value("skills", id, snappedf(float(skill_xp[id]), 0.01))
	if Env.raw("BMX_LENS") == "": _lens_saved = goggle_lens
	cf.set_value("game", "lens", _lens_saved)
	cf.set_value("game", "bmx_tyre", bmx_tyre)
	for id in computer_cfg:
		cf.set_value("computer_" + id, "cfg", computer_cfg[id])
	for k in records:
		cf.set_value("records", k, records[k])
	cf.set_value("shop", "money", money)
	cf.set_value("shop", "owned", owned)
	cf.set_value("shop", "log", wallet_log)
	var live_claims := {}
	for k in claimed:   # old goals fall out (this week / month's keys carry their number)
		live_claims[k] = true
	cf.set_value("shop", "claimed", live_claims)
	var oldest := today() - KEEP_DAYS
	for d in days:
		if int(d) >= oldest: cf.set_value("days", str(d), days[d])
	Settings.save_cfg(cf, SAVE)

# ---------------------------------------------------------------- activity log (title card: this week + streak)
## per day ridden (key = days since 1970, local date): [metres, rides]. A ride counts as an activity once it
## has covered ACTIVITY_M; the streak is Zwift-style: weeks in a row (Monday to Sunday) with at least one.
const ACTIVITY_M := 200.0
const KEEP_DAYS := 800
var days := {}
## the rider's profile (title menu, top right): a name and the achievements earned (id -> unix time; Steam.ACHIEVEMENTS
## has the list). Kept here whether or not Steam is running, Steam only mirrors it.
var rider_name := "RIDER"
var tricks_seen := {}    # trick keys landed at least once (Collection.TRICK_KEYS values)
var bikes_ridden := {}   # bike id -> rides of at least ACTIVITY_M on it
var achieved := {}

## ---- skills (Skills): XP per skill id, collected while riding; a level up is announced by the HUD
signal skill_leveled(id: String, level: int)
var skill_xp := {}
var skill_gain := {}     # XP gained since the last RIDE press (the profile shows it)
var _skills_test := Env.raw("BMX_SKILLS") != ""

func skill_level(id: String) -> int:
	return Skills.level_of(float(skill_xp.get(id, 0.0)))

## XP in: only for the player's own rides (tests: BMX_SKILLS=1 to try it, never saved)
func skill_add(id: String, amount: float) -> void:
	if amount <= 0.0 or not Skills.DEFS.has(id): return
	if not _live and not _skills_test: return
	var before := skill_level(id)
	skill_xp[id] = float(skill_xp.get(id, 0.0)) + amount
	skill_gain[id] = float(skill_gain.get(id, 0.0)) + amount
	var after := skill_level(id)
	if _skills_test and fmod(float(skill_gain[id]), 25.0) < amount: print("SKILLXP %s xp=%.1f lv=%d" % [id, float(skill_xp[id]), after])   # tests
	if after > before:
		skill_leveled.emit(id, after)
		touch_records()

## every ride step while the bike is up (HUD._ride_stats): speed, cornering, balance
func skill_tick(st, dt: float) -> void:
	if (not _live and not _skills_test) or st.crash_on or st.air: return
	var kmh: float = absf(st.v) * 3.6
	if kmh > Skills.SPEED_FROM: skill_add("speed", (kmh - Skills.SPEED_FROM) * Skills.SPEED_RATE * dt)
	var ln: float = absf(st.lean)
	if ln > Skills.CORNER_LEAN and absf(st.v) > Skills.CORNER_MIN_V:
		skill_add("cornering", Skills.CORNER_RATE * clampf(ln / 0.8, 0.0, 1.5) * dt)
	if (st.man_a > 0.12 or st.nose_a > 0.12) and absf(st.v) > 2.0:
		skill_add("balance", Skills.BALANCE_RATE * dt)

## a jump landed without a crash
func skill_landing(air_time: float, dist: float, height: float) -> void:
	skill_add("jumping", Skills.JUMP_BASE + dist * Skills.JUMP_PER_M)
	skill_add("air", (pow(maxf(height, 0.0), 1.3) * Skills.AIR_PER_M if height > 0.3 else 0.0) + air_time * Skills.AIR_PER_S)

## a trick landed (the first of its family pays extra), and the style points it scored
func skill_trick(trick: String) -> void:
	var fresh := false
	var up := trick.to_upper()
	for frag in Collection.TRICK_KEYS:
		if up.contains(frag) and not tricks_seen.has(Collection.TRICK_KEYS[frag]): fresh = true
	skill_add("style", Skills.TRICK_BONUS + (Skills.NEW_TRICK_BONUS if fresh else 0.0))

func skill_style(points: int) -> void:
	skill_add("style", float(points) * Skills.STYLE_PER_POINT)

## the rider's level from the total distance: one every 20 km
static func level_for(metres: float) -> int:
	return 1 + int(metres / 20000.0)
var _ride_m := 0.0          # this ride so far
var _live := false          # a ride of the player's (not the demo AI, the menu backdrop or a test run)
var _ride_counted := true   # this ride is already an activity

## a new ride starts (RIDE / GO): its distance is logged, and it becomes an activity after ACTIVITY_M
const RIDE_RATE := 0.03        # cash per metre ridden (a 10 km ride = $300)
const DAILY_BASE := 50         # the day's first activity pays this + DAILY_STEP per day of the streak (up to 10)
const DAILY_STEP := 25
var _pending := 0.0            # earned cents not yet whole dollars
var _ride_log_idx := -1        # this ride's entry in the ledger (grows as the ride goes on)

func begin_ride() -> void:
	_ride_log_idx = -1
	_live = not Settings._test_run
	_ride_m = 0.0
	_ride_counted = false
	skill_gain.clear()

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
	skill_add("endurance", ds / 1000.0 * Skills.ENDURANCE_PER_KM)
	_pay_ride(ds)
	if not _ride_counted and _ride_m >= ACTIVITY_M:
		_ride_counted = true
		e[1] = int(e[1]) + 1
		days[d] = e
		bikes_ridden[bike_id] = int(bikes_ridden.get(bike_id, 0)) + 1
		_daily_bonus(d)
	days[d] = e

## the ride pays as it goes: one growing "Ride" line in the ledger
func _pay_ride(ds: float) -> void:
	_pending += ds * RIDE_RATE
	var n := int(_pending)
	if n < 1: return
	_pending -= n
	money += n
	records.earned = float(records.earned) + n
	if _ride_log_idx >= 0 and _ride_log_idx < wallet_log.size():
		wallet_log[_ride_log_idx][1] = int(wallet_log[_ride_log_idx][1]) + n
	else:
		wallet_log.append([int(Time.get_unix_time_from_system()), n, "Ride"])
		while wallet_log.size() > LEDGER_MAX: wallet_log.pop_front()
		_ride_log_idx = wallet_log.size() - 1

## the first activity of a day pays a bonus that grows with the days in a row
func _daily_bonus(day: int) -> void:
	var key := "d%d" % day
	if claimed.has(key): return
	claimed[key] = true
	var n := day_streak()
	earn(DAILY_BASE + DAILY_STEP * mini(n, 10), "Daily bonus · day %d" % n)
	skill_add("consistency", Skills.DAILY_BASE + Skills.DAILY_STEP * mini(n, 10))

## days in a row with an activity, ending today (or yesterday while today has none yet)
func day_streak() -> int:
	var d := today()
	if int(days.get(d, [0.0, 0])[1]) <= 0: d -= 1
	var n := 0
	while int(days.get(d, [0.0, 0])[1]) > 0:
		n += 1; d -= 1
	return n

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

