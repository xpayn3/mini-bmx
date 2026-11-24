class_name AnimLib
extends RefCounted
## The animation library behind the menus' standing rider (RiderAnim) and the Anim Studio (--anim):
##  - IMPORT: any Mixamo FBX / glTF is copied to user://anim/mixamo/ and loaded at RUN TIME (FBXDocument; no editor
##    import needed). Retargeting is automatic: RiderAnim reads the clip's bone DIRECTIONS and keeps the rider's own
##    proportions, so any Mixamo character / skin works.
##  - per clip settings (ON, IDLE = the clip the menu comes back to, speed, pick weight, hold seconds, fade-in, and pose
##    OFFSETS on the same channels as the Pose Lab: hips / torso / head / elbows / knees) in
##    res://data/anim_library.json (committed with the game; user://anim/library.json when res:// is read-only)
##  - BAKE: sample a clip into a Pose Lab clip (PoseKeys) so a Mixamo move can drive the rider in rides too (hips, torso
##    lean / turn, head, elbows / knees out; hands and feet stay on the bike).

const USER_DIR := "user://anim/mixamo/"
const CFG_RES := "res://data/anim_library.json"
const CFG_USER := "user://anim/library.json"
const EXTS := ["fbx", "glb", "gltf"]
## offsets a clip can carry: the Pose Lab's body channels (no bike channels: the menu rider has no bike)
const OFF_CH := ["hip_x", "hip_y", "hip_z", "torso_pitch", "torso_roll", "torso_yaw", "head_pitch", "head_yaw", "elbows_out", "knees_out"]

static var cfg := {}          # clip name -> settings
static var dirty := false
static var _loaded := false
static var status := ""


static func defaults() -> Dictionary:
	return {"on": true, "idle": false, "speed": 1.0, "weight": 1.0, "hold": 0.0, "fade": 0.45, "off": {}}


static func ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	load_cfg()


static func load_cfg() -> void:
	cfg.clear()
	var path := CFG_USER if FileAccess.file_exists(CFG_USER) else CFG_RES
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			f.close()
			if d is Dictionary: cfg = (d.get("clips", {}) as Dictionary).duplicate(true)
	dirty = false


static func save_cfg() -> String:
	if Settings._no_save:
		status = "NOT SAVED (TEST RUN)"
		return status
	var txt := JSON.stringify({"version": 1, "clips": cfg}, "\t")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data"))
	var f := FileAccess.open(CFG_RES, FileAccess.WRITE)
	var where := CFG_RES
	if f == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://anim"))
		f = FileAccess.open(CFG_USER, FileAccess.WRITE)
		where = CFG_USER
	elif FileAccess.file_exists(CFG_USER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_USER))
	if f == null:
		status = "SAVE FAILED"
		return status
	f.store_string(txt)
	f.close()
	dirty = false
	status = "SAVED " + where
	return status


## the settings of a clip (every key present; a new clip gets the defaults)
static func get_cfg(clip: String) -> Dictionary:
	ensure_loaded()
	var c: Dictionary = defaults()
	if cfg.has(clip):
		for k in (cfg[clip] as Dictionary): c[k] = cfg[clip][k]
	return c


static func set_cfg(clip: String, key: String, v) -> void:
	ensure_loaded()
	if not cfg.has(clip): cfg[clip] = {}
	cfg[clip][key] = v
	dirty = true


static func set_off(clip: String, ch: String, v: float) -> void:
	ensure_loaded()
	if not cfg.has(clip): cfg[clip] = {}
	if not cfg[clip].has("off"): cfg[clip]["off"] = {}
	cfg[clip]["off"][ch] = v
	dirty = true


# ---- import ----------------------------------------------------------------------------------------------------

static func user_files() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(USER_DIR)
	if d == null: return out
	for f in d.get_files():
		if f.get_extension().to_lower() in EXTS: out.append(USER_DIR + f)
	out.sort()
	return out


