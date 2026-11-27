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

var fork_model := "dh"   # whose fork crowns are on the steer: dh's own or a fork model's glb id (_swap_fork); stems sit on its seat
var _lever_surf0 := -1   # first steer-mesh surface that belongs to model brake levers (_swap_levers), -1 = none
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
	var stem := str(build.get("bars", {}).get("stem", "stock"))
	var bar_glb := Handlebar.glb_of(build.get("bars", {}))
	if (stem != "stock" or bar_glb != "") and not extras.get("noBarMod", false) and not extras.get("noDecals", false):   # the stock frame: stem / bar from a model
		_swap_cockpit(stem, bar_glb)
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
	_pedals(str(build.get("drive", {}).get("pedals", "stock")), str(cfg.file))
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
	if cfg.get("head", null) is Dictionary and not extras.get("noBarMod", false):   # our fork on another frame's head tube
		_seat_head(cfg.head)
	MetalFinish.apply(model)   # bare metal parts get the brushed-metal scan (paint stays as it is)
	for r in rotors:
		MetalFinish.dress_rotor(r.material)
		r.build_lod()
	if extras.has("suspension"):
		susp = Suspension.new(model, extras)
	if not extras.has("chain"):
		BikeChain.adopt_stock(model, extras)   # the stock frame: its fixed chain mesh -> a drawn chain
	BikeAO.apply(model, wheel_f, wheel_r)   # baked AO in the vertex colours (before decals / cam / lights)
	_build_tyre_lods()
	if extras.has("chain") and cfg.get("chain", null) is Dictionary:   # GameState.BIKES fixes to a glb's chain data
		(extras.chain as Dictionary).merge(cfg.chain, true)
	if extras.has("chain"):
		chain = BikeChain.new()
		model.add_child(chain)
		chain.setup(self, build)
	if not decal_cfg.is_empty():
		BikeDecals.add_bike_decals(model, decal_cfg)
	mount_cam(str(build.get("camera", {}).get("mount", "none")), build.get("camera", {}))
	mount_lights(str(build.get("lights", {}).get("model", "luma")))   # builds saved before lights: a mid lamp
	if extras.has("suspension") and model.find_child("rocker", true, false):
		var r: Dictionary = extras.suspension.rear
		var bolts := BikeDecals.add_pivot_bolts(model, [{"node": "rocker", "at": r.G2, "z": 0.029}, {"node": "rocker", "at": r.C2, "z": 0.029}, {"node": "rocker", "at": r.D, "z": 0.031, "r": 0.005}])
		if not bolts.is_empty():   # 15 little pieces -> one mesh on the rocker
			_MERGE.merge(bolts[0].get_parent(), bolts)

const _MERGE := preload("res://scripts/core/mesh_merge.gd")

## dh.glb's head tube on its steering axis, from the steer node: top / bottom end (our fork's crowns sit just past them)
const HT_DH := [0.0565, -0.0418]
var head_n: Node3D   # _seat_head: the front end's parent on another frame's head tube (null = straight under the model)

## our fork on another frame (GameState.BIKES.<id>.head = that frame's head tube ends in model space, measured off its
## mesh): the whole front end (steer, fork, wheel, bars) goes under one "head" node turned to that head tube's angle with
## the upper crown on its top. Steering still turns about steer_axis in that node's space, the fork still slides along it.
## A longer head tube slides the lower crown down the stanchions (like a real crown clamp) to sit under its bottom.
func _seat_head(head: Dictionary) -> void:
	var top := Vector3(float(head.top[0]), float(head.top[1]), 0.0)
	var bot := Vector3(float(head.bottom[0]), float(head.bottom[1]), 0.0)
	var a1 := (top - bot).normalized()
	var b := Basis(Vector3(0, 0, 1), atan2(a1.y, a1.x) - atan2(steer_axis.y, steer_axis.x))
	var t0 := steer_n.position + steer_axis * float(HT_DH[0])
	var hd := Node3D.new()
	hd.name = "head"
	hd.transform = Transform3D(b, top - b * t0)
	var fl := steer_n.find_child("fork_lower", false, false) as Node3D
	var axle0 := steer_n.position + (fl.position if fl else Vector3.ZERO)
	var par := steer_n.get_parent()
	par.add_child(hd)
	par.move_child(hd, steer_n.get_index())
	steer_n.reparent(hd, false)
	head_n = hd
	extras.wheelbase = float(extras.get("wheelbase", 1.25)) + ((hd.transform * axle0).x - axle0.x)   # the front axle moved
	var drop: float = (bot - top).length() - (float(HT_DH[0]) - float(HT_DH[1]))
	if drop > 0.004:
		for mi in [steer_n, steer_n.find_child("fork_crown", false, false)]:
			if mi is MeshInstance3D and (mi as MeshInstance3D).mesh is ArrayMesh:
				_slide_crown(mi, -drop)

