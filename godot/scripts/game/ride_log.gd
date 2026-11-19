class_name RideLog
extends RefCounted
## The last SECS seconds of the ride, every physics step (120 Hz): the bike's physics, the rider's body,
## the drawn bike's corrections and the player's inputs. Kept in a ring buffer the whole ride (cheap: one
## PackedFloat32Array per step); "save_log" (R3 / F8) writes it to user://ridelogs/ride_<date>.csv, the
## moment of the press marked, so a glitch the player saw can be found in the numbers afterwards.

const SECS := 60.0
const HZ := 120
const COLS := [
	"t", "x", "y", "z", "v", "vy", "heading", "course", "slip", "pitch", "ground_pitch",
	"lean", "bike_lean", "counter", "rock", "bank", "bank_raw", "lat_a", "load_g", "steer", "steer_in",
	"air", "air_time", "front_air", "rear_air", "compress", "legs", "body_x", "hip_shift",
	"flick", "body_in", "air_stick_x", "air_stick_y", "manual_up", "wheelie_up", "edge_s", "stick_yaw",
	"sprint", "stamina", "crash", "brake_stop",
	"in_throttle", "in_brake", "in_steer", "in_body_fwd", "in_body_lean", "in_hop", "in_sprint", "pad",
	"tyre_lift", "drawn_y", "pelvis_x", "pelvis_y", "pelvis_z", "chest_x", "chest_y", "chest_z", "head_x", "head_y", "head_z",
	"whip", "whip_hold", "flick_kick", "raw_right_x", "raw_left_x",
]

var _rows: Array = []
var _head := 0
var _count := 0
var _t := 0.0

func _init() -> void:
	_rows.resize(int(SECS * HZ))

func record(dt: float, st: BikePhysics, inp: Dictionary, lift: float, drawn_y: float, J: Array) -> void:
	_t += dt
	var pel: Vector3 = J[2] if J.size() > 2 and J[2] is Vector3 else Vector3.ZERO
	var ch: Vector3 = J[1] if J.size() > 1 and J[1] is Vector3 else Vector3.ZERO
	var hd: Vector3 = J[0] if J.size() > 0 and J[0] is Vector3 else Vector3.ZERO
	var b := func(x) -> float: return 1.0 if x else 0.0
	var r := PackedFloat32Array([
		_t, st.x, st.y, st.z, st.v, st.vy, st.heading, st.course, st.slip, st.pitch, st._g_pitch,
		st.lean, st.bike_lean, st.counter, st.rock, st.bank, st._bank_raw, st.lat_a, st.n_load / BikePhysics.G, st.steer, st.steer_in,
		b.call(st.air), st.air_time, b.call(st.front_air), b.call(st.rear_air), st.compress, st.body_y - st.y, st.body_x, st.hip_shift,
		st.flick, st.body_in, st.air_stick.x, st.air_stick.y, st.manual_up, st.wheelie_up, st.edge_s, st.stick_yaw,
		st.sprint, st.stamina, b.call(st.crash_on), b.call(st.brake_stop),
		float(inp.get("throttle", 0.0)), float(inp.get("brake", 0.0)), float(inp.get("steer", 0.0)),
		float(inp.get("body_fwd", 0.0)), float(inp.get("body_lean", 0.0)), b.call(inp.get("hop", false)), b.call(inp.get("sprint", false)), b.call(inp.get("pad", false)),
		lift, drawn_y, pel.x, pel.y, pel.z, ch.x, ch.y, ch.z, hd.x, hd.y, hd.z,
		st.whip, st.whip_hold, st.flick_kick, Input.get_action_strength("body_right") - Input.get_action_strength("body_left"),
		Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
	])
	_rows[_head] = r
	_head = (_head + 1) % _rows.size()
	_count = mini(_count + 1, _rows.size())

## writes the buffer (oldest first) and returns the file's full path ("" if it failed). `mark` = the time
## the player pressed the button (the last row), so "seconds before the press" is easy to read
func save() -> String:
	DirAccess.make_dir_recursive_absolute("user://ridelogs")
	var path := "user://ridelogs/ride_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	f.store_line("# Mini BMX ride log: last %.0f s at %d Hz, saved at t=%.2f s (the last row = the moment of the press). before_press = seconds before it" % [SECS, HZ, _t])
	f.store_line("before_press," + ",".join(COLS))
	var n := _rows.size()
	for i in _count:
		var r: PackedFloat32Array = _rows[(_head - _count + i + n) % n]
		var parts := PackedStringArray(["%.3f" % (_t - r[0])])
		for v in r: parts.append("%.4f" % v)
		f.store_line(",".join(parts))
	f.close()
	return ProjectSettings.globalize_path(path)
