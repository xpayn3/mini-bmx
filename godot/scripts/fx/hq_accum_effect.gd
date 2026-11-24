class_name HqAccumEffect
extends CompositorEffect
## The GPU half of the HQ still (fx/hq_still.gd): keeps a running sum of the frames in an RGBA32F texture
## and writes the average back over the scene colour (HDR, before glow / tonemap). HqStill sets
## `mode` / `n` every frame on the main thread; the render thread reads them for that frame.

const MODE_OFF := -1
const MODE_ADD := 0
const MODE_SHOW := 1

var mode := MODE_OFF
var n := 0                     # samples already in the sum before this frame
var size := Vector2i.ZERO      # the render size the sum was made at (HqStill resets when it changes)
var ok := false

var _rd: RenderingDevice
var _shader: RID
var _pipe: RID
var _accum: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	RenderingServer.call_on_render_thread(_create)

func _create() -> void:
	var sf: RDShaderFile = load("res://shaders/hq_accum.glsl")
	var sp := sf.get_spirv()
	if sp.compile_error_compute != "":
		push_error("hq accum: %s" % sp.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(sp)
	_pipe = _rd.compute_pipeline_create(_shader)
	ok = true

func _resize(s: Vector2i) -> void:
	if _accum.is_valid(): _rd.free_rid(_accum)
	var f := RDTextureFormat.new()
	f.width = s.x; f.height = s.y
	f.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	_accum = _rd.texture_create(f, RDTextureView.new(), [])
	_rd.texture_clear(_accum, Color(0, 0, 0, 0), 0, 1, 0, 1)
	size = s

static func _img(b: int, t: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = b
	u.add_id(t)
	return u

func _render_callback(_type: int, rdata: RenderData) -> void:
	if not ok or mode == MODE_OFF: return
	var rsb := rdata.get_render_scene_buffers() as RenderSceneBuffersRD
	if rsb == null: return
	var s := rsb.get_internal_size()
	if s.x < 2 or s.y < 2: return
	if s != size:
		_resize(s)
		if mode == MODE_SHOW or n > 0: return   # the sum is gone: HqStill sees `size` change and starts over
	var color := rsb.get_color_layer(0)
	var pc := PackedFloat32Array([float(s.x), float(s.y), float(n), float(mode)]).to_byte_array()
	var set_ := UniformSetCacheRD.get_cache(_shader, 0, [_img(0, color), _img(1, _accum)])
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	_rd.compute_list_bind_uniform_set(cl, set_, 0)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, ceili(s.x / 8.0), ceili(s.y / 8.0), 1)
	_rd.compute_list_end()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		var rids: Array[RID] = [_accum, _pipe, _shader]
		var dev := _rd
		RenderingServer.call_on_render_thread(func():
			for r in rids:
				if r.is_valid(): dev.free_rid(r))