## the steer node at rest, in model space
func steer_rest() -> Transform3D:
	var t := Transform3D(Basis(), steer_n.position)
	return head_n.transform * t if head_n else t

func _slide_crown(mi: MeshInstance3D, d: float) -> void:
	var src: ArrayMesh = mi.mesh
	var out := ArrayMesh.new()
	var moved := 0
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var mat := src.surface_get_material(i)
		if not (mat and mat.resource_name == "gold"):
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for j in v.size():
				var t := v[j].dot(steer_axis)
				if t > float(HT_DH[1]) - 0.09 and t < float(HT_DH[1]) - 0.004:
					v[j] += steer_axis * d
					moved += 1
			arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_name(i, src.surface_get_name(i))
		out.surface_set_material(i, mat)
	if moved > 0:
		mi.mesh = out

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
		fork_model = id
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
		_lever_surf0 = am.get_surface_count()
		for i in lm.mesh.get_surface_count(): add.call(lm.mesh, i)
		(steer_n as MeshInstance3D).mesh = am
	ls.free()
	if bs: bs.free()

## a model's stem and / or handlebar on the stock frame (assets/forks/stem_<id>.glb, bar_<id>.glb, made by tools/make_forks.py), in one pass
## over the steer mesh (whatever fork / lever variant it is): dh's stem / bar + grips are dropped, the model's go in as more surfaces. The stem
## slides along the steering axis onto the crown in use and the bar (dh's, or the model's at its middle) rides in its clamp (shift d); the
## brake levers come along and, on a model bar, move by leverShift[side] so they sit against its grips as they sat against dh's; the brake
## hose bends: its top follows. dh's pieces are found by their triangle middles (extras), matched within 0.4 mm (imported positions are quantised).
func _swap_cockpit(stem_id: String, bar_id: String) -> void:
	if not (steer_n is MeshInstance3D): return
	var sx := _glb_extras("res://assets/forks/stem_%s.glb" % stem_id, "stemroot") if stem_id != "stock" else []
	var bx := _glb_extras("res://assets/forks/bar_%s.glb" % bar_id, "barroot") if bar_id != "" else []
	if sx.is_empty() and bx.is_empty(): return
	var slide := Vector3.ZERO
	var d := Vector3.ZERO
	var cut := {}; var mv := {}; var hose := {}; var barcut := {}; var levs := {}
	var hy := [-0.05, 0.12]
	if not sx.is_empty():
		var ex: Dictionary = sx[1]
		var ax: Array = ex.axis
		var seats: Dictionary = ex.seats
		slide = Vector3(float(ax[0]), float(ax[1]), 0.0) * (float(seats.get(fork_model, seats.dh)) - float(seats[ex.own]))   # own fork's seat -> the crown in use
		d = Vector3(float(ex.shift[0]), float(ex.shift[1]), 0.0) + slide
		cut = _mid_set(ex.cut); mv = _mid_set(ex.move); hose = _mid_set(ex.hose); hy = ex.hoseY
	var e := [Vector3.ZERO, Vector3.ZERO]   # levers' extra move on a model bar: left, right
	var bmid := Vector3.ZERO
	if not bx.is_empty():
		var ex: Dictionary = bx[1]
		barcut = _mid_set(ex.barcut); levs = _mid_set(ex.levers)
		if hose.is_empty(): hose = _mid_set(ex.hose); hy = ex.hoseY
		for k in 2:
			var a: Array = ex.leverShift[k]
			e[k] = Vector3(float(a[0]), float(a[1]), float(a[2]))
		bmid = Vector3(float(ex.dhMid[0]), float(ex.dhMid[1]), 0.0) + d
	var old: Mesh = (steer_n as MeshInstance3D).mesh
	var am := ArrayMesh.new()
	var lev0 := -1
	for si in old.get_surface_count():
		if si == _lever_surf0: lev0 = am.get_surface_count()
		var arr := old.surface_get_arrays(si)
		var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(P.size()))
		var keep := PackedInt32Array()
		var off := PackedVector3Array(); off.resize(P.size())   # each vertex's move
		var w := PackedFloat32Array(); w.resize(P.size())       # how much of it (the hose bends)
		var whole := _lever_surf0 >= 0 and si >= _lever_surf0   # model levers: on the bar
		for t in range(0, I.size(), 3):
			var m := (P[I[t]] + P[I[t + 1]] + P[I[t + 2]]) / 3.0
			if not whole and (_mid_has(cut, m) or _mid_has(barcut, m)): continue
			keep.append_array(PackedInt32Array([I[t], I[t + 1], I[t + 2]]))
			var to := Vector3.ZERO; var wt := 0.0
			if whole or _mid_has(levs, m):
				to = d + e[1 if m.z > 0.0 else 0]; wt = 1.0
			elif _mid_has(mv, m):
				to = d; wt = 1.0
			elif _mid_has(hose, m):
				to = d + e[0]; wt = -1.0
			if wt == 0.0: continue
			for k in 3:
				var vi := I[t + k]
				var wk := wt if wt > 0.0 else smoothstep(float(hy[0]), float(hy[1]), P[vi].y)
				if wk >= w[vi]:
					w[vi] = wk; off[vi] = to
		for i in P.size():
			if w[i] > 0.0: P[i] += off[i] * w[i]
		arr[Mesh.ARRAY_VERTEX] = P
		arr[Mesh.ARRAY_INDEX] = keep
		if keep.is_empty(): continue
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, old.surface_get_material(si))
	_lever_surf0 = lev0
	var mats := {}
	for i in old.get_surface_count():
		var m := old.surface_get_material(i)
		if m: mats[m.resource_name] = m
	var add := func(mesh: Mesh, at: Vector3, rename: String) -> void:
		for i in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(i)
			var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in P.size(): P[k] += at
			arr[Mesh.ARRAY_VERTEX] = P
			var m := mesh.surface_get_material(i)
			var mat: Material = mats.get(m.resource_name, m) if m else null
			if rename != "" and m and m.resource_name == "black":   # the bar tube: its own surface (carbon / paint like the stock bar's)
				mat = mat.duplicate(); mat.resource_name = rename
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, mat)
	if not sx.is_empty():
		add.call((sx[0].find_child("stem", true, false) as MeshInstance3D).mesh, slide, "")
	if not bx.is_empty():
		add.call((bx[0].find_child("bar", true, false) as MeshInstance3D).mesh, bmid, "bar")
		add.call((bx[0].find_child("grips", true, false) as MeshInstance3D).mesh, bmid, "")
	(steer_n as MeshInstance3D).mesh = am
	for x in [sx, bx]:
		if not x.is_empty(): (x[0] as Node).free()

