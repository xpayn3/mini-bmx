class_name BikeRig
extends Node3D
## The drawn bike: root (position + heading) > pitch > lean > model (+ rider).
## Loads the bike .glb, finds the moving parts, splits the pedals off the crank so they stay level,
## measures the grips and saddle for the rider, and poses everything from BikePhysics each frame.

var pitch_g := Node3D.new()
var lean_g := Node3D.new()
var model: Node3D
var extras: Dictionary = {}
var steer_n: Node3D
var wheel_f: Node3D
var wheel_r: Node3D
var crank_n: Node3D
var steer_axis := Vector3(-0.2546, 0.967, 0).normalized()
var pedal_pivots: Array[Node3D] = []
var pedal_a0 := [0.0, 0.0]
var grip_l := Vector3.ZERO
var grip_r := Vector3.ZERO
var seat = null
var susp = null
var rotors: Array = []
# tailwhip: the frame turns round the head tube (axis + a point on it, in fit_g space); the bars stay put
var model_t0 := Transform3D.IDENTITY
var whip_axis := Vector3.UP
var whip_piv := Vector3.ZERO
var whip_w := 0.0

func _init() -> void:
	name = "BikeRig"
	add_child(pitch_g)
	pitch_g.add_child(lean_g)

var fit_g := Node3D.new()   # lifts / tilts the model when the wheels are bigger or smaller than stock
var wheel_rf := 0.374
var wheel_rr := 0.355

## build: a BikeBuild dictionary (paint, logos, wheels, suspension) or {} for the stock bike
func load_bike(cfg: Dictionary, build: Dictionary = {}) -> void:
	var scene: Node3D = load(cfg.file).instantiate()
	model = scene.find_child(cfg.root, true, false)
	model.get_parent().remove_child(model)
	scene.free()
	lean_g.add_child(fit_g)
	fit_g.add_child(model)
	extras = model.get_meta("extras", {}).duplicate(true)
	if extras.has("steerAxis"):
		var a: Array = extras.steerAxis
		steer_axis = Vector3(a[0], a[1], a[2]).normalized()
	steer_n = model.find_child("steer", true, false)
	wheel_f = model.find_child("wheel_front", true, false)
	wheel_r = model.find_child("wheel_rear", true, false)
	crank_n = model.find_child("crank", true, false)
	wheel_rf = float(extras.get("wheelRadius", 0.261)); wheel_rr = float(extras.get("wheelRadiusRear", wheel_rf))
	model_t0 = model.transform
	var chain := Transform3D.IDENTITY   # steer node's parent -> model space
	var n: Node = steer_n.get_parent()
	while n != null and n != model:
		chain = (n as Node3D).transform * chain
		n = n.get_parent()
	whip_axis = (model_t0.basis * chain.basis * steer_axis).normalized()
	whip_piv = model_t0 * (chain * steer_n.position)
	_materials(cfg)
	_grips()
	_pedals()
	_saddle()
	var decal_cfg: Dictionary = BikeDecals.DH_DECALS if cfg.get("decals", false) else {}
	if not build.is_empty():
		var mods := BikeBuild.ride_mods(build)
		_swap_wheels(build, mods)
		if extras.has("suspension"):
			extras.suspension.fork.travel = mods.fork_travel
			extras.suspension.rear.travel = mods.shock_travel
		BikeBuild.apply_paint(model, build)
		decal_cfg = BikeBuild.decal_config(build)
	if extras.has("suspension"):
		susp = Suspension.new(model, extras)
	if not decal_cfg.is_empty():
		BikeDecals.add_bike_decals(model, decal_cfg)
	if extras.has("suspension") and model.find_child("rocker", true, false):
		var r: Dictionary = extras.suspension.rear
		BikeDecals.add_pivot_bolts(model, [{"node": "rocker", "at": r.G2, "z": 0.029}, {"node": "rocker", "at": r.C2, "z": 0.029}, {"node": "rocker", "at": r.D, "z": 0.031, "r": 0.005}])

