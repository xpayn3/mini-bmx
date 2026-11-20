class_name PartThumbs
extends SubViewport
## Pictures of single bike parts (handlebars, forks, wheels) for the garage's part cards: one
## off-screen viewport with its own little studio (white-grey sky, key / fill / rim light, see-through
## background). Each part is built, framed and drawn once (one per frame), the picture is cached by key.

const SIZE := Vector2i(360, 220)
const BAR_CUT := 0.115   # steer mesh: above this the bar + stem clamp, below it the crown + stanchions

static var _parts := {}   # dh.glb node name -> [mesh, transform in the model]

var _cache := {}          # key -> ImageTexture
var _queue: Array = []    # [key, make: Callable, view: Vector3]
var _waiting := {}        # key -> [callbacks]
var _busy := false
var _stage := Node3D.new()
var _cam := Camera3D.new()


func _init() -> void:
	size = SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.82, 0.86, 0.92); sm.sky_horizon_color = Color(0.95, 0.95, 0.95)
	sm.ground_bottom_color = Color(0.25, 0.25, 0.27); sm.ground_horizon_color = Color(0.8, 0.8, 0.8)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new(); we.environment = env
	add_child(we)
	for l in [[Vector3(-0.6, -0.8, -0.5), 1.7, Color(1, 0.97, 0.92)], [Vector3(0.7, -0.3, 0.4), 0.55, Color(0.85, 0.9, 1)],
			[Vector3(0.2, -0.4, 0.9), 0.9, Color(1, 1, 1)]]:
		var d := DirectionalLight3D.new()
		d.light_energy = l[1]; d.light_color = l[2]
		add_child(d)
		d.look_at_from_position(Vector3.ZERO, l[0], Vector3.UP if absf(l[0].normalized().y) < 0.99 else Vector3.FORWARD)
	add_child(_stage)
	_cam.fov = 24.0
	add_child(_cam)


## the picture for `key` goes to cb(texture) (at once when cached); `make` builds the part as a Node3D,
## `view` is the direction from the part to the camera
func request(key: String, make: Callable, view: Vector3, cb: Callable) -> void:
	if _cache.has(key):
		cb.call(_cache[key]); return
	if _disk_path(key) != "" and FileAccess.file_exists(_disk_path(key)):   # pictured in an earlier session
		var img := Image.load_from_file(_disk_path(key))
		if img != null and not img.is_empty():
			_cache[key] = ImageTexture.create_from_image(img)
			cb.call(_cache[key]); return
	if _waiting.has(key):
		_waiting[key].append(cb); return
	_waiting[key] = [cb]
	_queue.append([key, make, view])
	if not _busy: _run()


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		var node: Node3D = job[1].call()
		_stage.add_child(node)
		_frame(node, job[2])
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var img := get_texture().get_image()
		var tex := ImageTexture.create_from_image(img)
		_cache[job[0]] = tex
		if _disk_path(job[0]) != "":
			DirAccess.make_dir_recursive_absolute(DISK_DIR)
			img.save_png(_disk_path(job[0]))
		_stage.remove_child(node); node.queue_free()
		for cb in _waiting.get(job[0], []):
			if (cb as Callable).is_valid(): cb.call(tex)
		_waiting.erase(job[0])
	_busy = false


