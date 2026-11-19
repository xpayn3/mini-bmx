using System;
using Godot;

/// Procedural tyre-on-gravel roll, fitted to a real recording (freesound_community "tires on gravel
/// road 2"): the crunch is thousands of tiny pebble knocks per second, each a short damped ring
/// (log-normal pitch around ~700 Hz, 2-6 ms decay) with a bright sub-ms crack on top, a few bigger
/// stones, a low casing rumble (90-220 Hz) and a fast 3-30 Hz loudness flutter. Tuned so the band
/// spectrum, transient rate and envelope spread match the recording within ~2-3 dB.
/// Speed sets how many knocks per second (they are laid per metre), so slow rolling is a sparse
/// crackle and speed fills it into a hiss; the tone shifts only a little. One Render() per frame.
public partial class GravelSynth : RefCounted
{
	private const int VOICES = 96;
	private const double PER_M = 500.0;   // pebble knocks per metre rolled (4000/s at 8 m/s, the recording)
	private const double NORM = 0.05;     // amp 1 at 8 m/s ~ the recording's level (rms ~0.12)
	private const double RUMBLE_K = 10.0; // rumble scale (calibrated with tools/gravel_render.gd)

	private readonly double[] _c1 = new double[VOICES], _c2 = new double[VOICES];
	private readonly double[] _y1 = new double[VOICES], _y2 = new double[VOICES];
	private readonly double[] _pl = new double[VOICES], _pr = new double[VOICES];
	private int _voice;
	private readonly Random _rng = new Random(4242);
	private double _next, _amp, _speed;
	private double _crack, _hp;
	private double _r1, _r2, _r3;
	// loudness flutter: (rate Hz, depth, phase, from, to)
	private static readonly double[,] MOD = { { 3.0, 0.1, 0, 0, 0 }, { 8.0, 0.5, 0, 0, 0 }, { 16.0, 0.8, 0, 0, 0 }, { 30.0, 0.9, 0, 0, 0 } };
	private readonly double[] _mph = new double[4], _ma = new double[4], _mb = new double[4];

	public GravelSynth() : this(22050.0) { }

	public GravelSynth(double sr)
	{
		Sr = sr;
		for (int k = 0; k < 4; k++) { _ma[k] = Gauss(); _mb[k] = Gauss(); _mph[k] = _rng.NextDouble(); }
		_next = Exp() / 1000.0;
	}

	public double Sr { get; private set; }

	private double Gauss()
	{
		double u = 1.0 - _rng.NextDouble(), v = _rng.NextDouble();
		return Math.Sqrt(-2.0 * Math.Log(u)) * Math.Cos(2.0 * Math.PI * v);
	}
	private double Exp() => -Math.Log(1.0 - _rng.NextDouble());
	private double Noise() => _rng.NextDouble() * 2.0 - 1.0;

	/// n stereo frames. speed: rolling speed m/s (0 = silent, the last knocks ring out);
	/// amp: output gain; tone: pitch centre Hz (~700 gravel, lower = softer ground);
	/// crack: bright click amount (gravel ~0.3, grass/sand less); rumble: casing rumble amount.
	/// speed and amp glide over the block so nothing zips.
	public Vector2[] Render(int n, double speed, double amp, double tone, double crack, double rumble)
	{
		var buf = new Vector2[n];
		double s0 = _speed, a0 = _amp;
		double dt = 1.0 / Sr;
		double rl = 1.0 - Math.Exp(-2.0 * Math.PI * 220.0 / Sr), rh = 1.0 - Math.Exp(-2.0 * Math.PI * 90.0 / Sr);
		for (int i = 0; i < n; i++)
		{
			double t = (i + 1.0) / n;
			double sp = s0 + (speed - s0) * t;
			double ga = a0 + (amp - a0) * t;
			// flutter: smooth random values per rate, cosine-interpolated
			double m = 0.0;
			for (int k = 0; k < 4; k++)
			{
				_mph[k] += MOD[k, 0] * dt;
				if (_mph[k] >= 1.0) { _mph[k] -= 1.0; _ma[k] = _mb[k]; _mb[k] = Gauss(); }
				double w = 0.5 - 0.5 * Math.Cos(Math.PI * _mph[k]);
				m += MOD[k, 1] * (_ma[k] + (_mb[k] - _ma[k]) * w);
			}
			m = Math.Max(0.3, 1.0 + 0.25 * m / 1.4);
			// pebble knocks: Poisson in distance rolled
			double rate = sp * PER_M;
			double xin = 0.0;
			if (rate > 1.0)
			{
				_next -= dt;
				while (_next <= 0.0)
				{
					_next += Exp() / rate;
					double a = 0.5 + _rng.NextDouble();
					if (_rng.NextDouble() < 0.02) a *= 1.6;   // a slightly bigger stone (3.5x made isolated clicks)
					a *= m;
					int v = _voice; _voice = (_voice + 1) % VOICES;
					double f = Math.Min(5000.0, tone * (0.9 + 0.2 * Math.Min(1.0, sp / 10.0)) * Math.Exp(Gauss() * 0.45));
					double tau = 0.003 + 0.005 * _rng.NextDouble();   // softer, longer rings: less tick
					double r = Math.Exp(-1.0 / (tau * Sr)), wv = 2.0 * Math.PI * f / Sr;
					_c1[v] = 2.0 * r * Math.Cos(wv); _c2[v] = -r * r;
					// excite with a quarter-period offset so each knock starts with a random phase
					double ph = _rng.NextDouble() * 2.0 * Math.PI;
					_y1[v] = a * Math.Sin(ph); _y2[v] = a * Math.Sin(ph - wv) / r;
					double p = (_rng.NextDouble() * 2.0 - 1.0) * 0.35;
					_pl[v] = 1.0 - p; _pr[v] = 1.0 + p;
					_crack += a * crack * 0.3;   // the bright sub-ms crack was the clicking
				}
			}
			double l = 0.0, rr = 0.0;
			for (int k = 0; k < VOICES; k++)
			{
				double y = _c1[k] * _y1[k] + _c2[k] * _y2[k];
				_y2[k] = _y1[k]; _y1[k] = y;
				l += y * _pl[k]; rr += y * _pr[k];
			}
			// crack: sub-ms bright noise burst
			double cn = Noise() * _crack;
			_crack *= 0.86;
			xin += cn;
			// casing rumble: band-passed noise, follows the knock density
			double wn = Noise();
			_r1 += (wn - _r1) * rl; _r2 += (_r1 - _r2) * rl; _r3 += (_r2 - _r3) * rh;
			double dens = Math.Min(1.0, rate / 4000.0);
			xin += (_r2 - _r3) * rumble * RUMBLE_K * Math.Sqrt(dens) * m;
			// slow rolling = a few lone knocks per second = ticking: fade the whole thing in over 0..2 m/s
			double sparse = Math.Min(1.0, rate / 1000.0); sparse *= sparse;
			double g = NORM * ga * sparse;
			buf[i] = new Vector2((float)((l + xin) * g), (float)((rr + xin) * g));
		}
		_speed = speed; _amp = amp;
		return buf;
	}
}
