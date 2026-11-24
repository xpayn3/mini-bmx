@tool
class_name BmxLevel
extends Node3D
## The root of a built level (the level builder plugin, addons/level_builder; levels live in res://levels/*.tscn).
## Its own settings shape the slope; a BmxTrail child is the line down it. In the editor it draws the ground as
## the ride will have it (LevelField, a 1 m preview), the trail coloured by the speed a rider carries (blue slow ..
## red fast) and the start. The game loads the scene and asks make_field() for the ground (LevelTerrain).

signal rebuilt(summary: String)

@export var title := "New level":
	set(v): title = v
@export_group("Slope")
@export_range(100.0, 2000.0, 10.0, "suffix:m") var length := 420.0:
	set(v): length = v; _queue()
@export_range(60.0, 600.0, 10.0, "suffix:m") var width := 180.0:
	set(v): width = v; _queue()
@export_range(0.0, 400.0, 1.0, "suffix:m") var drop := 70.0:
	set(v): drop = v; _queue()
@export var flat_ground := false:   ## a flat spot (a park, a jump line): no slope, no valley; bumps only if rough > 0
	set(v): flat_ground = v; _queue()
@export_range(-1.0, 1.0, 0.05) var steep_top := 0.3:
	set(v): steep_top = v; _queue()
@export_range(0.0, 80.0, 0.5, "suffix:m") var side_rise := 18.0:
	set(v): side_rise = v; _queue()
@export_group("Bumps")
@export_range(0.0, 15.0, 0.1, "suffix:m") var rough := 3.0:
	set(v): rough = v; _queue()
@export_range(5.0, 200.0, 1.0, "suffix:m") var rough_scale := 45.0:
	set(v): rough_scale = v; _queue()
@export var noise_seed := 1:
	set(v): noise_seed = v; _queue()
@export_group("Light")
@export_range(5.0, 20.0, 0.25, "suffix:h") var hour := 16.5:   ## the level's time of day (its light is baked for it)
	set(v): hour = v; _queue()
@export_range(-180.0, 180.0, 1.0, "suffix:°") var sun_turn := 0.0:   ## turn the sun round the level
	set(v): sun_turn = v; _queue()
@export_group("Nature")
@export_range(0.0, 3.0, 0.05) var trees := 1.0:   ## tree density (0 none .. a forest)
	set(v): trees = v; _queue()
@export_range(0.0, 30.0, 0.5, "suffix:m") var tree_clear := 4.0:   ## kept clear either side of the trail's edge
	set(v): tree_clear = v; _queue()
@export var tree_seed := 1:
	set(v): tree_seed = v; _queue()
@export_group("Layers")
@export var layers: LevelLayers   ## imported land, sculpting, surface paint (levels/<name>_layers.res)
@export_group("Editor")
@export var live_preview := true:
	set(v): live_preview = v; _queue()

var field: LevelField          # the last preview bake (editor)
var _wait := -1.0
var _ground: MeshInstance3D
var _far: MeshInstance3D
var _line: MeshInstance3D
var _pieces_root: Node3D
var _grid_mat: ShaderMaterial
var _marks: Array = []          # LevelBake.marks of the last preview


## the editor's snap grid drawn on the preview ground (fine lines every `cell` m, bold every 5)
func show_grid(cell: float) -> void:
	if _grid_mat: _grid_mat.set_shader_parameter("grid_cell", maxf(0.05, cell))


## the ground (and structures) under a ray from the editor camera: level space point, or null
func ray_ground(from: Vector3, dir: Vector3):
	if field == null: return null
	var inv := global_transform.affine_inverse()
	var o := inv * from
	var d := (inv.basis * dir).normalized()
	var t := 0.0
	var step := 0.5
	var prev_above := true
	while t < 2500.0:
		var p := o + d * t
		var g := field.height(p.x, p.z)
		if p.y <= g:
			if not prev_above: return null
			var lo := t - step; var hi := t   # refine
			for k in 12:
				var m := (lo + hi) * 0.5
				var q := o + d * m
				if q.y <= field.height(q.x, q.z): hi = m
				else: lo = m
			var r := o + d * hi
			return Vector3(r.x, field.height(r.x, r.z), r.z)
		t += step
		step = minf(4.0, step * 1.04)
	return null


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_queue()
	else:
		set_process(false)


