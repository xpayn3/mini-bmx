class_name HqStill
extends Node
## HQ still render, the "offline renderer" look for the garage showroom and photo mode: once the camera has
## rested for a moment, every frame renders the scene again shifted by a fraction of a pixel (a tent filter
## ~1.6 px wide), with each shadow-casting light wobbled inside a small cone / sphere, and the frames are
## averaged on the GPU (HqAccumEffect, before glow / tonemap). After SAMPLES frames the picture is clean:
## no jaggies on thin tubes / spokes, glossy highlights resolved, soft shadow edges, SSAO / SSIL noise
## smoothed. Moving the camera, a light, or the owner calling reset() starts again.
##
## The pixel shift goes through the camera's frustum offset (the camera is switched to a frustum projection
## matching its fov while sampling), so the camera's transform is never touched and its owner can keep
## setting it every frame. Lights are jittered from their last "clean" transform and put back on stop.
## TAA is off while sampling (it would fight the jitter) and back on after.
##   var hq := HqStill.new(); hq.cam = cam; add_child(hq)    # (cam.compositor gets the effect)
##   hq.enabled = <scene is still>;  hq.reset() after a change the camera doesn't show
## Tests: BMX_HQ=0 off, BMX_HQ_SAMPLES=n, BMX_HQ_PROBE=1 (HQ lines).

signal finished

const SAMPLES := 128
const SETTLE := 0.3            # s the camera must rest first
const MOVE_EPS := 0.0003       # m: less than this is "still" (eased cameras creep for a while)
const TURN_EPS := 0.00008      # rad
const PIXEL_FILTER := 0.8      # tent filter radius in pixels (0.8 = ~1.6 px wide, like an offline AA filter)
const SUN_CONE := 0.006        # rad a directional light wanders (~0.35 deg: the sun's own size is 0.27)
const LAMP_SPHERE := 0.03      # m a positional light wanders

var cam: Camera3D
var show_badge := false    # a small "HQ" progress line at the top of the screen
var badge_hidden := false  # (photo mode hides it while it takes the shot)
var enabled := true
var samples := SAMPLES
var effect: HqAccumEffect

var _n := 0
var _running := false
var _still_t := 0.0
var _last_us := 0
var _xf := Transform3D()
var _fov := -1.0
var _off := Vector2.ZERO
var _lights := {}          # Light3D -> [clean Transform3D, applied Transform3D]
var _taa_saved := false
var _proj_saved := Camera3D.PROJECTION_PERSPECTIVE
var _size_seen := Vector2i.ZERO
var _probe := Env.raw("BMX_HQ_PROBE") != ""
var _hq_off := Env.raw("BMX_HQ") == "0"   # tests: never (before / after shots)
var _t0 := 0
var _badge: Label = null
var _badge_a := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # photo mode freezes time
	process_priority = 100000                 # after every owner has placed the camera this frame
	var e := Env.raw("BMX_HQ_SAMPLES")
	if e != "": samples = maxi(1, int(e))
	effect = HqAccumEffect.new()
	if cam:
		if cam.compositor == null: cam.compositor = Compositor.new()
		var fx := cam.compositor.compositor_effects.duplicate()
		fx.append(effect)   # last: after the dust has been drawn into the colour
		cam.compositor.compositor_effects = fx
	_last_us = Time.get_ticks_usec()
	if show_badge:
		var cl := CanvasLayer.new()
		cl.layer = 5
		add_child(cl)
		_badge = Label.new()
		_badge.add_theme_font_size_override("font_size", 13)
		_badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		_badge.add_theme_constant_override("outline_size", 4)
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_badge.position = Vector2(-120, 10)
		_badge.size = Vector2(240, 20)
		_badge.modulate.a = 0.0
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(_badge)

func _update_badge(rdt: float) -> void:
	if _badge == null: return
	var want := 0.0
	if _running and _n < samples:
		want = 1.0
		_badge.text = "HQ RENDER  %d%%" % int(progress() * 100.0)
	elif _running:
		_badge.text = "HQ RENDER  DONE"
	_badge_a = move_toward(_badge_a, want, rdt * (4.0 if want > _badge_a else 0.8))
	_badge.modulate.a = 0.0 if badge_hidden else _badge_a

func _exit_tree() -> void:
	_stop()
	if cam and is_instance_valid(cam) and cam.compositor:
		var fx := cam.compositor.compositor_effects.duplicate()
		fx.erase(effect)
		cam.compositor.compositor_effects = fx

## start again (something changed that the camera can't see: paint, a part, the light)
func reset() -> void:
	_stop()
	_still_t = 0.0

func running() -> bool: return _running
func done() -> bool: return _running and _n >= samples
func progress() -> float: return clampf(float(_n) / samples, 0.0, 1.0) if _running else 0.0
func count() -> int: return _n if _running else 0

func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var rdt := minf((now - _last_us) / 1e6, 0.1)   # real time: photo mode runs at time_scale 0
	_last_us = now
	_update_badge(rdt)
	if cam == null or not is_instance_valid(cam) or effect == null: return
	var changed := _cam_changed()
	changed = _lights_changed() or changed
	if effect.size != _size_seen:
		_size_seen = effect.size
		changed = true
	if changed or not enabled or _hq_off or not cam.current:
		if _running and _probe: print("HQ stop n=%d changed=%s enabled=%s" % [_n, changed, enabled])
		_stop()
		_still_t = 0.0
		return
	_still_t += rdt
	if _still_t < SETTLE: return
	if not _running: _start()
	if _n < samples:
		_jitter(_n)
		effect.n = _n
		effect.mode = HqAccumEffect.MODE_ADD
		_n += 1
		if _n >= samples:
			if _probe: print("HQ done samples=%d ms=%.0f cam=%s fov=%.2f proj=%d size=%.4f" % [_n, (Time.get_ticks_usec() - _t0) / 1000.0, cam.global_position, cam.fov, cam.projection, cam.size])
			finished.emit()
	else:
		_unjitter()   # nothing more to add: the camera / lights back as they were, the sum is shown
		effect.n = _n
		effect.mode = HqAccumEffect.MODE_SHOW

