using System;
using Godot;

/// Procedural freewheel (freehub pawls clicking while coasting), modelled on a real recording
/// (freesound_community "bicycle forward movement"): every click is a short noise crack plus the hub's
/// resonances, damped to a few ms and detuned per click so it ticks instead of chiming.
/// One Render() call per frame from ride_audio.gd. Research + measurements: docs/research/freewheel.md.
///
/// How a real hub behaves and what this copies (2026-11-28 model):
/// - the ratchet's teeth are machined evenly: a click fires as the wheel passes each tooth's FIXED place
///   (`_tp` = the wheel's position in teeth), with a small offset per tooth that comes back every turn and a
///   tiny random one. Nothing accumulates, so at speed the clicks form a clean buzz whose pitch is the click rate;
/// - phased pawls (two sets half a tooth apart) are never perfectly in phase: odd / even clicks sit a touch off;
///   several pawls landing together make each click a 2-3 tick flam within a fraction of a millisecond;
/// - each click is as loud at walking pace as at speed (the pawl's spring sets the hit); the clicks only get
///   softer, duller and shorter once a tooth passes faster than the pawl can fall into the next valley
///   (`dropMs`: the pawls "float"), so that depends on the click RATE, not on km/h;
/// - the snap is low-passed (`SNAP_LP`): the real hub's energy sits at 2-8 kHz, almost none over 12 kHz;
/// - the hub shell's ring tones don't move with speed; a little low body is the wheel acting as a soundboard.
/// BMX_OLD_FWSYNTH=1 = the model before (random chained intervals, 4-step pawl pattern, full-band snap,
/// speed effects by km/h from ride_audio.gd's `fast`).
public partial class FreewheelSynth : RefCounted
{
	public static readonly bool OLD = DevFlags.Env("BMX_OLD_FWSYNTH") is { Length: > 0 };

	// freq Hz, gain, decay (s to 1/e) - the recording's click resonances, kept short and dry (long, pure
	// rings read as a glass bottle); each click re-detunes them a little so no one note sticks out
	private static readonly double[,] MODES_OLD = {
		{ 5490, 0.80, 0.0075 }, { 5813, 0.60, 0.0060 }, { 4371, 0.45, 0.0065 }, { 7568, 0.60, 0.0045 },
		{ 3843, 0.40, 0.0060 }, { 2594, 0.30, 0.0050 }, { 1450, 0.12, 0.0030 }, { 9800, 0.50, 0.0030 },
		{ 8650, 0.50, 0.0035 }, { 11200, 0.35, 0.0020 },
	};
	// the same hub with the top modes taken down (the recording has ~nothing past 12 kHz) and the wheel's
	// low body (rim + spokes carrying the hub's knock) added at the bottom
	private static readonly double[,] MODES_NEW = {
		{ 5490, 0.80, 0.0075 }, { 5813, 0.60, 0.0060 }, { 4371, 0.50, 0.0065 }, { 7568, 0.70, 0.0045 },
		{ 3843, 0.45, 0.0060 }, { 2594, 0.34, 0.0050 }, { 1450, 0.12, 0.0030 }, { 9800, 0.16, 0.0030 },
		{ 8650, 0.42, 0.0035 }, { 11200, 0.05, 0.0020 }, { 760, 0.022, 0.0045 }, { 1130, 0.030, 0.0040 },
	};
	private static readonly double[,] MODES = OLD ? MODES_OLD : MODES_NEW;
	private const double DETUNE = 0.035;   // +-3.5 % per click
	// old model: uneven engagement spacing (4 pawls), mean ~1
	private static readonly double[] PAWL = { 0.62, 1.05, 1.12, 1.21 };
	private const double EXCITE = 0.06;
	private const double CRACK = 0.75;
	private const double CRACK_DECAY = 0.94;   // per sample: ~0.4 ms
	// new model
	private const double SNAP_LP = 6000.0;     // Hz, three one-pole stages on the snap (with its +6 dB/oct rise: a peak ~4-6 kHz,
	                                           // -12 dB/oct above: two stages still left the top 12-20 kHz at -11 dB, the recording < -50)
	private const double SNAP_GAIN = 2.4;      // the low-pass takes ~7 dB of the snap's level: put it back
	private const double PHASE_AB = 0.015;     // teeth: odd / even clicks off by this x uneven (phased pawl sets; 0.04 already
	                                           // made every 2nd click the strongest rhythm, an octave under the click rate)
	private const double FLAM_P = 0.6;         // chance a click is a flam of several pawls
	private const double FLAM_GAP = 0.00025;   // s, mean gap between the flam's ticks
	private const double OFF_MAX = 0.3;        // teeth: a click never strays further from its tooth