## [instantiated glb, its root node's extras] or [] when the file / extras are missing
func _glb_extras(path: String, root_name: String) -> Array:
	if not ResourceLoader.exists(path): return []
	var n: Node = load(path).instantiate()
	var root := n if n.name == root_name else n.find_child(root_name, true, false)
	if root == null or not root.has_meta("extras"):
		n.free(); return []
	return [n, root.get_meta("extras")]

## triangle middles (flat x, y, z list) -> a 1 mm grid: each one is filed in every cell its +-0.4 mm box touches
static func _mid_set(flat: Array) -> Dictionary:
	var out := {}
	for i in range(0, flat.size(), 3):
		var p := Vector3(float(flat[i]), float(flat[i + 1]), float(flat[i + 2]))
		for dx in [-0.0004, 0.0004]:
			for dy in [-0.0004, 0.0004]:
				for dz in [-0.0004, 0.0004]:
					var k := Vector3i((p + Vector3(dx, dy, dz)) * 1000.0)
					if not out.has(k): out[k] = []
					if not (out[k] as Array).has(p): (out[k] as Array).append(p)
	return out

static func _mid_has(cells: Dictionary, m: Vector3) -> bool:
	var cell = cells.get(Vector3i(m * 1000.0))
	if cell == null: return false
	for p in cell:
		if (p as Vector3).distance_squared_to(m) < 0.0004 * 0.0004: return true
	return false


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
		var m := ArrayMesh.new()
		for i in src.mesh.get_surface_count():
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BikeFX.RotorGlow.flat_arrays(src.mesh.surface_get_arrays(i)))
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

# ---------------------------------------------------------------- tyre LODs
## Each generated wheel gets three meshes sharing its arrays: 0 = as built, 1 = no knobs (the casing alone), 2 = the casing
## thinned to a third of its triangles. ~10k triangles a tyre -> ~5k -> ~1.5k. Picked by the camera's distance (BMX_TYRE_LOD=0
## off, 1 / 2 = always that level). Drawing only: the physics and the tyre fit never read the mesh.
const TYRE_LOD1 := 5.0     # m (as seen through a 75 deg lens)
const TYRE_LOD2 := 14.0
const TYRE_LOD_HYST := 0.8
var _wlods: Array = []
var _wlod_ms := 0
var _wlod_t := 0.0
var _gen_wheels := false
var _wheel_build: Dictionary = {}

