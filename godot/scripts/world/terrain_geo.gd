class_name TerrainGeo
extends RefCounted
## Shared low-poly decoration meshes and materials (terrain.js GEO / MAT, sheds.js, fences.js,
## tape.js stakes, cactus.js pieces). Built once, lazily, on the main thread.

static var MESH := {}        # name -> ArrayMesh
static var MAT := {}         # name -> Material
static var SHEDS: Array = [] # [{mesh, hw, hd, extra}] 8 designs (2 shapes x 4 palettes)
static var FENCE_SIZE := {}  # kind -> Vector3 (box extents of the unscaled piece, for debris shapes)

const FENCE_STYLES := {
	"ranch": {"postH": 1.2, "rails": [[0.42, 0.13, 0.05], [0.85, 0.13, 0.05]], "railOff": 0.09, "pickets": 0.0,
		"cols": [0x8b6a4a, 0x9a7650, 0x7d5e40, 0x85704f]},
	"picket": {"postH": 1.05, "rails": [[0.3, 0.08, 0.04], [0.72, 0.08, 0.04]], "railOff": -0.05, "pickets": 0.27,
		"cols": [0xf2efe6, 0xe9e3d3, 0xf6f3ea]},
}
const SPAN := 2.4


static func lin(hex: int) -> Color:
	return TerrainField.lin(hex)


static func ensure() -> void:
	if not MESH.is_empty():
		return
	_build_materials()
	MESH["trunk"] = GeoBuf.cylinder(0.1, 0.16, 1, 8).translate(0, 0.5, 0).to_mesh(false, _soft_normals(GeoBuf.cylinder(0.1, 0.16, 1, 8).translate(0, 0.5, 0)))
	MESH["blob"] = _crown(7, 2, false).to_mesh(true)
	MESH["pine"] = GeoBuf.merge([GeoBuf.cone(1, 1.6, 6).translate(0, 0.8, 0), GeoBuf.cone(0.75, 1.3, 6).translate(0, 1.6, 0),
		GeoBuf.cone(0.45, 1.0, 6).translate(0, 2.3, 0)]).to_mesh()
	MESH["rock"] = _boulder(3, 1).to_mesh()
	MESH["pebble"] = _boulder(3, 0).to_mesh()
	MESH["box"] = GeoBuf.box(1, 1, 1).to_mesh()
	CactusGeo.ensure()
	for k in CactusGeo.KINDS:
		MESH["cactus%d" % k] = CactusGeo.MESHES[k]
	var fl := _flowers()
	for k in fl:
		MESH[k] = fl[k].to_mesh()
	MESH["bush"] = _crown(11, 2, true).translate(0, 0.55, 0).scale(1, 0.7, 1).to_mesh(true)
	# bushes are leaf cards (card_bush.gd): bush / bush1 / bush2 = green variants, bushdry = the dry biomes' shrub.
	# BMX_OLD_BUSH=1 = the old blobs for all of them.
	if OS.get_environment("BMX_OLD_BUSH") == "1":
		for k in ["bush1", "bush2", "bushdry"]:
			MESH[k] = MESH["bush"]
		for k in ["leafCard", "leafCardDry"]:
			MAT[k] = MAT["leafSoft"]
	else:
		for k in CardBush.VARIANTS:
			MESH[k] = CardBush.mesh(k)
		MAT["leafCard"] = CardBush.material("leaf")
		MAT["leafCardDry"] = CardBush.material("dry")
	var log_g := GeoBuf.merge([GeoBuf.cylinder(0.17, 0.21, 1, 7).rot_z(PI / 2),
		GeoBuf.cylinder(0.035, 0.05, 0.4, 4).rot_z(-0.7).translate(0.18, 0.2, 0.05)])
	MESH["log"] = log_g.to_mesh(false, _soft_normals(log_g))
	MESH["root"] = _root_mesh()
	var stick := GeoBuf.cylinder(0.012, 0.02, 1, 4).rot_z(PI / 2)
	MESH["stick"] = stick.to_mesh(false, _soft_normals(stick))
	MESH["weed"] = _jitter(GeoBuf.ico(1, 1), 0.45, 23).to_mesh()
	# fences (centred on the origin, like fences.js)
	var post := GeoBuf.merge([GeoBuf.box(0.13, 1, 0.13), GeoBuf.cone(0.092, 0.1, 4).rot_y(PI / 4).translate(0, 0.55, 0)]).center()
	var picket := GeoBuf.merge([GeoBuf.box(0.085, 0.9, 0.025), GeoBuf.cone(0.06, 0.1, 4).rot_y(PI / 4).scale(1, 1, 0.3).translate(0, 0.5, 0)]).center()
	MESH["post"] = post.to_mesh()
	MESH["rail"] = GeoBuf.box(1, 1, 1).to_mesh()
	MESH["picket"] = picket.to_mesh()
	# distance sign: a plain square stick (unit box, scaled) and the printed plate (unit box, the design on +Z)
	MESH["pole"] = MESH["rail"]
	MESH["signboard"] = _sign_board()
	FENCE_SIZE = {"post": Vector3(0.13, 1.1, 0.13), "rail": Vector3(1, 1, 1), "picket": Vector3(0.085, 1.0, 0.03),
		"pole": Vector3(1, 1, 1), "signboard": Vector3(1, 1, 1)}
	# tape stake: thin white fibreglass stake with an orange cap, 0.2 m in the ground
	MESH["stake"] = GeoBuf.merge([GeoBuf.cylinder(0.018, 0.022, 1.15, 5).translate(0, 0.575 - 0.2, 0).paint(lin(0xe9e6dc)),
		GeoBuf.cylinder(0.024, 0.024, 0.12, 5).translate(0, 0.9, 0).paint(lin(0xff6a1a))]).to_mesh()
	# loose stake pieces (Terrain.stake_yank), centred on their middle: pulled out whole (earth on its foot),
	# the top snapped off at the ground, and the stub left standing
	MESH["stake_whole"] = GeoBuf.merge([GeoBuf.cylinder(0.018, 0.022, 1.15, 5).paint(lin(0xe9e6dc)),
		GeoBuf.cylinder(0.026, 0.03, 0.2, 5).translate(0, -0.475, 0).paint(lin(0x5a4430)),
		GeoBuf.cylinder(0.024, 0.024, 0.12, 5).translate(0, 0.525, 0).paint(lin(0xff6a1a))]).to_mesh()
	MESH["stake_top"] = GeoBuf.merge([GeoBuf.cylinder(0.018, 0.021, 0.86, 5).paint(lin(0xe9e6dc)),
		GeoBuf.cone(0.02, 0.06, 4).rot_x(PI).translate(0.004, -0.46, 0).paint(lin(0xe9e6dc)),
		GeoBuf.cylinder(0.024, 0.024, 0.12, 5).translate(0, 0.405, 0).paint(lin(0xff6a1a))]).to_mesh()
	MESH["stake_stub"] = GeoBuf.merge([GeoBuf.cylinder(0.021, 0.022, 0.26, 5).translate(0, -0.07, 0),
		GeoBuf.cone(0.02, 0.05, 4).translate(-0.004, 0.085, 0)]).paint(lin(0xe9e6dc)).to_mesh()
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.6
	MAT["stake_loose"] = lm
	_build_sheds()


