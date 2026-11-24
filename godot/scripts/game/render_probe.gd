extends Node
## BMX_RENDER_PROBE=1 (+ BMX_IDLE=1 so the picture holds still, BMX_NOVSYNC=1, --autotest=60): where the GPU time
## goes. Turns one part of the picture off at a time (sun shadows, grass, decorations, ground, smoke, post effects,
## MSAA, resolution...), measures the GPU time over MEASURE frames against the full picture, prints
##   RPROBE <part> gpu_ms= saves_ms= draws= prims= shadow_draws= shadow_prims=
## and RPROBE base ... first. Nothing is saved; every switch is put back.

const START := 6.0     # seconds into the ride (chunks, grass, shaders settled)
const SETTLE := 24     # frames after a switch before measuring
const MEASURE := 90

var game
var _t := 0.0
var _i := -1           # test index, -1 = waiting
var _f := 0
var _sum := 0.0
var _base := 0.0
var _sum_cpu := 0.0
var _base_cpu := 0.0
var _tests: Array = []
var _undo: Callable

func _init(g) -> void:
	game = g
	name = "RenderProbe"

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var e: Environment = game.env
	_tests = [
		["base", func(): return func(): pass],
		["sun_shadows", func():
			var s: DirectionalLight3D = game.sun; s.shadow_enabled = false
			return func(): s.shadow_enabled = true],
		["grass", func(): return _hide([game.grass])],
		["deco_all", func(): return _hide(_under(game.terrain, true))],
		["deco_shadows", func():
			var l := _under(game.terrain, true); var was := []
			for n in l: was.append(n.cast_shadow); n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return func():
				for k in l.size(): l[k].cast_shadow = was[k]],
		["terrain_meshes", func(): return _hide(_under(game.terrain, false))],
		["far_hills", func(): return _hide([game.far_hills] if game.far_hills else [])],
		["rider_bike", func(): return _hide([game.rig, game.rider])],
		["smoke", func():
			var sim = game.dust.sim if game.dust else null
			var c = sim.compositor if sim else null
			if c == null: return func(): pass
			c.enabled = false
			return func(): c.enabled = true],
		["ssao", _env(e, "ssao_enabled")],
		["ssil", _env(e, "ssil_enabled")],
		["sdfgi", _env(e, "sdfgi_enabled")],
		["vol_fog", _env(e, "volumetric_fog_enabled")],
		["glow", _env(e, "glow_enabled")],
		["ssr", _env(e, "ssr_enabled")],
		["dof", func():
			var a = get_viewport().get_camera_3d().attributes
			if a == null or not (a is CameraAttributesPractical): return func(): pass
			var f: bool = a.dof_blur_far_enabled; var n: bool = a.dof_blur_near_enabled
			a.dof_blur_far_enabled = false; a.dof_blur_near_enabled = false
			return func(): a.dof_blur_far_enabled = f; a.dof_blur_near_enabled = n],
		["msaa", func():
			var vp := get_viewport(); var m := vp.msaa_3d; vp.msaa_3d = Viewport.MSAA_DISABLED
			return func(): vp.msaa_3d = m],
		["half_res", func():
			var vp := get_viewport(); var s := vp.scaling_3d_scale; vp.scaling_3d_scale = s * 0.5
			return func(): vp.scaling_3d_scale = s],
	]

func _env(e: Environment, prop: String) -> Callable:
	return func():
		var was = e.get(prop)
		e.set(prop, false)
		return func(): e.set(prop, was)

func _hide(nodes: Array) -> Callable:
	var shown := []
	for n in nodes:
		if n is Node3D and (n as Node3D).visible:
			n.visible = false; shown.append(n)
	return func():
		for n in shown:
			if is_instance_valid(n): n.visible = true

## every MultiMeshInstance3D (mm = true) or plain MeshInstance3D (false) under root
func _under(root: Node, mm: bool) -> Array:
	var out := []
	if root == null: return out
	var st: Array[Node] = [root]
	while not st.is_empty():
		var o: Node = st.pop_back()
		st.append_array(o.get_children())
		if mm and o is MultiMeshInstance3D: out.append(o)
		elif not mm and o is MeshInstance3D: out.append(o)
	return out

## how many visible meshes / surfaces (= draw calls per pass) a root has, how many cast shadows, by size
func _parts(label: String, root: Node) -> void:
	var meshes := 0; var surfs := 0; var cast := 0; var small := 0; var small_cast := 0
	var names := {}
	for mi in _under(root, false):
		if not mi.is_visible_in_tree() or mi.mesh == null: continue
		var s: int = mi.mesh.get_surface_count()
		var sz: float = (mi.get_aabb().size * mi.global_transform.basis.get_scale()).length()
		meshes += 1; surfs += s
		var c: bool = mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if c: cast += s
		if sz < 0.12:
			small += s
			if c: small_cast += s
		var nm := String(mi.name).rstrip("0123456789@_")
		names[nm] = names.get(nm, 0) + s
	var top := names.keys()
	top.sort_custom(func(a, b): return names[a] > names[b])
	var tl := []
	for k in top.slice(0, 12): tl.append("%s:%d" % [k, names[k]])
	print("RPARTS %s meshes=%d surfaces=%d casting=%d small(<12cm)=%d small_casting=%d top=%s" % [label, meshes, surfs, cast, small, small_cast, ", ".join(tl)])
	if Env.s("BMX_RPARTS_LIST") != "":   # every visible mesh: its path under the root, surfaces, size, shadow
		for mi in _under(root, false):
			if not mi.is_visible_in_tree() or mi.mesh == null: continue
			print("RPART %s %s surf=%d across=%.3f cast=%d" % [label, String(root.get_path_to(mi)), mi.mesh.get_surface_count(),
				(mi.get_aabb().size * mi.global_transform.basis.get_scale()).length(), int(mi.cast_shadow)])

