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
var chain: BikeChain   # drawn chain + derailleur pulleys, for frames that carry "chain" in their extras
var crank_angle := 0.0

func _init() -> void:
	name = "BikeRig"
	add_child(pitch_g)
	pitch_g.add_child(lean_g)

var fit_g := Node3D.new()   # lifts / tilts the model when the wheels are bigger or smaller than stock
var wheel_rf := 0.374
var wheel_rr := 0.355
var tyre_hw := 0.03   # half the tyre's width (m): the casing is round, about as tall as it is wide

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
	var fork_id := BikeBuild.fork_glb(build)
	if fork_id != "" and not extras.get("noBarMod", false):   # frames with their own cockpit + fork keep them
		_swap_fork(fork_id, build)
	var rc := str(build.get("suspension", {}).get("rear_caliper", "stock"))
	if rc != "stock" and not extras.get("noBarMod", false) and not extras.get("noDecals", false):   # the stock frame's own rear triangle only
		_swap_rear_caliper(rc)
	_materials(cfg)
	var rotor_id := str(build.get("suspension", {}).get("rotor", "stock"))
	if rotor_id != "stock":
		_swap_rotors(rotor_id)
	_grips()
	_pedals()
	_saddle()
	var decal_cfg: Dictionary = BikeDecals.DH_DECALS if cfg.get("decals", false) else {}
	if build.is_empty() and cfg.has("tyre_build"):   # a frame without a garage build: just the tyres
		_swap_wheels(cfg.tyre_build, BikeBuild.ride_mods(cfg.tyre_build))
	if not build.is_empty():
		var mods := BikeBuild.ride_mods(build)
		_swap_wheels(build, mods)
		if extras.has("suspension"):
			extras.suspension.fork.travel = minf(float(mods.fork_travel), float(extras.suspension.fork.get("maxTravel", 9.0)) * 1.0)
			extras.suspension.rear.travel = mods.shock_travel
		BikeBuild.apply_paint(model, build)
		if build.has("bars") and not extras.get("noBarMod", false):   # a frame with its own cockpit keeps its bars
			Handlebar.apply(steer_n as MeshInstance3D, build.bars)
			_grips()   # the grips moved with the bar
		decal_cfg = BikeBuild.decal_config(build)
		if extras.get("noDecals", false):   # the slot numbers are the GLORY's: place each one on this frame from its own geometry
			var fitted := []
			for L in decal_cfg.get("labels", []):
				if L.get("bar", false):
					if not extras.get("noBarMod", false):   # the garage bars are the same mesh on the goat
						fitted.append(L)
					continue
				var F := BikeDecals.fit_label(model, L)
				if not F.is_empty():
					fitted.append(F)
			decal_cfg["labels"] = fitted
		if fork_id != "" and decal_cfg.has("labels"):   # the fork leg logo slot is cut for the stock fork
			decal_cfg.labels = (decal_cfg.labels as Array).filter(func(l): return str(l.get("mesh", "")) != "fork_lower")
	MetalFinish.apply(model)   # bare metal parts get the brushed-metal scan (paint stays as it is)
	for r in rotors:
		MetalFinish.dress_rotor(r.material)
	if extras.has("suspension"):
		susp = Suspension.new(model, extras)
	if extras.has("chain"):
		chain = BikeChain.new()
		model.add_child(chain)
		chain.setup(self)
	if not decal_cfg.is_empty():
		BikeDecals.add_bike_decals(model, decal_cfg)
	if extras.has("suspension") and model.find_child("rocker", true, false):
		var r: Dictionary = extras.suspension.rear
		BikeDecals.add_pivot_bolts(model, [{"node": "rocker", "at": r.G2, "z": 0.029}, {"node": "rocker", "at": r.C2, "z": 0.029}, {"node": "rocker", "at": r.D, "z": 0.031, "r": 0.005}])