func trail() -> BmxTrail:
	for c in get_children():
		if c is BmxTrail: return c
	return null


## a field set up from this level's settings + its trail (not baked)
func make_field() -> LevelField:
	var f := LevelField.new()
	f.length = length; f.width = width; f.drop = drop; f.steep_top = steep_top; f.side_rise = side_rise
	f.rough = rough; f.rough_scale = rough_scale; f.noise_seed = noise_seed; f.flat = flat_ground
	f.trees = trees; f.tree_clear = tree_clear; f.tree_seed = tree_seed
	if layers: f.layers = layers.data()
	var t := trail()
	if t: t.fill(f)
	f.alts_in = []
	for c in get_children():   # (every BmxTrail after the first: an alternative line)
		if c is BmxTrail and c != t:
			var g := LevelField.new()
			c.fill(g)
			f.alts_in.append({"pts": g.trail_in})
	f.pieces = []
	for pc in pieces(): f.pieces.append(pc.piece())
	return f


## every BmxPiece under the level (any depth: folders are fine)
func pieces() -> Array:
	var out := []
	var stack: Array = get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BmxPiece: out.append(n)
		if not (n is BmxPiece): stack.append_array(n.get_children())
	return out


func _queue() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	_wait = 0.35   # (rebuild once the slider / handle stops moving)


var _poll := 0.0
var _sig := 0
func _process(dt: float) -> void:
	# any change (inspector, gizmos, undo / redo) shows in the inputs: rebuild when they change
	_poll -= dt
	if _poll <= 0.0 and _wait < 0.0:
		_poll = 0.3
		var sg := _signature()
		if sg != _sig: _sig = sg; _wait = 0.25
	if _wait < 0.0: return
	_wait -= dt
	if _wait < 0.0: rebuild_preview()


func _signature() -> int:
	var f := make_field()
	return hash(str([f.alts_in, layers.content_hash() if layers else 0, f.trees, f.tree_clear, f.tree_seed, f.flat, f.length, f.width, f.drop, f.steep_top, f.side_rise, f.rough, f.rough_scale, f.noise_seed, f.trail_in,
		f.trail_width, f.blend, f.berms, f.bank_max_deg, f.smooth_len, f.follow, f.start_speed, f.pieces]))


func rebuild_preview() -> void:
	if not live_preview: return
	var t0 := Time.get_ticks_msec()
	field = make_field()
	field.bake(1.0)
	if _ground == null:
		_ground = _internal("Preview ground")
		_far = _internal("Preview far land")
		_line = _internal("Preview trail")
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/playground_ground.gdshader")
		m.set_shader_parameter("contour", 0.0)
		m.set_shader_parameter("line_1m", 0.08)
		_grid_mat = m
		m.set_shader_parameter("line_5m", 0.2)
		_ground.material_override = m
		_far.material_override = m
	_ground.mesh = field.ground_mesh(1)
	_far.mesh = field.far_mesh(700.0, 16.0)
	_line.mesh = _trail_lines()
	# the pieces: snapped onto the trail where they follow it, then drawn
	for pc in pieces():
		var p: Dictionary = pc.piece()
		if pc.follow_trail and field.TX.size() > 1:
			var pl: Array = field._place({"pos": p.pos, "dir": p.dir, "follow": true})   # (the nearest line, alt lines too: as the bake places it)
			pc.place_at(pl[0], pl[1], field.grid_height(pl[0].x, pl[0].y))
		else:   # (placed freely: kept where it is, standing on the ground)
			pc.place_at(p.pos, p.dir, field.grid_height(p.pos.x, p.pos.y))
	if _pieces_root: _pieces_root.queue_free()
	_pieces_root = Node3D.new()
	_pieces_root.name = "Preview pieces"
	add_child(_pieces_root, false, Node.INTERNAL_MODE_BACK)
	LevelVisuals.build(field, _pieces_root, false)
	_marks = LevelBake.marks(field)
	for m in _marks:   # every problem a rider will meet: a post + its words where it is (red = fix it, yellow = a note)
		var col := Color(1.0, 0.2, 0.15) if m.warn else Color(1.0, 0.8, 0.15)
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.25, 5.0, 0.25)
		var pm := StandardMaterial3D.new(); pm.albedo_color = col; pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = pm
		post.mesh = bm
		post.position = m.pos + Vector3(0, 2.5, 0)
		_pieces_root.add_child(post)
		var lb := Label3D.new()
		lb.text = str(m.msg)
		lb.modulate = col
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.font_size = 40; lb.pixel_size = 0.01; lb.outline_size = 10
		lb.width = 900.0; lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.position = m.pos + Vector3(0, 5.8, 0)
		_pieces_root.add_child(lb)
	_sig = _signature()
	var s := field.summary() + " · preview %d ms" % (Time.get_ticks_msec() - t0)
	var jr := field.jump_report()
	if jr != "": s += "

