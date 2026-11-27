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
		["feelAirFlow", "Air flow", 1.0, 0.5, 1.5, 0.05, ""],
	]],
	["Steering", [
		["steerEase", "Steer eases in (higher = snappier)", 30, 2, 40, 0.5, "/s"],
		["steerCurve", "Soft centre", 0.1, 0, 1, 0.05, ""],
		["turnFloor", "Min turn rate", 2.6, 0.3, 3.5, 0.05, "rad/s"],
		["steerMax", "Max bar angle", 0.7, 0.2, 0.9, 0.01, "rad"],
		["slowSteer", "Bar angle when slow", 0.85, 0.4, 1.4, 0.02, "rad"],
		["slowSteerFade", "Slow steering fades by", 4, 1, 10, 0.5, "m/s"],
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
		["gripLoose", "Loose patches (grip varies)", 0.5, 0, 1.5, 0.05, "×"],
		["slideHold", "Rider holds slides he didn't ask for", 6.0, 0, 15, 0.5, "/s"],
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
	]],
	["Crashing", [
		["crashTime", "Losing it takes (at 1x past the limit)", 0.4, 0.05, 1.5, 0.05, "s"],
		["riderSave", "Rider fights back (meter drains)", 1.2, 0.2, 4, 0.05, "/s"],
		["riderSkill", "Rider reflexes in trouble", 1.0, 0, 2, 0.05, "×"],
		["crashHard", "Down at once when this far past the limit", 3.0, 1.0, 8.0, 0.1, "×"],
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
		["frontWashAt", "Front washes out past", 1.7, 1.05, 2.5, 0.05, "× grip"],
		["frontWashTime", "Pushing that hard for", 0.7, 0.05, 1.5, 0.05, "s"],
	]],
	["Brakes", [
		["brakeFront", "Front brake power", 0.75, 0, 1.5, 0.05, "×"],
		["brakeRear", "Rear brake power", 0.6, 0, 1.5, 0.05, "×"],
		["brakeGrip", "Braking grip (how hard the tyres can stop)", 1.0, 0.5, 1.5, 0.05, "×"],
		["brakeFrontMix", "Brake key: front lever share", 0.7, 0, 1, 0.05, ""],
		["brakeSkid", "Brake key: how far the rear skids", 0.4, 0, 1, 0.05, ""],
		["brakeFade", "Brake fade: most braking lost when the brakes are hot", 0.35, 0, 0.8, 0.05, "×"],
		["brakeRamp", "Brakes: seconds to bite fully", 0.15, 0.01, 0.5, 0.01, "s"],
		["brakeLoose", "Brakes: loose patches cut the grip", 1.0, 0, 2, 0.05, "×"],
		["brakeRough", "Brakes: rough ground makes the grip jump", 1.0, 0, 2, 0.05, "×"],
		["brakeMuGround", "Stopping grip: grass / plain ground", 0.54, 0.2, 1.1, 0.01, "μ"],
		["brakeMuTrail", "Stopping grip: trail hardpack", 0.64, 0.2, 1.1, 0.01, "μ"],
		["brakeMuWater", "Stopping grip: water", 0.5, 0.2, 1.1, 0.01, "μ"],
		["brakeMuSand", "Stopping grip: sand", 0.4, 0.2, 1.1, 0.01, "μ"],
		["lockSlideGround", "Locked tyre slides at: grass / ground", 0.66, 0.3, 1.0, 0.01, "×"],
		["lockSlideTrail", "Locked tyre slides at: trail", 0.76, 0.3, 1.0, 0.01, "×"],
		["lockSlideWater", "Locked tyre slides at: water", 0.6, 0.3, 1.0, 0.01, "×"],
		["lockSlideSand", "Locked tyre slides at: sand", 0.58, 0.3, 1.0, 0.01, "×"],
		["brakeFeelLag", "Brake key: how late the rider feels the grip change", 0.15, 0.01, 0.5, 0.01, "s"],
		["brakeFrontHold", "Brake key: front held at this share of the grip felt", 0.93, 0.7, 1.05, 0.01, "×"],
		["brakeSkidEar", "Brake key: how fast a rear skid makes him let off", 1.0, 0, 3, 0.05, "×"],
		["brakeDrift", "Brake key into a turn: lets the rear come round (brake drift)", 0.6, 0, 1.5, 0.05, "×"],
		["brakeDriftAngle", "Brake drift: how far the rear may come round", 0.3, 0.05, 0.7, 0.01, "rad"],
		["brakeRearLet", "Rear lever: lets off once the rear is this far out", 0.55, 0.2, 1.5, 0.05, "× slipMax"],
	]],
	["Ground", [
		["bermAssist", "Berms: lean with them, they carry the turn", 0.8, 0, 1, 0.05, ""],
		["bankLean", "Lean into tilted ground (look)", 0.6, 0, 1, 0.05, "×"],
		["bankBody", "On a bank the body leans with the bike (look)", 0.7, 0, 1, 0.05, ""],
		["bermLeanRoom", "Extra bike lean a berm allows (look)", 0.15, 0, 0.3, 0.01, "rad"],
		["camberPull", "Side slopes pull you down", 0.22, 0, 1.5, 0.02, "×"],
		["bankLock", "Leaned into tilted ground (berms): pulls you down the face", 0.6, 0, 2, 0.05, "×"],
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
		["damperBlow", "High-speed compression (big hits)", 0.4, 0.0, 1.0, 0.05, "×"],
		["suspSag", "Sag (× the bike's setup: softer springs)", 1.0, 0.6, 1.5, 0.02, "×"],
		["suspRebound", "Rebound damping (× the setup)", 1.0, 0.4, 2.0, 0.05, "×"],
		["suspProg", "Ramp-up at the end of the travel (× the setup)", 1.0, 0.0, 2.5, 0.05, "×"],
		["suspGeo", "Brake dive and pedal squat from the geometry", 1.0, 0.0, 2.0, 0.05, "×"],
		["suspSubsteps", "Suspension substeps a physics tick (4 = 480 Hz, 16 = 1920 Hz)", 4.0, 1.0, 32.0, 1.0, ""],
		["diveSteer", "Fork dive shortens the wheelbase (quicker turn-in)", 1.0, 0.0, 2.0, 0.05, "×"],
		["pedalBob", "Pedal bob (the shock moves with each stroke)", 1.0, 0.0, 2.0, 0.05, "×"],
		["pedalKick", "Pedal kickback (cranks pushed back over bumps)", 1.0, 0.0, 2.0, 0.05, "×"],
		["riderBalance", "Rider balance (1 wheel)", 0.7, 0, 1.5, 0.05, ""],
		["noseDive", "Nose-dive crash angle", 0.6, 0.3, 1.2, 0.05, "rad"],
		["pumpLegs", "Pumping: the legs' stroke against the ground (× a real rider)", 1.0, 0, 3, 0.05, "×"],
	]],
	["Lean", [
		["leanMax", "Max lean", 0.95, 0.15, 1.3, 0.01, "rad"],
		["leanDamp", "Lean damping", 1.0, 0.3, 1.6, 0.02, ""],
		["leanRate", "Fastest roll (side to side)", 6.0, 0.5, 8, 0.1, "rad/s"],
		["leanLead", "Slow: lean goes with the steer", 0.5, 0, 1, 0.05, ""],
		["slowRoll", "Slow: quicker roll", 1.0, 0, 3, 0.05, "×"],
		["slowLean", "Slow: bike thrown under you", 0.5, 0, 0.8, 0.01, "rad"],
		["slowBody", "Slow: body's share of the bike's lean (bike under an upright body)", 0.15, 0, 1, 0.01, "×"],
		["slowBodyFrom", "Body starts leaning with the bike from", 4.0, 0, 15, 0.1, "m/s"],
		["slowBodyTo", "Body leans fully with the bike from", 11.0, 1, 25, 0.1, "m/s"],
		["slowBikeCap", "Slow: the bike's soft lean cap", 0.62, 0.3, 1.5, 0.01, "rad"],
		["bikeLeanMul", "Bike leans extra", 1.55, 0.7, 2.0, 0.01, "×"],
		["bikeLeanCap", "Bike lean soft cap", 1.3, 0.3, 1.5, 0.01, "rad"],
		["bikeLead", "Bike goes over before the body (two masses)", 0.08, 0, 0.2, 0.005, "s"],
		["bodyLean", "Fast: body's share of the bike's lean", 0.8, 0.3, 1.0, 0.01, "×"],
		["cornerBody", "Deep turns: body's share of the bike's lean", 0.7, 0.2, 0.9, 0.01, "×"],
		["groundLeanMax", "Max lean against the ground (off-camber)", 1.05, 0.6, 1.4, 0.01, "rad"],
	]],
	["Legs & body", [
		["legStiff", "Leg spring", 30, 4, 150, 1, ""],
		["legDamp", "Leg damping", 0.75, 0.15, 1.6, 0.01, ""],
		["legComp", "Leg bend travel", 0.2, 0.03, 0.4, 0.01, "m"],
		["legExt", "Leg extend travel", 0.13, 0.02, 0.3, 0.01, "m"],
		["autoAbsorb", "Hands off the legs bend ahead of crests (experimental, off: no clear gain)", 0.0, 0, 2, 0.05, "×"],
		["bodyLevel", "Keep body level", 0.85, 0, 1, 0.05, ""],
		["attackDrop", "Get low on descents", 0.18, 0, 0.45, 0.01, "m"],
		["riderMass", "Body weight on legs", 0.45, 0, 0.7, 0.05, ""],
		["weightShift", "Weight shift reach", 0.12, 0, 0.25, 0.01, "m"],
		["loadHeight", "Weight transfer height", 0.25, 0, 1, 0.05, "m"],
		["bodyStiff", "Body follows the bike", 60, 10, 200, 1, ""],
		["bodyInertia", "Body thrown by braking / landings", 0.35, 0, 1.5, 0.01, ""],
	]],
	["Jumping", [
		["prepTime", "Spot lip ahead", 0.8, 0.1, 1.2, 0.05, "s"],
		["prepDepth", "Crouch into lip", 0.22, 0, 0.3, 0.01, "m"],
		["popKick", "Leg push (pop / hop)", 2.4, 0, 5, 0.1, "m/s"],
		["autoPump", "Hands off: his own skill at a lip", 0.75, 0, 1, 0.05, ""],
		["crouchTime", "Preload: crouch time", 0.25, 0.08, 0.8, 0.01, "s"],
		["popRebound", "Preload timing matters", 0.18, 0, 0.5, 0.01, "×"],
		["popAssist", "Held crouch: pop timed for you", 0.6, 0, 1, 0.05, ""],
		["popWindow", "Pop window before a lip", 0.24, 0.1, 0.5, 0.01, "s"],
		["squashPower", "Squash a lip (stick forward)", 1.0, 0, 1.5, 0.05, "×"],
		["airLift", "Lifts the bike after take-off", 0.6, 0, 1, 0.05, ""],
		["tuckPull", "Air tuck: how far holding hop pulls the bike up", 0.32, 0.1, 0.5, 0.01, "m"],
		["autoTuck", "Tuck on every jump (share of the full tuck)", 0.7, 0, 1, 0.05, ""],
		["tuckEase", "How smoothly the tuck comes and goes (half-life)", 0.09, 0.03, 0.3, 0.01, "s"],
		["landPrepTime", "Reach for landing", 0.35, 0.05, 1, 0.05, "s"],
		["airAimDelay", "Wait before aiming at the landing", 1.0, 0, 2, 0.05, "s"],
		["airAimSpeed", "Aim at the landing: softness", 14, 4, 70, 1, ""],
		["airAssist", "Landing help in the air, hands off (0 = all yours)", 0.6, 0, 1, 0.05, ""],
		["shortAim", "Short hops: how much sooner he lines the bike up (0 = off)", 0.0, 0, 1, 0.05, ""],
	]],
	["Speed", [
		["topSpeed", "Top speed", 1.2, 0.5, 2.0, 0.05, "×"],
		["pedalLaunch", "Launch push", 8, 2, 16, 0.5, "m/s²"],
		["pedalPower", "Pedal power", 21, 5, 50, 1, ""],
		["pedalTop", "Pedal top speed", 11.8, 4, 22, 0.2, "m/s"],
		["airDrag", "Air drag", 0.0036, 0, 0.012, 0.0002, ""],
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
		["wheelieDrop", "Wheelie set-down speed", 1.6, 0.4, 4, 0.1, "rad/s"],
	]],
	["Body stick", [
		["stickShift", "Fore / aft reach (× weight shift)", 1.7, 0, 3, 0.05, "×"],
		["manualFrom", "Manual / wheelie: stick pulled back past", 0.25, 0.1, 0.95, 0.05, ""],
		["flickSteer", "Side lean turns the bars", 0.0, 0, 1, 0.05, ""],
		["flickGrip", "Lean into a turn: extra grip", 0.2, 0, 0.6, 0.02, "×"],
		["flickLean", "Bike thrown under the body", 0.0, 0, 0.8, 0.01, "rad"],
		["flickSpeed", "Bike flick speed", 14, 3, 30, 0.5, "/s"],
		["flickKick", "Quick flick whips the bike round", 0.0, 0, 0.5, 0.01, "rad"],
		["flickWide", "Lean out of a turn: runs wider", 3.0, 0, 8, 0.1, "m/s²"],
		["whipDrift", "Corner whip (both sticks one way): drift angle", 0.42, 0, 0.8, 0.01, "rad"],
		["whipTrigger", "Corner whip: how far both sticks must go", 0.6, 0.2, 0.95, 0.05, ""],
		["whipStraight", "Straight whip: how far the rear swings out (0 = off)", 1.0, 0, 1.8, 0.05, "×"],
		["whipFlowIn", "Straight whip: how fast it swings out", 2.5, 0.8, 6, 0.1, "/s"],
		["whipFlowOut", "Straight whip: how fast it comes back", 1.8, 0.6, 6, 0.1, "/s"],
		["whipGlide", "Whip held: bumps knock it about less", 0.6, 0, 1, 0.05, ""],
		["whipStyle", "Straight whip: style points", 1.0, 0, 3, 0.1, "×"],
		["stickAirTilt", "Air: stick tilts the nose", 0.55, 0, 1.2, 0.05, "rad"],
		["stickAirRoll", "Air: stick lays the bike over (tabletop, at 0.8 of stick)", 0.8, 0, 1.5, 0.05, "rad"],
		["airSteer", "Air: steer (A / D, left stick) turns the bike towards the next line", 0.6, 0, 1.0, 0.02, "rad"],
		["airAim", "Air: hands off, the bike points where the trail goes after the landing (0 = off)", 0.6, 0, 1.0, 0.05, "×"],
		["carveStyle", "Landing carve: style points + flow (0 = none)", 1.0, 0, 3.0, 0.1, "×"],
		["barCarve", "Landing carve: bars turn into it (drawing only, 0 = straight)", 0.5, 0, 1.5, 0.05, "×"],
		["airPrelean","Air: bike banks into that turn (ready for the next berm)", 0.5, 0, 1.0, 0.05, "×"],
		["camHeadingRate", "Camera: how fast the view's heading may turn at touch-down (0 = the old jump)", 3.0, 0.0, 12.0, 0.25, "rad/s"],
		["landSwapRate","Landing: how fast the lean swings to the next turn right after touch-down (old: 3, bank 1.5)", 7.0, 1.5, 20.0, 0.5, "rad/s"],
		["airBodyMin", "Air pose: a flight shorter than this keeps the ground pose (skips off a berm face; drawing)", 0.25, 0.0, 0.8, 0.01, "s"],
		["airBodyIn", "Air pose: how long it takes to come in off a lip (drawing)", 0.18, 0.02, 0.6, 0.01, "s"],
		["airBodyOut", "Air pose: how long it takes to go back to the ground pose after touch-down (drawing)", 0.25, 0.02, 0.6, 0.01, "s"],
		["landCarve","Landing: a steered heading becomes a turn, not a slide", 0.8, 0, 1.0, 0.05, "×"],
		["airWhip", "Air: biggest whip (carved in at the lip: stick to the side into it)", 1.5, 0, 1.6, 0.05, "rad"],
		["whipReturn", "Air: whip straightened for the landing", 0.7, 0, 1, 0.05, ""],
		["stickAirEase", "Air: bike follows the stick (higher = snappier)", 8.0, 1, 12, 0.25, "/s"],
		["stickYawRate", "Air: flat spin speed (stick at left / right edge)", 5.0, 1, 9, 0.1, "rad/s"],
		["stickBodyCounter", "Air: body leans against the bike", 0.25, 0, 0.6, 0.05, "×"],
		["stickBodyTilt", "Air: body stays as the bike tilts", 0.6, 0, 1, 0.05, "×"],
		["tuckDrag", "Tuck: air drag cut (stick forward)", 0.42, 0, 0.8, 0.02, "×"],
		["upDrag", "Sit up: extra air drag (stick back)", 0.3, 0, 1, 0.05, "×"],
		["speedTuck", "Speed tuck: how far he tucks by himself at speed (0 = only with the stick)", 1.0, 0, 1, 0.05, "×"],
		["speedTuckFrom", "Speed tuck: starts at", 11.0, 4, 25, 0.5, "m/s"],
		["speedTuckFull", "Speed tuck: full at", 18.0, 6, 30, 0.5, "m/s"],
		["speedTuckDrag", "Speed tuck: drag cut of the automatic tuck (x the stick tuck's)", 0.5, 0, 1, 0.05, "×"],
	]],
	# side-on BMX game feel: the manual / wheelie is a balance you work, holding hop on the downhills pumps speed,
	# a landing in line with the ground gives speed back
	["Balance & pump", [
		["manDirect", "Manual: stick sets the front height (0 = old tipping balance)", 1.0, 0, 1, 0.05, ""],
		["manPullTime", "Manual: starts from a pull back quicker than (0 = any pull)", 0.25, 0, 0.6, 0.01, "s"],
		["manBothSticks", "Manual: pull BOTH sticks back to start it (pad)", 0.0, 0, 1, 1, ""],
		["manGate", "Manual / wheelie only starts leaned less than", 0.2, 0.05, 1.3, 0.01, "rad"],
		["manPower", "Wheelie: weight back + pedalling lifts the front", 1.0, 0, 1, 0.05, ""],
		["manPowerSpeed", "Wheelie: pedals can lift the front up to", 9.0, 3, 20, 0.5, "m/s"],
		["manFollow", "Manual: how quickly the front follows the stick", 40.0, 10, 120, 1, ""],
		["manFall", "Manual: fall off the back when pulled too far (0 = floats)", 1.0, 0, 1, 1, ""],
		["manLean", "Manual: most lean in a turn", 0.42, 0.1, 0.7, 0.01, "rad"],
		["manBalance", "Balance point (front up)", 0.55, 0.3, 0.9, 0.01, "rad"],
		["manGravity", "Falls away from the balance point", 7.0, 2, 16, 0.25, "rad/s²"],
		["manLift", "Pull on the bars (stick back)", 9.0, 3, 20, 0.25, "rad/s²"],
		["manPedal", "A pedal stroke lifts it", 3.0, 0, 8, 0.25, "rad/s²"],
		["manBrake", "Rear brake drops it", 12.0, 0, 30, 0.5, "rad/s²"],
		["manDamp", "Damping", 1.6, 0, 6, 0.1, "/s"],
		["manLoop", "Loops out past the balance point by", 0.42, 0.15, 0.7, 0.01, "rad"],
		["manZone", "Sweet spot width", 0.14, 0.04, 0.3, 0.01, "rad"],
		["manBoost", "Sweet spot speed push", 0.5, 0, 2, 0.05, "m/s²"],
		["manTurn", "Manual / wheelie: turning on the back wheel", 0.65, 0, 1, 0.05, "×"],
		["manLoopKeep", "Looped out: speed kept", 0.72, 0.3, 1, 0.02, "×"],
		["manSlideCatch", "Front set down when the rear slides past (× slide limit)", 0.7, 0.3, 1, 0.05, "×"],
		["manSprintLift", "Sprint stamp from slow lifts the front", 1.1, 0, 2.5, 0.05, "×"],
		["pumpStick", "Body stick forward: berm pump strength (× the button)", 1.2, 0, 2, 0.05, "×"],
		["bermPump", "Pumping a berm: speed from the turn's load (× corner load)", 0.12, 0, 0.4, 0.01, "×"],
		["landPerfect", "Perfect landing within", 0.14, 0.03, 0.4, 0.01, "rad"],
		["landBoost", "Perfect landing on a downslope: speed pumped", 1.6, 0, 5, 0.1, "m/s"],
		["landAngleCost", "Landing off the slope's angle: speed lost (at 35 deg+)", 0.25, 0, 0.6, 0.01, "×"],
		["landHeavy", "Heavy landing from (share of a slam)", 0.6, 0.2, 0.9, 0.05, ""],
		["landForgive", "Clean landing: extra hit taken (x a slam)", 1.0, 0, 3, 0.05, "×"],
		["landYawFree", "Sideways landing: free angle", 0.12, 0, 0.5, 0.01, "rad"],
		["landYawGrip", "Sideways landing: tyres catch at once", 1.0, 0.3, 2, 0.05, "×"],
		["landYawCrash", "Sideways landing: highside from", 5.5, 2, 12, 0.1, "m/s"],
		["landPerfectAir", "Perfect landing: from air time", 0.45, 0.1, 1.5, 0.05, "s"],
		["inputForgive", "Timing forgiveness (hop, lip pump, flip throw)", 0.12, 0, 0.3, 0.01, "s"],
		["stickHop", "Bunny hop scoop (front up when you hop): height", 1.0, 0, 1.25, 0.05, "×"],
		["noseBalance", "Nose manual: balance point (rear up)", 0.5, 0.3, 0.8, 0.01, "rad"],
		["noseGravity", "Nose manual: falls away from the balance point", 7.0, 2, 16, 0.25, "rad/s²"],
		["noseLift", "Nose manual: weight over the bars lifts the rear (0 = off)", 9.0, 0, 20, 0.25, "rad/s²"],
		["noseBrake", "Nose manual: the front brake tips it further", 4.0, 0, 12, 0.25, "rad/s²"],
		["noseLoop", "Nose manual: too far past the balance point by", 0.4, 0.15, 0.7, 0.01, "rad"],
		["noseFrom", "Nose manual: stick pushed forward past", 0.6, 0.2, 0.9, 0.05, ""],
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
		["dustWidth", "Spray cone at the tyre", 8, 0, 60, 1, "°"],
		["dustPushOut", "Pushed out sideways", 1.0, 0, 3, 0.05, "×"],
		["dustKickUp", "Kicked up", 1.0, 0, 3, 0.05, "×"],
		["dustThrow", "Thrown back", 1.0, 0, 3, 0.05, "×"],
		["dustGust", "Gusty / pulsing", 2.6, 0, 5, 0.1, ""],
		["dustLanding", "Landing / crash clouds", 1.0, 0, 3, 0.05, "×"],
	]],
	["Dust grit", [
		["dustGrit", "Amount (flying grains)", 1.0, 0, 3, 0.05, "×"],
		["dustGritSize", "Grain size", 1.0, 0.2, 4, 0.05, "×"],
		["dustGritWidth", "Spread (random scatter)", 1.0, 0, 4, 0.05, "×"],
		["dustGritThrow", "Thrown back", 1.4, 0, 3, 0.05, "×"],
		["dustGritUp", "Kicked up", 1.0, 0, 3, 0.05, "×"],
		["dustGritFrom", "Starts at speed", 30, 0, 80, 1, "km/h"],
	]],
]

