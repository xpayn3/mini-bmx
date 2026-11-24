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
@export_group("Editor")
@export var live_preview := true:
	set(v): live_preview = v; _queue()

var field: LevelField          # the last preview bake (editor)
var _wait := -1.0
var _ground: MeshInstance3D
var _far: MeshInstance3D
var _line: MeshInstance3D


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
	f.rough = rough; f.rough_scale = rough_scale; f.noise_seed = noise_seed
	var t := trail()
	if t: t.fill(f)
	return f


func _queue() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	_wait = 0.35   # (rebuild once the slider / handle stops moving)


func _process(dt: float) -> void:
	if _wait < 0.0: return
	_wait -= dt
	if _wait < 0.0: rebuild_preview()


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
		m.set_shader_parameter("line_5m", 0.2)
		_ground.material_override = m
		_far.material_override = m
	_ground.mesh = field.ground_mesh(1)
	_far.mesh = field.far_mesh(700.0, 16.0)
	_line.mesh = _trail_lines()
	var s := field.summary() + " · preview %d ms" % (Time.get_ticks_msec() - t0)
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
