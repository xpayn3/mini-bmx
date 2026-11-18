extends Node
## Ride autotest add-on: every second, print cloth stretch / finiteness and the cloth's frame cost.
var game
var t := 0.0
func _process(dt: float) -> void:
	t += dt
	if game == null or game.rider == null or game.rider.cloth == null: return
	var c: RiderCloth = game.rider.cloth
	if int(t) != int(t - dt):
		var sag := 0.0
		var ok := true
		for p in c._pieces:
			sag = maxf(sag, p.sim.MaxSag()); ok = ok and p.sim.IsFinite()
		var t0 := Time.get_ticks_usec()
		c._process(1.0 / 60)
		print("CLOTH t=%d v=%.1f max_sag=%.3f finite=%s frame_cost=%dus crash=%s" % [int(t), game.phys.v * 3.6, sag, ok, Time.get_ticks_usec() - t0, game.phys.crash_on])
