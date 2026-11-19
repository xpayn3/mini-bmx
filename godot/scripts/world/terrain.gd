class_name Terrain
extends Node3D
## The procedural world (port of terrain.js and friends). Same seed -> same landscape and the same
## height function as the JS. Chunks (48 m) stream in around the player: they are built on worker
## threads (TerrainChunkBuilder) and turned into nodes here, time-sliced by update_stream(budget_ms).
##
## Physics API: height(), deck_height(), surface(), jump(), colliders_near(), biome_name(), ground_color().

const WATER := -2.2
const SIZE := 48.0
const RADIUS := 3
const ROCK_CELL := 2.0
var view_scale := 1.0   # Settings view distance: scales the decoration draw ranges
const LAYER_GROUND := 1 << 1    # physics layer 2: chunk ground colliders (only for debris)

## ground mesh / texture resolution per 48 m chunk (JS: 128 -> 0.375 m). 96 = 0.5 m keeps the
## worker-thread build time per chunk sane in GDScript.
@export var seg: int = 96
## worker threads building chunks. GDScript calls contend across threads in this engine build (beyond
## ~4 workers each chunk gets slower), so: 0 = auto = clamp(cores - 2, 1, 4) while streaming, 6 at spawn.
@export var max_jobs: int = 0
@export var spawn_jobs: int = 6
@export var water_enabled: bool = true

## the terrain math in C# (TerrainFieldCs.cs: same results as the GDScript TerrainField, bit for bit, ~10x
## faster). false = everything through the GDScript TerrainField, which stays the reference. Falls back
## to GDScript by itself when the C# assembly can't be loaded (e.g. a non-.NET Godot build).
const USE_CS := true
const CS_FIELD := "res://scripts/world/TerrainFieldCs.cs"
var use_cs := USE_CS and OS.get_environment("BMX_TERRAIN_GD") == ""   # env BMX_TERRAIN_GD=1: GDScript (A/B runs); tools flip it before set_seed()

var seed_value: int = 0
var field: TerrainField          # GDScript field: the seed's course / route tables (and every query without C#)
var fcs = null                   # TerrainFieldCs on the main thread (physics queries), or null
var chunks := {}                 # Vector2i -> chunk record (Dictionary)
var _jobs := {}                  # Vector2i -> {task, builder}
var _stale_tasks: Array = []     # task ids of a previous seed / far away, still to be joined
var _gen: int = 0
var _rock_grid := {}             # int key -> Array[collider]
var _col_grid := {}              # 4 m cell key -> Array[collider] (by collider centre)
const COL_CELL := 4.0
var _indices := PackedInt32Array()
var _indices_n: int = -1
var _ground_shader: Shader = preload("res://scripts/world/ground.gdshader")
var _tape_mat: ShaderMaterial
var _debris: TerrainDebris
var _tapes: TapeSim              # torn tape ribbons (tape.js TapeSim)
var _focus := Vector2.ZERO       # last update_stream() position: the torn tape simulates near it
var _water: TerrainWater
var _broken: Array = []          # [{kind, rec}] for clear_dynamic()
var _time: float = 0.0
var _wind_t: float = 0.0
var _wind_ph: float = 0.0
var _wind_dir := Vector3(0.8, 0, 0.6)
var _wind_ws: float = 6.0
## the endless trail: once the rider is within GROW_AHEAD m (along x) of the end of the course laid out
## so far, a worker lays out GROW_STEP m more on a fork of the field; the main thread then takes it over
const GROW_AHEAD := 2000.0
const GROW_STEP := 3000.0
var _grow_task: int = -1
var _grow_gen: int = -1
var _grow_box: Array = []   # the running grow job's result (each job has its own box)
var last_finalize_ms: float = 0.0
var last_build_ms: float = 0.0
## profiling (--hitch): main-thread ms of the last update_stream() call, chunks finalized in it, and
## that time split into ground mesh+textures / occluder / collider / decorations / grids+tape
var last_stream_ms: float = 0.0
var last_finalized: int = 0
var fin_parts := PackedFloat64Array([0, 0, 0, 0, 0])