## generated wheels (size, tyres, rims, spokes, hubs, cassette); the brake rotors split off the stock
## wheels stay. The frame is lifted / tilted so the new tyres sit on the ground.
func _swap_wheels(build: Dictionary, mods: Dictionary) -> void:
	var rf0 := wheel_rf
	var rr0 := wheel_rr
	if ResourceLoader.exists("res://scripts/bike/wheel_gen.gd"):
		var WG = load("res://scripts/bike/wheel_gen.gd")
		for pair in [[wheel_f, false], [wheel_r, true]]:
			var mi := pair[0] as MeshInstance3D
			if mi == null: continue
			var spec := BikeBuild.wheel_spec(build, pair[1])
			mi.mesh = WG.build(spec)
			for i in mi.mesh.get_surface_count(): mi.set_surface_override_material(i, null)
		wheel_rf = WG.tyre_radius(BikeBuild.wheel_spec(build, false))
		wheel_rr = WG.tyre_radius(BikeBuild.wheel_spec(build, true))
	else:
		wheel_rf = mods.wheel_f; wheel_rr = mods.wheel_r
		var sf := wheel_rf / rf0
		var sr := wheel_rr / rr0
		wheel_f.scale = Vector3(sf, sf, 1); wheel_r.scale = Vector3(sr, sr, 1)
	extras.wheelRadius = wheel_rf
	extras.wheelRadiusRear = wheel_rr
	var L := float(extras.get("wheelbase", 1.0))
	var bb := float(extras.get("bbToRearAxle", 0.44))
	var df := wheel_rf - rf0
	var dr := wheel_rr - rr0
	fit_g.position.y = dr + (df - dr) * (bb / L)
	fit_g.rotation.z = atan2(df - dr, L)

static func _has_class(n: String) -> bool:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == n:
			return true
	return false

func _meshes(root: Node) -> Array:
	var out := []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out

func _surface_named(mi: MeshInstance3D, mat_name: String) -> int:
	if mi == null or mi.mesh == null:
		return -1
	for i in mi.mesh.get_surface_count():
		var m: Material = mi.mesh.surface_get_material(i)
		if m and m.resource_name == mat_name:
			return i
	return -1

func _materials(_cfg: Dictionary) -> void:
	var paint: Material = BikeFX.car_paint(null)
	for mi in _meshes(model):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(i)
			if m == null: continue
			if m.resource_name == "paint":
				mi.set_surface_override_material(i, paint)
			elif m.resource_name == "chrome" and m is BaseMaterial3D:
				var c: BaseMaterial3D = m.duplicate()
				c.metallic = maxf(c.metallic, 0.9); c.roughness = minf(c.roughness, 0.2)
				mi.set_surface_override_material(i, c)
	for w in [wheel_f, wheel_r]:
		if w is MeshInstance3D:
			var r = BikeFX.find_rotor(w)
			if r: rotors.append(r)

func _grips() -> void:
	var mi := steer_n as MeshInstance3D
	var si := _surface_named(mi, "rubber")
	if si < 0:
		grip_l = Vector3(0, 0, -0.3); grip_r = Vector3(0, 0, 0.3); return
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
	var nl := 0; var nr := 0
	for p in verts:
		if p.z > 0: grip_r += p; nr += 1
		else: grip_l += p; nl += 1
	grip_l /= maxi(nl, 1); grip_r /= maxi(nr, 1)

