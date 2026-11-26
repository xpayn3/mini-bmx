extends SceneTree
## Goggle lens LUTs through Godot's real tonemap pass (not headless: it renders).
##   ..._console.exe --path godot -s res://tools/lens_lut_probe.gd -- <out_dir> [photo.png]
## 1. a test card (grey ramp + R / G / B ramps + colour grid) with no LUT vs the identity LUT: must match (IDENTITY max_err)
## 2. every lens: the GPU result vs GoggleLens.grade on the CPU (axis order, half-texel): LENS <id> max_err / mean_err
## 3. saves <out_dir>/lens_<id>.png of the photo (or the test card) graded by each lens + lens_sheet.png. Prints PASS / FAIL.

const GoggleLens = preload("res://scripts/rider/goggle_lens.gd")
const W := 512
const H := 288

var vp: SubViewport
var env: Environment
var mat: StandardMaterial3D

func _init() -> void:
	_run.call_deferred()

func _card() -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var u := float(x) / (W - 1)
			var c: Color
			var band := y * 6 / H
			match band:
				0: c = Color(u, u, u)
				1: c = Color(u, 0, 0)
				2: c = Color(0, u, 0)
				3: c = Color(0, 0, u)
				_:   # a colour grid: hue across, value / saturation down
					var vv := float(y - H * 4 / 6) / (H * 2 / 6)
					c = Color.from_hsv(u, 0.25 + 0.75 * vv, 1.0 - 0.7 * vv)
			img.set_pixel(x, y, c)
	return img

func _render(lut: Texture3D) -> Image:
	env.adjustment_color_correction = lut
	for i in 6: await process_frame
	return vp.get_texture().get_image()

func _cmp(a: Image, b: Image) -> Vector2:
	var mx := 0.0; var sum := 0.0; var n := 0
	for y in range(2, H - 2, 2):
		for x in range(2, W - 2, 2):
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			var d := maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b)))
			mx = maxf(mx, d); sum += d; n += 1
	return Vector2(mx * 255.0, sum / n * 255.0)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.adjustment_enabled = true
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0   # vertical extent
	cam.position = Vector3(0, 0, 1)
	vp.add_child(cam)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(float(W) / H, 1.0)
	q.mesh = qm
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material_override = mat
	vp.add_child(q)
	var ok := true
	# 1 + 2: the test card
	var card := _card()
	mat.albedo_texture = ImageTexture.create_from_image(card)
	var plain: Image = await _render(null)
	var idn: Image = await _render(GoggleLens.make_lut({}))
	var e := _cmp(plain, idn)
	print("IDENTITY max_err=%.2f mean_err=%.3f (of 255)" % [e.x, e.y])
	if e.x > 4.5 or e.y > 0.5: ok = false   # (33^3 LUT: a few levels in the darkest / brightest 1 %)
	if OS.get_environment("BMX_LUT_DIAG") != "":
		var line := "DIAG grey u: plain/id"
		for k in 11:
			var x := int(k * (W - 1) / 10.0)
			line += "  %.2f:%d/%d" % [k / 10.0, roundi(plain.get_pixel(x, H / 12).r * 255), roundi(idn.get_pixel(x, H / 12).r * 255)]
		print(line)
	var pass_raw := _cmp(plain, card)
	print("PIPELINE plain render vs card max_err=%.2f mean_err=%.3f" % [pass_raw.x, pass_raw.y])
	for id in GoggleLens.ids():
		var lut := GoggleLens.lut(id)
		if lut == null:
			print("LENS %s = no LUT" % id)
			continue
		var t0 := Time.get_ticks_usec()
		GoggleLens._cache.erase(id)
		lut = GoggleLens.lut(id)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var gpu: Image = await _render(lut)
		var cpu := plain.duplicate()
		for y in H:
			for x in W:
				cpu.set_pixel(x, y, GoggleLens.grade(plain.get_pixel(x, y), GoggleLens.LENSES[id].grade))
		var d := _cmp(gpu, cpu)
		print("LENS %s (%s) build_ms=%.1f gpu_vs_cpu max_err=%.2f mean_err=%.3f" % [id, GoggleLens.display_name(id), build_ms, d.x, d.y])
		if d.y > 1.2 or d.x > 10.0: ok = false   # (33^3 + hue moves: the trilinear LUT rounds sharp hue bands a little)
	# 3: the photo (or the card) through every lens
	if args.size() > 1:
		var ph := Image.load_from_file(args[1])
		if ph:
			ph.convert(Image.FORMAT_RGBA8)
			ph.resize(W * 2, H * 2, Image.INTERPOLATE_LANCZOS)
			vp.size = Vector2i(W * 2, H * 2)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			mat.albedo_texture = ImageTexture.create_from_image(ph)
	var sheet: Image = null
	var ids := GoggleLens.ids()
	var i := 0
	for id in ids:
		var img: Image = await _render(GoggleLens.lut(id))
		img.save_png(out.path_join("lens_%s.png" % id))
		var sw := img.get_width() / 2; var sh := img.get_height() / 2
		if sheet == null: sheet = Image.create(sw * 4, sh * 2, false, img.get_format())
		var small := img.duplicate(); small.resize(sw, sh, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(small, Rect2i(0, 0, sw, sh), Vector2i((i % 4) * sw, (i / 4) * sh))
		i += 1
	sheet.save_png(out.path_join("lens_sheet.png"))
	print("LENS_PROBE %s -> %s" % ["PASS" if ok else "FAIL", out])
	quit(0 if ok else 1)
