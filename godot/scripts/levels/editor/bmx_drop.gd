@tool
class_name BmxDrop
extends BmxPiece
## A drop: the trail climbs gently onto a built deck, then falls `height` m. The edge can be a square step
## (`edge` m straight down); the landing face below follows the flight of a rider at the design speed (faster
## riders land further down it), straight at most `face_deg`, into a bottom transition sized to the speed.
## The node marks where the climb starts.

@export_range(0.3, 8.0, 0.1, "suffix:m") var height := 1.5
@export_range(0.0, 3.0, 0.05, "suffix:m") var edge := 0.4           ## square step at the edge (0 = a roll-off)
@export_range(0.02, 0.4, 0.01) var climb := 0.12                    ## the approach's rise per metre (over the ground's grade)
@export_range(0.0, 20.0, 0.5, "suffix:m") var deck_len := 3.0       ## flat top before the edge
@export_range(15.0, 50.0, 1.0, "suffix:°") var face_deg := 32.0
@export var auto_speed := true
@export_range(0.5, 1.5, 0.01) var speed_scale := 1.0
@export_range(10.0, 90.0, 1.0, "suffix:km/h") var design_kmh := 36.0
@export_range(1.0, 8.0, 0.25, "suffix:m") var width := 3.4
@export_enum("dirt", "wood") var build := "dirt"


func piece() -> Dictionary:
	var p := _base("drop")
	p.merge({"height": height, "edge": edge, "climb": climb, "deck": deck_len, "face_deg": face_deg, "auto_v": auto_speed,
		"v_k": speed_scale, "v": design_kmh / 3.6, "width": width, "build": build})
	return p
