extends SceneTree
## Reference for the Unity world port (unity/Assets/Runout/World, engine-free C#): per seed, everything the world
## setup builds (TerrainField's own tables, the TrailCourse, the RouteSpine, the route features: every script
## variable, as a tagged binary tree) + the field queried at sample points (heights, masks, berms, biome, colours).
## The Unity side (unity/SimTests WorldCheck) must reproduce both exactly.
## godot --headless --path godot --script res://tools/world_dump.gd -- out=<dir> [seeds=4242,5,12] [grow=1]
##
## File: "RWD1", then one value. Tags: 0 null, 1 bool, 2 int64, 3 float64, 4 string, 5 f64[], 6 f32[], 7 i32[],
## 8 i64[], 9 Color (4 x f32), 10 Array (n, values), 11 Dictionary (n, key value), 12 Object (class name, then a
## Dictionary of its script variables), 13 Object already written (its index), 14 Color[] (n x 4 f32),
## 15 Vector2 (2 x f32), 16 Vector3 (3 x f32), 17 string[] (n strings).

const STYLE := {"jumps": 1.0, "bends": 1.0, "rolling": 1.0, "grade": 1.0, "biome": 0.0}
const SKIP := ["_M", "_r", "_cells", "_jc", "_sn_key", "script", "Built-in script"]

var _f: FileAccess
var _objs := []


