extends Node
## Steam: start-up, achievements, rich presence (autoload `Steam`). Wraps SteamService.cs (Steamworks.NET).
## Without Steam (plain Godot, Steam client closed, test runs, BMX_NO_STEAM=1) every call does nothing.
##
## Before release:
## - APP_ID = your app's number (Steamworks > App Admin), and the same number in `steam_appid.txt`.
##   480 = Valve's public test app "Spacewar" (achievement calls fail on it: it has its own list).
## - Create each id in ACHIEVEMENTS in Steamworks > Stats & Achievements (API name = the id), publish.
## - RESTART_OUTSIDE_STEAM = true once the real App ID is in: a copy started outside Steam relaunches through it.

const APP_ID := 480
const RESTART_OUTSIDE_STEAM := false

## API name -> [display name, description, how it's earned]. Names / descriptions are what to enter in Steamworks.
## kind: "rec" = GameState.records[key] >= val, "trick" = a landed trick whose name contains val,
## "event" = unlocked by name from code (Steam.event(id)).
const ACHIEVEMENTS := {
	"FIRST_DROP":   ["First Drop", "Start your first ride.", "event"],
	"AIR_1S":       ["Hang Time", "Stay in the air for 1 second.", "rec", "air", 1.0],
	"AIR_3S":       ["Frequent Flyer", "Stay in the air for 3 seconds.", "rec", "air", 3.0],
	"LONG_20":      ["Long Jump", "Land a jump 20 m long.", "rec", "longest", 20.0],
	"LONG_50":      ["Gap Year", "Land a jump 50 m long.", "rec", "longest", 50.0],
	"HIGH_8":       ["Up There", "Get 8 m above the ground.", "rec", "highest", 8.0],
	"SPEED_60":     ["Quick", "Reach 60 km/h.", "rec", "top_speed", 60.0],
	"SPEED_80":     ["Terminal Velocity", "Reach 80 km/h.", "rec", "top_speed", 80.0],
	"JUMPS_100":    ["Air Miles", "Land 100 jumps.", "rec", "jumps", 100.0],
	"DIST_10K":     ["Trail Dog", "Ride 10 km in total.", "rec", "distance", 10000.0],
	"DIST_100K":    ["Century", "Ride 100 km in total.", "rec", "distance", 100000.0],
	"FLIP":         ["Head Over Heels", "Land a flip.", "trick", "FLIP"],
	"SPIN_360":     ["Full Circle", "Land a 360.", "trick", "360"],
	"SPIN_720":     ["Twice Round", "Land a 720.", "trick", "720"],
	"FAKIE":        ["Wrong Way Round", "Ride away from a backwards landing.", "trick", "FAKIE"],
	"WASTED":       ["Wasted", "Crash hard.", "event"],
	"REVIVE":       ["Not Today", "Get back up after being knocked out.", "event"],
	"GARAGE":       ["Wrench", "Save a bike build in the garage.", "event"],
	"PHOTO":        ["Shutterbug", "Take a photo in photo mode.", "event"],
	"HEALTH_PACK":  ["Patched Up", "Pick up a health pack.", "event"],
}

var on := false           # Steam is up
var player_name := ""     # the Steam name ("" without Steam)
var _svc = null           # SteamService (C#)
var _poll := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var forced := OS.get_environment("BMX_STEAM") != ""   # tests: start Steam anyway
	var args := OS.get_cmdline_args()
	var tool_run := DisplayServer.get_name() == "headless" or args.has("-s") or args.has("--script")   # tools / headless exports
	# On the placeholder app 480 ("Spacewar") Steam Input takes the Xbox pad: the game got no buttons / sticks at all
	# while Steam ran (measured). So Steam only starts with the real App ID, or when forced (BMX_STEAM=1).
	var placeholder := APP_ID == 480 and not forced
	if placeholder or (Settings._test_run and not forced) or tool_run or OS.get_environment("BMX_NO_STEAM") != "" or not ClassDB.class_exists("CSharpScript"):
		return
	var s = load("res://scripts/core/SteamService.cs")
	if s == null: return
	_svc = s.new()
	if RESTART_OUTSIDE_STEAM and not OS.has_feature("editor") and _svc.RestartIfNeeded(APP_ID):
		get_tree().quit()
		return
	on = _svc.Init()
	if on:
		player_name = _svc.PlayerName()
		print("Steam: ready, ", player_name)
	else:
		print("Steam: off (", _svc.Error, ")")
		_svc = null

func _process(dt: float) -> void:
	if not on: return
	_svc.Tick()
	_poll += dt
	if _poll > 1.0:
		_poll = 0.0
		_check_records()

func _exit_tree() -> void:
	if on: _svc.Shutdown()
	on = false

func _check_records() -> void:
	for id in ACHIEVEMENTS:
		var a: Array = ACHIEVEMENTS[id]
		if a[2] == "rec" and float(GameState.records.get(a[3], 0.0)) >= float(a[4]):
			unlock(id)

## unlocks once; true if it was new
func unlock(id: String) -> bool:
	if not on or not ACHIEVEMENTS.has(id): return false
	return _svc.Unlock(id)

## an "event" achievement happened (safe to call every time)
func event(id: String) -> void:
	unlock(id)

## a landed trick by its HUD name ("360 BACKFLIP", "FAKIE!"...)
func trick(name: String) -> void:
	if not on: return
	var up := name.to_upper()
	for id in ACHIEVEMENTS:
		var a: Array = ACHIEVEMENTS[id]
		if a[2] == "trick" and up.contains(String(a[3])): unlock(id)

## what friends see in their Steam list ("Riding · Desert", "In the garage")
func presence(text: String) -> void:
	if on: _svc.SetRichPresence("status", text)
