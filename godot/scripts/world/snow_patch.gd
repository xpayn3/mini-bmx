class_name SnowPatch
extends MeshInstance3D
## Real snow round the rider (2026-11-27, user: "real accumulated snow, 20 cm, that we trample when riding").
## The ground mesh (0.25 / 0.5 m) carries the snow's thickness everywhere (ground.gdshader lifts it by DEPTH x the bake's
## snow G), but it is far too coarse for a tyre's trench. So round the rider a fine grid (CELL ~6 cm, SIZE m across) draws
## the snow instead, the way the snow games do it (a deformable heightfield that follows the player): its height = the
## ground (the chunks' 0.5 m heights, the same ones the grass uses) + DEPTH x the snow's depth, cut down to a packed
## floor wherever a tyre (or a shoe) has pressed a print into the rut field (world/ruts.gd: the prints' signed edge
## distance, 5 cm cells, ~88 m window), with a little snow pushed up on each side. The ground hands its deep snow over to
## it by a screen-door pattern (global `snow_patch`, both shaders), so every pixel is drawn once.
## The trenches live as long as the prints (the rut field keeps ~2 km of ride); past the patch the ground shader still
## shows them as prints. Physics: the bike rides the ground under the snow; untrodden snow drags (BikePhysics.snow_k).
## BMX_OLD_SNOW=1 = none (Terrain.OLD_SNOW), BMX_SNOW_PATCH=0 = no patch (the ground's lifted snow only).

const DEPTH := 0.2         # m of snow where the bake's G = 1 (ground.gdshader snow_depth)
const SIZE := 22.0         # m across
const CELLS := 440         # grid cells across (5 cm = the rut field's cells: a vertex on every print texel, no sawtooth)
const WIN := 3             # chunks across the data window (3 x 48 m: the patch never leaves the middle one's ring)

var game
var _mat: ShaderMaterial
var _img_h: Image
var _img_s: Image
var _tex_h: ImageTexture
var _tex_s: ImageTexture
var _win_k := Vector2i(1 << 30, 0)
var _serial := -1
var _has_snow := false

func _init(g) -> void:
	game = g
	name = "SnowPatch"
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	pm.subdivide_width = CELLS - 1
	pm.subdivide_depth = CELLS - 1
	mesh = pm
	custom_aabb = AABB(Vector3(-SIZE, -3000, -SIZE), Vector3(SIZE * 2, 6000, SIZE * 2))
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/snow_patch.gdshader")
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	layers = 1 | Terrain.GROUND_LAYER
	var n := WIN * 96 + 1
	_img_h = Image.create_empty(n, n, false, Image.FORMAT_RF)
	_img_s = Image.create_empty(n, n, false, Image.FORMAT_RG8)
	_tex_h = ImageTexture.create_from_image(_img_h)
	_tex_s = ImageTexture.create_from_image(_img_s)
	_mat.set_shader_parameter("win_h", _tex_h)
	_mat.set_shader_parameter("win_s", _tex_s)
	_mat.set_shader_parameter("depth", DEPTH)
	_mat.set_shader_parameter("cell", SIZE / CELLS)
	top_level = true
	visible = false


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("snow_patch", Vector4.ZERO)


## the 3 x 3 chunks round the rider: their ground heights (grass_h, 0.5 m) and snow (snow_img: R cover, G depth)
func _refresh(px: float, pz: float) -> void:
	var t = game.terrain
	var S: float = Terrain.SIZE
	var ck := Vector2i(roundi(px / S), roundi(pz / S))
	if ck == _win_k and t.chunk_serial == _serial:
		return
	_win_k = ck
	_serial = t.chunk_serial
	_img_h.fill(Color(-1000, 0, 0, 0))
	_img_s.fill(Color(0, 0, 0, 0))
	_has_snow = false
	var h := WIN / 2
	for j in WIN:
		for i in WIN:
			var c = t.chunks.get(ck + Vector2i(i - h, j - h))
			if c == null or not c.has("grass_h"):
				continue
			var gh: Image = c["grass_h"]
			_img_h.blit_rect(gh, Rect2i(Vector2i.ZERO, gh.get_size()), Vector2i(i * 96, j * 96))
			var si = c.get("snow_img")
			if si != null:
				var s0: Image = si
				if s0.has_mipmaps():
					s0 = s0.duplicate()
					s0.clear_mipmaps()
				_img_s.blit_rect(s0, Rect2i(Vector2i.ZERO, s0.get_size()), Vector2i(i * 96, j * 96))
				_has_snow = true
	_tex_h.update(_img_h)
	_tex_s.update(_img_s)
	# texel (0, 0) = the window's first grid node
	_mat.set_shader_parameter("win_origin", Vector2((ck.x - h) * S - S / 2, (ck.y - h) * S - S / 2))
	_mat.set_shader_parameter("win_texel", S / 96.0)


func _process(_dt: float) -> void:
	if game == null or game.phys == null or game.terrain == null:
		return
	var px: float = game.phys.x
	var pz: float = game.phys.z
	_refresh(px, pz)
	visible = _has_snow
	if not _has_snow:
		RenderingServer.global_shader_parameter_set("snow_patch", Vector4.ZERO)
		return
	# whole cells only: the grid's vertices never slide over the snow (no swimming)
	var c := SIZE / CELLS
	# (+ half a cell: the vertices land on the rut field's texel centres)
	var cx := roundf(px / c) * c + c * 0.5
	var cz := roundf(pz / c) * c + c * 0.5
	global_position = Vector3(cx, 0.0, cz)
	RenderingServer.global_shader_parameter_set("snow_patch", Vector4(cx, cz, SIZE * 0.5, 1.0))