func _frame(node: Node3D, view: Vector3) -> void:
	var box := AABB()
	var first := true
	var mis: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: mis.append(node)
	if node.has_meta("frame_on"):   # frame this one part (the rest may run off the picture: context)
		mis = [node.get_meta("frame_on")]
	for mi in mis:
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if node.has_meta("crop_top"):
		var h: float = box.size.y * float(node.get_meta("crop_top"))
		box = AABB(Vector3(box.position.x + box.size.x * 0.2, box.end.y - h, box.position.z), Vector3(box.size.x * 0.6, h, box.size.z))
	var c := box.get_center()
	var d := view.normalized()
	var basis := Basis.looking_at(-d, Vector3.UP)
	var right := basis.x; var up := basis.y
	var tv := tan(deg_to_rad(_cam.fov * 0.5))
	var th := tv * float(size.x) / float(size.y)
	# the part's own points (not its box: a part lying at an angle has a much bigger box than itself, so it came
	# out small and off centre): centre on their extent across the view, then fit them as big as the picture lets
	var pts := _points(mis, 600)
	if node.has_meta("crop_top") or pts.is_empty():
		for i in 8: pts.append(box.get_endpoint(i))
	var lo := Vector2(INF, INF); var hi := -lo
	for p in pts:
		var q: Vector3 = p - c
		var v := Vector2(q.dot(right), q.dot(up))
		lo = lo.min(v); hi = hi.max(v)
	c += right * (lo.x + hi.x) * 0.5 + up * (lo.y + hi.y) * 0.5
	var dist := 0.0
	for p in pts:
		var q: Vector3 = p - c
		var z := q.dot(d)
		dist = maxf(dist, z + absf(q.dot(right)) / th)
		dist = maxf(dist, z + absf(q.dot(up)) / tv)
	dist *= float(node.get_meta("frame_pad", 1.03))
	var r := maxf(box.size.length(), dist)   # (near / far: room for any context round a framed part)
	_cam.near = maxf(dist - r, 0.01); _cam.far = dist + r
	_cam.look_at_from_position(c + d * dist, c, Vector3.UP)


## up to ~n world-space vertices of these meshes (every k-th), for framing
static func _points(mis: Array, n: int) -> Array:
	var out := []
	var total := 0
	for mi in mis:
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null: continue
		for si in m.get_surface_count(): total += (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var step := maxi(1, total / maxi(n, 1))
	for mi in mis:
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null: continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for si in m.get_surface_count():
			var vs: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for i in range(0, vs.size(), step): out.append(xf * vs[i])
	return out


# ---------------------------------------------------------------- parts
## a mesh from dh.glb with its transform in the model
static func glb_part(n: String) -> Array:
	if _parts.is_empty():
		var sc: Node3D = load("res://assets/dh.glb").instantiate()
		for name in ["steer", "fork_lower", "seatstay", "wheel_front", "wheel_rear"]:
			var mi: MeshInstance3D = sc.find_child(name, true, false)
			var xf := Transform3D.IDENTITY
			var p: Node = mi
			while p != sc:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			_parts[name] = [mi.mesh, xf]
		sc.free()
	return _parts[n]


## the triangles of `mesh` that `keep(a, b, c)` accepts, surface materials (names) kept; empty surfaces dropped
static func _filter(mesh: Mesh, keep: Callable, only := []) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var mat := mesh.surface_get_material(si)
		var nm: String = mat.resource_name if mat else ""
		if not only.is_empty() and not nm in only: continue
		var arr := mesh.surface_get_arrays(si)
		var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(P.size()))
		var K := PackedInt32Array()
		for t in range(0, I.size(), 3):
			if keep.call(P[I[t]], P[I[t + 1]], P[I[t + 2]]):
				K.append_array(PackedInt32Array([I[t], I[t + 1], I[t + 2]]))
		if K.is_empty(): continue
		arr = _compact(arr, K)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## only the vertices the kept triangles use (so the mesh's bounds are the part's own)
