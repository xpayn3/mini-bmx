class_name CardFace
extends Control
## One collectible card drawn flat (520 x 728, 5:7): rarity frame, name banner, art window with a big glyph, flavour text + what it takes.
## `texture(id, owned, host)` renders it once into a texture (cached) for the grid thumbnails and the 3D holo viewer.
## id "back" = the card back. A card not yet owned is drawn as a dark silhouette with only what it takes.

const W := 520
const H := 728
var card_id := ""
var got := true
var number := 1
var total := 1

static var _cache := {}

static func texture(id: String, owned: bool, host: Node) -> Texture2D:
	var key := "%s:%d" % [id, 1 if owned else 0]
	if _cache.has(key): return _cache[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var f := CardFace.new()
	f.card_id = id; f.got = owned
	var ids: Array = Collection.CARDS.keys()
	f.number = ids.find(id) + 1; f.total = ids.size()
	f.size = Vector2(W, H)
	vp.add_child(f)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

func _draw() -> void:
	var disp := UITheme.display_font(900, Tokens.SLANT)
	var disp0 := UITheme.display_font(900)
	var body := UITheme.font(false)
	var sym := UITheme.symbols()
	var info: Dictionary = Collection.CARDS.get(card_id, {})
	var rar: Dictionary = Collection.RARITY.get(info.get("rarity", "common"), Collection.RARITY.common)
	var rc: Color = rar.col if got else Color("3a4156")
	# card body + frame
	var frame := StyleBoxFlat.new()
	frame.bg_color = rc.darkened(0.15) if card_id != "back" else Color("1c2130")
	frame.set_corner_radius_all(30)
	frame.anti_aliasing = true
	draw_style_box(frame, Rect2(0, 0, W, H))
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color("11141c") if got else Color("0d1017")
	inner.set_corner_radius_all(22)
	inner.anti_aliasing = true
	draw_style_box(inner, Rect2(12, 12, W - 24, H - 24))
	if card_id == "back":
		_back(disp, sym)
		return
	# name banner
	draw_string(disp, Vector2(40, 74), String(info.get("name", "?")) if got else "? ? ?", HORIZONTAL_ALIGNMENT_LEFT, W - 200, 46, Color.WHITE if got else Color("5d667e"))
	draw_string(body, Vector2(40, 104), String(info.get("kind", "")) + "  ·  " + String(rar.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, rc)
	# rarity pips
	var pips: int = ["common", "rare", "epic", "legendary"].find(info.get("rarity", "common")) + 1
	for i in 4:
		draw_circle(Vector2(W - 44 - i * 26, 62), 9.0, rc if i < pips else Color(rc, 0.18))
	# art window
	var art := Rect2(40, 128, W - 80, 400)
	var artbox := StyleBoxFlat.new()
	artbox.bg_color = rc.darkened(0.55) if got else Color("151a25")
	artbox.set_corner_radius_all(18)
	artbox.anti_aliasing = true
	draw_style_box(artbox, art)
	# a glow and diagonal stripes in the window
	for i in 14:
		var y := art.position.y + i * 38.0
		draw_line(Vector2(art.position.x, y + 60.0), Vector2(art.end.x, y - 60.0), Color(rc, 0.10 if got else 0.04), 14.0)
	var gl := String(info.get("glyph", "?")) if got else "?"
	var gs := 280
	var gw := sym.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
	if gl == "?": gw = disp0.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, gs).x
	var gf: Font = disp0 if gl == "?" else UITheme.font(true)
	draw_string(gf, Vector2(art.position.x + (art.size.x - gw) * 0.5, art.position.y + art.size.y * 0.5 + gs * 0.33), gl, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(rc.lightened(0.55), 0.95) if got else Color("2a3042"))
	# text
	var txt := String(info.get("text", "")) if got else String(info.get("need", ""))
	draw_multiline_string(body, Vector2(44, 568), txt, HORIZONTAL_ALIGNMENT_LEFT, W - 88, 26, 3, Color("d4d9e6") if got else Color("7a8399"))
	if got: draw_string(body, Vector2(44, 660), String(info.get("need", "")), HORIZONTAL_ALIGNMENT_LEFT, W - 88, 18, Color("7a8399"))
	draw_line(Vector2(40, 676), Vector2(W - 40, 676), Color(rc, 0.35), 2.0)
	draw_string(disp0, Vector2(40, 704), "RUNOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("7a8399"))
	var nn := "No. %02d / %02d" % [number, total]
	draw_string(body, Vector2(W - 40 - body.get_string_size(nn, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, 704), nn, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("7a8399"))

func _back(disp: Font, sym: Font) -> void:
	for i in 18:
		draw_line(Vector2(0, i * 60.0), Vector2(W, i * 60.0 - 260.0), Color(1, 1, 1, 0.03), 18.0)
	var c := Vector2(W, H) * 0.5
	draw_circle(c, 150.0, Color("232a3d"))
	draw_circle(c, 126.0, Color("ffd21f"))
	var w := disp.get_string_size("R", HORIZONTAL_ALIGNMENT_LEFT, -1, 190).x
	draw_string(disp, c + Vector2(-w * 0.5, 66), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 190, Color("151a23"))
	var t := "RUNOUT"
	var tw := disp.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	draw_string(disp, Vector2((W - tw) * 0.5, H - 70), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("7a8399"))
