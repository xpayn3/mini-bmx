using System;
using Godot;
using static AirDsp;

/// Procedural ambience of a big open landscape: the air over a wide valley / ridge top, the way a field recording
/// of open country sounds (no wind ON the microphone, the wind out THERE over the land):
///  * a deep bed (pink noise under ~250 Hz) that swells and sinks over tens of seconds: distant air moving
///    over the hills;
///  * the "air" band (~300-1500 Hz) in slow gusts, each ear its own mix (the sound comes from everywhere);
///  * far gust fronts every few seconds: a swell of 2-5 s that brightens as it comes, from one side, and
///    rolls across the stereo field as it passes;
///  * a faint high hiss on the gusts (grass / scrub moving far off), heavily rolled off (distance);
///  * the analog chain from PassBySynth (DC block, a touch of saturation, top roll-off).
/// RenderLoop() makes a seamless stereo loop (its end crossfaded into its start), 16-bit 48 kHz.
/// Two loops of different lengths played together never line up the same way twice.
public partial class VastAirSynth : RefCounted
{
	private readonly object _lock = new();

	public byte[] RenderLoop(int seed, float secs)
	{
		var rng = new Random(seed);
		int xf = RATE * 3;                   // 3 s crossfade end -> start
		int n = (int)(secs * RATE);
		int m = n + xf;
		var L = new float[m]; var R = new float[m];

		// deep bed, shared with a little difference per ear
		{
			Pink pa = new(), pb = new(); Lp la = new(), lb = new(), la2 = new(), lb2 = new();
			Drift sw = new(), cl = new();
			for (int i = 0; i < m; i++)
			{
				double g = 0.65 + 0.35 * sw.Next(rng, 0.05);
				double fc = 180.0 + 70.0 * cl.Next(rng, 0.08);
				double c = pa.Next(rng), d = pb.Next(rng);
				double l = la2.Run(la.Run(c * 0.8 + d * 0.2, fc), fc);
				double r = lb2.Run(lb.Run(c * 0.2 + d * 0.8, fc), fc);
				L[i] += (float)(l * g * 1.6); R[i] += (float)(r * g * 1.6);
			}
		}
		// the air band, its own slow gusts per ear
		for (int ch = 0; ch < 2; ch++)
		{
			Pink p = new(); Svf a = new(), b = new(); Drift gu = new(), co = new();
			float[] o = ch == 0 ? L : R;
			for (int i = 0; i < m; i++)
			{
				double g = Math.Max(0.0, 0.5 + 0.35 * gu.Next(rng, 0.18));
				double fc = 650.0 * (1.0 + 0.3 * co.Next(rng, 0.12));
				double x = p.Next(rng);
				double y = a.Band(x, fc, 0.7) + b.Band(x, fc * 0.45, 0.9) * 0.6;
				o[i] += (float)(y * g * g * 3.2);
			}
		}
		// far gust fronts rolling across
		{
			Pink p = new(); Svf bp = new(); Lp hs = new(); Lp hs2 = new();
			double tNext = 1.0 + rng.NextDouble() * 4.0;
			double t0 = -100, dur = 3, from = 0, gain = 0;
			for (int i = 0; i < m; i++)
			{
				double t = i / (double)RATE;
				if (t >= tNext)
				{
					t0 = t; dur = 2.0 + rng.NextDouble() * 3.0; from = rng.NextDouble() < 0.5 ? -1 : 1;
					gain = 0.5 + rng.NextDouble() * 0.6;
					tNext = t + dur * 0.7 + 2.0 + rng.NextDouble() * 6.0;
				}
				double u = (t - t0) / dur;
				double x = p.Next(rng);
				if (u < 0 || u > 1) { bp.Band(x, 500, 0.8); hs.Run(x, 3000); continue; }
				double env = Math.Sin(Math.PI * u); env = env * env * (u < 0.6 ? 1.0 : 1.0);
				double bright = 380.0 + 700.0 * env;
				double y = bp.Band(x, bright, 0.6) * 1.2 + hs2.Run(hs.Run(x, 3500.0), 3500.0) * 0.5 * env;
				y *= env * gain;
				double pan = from * (1.0 - 2.0 * u) * 0.7;   // comes in on one side, rolls over to the other
				L[i] += (float)(y * (1.0 - pan) * 2.4); R[i] += (float)(y * (1.0 + pan) * 2.4);
			}
		}

		// analog chain
		double mx = 1e-6;
		for (int i = 0; i < m; i++) mx = Math.Max(mx, Math.Max(Math.Abs(L[i]), Math.Abs(R[i])));
		double drive = 0.5 / mx;
		{
			double dl = 0, dr = 0, ol = 0, or_ = 0; Lp tl = new(), tr = new();
			for (int i = 0; i < m; i++)
			{
				ol = L[i] - dl + 0.996 * ol; dl = L[i];
				or_ = R[i] - dr + 0.996 * or_; dr = R[i];
				double a = Math.Tanh(ol * drive + 0.05) - Math.Tanh(0.05);
				double b = Math.Tanh(or_ * drive + 0.05) - Math.Tanh(0.05);
				L[i] = (float)tl.Run(a, 9000.0); R[i] = (float)tr.Run(b, 9000.0);
			}
		}
		// seamless loop: the last xf samples fade into the first xf (equal power)
		var oL = new float[n]; var oR = new float[n];
		Array.Copy(L, xf, oL, 0, n); Array.Copy(R, xf, oR, 0, n);
		for (int i = 0; i < xf; i++)
		{
			double k = i / (double)xf;
			double gi = Math.Sin(k * Math.PI * 0.5), go = Math.Cos(k * Math.PI * 0.5);
			// oL[n - xf + i] runs into oL[0] next: blend the head (pre-roll) under the tail
			oL[n - xf + i] = (float)(oL[n - xf + i] * go + L[i] * gi);
			oR[n - xf + i] = (float)(oR[n - xf + i] * go + R[i] * gi);
		}
		double pk = 1e-6;
		for (int i = 0; i < n; i++) pk = Math.Max(pk, Math.Max(Math.Abs(oL[i]), Math.Abs(oR[i])));
		double sc = 0.7 / pk;
		var b8 = new byte[n * 4];
		for (int i = 0; i < n; i++)
		{
			double d = (rng.NextDouble() - rng.NextDouble()) / 32767.0;
			int ql = (int)Math.Round(Math.Clamp(oL[i] * sc + d, -1.0, 1.0) * 32767.0);
			int qr = (int)Math.Round(Math.Clamp(oR[i] * sc + d, -1.0, 1.0) * 32767.0);
			b8[4 * i] = (byte)(ql & 0xff); b8[4 * i + 1] = (byte)((ql >> 8) & 0xff);
			b8[4 * i + 2] = (byte)(qr & 0xff); b8[4 * i + 3] = (byte)((qr >> 8) & 0xff);
		}
		return b8;
	}

	/// render two loops on a worker; Take() returns them as one array [a, b] once both are done
	private byte[] _a, _b;
	public void Start(int seed)
	{
		System.Threading.Tasks.Task.Run(() =>
		{
			var a = RenderLoop(seed, 29f);
			var b = RenderLoop(seed + 101, 37f);
			lock (_lock) { _a = a; _b = b; }
		});
	}
	public Godot.Collections.Array Take()
	{
		lock (_lock)
		{
			if (_a == null || _b == null) return new Godot.Collections.Array();
			var r = new Godot.Collections.Array { _a, _b };
			_a = null; _b = null;
			return r;
		}
	}
}
