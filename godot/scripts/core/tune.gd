extends Node
## Ride-feel tuning (port of src/tune.js). Every value the bike's handling depends on, with the
## per-bike multipliers applied on top (BIKES.dh.ride in the web version). Saved to user://tune.cfg.

signal changed

const DEFS := [
	["Steering", [
		["steerRate", "Steer build-up", 15, 1, 25, 0.5, "/s"],
		["steerRelease", "Steer release", 10, 1, 25, 0.5, "/s"],
		["steerCurve", "Soft centre", 0.1, 0, 1, 0.05, ""],
		["turnSlow", "Turn force (slow)", 9, 1, 12, 0.1, "m/s²"],
		["turnFast", "Turn force (fast)", 13, 1, 14, 0.1, "m/s²"],
		["turnFloor", "Min turn rate", 2.6, 0.3, 3.5, 0.05, "rad/s"],
		["steerMax", "Max bar angle", 0.7, 0.2, 0.9, 0.01, "rad"],
		["slowSteer", "Bar angle when slow", 1.2, 0.4, 1.4, 0.02, "rad"],
		["slowSteerFade", "Slow steering fades by", 4, 1, 10, 0.5, "m/s"],
		["barSpeed", "Bar speed", 28, 3, 40, 1, "/s"],
		["counter", "Countersteer flick", 0.2, 0, 0.8, 0.02, ""],
	]],
	["Grip & slides", [
		["grip", "Tyre grip", 1.3, 0.4, 1.6, 0.02, "×"],
		["oversteer", "Rear steps out", 0.35, 0, 1, 0.05, ""],
		["slipRecover", "Slide catch", 8, 0.5, 15, 0.5, "/s"],
		["slipMax", "Wash-out angle", 1.1, 0.4, 1.4, 0.05, "rad"],
	]],
	["Momentum", [
		["turnWeight", "Turn weight", 0.09, 0, 0.5, 0.01, "s"],
		["rollRes", "Rolling resistance", 0.8, 0.3, 1.5, 0.05, "×"],
		["flowCarry", "Flow speed carry", 0.4, 0, 0.8, 0.05, ""],
		["flowTime", "Flow lasts", 4, 1, 10, 0.5, "s"],
	]],
	["Carving", [
		["carveBite", "Carve extra turn", 2.0, 0, 5, 0.1, "m/s²"],
		["carveGrip", "Carve extra grip", 0.12, 0, 0.3, 0.01, "×"],
		["carveBoost", "Carve exit speed", 1.2, 0, 3, 0.1, "m/s"],
	]],
	["Air", [
		["airTwist", "Hip twist in the air", 0.45, 0, 1.4, 0.05, "rad"],
		["flipRate", "Lip throw: max spin (W / S at the lip)", 6.5, 1, 12, 0.1, "rad/s"],
		["flipAccel", "Lip throw: pull", 26, 2, 60, 0.5, "rad/s²"],
		["airTilt", "Body shift tilts the bike (air W / S)", 0.45, 0, 0.9, 0.05, "rad"],
		["tuckSpin", "Tuck spins faster (Space)", 0.35, 0, 0.6, 0.05, ""],
		["riderShare", "Rider's share of the spin", 0.85, 0.5, 0.95, 0.01, ""],
		["airRoll", "Air lean left / right (A / D)", 0.6, 0, 1.2, 0.05, "rad"],
		["landBack", "Back-wheel balance limit", 1.3, 0.5, 1.5, 0.05, "rad"],
		["slamJolt", "Legs take a hit up to", 6.0, 2, 12, 0.1, "m/s"],
		["pivotRate", "Pivot speed (brake + A / D, slow)", 5, 1, 10, 0.25, "rad/s"],
	]],
	["Wheels & pump", [
		["tyreHz", "Bounce frequency", 3.2, 1.2, 7, 0.1, "Hz"],
		["tyreDamp", "Bounce damping", 0.3, 0.05, 1, 0.01, ""],
		["travel", "Suspension travel", 0.14, 0.02, 0.25, 0.005, "m"],
		["legPress", "Legs press bike down", 0.5, 0, 2, 0.05, "g"],
		["riderBalance", "Rider balance (1 wheel)", 0.7, 0, 1.5, 0.05, ""],
		["noseDive", "Nose-dive crash angle", 0.6, 0.3, 1.2, 0.05, "rad"],
		["pumpGain", "Pump strength", 9, 0, 25, 0.5, ""],
	]],
	["Lean", [
		["leanMax", "Max lean", 0.7, 0.15, 1.1, 0.01, "rad"],
		["leanIn", "Roll-in stiffness", 40, 8, 200, 1, ""],
		["leanOut", "Roll-out stiffness", 30, 8, 200, 1, ""],
		["leanDamp", "Lean damping", 1.0, 0.3, 1.6, 0.02, ""],
		["bikeLeanMul", "Bike leans extra", 1.15, 0.7, 1.8, 0.01, "×"],
		["bikeLeanCap", "Bike lean soft cap", 0.8, 0.3, 1.2, 0.01, "rad"],
	]],
	["Legs & body", [
		["legStiff", "Leg spring", 30, 4, 150, 1, ""],
		["legDamp", "Leg damping", 0.75, 0.15, 1.6, 0.01, ""],
		["legComp", "Leg bend travel", 0.2, 0.03, 0.4, 0.01, "m"],
		["legExt", "Leg extend travel", 0.13, 0.02, 0.3, 0.01, "m"],
		["bodyLevel", "Keep body level", 0.85, 0, 1, 0.05, ""],
		["attackDrop", "Get low on descents", 0.18, 0, 0.45, 0.01, "m"],
		["riderMass", "Body weight on legs", 0.45, 0, 0.7, 0.05, ""],
		["weightShift", "Weight shift reach", 0.12, 0, 0.25, 0.01, "m"],
		["loadHeight", "Weight transfer height", 0.25, 0, 1, 0.05, "m"],
		["bodyStiff", "Body follows the bike", 60, 10, 200, 1, ""],
		["bodyInertia", "Body thrown by braking / landings", 0.35, 0, 1.5, 0.01, ""],
	]],
	["Jumping", [
		["prepTime", "Spot lip ahead", 0.55, 0.1, 1.2, 0.05, "s"],
		["prepDepth", "Crouch into lip", 0.16, 0, 0.3, 0.01, "m"],
		["popKick", "Pump extension", 1.5, 0, 4, 0.1, "m/s"],
		["landPrepTime", "Reach for landing", 0.35, 0.05, 1, 0.05, "s"],
		["chargeTime", "Hop charge time", 2, 0.5, 4, 0.1, "s"],
		["chargePop", "Full-charge extra pop", 0.6, 0, 4, 0.1, "m/s"],
	]],
	["Speed", [
		["topSpeed", "Top speed", 1.2, 0.5, 2.0, 0.05, "×"],
		["pedalLaunch", "Launch push", 8, 2, 16, 0.5, "m/s²"],
		["pedalPower", "Pedal power", 21, 5, 50, 1, ""],
		["pedalTop", "Pedal top speed", 11.8, 4, 22, 0.2, "m/s"],
		["airDrag", "Air drag", 0.0036, 0, 0.012, 0.0002, ""],
		["brakeForce", "Brake", 7.5, 2, 15, 0.5, "m/s²"],
		["sprintPower", "Sprint power", 1.5, 1, 2.5, 0.05, "×"],
		["sprintTop", "Sprint extra top speed", 3, 0, 8, 0.2, "m/s"],
		["sprintTime", "Sprint stamina", 20, 3, 60, 1, "s"],
		["sprintRecharge", "Stamina refill time", 45, 5, 120, 1, "s"],
		["popPower", "Pump pop", 2.4, 0.5, 6, 0.1, "m/s"],
	]],
]

