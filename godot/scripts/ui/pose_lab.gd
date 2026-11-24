class_name PoseLab
extends CanvasLayer
## The Pose Lab (Insert in a ride / the test playground; in the instant replay Insert = "pose from here"): pause the ride
## ANYWHERE (mid-air too), pose the rider with sliders, key the poses on the jump timeline and play them back morphed.
## STYLE ONLY: pausing just holds the physics step (like the playground's G), nothing in the physics changes; the keys
## (PoseKeys) are offsets added to the rider's pose in every ride, jump after jump. Hands and feet stay on the grips
## and pedals: moving the hips / tilting the torso carries the head and shoulders, the arms and legs follow by IK, and
## tilting the bike under the body makes them follow the bike.
##   sliders = the key at the playhead (moving one on a spot with no key makes a key there: auto-key)
##   timeline = drag the playhead (orange) / a key (diamond), right click a key = delete, double click = a key there
## The playhead follows the live ride (LIVE) or sits where you put it (preview: the keys' pose shown over the
## frozen moment, so you can play the whole morph on one frozen frame).

var game
var preview_t := -1.0           # < 0: the playhead follows the ride
var _open := false
var _sel := -1
var _sync := false
var _slider_drag := false
var _play := false
var _play_t := 0.0
var _panel: PanelContainer
var _sl := {}                   # channel -> HSlider
var _vl := {}                   # channel -> Label
var _tl                         # the Timeline control
var _head: Label
var _status: Label
var _btn_hold: Button
var _btn_play: Button
var _chk: CheckBox
var _amt: HSlider
var _amt_l: Label
var _pull_t := 0.0
var _status_t := 0.0
var _gz                         # the 3D overlay (skeleton + bike handles)
var _hs: Array = []             # this frame's handles: {id, w (world), p (screen), ok (editable), name}
var _hover := -1
var _dg := {}                   # the drag in progress
const PICK_R := 15.0
const BAR_SIGN := 1.0           # which way a grip dragged forward turns the bars (set from the drawn result)
## the rider's joints (Rider.J order) joined into a skeleton to draw
const BONES := [[0, 1], [1, 2], [1, 3], [1, 6], [3, 4], [4, 5], [6, 7], [7, 8], [2, 9], [2, 12], [9, 10], [10, 11], [12, 13], [13, 14]]

const C_BG := Color(0.07, 0.08, 0.10, 0.92)
const C_ACC := Color(1.0, 0.72, 0.15)
const C_TXT := Color(0.88, 0.9, 0.93)
const C_DIM := Color(0.55, 0.58, 0.63)
const PLAY_RATE := 0.22         # the timeline per second while "play keys" runs on the frozen moment
const W_PANEL := 330.0
const H_TL := 150.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	PoseKeys.ensure_loaded()
	_build()


func is_open() -> bool: return _open


## where on the timeline the rider is posed now: the playhead the user put down, else the ride's own moment
func t_for_pose(live: float) -> float:
	return preview_t if preview_t >= 0.0 else live


func head_t() -> float:
	return preview_t if preview_t >= 0.0 else (game.pose_t if game else -1.0)


func toggle() -> void:
	if _open: close()
	else: open()


func open(hold: bool = true) -> void:
	_open = true
	visible = true
	preview_t = -1.0
	_sel = -1
	if hold: game.pose_hold = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pull()
	_refresh_buttons()


func close() -> void:
	_open = false
	visible = false
	_play = false
	preview_t = -1.0
	game.pose_hold = false
	game.pose_steps = 0
	if PoseKeys.dirty: PoseKeys.save_file()   # (never lose an edit by closing)


func _say(s: String) -> void:
	if _status: _status.text = s
	_status_t = 3.0


# ---- building the UI ---------------------------------------------------------------------------------------------