const PATH := "user://tune.cfg"
## bump VER when defaults are retuned: saved values of the RETUNED keys are dropped once
const VER := 36
## later retunes, per version: only these keys are dropped for saves older than that version (bumping VER
## with one shared list would reset every earlier retuned key again)
const RETUNED_AT := {8: ["manualFrom", "stickAirRoll", "stickSpinBuild", "stickYawRate"], 9: ["leanMax"], 11: ["leanIn", "leanOut", "flickSpeed"], 12: ["leanIn", "leanOut", "flickSpeed", "steerEase", "leanRate"], 13: ["leanIn", "leanOut", "flickSpeed", "steerEase", "leanRate"], 14: ["sprintRock"], 15: ["dustWidth"], 16: ["bodyLean"], 17: ["stickAirEase"], 18: ["manualFrom"], 19: ["manBothSticks"], 22: ["popKick"], 23: ["damperBlow"], 24: ["landHeavy"], 25: ["autoAbsorb"], 26: ["autoPump", "prepTime", "prepDepth"], 27: ["airWhip"], 28: ["airAssist"], 29: ["airAssist"], 30: ["stickAirRoll"], 31: ["flickSteer", "flickLean", "flickKick"], 32: ["airBodyOut"], 33: ["slowSteer"], 34: ["stickAirRoll"], 35: ["slowLean"], 36: ["cornerBody"], 20: ["manBothSticks"], 21: ["frontWashAt", "frontWashTime"]}
const RETUNED := ["steerRate", "steerRelease", "steerCurve", "turnFloor", "steerMax", "slowSteer",
	"barSpeed", "grip", "slipRecover", "slipMax", "turnWeight", "leanMax", "leanIn", "leanOut", "leanDamp", "bikeLeanMul", "bikeLeanCap", "flipAccel", "flipRate", "airTwist", "landBack", "travel", "popKick"]
