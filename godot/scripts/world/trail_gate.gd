class_name TrailGate
extends RefCounted
## Distance gates over the trail: wooden-stick towers with a cloth flag between them (the chunk builder
## makes the towers, Terrain adds the flag from this).

# made-up brands: [name, background hex, text hex]
const SPONSORS := [
	["REDSHIFT", 0xd8262b, 0xffffff], ["NITRO", 0xf5c518, 0x1a1a1a], ["APEX BIKES", 0x1f5fbf, 0xffffff],
	["TERRA", 0x2e7d4a, 0xffffff], ["FOXTAIL", 0xf07a1c, 0x1a1a1a], ["GRIPZONE", 0x18181c, 0xf5c518],
	["SUMMIT", 0xf2efe6, 0x1f3a6e], ["VOLT", 0x7b3fc4, 0xffffff], ["DIRTLAB", 0x3a3a40, 0xff6a1a],
	["HYDRA", 0x13a3b5, 0xffffff], ["IRONHOOF", 0x8c1d1d, 0xf2efe6], ["SPRINT", 0xe8e8e8, 0xd8262b]]

static var _steel: StandardMaterial3D
static var _font: FontVariation


static func sponsor(seed_i: int) -> Array:
	return SPONSORS[posmod(seed_i * 7 + (seed_i >> 3), SPONSORS.size())]


static func font() -> Font:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.9
	return _font


static func label(text: String, col: Color, width: float, height: float, basis: Basis, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = 200
	l.pixel_size = clampf(minf(height * 0.62 / 200.0, width * 0.9 / (maxf(text.length(), 3) * 0.62 * 200.0)), 0.001, 0.02)
	l.modulate = col
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.transform = Transform3D(basis, at)
	return l


## the text on a distance flag: "300 M", "1.2 KM"
static func dist_text(m: float) -> String:
	if m < 1000.0:
		return "%d M" % int(round(m / 10.0) * 10.0)
	var km := snappedf(m / 1000.0, 0.1)
	return ("%d KM" % int(km)) if is_equal_approx(km, floorf(km)) else ("%.1f KM" % km)


## a cloth flag with the distance on both sides: g = {at, w, h, basis (z = back up the trail), dist, i}
static func flag(g: Dictionary) -> Node3D:
	var sp := sponsor(int(g["i"]))
	var w: float = g["w"]
	var h: float = g["h"]
	var n := Node3D.new()
	n.transform = Transform3D(g["basis"], g["at"])
	# a grid of cloth that hangs a little loose: billows more towards the bottom edge
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 14
	var nv := 5
	var ph := float(g["i"]) * 0.7
	for iv in nv:
		for iu in nu:
			for c in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
				var u := float(iu + c[0]) / nu
				var v := float(iv + c[1]) / nv
				var z := 0.05 * sin(u * 9.0 + ph) * (0.25 + 0.75 * v) * sin(minf(u, 1.0 - u) * PI * 2.0 + 0.2)
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3((u - 0.5) * w, (0.5 - v) * h, z))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TerrainField.lin(sp[1])
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	n.add_child(mi)
	var txt := dist_text(g["dist"])
	var tc: Color = Color.html("#%06x" % sp[2])
	n.add_child(label(txt, tc, w, h, Basis.IDENTITY, Vector3(0, 0, 0.07)))
	n.add_child(label(txt, tc, w, h, Basis(Vector3.UP, PI), Vector3(0, 0, -0.07)))
	return n


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	parent.add_child(m)


## one gantry: g = {x, z, tx, tz, half, hl, hr, hc, i}
static func build(g: Dictionary) -> Node3D:
	if _steel == null:
		_steel = StandardMaterial3D.new()
		_steel.albedo_color = Color(0.2, 0.22, 0.26)
		_steel.metallic = 0.15
		_steel.roughness = 0.6
	var sp := sponsor(int(g["i"]))
	var n := Node3D.new()
	var fwd := Vector3(g["tx"], 0, g["tz"])
	# local -Z = the way the riders go, so the front of the banner (local +Z) faces them
	var basis := Basis.looking_at(fwd, Vector3.UP)
	n.transform = Transform3D(basis, Vector3(g["x"], 0, g["z"]))
	var half: float = g["half"]
	var ytop: float = maxf(g["hl"], g["hr"]) + 8.4
	var bw := half * 2.0 + 1.0
	var bh := 2.5
	for s in [-1.0, 1.0]:
		var gh: float = g["hl"] if s < 0.0 else g["hr"]
		var ph: float = ytop - gh + 0.6
		# side of the trail: local x = ±half  (Basis.looking_at: x is to the riders' right)
		_box(n, Vector3(0.55, ph, 0.55), Vector3(s * half, gh - 0.6 + ph / 2.0, 0), _steel)
		_box(n, Vector3(1.0, 0.5, 1.0), Vector3(s * half, gh + 0.05, 0), _steel)
		# diagonal brace up to the truss
		var br := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.2, 1.9, 0.2)
		br.mesh = bm
		br.material_override = _steel
		br.position = Vector3(s * (half - 0.8), ytop - bh - 0.4 - 0.75, 0)
		br.rotation = Vector3(0, 0, -s * 0.7)
		n.add_child(br)
	# top truss (two chords + the banner hanging under it)
	_box(n, Vector3(half * 2.0 + 1.1, 0.28, 0.5), Vector3(0, ytop, 0), _steel)
	_box(n, Vector3(half * 2.0 + 1.1, 0.2, 0.5), Vector3(0, ytop - bh - 0.4, 0), _steel)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = TerrainField.lin(sp[1])
	bmat.roughness = 0.8
	var by := ytop - 0.2 - bh / 2.0
	_box(n, Vector3(bw, bh, 0.1), Vector3(0, by, 0), bmat)
	var tc: Color = Color.html("#%06x" % sp[2])
	n.add_child(label(sp[0], tc, bw, bh, Basis.IDENTITY, Vector3(0, by, 0.07)))
	n.add_child(label(sp[0], tc, bw, bh, Basis(Vector3.UP, PI), Vector3(0, by, -0.07)))
	# two floodlight boxes on the truss
	for s in [-0.3, 0.3]:
		_box(n, Vector3(0.5, 0.3, 0.4), Vector3(s * bw, ytop + 0.3, 0.1), _steel)
	return n