func _pedals() -> void:
	## the crank's plastic surface holds both pedals: cut it into a left and a right pedal, each on
	## its own pivot, counter-rotated every frame so the pedals stay level while the crank turns
	var mi := crank_n as MeshInstance3D
	var si := _surface_named(mi, "plastic")
	if si < 0:
		return
	var arr := mi.mesh.surface_get_arrays(si)
	var mat := mi.mesh.surface_get_material(si)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx.resize(pos.size())
		for i in pos.size(): idx[i] = i
	for side in [-1.0, 1.0]:
		var c := Vector3.ZERO; var n := 0
		var sel := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var zc := (pos[idx[t]].z + pos[idx[t + 1]].z + pos[idx[t + 2]].z) / 3.0
			if signf(zc) == side:
				for k in 3:
					sel.append(idx[t + k]); c += pos[idx[t + k]]; n += 1
		if n == 0: continue
		c /= n
		var p2 := PackedVector3Array(); var n2 := PackedVector3Array(); var i2 := PackedInt32Array()
		var remap := {}
		for vi in sel:
			if not remap.has(vi):
				remap[vi] = p2.size(); p2.append(pos[vi] - c); n2.append(nrm[vi] if nrm.size() > vi else Vector3.UP)
			i2.append(remap[vi])
		var a2 := []; a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = p2; a2[Mesh.ARRAY_NORMAL] = n2; a2[Mesh.ARRAY_INDEX] = i2
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		am.surface_set_material(0, mat)
		var pm := MeshInstance3D.new(); pm.mesh = am
		var pivot := Node3D.new(); pivot.position = c
		pivot.add_child(pm)
		mi.add_child(pivot)
		pedal_pivots.append(pivot)
	pedal_a0 = [atan2(pedal_pivots[0].position.y, pedal_pivots[0].position.x), atan2(pedal_pivots[1].position.y, pedal_pivots[1].position.x)] if pedal_pivots.size() == 2 else [0.0, PI]
	# remove the original pedals from the crank (they are now the two level pedals above); a hidden
	# surface could be shown again by a later material override (paint), so cut it out of the mesh
	var cm: ArrayMesh = mi.mesh.duplicate()
	cm.surface_remove(si)
	mi.mesh = cm

func _saddle() -> void:
	var mi := model.find_child("frame", true, false) as MeshInstance3D
	var si := _surface_named(mi, "plastic")
	if si < 0: return
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
	if verts.is_empty(): return
	var lo := verts[0]; var hi := verts[0]
	for p in verts:
		lo = lo.min(p); hi = hi.max(p)
	seat = {"top": hi.y, "rear": lo.x, "front": hi.x}

## grip midpoint in model space (for fitting the rider)
func grip_mid() -> Vector3:
	return (grip_l + grip_r) * 0.5 + steer_n.position

## Pose from the physics state (already interpolated by the caller).
func pose(px: float, py: float, pz: float, heading: float, pitch: float, hop_nose: float, lean: float,
		steer: float, wf: float, wr: float, crank: float, whip := 0.0) -> void:
	position = Vector3(px, py, pz)
	whip_w = whip
	if whip != 0.0:
		var b := Basis(whip_axis, whip)
		model.transform = Transform3D(b, whip_piv - b * whip_piv) * model_t0
	else:
		model.transform = model_t0
	rotation = Vector3(0, heading, 0)
	pitch_g.rotation = Vector3(0, 0, pitch + hop_nose)
	lean_g.rotation = Vector3(-lean, 0, 0)
	steer_n.quaternion = Quaternion(steer_axis, steer - whip)
	wheel_f.rotation.z = -wf
	wheel_r.rotation.z = -wr
	crank_n.rotation.z = -crank
	for p in pedal_pivots:
		p.rotation.z = crank
	if susp:
		susp.apply()

## Hands / feet in lean-node space for the rider IK.
func limb_targets() -> Dictionary:
	var to_lean := func(n: Node3D, v: Vector3) -> Vector3: return lean_g.to_local(n.to_global(v))
	var out := {"handL": to_lean.call(steer_n, grip_l), "handR": to_lean.call(steer_n, grip_r),
		"footL": Vector3.ZERO, "footR": Vector3.ZERO}
	if pedal_pivots.size() == 2:
		out.footL = lean_g.to_local(pedal_pivots[0].global_position)
		out.footR = lean_g.to_local(pedal_pivots[1].global_position)
		if whip_w != 0.0:
			# mid-whip the feet leave the pedals: keep them where the pedals would be, spread wide
			var b := Basis(whip_axis, whip_w)
			var inv := (Transform3D(b, whip_piv - b * whip_piv)).affine_inverse()
			var spread := minf(1.0, absf(wrapf(whip_w, -PI, PI)) * 3.0) * 0.12
			for k in ["footL", "footR"]:
				var pf: Vector3 = inv * fit_g.to_local(lean_g.to_global(out[k]))
				var q := lean_g.to_local(fit_g.to_global(pf))
				q.z += signf(q.z) * spread; q.y += spread * 0.5
				out[k] = q
	return out

func set_brake_heat(k: float) -> void:
	for r in rotors:
		if r.has_method("set_heat"): r.set_heat(k)