	private readonly int _m = MODES.GetLength(0);
	private readonly double[] _c1, _c2, _g, _y1, _y2, _ex;
	// new model: a rotating (coupled-form) resonator per mode; retuning it never changes what is ringing
	private readonly double[] _re, _im, _rc, _rs, _isw;
	private readonly Random _rng = new Random(1234);
	private double _ph, _next = 1.0, _burst, _hpz, _amp, _rate;
	private int _pawl;
	// player-tunable sound (Sound tab of the tuning card; 1 / defaults = the recording)
	private double _pitch = 1.0, _ringK = 1.0, _crackK = 1.0, _crackLen = 1.0, _detune = DETUNE, _tilt = 0.0,
		_uneven = 1.0, _jitter = 0.06, _vary = 0.55, _crackDecay = CRACK_DECAY;
	// the wheel's turn + speed character (SetSpeedParams)
	private double _poe = 24.0, _warble = 0.0, _spPitch = 0.0, _spBright = 0.0, _spRing = 0.0, _repeat = 0.0, _spSoft = 0.0;
	private double _dropS = 0.002;
	// faster = harder hits: the pawl lands on the next tooth's ramp while that tooth is moving, so the impact
	// speed is the pawl's spring drop (~DROP_V) plus the tooth's speed x sin(ramp). With a ~22 mm ratchet that is
	// +10 % at 15 km/h, +35 % at 60 km/h (`_hit`, x `_spHit`): louder, brighter clicks the faster the wheel turns
	private const double RING_R = 0.022, RAMP = 0.3, DROP_V = 0.8;
	private double _spHit = 1.0, _hit;
	private double _clp, _crackG = 1.0, _crackK1 = 1.0;
	private double _rev, _fast, _ringE = 1.0;
	private int _ci;
	// new model: the wheel's position in teeth, the next tooth and where its click fires
	private double _tp, _fireAt = 1.0, _lp1, _lp2, _lp3, _lpK = 1.0;
	private long _tooth = 1;
	private int _fln; private double _flt, _fla;
	// a hit on the rear wheel (Knock): the pawls bounce off the ratchet and slap back = a quick loose flurry
	private int _kn; private double _kt, _ka;
	// road vibration through the rear wheel (SetShake, 0 smooth .. 1 rough): the pawls get knocked off
	// their rhythm, hit harder / softer, and the hub rattles on its own between them
	// (the timing is NOT touched: the pawls drop on the ratchet's teeth and the wheel's spin doesn't change
	// with a bump; a per-click timing spread bunched clicks up and left audible gaps at speed)
	private double _shake, _wob, _wobT, _wobN;
	private const double SHAKE_AMP = 0.35;     // depth of the loudness wobble at full shake
	private const double SHAKE_HZ = 28.0;      // how fast the wobble moves (the wheel / frame shaking)
	private const double SHAKE_RATTLE = 8.0;   // quiet loose ticks a second at full shake
	private const int TAB = 256;
	private readonly double[] _tabG = new double[TAB], _tabU = new double[TAB];   // one wheel turn's fixed pattern

	/// how far the pawls "float" right now (0 they reach every valley .. 1 they skim the tips); the new model
	/// works it out from the click rate, the old one follows Render's `fast`
	public double Fast => _fast;

