class_name PadGlyph
extends RefCounted
## Button icons drawn in code, used everywhere a control is shown (prompt bars, the get-up prompt, the
## controls menu): Xbox Series style - glossy near-black face buttons with the letter in its colour, bumpers,
## triggers, sticks, the D-pad, View / Menu / Share - and key caps for the keyboard / mouse.
## draw(ci, name, centre, h) draws one; width(name, h) says how wide it is. Names: "A" "B" "X" "Y" "LB" "RB"
## "LT" "RT" "LS" "RS" "L3" "R3" "DPAD" "D-Up" "D-Down" "D-Left" "D-Right" "VIEW" "MENU" "SHARE" "MOUSE" "WHEEL";
## "K:<text>" (or anything else) is a key cap with that text. glyph_for(action) gives the name for the device in use.

const FACE := {"A": Color("6cc94a"), "B": Color("ee4a3f"), "X": Color("3c8cf0"), "Y": Color("f5c022")}
const BODY := Color("26282d")
const BODY_HI := Color("4a4e57")
const RIM := Color("0e0f12")
const LETTER := Color("f2f3f5")

static var _font: Font

static func font() -> Font:
	if _font == null:
		_font = UITheme.display_font(700)
	return _font


## the icon name for an action on the device in use (Settings.pad_active)
static func glyph_for(action: String, pad := Settings.pad_active) -> String:
	var evs: Array = InputMap.action_get_events(action) if InputMap.has_action(action) else []
	if pad and not evs.any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion):
		evs = Settings.default_events(action)   # (test runs install no pad bindings)
	for e in evs:
		var e_pad: bool = e is InputEventJoypadButton or e is InputEventJoypadMotion
		if e_pad != pad: continue
		if e is InputEventJoypadButton:
			return ["A", "B", "X", "Y", "VIEW", "GUIDE", "MENU", "L3", "R3", "LB", "RB", "D-Up", "D-Down", "D-Left", "D-Right", "SHARE"][e.button_index] if e.button_index < 16 else "?"
		if e is InputEventJoypadMotion:
			return ["LS", "LS", "RS", "RS", "LT", "RT"][e.axis] if e.axis < 6 else "?"
		if e is InputEventMouseButton:
			return "WHEEL" if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] else "MOUSE"
		return "K:" + Settings.event_text(e)
	return "?" if pad else glyph_for(action, true)


static func is_face(n: String) -> bool:
	return FACE.has(n)


static func width(n: String, h: float) -> float:
	if n.begins_with("K:"):
		var kf := font()
		return maxf(h, kf.get_string_size(n.substr(2), HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.46)).x + h * 0.6)
	match n:
		"A", "B", "X", "Y", "LS", "RS", "L3", "R3", "DPAD", "D-Up", "D-Down", "D-Left", "D-Right", "VIEW", "MENU", "SHARE", "GUIDE", "MOUSE", "WHEEL":
			return h
		"LB", "RB":
			return h * 1.55
		"LT", "RT":
			return h * 1.1
	var f := font()
	return maxf(h, f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.48)).x + h * 0.6)


