class_name GrassField
extends Node3D
## A grass carpet over the whole landscape round the camera, drawn on the GPU (shaders/grass_field.gdshader).
##
## Nothing is stored per blade. Every chunk bakes two small images (TerrainChunkBuilder: `grass_h` = its ground
## heights, `grass_img` = its land colour + grass density in alpha: none on the trail / jumps, rock faces, sand,
## dunes, snow, water, sheds); this node copies the 5 x 5 chunks round the camera into two window textures
## (0.5 m texels, 240 m across) whenever the camera's chunk or the chunks there change.
## The blades are tiles of a fixed lattice (one MultiMesh per ring, an instance = a tile's world origin). Each
## blade's place on the lattice is a whole number, so its hash (size, lean, colour, whether it grows at all
## here) never changes as the tiles move with the camera. Rings: NEAR (dense, 3-part blades) and MID (sparse,
## wider single-triangle blades that face the camera), cross-faded by distance; past MID the ground's own
## colour (the same colour the blades are tinted with) carries on, so the land reads as grass all the way.
## Tiles out of view are skipped every frame (only a few hundred to test).
## Settings "grass": 0 off, 1 low, 2 medium, 3 high (`QUALITY`). `BMX_GRASS=0..3` overrides it for a test run.

const WIN_CHUNKS := 5                 # chunks across the window
const CHUNK := 48.0
const SEG := 96                       # texels per chunk side (= Terrain.seg; 0.5 m)
const TEX := WIN_CHUNKS * SEG + 1     # window texture size

## per quality: near spacing / tile / radius, mid spacing / tile / radius
const QUALITY := {
	1: {"ns": 0.16, "nt": 4.48, "nr": 16.0, "ms": 0.45, "mt": 9.0, "mr": 64.0},
	2: {"ns": 0.12, "nt": 3.84, "nr": 22.0, "ms": 0.40, "mt": 8.0, "mr": 90.0},
	3: {"ns": 0.10, "nt": 3.9, "nr": 26.0, "ms": 0.36, "mt": 9.0, "mr": 96.0},
}

static var _shader: Shader

var terrain
var quality := 0
var _q: Dictionary
var _img_c: Image
var _img_h: Image
var _tex_c: ImageTexture
var _tex_h: ImageTexture
var _win_k := Vector2i(1 << 30, 0)     # the window's centre chunk
var _win_sig := ""                     # which chunks were copied in
var _serial := -1
var _mat: ShaderMaterial
var _near: MultiMeshInstance3D
var _mid: MultiMeshInstance3D
var _tile_buf := {}                    # MultiMesh -> PackedFloat32Array (reused)
var _tile_prev := {}                   # MultiMesh -> [buffer last uploaded, its count]: unchanged = no upload
var _h_arr := PackedFloat32Array()     # the height window as floats (for the tiles' height range)
var _tile_h := {}                      # MultiMesh -> {tile Vector2i: Vector2(min, max) ground height}, per window
var probe := Env.s("BMX_GRASS_PROBE") != ""
var _probe_t := 0.0

# ---- trampled trail: where the tyres / a crashed body pressed the grass down. A window of TR x TR texels
# (TR_TEXEL m) round the rider; each texel holds (time it was pressed, direction it was pressed in, rad).
# The shader lays those blades down and lets them spring back over TRAMPLE_BACK s: nothing decays here.
const TR := 192
const TR_TEXEL := 0.25
const TR_EMPTY := -1.0e6
var _tr_img: Image
var _tr_tex: ImageTexture
var _tr_origin := Vector2(INF, INF)    # world xz of texel (0, 0)'s corner
var _tr_now := 0.0                     # the trail's own clock (stops in photo mode / pause)
var _tr_dirty := false
var _tr_up_ms := 0                     # when the trample texture was last uploaded (real time)
const TR_UPLOAD_MS := 33               # at most this often (192^2 RGBAF = 590 KB a go); the tyre covers the lag
var _tr_last := {}                     # stamp id -> last stamped point (strokes between frames have no gaps)


func _init(t) -> void:
	terrain = t
	name = "GrassField"
	process_priority = 1000   # after the camera has moved this frame
	process_mode = Node.PROCESS_MODE_ALWAYS   # photo mode / pause: the camera still moves


