class_name AnimStudio
extends Node3D
## The Anim Studio (`--anim`, or Insert in the rider room): the standing rider of the menus with their animation library.
##  IMPORT any Mixamo FBX / glTF (run-time, retargeted automatically by RiderAnim), then per clip: ON, IDLE (the clip the
##  menu returns to), speed, pick weight, hold, fade, and pose OFFSETS (move where the driver stands / how they lean and
##  look: hips, torso, head, elbows, knees) - saved in the library (AnimLib) and used by every menu that shows the standing rider.
##  Modes: PLAYLIST = exactly what the menus play, CLIP = loop one, BLEND = two clips mixed by a slider (phase-locked or not).
##  BAKE sends the clip to the Pose Lab as a ride clip (hips / torso / head / elbows / knees, relative to its first frame),
##  where it gets a trigger and plays in rides. Drag = orbit, wheel = zoom, Esc = back.

signal closed

var rider: Rider
var anim: RiderAnim
var cam: Camera3D
var _yaw := -0.5
var _pitch := 0.12
var _dist := 3.2
var _drag := false
var _sel := -1
var _selb := -1
var _mode := 0                  # 0 playlist, 1 clip, 2 blend
var _ta := 0.0
var _tb := 0.0
var _mix := 0.5
var _sync := true
var _paused := false
var _ui: CanvasLayer
var _list: ItemList
var _status: Label
var _now: Label
var _chk_on: CheckBox
var _chk_idle: CheckBox
var _chk_sync: CheckBox
var _cs := {}                   # setting -> slider
var _os := {}                   # offset channel -> slider
var _ov := {}                   # offset channel -> value label
var _pick_b: OptionButton
var _mix_s: HSlider
var _scrub: HSlider
var _dlg: FileDialog
var _lock := false

const C_ACC := Color(1.0, 0.72, 0.15)
const C_TXT := Color(0.88, 0.9, 0.93)
const C_DIM := Color(0.55, 0.58, 0.63)
const SETS := [["speed", "Speed", 0.25, 2.0, 0.05], ["weight", "Pick weight", 0.0, 5.0, 0.1], ["hold", "Hold (s)", 0.0, 20.0, 0.5], ["fade", "Fade in (s)", 0.05, 2.0, 0.05]]


func _ready() -> void:
	AnimLib.ensure_loaded()
	_build_world()
	_build_ui()
	_reload()
	_test_setup()


# ---- the scene --------------------------------------------------------------------------------------------------

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.24, 0.27)
	fm.roughness = 0.9
	fl.material_override = fm
	add_child(fl)
	var grid := MeshInstance3D.new()   # a 1 m grid on the floor: how far the driver moves
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-3, 4):
		im.surface_add_vertex(Vector3(i, 0.002, -3)); im.surface_add_vertex(Vector3(i, 0.002, 3))
		im.surface_add_vertex(Vector3(-3, 0.002, i)); im.surface_add_vertex(Vector3(3, 0.002, i))
	im.surface_end()
	grid.mesh = im
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1, 1, 1, 0.12)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid.material_override = gm
	add_child(grid)
	rider = Rider.new()
	add_child(rider)
	rider.set_look(RiderPanels.load_look())
	rider.set_style(Garage.STAND_POSE)
	rider.use_helmet(str(rider.look.get("helmet", "glory")))
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.current = true
	add_child(cam)
	_cam()


func _cam() -> void:
	var tgt := Vector3(0, 0.95, 0)
	var off := Vector3(cos(_pitch) * cos(_yaw), sin(_pitch), cos(_pitch) * sin(_yaw)) * _dist
	cam.look_at_from_position(tgt + off + Vector3(0.5, 0, 0), tgt + Vector3(0.5, 0, 0))   # (a little right: the panel covers the left)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		_close()
	elif e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT: _drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed: _dist = maxf(1.2, _dist / 1.08)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed: _dist = minf(8.0, _dist * 1.08)
	elif e is InputEventMouseMotion and _drag:
		_yaw -= (e as InputEventMouseMotion).relative.x * 0.008
		_pitch = clampf(_pitch + (e as InputEventMouseMotion).relative.y * 0.005, -0.3, 1.2)


func _close() -> void:
	if AnimLib.dirty: AnimLib.save_cfg()
	closed.emit()


# ---- the library ------------------------------------------------------------------------------------------------