## a 1 x 1 x 1 box whose +Z face carries the whole sign texture (UV 0..1, upright); the back and the edges read
## a plain white texel of the design's bottom strip
static func _sign_board() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plain := Vector2(0.5, 0.995)
	# [normal, u axis, v axis (down)]: each face = centre n/2, corners +-u/2 +-v/2
	var faces := [[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]]
	for fi in faces.size():
		var n: Vector3 = faces[fi][0]
		var u: Vector3 = faces[fi][1]
		var v: Vector3 = faces[fi][2]
		var c := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var p := []
		for q: Vector2 in c:
			p.append(n * 0.5 + u * (q.x - 0.5) + v * (q.y - 0.5))
		for k in [0, 1, 2, 0, 2, 3]:   # clockwise seen from outside = Godot's front face
			st.set_normal(n)
			st.set_uv(c[k] if fi == 0 else plain)
			st.add_vertex(p[k])
	return st.commit()


static func _mat(albedo: Color, rough: float, metal: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/world/deco.gdshader")
	m.set_shader_parameter("albedo", Vector3(albedo.r, albedo.g, albedo.b))
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	return m


static func _bark_mat(id: String, tint: Color) -> ShaderMaterial:
	var m := _mat(tint, 0.9)
	m.set_shader_parameter("bark", true)
	m.set_shader_parameter("bark_col", load("res://assets/textures/bark/%s_col.jpg" % id))
	m.set_shader_parameter("bark_nrm", load("res://assets/textures/bark/%s_nrm.jpg" % id))
	m.set_shader_parameter("bark_rgh", load("res://assets/textures/bark/%s_rgh.jpg" % id))
	m.set_shader_parameter("specular", 0.25)
	return m


## a tree root running across the ground (forest singletrack roots, 2026-11-25, user: "more like a root, realistic"), at real
## size: 2 m long along x (-1 .. 1), 9 cm radius at the thick end tapering to ~3 cm, winding ~20 cm side to side, dipping
## under the dirt and coming up again, knobbly, a little flattened, with two thinner side roots. UV = (round it, along it in
## metres): the bark scan runs along it (deco.gdshader bark_uv). TerrainChunkBuilder._roots scales it to each root
static func _root_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _root_tube(st, Vector3(-1.0, 0, 0), Vector3(1, 0, 0), 2.0, 0.09, 0.028, 0.0, 1.7)
	# side roots: off the main one at 30 % (one side) and 62 % (the other), each smaller
	_root_tube(st, main[int(0.3 * ROOT_NS)] + Vector3(0, -0.01, 0), Vector3(0.7, 0, 0.71).normalized(), 0.8, 0.05, 0.014, 0.6, 4.3)
	_root_tube(st, main[int(0.62 * ROOT_NS)] + Vector3(0, -0.01, 0), Vector3(0.8, 0, -0.6).normalized(), 0.55, 0.034, 0.011, 1.25, 2.9)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


const ROOT_NS := 24   # rings along a root

## one tapered, winding tube from a along dir; returns its centre points (side roots branch from them)
static func _root_tube(st: SurfaceTool, a: Vector3, dir: Vector3, len: float, r0: float, r1: float, v0: float, ph: float) -> PackedVector3Array:
	const NR := 8
	var side := Vector3(-dir.z, 0, dir.x)
	var rings := []
	var cs := PackedVector3Array()
	for i in ROOT_NS + 1:
		var t := float(i) / ROOT_NS
		var w := minf(1.0, t * 6.0)   # (starts on its line: a side root grows out of the main one)
		var c := a + dir * len * t + side * (0.1 * sin(t * 4.7 + ph) + 0.03 * sin(t * 13.0 + ph * 2.0)) * len * 0.5 * w
		c.y += (0.035 * sin(t * 8.3 + ph) - 0.012) * w   # in and out of the dirt
		cs.append(c)
		var r := lerpf(r0, r1, pow(t, 0.75)) * (1.0 + 0.16 * sin(t * 27.0 + ph) + 0.08 * sin(t * 61.0 + ph))
		var ring := []
		for k in NR:
			var ang := TAU * k / NR
			ring.append(c + side * cos(ang) * r + Vector3.UP * sin(ang) * r * 0.78)
		rings.append([ring, v0 + t * len])
	for i in ROOT_NS:
		var ra: Array = rings[i][0]; var rb: Array = rings[i + 1][0]
		var va: float = rings[i][1]; var vb: float = rings[i + 1][1]
		for k in NR:
			var k2 := (k + 1) % NR
			var u0 := float(k) / NR
			var u1 := float(k + 1) / NR
			for q in [[ra[k], u0, va], [rb[k], u0, vb], [rb[k2], u1, vb], [ra[k], u0, va], [rb[k2], u1, vb], [ra[k2], u1, va]]:
				st.set_uv(Vector2(q[1], q[2]))
				st.add_vertex(q[0])
	return cs

static func _build_materials() -> void:
	var w := Color(1, 1, 1)
	MAT["trunk_plain"] = _mat(lin(0x7a5233), 0.9)   # (logs, sticks: lying down, no bark wrap)
	# standing trunks: three bark scans (assets/textures/bark, CC0): light grey-tan, pale (birch-like), reddish pine
	MAT["trunk"] = _bark_mat("bark_light", Color(0.92, 0.88, 0.82))
	MAT["trunk_pale"] = _bark_mat("bark_pale", Color(0.95, 0.95, 0.92))
	MAT["trunk_pine"] = _bark_mat("bark_pine", Color(1.0, 0.95, 0.9))
	MAT["root"] = _bark_mat("bark_pine", Color(0.72, 0.62, 0.55))   # (darker: earthy, worn by tyres)
	MAT["root"].set_shader_parameter("bark_uv", true)
	MAT["root"].set_shader_parameter("bark_tile", 0.35)
	MAT["root_world"] = MAT["root"].duplicate()   # (draped roots: one plain mesh per chunk, no instance data)
	MAT["root_world"].set_shader_parameter("use_instance", false)
	MAT["wood"] = _mat(w, 0.85)
	MAT["leaf"] = _mat(w, 0.8)
	MAT["leafSoft"] = _mat(w, 0.85)
	MAT["rock"] = _mat(lin(0xa8a39a), 0.82, 0.02)
	MAT["tuft"] = _mat(w, 0.9)
	MAT["shed"] = _mat(w, 0.85)
	MAT["fence"] = _mat(w, 0.9)
	MAT["stake"] = _mat(w, 0.6)
	var sb := ShaderMaterial.new()
	sb.shader = preload("res://shaders/sign_board.gdshader")
	sb.set_shader_parameter("board_tex", load("res://assets/signs/distance_board.png"))
	sb.set_shader_parameter("grime_tex", load("res://assets/textures/grime/grime_dirt.jpg"))
	sb.set_shader_parameter("grime_nrm", load("res://assets/textures/grime/grime_normal.jpg"))
	sb.set_shader_parameter("dirt_tex", load("res://assets/textures/lens/lens_dirt.png"))
	sb.set_shader_parameter("wood_col", load("res://assets/textures/wood_plank/wood_color.jpg"))
	sb.set_shader_parameter("wood_nrm", load("res://assets/textures/wood_plank/wood_normal.jpg"))
	MAT["signboard"] = sb
	# wooden fences: the Wood049 scan (clean sawn-plank grain), grain along the rails / up the posts and pickets (white = painted)
	for k in [["fenceRail", 0], ["fencePost", 1]]:
		var fm := ShaderMaterial.new()
		fm.shader = preload("res://shaders/wood_fence.gdshader")
		fm.set_shader_parameter("grain_axis", k[1])
		fm.set_shader_parameter("wood_col", load("res://assets/textures/wood_plank/wood_color.jpg"))
		fm.set_shader_parameter("wood_nrm", load("res://assets/textures/wood_plank/wood_normal.jpg"))
		fm.set_shader_parameter("wood_rgh", load("res://assets/textures/wood_plank/wood_rough.jpg"))
		fm.set_shader_parameter("grime_tex", load("res://assets/textures/grime/grime_dirt.jpg"))
		MAT[k[0]] = fm
	var sp := ShaderMaterial.new()
	sp.shader = preload("res://shaders/sign_pole.gdshader")
	sp.set_shader_parameter("wood_col", load("res://assets/textures/wood_post/wood_color.jpg"))
	sp.set_shader_parameter("wood_nrm", load("res://assets/textures/wood_post/wood_normal.jpg"))
	sp.set_shader_parameter("wood_rgh", load("res://assets/textures/wood_post/wood_rough.jpg"))
	MAT["signpole"] = sp
	MAT["cactus"] = _mat(w, 0.7)
	MAT["cactus"].set_shader_parameter("tint_own", true)
	# what the wind moves (m of sway per m of height in a full gust) and how much sun shows through
	for k in [["leaf", 0.02, 0.2], ["cactus", 0.004, 0.12], ["leafSoft", 0.035, 0.25], ["tuft", 0.12, 0.3]]:
		MAT[k[0]].set_shader_parameter("sway", k[1])
		MAT[k[0]].set_shader_parameter("backlight", k[2])
		MAT[k[0]].set_shader_parameter("specular", 0.1)
	# golden-hour light through the leaves (view dependent: low sun behind the plant) and, for crowns,
	# dappled shadows (holes in their sun shadow: flecks of sun under the trees). Trunks / rocks / wood: none.
	for k in [["leaf", 0.7, 0.0, 0.32], ["leafSoft", 0.9, 0.0, 0.4], ["tuft", 0.8, 0.0, 0.0], ["cactus", 0.5, 1.0, 0.0]]:
		MAT[k[0]].set_shader_parameter("scatter", k[1])
		MAT[k[0]].set_shader_parameter("scatter_rim", k[2])
		MAT[k[0]].set_shader_parameter("dapple", k[3])
	var f := ShaderMaterial.new()
	f.shader = preload("res://scripts/world/flower.gdshader")
	MAT["flower"] = f


## normals smoothed across faces less than ~60 deg apart (cylinders: round sides, flat caps)
static func _soft_normals(g: GeoBuf) -> PackedVector3Array:
	var fn := g.face_normals()
	var groups := {}
	var keys := []
	keys.resize(g.pos.size())
	for i in g.pos.size():
		var p := g.pos[i]
		var key := Vector3i(roundi(p.x * 10000), roundi(p.y * 10000), roundi(p.z * 10000))
		keys[i] = key
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	var out := PackedVector3Array()
	out.resize(g.pos.size())
	for i in g.pos.size():
		var s := Vector3.ZERO
		for j in groups[keys[i]]:
			if fn[j].dot(fn[i]) > 0.5:
				s += fn[j]
		out[i] = s.normalized() if s.length_squared() > 1e-12 else fn[i]
	return out


# ---------------- boulders & crowns ----------------
static func _h3(x: float, y: float, z: float, sd: float) -> float:
	var nn := sin(x * 127.1 + y * 311.7 + z * 74.7 + sd * 13.1) * 43758.5453
	return nn - floorf(nn)


static func _vn(x: float, y: float, z: float, sd: float) -> float:
	var xi := floorf(x); var yi := floorf(y); var zi := floorf(z)
	var xf := x - xi; var yf := y - yi; var zf := z - zi
	var u := xf * xf * (3 - 2 * xf); var w := yf * yf * (3 - 2 * yf); var t := zf * zf * (3 - 2 * zf)
	var a := lerpf(lerpf(_h3(xi, yi, zi, sd), _h3(xi + 1, yi, zi, sd), u), lerpf(_h3(xi, yi + 1, zi, sd), _h3(xi + 1, yi + 1, zi, sd), u), w)
	var b := lerpf(lerpf(_h3(xi, yi, zi + 1, sd), _h3(xi + 1, yi, zi + 1, sd), u), lerpf(_h3(xi, yi + 1, zi + 1, sd), _h3(xi + 1, yi + 1, zi + 1, sd), u), w)
	return lerpf(a, b, t)


static func _boulder(sd: float, detail: int) -> GeoBuf:
	var g := GeoBuf.ico(1, detail)
	var facet := Vector3(0.6, 0.5, 0.62).normalized()
	var rad := PackedFloat32Array()
	rad.resize(g.pos.size())
	for i in g.pos.size():
		var v := g.pos[i]
		var q := v * 1.4
		var fbm := _vn(q.x + 5, q.y, q.z - 3, sd) * 0.55 + _vn((q.x + 5) * 2.1, q.y * 2.1, (q.z - 3) * 2.1, sd) * 0.28 \
			+ _vn((q.x + 5) * 4.3, q.y * 4.3, (q.z - 3) * 4.3, sd) * 0.12 + _vn((q.x + 5) * 9, q.y * 9, (q.z - 3) * 9, sd) * 0.05
		var r := 0.78 + fbm * 0.55
		r *= 1 - 0.12 * maxf(0, v.dot(facet) - 0.55) * 3
		v *= r
		if v.y < -0.25:
			v.y = -0.25 + (v.y + 0.25) * 0.25
		v.y *= 0.82
		g.pos[i] = v
		rad[i] = r
	var nr := g.face_normals()
	for i in g.pos.size():
		var v := g.pos[i]
		var cav := clampf((rad[i] - 0.8) / 0.45, 0, 1)
		var speck := 0.9 + _h3(v.x * 40, v.y * 40, v.z * 40, sd) * 0.2
		var c := (0.62 + cav * 0.45) * speck
		var moss := maxf(0, nr[i].y - 0.55) * 1.6 * (0.5 + 0.5 * _vn(v.x * 3, v.y * 3, v.z * 3, sd))
		g.col[i] = Color(c * (1 - moss * 0.35), c * (1 + moss * 0.05), c * (1 - moss * 0.45))
	return g


static func _crown(sd: float, detail: int, flat_base: bool) -> GeoBuf:
	var g := GeoBuf.ico(1, detail)
	var lump := PackedFloat32Array()
	lump.resize(g.pos.size())
	for i in g.pos.size():
		var v := g.pos[i]
		var l := _vn(v.x * 1.6 + 4, v.y * 1.6, v.z * 1.6 - 2, sd) * 0.7 + _vn(v.x * 3.4, v.y * 3.4 + 9, v.z * 3.4, sd) * 0.3
		v *= 0.84 + l * 0.32
		if flat_base and v.y < -0.35:
			v.y = -0.35 + (v.y + 0.35) * 0.3
		g.pos[i] = v
		lump[i] = l
	for i in g.pos.size():
		var y := g.pos[i].y
		var c := (0.72 + 0.28 * clampf(y * 0.6 + 0.55, 0, 1)) * (0.86 + lump[i] * 0.22)
		g.col[i] = Color(c, c, c * 0.97)
	return g


static func _jitter(g: GeoBuf, amt: float, sd: int) -> GeoBuf:
	var r := WorldRng.new(sd)
	var m := {}
	for i in g.pos.size():
		var p := g.pos[i]
		var key := Vector3i(roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000))
		if not m.has(key):
			m[key] = Vector3((r.next() - .5) * amt, (r.next() - .5) * amt, (r.next() - .5) * amt)
		g.pos[i] = p + m[key]
	return g