## a fork model for the stock frame (assets/forks/<id>.glb, made by tools/make_forks.py): the steer mesh loses its own crowns
## and stanchions (assets/forks/dh_cockpit.glb is the rest: stem, bars, grips), the new crowns + stanchions ride on the steer
## node, the lowers (+ caliper) replace the fork_lower mesh, and the lowers' node sits where the axle belongs (the fork's own offset).
func _swap_fork(id: String, build: Dictionary) -> void:
	var fs: Node = load("res://assets/forks/%s.glb" % id).instantiate()
	var cs: Node = load("res://assets/forks/dh_cockpit.glb").instantiate()
	var crown := fs.find_child("fork_crown", true, false) as MeshInstance3D
	var lowers := fs.find_child("fork_lower", true, false) as MeshInstance3D
	var cock := cs.find_child("steer", true, false) as MeshInstance3D
	var fl := model.find_child("fork_lower", true, false) as MeshInstance3D
	if crown and lowers and cock and fl and steer_n is MeshInstance3D:
		var fnode := fs.find_child("fork", true, false)   # the glb's root node carries the placement (extras)
		var fx: Dictionary = fnode.get_meta("extras", {}) if fnode and fnode.has_meta("extras") else {}
		(steer_n as MeshInstance3D).mesh = cock.mesh
		crown.get_parent().remove_child(crown)
		crown.name = "fork_crown"
		crown.transform = Transform3D.IDENTITY
		steer_n.add_child(crown)
		fl.mesh = lowers.mesh
		var ax: Array = fx.get("axle", [])
		if ax.size() == 2:
			var old := fl.position
			fl.position = Vector3(float(ax[0]), float(ax[1]), 0.0)
			extras.wheelbase = float(extras.get("wheelbase", 1.25)) + (fl.position.x - old.x)   # the axle moved with the fork's offset
		if extras.has("suspension"):   # the lowers stop at the crown: never more travel than fits
			var f: Dictionary = extras.suspension.fork
			f.maxTravel = float(fx.get("travel", 0.18))
	fs.free()
	cs.free()

## a rotor model (assets/forks/rotor_<id>.glb): the "rotor" meshes the wheels split off keep their heat-glow material and get the model's disc
func _swap_rotors(id: String) -> void:
	if not ResourceLoader.exists("res://assets/forks/rotor_%s.glb" % id):
		return
	var rs: Node = load("res://assets/forks/rotor_%s.glb" % id).instantiate()
	for r in rotors:
		var mi: MeshInstance3D = r.mesh_instance
		if mi == null or mi.get_parent() == null:
			continue
		var front: bool = mi.get_parent() == wheel_f
		var src := rs.find_child("rotor_front" if front else "rotor_rear", true, false) as MeshInstance3D
		if src == null or src.mesh == null:
			continue
		var m: ArrayMesh = src.mesh.duplicate()
		for i in m.get_surface_count():
			m.surface_set_material(i, r.material)
		mi.mesh = m
	rs.free()

## a rear brake caliper for the stock frame: the seatstay mesh loses its own caliper (assets/forks/dh_seatstay.glb) and the model's
## caliper (assets/forks/caliper_<id>.glb, already turned to the stock one's place on the rotor, relative to the axle) rides on the seatstay
func _swap_rear_caliper(id: String) -> void:
	var ss := model.find_child("seatstay", true, false) as MeshInstance3D
	if ss == null or wheel_r == null or not ResourceLoader.exists("res://assets/forks/caliper_%s.glb" % id):
		return
	var a: Node = load("res://assets/forks/dh_seatstay.glb").instantiate()
	var c: Node = load("res://assets/forks/caliper_%s.glb" % id).instantiate()
	var nss := a.find_child("seatstay", true, false) as MeshInstance3D
	var cal := c.find_child("caliper", true, false) as MeshInstance3D
	if nss and cal:
		ss.mesh = nss.mesh
		cal.get_parent().remove_child(cal)
		cal.name = "rear_caliper"
		cal.position = wheel_r.position   # relative to the axle; the wheel node sits on the seatstay
		ss.add_child(cal)
	a.free()
	c.free()

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
	tyre_hw = float(build.wheels.get("tyre_w", 2.4)) * 0.0254 * 0.5
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
	grip_l = Vector3.ZERO; grip_r = Vector3.ZERO
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
		steer: float, wf: float, wr: float, crank: float) -> void:
	position = Vector3(px, py, pz)
	rotation = Vector3(0, heading, 0)
	pitch_g.rotation = Vector3(0, 0, pitch + hop_nose)
	lean_g.rotation = Vector3(-lean, 0, 0)
	steer_n.quaternion = Quaternion(steer_axis, steer)
	wheel_f.rotation.z = -wf
	wheel_r.rotation.z = -wr
	crank_n.rotation.z = -crank
	crank_angle = crank
	for p in pedal_pivots:
		p.rotation.z = crank
	if susp:
		susp.apply()

