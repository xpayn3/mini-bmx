extends SceneTree
## Trail bumpiness along a path, as a rider feels it: the 2nd difference of the physics ground every 0.5 m (mm) following
## the ridden line itself, and following a path 1.2 m beside it; plus how the line's bumpiness changes along the route
## (per 50 m: p10 / p50 / p90). -- [seed] [metres]
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sd := int(args[0]) if args.size() > 0 else 4242
	var L := float(args[1]) if args.size() > 1 else 3000.0
	var t := Terrain.new(sd)
	var f: TerrainField = t.field
	var C = f.course
	var res := []
	for side: float in [0.0, 1.2]:
		var hs := PackedFloat32Array()
		var js := PackedByteArray()
		var s := 100.0
		while s < L:
			var p: Array = C.at(s)
			var nx: float = -p[3]; var nz: float = p[2]
			var off := f.line_off(p[0], p[1])
			var sg := 1.0
			if absf(f.across(p[0] + nx, p[1] + nz) - f.across(p[0], p[1]) - 1.0) > 0.5: sg = -1.0
			var a: float = (off + side) * sg
			var px: float = p[0] + nx * a; var pz: float = p[1] + nz * a
			var tx: float = p[2] * 0.5; var tz: float = p[3] * 0.5
			js.append(1 if f.jump_mask(px, pz) > 0.0 else 0)
			hs.append((f.ground(px, pz) - 0.5 * (f.ground(px + tx, pz + tz) + f.ground(px - tx, pz - tz))) * 1000.0)
			s += 0.5
		var tot := 0.0; var bins := []; var b := 0.0; var cnt := 0
		for i in range(1, hs.size() - 1):
			var m := 0.0; var c := 0
			for k in range(maxi(0, i - 5), mini(hs.size(), i + 6)): m += hs[k]; c += 1
			var r := absf(hs[i] - m / c)
			if js[i] == 1: r = 0.0
			else: cnt += 1
			tot += r; b += r
			if i % 100 == 0: bins.append(b / 100.0); b = 0.0
		bins.sort()
		res.append([tot / maxi(1, cnt), bins[int(bins.size() * 0.1)], bins[bins.size() / 2], bins[int(bins.size() * 0.9)]])
	print("WEAR seed=%d line=%.2f mm beside=%.2f mm ratio=%.2f | line per 50 m p10=%.2f p50=%.2f p90=%.2f" % [sd, res[0][0], res[1][0], res[0][0] / res[1][0], res[0][1], res[0][2], res[0][3]])
	t.free()
	quit()
