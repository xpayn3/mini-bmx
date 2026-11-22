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
var _key: DirectionalLight3D = null
var _table := MeshInstance3D.new()

var _blob := MeshInstance3D.new()
const TABLE_LAYER := 1 << 19   # render layer 20: only the key light reaches the table

## the table under every part: a shadow catcher (only the key light's shadow shows), edges faded
const TABLE_SHADER := "shader_type spatial;
render_mode shadow_to_opacity, depth_draw_never, cull_disabled, specular_disabled;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.2, 0.5, length(UV - 0.5))) * 0.55;
}"


func _init() -> void:
	size = SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_ALWAYS   # saved pictures decode in _process, also behind a paused game


func _ready() -> void:
	_prune_disk()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.82, 0.86, 0.92); sm.sky_horizon_color = Color(0.95, 0.95, 0.95)
	sm.ground_bottom_color = Color(0.25, 0.25, 0.27); sm.ground_horizon_color = Color(0.8, 0.8, 0.8)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# a product-shot studio: AgX keeps white paint and chrome from clipping, a big key from above-front,
	# a weak cool fill so the shadow side keeps its shape, a strong rim from behind to draw the tubes'
	# edges, little flat ambient (it washed everything out)
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new(); we.environment = env
	add_child(we)
	# tabletop product light: a big soft key high front-left that casts a soft shadow onto the table, a cool fill,
	# a strong rim from behind (the edges), a soft top light (the upper faces read as lit from a softbox)
	for l in [[Vector3(-0.45, -0.9, -0.35), 1.15, Color(1, 0.97, 0.93)], [Vector3(0.8, -0.25, -0.3), 0.3, Color(0.82, 0.88, 1)],
			[Vector3(0.25, -0.35, 0.9), 1.3, Color(1, 1, 1)], [Vector3(0.05, -1.0, 0.1), 0.25, Color(1, 1, 1)]]:
		var d := DirectionalLight3D.new()
		d.light_energy = l[1]; d.light_color = l[2]
		add_child(d)
		d.look_at_from_position(Vector3.ZERO, l[0], Vector3.UP if absf(l[0].normalized().y) < 0.99 else Vector3.FORWARD)
		if _key == null:
			_key = d
			d.shadow_enabled = true
			d.light_angular_distance = 7.0   # soft box: the shadow blurs with distance from the part
			d.shadow_blur = 1.5
			d.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			d.shadow_bias = 0.02; d.shadow_normal_bias = 0.6
		else:
			d.light_cull_mask &= ~TABLE_LAYER   # the table sees the key only: any other light lifted its shadow away
	# the table: invisible, it only shows the key light's shadow (shadow_to_opacity) and a soft contact darkening
	# right under the part, faded out round the edge so it never shows as a plane on the card
	var tm := ShaderMaterial.new()
	tm.shader = Shader.new()
	tm.shader.code = TABLE_SHADER
	_table.material_override = tm
	_table.mesh = PlaneMesh.new()
	_table.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_table.layers = TABLE_LAYER
	add_child(_table)
	if _shadow_shader == null:
		_shadow_shader = Shader.new(); _shadow_shader.code = SHADOW_SHADER
	var bm := ShaderMaterial.new(); bm.shader = _shadow_shader
	bm.set_shader_parameter("strength", 0.38); bm.set_shader_parameter("softness", 1.8)
	_blob.material_override = bm
	_blob.mesh = PlaneMesh.new()
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob)
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
	if BAKE == "" and (FileAccess.file_exists(_ship_path(key)) or FileAccess.file_exists(_disk_path(key))):
		_disk_queue.append([key, make, view])   # shipped with the game / pictured in an earlier session: decoded a few per frame
		return
	_queue.append([key, make, view])
	if not _busy: _run()

## nothing waiting to be made or decoded (the bake waits for this)
func idle() -> bool:
	return not _busy and _queue.is_empty() and _disk_queue.is_empty()

## Pictures that ship with the game: every picture a fresh install shows (stock builds, factory paint, the
## default rider) is made at release time by the bake (tools/bake_thumbs.ps1: BMX_BAKE_THUMBS=<dir> renders
## everything fresh and writes <md5>.thumb = PNG bytes there; .thumb so Godot doesn't import them, the
## export preset includes assets/thumbs/*.thumb). Only pictures of the player's own changes are made on
## their machine, then cached in user://cache/thumbs for the next time.
const SHIP_DIR := "res://assets/thumbs"
static var BAKE := Env.s("BMX_BAKE_THUMBS")
static var _baked := 0
static func _ship_path(key: String) -> String:
	return _disk_path(key).replace(DISK_DIR, SHIP_DIR).replace(".png", ".thumb")

