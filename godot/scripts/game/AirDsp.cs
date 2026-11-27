using System;

/// Small audio building blocks shared by the procedural air sounds (PassBySynth, VastAirSynth): pink noise,
/// a slow random drift, a state-variable band-pass and a one-pole low-pass whose settings may move every sample.
public static class AirDsp
{
	public const int RATE = 48000;

	// pink-ish noise: Paul Kellet's filter on white noise
	public struct Pink
	{
		public double b0, b1, b2, b3, b4, b5, b6;
		public double Next(Random r)
		{
			double w = r.NextDouble() * 2.0 - 1.0;
			b0 = 0.99886 * b0 + w * 0.0555179;
			b1 = 0.99332 * b1 + w * 0.0750759;
			b2 = 0.96900 * b2 + w * 0.1538520;
			b3 = 0.86650 * b3 + w * 0.3104856;
			b4 = 0.55000 * b4 + w * 0.5329522;
			b5 = -0.7616 * b5 - w * 0.0168980;
			double o = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
			b6 = w * 0.115926;
			return o * 0.11;
		}
	}

	// smooth random wander (turbulence / gusts / wow): white noise low-passed twice, about unit variance
	public struct Drift
	{
		public double y1, y2, a, sc, hz0;
		public double Next(Random r, double hz)
		{
			if (hz != hz0) { hz0 = hz; a = 1.0 - Math.Exp(-2.0 * Math.PI * hz / RATE); sc = Math.Sqrt(6.0 / a); }
			y1 += a * ((r.NextDouble() * 2.0 - 1.0) * sc - y1);
			y2 += a * (y1 - y2);
			return Math.Clamp(y2 * 1.4, -2.0, 2.0);
		}
	}

	// Chamberlin state-variable filter
	public struct Svf
	{
		public double lo, bp, f, fc0;
		public double Band(double x, double fc, double q)
		{
			if (Math.Abs(fc - fc0) > fc0 * 0.0005) { fc0 = fc; f = 2.0 * Math.Sin(Math.PI * Math.Min(fc, RATE / 6.5) / RATE); }
			double hi = x - lo - bp / q;
			bp += f * hi;
			lo += f * bp;
			return bp;
		}
	}

	// one-pole low-pass with a moving cutoff
	public struct Lp
	{
		public double y, a, fc0;
		public double Run(double x, double fc)
		{
			if (Math.Abs(fc - fc0) > fc0 * 0.0005) { fc0 = fc; a = 1.0 - Math.Exp(-2.0 * Math.PI * Math.Min(fc, 20000.0) / RATE); }
			y += a * (x - y);
			return y;
		}
	}

}
