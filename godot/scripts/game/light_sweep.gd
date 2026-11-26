extends Node
## Test tool (BMX_LIGHT_SWEEP=h1,h2,... or =1 for the default list): steps the time of day through the hours, waits for the
## light / sky / auto exposure to settle, then measures the picture and saves a shot (BMX_LIGHT_SWEEP_SHOTS=dir/prefix).
## LSWEEP lines: mean / median / p98 display brightness, % clipped (any channel >= 0.985) and % crushed (< 0.02), the same
## on the rider (a box round him on screen), and the light values in use. Quits after the last hour.
## Run standing still: BMX_IDLE=1 BMX_SEED=4242 --autotest=<n x SETTLE + 4>

const DEFAULT := [5.9, 6.4, 7.0, 8.0, 10.0, 13.0, 16.0, 18.0, 19.0, 19.33, 19.7, 20.0, 20.3, 20.7, 21.5, 23.5]
const SETTLE := 3.2      # s per hour (sky radiance + auto exposure settle)

var game
var hours: Array = []
var i := -1
var t := 0.0
var shots := ""
var start := 2.5

func _ready() -> void:
	var s := Env.s("BMX_LIGHT_SWEEP")
	hours = DEFAULT.duplicate() if s == "1" else Array(s.split_floats(","))
	shots = Env.s("BMX_LIGHT_SWEEP_SHOTS")
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(dt: float) -> void:
	if game == null: return
	t += dt
	if i < 0:
		if t < start: return
		_next()
		return
	if t < SETTLE: return
	await RenderingServer.frame_post_draw
	_measure(float(hours[i]))
	_next()

func _next() -> void:
	i += 1
	t = 0.0
	if i >= hours.size():
		print("LSWEEP done")
		GameState.quit()
		return
	LightSettings.ensure_loaded()
	LightSettings.current["time"] = float(hours[i])
	LightSettings.current["cycle"] = 0.0
	LightSettings.version += 1
	if game.hud: game.hud.visible = false

func _measure(h: float) -> void:
	var img := get_viewport().get_texture().get_image()
	var full := img.get_size()
	var rb := _rider_box(full)
	var all := _stats(img, Rect2i(Vector2i.ZERO, full), 8)
	var rid := _stats(img, rb, 2) if rb.size.x > 4 else {"mean": -1.0, "p98": -1.0, "clip": -1.0, "crush": -1.0}
	var el := Game.sun_elev_deg(h)
	print("LSWEEP h=%5.2f el=%5.1f | frame mean=%.3f med=%.3f p98=%.3f clip=%.2f%% crush=%.2f%% | rider mean=%.3f p98=%.3f clip=%.2f%% | sun=%.3f sky_le=%s expo=%.3f ae=%.0f..%.0f scale=%.3f | %s" % [
		h, el, all.mean, all.med, all.p98, all.clip, all.crush, rid.mean, rid.p98, rid.clip,
		game.sun.light_energy, str(game.sky_mat.get_shader_parameter("light_energy")), game.env.tonemap_exposure,
		game.cam_attr.auto_exposure_min_sensitivity, game.cam_attr.auto_exposure_max_sensitivity, game.cam_attr.auto_exposure_scale,
		game.light_note if "light_note" in game else ""])
	if shots != "":
		img.save_png("%s_%05.2f.png" % [shots, h])

func _rider_box(full: Vector2i) -> Rect2i:
	var c3 := get_viewport().get_camera_3d()
	if c3 == null or game.rider == null: return Rect2i()
	var hips: Vector3 = game.rider.global_position + Vector3(0, 1.0, 0)
	if c3.is_position_behind(hips): return Rect2i()
	var sp := c3.unproject_position(hips)
	var top := c3.unproject_position(hips + Vector3(0, 0.8, 0))
	var r := maxf(absf(sp.y - top.y), 8.0)
	var rr := Rect2i(int(sp.x - r * 0.7), int(sp.y - r), int(r * 1.4), int(r * 2.0))
	return rr.intersection(Rect2i(Vector2i.ZERO, full))

func _stats(img: Image, r: Rect2i, step: int) -> Dictionary:
	var ls := PackedFloat32Array()
	var clip := 0
	var crush := 0
	var n := 0
	for y in range(r.position.y, r.end.y, step):
		for x in range(r.position.x, r.end.x, step):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			ls.append(l)
			if maxf(c.r, maxf(c.g, c.b)) >= 0.985: clip += 1
			if l < 0.02: crush += 1
			n += 1
	if n == 0: return {"mean": 0.0, "med": 0.0, "p98": 0.0, "clip": 0.0, "crush": 0.0}
	ls.sort()
	var sum := 0.0
	for v in ls: sum += v
	return {"mean": sum / n, "med": ls[n / 2], "p98": ls[mini(n - 1, int(n * 0.98))], "clip": 100.0 * clip / n, "crush": 100.0 * crush / n}