# ---------------- wildflowers, grass, ferns, mushrooms ----------------
static func _blade(len: float, wid: float, cup: float) -> GeoBuf:
	return GeoBuf.of(PackedVector3Array([Vector3(0, 0, 0), Vector3(len * 0.45, cup * 0.4, -wid), Vector3(len, cup, 0),
		Vector3(0, 0, 0), Vector3(len, cup, 0), Vector3(len * 0.45, cup * 0.4, wid)]))


static func _part(g: GeoBuf, hex: int, tint: float, shade: Callable = Callable()) -> GeoBuf:
	var c := lin(hex)
	for i in g.pos.size():
		var k := 1.0
		if shade.is_valid():
			k = shade.call(g.pos[i])
		g.col[i] = Color(c.r * k, c.g * k, c.b * k)
		g.tint[i] = tint
	return g


static func _flowers() -> Dictionary:
	var STEM := 0x4c8a2c
	var LEAF := 0x5f9e38
	var EYE := 0xf0b030
	var stem := func(h: float) -> GeoBuf: return _part(GeoBuf.cylinder(0.005, 0.008, h, 3).translate(0, h / 2, 0), STEM, 0)
	var leaves := func(y: float, len: float) -> Array:
		var out := []
		var angs := [0.0, 2.6]
		for i in 2:
			out.append(_part(_blade(len, 0.018, len * 0.35).rot_y(angs[i] + i * 0.4).translate(0, y + i * 0.03, 0), LEAF, 0))
		return out
	var petal_shade := func(p: Vector3) -> float: return 0.78 + 0.22 * minf(1, Vector2(p.x, p.z).length() / 0.06)
	# daisy
	var DH := 0.24
	var head := []
	for i in 8:
		head.append(_part(_blade(0.075, 0.02, 0.018).rot_y(i * PI / 4 + 0.2), 0xffffff, 1, petal_shade))
	head.append(_part(GeoBuf.ico(0.022, 0).scale(1, 0.55, 1).translate(0, 0.006, 0), EYE, 0))
	var daisy_parts: Array = [stem.call(DH)]
	daisy_parts.append_array(leaves.call(0.05, 0.085))
	for g in head:
		daisy_parts.append(g.rot_z(0.18).translate(0.012, DH, 0))
	# tulip
	var TH := 0.26
	var tulip_parts: Array = [stem.call(TH)]
	tulip_parts.append_array(leaves.call(0.04, 0.11))
	for i in 5:
		tulip_parts.append(_part(_blade(0.07, 0.026, 0.0).rot_z(1.2).rot_y(i * TAU / 5), 0xffffff, 1,
			func(p: Vector3) -> float: return 0.7 + 0.3 * minf(1, p.y / 0.06)).translate(0, TH - 0.01, 0))
	# spike
	var SH := 0.32
	var spike_parts: Array = [stem.call(SH)]
	spike_parts.append_array(leaves.call(0.06, 0.1))
	for i in 6:
		var y := SH - 0.13 + i * 0.026
		var r := 0.024 * (1 - i * 0.11)
		var a := i * 2.4
		var k := 0.82 + i * 0.035
		spike_parts.append(_part(GeoBuf.octa(r).translate(cos(a) * 0.012, y, sin(a) * 0.012), 0xffffff, 1, func(_p: Vector3) -> float: return k))
	# grass clump: nine curved, tapered blades, dark at the root, bright at the tip
	var gr := WorldRng.new(4242)
	var blades := []
	for b in 9:
		var h := 0.17 + gr.next() * 0.2
		var w := 0.022 + gr.next() * 0.012
		var lean := 0.25 + gr.next() * 0.55
		var segs := 3
		var pts := PackedVector3Array()
		for k2 in segs:
			var u0 := float(k2) / segs
			var u1 := float(k2 + 1) / segs
			var x0 := lean * h * u0 * u0
			var y0 := h * u0 * (1 - 0.12 * u0 * u0 * lean)
			var x1 := lean * h * u1 * u1
			var y1 := h * u1 * (1 - 0.12 * u1 * u1 * lean)
			var w0 := w * (1 - float(k2) / segs)
			var w1 := w * (1 - float(k2 + 1) / segs)
			pts.append_array([Vector3(x0, y0, -w0 / 2), Vector3(x1, y1, -w1 / 2), Vector3(x0, y0, w0 / 2)])
			if w1 > 1e-5:
				pts.append_array([Vector3(x0, y0, w0 / 2), Vector3(x1, y1, -w1 / 2), Vector3(x1, y1, w1 / 2)])
		var hh := h
		var pg := _part(GeoBuf.of(pts), 0xffffff, 1, func(p: Vector3) -> float: return 0.42 + 0.72 * minf(1, p.y / hh))
		var a := gr.next() * TAU
		var rr := gr.next() * 0.05
		blades.append(pg.rot_y(a).translate(cos(a) * rr, 0, -sin(a) * rr))
	# fern
	var fronds := []
	for i in 7:
		var len := 0.3 + (i % 3) * 0.06
		fronds.append(_part(_blade(len, 0.045, len * 0.25).rot_z(0.55 - (i % 2) * 0.15).rot_y(i * 0.9), 0xffffff, 1,
			func(p: Vector3) -> float: return 0.75 + 0.25 * minf(1, Vector2(p.x, p.z).length() / len)))
	# mushroom
	var MH := 0.07
	var mush := [_part(GeoBuf.cylinder(0.009, 0.013, MH, 5).translate(0, MH / 2, 0), 0xefe6d2, 0),
		_part(GeoBuf.sphere(0.034, 7, 3, 0, TAU, 0, PI / 2).scale(1, 0.6, 1).translate(0, MH - 0.004, 0), 0xffffff, 1)]
	return {"daisy": GeoBuf.merge(daisy_parts), "tulip": GeoBuf.merge(tulip_parts), "spike": GeoBuf.merge(spike_parts),
		"fern": GeoBuf.merge(fronds), "mushroom": GeoBuf.merge(mush), "grass": GeoBuf.merge(blades)}