## (re)load every clip: the project's and the player's imported ones
func _reload() -> void:
	if anim != null: anim.free_clips()
	anim = RiderAnim.new(rider)
	_fill_list()
	if _sel < 0 or _sel >= anim.clips.size(): _sel = 0 if anim.clips.size() > 0 else -1
	_select(_sel)


func _fill_list() -> void:
	_list.clear()
	for c in anim.clips:
		var cf := AnimLib.get_cfg(str(c.name))
		var tag := ""
		if not bool(cf.on): tag += "  (off)"
		if bool(cf.idle) or str(c.name).to_lower().contains("idle"): tag += "  [IDLE]"
		if str(c.name) + ".fbx" in _user_names() or str(c.name) + ".glb" in _user_names(): tag += "  (imported)"
		_list.add_item(str(c.name) + tag)
	_fill_b()


func _user_names() -> PackedStringArray:
	var o := PackedStringArray()
	for p in AnimLib.user_files(): o.append(p.get_file())
	return o


func _fill_b() -> void:
	if _pick_b == null: return
	_pick_b.clear()
	for c in anim.clips: _pick_b.add_item(str(c.name))
	if _selb < 0 or _selb >= anim.clips.size(): _selb = mini(1, anim.clips.size() - 1)
	if _selb >= 0: _pick_b.select(_selb)


func _select(i: int) -> void:
	_sel = i
	_ta = 0.0
	_tb = 0.0
	if i < 0 or i >= anim.clips.size(): return
	var c: Dictionary = anim.clips[i]
	var cf := AnimLib.get_cfg(str(c.name))
	_lock = true
	_list.select(i)
	_chk_on.button_pressed = bool(cf.on)
	_chk_idle.button_pressed = bool(cf.idle)
	for k in _cs: (_cs[k] as HSlider).value = float(cf[k])
	for ch in _os:
		var v := float((cf.off as Dictionary).get(ch, 0.0))
		(_os[ch] as HSlider).value = v
		_off_label(ch, v)
	_scrub.max_value = float(c.len)
	_lock = false


func _off_label(ch: String, v: float) -> void:
	var inf: Array = PoseKeys.ch_info(ch)
	_ov[ch].text = ("%+.0f°" % rad_to_deg(v)) if inf[6] == "deg" else (("%+.1f cm" % (v * 100.0)) if inf[6] == "cm" else "%+.2f" % v)


func _name_of(i: int) -> String:
	return str(anim.clips[i].name) if i >= 0 and i < anim.clips.size() else ""


# ---- per frame --------------------------------------------------------------------------------------------------

var _tt := 0.0

func _process(dt: float) -> void:
	_cam()
	_tt += dt
	if Env.s("BMX_ANIM_SHOT") != "" and _tt > 3.0:   # tests: a picture after 3 s, then quit
		get_viewport().get_texture().get_image().save_png(Env.s("BMX_ANIM_SHOT"))
		if AnimLib.dirty and Env.s("BMX_ANIM_SAVE") != "": print("ANIMSTUDIO ", AnimLib.save_cfg())
		GameState.quit()
		return
	if anim == null or anim.clips.is_empty():
		_now.text = "No clips yet: IMPORT a Mixamo FBX (Without Skin, 30 fps)"
		return
	match _mode:
		0:
			anim.step(dt)
			_now.text = "PLAYLIST  ·  now: " + _name_of(anim.cur)
		1:
			if not _paused: _ta += dt * float(AnimLib.get_cfg(_name_of(_sel)).speed)
			var pose := anim.pose_for(_sel, _ta)
			rider.pose_points(pose.P, pose.o)
			_now.text = "CLIP  ·  " + _name_of(_sel) + "  %.2f / %.2f s" % [fmod(_ta, float(anim.clips[_sel].len)), float(anim.clips[_sel].len)]
			_scrub.set_value_no_signal(fmod(_ta, float(anim.clips[_sel].len)))
		2:
			if _selb < 0 or _sel < 0: return
			if not _paused:
				_ta += dt * float(AnimLib.get_cfg(_name_of(_sel)).speed)
			var la: float = anim.clips[_sel].len
			var lb: float = anim.clips[_selb].len
			_tb = fmod(_ta, la) / la * lb if _sync else _tb + dt * float(AnimLib.get_cfg(_name_of(_selb)).speed)
			var pa := anim.pose_for(_sel, _ta)
			var pb := anim.pose_for(_selb, _tb)
			var pm := RiderAnim.blend_poses(pa, pb, _mix)
			rider.pose_points(pm.P, pm.o)
			_now.text = "BLEND  ·  %s  %d%%  +  %s  %d%%" % [_name_of(_sel), roundi((1.0 - _mix) * 100.0), _name_of(_selb), roundi(_mix * 100.0)]


