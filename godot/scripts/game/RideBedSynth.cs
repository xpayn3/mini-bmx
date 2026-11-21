using System;
using Godot;

/// The ride's continuous sound bed, moved out of ride_audio.gd's per-sample GDScript loop (same filters, same
/// numbers): wind = two-pole low-passed noise per ear with two slow gust LFOs and a band-passed helmet whistle;
/// splash = high-passed hiss; the old noise rumble / skid hiss only when there is no gravel synth. The gravel
/// buffer (GravelSynth.Render) is mixed in here and the result clamped, so GDScript only adds the rare one-shots.
public partial class RideBedSynth : RefCounted
{
	private const double RATE = 22050.0;
	private readonly Random _rng = new Random(7);
	// gusts: no fixed LFOs (a steady sine read as a "whoosh whoosh" in the pedalling rhythm). Loudness and
	// left / right balance each ease towards a random target that changes after a random 0.7-2.6 s.
	private double _gT = 0.78, _gV = 0.78, _gV2 = 0.78, _gTimer;
	private double _pT, _pV, _pV2, _pTimer;
	private double _lpW, _lpW2, _lpWR, _lpWR2, _bpHi, _bpLo, _lpR, _lpR2, _hpS;

	private double Noise() => _rng.NextDouble() * 2.0 - 1.0;

	/// gravel: GravelSynth's buffer for these n frames, or an empty array (no gravel synth: the old rumble plays)
	public Vector2[] Render(int n, double windTone, double rollTone, double wind, double roll, double skid,
		double water, double whistle, Vector2[] gravel)
	{
		var buf = new Vector2[n];
		bool hasGravel = gravel != null && gravel.Length >= n;
		double aw = windTone, ar = rollTone;
		const double dt = 1.0 / RATE;
		const double gA = 1.0 / (RATE * 0.35);   // two-pole ease, ~0.35 s per pole: soft swells, no corners
		double wamp = wind * 2.6 / Math.Sqrt(Math.Max(aw, 0.02) / 0.03);   // keep loudness even as it brightens
		double splash = (hasGravel ? 0.0 : skid * 0.35) + water * 0.25;
		for (int i = 0; i < n; i++)
		{
			_gTimer -= dt;
			if (_gTimer <= 0.0) { _gT = 0.62 + 0.32 * _rng.NextDouble(); _gTimer = 0.7 + 1.9 * _rng.NextDouble(); }
			_pTimer -= dt;
			if (_pTimer <= 0.0) { _pT = 0.16 * (_rng.NextDouble() * 2.0 - 1.0); _pTimer = 1.2 + 2.4 * _rng.NextDouble(); }
			_gV += (_gT - _gV) * gA; _gV2 += (_gV - _gV2) * gA;
			_pV += (_pT - _pV) * gA; _pV2 += (_pV - _pV2) * gA;
			double gust = _gV2;
			double w = Noise();
			_lpW += (w - _lpW) * aw;
			_lpW2 += (_lpW - _lpW2) * aw;
			double wn = Noise();
			_lpWR += (wn - _lpWR) * aw;
			_lpWR2 += (_lpWR - _lpWR2) * aw;
			_bpHi += (w - _bpHi) * 0.18;
			_bpLo += (_bpHi - _bpLo) * 0.06;
			double wh = (_bpHi - _bpLo) * whistle * (0.45 + 0.6 * (gust - 0.62) / 0.32);
			double wl = _lpW2 * wamp * gust * (1.0 + _pV2) + wh;
			double wr = _lpWR2 * wamp * gust * (1.0 - _pV2) + wh;
			double s = 0.0;
			double w2 = Noise();
			if (!hasGravel)
			{
				_lpR += (w2 - _lpR) * ar;
				_lpR2 += (_lpR - _lpR2) * ar;
				s += _lpR2 * roll * 2.2;
			}
			_hpS += (w2 - _hpS) * 0.25;
			s += (w2 - _hpS) * splash;
			double l = s + wl, r = s + wr;
			if (hasGravel) { l += gravel[i].X; r += gravel[i].Y; }
			buf[i] = new Vector2((float)Math.Clamp(l, -1.0, 1.0), (float)Math.Clamp(r, -1.0, 1.0));
		}
		return buf;
	}
}
