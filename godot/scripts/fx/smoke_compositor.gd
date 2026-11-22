class_name SmokeCompositor
extends CompositorEffect
## Draws the dust simulation (fx/smoke_sim.gd) as a compositor effect on the ride camera, instead of the
## box mesh: smooth and cheaper.
##   1 march (half resolution): the raymarch of shaders/smoke/smoke_render.gdshader, ported to compute
##   2 temporal: blended with last frame (reprojected, clamped): the per-frame step jitter and the
##     rotating sub-pixel average out -> no grain, a quarter of the pixels to march
##   3 composite (full resolution): depth-aware upsample over the scene (dust + its shadow)
## SmokeSim fills `params` every frame; `active` = there is dust to draw.

const PASSES := ["smoke_march", "smoke_taa", "smoke_comp"]
const HISTORY := 0.14             # weight of the newest frame
const UBO_FLOATS := 92

var params := {}
var active := false
var ok := false

var _rd: RenderingDevice
var _shader := {}
var _pipe := {}
var _lin: RID
var _near: RID
var _rep: RID
var _ubo: RID
var _half := Vector2i.ZERO
var _dust: RID
var _dist: RID
var _hist: Array[RID] = [RID(), RID()]
var _cur := 0
var _frame := 0
var _prev_vp := Projection.IDENTITY
var _prev_cam := Transform3D.IDENTITY
var _has_prev := false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	RenderingServer.call_on_render_thread(_create)

func _sampler(filter: int, repeat: int) -> RID:
	var s := RDSamplerState.new()
	s.mag_filter = filter
	s.min_filter = filter
	s.repeat_u = repeat; s.repeat_v = repeat; s.repeat_w = repeat
	return _rd.sampler_create(s)

func _create() -> void:
	for p in PASSES:
		var sf: RDShaderFile = load("res://shaders/smoke/%s.glsl" % p)
		var sp := sf.get_spirv()
		if sp.compile_error_compute != "":
			push_error("smoke compositor %s: %s" % [p, sp.compile_error_compute])
			return
		_shader[p] = _rd.shader_create_from_spirv(sp)
		_pipe[p] = _rd.compute_pipeline_create(_shader[p])
	_lin = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_near = _sampler(RenderingDevice.SAMPLER_FILTER_NEAREST, RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE)
	_rep = _sampler(RenderingDevice.SAMPLER_FILTER_LINEAR, RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT)
	_ubo = _rd.uniform_buffer_create(UBO_FLOATS * 4)
	ok = true

func _tex2d(size: Vector2i) -> RID:
	var f := RDTextureFormat.new()
	f.width = size.x; f.height = size.y
	f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var t := _rd.texture_create(f, RDTextureView.new(), [])
	_rd.texture_clear(t, Color(0, 0, 0, 0), 0, 1, 0, 1)
	return t

func _resize(half: Vector2i) -> void:
	for t in [_dust, _dist, _hist[0], _hist[1]]:
		if t.is_valid(): _rd.free_rid(t)
	_dust = _tex2d(half); _dist = _tex2d(half)
	_hist[0] = _tex2d(half); _hist[1] = _tex2d(half)
	_half = half
	_has_prev = false

