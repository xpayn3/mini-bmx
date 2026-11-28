// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
using System;

namespace Runout.Sim
{
	/// <summary>
	/// The transcendental functions exactly as GDScript computes them on PC (Godot's Windows build evaluates libm on
	/// the x87 FPU: the result is the true value rounded to the 64-bit x87 mantissa, then to a double; sin / cos / tan
	/// reduce the argument with the x87's 66-bit pi). Here each is rebuilt in double-double arithmetic and rounded the
	/// x87 way, so the result is the same on every CPU (ARM consoles / phones included) and every compiler.
	///
	/// Where the true value lies within 2 x87 ulps of a double rounding tie (~0.2 % of calls) the x87's own last-bit
	/// error decides. Then <see cref="TieBreak"/> is asked if a host set one (the Godot adapter asks the engine, so the
	/// C# ride matches GDScript bit for bit on PC); without one the double-double answer is kept (deterministic).
	/// </summary>
	public static class SimMath
	{
		public const int F_SIN = 0, F_COS = 1, F_TAN = 2, F_ATAN = 3, F_ASIN = 4, F_ACOS = 5, F_EXP = 6, F_LOG = 7,
			F_TANH = 8, F_ATAN2 = 9, F_POW = 10;

		/// (function id, a, b) -> the platform's own result for a near-tie. b is 0 for one-argument functions.
		public static Func<int, double, double, double> TieBreak;

		/// how many near-ties were met (tests)
		public static long Ties;

		// ---------------------------------------------------------------- constants
		// pi/2 as the x87 holds it (66 bits): C_HI + C_LO exactly
		private static readonly double C_HI = BitConverter.Int64BitsToDouble(0x3FF921FB54442D18);
		private static readonly double C_LO = BitConverter.Int64BitsToDouble(0x3C91A60000000000);
		// true pi/2 to ~160 bits (for the inverse functions' refinement)
		private static readonly double P2_HI = BitConverter.Int64BitsToDouble(0x3FF921FB54442D18);
		private static readonly double P2_LO = BitConverter.Int64BitsToDouble(0x3C91A62633145C07);
		private static readonly double LN2_HI = BitConverter.Int64BitsToDouble(0x3FE62E42FEFA39EF);
		private static readonly double LN2_LO = BitConverter.Int64BitsToDouble(0x3C7ABC9E3B39803F);
		// (x87 ln2 constant) / ln2 - 1: the x87 log = its ln2 * log2(x)
		private static readonly double LN2_X87_REL = BitConverter.Int64BitsToDouble(0x3BD384291B5EE917);
		private static readonly double[] IFH = new double[10], IFL = new double[10];   // 1/n! as double-doubles

		static SimMath()
		{
			double f = 1.0;
			for (int n = 0; n < 10; n++)
			{
				if (n > 0)
					f *= n;
				IFH[n] = 1.0 / f;
				IFL[n] = Math.FusedMultiplyAdd(-IFH[n], f, 1.0) / f;
			}
		}

		// ---------------------------------------------------------------- double-double helpers
		private static void TwoSum(double a, double b, out double s, out double e)
		{
			s = a + b;
			double bb = s - a;
			e = (a - (s - bb)) + (b - bb);
		}

		private static void Mul(double ah, double al, double bh, double bl, out double h, out double l)
		{
			double p = ah * bh;
			double e = Math.FusedMultiplyAdd(ah, bh, -p) + (ah * bl + al * bh);
			h = p + e;
			l = e - (h - p);
		}

		private static void Add(double ah, double al, double bh, double bl, out double h, out double l)
		{
			TwoSum(ah, bh, out double s, out double e);
			e += al + bl;
			h = s + e;
			l = e - (h - s);
		}

		private static void Div(double ah, double al, double bh, double bl, out double h, out double l)
		{
			double q = ah / bh;
			// remainder a - q * b, exact-ish in double-double
			Mul(q, 0.0, bh, bl, out double ph, out double pl);
			Add(ah, al, -ph, -pl, out double rh, out double rl);
			double q2 = (rh + rl) / bh;
			TwoSum(q, q2, out h, out l);
		}

