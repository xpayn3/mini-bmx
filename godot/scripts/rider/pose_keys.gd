class_name PoseKeys
extends RefCounted
## The pose CLIP library (Pose Lab): STYLE only, never physics. Industry-style layered animation: the rider's live
## procedural pose (physics + IK) stays underneath, and authored ADDITIVE clips are faded in on top of it when the
## game says so (a whip, a tabletop, a flip, a manual, a jump...).
## A clip = a set of keys (pose offsets over the clip's own timeline) + how it is driven:
##   trigger     what in the game turns it on (a signal read from the physics state, 0..1, with a side for mirroring)
##   time source "jump" = the normalised jump timeline (approach .. land), "clip" = seconds since the trigger fired
##   fade in / out, strength, mirror (a left whip is the right whip flipped), enabled
## Between keys every channel is morphed with a smooth cubic (Cardinal tangents); before the first key and after the last
## it eases to neutral at 0 and 1. All active clips are summed (weight x strength x amount), then the rider's own
## limits (bars, reach) still apply. Hands and feet stay pinned to the grips and pedals; hips / torso / head move,
## arms and legs follow by IK.
## Saved as JSON: res://data/pose_keys.json (committed with the game; user://pose_keys.json when res:// is read-only).

const PATH_RES := "res://data/pose_keys.json"
const PATH_USER := "user://pose_keys.json"
const VER := 2
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
## channels that flip sign when a clip is mirrored (a left whip -> a right whip)
const MIRROR := ["rel_roll", "bar_steer", "hip_z", "torso_roll", "torso_yaw", "head_yaw"]
## the jump timeline's parts: [name, start]; each runs to the next one's start (the last to 1.0)
const PHASES := [["APPROACH", 0.0], ["LOAD", 0.12], ["POP", 0.30], ["AIR", 0.40], ["REACH", 0.80], ["LAND", 0.90]]
## what turns a clip on: [id, label]. The signals are read in Game._clip_signal (physics state, read only)
const TRIGGERS := [
	["jump", "Jump (whole jump timeline)"], ["whip", "Air whip"], ["tabletop", "Tabletop (side lean in air)"],
	["scrub", "Scrub / squash at a lip"], ["backflip", "Back flip"], ["frontflip", "Front flip"], ["spin", "Flat spin"],
	["manual", "Manual / wheelie"], ["stoppie", "Nose manual / stoppie"], ["corner", "Cornering (lean)"],
	["sprint", "Sprinting"], ["air", "Any time in the air"], ["ground", "Any time on the ground"], ["always", "Always"],
	["manual_only", "Never (only when previewed)"],
]
const TIME_SRC := [["jump", "Jump timeline"], ["clip", "Clip time (s)"]]

static var clips: Array = []         # [{name, trigger, time, length, fade_in, fade_out, strength, mirror, enabled, keys}]
static var cur := 0                  # the clip being edited
static var keys: Array = []          # = clips[cur].ks (the same array): [{t: float, v: {channel: float}}] sorted by t
static var enabled := true           # the clips play in rides
static var amount := 1.0             # how much of them all (0 = none .. 1.5)
static var dirty := false
static var rev := 0                  # bumped when the library's clips change (the replay's style names)
static var live_t := -1.0            # where the current clip is now in its own timeline (Game sets it; -1 = off)
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


# ---- clips ------------------------------------------------------------------------------------------------------

static func make_clip(nm: String, trigger: String = "manual_only", time: String = "clip") -> Dictionary:
	return {"name": nm, "trigger": trigger, "time": time, "length": 0.6, "fade_in": 0.12, "fade_out": 0.25,
		"strength": 1.0, "mirror": true, "enabled": true, "ks": []}


static func cur_clip() -> Dictionary:
	if clips.is_empty(): return {}
	return clips[clampi(cur, 0, clips.size() - 1)]


static func select(i: int) -> void:
	if clips.is_empty(): return
	cur = clampi(i, 0, clips.size() - 1)
	keys = clips[cur].ks


static func add_clip(c: Dictionary) -> int:
	clips.append(c)
	rev += 1
	select(clips.size() - 1)
	dirty = true
	return cur