	/// poe: clicks per wheel turn; warble: loudness / brightness swell per wheel turn (0..1);
	/// spPitch: resonances rise by this fraction at full float; spBright: tilt added at full float;
	/// spRing: ring shortened by this fraction at full float; repeat: share of the timing / strength
	/// pattern that comes back every wheel turn (0 = all random .. 1 = the same every turn);
	/// spSoft: at full float the click is this much quieter and duller (the pawls drop less far);
	/// dropMs: how long a pawl takes to fall into the next valley (new model: floating starts once a tooth
	/// passes in under ~2x this, full at ~2/3 of it)
	public void SetSpeedParams(double poe, double warble, double spPitch, double spBright, double spRing, double repeat,
		double spSoft = 0.0, double dropMs = 2.0, double spHit = 1.0)
	{
		_spHit = Math.Clamp(spHit, 0.0, 4.0);
		_spSoft = Math.Clamp(spSoft, 0.0, 1.0);
		_poe = Math.Clamp(poe, 1.0, 1000.0); _warble = Math.Clamp(warble, 0.0, 1.0);
		_spPitch = Math.Clamp(spPitch, -0.5, 1.0); _spBright = Math.Clamp(spBright, -2.0, 2.0);
		_spRing = Math.Clamp(spRing, 0.0, 0.9); _repeat = Math.Clamp(repeat, 0.0, 1.0);
		_dropS = Math.Clamp(dropMs, 0.1, 20.0) * 0.001;
	}

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
		_re = new double[_m]; _im = new double[_m]; _rc = new double[_m]; _rs = new double[_m]; _isw = new double[_m];
		Sr = sr;
		var tr = new Random(777);
		for (int i = 0; i < TAB; i++)
		{
			double u = 1.0 - tr.NextDouble(), v = tr.NextDouble();
			_tabG[i] = Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
			_tabU[i] = tr.NextDouble();
		}
		for (int k = 0; k < _m; k++)
		{
			_g[k] = MODES[k, 1];
			_ex[k] = 1.0;
			SetMode(k, MODES[k, 0]);
		}
	}

	private void SetMode(int k, double f)
	{
		double r = Math.Exp(-1.0 / (MODES[k, 2] * _ringK * _ringE * Sr));
		double w = 2.0 * Math.PI * Math.Min(f, Sr * 0.45) / Sr;
		_c1[k] = 2.0 * r * Math.Cos(w);
		_c2[k] = -r * r;
		_rc[k] = r * Math.Cos(w); _rs[k] = r * Math.Sin(w);
		_isw[k] = 1.0 / Math.Max(Math.Sin(w), 1e-3);   // the direct form's gain: keeps both models' levels alike
	}

	public double Sr { get; private set; }

	/// road vibration through the rear wheel, 0 smooth .. 1 rough (ride_audio.gd, every frame)
	public void SetShake(double k) { _shake = Math.Clamp(k, 0.0, 1.0); }

	/// a hit on the rear wheel (k 0..1: a bump .. a hard landing): 2-5 extra, loose pawl clicks over ~10-40 ms
	/// on top of the ratchet (a real hub rattles when the wheel is knocked while it freewheels)
	public void Knock(double k)
	{
		k = Math.Clamp(k, 0.0, 1.0);
		if (k < 0.02) return;
		_kn = Math.Max(_kn, 2 + (int)(k * 3.0 + _rng.NextDouble()));
		_ka = Math.Max(_ka, 0.45 + 0.75 * k);
		if (_kt <= 0.0) _kt = (0.0005 + 0.002 * _rng.NextDouble()) * Sr;
	}

	// one click: excite the hub's resonances and the snap (shared by the ratchet, flams and the knock flurry)
	private void Fire(double a, double wv, bool retune = true)
	{
		_burst = Math.Max(_burst, a);
		if (!retune) return;
		double pe = _pitch * (1.0 + _spPitch * _fast);
		double te = _tilt + _spBright * _fast + 0.4 * _warble * wv + 0.6 * _hit;
		_ringE = 1.0 - _spRing * _fast;
		for (int k = 0; k < _m; k++)
		{
			_ex[k] = 0.5 + 1.0 * _rng.NextDouble();
			_g[k] = MODES[k, 1] * Math.Pow(MODES[k, 0] * _pitch / 4500.0, te);
			SetMode(k, MODES[k, 0] * pe * (1.0 + (_rng.NextDouble() * 2.0 - 1.0) * _detune));
		}
	}

	/// n stereo frames. clicks: pawl clicks per second (0 = none, the ring still dies away naturally);
	/// amp: output gain. Both glide over the block so nothing zips. fast: (old model only) 0 slow .. 1 full
	/// speed character; the new model works out its float from the click rate.
	public Vector2[] Render(int n, double clicks, double amp, double fast = 0.0)
	{
		if (OLD) return RenderOld(n, clicks, amp, fast);
		// float: a tooth passes every 1 / clicks s; a pawl needs ~_dropS to fall into the valley
		double ft = SmoothStep(0.5, 1.5, clicks * _dropS);
		_fast += (ft - _fast) * Math.Min(1.0, n / (0.08 * Sr));
		double soft = 1.0 - 0.5 * _spSoft * _fast;       // a shorter fall = a weaker hit
		double toothV = clicks / _poe * 2.0 * Math.PI * RING_R * Math.Sin(RAMP);
		_hit += (_spHit * toothV / DROP_V - _hit) * Math.Min(1.0, n / (0.08 * Sr));
		soft *= 1.0 + _hit;
		_crackG = 1.0 - 0.6 * _spSoft * _fast;
		double fc = SNAP_LP * (1.0 - 0.45 * _spSoft * _fast) * (1.0 + 0.8 * _hit);
		_lpK = 1.0 - Math.Exp(-2.0 * Math.PI * fc / Sr);
		var buf = new Vector2[n];
		double a0 = _amp, r0 = _rate;
		int pr = Math.Max(1, (int)Math.Round(_poe));
		for (int i = 0; i < n; i++)
		{
			double t = (i + 1.0) / n;
			double cr = r0 + (clicks - r0) * t;
			double ga = a0 + (amp - a0) * t;
			double imp = 0.0;
			if (cr > 0.5)
			{
				_tp += cr / Sr;
				int guard = 4;
				while (_tp >= _fireAt && guard-- > 0)
				{
					_ci = (int)(((_tooth % pr) + pr) % pr) % TAB;
					// strength: part fixed per tooth (worn / tight teeth), part random
					double a = 1.0 - _vary + _vary * (_repeat * _tabU[_ci] + (1.0 - _repeat) * _rng.NextDouble());
					double turn = _tp / _poe;
					double wv = 0.7 * Math.Sin(2.0 * Math.PI * turn) + 0.3 * Math.Sin(4.0 * Math.PI * turn + 1.3);
					a *= Math.Max(0.1, 1.0 + _warble * wv) * soft;
					imp = a;
					Fire(a, wv);
					if (_rng.NextDouble() < FLAM_P)
					{
						_fln = 1 + (_rng.NextDouble() < 0.35 ? 1 : 0);
						_fla = a * (0.25 + 0.2 * _rng.NextDouble());
						_flt = FLAM_GAP * (0.4 + 1.2 * _rng.NextDouble()) * Sr;
					}
					_tooth++;
					_fireAt = _tooth + ToothOffset(_tooth, pr);
				}
				if (_tp > _fireAt + 1.0) { _tooth = (long)Math.Floor(_tp) + 1; _fireAt = _tooth + ToothOffset(_tooth, pr); }
			}
			// the other pawls of a flam: the same click, a fraction of a millisecond later (no retune: one tooth)
			if (_fln > 0 && (_flt -= 1.0) <= 0.0)
			{
				imp = Math.Max(imp, _fla);
				Fire(_fla, 0.0, false);
				_fln--; _fla *= 0.6;
				_flt = FLAM_GAP * (0.4 + 1.2 * _rng.NextDouble()) * Sr;
			}
			// rough ground: now and then the hub rattles by itself between the clicks
			if (_shake > 0.0 && cr > 0.5 && _kn == 0 && _rng.NextDouble() < _shake * SHAKE_RATTLE / Sr)
			{
				_kn = 1; _ka = 0.25 + 0.3 * _shake * _rng.NextDouble(); _kt = 1.0;
			}
			if ((_wobN -= 1.0) <= 0.0) { _wobT = Math.Clamp(Gauss(), -2.0, 2.0); _wobN = Sr / SHAKE_HZ; }
			_wob += (_wobT - _wob) * (SHAKE_HZ * 2.0 / Sr);
			ga *= Math.Max(0.55, 1.0 + _shake * SHAKE_AMP * _wob);
			if (_kn > 0)
			{
				if (cr <= 0.5) _kn = 0;
				else if ((_kt -= 1.0) <= 0.0)
				{
					double a = _ka * (0.55 + 0.45 * _rng.NextDouble());
					imp = Math.Max(imp, a);
					Fire(a, 0.0);
					_kn--; _ka *= 0.72;
					_kt = (0.003 + 0.009 * _rng.NextDouble()) * Sr;
				}
			}
			double s = 0.0;
			for (int k = 0; k < _m; k++)
			{
				double re = _rc[k] * _re[k] - _rs[k] * _im[k] + imp * _g[k] * _ex[k] * EXCITE * _isw[k];
				double im = _rs[k] * _re[k] + _rc[k] * _im[k];
				_re[k] = re; _im[k] = im; s += im;
			}
			if (_burst > 1e-4 || Math.Abs(_lp3) > 1e-6)
			{
				double nz = _rng.NextDouble() * 2.0 - 1.0;
				double d = (nz - _hpz) * _burst;   // differentiated noise: all crack, no thump
				_hpz = nz;
				_lp1 += (d - _lp1) * _lpK;
				_lp2 += (_lp1 - _lp2) * _lpK;
				_lp3 += (_lp2 - _lp3) * _lpK;
				s += _lp3 * CRACK * SNAP_GAIN * _crackK * _crackG;
				_burst *= _crackDecay;
			}
			float v = (float)(s * ga);
			buf[i] = new Vector2(v, v);
		}
		_amp = amp; _rate = clicks;
		return buf;
	}

	// where tooth k's click fires, in teeth from the tooth itself: a fixed part that comes back every turn
	// (machining / wear), a small random part, and the phased pawl sets' odd / even offset
	private double ToothOffset(long k, int pr)
	{
		int i = (int)(((k % pr) + pr) % pr) % TAB;
		double r = _repeat * _tabG[(i * 37 + 11) % TAB] + Math.Sqrt(Math.Max(0.0, 1.0 - _repeat * _repeat)) * Gauss();
		double ab = ((k & 1) == 0 ? -1.0 : 1.0) * PHASE_AB * _uneven;
		return Math.Clamp(0.5 * _jitter * r + ab, -OFF_MAX, OFF_MAX);
	}

	private static double SmoothStep(double a, double b, double x)
	{
		double t = Math.Clamp((x - a) / (b - a), 0.0, 1.0);
		return t * t * (3.0 - 2.0 * t);
	}

	// the model before 2026-11-28 (BMX_OLD_FWSYNTH=1)
	private Vector2[] RenderOld(int n, double clicks, double amp, double fast)
	{
		_fast += (Math.Clamp(fast, 0.0, 1.0) - _fast) * Math.Min(1.0, n / (0.08 * Sr));
		_crackG = 1.0 - 0.6 * _spSoft * _fast;
		_crackK1 = 1.0 - 0.8 * _spSoft * _fast;   // one-pole low-pass on the snap: 1 = none
		var buf = new Vector2[n];
		double a0 = _amp, r0 = _rate;
		for (int i = 0; i < n; i++)
		{
			double t = (i + 1.0) / n;
			double cr = r0 + (clicks - r0) * t;
			double ga = a0 + (amp - a0) * t;
			double imp = 0.0;
			_ph += cr / Sr;
			_rev += cr / (_poe * Sr);
			if (_rev >= 1.0) _rev -= Math.Floor(_rev);
			if (cr > 0.5 && _ph >= _next)
			{
				_ph -= _next;
				_ci = (int)(_rev * _poe) % TAB;
				double jg = _repeat * _tabG[_ci] + Math.Sqrt(1.0 - _repeat * _repeat) * Gauss();
				_next = Math.Max(0.05, (1.0 + (PAWL[_pawl] - 1.0) * _uneven) * (1.0 + jg * _jitter));
				_pawl = (_pawl + 1) % PAWL.Length;
				double a = 1.0 - _vary + _vary * (_repeat * _tabU[_ci] + (1.0 - _repeat) * _rng.NextDouble());
				if (_pawl == 0) a *= 1.15;
				double wv = 0.7 * Math.Sin(2.0 * Math.PI * _rev) + 0.3 * Math.Sin(4.0 * Math.PI * _rev + 1.3);
				a *= Math.Max(0.1, 1.0 + _warble * wv);
				imp = a; _burst = a;
				Fire(a, wv);
			}
			else if (cr <= 0.5)
				_ph = 0.0;
			if (_shake > 0.0 && cr > 0.5 && _kn == 0 && _rng.NextDouble() < _shake * SHAKE_RATTLE / Sr)
			{
				_kn = 1; _ka = 0.25 + 0.3 * _shake * _rng.NextDouble(); _kt = 1.0;
			}
			if ((_wobN -= 1.0) <= 0.0) { _wobT = Math.Clamp(Gauss(), -2.0, 2.0); _wobN = Sr / SHAKE_HZ; }
			_wob += (_wobT - _wob) * (SHAKE_HZ * 2.0 / Sr);
			ga *= Math.Max(0.55, 1.0 + _shake * SHAKE_AMP * _wob);
			if (_kn > 0)
			{
				if (cr <= 0.5) _kn = 0;
				else if ((_kt -= 1.0) <= 0.0)
				{
					double a = _ka * (0.55 + 0.45 * _rng.NextDouble());
					imp = Math.Max(imp, a);
					Fire(a, 0.0);
					_kn--; _ka *= 0.72;
					_kt = (0.003 + 0.009 * _rng.NextDouble()) * Sr;
				}
			}
			double s = 0.0;
			for (int k = 0; k < _m; k++)
			{
				double y = _c1[k] * _y1[k] + _c2[k] * _y2[k] + imp * _g[k] * _ex[k] * EXCITE;
				_y2[k] = _y1[k]; _y1[k] = y; s += y;
			}
			if (_burst > 1e-4)
			{
				double nz = _rng.NextDouble() * 2.0 - 1.0;
				_clp += ((nz - _hpz) - _clp) * _crackK1;
				s += _clp * _burst * CRACK * _crackK * _crackG;
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
