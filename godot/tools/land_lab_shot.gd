extends SceneTree
## Test of the Land Lab editor tab outside the editor: shows the panel in a window, waits for its first build (and
## optionally the 3D view), saves a screenshot, quits. -- out.png [3d] [k=v ...]  (land values to set first)
var _p
var _out := ""
var _t := 0.0
var _shot_at := -1.0

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	_out = a[0] if a.size() > 0 else "land_lab_shot.png"
	root.size = Vector2i(1600, 900)
	_p = load("res://addons/land_lab/land_lab_panel.gd").new()
	_p.size = Vector2(1600, 900)
	root.add_child(_p)
	_args = a.slice(1)

var _args := []
var _set := false
func _apply_args() -> void:
	for s in _args:
		if s == "3d":
			_p.view_3d = true
			_p._show_view()
		elif s.begins_with("size="):
			_p.size_i = int(s.get_slice("=", 1))
		elif s.begins_with("at="):
			_p.cx = float(s.get_slice("=", 1).get_slice(",", 0)); _p.cz = float(s.get_slice("=", 1).get_slice(",", 1))
		elif s.begins_with("orbit="):
			_p._orbit = Vector2(float(s.get_slice("=", 1).get_slice(",", 0)), float(s.get_slice("=", 1).get_slice(",", 1)))
		elif "=" in s:
			LandParams.values[s.get_slice("=", 0)] = float(s.get_slice("=", 1))
			_p._sync()

func _process(dt: float) -> bool:
	_t += dt
	if not _set:
		_set = true
		_apply_args()
		_p._mark()
	if _shot_at < 0.0 and not _p._cur.is_empty() and _p._wait_id < 0 and not _p._dirty:
		_shot_at = _t + 0.5
	if _shot_at > 0.0 and _t >= _shot_at:
		root.get_texture().get_image().save_png(_out)
		print("LANDLAB shot ", _out, " | ", _p._status.text, " | ", str(_p._stats.text).replace("\n", " | "))
		_p.stop_worker()
		return true
	return _t > 90.0
