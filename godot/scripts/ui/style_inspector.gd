class_name StyleInspector
extends Control
## The Style Inspector (T in the instant replay and in a saved replay): everything the rider's STYLE did, over time, so a
## riding style can be tuned. Reads the per-sample "style row" recorded with the replay (Game._style_fill):
##   CLIP LAYERS  one lane per Pose Lab clip over a window round the playhead: fill = its fade weight, line = the trigger's
##                signal, a tick where it fired (weight > 5 %) / let go; the click picks a clip (then Insert = edit that
##                clip at this very moment in the Pose Lab)
##   EVENTS       a list of what fired when, relative to the playhead
##   POSE CHANNELS the offsets the clips added (hips, torso, head, elbows, knees, bike) as curves, with their value now
##   RIDER STATE  the physics signals the triggers read and the procedural pose inputs (preload, pop, tuck, landing...)
## Y = window 3 / 6 / 12 s. Click a lane = go to that time.

var rp                          # the ReplayMode
var win := 6.0
var sel := ""                   # the clip picked
var _idx := {}                  # names hash -> {name: index}
var _lane_hit: Array = []       # [Rect2, clip name] this frame
var _t_hit := Rect2()           # the lanes' time axis (click = go there)

const W := 470.0
const C_BG := Color(0.06, 0.07, 0.09, 0.93)
const C_TXT := Color(0.88, 0.9, 0.93)
const C_DIM := Color(0.55, 0.58, 0.63)
const C_ACC := Color(1.0, 0.72, 0.15)
const LANE_H := 24.0
const MAX_LANES := 8


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -W
	offset_top = 0.0
	offset_bottom = -44.0   # (the replay's bar stays visible under it)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func cycle_window() -> void:
	win = 12.0 if win >= 12.0 else (win * 2.0 if win >= 3.0 else 3.0)


func has_point(p: Vector2) -> bool:
	return visible and get_global_rect().has_point(p)


func _names(f: Array) -> PackedStringArray:
	return f[12] if f.size() > 12 and f[12] is PackedStringArray else PackedStringArray()


func _index(names: PackedStringArray) -> Dictionary:
	var h := hash(names)
	if not _idx.has(h):
		var d := {}
		for i in names.size(): d[names[i]] = i
		_idx[h] = d
	return _idx[h]


func val(f: Array, key: String, dflt := 0.0) -> float:
	if f.size() <= 12 or not (f[11] is PackedFloat32Array): return dflt
	var d := _index(_names(f))
	if not d.has(key): return dflt
	var i: int = d[key]
	var row: PackedFloat32Array = f[11]
	return row[i] if i < row.size() else dflt


func has_style(f: Array) -> bool:
	return f.size() > 12 and f[11] is PackedFloat32Array and (f[11] as PackedFloat32Array).size() > 0