static func _compact(arr: Array, K: PackedInt32Array) -> Array:
	var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var remap := PackedInt32Array(); remap.resize(P.size()); remap.fill(-1)
	var used := PackedInt32Array()
	for i in K:
		if remap[i] < 0:
			remap[i] = used.size(); used.append(i)
	var out := []; out.resize(Mesh.ARRAY_MAX)
	var nv := PackedVector3Array(); var nn := PackedVector3Array(); var nt := PackedFloat32Array()
	var nc := PackedColorArray(); var nu := PackedVector2Array(); var nu2 := PackedVector2Array()
	var N = arr[Mesh.ARRAY_NORMAL]; var T = arr[Mesh.ARRAY_TANGENT]; var C = arr[Mesh.ARRAY_COLOR]
	var U = arr[Mesh.ARRAY_TEX_UV]; var U2 = arr[Mesh.ARRAY_TEX_UV2]
	for i in used:
		nv.append(P[i])
		if N != null: nn.append(N[i])
		if T != null: for j in 4: nt.append(T[i * 4 + j])
		if C != null: nc.append(C[i])
		if U != null: nu.append(U[i])
		if U2 != null: nu2.append(U2[i])
	out[Mesh.ARRAY_VERTEX] = nv
	if N != null: out[Mesh.ARRAY_NORMAL] = nn
	if T != null: out[Mesh.ARRAY_TANGENT] = nt
	if C != null: out[Mesh.ARRAY_COLOR] = nc
	if U != null: out[Mesh.ARRAY_TEX_UV] = nu
	if U2 != null: out[Mesh.ARRAY_TEX_UV2] = nu2
	var I2 := PackedInt32Array(); I2.resize(K.size())
	for t in K.size(): I2[t] = remap[K[t]]
	out[Mesh.ARRAY_INDEX] = I2
	return out


static var _bar_stock: ArrayMesh = null

## Whole-bike pictures (ride setup cards) are kept on disk: building a bike takes ~0.2-0.4 s, and the setup
## page wants one per frame. The key holds a hash of everything the bike is built from (frame, garage
## build), so a changed build gets a new picture; THUMB_VER: bump when how bikes look changes (models,
## materials, decals, this studio).
const DISK_DIR := "user://cache/thumbs"
const THUMB_VER := 1
static func bike_key(id: String) -> String:
	var sig := var_to_str([THUMB_VER, ProjectSettings.get_setting("application/config/version", ""), SIZE, GameState.bike_config_for(id)])
	return "bike|%s|%s" % [id, sig.md5_text()]

static func _disk_path(key: String) -> String:
	if not key.begins_with("bike|"): return ""
	return "%s/%s.png" % [DISK_DIR, key.md5_text()]

## a whole bike (stock frame + the player's garage build when the frame takes one), for the ride setup cards
static func make_bike(id: String) -> Node3D:
	var cfg := GameState.bike_config_for(id)
	var rig := BikeRig.new()
	rig.load_bike(cfg, cfg.get("build", {}))
	return rig

## drop the cached bike pictures (after a part changed)
func forget_bikes() -> void:
	for k in _cache.keys():
		if String(k).begins_with("bike|"): _cache.erase(k)

## the handlebar alone (bar, stem clamp, grips, levers) at a width / rise / material, painted like the build
static func make_bars(m: Dictionary, crown_paint: Dictionary, grip_paint: Dictionary) -> Node3D:
	if _bar_stock == null:
		_bar_stock = _filter(glb_part("steer")[0], func(a, b, c): return a.y > BAR_CUT and b.y > BAR_CUT and c.y > BAR_CUT,
			["black", "rubber", "plastic", "chrome"])
	var mi := MeshInstance3D.new()
	if m.has("glb"):   # a model's bar + grips (assets/forks/bar_<glb>.glb) as one mesh, the tube as "bar"
		var n: Node = load("res://assets/forks/bar_%s.glb" % m.glb).instantiate()
		var am := ArrayMesh.new()
		for part in ["bar", "grips"]:
			var src := (n.find_child(part, true, false) as MeshInstance3D).mesh
			for i in src.get_surface_count():
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
				var mat := src.surface_get_material(i)
				if part == "bar" and mat and mat.resource_name == "black":
					mat = mat.duplicate(); mat.resource_name = "bar"
				am.surface_set_material(am.get_surface_count() - 1, mat)
		n.free()
		mi.mesh = am
		var stock_mid := _bar_stock.get_aabb().get_center()
		mi.position = Vector3(stock_mid.x, stock_mid.y, 0.0)   # about where the stock bar sits, so the card framing fits
	else:
		mi.mesh = Handlebar.build(_bar_stock, float(m.width), float(m.rise))
	var paint := BikeBuild.paint_material(crown_paint)
	for i in mi.mesh.get_surface_count():
		var nm: String = mi.mesh.surface_get_material(i).resource_name
		if nm == "black": mi.set_surface_override_material(i, paint)
		elif nm == "rubber": mi.set_surface_override_material(i, BikeBuild.paint_material(grip_paint))
		elif nm == "bar":
			if String(m.material).begins_with("carbon"):
				var cm: StandardMaterial3D = WheelGen.carbon_material("bar", m.material == "carbon", Vector3(70, 70, 70))
				cm.uv1_triplanar = true
				mi.set_surface_override_material(i, cm)
			else:
				mi.set_surface_override_material(i, paint)
	return mi


