class_name Blood
extends Node3D
## Blood after a crash (Settings › Gameplay › Blood):
##  * on the GROUND: every ragdoll part that slides along the ground while it is bleeding drags a smear
##    behind it (thinner and patchier the further it slides), and a part that slams down leaves a splat
##    with droplets. One MultiMesh of flat quads (shaders/blood_streak.gdshader), a ring of MAX quads.
##  * TORN-OFF LIMBS: a very hard crash can tear an arm or a leg off (at the shoulder / elbow / hip /
##    knee, Ragdoll.sever): the piece tumbles away on its own; the stump pumps an arterial jet with each
##    heartbeat (weakening over JET_T s) and the piece pours out of its end.
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
## hit splats are projected Decals (they hug every bump of the ground, never clip or flicker): one of
## SPLAT_KINDS textures made once (BloodSplatTex.cs), random turn / size / stretch; ground layer only
const SPLAT_KINDS := 8
const SPLAT_MAX := 160
const DRY_T := 45.0
var _splat_tex: Array = []
var _splat_orm: ImageTexture
var _decals: Array = []
var _slid := PackedFloat32Array()   # how far each part has smeared since it started sliding (ramps the smear in)
## a FATAL crash (> FATAL_SPEED, or a limb torn off): once the body lies still a pool of blood spreads from
## under the chest (and each stump), slowly, to POOL_R, while he stays down; it stays until a respawn
const FATAL_SPEED := 12.0
const POOL_R := 1.15            # m, the chest pool's final radius (a stump's: 0.6)
const POOL_T := 9.0             # s, how fast it spreads (most of it in the first POOL_T)
const POOL_MAX := 8
var _fatal := false
var _rest_t := 0.0
const POOL := preload("res://scripts/fx/blood_pool.gd")
var _pools: Array = []          # blood_pool.gd nodes still spreading (this crash)
var _all_pools: Array = []      # every pool on the ground (freed after a respawn wipe)
var _warm_mat: ShaderMaterial   # keeps the warmed-up pool shaders alive
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
## BROKEN BONES: a limb that lands very hard in a fast crash (> BREAK_SPEED) breaks at the elbow / knee
## (hand / forearm hit -> elbow, foot / shin hit -> knee; Ragdoll.break_joint: it flops, bends the wrong
## way), with a crunch, a bone end sticking out of a bleeding wound. At most BREAK_MAX per crash.
## Torn-off limbs show bone in both stumps too.
const BREAK_SPEED := 9.0
const BREAK_HIT := 5.5
const BREAK_MAX := 2
const BREAK_AT := {5: 4, 4: 4, 8: 7, 7: 7, 11: 10, 10: 10, 14: 13, 13: 13}   # hit point -> joint that breaks
const BREAK_PARENT := {4: 3, 7: 6, 10: 9, 13: 12}                           # joint -> the bone above it
var _break_ready := false
var _broken := 0
var _fractures: Array = []      # {j, bone: MeshInstance3D, ring: MeshInstance3D}
var _bone_mesh: CylinderMesh
var _stub_mesh: CylinderMesh
var _ring_mesh: SphereMesh
var _crunch: AudioStreamWAV
## tyres that rolled through blood print red for a while (game.gd -> tyre_color)
var _tyre_blood := [0.0, 0.0]
var _tyre_last: Array = [null, null]
## the ARTERIAL JET: the stump pumps a stream with every heartbeat (HEART_HZ), strong at first and
## weakening over JET_T seconds; the torn-off piece pours out of its end, weaker. Drops fly ballistic,
## drawn stretched along their flight (shaders/blood_jet.gdshader) so they join into one stream; where
## they land they pool (splats).
const JET_MAX := 900
const JET_T := 9.0              # how long the stump pumps
const JET_RATE := 260.0         # drops per second per jet at full pressure
const JET_SPEED := 5.0          # m/s out of the stump at the top of a beat
const HEART_HZ := 2.0           # beats per second (a racing heart)
const JET_SHADER := preload("res://shaders/blood_jet.gdshader")
var _jet_mm: MultiMesh
var _jp := PackedVector3Array()
var _jv := PackedVector3Array()
var _jw := PackedFloat32Array()   # drop width
var _jn := 0
var jet_drops := 0                # tests
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
	# warm the C# blood code up now (its first call compiles: a ~0.1 s hitch mid-crash otherwise)
	if ResourceLoader.exists("res://scripts/fx/BloodPoolSim.cs"):
		var warm = load("res://scripts/fx/BloodPoolSim.cs").new()
		warm.Setup(8, 0.04, PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), 2, 1.0)
		warm.Step(1e-6, 4, 4, 2)
		warm.MakeImage()
		warm.DepthAt(1, 1)
	# and the pool shaders: their first use compiles them (~0.12 s): do it while the ride loads
	var pm := ShaderMaterial.new()
	pm.shader = POOL.SHADER
	pm.next_pass = ShaderMaterial.new()
	(pm.next_pass as ShaderMaterial).shader = POOL.HALO
	_warm_mat = pm
	# the jet drops
	var jq := QuadMesh.new()
	jq.size = Vector2.ONE
	var jmat := ShaderMaterial.new()
	jmat.shader = JET_SHADER
	jq.material = jmat
	_jet_mm = MultiMesh.new()
	_jet_mm.transform_format = MultiMesh.TRANSFORM_3D
	_jet_mm.mesh = jq
	_jet_mm.instance_count = JET_MAX
	_jet_mm.visible_instance_count = 0
	_jet_mm.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	var jmi := MultiMeshInstance3D.new()
	jmi.name = "blood_jet"
	jmi.multimesh = _jet_mm
	jmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(jmi)
	_jp.resize(JET_MAX); _jv.resize(JET_MAX); _jw.resize(JET_MAX)