func _process(dt: float) -> void:
	if is_visible_in_tree():
		if not get_tree().paused:
			_tr_now += dt          # already game time (0 in photo mode, slow in crash slow motion)
		_mat.set_shader_parameter("trample_now", _tr_now)
		var now_ms := Time.get_ticks_msec()
		if _tr_dirty and now_ms - _tr_up_ms >= TR_UPLOAD_MS:
			_tr_tex.update(_tr_img)
			_tr_dirty = false
			_tr_up_ms = now_ms
		update(get_viewport().get_camera_3d())


## presses the grass down along the stroke from this id's last point to p (a tyre, a body part), in direction
## dir, r metres wide either side. Call every frame something rolls / slides through the grass.
func trample(id: int, p: Vector3, dir: Vector3, r: float) -> void:
	if quality == 0 or _tr_img == null:
		return
	var q := Vector2(p.x, p.z)
	_tr_recentre(q)
	var last: Vector2 = _tr_last.get(id, q)
	_tr_last[id] = q
	var seg := q - last
	if seg.length() > 3.0:      # teleported (respawn, get-up): start a new stroke
		seg = Vector2.ZERO
		last = q
	var d2 := Vector2(dir.x, dir.z)
	var ang := atan2(d2.y, d2.x) if d2.length() > 0.05 else atan2(seg.y, seg.x)
	var steps := clampi(ceili(seg.length() / (TR_TEXEL * 0.7)), 1, 24)
	var rt := r / TR_TEXEL
	var ri := ceili(rt)
	var wrote := false
	for s in steps:
		var c := (last + seg * float(s + 1) / steps - _tr_origin) / TR_TEXEL
		var cx := int(c.x)
		var cy := int(c.y)
		for y in range(cy - ri, cy + ri + 1):
			if y < 0 or y >= TR: continue
			for x in range(cx - ri, cx + ri + 1):
				if x < 0 or x >= TR: continue
				var k := Vector2(x + 0.5, y + 0.5).distance_to(c) / maxf(rt, 0.5)
				if k > 1.0: continue
				var want := 1.0 - k * 0.55
				var was := _tr_img.get_pixel(x, y)
				if was.r > _tr_now - 0.25 and was.b >= want - 0.02:
					continue   # pressed just now already (a standing / slow tyre): nothing new to show
				_tr_img.set_pixel(x, y, Color(_tr_now, ang, want, 0.0))
				wrote = true
	if wrote:
		_tr_dirty = true
	if probe and id == 1 and Engine.get_process_frames() % 60 == 0:
		var px := Vector2i(((q - _tr_origin) / TR_TEXEL).floor())
		print("TRAMPLE now=%.1f at=%s px=%s val=%s" % [_tr_now, q, px, _tr_img.get_pixelv(px.clamp(Vector2i.ZERO, Vector2i(TR - 1, TR - 1)))])


## forget the trail (a new world / respawn)
func clear_trample() -> void:
	if _tr_img:
		_tr_img.fill(Color(TR_EMPTY, 0, 0, 0))
		_tr_dirty = true
	_tr_last.clear()


## keeps the window round the rider: snapped to 8 m, content moved along with it
func _tr_recentre(q: Vector2) -> void:
	var span := TR * TR_TEXEL
	var rel := q - _tr_origin
	if rel.x > span * 0.25 and rel.x < span * 0.75 and rel.y > span * 0.25 and rel.y < span * 0.75:
		return
	var o := ((q - Vector2(span, span) * 0.5) / 8.0).floor() * 8.0
	if _tr_origin.x != INF:
		var sh := Vector2i(((_tr_origin - o) / TR_TEXEL).round())
		var old := _tr_img
		_tr_img = Image.create_empty(TR, TR, false, Image.FORMAT_RGBAF)
		_tr_img.fill(Color(TR_EMPTY, 0, 0, 0))
		if absi(sh.x) < TR and absi(sh.y) < TR:
			_tr_img.blit_rect(old, Rect2i(0, 0, TR, TR), sh)
	_tr_origin = o
	_mat.set_shader_parameter("trample_origin", o)
	_tr_dirty = true