## How deep the tyre on `wheel` (radius R) sits inside the ground (m, > 0 = inside), the ground given as
## top(x, z) -> height. Samples round the tyre (the lower half when it stands, all the way round when it
## lies over) and across the round casing.
func tyre_depth(wheel: Node3D, R: float, top: Callable) -> float:
	var xf := wheel.global_transform
	var c := xf.origin
	var ax := xf.basis.z.normalized()
	var down := Vector3.DOWN - ax * ax.dot(Vector3.DOWN)
	var dl := down.length()
	var d0 := down / dl if dl > 1e-3 else xf.basis.x.normalized()
	var side := ax.cross(d0)
	var full := dl < 0.6
	var n := 16 if full else 11
	var hw := tyre_hw
	var worst := -INF
	for i in n:
		var a := TAU * i / n if full else -1.4 + 2.8 * i / (n - 1)
		var dir := d0 * cos(a) + side * sin(a)
		for wo in [-0.8, 0.0, 0.8]:
			var off: float = wo * hw
			var r := R - hw + sqrt(hw * hw - off * off)
			var p := c + dir * r + ax * off
			worst = maxf(worst, float(top.call(p.x, p.z)) - p.y)
	return worst

## Riding: put each wheel on the ground with the suspension (the frame stays where the physics put the
## body): the fork slides and the swingarm swings until the tyre just touches, within the travel; topped
## out when the ground is further away (in the air). What the travel can't take, unclip_tyres() lifts.
func fit_wheels(top: Callable) -> void:
	if susp == null or not susp.wheels_follow:
		return
	var mb := model.global_transform.basis
	var up_f: float = maxf(0.4, (mb * susp.axis).normalized().y)   # world rise per metre of fork travel
	var up_r: float = maxf(0.4, mb.y.normalized().y)                 # ... per metre of rear axle rise
	for it in 3:
		var dF := tyre_depth(wheel_f, wheel_rf, top)
		var dR := tyre_depth(wheel_r, wheel_rr, top)
		var nF := clampf(susp.xF + dF / up_f, susp.F["min"], susp.F["max"]) if susp.has_f else 0.0
		var nR := clampf(susp.xR + dR / up_r, susp.R["min"], susp.R["max"]) if susp.has_r else 0.0
		if absf(nF - susp.xF) < 5e-4 and absf(nR - susp.xR) < 5e-4:
			break
		susp.xF = nF; susp.xR = nR
		susp.apply()

## Lift / tilt the drawn bike (not the physics) until no tyre is inside the ground, leaving `gap` m.
## Returns how deep the deepest tyre was before (for probes).
func unclip_tyres(top: Callable, gap: float = 0.003) -> float:
	var first := -INF
	for it in 5:
		var pf := tyre_depth(wheel_f, wheel_rf, top) + gap
		var pr := tyre_depth(wheel_r, wheel_rr, top) + gap
		if it == 0: first = maxf(pf, pr) - gap
		if pf <= 1e-4 and pr <= 1e-4:
			break
		pf = maxf(pf, 0.0); pr = maxf(pr, 0.0)
		# rotate about the pitch pivot (the rig's origin) + lift, so each wheel rises by what it needs
		var fw := global_transform.basis.x.normalized()
		var aF := (wheel_f.global_position - global_position).dot(fw)
		var aR := (wheel_r.global_position - global_position).dot(fw)
		var dth := 0.0
		if aF - aR > 0.3 and it < 4:
			dth = clampf((pf - pr) / (aF - aR), -0.25, 0.25)
		var dy := maxf(pf - aF * dth, pr - aR * dth)
		pitch_g.rotation.z += dth
		position.y += dy
	return first

## Hands / feet in lean-node space for the rider IK.
func limb_targets() -> Dictionary:
	var to_lean := func(n: Node3D, v: Vector3) -> Vector3: return lean_g.to_local(n.to_global(v))
	var out := {"handL": to_lean.call(steer_n, grip_l), "handR": to_lean.call(steer_n, grip_r),
		"footL": Vector3.ZERO, "footR": Vector3.ZERO}
	if pedal_pivots.size() == 2:
		out.footL = lean_g.to_local(pedal_pivots[0].global_position)
		out.footR = lean_g.to_local(pedal_pivots[1].global_position)
	return out

func set_brake_heat(k: float) -> void:
	for r in rotors:
		if r.has_method("set_heat"): r.set_heat(k)