static func _load_pic(key: String) -> Image:
	for p in [_ship_path(key), _disk_path(key)]:
		if not FileAccess.file_exists(p): continue
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK and not img.is_empty(): return img
	return null

static func baked_count() -> int:
	return _baked

## saved pictures waiting to be decoded: a page full of cards decoded at once was a ~70 ms hitch
var _disk_queue: Array = []
const DISK_BUDGET_US := 4000

func _process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	while not _disk_queue.is_empty() and Time.get_ticks_usec() - t0 < DISK_BUDGET_US:
		var job: Array = _disk_queue.pop_front()
		var img := _load_pic(job[0])
		if img == null:   # unreadable: make it again
			_queue.append(job)
			if not _busy: _run()
			continue
		var tex := ImageTexture.create_from_image(img)
		_cache[job[0]] = tex
		for cb in _waiting.get(job[0], []):
			if (cb as Callable).is_valid(): cb.call(tex)
		_waiting.erase(job[0])


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		var node: Node3D = job[1].call()
		_stage.add_child(node)
		if node.has_meta("setup"): (node.get_meta("setup") as Callable).call()
		for i in int(node.get_meta("settle", 0)):   # a rider: posed every frame until the hair has fallen
			if node.has_meta("tick"): (node.get_meta("tick") as Callable).call(1.0 / 60.0)
			await get_tree().process_frame
			if not is_inside_tree() or not is_instance_valid(node): return
		_frame(node, job[2])
		render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var img := get_texture().get_image()
		var tex := ImageTexture.create_from_image(img)
		_cache[job[0]] = tex
		if BAKE != "":   # the release bake: into the game's own folder
			DirAccess.make_dir_recursive_absolute(BAKE)
			var f := FileAccess.open(_ship_path(job[0]).replace(SHIP_DIR, BAKE), FileAccess.WRITE)
			if f:
				f.store_buffer(img.save_png_to_buffer()); f.close()
				_baked += 1
		else:
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
	mis = mis.filter(func(m): return not m.has_meta("no_frame"))
	for mi in mis:
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if node.has_meta("focus"):   # a close-up of one spot (a part on a whole bike, the rider's head)
		box = (node.get_meta("focus") as Callable).call()
	elif node.has_meta("crop_top"):
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
	var pts := [] if node.has_meta("focus") else _points(mis, 600)
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
	dist *= 1.03
	var r := box.size.length()
	_cam.near = maxf(dist - r, 0.01); _cam.far = dist + r
	_cam.look_at_from_position(c + d * dist, c, Vector3.UP)
	_place_table(node, mis, box, dist + r)


## the table under the part's lowest point: shadow catcher (3x the part) + a contact darkening on its footprint;
## close-ups (`focus`: a spot on a whole bike, the head) rest on the bike's / rider's own floor
func _place_table(node: Node3D, mis: Array, box: AABB, reach: float) -> void:
	var all := _points(mis, 1500)
	if all.is_empty(): return
	var lo := INF
	for p in all: lo = minf(lo, (p as Vector3).y)
	var foot := AABB()
	var first := true
	for p: Vector3 in all:   # footprint = the points in the bottom 15 % of the part's height
		if p.y > lo + maxf(box.size.y * 0.15, 0.004): continue
		if first: foot = AABB(p, Vector3.ZERO); first = false
		else: foot = foot.expand(p)
	var full := AABB(box.position, box.size)
	for p: Vector3 in all: full = full.expand(p)
	var span := maxf(full.size.x, full.size.z)
	var mid := full.get_center()
	_table.global_transform = Transform3D(Basis().scaled(Vector3(span * 3.5, 1, span * 3.5)), Vector3(mid.x, lo - 0.0005, mid.z))
	var fc := foot.get_center()
	var fx := maxf(foot.size.x, span * 0.15) * 1.5; var fz := maxf(foot.size.z, span * 0.15) * 1.5
	_blob.global_transform = Transform3D(Basis().scaled(Vector3(fx, 1, fz)), Vector3(fc.x, lo + 0.0005, fc.z))
	_blob.visible = not node is BikeRig   # bikes lay their own tyre shadows
	_key.directional_shadow_max_distance = maxf(reach * 1.5, 0.5)


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

