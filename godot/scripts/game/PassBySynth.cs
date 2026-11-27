using System;
using Godot;
using static AirDsp;

/// Procedural pass-by "whoosh" for riding under a gate (the trail's sponsor gantries, a level's race gates).
/// Built the way racing games build trackside pass-bys: no recording, the sound is worked out from the
/// geometry of the pass at the speed it happens, then made to sound like air and a microphone, not a synth:
///  * Air past each post: pink noise with turbulence (slow random gusts in loudness and colour, like real
///    wind never holds still) through a band-pass that follows the Doppler shift (f0 x c / (c + v_radial)),
///    loudness (r0 / r)^2 from the distance to the post, high end lost with distance (air absorption: the
///    post is brightest right beside you). Left post left, right post right, the far ear a little later
///    (interaural delay, ~0.4 ms) and duller (head shadow).
///  * Overhead: the rider's own wind reflected off the banner, the lower and upper truss chords. Each
///    reflection's delay is its round trip (2 r / c) with a little wobble, so instead of one clean (metallic)
///    comb they smear into the soft "fffwOOM" of passing under a bridge. Plus a low pressure swell.
///  * Flap: the banner flutters irregularly (two drifting rates), louder after the bike passes (its wake).
///  * The "analog" chain: DC block, a tape-like soft saturation, a gentle top roll-off, a touch of wow
///    (slow pitch drift) on the whole thing.
/// Render() returns 16-bit 48 kHz stereo PCM, the pass (closest point) at PEAK seconds in.
public partial class PassBySynth : RefCounted
{
	public const int RATE = 48000;
	public const float PEAK = 0.6f;   // s from the start of the clip to the moment under the gate
	private const float LEN = 1.7f;
	private const float C = 343f;

	// a mono buffer read back with a fractional delay
	private static double Tap(float[] b, double at)
	{
		if (at < 0) return 0;
		int i = (int)at; double fr = at - i;
		if (i + 1 >= b.Length) return 0;
		return b[i] + (b[i + 1] - b[i]) * fr;
	}

