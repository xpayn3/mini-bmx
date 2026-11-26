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
static var _gl_compat: bool = RenderingServer.get_rendering_device() == null   # OpenGL fallback renderer
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
## render layer bit only the ground meshes have (on top of layer 1): Decals with this cull mask paint the
## ground and nothing lying on it
const GROUND_LAYER := 1 << 10
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
var _ground_shader: Shader = preload("res://scripts/world/ground.gdshader")
## the trail's surface relief (assets/textures/trail/SOURCE.txt): the normals + roughness of two scans, packed dirt and
## loose gravel. Colour, rider lines, wear and puddles are procedural in ground.gdshader; the scans only add fine relief.
const TRAIL_SCANS := ["brown_mud_02", "gravelly_sand"]
static var _trail_debug := int(OS.get_environment("BMX_TRAIL_DEBUG"))
static var _trail_play := OS.get_environment("BMX_TRAIL_PLAY")   # test: 1 = a playful mark in every stretch
static var _trail_puddles := OS.get_environment("BMX_TRAIL_PUDDLES")   # test: 0 = none, 2 = on every wet road
static var _trail_tex: Array = []   # [nr0, nr1], loaded once
static func trail_textures() -> Array:
	if _trail_tex.is_empty():
		for id in TRAIL_SCANS:
			_trail_tex.append(load("res://assets/textures/trail/%s_nr.jpg" % id))
	return _trail_tex
var _tape_mat: ShaderMaterial
var _debris: TerrainDebris
var _tapes: TapeSim              # torn tape ribbons (tape.js TapeSim)
var _focus := Vector2.ZERO       # last update_stream() position: the torn tape simulates near it
var _clutter_cc := Vector2i(1 << 30, 0)   # the chunk the clutter visibility was last set for
var _clutter_dirty := true                # a chunk came / went since
## far decoration shadows (_update_far_shadows): set by Game every frame. A chunk's trees / rocks cast only
## if their shadows can land in the shadow-mapped area round the camera; that depends on the sun (a low sun
## throws a 20 m tree's shadow 100+ m), so it is not a fixed ring round the rider.
var shadow_eye := Vector3.ZERO     # the camera
var shadow_sun := Vector3.UP       # unit vector towards the sun / moon
var shadow_reach := 150.0          # the light's directional_shadow_max_distance
var _shadow_at := Vector3(INF, 0, 0)   # eye / sun / reach the casting was last decided for
var _shadow_sun_at := Vector3.ZERO
var _shadow_reach_at := 0.0
var _shadow_dirty := true          # a chunk came since
var _shadow_probe := Env.s("BMX_SHADOW_PROBE") != ""
var _shadow_flips := 0
var _water: TerrainWater
var _broken: Array = []          # [{kind, rec}] for clear_dynamic()
var _stakes := {}                # tape stake index -> {mm, i, pos, basis, basis0, chunk, node, lean, gone, stub}
var _stake_spans := {}           # tape stake index -> the spans tied to it (one each side)
var _time: float = 0.0
var _wind_t: float = float(Env.s("BMX_WIND_T0")) if Env.s("BMX_WIND_T0") != "" else 0.0   # tests: start the wind clock later
var _wind_ph: float = 0.0
var _wind_dir := Vector3(0.8, 0, 0.6)
var _wind_ws: float = 6.0
## the endless trail: once the rider is within GROW_AHEAD m (along the route spine) of the end of the course laid out
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
var chunk_serial: int = 0                # bumped whenever a chunk comes or goes (GrassField)
var fin_parts := PackedFloat64Array([0, 0, 0, 0, 0])
## health packs beside the sheds: key (position in 25 cm cells) -> {node, pos, chunk}; taken ones stay gone
var _packs := {}
var _pack_taken := {}
## rope bridges (RopeBridge) within reach of the rider: their swinging decks are part of height() / deck_height()
var ropes: Array = []
## the bike's height (set by Game each tick): a deck well above it (rider down in the crevasse) doesn't count
var rope_ref_y := INF
var _rope_ok := false
var _rope_t := 0.0
## bridges still being built, a few ms a frame (RopeBridge.build_step); they join `ropes` once complete
var _ropes_building: Array = []
const ROPE_BUILD_US := 3000     # build budget per frame
const ROPE_BUILD_NOW := 90.0    # a bridge whose middle is nearer the rider than this is finished at once


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
	CactusGeo.join()   # the static cactus fracture task too (quitting while it ran crashed on exit)


func _process(delta: float) -> void:
	_time += delta
	_update_wind(delta)
	_rope_t -= delta
	if _rope_t <= 0.0:
		_rope_t = 0.5
		_update_ropes()
	if not _ropes_building.is_empty():
		_build_ropes()
	_tapes.update(delta, _focus.x, _focus.y, _wind_t, _wind_dir, _wind_ws)
	for key in _packs:
		var pk: Dictionary = _packs[key]
		if absf(pk["pos"].x - _focus.x) < 120.0 and absf(pk["pos"].z - _focus.y) < 120.0:
			(pk["node"] as HealthPack).tick(delta)