static func duplicate_clip(i: int) -> int:
	if i < 0 or i >= clips.size(): return cur
	var c: Dictionary = (clips[i] as Dictionary).duplicate(true)
	c.name = str(c.name) + " copy"
	c.erase("_rt")
	return add_clip(c)


static func delete_clip(i: int) -> void:
	if clips.size() <= 1 or i < 0 or i >= clips.size(): return   # (one clip always stays)
	clips.remove_at(i)
	rev += 1
	select(mini(i, clips.size() - 1))
	dirty = true


## the runtime state of a clip (its fade weight, time since it fired, the side it fired on)
static func rt(c: Dictionary) -> Dictionary:
	if not c.has("_rt"): c["_rt"] = {"w": 0.0, "age": 0.0, "side": 1.0}
	return c["_rt"]


# ---- the starter library ----------------------------------------------------------------------------------------

static func _k(t: float, v: Dictionary) -> Dictionary:
	var full := zero_vals()
	for id in v: full[id] = float(v[id])
	return {"t": t, "v": full}


## clips a new install starts with: a first guess to tweak in the Lab (every one is editable, none is final)
static func starter() -> Array:
	var out: Array = []
	var c := make_clip("Jump style", "jump", "jump")
	c.fade_in = 0.05; c.fade_out = 0.1
	out.append(c)
	c = make_clip("Whip", "whip", "clip")
	c.length = 0.45; c.fade_in = 0.08; c.fade_out = 0.3
	c.ks = [_k(0.0, {}), _k(0.35, {"rel_roll": 0.35, "torso_roll": -0.2, "hip_z": -0.06, "torso_yaw": 0.2, "head_yaw": -0.25, "knees_out": 0.25}),
		_k(1.0, {"rel_roll": 0.45, "torso_roll": -0.25, "hip_z": -0.08, "torso_yaw": 0.25, "head_yaw": -0.3, "knees_out": 0.3})]
	out.append(c)
	c = make_clip("Tabletop", "tabletop", "clip")
	c.length = 0.35; c.fade_in = 0.12; c.fade_out = 0.3
	c.ks = [_k(0.0, {}), _k(1.0, {"rel_roll": 0.7, "torso_roll": -0.3, "hip_z": -0.1, "knees_out": 0.4, "elbows_out": 0.2, "head_yaw": -0.2})]
	out.append(c)
	c = make_clip("Scrub", "scrub", "clip")
	c.length = 0.25; c.fade_in = 0.08; c.fade_out = 0.3
	c.ks = [_k(0.0, {}), _k(1.0, {"rel_roll": 0.5, "hip_y": -0.08, "hip_x": -0.05, "torso_pitch": 0.3, "knees_out": 0.3})]
	out.append(c)
	c = make_clip("Back flip tuck", "backflip", "clip")
	c.length = 0.8; c.fade_in = 0.1; c.fade_out = 0.3; c.mirror = false
	c.ks = [_k(0.0, {}), _k(0.4, {"hip_y": -0.06, "torso_pitch": 0.35, "head_pitch": 0.25, "knees_out": 0.25}), _k(1.0, {"hip_y": -0.04, "torso_pitch": 0.2, "head_pitch": 0.1})]
	out.append(c)
	c = make_clip("Front flip tuck", "frontflip", "clip")
	c.length = 0.8; c.fade_in = 0.1; c.fade_out = 0.3; c.mirror = false
	c.ks = [_k(0.0, {}), _k(0.4, {"hip_y": -0.06, "hip_x": 0.05, "torso_pitch": 0.45, "head_pitch": 0.3, "knees_out": 0.2}), _k(1.0, {"torso_pitch": 0.2, "head_pitch": 0.1})]
	out.append(c)
	c = make_clip("Manual", "manual", "clip")
	c.length = 0.4; c.fade_in = 0.15; c.fade_out = 0.3; c.mirror = false
	c.ks = [_k(0.0, {}), _k(1.0, {"hip_x": -0.07, "hip_y": -0.03, "torso_pitch": -0.2, "head_pitch": -0.1})]
	out.append(c)
	c = make_clip("Stoppie", "stoppie", "clip")
	c.length = 0.4; c.fade_in = 0.15; c.fade_out = 0.3; c.mirror = false
	c.ks = [_k(0.0, {}), _k(1.0, {"hip_x": 0.07, "hip_y": 0.02, "torso_pitch": 0.3, "head_pitch": 0.15, "elbows_out": 0.2})]
	out.append(c)
	c = make_clip("Attack stance", "ground", "clip")
	c.length = 0.5; c.fade_in = 0.3; c.fade_out = 0.3; c.mirror = false; c.enabled = false
	c.ks = [_k(0.0, {}), _k(1.0, {"hip_y": -0.03, "torso_pitch": 0.1, "elbows_out": 0.25, "knees_out": 0.15})]
	out.append(c)
	return out