## seed_in: the world to build (pass it here rather than calling set_seed afterwards, which would
## generate the world twice)
func _init(seed_in := 12345) -> void:
	TerrainGeo.ensure()
	TerrainChunkBuilder.ensure_static()
	_tape_mat = ShaderMaterial.new()
	_tape_mat.shader = preload("res://scripts/world/tape.gdshader")
	_debris = TerrainDebris.new()
	_debris.name = "Debris"
	add_child(_debris)
	_tapes = TapeSim.new()
	_tapes.name = "TornTape"
	_tapes.terrain = self
	add_child(_tapes)
	_water = TerrainWater.new()
	_water.name = "Water"
	_water.terrain = self
	add_child(_water)
	set_seed(seed_in)


func _exit_tree() -> void:
	_join_all()


func _process(delta: float) -> void:
	_time += delta
	_update_wind(delta)
	_tapes.update(delta, _focus.x, _focus.y, _wind_t, _wind_dir, _wind_ws)


# ======================================================================
# world state
# ======================================================================
func set_seed(seed_in: int) -> void:
	seed_value = seed_in
	_gen += 1
	for k in chunks.keys():
		_unload(k)
	chunks.clear()
	for k in _jobs:
		_stale_tasks.append(_jobs[k]["task"])
	_jobs.clear()
	if _grow_task >= 0:
		_stale_tasks.append(_grow_task)
		_grow_task = -1
	_rock_grid.clear()
	_col_grid.clear()
	_broken.clear()
	if _debris:
		_debris.clear()
	if _tapes:
		_tapes.clear()
	field = TerrainField.new()
	field.setup(seed_in)
	fcs = _make_cs() if use_cs else null
	if fcs != null:
		fcs.setup_from(field)   # takes over the finished noise / course / route tables
	if _water:
		_water.invalidate()


func clear_dynamic() -> void:
	_debris.clear()
	_tapes.clear()
	for b in _broken:
		var rec: Dictionary = b["rec"]
		rec["broken"] = false
		match b["kind"]:
			"fence":
				for part in rec["parts"]:
					var mm: MultiMesh = rec["meshes"].get(part["kind"])
					if mm:
						mm.set_instance_transform(part["i"], part["xform"])
			"cactus":
				var mm2: MultiMesh = rec.get("mm")
				if mm2:
					mm2.set_instance_transform(rec["i"], rec["xform"])
			"tape":
				var ch = chunks.get(rec.get("chunk", Vector2i(1 << 30, 0)))
				if ch != null:
					_rebuild_tape(ch)
	_broken.clear()


# ======================================================================
# physics queries
# ======================================================================
static func _make_cs():
	if not ResourceLoader.exists(CS_FIELD):
		return null
	var sc = load(CS_FIELD)
	if sc == null or not sc.can_instantiate():
		push_warning("Terrain: C# field unavailable, using the GDScript TerrainField")
		return null
	return sc.new()


## the field the chunk builders fork: the C# one when it's on
func query_field():
	return fcs if fcs != null else field


static func _chunk_id(k: Vector2i) -> int:
	return k.x * 1048576 + k.y


static func _rock_key(gx: int, gz: int) -> int:
	return WorldRng.i32(gx * 73856093) ^ WorldRng.i32(gz * 19349663)


## what you ride on: ground, a wooden deck, and a dome over every rock / log / stump of loaded chunks
func height(x: float, z: float) -> float:
	if fcs != null:
		return fcs.height(x, z)   # the same, domes included (mirrored by _finalize / _unload)
	var f := field
	var g := f.ground(x, z)
	if f.has_wood and f.wood > g:
		g = f.wood
	var list = _rock_grid.get(_rock_key(floori(x / ROCK_CELL), floori(z / ROCK_CELL)))
	if list != null:
		for c in list:
			var dx: float = x - c["x"]
			var dz: float = z - c["z"]
			var r: float = c["r"]
			var q := (dx * dx + dz * dz) / (r * r)
			if q < 1.0:
				var base: float = c["base"]
				var h: float = base + (c["top"] - base) * sqrt(1.0 - q)
				if h > g:
					g = h
	return g


## the ground or a wooden deck WITHOUT the rock / log domes (JS's shadowed surface(): cliff-wall test)
func deck_height(x: float, z: float) -> float:
	if fcs != null:
		return fcs.deck(x, z)
	return field.deck(x, z)