func _clip_names(f: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for n in _names(f):
		if n.begins_with("clip|") and n.ends_with("|w"): out.append(n.get_slice("|", 1))
	return out


func _col(nm: String) -> Color:
	return Color.from_hsv(float(absi(nm.hash()) % 360) / 360.0, 0.55, 0.95)


## the time of the window's left edge .. right edge
func _t_at_x(x: float, r: Rect2) -> float:
	return rp.tp - win + clampf((x - r.position.x) / maxf(r.size.x, 1.0), 0.0, 1.0) * win * 2.0


func click(pos: Vector2) -> bool:
	if not has_point(pos): return false
	for h in _lane_hit:
		if (h[0] as Rect2).has_point(pos):
			sel = str(h[1])
			return true
	if _t_hit.has_point(pos):
		rp.tp = clampf(_t_at_x(pos.x, _t_hit), rp.t0(), rp.t1())
		rp.playing = false
		return true
	return true   # (eaten: the panel's own area)


func _draw() -> void:
	_lane_hit.clear()
	if rp == null or not visible: return
	var f := ThemeDB.fallback_font
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), C_BG)
	var fr: Array = rp.frames
	var i_now: int = rp._at(rp.tp)
	if fr.is_empty(): return
	var cur: Array = fr[clampi(i_now, 0, fr.size() - 1)]
	draw_string(f, Vector2(12, 22), "STYLE INSPECTOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_ACC)
	if not has_style(cur):
		draw_string(f, Vector2(12, 48), "No style data in this recording (made before the Pose Lab).", HORIZONTAL_ALIGNMENT_LEFT, W - 24, 12, C_DIM)
		return
	var pt := val(cur, "pose|t", -1.0)
	draw_string(f, Vector2(12, 40), "t=%s   speed %.0f km/h   jump timeline %s   window ±%.0fs (Y)" % [ReplayMode.clock(rp.tp - rp.t1()), float(cur[6]), ("%.2f %s" % [pt, PoseKeys.phase_name(pt)]) if pt >= 0.0 else "-", win],
		HORIZONTAL_ALIGNMENT_LEFT, W - 24, 11, C_DIM)
	# the window's samples
	var i0: int = rp._at(rp.tp - win)
	var i1: int = rp._at(rp.tp + win)
	var step := maxi(1, (i1 - i0) / 260)
	var idxs: Array = []
	var i := i0
	while i <= i1:
		idxs.append(i)
		i += step
	if idxs.is_empty() or idxs[-1] != i1: idxs.append(i1)
	var x0 := 12.0
	var x1 := W - 12.0
	var lane_r := Rect2(x0 + 112.0, 56.0, x1 - x0 - 112.0, 0.0)
	var xt := func(t: float) -> float: return lane_r.position.x + (t - (rp.tp - win)) / (win * 2.0) * lane_r.size.x
	# which clips took part in the window (any weight), the busiest first
	var names := _clip_names(cur)
	var score := {}
	for n in names:
		var m := 0.0
		for k in idxs: m = maxf(m, val(fr[k], "clip|%s|w" % n))
		score[n] = m
	var shown: Array = []
	for n in names:
		if float(score[n]) > 0.01 or n == sel: shown.append(n)
	shown.sort_custom(func(a, b): return float(score[a]) > float(score[b]))
	if shown.size() > MAX_LANES: shown.resize(MAX_LANES)
	draw_string(f, Vector2(x0, 56.0), "CLIP LAYERS" + ("  (none fired in this window)" if shown.is_empty() else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_ACC)
	var y := 62.0
	lane_r.position.y = y
	lane_r.size.y = float(shown.size()) * LANE_H
	_t_hit = Rect2(lane_r.position.x, y, lane_r.size.x, maxf(lane_r.size.y, LANE_H))
	var events: Array = []
	for n in shown:
		var lr := Rect2(x0, y, x1 - x0, LANE_H - 3.0)
		draw_rect(lr, Color(1, 1, 1, 0.10 if n == sel else 0.05))
		_lane_hit.append([Rect2(x0, y, 110.0, LANE_H - 3.0), n])
		var col := _col(n)
		var wnow := val(cur, "clip|%s|w" % n)
		draw_string(f, Vector2(x0 + 4, y + 16), "%s %d%%" % [n, roundi(wnow * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, 106.0, 11, col if wnow > 0.01 else C_DIM)
		var pw := PackedVector2Array()
		var ps := PackedVector2Array()
		var prev_w := -1.0
		for k in idxs:
			var fk: Array = fr[k]
			var tk: float = fk[0]
			var w := val(fk, "clip|%s|w" % n)
			var sg := val(fk, "clip|%s|sig" % n)
			var xk: float = xt.call(tk)
			pw.append(Vector2(xk, y + LANE_H - 4.0 - w * (LANE_H - 7.0)))
			ps.append(Vector2(xk, y + LANE_H - 4.0 - sg * (LANE_H - 7.0)))
			if prev_w >= 0.0:
				if prev_w < 0.05 and w >= 0.05: events.append([tk, n, true])
				elif prev_w >= 0.05 and w < 0.05: events.append([tk, n, false])
			prev_w = w
		if pw.size() >= 2:
			var poly := PackedVector2Array([Vector2(pw[0].x, y + LANE_H - 4.0)])
			poly.append_array(pw)
			poly.append(Vector2(pw[-1].x, y + LANE_H - 4.0))
			draw_colored_polygon(poly, Color(col, 0.55))
			draw_polyline(ps, Color(1, 1, 1, 0.45), 1.0)
		y += LANE_H
	# the playhead + the lanes' time axis
	var xp: float = xt.call(rp.tp)
	draw_line(Vector2(xp, 58.0), Vector2(xp, y + 4.0), Color.WHITE, 1.5)
	for q in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var xq: float = lane_r.position.x + (q * 0.5 + 0.5) * lane_r.size.x
		draw_string(f, Vector2(xq - 14.0, y + 14.0), "%+.1fs" % (q * win), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_DIM)
	y += 24.0
	# events
	draw_string(f, Vector2(x0, y), "FIRED / LET GO  (relative to now)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_ACC)
	y += 4.0
	events.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var shown_ev := 0
	for ev in events:
		if shown_ev >= 7: break
		y += 14.0
		var dtv: float = float(ev[0]) - rp.tp
		draw_string(f, Vector2(x0 + 4, y), "%+.2fs   %s   %s" % [dtv, "▲ ON " if bool(ev[2]) else "▼ OFF", ev[1]], HORIZONTAL_ALIGNMENT_LEFT, W - 30, 11, _col(str(ev[1])) if bool(ev[2]) else C_DIM)
		shown_ev += 1
	if events.is_empty():
		y += 14.0
		draw_string(f, Vector2(x0 + 4, y), "-", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
	y += 18.0
	# pose channels: the offsets the clips added, as curves
	draw_string(f, Vector2(x0, y), "POSE CHANNELS  (sum of the clips, applied to the rider)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_ACC)
	y += 4.0
	for ch in PoseKeys.CH:
		var id: String = ch[0]
		var mx := maxf(absf(float(ch[3])), absf(float(ch[4])))
		var vnow := val(cur, "ch|" + id)
		var used := absf(vnow) > 1e-4
		var cr := Rect2(x0 + 112.0, y + 2.0, x1 - x0 - 112.0 - 64.0, 14.0)
		draw_rect(cr, Color(1, 1, 1, 0.05))
		draw_line(Vector2(cr.position.x, cr.position.y + 7.0), Vector2(cr.end.x, cr.position.y + 7.0), Color(1, 1, 1, 0.12))
		var pl := PackedVector2Array()
		var any := false
		for k in idxs:
			var fk: Array = fr[k]
			var v := val(fk, "ch|" + id)
			if absf(v) > 1e-4: any = true
			var xk: float = cr.position.x + (float(fk[0]) - (rp.tp - win)) / (win * 2.0) * cr.size.x
			pl.append(Vector2(xk, cr.position.y + 7.0 - clampf(v / mx, -1.0, 1.0) * 6.5))
		if pl.size() >= 2: draw_polyline(pl, Color(0.35, 0.8, 1.0, 0.9 if any else 0.3), 1.5)
		draw_line(Vector2(xp - (lane_r.position.x - cr.position.x) * 0.0, cr.position.y), Vector2(xp, cr.end.y), Color(1, 1, 1, 0.35))
		draw_string(f, Vector2(x0 + 4, y + 13.0), str(ch[1]), HORIZONTAL_ALIGNMENT_LEFT, 106.0, 10, C_TXT if used else C_DIM)
		var unit := str(ch[6])
		var txt := ("%+.0f°" % rad_to_deg(vnow)) if unit == "deg" else (("%+.1fcm" % (vnow * 100.0)) if unit == "cm" else "%+.2f" % vnow)
		draw_string(f, Vector2(cr.end.x + 6.0, y + 13.0), txt, HORIZONTAL_ALIGNMENT_LEFT, 60.0, 10, C_TXT if used else C_DIM)
		y += 17.0
	y += 10.0
	# the state the triggers read + the procedural pose's own inputs
	draw_string(f, Vector2(x0, y), "RIDER STATE NOW  (what the triggers read · the procedural pose's inputs)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_ACC)
	y += 6.0
	var col_i := 0
	var base_y := y
	for n in _names(cur):
		if not (n.begins_with("sig|") or n.begins_with("drv|")): continue
		var v2 := val(cur, n)
		var cx := x0 + 4.0 + float(col_i % 2) * (W - 24.0) * 0.5
		var cy := base_y + 13.0 + float(col_i / 2) * 14.0
		if cy > sz.y - 6.0: break
		draw_string(f, Vector2(cx, cy), "%s %s" % [n.get_slice("|", 1), ("%.2f" % v2)], HORIZONTAL_ALIGNMENT_LEFT, (W - 24.0) * 0.5 - 6.0, 10, C_TXT if absf(v2) > 0.02 else C_DIM)
		col_i += 1
	if sel != "":
		draw_string(f, Vector2(x0, sz.y - 8.0), "picked: %s   ·   Insert = edit it at this moment in the Pose Lab" % sel, HORIZONTAL_ALIGNMENT_LEFT, W - 24, 10, C_ACC)