" + jr
	rebuilt.emit(s)


func _internal(nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	add_child(mi, false, Node.INTERNAL_MODE_BACK)   # (internal + no owner: never saved into the scene)
	return mi


## the trail's centre a little above the ground, coloured by speed, ticks across it every 10 m showing the bank,
## and a post at the start
func _trail_lines() -> ImmediateMesh:
	var im := ImmediateMesh.new()
	var f := field
	if f.TX.size() < 2: return im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = false
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var vmax := 0.1
	for v in f.TV: vmax = maxf(vmax, v)
	for i in f.TX.size() - 1:
		for k in 2:
			var j := i + k
			var c := Color(0.2, 0.5, 1.0).lerp(Color(1.0, 0.25, 0.15), f.TV[j] / vmax)
			im.surface_set_color(c)
			im.surface_add_vertex(Vector3(f.TX[j], f.TY[j] + 0.35, f.TZ[j]))
	for alt in f.ALT:   # the other lines, coloured the same way
		for i in (alt.TX as PackedFloat32Array).size() - 1:
			for k in 2:
				var j := i + k
				im.surface_set_color(Color(0.2, 0.5, 1.0).lerp(Color(1.0, 0.25, 0.15), alt.TV[j] / vmax))
				im.surface_add_vertex(Vector3(alt.TX[j], alt.TY[j] + 0.35, alt.TZ[j]))
	var hw := f.trail_width * 0.5
	for i in range(0, f.TX.size(), 10):
		var l := LevelField._left(f.DX[i], f.DZ[i])
		var b := absf(f.TB[i])
		var c := Color(1, 1, 1).lerp(Color(1.0, 0.85, 0.1), clampf(b / 0.6, 0.0, 1.0))
		im.surface_set_color(c)
		for s: float in [-hw - 1.0, hw + 1.0]:
			var x := f.TX[i] + l.x * s; var z := f.TZ[i] + l.y * s
			im.surface_add_vertex(Vector3(x, f.height(x, z) + 0.25, z))
	var sp := Vector3(f.TX[0], f.TY[0], f.TZ[0])
	im.surface_set_color(Color(0.2, 1.0, 0.3))
	im.surface_add_vertex(sp); im.surface_add_vertex(sp + Vector3(0, 4, 0))
	var e := f.TX.size() - 1
	var ep := Vector3(f.TX[e], f.TY[e], f.TZ[e])
	im.surface_set_color(Color(1.0, 1.0, 1.0))
	im.surface_add_vertex(ep); im.surface_add_vertex(ep + Vector3(0, 4, 0))
	# every jump's flights at 85 / 100 / 115 % of its design speed (blue / green / red), a post where each lands
	var fc := [Color(0.3, 0.6, 1.0), Color(0.2, 1.0, 0.3), Color(1.0, 0.3, 0.25)]
	for st in f.structs:
		if not st.has("flights"): continue
		for k in 3:
			var pts: PackedVector3Array = st.flights[k].pts
			im.surface_set_color(fc[k])
			for q in range(1, pts.size(), 2):
				im.surface_add_vertex(pts[q - 1]); im.surface_add_vertex(pts[q])
			if pts.size() > 0:
				im.surface_add_vertex(pts[pts.size() - 1]); im.surface_add_vertex(pts[pts.size() - 1] + Vector3(0, 1.2, 0))
	im.surface_end()
	return im


## editor: put every trail point on the ground (so the curve handles sit where the trail is)
func snap_trail_to_ground() -> void:
	var t := trail()
	if t == null or t.curve == null: return
	var f := make_field()
	f.bake(2.0)   # (no trail cut needed: just the land)
	for i in t.curve.point_count:
		var p := t.transform * t.curve.get_point_position(i)
		var y := f.base(p.x, p.z) + 0.3
		var lp := t.transform.affine_inverse() * Vector3(p.x, y, p.z)
		t.curve.set_point_position(i, lp)


## a new level: the default slope with a winding trail down it (sweepers, a hairpin pair, esses)
static func make_new(title_in := "New level") -> BmxLevel:
	var lvl := BmxLevel.new()
	lvl.name = "Level"
	lvl.title = title_in
	var t := BmxTrail.new()
	t.name = "Trail"
	var c := Curve3D.new()
	var P := [Vector2(8, 0), Vector2(55, -18), Vector2(100, 15), Vector2(135, 40), Vector2(152, 12), Vector2(162, -28),
		Vector2(195, -44), Vector2(235, -12), Vector2(262, 24), Vector2(302, 30), Vector2(340, -4), Vector2(380, -20), Vector2(412, 0)]
	for i in P.size():
		var a: Vector2 = P[maxi(0, i - 1)]; var b: Vector2 = P[mini(P.size() - 1, i + 1)]
		var h := (b - a) / 6.0   # (Catmull-Rom through the points)
		var p: Vector2 = P[i]
		c.add_point(Vector3(p.x, 0, p.y), Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, h.y))
	t.curve = c
	lvl.add_child(t)
	t.owner = lvl
	lvl.snap_trail_to_ground()
	return lvl


