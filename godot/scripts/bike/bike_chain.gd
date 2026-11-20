class_name BikeChain
extends Node3D
## A drawn, moving chain: real 1/2" links (outer plates + pins, inner plates + rollers, two MultiMeshes) laid
## pin to pin along the chain path every frame: chainring -> top run -> the cog of the current gear -> S through
## the derailleur's two pulleys -> bottom run -> chainring. The path is built from tangent lines + arcs between the
## circles, so it follows the suspension (the axle and the pulleys move with the rear triangle), the chainring
## (its teeth from the garage build) and the gear: a shift moves the chain onto the new cog's size and plane in
## SHIFT_T (a bigger cog = a longer chain, links are added / dropped). The links travel with the cranks.
## Frames carry the data in their glb extras ("chain": ring_r / ring_z / cog_z, pulleys as nodes "pulley_1" /
## "pulley_2" under the rear triangle; GameState.BIKES.<id>.chain overrides keys); "ring_teeth" = the drawn ring is
## the stock crank's (that many teeth): it and the chain take the build's chainring; "follow" = the chain sits on the
## cassette's cog planes (WheelGen.cog_z), "cage" = the pulleys move across with it. The stock RUNOUT DH (dh.glb) has a fixed chain mesh on its swingarm
## instead: `adopt_stock` cuts it out and sets the same data up from STOCK.
## Sits under the bike model; runs after the game has posed the bike (child of it in the tree).

const PITCH := 0.0127
const MAX_LINKS := 200
const SHIFT_T := 0.12        # s: the chain moving onto a new cog
## dh.glb, measured off its chain mesh / derailleur cage: the 34T ring, the pulley centres (seatstay-local)
const STOCK := {"ring_r": 0.0688, "ring_z": 0.056, "cog_z": 0.052, "pulley_r": 0.0225, "pulley_z": 0.052,
	"pulleys": [[0.0167, -0.0356], [0.0017, -0.1026]], "ring_teeth": 34, "follow": true, "cage": true}

var rig: BikeRig
var cfg: Dictionary
var ring_node: Node3D
var axle: Node3D
var pulleys: Array = []   # [node, radius, sense, z]
var mm_out: MultiMesh     # outer links (plates + pins)
var mm_in: MultiMesh      # inner links (plates + rollers)
var ring_r := 0.0688
var cogs: Array = [16]    # the cassette, small to big
var gear := 0
var cog_teeth := 16.0     # set_gear(): the cog in use (eased while shifting)
var _cog_r := -1.0
var _cog_zl := 0.05       # wheel-local plane of the cog in use (eased)
var _pins := PackedVector3Array()

static var _mesh_out: ArrayMesh
static var _mesh_in: ArrayMesh


static func pitch_r(teeth: float) -> float:
	return PITCH / (2.0 * sin(PI / maxf(teeth, 6.0)))


## the stock frame (dh.glb): its chain is a fixed mesh on the swingarm (moved with it, never with the cranks).
## Cut it out and give the model the data for a drawn chain. False when the model has no such mesh.
static func adopt_stock(model: Node3D, extras: Dictionary) -> bool:
	var sw := model.find_child("swing", true, false) as MeshInstance3D
	var seat := model.find_child("seatstay", true, false) as Node3D
	if sw == null or seat == null or sw.mesh == null:
		return false
	var si := -1
	for i in sw.mesh.get_surface_count():
		var m: Material = sw.mesh.surface_get_material(i)
		if m and m.resource_name == "chain":
			si = i
	if si < 0:
		return false
	var cm: ArrayMesh = sw.mesh.duplicate()
	cm.surface_remove(si)
	sw.mesh = cm
	for k in 2:
		var p := Node3D.new()
		p.name = "pulley_%d" % (k + 1)
		p.position = Vector3(STOCK.pulleys[k][0], STOCK.pulleys[k][1], STOCK.pulley_z)
		seat.add_child(p)
	extras["chain"] = STOCK.duplicate(true)
	return true


func setup(p_rig: BikeRig, build: Dictionary = {}) -> void:
	rig = p_rig
	cfg = rig.extras.chain
	name = "chain"
	ring_node = rig.crank_n
	axle = rig.wheel_r
	ring_r = float(cfg.ring_r)
	var drive: Dictionary = build.get("drive", {})
	if cfg.has("ring_teeth") and drive.has("ring"):   # the stock crank: its ring takes the build's teeth
		var teeth := float(drive.ring)
		ring_r = pitch_r(teeth)
		_resize_ring(ring_r - pitch_r(float(cfg.ring_teeth)))
	var cas: Dictionary = BikeBuild.CASSETTES.get(str(drive.get("cassette", "")), {})
	if cas.has("cogs"):
		cogs = (cas.cogs as Array).duplicate()
	gear = cogs.size() / 2   # the garage / menus: a middle gear
	cog_teeth = float(cogs[gear])
	_cog_zl = WheelGen.cog_z(gear, cogs.size())
	var seat := rig.model.find_child("seatstay", true, false)
	for k in 2:
		var n: Node3D = seat.find_child("pulley_%d" % (k + 1), true, false) if seat else null
		if n == null:
			queue_free(); return
		pulleys.append([n, float(cfg.pulley_r), 1 if k == 1 else -1, float(cfg.pulley_z)])
	if _mesh_out == null:
		_mesh_out = _link_mesh(true)
		_mesh_in = _link_mesh(false)
	mm_out = _multimesh(_mesh_out)
	mm_in = _multimesh(_mesh_in)


