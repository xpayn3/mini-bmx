class_name WaterWake
extends RefCounted
## The water's wake: the rider's tyres, landings and crashes push the surface and the ripples run out across
## the lake (compute shader shaders/water_wake.glsl, a wave-equation height field on the GPU). One 320 x 320
## texture of 15 cm cells (48 m) that follows the rider; TerrainWater hands it to water.gdshader as `u_wake`.
## One dispatch of 65k texels per step, a step 60 times a second, and nothing runs while the water is quiet.
## Needs a RenderingDevice (Forward+ / Mobile); without one `ok` stays false and the water is as it was.

const N := 320
const CELL := 0.15                # finer cells: tyre-sized ripples
const SPAN := N * CELL            # 48 m
const STEP_DT := 1.0 / 60.0
const MAX_STEPS := 2
const MAX_SRC := 32
const WAVE_C := 1.8               # m/s the ripples travel: a rider at 8 m/s leaves a V about 13 deg half-angle, like a boat's
const DAMP := 0.9                 # /s
const IDLE_STOP := 9.0            # s with nothing pushed: the water has settled, stop stepping

var ok := false
var tex: Texture2DRD
var centre := Vector2.ZERO        # world metres of the window's middle (for the shader's edge fade)

var rd: RenderingDevice
var _t: Array[RID] = [RID(), RID()]
var _buf: RID
var _shader: RID
var _pipe: RID
var _sets: Array[RID] = [RID(), RID()]
var _cur := 0
var _src := PackedFloat32Array()
var _n := 0
var _acc := 0.0
var _idle := 1e9
var _cc := Vector2i.ZERO
var _probe := Env.s("BMX_WAKE_PROBE") != ""
var _pr_t := 0.0
var _pr_steps := 0
var _pr_src := 0
var _pr_read := 0
var _pr_amt := 0.0
var _src_max := 0.0


func _init() -> void:
	if Env.s("BMX_WAKE") == "0": return
	rd = RenderingServer.get_rendering_device()
	if rd == null: return
	tex = Texture2DRD.new()
	_src.resize(MAX_SRC * 4)
	ok = true
	if _probe: print("WAKE created")
	RenderingServer.call_on_render_thread(_gpu_create)


## push the water down at p (world) for this frame: amount = the speed it is pushed to (m/s, ~0.05 a tyre
## in a frame, ~1 a hard landing), radius the size of the push in metres (>= 0.4 or the grid can't draw it)
func splash(p: Vector3, amount: float, radius := 0.5) -> void:
	if not ok or amount <= 0.0: return
	if _n >= MAX_SRC:   # a long frame: the oldest go
		for k in (MAX_SRC - 1) * 4: _src[k] = _src[k + 4]
		_n = MAX_SRC - 1
	var o := _n * 4
	if _probe and _n == 0: print("WAKE splash %.2f" % amount)
	_src_max = maxf(_src_max, amount)
	_src[o] = p.x; _src[o + 1] = p.z; _src[o + 2] = maxf(radius, 0.26); _src[o + 3] = amount
	_n += 1
	_idle = 0.0


## once per drawn frame while the water is on screen; focus = the rider
func step(dt: float, focus: Vector3) -> void:
	if not ok or not _pipe.is_valid(): return
	_idle += dt
	if _idle > IDLE_STOP:
		_n = 0
		_acc = 0.0
		return
	_acc += minf(dt, 0.1)
	var steps := 0
	while _acc >= STEP_DT and steps < MAX_STEPS:
		_acc -= STEP_DT
		steps += 1
	if steps == MAX_STEPS: _acc = minf(_acc, STEP_DT)
	if steps == 0: return   # pushes wait for the next step
	var nc := Vector2i(floori(focus.x / CELL), floori(focus.z / CELL))
	var n := _n
	var sb := _src.slice(0, n * 4).to_byte_array()
	_n = 0
	centre = Vector2(nc) * CELL
	if _probe:
		_pr_steps += steps; _pr_src += n; _pr_t += dt; _pr_amt = maxf(_pr_amt, _src_max)
		if _pr_t >= 2.0:
			print("WAKE steps/s=%.0f src/s=%.0f max_amount=%.3f centre=(%.0f,%.0f)" % [_pr_steps / _pr_t, _pr_src / _pr_t, _pr_amt, centre.x, centre.y]); _pr_amt = 0.0; _src_max = 0.0
			_pr_steps = 0; _pr_src = 0; _pr_t = 0.0
	RenderingServer.call_on_render_thread(_gpu_step.bind(steps, sb, n, _cc, nc))
	_cc = nc