func _ready() -> void:
	if _shader == null:
		_shader = load("res://shaders/grass_field.gdshader")
	_img_c = Image.create_empty(TEX, TEX, false, Image.FORMAT_RGBA8)
	_img_h = Image.create_empty(TEX, TEX, false, Image.FORMAT_RF)
	_tex_c = ImageTexture.create_from_image(_img_c)
	_tex_h = ImageTexture.create_from_image(_img_h)
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("grass_col", _tex_c)
	_mat.set_shader_parameter("grass_h", _tex_h)
	_mat.set_shader_parameter("win_size", float(TEX))
	_tr_img = Image.create_empty(TR, TR, false, Image.FORMAT_RGBAF)
	_tr_img.fill(Color(TR_EMPTY, 0, 0, 0))
	_tr_tex = ImageTexture.create_from_image(_tr_img)
	_mat.set_shader_parameter("trample", _tr_tex)
	_mat.set_shader_parameter("trample_span", TR * TR_TEXEL)
	_mat.set_shader_parameter("trample_origin", Vector2(1.0e7, 1.0e7))


## 0 = off (frees the meshes), 1..3 = the QUALITY rows
func set_quality(q: int) -> void:
	q = clampi(q, 0, 3)
	if q == quality:
		return
	quality = q
	for n in [_near, _mid]:
		if n: n.queue_free()
	_near = null
	_mid = null
	_tile_buf.clear()
	_tile_prev.clear()
	_tile_h.clear()
	visible = q > 0
	if q == 0:
		_set_ground_info()
		return
	_q = QUALITY[q]
	_near = _ring(_q.ns, _q.nt, true)
	_mid = _ring(_q.ms, _q.mt, false)
	_mat.set_shader_parameter("near_r", float(_q.nr))
	_mat.set_shader_parameter("mid_r", float(_q.mr))
	_mat.set_shader_parameter("near_spacing", float(_q.ns))
	_mat.set_shader_parameter("mid_spacing", float(_q.ms))
	_set_ground_info()


## the ground shader (world/ground.gdshader) reads the window too: under grass it shades the floor like the
## blades' roots so field and floor read as one. Global `grass_win_info` = (origin x, z, texel, grass radius; 0 = off).
func _set_ground_info() -> void:
	var on := quality > 0 and _win_sig != "" and is_inside_tree()
	RenderingServer.global_shader_parameter_set("grass_win", _tex_c)
	var h := WIN_CHUNKS / 2
	RenderingServer.global_shader_parameter_set("grass_win_info", Vector4(
		(_win_k.x - h) * CHUNK - CHUNK / 2, (_win_k.y - h) * CHUNK - CHUNK / 2, CHUNK / SEG,
		float(_q.mr) if on else 0.0))


func _enter_tree() -> void:
	if _tex_c != null:      # moved between viewports (the ride pre-built behind the intro)
		_set_ground_info()


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("grass_win_info", Vector4.ZERO)


