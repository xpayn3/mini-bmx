class_name GloveFingers
extends RefCounted

## The rider's fingers: five low-poly gloved fingers per hand, skinned to the humanoid skeleton's finger bones
## (RiderSkeleton: LeftIndexProximal ... RightThumbDistal), one mesh + one draw call per hand.
##
## Everything here is in the hand's space (the glove node, Rider.orient_hand): +X along the forearm toward the
## fingers, +Y the back of the hand, +Z the rider's right. The origin is the grip point: on the bike the bar runs
## along Z through it. `curl` 0 = an open, slightly drooping hand, 1 = the fist wrapped round the bar: at 1 every
## finger's joints lie on a circle round the grip (GRIP_R), the thumb wrapping the other way under it; in between
## each phalanx's angle is blended. ~0.4 = a relaxed hand (standing, crash, animation clips).

const GRIP_R := 0.0305         # finger centre line round the bar (bar radius ~0.016 + a gloved finger)
const KNUCKLE_ANG := 0.96      # where the fingers leave the palm on that circle (rad from +X toward +Y)
const OPEN_ANG := -0.12        # every phalanx's direction with the hand open (a slight droop)
const SIDES := 8               # low poly: octagonal fingers, flat shaded
const RELAXED := 0.4

## [name, z across the hand (+ = toward the thumb), lengths, radii, knuckle angle offset]
const FINGERS := [
	["Index",  0.0345, [0.034, 0.021, 0.018], [0.0146, 0.0141, 0.0136], 0.00],
	["Middle", 0.0115, [0.037, 0.023, 0.019], [0.0150, 0.0145, 0.0139], 0.04],
	["Ring",  -0.0115, [0.035, 0.022, 0.018], [0.0144, 0.0139, 0.0133], 0.00],
	["Little", -0.0335, [0.028, 0.017, 0.015], [0.0130, 0.0125, 0.0120], -0.10],
]
## how early each phalanx follows the curl (exponent on it): the knuckle bends first, the tips last, so a
## half-curled hand is softly bent from the knuckles, not hooked at the fingertips like a claw
const CURL_EXP := [0.7, 1.15, 1.7]
const THUMB_BASE := Vector3(-0.046, 0.010, 0.026)   # z: toward the thumb side
const THUMB_Z := 0.056
const THUMB_START := 2.75      # rad round the grip where the thumb meets it (behind, a little up)
const THUMB_L := [0.029, 0.024]
const THUMB_R := [0.0160, 0.0152, 0.0142]   # metacarpal, proximal, distal
const THUMB_OPEN := -0.5       # the open thumb's direction in its plane


## the side's bone name prefix: glove 0 = left
static func prefix(i: int) -> String:
	return "Left" if i == 0 else "Right"


## every finger bone's transform in hand space for this curl: [[bone, Transform3D], ...] (Y along the bone,
## Z the hand's +Z), parents first. i: 0 left, 1 right
static func pose(i: int, curl: float) -> Array:
	var inner := 1.0 if i == 0 else -1.0     # the thumb side of the hand along +Z
	var out := []
	var pre := prefix(i)
	for f in FINGERS:
		var a0: float = KNUCKLE_ANG + f[4]
		var p := Vector3(cos(a0) * GRIP_R, sin(a0) * GRIP_R, inner * float(f[1]))
		var ang := a0
		var names := ["Proximal", "Intermediate", "Distal"]
		for k in 3:
			var L: float = f[2][k]
			# the grip: the next joint on the circle (a chord), turning down the front of the bar and under it
			var th := 2.0 * asin(clampf(L / (2.0 * GRIP_R), 0.0, 1.0))
			var grip_dir := ang - th * 0.5 - PI * 0.5
			ang -= th
			var d := lerp_angle(OPEN_ANG, grip_dir, pow(clampf(curl, 0.0, 1.0), CURL_EXP[k]))
			out.append([pre + f[0] + names[k], _seg(p, d)])
			p += Vector3(cos(d), sin(d), 0.0) * L
	# thumb: the metacarpal from the heel of the palm to the grip circle, then two phalanges round the other way
	var tb := Vector3(THUMB_BASE.x, THUMB_BASE.y, inner * THUMB_BASE.z)
	var ts := Vector3(cos(THUMB_START) * GRIP_R, sin(THUMB_START) * GRIP_R, inner * THUMB_Z)
	out.append([pre + "ThumbMetacarpal", _frame(tb, (ts - tb).normalized())])
	var p := ts
	var ang := THUMB_START
	var tn := ["ThumbProximal", "ThumbDistal"]
	for k in 2:
		var L: float = THUMB_L[k]
		var th := 2.0 * asin(clampf(L / (2.0 * (GRIP_R + 0.002)), 0.0, 1.0))
		var grip_dir := ang + th * 0.5 + PI * 0.5
		ang += th
		var d := lerp_angle(THUMB_OPEN, grip_dir, pow(clampf(curl, 0.0, 1.0), CURL_EXP[k + 1]))
		out.append([pre + tn[k], _seg(p, d)])
		p += Vector3(cos(d), sin(d), 0.0) * L
	return out


