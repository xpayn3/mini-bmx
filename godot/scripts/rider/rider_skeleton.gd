class_name RiderSkeleton
extends Skeleton3D

## The rider's skeleton: Godot's standard humanoid (SkeletonProfileHumanoid: Root, Hips, Spine, Chest, UpperChest,
## Neck, Head, Left/RightShoulder, ...UpperArm, ...LowerArm, ...Hand + fingers, ...UpperLeg, ...LowerLeg, ...Foot,
## ...Toes, eyes, jaw). Same names, parents and rest axes as the profile, so BoneAttachment3D, retargeted
## animations and imported humanoid models all work with it.
##
## The rider is still drawn by its procedural parts; every frame (riding, ragdoll, playing a clip) the bones are
## set from where those parts are (`follow`), so the skeleton always matches what is on screen. The finger bones
## are posed by GloveFingers (curl per hand, `curls`) and drive the skinned finger meshes (`fingers`); eyes and
## jaw keep their rest pose under the head.
##
## The profile faces +Z with its left at +X; the rider faces +X with its right at +Z, so this node is turned a
## quarter about Y (`TO_RIDER`) and everything below works in rider space.

const TO_RIDER := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   # profile axes -> rider axes
const SCALE := 1.17   # the profile is 1.5 m tall at the eyes with 0.75 m legs; ours are 0.88 m

## body bones that follow the rider (the rest keep their rest pose under these); [bone, child point key]
const BODY := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

var _rest_g := {}     # bone -> global rest basis in rider space (orthonormal)
var fin := [null, null]       # per hand: the five fingers' own curl [thumb, index, middle, ring, little] (null = all at `curls`)
var lever := [0.0, 0.0]       # per hand: index + middle resting on the brake lever (0..1)
var pull := [0.0, 0.0]        # per hand: that lever squeezed (0..1)
var curls := [GloveFingers.RELAXED, GloveFingers.RELAXED]   # each hand's finger curl (Rider sets it, GloveFingers)
var fingers: Array[MeshInstance3D] = []   # the skinned finger meshes (left, right)


## the gloved fingers, skinned to the finger bones (one mesh per hand). Children of this node: a skinned mesh is
## drawn from its own transform x the bone poses, which are in this node's space
func make_fingers(mat: Material) -> void:
	for i in 2:
		var mi := GloveFingers.build(self, i, mat)
		add_child(mi)
		fingers.append(mi)
