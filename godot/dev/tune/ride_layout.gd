class_name RideLayout
extends RefCounted
## The tuning card's Ride tab: every ride / sim slider placed by what it's for on the bike, in plain words.
## PAGES = [id, tab name, blurb, [[section, [row, ...]], ...]]. A row = [key, hint, left end, right end] and
## a "*" before the key = shown in Simple view too (All shows every row). Labels come from Tune.DEFS unless
## LABELS has a clearer one. Any ride key not placed here lands in "More" on the last page (pages_checked).

const LABELS := {
	"grip": "Tyre grip", "frontGrip": "Front tyre grip", "brakeForce": "Brake power",
	"turnWeight": "Turn weight", "leanRate": "Roll speed", "steerEase": "Steer response",
	"bikeLeanMul": "Bike under the body", "legStiff": "Leg spring", "steerCurve": "Soft centre",
	"flickGrip": "Lean in: grips harder", "weightInside": "Hanging inside",
	"weightSteady": "Outside pedal", "flickSteer": "Side lean steers", "flickLean": "Bike thrown under",
	"flickSpeed": "Bike follows the stick", "flickKick": "Flick whips round", "flickWide": "Lean out: wider",
	"whipDrift": "Whip: drift angle", "whipSnap": "Whip: swing-out speed", "whipLean": "Whip: bike thrown over",
	"whipCarry": "Whip: keeps speed", "whipMinSpeed": "Whip: from speed", "whipTrigger": "Whip: stick travel",
	"whipCatch": "Whip: catch time", "stickShift": "Fore / aft reach", "leanTraction": "Weight shifts grip",
	"manualFrom": "Manual: stick pulled past", "stickWheelie": "Pedal wheelie height", "manualAngle": "Manual height",
	"stickAirTilt": "Stick tilts the nose", "stickAirRoll": "Stick lays it over", "stickAirEase": "Bike follows the stick",
	"stickSpinBuild": "Spin build-up", "stickSpinMax": "Flip spin strength", "stickSpinGrow": "Spin grows when held",
	"stickYawRate": "Flat spin speed", "stickBodyCounter": "Body leans against bike", "stickBodyTilt": "Body stays as bike tilts",
	"balanceSim": "Balanced bike", "balanceFall": "Falls in past the grip", "lowsideAngle": "Lowside margin",
	"gyroStable": "Steady at speed", "frontWashAt": "Front wash-out point", "frontWashTime": "Wash-out time",
	"brakeFront": "Front brake", "brakeRear": "Rear brake", "brakeFrontMix": "Brake key: front share",
	"brakeSkid": "Brake key: rear skid", "camberPull": "Side-slope pull", "bankLock": "Berm lock-in", "tuckPull": "Air tuck", "autoTuck": "Tuck on every jump", "tuckEase": "Tuck smoothness", "cornerBody": "Deep-turn body lean", "cornerLoad": "Turns press you down",
	"groundKnock": "Rocks & ruts knock", "leanLead": "Tip in with the steer", "slowRoll": "Quicker roll when slow",
	"slowLean": "Bike thrown under (slow)", "slowBody": "Slow: body stays upright", "slowBodyFrom": "Body leans in from", "slowBodyTo": "Body fully in by", "slowBikeCap": "Slow: most bike lean", "damperKnee": "Shock blow-off speed", "damperBlow": "Harshness past blow-off",
	"wheelMass": "Wheel weight", "airArcade": "Arcade air control", "airSpinRate": "Air tilt speed",
	"autoPump": "Pops on his own", "slamJolt": "Legs take a hit up to", "groundLeanMax": "Lean towards rising ground",
	"slowSteer": "Bar lock when slow", "slowSteerFade": "Slow lock fades by", "demoPace": "Cornering pace",
}

