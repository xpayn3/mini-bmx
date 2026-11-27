class_name LensFx
extends Node
## Water and dust on the camera lens (shown on the default trail camera only: game.gd).
##
## Water = real drops (fx/LensDropsCs.cs: mass points held by pinning, pushed by gravity and the air over
## the glass, merging, leaving beads and rivulets; after Nakata / Kakimoto / Nishita and Kaneda et al.).
## They are drawn into a half-resolution lens NORMAL MAP (two 2D SubViewports, shaders/lens_drop.gdshader):
##   rivulet map: never cleared, every running drop paints the stretch it ran; dried a little each frame
##                (shaders/lens_dry.gdshader, HDR target so the slow drying isn't stuck at 8-bit steps)
##   drop map:    the rivulet map + the drops on top, cleared every frame
## grade.gdshader reads the drop map and refracts the scene through it (shaders/lens_fx.gdshaderinc).
## Dust = one level 0..1 (`dust`): a scanned smudge mask that fades in as it rises (shader). Riding through
## dry dust builds it, water washes it off. (Mud splats were tried first: "very ugly", removed.)
## Slow, drops crawl down; fast, the air streams them down the glass, fanning out (from the camera's motion).
## Clean glass (no drops, no dust) = the viewports stop and the shader skips all of it.

const MAP_SCALE := 0.5       # the lens map's size against the screen
const RIVULET_LIFE := 1.0    # s a rivulet takes to dry to ~a third (the air dries it faster); 9 s lingered
                             # too long (user: "the streaks must disappear after him")

var rain := 0.0              # rain falling on the glass (weather; 0 = none), 0..1
var wind := 0.0              # air over the glass, 0..1
var wind_override := -1.0
const INERTIA := 0.6         # m/s of "airflow" per m/s^2 of the camera's acceleration (the water lagging)
var _flow := Vector2(0.0, 1.0)    # the air's direction over the glass, screen space
var _cam_p := Vector3.ZERO
var _cam_v := Vector3.ZERO
var _cam_a := Vector3.ZERO
var _cam_ok := false
var dust := 0.0              # dust on the glass, 0..1
var dust_col := Color(0.62, 0.55, 0.45)
const DUST_WASH := 0.05      # /s per unit of water on the glass
var _dust_tex: Texture2D = load("res://assets/textures/lens/lens_dirt.png")   # tools/make_lens_dirt.py

var drops: Object            # LensDropsCs (null without C#: no water, dust still works)
var _trail_vp: SubViewport
var _drop_vp: SubViewport
var _trail_mm: MultiMesh
var _drop_mm: MultiMesh
var _dry_mat: ShaderMaterial
var _map_live := false
var _wet_t := 0.0            # s since the last water: the map stops once everything has dried
var _aspect := 16.0 / 9.0
var _pend := 0.0
var _clear_left := 0
var _dump_t := 0.0

func _ready() -> void:
	drops = CrashLog.cs_new("res://scripts/fx/LensDropsCs.cs")
	if drops == null: return
	var quad := _quad()
	var dsh: Shader = load("res://shaders/lens_drop.gdshader")
	var dmat := ShaderMaterial.new()
	dmat.shader = dsh
	# cleared for its first frames (a never-cleared target starts as uninitialised GPU memory), then kept
	_trail_vp = _make_vp(SubViewport.CLEAR_MODE_ALWAYS)
	_clear_left = 3
	var dry := ColorRect.new()
	dry.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dry_mat = ShaderMaterial.new()
	_dry_mat.shader = load("res://shaders/lens_dry.gdshader")
	dry.material = _dry_mat
	_trail_vp.add_child(dry)
	_trail_mm = _make_mm(quad)
	var tmi := MultiMeshInstance2D.new()
	tmi.multimesh = _trail_mm
	tmi.material = dmat
	_trail_vp.add_child(tmi)
	_drop_vp = _make_vp(SubViewport.CLEAR_MODE_ALWAYS)
	var under := TextureRect.new()   # the rivulets, as they are (premultiplied)
	under.texture = _trail_vp.get_texture()
	under.set_anchors_preset(Control.PRESET_FULL_RECT)
	under.stretch_mode = TextureRect.STRETCH_SCALE
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	under.material = pm
	_drop_vp.add_child(under)
	_drop_mm = _make_mm(quad)
	var dmi := MultiMeshInstance2D.new()
	dmi.multimesh = _drop_mm
	dmi.material = dmat
	_drop_vp.add_child(dmi)
	add_child(_trail_vp)
	add_child(_drop_vp)
	if _pend > 0.0: splash(_pend)
	_pend = 0.0