## The neck, skinned the way an imported character's is (2026-11-28, user: "do a proper neck", "I will later use a
## real humanoid"): a tube authored in this skeleton's REST pose round the Neck bone, binds = the inverse of each
## bone's rest (what a glTF / FBX skin carries), weights Neck at the collar easing to Head up the neck. So the head
## turning / nodding / rolling bends and twists the neck along its length, as on a skinned humanoid; nothing poses
## the mesh itself, the bones do (follow). An imported body mesh skinned to these bone names behaves the same way.
const NECK_SEG := 18          # round
const NECK_RINGS := 9         # along
const NECK_DOWN := 0.35       # how far it starts below the Neck bone (x the rest neck length: inside the collar)
const NECK_UP := 0.25         # how far it reaches past the Head bone's origin (inside the helmet / skull)
const NECK_W0 := 0.15         # neck parameter where the Head bone starts taking over (0 = Neck bone, 1 = Head bone)
const NECK_W1 := 0.95         # ... and where it has it all
func make_neck(mat: Material, r_base: float, r_top: float) -> MeshInstance3D:
	var ni := bone("Neck")
	var hi := bone("Head")
	var nr := get_bone_global_rest(ni)
	var hr := get_bone_global_rest(hi)
	var axis := hr.origin - nr.origin
	var lr := maxf(axis.length(), 0.02)
	var d := axis / lr
	var side := nr.basis.x.normalized()   # profile: +X = the character's left
	side = (side - d * side.dot(d)).normalized()
	var front := side.cross(d).normalized()
	if front.dot(nr.basis.z) < 0.0: front = -front
	var st := SurfaceTool.new()
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)   # rest shape for the mud / blood passes (grime_pin 2)
	for j in NECK_RINGS:
		var t := lerpf(-NECK_DOWN, 1.0 + NECK_UP, float(j) / (NECK_RINGS - 1))
		var c := nr.origin + d * (t * lr)
		var r := lerpf(r_base, r_top, clampf(t, 0.0, 1.0))
		var wh := smoothstep(NECK_W0, NECK_W1, t)
		for s in NECK_SEG + 1:
			var a := TAU * float(s) / NECK_SEG
			var n := side * cos(a) + front * sin(a)
			var p := c + side * (cos(a) * r * 1.06) + front * (sin(a) * r * 0.94)   # a little wider than deep
			st.set_normal(n)
			st.set_uv(Vector2(float(s) / NECK_SEG, float(j) / (NECK_RINGS - 1)))
			st.set_custom(0, Color(p.x - nr.origin.x, p.y - nr.origin.y, p.z - nr.origin.z))
			st.set_bones(PackedInt32Array([0, 1, 0, 0]))
			st.set_weights(PackedFloat32Array([1.0 - wh, wh, 0.0, 0.0]))
			st.add_vertex(p)
	for j in NECK_RINGS - 1:
		for s in NECK_SEG:
			var a0 := j * (NECK_SEG + 1) + s
			var b0 := a0 + NECK_SEG + 1
			st.add_index(a0); st.add_index(b0); st.add_index(a0 + 1)
			st.add_index(a0 + 1); st.add_index(b0); st.add_index(b0 + 1)
	var mesh := st.commit(null, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var skin := Skin.new()
	skin.add_bind(ni, nr.affine_inverse())
	skin.add_bind(hi, hr.affine_inverse())
	var mi := MeshInstance3D.new()
	mi.name = "Neck"
	mi.mesh = mesh
	mi.material_override = mat
	if Env.s("BMX_NECK_SHOW") != "":   # tests: the neck in plain magenta, drawn over everything, to see where it is
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(1, 0, 1)
		if Env.s("BMX_NECK_SHOW") == "xray":
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; dm.no_depth_test = true; dm.render_priority = 10
		mi.material_override = dm
	mi.skin = skin
	mi.skeleton = NodePath("..")
	mi.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))   # the bones move it anywhere
	add_child(mi)
	return mi


## keep the skinned parts' culling boxes round the body (in a crash the rider node sits at the world origin)
func _keep_box(mi: MeshInstance3D, at_rider: Vector3) -> void:
	var c := TO_RIDER.inverse() * at_rider
	var bx := mi.custom_aabb
	if not bx.has_point(c - Vector3.ONE) or not bx.has_point(c + Vector3.ONE):
		mi.custom_aabb = AABB(c - Vector3(3, 3, 3), Vector3(6, 6, 6))
var neck: MeshInstance3D = null
var _idx := {}        # bone name -> index


func _init() -> void:
	name = "Skeleton"
	basis = TO_RIDER
	var prof := SkeletonProfileHumanoid.new()
	for i in prof.bone_size:
		add_bone(prof.get_bone_name(i))
	for i in prof.bone_size:
		var par := prof.get_bone_parent(i)
		if par != &"": set_bone_parent(i, find_bone(par))
		var r := prof.get_reference_pose(i)
		r.origin *= SCALE
		set_bone_rest(i, r)
	reset_bone_poses()
	for i in get_bone_count():
		_idx[get_bone_name(i)] = i
	for b in BODY:
		_rest_g[b] = TO_RIDER * get_bone_global_rest(_idx[b]).basis.orthonormalized()
	if Env.s("BMX_SKEL_DRAW") != "": _make_lines()


# ---- tests: BMX_SKEL_DRAW=1 draws every bone as a line to its parent + its axes (x red, y green, z blue), on top

var _lines: MeshInstance3D
func _make_lines() -> void:
	_lines = MeshInstance3D.new()
	_lines.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.vertex_color_use_as_albedo = true
	m.render_priority = 10
	_lines.material_override = m
	add_child(_lines)

