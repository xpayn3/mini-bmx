extends Node3D
## Bakes the far-view tree impostors (world/far_hills.gd): our card trees (card_tree.gd) rendered side-on, albedo only
## (unshaded, so the far shader lights them), on a transparent background, into one atlas of CELLS cells
## (assets/textures/tree_cards/impostors.png, BC7 + mipmaps on import) + impostors.json (per cell: kind, how much of the
## cell's height the tree fills, its width). Cells 0-1 pines, 2-3 leafy trees (whole trees, coloured: the backdrop);
## cells 4-5 pine crowns, 6-7 leafy crowns (crown only, white: the world chunks' billboard LOD, card_tree.gd, tinted by
## each tree's own colour; their json entries carry y0 / h / w = the cell's quad in the crown instance's own units).
## Re-run after changing the card trees:
##   godot --path godot res://tools/bake_tree_impostors.tscn

const CW := 256          # one cell
const CH := 512
const SS := 2            # rendered at this many times the cell size, then filtered down (smooth edges)
const OUT := "res://assets/textures/tree_cards/impostors.png"
## [kind, crown size (py for a pine, sc for a leafy tree), instance colour]
const VARIANTS := [["pine", 1.75, 0x3b7d4b], ["pine", 2.15, 0x2f6e45], ["leafy", 1.0, 0x6cb544], ["leafy", 1.2, 0x4f9a3a],
	["pine_crown", 0.0, 0xffffff], ["pine_crown", 1.9, 0xffffff], ["leafy_crown", 0.0, 0xffffff], ["leafy_crown", 2.3, 0xffffff]]
## crown cells: the crown at unit height (instance scale (A, 1, A)), its width squeezed by A into the 1 : 2 cell, so the
## billboard is stretched by the world instance's own x / y scale exactly like the 3D crown (crown v[1] = the yaw)
const PINE_A := 0.6
const BLOB_A := 0.533