## Whole-bike pictures (ride setup cards) are kept on disk: building a bike takes ~0.2-0.4 s, and the setup
## page wants one per frame. The key holds a hash of everything the bike is built from (frame, garage
## build), so a changed build gets a new picture; THUMB_VER: bump when how anything pictured looks changes
## (models, materials, decals, this studio), then re-run the bake (tools/bake_thumbs.ps1) so the shipped
## pictures match. The game version is not in the keys: the shipped set stays valid until THUMB_VER moves.
const DISK_DIR := "user://cache/thumbs"
const THUMB_VER := 6
static func bike_key(id: String) -> String:
	var sig := var_to_str([THUMB_VER, SIZE, GameState.bike_config_for(id)])
	return "bike|%s|%s" % [id, sig.md5_text()]

## Every picture is saved to disk and made once, ever: each one builds a whole bike / part / rider and
## costs ~30-120 ms, and making them while you click through the garage tabs was the stutter. Their keys
## hold everything that changes how they look (the memory cache relied on that already); THUMB_VER is
## added here, so a studio / look change makes new ones. Kept to DISK_MAX files (the oldest go, once a
## session). Looked up after the pictures shipped with the game (SHIP_DIR).
const DISK_MAX := 3000
static var _pruned := false
static func _disk_path(key: String) -> String:
	if not key.begins_with("bike|"):
		key = "v%d|%s" % [THUMB_VER, key]
	return "%s/%s.png" % [DISK_DIR, key.md5_text()]

static func _prune_disk() -> void:
	if _pruned: return
	_pruned = true
	var files := DirAccess.get_files_at(DISK_DIR)
	if files.size() <= DISK_MAX: return
	var list := []
	for f in files:
		list.append([FileAccess.get_modified_time(DISK_DIR + "/" + f), f])
	list.sort()
	for i in list.size() - DISK_MAX:
		DirAccess.remove_absolute(DISK_DIR + "/" + list[i][1])

## a whole bike (stock frame + the player's garage build when the frame takes one), for the ride setup cards
static func make_bike(id: String) -> Node3D:
	var cfg := GameState.bike_config_for(id)
	var rig := BikeRig.new()
	rig.load_bike(cfg, cfg.get("build", {}))
	rig.set_meta("setup", _ground_shadow.bind(rig))
	return rig

## the picture key (disk cached, see bike_key) of a frame with a given build on it
static func build_key(id: String, build: Dictionary) -> String:
	var sig := var_to_str([THUMB_VER, SIZE, id, build])
	return "bike|%s|b%s" % [id, sig.md5_text()]

## a frame (GameState.BIKES id) with a given build on it (garage showroom: your build, the editions)
static func make_bike_build(id: String, build: Dictionary) -> Node3D:
	var cfg: Dictionary = GameState.BIKES[id].duplicate(true)
	var rig := BikeRig.new()
	rig.load_bike(cfg, build)
	rig.set_meta("setup", _ground_shadow.bind(rig))
	return rig

## soft contact shadows on the (invisible) floor: a tight dark blob where each tyre touches, a wide faint
## pool under the whole bike, so the bike stands on something instead of floating on the card
const SHADOW_SHADER := "shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.5;
uniform float softness = 2.0;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = strength * pow(clamp(1.0 - r, 0.0, 1.0), softness);
}"
static var _shadow_shader: Shader = null

static func _ground_shadow(rig: BikeRig, k := 1.0) -> void:
	if rig.wheel_f == null or rig.wheel_r == null: return
	if _shadow_shader == null:
		_shadow_shader = Shader.new(); _shadow_shader.code = SHADOW_SHADER
	var up := rig.global_basis.y.normalized()
	var pf := rig.wheel_f.global_position - up * rig.wheel_rf
	var pr := rig.wheel_r.global_position - up * rig.wheel_rr
	var fwd := (pf - pr).normalized()
	var side := fwd.cross(up).normalized()
	var mid := (pf + pr) * 0.5
	var wb := pf.distance_to(pr)
	# [centre, length along the bike, width, strength, softness]
	for s in [[mid, wb + 2.2 * rig.wheel_rf, 0.55, 0.22, 1.6],
			[pf, 0.55, 0.16, 0.55, 1.8], [pr, 0.55, 0.16, 0.55, 1.8]]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(1, 1)
		mi.mesh = pm
		var mat := ShaderMaterial.new(); mat.shader = _shadow_shader
		mat.set_shader_parameter("strength", s[3] * k); mat.set_shader_parameter("softness", s[4])
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("no_frame", true)   # not counted when the picture is framed
		rig.add_child(mi)
		mi.global_transform = Transform3D(Basis(fwd * s[1], up, side * s[2]), s[0] + up * 0.002)

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


