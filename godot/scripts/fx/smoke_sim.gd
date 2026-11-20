class_name SmokeSim
extends Node3D
## Real dust simulation (no sprites): a 3D grid of air on the GPU (compute shaders in shaders/smoke/)
## that follows the rider. Every frame:
##   advect   - air velocity + dust density carried by the air (semi-Lagrangian), the box scrolled with
##              the rider, dust settles and thins, sources splatted in (wheel roost, landings, the bike's wake)
##   curl / confine - vorticity confinement: the rolling, billowing swirls
##   divergence / pressure (red-black Gauss-Seidel) / project - incompressible air: dust thrown into
##              the ground spreads sideways, a passing bike drags a swirling wake
##   light    - sunlight through the dust to every voxel (self-shadowing) + sky openness
## Drawn by raymarching that light volume (shaders/smoke/smoke_render.gdshader).
## The grid follows the ground: voxel height is measured from the terrain, so dust hugs slopes.
## Needs a RenderingDevice (Forward+ / Mobile); RideDust falls back to sprites without one.

const NX := 128
const NY := 32
const NZ := 128
const H := 0.2                    # metres per voxel -> 25.6 x 6.4 x 25.6 m
const SHADOW_K := 0.0               # dust shadow on the ground / bike behind it: off (light dust; it showed as a dark patch ahead of the bike)
const HM := 32                    # heightmap cells across the box
const HM_CELL := H * NX / HM      # 0.8 m; the box moves in whole heightmap cells
const MAX_SRC := 64
const PRESSURE_ITERS := 14
var ahead := 3.0                  # metres of box kept ahead of the rider (the rest trails behind: long dust trails)
const PASSES := ["advect", "curl", "confine", "divergence", "pressure", "project", "light", "occupancy"]
const BRICK := 8                  # voxels per occupancy cell (empty-space skipping)
const SRC_F := 20                 # floats per source: pos+r, vel+rate, blend/radial, colour, spin

## tuning
var density_fade := 0.07          # /s (low: the trail hangs in the air a long way back)
var vel_relax := 0.35             # /s back toward the wind
var rise := float(Env.s("BMX_SMOKE_RISE")) if Env.s("BMX_SMOKE_RISE") != "" else 0.55   # m/s the dust rises through the air (more when riding fast)
var vorticity := 0.9
var extinction := 0.6      # light, see-through dust: the ground shows through (was 3.0, then 0.9)
var turbulence := 6.5             # curl-noise swirl force
var turb_scale := 0.7             # 1/m: swirl size ~ 1.5 m
var disperse := 1.3               # /s: how fast dust mixes out into the air (turbulent diffusion)
var disperse_reach := 1.6         # voxels
var wisps := 1.15                 # noise erosion of the edges (render)
var _rise_env := Env.s("BMX_SMOKE_RISE") != ""

var ok := false
var terrain = null
var sun: DirectionalLight3D = null
var wind := Vector2.ZERO           # m/s
var dust_col := Color(0.78, 0.66, 0.52)
var amb_col := Color(0.5, 0.6, 0.78)
var sun_gain := 1.0   # Game: less at a low sun (dust between the camera and the sun lit up the whole screen)

var rd: RenderingDevice
var _st: Array[RID] = [RID(), RID()]
var _curl: RID
var _div: RID
var _pres: RID
var _light: RID
var _cm: Array[RID] = [RID(), RID()]   # dust colour mass, ping-pong with the state
var _colr: RID                         # dust colour for drawing
var _velr: RID                         # air velocity + density for the grit particles
var _colr3d: Texture3DRD
var vel3d: Texture3DRD
var _occ: RID
var _occ3d: Texture3DRD
var _sampler: RID
var _buf: RID
var _shader := {}
var _pipe := {}
var _sets := {}
var _cur := 0
var _sim_t := 0.0
var speed := 0.0                  # the rider's speed (smoothed): faster = a more turbulent wake

