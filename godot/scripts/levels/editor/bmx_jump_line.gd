@tool
class_name BmxJumpLine
extends BmxJump
## A jump line: `count` jumps down the trail from here, in rhythm: each sized for the speed riders carry at its spot
## (auto speed), the next lip one roll-out after the last one's landing (`rollout` s at the speed there, 6 .. 14 m,
## as the world's jump lines). Every jump control of BmxJump applies to all of them. Needs a trail.

@export_range(2, 8, 1) var count := 3
@export_range(0.4, 1.5, 0.05, "suffix:s") var rollout := 0.75


func piece() -> Dictionary:
	var p := super.piece()
	p.kind = "line"
	p["count"] = count
	p["rollout"] = rollout
	return p