func _draw_lines() -> void:
	var im := _lines.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in get_bone_count():
		var g := get_bone_global_pose(i)
		var par := get_bone_parent(i)
		if par >= 0:
			im.surface_set_color(Color(1, 1, 0.2))
			im.surface_add_vertex(get_bone_global_pose(par).origin); im.surface_add_vertex(g.origin)
		for a in 3:
			im.surface_set_color([Color.RED, Color.GREEN, Color.BLUE][a])
			im.surface_add_vertex(g.origin); im.surface_add_vertex(g.origin + g.basis[a].normalized() * 0.05)
	im.surface_end()


func bone(n: String) -> int:
	return _idx.get(n, -1)

## a bone's transform in the rider's space (where its parts are drawn)
func bone_rider(n: String) -> Transform3D:
	return transform * get_bone_global_pose(_idx[n])


## a basis whose bone axis (y) points along `d` and which is otherwise the rest pose swung there (shortest arc),
## then twisted about `d` so that the rest axis `rest_ref` (rider space, at rest) points as close to `ref` as it can
func _aim(b: String, d: Vector3, rest_ref: Vector3, ref: Vector3) -> Basis:
	var r: Basis = _rest_g[b]
	if d.length_squared() < 1e-10: return r
	d = d.normalized()
	var q := Quaternion(r.y.normalized(), d) if r.y.normalized().dot(d) > -0.9999 else Quaternion(r.x.normalized(), PI)
	var s := Basis(q) * r
	if ref.length_squared() > 1e-10:
		var a := Basis(q) * rest_ref
		a -= d * a.dot(d)
		var t := ref - d * ref.dot(d)
		if a.length_squared() > 1e-8 and t.length_squared() > 1e-8:
			s = Basis(d, a.normalized().signed_angle_to(t.normalized(), d)) * s
	return s


func _put(b: String, at: Vector3, bas: Basis) -> void:
	# rider space -> this node's space (the quarter turn), then into the skeleton
	set_bone_global_pose(_idx[b], Transform3D(TO_RIDER.inverse() * bas, TO_RIDER.inverse() * at))


## The twist reference of an arm / leg (k: 0/1 arms, 2/3 legs) = which way its elbow / knee points. A bent limb says
## so itself; nearly straight it doesn't (the bend vector shrinks to noise: in a crash the upper arm rolled 204 deg in
## one frame, BMX_SKEL_AUDIT), so the last frame's is carried over there, re-squared to the limb's line, and it
## blends to the measured one as the limb bends (bend share of the limb 3 .. 15 %). BMX_OLD_SKELTWIST=1 = before.
static var _OLD_TWIST := Env.raw("BMX_OLD_SKELTWIST") != ""
var _fold_prev: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
func _carry_fold(k: int, bend: Vector3, seg_len: float, line: Vector3, fallback: Vector3) -> Vector3:
	if _OLD_TWIST:
		return bend if bend.length_squared() > 1e-8 else fallback
	var ln := line.normalized() if line.length_squared() > 1e-10 else Vector3.UP
	var prev: Vector3 = _fold_prev[k]
	prev = prev - ln * prev.dot(ln)
	if prev.length_squared() < 1e-8:
		prev = fallback - ln * fallback.dot(ln)
	var out := prev.normalized() if prev.length_squared() > 1e-8 else bend
	# a knee / elbow only folds one way: a bend reading the other way is the limb a hair past straight (a ragdoll
	# overextended): keep the side it had, never roll the bone half a turn for it
	if out.length_squared() > 1e-8 and bend.dot(out) < 0.0: bend = -bend
	var s := smoothstep(0.03, 0.15, bend.length() / maxf(seg_len, 1e-4))
	if s > 0.0 and bend.length_squared() > 1e-10:
		out = out.slerp(bend.normalized(), s) if out.length_squared() > 1e-8 and out.dot(bend.normalized()) > -0.999 else bend.normalized()
	if out.length_squared() < 1e-8: out = fallback
	_fold_prev[k] = out
	return out