func _make_vp(clear: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.use_hdr_2d = true
	vp.render_target_clear_mode = clear
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(800, 450)
	return vp

func _make_mm(quad: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = 1800
	mm.visible_instance_count = 0
	return mm

## a unit quad, UV (0, 0) at (-0.5, -0.5): local +x = along the heading, +y across (lens_drop.gdshader)
func _quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func active() -> bool:
	return _map_live or dust > 0.003 or rain > 0.0

## dust on the glass: k per second of riding through it (ride_fx: fast on dry dirt / sand), or a bump (a crash)
func add_dust(k: float, col: Color) -> void:
	dust = clampf(dust + k, 0.0, 0.75)   # (never fully filthy: subtle, edges and corners only)
	dust_col = dust_col.lerp(col, clampf(k * 4.0, 0.02, 0.5))

## water thrown at the glass (a splash: 0.05 a few drops .. 1 soaked). k sets HOW MANY drops, not how big:
## riding through water calls this every frame with a tiny k, which used to give one speck (1-4 px) a frame,
## smaller the higher the frame rate. The fractions add up to whole drops of the full size mix.
const SPRAY_DROPS := 70.0    # drops per unit of k
var _spray := 0.0
var _se_t := 0.0

func splash(k: float) -> void:
	if not is_inside_tree(): _pend += k   # before the sim exists (the first respawn runs before _ready)
	if drops == null or k <= 0.0: return
	_wet_t = 0.0
	_spray += k * SPRAY_DROPS
	var n := int(_spray)
	if n < 1: return
	_spray -= n
	# radius in screen heights, many small and a few big (LensDropsCs.RandR)
	drops.Splash(n, _aspect, 0.0025, 0.014 + 0.004 * minf(k * 2.0, 1.0))

func wipe() -> void:
	dust = 0.0
	if drops: drops.Clear()
	if _trail_vp:   # empty the rivulet map
		_trail_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_clear_left = 3
		_trail_mm.visible_instance_count = 0
	_map_live = false

## The air over the glass comes from the CAMERA's own motion (whatever view is in use): its velocity in its
## own frame says where the air hits the lens from (forward = down the glass, fanning out, sideways (the
## side cam) = across it, rising / falling = down / up), and its acceleration makes the water lag (a camera
## swinging round a bend throws it to the outside). A camera standing still (trackside) has no airflow.
## focus = the view's middle (uv); vs = the screen's size.
func update(dt: float, cam: Camera3D, vs: Vector2, focus: Vector2) -> void:
	_aspect = vs.x / maxf(vs.y, 1.0)
	var flow := Vector2(0.0, 1.0)
	var spd := 0.0
	if cam and dt > 0.0:
		var p := cam.global_position
		var v := (p - _cam_p) / dt if _cam_ok else Vector3.ZERO
		_cam_p = p
		_cam_ok = true
		if v.length() > 80.0: v = _cam_v   # a cut / teleport: not motion
		var pv := _cam_v
		_cam_v = _cam_v.lerp(v, minf(1.0, dt * 6.0))
		_cam_a = _cam_a.lerp((_cam_v - pv) / dt, minf(1.0, dt * 4.0))
		var bi := cam.global_transform.basis.orthonormalized().inverse()
		var vl := bi * _cam_v    # x right, y up, -z forward
		var al := bi * _cam_a
		# screen space, y down. Moving forward streams the water DOWN the glass (user, 2026-11-24: up, like a
		# car windshield, read as inverted); sideways motion across it, rising / falling down / up
		var air := Vector2(-vl.x, maxf(-vl.z, 0.0) + vl.y)
		air += Vector2(-al.x, al.y) * INERTIA                 # the water lags the glass's acceleration
		spd = air.length()
		if spd > 0.01: flow = air / spd
	_flow = _flow.lerp(flow, minf(1.0, dt * 5.0)).normalized() if _flow != Vector2.ZERO else flow
	var wt := smoothstep(3.0, 17.0, spd) if wind_override < 0.0 else wind_override
	wind += (wt - wind) * minf(1.0, dt * 2.5)
	var fa := Vector2(focus.x * _aspect, focus.y)
	if drops == null: return
	# water on the glass washes the dust off (each drop's own path is drawn clean in the shader too)
	if dt > 0.0 and dust > 0.0:
		dust = maxf(0.0, dust - dt * DUST_WASH * minf(float(drops.Count()) / 150.0 + rain, 1.5))
	# test: BMX_LENS_SPLASH_EVERY=secs[,k] splashes the lens that often (to watch drops land, cling and run)
	if dt > 0.0 and Env.s("BMX_LENS_SPLASH_EVERY") != "":
		var se := Env.s("BMX_LENS_SPLASH_EVERY").split(",")
		_se_t += dt
		if _se_t >= float(se[0]):
			_se_t = 0.0
			splash(float(se[1]) if se.size() > 1 else 0.5)
	if dt > 0.0:
		drops.Step(minf(dt, 0.05), rain, wind, _aspect, fa.x, fa.y, 1.0, _flow.x, _flow.y)
	var n: int = drops.Count()
	_wet_t = 0.0 if n > 0 or rain > 0.0 else _wet_t + dt
	var live := _wet_t < RIVULET_LIFE * 1.5   # keep drying the rivulets after the last drop is gone
	if live != _map_live:
		_map_live = live
		var mode := SubViewport.UPDATE_ALWAYS if live else SubViewport.UPDATE_DISABLED
		_trail_vp.render_target_update_mode = mode
		_drop_vp.render_target_update_mode = mode
	if not live: return
	var sz := Vector2i(maxi(64, int(vs.x * MAP_SCALE)), maxi(36, int(vs.y * MAP_SCALE)))
	if _drop_vp.size != sz:
		_drop_vp.size = sz
		_trail_vp.size = sz
	if _clear_left > 0:
		_clear_left -= 1
		if _clear_left == 0: _trail_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	var h := float(sz.y)
	# drying: a rivulet lasts RIVULET_LIFE (less in the wind); frozen while paused (dt 0)
	_dry_mat.set_shader_parameter("keep", exp(-dt / (RIVULET_LIFE / (1.0 + 2.0 * wind))))
	var tb: PackedFloat32Array = drops.TrailBuffer(h)
	_trail_mm.visible_instance_count = 0
	_trail_mm.buffer = tb
	_trail_mm.visible_instance_count = drops.TrailCount()
	var db: PackedFloat32Array = drops.Buffer(h)
	_drop_mm.visible_instance_count = 0
	_drop_mm.buffer = db
	_drop_mm.visible_instance_count = n
	# test: BMX_LENS_DUMP=file.png saves the lens normal map once, 10 s in
	_dump_t += dt
	if _dump_t > 10.0 and _dump_t - dt <= 10.0 and Env.s("BMX_LENS_DUMP") != "":
		_drop_vp.get_texture().get_image().save_png(Env.s("BMX_LENS_DUMP"))
		print("LENS drops=%d rivulet_segments=%d wind=%.2f flow=(%.2f, %.2f) cam_v=%.1f map=%s" % [n, drops.TrailCount(), wind, _flow.x, _flow.y, _cam_v.length(), str(_drop_vp.size)])

func apply(gm: ShaderMaterial, enabled: bool) -> void:
	var water := enabled and _map_live and _drop_vp != null
	gm.set_shader_parameter("lens_water", 1.0 if water else 0.0)
	if water: gm.set_shader_parameter("lens_map", _drop_vp.get_texture())
	var d := dust if enabled else 0.0
	gm.set_shader_parameter("lens_dust", d)
	if d > 0.003:
		gm.set_shader_parameter("lens_dust_tex", _dust_tex)
		gm.set_shader_parameter("lens_dust_col", Vector3(dust_col.r, dust_col.g, dust_col.b))