# ---------------- sheds (sheds.js) ----------------
static func _sbox(w: float, h: float, d: float, x: float, y: float, z: float, col: Color, rx: float = 0, ry: float = 0, rz: float = 0) -> GeoBuf:
	var g := GeoBuf.box(w, h, d)
	if rx != 0: g.rot_x(rx)
	if ry != 0: g.rot_y(ry)
	if rz != 0: g.rot_z(rz)
	return g.translate(x, y, z).paint(col)


static func _scyl(r: float, h: float, x: float, y: float, z: float, col: Color, seg: int = 6, axis: String = "y") -> GeoBuf:
	var g := GeoBuf.cylinder(r, r, h, seg)
	if axis == "x": g.rot_z(PI / 2)
	if axis == "z": g.rot_x(PI / 2)
	return g.translate(x, y, z).paint(col)


static func _battens(o: Array, x0: float, z0: float, x1: float, z1: float, nx: float, nz: float, y0: float, y1, col: Color, step: float = 0.42) -> void:
	var len := Vector2(x1 - x0, z1 - z0).length()
	var k: int = maxi(1, WorldRng.jround(len / step))
	for i in range(1, k):
		var t := float(i) / k
		var x := x0 + (x1 - x0) * t + nx * 0.03
		var z := z0 + (z1 - z0) * t + nz * 0.03
		var top: float = y1.call(x, z) if y1 is Callable else y1
		o.append(_sbox(0.04 if nx != 0 else 0.06, top - y0, 0.06 if nx != 0 else 0.04, x, (y0 + top) / 2, z, col))