## the rider rolls through a health pack within r (metres, sideways) of (x, z) and about the bike's height y:
## returns its position (it is gone for good) or null
func take_pack(x: float, y: float, z: float, r: float = 1.6):
	for key in _packs:
		var pk: Dictionary = _packs[key]
		var p: Vector3 = pk["pos"]
		if absf(p.x - x) < r and absf(p.z - z) < r and Vector2(p.x - x, p.z - z).length() < r and absf(p.y - y) < 2.5:
			_pack_taken[key] = true
			(pk["node"] as Node).queue_free()
			_packs.erase(key)
			return p
	return null


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
	_stakes.clear()
	_stake_spans.clear()
	_packs.clear()
	_pack_taken.clear()
	if _debris:
		_debris.clear()
	if _tapes:
		_tapes.clear()
	for rb in ropes + _ropes_building:
		(rb as Node).queue_free()
	ropes.clear()
	_ropes_building.clear()
	_rope_t = 0.0
	if use_cs and RopeBridge.available():
		RopeBridge.warm()   # their materials' shaders compile while the ride loads, not as the first bridge appears
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
				if rec.has("flag") or rec.has("bb") or rec.has("plate"):   # its flag / sponsor text / sign plate was freed by the smash
					var chf = chunks.get(b.get("chunk", Vector2i(1 << 30, 0)))
					if chf != null and is_instance_valid(chf["node"]):
						for lb in rec.get("labels", []):
							if is_instance_valid(lb): lb.queue_free()
						_panel_labels(rec, chf["node"])
			"cactus":
				var mm2: MultiMesh = rec.get("mm")
				if mm2:
					mm2.set_instance_transform(rec["i"], rec["xform"])
			"tape":
				var ch = chunks.get(rec.get("chunk", Vector2i(1 << 30, 0)))
				if ch != null:
					_rebuild_tape(ch)
			"stake":
				rec["gone"] = false
				rec["lean"] = 0.0
				rec["basis"] = rec["basis0"]
				(rec["mm"] as MultiMesh).set_instance_transform(rec["i"], Transform3D(rec["basis0"], rec["pos"]))
				if is_instance_valid(rec.get("stub")): rec["stub"].queue_free()
				rec.erase("stub")
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


## what you ride on: ground, a wooden deck, a rope bridge's deck, and a dome over every rock / log / stump of loaded chunks
## ruts (world/ruts.gd): the C# field and the area anything was dug in (x0, z0, x1, z1); every ground height the
## physics reads near the bike subtracts the depth there
var rut_field = null
var rut_box := Vector4(INF, INF, -INF, -INF)
func rut_at(x: float, z: float) -> float:
	if rut_field == null or x < rut_box.x or z < rut_box.y or x > rut_box.z or z > rut_box.w: return 0.0
	return rut_field.Depth(x, z)

func height(x: float, z: float) -> float:
	var g := _height0(x, z)
	if not ropes.is_empty():
		g = maxf(g, _rope_deck(x, z))
	return g - rut_at(x, z)


func _rope_deck(x: float, z: float) -> float:
	var best := -INF
	for rb in ropes:
		var d: float = rb.deck_at(x, z)
		if d > best and d < rope_ref_y + 1.5:
			best = d
	return best


## the rope bridge whose deck is under (x, z) at about height y, or null
func rope_under(x: float, z: float, y: float):
	for rb in ropes:
		var d: float = rb.deck_at(x, z)
		if d > -INF and absf(d - y) < 0.35:
			return rb
	return null


## where to steer for (world x, z) on or approaching a rope bridge, `ahead` m along its line; null when none is
## near. The trail's centreline bows up to ~2 m off the bridge's straight line (the deck is 1.1 m wide), so
## anything that follows the trail (the demo rider, test autopilots) rode off the side mid-span
func rope_aim(x: float, z: float, ahead: float):
	for rb in ropes:
		var l: Vector2 = rb.local(x, z)
		if l.x > -20.0 and l.x < rb.length - 2.0 and absf(l.y) < 6.0:
			return rb.world(l.x + ahead, 0.0)
	return null


## keep a RopeBridge for every rope-bridge route feature within ~220 m of the rider (C# needed)
func _update_ropes() -> void:
	if not _rope_ok:
		_rope_ok = RopeBridge.available() and use_cs and fcs != null
		if not _rope_ok:
			return
	var keep := {}
	for rb in ropes + _ropes_building:
		keep[rb.feat_s] = rb
	for j in field.route_feats:
		if j.type != "rope":
			continue
		var d := Vector2(j.x + j.dx * j.len * 0.5 - _focus.x, j.z + j.dz * j.len * 0.5 - _focus.y).length()
		var rb = keep.get(j.s)
		if rb == null and d < 220.0:
			rb = RopeBridge.new()
			rb.name = "RopeBridge"
			add_child(rb)
			rb.begin(j, self)
			_ropes_building.append(rb)
		elif rb != null and d > 300.0:
			ropes.erase(rb)
			_ropes_building.erase(rb)
			rb.queue_free()
	_build_ropes()


## a slice of the bridges being built (a few ms a frame); one the rider is already close to is finished now
func _build_ropes() -> void:
	var t0 := Time.get_ticks_usec()
	for rb in _ropes_building.duplicate():
		var mid: Vector2 = rb.world(rb.length * 0.5, 0.0)
		var now: bool = mid.distance_to(_focus) < ROPE_BUILD_NOW
		if not now and Time.get_ticks_usec() - t0 > ROPE_BUILD_US:
			continue
		var done := false
		while true:
			var ts := Time.get_ticks_usec()
			var stg: int = rb._stage
			done = rb.build_step()
			if Env.s("BMX_ROPE_PROBE") != "" and Time.get_ticks_usec() - ts > 2000:
				print("ROPE build stage %d took %.1f ms" % [stg, (Time.get_ticks_usec() - ts) / 1000.0])
			if done or (not now and Time.get_ticks_usec() - t0 > ROPE_BUILD_US):
				break
		if done:
			_ropes_building.erase(rb)
			ropes.append(rb)
			if Env.s("BMX_ROPE_PROBE") != "": print("ROPE built s=%.0f" % rb.feat_s)


## one physics tick of every rope bridge near the rider (Game, after the bike's step)
func ropes_step(dt: float) -> void:
	for rb in ropes:
		rb.step(dt, _wind_dir * _wind_ws * 1.6)   # the crevasse funnels the wind: stronger up there


func _height0(x: float, z: float) -> float:
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
				var h: float = dome_h(c["base"], c["top"], c.get("sink", 0.0), q)
				if h > g:
					g = h
	return g