## the layers resource (made + saved as levels/<scene>_layers.res the first time), its sculpt / paint grid fitted to the
## level's ground (1 m, x -40 .. length + 40, z -(width / 2 + 10) .. +)
func ensure_layers() -> LevelLayers:
	if layers == null:
		layers = LevelLayers.new()
		if scene_file_path != "":   # (an unsaved level keeps its layers inside the scene until it is saved somewhere)
			var path := scene_file_path.get_basename() + "_layers.res"
			ResourceSaver.save(layers, path)
			layers.take_over_path(path)
	layers.fit(-40.0, -width * 0.5 - 10.0, int(length + 81.0), int(width + 21.0))
	return layers


## a world stretch from tools/import_world.gd: the level takes its size, the land under it and its trail
func apply_import(d: Dictionary) -> void:
	length = float(d.length); width = float(d.width); flat_ground = false
	var L := ensure_layers()
	L.import_h = d.H; L.import_x0 = float(d.x0); L.import_z0 = float(d.z0); L.import_nx = int(d.nx); L.import_nz = int(d.nz)
	var t := trail()
	if t:
		var c := Curve3D.new()
		var P: PackedVector2Array = d.pts
		for i in P.size():
			var a: Vector2 = P[maxi(0, i - 1)]; var b: Vector2 = P[mini(P.size() - 1, i + 1)]
			var h := (b - a) / 6.0
			c.add_point(Vector3(P[i].x, 0, P[i].y), Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, h.y))
		t.transform = Transform3D()
		t.curve = c
	snap_trail_to_ground()
