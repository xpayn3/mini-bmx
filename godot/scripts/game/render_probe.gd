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