## The rideable shape of a rock / log / stump at q = (distance / r)^2 from its middle: the part above the ground of
## a stone whose middle lies `sink` under it (rocks are drawn sunk ~0.3 of their size). sink = 0 is a half dome,
## which meets the ground as a vertical wall: every garden rock used to be a square-edged step to the wheel (a
## 20 cm rock at 35 km/h pitched the bike 15 deg and threw it into the air). Mirrored in TerrainFieldCs.height
static func dome_h(base: float, top: float, sink: float, q: float) -> float:
	var a := top - base + sink
	var k := sink / a if a > 1e-9 else 0.0
	return base - sink + a * sqrt(1.0 - q * (1.0 - k * k))


## the ground or a wooden deck WITHOUT the rock / log domes (JS's shadowed surface(): cliff-wall test)
func deck_height(x: float, z: float) -> float:
	var g: float = fcs.deck(x, z) if fcs != null else field.deck(x, z)
	if not ropes.is_empty():
		g = maxf(g, _rope_deck(x, z))
	return g - rut_at(x, z)


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


## the trail's drawn puddles at a point (world/trail_puddle.gd): x = damp soil round one, y = standing water, 0..1
func puddle_at(x: float, y: float, z: float) -> Vector2:
	var k := Vector2i(WorldRng.jround(x / SIZE), WorldRng.jround(z / SIZE))
	var rec = chunks.get(k)
	if rec == null:
		return Vector2.ZERO
	var tab: PackedFloat32Array = rec.get("pud", PackedFloat32Array())
	if tab.is_empty():
		return Vector2.ZERO
	var n: int = rec["N"]
	var cell := SIZE / n
	var tp := float(_trail_puddles) if _trail_puddles != "" else 1.0
	return TrailPuddle.at(tab, n, (x - k.x * SIZE + SIZE * 0.5) / cell, (z - k.y * SIZE + SIZE * 0.5) / cell, Vector3(x, y, z), tp)


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
## every chunk round the last update_stream point is built (nothing left to stream there)
func stream_complete() -> bool:
	if not stream_filter.is_valid():
		return _jobs.is_empty() and chunks.size() >= (2 * RADIUS + 1) * (2 * RADIUS + 1)
	return _jobs.is_empty() and _missing(WorldRng.jround(_focus.x / SIZE), WorldRng.jround(_focus.y / SIZE)).is_empty()

## Optional: which chunks to build at all (Vector2i chunk key -> bool). The garage's world out of the door only
## wants the ones that can be seen through it. Empty = all within RADIUS (a ride).
var stream_filter := Callable()


func _max_jobs() -> int:
	if max_jobs > 0:
		return max_jobs
	return clampi(OS.get_processor_count() - 2, 1, 4)


## budget_ms INF = build everything round (px, pz) now; sync_r >= 0 then limits that to the chunks within sync_r of
## it (the rest streams in later calls with a normal budget)
const CASTER_H := 26.0        # the tallest decoration (tall pines) whose shadow counts
const SHADOW_MARGIN := 16.0   # m beyond the shadow reach a chunk still casts (camera lead, crown width)
const SHADOW_HYST := 12.0     # ... and this much more before a casting chunk stops (no flicker on the line)

## Decorations whose shadows can't reach the shadow-mapped area cast none (draw calls for nothing); all the
## others always cast. Until 2026-11-22 it was "2+ chunks from the rider's chunk": crossing a chunk line
## switched whole chunks of trees' shadows off / on at once, and at golden hour (sun ~10 deg) those shadows
## are 100+ m long and lie right across the trail ahead, so they blinked out and back while riding.
func _update_far_shadows() -> void:
	var de := Vector2(shadow_eye.x - _shadow_at.x, shadow_eye.z - _shadow_at.z)
	if not _shadow_dirty and de.length_squared() < 16.0 and shadow_sun.dot(_shadow_sun_at) > 0.9995 			and absf(shadow_reach - _shadow_reach_at) < 5.0:
		return
	_shadow_dirty = false
	_shadow_at = shadow_eye
	_shadow_sun_at = shadow_sun
	_shadow_reach_at = shadow_reach
	# a caster throws its shadow away from the sun, up to CASTER_H / tan(sun height) along the ground: a
	# chunk matters if it is within the shadow disc round the camera swept that far towards the sun
	var s2 := Vector2(shadow_sun.x, shadow_sun.z)
	var sl := s2.length()
	var sweep := Vector2.ZERO
	if sl > 1e-4:
		sweep = s2 / sl * minf(CASTER_H * sl / maxf(shadow_sun.y, 0.05), 320.0)
	var e := Vector2(shadow_eye.x, shadow_eye.z)
	var r := shadow_reach + SHADOW_MARGIN
	var steps := clampi(int(sweep.length() / 16.0), 0, 20)
	var hb := SIZE * 0.5
	for k in chunks:
		var c: Dictionary = chunks[k]
		var was: int = int(c.get("shadow_far", -1))
		var cx: float = k.x * SIZE
		var cz: float = k.y * SIZE
		var d := INF
		for i in steps + 1:
			var p := e + sweep * (float(i) / float(maxi(steps, 1)))
			var dx := maxf(absf(p.x - cx) - hb, 0.0)
			var dz := maxf(absf(p.y - cz) - hb, 0.0)
			d = minf(d, sqrt(dx * dx + dz * dz))
		var far: bool = d > (r + SHADOW_HYST if was == 0 else r)
		var fk := 1 if far else 0
		if _shadow_probe:
			# what the old ring rule did here (2+ chunks from the rider's chunk = off)
			var cc := Vector2i(WorldRng.jround(_focus.x / SIZE), WorldRng.jround(_focus.y / SIZE))
			var old_far := 1 if maxi(absi(k.x - cc.x), absi(k.y - cc.y)) >= 2 else 0
			var ow: int = int(c.get("shadow_old", -1))
			c["shadow_old"] = old_far
			if ow != -1 and ow != old_far and not far:
				print("SHADOWOLD t=%.1f chunk=%s old rule %s a chunk whose shadows reach the view (eye %.0f m)" % [
					Time.get_ticks_msec() / 1000.0, k, "turned OFF" if old_far == 1 else "turned on", d])
		if was == fk:
			continue
		c["shadow_far"] = fk
		for mi in c.get("deco_mi", []):
			if is_instance_valid(mi):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if far else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _shadow_probe and was != -1:
			_shadow_flips += 1
			print("SHADOWFLIP t=%.1f chunk=%s %s d=%.0f reach=%.0f sweep=%.0f flips=%d" % [
				Time.get_ticks_msec() / 1000.0, k, "off" if far else "on", d, r, sweep.length(), _shadow_flips])


