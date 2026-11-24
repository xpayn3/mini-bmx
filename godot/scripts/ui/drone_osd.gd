class_name DroneOSD
extends Control
## The Drone view's on-screen display, like a camera drone's live feed: frame corners, a blinking REC
## with the clip time, centre mark, a roll ladder that follows the airframe's bank, and flight readouts
## (height over the ground, distance to the rider, speed, battery, satellites). Drawn by CameraRig.

var rig: CameraRig
var rec_t := 0.0
var batt := 0.97

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(dt: float) -> void:
	if not visible:
		rec_t = 0.0
		return
	rec_t += dt
	batt = maxf(0.08, batt - dt / 1500.0)
	queue_redraw()

func _txt(p: Vector2, s: String, size := 15, col := Color(1, 1, 1, 0.9), align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, p + Vector2(1, 1), s, align, w, size, Color(0, 0, 0, 0.5))
	draw_string(f, p, s, align, w, size, col)

func _draw() -> void:
	if rig == null or rig.game == null:
		return
	var sz := size
	var white := Color(1, 1, 1, 0.85)
	var m := 36.0
	var top := 84.0    # under the HUD's info lines
	var L := 34.0
	# frame corners
	for c in [Vector2(m, top), Vector2(sz.x - m, top), Vector2(m, sz.y - m), Vector2(sz.x - m, sz.y - m)]:
		var sx := 1.0 if c.x < sz.x * 0.5 else -1.0
		var sy := 1.0 if c.y < sz.y * 0.5 else -1.0
		draw_line(c, c + Vector2(L * sx, 0), white, 2.0)
		draw_line(c, c + Vector2(0, L * sy), white, 2.0)
	# centre mark
	var ctr := sz * 0.5
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_line(ctr + d * 6.0, ctr + d * 16.0, Color(1, 1, 1, 0.7), 1.5)
	# roll ladder: a short horizon bar tilted by the airframe's bank
	var roll := rig.dr_roll * 0.55
	var hv := Vector2(cos(roll), sin(roll))
	draw_line(ctr - hv * 70.0, ctr - hv * 30.0, Color(1, 1, 1, 0.55), 1.5)
	draw_line(ctr + hv * 30.0, ctr + hv * 70.0, Color(1, 1, 1, 0.55), 1.5)
	# REC + clip time
	if fmod(rec_t, 1.0) < 0.6:
		draw_circle(Vector2(m + 18, top + 22), 6.0, Color(1, 0.16, 0.12))
	var secs := int(rec_t)
	_txt(Vector2(m + 30, top + 28), "REC  %02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60], 16)
	_txt(Vector2(sz.x - m - 260, top + 28), "4K 60  ·  ISO 100  ·  1/240", 14, white, HORIZONTAL_ALIGNMENT_RIGHT, 220)
	# flight readouts
	var cam_p := rig.global_position
	var g: float = rig.game.terrain.height(cam_p.x, cam_p.z) if rig.game.terrain else cam_p.y
	var rider_p: Vector3 = rig.game.drawn_pos
	var hs := Vector2(rig.dr_vel.x, rig.dr_vel.z).length() * 3.6
	var y := sz.y - m - 14
	_txt(Vector2(200, y), "H %5.1f m   D %5.1f m   H.S %4.0f km/h   V.S %+4.1f m/s" % [cam_p.y - g, cam_p.distance_to(rider_p), hs, rig.dr_vel.y], 15)
	var bc := Color(1, 1, 1, 0.9) if batt > 0.25 else Color(1, 0.35, 0.25)
	_txt(Vector2(sz.x - m - 264, y), "GPS 18   | %d%%" % int(batt * 100.0), 15, bc, HORIZONTAL_ALIGNMENT_RIGHT, 260)