static func _door(o: Array, x: float, z: float, w: float, h: float, y0: float, wood: Color, trim: Color, metal: Color) -> void:
	o.append(_sbox(w + 0.14, h + 0.08, 0.05, x, y0 + (h + 0.08) / 2, z + 0.02, trim))
	o.append(_sbox(w, h, 0.06, x, y0 + h / 2, z + 0.05, wood))
	for yy in [0.22, h - 0.22]:
		o.append(_sbox(w - 0.04, 0.1, 0.03, x, y0 + yy, z + 0.09, trim))
	var diag := atan2(h - 0.44, w - 0.1)
	o.append(_sbox(Vector2(w - 0.1, h - 0.44).length(), 0.09, 0.03, x, y0 + h / 2, z + 0.09, trim, 0, 0, diag))
	o.append(_sbox(0.05, 0.05, 0.06, x + w / 2 - 0.12, y0 + h * 0.5, z + 0.12, metal))


static func _window_side(o: Array, x: float, z: float, w: float, h: float, yc: float, frame: Color, glass: Color) -> void:
	o.append(_sbox(0.05, h + 0.12, w + 0.12, x + 0.02, yc, z, frame))
	o.append(_sbox(0.04, h, w, x + 0.04, yc, z, glass))
	o.append(_sbox(0.03, h, 0.05, x + 0.07, yc, z, frame))
	o.append(_sbox(0.03, 0.05, w, x + 0.07, yc, z, frame))
	o.append(_sbox(0.16, 0.05, w + 0.2, x + 0.08, yc - h / 2 - 0.08, z, frame))
	o.append(_sbox(0.12, 0.2, w + 0.08, x + 0.1, yc - h / 2 - 0.2, z, lin(0x7a4a2a)))
	for dz in [-0.2, 0.0, 0.2]:
		o.append(_sbox(0.1, 0.1, 0.1, x + 0.12, yc - h / 2 - 0.05, z + dz * w * 1.6, lin(0xff5d73 if dz != 0 else 0xffd23f), 0.5, 0.5, 0))