## pose the bones from the rider's parts. P = the 15 joint points (Ragdoll order, rider space), spine = the 5
## spine bone transforms (Rider.spine_skel), head / hands / shoes = those parts' transforms (rider space)
func follow(P: Array, spine: Array, head_t: Transform3D, hands: Array, shoes: Array) -> void:
	var fwd := Vector3(1, 0, 0); var up := Vector3(0, 1, 0)
	var pe: Vector3 = P[2]
	var hip_r: Vector3 = P[12] - P[9]
	var sh_r: Vector3 = P[6] - P[3]
	var hips_mid: Vector3 = (P[9] + P[12]) * 0.5
	var tor_up: Vector3 = (P[1] - pe)
	# hips: up the torso, facing forward (the hip line gives sideways)
	var hb := _aim("Hips", tor_up, Vector3(0, 0, 1), hip_r)
	_put("Hips", hips_mid, hb)
	# spine: along the bent torso (the skinned spine's bones at 1/4, 1/2, 3/4), neck from the collar
	# (a point up the torso's axis, t 0 hips .. 1 collar, blended between bones like the skinned mesh)
	var spine_at := func(t: float) -> Vector3:
		var u := clampf(t, 0.0, 1.0) * (spine.size() - 1)
		var k := mini(int(u), spine.size() - 2)
		var m := Vector3(0, t - 0.5, 0)
		return ((spine[k] as Transform3D) * m).lerp((spine[k + 1] as Transform3D) * m, u - k)
	var s1: Vector3 = spine_at.call(0.3)
	var s2: Vector3 = spine_at.call(0.6)
	var s3: Vector3 = spine_at.call(0.85)
	var collar: Vector3 = (spine[spine.size() - 1] as Transform3D) * Vector3(0, 0.5, 0)
	var head_base: Vector3 = head_t * Rider.NECK_TOP
	_put("Spine", s1, _aim("Spine", s2 - s1, Vector3(0, 0, 1), sh_r.lerp(hip_r, 0.6)))
	_put("Chest", s2, _aim("Chest", s3 - s2, Vector3(0, 0, 1), sh_r.lerp(hip_r, 0.3)))
	_put("UpperChest", s3, _aim("UpperChest", collar - s3, Vector3(0, 0, 1), sh_r))
	_put("Neck", collar, _aim("Neck", head_base - collar, Vector3(1, 0, 0), head_t.basis.x))
	_put("Head", head_base, _aim("Head", head_t.basis.y, Vector3(1, 0, 0), head_t.basis.x))
	if neck: _keep_box(neck, collar)
	for i in 2:
		var side := "Left" if i == 0 else "Right"
		var o := i * 3
		var sh: Vector3 = P[3 + o]; var el: Vector3 = P[4 + o]; var ha: Vector3 = P[5 + o]
		var hp: Vector3 = P[9 + o]; var kn: Vector3 = P[10 + o]; var ft: Vector3 = P[11 + o]
		var hand_t: Transform3D = hands[i]
		var shoe_t: Transform3D = shoes[i]
		# arms: the elbow's bend direction (where the forearm folds to) is "forward" at rest (T-pose)
		# (elbow out of the shoulder -> hand line. It was (ha - sh) - ..., a vector ALONG that line: the same twist for the
		# forearm, but the upper arm bone rolled half a turn about its own axis against it)
		var bend_a := (el - sh) - (el - sh).project(ha - sh)
		var fold := _carry_fold(i, -bend_a, (el - sh).length(), ha - sh, -fwd)
		_put(side + "Shoulder", collar.lerp(sh, 0.15), _aim(side + "Shoulder", sh - collar, up, tor_up))
		_put(side + "UpperArm", sh, _aim(side + "UpperArm", el - sh, fwd, fold))
		_put(side + "LowerArm", el, _aim(side + "LowerArm", ha - el, fwd, fold))
		# hand: the glove's x runs along the forearm, its y is the back of the hand (up at rest, palms down)
		var wrist := ha - hand_t.basis.x.normalized() * 0.07
		_put(side + "Hand", wrist, _aim(side + "Hand", hand_t.basis.x, up, hand_t.basis.y))
		# fingers (GloveFingers): curled round the bar / relaxed, drawn by the skinned finger meshes
		var hand_b := hand_t.basis.orthonormalized()
		for bt in GloveFingers.pose(i, curls[i], fin[i], lever[i], pull[i]):
			var t: Transform3D = bt[1]
			_put(bt[0], hand_t * t.origin, hand_b * t.basis)
		if i < fingers.size():
			var c := TO_RIDER.inverse() * hand_t.origin
			var bx: AABB = fingers[i].custom_aabb
			if not bx.has_point(c - Vector3.ONE) or not bx.has_point(c + Vector3.ONE):
				fingers[i].custom_aabb = AABB(c - Vector3(3, 3, 3), Vector3(6, 6, 6))
		# legs: knees point forward at rest
		var bend_l := (kn - hp) - (kn - hp).project(ft - hp)
		var kf := _carry_fold(2 + i, bend_l, (kn - hp).length(), ft - hp, fwd)
		_put(side + "UpperLeg", hp, _aim(side + "UpperLeg", kn - hp, fwd, kf))
		_put(side + "LowerLeg", kn, _aim(side + "LowerLeg", ft - kn, fwd, kf))
		# foot: from the ankle toward the toes (the shoe's x), sole down
		var toe_dir := shoe_t.basis.x.normalized()
		_put(side + "Foot", ft, _aim(side + "Foot", toe_dir, up, shoe_t.basis.y))
		_put(side + "Toes", shoe_t.origin + toe_dir * 0.09, _aim(side + "Toes", toe_dir, up, shoe_t.basis.y))
	if _lines: _draw_lines()
	if _probe: _probe_err(P)
	if _audit: _audit_step(P, collar, head_base, hands)
	if _audit and _au_n % 120 == 1:
		var nr := get_bone_global_rest(_idx["Neck"]); var hr := get_bone_global_rest(_idx["Head"])
		print("NECKLEN rest=%.3f posed=%.3f neck_rest_basis=%s" % [nr.origin.distance_to(hr.origin), collar.distance_to(head_base), nr.basis])