func update_stream(px: float, pz: float, budget_ms: float = 4.0, sync_r := -1) -> void:
	var t0 := Time.get_ticks_usec()
	last_finalized = 0
	fin_parts.fill(0.0)
	_focus = Vector2(px, pz)
	_update_grow(px, pz)
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
	# ground clutter only in the 3x3 chunks round the rider (redone only when the rider changes chunk or a
	# chunk was added / dropped: walking every chunk's clutter every frame cost ~0.1 ms for nothing)
	var cc := Vector2i(ccx, ccz)
	if cc != _clutter_cc or _clutter_dirty:
		_clutter_cc = cc
		_clutter_dirty = false
		for k in chunks:
			var ring: int = maxi(absi(k.x - ccx), absi(k.y - ccz))
			var near: bool = ring <= 1
			for o in chunks[k]["small"]:
				o.visible = near
	_update_far_shadows()
	if is_inf(budget_ms):
		var queue := _missing(ccx, ccz)
		if sync_r >= 0:
			queue = queue.filter(func(k: Vector2i) -> bool: return absi(k.x - ccx) <= sync_r and absi(k.y - ccz) <= sync_r)
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
			if not chunks.has(k) and (not stream_filter.is_valid() or stream_filter.call(k)):
				out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x - ccx) * (a.x - ccx) + (a.y - ccz) * (a.y - ccz) < (b.x - ccx) * (b.x - ccx) + (b.y - ccz) * (b.y - ccz))
	return out


func _dispatch_missing(ccx: int, ccz: int) -> void:
	if _jobs.size() >= _max_jobs():
		return
	# quick look first: usually every chunk is there or already being built, and building + sorting the
	# missing list (a GDScript lambda per compare) twice a frame was most of update_stream's idle cost
	var any := false
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var k := Vector2i(ccx + dx, ccz + dz)
			if not chunks.has(k) and not _jobs.has(k) and (not stream_filter.is_valid() or stream_filter.call(k)):
				any = true
				break
		if any: break
	if not any:
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


