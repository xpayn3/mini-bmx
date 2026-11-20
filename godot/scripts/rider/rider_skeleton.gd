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
var curls := [GloveFingers.RELAXED, GloveFingers.RELAXED]   # each hand's finger curl (Rider sets it, GloveFingers)
var fingers: Array[MeshInstance3D] = []   # the skinned finger meshes (left, right)


## the gloved fingers, skinned to the finger bones (one mesh per hand). Children of this node: a skinned mesh is
## drawn from its own transform x the bone poses, which are in this node's space
func make_fingers(mat: Material) -> void:
	for i in 2:
		var mi := GloveFingers.build(self, i, mat)
		add_child(mi)
		fingers.append(mi)
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
	for i in 2:
		var side := "Left" if i == 0 else "Right"
		var o := i * 3
		var sh: Vector3 = P[3 + o]; var el: Vector3 = P[4 + o]; var ha: Vector3 = P[5 + o]
		var hp: Vector3 = P[9 + o]; var kn: Vector3 = P[10 + o]; var ft: Vector3 = P[11 + o]
		var hand_t: Transform3D = hands[i]
		var shoe_t: Transform3D = shoes[i]
		# arms: the elbow's bend direction (where the forearm folds to) is "forward" at rest (T-pose)
		var bend_a := (ha - sh) - (el - sh).project(ha - sh)   # elbow out of the shoulder -> hand line
		var fold := -bend_a if bend_a.length_squared() > 1e-8 else -fwd
		_put(side + "Shoulder", collar.lerp(sh, 0.15), _aim(side + "Shoulder", sh - collar, up, tor_up))
		_put(side + "UpperArm", sh, _aim(side + "UpperArm", el - sh, fwd, fold))
		_put(side + "LowerArm", el, _aim(side + "LowerArm", ha - el, fwd, fold))
		# hand: the glove's x runs along the forearm, its y is the back of the hand (up at rest, palms down)
		var wrist := ha - hand_t.basis.x.normalized() * 0.07
		_put(side + "Hand", wrist, _aim(side + "Hand", hand_t.basis.x, up, hand_t.basis.y))
		# fingers (GloveFingers): curled round the bar / relaxed, drawn by the skinned finger meshes
		var hand_b := hand_t.basis.orthonormalized()
		for bt in GloveFingers.pose(i, curls[i]):
			var t: Transform3D = bt[1]
			_put(bt[0], hand_t * t.origin, hand_b * t.basis)
		if i < fingers.size():
			var c := TO_RIDER.inverse() * hand_t.origin
			var bx: AABB = fingers[i].custom_aabb
			if not bx.has_point(c - Vector3.ONE) or not bx.has_point(c + Vector3.ONE):
				fingers[i].custom_aabb = AABB(c - Vector3(3, 3, 3), Vector3(6, 6, 6))
		# legs: knees point forward at rest
		var bend_l := (kn - hp) - (kn - hp).project(ft - hp)
		var kf := bend_l if bend_l.length_squared() > 1e-8 else fwd
		_put(side + "UpperLeg", hp, _aim(side + "UpperLeg", kn - hp, fwd, kf))
		_put(side + "LowerLeg", kn, _aim(side + "LowerLeg", ft - kn, fwd, kf))
		# foot: from the ankle toward the toes (the shoe's x), sole down
		var toe_dir := shoe_t.basis.x.normalized()
		_put(side + "Foot", ft, _aim(side + "Foot", toe_dir, up, shoe_t.basis.y))
		_put(side + "Toes", shoe_t.origin + toe_dir * 0.09, _aim(side + "Toes", toe_dir, up, shoe_t.basis.y))
	if _lines: _draw_lines()
	if _probe: _probe_err(P)


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