# ---- the UI -----------------------------------------------------------------------------------------------------

func _label(t: String, sz: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _row(parent: Control, text: String, mn: float, mx: float, st: float, cb: Callable) -> Array:
	var r := HBoxContainer.new()
	parent.add_child(r)
	var l := _label(text, 11, C_TXT)
	l.custom_minimum_size = Vector2(96, 0)
	r.add_child(l)
	var s := HSlider.new()
	s.min_value = mn; s.max_value = mx; s.step = st
	s.scrollable = false
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	r.add_child(s)
	var v := _label("", 11, C_DIM)
	v.custom_minimum_size = Vector2(52, 0)
	r.add_child(v)
	return [s, v]


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size = Vector2(360, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.10, 0.94)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	_ui.add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	vb.add_child(_label("ANIM STUDIO", 20, C_ACC))
	_now = _label("", 12, C_DIM)
	vb.add_child(_now)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 4)
	vb.add_child(r1)
	r1.add_child(_button("IMPORT…", func(): _import_dialog()))
	r1.add_child(_button("SAVE", func(): _say(AnimLib.save_cfg())))
	r1.add_child(_button("BACK", func(): _close()))
	var mode := OptionButton.new()
	mode.focus_mode = Control.FOCUS_NONE
	for m in ["PLAYLIST (as the menus)", "CLIP (loop one)", "BLEND (two clips)"]: mode.add_item(m)
	mode.item_selected.connect(func(i): _mode = i; _paused = false; _ta = 0.0; _tb = 0.0)
	vb.add_child(mode)
	vb.add_child(_label("CLIPS  (the first selected is A)", 12, C_ACC))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 150)
	_list.item_selected.connect(func(i): _select(i))
	vb.add_child(_list)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	vb.add_child(r2)
	_chk_on = _check("ON", func(b): _cfg_set("on", b))
	_chk_idle = _check("IDLE (menu returns here)", func(b): _cfg_set("idle", b))
	r2.add_child(_chk_on); r2.add_child(_chk_idle)
	for cs in SETS:
		var pr := _row(vb, cs[1], cs[2], cs[3], cs[4], func(v): pass)
		var key: String = cs[0]
		var sl: HSlider = pr[0]
		var vl: Label = pr[1]
		sl.value_changed.connect(func(v): vl.text = "%.2f" % v; _cfg_set(key, v))
		_cs[key] = sl
	vb.add_child(_label("WHERE THE DRIVER STANDS / LEANS  (offsets on this clip)", 12, C_ACC))
	for ch in AnimLib.OFF_CH:
		var inf: Array = PoseKeys.ch_info(ch)
		var pr2 := _row(vb, str(inf[1]), float(inf[3]), float(inf[4]), float(inf[5]), func(v): pass)
		var sl2: HSlider = pr2[0]
		var chn: String = ch
		sl2.value_changed.connect(func(v): _on_off(chn, v))
		_os[ch] = sl2
		_ov[ch] = pr2[1]
	vb.add_child(_button("RESET OFFSETS", func(): _reset_off()))
	vb.add_child(_label("BLEND", 12, C_ACC))
	_pick_b = OptionButton.new()
	_pick_b.focus_mode = Control.FOCUS_NONE
	_pick_b.clip_text = true
	_pick_b.item_selected.connect(func(i): _selb = i)
	vb.add_child(_pick_b)
	var pm := _row(vb, "A <-> B mix", 0.0, 1.0, 0.01, func(v): _mix = v)
	_mix_s = pm[0]
	_mix_s.value = 0.5
	_chk_sync = _check("PHASE-LOCK B to A", func(b): _sync = b)
	_chk_sync.button_pressed = true
	vb.add_child(_chk_sync)
	var ps := _row(vb, "Scrub (CLIP)", 0.0, 10.0, 0.01, func(v): _paused = true; _ta = v)
	_scrub = ps[0]
	vb.add_child(_button("PLAY / PAUSE", func(): _paused = not _paused))
	vb.add_child(_label("USE IN RIDES", 12, C_ACC))
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 4)
	vb.add_child(r3)
	r3.add_child(_button("BAKE → RIDE CLIP", func(): _bake()))
	r3.add_child(_button("REMOVE (imported)", func(): _remove()))
	_status = _label("Drop a Mixamo FBX with IMPORT…", 11, C_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)
	_dlg = FileDialog.new()
	_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_dlg.use_native_dialog = true
	_dlg.filters = PackedStringArray(["*.fbx, *.glb, *.gltf ; Mixamo / glTF animation clips"])
	_dlg.files_selected.connect(func(ps2): _import(ps2))
	_ui.add_child(_dlg)