func _update_grow(px: float, pz: float) -> void:
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
			print_verbose("TRAIL grown to s=%.0f (%d points), adopted in %.1f ms" % [field.course.end_s(), field.course.n,
				(Time.get_ticks_usec() - t0) / 1000.0])
		_grow_box = []
		return
	# how far along the route the rider is (the route can run any way: x says nothing). Off the route (beyond its reach)
	# nothing grows until they are back near it
	var end := field.course.end_s()
	field.spine_near(px, pz)
	if field.sp_ad >= RouteSpine.R or field.sp_s < end - GROW_AHEAD:
		return
	var g := field.fork()   # forked here: fork() reads the live field, which the main thread keeps changing
	var to := end + GROW_STEP
	_grow_gen = _gen
	var box := []
	_grow_box = box
	_grow_task = WorkerThreadPool.add_task(func():
		var t0 := Time.get_ticks_usec()
		g.grow_course(to)
		box.append(g)
		print_verbose("TRAIL grow on worker: %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)), false, "trail grow")


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
	if _grow_task >= 0:   # the trail grow job too: a worker still running at quit crashes the exit
		_stale_tasks.append(_grow_task)
		_grow_task = -1
	_grow_box = []
	_reap_stale(true)


func _unload(k: Vector2i) -> void:
	var c = chunks.get(k)
	if c == null:
		return
	_clutter_dirty = true
	if fcs != null:
		fcs.domes_remove(_chunk_id(k))
		fcs.mesh_remove(k.x, k.y)
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
	for pkey in c.get("packs", []):
		_packs.erase(pkey)
	for sk in c.get("stakes", []):
		_stakes.erase(sk)
	if c.has("tape"):
		for sp in c["tape"]["spans"]:
			for sk in [sp["ka"], sp["kb"]]:
				var l = _stake_spans.get(sk)
				if l != null:
					l.erase(sp)
					if l.is_empty(): _stake_spans.erase(sk)
	for i in range(_broken.size() - 1, -1, -1):   # its smashed things go with it (they held its MultiMeshes alive)
		if _broken[i].get("chunk") == k: _broken.remove_at(i)
	(c["node"] as Node).queue_free()
	if _debris: _debris.drop_chunk(k)
	chunks.erase(k)
	chunk_serial += 1
	if _water:
		_water.mark_dirty(Vector2(k) * SIZE, SIZE)


const LIST_SPEC := {
	# name: [mesh, material, cast shadow, small clutter]
	"trunk": ["trunk", "trunk", true, false], "trunk_pale": ["trunk", "trunk_pale", true, false], "trunk_pine": ["trunk", "trunk_pine", true, false],
	"blob": ["blob", "leafSoft", true, false], "pine": ["pine", "leaf", true, false],
	"rock": ["rock", "rock", true, false], "pebble": ["pebble", "rock", false, true], "grass": ["grass", "flower", false, true],
	"daisy": ["daisy", "flower", false, true], "tulip": ["tulip", "flower", false, true], "spike": ["spike", "flower", false, true],
	"bush": ["bush", "leafCard", true, false], "bush1": ["bush1", "leafCard", true, false], "bush2": ["bush2", "leafCard", true, false],
	"bushdry": ["bushdry", "leafCardDry", true, false], "log": ["log", "trunk_plain", true, false], "root": ["root", "root", true, false],
	"weed": ["weed", "tuft", false, false],
	"stick": ["stick", "trunk_plain", false, true], "fern": ["fern", "flower", false, true], "mushroom": ["mushroom", "flower", false, true],
	"cactus0": ["cactus0", "cactus", true, false], "cactus1": ["cactus1", "cactus", true, false], "cactus2": ["cactus2", "cactus", true, false],
	"cactus3": ["cactus3", "cactus", true, false], "cactus4": ["cactus4", "cactus", true, false],
	"plank": ["box", "fence", true, false], "beam": ["box", "fence", true, false],   # (the fences' wood)
	# thin fence / tape parts: their shadows are a few pixels wide but each is a draw call in every cascade
	"post": ["post", "fencePost", false, false], "rail": ["rail", "fenceRail", false, false], "picket": ["picket", "fencePost", false, false],
	"stake": ["stake", "stake", false, false],
	"pole": ["pole", "signpole", true, false], "signboard": ["signboard", "signboard", true, false],
}


## how far (m, camera to the chunk's centre) each kind of decoration is drawn; past the fog they fade
## out. Small ground clutter is also limited to the 3x3 chunks round the rider (update_stream).
const VIS_RANGE := {"pebble": 90.0, "grass": 90.0, "daisy": 90.0, "tulip": 90.0, "spike": 90.0, "stick": 90.0,
	"fern": 90.0, "mushroom": 90.0}
## everything else (trees, rocks, bushes, logs, weeds, fence wood, sheds) has no per-chunk range: it dissolves by
## its own distance from the rider (shaders/deco_fade.gdshaderinc, the band set by Game: FADE_IN .. FADE_OUT),
## and the far backdrop's trees take over past it. A chunk-centre range popped whole chunks in at the load edge.

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
	if _gl_compat:
		# OpenGL fallback: a MultiMesh without per-instance colours gives the shader's COLOR a garbage
		# instance colour (some trees came out bright pink). Give every instance white: 12 + 4 + 4 floats.
		mm.use_colors = true
		mm.instance_count = count
		var wide := PackedFloat32Array()
		wide.resize(count * 20)
		for i in count:
			var s := i * 16
			var d := i * 20
			for j in 12: wide[d + j] = buf[s + j]
			wide[d + 12] = 1.0; wide[d + 13] = 1.0; wide[d + 14] = 1.0; wide[d + 15] = 1.0
			for j in 4: wide[d + 16 + j] = buf[s + 12 + j]
		mm.buffer = wide
	else:
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


## a panel's text / cloth: the distance gate's flag, a roadside billboard's sponsor lettering (both sides).
## Freed when the panel is smashed (break_collider), made again by clear_dynamic.
func _panel_labels(p: Dictionary, node: Node3D) -> void:
	p["labels"] = []
	if p.has("flag"):
		var fl := TrailGate.flag(p["flag"])
		node.add_child(fl)
		p["labels"].append(fl)
	if p.has("plate"):   # distance sign / billboard: its printed plate (SignTex)
		var pm := MeshInstance3D.new()
		pm.mesh = TerrainGeo.MESH["signboard"]
		pm.material_override = SignTex.for_plate(p["plate"])
		pm.transform = p["plate"]["xform"]
		node.add_child(pm)
		p["labels"].append(pm)
	if p.has("bb"):
		var bbs: Array = [p["bb"]]
		bbs.append_array(p.get("bb_more", []))
		for bb: Dictionary in bbs:
			for s in ([1.0] if bb.get("one_side", false) else [1.0, -1.0]):
				var bas: Basis = bb["basis"] if s > 0 else Basis(Vector3.UP, PI) * bb["basis"]
				var lb := TrailGate.label(bb["text"], bb["col"], bb["w"], bb["h"], bas, bb["at"] + bb["nrm"] * float(bb.get("off", 0.055)) * s)
				node.add_child(lb)
				p["labels"].append(lb)


## tools/bake_title.gd: keep every built chunk's data ({k: {"o": out, "N": n}}) to save as the title's fixed land
var keep_outs := false
var outs := {}

func _finalize(k: Vector2i) -> void:
	var job: Dictionary = _jobs[k]
	_jobs.erase(k)
	var b: TerrainChunkBuilder = job["builder"]
	if b.gen != _gen:
		return
	last_build_ms = b.ms_used
	if keep_outs: outs[k] = {"o": b.out.duplicate(true), "N": b.N}   # (before _finalize_out adds node references to it)
	_finalize_out(k, b.out, b.N)

## a chunk's built data (TerrainChunkBuilder.out, grid size chunk_n) turned into its nodes, records and lookups
## (TitleTerrain feeds it saved data)
func _finalize_out(k: Vector2i, o: Dictionary, chunk_n: int) -> void:
	_clutter_dirty = true
	_shadow_dirty = true
	var t0 := Time.get_ticks_usec()
	var tp := t0
	last_finalized += 1
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
	var scans := trail_textures()
	for i in TRAIL_SCANS.size():
		mat.set_shader_parameter("tr_nr%d" % i, scans[i])
	mat.set_shader_parameter("trail_tex", ImageTexture.create_from_image(o["trail_img"]))
	mat.set_shader_parameter("trail2_tex", ImageTexture.create_from_image(o["trail2_img"]))
	mat.set_shader_parameter("trail3_tex", ImageTexture.create_from_image(o["trail3_img"]))
	mat.set_shader_parameter("trail_fx", 1.0)
	if _trail_puddles != "": mat.set_shader_parameter("trail_puddles", float(_trail_puddles))
	if _trail_play != "": mat.set_shader_parameter("trail_play", float(_trail_play))
	if _trail_debug > 0: mat.set_shader_parameter("trail_debug", _trail_debug)   # BMX_TRAIL_DEBUG=1: the mask layers
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = mat
	gi.layers = 1 | GROUND_LAYER   # + its own layer: ground-only decals (blood splats, fx/blood.gd) project onto it
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
	var deco_mi := []   # the shadow-casting ones: update_stream turns their shadows off 2+ chunks out
	for name in LIST_SPEC:
		var n: int = counts.get(name, 0)
		if n == 0:
			continue
		var spec: Array = LIST_SPEC[name]
		var mm := _multimesh(node, TerrainGeo.MESH[spec[0]], TerrainGeo.MAT[spec[1]], lists[name], n, spec[2], VIS_RANGE.get(name, 0.0))
		mms[name] = mm
		var dmi := node.get_child(node.get_child_count() - 1)
		dmi.set_instance_shader_parameter("fade_mode", 2.0 if spec[3] else 1.0)   # deco_fade.gdshaderinc
		CardTree.add_twin(dmi, spec[0], CardTree.CHUNK_VIS)   # tree crowns: leaf cards near the rider (card_tree.gd), sets both fade modes
		if spec[2]:
			deco_mi.append(dmi)
		if spec[3]:
			small.append(dmi)
	if o.has("gates"):
		for g in o["gates"]:
			node.add_child(TrailGate.build(g))
	if o.has("arches"):
		for a in o["arches"]:
			node.add_child(TrailArch.build(a))
	if o.has("roots"):   # tree roots across a forest singletrack, grown along the ground (TerrainChunkBuilder._root_system)
		var rm := ArrayMesh.new()
		rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, o["roots"])
		var rmi := MeshInstance3D.new()
		rmi.mesh = rm
		rmi.material_override = TerrainGeo.MAT["root_world"]
		node.add_child(rmi)
	var sheds: Array = o["sheds"]
	for i in sheds.size():
		var buf: PackedFloat32Array = sheds[i]
		if buf.size() > 0:
			_multimesh(node, TerrainGeo.SHEDS[i], TerrainGeo.MAT["shed"], buf, buf.size() / 16, true)
			node.get_child(node.get_child_count() - 1).set_instance_shader_parameter("fade_mode", 1.0)
			deco_mi.append(node.get_child(node.get_child_count() - 1))
	for p in o["panels"]:
		p["meshes"] = mms
		_panel_labels(p, node)
	fin_parts[3] += (Time.get_ticks_usec() - tp) / 1000.0; tp = Time.get_ticks_usec()
	var colliders: Array = o["colliders"]
	var rec := {"cx": k.x, "cz": k.y, "node": node, "colliders": colliders, "small": small, "deco_mi": deco_mi, "rock_keys": [],
		"G": o["G"], "N": chunk_n, "MG": o.get("GF", o["G"]), "MN": o.get("MN", chunk_n), "mms": mms, "packs": [], "grass_img": o["grass_img"], "grass_h": o["grass_h"],
		"pud": o.get("pud", PackedFloat32Array()), "mat": mat}   # (mat: RoadDetail bakes from its trail textures)
	chunk_serial += 1   # GrassField re-reads the chunks round the camera
	for pp in o.get("packs", []):
		var pkey := Vector2i(roundi(pp.x * 4.0), roundi(pp.z * 4.0))
		if _pack_taken.has(pkey) or _packs.has(pkey):
			continue
		var hp := HealthPack.new()
		hp.name = "HealthPack"
		hp.position = pp
		node.add_child(hp)
		_packs[pkey] = {"node": hp, "pos": pp}
		rec["packs"].append(pkey)
		if OS.get_environment("BMX_PACK_PROBE") != "": print("PACK at ", pp)
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
			for sk in [sp["ka"], sp["kb"]]:
				if not _stake_spans.has(sk): _stake_spans[sk] = []
				_stake_spans[sk].append(sp)
		_rebuild_tape(rec)
	if o.has("stakes") and mms.has("stake"):
		var sks := []
		for e in o["stakes"]:
			var bs := TerrainChunkBuilder.euler_xyz(e[5], 0, -e[5])
			_stakes[e[0]] = {"mm": mms["stake"], "i": e[1], "pos": Vector3(e[2], e[3], e[4]), "basis": bs, "basis0": bs,
				"chunk": k, "node": node, "lean": 0.0, "gone": false}
			sks.append(e[0])
		rec["stakes"] = sks
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
				dd.append_array([c["x"], c["z"], c["r"], c["base"], c["top"], c.get("sink", 0.0)])
		fcs.domes_add(_chunk_id(k), dd)
		if OLD_TOPFIT: fcs.mesh_add(k.x, k.y, int(rec["N"]), rec["G"])
		else: fcs.mesh_add(k.x, k.y, int(rec["MN"]), rec["MG"])   # for tyre_worst (the drawn tyres' fit, one call per tyre)
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


## the ground exactly as drawn: the full-detail chunk mesh's own triangles (0.5 m grid, or the 0.25 m one
## with its micro detail near the trail; split along the (x+1, z) - (x, z+1) diagonal like _grid_lod_indices).
## It differs from height(), the smooth field, by up to a few cm. -INF where no chunk is loaded.
func mesh_height(x: float, z: float) -> float:
	return _mesh_h(x, z, false)

## the chunk's 0.5 m grid only (what the old fit read: BMX_OLD_TOPFIT)
func coarse_mesh_height(x: float, z: float) -> float:
	return _mesh_h(x, z, true)

func _mesh_h(x: float, z: float, coarse: bool) -> float:
	var k := Vector2i(WorldRng.jround(x / SIZE), WorldRng.jround(z / SIZE))
	var c = chunks.get(k)
	if c == null:
		return -INF
	var N: int = c["N"] if coarse else c.get("MN", c["N"])
	var d := SIZE / N
	var W := N + 3
	var G: PackedFloat32Array = c["G"] if coarse else c.get("MG", c["G"])
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


## the highest solid thing drawn here: the ground mesh, a wooden deck, or a rock / log / stump dome.
## The drawn ground is the mesh itself, also where it dips under the smooth field (micro detail, potholes): the
## drawn tyres sit on what is drawn, not hover over it (the physics still rides the smooth field). A rock, log,
## wooden deck or rope deck (height() above the plain ground) still counts where it stands up out of the mesh.
## BMX_OLD_TOPFIT=1 = the old max(field, coarse mesh) (the bike hovered over every drawn dip)
static var OLD_TOPFIT := OS.get_environment("BMX_OLD_TOPFIT") != ""
func top_height(x: float, z: float) -> float:
	if OLD_TOPFIT:
		var r0 := rut_at(x, z)
		return maxf(height(x, z) + r0, coarse_mesh_height(x, z)) - r0   # (the coarse drawn mesh, dug in too)
	return drawn_height(x, z)

## what is drawn here, whatever BMX_OLD_TOPFIT says (top_height without the old switch; probes measure against it)
func drawn_height(x: float, z: float) -> float:
	var r := rut_at(x, z)
	var m := mesh_height(x, z)
	var h := height(x, z) + r
	if m == -INF:
		return h - r
	var g: float = fcs.ground(x, z) if fcs != null else field.ground(x, z)   # (cached by height's own read)
	return (maxf(h, m) if h > g + 0.001 else m) - r

## BikeRig.tyre_depth's whole sample loop over top_height in one C# call (it was ~30-50 GDScript -> C# calls
## per tyre, up to ~22 tyres a frame). null = do it in GDScript (no C#, a rope bridge near, or a level with
## its own ground: cs_tyres false)
var cs_tyres := Env.s("BMX_TYRE_GD") == ""   # BMX_TYRE_GD=1: the GDScript loop (A/B runs)
func tyre_worst(c: Vector3, ax: Vector3, d0: Vector3, side: Vector3, r: float, hw: float, n: int, full: bool):
	if fcs == null or not cs_tyres or not ropes.is_empty():
		return null
	return fcs.tyre_worst(c, ax, d0, side, r, hw, n, full)


## true when a loaded chunk within `reach` (square) of (px, pz) has ground below the water level (chunks
## not loaded are skipped: no ground is drawn there to show water against). The water sheet is only drawn /
## baked then (TerrainWater); each chunk's lowest grid point is worked out once and kept in its record.
func water_near(px: float, pz: float, reach: float) -> bool:
	var k0 := Vector2i(WorldRng.jround((px - reach) / SIZE), WorldRng.jround((pz - reach) / SIZE))
	var k1 := Vector2i(WorldRng.jround((px + reach) / SIZE), WorldRng.jround((pz + reach) / SIZE))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var c = chunks.get(Vector2i(kx, kz))
			if c == null or not c.has("G"):
				continue   # not streamed in (far / still building): nothing drawn there to show water against
			if not c.has("gmin"):
				var m := INF
				for h in (c["G"] as PackedFloat32Array): m = minf(m, h)
				c["gmin"] = m
			if c["gmin"] < WATER + 0.05:
				return true
	return false

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
## the bike's front at tape height (null while crashed / not riding): what a grabbed tape stretches over
func tape_push(p) -> void:
	if _tapes: _tapes.push_at = p


## a tape that was stretched but not torn springs back: whole again (hittable, drawn by its chunk)
func restore_tape(sp: Dictionary) -> void:
	if not sp["broken"]: return
	sp["broken"] = false
	for i in range(_broken.size() - 1, -1, -1):
		if is_same(_broken[i]["rec"], sp): _broken.remove_at(i)
	var ch = chunks.get(sp.get("chunk"))
	if ch != null and ch.has("tape"): _rebuild_tape(ch)


## a MultiMesh instance hidden where it stands (scale 0). Never at the world origin: that stretched the
## MultiMesh's box all the way there, its middle moved off the chunk, and past ~300 m from the origin the
## draw distance (measured to that middle) hid every other fence part / stake of the chunk too
static func _hidden_at(pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), pos)