## 0 grass, 1 trail, 2 water, 3 sand (beaches, dunes)
func surface(x: float, z: float) -> int:
	var h := height(x, z)
	if fcs != null:
		return fcs.surface_at(x, z, h)
	if h < WATER - 0.05:
		return 2
	if field.trail(x, z) > 0.5:
		return 1
	if h < WATER + 0.45:
		return 3
	field.biome(x, z)
	if field.b_dry > 0.7:
		return 3
	return 0


## [feature height, mask, flattened ground height, dug depth, wood deck top or null]
func jump(x: float, z: float) -> Array:
	if fcs != null:
		return fcs.jump(x, z)
	return field.jump(x, z)


func jump_mask(x: float, z: float) -> float:
	if fcs != null:
		return fcs.jump_mask(x, z)
	return field.jump_mask(x, z)


func biome_name(x: float, z: float) -> String:
	if fcs != null:
		return fcs.biome_name(x, z)
	return field.biome_name(x, z)


## the flattened terrain colour (JS color(x, z, height, ny = 1)), returned in sRGB (Godot convention)
func ground_color(x: float, z: float, ny: float = 1.0) -> Color:
	var h := height(x, z)
	var c: Color = fcs.color(x, z, h, ny) if fcs != null else field.color(x, z, h, ny)
	return c.linear_to_srgb()


func trail(x: float, z: float) -> float:
	if fcs != null:
		return fcs.trail(x, z)
	return field.trail(x, z)


static func _col_key(gx: int, gz: int) -> int:
	return gx * 1000003 + gz


## everything within 3 m (by centre) that can be hit: trees, rocks, logs, stumps, sheds, fences, tape, cacti
func colliders_near(x: float, z: float) -> Array:
	var out := []
	for gx in range(floori((x - 3.0) / COL_CELL), floori((x + 3.0) / COL_CELL) + 1):
		for gz in range(floori((z - 3.0) / COL_CELL), floori((z + 3.0) / COL_CELL) + 1):
			var l = _col_grid.get(_col_key(gx, gz))
			if l == null:
				continue
			for k in l:
				if absf(k["x"] - x) < 3 and absf(k["z"] - z) < 3:
					if k.has("fence") and k["fence"]["broken"]:
						continue
					if k.has("tape") and k["tape"]["broken"]:
						continue
					if k.has("cactus") and k["cactus"]["broken"]:
						continue
					out.append(k)
	return out


# ======================================================================
# streaming
# ======================================================================
func _max_jobs() -> int:
	if max_jobs > 0:
		return max_jobs
	return clampi(OS.get_processor_count() - 2, 1, 4)


