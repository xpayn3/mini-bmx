extends SceneTree
## Top-down picture of the racing line: trail edges grey, centreline faint, LN red, from course point i0 for len points.
## Run: godot --headless --path godot -s res://tools/racing_line_map.gd -- out.png [seed] [i0] [len] [px per m]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	var seed := int(a[1]) if a.size() > 1 else 4242
	var i0 := int(a[2]) if a.size() > 2 else 0
	var ln := int(a[3]) if a.size() > 3 else 300
	var ppm := float(a[4]) if a.size() > 4 else 6.0
	var f := TerrainField.new()
	f.setup(seed)
	var c: TrailCourse = f.course
	var i1 := mini(c.n - 1, i0 + ln)
	var mn := Vector2(INF, INF); var mx := Vector2(-INF, -INF)
	for i in range(i0, i1):
		var p := Vector2(c.X[i], c.Z[i])
		mn = mn.min(p); mx = mx.max(p)
	mn -= Vector2(6, 6); mx += Vector2(6, 6)
	var sz := ((mx - mn) * ppm).ceil()
	var img := Image.create(int(sz.x), int(sz.y), false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.88, 0.78))
	var sub := maxi(1, int(ppm))
	for pass_ in 2:
		for i in range(i0, i1 - 1):
			for q in sub:
				var k := float(q) / sub
				var t := Vector2(-lerpf(c.TZ[i], c.TZ[i + 1], k), lerpf(c.TX[i], c.TX[i + 1], k)).normalized()
				var ctr := Vector2(lerpf(c.X[i], c.X[i + 1], k), lerpf(c.Z[i], c.Z[i + 1], k))
				var w := lerpf(c.W[i], c.W[i + 1], k)
				if pass_ == 0:
					for s in 60:
						_dot(img, (ctr + t * lerpf(-w, w, s / 59.0) - mn) * ppm, 1, Color(0.78, 0.62, 0.45))
				else:
					_dot(img, (ctr - mn) * ppm, 0, Color(0.5, 0.4, 0.3))
					_dot(img, (ctr + t * lerpf(c.LN[i], c.LN[i + 1], k) - mn) * ppm, 2, Color(0.8, 0.05, 0.05))
	img.save_png(out)
	print("LINEMAP ", out, " ", img.get_size())
	quit()


func _dot(img: Image, p: Vector2, r: int, col: Color) -> void:
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := int(p.x) + dx; var y := int(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)