func _process(dt: float) -> void:
	_t += dt
	mat.set_shader_parameter("now", _t)
	if _jn > 0: _jet_step(minf(dt, 0.05))

## one drop of the jet: at p going v (already moved `ahead` seconds along, so drops born within one
## frame spread out along the stream instead of bunching)
func _jet_emit(p: Vector3, v: Vector3, width: float, ahead: float) -> void:
	if _jn >= JET_MAX: return
	var g := Vector3(0, -9.8, 0)
	_jp[_jn] = p + v * ahead + g * (0.5 * ahead * ahead)
	_jv[_jn] = v + g * ahead
	_jw[_jn] = width
	_jn += 1
	jet_drops += 1
	if probe and jet_drops % 200 == 1: print("JET drops=%d live=%d p=%s v=%s" % [jet_drops, _jn, _jp[_jn - 1], _jv[_jn - 1]])

## fly the drops; a drop that reaches the ground goes, now and then leaving a splat (they pool up)
func _jet_step(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else Vector3.ZERO
	var i := 0
	while i < _jn:
		var v: Vector3 = _jv[i]
		v.y -= 9.8 * dt
		v *= 1.0 - 0.15 * dt
		var p: Vector3 = _jp[i] + v * dt
		var g: float = _ground(p.x, p.z)
		if p.y <= g + 0.01:
			if randf() < 0.07:
				splat(Vector3(p.x, 0, p.z), 0.07 + randf() * 0.1, 0.6 + randf() * 0.4, Vector3.ZERO, false)
			_jn -= 1
			_jp[i] = _jp[_jn]; _jv[i] = _jv[_jn]; _jw[i] = _jw[_jn]
			continue
		_jp[i] = p
		_jv[i] = v
		i += 1
	# draw: each drop a quad along its flight, long enough to reach the next drop (one stream)
	for j in _jn:
		var p: Vector3 = _jp[j]
		var v: Vector3 = _jv[j]
		var sp := v.length()
		var along := v / sp if sp > 1e-3 else Vector3.DOWN
		var to_eye := (eye - p).normalized()
		var side := along.cross(to_eye)
		if side.length_squared() < 1e-6: side = along.cross(Vector3.RIGHT)
		side = side.normalized()
		var face := side.cross(along)
		var ln := maxf(_jw[j] * 1.6, sp * 0.065)   # ~ the gap to the next drop: they overlap into a stream
		_jet_mm.set_instance_transform(j, Transform3D(Basis(side * _jw[j], along * ln, face), p))
	_jet_mm.visible_instance_count = _jn

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
	# a flat sheet on bumpy ground: lift it until no part of it is under the ground (the exact drawn
	# mesh height, Terrain.top_height), so it never z-fights / cuts into it (it flickered)
	var lift := 0.0
	for k in 9:
		var fx := (float(k % 3) - 1.0) * 0.5
		var fz := (float(k / 3) - 1.0) * 0.5
		var pt := origin + xd * (width * fx) + zd * (length * fz)
		var g := _ground(pt.x, pt.z) + 0.025
		# the sheet's height at pt (pt.y) vs the ground there, measured along the sheet's normal
		lift = maxf(lift, (g - pt.y) / maxf(n.y, 0.3))
	origin += n * lift
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
	_put(mid + Vector3(0, 0.03, 0), _normal(mid.x, mid.z), d, width, ln + width * 0.35, strength, 0)
	smears += 1
	if probe and smears % 5 == 1: print("BLOOD smear #%d len=%.2f w=%.2f s=%.2f" % [smears, ln, width, strength])

## a splat (and droplets) where something hit the ground
func splat(at: Vector3, size: float, strength: float, vel := Vector3.ZERO, drops := true) -> void:
	var g := _ground(at.x, at.z)
	var p := Vector3(at.x, g + 0.03, at.z)
	var fwd := Vector3(vel.x, 0, vel.z)
	if fwd.length() < 0.1: fwd = Vector3(randf() - 0.5, 0, randf() - 0.5)
	# stretched a little the way it was going
	var k := clampf(fwd.length() / 8.0, 0.0, 0.6)
	_decal(Vector3(at.x, g, at.z), _normal(at.x, at.z), fwd, size, size * (1.0 + k), strength)
	if fx != null and drops:
		for j in int(4 + 8 * strength):
			var dv := Vector3((randf() - 0.5) * 2.4, 0.8 + randf() * 1.8, (randf() - 0.5) * 2.4) + Vector3(vel.x, 0, vel.z) * 0.25
			fx.chunk(p + Vector3(0, 0.08, 0), dv, Color(0.2, 0.01, 0.01), 0.012, 0.9)

## a splat as a Decal: projected down onto the ground (layer GROUND_LAYER only, so never the rider / bike)
func _decal(at: Vector3, n: Vector3, along: Vector3, width: float, length: float, strength: float) -> void:
	if _splat_tex.is_empty():
		var gen = load("res://scripts/fx/BloodSplatTex.cs").new()
		for i in SPLAT_KINDS:
			_splat_tex.append(ImageTexture.create_from_image(gen.Make(1000 + i * 77, 128)))
		var orm := Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
		orm.fill(Color(1.0, 0.16, 0.0))   # AO, roughness (wet: glossy), metal
		_splat_orm = ImageTexture.create_from_image(orm)
	var d := Decal.new()
	d.texture_albedo = _splat_tex[randi() % SPLAT_KINDS]
	d.texture_orm = _splat_orm
	d.cull_mask = terrain.GROUND_LAYER
	d.size = Vector3(width * 2.0, 0.6, length * 2.0)   # the texture's splat fills ~half its square
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.normal_fade = 0.3
	d.distance_fade_enabled = true
	d.distance_fade_begin = 45.0
	d.distance_fade_length = 15.0
	var zd := (along - n * along.dot(n))
	zd = zd.normalized() if zd.length() > 1e-3 else n.cross(Vector3.RIGHT).normalized()
	var xd := n.cross(zd).normalized()
	add_child(d)
	d.global_transform = Transform3D(Basis(xd, n, zd).rotated(n, randf_range(-0.6, 0.6)), at)
	var a := clampf(0.8 + 0.2 * strength, 0.0, 1.0)
	d.modulate = Color(1, 1, 1, 0.0)
	var tw := d.create_tween()
	tw.tween_property(d, "modulate", Color(1, 1, 1, a), 0.15)            # soaks in
	tw.tween_property(d, "modulate", Color(0.55, 0.42, 0.36, a), DRY_T)  # dries darker / browner
	_decals.append(d)
	laid += 1
	while _decals.size() > SPLAT_MAX:
		var old = _decals.pop_front()
		if is_instance_valid(old): old.queue_free()

## the crash starts: a fast fall already has the rider bleeding a little everywhere
func crash_start(speed: float) -> void:
	_air.resize(0)
	laid = 0
	smears = 0
	if not enabled: return
	_sever_ready = speed > SEVER_SPEED or OS.get_environment("BMX_SEVER") != ""
	_fatal = speed > FATAL_SPEED or OS.get_environment("BMX_FATAL") != ""
	_rest_t = 0.0
	_pools.clear()
	_pools_started = false
	_severed = 0
	_broken = 0
	_break_ready = speed > BREAK_SPEED or OS.get_environment("BMX_BREAK") != ""
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
		_slid.resize(n)
		if _bleed.size() < n:
			var b0 := _bleed.size()
			_bleed.resize(n)
			for i in range(b0, n): _bleed[i] = 0.0
		for i in range(n0, n):
			var p0: Vector3 = pts[i]
			_air[i] = 1 if p0.y - terrain.height(p0.x, p0.z) > float(rad[i]) + 0.18 else 0
			_last[i] = null
			_slid[i] = 0.0
	if not _wounds.is_empty(): _bleed_wounds(pts, prv, h, get_process_delta_time())
	if not _fractures.is_empty(): _place_fractures(pts)
	if _spin_probe: _probe_spin(pts)
	if _fatal and _pools_started == false: _check_rest(pts, prv, h)
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
			elif _break_ready and BREAK_AT.has(i) and _broken < BREAK_MAX and hit > BREAK_HIT:
				_break(BREAK_AT[i], pts, v)
			if hit > 2.2:
				var k := clampf((hit - 2.2) / 6.0, 0.1, 1.0)
				_bleed[i] = minf(1.6, _bleed[i] + (0.4 + k) * k_i)
				splat(at, (0.22 + 0.4 * k) * (0.6 + 0.4 * k_i), k, v)
				if probe: print("BLOOD hit i=%d hit=%.1f bleed=%.2f" % [i, hit, _bleed[i]])

		if _bleed[i] > 0.05 and hs > 0.5:
			if _last[i] == null:
				_last[i] = at
				_slid[i] = 0.0
				continue
			var last: Vector3 = _last[i]
			var ln := Vector2(at.x - last.x, at.z - last.z).length()
			if ln < 0.1: continue
			if ln > 1.2:
				_last[i] = at
				continue
			# it starts as a faint narrow trace and builds up over the first ~metre of the slide
			_slid[i] += ln
			var ramp := smoothstep(0.0, 1.0, _slid[i])
			smear(last, at, clampf(r * 1.5, 0.07, 0.2) * (0.35 + 0.65 * ramp), minf(1.0, _bleed[i]) * (0.12 + 0.88 * ramp))
			_bleed[i] = maxf(0.0, _bleed[i] - ln * 0.09)   # ~10 m of smear from a full bleed
			_last[i] = at
		elif hs < 0.2:
			_last[i] = null

## fatal crash: wait until the body lies still, then start the pools (chest + each stump)
var _pools_started := false
func _check_rest(pts: Array, prv: Array, h: float) -> void:
	var pe: Vector3 = pts[2]
	var v := pe.distance_to(prv[2]) / maxf(h, 1e-4)
	var dt := get_process_delta_time()
	_rest_t = _rest_t + dt if v < 0.35 else 0.0
	if _rest_t < 0.6: return
	_pools_started = true
	var c: Vector3 = ((pts[1] as Vector3) + (pts[2] as Vector3)) * 0.5
	_add_pool(c, POOL_R * (0.85 + randf() * 0.3))
	for w in _wounds:
		_add_pool(pts[w.a], POOL_R * 0.6)
	if probe: print("BLOOD pool start at=%s pools=%d" % [c, _pools.size()])

func _add_pool(at: Vector3, r: float) -> void:
	if terrain.surface(at.x, at.z) == 2: return   # in water: it washes away
	var pl = POOL.new(terrain, at, r, POOL_T)
	add_child(pl)
	_pools.append(pl)
	_all_pools.append(pl)
	while _all_pools.size() > POOL_MAX:
		(_all_pools.pop_front() as Node).queue_free()

## tests (BMX_SPIN_PROBE): how fast / how far the torso turns while crashed (per game second)
var _spin_probe := OS.get_environment("BMX_SPIN_PROBE") != ""
var _sp_last = null
var spin_total := 0.0
var spin_max := 0.0
var _sp_t := 0.0
func _probe_spin(pts: Array) -> void:
	var u: Vector3 = ((pts[1] as Vector3) - (pts[2] as Vector3)).normalized()
	var sx: Vector3 = ((pts[6] as Vector3) - (pts[3] as Vector3))
	sx = (sx - u * sx.dot(u)).normalized()
	var bs := Basis(sx, u, sx.cross(u)).orthonormalized()
	var dt := get_process_delta_time()   # scaled by Engine.time_scale = game time
	_sp_t += dt
	if _sp_last != null and dt > 0.0:
		var ang: float = Quaternion((_sp_last as Basis).inverse() * bs).get_angle()
		spin_total += ang
		spin_max = maxf(spin_max, ang / dt)
		if Engine.get_process_frames() % 10 == 0: print("SPIN t=%.2f w=%.1f turns=%.2f ts=%.2f" % [_sp_t, ang / dt, spin_total / TAU, Engine.time_scale])
	_sp_last = bs

## tear the limb off at joint a: free it in the ragdoll, throw it on, cap both ends, start the stump spurting
func _sever(a: int, pts: Array, v: Vector3) -> void:
	if ragdoll == null: return
	var kick := Vector3(v.x * 0.3, 1.5 + randf() * 2.0, v.z * 0.3) + Vector3(randf() - 0.5, 0, randf() - 0.5) * 2.5
	var root: int = ragdoll.sever(a, kick)
	if root < 0: return
	_severed += 1
	_fatal = true
	var w := {a = a, root = root, t = JET_T, ph = randf(), acc = 0.0, acc2 = 0.0, body = _cap(), end = _cap(), bone_b = _bone(_stub_m()), bone_e = _bone(_stub_m())}
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

## break the bone at joint j (elbow / knee): the ragdoll lets it flop (thrown the wrong way), a crunch,
## a bone end sticking out of a bleeding wound
func _break(j: int, pts: Array, v: Vector3) -> void:
	if ragdoll == null: return
	var pj: Vector3 = pts[j]
	var pc: Vector3 = pts[ragdoll.LIMB_NEXT[j]]
	var pp: Vector3 = pts[BREAK_PARENT[j]]
	# the wrong way: push the lower bone out past straight (away from where it normally folds)
	var mid := (pp + pc) * 0.5
	var outw := (pj - mid)
	outw = outw.normalized() if outw.length() > 1e-3 else (pc - pp).cross(Vector3.UP).normalized()
	var kick := -outw * (2.5 + randf() * 1.5) + Vector3(0, 0.5, 0)
	if not ragdoll.break_joint(j, kick): return
	_broken += 1
	_bleed[j] = maxf(_bleed[j], 1.4)
	splat(Vector3(pj.x, 0, pj.z), 0.3, 0.9, v)
	_fractures.append({j = j, bone = _bone(_bone_m()), ring = _ring()})
	_play_crunch(pj)
	if probe: print("BLOOD break joint=%d v=%.1f" % [j, v.length()])

## each frame: the bone end sticks out of the outside of the bend, a dark wound round where it comes out
func _place_fractures(pts: Array) -> void:
	for fr in _fractures:
		var j: int = fr.j
		var pj: Vector3 = pts[j]
		var a: Vector3 = ((pts[BREAK_PARENT[j]] as Vector3) - pj).normalized()
		var b: Vector3 = ((pts[ragdoll.LIMB_NEXT[j]] as Vector3) - pj).normalized()
		var d := -(a + b)
		if d.length() < 0.15: d = a.cross(Vector3.UP)
		if d.length() < 0.05: d = a.cross(Vector3.RIGHT)
		d = d.normalized()
		# tilt it a little along the upper bone (a splintered end, not a peg)
		var dir := (d + a * 0.35).normalized()
		var r: float = ragdoll.rad[j] if j < ragdoll.rad.size() else 0.045
		var bs := 3.0 if OS.get_environment("BMX_BONE_BIG") != "" else 1.0   # tests: see where it is
		(fr.bone as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3.ONE * bs), pj + dir * (r * 0.3 + 0.065 * bs))
		(fr.ring as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), pj + dir * r * 0.85)

