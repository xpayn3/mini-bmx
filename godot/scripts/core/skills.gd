class_name Skills
extends RefCounted
## The rider's skills, like the motocross games' rider card: every skill collects XP while he rides and levels up.
## XP is earned by what he does on the bike (GameState.skill_tick / skill_xp feed it, the HUD pops a level up);
## nothing here touches the riding physics. Saved in save.cfg [skills].

const MAX_LEVEL := 10
## cumulative XP needed to HAVE level L (L1 = 0): 100 x (L-1)^2  ->  L2 100, L3 400, L5 1600, L10 8100
const STEP := 100.0

## id -> [name, what earns it]
const DEFS := {
	"speed": ["TOP SPEED", "RIDING FAST: XP EVERY SECOND ABOVE 30 KM/H, MORE THE FASTER"],
	"cornering": ["CORNERING", "LEANING INTO TURNS AT SPEED"],
	"balance": ["BALANCE", "HOLDING A MANUAL OR A NOSE MANUAL"],
	"jumping": ["JUMPING", "EVERY JUMP LANDED: LONGER FLIGHTS PAY MORE"],
	"air": ["BIG AIR", "HEIGHT AND HANG TIME OF A LANDED JUMP"],
	"style": ["STYLE", "TRICKS AND STYLE POINTS, A BONUS FOR EACH NEW TRICK"],
	"endurance": ["ENDURANCE", "DISTANCE RIDDEN"],
	"consistency": ["CONSISTENCY", "RIDING DAY AFTER DAY"],
}
const ORDER := ["speed", "cornering", "balance", "jumping", "air", "style", "endurance", "consistency"]

# ---- what each thing pays (tune here)
const SPEED_FROM := 30.0        # km/h
const SPEED_RATE := 0.06        # XP per second per km/h above it (60 km/h = 1.8 XP/s)
const CORNER_LEAN := 0.35       # rad of lean that counts as cornering
const CORNER_MIN_V := 7.0       # m/s
const CORNER_RATE := 2.5        # XP per second at 0.8 rad of lean
const BALANCE_RATE := 4.0       # XP per second in a manual / nose manual
const JUMP_BASE := 5.0          # per landed jump...
const JUMP_PER_M := 1.2         # ...plus per metre flown
const AIR_PER_M := 30.0         # per metre of height (height^1.3: small hops pay little)
const AIR_PER_S := 12.0         # per second of hang time
const STYLE_PER_POINT := 0.12
const TRICK_BONUS := 40.0       # every trick landed
const NEW_TRICK_BONUS := 120.0  # the first time a trick family is landed
const ENDURANCE_PER_KM := 8.0
const DAILY_BASE := 50.0        # the day's first activity...
const DAILY_STEP := 20.0        # ...plus per day of the streak (up to 10)

## XP that has to be collected in total to have level `lv`
static func xp_at(lv: int) -> float:
	return STEP * float((lv - 1) * (lv - 1))

static func level_of(xp: float) -> int:
	var lv := 1
	while lv < MAX_LEVEL and xp + 1e-6 >= xp_at(lv + 1): lv += 1
	return lv

## [level, XP into this level, XP this level takes (0 at the top), fraction 0..1]
static func progress(xp: float) -> Array:
	var lv := level_of(xp)
	if lv >= MAX_LEVEL: return [lv, xp - xp_at(lv), 0.0, 1.0]
	var a := xp_at(lv)
	var b := xp_at(lv + 1)
	return [lv, xp - a, b - a, clampf((xp - a) / (b - a), 0.0, 1.0)]

## players from before the XP system keep what their records earned: the old record-based levels, as XP
static func seed_from_records(r: Dictionary, tricks: int, day_best: int) -> Dictionary:
	var out := {}
	out["speed"] = _seed(float(r.get("top_speed", 0.0)), [0, 30, 45, 55, 65, 75, 85, 95, 105, 120])
	out["jumping"] = _seed(float(r.get("longest", 0.0)), [0, 5, 10, 15, 20, 30, 40, 50, 65, 80])
	out["air"] = maxf(_seed(float(r.get("highest", 0.0)), [0, 0.5, 1, 2, 3, 4, 6, 8, 10, 12]), _seed(float(r.get("air", 0.0)), [0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 6]))
	out["style"] = _seed(float(tricks), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	out["endurance"] = _seed(float(r.get("distance", 0.0)) / 1000.0, [0, 5, 15, 30, 60, 100, 150, 250, 400, 600])
	out["consistency"] = _seed(float(day_best), [0, 1, 2, 3, 5, 7, 10, 14, 21, 30])
	return out

static func _seed(v: float, th: Array) -> float:
	var lv := 0
	for t in th:
		if v + 1e-6 >= float(t): lv += 1
	return xp_at(clampi(lv, 1, MAX_LEVEL))
