## The bike computer's piezo buzzer, with the tones a real GPS bike computer makes: power-on chime,
## key beep, satellites found, timer auto-pause (falling two-note) / resume (rising two-note), auto lap
## (three even beeps every km), navigation turn prompt, feature-ahead double beep, low battery (falling
## three-note), a new best jump (a short fanfare) and the incident-detection alarm (knocked out). Tuned to be easy on the ear: near-pure sine tones around 1–2.6 kHz, a soft attack and a gentle ring-out; rendered once into AudioStreamWAVs and played on the SFX bus.
extends AudioStreamPlayer

const RATE := 44100
const RES := 3600.0      # Hz, the disc's resonance: tones near it are loudest

static var _tones := {}   # name -> AudioStreamWAV

# notes: [hz (0 = rest), seconds]. Piezo-friendly pitches (C7 2093, E7 2637, F7 2794, G7 3136, A7 3520,
# A#7 3729, C8 4186): a real unit plays its prompts high up near the disc's resonance, short and square.
const TONES := {
	# power on: soft rising arpeggio (C6 E6 G6 C7) with a held top note
	"power": [[1047.0, 0.09], [0.0, 0.03], [1319.0, 0.09], [0.0, 0.03], [1568.0, 0.09], [0.0, 0.03], [2093.0, 0.32]],
	"key": [[1760.0, 0.05]],
	"gps": [[1319.0, 0.08], [0.0, 0.03], [1760.0, 0.2]],
	"resume": [[1397.0, 0.1], [0.0, 0.03], [1865.0, 0.22]],
	"pause": [[1865.0, 0.1], [0.0, 0.03], [1397.0, 0.26]],
	"lap": [[1760.0, 0.09], [0.0, 0.08], [1760.0, 0.09], [0.0, 0.08], [1760.0, 0.14]],
	"turn": [[1568.0, 0.09], [0.0, 0.03], [2093.0, 0.09], [0.0, 0.03], [1568.0, 0.22]],
	"feature": [[1865.0, 0.07], [0.0, 0.06], [1865.0, 0.12]],
	"battery": [[1568.0, 0.14], [0.0, 0.05], [1319.0, 0.14], [0.0, 0.05], [1047.0, 0.34]],
	"record": [[1047.0, 0.08], [0.0, 0.02], [1319.0, 0.08], [0.0, 0.02], [1568.0, 0.08], [0.0, 0.02],
		[2093.0, 0.12], [0.0, 0.05], [1568.0, 0.08], [0.0, 0.02], [2093.0, 0.4]],
	# shifted into the last gear: a short high double blip
	"gear_end": [[2093.0, 0.04], [0.0, 0.04], [2093.0, 0.07]],
	# no gear left that way: a low soft "no"
	"gear_none": [[1047.0, 0.08], [0.0, 0.04], [1047.0, 0.16]],
	"incident": [[2093.0, 0.13], [1397.0, 0.13], [2093.0, 0.13], [1397.0, 0.13], [2093.0, 0.13], [1397.0, 0.13],
		[0.0, 0.2], [2093.0, 0.13], [1397.0, 0.13], [2093.0, 0.13], [1397.0, 0.13], [2093.0, 0.13], [1397.0, 0.13]],
	# points banked / combos / pickups, same piezo voice as the rest
	"points": [[1568.0, 0.06], [0.0, 0.02], [2093.0, 0.14]],
	"combo": [[1760.0, 0.06], [0.0, 0.02], [2217.0, 0.06], [0.0, 0.02], [2637.0, 0.18]],
	"gain": [[1760.0, 0.07]],
	"pickup": [[1319.0, 0.07], [0.0, 0.02], [1760.0, 0.07], [0.0, 0.02], [2093.0, 0.2]],
}

func _ready() -> void:
	bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	volume_db = -15.0
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
	total += 0.08   # ring-out
	var count := int(total * RATE)
	var buf := PackedFloat32Array(); buf.resize(count)
	var i0 := 0
	for n in notes:
		var hz: float = n[0]
		var n_len := int(float(n[1]) * RATE)
		if hz > 0.0:
			# louder near the resonance, like a real piezo
			var gain := 0.55 + 0.45 / (1.0 + pow((hz - RES) / 1800.0, 2.0))
			var ring := int(0.06 * RATE)
			for j in n_len + ring:
				var t := float(j) / RATE
				var env := minf(1.0, t / 0.007)                                   # soft 7 ms attack
				if j > n_len: env *= exp(-float(j - n_len) / (0.014 * RATE))         # gentle ring-out
				else: env *= 1.0 - 0.25 * float(j) / maxf(1.0, float(n_len))   # slight decay so held notes breathe
				var ph := TAU * hz * t
				# square-ish: fundamental + weak odd harmonics (the disc filters the rest)
				var s := sin(ph) + 0.09 * sin(2.0 * ph) + 0.04 * sin(3.0 * ph)
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