static func _u(type: int, b: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = b
	for id in ids: u.add_id(id)
	return u

func _smp(b: int, s: RID, t: RID) -> RDUniform: return _u(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, b, [s, t])
func _img(b: int, t: RID) -> RDUniform: return _u(RenderingDevice.UNIFORM_TYPE_IMAGE, b, [t])

static func _put_proj(a: PackedFloat32Array, o: int, p: Projection) -> void:
	for c in 4:
		var v: Vector4 = p[c]
		a[o + c * 4] = v.x; a[o + c * 4 + 1] = v.y; a[o + c * 4 + 2] = v.z; a[o + c * 4 + 3] = v.w

static func _put4(a: PackedFloat32Array, o: int, v: Vector3, w: float) -> void:
	a[o] = v.x; a[o + 1] = v.y; a[o + 2] = v.z; a[o + 3] = w

var _dbg := 0
var _probe := OS.get_environment("BMX_SMOKE_PROBE") != ""   # read once: the callback runs every frame on the render thread
func _dbgp(m: String) -> void:
	if _probe and _dbg < 40:
		_dbg += 1
		print("SMOKECOMP ", m)

func _render_callback(_type: int, rdata: RenderData) -> void:
	if _probe: _dbgp("cb ok=%s active=%s params=%d" % [ok, active, params.size()])
	if not ok or not active or params.is_empty():
		_has_prev = false
		return
	var rsb := rdata.get_render_scene_buffers() as RenderSceneBuffersRD
	var sd := rdata.get_render_scene_data() as RenderSceneDataRD
	if rsb == null or sd == null: return
	var size := rsb.get_internal_size()
	if size.x < 2 or size.y < 2: return
	var half := Vector2i((size.x + 1) / 2, (size.y + 1) / 2)
	if half != _half: _resize(half)
	var color := rsb.get_color_layer(0)
	var depth := rsb.get_depth_layer(0)
	var light: RID = (params.light as Texture3DRD).texture_rd_rid
	var colv: RID = (params.colv as Texture3DRD).texture_rd_rid
	var occ: RID = (params.occ as Texture3DRD).texture_rd_rid
	if not (light.is_valid() and colv.is_valid() and occ.is_valid()):
		_dbgp("sim textures not valid"); return
	var hmap := RenderingServer.texture_get_rd_texture((params.hmap as Texture).get_rid())
	var detail := RenderingServer.texture_get_rd_texture((params.detail as Texture).get_rid())
	if not (hmap.is_valid() and detail.is_valid()):
		_dbgp("hmap/detail not valid %s %s" % [hmap, detail]); return
	if _probe: _dbgp("draw size=%s color=%s depth=%s" % [size, color, depth])

	# already Godot's RD projection (depth 0..1 reversed, y flipped)
	var proj := sd.get_cam_projection()
	var cam := sd.get_cam_transform()
	var vp := proj * Projection(cam.affine_inverse())
	var k := HISTORY
	if not _has_prev or cam.origin.distance_to(_prev_cam.origin) > 3.0: k = 1.0
	var a := PackedFloat32Array()
	a.resize(UBO_FLOATS)
	_put_proj(a, 0, proj.inverse())
	_put_proj(a, 16, Projection(cam))
	_put_proj(a, 32, _prev_vp if _has_prev else vp)
	var o := 48
	a[o] = params.origin.x; a[o + 1] = params.origin.z; a[o + 2] = params.hm_cells; a[o + 3] = float(_frame); o += 4
	_put4(a, o, params.size_m, params.step); o += 4
	_put4(a, o, params.box_min, params.ext); o += 4
	_put4(a, o, params.box_max, params.shadow_k); o += 4
	_put4(a, o, params.sun_dir, params.detail_amt); o += 4
	_put4(a, o, params.sun_col, params.max_steps); o += 4
	_put4(a, o, params.amb_col, k); o += 4
	_put4(a, o, params.dust_col, float(params.get("fade", 0.0))); o += 4   # w: fade-out before the sim stops
	_put4(a, o, params.drift, 0.0); o += 4
	var cv: Vector4 = params.cloud
	a[o] = cv.x; a[o + 1] = cv.y; a[o + 2] = cv.z; a[o + 3] = cv.w; o += 4
	a[o] = size.x; a[o + 1] = size.y; a[o + 2] = half.x; a[o + 3] = half.y
	var bytes := a.to_byte_array()
	_rd.buffer_update(_ubo, 0, bytes.size(), bytes)
	var ubo := _u(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [_ubo])

	var hcur: RID = _hist[_cur]
	var hprev: RID = _hist[1 - _cur]
	var s_march := UniformSetCacheRD.get_cache(_shader.smoke_march, 0, [ubo, _smp(1, _near, depth), _smp(2, _lin, light),
		_smp(3, _lin, colv), _smp(4, _near, occ), _smp(5, _lin, hmap), _smp(6, _rep, detail), _img(7, _dust), _img(8, _dist)])
	var s_taa := UniformSetCacheRD.get_cache(_shader.smoke_taa, 0, [ubo, _img(1, _dust), _img(2, _dist), _smp(3, _lin, hprev), _img(4, hcur)])
	var s_comp := UniformSetCacheRD.get_cache(_shader.smoke_comp, 0, [ubo, _smp(1, _near, depth), _smp(2, _lin, hcur), _img(3, _dist), _img(4, color)])
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe.smoke_march)
	_rd.compute_list_bind_uniform_set(cl, s_march, 0)
	_rd.compute_list_dispatch(cl, ceili(half.x / 8.0), ceili(half.y / 8.0), 1)
	_rd.compute_list_add_barrier(cl)
	_rd.compute_list_bind_compute_pipeline(cl, _pipe.smoke_taa)
	_rd.compute_list_bind_uniform_set(cl, s_taa, 0)
	_rd.compute_list_dispatch(cl, ceili(half.x / 8.0), ceili(half.y / 8.0), 1)
	_rd.compute_list_add_barrier(cl)
	_rd.compute_list_bind_compute_pipeline(cl, _pipe.smoke_comp)
	_rd.compute_list_bind_uniform_set(cl, s_comp, 0)
	_rd.compute_list_dispatch(cl, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()
	_cur = 1 - _cur
	_frame += 1
	_prev_vp = vp
	_prev_cam = cam
	_has_prev = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		var rids: Array[RID] = [_dust, _dist, _hist[0], _hist[1], _lin, _near, _rep, _ubo]
		for s in _shader.values(): rids.append(s)
		var dev := _rd
		RenderingServer.call_on_render_thread(func():
			for r in rids:
				if r.is_valid(): dev.free_rid(r))
