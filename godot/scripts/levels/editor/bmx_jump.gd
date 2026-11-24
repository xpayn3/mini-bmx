@tool
class_name BmxJump
extends BmxPiece
## A built jump from the formula (JumpDesign: the same recipe as the trail's jumps and the playground's ramp
## editor), every control of it here. The node marks the LIP. It sits on the ground's grade there (the ground under
## it is levelled to that grade); auto speed designs it for the speed riders carry at that spot of the trail.
## The editor draws where riders at 85 / 100 / 115 % of the design speed fly and land (on the real ground).

@export_enum("table", "gap", "kicker") var kind := "table"
@export_enum("dirt", "wood") var build := "dirt"
@export_group("Speed")
@export var auto_speed := true                       ## design speed = the speed riders carry here (x speed_scale)
@export_range(0.5, 1.5, 0.01) var speed_scale := 1.0
@export_range(10.0, 90.0, 1.0, "suffix:km/h") var design_kmh := 43.0   ## used when auto speed is off
@export_group("Take-off")
@export_range(8.0, 50.0, 1.0, "suffix:°") var lip_deg := 26.0         ## take-off angle (the straight lip's)
@export_range(0.6, 3.5, 0.05, "suffix:g") var lip_g := 1.5            ## most g the curve puts on the rider (sets its radius)
@export_range(0.0, 0.5, 0.01, "suffix:s") var lip_t := 0.25           ## straight lip, seconds at the lip speed
@export_range(0.0, 6.0, 0.05, "suffix:m") var height := 0.0           ## 0 = what the curve + lip give; else this lip height
@export_group("Deck / gap")
@export_range(0.0, 30.0, 0.25, "suffix:m") var deck := 0.0            ## table: lip to knuckle; 0 = auto (as long as the flight)
@export_range(0.0, 30.0, 0.25, "suffix:m") var gap := 0.0             ## gap: lip to landing knuckle; 0 = auto
@export_range(0.0, 6.0, 0.05, "suffix:m") var land_h := 0.0           ## gap: landing knuckle height (0 = the lip's)
@export_range(0.0, 6.0, 0.05, "suffix:m") var fill := 0.0             ## gap: the gap's floor over the ground
@export_group("Landing")
@export_range(0.0, 50.0, 1.0, "suffix:°") var land_deg := 0.0         ## 0 = auto: matched to the flight
@export_range(0.0, 1.0, 0.05) var aim := 0.2                          ## where the design speed comes down (0 knuckle .. 1 bottom)
@export_range(1.0, 5.0, 0.1, "suffix:g") var land_g := 2.5            ## most g in the landing's bottom transition
@export_range(0.3, 6.0, 0.1, "suffix:m") var knuckle_r := 2.5         ## how round the deck's edge is
@export_group("Size")
@export_range(1.0, 8.0, 0.25, "suffix:m") var width := 3.0


func piece() -> Dictionary:
	var p := _base("jump")
	p["auto_v"] = auto_speed; p["v_k"] = speed_scale
	p["prm"] = {"kind": kind, "build": build, "v": design_kmh / 3.6, "lip_deg": lip_deg, "lip_g": lip_g, "lip_t": lip_t,
		"height": height, "deck": deck, "gap": gap, "land_h": land_h, "fill": fill, "land_deg": land_deg, "land_g": land_g,
		"knuckle_r": knuckle_r, "aim": aim, "width": width}
	return p
