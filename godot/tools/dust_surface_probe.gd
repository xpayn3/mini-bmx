extends SceneTree
## Reads a ride_log.csv (F8) and prints, along the ridden path, the surface the dust code sees under the
## rear tyre (0 ground, 1 trail, 2 water, 3 sand), the trail mask, the half width and distance from the centreline.
## -s res://tools/dust_surface_probe.gd -- <seed> <ride_log.csv>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var sd := int(a[0])
	var tr := Terrain.new()
	tr.use_cs = true
	tr.set_seed(sd)
	var f: TerrainField = tr.field
	var fh := FileAccess.open(a[1], FileAccess.READ)
	fh.get_line(); fh.get_line()
	var n := 0
	var cnt := [0, 0, 0, 0]
	while not fh.eof_reached():
		var l := fh.get_line().split(",")
		if l.size() < 10: continue
		n += 1
		var x := float(l[2]); var z := float(l[4]); var hd := float(l[7])
		# rear tyre ~0.45 m behind the bike's point
		var rx := x - cos(hd) * 0.45; var rz := z - sin(hd) * 0.45
		var s := tr.surface(rx, rz)
		cnt[s] += 1
		if n % 120 == 0:
			f.query(rx, rz)
			print("SURF t=%s x=%.0f z=%.0f v=%s surf=%d trail=%.2f w=%.2f d=%.2f air=%s" % [l[1], rx, rz, l[5], s, f.trail(rx, rz), f.q_w, f.q_d, l[22]])
	print("SURFSUM rows=%d ground=%d trail=%d water=%d sand=%d" % [n, cnt[0], cnt[1], cnt[2], cnt[3]])
	quit()
