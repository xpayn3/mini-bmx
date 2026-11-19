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
	"turnSlow": 1.0, "turnFast": 1.1,
	"leanMax": 1.1, "leanIn": 0.8, "leanOut": 0.8, "leanDamp": 1.2,
	"legStiff": 0.6, "legDamp": 1.2, "legComp": 1.3, "legExt": 1.3, "attackDrop": 1.3,
	"pedalLaunch": 0.75, "pedalPower": 0.85, "pedalTop": 1.35, "airDrag": 0.85, "brakeForce": 1.3, "popPower": 0.7,
	"grip": 1.15, "oversteer": 0.7,
	"tyreHz": 0.75, "tyreDamp": 1.3, "travel": 2.2,
}

const BIKES := {
	"dh": {
		"label": "Downhill", "file": "res://assets/dh.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE,
		"land": 1.45, "geared": true, "decals": true, "garage": true,
	},
	# the YT Tues frame with its own fork, bars, brakes and cranks (tools/export_tues.py)
	"tues": {"label": "YT Tues", "file": "res://assets/tues.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE, "land": 1.45, "geared": true, "garage": true},
	# the Sketchfab "DH bike frame" (CC-BY, assets/dhframe_LICENSE.txt) on our fork / bars / cranks (tools/export_dhframe.py)
	"goat": {"label": "Goat DH", "file": "res://assets/dhframe.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE, "land": 1.45, "geared": true, "garage": true},
	# the NS Bikes Fuzz frame with its own fork, bars, brakes, cranks and derailleur (tools/export_fuzz.py)
	"fuzz": {"label": "NS Fuzz", "file": "res://assets/fuzz.glb", "root": "dh", "pose": DH_POSE, "ride": DH_RIDE, "land": 1.45, "geared": true, "garage": true},
	"bmx": {"label": "BMX", "file": "res://assets/bmx.glb", "root": "bmx", "pose": {}, "ride": {}, "land": 1.0, "geared": false},
}

var bike_id := "dh"   # the downhill bike is the main bike: every launch starts on it (B / title screen switch)
var computer_id := "classic"   # the bike computer mounted for every ride (ComputerUnits, chosen on the ride setup page)
var computer_cfg := {}   # per bike computer: switched-off pages, alerts, beep, backlight (ComputerUnits.opt)
var seed := 0
var records := {"longest": 0.0, "highest": 0.0, "air": 0.0, "top_speed": 0.0, "jumps": 0, "distance": 0.0}

func _ready() -> void:
	randomize()
	seed = randi() % 1000000
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		for k in records:
			records[k] = cf.get_value("records", k, records[k])
		computer_id = String(cf.get_value("game", "computer", computer_id))
		if not ComputerUnits.UNITS.has(computer_id): computer_id = ComputerUnits.DEFAULT
		for id in ComputerUnits.UNITS:
			var c = cf.get_value("computer_" + id, "cfg", {})
			if c is Dictionary: computer_cfg[id] = c
	if BIKES.has(OS.get_environment("BMX_BIKE")): bike_id = OS.get_environment("BMX_BIKE")   # tests: ride this frame
	if OS.get_environment("BMX_COMPUTER") != "": computer_id = OS.get_environment("BMX_COMPUTER")   # tests: mount this unit

## the bike to ride: the downhill bike carries the player's garage build (parts change the ride)
func bike_config() -> Dictionary:
	var cfg: Dictionary = BIKES[bike_id].duplicate(true)
	if cfg.get("garage", false):
		var b := BikeBuild.load_build()
		var mods := BikeBuild.ride_mods(b)
		cfg.build = b
		cfg.mods = mods
		for k in mods.ride:
			cfg.ride[k] = float(cfg.ride.get(k, 1.0)) * float(mods.ride[k])
	return cfg

func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "bike", bike_id)
	cf.set_value("game", "computer", computer_id)
	for id in computer_cfg:
		cf.set_value("computer_" + id, "cfg", computer_cfg[id])
	for k in records:
		cf.set_value("records", k, records[k])
	cf.save(SAVE)

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
	cs_gc()
	get_tree().quit(code)


static func cs_gc() -> void:
	if ClassDB.class_exists("CsGc"): ClassDB.instantiate("CsGc").collect()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: cs_gc()   # the window's close button (auto-accepted right after)