static func _gable(p: Dictionary) -> GeoBuf:
	var STONE := lin(0x8d8a84); var STONE_D := lin(0x6e6b66); var GLASS := lin(0x2c3d4a); var METAL := lin(0x3a3a3a)
	var W := 2.6; var D := 3.2; var F := 0.2; var E := 2.05; var R := 3.0
	var o := []
	var hw := W / 2; var hd := D / 2
	o.append(_sbox(W + 0.24, 0.9, D + 0.24, 0, F - 0.45, 0, STONE))
	o.append(_sbox(0.9, 0.12, 0.45, 0, F - 0.06, hd + 0.3, STONE_D))
	o.append(_sbox(W, E - F, D, 0, (E + F) / 2, 0, p.wall))
	o.append(GeoBuf.prism([Vector2(-hw, E), Vector2(hw, E), Vector2(0, R)], -hd, hd, "z").paint(p.wall))
	var roof_y := func(x: float, _z: float) -> float: return E + (R - E) * (1 - absf(x) / hw) - 0.05
	_battens(o, -hw, hd, hw, hd, 0, 1, F, roof_y, p.batten)
	_battens(o, -hw, -hd, hw, -hd, 0, -1, F, roof_y, p.batten)
	_battens(o, hw, -hd, hw, hd, 1, 0, F, E, p.batten)
	_battens(o, -hw, -hd, -hw, hd, -1, 0, F, E, p.batten)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			o.append(_sbox(0.12, E - F, 0.12, sx * (hw + 0.01), (E + F) / 2, sz * (hd + 0.01), p.trim))
	var pitch := atan2(R - E, hw); var ov := 0.32; var sl := Vector2(hw, R - E).length() + ov; var T := 0.09
	for s in [-1, 1]:
		var cx: float = s * (hw + ov * cos(pitch) - sl * cos(pitch) / 2)
		var cy := R - (sl / 2) * sin(pitch) + T * 0.6
		o.append(_sbox(sl, T, D + 0.6, cx, cy, 0, p.roof, 0, 0, -s * pitch))
		for f in [0.3, 0.62]:
			var along: float = sl * (f - 0.5)
			o.append(_sbox(0.05, 0.04, D + 0.6, cx + s * along * cos(pitch), cy - along * sin(pitch) + T * 0.55, 0, p.roofD, 0, 0, -s * pitch))
		for zz in [-1, 1]:
			o.append(_sbox(sl, 0.16, 0.05, cx, cy - 0.06, zz * (hd + 0.3), p.trim, 0, 0, -s * pitch))
	o.append(_sbox(0.2, 0.12, D + 0.66, 0, R + T + 0.02, 0, p.roofD))
	_door(o, 0, hd, 0.95, 1.8, F, p.door, p.trim, METAL)
	o.append(_sbox(0.36, 0.36, 0.05, 0, E + 0.38, hd + 0.04, p.trim, 0, 0, PI / 4))
	o.append(_sbox(0.24, 0.24, 0.05, 0, E + 0.38, hd + 0.07, GLASS, 0, 0, PI / 4))
	_window_side(o, hw, -0.2, 0.8, 0.6, 1.35, p.trim, GLASS)
	o.append(_scyl(0.3, 0.75, hw + 0.42, F + 0.37, hd - 0.4, lin(0x4d6b8a), 8))
	for yy in [0.2, 0.55]:
		o.append(_scyl(0.315, 0.05, hw + 0.42, F + yy, hd - 0.4, METAL, 8))
	o.append(_scyl(0.04, E - 0.85, hw + 0.36, (E + 0.9) / 2, hd - 0.4, lin(0x9aa0a4), 5))
	return GeoBuf.merge(o)


