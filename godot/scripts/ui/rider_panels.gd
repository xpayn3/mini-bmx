class_name RiderPanels
extends RefCounted
## Rider pose / look data and saving (user://rider.cfg). The sliders live in the tuning card
## (scripts/ui/tune_card.gd: Rider and Look tabs) and the garage Rider tab.

const PATH := "user://rider.cfg"

const POSE_DEFS := [
	["Body position", [
		["hipX", "Hips forward / back", -0.25, 0.25, 0.005, "m"],
		["hipY", "Hips up / down", -0.2, 0.2, 0.005, "m"],
		["lean", "Chest lean forward", -0.4, 0.7, 0.01, "rad"],
		["torso", "Torso length", 0.36, 0.56, 0.005, "m"],
	]],
	["Spine", [
		["spineCurve", "Back hunch (+) / arch (-)", -0.3, 0.3, 0.005, ""],
		["spineSide", "Spine side curve", -0.2, 0.2, 0.005, ""],
		["spineLow", "Bend low (hips) / high (shoulders)", 0.1, 0.9, 0.01, ""],
		["twist", "Torso twist", -0.6, 0.6, 0.01, "rad"],
	]],
	["Pelvis", [
		["hipZ", "Hips side shift", -0.15, 0.15, 0.005, "m"],
		["pelvisTilt", "Pelvis tilt fwd / back", -0.5, 0.5, 0.01, "rad"],
		["pelvisRoll", "Pelvis roll (hip drop)", -0.4, 0.4, 0.01, "rad"],
		["pelvisYaw", "Pelvis turn", -0.5, 0.5, 0.01, "rad"],
	]],
	["Chest", [
		["chestFwd", "Chest forward / back", -0.2, 0.2, 0.005, "m"],
		["chestUp", "Chest up / down", -0.2, 0.2, 0.005, "m"],
		["chestSide", "Chest side bend", -0.15, 0.15, 0.005, "m"],
	]],
	["Head", [
		["headTilt", "Head tilt (+ looks down)", -0.5, 0.5, 0.01, "rad"],
		["lookAhead", "Head forward", -0.08, 0.12, 0.005, "m"],
		["neck", "Neck length", -0.06, 0.08, 0.005, "m"],
		["headYaw", "Head turn (fixed)", -0.8, 0.8, 0.01, "rad"],
		["headRoll", "Head roll", -0.5, 0.5, 0.01, "rad"],
		["headTurn", "Look into turns", 0.0, 2.0, 0.05, "×"],
	]],
	["Shoulders & arms", [
		["shoulders", "Shoulder width", 0.095, 0.235, 0.005, "m"],
		["elbowsOut", "Elbows out", -1.0, 1.0, 0.05, ""],
		["shoulderFwd", "Shoulders forward / back", -0.1, 0.1, 0.005, "m"],
		["shoulderUp", "Shoulders up / down", -0.1, 0.1, 0.005, "m"],
		["elbowsDown", "Elbows down / up", -1.0, 1.0, 0.05, ""],
		["elbowsBack", "Elbows back / forward", -1.0, 1.0, 0.05, ""],
		["armBend", "Arm bend (chest to bars)", -0.4, 1.5, 0.05, ""],
		["elbowOutL", "Left elbow out", -1.0, 1.0, 0.05, ""],
		["elbowOutR", "Right elbow out", -1.0, 1.0, 0.05, ""],
		["wristRoll", "Wrist roll", -0.8, 0.8, 0.02, "rad"],
	]],
	["Legs & feet", [
		["stance", "Hip width", -0.09, 0.04, 0.005, "m"],
		["kneesOut", "Knees out", -0.3, 0.7, 0.05, ""],
		["kneesFwd", "Knees forward / back", -0.8, 0.8, 0.05, ""],
		["kneeOutL", "Left knee out", -0.5, 0.5, 0.05, ""],
		["kneeOutR", "Right knee out", -0.5, 0.5, 0.05, ""],
		["heelFwd", "Heels forward / back", -0.08, 0.08, 0.005, "m"],
		["heelUp", "Heels up / down", -0.06, 0.08, 0.005, "m"],
		["footAngle", "Foot angle (toes down)", -0.5, 0.5, 0.01, "rad"],
		["footOut", "Toes out", -0.4, 0.6, 0.01, "rad"],
	]],
	["Movement", [
		["crouch", "Crouch depth", 0.0, 2.0, 0.05, "×"],
		["standPedal", "Stand up to pedal", 0.0, 2.0, 0.05, "×"],
		["aero", "Speed tuck (aero)", 0.0, 2.0, 0.05, "×"],
		["sway", "Body sway", 0.0, 2.0, 0.05, "×"],
		["bikeRock", "Bike rock (sprint)", 0.0, 2.0, 0.05, "×"],
		["upright", "Torso stays upright", 0.0, 1.0, 0.05, ""],
		["hipSway", "Hip sway", 0.0, 0.12, 0.005, "m"],
		["bodyBob", "Body bob (up / down)", 0.0, 4.0, 0.05, "×"],
		["attackStand", "Stand when rolling", 0.0, 1.5, 0.05, "×"],
		["kneeOpen", "Inside knee opens in turns", 0.0, 2.0, 0.05, "×"],
		["bumpAbsorb", "Bump bounce (body soaks bumps)", 0.0, 3.0, 0.05, "×"],
		["bodyBounce", "Body bounce damping (low = springy)", 0.15, 1.0, 0.01, ""],
	]],
	["Style", [
		["hipSteady", "Hips steady (up / down)", 20.0, 400.0, 5.0, ""],
		["standHeight", "Stand height", 0.0, 0.3, 0.005, "m"],
		["standBack", "Hips back when standing", -0.1, 0.15, 0.005, "m"],
		["pedalChest", "Chest up when pedalling", -0.2, 0.3, 0.01, "rad"],
		["turnLow", "Get low in turns", 0.0, 3.0, 0.05, "×"],
		["turnTwist", "Shoulders into turns", 0.0, 3.0, 0.05, "×"],
		["turnHips", "Hips into turns", 0.0, 3.0, 0.05, "×"],
		["slowWobble", "Balance wobble when slow", 0.0, 3.0, 0.05, "×"],
		["airCrouch", "Crouch in the air", 0.0, 3.0, 0.05, "×"],
	]],
]

