extends Label3D
## The action cam's front LCD: the recording time (M:SS, H:MM:SS past an hour) in the bike computer's
## dot-matrix font. Counts game time from when the camera was built (a ride start / a new camera after a
## crash), so it stops in photo mode and runs slow in crash slow motion like everything else.

var rec_t := 0.0
var _shown := -1

func _ready() -> void:
	_show()

func _process(dt: float) -> void:
	rec_t += dt
	if int(rec_t) != _shown:
		_show()

func _show() -> void:
	_shown = int(rec_t)
	var s := _shown % 60
	var m := (_shown / 60) % 60
	var h := _shown / 3600
	text = "%d:%02d:%02d" % [h, m, s] if h > 0 else "%d:%02d" % [m, s]
