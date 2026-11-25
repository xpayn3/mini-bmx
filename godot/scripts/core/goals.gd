class_name Goals
extends RefCounted
## Weekly and monthly goals (the profile's GOALS tab): a few clear targets that reset every Monday / on the 1st, each paying cash into the wallet
## once the rider CLAIMS it (the claim is the reason to open the profile; the avatar shows a dot while something waits). Weekly distance
## adapts to the rider: 10 % over their average of the last four weeks, so it stays reachable and keeps climbing.
## Progress is read from GameState.days (per day: [metres, rides]); nothing is stored but which goals were claimed.

const MIN_WEEK_M := 10000.0
const MAX_WEEK_M := 150000.0

static func _round_to(v: float, step: float) -> float:
	return roundf(v / step) * step

## this week's distance target (metres): 10 % over the last four weeks' average, rounded to 5 km
static func week_target_m() -> float:
	var w := GameState.week_of(GameState.today())
	var tot := 0.0
	for d in GameState.days:
		var k := w - GameState.week_of(int(d))
		if k >= 1 and k <= 4: tot += float(GameState.days[d][0])
	return clampf(_round_to(tot / 4.0 * 1.1, 5000.0), MIN_WEEK_M, MAX_WEEK_M)

static func _month_key(day: int) -> int:
	var t := Time.get_date_dict_from_unix_time(day * 86400)
	return int(t.year) * 12 + int(t.month) - 1

static func today_month() -> int:
	return _month_key(GameState.today())

## every goal now: {key, kind "week" | "month", title, have, want, reward, unit ("m" | "n"), claimed, done}
static func list() -> Array:
	var out: Array = []
	var td := GameState.today()
	var w := GameState.week_of(td)
	var mo := today_month()
	var wm := 0.0; var wr := 0; var wd := 0
	var mm := 0.0; var mr := 0; var md := 0
	for d in GameState.days:
		var e: Array = GameState.days[d]
		if GameState.week_of(int(d)) == w:
			wm += float(e[0]); wr += int(e[1])
			if int(e[1]) > 0: wd += 1
		if _month_key(int(d)) == mo:
			mm += float(e[0]); mr += int(e[1])
			if int(e[1]) > 0: md += 1
	var wt := week_target_m()
	var add := func(key: String, kind: String, title: String, have: float, want: float, reward: int, unit: String) -> void:
		var done := have >= want
		out.append({"key": key, "kind": kind, "title": title, "have": have, "want": want, "reward": reward, "unit": unit,
			"claimed": GameState.claimed.has(key), "done": done})
	add.call("w%d:dist" % w, "week", "RIDE %d KM" % roundi(wt / 1000.0), wm, wt, int(wt / 1000.0 * 12.0) + 200, "m")
	add.call("w%d:rides" % w, "week", "3 RIDES", float(wr), 3.0, 250, "n")
	add.call("w%d:days" % w, "week", "RIDE ON 3 DAYS", float(wd), 3.0, 300, "n")
	add.call("m%d:dist" % mo, "month", "RIDE %d KM" % roundi(wt * 4.0 / 1000.0), mm, wt * 4.0, int(wt / 1000.0 * 4.0 * 12.0) + 800, "m")
	add.call("m%d:days" % mo, "month", "RIDE ON 12 DAYS", float(md), 12.0, 1000, "n")
	add.call("m%d:rides" % mo, "month", "20 RIDES", float(mr), 20.0, 1200, "n")
	return out

## done but not yet claimed
static func claimable() -> int:
	var n := 0
	for g in list():
		if g.done and not g.claimed: n += 1
	return n

## pays a finished goal once; false if it isn't done / was paid already
static func claim(key: String) -> bool:
	for g in list():
		if g.key == key:
			if not g.done or g.claimed: return false
			GameState.claimed[key] = true
			GameState.earn(int(g.reward), ("Weekly goal: " if g.kind == "week" else "Monthly goal: ") + String(g.title).capitalize())
			return true
	return false

static func days_left_week() -> int:
	return (GameState.week_of(GameState.today()) + 1) * 7 - 3 - GameState.today()

static func days_left_month() -> int:
	var t := Time.get_date_dict_from_unix_time(GameState.today() * 86400)
	var dim: int = [31, 29 if (int(t.year) % 4 == 0 and (int(t.year) % 100 != 0 or int(t.year) % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][int(t.month) - 1]
	return dim - int(t.day) + 1