## copy a Mixamo download into the library and check it loads. Returns a message (starts with "IMPORTED" on success)
static func import_file(src: String) -> String:
	if not FileAccess.file_exists(src): return "NOT FOUND: " + src.get_file()
	var ext := src.get_extension().to_lower()
	if not ext in EXTS: return "NOT A CLIP (FBX / GLB): " + src.get_file()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var dst := USER_DIR + src.get_file()
	var bytes := FileAccess.get_file_as_bytes(src)
	if bytes.is_empty(): return "EMPTY FILE: " + src.get_file()
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null: return "CAN'T WRITE " + dst
	f.store_buffer(bytes)
	f.close()
	var inst := load_instance(dst)
	if inst == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dst))
		return "CAN'T READ " + src.get_file() + " (FBX Binary / glTF with a skeleton + animation)"
	inst.free()
	return "IMPORTED " + src.get_file()


static func remove_user_clip(path: String) -> void:
	if path.begins_with(USER_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		cfg.erase(path.get_file().get_basename())
		dirty = true


## a clip file as a node tree, loaded at run time (user:// files: no editor import). null = unreadable
static func load_instance(path: String) -> Node3D:
	var ext := path.get_extension().to_lower()
	var gp := ProjectSettings.globalize_path(path)
	var n: Node = null
	if ext == "fbx":
		var doc := FBXDocument.new()
		var st := FBXState.new()
		if doc.append_from_file(gp, st) == OK: n = doc.generate_scene(st)
	elif ext in ["glb", "gltf"]:
		var doc2 := GLTFDocument.new()
		var st2 := GLTFState.new()
		if doc2.append_from_file(gp, st2) == OK: n = doc2.generate_scene(st2)
	return n as Node3D


# ---- offsets on a retargeted pose -------------------------------------------------------------------------------

## the clip's pose offsets (hips move, torso / head turn, elbows / knees out) on a pose {P: 15 joint points, o: orientations}.
## The upper body is one chain (the hips carry it, a torso tilt carries the head, shoulders and hands); the legs and arms
## are solved again by IK so they never stretch (feet stay where they are, hands follow the chain)
static func offset_pose(pose: Dictionary, off: Dictionary, _rider = null) -> Dictionary:
	var has := false
	for k in OFF_CH:
		if absf(float(off.get(k, 0.0))) > 1e-5: has = true
	if not has: return pose
	var P: Array = (pose.P as Array).duplicate()
	var o: Dictionary = (pose.o as Dictionary).duplicate()
	var hip := Vector3(float(off.get("hip_x", 0.0)), float(off.get("hip_y", 0.0)), float(off.get("hip_z", 0.0)))
	var rot := Basis(Vector3(1, 0, 0), float(off.get("torso_roll", 0.0))) * Basis(Vector3(0, 0, 1), -float(off.get("torso_pitch", 0.0))) \
		* Basis(Vector3.UP, float(off.get("torso_yaw", 0.0)))
	var pel0: Vector3 = P[2]
	var pel: Vector3 = pel0 + hip
	for i in [0, 1, 3, 4, 5, 6, 7, 8]: P[i] = pel + rot * ((P[i] as Vector3) - pel0)
	P[2] = pel
	# the head: nod about the chest, turn about up
	var hp := float(off.get("head_pitch", 0.0))
	var hy := float(off.get("head_yaw", 0.0))
	if absf(hp) > 1e-5 or absf(hy) > 1e-5:
		var hb := Basis(Vector3.UP, hy) * Basis(Vector3(0, 0, 1), -hp)
		P[0] = (P[1] as Vector3) + hb * ((P[0] as Vector3) - (P[1] as Vector3))
		if o.has("head"): o["head"] = hb * (rot * (o["head"] as Basis))
	elif o.has("head"):
		o["head"] = rot * (o["head"] as Basis)
	for i in 2:   # hands / feet orientations follow the chain (hands); the feet stay
		if o.has("hand%d" % i): o["hand%d" % i] = rot * (o["hand%d" % i] as Basis)
	var eo := float(off.get("elbows_out", 0.0))
	var ko := float(off.get("knees_out", 0.0))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# arms: shoulder -> hand, the elbow pushed out / in
		var sh: Vector3 = P[3 + i * 3]
		var ha: Vector3 = P[5 + i * 3]
		var el0: Vector3 = P[4 + i * 3]
		var pole := el0 - (sh + ha) * 0.5 + Vector3(0, 0, side * eo * 0.6)
		var ika := Rider.limb_ik(sh, ha, Rider.L_UARM, Rider.L_FARM, pole.normalized(), Vector3(0, -0.5, side), Rider.ELBOW_MIN, Rider.ELBOW_MAX, Vector3.ZERO, PI)
		P[4 + i * 3] = ika[0]
		P[5 + i * 3] = ika[1]
		# legs: the hips moved with the pelvis, the feet stay: the knee is solved again
		var hpnt: Vector3 = (P[9 + i * 3] as Vector3) + hip
		var ft: Vector3 = P[11 + i * 3]
		var kn0: Vector3 = P[10 + i * 3]
		var pl := kn0 - ((P[9 + i * 3] as Vector3) + ft) * 0.5 + Vector3(0, 0, side * ko * 0.6)
		var ikl := Rider.limb_ik(hpnt, ft, Rider.L_THIGH, Rider.L_SHIN, pl.normalized(), Vector3.UP, Rider.KNEE_MIN, Rider.KNEE_MAX, Vector3.ZERO, PI)
		P[9 + i * 3] = hpnt
		P[10 + i * 3] = ikl[0]
		P[11 + i * 3] = ikl[1]
	return {P = P, o = o}


# ---- bake a clip into a Pose Lab clip ---------------------------------------------------------------------------

## sample clip i of `anim` (a RiderAnim) n times and turn the motion (relative to its first frame) into Pose Lab keys:
## hips move, torso lean / turn, head nod / turn, elbows / knees out. Returns a PoseKeys clip (trigger "never": pick a
## trigger in the Pose Lab to make it play in rides)
static func bake(anim, i: int, n: int = 14) -> Dictionary:
	var c: Dictionary = anim.clips[i]
	var cfgc := get_cfg(str(c.name))
	var base := _chan(anim.pose_at(i, 0.0), null)
	var cl := PoseKeys.make_clip(str(c.name), "manual_only", "clip")
	cl.length = maxf(float(c.len) / maxf(float(cfgc.speed), 0.1), 0.2)
	cl.fade_in = 0.15; cl.fade_out = 0.3
	var ks: Array = []
	for s in n:
		var k := float(s) / float(n - 1)
		var ch := _chan(anim.pose_at(i, k * float(c.len)), base)
		var v := PoseKeys.zero_vals()
		for id in ch:
			var inf: Array = PoseKeys.ch_info(id)
			v[id] = clampf(float(ch[id]), float(inf[3]), float(inf[4]))
		ks.append({"t": k, "v": v})
	cl.ks = ks
	return cl


## the Pose Lab channels of a pose; with `base` the change from that pose
static func _chan(pose: Dictionary, base) -> Dictionary:
	var P: Array = pose.P
	var pel: Vector3 = P[2]
	var ch: Vector3 = P[1]
	var hd: Vector3 = P[0]
	var tv := ch - pel
	var sv: Vector3 = (P[6] as Vector3) - (P[3] as Vector3)
	var hv := hd - ch
	var hb: Basis = pose.o["head"] if (pose.o as Dictionary).has("head") else Basis()
	var fwd := hb.x
	var el := 0.0
	var kn := 0.0
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		el += side * ((P[4 + i * 3] as Vector3).z - (P[3 + i * 3] as Vector3).z)
		kn += side * ((P[10 + i * 3] as Vector3).z - (P[9 + i * 3] as Vector3).z)
	var raw := {
		"hip_x": pel.x, "hip_y": pel.y, "hip_z": pel.z,
		"torso_pitch": atan2(tv.x, tv.y), "torso_roll": atan2(tv.z, tv.y), "torso_yaw": atan2(sv.x, sv.z),
		"head_pitch": atan2(hv.x, hv.y), "head_yaw": atan2(-fwd.z, fwd.x),
		"elbows_out": el * 0.5 / 0.12, "knees_out": kn * 0.5 / 0.12}
	if base == null: return raw
	var out := {}
	for k in raw:
		out[k] = wrapf(float(raw[k]) - float((base as Dictionary)[k]), -PI, PI) if k.contains("pitch") or k.contains("yaw") or k.contains("roll") else float(raw[k]) - float((base as Dictionary)[k])
	return out
