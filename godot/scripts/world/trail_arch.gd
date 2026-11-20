class_name TrailArch
extends RefCounted
## Rare rock tunnels and cliff overhangs over the trail. Pure visual props (one merged blobby-rock mesh each,
## no collision: the rider passes through). Placed by TerrainChunkBuilder._arches from TrailCourse.chunk_arches.

const KIND_OVERHANG := 0
const KIND_TUNNEL := 1

static var _mat: StandardMaterial3D
static var _mesh: SphereMesh


## which prop sits in 200 m slot k of the trail: -1 none, 0 overhang, 1 tunnel
static func kind_for(k: int, seed_i: int) -> int:
	var r := TrailCourse._hash(k, seed_i + 11)
	if r < 0.08:
		return KIND_TUNNEL
	if r < 0.17:
		return KIND_OVERHANG
	return -1


static func _blob(st: SurfaceTool, rng: RandomNumberGenerator, pos: Vector3, size: float) -> void:
	var sc := Vector3(size * (0.8 + rng.randf() * 0.5), size * (0.65 + rng.randf() * 0.45), size * (0.8 + rng.randf() * 0.5))
	var b := Basis.from_euler(Vector3(rng.randf() * 0.8, rng.randf() * TAU, rng.randf() * 0.8)).scaled(sc)
	st.append_from(_mesh, 0, Transform3D(b, pos))


## a = {x, z, tx, tz, half, hl, hr, hc, i, kind}
static func build(a: Dictionary) -> Node3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.36, 0.32, 0.28)
		_mat.roughness = 1.0
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 7
		_mesh.rings = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["i"]) * 7919 + 13
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = a["half"]
	var hl: float = a["hl"]
	var hr: float = a["hr"]
	var gm := (hl + hr) * 0.5
	if int(a["kind"]) == KIND_TUNNEL:
		var L := 22.0
		var R := half + 0.7
		var rings := 9
		for ri in rings:
			var z := -L * 0.5 + L * ri / (rings - 1)
			var end := ri == 0 or ri == rings - 1
			for q in 11:
				var ang := PI * q / 10.0
				var px := cos(ang) * R
				var py := gm + sin(ang) * (R * 0.95 + 0.6)
				_blob(st, rng, Vector3(px, py, z), (1.7 if end else 1.4) + rng.randf() * 0.5)
				# outer shell: a thick mound over the tube
				var ro := R + 1.5
				_blob(st, rng, Vector3(cos(ang) * ro, gm + sin(ang) * (ro * 0.95 + 0.6), z + rng.randf() - 0.5), 2.2 + rng.randf() * 0.7)
			# feet: down to the ground each side
			_blob(st, rng, Vector3(-R, hl - 0.8, z), 2.0 + rng.randf() * 0.5)
			_blob(st, rng, Vector3(R, hr - 0.8, z), 2.0 + rng.randf() * 0.5)
			_blob(st, rng, Vector3(-R - 1.6, hl - 1.2, z), 2.3)
			_blob(st, rng, Vector3(R + 1.6, hr - 1.2, z), 2.3)
	else:
		var side := 1.0 if TrailCourse._hash(int(a["i"]), 3) < 0.5 else -1.0
		var L := 16.0
		var base_h: float = hl if side < 0.0 else hr
		for ri in 7:
			var z := -L * 0.5 + L * ri / 6.0
			# the cliff face behind
			for lv in 4:
				_blob(st, rng, Vector3(side * (half + 1.6 + rng.randf() * 0.6), base_h - 1.0 + lv * 2.0, z), 2.3 + rng.randf() * 0.6)
			# the ledge jutting out over the trail, 5 m up
			for cx in 4:
				var off := half + 1.4 - cx * (half * 0.55)
				_blob(st, rng, Vector3(side * off, gm + 5.4 + rng.randf() * 0.5, z + rng.randf() - 0.5), 1.9 + rng.randf() * 0.5)
			_blob(st, rng, Vector3(side * (half * 0.5), gm + 7.0, z), 2.4)
	st.generate_normals()
	var n := Node3D.new()
	var fwd := Vector3(a["tx"], 0, a["tz"])
	n.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(a["x"], 0, a["z"]))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.visibility_range_end = 420.0
	n.add_child(mi)
	return n
