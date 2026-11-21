class_name RideLog
extends RefCounted
## The last SECS seconds of the ride, every physics step (120 Hz): the bike's physics, the rider's body,
## the drawn bike's corrections and the player's inputs. Kept in a ring buffer the whole ride (cheap: one
## flat PackedFloat32Array written in place); "save_log" (R3 / F8) writes it to user://ridelogs/ride_<date>.csv, the
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
	"in_brake_f", "in_brake_r", "front_use", "front_lock", "rear_lock", "corner_g", "knock", "lean_err", "weight_in", "balance",
]

const ROWS := int(SECS * HZ)
const NC := 75   # = COLS.size()
var _buf := PackedFloat32Array()   # ROWS x NC floats, written in place (no per-step arrays)
var _head := 0
var _count := 0
var _t := 0.0

func _init() -> void:
	assert(COLS.size() == NC)
	_buf.resize(ROWS * NC)

func record(dt: float, st: BikePhysics, inp: Dictionary, lift: float, drawn_y: float, J: Array) -> void:
	_t += dt
	var pel: Vector3 = J[2] if J.size() > 2 and J[2] is Vector3 else Vector3.ZERO
	var ch: Vector3 = J[1] if J.size() > 1 and J[1] is Vector3 else Vector3.ZERO
	var hd: Vector3 = J[0] if J.size() > 0 and J[0] is Vector3 else Vector3.ZERO
	var o := _head * NC
	_buf[o + 0] = _t
	_buf[o + 1] = st.x
	_buf[o + 2] = st.y
	_buf[o + 3] = st.z
	_buf[o + 4] = st.v
	_buf[o + 5] = st.vy
	_buf[o + 6] = st.heading
	_buf[o + 7] = st.course
	_buf[o + 8] = st.slip
	_buf[o + 9] = st.pitch
	_buf[o + 10] = st._g_pitch
	_buf[o + 11] = st.lean
	_buf[o + 12] = st.bike_lean
	_buf[o + 13] = st.counter
	_buf[o + 14] = st.rock
	_buf[o + 15] = st.bank
	_buf[o + 16] = st._bank_raw
	_buf[o + 17] = st.lat_a
	_buf[o + 18] = st.n_load / BikePhysics.G
	_buf[o + 19] = st.steer
	_buf[o + 20] = st.steer_in
	_buf[o + 21] = float(st.air)
	_buf[o + 22] = st.air_time
	_buf[o + 23] = float(st.front_air)
	_buf[o + 24] = float(st.rear_air)
	_buf[o + 25] = st.compress
	_buf[o + 26] = st.body_y - st.y
	_buf[o + 27] = st.body_x
	_buf[o + 28] = st.hip_shift
	_buf[o + 29] = st.flick
	_buf[o + 30] = st.body_in
	_buf[o + 31] = st.air_stick.x
	_buf[o + 32] = st.air_stick.y
	_buf[o + 33] = st.man_a
	_buf[o + 34] = st.wheelie_up
	_buf[o + 35] = st.edge_s
	_buf[o + 36] = st.stick_yaw
	_buf[o + 37] = st.sprint
	_buf[o + 38] = st.stamina
	_buf[o + 39] = float(st.crash_on)
	_buf[o + 40] = float(st.brake_stop)
	_buf[o + 41] = float(inp.get("throttle", 0.0))
	_buf[o + 42] = float(inp.get("brake", 0.0))
	_buf[o + 43] = float(inp.get("steer", 0.0))
	_buf[o + 44] = float(inp.get("body_fwd", 0.0))
	_buf[o + 45] = float(inp.get("body_lean", 0.0))
	_buf[o + 46] = float(inp.get("hop", false))
	_buf[o + 47] = float(inp.get("sprint", false))
	_buf[o + 48] = float(inp.get("pad", false))
	_buf[o + 49] = lift
	_buf[o + 50] = drawn_y
	_buf[o + 51] = pel.x
	_buf[o + 52] = pel.y
	_buf[o + 53] = pel.z
	_buf[o + 54] = ch.x
	_buf[o + 55] = ch.y
	_buf[o + 56] = ch.z
	_buf[o + 57] = hd.x
	_buf[o + 58] = hd.y
	_buf[o + 59] = hd.z
	_buf[o + 60] = st.whip
	_buf[o + 61] = st.whip_hold
	_buf[o + 62] = st.flick_kick
	_buf[o + 63] = Input.get_action_strength("body_right") - Input.get_action_strength("body_left")
	_buf[o + 64] = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	_buf[o + 65] = st.brake_f
	_buf[o + 66] = st.brake_r
	_buf[o + 67] = st.front_use
	_buf[o + 68] = st.front_lock
	_buf[o + 69] = st.rear_lock
	_buf[o + 70] = st.corner_g
	_buf[o + 71] = st.knock
	_buf[o + 72] = st.lean_err
	_buf[o + 73] = st.weight_in
	_buf[o + 74] = st.bal_k
	_head = (_head + 1) % ROWS
	_count = mini(_count + 1, ROWS)

## writes the buffer (oldest first) and returns the file's full path ("" if it failed). `mark` = the time
## the player pressed the button (the last row), so "seconds before the press" is easy to read
func save(path := "") -> String:
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://ridelogs")
		path = "user://ridelogs/ride_%s.csv" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return ""
	f.store_line("# Mini BMX ride log: last %.0f s at %d Hz, saved at t=%.2f s (the last row = the moment of the press). before_press = seconds before it" % [SECS, HZ, _t])
	f.store_line("before_press," + ",".join(COLS))
	for i in _count:
		var o := ((_head - _count + i + ROWS) % ROWS) * NC
		var parts := PackedStringArray(["%.3f" % (_t - _buf[o])])
		for k in NC: parts.append("%.4f" % _buf[o + k])
		f.store_line(",".join(parts))
	f.close()
	return ProjectSettings.globalize_path(path)
