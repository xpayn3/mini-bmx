class_name GetUpAnim
extends RefCounted

## Getting up after a crash: from wherever the ragdoll came to rest, the rider pushes up onto hands and knees,
## brings one foot forward, and stands up (~1.6 s). Game then puts them back on the bike (Game.get_up) and blends
## the standing body into the riding pose.
##
## Keyframes are body targets in a frame on the ground under the pelvis, facing the way the body lay (head end):
## pelvis, chest, head, hands, feet + knee / elbow poles. In between they are blended and the limbs solved with the
## rider's own IK (Rider.limb_ik: lengths kept, joint limits), so nothing stretches. Heights are over the ground under
## each point (Terrain.top_height), so hands, knees and feet stay on the ground on a slope. The first key is the
## ragdoll's own pose, so it starts exactly where the body lies.

const KEYS := [   # time (s), key
	[0.0, "rag"], [0.5, "kneel"], [1.05, "lunge"], [1.6, "stand"],
]
const DONE := 1.75   # the last key holds a moment

## frame space: x forward, y up (over the ground), z right; i 0 = left, 1 = right
const POSES := {
	"kneel": {pelvis = Vector3(-0.05, 0.56, 0), chest = Vector3(0.38, 0.62, 0), head = Vector3(0.6, 0.62, 0),
		hand = [Vector3(0.42, 0.05, -0.22), Vector3(0.42, 0.05, 0.22)],
		foot = [Vector3(-0.48, 0.07, -0.12), Vector3(-0.48, 0.07, 0.12)],
		knee_pole = [Vector3(1, -1, 0), Vector3(1, -1, 0)], elbow_pole = [Vector3(-1, 0, -0.4), Vector3(-1, 0, 0.4)],
		foot_x = [Vector3(-1, 0, 0), Vector3(-1, 0, 0)], foot_y = [Vector3(0, -1, 0), Vector3(0, -1, 0)]},
	"lunge": {pelvis = Vector3(0.0, 0.6, 0), chest = Vector3(0.24, 1.0, 0), head = Vector3(0.36, 1.18, 0),
		hand = [Vector3(0.3, 0.6, -0.16), Vector3(0.38, 0.58, 0.2)],
		foot = [Vector3(-0.42, 0.07, -0.12), Vector3(0.42, 0.08, 0.14)],
		knee_pole = [Vector3(1, -1, 0), Vector3(1, 0.4, 0)], elbow_pole = [Vector3(-1, 0, -0.4), Vector3(-1, 0, 0.4)],
		foot_x = [Vector3(-1, -0.5, 0), Vector3(1, 0, 0)], foot_y = [Vector3(0, -1, 0), Vector3(0, 1, 0)]},
	"stand": {pelvis = Vector3(0.0, 0.96, 0), chest = Vector3(0.03, 1.41, 0), head = Vector3(0.07, 1.61, 0),
		hand = [Vector3(0.03, 0.85, -0.27), Vector3(0.03, 0.85, 0.27)],
		foot = [Vector3(0.0, 0.08, -0.13), Vector3(0.02, 0.08, 0.13)],
		knee_pole = [Vector3(1, 0, -0.1), Vector3(1, 0, 0.1)], elbow_pole = [Vector3(-1, 0, -0.25), Vector3(-1, 0, 0.25)],
		foot_x = [Vector3(1, 0, -0.1), Vector3(1, 0, 0.1)], foot_y = [Vector3(0, 1, 0), Vector3(0, 1, 0)]},
}

var rider: Rider
var terrain
var t := 0.0
var frame := Transform3D()   # frame space (y = 0 here) -> world
var _rag := {}               # the ragdoll's pose as a key (frame space, heights over the ground)
var last_world: Array = []   # the 15 joints drawn last (world space): the standing pose when it finishes


