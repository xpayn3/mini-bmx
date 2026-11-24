@tool
class_name BmxPiece
extends Node3D
## A piece put down on a BmxLevel (a child of it): a jump, a drop, a rock garden, a gate. Its position is where
## it sits (a jump: its lip; the others: their start); its +X axis is the way it is ridden. With follow_trail the
## level snaps it onto the nearest point of the trail, facing down it (the node is moved there in the editor).
## piece() hands its numbers to the LevelField as a plain dictionary (the editor preview and the ride use the same).

@export var follow_trail := true
## jumps / drops: a ramp on the ground as it is (its own object: the ground under it isn't levelled or blended)
@export var standalone := false


## this piece's numbers for LevelField (override; call _base() for the placement)
func piece() -> Dictionary:
	return _base("none")


func _base(kind: String) -> Dictionary:
	var t := level_transform()
	var f := Vector2(t.basis.x.x, t.basis.x.z)
	if f.length() < 1e-4: f = Vector2(1, 0)
	return {"kind": kind, "name": String(name), "pos": Vector2(t.origin.x, t.origin.z), "dir": f.normalized(), "follow": follow_trail,
		"standalone": standalone}


## the transform in the level's space (pieces may sit under plain Node3D folders)
func level_transform() -> Transform3D:
	var t := transform
	var p := get_parent()
	while p != null and not (p is BmxLevel):
		if p is Node3D: t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func level() -> BmxLevel:
	var p := get_parent()
	while p != null and not (p is BmxLevel): p = p.get_parent()
	return p as BmxLevel


## the editor: put it where the level placed it (on the trail), keeping its height on the ground
func place_at(pos: Vector2, dir: Vector2, y: float) -> void:
	var lt := level_transform()
	var want := Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(pos.x, y, pos.y))
	if lt.origin.distance_to(want.origin) < 0.02 and lt.basis.x.dot(want.basis.x) > 0.9999: return
	var parent_lt := lt * transform.affine_inverse()   # (level space of the parent)
	transform = parent_lt.affine_inverse() * want
