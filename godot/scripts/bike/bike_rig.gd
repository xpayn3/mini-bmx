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
var action_cam: Node3D = null   # the bike's action cam (build.camera.mount: bars / fork); its "Body/Lens" is the Bike cam view
var cam_mount := "none"
var crank_angle := 0.0

func _init() -> void:
	name = "BikeRig"
	add_child(pitch_g)
	pitch_g.add_child(lean_g)

var fit_g := Node3D.new()   # lifts / tilts the model when the wheels are bigger or smaller than stock
var wheel_rf := 0.374
var wheel_rr := 0.355
const TYRE_ACROSS := [-0.8, 0.0, 0.8]   # where across the casing tyre_depth samples (x tyre_hw); one array, not one per call
var tyre_hw := 0.03   # half the tyre's width (m): the casing is round, about as tall as it is wide

static var _fit_cache := {}   # sticker fits on noDecals frames (BikeDecals.fit_label is slow in GDScript)

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
	var lev := str(build.get("bars", {}).get("levers", "stock"))
	if lev != "stock" and not extras.get("noBarMod", false) and not extras.get("noDecals", false):   # the stock frame: brake levers from a model
		_swap_levers(lev, fork_id != "")
	if not extras.get("noBarMod", false) and not extras.get("noDecals", false):   # the stock frame: saddle model + seat post
		_swap_seat(build)
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
				var fkey := str(cfg.file) + "|" + fork_id + "|" + var_to_str(L)   # same frame + label = same fit (the garage rebuilds per click)
				if not _fit_cache.has(fkey):
					_fit_cache[fkey] = BikeDecals.fit_label(model, L)
				var F: Dictionary = (_fit_cache[fkey] as Dictionary).duplicate(true)
				if not F.is_empty():
					fitted.append(F)
			decal_cfg["labels"] = fitted
		if fork_id != "" and decal_cfg.has("labels"):   # the fork leg logo slot is cut for the stock fork
			decal_cfg.labels = (decal_cfg.labels as Array).filter(func(l): return str(l.get("mesh", "")) != "fork_lower")
	if extras.has("suspension"):
		susp = Suspension.new(model, extras)
	if extras.has("chain"):
		chain = BikeChain.new()
		model.add_child(chain)
		chain.setup(self)
	if not decal_cfg.is_empty():
		BikeDecals.add_bike_decals(model, decal_cfg)
	mount_cam(str(build.get("camera", {}).get("mount", "none")))
	if extras.has("suspension") and model.find_child("rocker", true, false):
		var r: Dictionary = extras.suspension.rear
		BikeDecals.add_pivot_bolts(model, [{"node": "rocker", "at": r.G2, "z": 0.029}, {"node": "rocker", "at": r.C2, "z": 0.029}, {"node": "rocker", "at": r.D, "z": 0.031, "r": 0.005}])

## a fork model for the stock frame (assets/forks/<id>.glb, made by tools/make_forks.py): the steer mesh loses its own crowns
## and stanchions (assets/forks/dh_cockpit.glb is the rest: stem, bars, grips), the new crowns + stanchions ride on the steer
## node, the lowers (+ caliper) replace the fork_lower mesh, and the lowers' node sits where the axle belongs (the fork's own offset).
func _swap_fork(id: String, build: Dictionary) -> void:
	var fs: Node = load("res://assets/forks/%s.glb" % id).instantiate()
	var nl := str(build.get("bars", {}).get("levers", "stock")) != "stock"   # levers from a model: the cockpit comes without dh's own
	var cs: Node = load("res://assets/forks/dh_cockpit_nl.glb" if nl else "res://assets/forks/dh_cockpit.glb").instantiate()
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

## brake levers from a model on the stock frame (assets/forks/levers_<id>.glb, made by tools/make_forks.py): the steer mesh loses dh's own
## levers (forks/dh_steer_nl.glb is the whole steer mesh without them; when a fork model is picked _swap_fork already used the cockpit
## without them) and gets the model's as more surfaces of the same mesh, so Handlebar.apply moves them with the bar.
func _swap_levers(id: String, fork_swapped: bool) -> void:
	var path := "res://assets/forks/levers_%s.glb" % id
	if not (steer_n is MeshInstance3D) or not ResourceLoader.exists(path): return
	var ls: Node = load(path).instantiate()
	var lm := _first_mesh(ls)
	var base: Mesh = (steer_n as MeshInstance3D).mesh
	var bs: Node = null
	if not fork_swapped:
		bs = load("res://assets/forks/dh_steer_nl.glb").instantiate()
		var bm := _first_mesh(bs)
		if bm: base = bm.mesh
	if lm and base:
		var mats := {}
		for i in (steer_n as MeshInstance3D).mesh.get_surface_count():
			var m := (steer_n as MeshInstance3D).mesh.surface_get_material(i)
			if m: mats[m.resource_name] = m
		var am := ArrayMesh.new()
		var add := func(src: Mesh, i: int) -> void:
			var m := src.surface_get_material(i)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
			am.surface_set_material(am.get_surface_count() - 1, mats.get(m.resource_name, m) if m else null)
		for i in base.get_surface_count(): add.call(base, i)
		for i in lm.mesh.get_surface_count(): add.call(lm.mesh, i)
		(steer_n as MeshInstance3D).mesh = am
	ls.free()
	if bs: bs.free()