## the game, every frame: the gear in use (index into the cassette, small to big)
func set_gear(i: int, p_cogs: Array) -> void:
	if p_cogs.is_empty():
		return
	if p_cogs != cogs:
		cogs = p_cogs.duplicate()
	gear = clampi(i, 0, cogs.size() - 1)


func _multimesh(mesh: Mesh) -> MultiMesh:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = mesh
	m.instance_count = MAX_LINKS / 2
	m.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = m
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(inst)
	return m


func _process(dt: float) -> void:
	if rig == null or rig.model == null or not is_instance_valid(axle):
		return
	# shifting: the chain eases onto the new cog's size and plane
	var k := 1.0 - exp(-dt / (SHIFT_T * 0.35))
	var tr := pitch_r(float(cogs[gear]))
	_cog_r = tr if _cog_r < 0.0 else lerpf(_cog_r, tr, k)
	_cog_zl = lerpf(_cog_zl, WheelGen.cog_z(gear, cogs.size()), k)
	cog_teeth = float(cogs[gear])
	var to_model := rig.model.global_transform.affine_inverse()
	var pa := to_model * axle.global_position
	var cz: float = (to_model * (axle.global_transform * Vector3(0, 0, _cog_zl))).z if cfg.get("follow", false) else float(cfg.cog_z)
	var pr := ring_node.position
	var circles := []   # [centre (xy), radius, sense (+1 ccw), z]
	circles.append([Vector2(pr.x, pr.y), ring_r, 1, float(cfg.ring_z)])
	circles.append([Vector2(pa.x, pa.y), _cog_r, 1, cz])
	for p in pulleys:
		var q: Vector3 = to_model * (p[0] as Node3D).global_position
		circles.append([Vector2(q.x, q.y), p[1], p[2], cz if cfg.get("cage", false) else p[3]])   # stock: the cage follows the cog
	var pts := _path(circles)
	if pts.size() < 4:
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + (pts[i] - pts[i - 1]).length())
	var total: float = cum[cum.size() - 1]
	var n := mini(MAX_LINKS, maxi(4, int(round(total / PITCH))) & ~1)
	var step := total / n
	# the pins: the chain runs the other way round to the path when pedalling forward
	var phase := fposmod(-rig.crank_angle * ring_r, step * 2.0)
	_pins.resize(n)
	for i in n:
		var s := fposmod(phase + i * step, total)
		var seg := clampi(cum.bsearch(s), 1, cum.size() - 1)
		var u := clampf((s - cum[seg - 1]) / maxf(cum[seg] - cum[seg - 1], 1e-6), 0.0, 1.0)
		_pins[i] = pts[seg - 1].lerp(pts[seg], u)
	# each link spans two pins (a polygon round the sprockets, like a real chain); even = outer, odd = inner
	mm_out.visible_instance_count = n / 2
	mm_in.visible_instance_count = n / 2
	for i in n:
		var a := _pins[i]
		var b := _pins[(i + 1) % n]
		var dir := b - a
		if dir.length_squared() < 1e-10:
			dir = Vector3.RIGHT
		dir = dir.normalized()
		var yy := Vector3(0, 0, 1).cross(dir).normalized()
		var bs := Basis(dir, yy, dir.cross(yy))
		(mm_out if i % 2 == 0 else mm_in).set_instance_transform(i / 2, Transform3D(bs, (a + b) * 0.5))


## the stock crank's chainring follows the build's teeth: its tooth band moves out / in by dr (the ring's plane only,
## the spider and the arm stay)
func _resize_ring(dr: float) -> void:
	if absf(dr) < 1e-5:
		return
	var mi := ring_node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var src: ArrayMesh = mi.mesh
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var mat := src.surface_get_material(i)
		if mat and mat.resource_name == "black":
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for j in v.size():
				var p := v[j]
				if p.z < 0.048 or p.z > 0.0615: continue
				var r := Vector2(p.x, p.y).length()
				if r < 0.045 or r > 0.085: continue
				var w := smoothstep(0.045, 0.056, r)
				var nr := r + dr * w
				v[j] = Vector3(p.x * nr / r, p.y * nr / r, p.z)
			arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_name(out.get_surface_count() - 1, src.surface_get_name(i))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	mi.mesh = out


