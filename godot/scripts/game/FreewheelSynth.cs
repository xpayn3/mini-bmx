using System;
using Godot;

/// Procedural freewheel (freehub pawls clicking while coasting), modelled on a real recording
/// (freesound_community "bicycle forward movement"): every click is a short, bright noise crack plus
/// the hub's resonances, damped to a few ms and detuned per click so it ticks instead of chiming. Clicks come in an uneven pawl pattern
/// with varied strength. Speed changes only the click RATE, never the tone, so the ramp from slow
/// ticks to a fast buzz stays crisp. One Render() call per frame from ride_audio.gd.
public partial class FreewheelSynth : RefCounted
{
	// freq Hz, gain, decay (s to 1/e) - the recording's click resonances, kept short and dry (long, pure
	// rings read as a glass bottle); each click re-detunes them a little so no one note sticks out
	private static readonly double[,] MODES = {
		{ 5490, 0.80, 0.0075 }, { 5813, 0.60, 0.0060 }, { 4371, 0.45, 0.0065 }, { 7568, 0.60, 0.0045 },
		{ 3843, 0.40, 0.0060 }, { 2594, 0.30, 0.0050 }, { 1450, 0.12, 0.0030 }, { 9800, 0.50, 0.0030 },
		{ 8650, 0.50, 0.0035 }, { 11200, 0.35, 0.0020 },
	};
	private const double DETUNE = 0.035;   // +-3.5 % per click
	// uneven engagement spacing (4 pawls), mean ~1
	private static readonly double[] PAWL = { 0.62, 1.05, 1.12, 1.21 };
	private const double EXCITE = 0.06;
	private const double CRACK = 0.75;
	private const double CRACK_DECAY = 0.94;   // per sample: ~0.4 ms

	private readonly int _m = MODES.GetLength(0);
	private readonly double[] _c1, _c2, _g, _y1, _y2, _ex;
	private readonly Random _rng = new Random(1234);
	private double _ph, _next = 1.0, _burst, _hpz, _amp, _rate;
	private int _pawl;
	// player-tunable sound (Sound tab of the tuning card; 1 / defaults = the recording)
	private double _pitch = 1.0, _ringK = 1.0, _crackK = 1.0, _crackLen = 1.0, _detune = DETUNE, _tilt = 0.0,
		_uneven = 1.0, _jitter = 0.06, _vary = 0.55, _crackDecay = CRACK_DECAY;

	/// pitch: all resonances x; ring: decay x; crack: snap amount x; crackLen: snap length x;
	/// detune: +-fraction per click; tilt: -1 dark .. +1 bright; uneven: pawl spacing spread x;
	/// jitter: timing randomness; vary: click strength randomness (0..1)
	public void SetParams(double pitch, double ring, double crack, double crackLen, double detune, double tilt,
		double uneven, double jitter, double vary)
	{
		_pitch = Math.Clamp(pitch, 0.2, 3.0); _ringK = Math.Clamp(ring, 0.1, 6.0); _crackK = Math.Max(0.0, crack);
		_crackLen = Math.Clamp(crackLen, 0.1, 6.0); _detune = Math.Clamp(detune, 0.0, 0.5); _tilt = Math.Clamp(tilt, -2.0, 2.0);
		_uneven = Math.Clamp(uneven, 0.0, 3.0); _jitter = Math.Clamp(jitter, 0.0, 0.4); _vary = Math.Clamp(vary, 0.0, 1.0);
		_crackDecay = Math.Pow(CRACK_DECAY, 1.0 / _crackLen);
		for (int k = 0; k < _m; k++)
		{
			double f = MODES[k, 0] * _pitch;
			// tilt: gain x (f / 4.5 kHz)^tilt, so + lifts the high modes and - the low ones
			_g[k] = MODES[k, 1] * Math.Pow(f / 4500.0, _tilt);
			SetMode(k, f);
		}
	}

	public FreewheelSynth() : this(44100.0) { }

	public FreewheelSynth(double sr)
	{
		_c1 = new double[_m]; _c2 = new double[_m]; _g = new double[_m];
		_y1 = new double[_m]; _y2 = new double[_m]; _ex = new double[_m];
		Sr = sr;
		for (int k = 0; k < _m; k++)
		{
			_g[k] = MODES[k, 1];
			_ex[k] = 1.0;
			SetMode(k, MODES[k, 0]);
		}
	}

	private void SetMode(int k, double f)
	{
		double r = Math.Exp(-1.0 / (MODES[k, 2] * _ringK * Sr));
		double w = 2.0 * Math.PI * Math.Min(f, Sr * 0.45) / Sr;
		_c1[k] = 2.0 * r * Math.Cos(w);
		_c2[k] = -r * r;
	}

	public double Sr { get; private set; }

	/// n stereo frames. clicks: pawl clicks per second (0 = none, the ring still dies away naturally);
	/// amp: output gain. Both glide over the block so nothing zips.
	public Vector2[] Render(int n, double clicks, double amp)
	{
		var buf = new Vector2[n];
		double a0 = _amp, r0 = _rate;
		for (int i = 0; i < n; i++)
		{
			double t = (i + 1.0) / n;
			double cr = r0 + (clicks - r0) * t;
			double ga = a0 + (amp - a0) * t;
			double imp = 0.0;
			_ph += cr / Sr;
			if (cr > 0.5 && _ph >= _next)
			{
				_ph -= _next;
				_next = Math.Max(0.05, (1.0 + (PAWL[_pawl] - 1.0) * _uneven) * (1.0 + Gauss() * _jitter));
				_pawl = (_pawl + 1) % PAWL.Length;
				double a = 1.0 - _vary + _vary * _rng.NextDouble();
				if (_pawl == 0) a *= 1.15;
				imp = a; _burst = a;
				for (int k = 0; k < _m; k++)
				{
					_ex[k] = 0.5 + 1.0 * _rng.NextDouble();
					SetMode(k, MODES[k, 0] * _pitch * (1.0 + (_rng.NextDouble() * 2.0 - 1.0) * _detune));
				}
			}
			else if (cr <= 0.5)
				_ph = 0.0;
			double s = 0.0;
			for (int k = 0; k < _m; k++)
			{
				double y = _c1[k] * _y1[k] + _c2[k] * _y2[k] + imp * _g[k] * _ex[k] * EXCITE;
				_y2[k] = _y1[k]; _y1[k] = y; s += y;
			}
			if (_burst > 1e-4)
			{
				double nz = _rng.NextDouble() * 2.0 - 1.0;
				s += (nz - _hpz) * _burst * CRACK * _crackK;   // differentiated noise: all crack, no thump
				_hpz = nz;
				_burst *= _crackDecay;
			}
			float v = (float)(s * ga);
			buf[i] = new Vector2(v, v);
		}
		_amp = amp; _rate = clicks;
		return buf;
	}

	private double Gauss()
	{
		double u = 1.0 - _rng.NextDouble(), v = _rng.NextDouble();
		return Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
	}
}
