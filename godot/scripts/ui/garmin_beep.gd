## The bike computer's piezo buzzer: a power-on chime when the ride starts and a short key beep on the
## bezel buttons. A piezo disc is a square-ish tone with a strong resonance around 3–4 kHz, a hard
## start and a tiny ring-out; rendered once into AudioStreamWAVs and played on the SFX bus.
extends AudioStreamPlayer

const RATE := 44100
const RES := 3600.0      # Hz, the disc's resonance: tones near it are loudest

static var _power: AudioStreamWAV
static var _key: AudioStreamWAV

func _ready() -> void:
	bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	volume_db = -9.0
	max_polyphony = 3
	if _power == null:
		# power on: three quick rising notes and a held top note (C7 E7 G7 C8)
		_power = _render([[2093.0, 0.075], [0.0, 0.025], [2637.0, 0.075], [0.0, 0.025],
			[3136.0, 0.075], [0.0, 0.025], [4186.0, 0.22]])
		_key = _render([[3520.0, 0.04]])

func power_on() -> void:
	if not ComputerUnits.opt(GameState.computer_id, "beep"): return
	stream = _power
	play()

func key() -> void:
	if not ComputerUnits.opt(GameState.computer_id, "beep"): return
	stream = _key
	play()

## notes = [[hz (0 = silence), seconds], ...]
static func _render(notes: Array) -> AudioStreamWAV:
	var total := 0.0
	for n in notes: total += n[1]
	total += 0.03   # ring-out
	var count := int(total * RATE)
	var buf := PackedFloat32Array(); buf.resize(count)
	var i0 := 0
	for n in notes:
		var hz: float = n[0]
		var n_len := int(float(n[1]) * RATE)
		if hz > 0.0:
			# louder near the resonance, like a real piezo
			var gain := 1.0 / (1.0 + pow((hz - RES) / 1800.0, 2.0))
			var ring := int(0.012 * RATE)
			for j in n_len + ring:
				var t := float(j) / RATE
				var env := minf(1.0, t / 0.002)                                   # hard 2 ms attack
				if j > n_len: env *= exp(-float(j - n_len) / (0.003 * RATE))         # tiny ring-out
				elif j > n_len - int(0.004 * RATE): env *= 0.9
				var ph := TAU * hz * t
				# square-ish: fundamental + weak odd harmonics (the disc filters the rest)
				var s := sin(ph) + 0.28 * sin(3.0 * ph) + 0.1 * sin(5.0 * ph)
				var k := i0 + j
				if k < count: buf[k] += s * env * gain * 0.55
		i0 += n_len
	var data := PackedByteArray(); data.resize(count * 2)
	for k in count:
		data.encode_s16(k * 2, int(clampf(buf[k], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
