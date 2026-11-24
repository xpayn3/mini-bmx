@tool
class_name BmxGate
extends BmxPiece
## A race gate across the trail: the start (riders start here, facing down the trail), checkpoints, the finish.
## (Timing comes with publishing; for now it is the start spot and a marker.)

@export_enum("start", "checkpoint", "finish") var gate := "checkpoint"
@export_range(3.0, 16.0, 0.5, "suffix:m") var span := 7.0


func piece() -> Dictionary:
	var p := _base("gate")
	p.merge({"gate": gate, "span": span})
	return p
