extends MeshInstance3D
## One pool of blood (fx/blood.gd, after a fatal crash) as a small real liquid simulation that follows
## the ground (BloodPoolSim.cs): blood pours in at the source (fast, then slowing over grow_t), runs to
## lower ground, fills dips, spreads round on the flat with an uneven edge and stops by itself when the
## front has thinned to a film. N x N cells of CELL m; the ground is sampled every 16 cm once at the
## start (top_height, the exact drawn ground) and interpolated by the sim.
## The depths go into a float texture; the mesh is a grid draped on the ground that reads it
## (shaders/blood_pool.gdshader: smooth edge, deep / thin colour, meniscus, gloss, bubbles).
const N := 256
const CELL := 0.04                 # m: the grid is N * CELL = 10.24 m across (room to run downhill: never cut off)
const GROUND_N := 65               # ground samples per side (16 cm apart); the draped mesh uses them too
const ITERS := 6                   # flow iterations per frame
const MESH_N := 64                 # draped mesh: one vertex per ground sample (16 cm)
const SIM := "res://scripts/fx/BloodPoolSim.cs"
const SHADER := preload("res://shaders/blood_pool.gdshader")
const HALO := preload("res://shaders/blood_halo.gdshader")
var _halo: ShaderMaterial

var terrain
var t := 0.0                       # seconds since it started
var volume := 0.009                # m^3 it ends up with (~9 l: a big pool)
var grow_t := 9.0                  # seconds: most of the pouring
var growing := true
var hit_edge := false              # tests: it reached the grid's edge (would be cut off)
var _o := Vector3.ZERO             # grid corner (world)
var _sim
var _tex: ImageTexture
var _poured := 0.0
var _upl := 0.0
var _seed := 0.0

## Set up over a few frames (_setup_step), not all at once: the ground samples (4225 top_height calls), the C#
## sim, the depth texture and the draped mesh cost ~25 ms a pool, and a fatal crash starts up to 3 at once:
## each stage is a few ms, and only one pool works per frame (~20 frames to start, unnoticeable under the body).
var _gr := PackedFloat32Array()
var _row := 0
var _stage := 0                    # 0 ground rows, 1 sim rows + texture, 3 mesh + material, 4 running
const ROWS_PER_FRAME := 8
const SIM_ROWS_PER_FRAME := 48     # of N: ~2 ms a frame
var _srow := 0
static var _busy_frame := -1       # one pool does setup work per frame (a fatal crash starts up to 3 at once)

func _init(p_terrain, at: Vector3, radius: float, p_grow_t: float) -> void:
	terrain = p_terrain
	grow_t = p_grow_t
	volume = 0.012 * pow(radius / 1.15, 2.0)
	_seed = randf() * 100.0
	_o = Vector3(at.x - N * CELL * 0.5, 0.0, at.z - N * CELL * 0.5)
	_gr.resize(GROUND_N * GROUND_N)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## one stage of the setup a frame