const PATH := "user://tune.cfg"
## bump VER when defaults are retuned: saved values of the RETUNED keys are dropped once
const VER := 5
const RETUNED := ["steerRate", "steerRelease", "steerCurve", "turnSlow", "turnFast", "turnFloor", "steerMax", "slowSteer",
	"barSpeed", "grip", "slipRecover", "slipMax", "turnWeight", "leanMax", "leanIn", "leanOut", "leanDamp", "bikeLeanMul", "bikeLeanCap", "flipAccel", "flipRate", "airTwist", "landBack", "travel"]
var defaults := {}
var base := {}       # the player's slider values (before the bike's ride multipliers)
var ride := {}       # multipliers for the bike being ridden
var v := {}          # effective values: base * ride (what the physics reads)
const DEFAULT_PINS := ["slowSteer", "turnWeight", "rollRes", "flowCarry", "carveBoost", "chargePop"]
var pins: Array = DEFAULT_PINS.duplicate()   # sliders on the Quick tune card
var quick_folded := false
signal pins_changed

func _ready() -> void:
	for g in DEFS:
		for row in g[1]:
			defaults[row[0]] = float(row[2])
	base = defaults.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		var old_ver: int = cf.get_value("ui", "ver", 1)
		for k in cf.get_section_keys("tune") if cf.has_section("tune") else []:
			if old_ver < VER and k in RETUNED: continue   # new defaults win over values saved before the retune
			if defaults.has(k):
				base[k] = float(cf.get_value("tune", k))
		pins = cf.get_value("ui", "pins", pins)
		quick_folded = cf.get_value("ui", "quick_folded", false)
		if old_ver < VER: save()
	for kv in OS.get_environment("BMX_TUNE").split(",", false):   # tests: "topSpeed=1.6,grip=1.1" (not saved)
		var p := kv.split("=")
		if p.size() == 2 and defaults.has(p[0]): base[p[0]] = float(p[1])
	_rebuild()

func set_ride(mult: Dictionary) -> void:
	ride = mult
	_rebuild()

func set_value(k: String, val: float) -> void:
	base[k] = val
	_rebuild()
	save()
	TunePresets.value_changed(k, val)

## load a whole preset at once (TunePresets.select)
func apply_values(d: Dictionary) -> void:
	for k in d:
		if defaults.has(k): base[k] = float(d[k])
	_rebuild()
	save()

func reset_defaults() -> void:
	base = defaults.duplicate()
	_rebuild()
	save()

func save() -> void:
	var cf := ConfigFile.new()
	for k in base:
		cf.set_value("tune", k, base[k])
	cf.set_value("ui", "pins", pins)
	cf.set_value("ui", "quick_folded", quick_folded)
	cf.set_value("ui", "ver", VER)
	cf.save(PATH)

func toggle_pin(k: String) -> void:
	if k in pins: pins.erase(k)
	else: pins.append(k)
	save()
	pins_changed.emit()

func row(k: String) -> Array:
	for g in DEFS:
		for r in g[1]:
			if r[0] == k: return r
	return []

func _rebuild() -> void:
	for k in base:
		v[k] = base[k] * float(ride.get(k, 1.0))
	changed.emit()
