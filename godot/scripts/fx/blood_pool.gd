extends MeshInstance3D
## One pool of blood (fx/blood.gd, after a fatal crash) as a small real liquid simulation that follows
## the ground (BloodPoolSim.cs): blood pours in at the source (fast, then slowing over grow_t), runs to
## lower ground, fills dips, spreads round on the flat with an uneven edge and stops by itself when the
## front has thinned to a film. N x N cells of CELL m; the ground is sampled every 16 cm once at the
## start (top_height, the exact drawn ground) and interpolated by the sim.
## The depths go into a float texture; the mesh is a grid draped on the ground that reads it
## (shaders/blood_pool.gdshader: smooth edge, deep / thin colour, meniscus, gloss, bubbles).
const N := 160
const CELL := 0.04                 # m: the grid is N * CELL = 6.4 m across
const GROUND_N := 41               # ground samples per side (16 cm apart)
const ITERS := 6                   # flow iterations per frame
const MESH_N := 64                 # draped mesh resolution (10 cm: hugs the ground)
const SIM := "res://scripts/fx/BloodPoolSim.cs"
const SHADER := preload("res://shaders/blood_pool.gdshader")

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

func _init(p_terrain, at: Vector3, radius: float, p_grow_t: float) -> void:
	terrain = p_terrain
	grow_t = p_grow_t
	volume = 0.012 * pow(radius / 1.15, 2.0)
	_seed = randf() * 100.0
	_o = Vector3(at.x - N * CELL * 0.5, 0.0, at.z - N * CELL * 0.5)
	var size := N * CELL
	var gr := PackedFloat32Array()
	gr.resize(GROUND_N * GROUND_N)
	for j in GROUND_N:
		for i in GROUND_N:
			gr[i + j * GROUND_N] = terrain.top_height(_o.x + size * i / (GROUND_N - 1), _o.z + size * j / (GROUND_N - 1))
	_sim = load(SIM).new()
	_sim.Setup(N, CELL, gr, GROUND_N, _seed)
	_tex = ImageTexture.create_from_image(_sim.MakeImage())
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_mesh()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 2
	m.set_shader_parameter("depth_tex", _tex)
	m.set_shader_parameter("seed", _seed)
	m.set_shader_parameter("grid_m", size)
	material_override = m

## the ground under the grid, draped (+1.6 cm so it never flickers into it)
func _build_mesh() -> void:
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
			st.add_vertex(Vector3(x, terrain.top_height(x, z) + 0.03, z))
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
	if dt <= 0.0: return
	t += dt
	(material_override as ShaderMaterial).set_shader_parameter("pool_t", t)
	if not growing: return
	# the pour: volume * (1 - e^(-t/T)) in total by now
	var want := volume * (1.0 - exp(-t / grow_t))
	var add := maxf(0.0, want - _poured)
	_poured += add
	_sim.Step(add, N / 2, N / 2, ITERS)
	if not hit_edge and _sim.AtEdge():
		hit_edge = true
		if OS.get_environment("BMX_BLOOD_PROBE") != "": print("BLOOD pool reached its grid edge at t=%.1f" % t)
	_upl -= dt
	if _upl <= 0.0:
		_tex.update(_sim.MakeImage())
		_upl = 0.033
	# long after the pour it has settled: stop simulating
	if t > grow_t * 4.0: growing = false

func wipe(_now_t: float, len: float) -> void:
	var m := material_override as ShaderMaterial
	m.set_shader_parameter("wipe_at", t)
	m.set_shader_parameter("wipe_len", len)
	growing = false