func _setup_step() -> void:
	var t0 := Time.get_ticks_usec()
	var size := N * CELL
	match _stage:
		0:
			var j1 := mini(_row + ROWS_PER_FRAME, GROUND_N)
			for j in range(_row, j1):
				for i in GROUND_N:
					_gr[i + j * GROUND_N] = terrain.top_height(_o.x + size * i / (GROUND_N - 1), _o.z + size * j / (GROUND_N - 1))
			_row = j1
			if _row >= GROUND_N: _stage = 1
		1:
			if _sim == null:
				_sim = load(SIM).new()
				_sim.SetupBegin(N, CELL, _gr, GROUND_N, _seed)
				_srow = 0
			else:
				_sim.SetupRows(_srow, _srow + SIM_ROWS_PER_FRAME)
				_srow += SIM_ROWS_PER_FRAME
				if _srow >= N:
					_tex = ImageTexture.create_from_image(_sim.MakeImage())
					_stage = 2
		2:
			_stage = 3   # (the mesh: its own frame)
		3:
			_build_mesh(_gr)
			var m := ShaderMaterial.new()
			m.shader = SHADER
			m.render_priority = 2
			m.set_shader_parameter("depth_tex", _tex)
			m.set_shader_parameter("seed", _seed)
			m.set_shader_parameter("grid_m", size)
			if Env.s("BMX_POOL_AGE") != "": m.set_shader_parameter("age_add", float(Env.s("BMX_POOL_AGE")))   # tests: start part dried
			material_override = m
			# the WET HALO: a second pass that darkens the dirt round the pool where blood has soaked in
			_halo = ShaderMaterial.new()
			_halo.shader = HALO
			_halo.render_priority = 1
			_halo.set_shader_parameter("depth_tex", _tex)
			_halo.set_shader_parameter("seed", _seed)
			_halo.set_shader_parameter("grid_m", size)
			if Env.s("BMX_POOL_AGE") != "": _halo.set_shader_parameter("age_add", float(Env.s("BMX_POOL_AGE")))
			m.next_pass = _halo
			_stage = 4
			if _wiped: _apply_wipe()
	if Env.raw("BMX_BLOOD_PROBE") != "": print("BLOOD pool setup stage %d %.1f ms" % [_stage, (Time.get_ticks_usec() - t0) / 1000.0])

## the ground under the grid, draped (+1.6 cm so it never flickers into it)
func _build_mesh(gr: PackedFloat32Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var size := N * CELL
	for j in MESH_N + 1:
		for i in MESH_N + 1:
			var u := float(i) / MESH_N
			var v := float(j) / MESH_N
			var x := _o.x + u * size
			var z := _o.z + v * size
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(x, gr[i + j * GROUND_N] + 0.03, z))   # MESH_N = GROUND_N - 1: the samples
	for j in MESH_N:
		for i in MESH_N:
			var a := i + j * (MESH_N + 1)
			var b := a + 1
			var c := a + MESH_N + 1
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	st.generate_normals()
	mesh = st.commit()

func _process(dt: float) -> void:
	if _stage < 4:
		if _busy_frame != Engine.get_process_frames():
			_busy_frame = Engine.get_process_frames()
			_setup_step()
		return
	if dt <= 0.0: return
	t += dt
	(material_override as ShaderMaterial).set_shader_parameter("pool_t", t)
	_halo.set_shader_parameter("pool_t", t)
	if not growing: return
	# the pour: volume * (1 - e^(-t/T)) in total by now
	var want := volume * (1.0 - exp(-t / grow_t))
	var add := maxf(0.0, want - _poured)
	_poured += add
	_sim.Step(add, N / 2, N / 2, ITERS)
	if not hit_edge and _sim.AtEdge():
		hit_edge = true
		if Env.raw("BMX_BLOOD_PROBE") != "": print("BLOOD pool reached its grid edge at t=%.1f" % t)
	_upl -= dt
	if _upl <= 0.0:
		_tex.update(_sim.MakeImage())
		_upl = 0.033
	# long after the pour it has settled: stop simulating
	if t > grow_t * 4.0: growing = false

## blood depth (m) under a world point (0 off the pool)
func depth_at(x: float, z: float) -> float:
	if _wiped or _stage < 4: return 0.0
	return _sim.DepthAt(int((x - _o.x) / CELL), int((z - _o.z) / CELL))

var _wiped := false
var _wipe_len := 0.0
func wipe(_now_t: float, len: float) -> void:
	_wiped = true
	_wipe_len = len
	growing = false
	if _stage >= 4: _apply_wipe()

func _apply_wipe() -> void:
	if _halo: _halo.set_shader_parameter("wipe_at", t)
	if _halo: _halo.set_shader_parameter("wipe_len", _wipe_len)
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("wipe_at", t)
	m.set_shader_parameter("wipe_len", _wipe_len)