func _build_tyre_lods() -> void:
	_wlods.clear()
	var force := Env.s("BMX_TYRE_LOD")
	if force == "0" or not _gen_wheels or _wheel_build.is_empty() or not _wheel_build.has("wheels"):
		return
	for pair in [[wheel_f, false], [wheel_r, true]]:
		var mi := pair[0] as MeshInstance3D
		if mi == null or not (mi.mesh is ArrayMesh):
			continue
		var src := mi.mesh as ArrayMesh
		var si := -1
		for i in src.get_surface_count():
			if src.surface_get_name(i) == "rubber":
				si = i
		if si < 0:
			continue
		var d: Dictionary = WheelGen.tyre_dims(BikeBuild.wheel_spec(_wheel_build, pair[1]))
		var rows: int = d.rows
		var cols: int = d.cols
		var arr := src.surface_get_arrays(si)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var UV = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nc := rows * cols
		# the casing grid must be where the generator put it (it was rebuilt by the AO bake: arrays and order are kept)
		if V.size() < nc or UV == null or idx.size() < (rows - 1) * (cols - 1) * 6:
			continue
		var uv: PackedVector2Array = UV
		if uv[0].distance_to(Vector2(0, 0)) > 1e-3 or uv[nc - 1].distance_to(Vector2(d.uv_rep, 1.0)) > 1e-3:
			continue
		var n1 := (rows - 1) * (cols - 1) * 6
		var idx1 := idx.slice(0, n1)
		# thinned casing: the same grid, every sj-th column and si-th row (same vertices, same winding as the generator's)
		var sj := maxi((cols - 1) / 32, 1)
		while (cols - 1) % sj != 0:
			sj -= 1
		var si_ := 2 if (rows - 1) % 2 == 0 else 1
		var flip: bool = idx[1] != idx[0] + 1
		var idx2 := PackedInt32Array()
		for i in range(0, rows - 1, si_):
			for j in range(0, cols - 1, sj):
				var a := i * cols + j
				var b := a + sj
				var c := a + si_ * cols + sj
				var e := a + si_ * cols
				if flip:
					idx2.append_array(PackedInt32Array([a, c, b, a, e, c]))
				else:
					idx2.append_array(PackedInt32Array([a, b, c, a, c, e]))
		_wlods.append({"mi": mi, "meshes": [src, _mesh_variant(src, si, idx1), _mesh_variant(src, si, idx2)], "cur": 0})
	if force == "1" or force == "2":
		for w in _wlods:
			_set_wheel_mesh(w.mi, w.meshes[int(force)])
			w.cur = int(force)
		_wlods.clear()
	set_process(not _wlods.is_empty())

func _mesh_variant(src: ArrayMesh, si: int, new_idx: PackedInt32Array) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = src.resource_name
	for s in src.get_surface_count():
		var a := src.surface_get_arrays(s)
		if s == si:
			a[Mesh.ARRAY_INDEX] = new_idx
		out.add_surface_from_arrays(src.surface_get_primitive_type(s), a)
		out.surface_set_name(s, src.surface_get_name(s))
		out.surface_set_material(s, src.surface_get_material(s))
	out.custom_aabb = src.custom_aabb if src.custom_aabb.size != Vector3.ZERO else src.get_aabb()
	return out

## swap a wheel's mesh and keep its per-surface material overrides (a new mesh drops them)
func _set_wheel_mesh(mi: MeshInstance3D, m: Mesh) -> void:
	var ov := []
	for s in mi.mesh.get_surface_count():
		ov.append(mi.get_surface_override_material(s))
	mi.mesh = m
	for s in mini(ov.size(), m.get_surface_count()):
		mi.set_surface_override_material(s, ov[s])

