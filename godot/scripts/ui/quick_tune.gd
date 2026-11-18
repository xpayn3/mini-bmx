extends PanelContainer
## The Quick tune card (top right, like the web version): the pinned ride sliders, always at hand.
## "All" opens the full tuning panel (P); "–" folds it.

var hud
var list: VBoxContainer
var fold_btn: Button

func _ready() -> void:
	theme = UITheme.get_theme()
	add_theme_stylebox_override("panel", UITheme.box(Color(0.08, 0.14, 0.18, 0.82), 14, 12))
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -300; offset_right = -18; offset_top = 64
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	add_child(vb)
	var head := HBoxContainer.new()
	var t := UITheme.label("Quick tune", 15, Color.WHITE, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var all := UITheme.button("All", func(): hud.toggle_tune(), 13); all.custom_minimum_size = Vector2(44, 28)
	all.focus_mode = Control.FOCUS_NONE
	fold_btn = UITheme.button("–", func(): Tune.quick_folded = not Tune.quick_folded; Tune.save(); _rebuild(), 13)
	fold_btn.custom_minimum_size = Vector2(32, 28); fold_btn.focus_mode = Control.FOCUS_NONE
	head.add_child(all); head.add_child(fold_btn)
	vb.add_child(head)
	list = VBoxContainer.new()
	vb.add_child(list)
	Tune.pins_changed.connect(_rebuild)
	Tune.changed.connect(_sync)
	_rebuild()

func _rebuild() -> void:
	for c in list.get_children(): c.queue_free()
	list.visible = not Tune.quick_folded
	fold_btn.text = "+" if Tune.quick_folded else "–"
	if Tune.pins.is_empty():
		list.add_child(UITheme.label("Pin sliders with ☆ in the tuning panel (P)", 12, UITheme.MUTED))
	for k in Tune.pins:
		var r: Array = Tune.row(k)
		if r.is_empty(): continue
		var top := HBoxContainer.new()
		var l := UITheme.label(r[1], 12); l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vl := UITheme.label("", 12, UITheme.ACCENT, true); vl.name = "V_" + k
		top.add_child(l); top.add_child(vl)
		var s := HSlider.new()
		s.name = "S_" + k
		s.min_value = r[3]; s.max_value = r[4]; s.step = r[5]; s.value = Tune.base[k]
		s.focus_mode = Control.FOCUS_NONE
		s.value_changed.connect(func(val): Tune.set_value(k, val))
		list.add_child(top); list.add_child(s)
	_sync()

func _sync() -> void:
	for k in Tune.pins:
		var r: Array = Tune.row(k)
		var vl := list.find_child("V_" + k, true, false) as Label
		if vl and not r.is_empty(): vl.text = ("%.4f" % Tune.base[k] if absf(Tune.base[k]) < 0.1 and Tune.base[k] != 0 else "%.2f" % Tune.base[k]) + " " + r[6]
