extends SceneTree
## Finds the sun in an equirect HDRI: brightest pixel -> elevation / azimuth, plus average sky colour.
func _init():
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr"))
	img.resize(1024, 512, Image.INTERPOLATE_BILINEAR)
	var best := -1.0; var bx := 0; var by := 0
	var avg := Color(0, 0, 0); var n := 0
	for y in 512:
		for x in 1024:
			var c := img.get_pixel(x, y)
			var l := c.r + c.g + c.b
			if l > best: best = l; bx = x; by = y
			if y < 256: avg += c; n += 1
	var u := (bx + 0.5) / 1024.0; var v := (by + 0.5) / 512.0
	print("sun px=", bx, ",", by, " lum=", best, " elevation_deg=", 90.0 - v * 180.0, " u=", u)
	print("upper-sky average=", avg / n, " sun colour=", img.get_pixel(bx, by))
	quit()