	/// speed m/s; half = half the gap between the posts; clear = banner bottom over the bike (m);
	/// (clear <= 0: nothing overhead); lat = the bike's sideways offset from the gate's middle (+ = right); depth = how deep the overhead
	/// part is along the trail (m); flap 0..1 (cloth banner); peak = loudest sample (0..1)
	public byte[] Render(int seed, float speed, float half, float clear, float lat, float depth, float flap, float peak)
	{
		var rng = new Random(seed);
		int n = (int)(LEN * RATE);
		var L = new float[n];
		var R = new float[n];
		double v = Math.Max(2.0, speed);
		int p0 = (int)(PEAK * RATE);
		double fast = Math.Clamp((v - 4.0) / 18.0, 0.0, 1.0);

		// --- the rider's wind: one turbulent source shared by the reflections (they echo the same air)
		var wind = new float[n];
		{
			var pk = new Pink(); var gust = new Drift(); var col = new Drift(); var lp = new Lp(); var hp = new Lp();
			for (int i = 0; i < n; i++)
			{
				double g = 1.0 + 0.35 * gust.Next(rng, 3.0);
				double x = pk.Next(rng) * g;
				double fc = (2500.0 + 5000.0 * fast) * (1.0 + 0.25 * col.Next(rng, 1.5));
				x = lp.Run(x, fc);
				x -= hp.Run(x, 90.0);   // nothing under ~90 Hz in the wind itself (the swell adds that)
				wind[i] = (float)x;
			}
		}

		// --- posts: one each side, at lateral distance half +- lat (the bike's offset)
		double[] side = { Math.Max(0.4, half + lat), Math.Max(0.4, half - lat) };   // left, right
		double f0 = 420.0 + 28.0 * v;
		for (int s = 0; s < 2; s++)
		{
			var pk = new Pink(); var sv = new Svf(); var sv2 = new Svf(); var gust = new Drift(); var air = new Lp();
			var farLp = new Lp();
			double r0 = side[s];
			double gain = 1.8 * Math.Pow(1.6 / (r0 + 0.6), 1.3) * (0.55 + 0.45 * fast);   // (x1.8: the posts give the left / right)
			float[] own = s == 0 ? L : R, other = s == 0 ? R : L;
			int itd = (int)(0.00042 * RATE);   // the far ear hears it ~0.4 ms later
			var lag = new float[itd + 1]; int li = 0;
			for (int i = 0; i < n; i++)
			{
				double t = (i - p0) / (double)RATE;
				double x = v * t;   // along the trail past the post (- = before)
				double r = Math.Sqrt(r0 * r0 + x * x);
				double vr = v * x / r;   // radial speed, + = going away
				double dop = C / (C + vr);
				double amp = gain * (r0 * r0) / (r * r) * (1.0 + 0.3 * gust.Next(rng, 5.0));
				double src = pk.Next(rng);
				double y = sv.Band(src, f0 * dop, 1.1) * 1.1 + sv2.Band(src, f0 * dop * 2.7, 0.8) * 0.55;
				// air absorption: the further the duller (and the wind noise of a near post is broadband)
				y = air.Run(y, 2500.0 + 14000.0 / (1.0 + r * 0.6));
				y *= amp;
				own[i] += (float)(y * 0.9);
				// far ear: later and head-shadowed
				double late = lag[li]; lag[li] = (float)y; li = (li + 1) % lag.Length;
				other[i] += (float)(farLp.Run(late, 1800.0) * 0.35);
			}
		}

		// --- overhead reflections: banner bottom, lower chord, top chord (each its own delay sweep + wobble);
		// clear <= 0: nothing over the trail (checkpoint feather flags)
		if (clear > 0f)
		{
			double h = Math.Max(1.5, clear);
			double[] hs = { h, h + 0.35, h + 2.9 };
			double[] gs = { 0.75, 0.35, 0.25 };
			double reach = depth * 0.5 + h * 0.75;
			double g0 = 1.1 * Math.Pow(4.0 / (h + 1.0), 0.8) * (0.5 + 0.5 * fast);
			var wob = new Drift[3]; var lpL = new Lp(); var lpR = new Lp();
			for (int i = 0; i < n; i++)
			{
				double t = (i - p0) / (double)RATE;
				double x = v * t;
				double env = Math.Exp(-(x / reach) * (x / reach));
				if (env < 1e-4) continue;
				double dir = wind[i] * 0.35;   // the direct wind: carrier the echoes beat against
				double e = 0.0, eR = 0.0;
				for (int k = 0; k < 3; k++)
				{
					double r = Math.Sqrt(hs[k] * hs[k] + x * x);
					double dl = 2.0 * r / C * RATE * (1.0 + 0.004 * wob[k].Next(rng, 0.7 + k * 0.6));
					double a = Tap(wind, i - dl) * gs[k];
					e += a;
					eR += Tap(wind, i - dl - 9 - 5 * k) * gs[k];   // the right ear a few samples off: wide, not mono
				}
				double yl = (dir + e) * env * g0, yr = (dir + eR) * env * g0;
				// the reflected part loses some top (fabric / steel aren't mirrors)
				yl = lpL.Run(yl, 5200.0 + 3000.0 * fast); yr = lpR.Run(yr, 5200.0 + 3000.0 * fast);
				L[i] += (float)yl; R[i] += (float)yr;
			}
			// the pressure swell: a low band, narrower in time, a soft "whomp"
			var pk = new Pink(); var sw = new Svf(); var sw2 = new Svf();
			double reach2 = reach * 0.55;
			for (int i = 0; i < n; i++)
			{
				double t = (i - p0) / (double)RATE;
				double x = v * t;
				double env2 = Math.Exp(-(x / reach2) * (x / reach2));
				double src = pk.Next(rng);
				double y = sw.Band(src, 95.0 + 2.5 * v, 1.4) * 1.6 + sw2.Band(src, 210.0 + 4.0 * v, 1.0) * 0.6;
				y *= env2 * g0 * 1.7;
				L[i] += (float)y; R[i] += (float)y;
			}
		}

		// --- flap: cloth flutters LOW and soft (a "whup-whup" of air pushed by the fabric, ~100-600 Hz) at a few Hz,
		// smoothly (no on / off), now and then a soft snap as the cloth pulls tight; louder after the bike (its wake)
		if (flap > 0.01f)
		{
			var pk = new Pink(); var lo = new Lp(); var lo2 = new Lp(); var sm = new Lp(); var body = new Svf();
			var d1 = new Drift(); var d2 = new Drift();
			double r1 = 4.0 + 0.12 * v + rng.NextDouble(), r2 = r1 * (1.6 + rng.NextDouble() * 0.3);
			double ph1 = rng.NextDouble() * 6.28, ph2 = rng.NextDouble() * 6.28;
			double reach = 5.0 + 0.3 * v;
			double pan = Math.Tanh(lat * 0.5) * 0.3;
			double snapE = 0.0; var snapLp = new Lp();
			for (int i = 0; i < n; i++)
			{
				double t = (i - p0) / (double)RATE;
				double x = v * t;
				ph1 += 2.0 * Math.PI * r1 * (1.0 + 0.3 * d1.Next(rng, 0.8)) / RATE;
				ph2 += 2.0 * Math.PI * r2 * (1.0 + 0.3 * d2.Next(rng, 1.1)) / RATE;
				double am = 0.55 + 0.3 * Math.Sin(ph1) + 0.15 * Math.Sin(ph2);   // always > 0: no gating clicks
				am = sm.Run(am, 30.0);
				// a soft snap: the cloth pulling tight at the top of a big flutter
				if (ph1 % 6.2832 < 0.0005 * r1 * 6.2832 && rng.NextDouble() < 0.35) snapE = 1.0;
				snapE *= 0.9992;
				double env = Math.Exp(-(x / reach) * (x / reach)) * (x > 0 ? 1.0 : 0.55);
				double src = pk.Next(rng);
				double y = lo2.Run(lo.Run(src, 650.0), 650.0) * 2.2 + body.Band(src, 180.0 + 40.0 * am, 0.8) * 0.9;
				y = y * am + snapLp.Run(src, 1100.0) * snapE * 0.5;
				y *= env * flap * 0.7;
				L[i] += (float)(y * (1.0 - pan)); R[i] += (float)(y * (1.0 + pan));
			}
		}

		// --- the analog chain: wow, DC block, tape saturation, top roll-off, fades
		{
			var wow = new Drift();
			var cl = (float[])L.Clone(); var cr = (float[])R.Clone();
			double dcl = 0, dcr = 0, ol = 0, or_ = 0;
			var tl = new Lp(); var tr = new Lp();
			double mx = 1e-6;
			for (int i = 0; i < n; i++) mx = Math.Max(mx, Math.Max(Math.Abs(cl[i]), Math.Abs(cr[i])));
			double drive = 0.55 / mx;   // only a touch into the saturation (warmth, no crackle); output normalised after
			int fade = RATE / 40;
			double peakOut = 1e-6;
			for (int i = 0; i < n; i++)
			{
				double w = 18.0 + 10.0 * wow.Next(rng, 0.6);   // samples of delay, drifting: slow pitch wow
				double a = Tap(cl, i - w), b = Tap(cr, i - w);
				// DC block
				ol = a - dcl + 0.995 * ol; dcl = a;
				or_ = b - dcr + 0.995 * or_; dcr = b;
				// tape-ish: soft asymmetric saturation (a little even harmonic warmth)
				double sa = Math.Tanh(ol * drive + 0.06) - Math.Tanh(0.06);
				double sb = Math.Tanh(or_ * drive + 0.06) - Math.Tanh(0.06);
				sa = tl.Run(sa, 12500.0); sb = tr.Run(sb, 12500.0);
				double k = Math.Min(1.0, Math.Min(i, n - 1 - i) / (double)fade);
				k = k * k * (3 - 2 * k);
				L[i] = (float)(sa * k); R[i] = (float)(sb * k);
				peakOut = Math.Max(peakOut, Math.Max(Math.Abs(L[i]), Math.Abs(R[i])));
			}
			double sc = Math.Clamp(peak, 0f, 1f) / peakOut;
			for (int i = 0; i < n; i++) { L[i] = (float)(L[i] * sc); R[i] = (float)(R[i] * sc); }
		}

		var b8 = new byte[n * 4];
		for (int i = 0; i < n; i++)
		{
			// a little TPDF dither (it's going to 16 bit anyway)
			double d = (rng.NextDouble() - rng.NextDouble()) / 32767.0;
			int ql = (int)Math.Round(Math.Clamp(L[i] + d, -1.0, 1.0) * 32767.0);
			int qr = (int)Math.Round(Math.Clamp(R[i] + d, -1.0, 1.0) * 32767.0);
			b8[4 * i] = (byte)(ql & 0xff); b8[4 * i + 1] = (byte)((ql >> 8) & 0xff);
			b8[4 * i + 2] = (byte)(qr & 0xff); b8[4 * i + 3] = (byte)((qr >> 8) & 0xff);
		}
		return b8;
	}

