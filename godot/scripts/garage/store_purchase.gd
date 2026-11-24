class_name StorePurchase
extends Control
## The moment you buy something in the SHOP (StorePage._buy): a reveal, not a dialog. The store UI slides
## away, cinema bars close in, the studio goes dark; then its lamps come back one after another with a short
## fluorescent flicker (rim strips, key, top, backdrop glow) while the camera slowly pushes in on what you bought.
## The name stamps on letter by letter (white-hot cooling to the accent yellow), a glint sweeps across it, the
## stars light up one by one, a receipt line ticks your cash down. Then FIT TO MY BIKE (parts) / CONTINUE.
## Enter / A = the first button, Esc / B = continue (also skips the reveal). Silent: no recording for it yet.
## Tests: BMX_SHOP_POP_AT=secs freezes the reveal there (screenshots).

signal fit_requested
signal closed

const T_DARK := 0.35          # s: lights out
const LAMP_AT := [0.65, 0.8, 1.05, 1.3, 1.55, 1.7]   # strip L, strip R, key, top, backdrop, fill
const T_KICK := 1.35
const T_NAME := 1.55
const LETTER := 0.045
const T_RULE := 2.0
const T_STARS := 2.3
const T_GLINT := 2.5
const T_RECEIPT := 2.9
const T_BTNS := 3.5

var g: Garage
var p: Dictionary
var cash0 := 0
var cash1 := 0
var can_fit := false

var t := 0.0
var _hold := -1.0
var _hidden := []            # [Control, its alpha]
var _cam0 := []
var _bars: Array[ColorRect] = []
var _letters: Array[Label] = []
var _stars: Array[Label] = []
var _kick: Label
var _rule: ColorRect
var _receipt: VBoxContainer
var _cash_l: Label
var _btns: HBoxContainer
var _glint_mat: ShaderMaterial
var _closing := false
var _lit := []

const GLINT := """
shader_type canvas_item;
uniform float x = -1.0;     // the band's centre, screen x in pixels
uniform float w = 90.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = (FRAGCOORD.x + FRAGCOORD.y * 0.35) - x;
	float band = exp(-d * d / (w * w)) * 0.9;
	COLOR = vec4(mix(c.rgb, vec3(1.0), band * step(0.01, c.a)), c.a);
}
"""

func setup(garage: Garage, product: Dictionary, before: int, after: int, fit: bool) -> void:
	g = garage; p = product; cash0 = before; cash1 = after; can_fit = fit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Env.s("BMX_SHOP_POP_AT") != "": _hold = float(Env.s("BMX_SHOP_POP_AT"))
	# the store UI slides away
	for c in get_parent().get_children():
		if c == self or not (c is Control): continue
		var cc := c as Control
		_hidden.append([cc, cc.modulate.a])
		cc.create_tween().tween_property(cc, "modulate:a", 0.0, 0.25)
	# the camera: a slow push-in from where it is (a bike a little lower and turned, a part closer)
	_cam0 = [g.orbit_t, g.pitch_t, g.dist_t, g.focus_t]
	if p.kind in ["edition", "frame"]:   # (aimed below the bike: it sits in the upper part, the words under it)
		g.orbit_t += 0.35; g.pitch_t = 5.0; g.dist_t = g.dist_t * 0.95; g.focus_t = g.focus_t + Vector3(0, -0.45, 0)
	else:
		g.dist_t = g.dist_t * 0.9; g.orbit_t += 0.2; g.focus_t = g.focus_t + Vector3(0, 0.12, 0)   # (the store's views aim low for the card strip: back up to the part)
	g.shop_reveal = true
	# cinema bars
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0)
		b.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(b)
		_bars.append(b)
	_build_text()
	if Env.s("BMX_SHOP_PROBE") != "": print("SHOPPOP ready size=%s parent=%s" % [size, get_parent().name])