var origin := Vector2.ZERO
var _has_origin := false
var _dir := Vector2(0, -1)
var _hcache := {}
var _hm := PackedFloat32Array()
var _hm_min := 0.0; var _hm_max := 0.0   # height range of _hm (set by _rebuild_hmap)
var _hm_img: Image
var _hm_tex: ImageTexture
var _tex3d: Texture3DRD
var _mat: ShaderMaterial
var _box: MeshInstance3D
var _src := PackedFloat32Array()
var _n := 0
var _emit: Array = []             # short bursts: {p, v, r, rate, radial, blend, t}
var _idle := 1e9
var _last_focus := Vector3.INF
var _col_target := dust_col
var _drift := Vector3.ZERO
var _body: Array = []             # solid parts this frame: {p, v, r, spin}
## drawn by this compositor effect on the ride camera when it works (half-res + temporal: smooth and
## cheap); otherwise by the box mesh with smoke_render.gdshader. BMX_SMOKE_BOX=1 forces the box.
var compositor: SmokeCompositor = null
var cloud := Vector4(0, 0, 0, 1)  # atm_cloud (cloud shadows): drift xy, depth, shade at the rider

var _scol := Vector3(3, 2.8, 2.5)

## what the grit (fx/grit.gd) needs to find the ground / the light / the air in the box
func shading_inputs() -> Dictionary:
	return {hmap = _hm_tex, size_m = Vector3(NX * H, NY * H, NZ * H), hm_cells = float(HM), light = _tex3d,
		origin = Vector3(origin.x, 0, origin.y), sun_col = _scol, amb_col = Vector3(amb_col.r, amb_col.g, amb_col.b)}

## the bike / rider as solid parts for this frame: [{p, v, r, spin}] (world space)
func set_body(parts: Array) -> void:
	_body = parts

func _init() -> void:
	name = "SmokeSim"
	rd = RenderingServer.get_rendering_device()
	if rd == null: return
	_src.resize(MAX_SRC * SRC_F)
	_hm.resize((HM + 1) * (HM + 1))
	_hm_img = Image.create_empty(HM + 1, HM + 1, false, Image.FORMAT_RF)
	_hm_tex = ImageTexture.create_from_image(_hm_img)
	_tex3d = Texture3DRD.new()
	_occ3d = Texture3DRD.new()
	_colr3d = Texture3DRD.new()
	vel3d = Texture3DRD.new()
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/smoke/smoke_render.gdshader")
	_mat.render_priority = 3
	_mat.set_shader_parameter("hmap", _hm_tex)
	_mat.set_shader_parameter("smoke", _tex3d)
	_mat.set_shader_parameter("occ", _occ3d)
	_mat.set_shader_parameter("colv", _colr3d)
	_mat.set_shader_parameter("size_m", Vector3(NX * H, NY * H, NZ * H))
	_mat.set_shader_parameter("hm_cells", float(HM))
	_mat.set_shader_parameter("detail", detail_texture())
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = _mat
	_box = MeshInstance3D.new()
	_box.name = "smoke_volume"
	_box.mesh = bm
	_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box.visible = false
	add_child(_box)
	ok = true
	RenderingServer.call_on_render_thread(_gpu_create)
	if Env.s("BMX_SMOKE_BOX") == "":
		compositor = SmokeCompositor.new()

static var _detail: ImageTexture3D

## tiling 3D noise the renderer erodes the dust with (built once, synchronously)
static func detail_texture() -> ImageTexture3D:
	if _detail != null: return _detail
	var t0 := Time.get_ticks_msec()
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.045
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	var imgs := nz.get_seamless_image_3d(64, 64, 64, false, 0.1, true)
	_detail = ImageTexture3D.new()
	_detail.create(imgs[0].get_format(), 64, 64, 64, false, imgs)
	if Env.s("BMX_SMOKE_PROBE") != "": print("SMOKE detail noise %d ms" % (Time.get_ticks_msec() - t0))
	return _detail

# ---------------------------------------------------------------- sources (world space, this frame)
## a dust / air source for this frame: dust density added per second inside radius r (m), the air
## inside pulled toward vel (blend /s) plus pushed out radially (m/s)
## col: the dust's colour (sRGB; alpha 0 = the current tint); spin: rad/s about its centre (a wheel)
func add_source(p: Vector3, vel: Vector3, r: float, rate: float, blend := 6.0, radial := 0.0,
		col := Color(0, 0, 0, 0), spin := Vector3.ZERO, solid := false) -> void:
	if not ok or _n >= MAX_SRC: return
	var o := _n * SRC_F
	var c := (col if col.a > 0.0 else _col_target).srgb_to_linear()
	_src[o] = p.x; _src[o + 1] = p.y; _src[o + 2] = p.z; _src[o + 3] = r
	_src[o + 4] = vel.x; _src[o + 5] = vel.y; _src[o + 6] = vel.z; _src[o + 7] = rate
	_src[o + 8] = blend; _src[o + 9] = radial; _src[o + 10] = 0.0; _src[o + 11] = 0.0
	_src[o + 12] = c.r; _src[o + 13] = c.g; _src[o + 14] = c.b; _src[o + 15] = 0.0
	_src[o + 16] = spin.x; _src[o + 17] = spin.y; _src[o + 18] = spin.z; _src[o + 19] = 1.0 if solid else 0.0
	_n += 1
	if rate > 0.0: _idle = 0.0

