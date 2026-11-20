## The bike computer's piezo buzzer, with the tones a real GPS bike computer makes: power-on chime,
## key beep, satellites found, timer auto-pause (falling two-note) / resume (rising two-note), auto lap
## (three even beeps every km), navigation turn prompt, feature-ahead double beep, low battery (falling
## three-note), a new best jump (a short fanfare) and the incident-detection alarm (knocked out). A piezo disc is a square-ish tone with a strong resonance around 3–4 kHz, a hard
## start and a tiny ring-out; rendered once into AudioStreamWAVs and played on the SFX bus.
extends AudioStreamPlayer

const RATE := 44100
const RES := 3600.0      # Hz, the disc's resonance: tones near it are loudest

static var _tones := {}   # name -> AudioStreamWAV

# notes: [hz (0 = rest), seconds]. Piezo-friendly pitches (C7 2093, E7 2637, F7 2794, G7 3136, A7 3520,
# A#7 3729, C8 4186): a real unit plays its prompts high up near the disc's resonance, short and square.
const TONES := {
	# power on: three quick rising notes and a held top note (C7 E7 G7 C8)
	"power": [[2093.0, 0.075], [0.0, 0.025], [2637.0, 0.075], [0.0, 0.025], [3136.0, 0.075], [0.0, 0.025], [4186.0, 0.22]],
	"key": [[3520.0, 0.04]],
	"gps": [[2637.0, 0.06], [0.0, 0.03], [3520.0, 0.12]],
	"resume": [[2794.0, 0.09], [0.0, 0.025], [3729.0, 0.15]],
	"pause": [[3729.0, 0.09], [0.0, 0.025], [2794.0, 0.17]],
	"lap": [[3520.0, 0.07], [0.0, 0.07], [3520.0, 0.07], [0.0, 0.07], [3520.0, 0.07]],
	"turn": [[3136.0, 0.07], [0.0, 0.02], [4186.0, 0.07], [0.0, 0.02], [3136.0, 0.14]],
	"feature": [[3729.0, 0.05], [0.0, 0.05], [3729.0, 0.05]],
	"battery": [[3136.0, 0.12], [0.0, 0.04], [2637.0, 0.12], [0.0, 0.04], [2093.0, 0.24]],
	"record": [[2093.0, 0.07], [0.0, 0.02], [2637.0, 0.07], [0.0, 0.02], [3136.0, 0.07], [0.0, 0.02],
		[4186.0, 0.1], [0.0, 0.05], [3136.0, 0.07], [0.0, 0.02], [4186.0, 0.28]],
	# shifted into the last gear (easiest or hardest cog): a short high double blip
	"gear_end": [[4186.0, 0.035], [0.0, 0.03], [4186.0, 0.05]],
	# tried to shift past the end / on a single speed: a low flat "no" buzz
	"gear_none": [[2093.0, 0.07], [0.0, 0.03], [2093.0, 0.12]],
	"incident": [[4186.0, 0.11], [2794.0, 0.11], [4186.0, 0.11], [2794.0, 0.11], [4186.0, 0.11], [2794.0, 0.11],
		[0.0, 0.18], [4186.0, 0.11], [2794.0, 0.11], [4186.0, 0.11], [2794.0, 0.11], [4186.0, 0.11], [2794.0, 0.11]],
}

func _ready() -> void:
	bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	volume_db = -9.0
	max_polyphony = 3
	if _tones.is_empty():
		for k in TONES: _tones[k] = _render(TONES[k])

## play a tone by name (TONES), if this unit's beeper is on
func tone(name: String) -> void:
	if not ComputerUnits.opt(GameState.computer_id, "beep") or not _tones.has(name): return
	if Env.s("BMX_BEEP_PROBE") != "": print("BEEP ", name)
	stream = _tones[name]
	play()

func power_on() -> void: tone("power")
func key() -> void: tone("key")

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