## one flat pedal (the drive side's), from a model's pedal pair (BikeRig.pedal_set); `own` = the frame's glb ("stock").
## Pin-studded platform seen from above and a little in front, in the frame model's own pedal material.
static func make_pedal(id: String, own: String) -> Node3D:
	var set := BikeRig.pedal_set(id, own)
	var mi := MeshInstance3D.new()
	if set.has(1.0): mi.mesh = set[1.0][0]
	elif set.has(-1.0): mi.mesh = set[-1.0][0]
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


# ---------------------------------------------------------------- close-ups on the whole bike / rider
## the stock frame built with `build`, the picture a close-up of one spot on it: "stem", "levers", "rotor", "caliper",
## "bars" / "fork" (the action cam mounts). Parts that only make sense where they sit are shown there.
static func make_bike_spot(build: Dictionary, spot: String) -> Node3D:
	var cfg := GameState.bike_config_for("dh")
	var rig := BikeRig.new()
	rig.load_bike(cfg, build)
	if spot == "light": rig.set_lights_on(true)   # the lamp's lens glows on its card
	rig.set_meta("focus", _spot_box.bind(rig, spot))
	return rig

static func _spot_box(rig: BikeRig, spot: String) -> AABB:
	var c := Vector3.ZERO
	var r := 0.1
	var sx := rig.steer_n.global_transform
	var mid := (rig.grip_l + rig.grip_r) * 0.5
	match spot:
		"stem": c = sx * _stem_top(rig.steer_n as MeshInstance3D) + Vector3(0, -0.02, 0); r = 0.065
		"levers": c = sx * rig.grip_l.lerp(mid, 0.15); r = 0.065
		"bars": c = sx * mid.lerp(rig.grip_r, 0.33); r = 0.08
		"light":   # the lamp (or where it would go on the bar)
			if not rig.bike_lights.is_empty():
				c = (rig.bike_lights[0].node as Node3D).global_position + Vector3(0, 0.03, 0); r = 0.11
			else:
				c = sx * mid.lerp(rig.grip_l, 0.36); r = 0.09
		"rotor", "caliper":   # the rotor itself (front / rear), the caliper sits on its edge
			for ro in rig.rotors:
				var mi: MeshInstance3D = ro.mesh_instance
				if mi and mi.get_parent() == (rig.wheel_f if spot == "rotor" else rig.wheel_r):
					var bb := mi.global_transform * mi.get_aabb()
					c = bb.get_center(); r = maxf(bb.size.x, bb.size.y) * 0.36
					if spot == "caliper": r *= 1.15
		"fork":
			var fl := rig.model.find_child("fork_lower", true, false) as Node3D
			c = (rig.action_cam.global_position if rig.action_cam else fl.global_position) + Vector3(0, -0.05, 0); r = 0.16
	return AABB(c - Vector3.ONE * r, Vector3.ONE * 2.0 * r)

## the top of the steerer / stem in the steer mesh (the highest point within 3 cm of the bike's middle plane)
static func _stem_top(mi: MeshInstance3D) -> Vector3:
	var best := Vector3(0, -INF, 0)
	if mi == null or mi.mesh == null: return Vector3.ZERO
	for si in mi.mesh.get_surface_count():
		for v in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(v.z) < 0.03 and v.y > best.y: best = v
	return best

## a wheelset like a product photo: the pair stood up, turned three-quarters, the second one behind and beside the first
static func make_wheelset(spec: Dictionary) -> Node3D:
	var m := WheelGen.build(spec)
	var root := Node3D.new()
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.rotation.y = -0.62
		mi.position = Vector3(0.36 * i, 0.0, -0.3 * i)
		root.add_child(mi)
	return root

