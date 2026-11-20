class_name RiderAnim
extends RefCounted

## Animation clips (Mixamo FBX downloads, or any humanoid glb / fbx with Mixamo bone names) played on the rider.
##
## Drop the files into `DIR` (Mixamo: Format FBX, "Without Skin" is enough, any frame rate). Each clip is loaded,
## played on its own hidden skeleton, and every frame its joints are read and retargeted onto the rider by
## direction: the clip gives where each limb points, the rider keeps its own bone lengths, torso, shoulder width
## (so clips made for any body size fit). Hands, feet and head take the clip's turn relative to its T-pose. Then
## `Rider.pose_points` draws it and the rider's RiderSkeleton follows as always.
##
## Plays the clips one after another (each for ~`CLIP_SECS`, whole loops), crossfading `FADE` s between them;
## a clip whose name has "idle" in it comes back between the others.

const DIR := "res://assets/anim/mixamo/"
const CLIP_SECS := 7.0
const FADE := 0.45
const TO_RIDER := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   # Mixamo (+Z forward, left +X) -> rider
const NEED := ["Hips", "Spine2", "Neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm",
	"RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]

static var _scenes := {}   # path -> PackedScene (kept for the session: a menu opened twice doesn't load again)

var rider: Rider
var clips: Array[Dictionary] = []
var cur := -1
var t := 0.0
var _until := 0.0
var _prev_pose := {}      # the last pose drawn (crossfade source)
var _fade_from := {}
var _fade_t := 1.0
var _rng := RandomNumberGenerator.new()


## the clip files in DIR (works in an exported game too: the .import / .remap names)
static func clip_files(dir := DIR) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null: return out
	for f in d.get_files():
		f = f.trim_suffix(".import").trim_suffix(".remap")
		var ext := f.get_extension().to_lower()
		if ext in ["fbx", "glb", "gltf", "tscn", "scn"] and not out.has(dir + f):
			out.append(dir + f)
	out.sort()
	return out

static func available() -> bool:
	return not clip_files(_dir()).is_empty()

static func _dir() -> String:
	var e := Env.s("BMX_ANIM_DIR")
	return e if e != "" else DIR


func _init(r: Rider) -> void:
	rider = r
	_rng.seed = Time.get_ticks_usec()
	for path in clip_files(_dir()):
		var c := _load_clip(path)
		if not c.is_empty(): clips.append(c)
	var only := Env.s("BMX_ANIM")   # tests: just this clip (part of its file name)
	if only != "":
		clips = clips.filter(func(c): return str(c.name).to_lower().contains(only.to_lower()))
	if Env.s("BMX_ANIM_PROBE") != "":
		print("ANIM clips=%d %s" % [clips.size(), ", ".join(clips.map(func(c): return "%s %.1fs" % [c.name, c.len]))])


func ok() -> bool:
	return not clips.is_empty()


func free_clips() -> void:
	for c in clips:
		if is_instance_valid(c.inst): (c.inst as Node).queue_free()
	clips.clear()


## Mixamo bone names come as "mixamorig:Hips", "mixamorig_Hips", "mixamorig1:Hips"...: the part after the prefix
static func _short(n: String) -> String:
	var i := n.find("mixamorig")
	if i < 0: return n
	var rest := n.substr(i + 9)
	while rest.length() > 0 and (rest[0].is_valid_int() or rest[0] == ":" or rest[0] == "_"):
		rest = rest.substr(1)
	return rest


func _load_clip(path: String) -> Dictionary:
	var ps: PackedScene = _scenes.get(path)
	if ps == null:
		ps = load(path) as PackedScene
		if ps == null: return {}
		_scenes[path] = ps
	var inst := ps.instantiate() as Node3D
	if inst == null: return {}
	var skel: Skeleton3D = null
	for s in inst.find_children("*", "Skeleton3D", true, false):
		skel = s; break
	var player: AnimationPlayer = null
	for a in inst.find_children("*", "AnimationPlayer", true, false):
		player = a; break
	if skel == null or player == null:
		inst.free(); return {}
	var bones := {}
	for i in skel.get_bone_count():
		bones[_short(skel.get_bone_name(i))] = i
	for n in NEED:
		if not bones.has(n):
			push_warning("RiderAnim: %s has no bone %s" % [path, n])
			inst.free(); return {}
	var anim_name := &""
	for a in player.get_animation_list():
		if a != &"RESET": anim_name = a; break
	if anim_name == &"":
		inst.free(); return {}
	# hidden: only its bones are read (a "with skin" download's mesh is never drawn)
	inst.visible = false
	inst.transform = Transform3D.IDENTITY
	rider.add_child(inst)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(anim_name)
	player.pause()
	var c := {name = path.get_file().get_basename(), inst = inst, skel = skel, player = player, anim = anim_name,
		len = maxf(player.get_animation(anim_name).length, 0.1), b = bones}
	# the skeleton's place under the scene root (Mixamo FBX: usually scaled 0.01 for centimetres)
	var chain := Transform3D.IDENTITY
	var n: Node = skel
	while n != inst and n != null:
		if n is Node3D: chain = (n as Node3D).transform * chain
		n = n.get_parent()
	c.chain = Transform3D(TO_RIDER) * chain
	# rest (T-pose) bases, and the size: the rider's legs / the clip's legs
	var rest := {}
	for k in bones: rest[k] = (c.chain * skel.get_bone_global_rest(bones[k])).basis.orthonormalized()
	c.rest = rest
	_seek(c, 0.0)
	var g := _globals(c)
	var leg := 0.0
	for s in ["Left", "Right"]:
		leg += g[s + "UpLeg"].origin.distance_to(g[s + "Leg"].origin) + g[s + "Leg"].origin.distance_to(g[s + "Foot"].origin)
	c.k = (Rider.L_THIGH + Rider.L_SHIN) * 2.0 / maxf(leg, 1e-3)
	# where the clip stands (its hips over the floor at the start) and how high its ankles sit on a flat foot
	var h0: Vector3 = g["Hips"].origin
	c.root = Vector3(h0.x, 0.0, h0.z)
	var ank := INF
	for s in ["Left", "Right"]:
		ank = minf(ank, (c.chain * skel.get_bone_global_rest(bones[s + "Foot"])).origin.y)
	c.ankle = ank * c.k
	# a T-pose rest has the arms out sideways; otherwise the turns of hands / feet / head can't be trusted
	var arm: Vector3 = (c.chain * skel.get_bone_global_rest(bones["LeftForeArm"])).origin - (c.chain * skel.get_bone_global_rest(bones["LeftArm"])).origin
	c.tpose = absf(arm.normalized().y) < 0.5
	return c


func _seek(c: Dictionary, at: float) -> void:
	(c.player as AnimationPlayer).seek(fmod(at, c.len), true)


func _globals(c: Dictionary) -> Dictionary:
	var out := {}
	var skel: Skeleton3D = c.skel
	for k in c.b:
		out[k] = c.chain * skel.get_bone_global_pose(c.b[k])
	return out


## the clip's turn of a bone from its T-pose, in rider space (rider axes at rest -> now)
static func _delta(c: Dictionary, g: Dictionary, n: String) -> Basis:
	if not c.tpose: return Basis()
	return (g[n] as Transform3D).basis.orthonormalized() * (c.rest[n] as Basis).inverse()


func _pick_next() -> void:
	var idle := -1
	for i in clips.size():
		if str(clips[i].name).to_lower().contains("idle"): idle = i; break
	var nxt := 0
	if clips.size() > 1:
		if cur != idle and idle >= 0: nxt = idle
		else:
			nxt = _rng.randi_range(0, clips.size() - 2)
			if nxt >= cur: nxt += 1
	cur = nxt
	t = 0.0
	var ln: float = clips[cur].len
	_until = maxf(1.0, round(CLIP_SECS / ln)) * ln


## one frame: advance the clip, pose the rider. False when there is nothing to play.
func step(dt: float) -> bool:
	if clips.is_empty(): return false
	if cur < 0: _pick_next()
	t += dt
	if t >= _until and clips.size() > 1:
		_fade_from = _prev_pose
		_fade_t = 0.0
		_pick_next()
	var c: Dictionary = clips[cur]
	_seek(c, t)
	var pose := _retarget(c)
	if _fade_t < 1.0 and not _fade_from.is_empty():
		_fade_t = minf(_fade_t + dt / FADE, 1.0)
		pose = _blend(_fade_from, pose, smoothstep(0.0, 1.0, _fade_t))
	_prev_pose = pose
	rider.pose_points(pose.P, pose.o)
	return true


static func _blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var P := []
	for i in 15: P.append((a.P[i] as Vector3).lerp(b.P[i], w))
	var o := {}
	for k in b.o:
		if a.o.has(k) and b.o[k] is Basis: o[k] = (a.o[k] as Basis).orthonormalized().slerp((b.o[k] as Basis).orthonormalized(), w)
		else: o[k] = b.o[k]
	return {P = P, o = o}


## the clip's pose on the rider's body: directions from the clip, lengths from the rider
func _retarget(c: Dictionary) -> Dictionary:
	var g := _globals(c)
	var k: float = c.k
	var q := func(n: String) -> Vector3: return ((g[n] as Transform3D).origin - c.root) * k
	var dir := func(a: String, b: String) -> Vector3:
		var d: Vector3 = q.call(b) - q.call(a)
		return d.normalized() if d.length_squared() > 1e-10 else Vector3.DOWN
	var sty := rider.style
	var hl: Vector3 = q.call("LeftUpLeg"); var hr: Vector3 = q.call("RightUpLeg")
	var mid := (hl + hr) * 0.5
	var r_h := (hr - hl).normalized()
	var up_t: Vector3 = (q.call("Neck") - mid).normalized()
	var pelvis := mid + up_t * 0.02
	var chest := pelvis + up_t * float(sty.get("torso", 0.46))
	var bc := _delta(c, g, "Spine2")
	var bn := _delta(c, g, "Neck")
	var bh := _delta(c, g, "Head")
	if not c.tpose:   # no usable rest: square the chest / head to the shoulders
		var r_s: Vector3 = (q.call("RightArm") - q.call("LeftArm")).normalized()
		bc = Rider._basis_from(up_t, r_s); bn = bc
		bh = Rider._basis_from(dir.call("Neck", "Head"), r_s)
	var head_p := chest + bn * Vector3(0.05, 0.2 + float(sty.get("neck", 0.0)), 0)
	var P := []
	P.resize(15)
	P[0] = head_p; P[1] = chest; P[2] = pelvis
	var o := {"head": bh}
	for i in 2:
		var s := "Left" if i == 0 else "Right"
		var side := -1.0 if i == 0 else 1.0
		var sh := chest + bc * Vector3(-0.03, -0.04, side * float(sty.get("shoulders", 0.2)))
		var el: Vector3 = sh + dir.call(s + "Arm", s + "ForeArm") * Rider.L_UARM
		var fa: Vector3 = dir.call(s + "ForeArm", s + "Hand")
		var ha := el + fa * Rider.L_FARM
		var hp := pelvis + r_h * side * 0.11 - up_t * 0.02
		var kn: Vector3 = hp + dir.call(s + "UpLeg", s + "Leg") * Rider.L_THIGH
		var ft: Vector3 = kn + dir.call(s + "Leg", s + "Foot") * Rider.L_SHIN
		P[3 + i * 3] = sh; P[4 + i * 3] = el; P[5 + i * 3] = ha
		P[9 + i * 3] = hp; P[10 + i * 3] = kn; P[11 + i * 3] = ft
		# hand: along the forearm, the back of the hand where the clip has it (palms down in the T-pose)
		var back := _delta(c, g, s + "Hand") * Vector3.UP
		back = back - fa * back.dot(fa)
		if back.length_squared() < 1e-6 or not c.tpose: back = Vector3(0, 1, 0) - fa * fa.y
		back = back.normalized()
		o["hand%d" % i] = Basis(fa, back, fa.cross(back))
		# foot: toward the toes, sole down
		var df := _delta(c, g, s + "Foot")
		var toe: Vector3 = dir.call(s + "Foot", s + "ToeBase") if c.b.has(s + "ToeBase") else df * Vector3.RIGHT
		var fup := df * Vector3.UP
		fup = fup - toe * fup.dot(toe)
		if fup.length_squared() < 1e-6: fup = Vector3.UP - toe * toe.y
		fup = fup.normalized()
		o["foot%d" % i] = Basis(toe, fup, toe.cross(fup))
	# on the floor: the lower ankle as high over it as the clip's (its flat-foot ankle height = our 0.08)
	var low := 0 if q.call("LeftFoot").y <= q.call("RightFoot").y else 1
	var clip_y: float = q.call("LeftFoot" if low == 0 else "RightFoot").y - float(c.ankle)
	var lift: float = clip_y + 0.08 - (P[11 + low * 3] as Vector3).y
	for i in 15: P[i] = (P[i] as Vector3) + Vector3(0, lift, 0)
	o["shoe_drop"] = 0.05
	return {P = P, o = o}
