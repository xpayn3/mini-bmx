class_name ShiftSound
extends Node
## The gear shift: the user's own recording of a shifter (Downloads "shifter sound.mp3", 2026-11-20),
## cut into its six shifts (`assets/audio/shifter/shift_0..5.ogg`: lever in + spring back, ~0.5 s each,
## starting 8 ms before the first click, rumble high-passed out, tails faded, peak-normalised).
## Each shift plays one at random (never the same twice in a row) with a touch of pitch spread.
## (Three synthesised versions were tried first; the user wanted the real thing.)

const CLIPS := 6
const DB := -6.0

static var _clips: Array = []

var player := AudioStreamPlayer.new()
var _last := -1

func _ready() -> void:
	player.bus = Settings.bus_for("Bike")
	player.max_polyphony = 3
	player.volume_db = DB
	add_child(player)
	if _clips.is_empty():
		for i in CLIPS:
			var s = load("res://assets/audio/shifter/shift_%d.ogg" % i)
			if s != null: _clips.append(s)

## the shifter was clicked (d = +1 easier, -1 harder: the recording covers both)
func shift(_d: int) -> void:
	if _clips.is_empty(): return
	var i := randi() % _clips.size()
	if i == _last and _clips.size() > 1: i = (i + 1) % _clips.size()
	_last = i
	player.stream = _clips[i]
	player.pitch_scale = randf_range(0.98, 1.02)
	player.play()