## P = the ragdoll's points (world; the rider node sits at the origin during a crash)
func _init(r: Rider, terr, P: Array) -> void:
	rider = r
	terrain = terr
	var pe: Vector3 = P[Ragdoll.PELVIS]
	var head_dir: Vector3 = (P[Ragdoll.HEAD] as Vector3) - pe
	head_dir.y = 0.0
	if head_dir.length_squared() < 1e-4: head_dir = Vector3(1, 0, 0)
	var f := head_dir.normalized()
	var right := f.cross(Vector3.UP)   # x forward, z right: z = x cross y
	frame = Transform3D(Basis(f, Vector3.UP, right), Vector3(pe.x, 0.0, pe.z))
	var to_f := func(w: Vector3) -> Vector3:
		var l: Vector3 = frame.affine_inverse() * w
		return Vector3(l.x, w.y - _ground(w), l.z)
	var key := {pelvis = to_f.call(P[Ragdoll.PELVIS]), chest = to_f.call(P[Ragdoll.CHEST]), head = to_f.call(P[Ragdoll.HEAD]),
		hand = [to_f.call(P[Ragdoll.HA_L]), to_f.call(P[Ragdoll.HA_R])],
		foot = [to_f.call(P[Ragdoll.FT_L]), to_f.call(P[Ragdoll.FT_R])], knee_pole = [], elbow_pole = [], foot_x = [], foot_y = []}
	var inv := frame.basis.inverse()
	for i in 2:
		var o := i * 3
		var hip: Vector3 = P[9 + o]; var kn: Vector3 = P[10 + o]; var ft: Vector3 = P[11 + o]
		var sh: Vector3 = P[3 + o]; var el: Vector3 = P[4 + o]; var ha: Vector3 = P[5 + o]
		key.knee_pole.append(inv * (kn - (hip + ft) * 0.5))
		key.elbow_pole.append(inv * (el - (sh + ha) * 0.5))
		var sb: Basis = rider.shoe[i].basis
		key.foot_x.append(inv * sb.x.normalized())
		key.foot_y.append(inv * sb.y.normalized())
	_rag = key


func _ground(w: Vector3) -> float:
	return terrain.top_height(w.x, w.z) if terrain else 0.0

func _to_world(l: Vector3) -> Vector3:
	var w: Vector3 = frame * Vector3(l.x, 0.0, l.z)
	w.y = _ground(w) + l.y
	return w

func _key(n: String) -> Dictionary:
	return _rag if n == "rag" else POSES[n]

static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for k in a:
		if a[k] is Array:
			var arr := []
			for i in 2: arr.append((a[k][i] as Vector3).lerp(b[k][i], w))
			out[k] = arr
		else:
			out[k] = (a[k] as Vector3).lerp(b[k], w)
	return out


func finished() -> bool:
	return t >= DONE


## advance and draw; true while it's still going
func step(dt: float) -> bool:
	t += dt
	var k := KEYS.size() - 2
	for j in KEYS.size() - 1:
		if t < KEYS[j + 1][0]: k = j; break
	var t0: float = KEYS[k][0]; var t1: float = KEYS[k + 1][0]
	var w := smoothstep(0.0, 1.0, clampf((t - t0) / (t1 - t0), 0.0, 1.0))
	var p := _mix(_key(KEYS[k][1]), _key(KEYS[k + 1][1]), w)
	_draw(p)
	return not finished()


func _draw(p: Dictionary) -> void:
	var fb := frame.basis
	var pelvis := _to_world(p.pelvis)
	var chest := _to_world(p.chest)
	var head := _to_world(p.head)
	var right := fb.z
	var bb := Rider._basis_from(chest - pelvis, right)
	var P := []
	P.resize(15)
	P[0] = head; P[1] = chest; P[2] = pelvis
	var o := {}
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hip := pelvis + bb * Vector3(0, -0.02, side * 0.11)
		var sh := chest + bb * Vector3(-0.03, -0.04, side * float(rider.style.get("shoulders", 0.2)))
		var foot := _to_world(p.foot[i])
		var hand := _to_world(p.hand[i])
		var kp: Vector3 = fb * (p.knee_pole[i] as Vector3)
		var ep: Vector3 = fb * (p.elbow_pole[i] as Vector3)
		var leg := Rider.limb_ik(hip, foot, Rider.L_THIGH, Rider.L_SHIN, kp.normalized() if kp.length_squared() > 1e-6 else fb.x,
			Vector3.UP, Rider.KNEE_MIN, Rider.KNEE_MAX, Vector3.ZERO, PI)
		var arm := Rider.limb_ik(sh, hand, Rider.L_UARM, Rider.L_FARM, ep.normalized() if ep.length_squared() > 1e-6 else -fb.x,
			Vector3(0, -0.5, side), Rider.ELBOW_MIN, Rider.ELBOW_MAX, Vector3.ZERO, PI)
		P[3 + i * 3] = sh; P[4 + i * 3] = arm[0]; P[5 + i * 3] = arm[1]
		P[9 + i * 3] = hip; P[10 + i * 3] = leg[0]; P[11 + i * 3] = leg[1]
		var fx: Vector3 = fb * (p.foot_x[i] as Vector3)
		var fy: Vector3 = fb * (p.foot_y[i] as Vector3)
		fy = fy - fx.normalized() * fy.dot(fx.normalized())
		if fx.length_squared() > 1e-6 and fy.length_squared() > 1e-6:
			fx = fx.normalized(); fy = fy.normalized()
			o["foot%d" % i] = Basis(fx, fy, fx.cross(fy))
	o["shoe_drop"] = 0.05
	last_world = P
	rider.pose_points(P, o)