## a source that keeps going for secs (a landing / crash cloud)
func burst(p: Vector3, vel: Vector3, r: float, rate: float, radial: float, secs := 0.2, col := Color(0, 0, 0, 0), blend := 7.0) -> void:
	if not ok: return
	_emit.append({p = p, v = vel, r = r, rate = rate, radial = radial, t = secs, blend = blend, col = col})
	if col.a > 0.0: tint(col)
	_idle = 0.0

## clear the air (new world / respawn far away)
func reset() -> void:
	_hcache.clear()
	_has_origin = false
	_emit.clear()
	_n = 0
	_last_focus = Vector3.INF

## the Dust tab sliders (Tune "Dust look" / "Dust trail"), read every frame so they apply live
func _read_tune() -> void:
	var t: Dictionary = Tune.v
	if t.is_empty(): return
	extinction = float(t.get("dustOpacity", extinction))
	wisps = float(t.get("dustWisps", wisps))
	if not _rise_env: rise = float(t.get("dustRise", rise))
	turbulence = float(t.get("dustSwirl", turbulence))
	turb_scale = float(t.get("dustSwirlSize", turb_scale))
	vorticity = float(t.get("dustCurl", vorticity))
	density_fade = float(t.get("dustFade", density_fade))
	disperse = float(t.get("dustSpread", disperse))
	vel_relax = float(t.get("dustWindCarry", vel_relax))
	ahead = float(t.get("dustAhead", ahead))

func tint(col: Color) -> void:
	_col_target = col

