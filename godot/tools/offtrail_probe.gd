extends SceneTree
## Off the trail: how rideable is the land? Straight lines through the open land (and along side paths), the ground
## sampled every 0.25 m (TerrainField.base: no jumps / rocks). Per class: the share of distance where a crest is curved
## enough to throw a bike off at 20 / 30 / 40 km/h (v^2 x curvature < -g, curvature over +-0.6 m and +-1.5 m), the
## share steeper than 15 / 25 deg, and the dips that compress hard (> +1 g at 30 km/h).
## Run: --headless -s res://tools/offtrail_probe.gd [-- seeds=4242,5]
const G := 9.81

func _init() -> void:
	var seeds := [4242, 5]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			seeds = []
			for s in a.substr(6).split(","): seeds.append(int(s))
	var tot := {}
	for sd in seeds:
		var tg := Terrain.new()
		tg.use_cs = false
		tg.set_seed(sd)
		var f: TerrainField = tg.field
		var rng := RandomNumberGenerator.new(); rng.seed = 77 + sd
		var lines := 0
		while lines < 220:
			var x0 := rng.randf_range(150.0, 2200.0)
			var z0 := rng.randf_range(-700.0, 700.0)
			if f.trail(x0, z0) > 0.0: continue
			var ap := absf(f.pathN(x0, z0))
			var cls := "path" if ap < 0.04 else ("land" if ap > 0.3 else "")
			if cls == "": continue
			var ang := rng.randf() * TAU
			if cls == "path":   # along the side path: across the gradient of pathN
				f._grad_at(x0, z0)
				ang = atan2(f._gx, -f._gz)
			var dx := cos(ang); var dz := sin(ang)
			lines += 1
			var st: Dictionary = tot.get(cls, {"m": 0.0, "c20": 0.0, "c30": 0.0, "c40": 0.0, "s20": 0.0, "s30": 0.0, "s40": 0.0, "g15": 0.0, "g25": 0.0, "dip": 0.0})
			var L := 60.0
			var s := 0.0
			while s < L:
				var px := x0 + dx * s; var pz := z0 + dz * s
				if cls == "path" and absf(f.pathN(px, pz)) > 0.06: break   # (left the path)
				if f.trail(px, pz) > 0.0: break
				var h0 := f.base(px, pz)
				var k6 := (f.base(px + dx * 0.6, pz + dz * 0.6) + f.base(px - dx * 0.6, pz - dz * 0.6) - 2.0 * h0) / 0.36
				var k15 := (f.base(px + dx * 1.5, pz + dz * 1.5) + f.base(px - dx * 1.5, pz - dz * 1.5) - 2.0 * h0) / 2.25
				var gr := absf(f.base(px + dx * 0.5, pz + dz * 0.5) - f.base(px - dx * 0.5, pz - dz * 0.5))
				var dl := 0.25
				st.m += dl
				for vv in [[20.0, "c20", "s20"], [30.0, "c30", "s30"], [40.0, "c40", "s40"]]:
					var v: float = vv[0] / 3.6
					if v * v * k6 < -G: st[vv[1]] += dl
					if v * v * k15 < -G: st[vv[2]] += dl
				if gr > tan(deg_to_rad(15.0)): st.g15 += dl
				if gr > tan(deg_to_rad(25.0)): st.g25 += dl
				if (30.0 / 3.6) ** 2 * k15 > G: st.dip += dl
				s += dl
			tot[cls] = st
		tg.free()
	for cls in tot:
		var st: Dictionary = tot[cls]
		var m: float = maxf(1.0, st.m)
		print("OFFTRAIL %-4s %5.0f m  throws (0.6 m) 20/30/40 km/h: %4.1f / %4.1f / %4.1f %%   (1.5 m): %4.1f / %4.1f / %4.1f %%   steeper 15/25 deg: %4.1f / %4.1f %%   hard dips @30: %4.1f %%" % [
			cls, m, 100 * st.c20 / m, 100 * st.c30 / m, 100 * st.c40 / m, 100 * st.s20 / m, 100 * st.s30 / m, 100 * st.s40 / m, 100 * st.g15 / m, 100 * st.g25 / m, 100 * st.dip / m])
	quit(0)