const FEEL := [
	["feelGrip", "How hard the tyres hold, front and rear: corner faster before anything lets go.", "Loose", "Grippy"],
	["feelAgile", "How quickly the bike answers: tips in, rolls over and swaps sides.", "Stable", "Nimble"],
	["feelSlide", "How happily the rear steps out: locked rear, bumps, power slides, whips.", "Planted", "Loose rear"],
	["feelReal", "Arcade vs sim: the balanced bike, slopes pulling, rocks knocking the front, real air.", "Arcade", "Sim"],
	["feelSpeed", "Pedal power, top speed and how much the air holds you back.", "Slow", "Fast"],
	["feelFlow", "How well speed is kept: rolling, pumping, carving out of berms.", "Work for it", "Keeps speed"],
	["feelAir", "Pop off lips and how freely the bike flips, spins and tilts in the air.", "Heavy", "Floaty"],
	["feelPlush", "Tyres, shock and legs: how much of the ground comes through.", "Firm", "Plush"],
	["feelAirFlow", "How freely you steer through the air and land into the next turn: air steer, aim, carve, the swing after landing and the camera.", "Tame", "Flowing"],
]

const PAGES := [
	["steer", "Steering", "How the bike turns, leans and balances", [
		["How it turns", [
			["*steerEase", "How fast the bars follow you: the build-up, the release and the bars themselves.", "Gentle", "Snappy"],
			["*slowSteer", "How far the bars turn when you're slow (tight hairpins).", "Little", "Full lock"],
			["slowSteerFade", "Speed by which that slow-speed lock is gone.", "Early", "Late"],
			["steerMax", "Most the bars turn at speed.", "Little", "Lots"],
			["steerCurve", "Soft centre: small inputs do less (fine control).", "Linear", "Soft centre"],
			["turnFloor", "The least turn you always get, even at speed.", "Little", "Lots"],
			["turnWeight", "Heavy = the turn settles in over a moment, light = instant.", "Light", "Heavy"],
		]],
		["Balance", [
			["*balanceSim", "Real bikes turn because they lean: tip in and the front follows. 0 = the bars drive the turn.", "Bars", "Balance"],
			["counter", "The short push the other way that starts a lean (countersteer).", "None", "Strong"],
			["balanceFall", "Leaned past what the tyres hold, the bike falls on in.", "Never", "Falls"],
			["lowsideAngle", "How far past the grip before it's a LOWSIDE crash.", "Strict", "Forgiving"],
		]],
		["Lean", [
			["*leanRate", "How fast the bike rolls over and back up, side to side.", "Lazy", "Quick"],
			["*bikeLeanMul", "How far the bike goes over under the rider in turns.", "With the body", "Way under"],
			["*bikeLead", "Two masses: the light bike goes over first, the heavy body follows.", "As one", "Bike first"],
			["leanDamp", "Settles without wobble.", "Bouncy", "Damped"],
			["leanMax", "Deepest lean.", "Shallow", "Deep"],
			["bikeLeanCap", "Bike lean soft limit.", "Low", "High"],
			["bodyLean", "How much of the lean the body takes.", "Upright", "Leans with it"],
			["cornerBody", "In a deep turn the body takes this share of the bike's lean (0.5 = Project X, 0.8 = before). Lower = the bike further out under you.", "Bike way out", "Leans with it"],
			["groundLeanMax", "Max lean towards ground rising beside you (off-camber).", "Careful", "Deep"],
		]],
		["Slow riding", [
			["*leanLead", "Slow, the bike tips in with the steer instead of after the turn.", "After", "With it"],
			["slowRoll", "Slow, the bike rolls quicker (nothing holding it up).", "Same", "Quick"],
			["slowLean", "Slow, the steer throws the bike under you.", "Upright", "Thrown under"],
			["*slowBody", "Slow, the body leans this share of the bike's lean: the bike is laid into the turn under an upright rider (Project X).", "Upright", "Leans in"],
			["slowBodyFrom", "Below this speed the body stays upright.", "Never", "Fast"],
			["slowBodyTo", "From this speed the body leans in with the bike.", "Early", "Late"],
			["slowBikeCap", "Slow: how far over the bike goes at most (soft).", "Upright", "Laid over"],
			["pivotRate", "Brake + steer when slow: pivot speed.", "Slow", "Fast"],
		]],
	]],
	["tyres", "Tyres", "Grip, slides and the front tyre", [
		["Grip", [
			["*grip", "Both tyres: how much they hold before sliding.", "Loose", "Grippy"],
			["*frontGrip", "The front alone: pushes wide earlier or later.", "Washy", "Planted"],
			["carveGrip", "Extra bite while carving a clean turn.", "None", "Lots"],
			["gripLoose", "Loose patches: grip changes under the tyres.", "Even", "Patchy"],
			["slideHold", "A slide you didn't ask for (no rear brake, whip or sprint) is caught back.", "Lets it go", "Holds it"],
		]],
		["Slides", [
			["*oversteer", "How much the rear steps out when you ask too much.", "Planted", "Steps out"],
			["*slipRecover", "How quickly a slide straightens itself, and how hard the rider catches it.", "Slow", "Quick"],
			["slipMax", "Slide angle that's a WASHED OUT crash.", "Small", "Huge"],
			["gripRearLock", "Locked rear swings round (fishtail).", "Straight", "Fishtails"],
			["gripPower", "Power slides / wheelspin step the rear out.", "Never", "Lots"],
			["gripBumps", "Bumps knock the rear loose near the limit.", "Never", "Lots"],
			["gripSquirm", "Tyres squirm a few degrees in turns.", "None", "Lots"],
			["gripPivot", "The rear swings round the front.", "Middle", "Front"],
		]],
		["Crashing (slides, wash-outs, lowsides: a build-up you can save)", [
			["*crashTime", "How long you can be past the limit before you go down (shorter the further past).", "Instant", "Lots of time"],
			["*riderSave", "How fast the trouble drains once you're back under the limit.", "Slow", "Fast"],
			["*riderSkill", "In trouble the rider eases the brakes, stands the bike up and fights the slide.", "None", "Pro"],
			["crashHard", "This far past the limit there's no saving it: down at once.", "Strict", "Forgiving"],
			["*frontWeight", "Leaned over he presses the front into the ground (keeps it from washing out).", "None", "Lots"],
			["bonkBoulder", "Hitting a boulder head-on throws you over the bars from this speed.", "Slow", "Fast"],
			["bonkSmall", "A rock just too tall to roll over needs this speed to throw you.", "Slow", "Fast"],
		]],
		["Front tyre", [
			["*frontWashAt", "How far past its grip the front can push before it washes out.", "Early", "Late"],
			["frontWashTime", "How long it can push that hard.", "Short", "Long"],
		]],
	]],
	["ground", "Ground", "Slopes, berms, rocks and flow", [
		["The land", [
			["*bermAssist", "Steer into a berm and the rider leans with it, square to its surface, and the berm carries you round.", "Upright", "With the berm"],
			["*bankLean", "On a berm or a slope, rider and bike lean into the tilt (square to the ground at 1).", "Upright", "Square to it"],
			["*bankBody", "On banked ground the rider leans in with the bike, in one line, instead of staying upright over it. Look only.", "Upright", "With the bike"],
			["*bermLeanRoom", "How much further the bike may lay over inside a berm than on flat ground. Look only.", "Like flat", "Laid over"],
			["*camberPull", "Riding across a side slope, the bike drifts down it unless you steer.", "None", "Strong"],
			["bankLock", "Leaned into a berm or any tilted ground, it steers you back down the face: you ride higher at speed instead of over the top.", "Free", "Locked in"],
			["*cornerLoad", "Turns (berms most) press you down into the bike: legs and shock sink, then pop.", "None", "Heavy"],
			["*groundKnock", "Rock flanks, roots and rut walls push the front off its line.", "Smooth", "Rough"],
		]],
		["Flow", [
			["*flowCarry", "Chained flow keeps more speed.", "Little", "Lots"],
			["flowTime", "How long flow lasts.", "Short", "Long"],
			["carveBoost", "Speed out of a clean carve or berm.", "None", "Lots"],
			["rollRes", "Rolling resistance.", "Rolls on", "Drags"],
		]],
	]],
	["brakes", "Brakes", "Two levers, each with its own tyre", [
		["Levers", [
			["*brakeFront", "Front lever: does most of the stopping, washes out if grabbed leaned over.", "Weak", "Strong"],
			["*brakeRear", "Rear lever: the rear goes light and locks easily (skids).", "Weak", "Strong"],
			["*brakeGrip", "How hard the tyres can stop: hardpack grips best, grass less, sand and water least.", "Slippy", "Sticky"],
			["brakeFrontMix", "The brake key (S / LT): how much front it squeezes with the rear.", "Rear only", "Both"],
			["brakeSkid", "The brake key: how far past locking the rear goes (dust!).", "No skid", "Skids"],
			["brakeFade", "Long hard braking heats the brakes and the levers lose bite.", "No fade", "Fades"],
		]],
	]],
	["speed", "Speed", "Pedalling, sprinting and air drag", [
		["Pedalling", [
			["*topSpeed", "Overall top speed.", "Slow", "Fast"],
			["*pedalPower", "Pedal power.", "Weak", "Strong"],
			["pedalLaunch", "Push from a standstill.", "Soft", "Hard"],
			["pedalTop", "Speed you can pedal to.", "Low", "High"],
			["airDrag", "Air drag.", "None", "Lots"],
			["tuckDrag", "Tuck (right stick forward) cuts the drag.", "Little", "Lots"],
			["upDrag", "Sat up (stick pulled right back) catches the wind.", "Little", "Lots"],
			["*speedTuck", "Fast and coasting he tucks by himself (a light pull back tucks him anyway).", "Never", "Fully"],
			["speedTuckFrom", "Speed the tuck starts.", "Slow", "Fast"],
			["speedTuckFull", "Speed he is fully tucked.", "Slow", "Fast"],
			["speedTuckDrag", "How much the automatic tuck cuts the drag.", "None", "Like the stick"],
		]],
		["Sprint", [
			["*sprintPower", "Sprint power.", "Weak", "Strong"],
			["sprintKick", "Extra kick sprinting from slow.", "None", "Big"],
			["sprintSlowTo", "That kick fades out by.", "Early", "Late"],
			["sprintTop", "Sprint top speed on top.", "Little", "Lots"],
			["sprintTime", "How long the stamina lasts.", "Short", "Long"],
			["sprintRecharge", "Stamina refill time.", "Quick", "Slow"],
			["sprintSpin", "Legs spin up from slow.", "Slow", "Fast"],
			["sprintEffort", "Body effort (look).", "Calm", "All in"],
			["sprintRock", "Bike thrown side to side sprinting.", "Still", "Thrown"],
		]],
	]],
	["body", "Body", "The right stick: weight in turns, fore / aft, manuals, the whip", [
		["Weight in turns", [
			["*flickGrip", "...and grips harder (weight on the outside pedal).", "None", "Lots"],
			["*weightInside", "Stick against the turn (hanging inside): the tyres lose bite.", "No cost", "Costly"],
			["*flickWide", "Stick against the turn: the bike runs wider.", "No", "Lots"],
			["weightSteady", "Weight on the outside pedal keeps the rear planted over bumps.", "None", "Planted"],
			["flickSteer", "The side lean steers the bike on its own too.", "No", "Lots"],
			["flickLean", "How far the bike is thrown under the body.", "Little", "Lots"],
			["flickSpeed", "How fast the bike follows the stick.", "Smooth", "Snappy"],
			["flickKick", "A quick flick of the stick whips the bike round.", "None", "Big"],
		]],
		["Weight fore / aft", [
			["*stickShift", "How far the stick moves the body over the bars / back.", "Little", "Lots"],
			["*leanTraction", "Weight back = rear grip, front light; forward = the other way.", "Little", "Lots"],
			["weightShift", "How far the body shifts by itself.", "Little", "Lots"],
			["loadHeight", "Weight moved by pedalling / braking.", "Little", "Lots"],
			["bodyInertia", "Body thrown forward by braking and landings.", "Little", "Lots"],
			["bodyStiff", "Body follows the bike.", "Loose", "Tight"],
		]],
		["Manual & wheelie", [
			["*manualFrom", "Stick pulled back past this = manual / wheelie.", "Light pull", "Full pull"],
			["wheelieDrop", "Set-down speed.", "Slow", "Fast"],
		]],
		["Corner whip (flick the stick with the steer)", [
			["*whipDrift", "How far the rear swings out, how fast, and how far the bike is thrown over.", "Small", "Big"],
			["whipTrigger", "How far both sticks must go.", "A little", "All the way"],
			["*whipStraight", "Throw the stick on a straight: how far the rear swings out (0 = off).", "Off", "Big"],
			["*whipFlowIn", "Throw the stick on a straight: how fast the rear swings out.", "Floaty", "Snappy"],
			["whipFlowOut", "...and how fast it comes back when you let go.", "Floaty", "Snappy"],
			["whipGlide", "Held, the rear is light: bumps knock it about less.", "None", "Glides"],
			["whipStyle", "Style points for a straight whip.", "None", "Lots"],
		]],
		["Legs", [
			["*legStiff", "How hard the legs hold the body up.", "Soft", "Stiff"],
			["*autoAbsorb", "Hands off, the legs soak up crests and dips so the wheels stay on the ground (no speed from it).", "Off", "Strong"],
			["legDamp", "Leg damping.", "Bouncy", "Damped"],
			["legComp", "How far the legs bend.", "Little", "Lots"],
			["legExt", "How far they stretch.", "Little", "Lots"],
			["bodyLevel", "Keeps the body level.", "Follows bike", "Level"],
			["attackDrop", "Gets low on descents.", "Tall", "Low"],
			["riderMass", "Body weight on the legs.", "Light", "Heavy"],
		]],
	]],
	["manual", "Manual & pump", "Manuals / wheelies you balance yourself, pumping for speed, perfect landings", [
		["Manual & wheelie", [
			["*manDirect", "The stick sets how high the front is, and it follows smoothly. 0 = the old balance that tips on its own.", "Old balance", "Stick = height"],
			["*manPullTime", "The manual starts from a quick pull back (centre to back within this time). Leaning back slowly, however far, only shifts your weight for cornering. 0 = any pull lifts the front.", "Any pull", "Slow pulls too"],
			["*manBothSticks", "On a pad: the left stick has to be pulled back together with the right one to start a manual. After that only the right stick holds it.", "Right stick", "Both sticks"],
			["*manGate", "The front only comes up when you ride roughly straight: leaned more than this, weight back just changes the corner.", "Straight only", "Anywhere"],
			["*manPower", "Weight back + pedalling lifts the front without any quick pull, like a motocross game. Stop pedalling and it comes down.", "Off", "On"],
			["*manPowerSpeed", "Up to what speed the pedals have the power to lift the front (full when slow, fading to nothing here).", "Slow only", "Fast too"],
			["*manFollow", "How quickly the front follows the stick.", "Lazy", "Snappy"],
			["*manFall", "Pulled too far back and held: he falls off the back. Off = the front just floats at the top.", "Floats", "Falls"],
			["*manLean", "How far he leans a manual / wheelie into a turn: more = tighter turns on the back wheel.", "Wide", "Tight"],
			["*manBalance", "The balance point: how high the front sits when it's balanced.", "Low", "High"],
			["*manGravity", "How fast it falls away from the balance point.", "Lazy", "Twitchy"],
			["manLift", "How hard pulling the stick back lifts the front.", "Gentle", "Strong"],
			["manPedal", "A pedal stroke lifts the front.", "No", "Lots"],
			["manBrake", "The rear brake drops the front.", "Gently", "Fast"],
			["manDamp", "Damping of the balance.", "Bouncy", "Damped"],
			["manLoop", "Past the balance point by this much it loops out.", "Strict", "Forgiving"],
			["manZone", "Sweet-spot width.", "Narrow", "Wide"],
			["manBoost", "Riding the sweet spot gives a small push.", "None", "Lots"],
			["manTurn", "Turning while on the back wheel.", "None", "Full"],
			["manLoopKeep", "Speed kept when it loops out.", "Little", "All"],
			["manSlideCatch", "The front is set down when the rear slides this far (x the slide limit).", "Early", "Late"],
			["manSprintLift", "A sprint stamp from slow lifts the front.", "No", "Lots"],
		]],
		["Nose manual & stoppie (front brake + stick forward)", [
			["*noseBalance", "The balance point: how high the rear sits when it's balanced.", "Low", "High"],
			["noseGravity", "How fast it falls away from the balance point.", "Lazy", "Twitchy"],
			["*noseLift", "How hard your weight over the bars lifts the rear. 0 = no nose manuals.", "Off", "Strong"],
			["noseBrake", "The front brake tips it further over.", "No", "Lots"],
			["noseLoop", "Past the balance point by this much it's too far.", "Strict", "Forgiving"],
			["noseFrom", "Stick pushed forward past this (with the front brake) starts it.", "Light push", "Full push"],
		]],
		["Hops & timing", [
			["*stickHop", "Hopping with the front up scoops the rear after it: out of a manual, or stick back then snapped forward.", "Off", "High"],
			["*inputForgive", "A hop, lip pump or flip throw this much early / late still counts.", "Exact", "Forgiving"],
		]],
		["Pumping", [
			["*pumpLegs", "Pump rollers and dips with your legs: bend them (hop held / stick back) over a crest, push them straight (let go / stick forward) down the back and into the dip.", "None", "Strong"],
			["*pumpStick", "Right stick forward pumps a berm (× the hop button).", "None", "Strong"],
			["*bermPump", "Pumping through a banked turn (hop held / stick forward) drives the bike out of it faster.", "None", "Strong"],
		]],
		["Perfect landings", [
			["*landBoost", "A landing matched to a downslope is pumped for speed (none on the flat).", "None", "Big"],
			["landPerfect", "How close to the slope counts as perfect.", "Strict", "Forgiving"],
			["landAngleCost", "Landing with the bike off the slope's angle bogs it down: speed lost (MX vs ATV style).", "Free", "Harsh"],
			["landPerfectAir", "Only from this much air time.", "Short", "Long"],
		]],
	]],
	["susp", "Suspension", "Tyres, shock and how the ground comes through", [
		["Wheels & shock", [
			["*travel", "Suspension travel.", "Short", "Long"],
			["*tyreHz", "Spring rate, on top of the bike's setup (garage > Shocks).", "Soft", "Stiff"],
			["*tyreDamp", "Damping, compression and rebound together, on top of the setup.", "Bouncy", "Damped"],
			["*suspSag", "Sag: how far the bike sits into its travel.", "Rides high", "Sits deep"],
			["*suspRebound", "Rebound damping: how fast it comes back up.", "Lively", "Planted"],
			["suspProg", "How much the springs ramp up at the end of the travel.", "Linear", "Ramps hard"],
			["*suspGeo", "Fork dive under the front brake, the rear's squat under power and under its brake.", "None", "Lots"],
			["suspSubsteps", "How many times a physics tick the springs, tyres and legs are stepped (x 120 Hz). More = stiffer hits resolved finer, costs CPU.", "4 (480 Hz)", "32 (3840 Hz)"],
			["diveSteer", "A diving fork shortens the wheelbase: the bike turns in quicker under the front brake.", "None", "Lots"],
			["pedalBob", "The shock pumps with every pedal stroke.", "None", "Lots"],
			["pedalKick", "Bumps push the cranks back against your feet while you pedal.", "None", "Lots"],
			["tyreSquash", "Tyre squash under load.", "Hard", "Squishy"],
			["damperKnee", "Shock blow-off speed (low = sharp bumps pass into the wheel).", "Low", "High"],
			["damperBlow", "High-speed compression: how much damping is left for big hits.", "Blows through", "Holds up"],
			["wheelMass", "Wheel weight (heavier = harsher bumps).", "Light", "Heavy"],
			["legPress", "Legs press the bike down.", "Light", "Heavy"],
		]],
		["Balance on one wheel", [
			["riderBalance", "Rider balance on one wheel.", "Wobbly", "Steady"],
			["noseDive", "Nose-dive crash angle.", "Strict", "Forgiving"],
		]],
	]],
	["jumps", "Jumps", "Take-off, the air, the right stick up there, landing", [
		["Take-off", [
			["*popKick", "Leg push: the most speed one pop or hop can add. 2.4 m/s is a strong rider.", "Weak", "Superhuman"],
			["*popRebound", "Preload timing: crouch (stick back / hold hop) and pop on the rebound for the full push; held still it loses this much.", "No matter", "Matters"],
			["*popAssist", "A crouch held right through a lip is timed for you, at this share of a well-timed pop.", "You time it", "Auto"],
			["*squashPower", "Stick held forward into a lip squashes it: low and fast.", "Off", "Lots"],
			["autoPump", "Hands off, he pops lips on his own this much.", "Not at all", "Fully"],
			["crouchTime", "Time to crouch right down.", "Quick", "Slow"],
			["popWindow", "A pop this long before a lip goes off at its edge.", "Exact", "Early ok"],
			["prepTime", "Spots the lip ahead.", "Late", "Early"],
			["prepDepth", "Crouch into the lip.", "Little", "Deep"],
			["airLift", "Lifts the bike after take-off.", "No", "Lots"],
			["tuckPull", "How far the full tuck pulls the bike up to you (knees to chest): right stick back or hop held in the air.", "A little", "Knees to chest"],
			["*autoTuck", "Every jump the rider tucks the bike up under him by himself, this share of the full tuck. Right stick back = all of it, forward = none.", "Stays long", "Full tuck"],
			["tuckEase", "How softly the bike comes up into the tuck and goes back down for the landing.", "Snappy", "Floaty"],
		]],
		["In the air", [
			["*airArcade", "Arcade air control (0 = real momentum physics).", "Physics", "Arcade"],
			["*airSpinRate", "Air tilt speed (W / S held), and how quickly it starts and stops.", "Slow", "Fast"],
			["airTilt", "Body shift tilts the bike.", "Little", "Lots"],
			["airTwist", "Hip twist in the air.", "Little", "Lots"],
			["airRoll", "Air lean left / right (A / D).", "Little", "Lots"],
			["tuckSpin", "Tuck spins faster (Space).", "No", "Lots"],
			["riderShare", "Rider's share of the spin.", "Bike", "Rider"],
			["flipRate", "Lip throw: max spin.", "Slow", "Fast"],
			["flipAccel", "Lip throw: pull.", "Gentle", "Hard"],
		]],
		["Steer in the air (A / D, left stick)", [
			["*airSteer", "Turns the bike in the air towards where you want to land and go next. Works from a small hop, no wind-up needed.", "None", "Lots"],
			["*airAim", "Hands off, the rider points the bike where the trail goes after the landing (the next bend). Any steer of yours takes over at once. 0 = off.", "Off", "Strong"],
			["airPrelean", "The bike banks into that turn while it is in the air: ready for the next berm.", "Flat", "Banked"],
			["landCarve", "Landed turned the way you steered: the tyres turn it into a corner (little speed lost) instead of a slide.", "Slides", "Carves"],
			["carveStyle", "A landing carved into the turn pays style points + a notch of flow. 0 = no reward.", "None", "Lots"],
			["barCarve", "The bars turn into the turn in the air and bite in at the carve (drawing only). 0 = straight bars.", "Straight", "Turned"],
		]],
		["Right stick in the air", [
			["*airWhip", "Whip: stick to the side kicks the bike out sideways under the body (pushed right to the edge into a lip: a 360).", "None", "Huge"],
			["whipReturn", "How much of the whip the rider straightens himself as the landing comes.", "You do it", "He does it"],
			["*stickAirEase", "How quickly the bike follows the stick in the air, and how fast a spin builds.", "Smooth", "Snappy"],
			["stickAirTilt", "Stick tilts the nose.", "Little", "Lots"],
			["stickAirRoll", "Stick lays the bike over.", "Little", "Lots"],
			["stickYawRate", "Flat spin speed.", "Slow", "Fast"],
			["stickBodyCounter", "Body leans against the bike.", "Little", "Lots"],
			["stickBodyTilt", "Body stays as the bike tilts.", "Follows", "Stays"],
		]],
		["Landing", [
			["*landSwapRate", "How quickly the bike and rider swing over to the next turn in the first third of a second after touch-down. Low = heavy, high = snappy.", "Heavy", "Snappy"],
			["camHeadingRate", "The camera does not jump round when you land turned: its heading turns at most this fast. Low = floaty, high / 0 = the old snap.", "Floaty", "Snap"],
			["*airBodyMin", "Skips shorter than this (a fast bike bouncing off a berm face) keep the rider's ground pose; only longer flights get the air pose. 0 = every skip switches (the old wobble).", "Every skip", "Only big air"],
			["airBodyIn", "How long the rider takes to go into the air pose off a lip.", "Snappy", "Smooth"],
			["airBodyOut", "How long the rider takes to go back to the ground pose after touch-down.", "Snappy", "Smooth"],
			["*landSlide", "Land on ground tilted sideways: the hit is softer, the rest slides you towards its low side.", "Sticks", "Slides"],
			["*slamJolt", "The hit that throws him down (what gets through suspension, tyres and legs).", "Fragile", "Tough"],
			["*landHeavy", "From this share of that, a landing is heavy: speed lost, a moment to recover.", "Soon", "Rarely"],
			["*landForgive", "Landed square to the ground: how much bigger a hit is only a heavy landing, not a crash.", "Strict", "Forgiving"],
			["*landYawFree", "Landed turned to the way you travel: this much costs nothing.", "Strict", "Forgiving"],
			["landYawGrip", "How much sideways speed the tyres catch at once (the rest is a slide).", "Slides", "Bites"],
			["*landYawCrash", "Sideways speed caught at once that throws you over (highside).", "Soon", "Never"],
			["landPrepTime", "Reaches for the landing.", "Late", "Early"],
			["shortAim", "Short hops only (under about a second of air): how much sooner and firmer he lines the bike up. 0 = as long jumps.", "Off", "Strong"],
			["*airAssist","How much the rider lines the bike up for the landing by himself. Only with your hands off the stick: your stick always wins.", "All yours", "He helps"],
			["airAimDelay", "Waits before aiming at the landing.", "At once", "Later"],
			["airAimSpeed", "Aim at the landing: softness.", "Soft", "Firm"],
			["landBack", "Back-wheel balance limit.", "Strict", "Forgiving"],
		]],
	]],
	["smooth", "Smoothing", "How smooth the ride looks: ground readings and how fast drawn parts may move. The steering itself stays as set", [
		["Ground readings", [
			["*bankSmooth", "The tilt under the bike settles over this long (rough ground, bank to bank).", "Raw", "Smooth"],
			["*knockSmooth", "Rock and rut knocks on the front build over this long.", "Sharp", "Soft"],
			["tyreRelax", "Tyre grip follows the load on it after this long (bumps).", "Instant", "Lazy"],
			["cornerSmooth", "The turn's load on the rider's legs builds over this long.", "Instant", "Soft"],
			["bankLeanRate", "Fastest the lean into tilted ground can change.", "Slow", "Fast"],
		]],
		["Motion caps (drawing only)", [
			["*motionCap", "Top speed of drawn bike lean, bars, body roll and hips: below 1 calmer, above 1 looser.", "Calm", "Loose"],
			["*torsoMaxSpeed", "The rider's hips and chest never move faster than this against the bike.", "Calm", "Free"],
		]],
	]],
	["demo", "Demo", "The AI rider (F2)", [
		["Demo rider", [
			["*demoPace", "Cornering pace (1 = safe pro).", "Careful", "Fast"],
			["*demoMaxKmh", "Top speed it allows.", "Slow", "Fast"],
			["demoLine", "Racing line (cuts the corners).", "Middle", "Cuts"],
			["demoPump", "Pumps the lips.", "No", "Yes"],
			["demoSmooth", "Smooth hands (higher = softer).", "Sharp", "Smooth"],
		]],
	]],
]

static var _checked: Array = []

## PAGES + a "More" section on the last ride page with any Tune key nobody placed (new sliders never get lost)
static func pages() -> Array:
	if not _checked.is_empty(): return _checked
	var placed := {}
	for r in FEEL: placed[r[0]] = true
	for p in PAGES:
		for sec in p[3]:
			for r in sec[1]: placed[str(r[0]).trim_prefix("*")] = true
	var more: Array = []
	for g in Tune.DEFS:
		for row in g[1]:
			var k: String = row[0]
			if k.begins_with("dust") or placed.has(k): continue
			more.append([k, "", "", ""])
	_checked = PAGES.duplicate(true)
	if not more.is_empty():
		for p in _checked:
			if p[0] == "body": p[3].append(["More", more])
	return _checked


static func page(id: String) -> Array:
	for p in pages():
		if p[0] == id: return p
	return []


## every key a page shows (Reset)
static func page_keys(id: String) -> Array:
	var out: Array = []
	if id == "feel":
		for r in FEEL: out.append(r[0])
		return out
	var p := page(id)
	if p.is_empty(): return out
	for sec in p[3]:
		for r in sec[1]: out.append(str(r[0]).trim_prefix("*"))
	return out