func _ready() -> void:
	TerrainGeo.ensure()
	RenderingServer.global_shader_parameter_set("deco_fade", Vector4(0, 0, 100, 124))   # cards on at the origin
	var vp := SubViewport.new()
	vp.size = Vector2i(CW * SS, CH * SS)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	# (a long lens, not orthographic: the deco shaders take an orthographic camera for the sun's shadow pass, where the
	# solid crown stays on under its cards)
	var cam := Camera3D.new()
	cam.fov = 1.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 4000.0
	vp.add_child(cam)
	var atlas := Image.create(CW * VARIANTS.size(), CH, false, Image.FORMAT_RGBA8)
	var meta := []
	for i in VARIANTS.size():
		var v: Array = VARIANTS[i]
		var root := Node3D.new()
		vp.add_child(root)
		var col := TerrainGeo.lin(int(v[2]))
		var H: float
		var crown := {}   # crown cells: frame bottom / height in world units, the instance's scale
		if v[0] == "pine_crown":
			var smi := _one(root, TerrainGeo.MESH["pine"], TerrainGeo.MAT["leaf"], Transform3D(Basis(Vector3.UP, float(v[1])).scaled(Vector3(PINE_A, 1, PINE_A)), Vector3.ZERO), col)
			CardTree.add_twin(smi, "pine")
			crown = {"yb": -0.45, "fh": 3.45, "a": PINE_A}
		elif v[0] == "leafy_crown":
			var smi := _one(root, TerrainGeo.MESH["blob"], TerrainGeo.MAT["leafSoft"], Transform3D(Basis(Vector3.UP, float(v[1])).scaled(Vector3(BLOB_A, 1, BLOB_A)), Vector3.ZERO), col)
			CardTree.add_twin(smi, "blob")
			crown = {"yb": -1.6, "fh": 3.2, "a": BLOB_A}
		elif v[0] == "pine":
			var sc := 1.0
			var py: float = v[1]
			var cb := sc * 0.6
			_one(root, TerrainGeo.MESH["trunk"], TerrainGeo.MAT["trunk_pine"], Transform3D(Basis().scaled(Vector3(sc, cb + 0.2 + py * 0.15, sc)), Vector3(0, -0.1, 0)), Color(1, 1, 1))
			var smi := _one(root, TerrainGeo.MESH["pine"], TerrainGeo.MAT["leaf"], Transform3D(Basis().scaled(Vector3(sc * 1.1, py, sc * 1.1)), Vector3(0, cb, 0)), col)
			CardTree.add_twin(smi, "pine")
			H = cb + CardTree.PINE_TOP * py
		else:
			var sc: float = v[1]
			var th := sc * 1.4
			_one(root, TerrainGeo.MESH["trunk"], TerrainGeo.MAT["trunk"], Transform3D(Basis().scaled(Vector3(sc, th + 0.3, sc)), Vector3(0, -0.1, 0)), Color(1, 1, 1))
			var smi := _one(root, TerrainGeo.MESH["blob"], TerrainGeo.MAT["leafSoft"], Transform3D(Basis().scaled(Vector3(sc * 1.2, sc * 1.05, sc * 1.2)), Vector3(0, th + sc * 0.7, 0)), col)
			CardTree.add_twin(smi, "blob")
			H = th + sc * 0.7 + sc * 1.05 * 1.45
		# frame: the cell is 1 : 2; a tree fits by its height, a wide one by its width (frame width = 2.9 x its scale)
		var fh := maxf(H * 1.06, (3.2 * float(v[1]) if v[0] == "leafy" else 0.0) * 2.0)
		var yb := -0.02
		if not crown.is_empty():
			fh = crown.fh
			yb = crown.yb
		cam.position = Vector3(0, yb + fh * 0.5, fh * 0.5 / tan(deg_to_rad(cam.fov * 0.5)))
		for f in 8:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img = _bleed_down(img)
		atlas.blit_rect(img, Rect2i(0, 0, CW, CH), Vector2i(i * CW, 0))
		# what of the cell the tree really covers (the far quad is sized by the tree's height)
		var top := CH
		var x0 := CW
		var x1 := 0
		for y in CH:
			for x in CW:
				if img.get_pixel(x, y).a > 0.5:
					top = mini(top, y); x0 = mini(x0, x); x1 = maxi(x1, x)
		var m := {"kind": v[0], "fill": float(CH - top) / CH, "width": float(x1 - x0 + 1) / CW}
		if not crown.is_empty():
			m["y0"] = crown.yb
			m["h"] = crown.fh
			m["w"] = crown.fh * 0.5 / crown.a
		meta.append(m)
		root.queue_free()
		await get_tree().process_frame
	atlas.save_png(OUT)
	var fa := FileAccess.open(OUT.get_basename() + ".json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"cells": VARIANTS.size(), "cell": [CW, CH], "trees": meta}, "\t"))
	fa.close()
	print("IMPOSTORS ", OUT, " ", meta)
	get_tree().quit()


## SS x SS down to one texel, premultiplied (no dark rim from the clear colour); transparent texels then take the
## foliage colour so the mips don't darken the outline
func _bleed_down(src: Image) -> Image:
	var out := Image.create(CW, CH, false, Image.FORMAT_RGBA8)
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in CH:
		for x in CW:
			var r := 0.0; var g := 0.0; var b := 0.0; var a := 0.0
			for dy in SS:
				for dx in SS:
					var c := src.get_pixel(x * SS + dx, y * SS + dy)
					r += c.r * c.a; g += c.g * c.a; b += c.b * c.a; a += c.a
			if a > 0.001:
				out.set_pixel(x, y, Color(r / a, g / a, b / a, a / (SS * SS)))
				if a > 0.9 * SS * SS:
					sum += Color(r / a, g / a, b / a); n += 1
			else:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	var fill := sum / maxf(n, 1)
	for y in CH:
		for x in CW:
			var c := out.get_pixel(x, y)
			if c.a < 0.5:
				out.set_pixel(x, y, Color(fill.r, fill.g, fill.b, c.a))
	return out


func _one(parent: Node3D, mesh: Mesh, mat: Material, t: Transform3D, col: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, t)
	mm.set_instance_custom_data(0, col)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	parent.add_child(mi)
	mi.set_instance_shader_parameter("fade_mode", 1.0)
	return mi