## one link, x along the chain (pins at +-PITCH/2), y in the chain's plane, z across. Outer: two plates outside +
## the pins (with their riveted heads); inner: two plates inside + the rollers the teeth sit between.
static func _link_mesh(outer: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plate_c := Color(0.62, 0.63, 0.66) if outer else Color(0.36, 0.37, 0.39)
	var zc := 0.0029 if outer else 0.0018   # plate middle
	var th := 0.0008
	for sd in [-1.0, 1.0]:
		_plate(st, sd * zc, th, 0.0037 if outer else 0.0039, 0.0026 if outer else 0.0030, plate_c)
	for e in [-1.0, 1.0]:
		var x: float = e * PITCH * 0.5
		if outer:
			_cyl(st, Vector3(x, 0, 0), 0.00185, -0.0040, 0.0040, Color(0.78, 0.79, 0.8))   # pin, heads proud of the plates
		else:
			_cyl(st, Vector3(x, 0, 0), 0.0038, -0.0013, 0.0013, Color(0.28, 0.28, 0.3))     # roller
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.85
	mat.roughness = 0.38
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mat)
	return st.commit()


## a figure-eight side plate: lobes of radius R round both pins, a waist of half-height w, thickness th at z
static func _plate(st: SurfaceTool, z: float, th: float, R: float, w: float, col: Color) -> void:
	var L := PITCH * 0.5 + R
	var N := 14
	var outl := PackedVector2Array()
	for k in N + 1:   # top edge, left -> right
		var x := -L + 2.0 * L * float(k) / N
		var d := absf(x) - PITCH * 0.5
		var lobe := sqrt(maxf(R * R - d * d, 0.0)) if absf(d) <= R else 0.0
		var y := maxf(lobe, w) if absf(x) < PITCH * 0.5 else lobe
		outl.append(Vector2(x, y))
	for k in range(N - 1, 0, -1):   # bottom edge, right -> left
		outl.append(Vector2(outl[k].x, -outl[k].y))
	var m := outl.size()
	for sd in [-1.0, 1.0]:   # faces: fans from the middle
		var zz: float = z + sd * th * 0.5
		var nrm := Vector3(0, 0, sd)
		for k in m:
			var a := outl[k]; var b := outl[(k + 1) % m]
			var tri := [Vector3(0, 0, zz), Vector3(a.x, a.y, zz), Vector3(b.x, b.y, zz)]
			if sd < 0: tri = [tri[0], tri[2], tri[1]]
			for p in tri:
				st.set_color(col); st.set_normal(nrm); st.add_vertex(p)
	for k in m:   # rim
		var a := outl[k]; var b := outl[(k + 1) % m]
		var e := b - a
		var nrm := Vector3(e.y, -e.x, 0).normalized()
		var p0 := Vector3(a.x, a.y, z - th * 0.5); var p1 := Vector3(b.x, b.y, z - th * 0.5)
		var p2 := Vector3(b.x, b.y, z + th * 0.5); var p3 := Vector3(a.x, a.y, z + th * 0.5)
		for p in [p0, p2, p1, p0, p3, p2]:
			st.set_color(col); st.set_normal(nrm); st.add_vertex(p)


## a cylinder along z from z0 to z1 with caps
static func _cyl(st: SurfaceTool, c: Vector3, r: float, z0: float, z1: float, col: Color) -> void:
	var N := 10
	for k in N:
		var a0 := TAU * k / N; var a1 := TAU * (k + 1) / N
		var d0 := Vector3(cos(a0), sin(a0), 0); var d1 := Vector3(cos(a1), sin(a1), 0)
		var q0 := c + d0 * r; var q1 := c + d1 * r
		var quad := [[q0 + Vector3(0, 0, z0), d0], [q1 + Vector3(0, 0, z1), d1], [q1 + Vector3(0, 0, z0), d1],
			[q0 + Vector3(0, 0, z0), d0], [q0 + Vector3(0, 0, z1), d0], [q1 + Vector3(0, 0, z1), d1]]
		for v in quad:
			st.set_color(col); st.set_normal(v[1]); st.add_vertex(v[0])
		for sd in [-1.0, 1.0]:
			var zz: float = z1 if sd > 0 else z0
			var tri := [c + Vector3(0, 0, zz), q0 + Vector3(0, 0, zz), q1 + Vector3(0, 0, zz)]
			if sd < 0: tri = [tri[0], tri[2], tri[1]]
			for p in tri:
				st.set_color(col); st.set_normal(Vector3(0, 0, sd)); st.add_vertex(p)


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