const KITS := [
	["Classic", {}],   # = Rider.DEFAULT_LOOK
	["Stealth", {"shell": "#0c0d0f", "peak": "#1a1b1e", "goggleFrame": "#18191c", "lens": "#8a96a8", "strap": "#2a2c30",
		"jersey": "#2b2e33", "pants": "#111215", "gloves": "#3a3d42", "shoes": "#141518", "shoeAccent": "#3a3d42"}],
	["Race white", {"shell": "#f4f4f0", "peak": "#e8231f", "goggleFrame": "#e8231f", "lens": "#3fb6ff", "strap": "#e8231f",
		"jersey": "#f4f4f0", "pants": "#202227", "gloves": "#e8231f", "shoes": "#f4f4f0", "shoeAccent": "#e8231f"}],
	["Monster", {"shell": "#7ed321", "peak": "#111214", "goggleFrame": "#111214", "lens": "#7ed321", "strap": "#7ed321",
		"jersey": "#111214", "pants": "#2c2f33", "gloves": "#7ed321", "shoes": "#111214", "shoeAccent": "#7ed321"}],
	["Ocean", {"shell": "#1478d4", "peak": "#f4f4f0", "goggleFrame": "#f4f4f0", "lens": "#ff9f2e", "strap": "#1478d4",
		"jersey": "#11b3c9", "pants": "#0d2847", "gloves": "#f4f4f0", "shoes": "#0d2847", "shoeAccent": "#11b3c9"}],
	["Sunset", {"shell": "#ff7a1a", "peak": "#6a1b9a", "goggleFrame": "#6a1b9a", "lens": "#ffd21f", "strap": "#ff7a1a",
		"jersey": "#6a1b9a", "pants": "#2a2140", "gloves": "#ff7a1a", "shoes": "#2a2140", "shoeAccent": "#ff7a1a"}],
]
const SW := ["#f4f4f0", "#16171a", "#e8231f", "#ff7a1a", "#ffd21f", "#7ed321", "#11b3c9", "#1478d4", "#6a1b9a", "#ff5fa2"]
const LENS := ["#ff7a2a", "#ffd21f", "#3fb6ff", "#7ed321", "#ff5fa2", "#8a96a8", "#d0d4da"]
const LOOK_ROWS := [
	["Helmet", [["shell", "Shell", SW], ["peak", "Peak", SW]]],
	["Goggles", [["lens", "Lens tint", LENS], ["goggleFrame", "Frame", SW], ["strap", "Strap", SW]]],
	["Kit", [["jersey", "Jersey", SW], ["pants", "Pants", SW], ["gloves", "Gloves", SW]]],
	["Shoes", [["shoes", "Upper", SW], ["shoeAccent", "Toe & collar", SW]]],
]

# ---------------------------------------------------------------- persistence
## bump POSE_VER when a bike's default pose is retuned: a pose saved before keeps every value except the
## RETUNED ones that still hold the OLD default (a slider the player moved stays theirs)
const POSE_VER := 2
const POSE_RETUNED := {"elbowsOut": -0.25, "elbowOutR": -0.05, "hipSway": 0.015}

static func load_pose(bike_id: String, bike_pose: Dictionary) -> Dictionary:
	var p: Dictionary = Rider.NEUTRAL.duplicate()
	p.merge(bike_pose, true)
	var cf := ConfigFile.new()
	var sec := "pose_" + bike_id
	if cf.load(PATH) == OK and cf.has_section(sec):
		var old := int(cf.get_value(sec, "_ver", 1)) < POSE_VER
		for k in cf.get_section_keys(sec):
			var val = cf.get_value(sec, k)
			if not p.has(k) or not typeof(val) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
				continue
			if old and POSE_RETUNED.has(k) and absf(float(val) - float(POSE_RETUNED[k])) < 1e-3:
				continue   # still the old default: take the new one
			p[k] = val
	return p

static func save_pose(bike_id: String, p: Dictionary) -> void:
	var cf := ConfigFile.new(); cf.load(PATH)
	if cf.has_section("pose_" + bike_id): cf.erase_section("pose_" + bike_id)
	for k in p: cf.set_value("pose_" + bike_id, k, p[k])
	cf.set_value("pose_" + bike_id, "_ver", POSE_VER)
	cf.save(PATH)

static func load_look() -> Dictionary:
	var l: Dictionary = Rider.DEFAULT_LOOK.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK and cf.has_section("look"):
		for k in cf.get_section_keys("look"):
			if l.has(k): l[k] = str(cf.get_value("look", k))
	return l

static func save_look(l: Dictionary) -> void:
	var cf := ConfigFile.new(); cf.load(PATH)
	for k in l: cf.set_value("look", k, l[k])
	cf.save(PATH)