func _build() -> void:
	_gz = Overlay.new()   # (first: the panels draw over it)
	_gz.lab = self
	_gz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gz)
	_panel = PanelContainer.new()
	_panel.position = Vector2(0, 0)
	_panel.size = Vector2(W_PANEL, 0)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.custom_minimum_size = Vector2(W_PANEL, 0)
	_panel.add_theme_stylebox_override("panel", _box(C_BG))
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)
	var title := _label("POSE LAB", 20, C_ACC)
	outer.add_child(title)
	_head = _label("", 12, C_DIM)
	outer.add_child(_head)
	# transport
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 4)
	outer.add_child(r1)
	_btn_hold = _button("PAUSE", func(): _toggle_hold())
	r1.add_child(_btn_hold)
	r1.add_child(_button("STEP", func(): game.pose_hold = true; game.pose_steps = 1; _refresh_buttons()))
	_btn_play = _button("PLAY KEYS", func(): _toggle_play())
	r1.add_child(_btn_play)
	r1.add_child(_button("LIVE", func(): preview_t = -1.0; _play = false; _pull(); _refresh_buttons()))
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 4)
	outer.add_child(r2)
	_chk = CheckBox.new()
	_chk.text = "KEYS ON"
	_chk.button_pressed = PoseKeys.enabled
	_chk.toggled.connect(func(b): PoseKeys.enabled = b; PoseKeys.dirty = true)
	_chk.add_theme_color_override("font_color", C_TXT)
	r2.add_child(_chk)
	_amt = HSlider.new()
	_amt.min_value = 0.0; _amt.max_value = 1.5; _amt.step = 0.05; _amt.value = PoseKeys.amount
	_amt.scrollable = false
	_amt.custom_minimum_size = Vector2(110, 18)
	_amt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_amt.value_changed.connect(func(v): PoseKeys.amount = v; PoseKeys.dirty = true; _amt_l.text = "x%.2f" % v)
	r2.add_child(_amt)
	_amt_l = _label("x%.2f" % PoseKeys.amount, 12, C_TXT)
	r2.add_child(_amt_l)
	var r3 := HBoxContainer.new()
	r3.add_theme_constant_override("separation", 4)
	outer.add_child(r3)
	r3.add_child(_button("+ KEY", func(): _add_key()))
	r3.add_child(_button("DEL KEY", func(): _del_key()))
	r3.add_child(_button("ZERO KEY", func(): _zero_key()))
	r3.add_child(_button("SAVE", func(): _say(PoseKeys.save_file())))
	r3.add_child(_button("RELOAD", func(): PoseKeys.load_file(); _sel = -1; _pull(); _say("RELOADED")))
	# the sliders, by group
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	var grp := ""
	for c in PoseKeys.CH:
		if c[2] != grp:
			grp = c[2]
			vb.add_child(_label(grp, 12, C_ACC))
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		vb.add_child(row)
		var top := HBoxContainer.new()
		row.add_child(top)
		var nm := _label(c[1], 12, C_TXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var vl := _label("", 12, C_DIM)
		top.add_child(vl)
		_vl[c[0]] = vl
		var s := HSlider.new()
		s.min_value = c[3]; s.max_value = c[4]; s.step = c[5]
		s.scrollable = false   # (the wheel never moves a slider: project rule)
		s.custom_minimum_size = Vector2(0, 16)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = c[0]
		s.value_changed.connect(func(v): _on_slider(id, v))
		s.drag_started.connect(func(): _slider_drag = true)
		s.drag_ended.connect(func(_ch): _slider_drag = false)
		row.add_child(s)
		_sl[id] = s
	_status = _label("Insert: close  ·  edits auto-key at the playhead", 11, C_DIM)
	outer.add_child(_status)
	# timeline along the bottom
	_tl = Timeline.new()
	_tl.lab = self
	_tl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_tl.offset_left = W_PANEL + 10.0
	_tl.offset_right = -10.0
	_tl.offset_top = -H_TL - 10.0
	_tl.offset_bottom = -10.0
	add_child(_tl)


func _box(c: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_content_margin_all(10)
	b.set_corner_radius_all(3)
	return b


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


# ---- actions ----------------------------------------------------------------------------------------------------

func _toggle_hold() -> void:
	game.pose_hold = not game.pose_hold
	game.pose_steps = 0
	if not game.pose_hold: _play = false
	_refresh_buttons()


func _toggle_play() -> void:
	_play = not _play
	if _play:
		game.pose_hold = true   # (the morph plays over the frozen moment)
		_play_t = maxf(preview_t, 0.0) if preview_t >= 0.0 and preview_t < 0.99 else 0.0
		preview_t = _play_t
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _btn_hold: _btn_hold.text = "RESUME" if game.pose_hold else "PAUSE"
	if _btn_play: _btn_play.text = "STOP" if _play else "PLAY KEYS"


func _need_t() -> float:
	var t := head_t()
	if t < 0.0:
		preview_t = 0.45   # (not in a jump: the playhead goes on the air part so there is something to pose)
		t = 0.45
	return t


func _add_key() -> void:
	var t := _need_t()
	_sel = PoseKeys.set_key(t, {})
	preview_t = t
	_say("KEY AT %.2f (%s)" % [t, PoseKeys.phase_name(t)])


func _del_key() -> void:
	var i := _sel if _sel >= 0 else PoseKeys.key_at(head_t())
	if i >= 0:
		PoseKeys.delete_key(i)
		_sel = -1
		_say("KEY DELETED")
		_pull()


func _zero_key() -> void:
	var t := _need_t()
	var z := PoseKeys.zero_vals()
	_sel = PoseKeys.set_key(t, z)
	preview_t = t
	_pull()


func _on_slider(id: String, v: float) -> void:
	if _sync: return
	_edit(id, v)


## write one channel at the playhead (a key is made there if there is none)
func _edit(id: String, v: float) -> void:
	var t := _need_t()
	preview_t = t   # (the playhead stays where the edit was made)
	_sel = PoseKeys.set_key(t, {id: v})
	_update_value_label(id, v)


func _update_value_label(id: String, v: float) -> void:
	var inf: Array = PoseKeys.ch_info(id)
	var s := ""
	match str(inf[6]):
		"deg": s = "%+.0f°" % rad_to_deg(v)
		"cm": s = "%+.1f cm" % (v * 100.0)
		_: s = "%+.2f" % v
	_vl[id].text = s


## the sliders show the morphed pose at the playhead
func _pull() -> void:
	var t := head_t()
	var vals := PoseKeys.eval(t, 1.0) if t >= 0.0 else {}
	_sync = true
	for id in _sl:
		var v := float(vals.get(id, 0.0))
		(_sl[id] as HSlider).value = v
		_update_value_label(id, v)
	_sync = false


func _process(dt: float) -> void:
	if not _open: return
	if _status_t > 0.0:
		_status_t -= dt
		if _status_t <= 0.0 and _status: _status.text = "Insert: close  ·  edits auto-key at the playhead"
	if _play:
		_play_t += PLAY_RATE * dt
		if _play_t > 1.0: _play_t = 0.0
		preview_t = _play_t
	var t := head_t()
	_head.text = "%s   t=%.2f %s   keys %d%s" % [
		"PAUSED" if game.pose_hold else "RUNNING", t, ("· " + PoseKeys.phase_name(t)) if t >= 0.0 else "· not in a jump (drag the timeline)",
		PoseKeys.keys.size(), "   *unsaved" if PoseKeys.dirty else ""]
	_pull_t -= dt
	if _pull_t <= 0.0 and not _slider_drag and (preview_t < 0.0 or _play):
		_pull_t = 0.08
		_pull()
	_tl.queue_redraw()
	_update_handles()
	_gz.queue_redraw()


# ---- the 3D skeleton + bike handles: click a joint / a bike point and drag ---------------------------------------
# What a drag writes (always the key at the playhead; auto-keyed):
#   hips -> hip x y z            chest -> torso lean forward / sideways (about the hips, head + arms follow)
#   head -> nod / turn           elbows / knees -> out / in           front / rear wheel -> bike nose up / down under the body
#   bar centre -> bike lays over under the body                       grips -> the handlebar turns (the hands go with it)
# Hands and feet are pinned to the grips and pedals: drawn grey, not draggable.

func _update_handles() -> void:
	_hs.clear()
	var cam := get_viewport().get_camera_3d()
	var r = game.rider
	var rg = game.rig
	if cam == null or r == null or rg == null or game.phys.crash_on or r.J.size() < 15: return
	var jw: Array = r.joints_world()
	var add := func(id: String, w: Vector3, ok: bool, nm: String) -> void:
		if cam.is_position_behind(w): return
		_hs.append({"id": id, "w": w, "p": cam.unproject_position(w), "ok": ok, "name": nm})
	add.call("head", jw[0], true, "HEAD: nod / turn")
	add.call("chest", jw[1], true, "CHEST: lean (head + arms follow)")
	add.call("hips", jw[2], true, "HIPS: move (torso follows)")
	add.call("elL", jw[4], true, "LEFT ELBOW: out / in")
	add.call("elR", jw[7], true, "RIGHT ELBOW: out / in")
	add.call("knL", jw[10], true, "LEFT KNEE: out / in")
	add.call("knR", jw[13], true, "RIGHT KNEE: out / in")
	for pair in [[5, "LEFT HAND"], [8, "RIGHT HAND"], [11, "LEFT FOOT"], [14, "RIGHT FOOT"]]:
		add.call("pin", jw[pair[0]], false, pair[1] + ": pinned to the bike")
	add.call("wf", rg.wheel_f.global_position, true, "FRONT WHEEL: bike nose up / down")
	add.call("wr", rg.wheel_r.global_position, true, "REAR WHEEL: bike nose up / down")
	add.call("bar", rg.steer_n.to_global((rg.grip_l + rg.grip_r) * 0.5), true, "BARS: lay the bike over")
	add.call("gripL", rg.steer_n.to_global(rg.grip_l), true, "LEFT GRIP: turn the handlebar")
	add.call("gripR", rg.steer_n.to_global(rg.grip_r), true, "RIGHT GRIP: turn the handlebar")
	_hover = -1
	if _dg.is_empty():
		var mp := get_viewport().get_mouse_position()
		var bd := PICK_R
		for i in _hs.size():
			if not _hs[i].ok: continue
			var d: float = (_hs[i].p as Vector2).distance_to(mp)
			if d <= bd: bd = d; _hover = i


func _over_ui(pos: Vector2) -> bool:
	return _panel.get_global_rect().has_point(pos) or _tl.get_global_rect().has_point(pos)


func _input(e: InputEvent) -> void:
	if not _open: return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := e as InputEventMouseButton
		if mb.pressed:
			if _over_ui(mb.position): return
			_update_handles()
			var best := -1
			var bd := PICK_R
			for i in _hs.size():
				if _hs[i].ok and (_hs[i].p as Vector2).distance_to(mb.position) <= bd:
					bd = (_hs[i].p as Vector2).distance_to(mb.position); best = i
			if best >= 0:
				_drag_begin(_hs[best].id, _hs[best].w, mb.position)
				get_viewport().set_input_as_handled()
		elif not _dg.is_empty():
			_dg = {}
			_say("DRAG DONE  ·  keys %d" % PoseKeys.keys.size())
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion and not _dg.is_empty():
		_drag_move((e as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()


func _ray_hit(pos: Vector2, w0: Vector3) -> Variant:
	var cam := get_viewport().get_camera_3d()
	var o := cam.project_ray_origin(pos)
	var n := cam.project_ray_normal(pos)
	return Plane(-cam.global_basis.z, w0).intersects_ray(o, n)


func _drag_begin(id: String, w0: Vector3, pos: Vector2) -> void:
	var t := _need_t()
	preview_t = t   # (the playhead stays; the drag edits the key there)
	_sel = PoseKeys.set_key(t, {})
	var hit = _ray_hit(pos, w0)
	if hit == null: return
	var loc: Array = []
	for v in game.rider.J: loc.append(v)
	_dg = {"id": id, "v0": (PoseKeys.keys[_sel].v as Dictionary).duplicate(), "hit0": hit, "w0": w0, "J0": loc}
	_say("DRAGGING " + id.to_upper())


func _drag_move(pos: Vector2) -> void:
	var hit = _ray_hit(pos, _dg.w0)
	if hit == null: return
	var dw: Vector3 = hit - (_dg.hit0 as Vector3)
	var id: String = _dg.id
	var bike: bool = id in ["wf", "wr", "bar", "gripL", "gripR"]
	var basis: Basis = game.rig.lean_g.global_basis if bike else game.rider.global_basis
	_drag_apply(id, basis.orthonormalized().inverse() * dw)


## d = the drag in the bike's frame (x forward, y up, z right), metres
func _drag_apply(id: String, d: Vector3) -> void:
	var v0: Dictionary = _dg.v0
	var out := {}
	match id:
		"hips":
			out = {"hip_x": float(v0.hip_x) + d.x, "hip_y": float(v0.hip_y) + d.y, "hip_z": float(v0.hip_z) + d.z}
		"chest":
			var J0: Array = _dg.J0
			var p: Vector3 = J0[2]
			var c0: Vector3 = J0[1]
			var c1: Vector3 = c0 + d
			out = {"torso_pitch": float(v0.torso_pitch) + atan2(c1.x - p.x, c1.y - p.y) - atan2(c0.x - p.x, c0.y - p.y),
				"torso_roll": float(v0.torso_roll) + atan2(c1.z - p.z, c1.y - p.y) - atan2(c0.z - p.z, c0.y - p.y)}
		"head":
			out = {"head_pitch": float(v0.head_pitch) + (d.x - 0.5 * d.y) / 0.2, "head_yaw": float(v0.head_yaw) - d.z / 0.2}
		"elL", "elR":
			out = {"elbows_out": float(v0.elbows_out) + d.z * (-1.0 if id == "elL" else 1.0) / 0.12}
		"knL", "knR":
			out = {"knees_out": float(v0.knees_out) + d.z * (-1.0 if id == "knL" else 1.0) / 0.12}
		"wf": out = {"rel_pitch": float(v0.rel_pitch) + d.y / 1.2}
		"wr": out = {"rel_pitch": float(v0.rel_pitch) - d.y / 1.2}
		"bar": out = {"rel_roll": float(v0.rel_roll) + d.z / 0.6}
		"gripL", "gripR":
			out = {"bar_steer": float(v0.bar_steer) + BAR_SIGN * d.x * (1.0 if id == "gripL" else -1.0) / 0.38}
	for k in out:
		var inf: Array = PoseKeys.ch_info(k)
		out[k] = clampf(float(out[k]), float(inf[3]), float(inf[4]))
	PoseKeys.set_key(float(PoseKeys.keys[_sel].t), out)
	_pull()


func test_drag(id: String, d: Vector3) -> void:   # tests: a drag of d metres (the bike's frame) on a handle
	var t := _need_t()
	preview_t = t
	_sel = PoseKeys.set_key(t, {})
	var loc: Array = []
	for v in game.rider.J: loc.append(v)
	_dg = {"id": id, "v0": (PoseKeys.keys[_sel].v as Dictionary).duplicate(), "hit0": Vector3.ZERO, "w0": Vector3.ZERO, "J0": loc}
	_drag_apply(id, d)
	_dg = {}


## the overlay's drawing (a Control under the panels)
func _draw_gizmos(c: Control) -> void:
	if not _open or _hs.is_empty(): return
	var cam := get_viewport().get_camera_3d()
	var r = game.rider
	if cam != null and r != null and r.J.size() >= 15:
		var jw: Array = r.joints_world()
		for b in BONES:
			if cam.is_position_behind(jw[b[0]]) or cam.is_position_behind(jw[b[1]]): continue
			c.draw_line(cam.unproject_position(jw[b[0]]), cam.unproject_position(jw[b[1]]), Color(0.3, 0.85, 1.0, 0.8), 2.5, true)
	var f := ThemeDB.fallback_font
	for i in _hs.size():
		var h: Dictionary = _hs[i]
		var p: Vector2 = h.p
		var bike: bool = h.id in ["wf", "wr", "bar", "gripL", "gripR"]
		if not h.ok:
			c.draw_circle(p, 3.5, Color(0.6, 0.62, 0.66, 0.9))
			continue
		var active: bool = (i == _hover) or (not _dg.is_empty() and _dg.id == h.id)
		var col := Color(0.4, 1.0, 0.5) if bike else Color(1.0, 0.72, 0.15)
		if bike:
			c.draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(col, 0.35 if not active else 0.9))
			c.draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), col, false, 2.0)
		else:
			c.draw_circle(p, 8.0, Color(col, 0.35 if not active else 0.95))
			c.draw_arc(p, 8.0, 0.0, TAU, 20, col, 2.0, true)
		if active:
			c.draw_string(f, p + Vector2(12, -10), h.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


class Overlay extends Control:
	var lab
	func _draw() -> void:
		if lab: lab._draw_gizmos(self)


# ---- tests (BMX_POSELAB=<secs|air>, BMX_POSELAB_SET="t:ch=v,ch=v;t:...", BMX_POSELAB_PLAY=1) --------------------------

func test_script(spec: String, play: String) -> void:
	for grp in spec.split(";", false):
		var pr := grp.split(":")
		if pr.size() < 2: continue
		preview_t = float(pr[0])
		for kv in pr[1].split(",", false):
			var p := kv.split("=")
			if p.size() == 2 and PoseKeys.ch_info(p[0]).size() > 0: _edit(p[0], float(p[1]))
		print("POSELAB key t=%.2f phase=%s keys=%d" % [preview_t, PoseKeys.phase_name(preview_t), PoseKeys.keys.size()])
	# BMX_POSELAB_DRAG="id:dx,dy,dz;..." = drags of a handle by metres in the bike's frame (x fwd, y up, z right)
	for grp in Env.s("BMX_POSELAB_DRAG").split(";", false):
		var pr := grp.split(":")
		if pr.size() < 2: continue
		var dv := pr[1].split(",")
		if dv.size() == 3: test_drag(pr[0], Vector3(float(dv[0]), float(dv[1]), float(dv[2])))
		print("POSELAB drag ", pr[0], " -> ", PoseKeys.keys[_sel].v if _sel >= 0 else {})
	# BMX_POSELAB_MOUSE="id:dx,dy" = a real mouse drag of that handle by pixels (the ray / plane path)
	for grp in Env.s("BMX_POSELAB_MOUSE").split(";", false):
		var pr := grp.split(":")
		if pr.size() < 2: continue
		_update_handles()
		for h in _hs:
			if h.id == pr[0] and h.ok:
				var dv := pr[1].split(",")
				_drag_begin(h.id, h.w, h.p)
				_drag_move((h.p as Vector2) + Vector2(float(dv[0]), float(dv[1])))
				print("POSELAB mouse ", pr[0], " -> ", PoseKeys.keys[_sel].v)
				_dg = {}
				break
	if play == "1": _toggle_play()
	_pull()


# ---- the timeline -----------------------------------------------------------------------------------------------

class Timeline extends Control:
	var lab
	var _drag := ""
	const PAD := 14.0
	const BAND_H := 22.0

	func _x(t: float) -> float:
		return lerpf(PAD, size.x - PAD, t)

	func _t(x: float) -> float:
		return clampf((x - PAD) / maxf(size.x - 2.0 * PAD, 1.0), 0.0, 1.0)

	func _key_hit(x: float) -> int:
		var best := -1
		var bd := 9.0
		for i in PoseKeys.keys.size():
			var d := absf(_x(float(PoseKeys.keys[i].t)) - x)
			if d <= bd: bd = d; best = i
		return best

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), PoseLab.C_BG)
		# the jump's parts
		var ph: Array = PoseKeys.PHASES
		for i in ph.size():
			var a: float = ph[i][1]
			var b: float = ph[i + 1][1] if i + 1 < ph.size() else 1.0
			var r := Rect2(_x(a), 4.0, _x(b) - _x(a), BAND_H)
			draw_rect(r, Color(1, 1, 1, 0.07 if i % 2 == 0 else 0.13))
			draw_string(f, r.position + Vector2(5, 15), ph[i][0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4.0, 11, PoseLab.C_DIM)
			draw_line(Vector2(_x(a), 4.0), Vector2(_x(a), size.y - 6.0), Color(1, 1, 1, 0.10))
		# the morph curve of the first few channels' size: how much the keys move the pose here
		var base_y := size.y - 24.0
		var top_y := BAND_H + 14.0
		var prev := Vector2.ZERO
		var steps := int(size.x / 4.0)
		for s in steps + 1:
			var tt := float(s) / steps
			var ev := PoseKeys.eval(tt, 1.0)
			var mag := 0.0
			for id in ev: mag += absf(float(ev[id])) / maxf(float(PoseKeys.ch_info(id)[4]), 0.01)
			var p := Vector2(_x(tt), base_y - clampf(mag * 0.28, 0.0, 1.0) * (base_y - top_y))
			if s > 0: draw_line(prev, p, Color(0.35, 0.8, 1.0, 0.85), 2.0)
			prev = p
		# the keys
		for i in PoseKeys.keys.size():
			var kx := _x(float(PoseKeys.keys[i].t))
			var c := PoseLab.C_ACC if i == lab._sel else Color(0.9, 0.93, 0.97)
			var ky := base_y + 10.0
			draw_colored_polygon(PackedVector2Array([Vector2(kx, ky - 8), Vector2(kx + 7, ky), Vector2(kx, ky + 8), Vector2(kx - 7, ky)]), c)
		# the playhead: orange = put down by hand, white = the ride's own moment
		var live: float = lab.game.pose_t
		if live >= 0.0:
			draw_line(Vector2(_x(live), 4.0), Vector2(_x(live), size.y - 6.0), Color(1, 1, 1, 0.55), 1.0)
		var ht: float = lab.head_t()
		if ht >= 0.0:
			var hx := _x(ht)
			draw_line(Vector2(hx, 2.0), Vector2(hx, size.y - 4.0), PoseLab.C_ACC if lab.preview_t >= 0.0 else Color.WHITE, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(hx - 6, 2), Vector2(hx + 6, 2), Vector2(hx, 12)]), PoseLab.C_ACC if lab.preview_t >= 0.0 else Color.WHITE)
		draw_string(f, Vector2(8, size.y - 5), "drag: playhead / key   ·   right click a key: delete   ·   double click: new key", HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 11, PoseLab.C_DIM)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var k := _key_hit(mb.position.x)
					if mb.double_click and k < 0:
						lab.preview_t = _t(mb.position.x)
						lab._add_key(); lab._pull()
					elif k >= 0:
						lab._sel = k
						lab.preview_t = float(PoseKeys.keys[k].t)
						_drag = "key"
						lab._pull()
					else:
						lab.preview_t = _t(mb.position.x)
						lab._sel = -1
						_drag = "head"
						lab._pull()
				else:
					_drag = ""
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var k2 := _key_hit(mb.position.x)
				if k2 >= 0:
					PoseKeys.delete_key(k2)
					lab._sel = -1
					lab._pull()
			accept_event()
		elif e is InputEventMouseMotion and _drag != "":
			var t := _t((e as InputEventMouseMotion).position.x)
			if _drag == "key" and lab._sel >= 0:
				lab._sel = PoseKeys.move_key(lab._sel, t)
			lab.preview_t = t
			lab._pull()
			accept_event()
