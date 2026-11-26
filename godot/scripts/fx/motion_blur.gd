class_name MotionBlur
extends CompositorEffect
## Camera motion blur (2026-11-26, user: Riders Republic-like "motion blur from the environment itself", not a fixed blur at
## the sides of the screen): shaders/post/motion_blur.glsl smears each pixel along Godot's motion vectors, before the
## tonemapper. Cost: a colour copy + one compute pass (12 taps where something moves). Knobs: LightLab "motion_blur"
## (shutter share, 0 = off) and "motion_max" (longest smear, px). Probe: BMX_MBLUR=0 turns it off.

var shutter := 0.5
var max_len := 40.0
var ok := false
var _rd: RenderingDevice
var _shader: RID
var _pipe: RID
var _cshader: RID
var _cpipe: RID
var _near: RID
var _lin: RID
var _copy: RID
var _size := Vector2i.ZERO

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	access_resolved_color = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	RenderingServer.call_on_render_thread(_create)

func _create() -> void:
	var sf: RDShaderFile = load("res://shaders/post/motion_blur.glsl")
	var sp := sf.get_spirv()
	if sp.compile_error_compute != "":
		push_error("motion blur: " + sp.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(sp)
	_pipe = _rd.compute_pipeline_create(_shader)
	var cf: RDShaderFile = load("res://shaders/post/motion_copy.glsl")
	var csp := cf.get_spirv()
	if csp.compile_error_compute != "":
		push_error("motion blur copy: " + csp.compile_error_compute)
		return
	_cshader = _rd.shader_create_from_spirv(csp)
	_cpipe = _rd.compute_pipeline_create(_cshader)
	var s := RDSamplerState.new()
	_near = _rd.sampler_create(s)
	s.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	_lin = _rd.sampler_create(s)
	ok = true

func _render_callback(_type: int, rdata: RenderData) -> void:
	if not ok or shutter <= 0.001: return
	var rsb := rdata.get_render_scene_buffers() as RenderSceneBuffersRD
	if rsb == null: return
	var size := rsb.get_internal_size()
	if size.x < 2 or size.y < 2: return
	var color := rsb.get_color_layer(0)
	var vel := rsb.get_velocity_layer(0)
	if not color.is_valid() or not vel.is_valid(): return
	if size != _size:
		if _copy.is_valid(): _rd.free_rid(_copy)
		var f := RDTextureFormat.new()
		f.width = size.x; f.height = size.y
		f.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		f.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		_copy = _rd.texture_create(f, RDTextureView.new(), [])
		_size = size
	var c0 := RDUniform.new(); c0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; c0.binding = 0; c0.add_id(color)
	var c1 := RDUniform.new(); c1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; c1.binding = 1; c1.add_id(_copy)
	var cset := UniformSetCacheRD.get_cache(_cshader, 0, [c0, c1])
	var u0 := RDUniform.new(); u0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE; u0.binding = 0
	u0.add_id(_lin); u0.add_id(_copy)
	var u1 := RDUniform.new(); u1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE; u1.binding = 1
	u1.add_id(_near); u1.add_id(vel)
	var u2 := RDUniform.new(); u2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE; u2.binding = 2
	u2.add_id(color)
	var set := UniformSetCacheRD.get_cache(_shader, 0, [u0, u1, u2])
	var pc := PackedFloat32Array([size.x, size.y, shutter, max_len]).to_byte_array()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _cpipe)
	_rd.compute_list_bind_uniform_set(cl, cset, 0)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_add_barrier(cl)
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	_rd.compute_list_bind_uniform_set(cl, set, 0)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, ceili(size.x / 8.0), ceili(size.y / 8.0), 1)
	_rd.compute_list_end()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		var rids: Array[RID] = [_copy, _near, _lin, _shader, _cshader]
		var dev := _rd
		RenderingServer.call_on_render_thread(func():
			for r in rids:
				if r.is_valid(): dev.free_rid(r))
