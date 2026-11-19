class_name Blood
extends Node3D
## Blood after a crash (Settings › Gameplay › Blood):
##  * on the GROUND: every ragdoll part that slides along the ground while it is bleeding drags a smear
##    behind it (thinner and patchier the further it slides), and a part that slams down leaves a splat
##    with droplets. One MultiMesh of flat quads (shaders/blood_streak.gdshader), a ring of MAX quads.
##  * TORN-OFF LIMBS: a very hard crash can tear an arm or a leg off (at the shoulder / elbow / hip /
##    knee, Ragdoll.sever): the piece tumbles away on its own and the stump spurts blood for a few seconds.
## Stays for the ride; a respawn (Backspace / new world) fades it all out over WIPE seconds (blood laid
## after the respawn stays).
const WIPE := 4.0

const MAX := 1500
const SHADER := preload("res://shaders/blood_streak.gdshader")
## which joints bleed onto the ground how much (feet are in shoes, hands in gloves: less)
const BLEED_K := [1.0, 1.0, 0.9, 0.8, 0.9, 0.5, 0.8, 0.9, 0.5, 0.7, 1.0, 0.25, 0.7, 1.0, 0.25]

var terrain
var fx                     # fx.gd: droplets thrown off on a hit
var enabled := true
var mm: MultiMesh
var mat: ShaderMaterial
var _next := 0
var _count := 0
var _t := 0.0
var _air := PackedByteArray()
var _bleed := PackedFloat32Array()
var _last: Array = []
var probe := false
## torn-off limbs: a fast crash (> SEVER_SPEED) tears off the first limb that hits the ground hard enough
## (> 3), any limb hit > SEVER_HIT tears it off; at most SEVER_MAX limbs per crash. A hand / foot hit
## takes the forearm / shin (at the elbow / knee), an elbow / knee hit the whole arm / leg.
const SEVER_SPEED := 16.0
const SEVER_HIT := 14.0
const SEVER_MAX := 2
const CUT_AT := {5: 4, 4: 3, 8: 7, 7: 6, 11: 10, 10: 9, 14: 13, 13: 12}   # hit point -> joint cut
const CUT_PARENT := {3: 1, 4: 3, 6: 1, 7: 6, 9: 2, 10: 9, 12: 2, 13: 12}   # joint -> the body side of it
var ragdoll                     # ragdoll.gd (game sets it)
var _sever_ready := false
var _severed := 0
var _wounds: Array = []         # {a, root, t, ph, body: MeshInstance3D, end: MeshInstance3D}
var _stump_mesh: SphereMesh
var laid := 0              # tests: quads laid this crash
var smears := 0

func _init(p_terrain, p_fx) -> void:
	name = "Blood"
	terrain = p_terrain
	fx = p_fx
	probe = OS.get_environment("BMX_BLOOD_PROBE") != ""
	var q := PlaneMesh.new()
	q.size = Vector2.ONE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 1
	q.material = mat
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	var mi := MultiMeshInstance3D.new()
	mi.name = "blood"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# the stump caps (body side + the torn-off piece's end): flattened dark red
	_stump_mesh = SphereMesh.new()
	_stump_mesh.radius = 0.05
	_stump_mesh.height = 0.045
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.2, 0.01, 0.01)
	smat.roughness = 0.2
	_stump_mesh.material = smat

func _process(dt: float) -> void:
	_t += dt
	mat.set_shader_parameter("now", _t)

## the ground under a point: the drawn mesh / rock / deck top, and its normal
func _ground(x: float, z: float) -> float:
	return terrain.top_height(x, z)

func _normal(x: float, z: float) -> Vector3:
	var e := 0.2
	return Vector3(_ground(x - e, z) - _ground(x + e, z), 2.0 * e, _ground(x, z - e) - _ground(x, z + e)).normalized()

func _put(origin: Vector3, n: Vector3, along: Vector3, width: float, length: float, strength: float, kind: int) -> void:
	var zd := (along - n * along.dot(n)).normalized()
	var xd := n.cross(zd).normalized()
	var b := Basis(xd * width, n, zd * length)
	var i := _next
	_next = (i + 1) % MAX
	_count = mini(_count + 1, MAX)
	mm.set_instance_transform(i, Transform3D(b, origin))
	mm.set_instance_custom_data(i, Color(randf() * 50.0, _t, clampf(strength, 0.0, 1.0), float(kind)))
	mm.visible_instance_count = _count
	laid += 1

