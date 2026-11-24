class_name PoseKeys
extends RefCounted
## Pose Lab keyframes: STYLE only, never physics. A key = a set of pose offsets at one moment of a jump, the moment
## given on a normalised JUMP TIMELINE (0..1: approach, load, pop, air, reach, land) instead of seconds, so one set of
## keys fits any jump size and speed. Between keys every channel is morphed with a smooth cubic (Cardinal / Catmull-Rom
## tangents); before the first key and after the last the pose eases to neutral at 0 and 1. The values are added on top
## of the live procedural pose (Rider.update_pose, "pk"), so lean, speed and the limits keep working. The limbs stay
## pinned to the grips and pedals: hips / torso / head move, the arms and legs follow by IK.
## Saved as JSON: res://data/pose_keys.json (committed with the game; user://pose_keys.json when res:// is read-only).

const PATH_RES := "res://data/pose_keys.json"
const PATH_USER := "user://pose_keys.json"
const VER := 1
const SAME := 0.012            # two keys closer than this on the timeline are the same key

## [id, label, group, min, max, step, unit hint]. Angles in radians (shown in degrees by the UI), offsets in metres.
const CH := [
	["rel_pitch", "Bike nose up (under body)", "BIKE", -0.9, 0.9, 0.01, "deg"],
	["rel_roll", "Bike lay over (under body)", "BIKE", -0.9, 0.9, 0.01, "deg"],
	["bar_steer", "Handlebar turn", "BIKE", -0.9, 0.9, 0.01, "deg"],
	["hip_x", "Hips forward", "HIPS", -0.3, 0.3, 0.005, "cm"],
	["hip_y", "Hips up", "HIPS", -0.3, 0.3, 0.005, "cm"],
	["hip_z", "Hips right", "HIPS", -0.25, 0.25, 0.005, "cm"],
	["torso_pitch", "Torso lean forward", "TORSO", -0.8, 0.8, 0.01, "deg"],
	["torso_roll", "Torso lean right", "TORSO", -0.6, 0.6, 0.01, "deg"],
	["torso_yaw", "Shoulders turn", "TORSO", -0.8, 0.8, 0.01, "deg"],
	["head_pitch", "Head nod down", "HEAD", -0.6, 0.6, 0.01, "deg"],
	["head_yaw", "Head turn", "HEAD", -0.9, 0.9, 0.01, "deg"],
	["elbows_out", "Elbows out", "LIMBS", -0.6, 0.9, 0.01, ""],
	["knees_out", "Knees out", "LIMBS", -0.6, 0.9, 0.01, ""],
]
## the timeline's parts: [name, start]; each runs to the next one's start (the last to 1.0)
const PHASES := [["APPROACH", 0.0], ["LOAD", 0.12], ["POP", 0.30], ["AIR", 0.40], ["REACH", 0.80], ["LAND", 0.90]]

static var keys: Array = []          # [{t: float, v: {channel: float}}] sorted by t
static var enabled := true           # the keys play in rides
static var amount := 1.0             # how much of them (0 = none .. 1.5)
static var dirty := false
static var _loaded := false
static var status := ""


static func ch_ids() -> PackedStringArray:
	var o := PackedStringArray()
	for c in CH: o.append(c[0])
	return o


static func ch_info(id: String) -> Array:
	for c in CH:
		if c[0] == id: return c
	return []


static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	load_file()


static func load_file() -> void:
	keys.clear()
	var path := PATH_USER if FileAccess.file_exists(PATH_USER) else PATH_RES
	if not FileAccess.file_exists(path):
		dirty = false
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if d is Dictionary:
		for k in (d.get("keys", []) as Array):
			if k is Dictionary and k.has("t"):
				var v := {}
				for id in ch_ids(): v[id] = float((k.get("v", {}) as Dictionary).get(id, 0.0))
				keys.append({"t": clampf(float(k.t), 0.0, 1.0), "v": v})
		enabled = bool(d.get("enabled", true))
		amount = float(d.get("amount", 1.0))
	_sort()
	dirty = false