## a phalanx at p pointing at angle a in the hand's XY plane (bending about Z)
static func _seg(p: Vector3, a: float) -> Transform3D:
	var y := Vector3(cos(a), sin(a), 0.0)
	return Transform3D(Basis(Vector3(y.y, -y.x, 0.0), y, Vector3(0, 0, 1)), p)

static func _frame(p: Vector3, y: Vector3) -> Transform3D:
	var x := y.cross(Vector3(0, 0, 1)).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), p)


## the skinned mesh of one hand's fingers (child of the skeleton, so it is drawn wherever the bones are)
static func build(skel: Skeleton3D, i: int, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var skin := Skin.new()
	var pre := prefix(i)
	var bind := 0
	for f in FINGERS:
		var names := ["Proximal", "Intermediate", "Distal"]
		for k in 3:
			skin.add_bind(skel.find_bone(pre + f[0] + names[k]), Transform3D.IDENTITY)
			var r0: float = f[3][k]
			var r1: float = r0 * 0.93
			_phalanx(st, bind, f[2][k], r0, r1, k == 2)
			bind += 1
	var tl := [0.036, THUMB_L[0], THUMB_L[1]]
	var tnames := ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal"]
	for k in 3:
		skin.add_bind(skel.find_bone(pre + tnames[k]), Transform3D.IDENTITY)
		_phalanx(st, bind, tl[k], THUMB_R[k], THUMB_R[k] * 0.93, k == 2)
		bind += 1
	var mi := MeshInstance3D.new()
	mi.name = pre + "Fingers"
	mi.mesh = st.commit()
	mi.skin = skin
	mi.skeleton = NodePath("..")
	mi.custom_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))   # the bones move it anywhere (see Rider.pose_fingers)
	return mi


## one phalanx along +Y from 0 to L: a flat-shaded hexagonal prism, a little wider across the hand than deep,
## running back into the joint behind it (no gaps when bent); the last one ends in a low-poly fingertip
static func _phalanx(st: SurfaceTool, bone: int, L: float, r0: float, r1: float, tip: bool) -> void:
	var y0 := -r0 * 0.75
	var y1 := L - r1 * 0.1
	_mid = (y0 + L) * 0.5
	var ring := func(y: float, r: float) -> Array:
		var pts := []
		for s in SIDES:
			var a := TAU * (s + 0.5) / SIDES
			pts.append(Vector3(cos(a) * r * 0.92, y, sin(a) * r))
		return pts
	var A: Array = ring.call(y0, r0 * 0.92)
	var B: Array = ring.call(y1, r1)
	for s in SIDES:
		var s2 := (s + 1) % SIDES
		_quad(st, bone, A[s], A[s2], B[s2], B[s])
	# back cap (inside the joint)
	for s in range(1, SIDES - 1):
		_tri(st, bone, A[0], A[s + 1], A[s])
	if tip:
		# fingertip: a short bevelled ring, then a flat pad
		var C: Array = ring.call(L + r1 * 0.55, r1 * 0.62)
		for s in SIDES:
			var s2 := (s + 1) % SIDES
			_quad(st, bone, B[s], B[s2], C[s2], C[s])
		var apex := Vector3(0, L + r1 * 0.8, 0)
		for s in SIDES:
			_tri(st, bone, C[s], C[(s + 1) % SIDES], apex)
	else:
		# a rounded knuckle running into the next phalanx (no step at the joint when it bends)
		var C: Array = ring.call(L + r1 * 0.5, r1 * 0.72)
		for s in SIDES:
			var s2 := (s + 1) % SIDES
			_quad(st, bone, B[s], B[s2], C[s2], C[s])
		for s in range(1, SIDES - 1):
			_tri(st, bone, C[0], C[s], C[s + 1])


static var _mid := 0.0   # the phalanx's middle on its axis: every face points away from it (convex shape)

static func _quad(st: SurfaceTool, bone: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, bone, a, b, c)
	_tri(st, bone, a, c, d)

static func _tri(st: SurfaceTool, bone: int, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot draws clockwise triangles' fronts: (c - a) x (b - a) is then the outward normal; flip to face out
	var n := (c - a).cross(b - a).normalized()
	var ctr := (a + b + c) / 3.0
	if n.dot(ctr - Vector3(0, _mid, 0)) < 0.0:
		var t := b; b = c; c = t
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
		st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		st.add_vertex(v)