	// ---- background rendering: Queue() a gate's pass a second or two ahead, Take() it when it is time to play
	private readonly System.Collections.Generic.Dictionary<long, byte[]> _ready = new();
	private readonly object _lock = new();

	public void Queue(long id, int seed, float speed, float half, float clear, float lat, float depth, float flap, float peak)
	{
		System.Threading.Tasks.Task.Run(() =>
		{
			var b = Render(seed, speed, half, clear, lat, depth, flap, peak);
			lock (_lock) _ready[id] = b;
		});
	}

	/// the queued clip for id (and forgets it); empty if it isn't done yet
	public byte[] Take(long id)
	{
		lock (_lock)
		{
			if (!_ready.TryGetValue(id, out var b)) return Array.Empty<byte>();
			_ready.Remove(id);
			return b;
		}
	}

	public void Forget(long id) { lock (_lock) _ready.Remove(id); }

	// ---- close pass-bys: a rock, a trunk, a bush going past the rider's head (one side, often inches away)
	public const float NEAR_PEAK = 0.35f;   // s into the clip: the closest moment
	private const float NEAR_LEN = 1.05f;
	private const double HEAD_R = 0.0875;   // m: half the ear-to-ear distance (Woodworth's head model)

	/// a close pass: speed m/s; r0 = closest distance from the head to the object's surface (m); side -1 left / +1 right;
	/// up = how far the closest point is above (+) / below (-) the ears (m); kind 0 rock, 1 bush, 2 trunk / post;
	/// size = the object's height (m); peak = loudest sample (0..1). Stereo with real head cues: the far ear later
	/// (ITD, up to ~0.65 ms), quieter and duller (head shadow, stronger for highs), a touch duller behind (the pinna).
	/// Hard things (rock, trunk): the rider's own wind reflected off the face, the echo's delay 2 r / c sweeping
	/// down to under a millisecond and back (the "phasing" swish of passing a wall) + the air pinched in the gap.
	/// A bush: many small reflections (leaves), no clean comb, a leafy hiss, and if it is within reach of the
	/// body (r0 under ~0.3 m) the leaves brush the helmet / shoulder: a crackle of twigs.
	public byte[] RenderNear(int seed, float speed, float r0, float side, float up, int kind, float size, float peak)
	{
		var rng = new Random(seed);
		int n = (int)(NEAR_LEN * RATE);
		var L = new float[n]; var R = new float[n];
		double v = Math.Max(2.0, speed);
		int p0 = (int)(NEAR_PEAK * RATE);
		double fast = Math.Clamp((v - 4.0) / 18.0, 0.0, 1.0);
		double d0 = Math.Max(0.05, r0);
		bool leafy = kind == 1;
		double sgn = side < 0 ? -1.0 : 1.0;
		double sz = Math.Clamp(size, 0.2, 6.0);
		// how long it is "beside" you: the object's own width along the path + the distance
		double reach = Math.Max(0.6, 0.8 * d0 + (kind == 2 ? 0.35 : 0.5 * Math.Min(sz, kind == 0 ? 3.5 : 1.5)));
		double big = kind == 0 ? Math.Clamp((sz - 0.7) / 1.8, 0.0, 1.0) : 0.0;   // a boulder: a big face   // (a little longer than the bare geometry: a 20 cm trunk at 50 km/h is ~30 ms)
		double lat2 = Math.Max(0.0, d0 * d0 - up * up);

		// the rider's wind at the head: turbulent pink noise, brighter with speed
		var wind = new float[n];
		{
			var pk = new Pink(); var gust = new Drift(); var col = new Drift(); var lp = new Lp(); var hp = new Lp();
			for (int i = 0; i < n; i++)
			{
				double x = pk.Next(rng) * (1.0 + 0.4 * gust.Next(rng, 6.0));
				x = lp.Run(x, (3000.0 + 7000.0 * fast) * (1.0 + 0.25 * col.Next(rng, 2.0)));
				x -= hp.Run(x, 120.0);
				wind[i] = (float)x;
			}
		}
		// the object's sound at its own position (mono), then put round the head
		var src = new float[n];
		var az = new double[n];   // azimuth: 0 ahead, +-pi/2 beside, +-pi behind (sign = side)
		{
			var air = new Lp(); var pk = new Pink(); var sv = new Svf(); var sv2 = new Svf(); var gust = new Drift();
			var svLo = new Svf(); var svLo2 = new Svf();
			var leaf = new Pink(); var leafHp = new Lp(); var leafAm = new Drift();
			double crack = leafy && d0 < 0.3 ? Math.Clamp((0.3 - d0) / 0.25, 0.0, 1.0) : 0.0;
			double f0 = 380.0 + 26.0 * v;
			for (int i = 0; i < n; i++)
			{
				double t = (i - p0) / (double)RATE;
				double x = v * t;                                   // along the path past it (- = still ahead)
				double r = Math.Sqrt(d0 * d0 + x * x);
				az[i] = sgn * Math.Atan2(Math.Sqrt(lat2) + 1e-3, -x);
				double near = (d0 * d0) / (r * r);                  // closest = 1
				double env = Math.Exp(-(x / reach) * (x / reach));
				double y = 0.0;
				if (!leafy)
				{
					// 1) the wind's echo off the face: delay 2 r / c (a 1.5 ms comb at 25 cm, sweeping)
					double dl = 2.0 * r / C * RATE;
					double echo = Tap(wind, i - dl) * (kind == 2 ? 0.95 : 0.85 + 0.35 * big);
					y += (wind[i] * 0.55 + echo) * env * (1.2 / (0.35 + d0));
					// 2) the air pinched in the gap: a band that rises the narrower the gap, Doppler-shifted
					double vr = v * x / r, dop = C / (C + vr);
					double fg = f0 * dop * (1.0 + 0.6 / (0.25 + d0));
					double ps = pk.Next(rng);
					y += (sv.Band(ps, fg, 1.0) + 0.5 * sv2.Band(ps, fg * 2.4, 0.7)) * near * (1.0 + 0.3 * gust.Next(rng, 7.0)) * 1.4;
					// a big face also pushes the air back as a low "whoomf" (like riding under a gate)
					if (big > 0.0)
					{
						double lw = pk.Next(rng);
						y += (svLo.Band(lw, 85.0 + 2.0 * v, 1.3) * 1.8 + svLo2.Band(lw, 190.0 + 3.5 * v, 1.0) * 0.7)
							* Math.Exp(-(x / (reach * 0.7)) * (x / (reach * 0.7))) * big * 2.2 / (0.5 + d0);
					}
				}
				else
				{
					// a bush: leaves scatter the wind (many short taps, no single comb) + a soft leafy hiss
					double e = 0.0;
					for (int k = 0; k < 6; k++)
					{
						double rk = r + 0.07 * k + 0.05 * Math.Sin(i * 0.0007 * (k + 1));
						e += Tap(wind, i - 2.0 * rk / C * RATE) * (0.32 - 0.04 * k);
					}
					double lh = leaf.Next(rng); lh -= leafHp.Run(lh, 2200.0);
					double flutter = 0.55 + 0.45 * Math.Abs(leafAm.Next(rng, 18.0));
					y += (e + lh * 0.6 * flutter) * env * (1.0 / (0.3 + d0));
					// twigs and leaves brushing the helmet / shoulder: short crackles while right beside
					if (crack > 0.0 && Math.Abs(x) < 0.35 + 0.3 * sz && rng.NextDouble() < crack * 900.0 / RATE)
					{
						double a = (0.4 + 0.6 * rng.NextDouble()) * crack;
						int len = 40 + rng.Next(160);
						for (int j = 0; j < len && i + j < n; j++)
							src[i + j] += (float)((rng.NextDouble() * 2 - 1) * a * Math.Exp(-j / (len * 0.3)) * 0.9);
					}
				}
				// air absorption: the further, the duller
				y = air.Run(y, 3000.0 + 15000.0 / (1.0 + r * 0.8));
				src[i] += (float)y;
			}
		}
		// round the head: ITD (Woodworth: a / c (sin + theta)), ILD + head shadow on the far ear, pinna behind
		{
			var nearLp = new Lp(); var farLp = new Lp(); var backLp = new Lp();
			for (int i = 0; i < n; i++)
			{
				double a = az[i];                                   // + right
				double th = Math.Abs(a) > Math.PI / 2 ? Math.PI - Math.Abs(a) : Math.Abs(a);   // lateral angle 0..pi/2
				double itd = HEAD_R / C * (Math.Sin(th) + th) * RATE;   // samples (~31 at 90 deg)
				double behind = Math.Clamp(-Math.Cos(a), 0.0, 1.0);
				double sb = backLp.Run(src[i], 16000.0 - 9000.0 * behind);
				double nearEar = nearLp.Run(sb, 18000.0) * (1.0 + 0.25 * Math.Sin(th));
				double far = farLp.Run(Tap(src, i - itd), 9000.0 - 7200.0 * Math.Sin(th)) * (1.0 - 0.55 * Math.Sin(th));
				if (a >= 0) { R[i] += (float)nearEar; L[i] += (float)far; }
				else { L[i] += (float)nearEar; R[i] += (float)far; }
			}
		}
		// the same analog finish as the gates: DC block, soft tape saturation, top roll-off, fades, normalised
		{
			double dcl = 0, dcr = 0, ol = 0, or_ = 0; var tl = new Lp(); var tr = new Lp();
			double mx = 1e-6;
			for (int i = 0; i < n; i++) mx = Math.Max(mx, Math.Max(Math.Abs(L[i]), Math.Abs(R[i])));
			double drive = 0.6 / mx, pkOut = 1e-6;
			int fade = RATE / 50;
			for (int i = 0; i < n; i++)
			{
				double a = L[i], b = R[i];
				ol = a - dcl + 0.995 * ol; dcl = a; or_ = b - dcr + 0.995 * or_; dcr = b;
				double sa = Math.Tanh(ol * drive + 0.05) - Math.Tanh(0.05), sb = Math.Tanh(or_ * drive + 0.05) - Math.Tanh(0.05);
				sa = tl.Run(sa, 14000.0); sb = tr.Run(sb, 14000.0);
				double k = Math.Min(1.0, Math.Min(i, n - 1 - i) / (double)fade); k = k * k * (3 - 2 * k);
				L[i] = (float)(sa * k); R[i] = (float)(sb * k);
				pkOut = Math.Max(pkOut, Math.Max(Math.Abs(L[i]), Math.Abs(R[i])));
			}
			double sc = Math.Clamp(peak, 0f, 1f) / pkOut;
			for (int i = 0; i < n; i++) { L[i] = (float)(L[i] * sc); R[i] = (float)(R[i] * sc); }
		}
		return Pcm(L, R, rng);
	}

	public void QueueNear(long id, int seed, float speed, float r0, float side, float up, int kind, float size, float peak)
	{
		System.Threading.Tasks.Task.Run(() =>
		{
			var b = RenderNear(seed, speed, r0, side, up, kind, size, peak);
			lock (_lock) _ready[id] = b;
		});
	}

	private static byte[] Pcm(float[] L, float[] R, Random rng)
	{
		int n = L.Length;
		var b8 = new byte[n * 4];
		for (int i = 0; i < n; i++)
		{
			double d = (rng.NextDouble() - rng.NextDouble()) / 32767.0;
			int ql = (int)Math.Round(Math.Clamp(L[i] + d, -1.0, 1.0) * 32767.0);
			int qr = (int)Math.Round(Math.Clamp(R[i] + d, -1.0, 1.0) * 32767.0);
			b8[4 * i] = (byte)(ql & 0xff); b8[4 * i + 1] = (byte)((ql >> 8) & 0xff);
			b8[4 * i + 2] = (byte)(qr & 0xff); b8[4 * i + 3] = (byte)((qr >> 8) & 0xff);
		}
		return b8;
	}
}