## res:// first (the project folder, committed with the game); user:// where that can't be written
static func save_file() -> String:
	if Settings._no_save:   # test runs never write the real files
		status = "NOT SAVED (TEST RUN)"
		return status
	var out := {"version": VER, "enabled": enabled, "amount": amount, "keys": keys}
	var txt := JSON.stringify(out, "\t")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var f := FileAccess.open(PATH_RES, FileAccess.WRITE)
	var where := PATH_RES
	if f == null:
		f = FileAccess.open(PATH_USER, FileAccess.WRITE)
		where = PATH_USER
	elif FileAccess.file_exists(PATH_USER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH_USER))   # (a stale copy would shadow the project's)
	if f == null:
		status = "SAVE FAILED"
		return status
	f.store_string(txt)
	f.close()
	dirty = false
	status = "SAVED " + where
	return status


static func _sort() -> void:
	keys.sort_custom(func(a, b): return float(a.t) < float(b.t))


static func zero_vals() -> Dictionary:
	var v := {}
	for id in ch_ids(): v[id] = 0.0
	return v


static func key_at(t: float) -> int:
	var best := -1
	var bd := SAME
	for i in keys.size():
		var d := absf(float(keys[i].t) - t)
		if d <= bd: bd = d; best = i
	return best


## the (morphed) value of every channel at timeline position t, x k
static func eval(t: float, k: float = 1.0) -> Dictionary:
	var out := {}
	if keys.is_empty() or k <= 0.0 or t < 0.0: return out
	t = clampf(t, 0.0, 1.0)
	# the key list with the implicit neutral ends
	var ts: Array = []
	var vs: Array = []
	if float(keys[0].t) > 0.001:
		ts.append(0.0); vs.append(zero_vals())
	for kk in keys:
		ts.append(float(kk.t)); vs.append(kk.v)
	if float(keys[-1].t) < 0.999:
		ts.append(1.0); vs.append(zero_vals())
	var n := ts.size()
	var i := 0
	while i < n - 2 and t > float(ts[i + 1]): i += 1
	var i1 := mini(i + 1, n - 1)
	var t0: float = ts[i]
	var t1: float = ts[i1]
	var u := 0.0 if t1 <= t0 + 1e-6 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	var ia := maxi(i - 1, 0)
	var ib := mini(i1 + 1, n - 1)
	for id in ch_ids():
		var p0: float = float(vs[i][id])
		var p1: float = float(vs[i1][id])
		# Cardinal tangents (per unit of u) from the neighbours, scaled to this segment's length
		var m0: float = (p1 - float(vs[ia][id])) / maxf(float(ts[i1]) - float(ts[ia]), 1e-4) * (t1 - t0)
		var m1: float = (float(vs[ib][id]) - p0) / maxf(float(ts[ib]) - float(ts[i]), 1e-4) * (t1 - t0)
		if i == ia: m0 = p1 - p0   # (the first segment: no neighbour before it)
		if i1 == ib: m1 = p1 - p0
		var u2 := u * u
		var u3 := u2 * u
		var val: float = (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1
		var inf: Array = ch_info(id)
		out[id] = clampf(val * k, float(inf[3]) * 1.5, float(inf[4]) * 1.5)
	return out


## set (or add) the key at t; vals = the channels to write (the rest keep the morphed value there). Returns its index
static func set_key(t: float, vals: Dictionary) -> int:
	t = clampf(t, 0.0, 1.0)
	var i := key_at(t)
	if i < 0:
		var base := eval(t, 1.0)
		if base.is_empty(): base = zero_vals()
		keys.append({"t": t, "v": base})
		_sort()
		i = key_at(t)
	for id in vals:
		if ch_info(id).size() > 0: keys[i].v[id] = float(vals[id])
	dirty = true
	return i


static func delete_key(i: int) -> void:
	if i >= 0 and i < keys.size():
		keys.remove_at(i)
		dirty = true


static func move_key(i: int, t: float) -> int:
	if i < 0 or i >= keys.size(): return i
	var k: Dictionary = keys[i]
	k.t = clampf(t, 0.0, 1.0)
	_sort()
	dirty = true
	return keys.find(k)


static func phase_name(t: float) -> String:
	var nm := "-"
	for p in PHASES:
		if t >= float(p[1]) - 1e-6: nm = p[0]
	return nm