func _bone_m() -> Mesh:
	if _bone_mesh == null:
		_bone_mesh = CylinderMesh.new()
		_bone_mesh.top_radius = 0.006      # the splintered tip
		_bone_mesh.bottom_radius = 0.016
		_bone_mesh.height = 0.13
		_bone_mesh.radial_segments = 7
		_bone_mesh.rings = 1
		_bone_mesh.material = _bone_mat()
	return _bone_mesh

func _stub_m() -> Mesh:
	if _stub_mesh == null:
		_stub_mesh = CylinderMesh.new()
		_stub_mesh.top_radius = 0.009
		_stub_mesh.bottom_radius = 0.014
		_stub_mesh.height = 0.07
		_stub_mesh.radial_segments = 7
		_stub_mesh.rings = 1
		_stub_mesh.material = _bone_mat()
	return _stub_mesh

var _bmat: StandardMaterial3D
func _bone_mat() -> StandardMaterial3D:
	if _bmat == null:
		_bmat = StandardMaterial3D.new()
		_bmat.albedo_color = Color(0.86, 0.8, 0.68)    # bone: off-white, a little yellow
		_bmat.roughness = 0.45
		# blood-stained toward the base: a vertex-less trick, a red rim light from the wound
		_bmat.rim_enabled = true
		_bmat.rim = 0.3
		_bmat.rim_tint = 0.8
	return _bmat