func _cam_changed() -> bool:
	var xf := cam.global_transform
	var off := Vector2(cam.h_offset, cam.v_offset)
	var moved := xf.origin.distance_to(_xf.origin) > MOVE_EPS or off.distance_to(_off) > MOVE_EPS \
		or absf(cam.fov - _fov) > 0.002
	if not moved:
		for i in 3:
			if xf.basis[i].distance_to(_xf.basis[i]) > TURN_EPS:
				moved = true
				break
	if moved:
		_xf = xf; _fov = cam.fov; _off = off
	return moved

## a jittered light that its owner moved since we last set it: take its new place as the clean one
func _lights_changed() -> bool:
	var any := false
	for l in _lights.keys():
		if not is_instance_valid(l):
			_lights.erase(l)
			continue
		var rec: Array = _lights[l]
		var t: Transform3D = l.transform
		var a: Transform3D = rec[1]
		if t.origin.distance_to(a.origin) > 1e-5 or t.basis.x.distance_to(a.basis.x) > 1e-5 \
				or t.basis.y.distance_to(a.basis.y) > 1e-5 or t.basis.z.distance_to(a.basis.z) > 1e-5:
			rec[0] = t; rec[1] = t
			any = true
	return any

func _start() -> void:
	_running = true
	_n = 0
	_t0 = Time.get_ticks_usec()
	var vp := cam.get_viewport()
	_taa_saved = vp.use_taa
	vp.use_taa = false
	_proj_saved = cam.projection
	_lights.clear()
	var w := cam.get_world_3d()
	for l in get_tree().root.find_children("*", "Light3D", true, false):
		var li := l as Light3D
		if li.shadow_enabled and li.is_visible_in_tree() and li.light_energy > 0.0 and li.get_world_3d() == w:
			_lights[li] = [li.transform, li.transform]
	if _probe: print("HQ start lights=%d samples=%d taa_was=%s" % [_lights.size(), samples, _taa_saved])

func _stop() -> void:
	if effect: effect.mode = HqAccumEffect.MODE_OFF
	if not _running: return
	_running = false
	_n = 0
	_unjitter()
	_lights.clear()
	if cam and is_instance_valid(cam):
		cam.projection = _proj_saved
		var vp := cam.get_viewport()
		if vp: vp.use_taa = _taa_saved

static func _halton(i: int, b: int) -> float:
	var f := 1.0
	var r := 0.0
	var k := i + 1
	while k > 0:
		f /= b
		r += f * (k % b)
		k /= b
	return r

static func _tent(u: float) -> float:   # uniform 0..1 -> tent -1..1 (a smooth reconstruction filter)
	return sqrt(2.0 * u) - 1.0 if u < 0.5 else 1.0 - sqrt(2.0 - 2.0 * u)

func _jitter(i: int) -> void:
	# pixel: a frustum projection equal to the camera's perspective, its centre moved by a sub-pixel amount
	var vp := cam.get_viewport()
	var px := Vector2(vp.get_visible_rect().size) * vp.scaling_3d_scale
	var near := cam.near
	var keep_h := cam.keep_aspect == Camera3D.KEEP_HEIGHT
	var size := 2.0 * near * tan(deg_to_rad(cam.fov) * 0.5)
	var pix := size / maxf(1.0, px.y if keep_h else px.x)
	var j := Vector2(_tent(_halton(i, 2)), _tent(_halton(i, 3))) * PIXEL_FILTER
	if i == 0: j = Vector2.ZERO
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.size = size
	cam.frustum_offset = j * pix
	# lights: each shadow-casting one somewhere in its little cone / sphere (smooth shadow edges)
	var u := _halton(i, 5)
	var v := _halton(i, 7)
	for l in _lights:
		var rec: Array = _lights[l]
		var clean: Transform3D = rec[0]
		var t := clean
		if i > 0:
			if l is DirectionalLight3D:
				var d := clean.basis.z.normalized()
				var a := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
				var b := d.cross(a)
				var ang := TAU * u
				var axis := (a * cos(ang) + b * sin(ang)).normalized()
				t.basis = Basis(axis, SUN_CONE * sqrt(v)) * clean.basis
			else:
				var w := _halton(i, 11)
				var r := LAMP_SPHERE * pow(w, 1.0 / 3.0)
				var z := 2.0 * u - 1.0
				var s := sqrt(maxf(0.0, 1.0 - z * z))
				t.origin += Vector3(s * cos(TAU * v), z, s * sin(TAU * v)) * r
		l.transform = t
		rec[1] = t

func _unjitter() -> void:
	if cam and is_instance_valid(cam) and cam.projection == Camera3D.PROJECTION_FRUSTUM:
		cam.frustum_offset = Vector2.ZERO
	for l in _lights:
		if not is_instance_valid(l): continue
		var rec: Array = _lights[l]
		l.transform = rec[0]
		rec[1] = rec[0]