func _check(t: String, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 11)
	c.add_theme_color_override("font_color", C_TXT)
	c.toggled.connect(cb)
	return c


func _say(s: String) -> void:
	_status.text = s


func _cfg_set(key: String, v) -> void:
	if _lock or _sel < 0: return
	AnimLib.set_cfg(_name_of(_sel), key, v)
	if key in ["on", "idle"]:
		var keep := _sel
		_fill_list()
		_lock = true
		_list.select(keep)
		_lock = false


func _on_off(ch: String, v: float) -> void:
	_off_label(ch, v)
	if not _lock and _sel >= 0: AnimLib.set_off(_name_of(_sel), ch, v)


func _reset_off() -> void:
	if _sel < 0: return
	AnimLib.set_cfg(_name_of(_sel), "off", {})
	_select(_sel)


func _import_dialog() -> void:
	_dlg.popup_centered_ratio(0.7)


func _import(paths: PackedStringArray) -> void:
	var msgs: Array = []
	for p in paths: msgs.append(AnimLib.import_file(p))
	_say("  ·  ".join(msgs))
	_reload()


func _remove() -> void:
	if _sel < 0: return
	var nm := _name_of(_sel)
	var removed := false
	for p in AnimLib.user_files():
		if p.get_file().get_basename() == nm:
			AnimLib.remove_user_clip(p)
			removed = true
	_say(("REMOVED " if removed else "NOT AN IMPORTED CLIP (project clips are deleted from assets/anim/mixamo): ") + nm)
	if removed:
		_sel = -1
		_reload()


func _bake() -> void:
	if _sel < 0: return
	PoseKeys.ensure_loaded()
	var c := AnimLib.bake(anim, _sel)
	PoseKeys.add_clip(c)
	_say("BAKED '%s' into the Pose Lab library (%d keys, %.1f s) - open the Pose Lab (Insert in a ride) to set its trigger. %s" % [c.name, c.ks.size(), c.length, PoseKeys.save_file()])


# ---- tests (BMX_ANIM_IMPORT=file, BMX_ANIM_SEL=name, BMX_ANIM_MODE=0|1|2, BMX_ANIM_MIX=0..1, BMX_ANIM_OFF="ch=v,..", BMX_ANIM_BAKE=1) ---

func _test_setup() -> void:
	if Env.s("BMX_ANIM_IMPORT") != "":
		print("ANIMSTUDIO ", AnimLib.import_file(Env.s("BMX_ANIM_IMPORT")))
		_reload()
	print("ANIMSTUDIO clips=%d: %s" % [anim.clips.size(), ", ".join(anim.clips.map(func(c): return "%s %.1fs" % [c.name, c.len]))])
	if Env.s("BMX_ANIM_SEL") != "":
		for i in anim.clips.size():
			if str(anim.clips[i].name).to_lower().contains(Env.s("BMX_ANIM_SEL").to_lower()): _select(i); break
	if Env.s("BMX_ANIM_MODE") != "": _mode = int(Env.s("BMX_ANIM_MODE"))
	if Env.s("BMX_ANIM_MIX") != "": _mix = float(Env.s("BMX_ANIM_MIX"))
	for kv in Env.s("BMX_ANIM_OFF").split(",", false):
		var p := kv.split("=")
		if p.size() == 2 and _sel >= 0:
			AnimLib.set_off(_name_of(_sel), p[0], float(p[1]))
			_select(_sel)
	if Env.s("BMX_ANIM_BAKE") != "" and _sel >= 0:
		var c := AnimLib.bake(anim, _sel)
		var k: Dictionary = c.ks[c.ks.size() / 2].v
		print("ANIMSTUDIO bake '%s' len=%.2f keys=%d mid=%s" % [c.name, c.length, c.ks.size(), JSON.stringify(k)])