static var _crown: ArrayMesh = null

## the fork alone: lowers + stanchions + crown / steerer, in the model's colours
static func make_fork(lowers: Dictionary, stanchions: Dictionary, crown_paint: Dictionary, glb := "") -> Node3D:
	if glb != "":
		return _make_fork_glb(glb, lowers, stanchions, crown_paint)
	if _crown == null:
		_crown = _filter(glb_part("steer")[0], func(a, b, c): return a.y < BAR_CUT or b.y < BAR_CUT or c.y < BAR_CUT,
			["black", "gold", "chrome"])
	var root := Node3D.new()
	var top := MeshInstance3D.new()
	top.mesh = _crown
	top.transform = glb_part("steer")[1]
	for i in _crown.get_surface_count():
		var nm: String = _crown.surface_get_material(i).resource_name
		if nm == "gold": top.set_surface_override_material(i, BikeBuild.paint_material(stanchions))
		elif nm == "black": top.set_surface_override_material(i, BikeBuild.paint_material(crown_paint))
	root.add_child(top)
	var low := MeshInstance3D.new()
	var lp: Array = glb_part("fork_lower")
	low.mesh = lp[0]
	low.transform = lp[1]
	for i in low.mesh.get_surface_count():
		if low.mesh.surface_get_material(i).resource_name == "black":
			low.set_surface_override_material(i, BikeBuild.paint_material(lowers))
	root.add_child(low)
	# laid down level along its own length (the long axis of the legs, in the side view), crown on the left
	var ax := Vector2.ZERO
	var vs: PackedVector3Array = lp[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mean := Vector2.ZERO
	for v in vs:
		var w: Vector3 = lp[1] * v
		mean += Vector2(w.x, w.y)
	mean /= maxf(1.0, vs.size())
	var sxx := 0.0; var syy := 0.0; var sxy := 0.0
	for v in vs:
		var w: Vector3 = lp[1] * v
		var q := Vector2(w.x, w.y) - mean
		sxx += q.x * q.x; syy += q.y * q.y; sxy += q.x * q.y
	var ang := 0.5 * atan2(2.0 * sxy, sxx - syy)   # the principal axis
	ax = Vector2(cos(ang), sin(ang))
	if ax.y < 0.0: ax = -ax                          # pointing up the fork (to the crown)
	return _catalogue_pose(root, ax)


## a fork model from assets/forks/<glb>.glb (crowns + stanchions, lowers + caliper) in the model's colours, catalogue pose
static func _make_fork_glb(glb: String, lowers: Dictionary, stanchions: Dictionary, crown_paint: Dictionary) -> Node3D:
	var fs: Node = load("res://assets/forks/%s.glb" % glb).instantiate()
	var root := Node3D.new()
	var crown := fs.find_child("fork_crown", true, false) as MeshInstance3D
	var low := fs.find_child("fork_lower", true, false) as MeshInstance3D
	var ax := Vector2(-0.457, 0.889)   # the steer axis of the stock frame the fork is fitted to
	for pair in [[crown, true], [low, false]]:
		var mi: MeshInstance3D = pair[0]
		mi.get_parent().remove_child(mi)
		for i in mi.mesh.get_surface_count():
			var nm: String = mi.mesh.surface_get_material(i).resource_name
			if pair[1]:
				if nm == "gold": mi.set_surface_override_material(i, BikeBuild.paint_material(stanchions))
				elif nm == "black": mi.set_surface_override_material(i, BikeBuild.paint_material(crown_paint))
			elif nm == "black":
				mi.set_surface_override_material(i, BikeBuild.paint_material(lowers))
		root.add_child(mi)
	fs.free()
	return _catalogue_pose(root, ax)


const FORK_RISE := 0.85   # rad: the fork stands at this angle above level, axle bottom left, crown top right
const FORK_TURN := 1.0    # rad: then turned about the vertical so both legs and the arch show (a 3/4 front view)

## a fork posed like a magazine / catalogue shot: standing diagonally across the picture, three-quarter view.
## `ax` = the fork's steer axis in its model's side view (pointing up to the crown)
static func _catalogue_pose(fork: Node3D, ax: Vector2) -> Node3D:
	fork.rotation.z = FORK_RISE - atan2(ax.y, ax.x)
	var root := Node3D.new()
	root.add_child(fork)
	root.rotation.y = FORK_TURN
	return root


# ---------------------------------------------------------------- brakes
## a stock part baked into a frame mesh: the triangles of `whole` that `without` (the same mesh with that part cut
## out by tools/make_forks.py) doesn't have. Triangles are matched by their middles on a 2 mm grid; the cut mesh's
## middles go in for every rounding within +-0.4 mm (imported positions are quantised a little differently).
static func _diff(whole: Mesh, without: Mesh) -> ArrayMesh:
	const Q := 500.0      # 2 mm cells
	const E := 0.0004
	var have := {}
	for si in without.get_surface_count():
		var arr := without.surface_get_arrays(si)
		var P: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(P.size()))
		for t in range(0, I.size(), 3):
			var m := (P[I[t]] + P[I[t + 1]] + P[I[t + 2]]) / 3.0
			for dx in [-E, E]:
				for dy in [-E, E]:
					for dz in [-E, E]:
						have[Vector3i(roundi((m.x + dx) * Q), roundi((m.y + dy) * Q), roundi((m.z + dz) * Q))] = true
	return _filter(whole, func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		var m := (a + b + c) / 3.0
		return not have.has(Vector3i(roundi(m.x * Q), roundi(m.y * Q), roundi(m.z * Q))))