## a smear from a to b (ground points), `width` metres wide
func smear(a: Vector3, b: Vector3, width: float, strength: float) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 1e-3: return
	var mid := (a + b) * 0.5
	_put(mid + Vector3(0, 0.012, 0), _normal(mid.x, mid.z), d, width, ln + width * 0.35, strength, 0)
	smears += 1
	if probe and smears % 5 == 1: print("BLOOD smear #%d len=%.2f w=%.2f s=%.2f" % [smears, ln, width, strength])

## a splat (and droplets) where something hit the ground
func splat(at: Vector3, size: float, strength: float, vel := Vector3.ZERO) -> void:
	var g := _ground(at.x, at.z)
	var p := Vector3(at.x, g + 0.014, at.z)
	var fwd := Vector3(vel.x, 0, vel.z)
	if fwd.length() < 0.1: fwd = Vector3(randf() - 0.5, 0, randf() - 0.5)
	# stretched a little the way it was going
	var k := clampf(fwd.length() / 8.0, 0.0, 0.6)
	_put(p, _normal(p.x, p.z), fwd, size, size * (1.0 + k), strength, 1)
	if fx != null:
		for j in int(4 + 8 * strength):
			var dv := Vector3((randf() - 0.5) * 2.4, 0.8 + randf() * 1.8, (randf() - 0.5) * 2.4) + Vector3(vel.x, 0, vel.z) * 0.25
			fx.chunk(p + Vector3(0, 0.08, 0), dv, Color(0.2, 0.01, 0.01), 0.012, 0.9)

## the crash starts: a fast fall already has the rider bleeding a little everywhere
func crash_start(speed: float) -> void:
	_air.resize(0)
	laid = 0
	smears = 0
	if not enabled: return
	_sever_ready = speed > SEVER_SPEED or OS.get_environment("BMX_SEVER") != ""
	_severed = 0
	var base := clampf((speed - 4.0) / 12.0, 0.0, 1.0)
	_bleed.resize(BLEED_K.size())
	for i in BLEED_K.size():
		_bleed[i] = base * (0.35 + randf() * 0.5) * float(BLEED_K[i])
	if probe: print("BLOOD start speed=%.1f base=%.2f" % [speed, base])

## per frame while crashed: pts / prv = ragdoll points now / one substep back, h = that substep
func crash_step(pts: Array, prv: Array, h: float, rad: Array) -> void:
	if not enabled: return
	var n := pts.size()
	if _air.size() < n:
		# first frame of a crash (or a torn-off piece's new root point)
		var n0 := _air.size()
		_air.resize(n)
		_last.resize(n)
		if _bleed.size() < n:
			var b0 := _bleed.size()
			_bleed.resize(n)
			for i in range(b0, n): _bleed[i] = 0.0
		for i in range(n0, n):
			var p0: Vector3 = pts[i]
			_air[i] = 1 if p0.y - terrain.height(p0.x, p0.z) > float(rad[i]) + 0.18 else 0
			_last[i] = null
	if not _wounds.is_empty(): _bleed_wounds(pts, get_process_delta_time())
	if ragdoll != null and OS.get_environment("BMX_RAGDOLL_PROBE") != "" and Engine.get_process_frames() % 15 == 0:
		var pel: Vector3 = pts[2]
		print("RAGDOLL neutral_off=%.2f pelvis_up=%.2f rise=%.2f vup=%.1f t=%.2f" % [ragdoll.nb_off / maxf(1.0, 9.0 * 3.0 * 15.0), pel.y - terrain.height(pel.x, pel.z), ragdoll.probe_rise, ragdoll.probe_vup, ragdoll.t_fall])
		ragdoll.nb_off = 0.0
	for i in n:
		var pp: Vector3 = pts[i]
		var g: float = terrain.height(pp.x, pp.z)
		var above := pp.y - g
		var r: float = rad[i]
		if above > r + 0.18:   # off the ground: the next touch-down is an impact
			_air[i] = 1
			_last[i] = null
			continue
		if above > r + 0.12:   # near the ground but not on it
			_last[i] = null
			continue
		if terrain.surface(pp.x, pp.z) == 2:   # in water: washes away
			_last[i] = null
			continue
		var v: Vector3 = (pp - (prv[i] as Vector3)) / maxf(h, 1e-4)
		var hs := Vector2(v.x, v.z).length()
		var at := Vector3(pp.x, _ground(pp.x, pp.z), pp.z)
		var k_i: float = BLEED_K[i] if i < BLEED_K.size() else 1.0
		if _air[i] == 1:
			_air[i] = 0
			var hit := maxf(0.0, -v.y) + hs * 0.35
			if CUT_AT.has(i) and _severed < SEVER_MAX and (hit > SEVER_HIT or (_sever_ready and _severed == 0 and hit > 3.0)):
				_sever(CUT_AT[i], pts, v)
			if hit > 2.2:
				var k := clampf((hit - 2.2) / 6.0, 0.1, 1.0)
				_bleed[i] = minf(1.6, _bleed[i] + (0.4 + k) * k_i)
				splat(at, (0.22 + 0.4 * k) * (0.6 + 0.4 * k_i), k, v)
				if probe: print("BLOOD hit i=%d hit=%.1f bleed=%.2f" % [i, hit, _bleed[i]])

		if _bleed[i] > 0.05 and hs > 0.5:
			if _last[i] == null:
				_last[i] = at
				continue
			var last: Vector3 = _last[i]
			var ln := Vector2(at.x - last.x, at.z - last.z).length()
			if ln < 0.1: continue
			if ln > 1.2:
				_last[i] = at
				continue
			smear(last, at, clampf(r * 1.5, 0.07, 0.2), minf(1.0, _bleed[i]))
			_bleed[i] = maxf(0.0, _bleed[i] - ln * 0.09)   # ~10 m of smear from a full bleed
			_last[i] = at
		elif hs < 0.2:
			_last[i] = null

