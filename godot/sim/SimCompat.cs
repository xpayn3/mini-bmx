// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
// The few .NET Core maths calls the ride needs for Godot-exact results, for runtimes that don't have them (Unity's
// .NET Standard 2.1 Mono: no Math.FusedMultiplyAdd / BitIncrement / ScaleB, no public BitOperations). Under .NET 8
// (the Godot build) every call goes straight to System.Math, so Godot rides exactly what it did. Elsewhere (or with
// RUNOUT_COMPAT defined: unity/SimTests builds that way to prove these against the Godot reference traces) the same
// results are computed exactly in plain double / integer maths:
//   ScaleB / ScaleBF: the musl scalbn / scalbnf algorithm .NET uses; BitIncrement / BitDecrement: .NET's own;
//   Fma: Dekker's exact product + an exact sum (correctly rounded; BigInteger only when the fast path can't prove it).
using System;
using System.Numerics;

namespace Runout.Sim
{
	public static class SimCompat
	{
#if NETCOREAPP && !RUNOUT_COMPAT
		public static double Fma(double a, double b, double c) => Math.FusedMultiplyAdd(a, b, c);
		public static double BitIncrement(double x) => Math.BitIncrement(x);
		public static double BitDecrement(double x) => Math.BitDecrement(x);
		public static double ScaleB(double x, int n) => Math.ScaleB(x, n);
		public static float ScaleBF(float x, int n) => MathF.ScaleB(x, n);
		public static int Lzc(uint v) => System.Numerics.BitOperations.LeadingZeroCount(v);
		public static int Lzc(ulong v) => System.Numerics.BitOperations.LeadingZeroCount(v);
#else
		public static int Lzc(uint v)
		{
			if (v == 0) return 32;
			int n = 0;
			while ((v & 0x80000000u) == 0) { v <<= 1; n++; }
			return n;
		}

		public static int Lzc(ulong v)
		{
			if (v == 0) return 64;
			int n = 0;
			while ((v & 0x8000000000000000ul) == 0) { v <<= 1; n++; }
			return n;
		}

		/// .NET's Math.BitIncrement
		public static double BitIncrement(double x)
		{
			long bits = BitConverter.DoubleToInt64Bits(x);
			if (((bits >> 32) & 0x7FF00000) >= 0x7FF00000)
				return bits == unchecked((long)0xFFF0000000000000) ? double.MinValue : x;   // NaN / +inf as they are, -inf -> MinValue
			if (bits == unchecked((long)0x8000000000000000)) return double.Epsilon;           // -0.0
			bits += bits < 0 ? -1 : +1;
			return BitConverter.Int64BitsToDouble(bits);
		}

		/// .NET's Math.BitDecrement
		public static double BitDecrement(double x)
		{
			long bits = BitConverter.DoubleToInt64Bits(x);
			if (((bits >> 32) & 0x7FF00000) >= 0x7FF00000)
				return bits == 0x7FF0000000000000 ? double.MaxValue : x;   // NaN / -inf as they are, +inf -> MaxValue
			if (bits == 0) return -double.Epsilon;                         // +0.0
			bits += bits < 0 ? +1 : -1;
			return BitConverter.Int64BitsToDouble(bits);
		}

		/// musl scalbn (what .NET's Math.ScaleB is)
		public static double ScaleB(double x, int n)
		{
			double y = x;
			double p1023 = BitConverter.Int64BitsToDouble(0x7FE0000000000000);   // 2^1023
			double pm1022 = BitConverter.Int64BitsToDouble(0x0010000000000000);  // 2^-1022
			double p53 = BitConverter.Int64BitsToDouble(0x4340000000000000);     // 2^53
			if (n > 1023)
			{
				y *= p1023; n -= 1023;
				if (n > 1023) { y *= p1023; n -= 1023; if (n > 1023) n = 1023; }
			}
			else if (n < -1022)
			{
				// make sure the final n < -53 to avoid double rounding in the subnormal range
				y *= pm1022 * p53; n += 1022 - 53;
				if (n < -1022) { y *= pm1022 * p53; n += 1022 - 53; if (n < -1022) n = -1022; }
			}
			return y * BitConverter.Int64BitsToDouble((long)(0x3FF + n) << 52);
		}

