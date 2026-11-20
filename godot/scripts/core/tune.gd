extends Node
## Ride-feel tuning (port of src/tune.js). Every value the bike's handling depends on, with the
## per-bike multipliers applied on top (BIKES.dh.ride in the web version). Saved to user://tune.cfg.

signal changed

const DEFS := [
	# the Feel page (2026-11-20): big-picture sliders, 1 = as the detail sliders have it. Each scales a set of
	# detail values (MACROS, x m^exp) on top of the player's sliders and the bike's multipliers
	["Feel", [
		["feelGrip", "Grip", 1.0, 0.5, 1.5, 0.05, ""],
		["feelAgile", "Handling", 1.0, 0.5, 1.5, 0.05, ""],
		["feelSlide", "Slides", 1.0, 0.5, 1.5, 0.05, ""],
		["feelReal", "Realism", 1.0, 0.5, 1.5, 0.05, ""],
		["feelSpeed", "Speed", 1.0, 0.5, 1.5, 0.05, ""],
		["feelFlow", "Flow", 1.0, 0.5, 1.5, 0.05, ""],
		["feelAir", "Air", 1.0, 0.5, 1.5, 0.05, ""],
		["feelPlush", "Suspension", 1.0, 0.5, 1.5, 0.05, ""],
	]],
	["Steering", [
		["steerEase", "Steer eases in (higher = snappier)", 30, 2, 40, 0.5, "/s"],
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
	["Tyre grip sim", [
		["gripRearLock", "Locked rear swings out (fishtail)", 1.0, 0, 2.5, 0.05, "×"],
		["gripCatch", "Rider catches slides", 0.6, 0, 2, 0.05, "×"],
		["gripLoose", "Loose patches (grip varies)", 0.5, 0, 1.5, 0.05, "×"],
		["gripBumps", "Bumps knock the rear loose", 1.0, 0, 3, 0.05, "×"],
		["gripPower", "Power slides / wheelspin", 1.0, 0, 3, 0.05, "×"],
		["gripSquirm", "Tyres squirm in turns", 1.0, 0, 3, 0.05, "×"],
		["gripPivot", "Rear swings round the front", 0.7, 0, 1, 0.05, ""],
		["leanTraction", "Lean fore/aft shifts grip", 0.45, 0, 1, 0.05, "×"],
	]],
	# the ground sim (2026-11-20): balance, front tyre, two brakes, slopes / berms, knocks, weight in the turn
	["Balance", [
		["balanceSim", "Balanced bike (turn follows the lean)", 0.4, 0, 1, 0.05, ""],
		["balanceFall", "Falls in when the grip goes", 0.5, 0, 1.5, 0.05, "×"],
		["lowsideAngle", "Lowside: lean past the grip by", 0.3, 0.1, 0.8, 0.01, "rad"],
		["gyroStable", "Fast = steadier (rolls slower)", 0.25, 0, 1, 0.05, "×"],
	]],
	["Crashing", [
		["crashTime", "Losing it takes (at 1x past the limit)", 0.4, 0.05, 1.5, 0.05, "s"],
		["riderSave", "Rider fights back (meter drains)", 1.2, 0.2, 4, 0.05, "/s"],
		["riderSkill", "Rider reflexes in trouble", 1.0, 0, 2, 0.05, "×"],
		["crashHard", "Down at once when this far past the limit", 3.0, 1.0, 8.0, 0.1, "×"],
		["reflexBrake", "Reflex: eases off the brakes", 0.6, 0, 1, 0.05, ""],
		["reflexStandUp", "Reflex: stands the bike up", 0.3, 0, 0.8, 0.05, ""],
		["reflexCatch", "Reflex: fights the slide harder", 1.5, 0, 4, 0.1, "×"],
		["frontWeight", "Weights the front in turns", 0.12, 0, 0.35, 0.01, "g"],
		["bonkBoulder", "Over the bars: a boulder throws you from", 6.0, 3, 15, 0.5, "m/s"],
		["bonkSmall", "Over the bars: a small rock throws you from", 12.0, 5, 25, 0.5, "m/s"],
	]],
	# the jitter fixes / motion caps (2026-11-20): how the ground readings are smoothed and how fast drawn parts may move
	["Smoothing", [
		["bankSmooth", "Bank reading settles over", 0.15, 0.02, 0.6, 0.01, "s"],
		["knockSmooth", "Rock / rut knocks build over", 0.08, 0.01, 0.4, 0.01, "s"],
		["tyreRelax", "Tyre grip follows its load over", 0.04, 0.005, 0.2, 0.005, "s"],
		["cornerSmooth", "Turn load on the body builds over", 0.1, 0.01, 0.5, 0.01, "s"],
		["bankLeanRate", "Lean into tilted ground changes at most", 1.5, 0.3, 6, 0.1, "rad/s"],
		["motionCap", "Drawn parts' speed cap (higher = looser)", 1.0, 0.3, 3, 0.05, "×"],
		["torsoMaxSpeed", "Rider torso moves at most", 2.5, 0.5, 8, 0.1, "m/s"],
	]],
	["Front tyre", [
		["frontGrip", "Front tyre grip", 1.0, 0.5, 1.6, 0.02, "×"],
		["frontWashAt", "Front washes out past", 1.35, 1.05, 2.5, 0.05, "× grip"],
		["frontWashTime", "Pushing that hard for", 0.35, 0.05, 1.5, 0.05, "s"],
	]],
	["Brakes", [
		["brakeFront", "Front brake power", 0.75, 0, 1.5, 0.05, "×"],
		["brakeRear", "Rear brake power", 0.6, 0, 1.5, 0.05, "×"],
		["brakeFrontMix", "Brake key: front lever share", 0.7, 0, 1, 0.05, ""],
		["brakeSkid", "Brake key: how far the rear skids", 0.4, 0, 1, 0.05, ""],
	]],
	["Ground", [
		["bermAssist", "Berms: lean with them, they carry the turn", 0.8, 0, 1, 0.05, ""],
		["bankLean", "Lean into tilted ground (look)", 0.6, 0, 1, 0.05, "×"],
		["camberPull", "Side slopes pull you down", 0.22, 0, 1.5, 0.02, "×"],
		["cornerLoad", "Turns press you down (berms)", 0.6, 0, 2, 0.05, "×"],
		["groundKnock", "Rocks / ruts knock the front", 0.6, 0, 2, 0.05, "×"],
		["landSlide", "Landing on a side slope slides you down it", 1.0, 0, 2, 0.05, "×"],
		["weightInside", "Hanging inside loses grip", 0.2, 0, 0.6, 0.02, "×"],
		["weightSteady", "Outside pedal: steady over bumps", 0.5, 0, 1, 0.05, "×"],
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
		["airArcade", "Arcade air control (0 = real physics)", 1.0, 0, 1, 0.05, ""],
		["airSpinRate", "Air tilt speed (W / S held)", 3.5, 0.5, 9, 0.1, "rad/s"],
		["airSpinResp", "Air tilt response", 7, 1, 25, 0.5, "/s"],
		["airSpinStop", "Air tilt stops when let go", 3, 0, 15, 0.25, "/s"],
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
		["wheelMass", "Wheel weight (heavier = harsher bumps)", 0.03, 0.01, 0.12, 0.005, ""],
		["tyreSquash", "Tyre squash under load", 1.2, 0.4, 3.0, 0.1, "cm"],
		["damperKnee", "Shock blow-off speed (low = bumps pass through)", 0.6, 0.1, 2.0, 0.05, "m/s"],
		["damperBlow", "Shock harshness past blow-off", 0.2, 0.0, 1.0, 0.05, "×"],
		["riderBalance", "Rider balance (1 wheel)", 0.7, 0, 1.5, 0.05, ""],
		["noseDive", "Nose-dive crash angle", 0.6, 0.3, 1.2, 0.05, "rad"],
		["pumpGain", "Pump strength", 9, 0, 25, 0.5, ""],
	]],
	["Lean", [
		["leanMax", "Max lean", 0.95, 0.15, 1.3, 0.01, "rad"],
		["leanIn", "Roll-in stiffness", 40, 8, 200, 1, ""],
		["leanOut", "Roll-out stiffness", 30, 8, 200, 1, ""],
		["leanDamp", "Lean damping", 1.0, 0.3, 1.6, 0.02, ""],
		["leanRate", "Fastest roll (side to side)", 6.0, 0.5, 8, 0.1, "rad/s"],
		["leanLead", "Slow: lean goes with the steer", 0.5, 0, 1, 0.05, ""],
		["slowRoll", "Slow: quicker roll", 1.0, 0, 3, 0.05, "×"],
		["slowLean", "Slow: bike thrown under you", 0.3, 0, 0.6, 0.01, "rad"],
		["bikeLeanMul", "Bike leans extra", 1.55, 0.7, 2.0, 0.01, "×"],
		["bikeLeanCap", "Bike lean soft cap", 1.3, 0.3, 1.5, 0.01, "rad"],
		["bikeLead", "Bike goes over before the body (two masses)", 0.08, 0, 0.2, 0.005, "s"],
		["bodyLean", "Body leans with bike", 0.8, 0.3, 1.0, 0.01, "×"],
		["groundLeanMax", "Max lean against the ground (off-camber)", 1.05, 0.6, 1.4, 0.01, "rad"],
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
		["popKick", "Pump extension", 2.2, 0, 5, 0.1, "m/s"],
		["autoPump", "Pumps on his own (1 = no Space needed)", 0.4, 0, 1, 0.05, ""],
		["airLift", "Lifts the bike after take-off", 0.6, 0, 1, 0.05, ""],
		["landPrepTime", "Reach for landing", 0.35, 0.05, 1, 0.05, "s"],
		["airAimDelay", "Wait before aiming at the landing", 1.0, 0, 2, 0.05, "s"],
		["airAimSpeed", "Aim at the landing: softness", 14, 4, 70, 1, ""],
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
		["popPower", "Pump pop", 2.4, 0.5, 6, 0.1, "m/s"],
	]],
	["Sprint & wheelie", [
		["sprintPower", "Sprint power", 1.5, 1, 2.5, 0.05, "×"],
		["sprintKick", "Sprint kick from slow", 0.9, 0, 2, 0.05, "×"],
		["sprintSlowTo", "Kick fades out by", 11.0, 4, 20, 0.5, "m/s"],
		["sprintTop", "Sprint extra top speed", 3, 0, 8, 0.2, "m/s"],
		["sprintTime", "Sprint stamina", 20, 3, 60, 1, "s"],
		["sprintRecharge", "Stamina refill time", 45, 5, 120, 1, "s"],
		["sprintSpin", "Legs spin-up from slow", 4.0, 0, 8, 0.25, "rad/s"],
		["sprintEffort", "Body effort (look)", 1.0, 0, 2, 0.05, "×"],
		["sprintRock", "Bike thrown side to side", 0.3, 0, 2, 0.05, "×"],
		["sprintLift", "Wheelie pull", 11.0, 0, 20, 0.5, ""],
		["wheelieAngle", "Wheelie pop angle", 0.4, 0.15, 0.9, 0.01, "rad"],
		["wheelieClimb", "Wheelie climbs while held", 0.45, 0.0, 1.5, 0.05, "rad/s"],
		["wheelieDrop", "Wheelie set-down speed", 1.6, 0.4, 4, 0.1, "rad/s"],
	]],
	["Body stick", [
		["stickShift", "Fore / aft reach (× weight shift)", 1.7, 0, 3, 0.05, "×"],
		["manualFrom", "Manual / wheelie: stick pulled back past", 0.4, 0.1, 0.95, 0.05, ""],
		["stickWheelie", "Wheelie (pedalling + stick back): front lifts to", 0.6, 0.1, 1.0, 0.01, "rad"],
		["manualAngle", "Manual: front lifts to", 0.32, 0, 0.7, 0.01, "rad"],
		["flickSteer", "Side lean turns the bars", 0.5, 0, 1, 0.05, ""],
		["flickTurn", "Lean into a turn: extra turn", 4.0, 0, 10, 0.1, "m/s²"],
		["flickGrip", "Lean into a turn: extra grip", 0.2, 0, 0.6, 0.02, "×"],
		["flickLean", "Bike thrown under the body", 0.35, 0, 0.8, 0.01, "rad"],
		["flickSpeed", "Bike flick speed", 14, 3, 30, 0.5, "/s"],
		["flickKick", "Quick flick whips the bike round", 0.16, 0, 0.5, 0.01, "rad"],
		["whipDrift", "Corner whip (both sticks one way): drift angle", 0.42, 0, 0.8, 0.01, "rad"],
		["whipSnap", "Corner whip: how fast the rear swings out", 5.0, 1, 15, 0.5, "/s"],
		["whipLean", "Corner whip: bike thrown over", 0.22, 0, 0.5, 0.01, "rad"],
		["whipCarry", "Corner whip: drift keeps its speed", 0.6, 0, 1, 0.05, ""],
		["whipMinSpeed", "Corner whip: from speed", 4.0, 1, 10, 0.5, "m/s"],
		["whipTrigger", "Corner whip: how far both sticks must go", 0.6, 0.2, 0.95, 0.05, ""],
		["whipCatch", "Corner whip: drift caught over (after letting go)", 0.9, 0.2, 3, 0.05, "s"],
		["stickAirTilt", "Air: stick tilts the nose", 0.55, 0, 1.2, 0.05, "rad"],
		["stickAirRoll", "Air: stick lays the bike over", 0.75, 0, 1.2, 0.05, "rad"],
		["airWhip", "Air: whip (stick to the side kicks the bike out)", 1.1, 0, 1.5, 0.05, "rad"],
		["whipReturn", "Air: whip straightened for the landing", 0.7, 0, 1, 0.05, ""],
		["stickAirEase", "Air: bike follows the stick (higher = snappier)", 3.5, 1, 12, 0.25, "/s"],
		["stickSpinBuild", "Air: spin builds up (stick at the edge)", 2.5, 0.3, 5, 0.1, "/s"],
		["stickSpinMax", "Air: flip spin strength (stick at the edge)", 0.7, 0.2, 1, 0.05, "×"],
		["stickSpinGrow", "Air: spin speeds up the longer it is held", 0.8, 0, 2, 0.05, "×/s"],
		["stickYawRate", "Air: flat spin speed (stick at left / right edge)", 5.0, 1, 9, 0.1, "rad/s"],
		["stickBodyCounter", "Air: body leans against the bike", 0.25, 0, 0.6, 0.05, "×"],
		["stickBodyTilt", "Air: body stays as the bike tilts", 0.6, 0, 1, 0.05, "×"],
		["tuckDrag", "Tuck: air drag cut (stick forward)", 0.42, 0, 0.8, 0.02, "×"],
		["upDrag", "Sit up: extra air drag (stick back)", 0.3, 0, 1, 0.05, "×"],
	]],
	# the demo rider (F2, tuning card › Ride › Demo; not ride feel, so presets leave it alone)
	["Demo rider", [
		["demoPace", "Cornering pace (1 = safe pro)", 1.0, 0.4, 1.7, 0.05, "×"],
		["demoMaxKmh", "Top speed it allows", 60, 15, 130, 1, "km/h"],
		["demoLine", "Racing line (cut the corners)", 0.5, 0, 1, 0.05, ""],
		["demoPump", "Pumps the lips", 1.0, 0, 1, 1, ""],
		["demoSmooth", "Smooth hands (higher = softer)", 1.0, 0.3, 2.5, 0.05, "×"],
	]],
	# dust (tuning card › Dust tab; not part of the ride presets: TunePresets keeps their current values)
	["Dust look", [
		["dustOpacity", "Thickness", 0.6, 0.1, 3, 0.05, ""],
		["dustWisps", "Wispy edges", 1.15, 0, 2.5, 0.05, ""],
		["dustRise", "Rises into the air", 0.55, 0, 1.5, 0.05, "m/s"],
		["dustSwirl", "Swirl strength", 6.5, 0, 15, 0.25, ""],
		["dustSwirlSize", "Swirl size", 0.7, 0.2, 2, 0.05, "1/m"],
		["dustCurl", "Curls / rolls", 0.9, 0, 3, 0.05, ""],
		["dustGrit", "Grit (flying grains)", 1.0, 0, 3, 0.05, "×"],
	]],
	["Dust trail", [
		["dustFade", "Fade speed (low = longer)", 0.07, 0, 0.6, 0.01, "/s"],
		["dustSpread", "Spreads out / thins", 1.3, 0, 4, 0.05, "/s"],
		["dustWindCarry", "Wind takes over", 0.35, 0, 1.5, 0.05, "/s"],
		["dustAhead", "Room ahead (rest = trail)", 3.0, 0, 10, 0.5, "m"],
	]],
	["Dust spray", [
		["dustAmount", "Rear tyre amount", 1.0, 0, 3, 0.05, "×"],
		["dustFront", "Front tyre amount", 0.35, 0, 1.5, 0.05, "×"],
		["dustWidth", "Spray width (fan)", 0.8, 0, 2.5, 0.05, "×"],
		["dustPushOut", "Pushed out sideways", 1.0, 0, 3, 0.05, "×"],
		["dustKickUp", "Kicked up", 1.0, 0, 3, 0.05, "×"],
		["dustThrow", "Thrown back", 1.0, 0, 3, 0.05, "×"],
		["dustGust", "Gusty / pulsing", 2.6, 0, 5, 0.1, ""],
		["dustLanding", "Landing / crash clouds", 1.0, 0, 3, 0.05, "×"],
	]],
]

const PATH := "user://tune.cfg"
## bump VER when defaults are retuned: saved values of the RETUNED keys are dropped once
const VER := 15
## later retunes, per version: only these keys are dropped for saves older than that version (bumping VER
## with one shared list would reset every earlier retuned key again)
const RETUNED_AT := {8: ["manualFrom", "stickAirRoll", "stickSpinBuild", "stickYawRate"], 9: ["leanMax"], 11: ["leanIn", "leanOut", "flickSpeed"], 12: ["leanIn", "leanOut", "flickSpeed", "steerEase", "leanRate"], 13: ["leanIn", "leanOut", "flickSpeed", "steerEase", "leanRate"], 14: ["sprintRock"], 15: ["bodyLean"]}
const RETUNED := ["steerRate", "steerRelease", "steerCurve", "turnSlow", "turnFast", "turnFloor", "steerMax", "slowSteer",
	"barSpeed", "grip", "slipRecover", "slipMax", "turnWeight", "leanMax", "leanIn", "leanOut", "leanDamp", "bikeLeanMul", "bikeLeanCap", "flipAccel", "flipRate", "airTwist", "landBack", "travel", "popKick"]
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
			if old_ver < 7 and k in RETUNED: continue   # new defaults win over values saved before the retune
			var stale := false
			for rv in RETUNED_AT:
				if old_ver < rv and k in RETUNED_AT[rv]: stale = true
			if stale: continue
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
	if OS.get_environment("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
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

## the Feel sliders: macro key -> {detail key: exponent}. The detail value is x m^exp (m 0.5..1.5); a minus
## exponent works the other way (more Realism = less arcade air control)
const MACROS := {
	"feelGrip": {"grip": 0.6, "frontGrip": 0.4, "slipRecover": 0.6, "gripLoose": -1.0, "carveGrip": 0.5},
	"feelAgile": {"steerEase": 0.8, "leanIn": 0.8, "leanOut": 0.8, "leanRate": 0.7, "flickSpeed": 0.8, "barSpeed": 0.5,
		"gyroStable": -1.0, "turnWeight": -1.0},
	"feelSlide": {"oversteer": 1.2, "gripRearLock": 1.0, "gripBumps": 1.0, "gripPower": 1.0, "slipRecover": -0.8, "whipDrift": 0.6},
	"feelReal": {"balanceSim": 1.2, "balanceFall": 1.2, "camberPull": 1.2, "groundKnock": 1.2, "cornerLoad": 1.0,
		"weightInside": 1.0, "airArcade": -1.5, "frontWashAt": -0.4},
	"feelSpeed": {"topSpeed": 0.5, "pedalPower": 0.6, "pedalTop": 0.5, "sprintTop": 0.6, "airDrag": -0.4},
	"feelFlow": {"flowCarry": 1.0, "carveBoost": 1.0, "pumpGain": 0.8, "flowTime": 0.8, "rollRes": -0.8},
	"feelAir": {"popKick": 0.6, "popPower": 0.5, "airSpinRate": 0.8, "airTilt": 0.6, "airTwist": 0.6, "flipRate": 0.6,
		"flipAccel": 0.6, "stickAirEase": 0.5, "slamJolt": 0.6},
	"feelPlush": {"tyreHz": -0.6, "travel": 0.6, "damperKnee": -0.5, "damperBlow": -0.6, "legStiff": -0.5, "tyreDamp": 0.3},
}
static var _macro_of := {}   # detail key -> [[macro, exp], ...]

## what a detail key is scaled by from the Feel sliders now
func macro_k(k: String) -> float:
	if _macro_of.is_empty():
		for m in MACROS:
			for dk in MACROS[m]:
				if not _macro_of.has(dk): _macro_of[dk] = []
				_macro_of[dk].append([m, float(MACROS[m][dk])])
	var f := 1.0
	for me in _macro_of.get(k, []):
		f *= pow(maxf(0.05, float(base.get(me[0], 1.0))), me[1])
	return f

func _rebuild() -> void:
	for k in base:
		var raw: float = base[k] * float(ride.get(k, 1.0))
		var f := macro_k(k)
		if f != 1.0:
			# a Feel slider can move a value past its own slider's range only as far as the range goes
			var r := row(k)
			var val := raw * f
			if r.size() > 4: val = clampf(val, minf(raw, float(r[3])), maxf(raw, float(r[4])))
			raw = val
		v[k] = raw
	changed.emit()