## a saddle model and / or a dropper seat post on the stock frame: the frame mesh loses its saddle (assets/seats/dh_frame.glb), the chosen saddle
## (seats/saddle_dh.glb = the stock one, parts/<id>_saddle.glb) is added as more surfaces of the SAME mesh (so the rider's seat, the paint
## by surface name and the decals keep working) at the stock place, raised along the seat tube by the dropper's height, with a post tube
## from the seat tube to the clamp.
func _swap_seat(build: Dictionary) -> void:
	var S: Dictionary = build.get("seat", {})
	var sid := str(S.get("model", "stock"))
	var dropper := str(S.get("post", "stock")) == "dropper"
	if sid == "stock" and not dropper:
		return
	var fmi := model.find_child("frame", true, false) as MeshInstance3D
	var path := "res://assets/seats/saddle_%s.glb" % ("dh" if sid == "stock" else sid)
	if fmi == null or fmi.mesh == null or not ResourceLoader.exists(path):
		return
	var fs: Node = load("res://assets/seats/dh_frame.glb").instantiate()
	var ss: Node = load(path).instantiate()
	var nf := fs.find_child("frame", true, false) as MeshInstance3D
	var sm := _first_mesh(ss)   # (the glb root and its mesh node share a name: find the mesh itself)
	var rootn := fs.find_child("seat", true, false)
	if nf and sm and rootn:
		var ex: Dictionary = rootn.get_meta("extras", {})
		var org := Vector2(float(ex.stockOrigin[0]), float(ex.stockOrigin[1]))
		var top := Vector2(float(ex.postTop[0]), float(ex.postTop[1]))
		var dir := Vector2(float(ex.postDir[0]), float(ex.postDir[1])).normalized()
		var h := float(S.get("post_h", 0.0)) if dropper else 0.0
		var clamp := org + dir * h
		var mats := {}
		for i in fmi.mesh.get_surface_count():
			var m := fmi.mesh.surface_get_material(i)
			if m: mats[m.resource_name] = m
		var am := ArrayMesh.new()
		var add := func(arr: Array, nm: String, fallback: Material) -> void:
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, mats.get(nm, fallback))
		for i in nf.mesh.get_surface_count():
			var m := nf.mesh.surface_get_material(i)
			add.call(nf.mesh.surface_get_arrays(i), m.resource_name, m)
		for i in sm.mesh.get_surface_count():
			var m := sm.mesh.surface_get_material(i)
			add.call(_moved(sm.mesh.surface_get_arrays(i), Transform3D(Basis.IDENTITY, Vector3(clamp.x, clamp.y, 0.0))), m.resource_name, m)
		if dropper:   # the post: a tube from inside the seat tube up to the clamp, with a collar at the tube's top
			var ang := atan2(dir.y, dir.x) - PI * 0.5
			var bas := Basis(Vector3.BACK, ang)
			var bottom := top - dir * 0.04
			var up := clamp + dir * 0.012
			var len := bottom.distance_to(up)
			var tube := CylinderMesh.new()
			tube.top_radius = 0.0155; tube.bottom_radius = 0.0155; tube.height = len; tube.radial_segments = 16; tube.rings = 1
			var mid := (bottom + up) * 0.5
			add.call(_moved(tube.get_mesh_arrays(), Transform3D(bas, Vector3(mid.x, mid.y, 0.0))), "black", null)
			var collar := CylinderMesh.new()
			collar.top_radius = 0.0185; collar.bottom_radius = 0.0185; collar.height = 0.02; collar.radial_segments = 16; collar.rings = 1
			var cp := top
			add.call(_moved(collar.get_mesh_arrays(), Transform3D(bas, Vector3(cp.x, cp.y, 0.0))), "chrome", null)
		fmi.mesh = am
	fs.free()
	ss.free()


static func _first_mesh(n: Node) -> MeshInstance3D:
	var l := n.find_children("*", "MeshInstance3D", true, false)
	return l[0] as MeshInstance3D if not l.is_empty() else null