## one paintable part alone (BikeBuild.PARTS), cut out of the whole bike built with `build`: every other surface hidden,
## the picture framed on what's left
static func make_paint_part(bike_id: String, build: Dictionary, part: String) -> Node3D:
	var cfg := GameState.bike_config_for(bike_id)
	var rig := BikeRig.new()
	rig.load_bike(cfg, build)
	var targets: Array = (BikeBuild.PARTS[part][1] as Array).duplicate()
	if part == "stanchions": targets.append(["fork_crown", "gold"])   # a fork model's own crowns + stanchions
	if part == "crown": targets.append(["fork_crown", "black"])
	var hide := StandardMaterial3D.new()
	hide.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hide.albedo_color = Color(0, 0, 0, 0)
	var kept := []   # [mesh instance, surface]
	var crank := rig.model.find_child("crank", true, false)
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var pedal: bool = crank != null and m.get_parent() != null and m.get_parent().get_parent() == crank and m.name != "rotor"
		var any := false
		if m.mesh:
			for i in m.mesh.get_surface_count():
				var sm := m.mesh.surface_get_material(i)
				var keep := pedal and part == "saddle"
				for t in targets:
					if m.name == t[0] and sm and sm.resource_name == t[1]: keep = true
				if keep: kept.append([m, i]); any = true
				else: m.set_surface_override_material(i, hide)
		if not any and m.material_override != null: m.material_override = hide   # (never hide the node: its children may be kept)
	rig.set_meta("focus", func():
		var box := AABB()
		var first := true
		for k in kept:
			var vs: PackedVector3Array = (k[0] as MeshInstance3D).mesh.surface_get_arrays(k[1])[Mesh.ARRAY_VERTEX]
			var xf: Transform3D = (k[0] as MeshInstance3D).global_transform
			for i in range(0, vs.size(), maxi(1, vs.size() / 300)):
				var p: Vector3 = xf * vs[i]
				if first: box = AABB(p, Vector3.ZERO); first = false
				else: box = box.expand(p)
		return box)
	return rig

## a paint sample: a glossy ball in that paint (colour, shift colour, finish)
static func make_ball(p: Dictionary) -> Node3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1; sm.height = 0.2; sm.radial_segments = 48; sm.rings = 24
	mi.mesh = sm
	mi.material_override = BikeBuild.paint_material(p)
	var key := OmniLight3D.new()   # a close soft box: a clear highlight, so gloss / satin / matte / chrome read apart
	key.position = Vector3(-0.18, 0.26, 0.3)
	key.light_energy = 2.2; key.omni_range = 1.2; key.light_size = 0.06
	mi.add_child(key)
	return mi

## a saddle alone (assets/seats/saddle_<id>.glb; the stock one is saddle_dh)
static func make_saddle(id: String) -> Node3D:
	var f := "res://assets/seats/saddle_%s.glb" % ("dh" if id == "stock" else id)
	return load(f).instantiate() if ResourceLoader.exists(f) else Node3D.new()

## an action camera alone with its gear (lens, housing, mic, top accessory), on its helmet buckle
static func make_cam(gear: Dictionary) -> Node3D:
	return ActionCam.build("top", gear)

## the rider's head in `look` (helmet model, hair, helmet cam): a standing rider, posed until the hair has settled;
## the picture frames the head (`below` m more under it: hair hanging down the back)
static func make_head(look: Dictionary, below := 0.0) -> Node3D:
	var r := Rider.new()
	var t := [0.0]
	r.set_meta("setup", func():
		r.set_look(look)
		r.use_helmet(str(look.get("helmet", "glory")))
		r.set_style(STAND_POSE))
	r.set_meta("tick", func(dt: float):
		t[0] += dt
		r.update_pose(dt, {"footL": Vector3(0.0, 0.0, -0.13), "footR": Vector3(0.02, 0.0, 0.13),
			"handL": Vector3(0.02, 0.83, -0.29), "handR": Vector3(0.04, 0.83, 0.29),
			"v": 0.0, "lean": 0.0, "steer": 0.0, "yawRate": 0.0, "counter": 0.0, "rockRoll": 0.0, "headRoll": 0.0,
			"absorb": 0.0, "pitch": 0.0, "bodyLevel": 0.85, "attackDrop": 0.0, "pedal": 0.0, "sprint": 0.0,
			"crank": 0.0, "air": 0.0, "compress": 0.0, "hipShift": 0.0, "t": t[0], "stand": 1.0, "relax": 1.0}))
	r.set_meta("settle", 36 if below > 0.0 else 3)   # only hanging hair needs time to fall
	r.set_meta("focus", func():
		var c: Vector3 = r.head.global_position + Vector3(0, 0.06 - below * 0.5, 0)
		var e := Vector3(0.12, 0.12 + below * 0.5, 0.12)
		return AABB(c - e, e * 2.0))
	return r

const STAND_POSE := {"hipX": 0.17, "hipY": 0.16, "lean": -0.66, "crouch": 0.0, "standPedal": 0.0, "sway": 0.0,
	"elbowsOut": -0.2, "kneesOut": 0.0, "stance": 0.0, "headTilt": 0.08, "headTurn": 0.0, "hipSway": 0.0}