## one icon, centred at c, h pixels tall
static func draw(ci: CanvasItem, n: String, c: Vector2, h: float, alpha := 1.0) -> void:
	var r := h * 0.5
	if n.begins_with("K:"):
		_key(ci, n.substr(2), c, h, alpha); return
	if FACE.has(n):
		var col: Color = FACE[n]
		ci.draw_circle(c + Vector2(0, h * 0.06), r, Color(0, 0, 0, 0.35 * alpha))          # drop shadow
		ci.draw_circle(c, r, Color(RIM, alpha))
		ci.draw_circle(c, r * 0.9, Color(BODY, alpha))
		ci.draw_circle(c + Vector2(0, -r * 0.1), r * 0.78, Color(BODY.lerp(BODY_HI, 0.45), alpha))   # dome
		ci.draw_arc(c, r * 0.9, PI * 1.12, PI * 1.88, 24, Color(1, 1, 1, 0.22 * alpha), maxf(1.0, h * 0.05), true)   # gloss
		ci.draw_arc(c, r * 0.9, 0, TAU, 40, Color(col, 0.5 * alpha), maxf(1.0, h * 0.04), true)   # coloured rim light
		_text(ci, n, c, int(h * 0.56), Color(col.lightened(0.15), alpha), true)
		return
	match n:
		"LB", "RB":
			var w := width(n, h)
			var rc := Rect2(c - Vector2(w, h * 0.78) * 0.5, Vector2(w, h * 0.78))
			_round(ci, rc.grow(1.5), h * 0.3, Color(RIM, alpha))
			_round(ci, rc, h * 0.28, Color(BODY, alpha))
			_round(ci, Rect2(rc.position + Vector2(2, 2), Vector2(rc.size.x - 4, rc.size.y * 0.42)), h * 0.2, Color(1, 1, 1, 0.08 * alpha))
			_text(ci, n, c, int(h * 0.42), Color(LETTER, alpha))
		"LT", "RT":
			var w := width(n, h)
			var pts := PackedVector2Array()
			for i in 13:   # a trigger: rounded top, straight sides, square foot
				var a := PI + PI * i / 12.0
				pts.append(c + Vector2(cos(a) * w * 0.5, -h * 0.1 + sin(a) * h * 0.4))
			pts.append(c + Vector2(w * 0.5, h * 0.48)); pts.append(c + Vector2(-w * 0.5, h * 0.48))
			ci.draw_colored_polygon(_grow_poly(pts, c, 1.08), Color(RIM, alpha))
			ci.draw_colored_polygon(pts, Color(BODY, alpha))
			_text(ci, n, c + Vector2(0, h * 0.06), int(h * 0.4), Color(LETTER, alpha))
		"LS", "RS", "L3", "R3":
			ci.draw_circle(c + Vector2(0, h * 0.06), r, Color(0, 0, 0, 0.35 * alpha))
			ci.draw_circle(c, r, Color(RIM, alpha))
			ci.draw_circle(c, r * 0.88, Color(BODY, alpha))
			ci.draw_arc(c, r * 0.62, 0, TAU, 32, Color(1, 1, 1, 0.16 * alpha), maxf(1.0, h * 0.05), true)   # the thumb dish
			ci.draw_arc(c, r * 0.88, PI * 1.15, PI * 1.85, 20, Color(1, 1, 1, 0.2 * alpha), maxf(1.0, h * 0.05), true)
			_text(ci, ("L" if n[0] == "L" else "R") + ("3" if n.ends_with("3") else ""), c, int(h * 0.4), Color(LETTER, alpha))
		"DPAD", "D-Up", "D-Down", "D-Left", "D-Right":
			var a := h * 0.32; var b := h * 0.5
			var arms := {"D-Up": Rect2(c.x - a * 0.5, c.y - b, a, b - a * 0.5), "D-Down": Rect2(c.x - a * 0.5, c.y + a * 0.5, a, b - a * 0.5),
				"D-Left": Rect2(c.x - b, c.y - a * 0.5, b - a * 0.5, a), "D-Right": Rect2(c.x + a * 0.5, c.y - a * 0.5, b - a * 0.5, a)}
			ci.draw_rect(Rect2(c.x - a * 0.5 - 1.5, c.y - b - 1.5, a + 3, 2 * b + 3), Color(RIM, alpha))
			ci.draw_rect(Rect2(c.x - b - 1.5, c.y - a * 0.5 - 1.5, 2 * b + 3, a + 3), Color(RIM, alpha))
			ci.draw_rect(Rect2(c.x - a * 0.5, c.y - b, a, 2 * b), Color(BODY, alpha))
			ci.draw_rect(Rect2(c.x - b, c.y - a * 0.5, 2 * b, a), Color(BODY, alpha))
			if arms.has(n): ci.draw_rect(arms[n], Color(LETTER, 0.9 * alpha))
		"VIEW", "MENU", "SHARE", "GUIDE":
			ci.draw_circle(c, r * 0.9, Color(RIM, alpha))
			ci.draw_circle(c, r * 0.8, Color(BODY, alpha))
			var s := h * 0.14
			var lc := Color(LETTER, alpha)
			if n == "VIEW":   # two overlapping windows
				ci.draw_rect(Rect2(c + Vector2(-s * 1.6, -s * 1.3), Vector2(s * 2.2, s * 1.7)), lc, false, maxf(1.0, h * 0.06))
				ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.4), Vector2(s * 2.2, s * 1.7)), lc, true)
			elif n == "MENU":   # three lines
				for i in 3: ci.draw_line(c + Vector2(-s * 1.4, (i - 1) * s * 1.1), c + Vector2(s * 1.4, (i - 1) * s * 1.1), lc, maxf(1.0, h * 0.07))
			elif n == "SHARE":   # a box with an arrow up out of it
				ci.draw_rect(Rect2(c + Vector2(-s * 1.4, -s * 0.4), Vector2(s * 2.8, s * 1.8)), lc, false, maxf(1.0, h * 0.06))
				ci.draw_line(c + Vector2(0, s * 0.6), c + Vector2(0, -s * 1.6), lc, maxf(1.0, h * 0.07))
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 2.0), c + Vector2(s * 0.8, -s * 1.0), c + Vector2(-s * 0.8, -s * 1.0)]), lc)
			else:
				ci.draw_arc(c, s * 1.5, 0, TAU, 24, lc, maxf(1.0, h * 0.07), true)
		"MOUSE", "WHEEL":
			var rc := Rect2(c - Vector2(h * 0.34, h * 0.48), Vector2(h * 0.68, h * 0.96))
			_round(ci, rc.grow(1.5), h * 0.34, Color(RIM, alpha))
			_round(ci, rc, h * 0.32, Color(Color("f4f5f7"), alpha))
			ci.draw_line(c + Vector2(0, -h * 0.48), c + Vector2(0, -h * 0.08), Color(RIM, alpha), maxf(1.0, h * 0.05))
			if n == "WHEEL": _round(ci, Rect2(c + Vector2(-h * 0.06, -h * 0.36), Vector2(h * 0.12, h * 0.22)), h * 0.06, Color(FACE["X"], alpha))
		_:
			_key(ci, n, c, h, alpha)