func _init() -> void:
	var out := ""
	var seeds := [4242, 5, 12]
	var grow := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		elif a.begins_with("seeds="):
			seeds = []
			for s in a.substr(6).split(","): seeds.append(int(s))
		elif a == "grow=1": grow = true
	if out == "":
		push_error("world_dump: out=<dir> needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	for seed in seeds:
		var t := Time.get_ticks_msec()
		var f := TerrainField.new()
		f.setup(seed, STYLE)
		if grow:
			f.grow_course(f.course.length + 3000.0)
		_write(out.path_join("setup_%d.rwd" % seed), _setup_tree(f))
		_write(out.path_join("samples_%d.rwd" % seed), _samples(f, seed))
		print("WORLDDUMP seed=%d course_m=%.1f feats=%d ms=%d" % [seed, f.course.length, f.route_feats.size(), Time.get_ticks_msec() - t])
	quit(0)


## the field's own tables + course + spine (the route features are inside the field's variables)
func _setup_tree(f: TerrainField) -> Dictionary:
	return {"field": f, "land": f.land_get() if f.has_method("land_get") else {}}


## the field queried at fixed points: random within 1.5 km, along the course across its width, on route features
func _samples(f: TerrainField, seed: int) -> Dictionary:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	var r := WorldRng.new(seed + 7)
	for i in 6000:
		var a := r.next() * TAU
		var d := sqrt(r.next()) * 1500.0
		xs.append(cos(a) * d); zs.append(sin(a) * d)
	var C: TrailCourse = f.course
	for i in 6000:
		var p: Array = C.at(r.next() * C.length)
		var w: float = (r.next() - 0.5) * 30.0
		xs.append(p[0] - p[3] * w); zs.append(p[1] + p[2] * w)
	var feats: Array = f.route_feats
	for i in 3000:
		if feats.is_empty(): break
		var j: TerrainField.Feat = feats[i % feats.size()]
		var u: float = r.next() * j.len
		var w: float = (r.next() - 0.5) * 2 * j.half
		xs.append(j.x + j.dx * u - j.dz * w); zs.append(j.z + j.dz * u + j.dx * w)
	var n := xs.size()
	var cols := {}
	var keys := ["ground", "landform", "trail", "berm", "line", "pathN", "jump_mask", "route_dist", "wild", "hill", "mtn",
		"deck", "b_dry", "b_rug", "b_cold", "b_wet", "b_forest", "b_sav", "b_ash"]
	for k in keys: cols[k] = PackedFloat64Array()
	var biome := PackedStringArray()
	var col := PackedFloat64Array()
	for i in n:
		var x := xs[i]
		var z := zs[i]
		cols["ground"].append(f.ground(x, z))
		cols["landform"].append(f.landform(x, z))
		cols["trail"].append(f.trail(x, z))
		cols["berm"].append(f.berm(x, z))
		cols["line"].append(f.line(x, z))
		cols["pathN"].append(f.pathN(x, z))
		cols["jump_mask"].append(f.jump_mask(x, z))
		cols["route_dist"].append(f.route_dist(x, z))
		cols["wild"].append(f.wild(x, z))
		cols["hill"].append(f.hill(x, z))
		cols["mtn"].append(f.mtn(x, z))
		cols["deck"].append(f.deck(x, z))
		f.biome(x, z)
		for b in ["b_dry", "b_rug", "b_cold", "b_wet", "b_forest", "b_sav", "b_ash"]:
			cols[b].append(float(f.get(b)))
		biome.append(f.biome_name(x, z))
		var h: float = f.ground(x, z)
		var c: Color = f.color(x, z, h, 0.95)
		col.append(c.r); col.append(c.g); col.append(c.b)
	cols["x"] = xs
	cols["z"] = zs
	cols["biome_name"] = biome
	cols["color_rgb"] = col
	return cols


# ------------------------------------------------------------------ writer
func _write(path: String, v) -> void:
	_f = FileAccess.open(path, FileAccess.WRITE)
	_objs = []
	_f.store_buffer("RWD1".to_ascii_buffer())
	_val(v)
	_f.close()


func _str(s: String) -> void:
	var b := s.to_utf8_buffer()
	_f.store_32(b.size())
	_f.store_buffer(b)


func _val(v) -> void:
	match typeof(v):
		TYPE_NIL: _f.store_8(0)
		TYPE_BOOL: _f.store_8(1); _f.store_8(1 if v else 0)
		TYPE_INT: _f.store_8(2); _f.store_64(v)
		TYPE_FLOAT: _f.store_8(3); _f.store_double(v)
		TYPE_STRING, TYPE_STRING_NAME: _f.store_8(4); _str(str(v))
		TYPE_PACKED_FLOAT64_ARRAY:
			_f.store_8(5); _f.store_32(v.size())
			for x in v: _f.store_double(x)
		TYPE_PACKED_FLOAT32_ARRAY:
			_f.store_8(6); _f.store_32(v.size())
			for x in v: _f.store_float(x)
		TYPE_PACKED_INT32_ARRAY:
			_f.store_8(7); _f.store_32(v.size())
			for x in v: _f.store_32(x)
		TYPE_PACKED_INT64_ARRAY:
			_f.store_8(8); _f.store_32(v.size())
			for x in v: _f.store_64(x)
		TYPE_COLOR:
			_f.store_8(9); _f.store_float(v.r); _f.store_float(v.g); _f.store_float(v.b); _f.store_float(v.a)
		TYPE_PACKED_COLOR_ARRAY:
			_f.store_8(14); _f.store_32(v.size())
			for c in v:
				_f.store_float(c.r); _f.store_float(c.g); _f.store_float(c.b); _f.store_float(c.a)
		TYPE_VECTOR2: _f.store_8(15); _f.store_float(v.x); _f.store_float(v.y)
		TYPE_VECTOR3: _f.store_8(16); _f.store_float(v.x); _f.store_float(v.y); _f.store_float(v.z)
		TYPE_PACKED_STRING_ARRAY:
			_f.store_8(17); _f.store_32(v.size())
			for s in v: _str(s)
		TYPE_ARRAY:
			_f.store_8(10); _f.store_32(v.size())
			for x in v: _val(x)
		TYPE_DICTIONARY:
			_f.store_8(11); _f.store_32(v.size())
			var ks: Array = v.keys()
			ks.sort_custom(func(a, b): return str(a) < str(b))
			for k in ks:
				_val(k)
				_val(v[k])
		TYPE_OBJECT:
			if v == null:
				_f.store_8(0)
				return
			var at := _objs.find(v)
			if at >= 0:
				_f.store_8(13); _f.store_32(at)
				return
			_objs.append(v)
			var sc: Script = v.get_script()
			var cname: String = sc.get_global_name() if sc else v.get_class()
			if cname == "" and sc: cname = sc.resource_path.get_file()
			_f.store_8(12)
			_str(cname)
			var d := {}
			for p in v.get_property_list():
				if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
				var nm: String = p.name
				if nm in SKIP: continue
				var x = v.get(nm)
				if typeof(x) == TYPE_OBJECT and x != null and not (x is TrailCourse or x is RouteSpine or x is TerrainField.Feat or x is TerrainField):
					continue   # rngs, helpers: not part of the data
				d[nm] = x
			_val(d)
		_:
			_f.store_8(0)