# ---- tests: BMX_SKEL_AUDIT=1: is this skeleton fit to drive a real skinned humanoid? Every frame, for every body bone:
# where it sits vs the drawn joint (m), whether its y points at the next joint (deg), any scale / skew in its global
# pose (an imported mesh would stretch), knees / elbows bending the anatomical way (their rest forward vs the fold),
# and how far the bones jump frame to frame (deg / m). Worst of each printed every 2 s (SKELAUDIT) + at the end.
var _audit := Env.s("BMX_SKEL_AUDIT") != ""
var _au := {}
var _au_prev := {}
var _au_n := 0
func _au_max(k: String, v: float, why: String) -> void:
	if v > float(_au.get(k, [-1.0])[0]): _au[k] = [v, why]
func _audit_step(P: Array, collar: Vector3, head_base: Vector3, hands: Array) -> void:
	var at := {Hips = (P[9] + P[12]) * 0.5, Neck = collar, Head = head_base,
		LeftUpperArm = P[3], LeftLowerArm = P[4], RightUpperArm = P[6], RightLowerArm = P[7],
		LeftUpperLeg = P[9], LeftLowerLeg = P[10], LeftFoot = P[11], RightUpperLeg = P[12], RightLowerLeg = P[13], RightFoot = P[14]}
	for b in at:
		_au_max("pos_m", bone_rider(b).origin.distance_to(at[b]), b)
	var aim := {LeftUpperArm = P[4], LeftLowerArm = P[5], RightUpperArm = P[7], RightLowerArm = P[8],
		LeftUpperLeg = P[10], LeftLowerLeg = P[11], RightUpperLeg = P[13], RightLowerLeg = P[14], Neck = head_base}
	for b in aim:
		var t := bone_rider(b)
		var d: Vector3 = (aim[b] as Vector3) - t.origin
		if d.length() > 0.01: _au_max("aim_deg", rad_to_deg(t.basis.y.normalized().angle_to(d)), b)
	for b in BODY:
		var bs := get_bone_global_pose(_idx[b]).basis
		var sc := bs.get_scale()
		_au_max("scale", maxf(absf(sc.x - 1.0), maxf(absf(sc.y - 1.0), absf(sc.z - 1.0))), b)
		var sk := maxf(absf(bs.x.normalized().dot(bs.y.normalized())), maxf(absf(bs.y.normalized().dot(bs.z.normalized())), absf(bs.x.normalized().dot(bs.z.normalized()))))
		_au_max("skew", sk, b)
		var g := bone_rider(b)
		if _au_prev.has(b):
			var pg: Transform3D = _au_prev[b]
			var rel: Basis = pg.basis.orthonormalized().inverse() * g.basis.orthonormalized()
			var jd := rad_to_deg(rel.get_rotation_quaternion().get_angle())
			_au_max("jump_deg", jd, b)
			if jd > 45.0 and _au_n > 10:   # (the first frames: no pose yet)
				print("SKELJUMP frame=%d bone=%s deg=%.1f aim_change_deg=%.1f folds=%s y=%s" % [_au_n, b, jd,
					rad_to_deg(pg.basis.y.normalized().angle_to(g.basis.y.normalized())), _fold_prev, g.basis.y.normalized()])
		_au_prev[b] = g
	# a knee folds the shin BACK, toward the bone's rest -z after the quarter turn = rider -x at rest; check the fold
	# direction against the bone's own "forward" (rider space): knees' fold should be along -forward, elbows' along +forward
	for side in ["Left", "Right"]:
		var o := 0 if side == "Left" else 3
		var th := bone_rider(side + "UpperLeg")
		var fold: Vector3 = (P[11 + o] as Vector3) - (P[10 + o] as Vector3)
		fold -= th.basis.y.normalized() * fold.dot(th.basis.y.normalized())
		if fold.length() > 0.02:
			var kf: Vector3 = th.basis.orthonormalized() * ((_rest_g[side + "UpperLeg"] as Basis).inverse() * Vector3(1, 0, 0))   # the bone's rest "forward", posed
			_au_max("knee_wrong_way", 1.0 if fold.normalized().dot(kf.normalized()) > 0.3 else 0.0, side)
	_au_n += 1
	if _au_n % 120 == 0 or _au_n == 2:
		var s := "SKELAUDIT frames=%d" % _au_n
		for k in ["pos_m", "aim_deg", "scale", "skew", "jump_deg", "knee_wrong_way"]:
			if _au.has(k): s += " %s=%.4f(%s)" % [k, _au[k][0], _au[k][1]]
		print(s)
		_au.clear()