var defaults := {}
var base := {}       # the player's slider values (before the bike's ride multipliers)
var ride := {}       # multipliers for the bike being ridden
var v := {}          # effective values: base * ride (what the physics reads)
const DEFAULT_PINS := ["slowSteer", "turnWeight", "rollRes", "flowCarry", "carveBoost", "popKick"]
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
	for kv in Env.raw("BMX_TUNE").split(",", false):   # tests: "topSpeed=1.6,grip=1.1" (not saved)
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
	if Env.raw("BMX_PADSEQ") != "": return   # menu tests: never into the player\'s files
	for a in OS.get_cmdline_user_args():   # ride tests too (an autotest must never change the player's tuning)
		if a.begins_with("--autotest") or a.begins_with("--bench"): return
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

## Followers (2026-11-20 slider merge): values that used to be sliders of their own and overlapped another one.
## They are no slider now; each follows its LEADER slider: value = default x (leader / leader's default)^exp x the
## bike's multiplier (BIKES / frame_mods still shape them) x the Feel sliders. exp 0 = a fixed value. So the ride
## is unchanged at the defaults and one slider moves the whole group. The physics reads them as before (T.key)
const FOLLOW := {
	"brakeForce": [13.0, "", 0.0],                                         # brake power: the front / rear levers set it
	"steerRate": [15.0, "steerEase", 1.0], "steerRelease": [10.0, "steerEase", 1.0], "barSpeed": [28.0, "steerEase", 1.0],
	"gripCatch": [0.6, "slipRecover", 1.0],                              # slide catch: one slider
	"reflexBrake": [0.6, "", 0.0], "reflexStandUp": [0.3, "", 0.0], "reflexCatch": [1.5, "", 0.0],   # riderSkill scales them all
	"leanIn": [40.0, "leanRate", 1.0], "leanOut": [30.0, "leanRate", 1.0], "gyroStable": [0.25, "", 0.0],
	"popPower": [2.4, "popKick", 1.0],                                   # the legs' push x the bike (a heavy one pops less)
	"antiSquat": [0.9, "", 0.0],   # the frame's anti-squat (1 = power doesn't squat the rear; BikeBuild.frame_mods)
	"shockProg": [1.0, "", 0.0],   # the frame's linkage ramp-up (BikeBuild.frame_mods; 1 = the reference frame)
	"pumpCentred": [0.75, "", 0.0], "pumpMinSpeed": [2.0, "", 0.0],
	"airSpinResp": [7.0, "airSpinRate", 1.0], "airSpinStop": [3.0, "airSpinRate", 1.0],
	"stickSpinBuild": [5.5, "stickAirEase", 1.0], "stickSpinGrow": [0.4, "", 0.0], "stickSpinMax": [0.7, "", 0.0],
	"whipSnap": [5.0, "whipDrift", 1.0], "whipLean": [0.22, "whipDrift", 1.0], "whipCarry": [0.6, "", 0.0],
	"whipCatch": [0.9, "", 0.0], "whipMinSpeed": [4.0, "", 0.0],
}

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
	"feelFlow": {"flowCarry": 1.0, "carveBoost": 1.0, "pumpLegs": 0.8, "flowTime": 0.8, "rollRes": -0.8},
	"feelAir": {"popKick": 0.6, "popPower": 0.5, "airSpinRate": 0.8, "airTilt": 0.6, "airTwist": 0.6, "flipRate": 0.6,
		"flipAccel": 0.6, "stickAirEase": 0.5, "slamJolt": 0.6},
	"feelAirFlow": {"airSteer": 0.8, "airAim": 0.8, "airPrelean": 0.5, "landCarve": 0.4, "landSwapRate": 0.8, "camHeadingRate": 0.3},
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
	# followers (FOLLOW): their leader slider's move, the bike's multiplier and the Feel sliders
	for k in FOLLOW:
		var fw: Array = FOLLOW[k]
		var lead: float = 1.0
		if str(fw[1]) != "" and defaults.has(fw[1]):
			lead = pow(maxf(1e-4, float(base.get(fw[1], defaults[fw[1]])) / maxf(1e-4, float(defaults[fw[1]]))), float(fw[2]))
		v[k] = float(fw[0]) * lead * float(ride.get(k, 1.0)) * macro_k(k)
	changed.emit()