func _process(_delta: float) -> void:
	# real time, not the game's delta: with time frozen (photo mode, a paused replay) the tyres kept the far,
	# knob-less LOD they had before, even with the camera right up at them
	var now := Time.get_ticks_msec()
	_wlod_t -= float(now - _wlod_ms) / 1000.0 if _wlod_ms > 0 else 0.0
	_wlod_ms = now
	if _wlod_t > 0.0 or _wlods.is_empty():
		return
	_wlod_t = 0.2
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var zoom := tan(deg_to_rad(cam.fov * 0.5)) / tan(deg_to_rad(37.5))   # (zoomed in counts as closer)
	for w in _wlods:
		if not is_instance_valid(w.mi) or not w.mi.is_inside_tree():
			continue
		var dist: float = cam.global_position.distance_to(w.mi.global_position) * zoom
		var want: int = w.cur
		var lim := [TYRE_LOD1, TYRE_LOD2]
		while want < 2 and dist > lim[want] + TYRE_LOD_HYST: want += 1
		while want > 0 and dist < lim[want - 1] - TYRE_LOD_HYST: want -= 1
		if want != w.cur:
			_set_wheel_mesh(w.mi, w.meshes[want])
			w.cur = want


## generated wheels (size, tyres, rims, spokes, hubs, cassette); the brake rotors split off the stock
## wheels stay. The frame is lifted / tilted so the new tyres sit on the ground.
func _swap_wheels(build: Dictionary, mods: Dictionary) -> void:
	var rf0 := wheel_rf
	var rr0 := wheel_rr
	if ResourceLoader.exists("res://scripts/bike/wheel_gen.gd"):
		var WG = load("res://scripts/bike/wheel_gen.gd")
		_gen_wheels = true
		_wheel_build = build
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
## `gear` = the camera + add-ons (ActionCam.GEAR_ROWS keys; build.camera carries them next to "mount")
func mount_cam(kind: String, gear := {}) -> void:
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
		action_cam = ActionCam.merged(ActionCam.build_clamp(Vector3(0, 0, 1), t.r, Vector3.UP, Vector3(0.0, t.r + 0.024, 0.0), 0.0, gear))
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
		action_cam = ActionCam.merged(ActionCam.build_clamp(axis, r, Vector3(0, 0, 1), Vector3(0.012, -0.03, r + 0.046), 0.0, gear))
		action_cam.position = at
		fl.add_child(action_cam)
		if probe: print("CAMMOUNT fork c=%s r=%.4f axis=%s" % [at, r, axis])
	else:
		return
	cam_mount = kind
	for mi in action_cam.find_children("*", "MeshInstance3D", true, false):
		if not mi.has_meta("shadow_sized"):   # the merged meshes decided their own (core/mesh_merge.gd)
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## bike lights (BikeLight.MODELS): the lamp on the left of the bar (the action cam takes the right; the light bar
## sits over the stem on two clamps) + a tail light under the saddle. Off until `set_lights_on(true)`.
var bike_lights: Array = []   # BikeLight.build results: {node, lens, lights, glow}
var lights_model := "none"
var _lights_on := false
func mount_lights(id: String) -> void:
	for l in bike_lights:
		if is_instance_valid(l.node):
			l.node.get_parent().remove_child(l.node)
			l.node.queue_free()
	bike_lights.clear()
	lights_model = "none"
	if not BikeLight.MODELS.has(id) or id == "none" or not (steer_n is MeshInstance3D): return
	var big: bool = BikeLight.MODELS[id].kind == "bar"
	var zc := lerpf(0.0, grip_l.z, 0.12 if big else 0.36)
	var hint := Vector3(lerpf(grip_l.x, 0.0, 0.3), grip_l.y, zc)
	var t := _tube_at(steer_n as MeshInstance3D, Vector3(0, 0, 1), zc, hint)
	if t.is_empty(): return
	var lamp := BikeLight.build(id, t.r)
	if lamp.is_empty(): return
	_MERGE.merge(lamp.node, [lamp.node], true, lamp.lens, lamp.lights)   # one mesh (the glowing lens its own surface)
	lamp.node.position = Vector3(t.c.x, t.c.y, 0.0) if big else t.c
	steer_n.add_child(lamp.node)
	bike_lights.append(lamp)
	lights_model = id
	var fr := model.find_child("frame", true, false) as MeshInstance3D
	if fr and seat is Dictionary:
		var tail := BikeLight.build_tail()
		_MERGE.merge(tail.node, [tail.node], true, tail.lens, tail.lights)
		# under the saddle's back, on the seat post / rails, facing back
		tail.node.position = Vector3(float(seat.rear) + 0.06, float(seat.top) - 0.075, 0.0)
		fr.add_child(tail.node)
		bike_lights.append(tail)
	var was := _lights_on
	_lights_on = not was
	set_lights_on(was)

func set_lights_on(on: bool) -> void:
	if on == _lights_on: return
	_lights_on = on
	for l in bike_lights:
		for lt in l.lights: (lt as Light3D).visible = on
		for m in l.lens: (m as StandardMaterial3D).emission_energy_multiplier = float(l.glow) if on else 0.0

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

