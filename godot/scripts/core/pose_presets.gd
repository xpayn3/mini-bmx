class_name PosePresets
extends RefCounted
## Named riding positions (the rider's pose sliders) for the garage Rider tab and the tuning card's
## Rider tab. Picking one makes it the pose you ride with (RiderPanels.save_pose, per bike).
## Built-ins are changes on top of the bike's own stock pose; the player's own presets hold every value.
## Saved to user://pose_presets.cfg. An own preset follows its sliders as they move (like TunePresets);
## a built-in shows "changed" until Save as. Same static API as TunePresets, so the preset bar works for both.

const BUILTIN := {
	"Stock": {},
	"Attack": {"hipY": -0.06, "lean": 0.42, "elbowsOut": 0.45, "kneesOut": 0.4, "headTilt": -0.12, "spineCurve": -0.08,
		"shoulderFwd": 0.03, "elbowsDown": -0.2, "heelUp": -0.02},
	"Relaxed": {"hipY": 0.04, "lean": 0.05, "elbowsOut": -0.4, "kneesOut": 0.1, "spineCurve": 0.12, "headTilt": 0.05,
		"shoulderUp": 0.02, "headTurn": 0.7},
	"Racer": {"hipX": 0.04, "hipY": -0.03, "lean": 0.55, "elbowsOut": 0.2, "spineCurve": 0.1, "headTilt": -0.2,
		"lookAhead": 0.05, "shoulderFwd": 0.05, "kneesOut": 0.15},
	"Laid back": {"hipX": -0.1, "hipY": 0.02, "lean": 0.0, "elbowsOut": 0.1, "spineCurve": -0.05, "headTilt": 0.0,
		"kneesFwd": -0.3, "heelFwd": 0.02},
	"Steezy": {"hipY": -0.02, "lean": 0.3, "elbowsOut": 0.7, "kneesOut": 0.6, "twist": 0.12, "pelvisYaw": 0.1,
		"headYaw": 0.12, "headTilt": -0.05, "footOut": 0.2},
}
const PATH := "user://pose_presets.cfg"

static var bike := "dh"      # whose pose the presets apply to (set by the garage / tuning card)
static var active := {}      # bike -> preset name
static var customs := {}     # name -> full pose
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		active = cf.get_value("presets", "active", {})
		customs = cf.get_value("presets", "customs", {})


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("presets", "active", active)
	cf.set_value("presets", "customs", customs)
	cf.save(PATH)


static func stock() -> Dictionary:
	var p: Dictionary = Rider.NEUTRAL.duplicate()
	p.merge(GameState.BIKES[bike].pose if GameState.BIKES.has(bike) else {}, true)
	return p


static func get_active() -> String:
	ensure_loaded()
	var a: String = str(active.get(bike, "Stock"))
	return a if (a in BUILTIN or a in customs) else "Stock"


static func builtin_count() -> int:
	return BUILTIN.size()


static func names() -> Array:
	ensure_loaded()
	var cn: Array = customs.keys(); cn.sort()
	return BUILTIN.keys() + cn


static func is_builtin(n: String) -> bool:
	return n in BUILTIN


## the full pose of a preset for the current bike
static func preset(n: String) -> Dictionary:
	ensure_loaded()
	var out := stock()
	if n in customs:
		for k in customs[n]:
			if out.has(k): out[k] = customs[n][k]
	else:
		var d: Dictionary = BUILTIN.get(n, {})
		for k in d:
			# built-ins are offsets from the bike's stock pose (headTurn is a plain value)
			out[k] = d[k] if k == "headTurn" else float(out.get(k, 0.0)) + float(d[k])
		# kept inside each slider's range
		for g in RiderPanels.POSE_DEFS:
			for row in g[1]:
				if out.has(row[0]): out[row[0]] = clampf(float(out[row[0]]), row[2], row[3])
	return out


## pick a preset: it becomes the pose you ride with
static func select(n: String) -> void:
	ensure_loaded()
	active[bike] = n
	RiderPanels.save_pose(bike, preset(n))
	save()


## the sliders moved (pose already saved): an own preset keeps up with its sliders
static func pose_changed(p: Dictionary) -> void:
	ensure_loaded()
	var a := get_active()
	if a in customs:
		customs[a] = p.duplicate()
		save()


static func modified() -> bool:
	var p := preset(get_active())
	var cur := RiderPanels.load_pose(bike, GameState.BIKES[bike].pose if GameState.BIKES.has(bike) else {})
	for k in p:
		if typeof(p[k]) == TYPE_BOOL:
			if bool(p[k]) != bool(cur.get(k, p[k])): return true
		elif absf(float(p[k]) - float(cur.get(k, p[k]))) > 1e-4: return true
	return false


static func save_as(n: String) -> String:
	ensure_loaded()
	n = n.strip_edges()
	if n == "": n = "My position %d" % (customs.size() + 1)
	if n in BUILTIN: n += " (mine)"
	customs[n] = RiderPanels.load_pose(bike, GameState.BIKES[bike].pose if GameState.BIKES.has(bike) else {})
	active[bike] = n
	save()
	return n


static func delete(n: String) -> void:
	ensure_loaded()
	if not n in customs: return
	customs.erase(n)
	for b in active.keys():
		if active[b] == n: active[b] = "Stock"
	save()