# ---------------------------------------------------------------- per frame
## focus: the rider (the box follows it), fwd: which way they're going
func step(dt: float, focus: Vector3, fwd: Vector3) -> void:
	if not ok: return
	dt = clampf(dt, 1.0 / 240.0, 1.0 / 30.0)
	_read_tune()
	for i in range(_emit.size() - 1, -1, -1):
		var e: Dictionary = _emit[i]
		add_source(e.p, e.v, e.r, e.rate, e.blend, e.radial, e.col)
		e.t -= dt
		if e.t <= 0.0: _emit.remove_at(i)
	if _last_focus != Vector3.INF:
		var bv := (focus - _last_focus) / dt
		if bv.length() < 40.0:
			speed += (bv.length() - speed) * (1.0 - exp(-dt * 3.0))
	_last_focus = focus
	# the bike and rider are solid in the air: air inside them moves with them (the pressure solve then
	# sends the air round them), and the wheels spin it - dust gets dragged, split and stirred
	for b in _body:
		add_source(b.p, b.v, b.r, 0.0, 40.0, 0.0, Color(0, 0, 0, 0), b.spin, true)
	_body = []
	_idle += dt
	if _idle > 14.0:   # nothing kicked up for a while: the air is clear, stop simulating
		_n = 0
		_box.visible = false
		if compositor != null: compositor.active = false
		return
	# the box: ahead of the rider along their heading, moved in whole heightmap cells
	var f2 := Vector2(fwd.x, fwd.z)
	if f2.length() > 0.1: _dir = _dir.lerp(f2.normalized(), 1.0 - exp(-dt * 1.2)).normalized()
	var ext := Vector2(NX * H, NZ * H)
	var center := Vector2(focus.x, focus.z) - _dir * (ext.x * 0.5 - ahead)
	var want := ((center - ext * 0.5) / HM_CELL).floor() * HM_CELL
	var shift := Vector2i.ZERO
	var clear := false
	if not _has_origin:
		clear = true
	elif want != origin:
		var s := (want - origin) / H
		shift = Vector2i(roundi(s.x), roundi(s.y))
		if absi(shift.x) >= NX or absi(shift.y) >= NZ:
			clear = true
			shift = Vector2i.ZERO
	if clear or want != origin:
		origin = want
		_has_origin = true
		_rebuild_hmap()
	# sources -> grid coordinates
	var bytes := PackedFloat32Array()
	bytes.resize(MAX_SRC * SRC_F)
	for i in _n:
		var o := i * SRC_F
		for k in SRC_F: bytes[o + k] = _src[o + k]
		var x := _src[o]; var y := _src[o + 1]; var z := _src[o + 2]
		bytes[o] = (x - origin.x) / H
		bytes[o + 1] = (y - _ground(x, z)) / H
		bytes[o + 2] = (z - origin.y) / H
	var n := _n
	_n = 0
	# shading inputs
	dust_col = dust_col.lerp(_col_target, 1.0 - exp(-dt * 2.0))
	var sdir := Vector3(0.4, 0.8, 0.3).normalized()
	var scol := Vector3(3, 2.8, 2.5)
	if sun != null and is_instance_valid(sun):
		sdir = sun.global_basis.z.normalized()
		var c := sun.light_color.srgb_to_linear() * sun.light_energy * sun_gain
		scol = Vector3(c.r, c.g, c.b)
	var mn := _hm_min
	var mx := _hm_max
	var bmin := Vector3(origin.x, mn - 0.3, origin.y)
	var bmax := Vector3(origin.x + ext.x, mx + NY * H + 0.3, origin.y + ext.y)
	_box.global_transform = Transform3D(Basis.from_scale(bmax - bmin), (bmin + bmax) * 0.5)
	var use_comp := compositor != null and compositor.ok
	_box.visible = not use_comp
	_mat.set_shader_parameter("origin", Vector3(origin.x, 0, origin.y))
	_mat.set_shader_parameter("box_min", bmin)
	_mat.set_shader_parameter("box_max", bmax)
	_mat.set_shader_parameter("shadow_k", SHADOW_K)
	_mat.set_shader_parameter("sun_dir", sdir)
	_mat.set_shader_parameter("sun_col", scol)
	_scol = scol
	_mat.set_shader_parameter("amb_col", Vector3(amb_col.r, amb_col.g, amb_col.b))
	var dc := dust_col.srgb_to_linear()
	_mat.set_shader_parameter("dust_col", Vector3(dc.r, dc.g, dc.b))
	_mat.set_shader_parameter("ext", extinction)
	_drift += Vector3(wind.x * 0.6, 0.12, wind.y * 0.6) * dt
	_mat.set_shader_parameter("drift", _drift)
	if use_comp:
		compositor.active = true
		compositor.params = {light = _tex3d, colv = _colr3d, occ = _occ3d, hmap = _hm_tex, detail = detail_texture(),
			origin = Vector3(origin.x, 0, origin.y), hm_cells = float(HM), size_m = Vector3(NX * H, NY * H, NZ * H),
			step = 0.08, ext = extinction, box_min = bmin, box_max = bmax, shadow_k = SHADOW_K, sun_dir = sdir,
			detail_amt = wisps, sun_col = scol, max_steps = 160.0, amb_col = Vector3(amb_col.r, amb_col.g, amb_col.b),
			dust_col = Vector3(dc.r, dc.g, dc.b), drift = _drift, cloud = cloud}
	RenderingServer.call_on_render_thread(_gpu_step.bind(dt, shift, clear, bytes.to_byte_array(), n, sdir))