static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D: return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r: return r
	return null

## a part's meshes in the model frame, out of a glb (node `node`, or the first mesh in it)
static func _glb_mesh(path: String, node := "") -> Mesh:
	var sc: Node = load(path).instantiate()
	var mi := sc.find_child(node, true, false) as MeshInstance3D if node != "" else null
	if mi == null: mi = _first_mesh(sc)
	var m: Mesh = mi.mesh if mi else null
	sc.free()
	return m

static var _stock_caliper: Mesh
static var _stock_levers: Mesh

## a disc rotor alone, face on and a little turned, with the bike's rotor material (heat glow cold + brushed rings).
## "stock" = the one split off dh.glb's front wheel (BikeFX.RotorGlow), else assets/forks/rotor_<id>.glb
static func make_rotor(id: String, front := true) -> Node3D:
	var host := MeshInstance3D.new()
	host.mesh = glb_part("wheel_front" if front else "wheel_rear")[0]
	var glow := BikeFX.find_rotor(host)   # splits the disc into its own child mesh (on this copy) and makes its material
	var mi := MeshInstance3D.new()
	if id == "stock":
		mi.mesh = glow.mesh_instance.mesh if glow else null
	else:
		mi.mesh = _glb_mesh("res://assets/forks/rotor_%s.glb" % id, "rotor_front" if front else "rotor_rear")
	if glow and mi.mesh:
		MetalFinish.dress_rotor(glow.material)
		for i in mi.mesh.get_surface_count(): mi.set_surface_override_material(i, glow.material)
	host.free()
	var root := Node3D.new()
	root.add_child(mi)
	root.rotation.y = 0.45   # a little turned so the disc reads as a disc, not a flat picture
	return root