func _bone(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _ring() -> MeshInstance3D:
	if _ring_mesh == null:
		_ring_mesh = SphereMesh.new()
		_ring_mesh.radius = 0.034
		_ring_mesh.height = 0.024
		_ring_mesh.radial_segments = 10
		_ring_mesh.rings = 4
		_ring_mesh.material = _stump_mesh.material
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	add_child(mi)
	return mi

## a bone crunch: a few sharp cracks + a dull thud, made once
func _play_crunch(at: Vector3) -> void:
	if _crunch == null:
		var rate := 44100
		var n := int(rate * 0.32)
		var data := PackedByteArray()
		data.resize(n * 2)
		var cracks := [0.0, 0.011, 0.024, 0.041, 0.07]
		var lp := 0.0
		var prev := 0.0
		for i in n:
			var t := float(i) / rate
			var x := 0.0
			for tk in cracks:
				if t >= tk:
					var e: float = exp(-(t - tk) * 700.0)
					x += (randf() * 2.0 - 1.0) * e * (1.0 if tk == 0.0 else 0.7)
			var hp := x - prev           # crisp: high-passed cracks
			prev = x
			lp += ((randf() * 2.0 - 1.0) - lp) * 0.08   # gritty low crunch
			var thud := sin(TAU * 68.0 * t) * exp(-t * 22.0) * 0.55 + lp * exp(-t * 30.0) * 0.6
			var y := clampf(hp * 0.8 + thud, -1.0, 1.0)
			data.encode_s16(i * 2, int(y * 30000.0))
		_crunch = AudioStreamWAV.new()
		_crunch.format = AudioStreamWAV.FORMAT_16_BITS
		_crunch.mix_rate = rate
		_crunch.data = data
	var pl := AudioStreamPlayer3D.new()
	pl.stream = _crunch
	pl.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	pl.unit_size = 8.0
	pl.pitch_scale = randf_range(0.85, 1.12)
	add_child(pl)
	pl.global_position = at
	pl.play()
	pl.finished.connect(pl.queue_free)

## blood on the ground at (x, z): 0..1 (pools: their depth, splats: inside their stain)
func blood_at(x: float, z: float) -> float:
	var b := 0.0
	for pl in _all_pools:
		if is_instance_valid(pl): b = maxf(b, clampf(pl.depth_at(x, z) / 0.002, 0.0, 1.0))
	if b >= 1.0: return b
	for d in _decals:
		if not is_instance_valid(d): continue
		var dp: Vector3 = (d as Node3D).global_position
		var r: float = (d as Decal).size.x * 0.22
		var dx := x - dp.x
		var dz := z - dp.z
		if dx * dx + dz * dz < r * r: b = maxf(b, 0.8)
	return b

## the colour a tyre prints: after rolling through blood, red, fading over ~10 m
func tyre_color(wheel: int, contact: Vector3, base: Color) -> Color:
	if not enabled: return base
	var last = _tyre_last[wheel]
	var moved := 0.0 if last == null else contact.distance_to(last)
	_tyre_last[wheel] = contact
	_tyre_blood[wheel] *= exp(-moved / 10.0)
	if _all_pools.size() > 0 or _decals.size() > 0:
		var b := blood_at(contact.x, contact.z)
		if b > 0.2:
			if probe and _tyre_blood[wheel] < 0.2: print("BLOOD tyre %d rolled through blood (%.2f)" % [wheel, b])
			_tyre_blood[wheel] = maxf(_tyre_blood[wheel], b)
	var k: float = clampf(_tyre_blood[wheel], 0.0, 1.0)
	if k < 0.01: return base
	return base.lerp(Color(0.55, 0.02, 0.015), minf(1.0, k * 1.2))

func _cap() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _stump_mesh
	add_child(m)
	return m

## per frame for each torn-off limb: the caps follow both ends, the stump pumps an arterial jet
func _bleed_wounds(pts: Array, prv: Array, h: float, dt: float) -> void:
	for w in _wounds:
		var a: int = w.a
		var pa: Vector3 = pts[a]
		var out: Vector3 = (pa - (pts[CUT_PARENT[a]] as Vector3)).normalized()
		(w.body as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, out)), pa + out * 0.03)
		(w.bone_b as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, out)), pa + out * 0.05)
		var r: int = w.root
		if r < pts.size():
			var pr: Vector3 = pts[r]
			var b: int = ragdoll.LIMB_NEXT[a]
			var into: Vector3 = (pr - (pts[b] as Vector3)).normalized()
			(w.end as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, into)), pr)
			(w.bone_e as MeshInstance3D).global_transform = Transform3D(Basis(Quaternion(Vector3.UP, into)), pr + into * 0.025)
		if w.t <= 0.0: continue
		w.t -= dt
		w.ph += dt
		# the heartbeat: a sharp surge each beat (systole) over a steady flow, the whole jet weakening
		# as the blood runs out; the jet wobbles a little round the limb's axis
		var f := fposmod(float(w.ph) * HEART_HZ, 1.0)
		var beat := 0.25 + 0.75 * exp(-pow((f - 0.12) / 0.1, 2.0))
		var left := pow(clampf(float(w.t) / JET_T, 0.0, 1.0), 0.7)
		var press := beat * left
		var va: Vector3 = (pa - (prv[a] as Vector3)) / maxf(h, 1e-4) if a < prv.size() else Vector3.ZERO
		var wob := Vector3(sin(float(w.ph) * 5.3), cos(float(w.ph) * 4.1), sin(float(w.ph) * 3.7)) * 0.12
		# a spurt arcs up and out (lying on the ground the stump would only squirt into the dirt)
		var flat := Vector3(out.x, 0, out.z)
		if flat.length() < 0.2: flat = Vector3(randf() - 0.5, 0, randf() - 0.5)
		var dir := (flat.normalized() * 0.75 + Vector3.UP * (0.55 + maxf(out.y, 0.0)) + wob).normalized()
		var n := float(w.acc) + JET_RATE * (0.35 + 0.65 * press) * left * dt
		var cnt := int(n)
		w.acc = n - cnt
		for j in cnt:
			var sp := JET_SPEED * (0.3 + 0.4 * left + 0.7 * press) * (0.95 + randf() * 0.1)
			_jet_emit(pa + out * 0.04 + Vector3(0, 0.03, 0), dir * sp + va * 0.8, 0.010 + 0.007 * press, dt * float(j) / float(cnt))
		# the torn-off piece pours out of its end: no pump, it runs out and dribbles
		if r < pts.size():
			var pr: Vector3 = pts[r]
			var into: Vector3 = (pr - (pts[ragdoll.LIMB_NEXT[a]] as Vector3)).normalized()
			var vr: Vector3 = (pr - (prv[r] as Vector3)) / maxf(h, 1e-4) if r < prv.size() else Vector3.ZERO
			var m := float(w.acc2) + JET_RATE * 0.3 * left * dt
			var c2 := int(m)
			w.acc2 = m - c2
			for j in c2:
				var jit := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.15
				_jet_emit(pr + into * 0.03, into * (0.5 + 0.6 * left) + jit + vr * 0.8, 0.008, dt * float(j) / float(c2))
		_bleed[a] = maxf(_bleed[a], 1.0)