# ---- load / save ------------------------------------------------------------------------------------------------

static func _keys_from(arr: Array) -> Array:
	var out: Array = []
	for k in arr:
		if k is Dictionary and k.has("t"):
			var v := {}
			for id in ch_ids(): v[id] = float((k.get("v", {}) as Dictionary).get(id, 0.0))
			out.append({"t": clampf(float(k.t), 0.0, 1.0), "v": v})
	out.sort_custom(func(a, b): return float(a.t) < float(b.t))
	return out


static func load_file() -> void:
	clips.clear()
	var path := PATH_USER if FileAccess.file_exists(PATH_USER) else PATH_RES
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary:
				enabled = bool(d.get("enabled", true))
				amount = float(d.get("amount", 1.0))
				if d.has("clips"):
					for cd in (d.clips as Array):
						if not (cd is Dictionary): continue
						var c := make_clip(str(cd.get("name", "Clip")), str(cd.get("trigger", "manual_only")), str(cd.get("time", "clip")))
						c.length = maxf(float(cd.get("length", 0.6)), 0.05)
						c.fade_in = maxf(float(cd.get("fade_in", 0.12)), 0.0)
						c.fade_out = maxf(float(cd.get("fade_out", 0.25)), 0.0)
						c.strength = float(cd.get("strength", 1.0))
						c.mirror = bool(cd.get("mirror", true))
						c.enabled = bool(cd.get("enabled", true))
						c.ks = _keys_from(cd.get("ks", []) as Array)
						clips.append(c)
				elif d.has("keys"):   # (version 1: one key set = the jump style)
					var c1 := make_clip("Jump style", "jump", "jump")
					c1.fade_in = 0.05; c1.fade_out = 0.1
					c1.ks = _keys_from(d.get("keys", []) as Array)
					clips.append(c1)
	if clips.is_empty(): clips = starter()
	rev += 1
	select(0)
	dirty = false


## res:// first (the project folder, committed with the game); user:// where that can't be written
static func save_file() -> String:
	if Settings._no_save:   # test runs never write the real files
		status = "NOT SAVED (TEST RUN)"
		return status
	var cl: Array = []
	for c in clips:
		var o := {}
		for k in c:
			if not str(k).begins_with("_"): o[k] = c[k]   # (no runtime state)
		cl.append(o)
	var out := {"version": VER, "enabled": enabled, "amount": amount, "clips": cl}
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


# ---- keys of the current clip -----------------------------------------------------------------------------------

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


## the (morphed) value of every channel of the CURRENT clip at timeline position t, x k
static func eval(t: float, k: float = 1.0) -> Dictionary:
	return eval_keys(keys, t, k)


## the same for any key list (a clip's)
static func eval_keys(ks: Array, t: float, k: float = 1.0) -> Dictionary:
	var out := {}
	if ks.is_empty() or k <= 0.0 or t < 0.0: return out
	t = clampf(t, 0.0, 1.0)
	# the key list with the implicit neutral ends
	var ts: Array = []
	var vs: Array = []
	if float(ks[0].t) > 0.001:
		ts.append(0.0); vs.append(zero_vals())
	for kk in ks:
		ts.append(float(kk.t)); vs.append(kk.v)
	if float(ks[-1].t) < 0.999:
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


## the label of timeline position t in the current clip: a jump phase, or seconds
static func phase_name(t: float) -> String:
	var c := cur_clip()
	if c.is_empty() or str(c.time) == "jump":
		var nm := "-"
		for p in PHASES:
			if t >= float(p[1]) - 1e-6: nm = p[0]
		return nm
	return "%.2fs" % (t * float(c.length))