func _build_text() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -110
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", Tokens.S3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var what: String = {"edition": "NEW BIKE IN YOUR GARAGE", "frame": "NEW FRAMESET IN YOUR GARAGE"}.get(p.kind,
		"NEW %s" % String(Catalog.KIND_LABEL.get(p.kind, "PART")).to_upper())
	_kick = UITheme.display("  ".join(String(what).split("")), Tokens.T_LG, Tokens.ACCENT, 0.0)   # letter-spaced
	_kick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kick.modulate.a = 0.0
	col.add_child(_kick)
	# the name, one Label a letter (they stamp on one after another)
	var nm := HBoxContainer.new()
	nm.alignment = BoxContainer.ALIGNMENT_CENTER
	nm.add_theme_constant_override("separation", 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	_glint_mat = ShaderMaterial.new()
	var sh := Shader.new(); sh.code = GLINT
	_glint_mat.shader = sh
	var font := UITheme.display_font(Tokens.W_BLACK, Tokens.SLANT_TITLE)
	var name_text := String(p.name).to_upper()
	var size := 96 if name_text.length() <= 14 else 72
	for ch in name_text:
		var l := Label.new()
		l.text = ch
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		l.add_theme_constant_override("shadow_offset_y", 4)
		l.material = _glint_mat
		l.modulate.a = 0.0
		nm.add_child(l)
		_letters.append(l)
	_rule = ColorRect.new()
	_rule.color = Tokens.ACCENT
	_rule.custom_minimum_size = Vector2(0, 3)
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_rule)
	# stars
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_theme_constant_override("separation", Tokens.S2)
	col.add_child(sr)
	for i in 5:
		var s := UITheme.text("★", Color("e9a400") if i < int(p.tier) else Color(1, 1, 1, 0.18), 40)
		s.modulate.a = 0.0
		sr.add_child(s)
		_stars.append(s)
	var tn := UITheme.display(Catalog.TIER_NAMES[int(p.tier)], Tokens.T_LG, Color(1, 1, 1, 0.85), 0.0)
	tn.modulate.a = 0.0
	sr.add_child(tn)
	_stars.append(tn)
	# the receipt line
	_receipt = VBoxContainer.new()
	_receipt.modulate.a = 0.0
	_receipt.add_theme_constant_override("separation", 0)
	col.add_child(_receipt)
	var paid := UITheme.display("PAID  %s" % Shop.fmt(int(p.price)), Tokens.T_XL, Color(1, 1, 1, 0.92), 0.0)
	paid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_receipt.add_child(paid)
	_cash_l = UITheme.caption("CASH  " + Shop.fmt(cash0), Color(1, 1, 1, 0.6), Tokens.T_SM)
	_cash_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_receipt.add_child(_cash_l)
	# buttons
	_btns = HBoxContainer.new()
	_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	_btns.add_theme_constant_override("separation", Tokens.S4)
	_btns.modulate.a = 0.0
	_btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gap := Control.new(); gap.custom_minimum_size.y = Tokens.S5
	col.add_child(gap)
	col.add_child(_btns)
	if can_fit:
		var f := UITheme.make_button("FIT TO MY %s" % String(GameState.BIKES[g.store.base_frame].label).to_upper(), func(): fit_requested.emit(); _close(), "primary", Tokens.T_XL)
		f.custom_minimum_size = Vector2(300, Tokens.H_BTN)
		_btns.add_child(f)
	var c := UITheme.make_button("CONTINUE", _close, "secondary" if can_fit else "primary", Tokens.T_XL)
	c.custom_minimum_size = Vector2(220, Tokens.H_BTN)
	_btns.add_child(c)
	for b in _btns.get_children(): (b as Button).disabled = true