# ---------------------------------------------------------------- GPU (render thread)
func _gpu_create() -> void:
	var f := RDTextureFormat.new()
	f.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	f.width = N; f.height = N
	f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	for i in 2:
		_t[i] = rd.texture_create(f, RDTextureView.new(), [])
		rd.texture_clear(_t[i], Color(0, 0, 0, 0), 0, 1, 0, 1)
	_buf = rd.storage_buffer_create(MAX_SRC * 16)
	var sf: RDShaderFile = load("res://shaders/water_wake.glsl")
	var spirv := sf.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("water wake: %s" % spirv.compile_error_compute)
		ok = false
		return
	_shader = rd.shader_create_from_spirv(spirv)
	_pipe = rd.compute_pipeline_create(_shader)
	for p in 2:
		_sets[p] = rd.uniform_set_create([_img(0, _t[p]), _img(1, _t[1 - p]),
			_u(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [_buf])], _shader, 0)
	tex.texture_rd_rid = _t[0]


func _u(type: int, b: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = b
	for id in ids: u.add_id(id)
	return u


func _img(b: int, t: RID) -> RDUniform:
	return _u(RenderingDevice.UNIFORM_TYPE_IMAGE, b, [t])


func _gpu_step(steps: int, src: PackedByteArray, n: int, old_c: Vector2i, new_c: Vector2i) -> void:
	if not ok or not _pipe.is_valid(): return
	if n > 0: rd.buffer_update(_buf, 0, n * 16, src)
	var coef := WAVE_C * WAVE_C / (CELL * CELL)
	var cl := rd.compute_list_begin()
	for k in steps:
		var oc := old_c if k == 0 else new_c
		var pc := PackedFloat32Array([STEP_DT, coef, DAMP, float(n if k == 0 else 0), oc.x, oc.y, new_c.x, new_c.y]).to_byte_array()
		rd.compute_list_bind_compute_pipeline(cl, _pipe)
		rd.compute_list_bind_uniform_set(cl, _sets[_cur], 0)
		rd.compute_list_set_push_constant(cl, pc, pc.size())
		rd.compute_list_dispatch(cl, N / 8, N / 8, 1)
		rd.compute_list_add_barrier(cl)
		_cur = 1 - _cur
	rd.compute_list_end()
	tex.texture_rd_rid = _t[_cur]
	if _probe:
		_pr_read += steps
		if _pr_read >= 120:
			_pr_read = 0
			var raw := rd.texture_get_data(_t[_cur], 0)
			var hm := 0.0; var fm := 0.0; var bad := 0
			var i := 0
			while i + 8 <= raw.size():
				var hv := raw.decode_half(i)
				if is_nan(hv) or is_inf(hv): bad += 1
				else: hm = maxf(hm, absf(hv))
				fm = maxf(fm, raw.decode_half(i + 4))
				i += 8 * 3
			print("WAKEFIELD max_h=%.4f m max_foam=%.2f bad=%d" % [hm, fm, bad])


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		var rids: Array[RID] = [_t[0], _t[1], _buf, _shader]   # freeing the shader frees its pipeline + uniform sets
		if tex != null: tex.texture_rd_rid = RID()
		var dev := rd
		ok = false
		RenderingServer.call_on_render_thread(func():
			for r in rids:
				if r.is_valid(): dev.free_rid(r))
