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
		var tex := ImageTexture.create_from_image(get_texture().get_image())
		_cache[job[0]] = tex
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
	for mi in mis:
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if node.has_meta("crop_top"):
		var h: float = box.size.y * float(node.get_meta("crop_top"))
		box = AABB(Vector3(box.position.x + box.size.x * 0.2, box.end.y - h, box.position.z), Vector3(box.size.x * 0.6, h, box.size.z))
	var c := box.get_center()
	var d := view.normalized()
	# fit the box's corners to the picture: the distance each corner needs, horizontally and vertically
	var basis := Basis.looking_at(-d, Vector3.UP)
	var right := basis.x; var up := basis.y
	var tv := tan(deg_to_rad(_cam.fov * 0.5))
	var th := tv * float(SIZE.x) / float(SIZE.y)
	var dist := 0.0
	for i in 8:
		var q := box.get_endpoint(i) - c
		var z := q.dot(d)
		dist = maxf(dist, z + absf(q.dot(right)) / th)
		dist = maxf(dist, z + absf(q.dot(up)) / tv)
	dist *= 1.02
	var r := box.size.length()
	_cam.near = maxf(dist - r, 0.01); _cam.far = dist + r
	_cam.look_at_from_position(c + d * dist, c, Vector3.UP)


# ---------------------------------------------------------------- parts
## a mesh from dh.glb with its transform in the model
static func glb_part(n: String) -> Array:
	if _parts.is_empty():
		var sc: Node3D = load("res://assets/dh.glb").instantiate()
		for name in ["steer", "fork_lower"]:
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

## the handlebar alone (bar, stem clamp, grips, levers) at a width / rise / material, painted like the build
static func make_bars(m: Dictionary, crown_paint: Dictionary, grip_paint: Dictionary) -> Node3D:
	if _bar_stock == null:
		_bar_stock = _filter(glb_part("steer")[0], func(a, b, c): return a.y > BAR_CUT and b.y > BAR_CUT and c.y > BAR_CUT,
			["black", "rubber", "plastic", "chrome"])
	var mi := MeshInstance3D.new()
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
static func make_fork(lowers: Dictionary, stanchions: Dictionary, crown_paint: Dictionary) -> Node3D:
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
	root.rotation.z = deg_to_rad(64.0)   # laid down along the picture (crown left), like a product shot
	return root


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