func crash_end() -> void:
	_sever_ready = false
	for pl in _pools: pl.growing = false   # the pools stay where they are, they just stop spreading
	_pools.clear()
	_pools_started = false
	_fatal = false
	for w in _wounds:
		(w.body as Node).queue_free()
		(w.end as Node).queue_free()
		(w.bone_b as Node).queue_free()
		(w.bone_e as Node).queue_free()
	_wounds.clear()
	for fr in _fractures:
		(fr.bone as Node).queue_free()
		(fr.ring as Node).queue_free()
	_fractures.clear()
	_break_ready = false
	_air.resize(0)
	_bleed.fill(0.0)
	if _spin_probe: print("SPINEND turns=%.2f wmax=%.1f" % [spin_total / TAU, spin_max])
	_sp_last = null; spin_total = 0.0; spin_max = 0.0; _sp_t = 0.0
	if probe: print("BLOOD end laid=%d smears=%d severed=%d jet_drops=%d" % [laid, smears, _severed, jet_drops])
	if ragdoll != null and OS.get_environment("BMX_RAGDOLL_PROBE") != "": print("EJECT rise=%.2f vup=%.1f" % [ragdoll.probe_rise, ragdoll.probe_vup])

## respawn: everything laid so far fades away over WIPE seconds (the shader: born before wipe_t)
func clear() -> void:
	mat.set_shader_parameter("wipe_t", _t)
	mat.set_shader_parameter("wipe_len", WIPE)
	# splat decals fade with it, then go
	for d in _decals:
		if not is_instance_valid(d): continue
		var tw := (d as Decal).create_tween()
		var c: Color = d.modulate
		tw.tween_property(d, "modulate", Color(c.r, c.g, c.b, 0.0), WIPE)
		tw.tween_callback((d as Node).queue_free)
	_decals.clear()
	# pools fade with it, then go
	for pl in _all_pools:
		if not is_instance_valid(pl): continue
		pl.wipe(_t, WIPE)
		get_tree().create_timer(WIPE + 0.2).timeout.connect((pl as Node).queue_free)
	_all_pools.clear()
	_pools.clear()