func _ground(x: float, z: float) -> float:
	# bilinear in the heightmap, exactly like the renderer
	var gx := clampf((x - origin.x) / HM_CELL, 0.0, HM - 0.001)
	var gz := clampf((z - origin.y) / HM_CELL, 0.0, HM - 0.001)
	var i := int(gx); var k := int(gz)
	var fx := gx - i; var fz := gz - k
	var a := _hm[k * (HM + 1) + i]; var b := _hm[k * (HM + 1) + i + 1]
	var c := _hm[(k + 1) * (HM + 1) + i]; var d := _hm[(k + 1) * (HM + 1) + i + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func _rebuild_hmap() -> void:
	var ci := roundi(origin.x / HM_CELL)
	var ck := roundi(origin.y / HM_CELL)
	var used := {}
	for k in HM + 1:
		for i in HM + 1:
			var key := Vector2i(ci + i, ck + k)
			var hv: float
			if _hcache.has(key):
				hv = _hcache[key]
			else:
				hv = terrain.height(key.x * HM_CELL, key.y * HM_CELL) if terrain != null else 0.0
				_hcache[key] = hv
			used[key] = hv
			_hm[k * (HM + 1) + i] = hv
	if _hcache.size() > 6000: _hcache = used
	_hm_min = 1e9; _hm_max = -1e9
	for hv in _hm:
		_hm_min = minf(_hm_min, hv); _hm_max = maxf(_hm_max, hv)
	_hm_img.set_data(HM + 1, HM + 1, false, Image.FORMAT_RF, _hm.to_byte_array())
	_hm_tex.update(_hm_img)

# ---------------------------------------------------------------- GPU (render thread)
func _tex(fmt_id: int, dims := Vector3i(NX, NY, NZ)) -> RID:
	var f := RDTextureFormat.new()
	f.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	f.width = dims.x; f.height = dims.y; f.depth = dims.z
	f.format = fmt_id
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	var t := rd.texture_create(f, RDTextureView.new(), [])
	rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
	return t

func _u(type: int, b: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = b
	for id in ids: u.add_id(id)
	return u

func _img(b: int, t: RID) -> RDUniform: return _u(RenderingDevice.UNIFORM_TYPE_IMAGE, b, [t])
func _smp(b: int, t: RID) -> RDUniform: return _u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, b, [_sampler, t])

func _gpu_create() -> void:
	var F16 := RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	var F32 := RenderingDevice.DATA_FORMAT_R32_SFLOAT
	_st[0] = _tex(F16); _st[1] = _tex(F16)
	_curl = _tex(F16); _light = _tex(F16)
	_div = _tex(F32); _pres = _tex(F32)
	_cm[0] = _tex(F16); _cm[1] = _tex(F16)
	_colr = _tex(F16); _velr = _tex(F16)
	_occ = _tex(RenderingDevice.DATA_FORMAT_R16_SFLOAT, Vector3i(NX / BRICK, NY / BRICK, NZ / BRICK))
	var ss := RDSamplerState.new()
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_BORDER
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_BORDER
	ss.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_BORDER
	ss.border_color = RenderingDevice.SAMPLER_BORDER_COLOR_FLOAT_TRANSPARENT_BLACK
	_sampler = rd.sampler_create(ss)
	_buf = rd.storage_buffer_create(MAX_SRC * SRC_F * 4)
	for p in PASSES:
		var sf: RDShaderFile = load("res://shaders/smoke/%s.glsl" % p)
		var spirv := sf.get_spirv()
		if spirv.compile_error_compute != "":
			push_error("smoke %s: %s" % [p, spirv.compile_error_compute])
			ok = false
			return
		_shader[p] = rd.shader_create_from_spirv(spirv)
		_pipe[p] = rd.compute_pipeline_create(_shader[p])
	for q in 2:
		var o := 1 - q
		_sets["advect%d" % q] = rd.uniform_set_create([_smp(0, _st[q]), _img(1, _st[o]),
			_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [_buf]), _smp(3, _cm[q]), _img(4, _cm[o])], _shader.advect, 0)
		_sets["curl%d" % q] = rd.uniform_set_create([_img(0, _st[q]), _img(1, _curl)], _shader.curl, 0)
		_sets["confine%d" % q] = rd.uniform_set_create([_img(0, _st[q]), _img(1, _curl)], _shader.confine, 0)
		_sets["divergence%d" % q] = rd.uniform_set_create([_img(0, _st[q]), _img(1, _div), _img(2, _pres)], _shader.divergence, 0)
		_sets["project%d" % q] = rd.uniform_set_create([_img(0, _st[q]), _img(1, _pres)], _shader.project, 0)
		_sets["light%d" % q] = rd.uniform_set_create([_smp(0, _st[q]), _img(1, _light), _smp(2, _cm[q]),
			_img(3, _colr), _img(4, _velr)], _shader.light, 0)
		_sets["occupancy%d" % q] = rd.uniform_set_create([_smp(0, _st[q]), _img(1, _occ)], _shader.occupancy, 0)
	_sets["pressure"] = rd.uniform_set_create([_img(0, _pres), _img(1, _div)], _shader.pressure, 0)
	_tex3d.texture_rd_rid = _light
	_occ3d.texture_rd_rid = _occ
	_colr3d.texture_rd_rid = _colr
	vel3d.texture_rd_rid = _velr

