@tool
class_name BmxRocks
extends BmxPiece
## A rock garden along the trail from this point (the world's own rock meshes + colliders, ridden over as domes).
## clean_line leaves a weaving line through it mostly clear (like the trail's gardens).

@export_range(4.0, 120.0, 1.0, "suffix:m") var length := 24.0
@export_range(0.0, 3.0, 0.05) var density := 1.0           ## 1 = the trail's (4 rocks per 2 m)
@export_range(0.05, 0.6, 0.01, "suffix:m") var size_min := 0.13
@export_range(0.05, 0.8, 0.01, "suffix:m") var size_max := 0.47
@export_range(0.0, 2.0, 0.05, "suffix:m") var spread := 0.0   ## past the trail's edges (0 = only on the trail)
@export var clean_line := true
@export var rock_seed := 1


func piece() -> Dictionary:
	var p := _base("rocks")
	p.merge({"length": length, "density": density, "size_min": size_min, "size_max": size_max, "spread": spread,
		"clean": clean_line, "seed": rock_seed})
	return p