func _info(type: int, what: int) -> int:
	return RenderingServer.viewport_get_render_info(get_viewport().get_viewport_rid(), type, what)

func _process(dt: float) -> void:
	_t += dt
	if _i == -1:
		if _t < START: return
		_parts("rig", game.rig)
		_parts("rider", game.rider)
		_i = 0; _f = 0; _undo = _tests[0][1].call()
		return
	if _i >= _tests.size(): return
	_f += 1
	if _f <= SETTLE: return
	var vrid := get_viewport().get_viewport_rid()
	_sum += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
	_sum_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vrid) + RenderingServer.get_frame_setup_time_cpu()
	if _f < SETTLE + MEASURE: return
	var ms := _sum / MEASURE
	var cpu := _sum_cpu / MEASURE
	_sum_cpu = 0.0
	var T := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var S := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var D := RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
	var P := RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
	if _i == 0: _base = ms; _base_cpu = cpu
	print("RPROBE %-15s gpu_ms=%.2f saves_ms=%.2f render_cpu_ms=%.2f saves_cpu=%.2f draws=%d prims=%dk shadow_draws=%d shadow_prims=%dk" % [
		_tests[_i][0], ms, _base - ms, cpu, _base_cpu - cpu, _info(T, D), _info(T, P) / 1000, _info(S, D), _info(S, P) / 1000])
	_undo.call()
	_sum = 0.0; _f = 0; _i += 1
	if _i < _tests.size():
		_undo = _tests[_i][1].call()
	else:
		print("RPROBE done")


# ---------------------------------------------------------------- tests: what merging could save (BMX_MERGE_SCAN=1)
## Records every visible rider / bike mesh's transform relative to its parent at 6 s, again at 12 s (riding: use with
## BMX_FOLLOW), then: draw surfaces now, how many never moved against their parent, and how many draws would be left if
## each (parent, material) group of those became one surface. Also how many are ShaderMaterials / transparent / textured.
static func merge_scan(root: Node, label: String, snap: Dictionary, final: bool) -> void:
	var surfs := 0; var stable := 0; var groups := {}; var moving := 0; var fgroups := {}; var grime_flat := 0
	var kinds := {"shader": 0, "transp": 0, "tex": 0, "plain": 0}
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree(): continue
		if not final:
			snap[mi] = mi.transform
			continue
		var still: bool = snap.has(mi) and (snap[mi] as Transform3D).is_equal_approx(mi.transform)
		for si in mi.mesh.get_surface_count():
			surfs += 1
			var mat: Material = mi.material_override
			if mat == null: mat = mi.get_surface_override_material(si)
			if mat == null: mat = mi.mesh.surface_get_material(si)
			if mat is ShaderMaterial: kinds.shader += 1
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: kinds.transp += 1
			elif mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null: kinds.tex += 1
			else: kinds.plain += 1
			if still:
				stable += 1
				groups[[mi.get_parent(), mat]] = true
				var flat: bool = mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and (mat as BaseMaterial3D).albedo_texture == null and not (mat as BaseMaterial3D).emission_enabled
				fgroups[[mi.get_parent(), "flat" if flat else mat]] = true
				if flat: grime_flat += 1 if (mat as BaseMaterial3D).next_pass != null else 0
			else: moving += 1
	if final:
		print("MERGESCAN %s surfaces=%d still=%d moving=%d -> same-material merge %d, colour-baked merge %d  kinds=%s flat_with_grime_pass=%d" % [label, surfs, stable, moving, moving + groups.size(), moving + fgroups.size(), kinds, grime_flat])


## tests (BMX_TRI_SCAN=1): every visible rider / bike mesh: triangles, LOD levels left (from the renderer: a mesh rebuilt in
## code from surface arrays loses the import's auto LODs), name; the biggest first + totals
static func tri_scan(root: Node, label: String) -> void:
	var rows: Array = []
	var tot := 0; var tot_lod := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh and mmi.multimesh.mesh and mmi.is_visible_in_tree():
				var tm := 0
				var m: Mesh = mmi.multimesh.mesh
				for si in m.get_surface_count(): tm += _tris(m, si)
				var cnt := mmi.multimesh.visible_instance_count if mmi.multimesh.visible_instance_count >= 0 else mmi.multimesh.instance_count
				rows.append([tm * cnt, 0, "%s (multimesh %d x %d)" % [String(root.get_path_to(n)), cnt, tm]])
				tot += tm * cnt
			continue
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree(): continue
		var t := 0; var lods := 99
		for si in mi.mesh.get_surface_count():
			t += _tris(mi.mesh, si)
			var sd: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), si)
			lods = mini(lods, (sd.get("lods", []) as Array).size())
		if lods == 99: lods = 0
		tot += t
		if lods > 0: tot_lod += t
		rows.append([t, lods, String(root.get_path_to(mi))])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("TRISCAN %s total_tris=%d with_lods=%d meshes=%d" % [label, tot, tot_lod, rows.size()])
	for r in rows.slice(0, 14): print("TRISCAN %s %7d tris lods=%d %s" % [label, r[0], r[1], r[2]])

static func _tris(m: Mesh, si: int) -> int:
	var sd: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), si)
	var ic: int = int(sd.get("index_count", 0))
	if ic > 0: return ic / 3
	return int(sd.get("vertex_count", 0)) / 3