func _process(dt: float) -> void:
	if _closing: return
	if Env.s("BMX_SHOP_PROBE") != "" and Engine.get_process_frames() % 30 == 0:
		print("SHOPPOP t=%.2f size=%s vis=%s mod=%s letters=%d a0=%.2f" % [t, size, is_visible_in_tree(), modulate, _letters.size(), _letters[0].modulate.a if _letters.size() > 0 else -1.0])
	if _hold >= 0.0: t = _hold
	else: t += minf(dt, 0.05) if Engine.time_scale > 0.0 else 0.016
	var vh := size.y
	var bar := vh * 0.1 * _ease(t / 0.45)
	_bars[0].offset_bottom = bar
	_bars[1].offset_top = -bar
	# the lights: out, then back one by one with a flicker
	var st: StudioSet = g.studio
	if st:
		var out := clampf(1.0 - t / T_DARK, 0.0, 1.0)
		st.env.ambient_light_energy = StudioSet.AMBIENT * maxf(out, _smooth((t - LAMP_AT[2]) / 0.6))
		for i in st.lamps.size():
			var at: float = LAMP_AT[mini(i, LAMP_AT.size() - 1)]
			st.set_lamp(i, maxf(out, _flicker(t - at)))
	g.orbit_t += dt * 0.04 if t < T_BTNS + 2.0 else 0.0   # the slow drift round it
	# the words
	_kick.modulate.a = _smooth((t - T_KICK) / 0.4)
	for i in _letters.size():
		var lt := t - T_NAME - i * LETTER
		var l := _letters[i]
		var k := clampf(lt / 0.32, 0.0, 1.0)
		l.modulate.a = clampf(lt / 0.06, 0.0, 1.0)
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2.ONE * lerpf(2.3, 1.0, _back(k))
		l.add_theme_color_override("font_color", Color(1, 1, 0.92).lerp(Tokens.ACCENT, _smooth(lt / 0.5)))
	var rw := 0.0
	for l in _letters: rw += l.size.x
	_rule.custom_minimum_size.x = rw * _ease((t - T_RULE) / 0.5)
	for i in _stars.size():
		var sk := clampf((t - T_STARS - i * 0.11) / 0.25, 0.0, 1.0)
		var s := _stars[i]
		s.modulate.a = sk
		s.pivot_offset = s.size * 0.5
		s.scale = Vector2.ONE * lerpf(1.8, 1.0, _back(sk))
	var gx := -400.0
	if t > T_GLINT and _letters.size() > 0:
		var l0 := _letters[0]; var l1 := _letters[_letters.size() - 1]
		var a := l0.get_global_transform_with_canvas().origin.x   # screen pixels (the UI layer is scaled)
		var b := (l1.get_global_transform_with_canvas() * Vector2(l1.size.x, 0.0)).x
		gx = lerpf(a - 200.0, b + 300.0, _smooth((t - T_GLINT) / 0.8))
	_glint_mat.set_shader_parameter("x", gx)
	_receipt.modulate.a = _smooth((t - T_RECEIPT) / 0.35)
	_cash_l.text = "CASH  %s  →  %s" % [Shop.fmt(cash0), Shop.fmt(int(lerpf(cash0, cash1, _ease((t - T_RECEIPT - 0.2) / 1.0))))]
	var bk := _smooth((t - T_BTNS) / 0.35)
	_btns.modulate.a = bk
	if bk > 0.5 and (_btns.get_child(0) as Button).disabled:
		for b in _btns.get_children(): (b as Button).disabled = false
		_btns.mouse_filter = Control.MOUSE_FILTER_PASS
		(_btns.get_child(0) as Button).grab_focus()

func _unhandled_input(e: InputEvent) -> void:
	if _closing: return
	if e.is_action_pressed("ui_cancel") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		if t < T_BTNS: t = T_BTNS   # skip the reveal
		else: _close()

## a lamp coming on: off until `x` = 0, then on, a short dip, on again, a softer dip, settles (fluorescent tubes)
static func _flicker(x: float) -> float:
	if x < 0.0: return 0.0
	if x < 0.05: return 1.15
	if x < 0.09: return 0.15
	if x < 0.16: return 1.0
	if x < 0.19: return 0.55
	return 1.0

static func _smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

static func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)

static func _back(k: float) -> float:   # eases in past 1 and settles (a stamp)
	k = clampf(k, 0.0, 1.0)
	var c := 1.6
	return 1.0 + (c + 1.0) * pow(k - 1.0, 3.0) + c * pow(k - 1.0, 2.0)

func _close() -> void:
	if _closing: return
	_closing = true
	if g.studio: g.studio.set_all(1.0)
	g.shop_reveal = false
	g.orbit_t = _cam0[0]; g.pitch_t = _cam0[1]; g.dist_t = _cam0[2]; g.focus_t = _cam0[3]
	for h in _hidden:
		if is_instance_valid(h[0]): (h[0] as Control).create_tween().tween_property(h[0], "modulate:a", h[1], 0.3)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): closed.emit(); queue_free())