func update_stream(px: float, pz: float, budget_ms: float = 4.0) -> void:
	var t0 := Time.get_ticks_usec()
	last_finalized = 0
	fin_parts.fill(0.0)
	_focus = Vector2(px, pz)
	_update_grow(px)
	var ccx := WorldRng.jround(px / SIZE)
	var ccz := WorldRng.jround(pz / SIZE)
	var R := RADIUS
	for k in chunks.keys():
		if absi(k.x - ccx) > R + 1 or absi(k.y - ccz) > R + 1:
			_unload(k)
	for k in _jobs.keys():
		if absi(k.x - ccx) > R + 1 or absi(k.y - ccz) > R + 1:
			_stale_tasks.append(_jobs[k]["task"])
			_jobs.erase(k)
	_reap_stale(false)
	# ground clutter only in the 3x3 chunks round the rider
	for k in chunks:
		var near: bool = absi(k.x - ccx) <= 1 and absi(k.y - ccz) <= 1
		for o in chunks[k]["small"]:
			o.visible = near
	if is_inf(budget_ms):
		var queue := _missing(ccx, ccz)
		var lim := maxi(spawn_jobs, _max_jobs())
		while not queue.is_empty() or not _jobs.is_empty():
			while _jobs.size() < lim and not queue.is_empty():
				var k: Vector2i = queue.pop_front()
				if not _jobs.has(k):
					_dispatch(k, true)
			var any := false
			for k in _jobs.keys():
				if WorkerThreadPool.is_task_completed(_jobs[k]["task"]):
					WorkerThreadPool.wait_for_task_completion(_jobs[k]["task"])
					_finalize(k)
					any = true
			if not any:
				OS.delay_usec(500)
		_reap_stale(true)
		last_stream_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return
	_dispatch_missing(ccx, ccz)
	var budget_us := budget_ms * 1000.0
	var done_one := false
	while true:
		var best = null
		var bd := 1 << 30
		for k in _jobs:
			if WorkerThreadPool.is_task_completed(_jobs[k]["task"]):
				var d: int = (k.x - ccx) * (k.x - ccx) + (k.y - ccz) * (k.y - ccz)
				if d < bd:
					bd = d
					best = k
		if best == null:
			break
		# a chunk right next to the rider: allow a bigger slice so it never stays a hole. Anything
		# further out is one chunk per frame: crossing a chunk border finishes a whole row (7) at
		# once out at the edge of the fog, and turning several into nodes in one frame was a 3-5 ms hitch.
		var near := bd <= 2
		var lim := budget_us * (3.0 if near else 1.0)
		if done_one and (not near or Time.get_ticks_usec() - t0 > lim):
			break
		WorkerThreadPool.wait_for_task_completion(_jobs[best]["task"])
		_finalize(best)
		done_one = true
		if Time.get_ticks_usec() - t0 > lim:
			break
	_dispatch_missing(ccx, ccz)
	last_stream_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _missing(ccx: int, ccz: int) -> Array:
	var out := []
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var k := Vector2i(ccx + dx, ccz + dz)
			if not chunks.has(k):
				out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x - ccx) * (a.x - ccx) + (a.y - ccz) * (a.y - ccz) < (b.x - ccx) * (b.x - ccx) + (b.y - ccz) * (b.y - ccz))
	return out


func _dispatch_missing(ccx: int, ccz: int) -> void:
	if _jobs.size() >= _max_jobs():
		return
	for k in _missing(ccx, ccz):
		if _jobs.size() >= _max_jobs():
			break
		if not _jobs.has(k):
			_dispatch(k)


func _dispatch(k: Vector2i, urgent: bool = false) -> void:
	var b := TerrainChunkBuilder.new(query_field().fork(), k.x, k.y, seg, _gen)
	var task := WorkerThreadPool.add_task(b.run, urgent, "terrain chunk")
	_jobs[k] = {"task": task, "builder": b}