## fences / cacti: smash it (hide the visual, throw rigid-body debris); tape: snap it (hide the span, hand
## its two halves to the ribbon sim). Returns true if it broke.
func break_collider(c: Dictionary, vel: Vector3, at = null) -> bool:
	if c.has("fence"):
		var panel: Dictionary = c["fence"]
		if panel["broken"]:
			return false
		panel["broken"] = true
		_broken.append({"kind": "fence", "rec": panel, "chunk": c.get("chunk")})
		var hit := Vector2(c["x"], c["z"])
		# throw the debris first, only then hide the fence parts: a part is never hidden without its piece
		var made: int = _debris.smash_fence(panel, vel, hit, c.get("chunk"))
		if made <= 0:
			panel["broken"] = false   # nothing came off: leave the fence standing
			_broken.pop_back()
			return false
		for part in panel["parts"]:
			if not TerrainDebris.fence_part_goes(part, hit):
				continue   # a post you didn't hit stays standing
			var mm: MultiMesh = panel["meshes"].get(part["kind"])
			if mm:
				mm.set_instance_transform(part["i"], _hidden_at(part["xform"].origin))
		for lb in panel.get("labels", []):
			if is_instance_valid(lb):
				lb.queue_free()
		return true
	if c.has("cactus"):
		var rec: Dictionary = c["cactus"]
		if rec["broken"]:
			return false
		rec["broken"] = true
		_broken.append({"kind": "cactus", "rec": rec, "chunk": c.get("chunk")})
		var mm: MultiMesh = rec.get("mm")
		if mm:
			mm.set_instance_transform(rec["i"], _hidden_at(rec["xform"].origin))
		_debris.smash_cactus(rec, vel, at if at is Vector3 else Vector3(c["x"], rec["xform"].origin.y + 0.5, c["z"]), c.get("chunk"))
		return true
	if c.has("tape"):
		var sp: Dictionary = c["tape"]
		if sp["broken"]:
			return false
		var pts: PackedVector3Array = sp["pts"]
		var hit := Vector2(at.x, at.z) if at is Vector3 else Vector2(c["x"], c["z"])
		var near_a := hit.distance_to(Vector2(pts[0].x, pts[0].z)) < STAKE_HIT
		var near_b := hit.distance_to(Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)) < STAKE_HIT
		_tape_off(sp)
		if near_a or near_b:
			# straight into a stake: it takes the whole hit, and the span is dragged down / along with it
			var hv := Vector3(vel.x, 0, vel.z)
			var sev := hv.length() / 6.0 * randf_range(0.8, 1.3)
			var res := stake_yank(sp["ka"] if near_a else sp["kb"], hv, sev, vel, sp)
			if not res.is_empty():
				var tie_a = res["to"] if near_a else pts[0]
				var tie_b = pts[pts.size() - 1] if near_a else res["to"]
				_tapes.hang(sp, tie_a, tie_b)
				return true
		_tapes.grab(sp, Vector2(c["x"], c["z"]), vel)
		return true
	return false