func _ring(spacing: float, tile: float, near: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true          # x = 1 near ring, 0 mid ring
	mm.mesh = _tile_mesh(spacing, tile, near)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.name = "Near" if near else "Mid"
	add_child(mi)
	return mi


## one tile of blades on the lattice: VERTEX.xz = the blade's root (cell centre, tile space), y = 0;
## UV = (side -1..1, height 0..1). Near blades: 3 segments + tip (7 verts); mid: one triangle.
static func _tile_mesh(spacing: float, tile: float, near: bool) -> ArrayMesh:
	var n := roundi(tile / spacing)
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var rows := [0.0, 0.38, 0.72] if near else [0.0]
	var per := rows.size() * 2 + 1
	v.resize(n * n * per)
	uv.resize(n * n * per)
	var o := 0
	for iz in n:
		for ix in n:
			var p := Vector3((ix + 0.5) * spacing, 0.0, (iz + 0.5) * spacing)
			var b := o
			for t in rows:
				v[o] = p; uv[o] = Vector2(-1.0, t); o += 1
				v[o] = p; uv[o] = Vector2(1.0, t); o += 1
			v[o] = p; uv[o] = Vector2(0.0, 1.0); o += 1
			for s in rows.size() - 1:
				var a := b + s * 2
				idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
			var l := b + (rows.size() - 1) * 2
			idx.append_array([l, l + 1, l + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-2, -2000, -2), Vector3(tile + 4, 4000, tile + 4))
	return m


# ---------------- the data window ----------------

func _refresh_window(cam: Vector3) -> void:
	var ck := Vector2i(roundi(cam.x / CHUNK), roundi(cam.z / CHUNK))
	var moved := false
	if _win_k.x == 1 << 30 or absf(cam.x - _win_k.x * CHUNK) > CHUNK * 0.75 or absf(cam.z - _win_k.y * CHUNK) > CHUNK * 0.75:
		_win_k = ck
		moved = true
	if not moved and terrain.chunk_serial == _serial:
		return
	_serial = terrain.chunk_serial
	var h := WIN_CHUNKS / 2
	var sig := PackedByteArray()
	sig.resize(WIN_CHUNKS * WIN_CHUNKS)
	for j in WIN_CHUNKS:
		for i in WIN_CHUNKS:
			var c = terrain.chunks.get(_win_k + Vector2i(i - h, j - h))
			sig[j * WIN_CHUNKS + i] = 1 if c != null and c.has("grass_img") else 0
	var s := "%d,%d:%s" % [_win_k.x, _win_k.y, sig.hex_encode()]
	if s == _win_sig:
		return
	_win_sig = s
	var t0 := Time.get_ticks_usec()
	_img_c.fill(Color(0, 0, 0, 0))
	_img_h.fill(Color(-1000, 0, 0, 0))
	for j in WIN_CHUNKS:
		for i in WIN_CHUNKS:
			var c = terrain.chunks.get(_win_k + Vector2i(i - h, j - h))
			if c == null or not c.has("grass_img"):
				continue
			var gi: Image = c["grass_img"]
			var gh: Image = c["grass_h"]
			_img_c.blit_rect(gi, Rect2i(Vector2i.ZERO, gi.get_size()), Vector2i(i * SEG, j * SEG))
			_img_h.blit_rect(gh, Rect2i(Vector2i.ZERO, gh.get_size()), Vector2i(i * SEG, j * SEG))
	_tex_c.update(_img_c)
	_tex_h.update(_img_h)
	_h_arr = _img_h.get_data().to_float32_array()
	_tile_h.clear()
	# texel (0, 0) sits on the window's first grid point
	_mat.set_shader_parameter("win_origin", Vector2((_win_k.x - h) * CHUNK - CHUNK / 2, (_win_k.y - h) * CHUNK - CHUNK / 2))
	_mat.set_shader_parameter("texel", CHUNK / SEG)
	_set_ground_info()
	if probe:
		print("GRASS window %s copied in %.2f ms" % [s.substr(0, 24), (Time.get_ticks_usec() - t0) / 1000.0])


# ---------------- per frame ----------------

func update(cam: Camera3D) -> void:
	if quality == 0 or cam == null:
		return
	var cp := cam.global_position
	_refresh_window(cp)
	# the rings centre where the camera looks: a high camera (trail, drone) sees the ground well ahead of
	# itself, and the dense ring there; a camera low over the ground keeps them round itself
	var ground: float = terrain.height(cp.x, cp.z)
	var fwd := -cam.global_basis.z
	var flat := Vector2(fwd.x, fwd.z)
	var rc := Vector2(cp.x, cp.z)
	if flat.length() > 0.05 and not is_nan(ground):
		rc += flat.normalized() * clampf((cp.y - ground) * 1.3, 0.0, _q.nr + 4.0)
	_mat.set_shader_parameter("ring_centre", rc)
	var c3 := Vector3(rc.x, cp.y, rc.y)
	var planes := cam.get_frustum()
	var nn := _place(_near, c3, planes, _q.nt, 0.0, _q.nr + 1.0, 1.0, ground)
	var nm := _place(_mid, c3, planes, _q.mt, _q.nr - 7.0, _q.mr + 1.0, 0.0, ground)
	if probe:
		_probe_t += get_process_delta_time()
		if _probe_t > 1.0:
			_probe_t = 0.0
			print("GRASS tiles near=%d mid=%d blades=%d" % [nn, nm,
				nn * roundi(_q.nt / _q.ns) ** 2 + nm * roundi(_q.mt / _q.ms) ** 2])


## puts the ring's tiles that reach r0..r1 (horizontal distance from the camera) and touch the view into its
## MultiMesh; returns how many
func _place(mi: MultiMeshInstance3D, cp: Vector3, planes: Array, tile: float, r0: float, r1: float, ring: float, ground: float) -> int:
	var mm := mi.multimesh
	var n := ceili(r1 / tile) + 1
	var cap := (2 * n + 1) * (2 * n + 1)
	if mm.instance_count < cap:
		mm.instance_count = cap
	var buf: PackedFloat32Array = _tile_buf.get(mm, PackedFloat32Array())
	if buf.size() != cap * 16:
		buf.resize(cap * 16)
	var tx0 := floori(cp.x / tile)
	var tz0 := floori(cp.z / tile)
	var hy := ground if not is_nan(ground) else cp.y
	var c := 0
	var half := tile * 0.5
	var rad := half * 1.4143
	var hcache: Dictionary = _tile_h.get(mm, {})
	_tile_h[mm] = hcache
	var have_h := _h_arr.size() == TEX * TEX
	var ex := half + 1.0   # + blades leaning / blowing over the tile's edge
	for dz in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var ox := (tx0 + dx) * tile
			var oz := (tz0 + dz) * tile
			var mx := ox + half
			var mz := oz + half
			var dd := Vector2(mx - cp.x, mz - cp.z).length()
			if dd - rad > r1 or dd + rad < r0:
				continue
			# view test: the tile as a box from its lowest ground to its highest blade tip (heights from the window);
			# without the window yet, a sphere round the camera's ground height +-30 m
			var inside := true
			if have_h:
				var tk := Vector2i(tx0 + dx, tz0 + dz)
				var hr = hcache.get(tk)
				if hr == null:
					hr = _tile_range(ox, oz, tile)
					hcache[tk] = hr
				if hr.x > hr.y:
					continue   # no ground data under it: no grass either
				var cy: float = (hr.x + hr.y) * 0.5 + 0.5
				var ey: float = (hr.y - hr.x) * 0.5 + 1.5   # 0.5 under the ground .. ~1.5 m blade tips over it
				var centre := Vector3(mx, cy, mz)
				for p in planes:
					var pl := p as Plane
					var r := absf(pl.normal.x) * ex + absf(pl.normal.y) * ey + absf(pl.normal.z) * ex
					if pl.distance_to(centre) > r:
						inside = false
						break
			else:
				var centre := Vector3(mx, hy, mz)
				var r := rad + 30.0
				for p in planes:
					if (p as Plane).distance_to(centre) > r:
						inside = false
						break
			if not inside:
				continue
			var b := c * 16
			buf[b] = 1.0; buf[b + 1] = 0.0; buf[b + 2] = 0.0; buf[b + 3] = ox
			buf[b + 4] = 0.0; buf[b + 5] = 1.0; buf[b + 6] = 0.0; buf[b + 7] = 0.0
			buf[b + 8] = 0.0; buf[b + 9] = 0.0; buf[b + 10] = 1.0; buf[b + 11] = oz
			buf[b + 12] = ring; buf[b + 13] = 0.0; buf[b + 14] = 0.0; buf[b + 15] = 0.0
			c += 1
	_tile_buf[mm] = buf
	# same tiles as last frame (camera within a tile, view barely turned): nothing to upload
	var prev: Array = _tile_prev.get(mm, [])
	if prev.is_empty() or prev[1] != c or prev[0] != buf:
		mm.buffer = buf
		mm.visible_instance_count = c
		_tile_prev[mm] = [buf.duplicate(), c]
	return c


## lowest / highest ground height under a tile (3 x 3 samples of the height window + 3 m margin for what lies
## between them); x > y = no ground data there
func _tile_range(ox: float, oz: float, tile: float) -> Vector2:
	var h := WIN_CHUNKS / 2
	var wx := (_win_k.x - h) * CHUNK - CHUNK / 2
	var wz := (_win_k.y - h) * CHUNK - CHUNK / 2
	var tx := CHUNK / SEG
	var lo := INF
	var hi := -INF
	for j in 3:
		for i in 3:
			var px := clampi(roundi((ox + tile * 0.5 * i - wx) / tx), 0, TEX - 1)
			var pz := clampi(roundi((oz + tile * 0.5 * j - wz) / tx), 0, TEX - 1)
			var v := _h_arr[pz * TEX + px]
			if v < -900.0:
				continue
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if lo > hi:
		return Vector2(1.0, 0.0)
	return Vector2(lo - 3.0, hi + 3.0)