func _disp(cl: int, pass_name: String, set_rid: RID, pcv: PackedFloat32Array, groups := Vector3i(NX / 8, NY / 4, NZ / 8)) -> void:
	rd.compute_list_bind_compute_pipeline(cl, _pipe[pass_name])
	rd.compute_list_bind_uniform_set(cl, set_rid, 0)
	if pcv.size() > 0:
		var b := pcv.to_byte_array()
		rd.compute_list_set_push_constant(cl, b, b.size())
	rd.compute_list_dispatch(cl, groups.x, groups.y, groups.z)
	rd.compute_list_add_barrier(cl)

func _gpu_step(dt: float, shift: Vector2i, clear: bool, src: PackedByteArray, n: int, sdir: Vector3) -> void:
	if not ok or not _pipe.has("light"): return
	if clear:
		rd.texture_clear(_st[0], Color(0, 0, 0, 0), 0, 1, 0, 1)
		rd.texture_clear(_st[1], Color(0, 0, 0, 0), 0, 1, 0, 1)
		rd.texture_clear(_cm[0], Color(0, 0, 0, 0), 0, 1, 0, 1)
		rd.texture_clear(_cm[1], Color(0, 0, 0, 0), 0, 1, 0, 1)
	var nb := n * SRC_F * 4
	if n > 0: rd.buffer_update(_buf, 0, nb, src.slice(0, nb))
	_sim_t += dt
	var _fast := clampf((speed - 3.0) / 9.0, 0.0, 1.0)   # 0 below ~11 km/h .. 1 at ~43 km/h
	var p := _cur
	var q := 1 - p
	var cl := rd.compute_list_begin()
	_disp(cl, "advect", _sets["advect%d" % p], PackedFloat32Array([dt, H, shift.x, shift.y,
		wind.x, wind.y, n, _sim_t, density_fade, vel_relax, rise * (1.0 + _fast * 1.6), 6.0,
		origin.x, origin.y, turbulence * (1.0 + _fast * 1.2), turb_scale,
		disperse * (1.0 + _fast * 0.6), disperse_reach * (1.0 + _fast * 0.5), 0, 0]))
	_disp(cl, "curl", _sets["curl%d" % q], PackedFloat32Array([dt, H, 0, 0]))
	_disp(cl, "confine", _sets["confine%d" % q], PackedFloat32Array([dt, H, vorticity, 0]))
	_disp(cl, "divergence", _sets["divergence%d" % q], PackedFloat32Array([dt, H, 0, 0]))
	for i in PRESSURE_ITERS:
		_disp(cl, "pressure", _sets.pressure, PackedFloat32Array([0, H, 1.6, 0]))
		_disp(cl, "pressure", _sets.pressure, PackedFloat32Array([1, H, 1.6, 0]))
	_disp(cl, "project", _sets["project%d" % q], PackedFloat32Array([dt, H, 0, 0]))
	_disp(cl, "light", _sets["light%d" % q], PackedFloat32Array([sdir.x, sdir.y, sdir.z, extinction, H, 0, 0, 0]))
	_disp(cl, "occupancy", _sets["occupancy%d" % q], PackedFloat32Array([1, 0, 0, 0]), Vector3i(maxi(1, NX / BRICK / 4), maxi(1, NY / BRICK / 4), maxi(1, NZ / BRICK / 4)))
	rd.compute_list_end()
	_cur = q

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and ok:
		ok = false
		_tex3d.texture_rd_rid = RID()
		_occ3d.texture_rd_rid = RID()
		_colr3d.texture_rd_rid = RID()
		vel3d.texture_rd_rid = RID()
		var rids: Array[RID] = []
		rids.append_array(_st)
		rids.append_array(_cm)
		rids.append_array([_colr, _velr])
		rids.append_array([_curl, _div, _pres, _light, _occ, _sampler, _buf])
		for s in _shader.values(): rids.append(s)   # frees its pipelines + uniform sets too
		var dev := rd
		RenderingServer.call_on_render_thread(func():
			for r in rids:
				if r.is_valid(): dev.free_rid(r))