## take a span out of its chunk's tape mesh (it's a sim strip now)
func _tape_off(sp: Dictionary) -> void:
	sp["broken"] = true
	_broken.append({"kind": "tape", "rec": sp, "chunk": sp.get("chunk")})
	var ch = chunks.get(sp.get("chunk"))
	if ch != null:
		_rebuild_tape(ch)


const STAKE_HIT := 0.3       # a tape hit this close (m) to a stake hits the stake itself
const STAKE_LEAN_MAX := 0.75 # rad: a stake leans at most this far before it gives way


## the tape (or the bike) yanks stake k towards `dir` (horizontal) with severity `sev` (~ speed / 11 m/s:
## < 0.2 nothing, then it leans over, past 0.8 it snaps off at the ground, past ~1.25 it pulls out whole; a
## stake already leaning gives way sooner). Tape still tied to it follows: strips pinned there move with it,
## an intact span on its other side drops / hangs from it (`skip` = the span doing the yanking).
## Returns {} (unchanged / unknown stake) or {"to": the tie point: Vector3, or {body, off} on a flying piece}.
func stake_yank(k: int, dir: Vector3, sev: float, vel: Vector3, skip = null) -> Dictionary:
	var st = _stakes.get(k)
	if st == null:
		return {}
	if st["gone"]:
		return {"to": null}
	sev += float(st["lean"]) * 0.8
	if sev < 0.2:
		return {}
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.RIGHT
	var ax := Vector3.UP.cross(dir)   # turning about it tips the top towards dir
	var old_tie := _stake_tie(st)
	var to
	if not _broken.any(func(b): return is_same(b["rec"], st)):
		_broken.append({"kind": "stake", "rec": st, "chunk": st["chunk"]})
	if sev < 0.8:
		var lean := minf(STAKE_LEAN_MAX, float(st["lean"]) + sev * 0.5 * randf_range(0.7, 1.2))
		st["basis"] = Basis(ax, lean - float(st["lean"])) * st["basis"]
		st["lean"] = lean
		(st["mm"] as MultiMesh).set_instance_transform(st["i"], Transform3D(st["basis"], st["pos"]))
		to = _stake_tie(st)
	else:
		st["gone"] = true
		var mm: MultiMesh = st["mm"]
		mm.set_instance_transform(st["i"], _hidden_at(st["pos"]))
		var whole: bool = sev > 1.25 or randf() < 0.25   # soft ground: out it comes, foot and all
		var bs: Basis = st["basis"]
		var pos: Vector3 = st["pos"]
		var mid := 0.375 if whole else 0.495             # the piece's middle above the ground
		if not whole:
			var stub := MeshInstance3D.new()
			stub.mesh = TerrainGeo.MESH["stake_stub"]
			stub.material_override = TerrainGeo.MAT["stake_loose"]
			(st["node"] as Node3D).add_child(stub)
			stub.global_transform = Transform3D(bs * Basis(ax, randf_range(0.05, 0.25)), pos)
			st["stub"] = stub
		var spd := Vector2(vel.x, vel.z).length()
		var v := dir * (1.5 + spd * 0.4) * randf_range(0.7, 1.2) + Vector3(vel.x, 0, vel.z) * 0.15 \
			+ Vector3(0, 1.0 + randf() * 1.5 + (1.0 if whole else 0.0), 0)
		var w := ax * (4.0 + spd * 0.6) * randf_range(0.7, 1.3) + Vector3(randf() - .5, randf() - .5, randf() - .5) * 3.0
		var body := _debris.fling(TerrainGeo.MESH["stake_whole" if whole else "stake_top"], TerrainGeo.MAT["stake_loose"],
			Transform3D(bs, pos + bs * Vector3(0, mid, 0)), Vector3(0.05, 1.15 if whole else 0.92, 0.05), v, w, st["chunk"])
		to = {"body": body, "off": Vector3(0, TerrainChunkBuilder.TAPE_H - mid, 0)}
	if Env.s("BMX_TAPE") != "" and Env.s("BMX_TAPE_PERF") == "":   # (a print costs ms: not while timing)
		print("STAKE %d sev=%.2f -> %s" % [k, sev, ("lean %.0f deg" % rad_to_deg(st["lean"])) if not st["gone"] else ("flies" if st.has("stub") == false else "snapped")])
	_tapes.retarget(old_tie, to)
	for sp in _stake_spans.get(k, []).duplicate():
		if is_same(sp, skip) or sp["broken"]:
			continue
		var pts: PackedVector3Array = sp["pts"]
		_tape_off(sp)
		_tapes.hang(sp, to if sp["ka"] == k else pts[0], to if sp["kb"] == k else pts[pts.size() - 1])
	return {"to": to}


func _stake_tie(st: Dictionary) -> Vector3:
	return st["pos"] + (st["basis"] as Basis) * Vector3(0, TerrainChunkBuilder.TAPE_H, 0)


# ======================================================================
# water & wind
# ======================================================================
func update_water(px: float, pz: float, t: float) -> void:
	if water_enabled and _water:
		_water.follow(px, pz, t)


## push the lake / sea surface at p (a tyre, a landing, a body): ripples run out from it (WaterWake)
func water_splash(p: Vector3, amount: float, radius := 0.5) -> void:
	if _water:
		_water.splash(p, amount, radius)


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
