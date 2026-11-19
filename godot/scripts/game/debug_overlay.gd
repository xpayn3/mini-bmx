class_name DebugOverlay
extends RefCounted
## F3 (or BMX_DEBUG_DRAW=1): the bike's live physics drawn in the world with the Debug Draw 3D addon
## (addons/debug_draw_3d, MIT, DmitriySalnikov). Development only: the release export loads the addon's
## no-op library, and without the addon this does nothing (looked up by name, so nothing fails to parse).
##   cyan arrow    travel direction (course), length = speed
##   white arrow   where the bike points (heading); the angle between them is the slide (slip)
##   orange arrow  where the front wheel points (heading + bars + drawn countersteer)
##   yellow arrow  turning force (lateral acceleration), towards the inside of the turn
##   bar at rear   rear tyre's sideways grip (green full .. red gone); square under it = loose ground
##   magenta path  in the air: the flight path to the landing (sphere = touch-down)

static var on := OS.get_environment("BMX_DEBUG_DRAW") != ""

static func toggle() -> bool:
	on = not on
	var d2 = _dd("DebugDraw2D")
	if not on and d2 != null: d2.clear_all()
	return on

static func available() -> bool:
	return _dd("DebugDraw3D") != null

static func _dd(n: String):
	return Engine.get_singleton(n) if Engine.has_singleton(n) else null

static func _fwd(h: float) -> Vector3:
	return Vector3(cos(h), 0.0, -sin(h))

static func draw(game, st, pos: Vector3, hd: float) -> void:
	if not on: return
	var d3 = _dd("DebugDraw3D")
	var d2 = _dd("DebugDraw2D")
	if d3 == null: return
	var cfg = d3.new_scoped_config()
	cfg.set_thickness(0.025)
	var p := pos + Vector3.UP * 0.08
	var fh := _fwd(hd)
	var fc := _fwd(st.course)
	var left := Vector3(-sin(st.course), 0.0, -cos(st.course))
	var va := absf(st.v)
	# travel vs heading
	if va > 0.3:
		d3.draw_arrow(p, p + fc * clampf(va * 0.18, 0.4, 4.0), Color(0.2, 0.9, 1.0), 0.15, true)
	d3.draw_arrow(p, p + fh * 1.6, Color.WHITE, 0.12, true)
	# front wheel aim
	var front: Vector3 = p + fh * (st.L - st.BB_REAR)
	d3.draw_arrow(front, front + _fwd(hd + st.steer + st.bar_catch) * 0.7, Color(1.0, 0.55, 0.1), 0.1, true)
	# turning force
	if not st.air and absf(st.lat_a) > 0.3:
		d3.draw_arrow(p + Vector3.UP * 0.4, p + Vector3.UP * 0.4 + left * st.lat_a * 0.12, Color(1.0, 0.9, 0.2), 0.12, true)
	# rear tyre grip + loose ground
	var rear: Vector3 = p - fh * st.BB_REAR
	var g := clampf(st.grip_r, 0.0, 1.2)
	var gc := Color(1.0, 0.15, 0.1).lerp(Color(0.2, 1.0, 0.3), clampf(g, 0.0, 1.0))
	d3.draw_line(rear, rear + Vector3.UP * (0.05 + g * 1.1), gc)
	if st.loose > 0.05:
		d3.draw_square(rear, 0.2 + st.loose * 0.5, Color(0.85, 0.6, 0.3, 0.6))
	# flight path to the landing
	if st.air:
		var pts := PackedVector3Array()
		var q := Vector3(st.x, st.y, st.z)
		var vel: Vector3 = fc * st.v + Vector3.UP * st.vy
		var land := Vector3.INF
		for i in 90:
			pts.append(q)
			vel.y -= 9.81 * 0.025
			q += vel * 0.025
			if q.y <= game.terrain.height(q.x, q.z):
				land = q; pts.append(q); break
		d3.draw_line_path(pts, Color(1.0, 0.3, 0.9))
		if land != Vector3.INF:
			d3.draw_sphere(land, 0.25, Color(1.0, 0.3, 0.9))
	if d2 != null:
		d2.config.text_block_offset = Vector2i(12, 140)   # top left, under the HUD jump card
		d2.set_text("DEBUG DRAW (F3)", "", 0, Color.WHITE)
		d2.set_text("speed", "%.1f km/h" % (st.v * 3.6), 1)
		d2.set_text("slide (slip)", "%.1f°  rate %.2f rad/s" % [rad_to_deg(st.slip), st.slip_w], 2)
		d2.set_text("rear grip", "%.0f %%  loose %.2f" % [st.grip_r * 100.0, st.loose], 3)
		d2.set_text("tyre squirm", "%.1f°" % rad_to_deg(st._squirm), 4)
		d2.set_text("bars / catch", "%.1f° / %.1f°" % [rad_to_deg(st.steer), rad_to_deg(st.bar_catch)], 5)
		d2.set_text("turn force", "%.1f m/s²" % st.lat_a, 6)
		d2.set_text("lean", "%.0f°" % rad_to_deg(st.bike_lean), 7)
		d2.set_text("air", "%s  vy %.1f" % [str(st.air), st.vy], 8)
