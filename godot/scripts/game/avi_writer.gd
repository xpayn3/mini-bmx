class_name AviWriter
extends RefCounted
## A minimal Motion-JPEG AVI file (RIFF AVI, one video stream, an idx1 index): every frame a JPEG. Plays in VLC,
## the Windows Media Player / Films & TV apps and video editors. Used by the instant replay's clip export
## (ReplayMode.export_clip). Godot only writes video itself in Movie Maker mode (a command-line start), hence this.
##   var w := AviWriter.new(); w.open(path, width, height, 30); w.add_jpeg(img.save_jpg_to_buffer(0.9)); w.close()

var f: FileAccess
var w := 0
var h := 0
var fps := 30
var frames := 0
var _idx := PackedByteArray()
var _movi_at := 0        # file offset of the "movi" fourcc (index offsets count from here)
var _riff_size_at := 4
var _movi_size_at := 0
var _avih_frames_at := 0
var _strh_len_at := 0
var _max_bytes := 0

func open(path: String, width: int, height: int, rate: int) -> bool:
	f = FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	w = width; h = height; fps = rate
	_fourcc("RIFF"); f.store_32(0); _fourcc("AVI ")
	_fourcc("LIST"); f.store_32(4 + 8 + 56 + 8 + 4 + 8 + 56 + 8 + 40); _fourcc("hdrl")
	# main header
	_fourcc("avih"); f.store_32(56)
	f.store_32(int(1000000.0 / fps))   # microseconds per frame
	f.store_32(0)                      # max bytes per second (patched)
	f.store_32(0)                      # padding granularity
	f.store_32(0x10)                   # AVIF_HASINDEX
	_avih_frames_at = f.get_position()
	f.store_32(0)                      # total frames (patched)
	f.store_32(0)                      # initial frames
	f.store_32(1)                      # streams
	f.store_32(w * h * 3)              # suggested buffer size
	f.store_32(w); f.store_32(h)
	for i in 4: f.store_32(0)
	# the video stream
	_fourcc("LIST"); f.store_32(4 + 8 + 56 + 8 + 40); _fourcc("strl")
	_fourcc("strh"); f.store_32(56)
	_fourcc("vids"); _fourcc("MJPG")
	f.store_32(0)                      # flags
	f.store_16(0); f.store_16(0)       # priority, language
	f.store_32(0)                      # initial frames
	f.store_32(1); f.store_32(fps)     # scale, rate: fps frames per second
	f.store_32(0)                      # start
	_strh_len_at = f.get_position()
	f.store_32(0)                      # length (patched)
	f.store_32(w * h * 3)              # suggested buffer size
	f.store_32(0xFFFFFFFF)             # quality: default
	f.store_32(0)                      # sample size
	f.store_16(0); f.store_16(0); f.store_16(w); f.store_16(h)
	_fourcc("strf"); f.store_32(40)    # BITMAPINFOHEADER
	f.store_32(40); f.store_32(w); f.store_32(h)
	f.store_16(1); f.store_16(24)
	_fourcc("MJPG")
	f.store_32(w * h * 3)
	f.store_32(0); f.store_32(0); f.store_32(0); f.store_32(0)
	# the frames
	_fourcc("LIST")
	_movi_size_at = f.get_position()
	f.store_32(0)
	_movi_at = f.get_position()
	_fourcc("movi")
	return true

func add_jpeg(jpg: PackedByteArray) -> void:
	if f == null or jpg.is_empty(): return
	var at := f.get_position()
	_fourcc("00dc"); f.store_32(jpg.size())
	f.store_buffer(jpg)
	if jpg.size() % 2 == 1: f.store_8(0)   # (chunks are word aligned)
	var e := PackedByteArray()
	e.resize(16)
	e.encode_u32(0, 0x63643030)          # "00dc"
	e.encode_u32(4, 0x10)                # AVIIF_KEYFRAME
	e.encode_u32(8, at - _movi_at)
	e.encode_u32(12, jpg.size())
	_idx.append_array(e)
	frames += 1
	_max_bytes = maxi(_max_bytes, jpg.size())

func close() -> void:
	if f == null: return
	var movi_end := f.get_position()
	_fourcc("idx1"); f.store_32(_idx.size()); f.store_buffer(_idx)
	var end := f.get_position()
	f.seek(_riff_size_at); f.store_32(end - 8)
	f.seek(_movi_size_at); f.store_32(movi_end - _movi_at)
	f.seek(_avih_frames_at); f.store_32(frames)
	f.seek(_strh_len_at); f.store_32(frames)
	f.seek(36); f.store_32(_max_bytes * fps)   # (avih max bytes / s: after RIFF, hdrl LIST, avih + its first field)
	f.close()
	f = null

func _fourcc(s: String) -> void:
	f.store_buffer(s.to_ascii_buffer())
