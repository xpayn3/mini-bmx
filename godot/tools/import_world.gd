extends SceneTree
## The level builder's "Import world trail" (run by the editor plugin as its own headless Godot, since the world's
## generator can't run inside the editor): -- <seed> <start m> <length m> <out file>
## Cuts that stretch of the procedural world's trail out, turns it so it runs down +x from (8, 0) like a level, keeps
## a few Bezier points of it (Ramer-Douglas-Peucker, 1.2 m), and samples the world's land at 1 m round it (relative
## to the start's height). Writes {pts, H, x0, z0, nx, nz, length, width, seed, start} with store_var.
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 4:
		push_error("import_world: -- seed start length out"); quit(1); return
	var sd := int(a[0]); var s0 := float(a[1]); var L := float(a[2]); var out := a[3]
	var t := Terrain.new(sd)   # (the seed to the constructor: set_seed after builds the world twice)
	var c: TrailCourse = t.field.course
	var i0 := clampi(int(s0 / TrailCourse.STEP), 0, c.n - 2)
	var i1 := clampi(int((s0 + L) / TrailCourse.STEP), i0 + 2, c.n - 1)
	var o := Vector2(c.X[i0], c.Z[i0])
	var e := Vector2(c.X[i1], c.Z[i1])
	var ang := atan2(e.y - o.y, e.x - o.x)
	var ca := cos(ang); var sa := sin(ang)
	var y0 := t.deck_height(o.x, o.y)
	var loc := PackedVector2Array()
	for i in range(i0, i1 + 1):
		var d := Vector2(c.X[i], c.Z[i]) - o
		loc.append(Vector2(d.x * ca + d.y * sa + 8.0, -d.x * sa + d.y * ca))
	var keep := _rdp(loc, 1.2)
	var maxx := 0.0; var maxz := 0.0
	for p in loc: maxx = maxf(maxx, p.x); maxz = maxf(maxz, absf(p.y))
	var length := maxf(100.0, ceilf(maxx + 30.0))
	var width := maxf(80.0, ceilf(maxz * 2.0 + 80.0))
	# the land at 1 m over the level's whole grid: x -40 .. length + 40, z -(width / 2 + 10) .. +
	var gx0 := -41.0; var gz0 := -(width * 0.5 + 11.0)
	var nx := int(length + 83.0); var nz := int(width + 23.0)
	var H := PackedFloat32Array(); H.resize(nx * nz)
	for j in nz:
		for i in nx:
			var lx := gx0 + i - 8.0; var lz := gz0 + j
			var wx := o.x + lx * ca - lz * sa; var wz := o.y + lx * sa + lz * ca
			H[j * nx + i] = t.deck_height(wx, wz) - y0
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_var({"pts": keep, "H": H, "x0": gx0, "z0": gz0, "nx": nx, "nz": nz, "length": length, "width": width, "seed": sd, "start": s0})
	fa.close()
	print("IMPORTWORLD seed=%d start=%.0f len=%.0f points=%d->%d level=%.0fx%.0f grid=%dx%d" % [sd, s0, L, loc.size(), keep.size(), length, width, nx, nz])
	t.free()
	quit()


static func _rdp(p: PackedVector2Array, eps: float) -> PackedVector2Array:
	if p.size() < 3: return p
	var dmax := 0.0; var idx := 0
	var a := p[0]; var b := p[p.size() - 1]
	var ab := b - a
	var l := maxf(ab.length(), 1e-6)
	for i in range(1, p.size() - 1):
		var d := absf(ab.cross(p[i] - a)) / l
		if d > dmax: dmax = d; idx = i
	if dmax <= eps: return PackedVector2Array([a, b])
	var left := _rdp(p.slice(0, idx + 1), eps)
	var right := _rdp(p.slice(idx), eps)
	left.remove_at(left.size() - 1)
	left.append_array(right)
	return left
