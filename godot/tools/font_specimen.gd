extends Control
## Every embedded font on one sheet: godot --path godot res://tools/font_specimen.tscn -- out.png
## Shows each face at a few sizes, the symbol glyphs and the LCD font, and prints the file sizes.

func _ready() -> void:
	var out := "font_specimen.png"
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".png"): out = a
	get_window().size = Vector2i(1400, 1000)
	var bg := ColorRect.new()
	bg.color = Color("f4f1ea"); bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(30, 20); box.add_theme_constant_override("separation", 6); add_child(box)
	var rows := [
		["UI text · Barlow Bold", UITheme.font(false), 26, "The quick brown fox jumps over the lazy dog 0123456789 °·×–—…"],
		["UI black · Barlow Black", UITheme.font(true), 26, "SETTINGS  GRAPHICS  AUDIO  Controls — Résumé Ñandú"],
		["Display · Barlow Condensed Bold", UITheme.display_font(700), 44, "RIDE  GARAGE  SHOP  REPLAYS  12.4 km/h"],
		["Display · Barlow Condensed Black", UITheme.display_font(900), 44, "RUNOUT DH  NEW WORLD  $23,200"],
		["Display slanted", UITheme.display_font(900, 0.2), 44, "SAVE & RIDE  GOLD 0:33.90"],
		["WASTED face · Anton", UITheme.punch_font(16), 64, "WASTED  ENTERING  BIG WHIP +650"],
		["Handwriting · Caveat Bold", UITheme.hand_font(), 38, "Lean into the berm, pump the rollers, don't look down!"],
		["Bike computer · Doto", UITheme.lcd_font(), 40, "47.3 KM/H  12:45  8.2%  23°"],
		["Symbols (embedded)", UITheme.font(false), 34, "★★★☆☆  ◀ ▶ ▲ ▼  ✓ ✕  ⚠  ● ▸ ◂  → ↓  🏆"],
	]
	for r in rows:
		var cap := Label.new(); cap.text = r[0]; cap.add_theme_font_size_override("font_size", 14)
		cap.add_theme_color_override("font_color", Color("777777")); box.add_child(cap)
		var l := Label.new(); l.text = r[3]
		l.add_theme_font_override("font", r[1]); l.add_theme_font_size_override("font_size", r[2])
		l.add_theme_color_override("font_color", Color("14181f")); box.add_child(l)
	var tot := 0
	for f in DirAccess.get_files_at("res://assets/fonts"):
		if f.ends_with(".ttf"):
			var n := FileAccess.get_file_as_bytes("res://assets/fonts/" + f).size()
			tot += n; print("FONT ", f, " ", n)
	print("FONT total bytes ", tot)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("SPECIMEN saved ", out)
	get_tree().quit()