		private static void Sqrt(double ah, double al, out double h, out double l)
		{
			double s = Math.Sqrt(ah);
			if (s == 0.0)
			{
				h = 0.0; l = 0.0;
				return;
			}
			// one Newton step: s + (a - s^2) / (2 s)
			Mul(s, 0.0, s, 0.0, out double sh, out double sl);
			Add(ah, al, -sh, -sl, out double dh, out double dl);
			TwoSum(s, (dh + dl) / (2.0 * s), out h, out l);
		}

		/// <summary>round hi + lo (a normalised double-double) to the 64-bit x87 mantissa, then to a double (nearest-even
		/// both); amb = within 2 x87 ulps of a tie, where the x87's own error could tip it</summary>
		private static double Round64To53(double hi, double lo, out bool amb, double width = 2.0)
		{
			amb = false;
			if (lo == 0.0 || double.IsNaN(lo) || double.IsInfinity(hi))
				return hi;
			long bits = BitConverter.DoubleToInt64Bits(hi);
			double ah = Math.Abs(hi);
			double U = Math.BitIncrement(ah) - ah;
			if ((bits & 0xFFFFFFFFFFFFFL) == 0 && (lo < 0) != (hi < 0))
			{
				// just below a power of two: the grid there is twice as fine and can only tie back to hi (even)
				amb = U / 4 - Math.Abs(lo) < width * U / 4096.0;
				return hi;
			}
			double u64 = U / 2048.0;
			amb = U / 2 - Math.Abs(lo) < width * u64;
			double q = Math.Round(lo / u64, MidpointRounding.ToEven);
			if (Math.Abs(q) < 1024.0)
				return hi;
			if ((bits & 1) == 0)
				return hi;
			return lo > 0 ? Math.BitIncrement(hi) : Math.BitDecrement(hi);
		}

		/// how each function is computed (index F_*), from tools/sim_math_probe.gd (2026-11-28, Godot 4.7.2 Windows):
		/// 0 = the x87 way (64-bit mantissa, then double): sin, cos, exp, log, atan2, pow match GDScript bit for bit
		///     (with the engine settling near-ties; pow only off for tiny bases to large powers, never used by the ride);
		/// 1 = correctly rounded to a double (portable, tests);
		/// 2 = the platform's libm via <see cref="Platform"/>: atan / asin / acos / tanh are the same CRT functions as
		///     .NET's on Windows (0 mismatches), tan matches neither model (the Godot adapter hands it to the engine).
		public static readonly int[] Model = { 0, 0, 2, 2, 2, 2, 0, 0, 2, 0, 0 };

		/// the platform's own function for Model 2 (default: .NET's Math, the same CRT as GDScript's on Windows).
		/// A host that wants the same answer on every platform sets the Model entries to 1 instead.
		public static Func<int, double, double, double> Platform = Net;

		/// x87 ulps either side of a rounding tie that pow leaves to the host (tests: tools/sim_math_probe.gd)
		public static double POW_WIDTH = 256.0;

		public static double Net(int fn, double a, double b) => fn switch
		{
			F_SIN => Math.Sin(a), F_COS => Math.Cos(a), F_TAN => Math.Tan(a), F_ATAN => Math.Atan(a), F_ASIN => Math.Asin(a),
			F_ACOS => Math.Acos(a), F_EXP => Math.Exp(a), F_LOG => Math.Log(a), F_TANH => Math.Tanh(a),
			F_ATAN2 => Math.Atan2(a, b), F_POW => Math.Pow(a, b), _ => double.NaN,
		};

		/// the 64-bit-mantissa value of hi + lo, as a double-double (exact)
		private static void Round64(double hi, double lo, out double h, out double l)
		{
			h = hi; l = 0.0;
			if (lo == 0.0 || double.IsNaN(lo) || double.IsInfinity(hi))
				return;
			double U = Math.BitIncrement(Math.Abs(hi)) - Math.Abs(hi);
			double u64 = U / 2048.0;
			if ((BitConverter.DoubleToInt64Bits(hi) & 0xFFFFFFFFFFFFFL) == 0 && (lo < 0) != (hi < 0))
				u64 /= 2.0;
			l = Math.Round(lo / u64, MidpointRounding.ToEven) * u64;
			TwoSum(h, l, out h, out l);
		}