## a rear caliper on the rear rotor (the build's rotor), seen from the drive side's opposite (the caliper side).
## "stock" = the RUNOUT's own, cut out of its seatstay; else assets/forks/caliper_<id>.glb, placed on the axle
## like BikeRig._swap_rear_caliper does.
static func make_caliper(id: String, rotor_id: String) -> Node3D:
	var ss: Array = glb_part("seatstay")
	var wr: Array = glb_part("wheel_rear")
	var root := Node3D.new()
	var cal := MeshInstance3D.new()
	if id == "stock":
		if _stock_caliper == null:
			_stock_caliper = _diff(ss[0], _glb_mesh("res://assets/forks/dh_seatstay.glb", "seatstay"))
		cal.mesh = _stock_caliper
		cal.transform = ss[1]
	else:
		cal.mesh = _glb_mesh("res://assets/forks/caliper_%s.glb" % id)
		cal.transform = Transform3D((ss[1] as Transform3D).basis, (wr[1] as Transform3D).origin)
	root.add_child(cal)
	var disc := make_rotor(rotor_id, false)
	var d: Node3D = disc.get_child(0)
	disc.remove_child(d)
	disc.free()
	d.transform = wr[1]
	root.add_child(d)
	MetalFinish.apply(root)
	# the axle in the middle, the caliper side towards the camera
	var mid: Vector3 = (wr[1] as Transform3D).origin
	for c in root.get_children(): (c as Node3D).position -= mid
	var turn := Node3D.new()
	turn.add_child(root)
	turn.rotation.y = PI + 0.35
	turn.set_meta("frame_on", cal)   # a close-up of the caliper, its disc running out of the picture
	turn.set_meta("frame_pad", 1.6)
	return turn

## the right-hand brake lever on its own (blade + body + clamp). "stock" = the RUNOUT's, cut out of its steer
## mesh (the bars without levers are forks/dh_steer_nl.glb); else assets/forks/levers_<id>.glb (fitted to the
## same bar). Only one side: both levers are 70 cm apart and came out tiny.
static func make_levers(id: String) -> Node3D:
	var st: Array = glb_part("steer")
	var m: Mesh
	if id == "stock":
		if _stock_levers == null:
			_stock_levers = _diff(st[0], _glb_mesh("res://assets/forks/dh_steer_nl.glb"))
		m = _stock_levers
	else:
		m = _glb_mesh("res://assets/forks/levers_%s.glb" % id)
	var one := _filter(m, func(a: Vector3, b: Vector3, c: Vector3) -> bool: return a.z + b.z + c.z > 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = one
	mi.transform = st[1]
	MetalFinish.apply(mi)
	return mi

## a cassette alone (cogs in their anodized colours, lockring, freehub stub)
static func make_cassette(key: String) -> Node3D:
	var c: Dictionary = BikeBuild.CASSETTES[key]
	var mi := MeshInstance3D.new()
	mi.mesh = WheelGen.build_cassette(c.cogs, BikeBuild.cassette_cols(key), float(c.rough))
	return mi


## a whole wheel from the wheel generator (tyre + rim + spokes + hub)
## `crop` > 0 frames only the top part of it (that fraction of the height): a close-up of the tread
static func make_wheel(spec: Dictionary, crop := 0.0) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = WheelGen.build(spec)
	if crop > 0.0: mi.set_meta("crop_top", crop)
	return mi
