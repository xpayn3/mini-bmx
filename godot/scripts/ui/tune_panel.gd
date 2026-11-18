extends PanelContainer
## Live ride-feel sliders (P), like the web version's tune panel. Values save automatically.

func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -380; offset_right = -14; offset_top = 64; offset_bottom = -90
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	add_child(vb)
	var head := HBoxContainer.new()
	var t := UITheme.label("RIDE TUNING", 18, UITheme.ACCENT, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UITheme.button("Reset", func(): Tune.reset_defaults(); _rebuild(), 14))
	vb.add_child(head)
	vb.add_child(UITheme.label("Values are scaled by the bike you ride. P closes.", 12, UITheme.MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new(); list.name = "List"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	_rebuild()

func _rebuild() -> void:
	var list := find_child("List", true, false)
	for c in list.get_children(): c.queue_free()
	for g in Tune.DEFS:
		list.add_child(UITheme.label(g[0].to_upper(), 13, UITheme.ACCENT, true))
		for row in g[1]:
			var key: String = row[0]
			var hb := HBoxContainer.new()
			var l := UITheme.label(row[1], 13)
			l.custom_minimum_size.x = 150
			l.clip_text = true
			var s := HSlider.new()
			s.min_value = row[3]; s.max_value = row[4]; s.step = row[5]
			s.value = Tune.base[key]
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.focus_mode = Control.FOCUS_NONE
			var vl := UITheme.label(_fmt(s.value, row[6]), 12, UITheme.MUTED)
			vl.custom_minimum_size.x = 70
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			s.value_changed.connect(func(v): vl.text = _fmt(v, row[6]); Tune.set_value(key, v))
			hb.add_child(l); hb.add_child(s); hb.add_child(vl)
			list.add_child(hb)

func _fmt(v: float, unit: String) -> String:
	return ("%.4f" % v if absf(v) < 0.1 and v != 0 else "%.2f" % v) + " " + unit
