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

##   (test playground also) RGB axes  the drawn bike's frame (red forward, green up, blue right)
##   pink ball     the rider's body mass on its leg spring (over the bike)
##   yellow path   where the bike really went (the last ~5 s): compare with the magenta prediction
##   white arrows  at each tyre: the force the ground pushes back with (1 m = the whole weight)
##   rings         each tyre's grip in use, lying on the ground: the dot = (along, across) / what it can hold;
##                 green inside, red past the ring (sliding). Front: brake + turn; rear: drive / brake + slide
##   white ghost   a replayed recording (lab, J): its bike + the path ahead of it
##   orange post   the lip of the jump ahead; green line = its landing, green ball = the sweet spot (35 % down it,
##                 what the test rider's AUTO speed aims for)

static var on := OS.get_environment("BMX_DEBUG_DRAW") != ""
static var text_on := true      # the text block (the playground's graphs show all of it: off there)
static var _trail := PackedVector3Array()

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
	if game.level_probe != null:
		_playground(game, st, d3)
	if d2 != null and text_on:
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


## the test playground's extras (see the list at the top)
static func _playground(game, st, d3) -> void:
	var rig = game.rig
	if rig != null:
		var b: Basis = rig.global_transform.basis
		var o: Vector3 = rig.global_position + Vector3.UP * 0.35
		d3.draw_arrow(o, o + b.x.normalized() * 0.9, Color(1, 0.25, 0.2), 0.08, true)
		d3.draw_arrow(o, o + b.y.normalized() * 0.9, Color(0.3, 1, 0.3), 0.08, true)
		d3.draw_arrow(o, o + b.z.normalized() * 0.6, Color(0.3, 0.5, 1), 0.08, true)
	if is_finite(st.body_y):
		d3.draw_sphere(Vector3(st.x, st.body_y + 1.0, st.z), 0.09, Color(1, 0.4, 0.85))
	if rig != null and rig.wheel_f != null and rig.wheel_r != null:
		_tyres(st, rig, d3)
	if game.lab != null:
		game.lab.draw_ghost(d3)
	# the path flown
	var p := Vector3(st.x, st.y + 0.05, st.z)
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(p) > 0.15:
		if not _trail.is_empty() and _trail[_trail.size() - 1].distance_to(p) > 4.0: _trail.clear()   # (put back)
		_trail.append(p)
		if _trail.size() > 400: _trail = _trail.slice(_trail.size() - 400)
	if _trail.size() >= 2: d3.draw_line_path(_trail, Color(1, 0.9, 0.2))
	# the jump ahead: lip, landing, sweet spot
	var pr = game.level_probe
	var f = pr._next_feature(st.x, st.z)
	if f == null: f = pr.course.feature_at(st.x, st.z)
	if f == null or f.has("bowl"): return
	var c: PlaygroundCourse = pr.course
	if float(f.lip) >= 0.0:
		var lp: Vector3 = c.feat_point(f, f.lip)
		d3.draw_line(lp, lp + Vector3.UP * 1.2, Color(1, 0.55, 0.1))
	if float(f.get("land0", -1.0)) >= 0.0:
		var pts := PackedVector3Array()
		var u := float(f.land0)
		while u <= float(f.land1):
			pts.append(c.feat_point(f, u) + Vector3.UP * 0.04); u += 0.25
		if pts.size() >= 2: d3.draw_line_path(pts, Color(0.3, 1, 0.4))
		var ut: float = f.land0 + 0.35 * (f.land1 - f.land0)
		d3.draw_sphere(c.feat_point(f, ut) + Vector3.UP * 0.1, 0.18, Color(0.3, 1, 0.4))


## the tyre forces and grip circles (see the list at the top)
static func _tyres(st, rig, d3) -> void:
	var b: Basis = rig.global_transform.basis
	var up := b.y.normalized()
	var fw := b.x.normalized()
	var sd := b.z.normalized()
	var mu_f: float = st._mu_f if is_finite(st._mu_f) else 0.9
	var mu_r: float = st._mu_r if is_finite(st._mu_r) else 0.9
	var nf: float = maxf(0.5, st.n_f if is_finite(st.n_f) else 4.0)
	var nr: float = maxf(0.5, st.n_r if is_finite(st.n_r) else 5.0)
	var sgn := signf(st.lat_a) if absf(st.lat_a) > 0.05 else 0.0
	var wheels := [
		[rig.wheel_f.global_position - up * rig.wheel_rf, st.dg_tyF, Vector2(-st._fb_f / (mu_f * nf), st.front_use * sgn), st.dg_cF],
		[rig.wheel_r.global_position - up * rig.wheel_rr, st.dg_tyR, Vector2(st._a_rear / (mu_r * nr), (1.0 - clampf(st.grip_r, 0.0, 1.0)) * sgn), st.dg_cR],
	]
	for w in wheels:
		var c: Vector3 = w[0] + up * 0.02
		var f: float = w[1] / 9.81
		if w[3] and f > 0.02:
			d3.draw_arrow(c, c + up * clampf(f, 0.0, 3.0), Color(1, 1, 1), 0.06, true)
		var use: Vector2 = w[2]
		var over := use.length() > 1.0
		var ring := PackedVector3Array()
		for k in 25:
			var a := TAU * k / 24.0
			ring.append(c + (fw * cos(a) + sd * sin(a)) * 0.25)
		d3.draw_line_path(ring, Color(1, 0.3, 0.25) if over else Color(0.4, 1, 0.5, 0.8))
		var dot := c + (fw * clampf(use.x, -1.5, 1.5) + sd * clampf(use.y, -1.5, 1.5)) * 0.25
		d3.draw_line(c, dot, Color(1, 0.3, 0.25) if over else Color(0.4, 1, 0.5))
		d3.draw_sphere(dot, 0.035, Color(1, 0.3, 0.25) if over else Color(0.4, 1, 0.5))
