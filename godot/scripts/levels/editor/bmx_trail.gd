@tool
class_name BmxTrail
extends Path3D
## The trail down a BmxLevel: draw it with the Path3D curve tools (add / move points, handles for smooth bends).
## Only the plan (x, z) is used: the trail's height comes from the land under it, smoothed along it. Its bends get
## banked to the speed a rider carries into them (LevelField). Ridden from its first point to its last.

@export_range(1.5, 10.0, 0.1, "suffix:m") var trail_width := 3.6:
	set(v): trail_width = v; _changed()
@export_range(1.0, 20.0, 0.5, "suffix:m") var blend := 6.0:
	set(v): blend = v; _changed()
@export_range(0.0, 1.5, 0.05) var berms := 1.0:
	set(v): berms = v; _changed()
@export_range(0.0, 50.0, 1.0, "suffix:°") var bank_max_deg := 35.0:
	set(v): bank_max_deg = v; _changed()
@export_range(5.0, 60.0, 1.0, "suffix:m") var smooth_len := 14.0:
	set(v): smooth_len = v; _changed()
@export_range(0.0, 1.0, 0.05) var follow := 0.0:
	set(v): follow = v; _changed()
@export_range(0.0, 15.0, 0.5, "suffix:m/s") var start_speed := 3.0:
	set(v): start_speed = v; _changed()


func _ready() -> void:
	if Engine.is_editor_hint() and not curve_changed.is_connected(_changed):
		curve_changed.connect(_changed)


func _changed() -> void:
	var p := get_parent()
	if p is BmxLevel: p._queue()


## hands the trail's plan + settings to a LevelField
func fill(f: LevelField) -> void:
	f.trail_width = trail_width; f.blend = blend; f.berms = berms; f.bank_max_deg = bank_max_deg
	f.smooth_len = smooth_len; f.follow = follow; f.start_speed = start_speed
	var pts := PackedVector2Array()
	if curve and curve.point_count >= 2:
		for p in curve.tessellate_even_length(6, 0.5):
			var w := transform * p
			pts.append(Vector2(w.x, w.z))
	f.trail_in = pts