## the pedal pair in a crank mesh's "plastic" surface (every frame model keeps both pedals there), cut into one
## pedal per side: {side (-1 / 1): [mesh centred on the pedal, centre in the crank's frame]}
static func _split_pedals(crank: Mesh) -> Dictionary:
	var out := {}
	var si := -1
	for i in crank.get_surface_count():
		var m := crank.surface_get_material(i)
		if m and m.resource_name == "plastic": si = i
	if si < 0: return out
	var arr := crank.surface_get_arrays(si)
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
		am.surface_set_material(0, crank.surface_get_material(si))   # (pictures; the bike overrides it with its own)
		out[side] = [am, c]
	return out

static var _pedal_models := {}   # glb path -> _split_pedals of its crank
var pedal_top := 0.017   # the pedals' top surface above their pivot (the foot's target), in the crank mesh's units

## the pedals' top above their pivot as `space` (the rider) measures it: the shoe's sole rests there
func pedal_top_in(space: Node3D) -> float:
	if pedal_pivots.is_empty() or not is_inside_tree() or not space.is_inside_tree(): return pedal_top
	return pedal_top * (space.global_basis.inverse() * pedal_pivots[0].global_basis).get_scale().y

## the pedals of a model (BikeBuild.PEDALS id; "stock" = this frame's own, `own` = its glb): {side: [mesh, centre]}
static func pedal_set(id: String, own := "res://assets/dh.glb") -> Dictionary:
	var path: String = own if id == "stock" else BikeBuild.PEDAL_GLB.get(id, own)
	if not _pedal_models.has(path):
		var sc: Node = load(path).instantiate()
		var cr := sc.find_child("crank", true, false) as MeshInstance3D
		_pedal_models[path] = _split_pedals(cr.mesh) if cr and cr.mesh else {}
		sc.free()
	return _pedal_models[path]

func _pedals(pedal_id := "stock", own_glb := "") -> void:
	## the crank's plastic surface holds both pedals: cut it into a left and a right pedal, each on
	## its own pivot, counter-rotated every frame so the pedals stay level while the crank turns.
	## Another model's pedals (garage Gears tab, build.drive.pedals) go on the same pivots: each pedal centred
	## where this frame's own pedal was.
	var mi := crank_n as MeshInstance3D
	var si := _surface_named(mi, "plastic")
	if si < 0:
		return
	var mat := mi.mesh.surface_get_material(si)
	var own := _split_pedals(mi.mesh)
	var use := own
	if pedal_id != "stock" and BikeBuild.PEDAL_GLB.has(pedal_id) and BikeBuild.PEDAL_GLB[pedal_id] != own_glb:
		use = pedal_set(pedal_id)
	pedal_top = 0.0
	for side in use: pedal_top = maxf(pedal_top, (use[side][0] as Mesh).get_aabb().end.y)
	if pedal_top <= 0.0: pedal_top = 0.017
	for side in [-1.0, 1.0]:
		if not own.has(side) or not use.has(side): continue
		var pm := MeshInstance3D.new()
		pm.mesh = use[side][0]
		pm.set_surface_override_material(0, mat)   # this frame's pedal material: paint keeps working
		var pivot := Node3D.new(); pivot.position = own[side][1]
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
	return steer_rest() * ((grip_l + grip_r) * 0.5)

## Pose from the physics state (already interpolated by the caller).
func pose(px: float, py: float, pz: float, heading: float, pitch: float, hop_nose: float, lean: float,
		steer: float, wf: float, wr: float, crank: float) -> void:
	_ground_cache.clear()
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

## ---- the crashed bike (CrashBikeCs, driven by BikePhysics._crash_step) ----
## every part mesh's support points along 26 directions in its own space, worked out once per bike (crash_hull_prepare,
## at ride load); at a crash they are taken to the world as the parts lie (pedals at their crank angle, the bars turned)
var _hull := []        # [MeshInstance3D, group: 0 frame / 1 steer, PackedVector3Array]
var _hull_cs = null
static var _cb_warmed := false   # (CrashBikeCs.Warm ran once this session)
var _wheel_rest := {}  # wheel node -> its transform before it came off (restore_wheels)