## tear the limb off at joint a: free it in the ragdoll, throw it on, cap both ends, start the stump spurting
func _sever(a: int, pts: Array, v: Vector3) -> void:
	if ragdoll == null: return
	var kick := Vector3(v.x * 0.3, 1.5 + randf() * 2.0, v.z * 0.3) + Vector3(randf() - 0.5, 0, randf() - 0.5) * 2.5
	var root: int = ragdoll.sever(a, kick)
	if root < 0: return
	_severed += 1
	var w := {a = a, root = root, t = 2.5, ph = randf() * 3.0, body = _cap(), end = _cap()}
	_wounds.append(w)
	var pa: Vector3 = pts[a]
	splat(Vector3(pa.x, 0, pa.z), 0.45, 1.0, v)
	_bleed[a] = 1.6
	if _bleed.size() <= root:
		var b0 := _bleed.size()
		_bleed.resize(root + 1)
		for i in range(b0, root + 1): _bleed[i] = 0.0
	_bleed[root] = 1.6
	if probe: print("BLOOD sever joint=%d v=%.1f" % [a, v.length()])

func _cap() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _stump_mesh
	add_child(m)
	return m

## per frame for each torn-off limb: the caps follow both ends, the stump spurts in pulses
func _bleed_wounds(pts: Array, dt: float) -> void:
	for w in _wounds:
		var a: int = w.a
		var pa: Vector3 = pts[a]
		var out: Vector3 = (pa - (pts[CUT_PARENT[a]] as Vector3)).normalized()
		(w.body as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, out)), pa + out * 0.03)
		var r: int = w.root
		if r < pts.size():
			var pr: Vector3 = pts[r]
			var b: int = ragdoll.LIMB_NEXT[a]
			var into: Vector3 = (pr - (pts[b] as Vector3)).normalized()
			(w.end as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, into)), pr)
		if w.t <= 0.0: continue
		w.t -= dt
		w.ph += dt
		# spurts in pulses (a heartbeat), weaker as it runs out
		var pulse := maxf(0.0, sin(float(w.ph) * 7.5)) * clampf(float(w.t) / 2.5, 0.0, 1.0)
		if fx != null:
			for j in int(pulse * 4.0):
				var dv := out * (1.5 + 2.5 * pulse) + Vector3(randf() - 0.5, randf() * 0.8, randf() - 0.5) * 1.2
				fx.chunk(pa + out * 0.05, dv, Color(0.2, 0.01, 0.01), 0.013, 0.8)
		if pulse > 0.6 and randf() < dt * 6.0:
			splat(pa + Vector3(out.x, 0, out.z) * (0.3 + randf() * 0.6), 0.1 + randf() * 0.12, 0.7)
		_bleed[a] = maxf(_bleed[a], 1.0)

func crash_end() -> void:
	_sever_ready = false
	for w in _wounds:
		(w.body as Node).queue_free()
		(w.end as Node).queue_free()
	_wounds.clear()
	_air.resize(0)
	_bleed.fill(0.0)
	if probe: print("BLOOD end laid=%d smears=%d severed=%d" % [laid, smears, _severed])
	if ragdoll != null and OS.get_environment("BMX_RAGDOLL_PROBE") != "": print("EJECT rise=%.2f vup=%.1f" % [ragdoll.probe_rise, ragdoll.probe_vup])

## respawn: everything laid so far fades away over WIPE seconds (the shader: born before wipe_t)
func clear() -> void:
	mat.set_shader_parameter("wipe_t", _t)
	mat.set_shader_parameter("wipe_len", WIPE)
