extends SceneTree
## Dumps the test playground's course data (PlaygroundCourse + JumpDesign) for the Unity port's check
## (unity/SimTests PLAYGROUND: the C# port in unity/Assets/Runout/Levels must give the same numbers).
## Writes one gzip'd tab-separated text file: bounds, every lane (its float32 profile h and mask m as hex), every
## feature (all its keys; designed jumps with their JumpDesign result), every bowl, every rock, then the samples:
## height_rocks / jump_mask / is_dirt / surface_at / feature_at on a 0.25 m grid along every lane row (z = lane z,
## +-0.5, +-1.5, +-3.2 m) and a 1 m grid over each bowl. Floats are written as the hex of their 8 little-endian
## bytes (exact).
## Usage: ..._console.exe --headless --path godot -s res://tools/pg_dump.gd -- out=<file.txt.gz>

var _L := PackedStringArray()


func _hx(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


func _val(v) -> String:
	match typeof(v):
		TYPE_FLOAT: return "f:" + _hx(v)
		TYPE_INT: return "i:%d" % v
		TYPE_BOOL: return "b:%d" % (1 if v else 0)
		TYPE_STRING, TYPE_STRING_NAME: return "s:" + str(v).replace("\t", " ")
		TYPE_PACKED_FLOAT32_ARRAY: return "h:" + (v as PackedFloat32Array).to_byte_array().hex_encode()
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for e in v: parts.append(_val(e))
			return "a:[" + "|".join(parts) + "]"
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			var keys: Array = v.keys(); keys.sort()
			for k in keys: parts.append(str(k) + "=" + _val(v[k]))
			return "d:{" + ";".join(parts) + "}"
	return "?:" + str(v)


func _rect(r: Rect2) -> String:
	return "%s,%s,%s,%s" % [_hx(r.position.x), _hx(r.position.y), _hx(r.size.x), _hx(r.size.y)]


func _feat(f: Dictionary) -> String:
	var parts := PackedStringArray()
	var keys: Array = f.keys(); keys.sort()
	for k in keys:
		if k == "bowl": parts.append("bowl=s:" + f.bowl.id); continue
		if k == "ramp": continue
		if k == "design":
			var d: Dictionary = f.design
			var dp := PackedStringArray()
			var dk: Array = d.keys(); dk.sort()
			for kk in dk: dp.append(str(kk) + "=" + _val(d[kk]))
			parts.append("design=D{" + ";".join(dp) + "}")
			continue
		parts.append(str(k) + "=" + _val(f[k]))
	return "\t".join(parts)


func _sample(c: PlaygroundCourse, x: float, z: float) -> void:
	var f = c.feature_at(x, z)
	_L.append("S\t%s\t%s\t%s\t%d\t%d\t%d\t%s" % [_hx(x), _hx(z), _hx(c.height_rocks(x, z)), int(c.jump_mask(x, z)),
		1 if c.is_dirt(x, z) else 0, c.surface_at(x, z), f.id if f != null else "-"])


func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	if out == "":
		print("PG_DUMP need out=<file>"); quit(1); return
	var c := PlaygroundCourse.new()
	_L.append("BOUNDS\t" + _rect(c.bounds))
	for l in c.lanes:
		_L.append("LANE\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % [l.id, l.title, _hx(l.z), _hx(l.hw), _hx(l.band), _rect(l.rect),
			l.h.to_byte_array().hex_encode(), l.m.hex_encode(), _val(l.camber), _val(l.skews), _val(l.surfs), _val(l.cones)])
	for f in c.feats:
		_L.append("FEAT\t" + _feat(f))
		var sp: Vector3 = c.spawn_for(f)
		var fp: Vector3 = c.feat_point(f, float(f.u0) + 1.0) if not f.has("bowl") else Vector3.ZERO
		_L.append("SPAWN\t%s\t%s,%s,%s\t%s,%s,%s" % [f.id, _hx(sp.x), _hx(sp.y), _hx(sp.z), _hx(fp.x), _hx(fp.y), _hx(fp.z)])
	for b in c.bowls:
		_L.append("BOWL\t%s\t%s\t%s,%s\t%s\t%s\t%s\t%s\t%s\t%s" % [b.id, b.title, _hx(b.c.x), _hx(b.c.y), _hx(b.R), _hx(b.W), _hx(b.tn),
			_hx(b.deg), _hx(b.open_dir), _rect(b.rect)])
	for r in c.rocks:
		_L.append("ROCK\t" + _val(r))
	var n := 0
	for l in c.lanes:
		for dz in [0.0, 0.5, -0.5, 1.5, -1.5, 3.2, -3.2]:
			var z: float = l.z + dz
			var x := PlaygroundCourse.X0 - 2.0
			var x1: float = PlaygroundCourse.X0 + l.length() + 2.0
			var i := 0
			while x <= x1:
				_sample(c, x, z); n += 1
				i += 1; x = PlaygroundCourse.X0 - 2.0 + i * 0.25
	for b in c.bowls:
		var r: Rect2 = b.rect
		for iz in int(r.size.y) + 1:
			for ix in int(r.size.x) + 1:
				_sample(c, r.position.x + ix, r.position.y + iz); n += 1
	var bytes := "\n".join(_L).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var fa := FileAccess.open(out, FileAccess.WRITE)
	if fa == null:
		print("PG_DUMP can't write ", out); quit(1); return
	fa.store_buffer(bytes)
	fa.close()
	print("PG_DUMP lanes=%d feats=%d bowls=%d rocks=%d samples=%d bytes=%d -> %s" % [c.lanes.size(), c.feats.size(), c.bowls.size(), c.rocks.size(), n, bytes.size(), out])
	quit(0)