func crash_hull_prepare() -> void:
	if not _hull.is_empty() or model == null: return
	if _hull_cs == null: _hull_cs = CrashLog.cs_new("res://scripts/bike/CrashBikeCs.cs")
	if _hull_cs == null: return
	var t0 := Time.get_ticks_usec()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null or not _shown_in_model(m): continue
		if m == wheel_f or m == wheel_r or wheel_f.is_ancestor_of(m) or wheel_r.is_ancestor_of(m): continue   # (tyres: a ring each)
		if m.mesh.get_aabb().get_longest_axis_size() < 0.02: continue
		var verts := PackedVector3Array()
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				verts.append_array(arr[Mesh.ARRAY_VERTEX])
		var sp: PackedVector3Array = _hull_cs.MeshSupport(verts)
		if not sp.is_empty(): _hull.append([m, 1 if steer_n.is_ancestor_of(m) else 0, sp])
	if not _hull.is_empty() and not _cb_warmed:
		_cb_warmed = true
		var w = CrashLog.cs_new("res://scripts/bike/CrashBikeCs.cs")
		if w: w.Warm()
	if Env.s("BMX_CRASHBIKE_PROBE") != "": print("CRASHBIKE hull parts=%d ms=%.1f" % [_hull.size(), (Time.get_ticks_usec() - t0) / 1000.0])

## shown, judged inside the model only (the rig may not be in the scene yet at load)
func _shown_in_model(n: Node) -> bool:
	while n != null and n != model:
		if n is Node3D and not (n as Node3D).visible: return false
		n = n.get_parent()
	return true

## the frame's and the steer's hull points in the world now ({frame, steer}; {} without C#)
func crash_points() -> Dictionary:
	crash_hull_prepare()
	if _hull_cs == null or _hull.is_empty(): return {}
	var fr := PackedVector3Array()
	var st := PackedVector3Array()
	for e in _hull:
		var mi: MeshInstance3D = e[0]
		if not is_instance_valid(mi) or not _shown_in_model(mi): continue
		var xf := mi.global_transform
		for p in (e[2] as PackedVector3Array):
			if e[1] == 0: fr.append(xf * p)
			else: st.append(xf * p)
	var b := model.global_transform.basis.orthonormalized()
	return {"frame": _hull_cs.Reduce(fr, b, 0.025), "steer": _hull_cs.Reduce(st, b, 0.025)}

## pose the crashed bike: model_xf = the model's world transform, steer = the bars' angle; off_f / off_r = a wheel that
## came off (its node's world transform) or null
func pose_crash(model_xf: Transform3D, steer: float, wf: float, wr: float, crank: float, off_f, off_r) -> void:
	_ground_cache.clear()
	pitch_g.transform = Transform3D.IDENTITY
	lean_g.transform = Transform3D.IDENTITY
	global_transform = model_xf * (fit_g.transform * model.transform).affine_inverse()
	steer_n.quaternion = Quaternion(steer_axis, steer)
	if off_f == null: wheel_f.rotation.z = -wf
	if off_r == null: wheel_r.rotation.z = -wr
	crank_n.rotation.z = -crank
	crank_angle = crank
	for p in pedal_pivots:
		p.rotation.z = crank
	if susp:
		susp.apply()
	for pair in [[wheel_f, off_f], [wheel_r, off_r]]:
		var w: Node3D = pair[0]
		if pair[1] == null: continue
		if not _wheel_rest.has(w): _wheel_rest[w] = w.transform
		w.global_transform = pair[1]
	if chain: chain.visible = off_r == null

## the wheels back on (getting up: a new bike, as with the torn-off action cam)
func restore_wheels() -> void:
	for w in _wheel_rest:
		if is_instance_valid(w): (w as Node3D).transform = _wheel_rest[w]
	_wheel_rest.clear()
	if chain: chain.visible = true

## the bars' angle the steer node is turned to now (rad, about steer_axis)
func steer_angle() -> float:
	var q := steer_n.quaternion
	var ang := q.get_angle()
	if ang < 1e-5: return 0.0
	return wrapf(ang * signf(q.get_axis().dot(steer_axis)), -PI, PI)

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
	# the ride's terrain does the whole loop below in one C# call (Terrain.tyre_worst)
	var ter = top.get_object()
	if ter is Terrain and top.get_method() == &"top_height":
		var w = ter.tyre_worst(c, ax, d0, side, R, hw, n, full)
		if w != null: return w
	var worst := -INF
	for i in n:
		var a := TAU * i / n if full else -1.4 + 2.8 * i / (n - 1)
		var dir := d0 * cos(a) + side * sin(a)
		for wo in TYRE_ACROSS:
			var off: float = wo * hw
			var r := R - hw + sqrt(hw * hw - off * off)
			var p := c + dir * r + ax * off
			# ground heights cached for this frame on a 1 mm grid: fit_wheels' last pass and unclip_tyres'
			# first ask for the very same points, and lifting the bike doesn't move them sideways
			var key := (roundi(p.x * 1000.0) << 32) ^ (roundi(p.z * 1000.0) & 0xffffffff)
			var h = _ground_cache.get(key)
			if h == null:
				h = float(top.call(p.x, p.z))
				_ground_cache[key] = h
			worst = maxf(worst, h - p.y)
	return worst