		/// correctly rounded double of hi + lo; amb = within a hair of a tie
		private static double Round53(double hi, double lo, out bool amb)
		{
			TwoSum(hi, lo, out double h, out double l);
			double U = Math.BitIncrement(Math.Abs(h)) - Math.Abs(h);
			amb = Math.Abs(Math.Abs(l) - U / 2) < U * 1e-9;
			return h;
		}

		private static double Done(double h, double l, int fn, double a, double b)
		{
			bool amb;
			// pow's x87 path (fyl2x, f2xm1) is off by up to ~100 of its own ulps: a wider band is asked of the host
			double r = Model[fn] == 1 ? Round53(h, l, out amb) : Round64To53(h, l, out amb, fn == F_POW ? POW_WIDTH : 2.0);
			if (amb)
			{
				Ties++;
				if (TieBreak != null)
					return TieBreak(fn, a, b);
			}
			return r;
		}

		// ---------------------------------------------------------------- kernels (unrounded double-doubles)
		/// sin (cos = false) or cos (cos = true) of a small reduced argument r (|r| <= ~pi/4)
		private static void Kernel(double rh, double rl, bool cos, out double h, out double l)
		{
			Mul(rh, rl, rh, rl, out double r2h, out double r2l);
			double z = r2h;
			if (!cos)
			{
				double tail = 1.0 / 39916800.0 - z * (1.0 / 6227020800.0 - z * (1.0 / 1307674368000.0 - z * (1.0 / 355687428096000.0
					- z * (1.0 / 121645100408832000.0 - z * (1.0 / 51090942171709440000.0 - z * (1.0 / 25852016738884976640000.0
					- z * (1.0 / 15511210043330985984000000.0 - z * (1.0 / 10888869450418352160768000000.0))))))));
				Mul(r2h, r2l, -tail, 0.0, out h, out l);
				Add(IFH[9], IFL[9], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(-IFH[7], -IFL[7], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(IFH[5], IFL[5], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(-IFH[3], -IFL[3], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Mul(rh, rl, h, l, out h, out l);
				Add(rh, rl, h, l, out h, out l);
			}
			else
			{
				double tail = 1.0 / 3628800.0 - z * (1.0 / 479001600.0 - z * (1.0 / 87178291200.0 - z * (1.0 / 20922789888000.0
					- z * (1.0 / 6402373705728000.0 - z * (1.0 / 2432902008176640000.0 - z * (1.0 / 1124000727777607680000.0
					- z * (1.0 / 620448401733239439360000.0 - z * (1.0 / 403291461126605635584000000.0))))))));
				Mul(r2h, r2l, -tail, 0.0, out h, out l);
				Add(IFH[8], IFL[8], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(-IFH[6], -IFL[6], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(IFH[4], IFL[4], h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(-0.5, 0.0, h, l, out h, out l);
				Mul(r2h, r2l, h, l, out h, out l);
				Add(1.0, 0.0, h, l, out h, out l);
			}
		}

		/// reduce x by k (pi/2) with the given pi/2 (hi + lo); returns the quadrant
		private static long Reduce(double x, double phi, double plo, out double rh, out double rl)
		{
			double k = Math.Round(x / phi);
			double p = k * phi;
			double pe = Math.FusedMultiplyAdd(k, phi, -p);
			double s = x - p;
			TwoSum(s, -(pe + k * plo), out rh, out rl);
			return (long)k & 3;
		}

		/// sin and cos of x (the x87's reduction when x87 = true, else the true pi), unrounded
		private static void SinCos(double x, bool x87, out double sh, out double sl, out double ch, out double cl)
		{
			long q = Reduce(x, x87 ? C_HI : P2_HI, x87 ? C_LO : P2_LO, out double rh, out double rl);
			Kernel(rh, rl, false, out double s0h, out double s0l);
			Kernel(rh, rl, true, out double c0h, out double c0l);
			switch (q)
			{
				case 0: sh = s0h; sl = s0l; ch = c0h; cl = c0l; break;
				case 1: sh = c0h; sl = c0l; ch = -s0h; cl = -s0l; break;
				case 2: sh = -s0h; sl = -s0l; ch = -c0h; cl = -c0l; break;
				default: sh = -c0h; sl = -c0l; ch = s0h; cl = s0l; break;
			}
		}

		/// e^x as a double-double (unrounded)
		private static void ExpDD(double x, out double h, out double l)
		{
			double m = Math.Round(x / LN2_HI);
			double p = m * LN2_HI;
			double pe = Math.FusedMultiplyAdd(m, LN2_HI, -p);
			TwoSum(x - p, -(pe + m * LN2_LO), out double rh, out double rl);
			double z = rh;
			double tail = 1.0 / 5040.0 + z * (1.0 / 40320.0 + z * (1.0 / 362880.0 + z * (1.0 / 3628800.0 + z * (1.0 / 39916800.0
				+ z * (1.0 / 479001600.0 + z * (1.0 / 6227020800.0 + z * (1.0 / 87178291200.0 + z * (1.0 / 1307674368000.0
				+ z * (1.0 / 20922789888000.0 + z * (1.0 / 355687428096000.0 + z * (1.0 / 6402373705728000.0
				+ z * (1.0 / 121645100408832000.0 + z * (1.0 / 2432902008176640000.0)))))))))))));
			Mul(rh, rl, tail, 0.0, out h, out l);
			Add(IFH[6], IFL[6], h, l, out h, out l);
			Mul(rh, rl, h, l, out h, out l);
			Add(IFH[5], IFL[5], h, l, out h, out l);
			Mul(rh, rl, h, l, out h, out l);
			Add(IFH[4], IFL[4], h, l, out h, out l);
			Mul(rh, rl, h, l, out h, out l);
			Add(IFH[3], IFL[3], h, l, out h, out l);
			Mul(rh, rl, h, l, out h, out l);
			Add(0.5, 0.0, h, l, out h, out l);
			Mul(rh, rl, h, l, out h, out l);
			Add(1.0, 0.0, h, l, out h, out l);
			Mul(rh, rl, h, l, out h, out l);
			Add(1.0, 0.0, h, l, out h, out l);
			int mi = (int)m;
			h = Math.ScaleB(h, mi);
			l = Math.ScaleB(l, mi);
		}

		/// e^(xh + xl)
		private static void ExpDD2(double xh, double xl, out double h, out double l)
		{
			ExpDD(xh, out h, out l);
			Mul(h, l, 1.0, xl, out h, out l);   // e^xl ~ 1 + xl
		}

		/// the true ln x as a double-double
		private static void LogDD(double x, out double h, out double l)
		{
			double y0 = Math.Log(x);
			ExpDD(y0, out double eh, out double el);
			Add(x, 0.0, -eh, -el, out double dh, out double dl);
			double c = (dh + dl) / eh;
			TwoSum(y0, c, out h, out l);
		}

		// ---------------------------------------------------------------- the functions
		public static double Sin(double x)
		{
			if (x == 0.0 || double.IsNaN(x))
				return x;
			if (!(Math.Abs(x) < 1e5))
				return TieOr(F_SIN, x, 0, Math.Sin(x));
			SinCos(x, true, out double h, out double l, out _, out _);
			return Done(h, l, F_SIN, x, 0);
		}

		public static double Cos(double x)
		{
			if (double.IsNaN(x))
				return x;
			if (!(Math.Abs(x) < 1e5))
				return TieOr(F_COS, x, 0, Math.Cos(x));
			SinCos(x, true, out _, out _, out double h, out double l);
			return Done(h, l, F_COS, x, 0);
		}

		/// tan: 0 = true tan of the x87-reduced argument, 1 = x87 sin / x87 cos in extended precision (probe models)
		public static int TanModel = 0;

		public static double Tan(double x)
		{
			if (Model[F_TAN] == 2)
				return Platform(F_TAN, x, 0);
			if (x == 0.0 || double.IsNaN(x))
				return x;
			if (!(Math.Abs(x) < 1e5))
				return TieOr(F_TAN, x, 0, Math.Tan(x));
			SinCos(x, true, out double sh, out double sl, out double ch, out double cl);
			if (TanModel == 1)
			{
				// sin and cos each held as x87 values, divided in extended precision
				Round64(sh, sl, out sh, out sl);
				Round64(ch, cl, out ch, out cl);
			}
			Div(sh, sl, ch, cl, out double h, out double l);
			if (TanModel == 1)
				Round64(h, l, out h, out l);
			return Done(h, l, F_TAN, x, 0);
		}

		/// atan2 refined from .NET's answer a0: atan2(y, x) = a0 + atan2(y cos a0 - x sin a0, x cos a0 + y sin a0)
		private static void Atan2DD(double y, double x, out double h, out double l)
		{
			double a0 = Math.Atan2(y, x);
			SinCos(a0, false, out double sh, out double sl, out double ch, out double cl);
			Mul(y, 0.0, ch, cl, out double ph, out double pl);
			Mul(x, 0.0, sh, sl, out double qh, out double ql);
			Add(ph, pl, -qh, -ql, out double nh, out double nl);   // the residual's sine (scaled)
			Mul(x, 0.0, ch, cl, out ph, out pl);
			Mul(y, 0.0, sh, sl, out qh, out ql);
			Add(ph, pl, qh, ql, out double dh, out double dl);     // its cosine (scaled)
			double d = (nh + nl) / (dh + dl);                      // tiny: atan(d) = d to far below an x87 ulp
			TwoSum(a0, d, out h, out l);
		}

		public static double Atan2(double y, double x)
		{
			if (double.IsNaN(x) || double.IsNaN(y) || y == 0.0 || double.IsInfinity(x) || double.IsInfinity(y))
				return Math.Atan2(y, x);
			if (x == 0.0)
				return y > 0 ? Done(P2_HI, P2_LO, F_ATAN2, y, x) : Done(-P2_HI, -P2_LO, F_ATAN2, y, x);
			Atan2DD(y, x, out double h, out double l);
			return Done(h, l, F_ATAN2, y, x);
		}

		public static double Atan(double x)
		{
			if (Model[F_ATAN] == 2)
				return Platform(F_ATAN, x, 0);
			if (x == 0.0 || double.IsNaN(x))
				return x;
			if (double.IsInfinity(x))
				return Math.Atan(x);
			Atan2DD(x, 1.0, out double h, out double l);
			return Done(h, l, F_ATAN, x, 0);
		}

		public static double Asin(double x)
		{
			if (Model[F_ASIN] == 2)
				return Platform(F_ASIN, x, 0);
			if (x == 0.0 || double.IsNaN(x) || Math.Abs(x) > 1.0)
				return Math.Asin(x);
			// atan2(x, sqrt((1 - x)(1 + x))) in double-double
			OneMinusSq(x, out double ph, out double pl);
			Sqrt(ph, pl, out double ch, out double cl);
			double a0 = Math.Asin(x);
			SinCos(a0, false, out double sh, out double sl, out double c0h, out double c0l);
			// residual = atan2(x c0 - c s0, c c0 + x s0)
			Mul(x, 0.0, c0h, c0l, out double ah, out double al);
			Mul(ch, cl, sh, sl, out double bh, out double bl);
			Add(ah, al, -bh, -bl, out double nh, out double nl);
			Mul(ch, cl, c0h, c0l, out ah, out al);
			Mul(x, 0.0, sh, sl, out bh, out bl);
			Add(ah, al, bh, bl, out double dh, out double dl);
			TwoSum(a0, (nh + nl) / (dh + dl), out double h, out double l);
			return Done(h, l, F_ASIN, x, 0);
		}

		public static double Acos(double x)
		{
			if (Model[F_ACOS] == 2)
				return Platform(F_ACOS, x, 0);
			if (double.IsNaN(x) || Math.Abs(x) > 1.0)
				return Math.Acos(x);
			if (x == 1.0)
				return 0.0;
			// acos x = atan2(sqrt(1 - x^2), x)
			OneMinusSq(x, out double ph, out double pl);
			Sqrt(ph, pl, out double ch, out double cl);
			double a0 = Math.Acos(x);
			SinCos(a0, false, out double sh, out double sl, out double c0h, out double c0l);
			// residual = atan2(c c0 - x s0, x c0 + c s0)
			Mul(ch, cl, c0h, c0l, out double ah, out double al);
			Mul(x, 0.0, sh, sl, out double bh, out double bl);
			Add(ah, al, -bh, -bl, out double nh, out double nl);
			Mul(x, 0.0, c0h, c0l, out ah, out al);
			Mul(ch, cl, sh, sl, out bh, out bl);
			Add(ah, al, bh, bl, out double dh, out double dl);
			TwoSum(a0, (nh + nl) / (dh + dl), out double h, out double l);
			return Done(h, l, F_ACOS, x, 0);
		}

		/// 1 - x^2 as a double-double
		private static void OneMinusSq(double x, out double h, out double l)
		{
			Mul(x, 0.0, x, 0.0, out double sh, out double sl);
			Add(1.0, 0.0, -sh, -sl, out h, out l);
		}

		public static double Exp(double x)
		{
			if (double.IsNaN(x))
				return x;
			if (x == 0.0)
				return 1.0;
			if (!(Math.Abs(x) < 700.0))
				return TieOr(F_EXP, x, 0, Math.Exp(x));
			ExpDD(x, out double h, out double l);
			return Done(h, l, F_EXP, x, 0);
		}

		public static double Log(double x)
		{
			if (!(x > 1e-300) || double.IsInfinity(x))
				return TieOr(F_LOG, x, 0, Math.Log(x));
			if (x == 1.0)
				return 0.0;
			LogDD(x, out double h, out double l);
			l += h * LN2_X87_REL;   // the x87 multiplies log2(x) by its rounded ln2
			double hh = h + l;
			l -= hh - h;
			return Done(hh, l, F_LOG, x, 0);
		}

		public static double Tanh(double x)
		{
			if (Model[F_TANH] == 2)
				return Platform(F_TANH, x, 0);
			if (x == 0.0 || double.IsNaN(x))
				return x;
			double ax = Math.Abs(x);
			if (ax > 22.0)
				return Math.Sign(x);
			// (e^2x - 1) / (e^2x + 1), with e^-2|x| for accuracy
			ExpDD(-2.0 * ax, out double eh, out double el);
			Add(1.0, 0.0, -eh, -el, out double nh, out double nl);
			Add(1.0, 0.0, eh, el, out double dh, out double dl);
			Div(nh, nl, dh, dl, out double h, out double l);
			if (x < 0)
			{
				h = -h; l = -l;
			}
			return Done(h, l, F_TANH, x, 0);
		}

		public static double Pow(double x, double y)
		{
			if (y == 0.0)
				return 1.0;
			if (y == 1.0)
				return x;
			if (double.IsNaN(x) || double.IsNaN(y))
				return double.NaN;
			if (x == 1.0)
				return 1.0;
			if (x <= 0.0 || double.IsInfinity(x) || double.IsInfinity(y))
				return TieOr(F_POW, x, y, Math.Pow(x, y));
			LogDD(x, out double lh, out double ll);
			// the x87 way (fyl2x, f2xm1, fscale): t = y log2 x rounded to the 64-bit mantissa, then 2^t
			Div(lh, ll, LN2_HI, LN2_LO, out double th, out double tl);
			Mul(th, tl, y, 0.0, out th, out tl);
			if (!(Math.Abs(th) < 1000.0))
				return TieOr(F_POW, x, y, Math.Pow(x, y));
			Round64(th, tl, out th, out tl);
			Mul(th, tl, LN2_HI, LN2_LO, out double ph, out double pl);
			ExpDD2(ph, pl, out double h, out double l);
			return Done(h, l, F_POW, x, y);
		}

		private static double TieOr(int fn, double a, double b, double fallback)
		{
			Ties++;
			return TieBreak != null ? TieBreak(fn, a, b) : fallback;
		}

		public static double Sqrt(double x) => Math.Sqrt(x);
	}
}
