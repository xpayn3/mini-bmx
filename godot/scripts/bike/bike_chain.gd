class_name BikeChain
extends Node3D
## A drawn chain for frames that carry the data in their glb extras ("chain": ring_r / ring_z / cog_z, the rear
## derailleur's two pulleys as nodes "pulley_1" / "pulley_2" under the rear triangle): one MultiMesh of links
## laid along the real chain path every frame: chainring -> top run -> the cog of the current gear -> S through
## the derailleur's pulleys -> bottom run -> chainring. The path is built from tangent lines + arcs between the
## circles, so it follows the suspension (the axle and the pulleys move with the rear triangle) and the
## gear (a bigger cog = a longer chain, the links are added / dropped). The links travel with the cranks.
## Sits under the bike model; runs after the game has posed the bike (child of it in the tree).

const PITCH := 0.0127
const MAX_LINKS := 190

var rig: BikeRig
var cfg: Dictionary
var ring_node: Node3D
var axle: Node3D
var pulleys: Array = []   # [node, radius, sense, z]
var mm: MultiMesh
var cog_teeth := 16.0     # set by the game for the gear in use


func setup(p_rig: BikeRig) -> void:
	rig = p_rig
	cfg = rig.extras.chain
	name = "chain"
	ring_node = rig.crank_n
	axle = rig.wheel_r
	var seat := rig.model.find_child("seatstay", true, false)
	for k in 2:
		var n: Node3D = seat.find_child("pulley_%d" % (k + 1), true, false) if seat else null
		if n == null:
			queue_free(); return
		pulleys.append([n, float(cfg.pulley_r), 1 if k == 1 else -1, float(cfg.pulley_z)])
	var link := BoxMesh.new()
	link.size = Vector3(PITCH * 0.92, 0.0072, 0.0078)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22); mat.metallic = 0.9; mat.roughness = 0.4
	link.material = mat
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link
	mm.instance_count = MAX_LINKS
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)


func _process(_dt: float) -> void:
	if rig == null or rig.model == null or not is_instance_valid(axle):
		return
	var to_model := rig.model.global_transform.affine_inverse()
	var pa := to_model * axle.global_position
	var pr := ring_node.position
	var circles := []   # [centre (xy), radius, sense (+1 ccw), z]
	circles.append([Vector2(pr.x, pr.y), float(cfg.ring_r), 1, float(cfg.ring_z)])
	circles.append([Vector2(pa.x, pa.y), 0.0127 / (2.0 * sin(PI / cog_teeth)), 1, float(cfg.cog_z)])
	for p in pulleys:
		var q: Vector3 = to_model * (p[0] as Node3D).global_position
		circles.append([Vector2(q.x, q.y), p[1], p[2], p[3]])
	var pts := _path(circles)
	if pts.size() < 4:
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + (pts[i] - pts[i - 1]).length())
	var total: float = cum[cum.size() - 1]
	var n := mini(MAX_LINKS, maxi(2, int(round(total / PITCH))) & ~1)
	var step := total / n
	# the chain runs the other way round to the path when pedalling forward
	var phase := fposmod(-rig.crank_angle * float(cfg.ring_r), step * 2.0)
	var seg := 1
	for i in MAX_LINKS:
		if i >= n:
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var s := fposmod(phase + i * step, total)
		while seg < cum.size() - 1 and cum[seg] < s: seg += 1
		while seg > 1 and cum[seg - 1] > s: seg -= 1
		var a: Vector3 = pts[seg - 1]
		var b: Vector3 = pts[seg]
		var u := clampf((s - cum[seg - 1]) / maxf(cum[seg] - cum[seg - 1], 1e-6), 0.0, 1.0)
		var pos := a.lerp(b, u)
		var dir := (b - a).normalized()
		var yy := Vector3(0, 0, 1).cross(dir).normalized()
		var zz := dir.cross(yy)
		var bs := Basis(dir, yy, zz)
		if i % 2 == 1:
			bs = bs.scaled_local(Vector3(1.0, 1.0, 0.78))
		mm.set_instance_transform(i, Transform3D(bs, pos))


## closed chain path through the circles in order (ring, cog, pulley 1, pulley 2); points are (x, y, z)
func _path(c: Array) -> PackedVector3Array:
	var k := c.size()
	var tin := []; var tout := []   # per circle: where the chain arrives / leaves
	tin.resize(k); tout.resize(k)
	for i in k:
		var j := (i + 1) % k
		var t := _tangent(c[i][0], c[i][1], c[i][2], c[j][0], c[j][1], c[j][2])
		if t.is_empty():
			return PackedVector3Array()
		tout[i] = t[0]; tin[j] = t[1]
	var out := PackedVector3Array()
	for i in k:
		var ctr: Vector2 = c[i][0]
		var r: float = c[i][1]
		var s: int = c[i][2]
		var z: float = c[i][3]
		var pin: Vector2 = tin[i]
		var pout: Vector2 = tout[i]
		var a0: float = (pin - ctr).angle()
		var a1: float = (pout - ctr).angle()
		var d: float = fposmod(a1 - a0, TAU) if s > 0 else -fposmod(a0 - a1, TAU)
		var steps := maxi(2, int(absf(d) * r / 0.004))
		for m in steps + 1:
			var ang: float = a0 + d * m / steps
			var p := ctr + Vector2.from_angle(ang) * r
			out.append(Vector3(p.x, p.y, z))
	out.append(out[0])
	return out


## the straight line from circle A (turning sa) to circle B (turning sb), as [point on A, point on B]
static func _tangent(A: Vector2, ra: float, sa: int, B: Vector2, rb: float, sb: int) -> Array:
	var d := B - A
	var L := d.length()
	if L < 1e-5:
		return []
	var kk := (ra - rb) if sa == sb else (ra + rb)
	var gam := acos(clampf(kk / L, -1.0, 1.0))
	for sg in [-1.0, 1.0]:
		var alpha: float = d.angle() + sa * PI * 0.5 + sg * gam
		var u := Vector2.from_angle(alpha)
		var pA := A + u.rotated(-sa * PI * 0.5) * ra
		var pB := B + u.rotated(-sb * PI * 0.5) * rb
		if (pB - pA).dot(u) > 0.0:
			return [pA, pB]
	return []