## mesh arrays moved by a transform (positions + normals)
static func _moved(arr: Array, xf: Transform3D) -> Array:
	var out := arr.duplicate()
	var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX].duplicate()
	for i in P.size():
		P[i] = xf * P[i]
	out[Mesh.ARRAY_VERTEX] = P
	if arr[Mesh.ARRAY_NORMAL] != null:
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL].duplicate()
		for i in N.size():
			N[i] = xf.basis * N[i]
		out[Mesh.ARRAY_NORMAL] = N
	return out


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
	var cal := _first_mesh(c)
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

## the action cam on the bike: "bars" = a bar clamp right of the stem, camera on top looking ahead (turns
## with the steering); "fork" = a clamp on the right fork lower (the caliper is on the left), camera beside
## the leg, low over the ground (moves with the suspension). Placed from the meshes themselves, so it fits
## every frame / bar / fork model. "none" (or no such part) = no camera.
func mount_cam(kind: String) -> void:
	if action_cam and is_instance_valid(action_cam):
		action_cam.get_parent().remove_child(action_cam)
		action_cam.queue_free()
	action_cam = null
	cam_mount = "none"
	var probe := Env.s("BMX_CAMMOUNT_PROBE") != ""
	if kind == "bars" and steer_n is MeshInstance3D:
		var zc := lerpf(0.0, grip_r.z, 0.33)   # a third of the way out: clear of the stem, inside the levers
		var hint := Vector3(lerpf(grip_r.x, 0.0, 0.3), grip_r.y, zc)
		var t := _tube_at(steer_n as MeshInstance3D, Vector3(0, 0, 1), zc, hint)
		if t.is_empty(): return
		action_cam = ActionCam.build_clamp(Vector3(0, 0, 1), t.r, Vector3.UP, Vector3(0.0, t.r + 0.024, 0.0))
		action_cam.position = t.c
		steer_n.add_child(action_cam)
		if probe: print("CAMMOUNT bars c=%s r=%.4f" % [t.c, t.r])
	elif kind == "fork":
		var fl := model.find_child("fork_lower", true, false) as MeshInstance3D
		if fl == null or fl.mesh == null: return
		var A := fl.mesh.get_aabb()
		var h := A.size.y
		var lo := _leg_band(fl, A.position.y + h * 0.3)
		var hi := _leg_band(fl, A.position.y + h * 0.55)
		if probe: print("CAMMOUNT fork aabb=%s lo=%s hi=%s" % [A, lo, hi])
		if lo.is_empty() or hi.is_empty(): return
		var axis: Vector3 = (hi.c - lo.c).normalized()
		var at: Vector3 = hi.c
		var r: float = hi.r
		# camera upright on the outside of the leg, centred on the clamp height, lens ahead
		action_cam = ActionCam.build_clamp(axis, r, Vector3(0, 0, 1), Vector3(0.012, -0.03, r + 0.046))
		action_cam.position = at
		fl.add_child(action_cam)
		if probe: print("CAMMOUNT fork c=%s r=%.4f axis=%s" % [at, r, axis])
	else:
		return
	cam_mount = kind
	for mi in action_cam.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## every vertex of a mesh (all surfaces), mesh space
static func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in mi.mesh.get_surface_count():
		out.append_array(mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	return out

## a round tube crossing the plane `axis`·p = d near `hint`: {c: its centre in that plane, r: radius}, {} if none
static func _tube_at(mi: MeshInstance3D, axis: Vector3, d: float, hint: Vector3) -> Dictionary:
	var ring := PackedVector3Array()
	for p in _verts(mi):
		if absf(p.dot(axis) - d) < 0.005: ring.append(p)
	if ring.is_empty(): return {}
	var near := ring[0]
	for p in ring:
		if p.distance_to(hint) < near.distance_to(hint): near = p
	var c := Vector3.ZERO; var n := 0
	for p in ring:
		if p.distance_to(near) < 0.03: c += p; n += 1
	c /= n
	var rr := 0.0; n = 0
	for p in ring:
		if p.distance_to(c) < 0.03: rr += (p - c).length(); n += 1
	c = c - axis * (c.dot(axis) - d)
	return {"c": c, "r": clampf(rr / maxi(n, 1), 0.008, 0.03)}

## the right fork lower's cross-section at height y (fork_lower space): {c, r}, {} if there's no leg there
static func _leg_band(mi: MeshInstance3D, y: float) -> Dictionary:
	var c := Vector3.ZERO; var n := 0
	var band := PackedVector3Array()
	for p in _verts(mi):
		if absf(p.y - y) < 0.02 and p.z > 0.03:
			band.append(p); c += p; n += 1
	if n < 6: return {}
	c /= n
	var rr := 0.0
	for p in band: rr = maxf(rr, Vector2(p.x - c.x, p.z - c.z).length())
	return {"c": c, "r": clampf(rr, 0.012, 0.035)}

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
		for wo in TYRE_ACROSS:
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