		/// musl scalbnf (what .NET's MathF.ScaleB is)
		public static float ScaleBF(float x, int n)
		{
			float y = x;
			float p127 = BitConverter.Int32BitsToSingle(0x7F000000);    // 2^127
			float pm126 = BitConverter.Int32BitsToSingle(0x00800000);   // 2^-126
			float p24 = BitConverter.Int32BitsToSingle(0x4B800000);     // 2^24
			if (n > 127)
			{
				y *= p127; n -= 127;
				if (n > 127) { y *= p127; n -= 127; if (n > 127) n = 127; }
			}
			else if (n < -126)
			{
				y *= pm126 * p24; n += 126 - 24;
				if (n < -126) { y *= pm126 * p24; n += 126 - 24; if (n < -126) n = -126; }
			}
			return y * BitConverter.Int32BitsToSingle((0x7F + n) << 23);
		}

		/// a * b + c rounded once (IEEE fused multiply-add)
		public static double Fma(double a, double b, double c)
		{
			if (double.IsNaN(a) || double.IsNaN(b) || double.IsNaN(c) || double.IsInfinity(a) || double.IsInfinity(b) || double.IsInfinity(c))
				return a * b + c;
			double p = a * b;
			if (a == 0 || b == 0) return p + c;
			if (double.IsInfinity(p) || Math.Abs(p) < 1e-290 || Math.Abs(p) > 1e290) return FmaExact(a, b, c);
			// exact product p + e (Dekker / Veltkamp: no overflow / underflow in the range checked above)
			double e = TwoProductErr(a, b, p);
			// exact sum c + p = s + t
			double s = c + p;
			double bb = s - c;
			double t = (c - (s - bb)) + (p - bb);
			// a*b + c = s + t + e exactly. If t + e is itself exact (u), then s + u IS a*b + c and the hardware's one rounding
			// of it is the correctly rounded result (the ride's uses - a product's exact error - always take this path)
			double u = t + e;
			double ub = u - t;
			double ue = (t - (u - ub)) + (e - ub);
			if (ue == 0) return s + u;
			return FmaExact(a, b, c);
		}

		static double TwoProductErr(double a, double b, double p)
		{
			const double SPLIT = 134217729.0;   // 2^27 + 1
			double ca = SPLIT * a, ah = ca - (ca - a), al = a - ah;
			double cb = SPLIT * b, bh = cb - (cb - b), bl = b - bh;
			return ((ah * bh - p) + ah * bl + al * bh) + al * bl;
		}

		/// exact a * b + c with integers, then rounded to nearest even
		static double FmaExact(double a, double b, double c)
		{
			Decompose(a, out BigInteger ma, out int ea);
			Decompose(b, out BigInteger mb, out int eb);
			Decompose(c, out BigInteger mc, out int ec);
			BigInteger mp = ma * mb; int ep = ea + eb;
			int e0 = Math.Min(ep, ec);
			BigInteger sum = (mp << (ep - e0)) + (mc << (ec - e0));
			if (sum.IsZero) return a * b + c;   // (signed zero as IEEE gives it)
			return ToDouble(sum, e0);
		}

		static void Decompose(double x, out BigInteger m, out int e)
		{
			long bits = BitConverter.DoubleToInt64Bits(x);
			bool neg = bits < 0;
			int exp = (int)((bits >> 52) & 0x7FF);
			long man = bits & 0xFFFFFFFFFFFFFL;
			if (exp == 0) exp = 1; else man |= 1L << 52;
			e = exp - 1075;
			m = neg ? -new BigInteger(man) : new BigInteger(man);
		}

		/// sum x 2^e rounded to the nearest double (ties to even)
		static double ToDouble(BigInteger sum, int e)
		{
			bool neg = sum.Sign < 0;
			BigInteger m = BigInteger.Abs(sum);
			int bits = (int)Math.Ceiling(BigInteger.Log(m, 2) + 1e-9);
			while (BigInteger.One << bits <= m) bits++;
			while (bits > 0 && BigInteger.One << (bits - 1) > m) bits--;
			// keep 53 significant bits (fewer in the subnormal range)
			int top = e + bits;                 // m x 2^e lies in [2^(top-1), 2^top)
			int keep = Math.Min(53, top - (-1074));
			if (keep < 0) keep = 0;
			int shift = bits - keep;
			BigInteger q;
			if (shift > 0)
			{
				q = m >> shift;
				BigInteger rem = m - (q << shift);
				BigInteger half = BigInteger.One << (shift - 1);
				if (rem > half || (rem == half && !q.IsEven)) q += 1;
				e += shift;
			}
			else q = m;
			double r = (double)q;   // exact: q fits in 54 bits
			r = ScaleB(r, e);
			return neg ? -r : r;
		}
#endif
	}
}