static func _lean_to(p: Dictionary) -> GeoBuf:
	var STONE := lin(0x8d8a84); var METAL := lin(0x3a3a3a)
	var W := 2.4; var D := 1.9; var F := 0.2; var Hf := 2.25; var Hb := 1.75
	var o := []
	var hw := W / 2; var hd := D / 2
	o.append(_sbox(W + 0.24, 0.9, D + 0.24, 0, F - 0.45, 0, STONE))
	o.append(_sbox(W, Hb - F, D, 0, (Hb + F) / 2, 0, p.wall))
	o.append(GeoBuf.prism([Vector2(-hd, Hb), Vector2(hd, Hb), Vector2(hd, Hf)], -hw, hw, "x").paint(p.wall))
	var top_y := func(_x: float, z: float) -> float: return Hb + (Hf - Hb) * (z + hd) / D - 0.04
	_battens(o, -hw, hd, hw, hd, 0, 1, F, Hf - 0.04, p.batten, 0.36)
	_battens(o, -hw, -hd, hw, -hd, 0, -1, F, Hb - 0.04, p.batten, 0.36)
	_battens(o, hw, -hd, hw, hd, 1, 0, F, top_y, p.batten, 0.36)
	_battens(o, -hw, -hd, -hw, hd, -1, 0, F, top_y, p.batten, 0.36)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var top := Hf if sz > 0 else Hb
			o.append(_sbox(0.12, top - F, 0.12, sx * (hw + 0.01), (top + F) / 2, sz * (hd + 0.01), p.trim))
	var pitch := atan2(Hf - Hb, D); var ov := 0.35; var sl := Vector2(D, Hf - Hb).length() + ov * 2; var T := 0.09
	var ry := (Hf + Hb) / 2 + T * 0.7
	o.append(_sbox(W + 0.7, T, sl, 0, ry, 0, p.roof, -pitch, 0, 0))
	for f in [-0.33, 0.0, 0.33]:
		o.append(_sbox(0.05, 0.04, sl, f * W, ry + T * 0.55, 0, p.roofD, -pitch, 0, 0))
	o.append(_sbox(W + 0.74, 0.16, 0.05, 0, Hf + 0.04 + ov * sin(pitch), hd + ov, p.trim))
	for s in [-1, 1]:
		_door(o, s * 0.42, hd, 0.8, 1.75, F, p.door, p.trim, METAL)
	var LOG := lin(0x8a5a34); var END := lin(0xd9b27c)
	for r in 4:
		for i in 6 - (1 if r > 2 else 0):
			var z := -hd + 0.2 + i * 0.27 + (r & 1) * 0.13
			var y := F + 0.12 + r * 0.22
			o.append(_scyl(0.11, 0.5, hw + 0.33, y, z, LOG, 6, "x"))
			o.append(_scyl(0.095, 0.02, hw + 0.59, y, z, END, 6, "x"))
	o.append(_scyl(0.22, 0.42, -hw - 0.5, F + 0.0, hd + 0.2, LOG, 7))
	o.append(_scyl(0.2, 0.02, -hw - 0.5, F + 0.22, hd + 0.2, END, 7))
	o.append(_sbox(0.04, 0.55, 0.04, -hw - 0.5, F + 0.48, hd + 0.2, lin(0xb08955), 0, 0, 0.35))
	o.append(_sbox(0.03, 0.12, 0.16, -hw - 0.58, F + 0.27, hd + 0.2, METAL, 0, 0, 0.35))
	return GeoBuf.merge(o)


