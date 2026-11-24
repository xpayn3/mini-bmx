extends SceneTree
## Bike physics on a stub terrain: flat start, a kicker at x=60, then a long descent.
class StubTerrain:
	func height(x, z): 
		var h := 0.0
		if x > 60 and x < 64: h = (x - 60) * 0.45          # kicker face
		elif x >= 64 and x < 75: h = -0.0                    # gap
		if x > 100: h -= (x - 100) * 0.15                    # descent
		return h
	func deck_height(x, z): return height(x, z)
	func surface(x, z): return 1
	func jump(x, z): return [0.0, 1.0 if (x > 55 and x < 80) else 0.0, 0.0, 0.0, null]
	func colliders_near(x, z): return []
class Host:
	var terrain = StubTerrain.new()
	var susp = null
	var ragdoll = null
	var pedal_a0 = [0.0, PI]
	var events := []
	var phys
	func flash(t): events.append("%.1fs %s" % [phys.distance, t])
	func msg_idle(): return true
	func burst(p, n, s, pw): pass
	func flow_up(): phys.flow_up()
	func smash(c, v, p): return false
	func rock_chips(c): pass
	func start_crash(r): events.append("CRASH " + r); phys.begin_crash()
	func get_up(): phys.get_up()
	func on_takeoff(): events.append("takeoff x=%.1f v=%.1f" % [phys.x, phys.v])
	func on_landing(at, imp): events.append("land x=%.1f air=%.2fs impact=%.1f" % [phys.x, at, imp])
	func on_bad_landing(_sev): pass
	func ride_fx(dt, f, va, w): pass
func _init():
	var tune = load("res://scripts/core/tune.gd").new()
	tune._ready()
	for bike in ["bmx", "dh"]:
		var gs = load("res://scripts/core/game_state.gd")
		var cfg: Dictionary = gs.BIKES[bike]
		tune.set_ride(cfg.ride)
		var h := Host.new()
		var p := BikePhysics.new(h); h.phys = p
		p.T = tune.v
		var ex := {"wheelbase": 1.2557, "wheelRadius": 0.374, "wheelRadiusRear": 0.355, "bbToRearAxle": 0.4423} if bike == "dh" else {}
		p.setup(ex, cfg)
		p.reset_at(0, 0, 0)
		var log := ""
		for i in 120 * 14:
			p.step(1.0 / 120, {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false})
			if i % 240 == 0: log += " t=%ds x=%.1f v=%.1fkmh y=%.2f |" % [i / 120, p.x, p.v * 3.6, p.y]
			if not p.is_sane(): log += " NON-FINITE at %d" % i; break
		print("== ", bike, log)
		print("   events: ", h.events)
		# turning test: steady left at speed
		p.reset_at(0, 0, 0)
		for i in 120 * 4: p.step(1.0 / 120, {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false})
		for i in 120 * 2: p.step(1.0 / 120, {"throttle": 1.0, "brake": 0.0, "steer": 1.0, "hop": false, "sprint": false})
		print("   turn: heading=%.2f lean=%.2f slip=%.2f v=%.1f crash=%s" % [p.heading, p.bike_lean, p.slip, p.v * 3.6, p.crash_on])
		# hop test
		p.reset_at(0, 0, 0)
		for i in 120 * 2: p.step(1.0 / 120, {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false})
		var maxy := 0.0
		for i in 30: p.step(1.0 / 120, {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "hop": true, "sprint": false})
		for i in 240:
			p.step(1.0 / 120, {"throttle": 1.0, "brake": 0.0, "steer": 0.0, "hop": false, "sprint": false})
			maxy = maxf(maxy, p.y)
		print("   hop peak=%.2f m  events=%s" % [maxy, h.events.slice(-2)])
	quit()