func _update_grow(px: float) -> void:
	if _grow_task >= 0:
		if not WorkerThreadPool.is_task_completed(_grow_task):
			return
		WorkerThreadPool.wait_for_task_completion(_grow_task)
		_grow_task = -1
		if _grow_gen == _gen and not _grow_box.is_empty():
			var t0 := Time.get_ticks_usec()
			field.adopt_course(_grow_box[0])
			if fcs != null:
				fcs.rebind_course(field)
			print("TRAIL grown to x=%.0f (%d points), adopted in %.1f ms" % [field.course.end_x(), field.course.n,
				(Time.get_ticks_usec() - t0) / 1000.0])
		_grow_box = []
		return
	var end := field.course.end_x()
	if px < end - GROW_AHEAD:
		return
	var src := field
	var to := end + GROW_STEP
	_grow_gen = _gen
	var box := []
	_grow_box = box
	_grow_task = WorkerThreadPool.add_task(func():
		var t0 := Time.get_ticks_usec()
		var g := src.fork()
		g.grow_course(to)
		box.append(g)
		print("TRAIL grow on worker: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)), false, "trail grow")


func _reap_stale(block: bool) -> void:
	var keep := []
	for t in _stale_tasks:
		if block or WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			keep.append(t)
	_stale_tasks = keep


func _join_all() -> void:
	for k in _jobs:
		_stale_tasks.append(_jobs[k]["task"])
	_jobs.clear()
	_reap_stale(true)


func _unload(k: Vector2i) -> void:
	var c = chunks.get(k)
	if c == null:
		return
	if fcs != null:
		fcs.domes_remove(_chunk_id(k))
	for key in c["rock_keys"]:
		var l = _rock_grid.get(key)
		if l == null:
			continue
		var nl := []
		for r in l:
			if r["chunk"] != k:
				nl.append(r)
		if nl.is_empty():
			_rock_grid.erase(key)
		else:
			_rock_grid[key] = nl
	for key in c["col_keys"]:
		var l = _col_grid.get(key)
		if l == null:
			continue
		var nl := []
		for r in l:
			if r["chunk"] != k:
				nl.append(r)
		if nl.is_empty():
			_col_grid.erase(key)
		else:
			_col_grid[key] = nl
	(c["node"] as Node).queue_free()
	if _debris: _debris.drop_chunk(k)
	chunks.erase(k)
	if _water:
		_water.mark_dirty(Vector2(k) * SIZE, SIZE)


func _grid_indices(n: int) -> PackedInt32Array:
	if _indices_n == n:
		return _indices
	var nv := n + 1
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var o := 0
	for iz in n:
		for ix in n:
			var v00 := iz * nv + ix
			var v10 := v00 + 1
			var v01 := v00 + nv
			var v11 := v01 + 1
			# clockwise seen from above (Godot front faces)
			idx[o] = v00; idx[o + 1] = v10; idx[o + 2] = v01
			idx[o + 3] = v10; idx[o + 4] = v11; idx[o + 5] = v01
			o += 6
	_indices = idx
	_indices_n = n
	return idx


const LIST_SPEC := {
	# name: [mesh, material, cast shadow, small clutter]
	"trunk": ["trunk", "trunk", true, false], "blob": ["blob", "leafSoft", true, false], "pine": ["pine", "leaf", true, false],
	"rock": ["rock", "rock", true, false], "pebble": ["pebble", "rock", false, true], "grass": ["grass", "flower", false, true],
	"daisy": ["daisy", "flower", false, true], "tulip": ["tulip", "flower", false, true], "spike": ["spike", "flower", false, true],
	"bush": ["bush", "leafSoft", true, false], "log": ["log", "trunk", true, false], "weed": ["weed", "tuft", true, false],
	"stick": ["stick", "trunk", false, true], "fern": ["fern", "flower", false, true], "mushroom": ["mushroom", "flower", false, true],
	"cactus0": ["cactus0", "cactus", true, false], "cactus1": ["cactus1", "cactus", true, false], "cactus2": ["cactus2", "cactus", true, false],
	"cactus3": ["cactus3", "cactus", true, false], "cactus4": ["cactus4", "cactus", true, false],
	"plank": ["box", "wood", true, false], "beam": ["box", "wood", true, false],
	"post": ["post", "fence", true, false], "rail": ["rail", "fence", true, false], "picket": ["picket", "fence", true, false],
	"stake": ["stake", "stake", true, false],
}


## how far (m, camera to the chunk's centre) each kind of decoration is drawn; past the fog they fade
## out. Small ground clutter is also limited to the 3x3 chunks round the rider (update_stream).
const VIS_RANGE := {"pebble": 90.0, "grass": 90.0, "daisy": 90.0, "tulip": 90.0, "spike": 90.0, "stick": 90.0,
	"fern": 90.0, "mushroom": 90.0, "weed": 130.0, "bush": 170.0, "log": 170.0, "rock": 200.0,
	"plank": 150.0, "beam": 150.0, "post": 150.0, "rail": 150.0, "picket": 150.0, "stake": 150.0}

## the view-distance setting: rescales the draw range of decorations already built, not just new chunks
func set_view_scale(s: float) -> void:
	if is_equal_approx(s, view_scale):
		return
	view_scale = s
	for k in chunks:
		var n = chunks[k].get("node")
		if not is_instance_valid(n): continue
		for mi in (n as Node).find_children("*", "MultiMeshInstance3D", true, false):
			if mi.has_meta("vis"):
				mi.visibility_range_end = float(mi.get_meta("vis")) * view_scale


func _multimesh(parent: Node3D, mesh: Mesh, mat: Material, buf: PackedFloat32Array, count: int, cast: bool, vis := 0.0) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis > 0.0:
		mi.set_meta("vis", vis)
		mi.visibility_range_end = vis * view_scale
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mm


func _finalize(k: Vector2i) -> void:
	var job: Dictionary = _jobs[k]
	_jobs.erase(k)
	var b: TerrainChunkBuilder = job["builder"]
	if b.gen != _gen:
		return
	var t0 := Time.get_ticks_usec()
	var tp := t0
	last_finalized += 1
	last_build_ms = b.ms_used
	var o: Dictionary = b.out
	var ox := k.x * SIZE
	var oz := k.y * SIZE
	var node := Node3D.new()
	node.name = "Chunk_%d_%d" % [k.x, k.y]
	add_child(node)
	# ground
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = o["verts"]
	arr[Mesh.ARRAY_NORMAL] = o["norms"]
	arr[Mesh.ARRAY_TEX_UV] = o["uvs"]
	arr[Mesh.ARRAY_INDEX] = o["indices"]
	var mesh := ArrayMesh.new()
	# distance LOD: coarser grids keyed by their geometric error (terrain_chunk_builder._ground_lods)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], o["lods"])
	var mat := ShaderMaterial.new()
	mat.shader = _ground_shader
	mat.set_shader_parameter("land_tex", ImageTexture.create_from_image(o["land_img"]))
	mat.set_shader_parameter("dirt_tex", ImageTexture.create_from_image(o["dirt_img"]))
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = mat
	gi.position = Vector3(ox, 0, oz)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(gi)
	fin_parts[0] += (Time.get_ticks_usec() - tp) / 1000.0; tp = Time.get_ticks_usec()
	# occluder: a coarse copy of the ground (4 m grid) sunk 0.6 m under it, so hills hide what's behind
	# them when occlusion culling is on (Settings "occlusion"); always under the real surface = safe
	var hm: PackedFloat32Array = o["hm"]
	var occ_v := PackedVector3Array()
	var occ_i := PackedInt32Array()
	for iz in 13:
		for ix in 13:
			var hx := mini(ix * 4, 48)
			var hz := mini(iz * 4, 48)
			occ_v.append(Vector3(hx - 24.0, hm[hz * 49 + hx] - 0.6, hz - 24.0))
	for iz in 12:
		for ix in 12:
			var v0 := iz * 13 + ix
			occ_i.append_array([v0, v0 + 1, v0 + 13, v0 + 1, v0 + 14, v0 + 13])
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(occ_v, occ_i)
	var oi := OccluderInstance3D.new()
	oi.occluder = occ
	oi.position = Vector3(ox, 0, oz)
	node.add_child(oi)
	fin_parts[1] += (Time.get_ticks_usec() - tp) / 1000.0; tp = Time.get_ticks_usec()
	# cheap collider for debris only (layer 2)
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_GROUND
	body.collision_mask = 0
	body.position = Vector3(ox, 0, oz)
	var shape := HeightMapShape3D.new()
	shape.map_width = 49
	shape.map_depth = 49
	shape.map_data = o["hm"]
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)
	fin_parts[2] += (Time.get_ticks_usec() - tp) / 1000.0; tp = Time.get_ticks_usec()
	# instanced decorations
	var counts: Dictionary = o["counts"]
	var lists: Dictionary = o["lists"]
	var mms := {}
	var small := []
	for name in LIST_SPEC:
		var n: int = counts.get(name, 0)
		if n == 0:
			continue
		var spec: Array = LIST_SPEC[name]
		var mm := _multimesh(node, TerrainGeo.MESH[spec[0]], TerrainGeo.MAT[spec[1]], lists[name], n, spec[2], VIS_RANGE.get(name, 0.0))
		mms[name] = mm
		if spec[3]:
			small.append(node.get_child(node.get_child_count() - 1))
	var sheds: Array = o["sheds"]
	for i in sheds.size():
		var buf: PackedFloat32Array = sheds[i]
		if buf.size() > 0:
			_multimesh(node, TerrainGeo.SHEDS[i], TerrainGeo.MAT["shed"], buf, buf.size() / 16, true)
	for p in o["panels"]:
		p["meshes"] = mms
	fin_parts[3] += (Time.get_ticks_usec() - tp) / 1000.0; tp = Time.get_ticks_usec()
	var colliders: Array = o["colliders"]
	var rec := {"cx": k.x, "cz": k.y, "node": node, "colliders": colliders, "small": small, "rock_keys": [],
		"G": o["G"], "N": b.N, "mms": mms}
	for c in colliders:
		if c.has("cactus"):
			c["cactus"]["mm"] = mms.get("cactus%d" % c["cactus"].get("kind", 0))
	# race tape
	if o.has("tape"):
		var t: Dictionary = o["tape"]
		rec["tape"] = t
		var tmi := MeshInstance3D.new()
		tmi.material_override = _tape_mat
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(tmi)
		rec["tape_mi"] = tmi
		for sp in t["spans"]:
			sp["chunk"] = k
		_rebuild_tape(rec)
	# rocks / logs / stumps into the dome grid
	var keys := {}
	for c in colliders:
		if not c.has("top"):
			continue
		c["chunk"] = k
		var r: float = c["r"]
		for gx in range(floori((c["x"] - r) / ROCK_CELL), floori((c["x"] + r) / ROCK_CELL) + 1):
			for gz in range(floori((c["z"] - r) / ROCK_CELL), floori((c["z"] + r) / ROCK_CELL) + 1):
				var key := _rock_key(gx, gz)
				if not _rock_grid.has(key):
					_rock_grid[key] = []
				_rock_grid[key].append(c)
				keys[key] = true
	rec["rock_keys"] = keys.keys()
	if fcs != null:
		var dd := PackedFloat64Array()
		for c in colliders:
			if c.has("top"):
				dd.append_array([c["x"], c["z"], c["r"], c["base"], c["top"]])
		fcs.domes_add(_chunk_id(k), dd)
	var ckeys := {}
	for c in colliders:
		c["chunk"] = k
		var key := _col_key(floori(c["x"] / COL_CELL), floori(c["z"] / COL_CELL))
		if not _col_grid.has(key):
			_col_grid[key] = []
		_col_grid[key].append(c)
		ckeys[key] = true
	rec["col_keys"] = ckeys.keys()
	chunks[k] = rec
	if _water:
		_water.mark_dirty(Vector2(k) * SIZE, SIZE)
	fin_parts[4] += (Time.get_ticks_usec() - tp) / 1000.0
	last_finalize_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _rebuild_tape(rec: Dictionary) -> void:
	var t: Dictionary = rec["tape"]
	var c0: PackedFloat32Array = t["c0"].duplicate()
	for sp in t["spans"]:
		if sp["broken"]:
			var v0: int = sp["v0"]
			for v in range(v0, v0 + TerrainChunkBuilder.TAPE_SEG * 6):
				c0[v * 4 + 3] = 0.0
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = t["pos"]
	arr[Mesh.ARRAY_NORMAL] = t["nrm"]
	arr[Mesh.ARRAY_COLOR] = t["col"]
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = t["c1"]
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	m.custom_aabb = m.get_aabb().grow(1.0)
	(rec["tape_mi"] as MeshInstance3D).mesh = m


## the ground exactly as drawn: the full-detail chunk mesh's own triangles (0.5 m grid, split along
## the (x+1, z) - (x, z+1) diagonal like _grid_lod_indices). In hollows it sits above height(), which
## is the smooth field. -INF where no chunk is loaded.
func mesh_height(x: float, z: float) -> float:
	var k := Vector2i(WorldRng.jround(x / SIZE), WorldRng.jround(z / SIZE))
	var c = chunks.get(k)
	if c == null:
		return -INF
	var N: int = c["N"]
	var d := SIZE / N
	var W := N + 3
	var G: PackedFloat32Array = c["G"]
	var gx := (x - (k.x * SIZE - SIZE / 2)) / d
	var gz := (z - (k.y * SIZE - SIZE / 2)) / d
	var ix := clampi(floori(gx), 0, N - 1)
	var iz := clampi(floori(gz), 0, N - 1)
	var tx := gx - ix
	var tz := gz - iz
	var b := (iz + 1) * W + ix + 1
	var h00 := G[b]
	var h10 := G[b + 1]
	var h01 := G[b + W]
	var h11 := G[b + W + 1]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


## the highest solid thing drawn here: the ground mesh, a wooden deck, or a rock / log / stump dome
func top_height(x: float, z: float) -> float:
	return maxf(height(x, z), mesh_height(x, z))


## ground height from the loaded chunk grids (bilinear, no domes / wood); NAN where nothing is loaded
func grid_height(x: float, z: float) -> float:
	var k := Vector2i(WorldRng.jround(x / SIZE), WorldRng.jround(z / SIZE))
	var c = chunks.get(k)
	if c == null:
		return NAN
	var N: int = c["N"]
	var d := SIZE / N
	var W := N + 3
	var G: PackedFloat32Array = c["G"]
	var gx := (x - (k.x * SIZE - SIZE / 2)) / d + 1.0
	var gz := (z - (k.y * SIZE - SIZE / 2)) / d + 1.0
	var x0 := clampi(floori(gx), 0, W - 2)
	var z0 := clampi(floori(gz), 0, W - 2)
	var tx := gx - x0
	var tz := gz - z0
	var a := lerpf(G[z0 * W + x0], G[z0 * W + x0 + 1], tx)
	var b := lerpf(G[(z0 + 1) * W + x0], G[(z0 + 1) * W + x0 + 1], tx)
	return lerpf(a, b, tz)


# ======================================================================
# breakables
# ======================================================================
## fences / cacti: smash it (hide the visual, throw rigid-body debris); tape: snap it (hide the span, hand
## its two halves to the ribbon sim). Returns true if it broke.
func break_collider(c: Dictionary, vel: Vector3, at = null) -> bool:
	if c.has("fence"):
		var panel: Dictionary = c["fence"]
		if panel["broken"]:
			return false
		panel["broken"] = true
		_broken.append({"kind": "fence", "rec": panel})
		var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
		var hit := Vector2(c["x"], c["z"])
		for part in panel["parts"]:
			if not TerrainDebris.fence_part_goes(part, hit):
				continue   # a post you didn't hit stays standing
			var mm: MultiMesh = panel["meshes"].get(part["kind"])
			if mm:
				mm.set_instance_transform(part["i"], zero)
		_debris.smash_fence(panel, vel, hit, c.get("chunk"))
		return true
	if c.has("cactus"):
		var rec: Dictionary = c["cactus"]
		if rec["broken"]:
			return false
		rec["broken"] = true
		_broken.append({"kind": "cactus", "rec": rec})
		var mm: MultiMesh = rec.get("mm")
		if mm:
			mm.set_instance_transform(rec["i"], Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_debris.smash_cactus(rec, vel, at if at is Vector3 else Vector3(c["x"], rec["xform"].origin.y + 0.5, c["z"]), c.get("chunk"))
		return true
	if c.has("tape"):
		var sp: Dictionary = c["tape"]
		if sp["broken"]:
			return false
		sp["broken"] = true
		_broken.append({"kind": "tape", "rec": sp})
		var ch = chunks.get(sp.get("chunk"))
		if ch != null:
			_rebuild_tape(ch)
		_tapes.snap(sp, Vector2(c["x"], c["z"]), vel)
		return true
	return false


# ======================================================================
# water & wind
# ======================================================================
func update_water(px: float, pz: float, t: float) -> void:
	if water_enabled and _water:
		_water.follow(px, pz, t)


## the ride light (sun / moon direction + colour, sky at the horizon / overhead) for the water's reflections
func water_light(sun_dir: Vector3, sun_col: Color, sky_h: Color, sky_z: Color) -> void:
	if _water:
		var m := _water.material_override as ShaderMaterial
		m.set_shader_parameter("u_sun_dir", sun_dir.normalized())
		m.set_shader_parameter("u_sun_col", Vector3(sun_col.r, sun_col.g, sun_col.b))
		m.set_shader_parameter("u_sky_h", sky_h)
		m.set_shader_parameter("u_sky_z", sky_z)


func _update_wind(dt: float) -> void:
	_wind_t += dt
	var t := _wind_t
	var ang := atan2(0.6, 0.8) + sin(t * 0.05) * 0.8 + sin(t * 0.21) * 0.25
	var gust := 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 0.7) * sin(t * 0.31 + 1.3)) + 0.25 * maxf(0, sin(t * 1.9) * sin(t * 0.45))
	var ws := 4.0 * gust * 1.5
	_wind_dir = Vector3(cos(ang), 0, sin(ang))
	_wind_ws = ws
	_wind_ph += dt * (4.5 + ws * 0.7)
	_tape_mat.set_shader_parameter("u_time", t)
	_tape_mat.set_shader_parameter("u_wind", Vector3(cos(ang), 0, sin(ang)) * ws)
	_tape_mat.set_shader_parameter("u_ph", _wind_ph)