const PALETTES := [
	{"wall": 0xb5462f, "batten": 0x9a3a27, "trim": 0xf0e6d0, "roof": 0x4a4440, "roofD": 0x3a3532, "door": 0xa63f2a},
	{"wall": 0x6f948d, "batten": 0x5e817b, "trim": 0xf1ede2, "roof": 0x8a3b2e, "roofD": 0x6e2e24, "door": 0x3f6b73},
	{"wall": 0xa8743f, "batten": 0x8c5e31, "trim": 0x6b4528, "roof": 0x8d949a, "roofD": 0x6f767c, "door": 0x7c5230},
	{"wall": 0xe4d6b0, "batten": 0xd3c39a, "trim": 0x5a6e48, "roof": 0x5a6e48, "roofD": 0x46583a, "door": 0x6f8a52},
]
## footprint (local, metres) and extra collider circles, per shape (SHED_DESIGNS order: gable x4, leanTo x4)
const SHED_SHAPES := [
	{"hw": 1.3, "hd": 1.6, "extra": [[1.72, 1.2, 0.35]]},
	{"hw": 1.2, "hd": 0.95, "extra": [[1.55, -0.4, 0.3], [1.55, 0.4, 0.3], [-1.7, 1.15, 0.25]]},
]


## design list without meshes (safe on worker threads): [{hw, hd, extra}] x 8
static func shed_designs() -> Array:
	var out := []
	for s in 2:
		for i in 4:
			out.append(SHED_SHAPES[s])
	return out


static func _build_sheds() -> void:
	SHEDS = []
	for s in 2:
		for pal in PALETTES:
			var p := {}
			for k in pal:
				p[k] = lin(pal[k])
			var g: GeoBuf = _gable(p) if s == 0 else _lean_to(p)
			SHEDS.append(g.to_mesh())