## a key cap: light, a little raised
static func _key(ci: CanvasItem, n: String, c: Vector2, h: float, alpha: float) -> void:
	var w := width("K:" + n, h)
	var rc := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
	_round(ci, Rect2(rc.position + Vector2(0, h * 0.08), rc.size), h * 0.2, Color(0, 0, 0, 0.35 * alpha))
	_round(ci, rc, h * 0.2, Color(Color("d9dce2"), alpha))
	_round(ci, Rect2(rc.position + Vector2(h * 0.08, h * 0.05), rc.size - Vector2(h * 0.16, h * 0.2)), h * 0.16, Color(Color("f7f8fa"), alpha))
	_text(ci, n, c + Vector2(0, -h * 0.04), int(h * 0.46), Color(Color("1d2028"), alpha))


static func _text(ci: CanvasItem, s: String, c: Vector2, size: int, col: Color, heavy := false) -> void:
	var f := font()
	var ts := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var p := c + Vector2(-ts.x * 0.5, f.get_ascent(size) * 0.5 - f.get_descent(size) * 0.35)
	if heavy: ci.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(1, size / 12), Color(0, 0, 0, 0.5 * col.a))
	ci.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func _round(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(minf(rad, minf(r.size.x, r.size.y) * 0.5)))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)


static func _grow_poly(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts: out.append(c + (p - c) * k)
	return out


## a row of [icons, label] items, centred: e.g. [[["LS"], "Travel"], [["RT", "LT"], "Zoom"]]. Plain (labels
## with a soft shadow); pill = true puts it on a dark translucent pill.
class PromptBar extends Control:
	var items := []
	var h := 30.0
	var label_size := 17
	var a := 1.0
	var pill := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_items(list: Array) -> void:
		items = list
		queue_redraw()

	func _measure() -> float:
		var f := UITheme.font(true)
		var w := 0.0
		for it in items:
			for g in it[0]: w += PadGlyph.width(g, h) + 4
			w += 8 + f.get_string_size(String(it[1]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x + 34
		return w - 34

	func _draw() -> void:
		if items.is_empty(): return
		var f := UITheme.font(true)
		var w := _measure()
		var x := (size.x - w) * 0.5
		var cy := size.y * 0.5
		if pill:
			var bg := Rect2(x - 22, cy - h * 0.5 - 9, w + 44, h + 18)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.05, 0.06, 0.08, 0.55 * a)
			sb.set_corner_radius_all(int(bg.size.y * 0.5))
			sb.anti_aliasing = true
			draw_style_box(sb, bg)
		for it in items:
			for g in it[0]:
				var gw := PadGlyph.width(g, h)
				PadGlyph.draw(self, g, Vector2(x + gw * 0.5, cy), h, a)
				x += gw + 4
			x += 8
			var t := String(it[1]).to_upper()
			var tp := Vector2(x, cy + f.get_ascent(label_size) * 0.5 - 2)
			draw_string(f, tp + Vector2(0, 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(0, 0, 0, 0.45 * a))   # soft shadow
			draw_string(f, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(1, 1, 1, 0.95 * a))
			x += f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x + 34