# ---- tests: BMX_SKEL_PROBE=1 checks the bones sit on the rider's joints (SKEL lines, 1 x / s)
var _probe := Env.s("BMX_SKEL_PROBE") != ""
var _probe_t := 0
func _probe_err(P: Array) -> void:
	_probe_t += 1
	if _probe_t % 60 != 0: return
	var pairs := [["LeftUpperLeg", 9], ["LeftLowerLeg", 10], ["LeftFoot", 11], ["RightLowerLeg", 13],
		["LeftUpperArm", 3], ["LeftLowerArm", 4], ["RightLowerArm", 7]]
	var worst := 0.0; var wn := ""
	for pr in pairs:
		var e: float = bone_rider(pr[0]).origin.distance_to(P[pr[1]])
		if e > worst: worst = e; wn = pr[0]
	# a bone's y runs to its child joint: the shin's y toward the ankle
	var ll := bone_rider("LeftLowerLeg")
	var aim_err := rad_to_deg(ll.basis.y.normalized().angle_to((P[11] as Vector3) - (P[10] as Vector3)))
	print("SKEL worst_m=%.4f (%s) shin_aim_deg=%.2f hips=%s head=%s" % [worst, wn, aim_err,
		bone_rider("Hips").origin.snapped(Vector3.ONE * 0.01), bone_rider("Head").origin.snapped(Vector3.ONE * 0.01)])