var _ground_cache := {}   # tyre_depth's ground samples, cleared every pose()

## Riding: put each wheel on the ground with the suspension (the frame stays where the physics put the
## body): the fork slides and the swingarm swings until the tyre just touches, within the travel; topped
## out when the ground is further away (in the air). What the travel can't take, unclip_tyres() lifts.
func fit_wheels(top: Callable) -> void:
	if susp == null or not susp.wheels_follow:
		return
	# The fork travel is solved with the bars STRAIGHT. Turning the bars (rake + trail) moves the front axle
	# in the frame by a centimetre or two; on a real bike that lifts / dips the frame and the fork doesn't move,
	# but fitting with the bars turned made the fork compress to cancel it ("suspension sinks when I turn the
	# bars standing still"). What is left is a tyre in / off the ground, which unclip_tyres() takes up in the frame.
	var steer_q := steer_n.quaternion
	var straight: bool = not steer_q.is_equal_approx(Quaternion.IDENTITY) and susp.has_f and Env.s("BMX_OLD_STEERFIT") == ""
	if straight:
		steer_n.quaternion = Quaternion.IDENTITY
		susp.apply()
	var mb := model.global_transform.basis
	var up_f: float = maxf(0.4, (mb * susp.axis).normalized().y)   # world rise per metre of fork travel
	var up_r: float = maxf(0.4, mb.y.normalized().y)                 # ... per metre of rear axle rise
	# how much clearance a metre of travel really gives is MEASURED from the last pass (secant), starting from the
	# axis' rise. Laid right over in a berm the wheel moves mostly sideways as it compresses, toward ground that
	# falls away: the real gain was ~0.85 where the axis' rise said 0.4, every pass overshot by more than it
	# corrected, and (the travel carries over from frame to frame) the wheels flipped between two answers on
	# alternate frames - the bike and the rider jumped ~8 cm up and down every frame at the top of a berm
	var gF := up_f; var gR := up_r
	var pdF := 0.0; var pdR := 0.0; var pxF := 0.0; var pxR := 0.0
	for it in 6:
		var dF := tyre_depth(wheel_f, wheel_rf, top)
		var dR := tyre_depth(wheel_r, wheel_rr, top)
		if it > 0:
			if absf(susp.xF - pxF) > 1e-4: gF = clampf((pdF - dF) / (susp.xF - pxF), up_f * 0.7, 4.0)
			if absf(susp.xR - pxR) > 1e-4: gR = clampf((pdR - dR) / (susp.xR - pxR), up_r * 0.7, 4.0)
		pdF = dF; pdR = dR; pxF = susp.xF; pxR = susp.xR
		var nF := clampf(susp.xF + dF / gF, susp.F["min"], susp.F["max"]) if susp.has_f else 0.0
		var nR := clampf(susp.xR + dR / gR, susp.R["min"], susp.R["max"]) if susp.has_r else 0.0
		if absf(nF - susp.xF) < 5e-4 and absf(nR - susp.xR) < 5e-4:
			break
		susp.xF = nF; susp.xR = nR
		susp.apply()
	if straight:
		steer_n.quaternion = steer_q
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
	# the grip's own frame (the bar turns with the steering): forward across the bar and the bar's axis, in lean space.
	# The rider's hands are locked to it (Rider.orient_grip) so the palm stays square on the bar however it is turned.
	var lb := lean_g.global_transform.basis.orthonormalized().inverse()
	var sb := steer_n.global_transform.basis.orthonormalized()
	out["gripX_L"] = (lb * (sb * Vector3(1, 0, 0))).normalized()
	out["gripX_R"] = out["gripX_L"]
	out["gripZ"] = (lb * (sb * Vector3(0, 0, 1))).normalized()
	if pedal_pivots.size() == 2:
		out.footL = lean_g.to_local(pedal_pivots[0].global_position)
		out.footR = lean_g.to_local(pedal_pivots[1].global_position)
	return out

func set_brake_heat(k: float) -> void:
	for r in rotors:
		if r.has_method("set_heat"): r.set_heat(k)
