using Godot;
using System;
using System.Collections.Generic;

// C# port of TerrainField (terrain_field.gd): the same height / surface / colour functions, the same float64
// arithmetic in the same order (GDScript floats are doubles, ints are int64), so the results match the
// GDScript field bit for bit. Only the query side is ported: setup() stays in GDScript (course layout,
// marking, route features) and hands its finished tables over with setup_from(). The GDScript TerrainField
// remains the reference; Terrain.USE_CS switches between the two.
//
// Threading: like the GDScript field, one instance per thread. The seed data (noise lattice, course arrays,
// route features, profiles, colours) is immutable and shared between fork()s; the little caches (course
// query, jump cells, memos) are per instance.
//
// Member names are snake_case on purpose: GDScript (terrain.gd, terrain_chunk_builder.gd) duck-types this
// object and the GDScript TerrainField through the same calls.

internal abstract class TfProfile
{
	public double length;
	public abstract double ev(double u);
}

internal sealed class TfFlat : TfProfile
{
	public TfFlat(double l) { length = l; }
	public override double ev(double u) => 0.0;
}

internal sealed class TfHermite : TfProfile
{
	private readonly double[] ku, kh, ksi, kso;

	// knots: [u, h, slopeIn, (slopeOut)]
	public TfHermite(double[][] knots)
	{
		int n = knots.Length;
		ku = new double[n]; kh = new double[n]; ksi = new double[n]; kso = new double[n];
		for (int i = 0; i < n; i++)
		{
			var k = knots[i];
			ku[i] = k[0]; kh[i] = k[1]; ksi[i] = k[2];
			kso[i] = k.Length > 3 ? k[3] : k[2];
		}
		length = ku[n - 1];
	}

	public override double ev(double u)
	{
		if (u <= 0.0 || u >= length)
			return 0.0;
		int i = 0;
		while (ku[i + 1] < u)
			i++;
		double u0 = ku[i];
		double h0 = kh[i];
		double so0 = kso[i];
		double u1 = ku[i + 1];
		double h1 = kh[i + 1];
		double si1 = ksi[i + 1];
		double d = u1 - u0;
		double t = (u - u0) / d;
		double t2 = t * t;
		double t3 = t2 * t;
		return (2 * t3 - 3 * t2 + 1) * h0 + (t3 - 2 * t2 + t) * d * so0 + (-2 * t3 + 3 * t2) * h1 + (t3 - t2) * d * si1;
	}
}

internal sealed class TfRollers : TfProfile
{
	private readonly TfHermite w;
	private readonly long n;

	public TfRollers(long count, double amp)
	{
		var ks = new double[TfSet.WHOOP.Length][];
		for (int i = 0; i < ks.Length; i++)
		{
			var k = TfSet.WHOOP[i];
			ks[i] = new[] { k[0], k[1] * amp / 0.48, k[2] * amp / 0.48 };
		}
		w = new TfHermite(ks);
		n = count;
		length = n * w.length;
	}

	public override double ev(double u)
	{
		if (u <= 0.0 || u >= n * w.length)
			return 0.0;
		return w.ev(u % w.length);   // fmod
	}
}

internal sealed class TfLine : TfProfile
{
	private readonly double[] starts;
	private readonly TfProfile[] parts;

	// items: TfProfile or a double gap
	public TfLine(params object[] items)
	{
		var st = new List<double>();
		var ps = new List<TfProfile>();
		double at = 0.0;
		foreach (var p in items)
		{
			if (p is double g)
			{
				at += g;
				continue;
			}
			var pr = (TfProfile)p;
			st.Add(at);
			ps.Add(pr);
			at += pr.length;
		}
		starts = st.ToArray();
		parts = ps.ToArray();
		length = at;
	}

	public override double ev(double u)
	{
		for (int i = 0; i < parts.Length; i++)
		{
			double s = starts[i];
			var p = parts[i];
			if (u > s && u < s + p.length)
				return p.ev(u - s);
		}
		return 0.0;
	}
}

/// wooden deck: top(u) above the flattened ground for u0 <= u <= u1, |w| <= half
internal sealed class TfWood
{
	public readonly long kind;   // 0 woodKicker, 1 skinny, 2 bridge
	public readonly double u0, u1, half;
	public readonly bool back_wall;
	private readonly TfProfile kick, skin;

	public TfWood(long k, double a, double b, double hf, bool bw, TfProfile kk, TfProfile sk)
	{
		kind = k; u0 = a; u1 = b; half = hf; back_wall = bw; kick = kk; skin = sk;
	}

	public double top(double u)
	{
		if (kind == 0)
			return u >= 3.8 ? 0.95 : kick.ev(u);
		if (kind == 1)
		{
			if (u < 4.0)
				return skin.ev(u);
			if (u < 15.0)
				return 0.85;
			return skin.ev(TerrainFieldCs.maxf(0.001, 19.0 - u));
		}
		if (u < 2.0)
			return ramp(0.0, 2.0, 0.02, 0.45, u);
		if (u < u1 - 2.0)
			return 0.45;
		return ramp(u1 - 2.0, u1, 0.45, 0.02, u);
	}

	private static double ramp(double a, double b, double h0, double h1, double u)
	{
		return h0 + (h1 - h0) * TerrainFieldCs.minf(1.0, TerrainFieldCs.maxf(0.0, (u - a) / (b - a)));
	}
}

/// trail_features.gd make_set(): immutable, so one set serves every thread
internal static class TfSet
{
	public const double WOOD_EDGE = 0.12, WOOD_BEVEL = 1.2, WOOD_BEVEL_MAX = 0.44;
	public static readonly double[][] TABLE = { new[] { 0.0, 0.0, 0.0, 0.0 }, new[] { 1.8, 0.0004, 0.0016, 0.0016 }, new[] { 2.6, 0.0033, 0.0063, 0.0063 }, new[] { 3.4, 0.0113, 0.0141, 0.0141 }, new[] { 4.25, 0.028, 0.0258, 0.0258 }, new[] { 5.05, 0.0541, 0.0401, 0.0401 }, new[] { 5.9, 0.0959, 0.0588, 0.0588 }, new[] { 6.75, 0.155, 0.081, 0.081 }, new[] { 7.55, 0.2294, 0.1054, 0.1054 }, new[] { 8.4, 0.3313, 0.135, 0.135 }, new[] { 9.2, 0.4517, 0.1666, 0.1666 }, new[] { 10.05, 0.6091, 0.2044, 0.2044 }, new[] { 10.85, 0.7883, 0.2444, 0.2444 }, new[] { 11.7, 1.0159, 0.292, 0.292 }, new[] { 12.55, 1.2865, 0.346, 0.346 }, new[] { 13.35, 1.5858, 0.4035, 0.4035 }, new[] { 13.4, 1.606, 0.404, 0.404 }, new[] { 15.95, 2.6179, 0.404, 0.0 }, new[] { 28.75, 2.6179, 0.0, 0.0 }, new[] { 29.55, 2.4782, -0.3371, -0.3371 }, new[] { 29.75, 2.3993, -0.4225, -0.4225 }, new[] { 32.9, 1.0729, -0.4225, -0.4225 }, new[] { 33.7, 0.7661, -0.35, -0.35 }, new[] { 34.55, 0.5012, -0.278, -0.278 }, new[] { 35.4, 0.2958, -0.2098, -0.2098 }, new[] { 36.2, 0.1543, -0.1482, -0.1482 }, new[] { 37.05, 0.0572, -0.0844, -0.0844 }, new[] { 37.9, 0.0138, -0.0216, -0.0216 }, new[] { 38.2, 0.0, 0.0, 0.0 }, new[] { 39.2, 0.0, 0.0, 0.0 } };   // baked: tools/bake_jumps.gd
	public static readonly double[][] DOUBLE = { new[] { 0.0, 0, 0 }, new[] { 8.0, 2.16, 0.58, -1.6 }, new[] { 9.6, 0.56, 0, 0 }, new[] { 12.0, 0.56, 0, 1.4 },
		new[] { 14.72, 1.92, 0, 0 }, new[] { 16.32, 1.92, 0, 0 }, new[] { 20.0, 1.36, -0.34 }, new[] { 30.4, 0.24, -0.16 }, new[] { 36.8, 0, 0 } };
	public static readonly double[][] KICKER = { new[] { 0.0, 0.0, 0.0, 0.0 }, new[] { 1.8, 0.0007, 0.0026, 0.0026 }, new[] { 2.6, 0.0056, 0.0105, 0.0105 }, new[] { 3.4, 0.0189, 0.0236, 0.0236 }, new[] { 4.25, 0.0469, 0.0434, 0.0434 }, new[] { 5.05, 0.0909, 0.0674, 0.0674 }, new[] { 5.9, 0.1612, 0.099, 0.099 }, new[] { 6.75, 0.2609, 0.1369, 0.1369 }, new[] { 7.55, 0.3868, 0.1789, 0.1789 }, new[] { 8.4, 0.5604, 0.2308, 0.2308 }, new[] { 9.2, 0.7671, 0.2876, 0.2876 }, new[] { 9.45, 0.8415, 0.3057, 0.3057 }, new[] { 11.45, 1.4508, 0.3057, 0.0 }, new[] { 22.2, 1.4508, 0.0, 0.0 }, new[] { 22.95, 1.3284, -0.304, -0.304 }, new[] { 25.55, 0.551, -0.304, -0.304 }, new[] { 26.35, 0.3377, -0.2342, -0.2342 }, new[] { 27.15, 0.1788, -0.1676, -0.1676 }, new[] { 27.95, 0.0723, -0.103, -0.103 }, new[] { 28.8, 0.0151, -0.0358, -0.0358 }, new[] { 29.3, 0.0, 0.0, 0.0 }, new[] { 30.3, 0.0, 0.0, 0.0 } };   // baked: tools/bake_jumps.gd
	public static readonly double[][] WHOOP = { new[] { 0.0, 0, 0 }, new[] { 1.6, 0.3, 0.3 }, new[] { 2.6, 0.48, 0 }, new[] { 8.6, 0.08, -0.09 }, new[] { 10.0, 0, 0 } };

	public static readonly string[] FEATURE_TYPES = { "table", "table", "double", "kicker", "rhythm", "tableLine", "flow", "doubleLine",
		"woodKicker", "woodKicker", "skinny", "bridge" };
	public static readonly string[] ROUTE_TYPES = { "table", "table", "kicker", "rhythm", "tableLine", "flow", "woodKicker", "bridge" };

	// the same three at their old size, for the free-ride jumps out in the land (see trail_features.gd)
	public static readonly double[][] TABLE_S = { new[] { 0.0, 0, 0 }, new[] { 5.5, 1.25, 0.5, 0 }, new[] { 9.5, 1.25, 0, 0 }, new[] { 11.5, 0.95, -0.36 }, new[] { 17.0, 0.18, -0.2 }, new[] { 21.0, 0, 0 } };
	public static readonly double[][] DOUBLE_S = { new[] { 0.0, 0, 0 }, new[] { 5.0, 1.35, 0.58, -1.6 }, new[] { 6.0, 0.35, 0, 0 }, new[] { 7.5, 0.35, 0, 1.4 },
		new[] { 9.2, 1.2, 0, 0 }, new[] { 10.2, 1.2, 0, 0 }, new[] { 12.5, 0.85, -0.34 }, new[] { 19.0, 0.15, -0.16 }, new[] { 23.0, 0, 0 } };
	public static readonly double[][] KICKER_S = { new[] { 0.0, 0, 0 }, new[] { 3.2, 0.7, 0.42, 0 }, new[] { 4.0, 0.7, 0, 0 }, new[] { 6.5, 0.48, -0.2 }, new[] { 14.0, 0, 0 } };
	public static readonly Dictionary<string, TfProfile> SMALL;
	public static readonly Dictionary<string, TfProfile> PROFILES;
	public static readonly Dictionary<string, TfWood> WOOD;
	public static readonly Dictionary<string, TfProfile> DIG;

	static TfSet()
	{
		var table = new TfHermite(TABLE);
		var dbl = new TfHermite(DOUBLE);
		var kicker = new TfHermite(KICKER);
		var tableS = new TfHermite(TABLE_S);
		var dblS = new TfHermite(DOUBLE_S);
		var kickerS = new TfHermite(KICKER_S);
		SMALL = new Dictionary<string, TfProfile>
		{
			["table"] = tableS, ["double"] = dblS, ["kicker"] = kickerS, ["tableLine"] = new TfLine(tableS, 3.0, kickerS),
			["flow"] = new TfLine(kickerS, 3.0, new TfRollers(3, 0.45)), ["doubleLine"] = new TfLine(dblS, 3.0, kickerS),
		};
		PROFILES = new Dictionary<string, TfProfile>
		{
			["table"] = table, ["double"] = dbl, ["kicker"] = kicker,
			["rhythm"] = new TfRollers(4, 0.5),
			["tableLine"] = new TfLine(table, 3.0, kicker),
			["flow"] = new TfLine(kicker, 3.0, new TfRollers(3, 0.45)),
			["doubleLine"] = new TfLine(dbl, 3.0, kicker),
			["woodKicker"] = new TfHermite(new[] { new[] { 0.0, 0, 0 }, new[] { 4.6, 0, 0 }, new[] { 6.4, 0.9, 0.1, 0 }, new[] { 7.4, 0.9, 0, 0 }, new[] { 10.0, 0.72, -0.17 }, new[] { 20.0, 0.14, -0.08 }, new[] { 26.0, 0, 0 } }),
			["skinny"] = new TfFlat(19.0),
			["bridge"] = new TfFlat(15.0),
			["gorge"] = new TfFlat(36.0),
			["rope"] = new TfFlat(46.0),
		};
		var kick = new TfHermite(new[] { new[] { 0.0, 0, 0.1 }, new[] { 3.8, 0.95, 0.4 } });
		var skin = new TfHermite(new[] { new[] { 0.0, 0.02, 0.05 }, new[] { 2.0, 0.42, 0.3 }, new[] { 4.0, 0.85, 0 } });
		WOOD = new Dictionary<string, TfWood>
		{
			["woodKicker"] = new TfWood(0, 0.0, 3.8, 0.85, true, kick, skin),
			["skinny"] = new TfWood(1, 0.0, 19.0, 0.33, false, kick, skin),
			["bridge"] = new TfWood(2, 0.0, 15.0, 1.0, false, kick, skin),
			["gorge"] = new TfWood(2, 0.0, 36.0, 1.4, false, kick, skin),
		};
		DIG = new Dictionary<string, TfProfile>
		{
			["bridge"] = new TfHermite(new[] { new[] { 0.0, 0, 0 }, new[] { 1.6, 0, 0 }, new[] { 3.4, -1.9, 0 }, new[] { 11.6, -1.9, 0 }, new[] { 13.4, 0, 0 }, new[] { 15.0, 0, 0 } }),
			["gorge"] = new TfHermite(new[] { new[] { 0.0, 0, 0 }, new[] { 3.0, 0, 0 }, new[] { 4.6, -9.0, 0 }, new[] { 31.4, -9.0, 0 }, new[] { 33.0, 0, 0 }, new[] { 36.0, 0, 0 } }),
		};
	}
}

/// a designed feature (TerrainField.Feat); immutable once made
internal sealed class TfFeat
{
	public double x, z, dx, dz, len, b0, b1, half, s;
	public double[] air = System.Array.Empty<double>();   // TrailFeatures.AIR of its type
	public bool canyon;   // rope bridge: a canyon across the land (TerrainField.canyon_rims)
	public double ramp = 6.0;   // TerrainField.Feat.ramp: the trail eased onto the feature's plane over this
	public TfProfile prof;
	public string type;
	public TfWood wood;
	public TfProfile dig;
}

/// mulberry32 exactly as WorldRng (uint arithmetic == the GDScript int32 emulation)
internal struct TfRng
{
	private uint a;

	public TfRng(int seed) { a = (uint)seed; }

	public double next()
	{
		a += 0x6D2B79F5u;
		uint t = a;
		t = (t ^ (t >> 15)) * (1u | t);
		t = (t + (t ^ (t >> 7)) * (61u | t)) ^ t;
		return (t ^ (t >> 14)) / 4294967296.0;
	}

	public static int i32(long v) => unchecked((int)v);
}

/// sin / exp / log as GDScript computes them. Godot's official Windows build (MinGW) evaluates libm on the
/// x87 FPU: the result is (almost exactly) the true value rounded to the 64-bit x87 mantissa, then to a double
/// (and for sin the argument is reduced with the x87's 66-bit pi). .NET's Math.Sin / Exp / Log differ from
/// that by 1 ulp in ~3% / 0.6% / 0.1% of cases, so here they are rebuilt in double-double arithmetic and
/// rounded the x87 way. Where the true value lies within 2 x87 ulps of a double rounding tie (~0.2% of
/// calls) the x87's own last-bit error decides, so `amb` is set and the caller asks the engine itself.
internal static class TfX87
{
	// pi/2 as the x87 holds it (66 bits): C_HI + C_LO exactly
	private static readonly double C_HI = BitConverter.Int64BitsToDouble(0x3FF921FB54442D18);
	private static readonly double C_LO = BitConverter.Int64BitsToDouble(0x3C91A60000000000);
	private static readonly double LN2_HI = BitConverter.Int64BitsToDouble(0x3FE62E42FEFA39EF);
	private static readonly double LN2_LO = BitConverter.Int64BitsToDouble(0x3C7ABC9E3B39803F);
	// (x87 ln2 constant) / ln2 - 1: log = ln2_x87 * log2(x)
	private static readonly double LN2_X87_REL = BitConverter.Int64BitsToDouble(0x3BD384291B5EE917);
	// 1/n! as double-doubles
	private static readonly double[] IFH = new double[10], IFL = new double[10];

	static TfX87()
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

	// ---- double-double helpers ----
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

	/// round hi + lo (normalised double-double) to the 64-bit x87 mantissa, then to a double (nearest-even both);
	/// amb: within 2 x87 ulps of a tie, where the x87's own error could tip it
	private static double Round64To53(double hi, double lo, out bool amb)
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
			amb = U / 4 - Math.Abs(lo) < 2.0 * U / 4096.0;
			return hi;
		}
		double u64 = U / 2048.0;
		amb = U / 2 - Math.Abs(lo) < 2.0 * u64;
		double q = Math.Round(lo / u64, MidpointRounding.ToEven);
		if (Math.Abs(q) < 1024.0)
			return hi;
		if ((bits & 1) == 0)
			return hi;
		return lo > 0 ? Math.BitIncrement(hi) : Math.BitDecrement(hi);
	}

	public static double Sin(double x, out bool amb)
	{
		amb = false;
		if (!(Math.Abs(x) < 1e5) || x == 0.0)
		{
			amb = x != 0.0;
			return Math.Sin(x);
		}
		double k = Math.Round(x / C_HI);
		// r = x - k * (C_HI + C_LO), as a double-double
		double p = k * C_HI;
		double pe = Math.FusedMultiplyAdd(k, C_HI, -p);
		double s = x - p;   // exact (Sterbenz)
		TwoSum(s, -(pe + k * C_LO), out double rh, out double rl);
		Mul(rh, rl, rh, rl, out double r2h, out double r2l);
		long q = (long)k & 3;
		double h, l;
		if ((q & 1) == 0)
		{
			// sin r = r + r^3 (-1/3! + r^2 (1/5! + r^2 (-1/7! + r^2 (1/9! - r^2 tail))))
			double z = r2h;
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
			// cos r = 1 + r^2 (-1/2 + r^2 (1/4! + r^2 (-1/6! + r^2 (1/8! - r^2 tail))))
			double z = r2h;
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
		if (q >= 2)
		{
			h = -h; l = -l;
		}
		return Round64To53(h, l, out amb);
	}

	/// e^x as a double-double (unrounded)
	private static void ExpDD(double x, out double h, out double l)
	{
		double m = Math.Round(x / LN2_HI);
		double p = m * LN2_HI;
		double pe = Math.FusedMultiplyAdd(m, LN2_HI, -p);
		TwoSum(x - p, -(pe + m * LN2_LO), out double rh, out double rl);   // x - p exact for |m| >= 1 (Sterbenz)
		// e^r = 1 + r + r^2/2 + ... : r^7.. in double, the rest double-double
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

	public static double Exp(double x, out bool amb)
	{
		if (!(Math.Abs(x) < 700.0))
		{
			amb = true;
			return Math.Exp(x);
		}
		ExpDD(x, out double h, out double l);
		return Round64To53(h, l, out amb);
	}

	public static double Log(double x, out bool amb)
	{
		amb = false;
		if (!(x > 1e-300) || double.IsInfinity(x))
		{
			amb = true;
			return Math.Log(x);
		}
		if (x == 1.0)
			return 0.0;
		// one Newton step from Math.Log in double-double: y = y0 + (x - e^y0) / e^y0
		double y0 = Math.Log(x);
		ExpDD(y0, out double eh, out double el);
		Add(x, 0.0, -eh, -el, out double dh, out double dl);
		double c = (dh + dl) / eh;
		TwoSum(y0, c, out double h, out double l);
		// the x87 multiplies log2(x) by its rounded ln2
		l += h * LN2_X87_REL;
		double hh = h + l;
		l -= hh - h;
		return Round64To53(hh, l, out amb);
	}
}

/// immutable seed data shared between forks
internal sealed class TfShared
{
	public long seed_value;
	public double sz;
	public double[] NT;
	public double rp_a, rp_sg;
	public double[] pitches;
	public double pitch_share;
	public double[] cX, cZ, cTX, cTZ, cKAP, cW, cBT, cE, cRD, cRK, cLN, cRO, cROS;
	public int[] cKD;
	public long c_gx0, c_gz0, c_gnx, c_gnz;
	public double[] c_seg;
	public int[] c_run_start, c_runs;
	public TfFeat[] route_feats;
	// colours (linear, float32 like Godot's Color)
	public Color grassA, grassB, meadow, alpine, dryGrass, litter, clover, dune, duneDark, dirt, dirtDark, desertDirt,
		gravel, greyDark, snow, sand, bed;
	public Color[] red_bands, grey_bands;
	public Godot.Collections.Dictionary col;
	public GodotObject course;

	public TfShared Clone() => (TfShared)MemberwiseClone();
}

[GlobalClass]
public partial class TerrainFieldCs : RefCounted
{
	public const double WATER = -2.2;
	public const double JC = 34.0;
	public const double HILL_TOP = 105.0;
	public const double HILL_LEN = 1400.0;
	public const double MTN_W = 150.0;
	public const double QR = 19.0;
	public const double CELL = 16.0;
	public const double CSTEP = 2.0;

	private const double I42 = 1.0 / 42.0;
	private const double I23 = 1.0 / 23.0;
	private const double I55 = 1.0 / 55.0;
	private const double I260 = 1.0 / 260.0;
	private const double I90 = 1.0 / 90.0;
	private const double I240 = 1.0 / 240.0;
	private const double I150 = 1.0 / 150.0;
	private const double I700 = 1.0 / 700.0;
	private const double I28 = 1.0 / 28.0;
	private const double I8 = 1.0 / 8.0;
	private const double I1_5 = 1.0 / 1.5;
	private const double I3_4 = 1.0 / 3.4;
	private const double I160 = 1.0 / 160.0;
	private const double I380 = 1.0 / 380.0;
	private const double I300 = 1.0 / 300.0;
	private const double I7 = 1.0 / 7.0;
	private const double I95 = 1.0 / 95.0;
	private const double I40 = 1.0 / 40.0;
	private const double I115 = 1.0 / 115.0;
	private const double I45 = 1.0 / 45.0;
	private const double I60 = 1.0 / 60.0;
	private const double I26 = 1.0 / 26.0;
	private const double I170 = 1.0 / 170.0;
	private const double I6 = 1.0 / 6.0;
	private const double I38 = 1.0 / 38.0;
	private const double I5 = 1.0 / 5.0;
	private const double I2_3 = 1.0 / 2.3;
	private const double I9 = 1.0 / 9.0;
	private const double I0_9 = 1.0 / 0.9;
	private const double I2 = 1.0 / 2.0;
	private const double I1_3 = 1.0 / 1.3;

	// ---------------- shared seed data (local refs for speed) ----------------
	private TfShared _sh;
	private double[] NT;
	private double rp_a, rp_sg, _sin_rp_a;
	private double[] pitches;
	private double pitch_share;
	private double[] cX, cZ, cTX, cTZ, cKAP, cW, cBT, cE, cRD, cRK, cLN, cRO, cROS;
	private int[] cKD;
	private long c_gx0, c_gz0, c_gnx, c_gnz;
	private double[] c_seg;
	private int[] c_run_start, c_runs;
	private TfFeat[] _route;

	public long seed_value;
	public double sz;

	// ---------------- per-instance state ----------------
	public double q_x = double.NaN, q_z = double.NaN, q_d = double.PositiveInfinity, q_a, q_t, q_w = double.NaN, q_k, q_bt, q_s, q_rd, q_rk, q_bench, q_mask;
	public long q_i, q_kind;
	private double[] _qp = new double[15];
	private int[] _cand = new int[64];
	private int _cand_n;
	public double fo_h, fo_m, fo_plane, fo_dig, fo_wood, fo_air;
	public bool fo_has_wood;
	private double _fo_x = double.NaN, _fo_z = double.NaN;
	public double wood;
	public bool has_wood;
	private readonly Dictionary<long, TfFeat> _jc = new Dictionary<long, TfFeat>();
	private double _pn_x = double.NaN, _pn_z = double.NaN, _pn_v;
	private double _mt_x = double.NaN, _mt_z = double.NaN, _mt_v;
	private double _zc_x = double.NaN, _zc_v;
	public double b_dry, b_rug;
	private double _bi_x = double.NaN, _bi_z = double.NaN;
	private double _g_x = double.NaN, _g_z = double.NaN, _g_v, _g_wood;
	private bool _g_has_wood;
	private double _gr_x = double.NaN, _gr_z = double.NaN, _gx, _gz;
	public Color cl_g, cl_d;
	public double cl_steep;
	public double cp_dry, cp_rug;
	public double _cp_h;
	private Godot.Collections.Dictionary _col;
	private Godot.Collections.Array _route_wrap;

	/// the GDScript TrailCourse (fences, stakes, arrays) the chunk builder reads
	public GodotObject course => _sh?.course;
	/// per-instance copy of TerrainField.col (linear colours by name)
	public Godot.Collections.Dictionary col => _col;
	/// the route features as TerrainFeatCs objects (made on first use, per instance)
	public Godot.Collections.Array route_feats
	{
		get
		{
			if (_route_wrap == null)
			{
				_route_wrap = new Godot.Collections.Array();
				foreach (var f in _route)
					_route_wrap.Add(new TerrainFeatCs(f));
			}
			return _route_wrap;
		}
	}

	// ======================================================================
	// helpers: Godot's semantics (minf/maxf/signf are the C macros, not Math.Min/Max/Sign)
	// ======================================================================
	internal static double minf(double a, double b) => a < b ? a : b;
	internal static double maxf(double a, double b) => a > b ? a : b;
	private static double signf(double v) => v == 0 ? 0.0 : (v < 0 ? -1.0 : 1.0);
	private static long floori(double v) => (long)Math.Floor(v);
	private static long posmod(long a, long b)
	{
		long v = a % b;
		if ((v < 0 && b > 0) || (v > 0 && b < 0))
			v += b;
		return v;
	}

	public static double sm(double a, double b, double x)
	{
		double t = (x - a) / (b - a);
		t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
		return t * t * (3.0 - 2.0 * t);
	}

	// Godot Color (float32): lerp / scale exactly like Color::lerp(Color, float) and Color * float
	private static Color clerp(Color a, Color b, double w)
	{
		float f = (float)w;
		return new Color(a.R + (b.R - a.R) * f, a.G + (b.G - a.G) * f, a.B + (b.B - a.B) * f, a.A + (b.A - a.A) * f);
	}

	private static Color cmul(Color c, double s)
	{
		float f = (float)s;
		return new Color(c.R * f, c.G * f, c.B * f, c.A * f);
	}

	// ======================================================================
	// setup: take over the tables of a set-up GDScript TerrainField
	// ======================================================================
	private static double[] F64(Variant v) => v.AsFloat64Array();
	private static double[] F32(Variant v)
	{
		float[] a = v.AsFloat32Array();
		var o = new double[a.Length];
		for (int i = 0; i < a.Length; i++)
			o[i] = a[i];
		return o;
	}

	public void setup_from(GodotObject f)
	{
		var sh = new TfShared();
		sh.seed_value = f.Get("seed_value").AsInt64();
		sh.sz = f.Get("sz").AsDouble();
		sh.NT = F64(f.Get("NT"));
		sh.rp_a = f.Get("rp_a").AsDouble();
		sh.rp_sg = f.Get("rp_sg").AsDouble();
		sh.pitches = F64(f.Get("pitches"));
		sh.pitch_share = f.Get("pitch_share").AsDouble();
		_course_from(sh, f);
		var col = f.Get("col").AsGodotDictionary();
		sh.col = col.Duplicate();
		Color C(string k) => col[k].AsColor();
		sh.grassA = C("grassA"); sh.grassB = C("grassB"); sh.meadow = C("meadow"); sh.alpine = C("alpine");
		sh.dryGrass = C("dryGrass"); sh.litter = C("litter"); sh.clover = C("clover"); sh.dune = C("dune");
		sh.duneDark = C("duneDark"); sh.dirt = C("dirt"); sh.dirtDark = C("dirtDark"); sh.desertDirt = C("desertDirt");
		sh.gravel = C("gravel"); sh.greyDark = C("greyDark"); sh.snow = C("snow"); sh.sand = C("sand"); sh.bed = C("bed");
		sh.red_bands = f.Get("red_bands").AsColorArray();
		sh.grey_bands = f.Get("grey_bands").AsColorArray();
		_bind(sh);
	}

	// the course tables (layout, query grid, route features) of a GDScript TerrainField
	private void _course_from(TfShared sh, GodotObject f)
	{
		sh.cX = F64(f.Get("cX"));
		sh.cZ = F64(f.Get("cZ"));
		sh.cKD = f.Get("cKD").AsInt32Array();
		sh.cTX = F32(f.Get("cTX"));
		sh.cTZ = F32(f.Get("cTZ"));
		sh.cKAP = F32(f.Get("cKAP"));
		sh.cW = F32(f.Get("cW"));
		sh.cBT = F32(f.Get("cBT"));
		sh.cE = F32(f.Get("cE"));
		sh.cRD = F32(f.Get("cRD"));
		sh.cRK = F32(f.Get("cRK"));
		sh.cLN = F32(f.Get("cLN"));
		sh.cRO = F32(f.Get("cRO"));
		sh.cROS = F32(f.Get("cROS"));
		sh.c_gx0 = f.Get("c_gx0").AsInt64();
		sh.c_gz0 = f.Get("c_gz0").AsInt64();
		sh.c_gnx = f.Get("c_gnx").AsInt64();
		sh.c_gnz = f.Get("c_gnz").AsInt64();
		sh.c_seg = F64(f.Get("c_seg"));
		sh.c_run_start = f.Get("c_run_start").AsInt32Array();
		sh.c_runs = f.Get("c_runs").AsInt32Array();
		sh.course = f.Get("course").AsGodotObject();
		var rf = f.Get("route_feats").AsGodotArray();
		sh.route_feats = new TfFeat[rf.Count];
		for (int i = 0; i < rf.Count; i++)
		{
			var j = rf[i].AsGodotObject();
			var c = make_feat(j.Get("x").AsDouble(), j.Get("z").AsDouble(), j.Get("dx").AsDouble(), j.Get("dz").AsDouble(),
				j.Get("type").AsString(), j.Get("b0").AsDouble(), j.Get("b1").AsDouble());
			c.s = j.Get("s").AsDouble();
			sh.route_feats[i] = c;
		}
	}

	/// take over a grown course (TerrainField.adopt_course) from the GDScript field: everything else is kept.
	/// Forks made before keep the old tables (they are never changed in place).
	public void rebind_course(GodotObject f)
	{
		var sh = (TfShared)_sh.Clone();
		_course_from(sh, f);
		_bind(sh);
	}

	private void _bind(TfShared sh)
	{
		_sh = sh;
		seed_value = sh.seed_value; sz = sh.sz; NT = sh.NT; rp_a = sh.rp_a; rp_sg = sh.rp_sg;
		_sin_rp_a = gd_sin(rp_a);
		pitches = sh.pitches; pitch_share = sh.pitch_share;
		cX = sh.cX; cZ = sh.cZ; cKD = sh.cKD; cTX = sh.cTX; cTZ = sh.cTZ; cKAP = sh.cKAP; cW = sh.cW; cBT = sh.cBT;
		cE = sh.cE; cRD = sh.cRD; cRK = sh.cRK; cLN = sh.cLN; cRO = sh.cRO; cROS = sh.cROS;
		c_gx0 = sh.c_gx0; c_gz0 = sh.c_gz0; c_gnx = sh.c_gnx; c_gnz = sh.c_gnz;
		c_seg = sh.c_seg; c_run_start = sh.c_run_start; c_runs = sh.c_runs;
		_route = sh.route_feats;
		_index_canyons();
		_col = sh.col.Duplicate();
		_route_wrap = null;
		_reset_caches();
	}

	/// a new instance sharing the seed data, with its own caches (one per worker thread)
	public TerrainFieldCs fork()
	{
		var f = new TerrainFieldCs();
		f._bind(_sh);
		return f;
	}

	private void _reset_caches()
	{
		_jc.Clear();
		q_x = double.NaN; q_z = double.NaN; q_d = double.PositiveInfinity;
		_qp[0] = double.NaN; _qp[1] = double.NaN; _qp[2] = double.PositiveInfinity;
		_fo_x = double.NaN; _gr_x = double.NaN; _pn_x = double.NaN; _mt_x = double.NaN; _zc_x = double.NaN; _bi_x = double.NaN; _g_x = double.NaN;
	}

	// ---------------- Perlin (three.js ImprovedNoise, z fixed at sz) ----------------
	public double noise(double x, double y)
	{
		double fx = Math.Floor(x);
		double fy = Math.Floor(y);
		long X = (long)fx & 255;
		long Y = (long)fy & 255;
		x -= fx;
		y -= fy;
		double u = x * x * x * (x * (x * 6.0 - 15.0) + 10.0);
		double v = y * y * y * (y * (y * 6.0 - 15.0) + 10.0);
		long X1 = (X + 1) & 255;
		long Y1 = (Y + 1) & 255;
		long i00 = ((X << 8) | Y) * 3;
		long i10 = ((X1 << 8) | Y) * 3;
		long i01 = ((X << 8) | Y1) * 3;
		long i11 = ((X1 << 8) | Y1) * 3;
		double x1 = x - 1.0;
		double y1 = y - 1.0;
		var nt = NT;
		double c00 = nt[i00] * x + nt[i00 + 1] * y + nt[i00 + 2];
		double c10 = nt[i10] * x1 + nt[i10 + 1] * y + nt[i10 + 2];
		double c01 = nt[i01] * x + nt[i01 + 1] * y1 + nt[i01 + 2];
		double c11 = nt[i11] * x1 + nt[i11 + 1] * y1 + nt[i11 + 2];
		double a = c00 + u * (c10 - c00);
		return a + v * (c01 + u * (c11 - c01) - a);
	}

	public double n(double x, double z, double s) => noise(x * s, z * s);

	// GDScript's sin / exp / log: the x87 emulation, and for the rare near-tie the engine's own function
	// (Expression calls the same Math::sin / exp / log as GDScript; one per instance = per thread)
	private Expression[] _libm;
	private Godot.Collections.Array _libm_args;
	public long libm_engine_calls;

	private double _engine(int fn, double x)
	{
		libm_engine_calls++;
		_libm ??= new Expression[3];
		if (_libm[fn] == null)
		{
			_libm[fn] = new Expression();
			_libm[fn].Parse(fn == 0 ? "sin(x)" : (fn == 1 ? "exp(x)" : "log(x)"), new[] { "x" });
		}
		_libm_args ??= new Godot.Collections.Array { 0.0 };   // one reused engine Array (disposed in release_libm), not one per call
		_libm_args[0] = x;
		return _libm[fn].Execute(_libm_args).AsDouble();
	}

	/// dispose the engine Expressions made for near-tie sin / exp / log now (made again if needed): the paper
	/// map's colour batches created them on the main field, and left for C#'s collector they were finalized after
	/// the engine shut down, which crashed the quit
	public void release_libm()
	{
		_libm_args?.Dispose();
		_libm_args = null;
		if (_libm == null) return;
		foreach (var e in _libm) e?.Dispose();
		_libm = null;
	}

	/// on delete, dispose the engine objects this instance made (feature wrappers, Expressions) instead of leaving
	/// them to the garbage collector, which could finalize them after the engine shut down (crashed the quit)
	public override void _Notification(int what)
	{
		if (what != NotificationPredelete) return;
		release_libm();
		if (_route_wrap != null)
		{
			foreach (var v in _route_wrap) v.AsGodotObject()?.Dispose();
			_route_wrap.Dispose();
			_route_wrap = null;
		}
	}

	/// true while the paper map samples: near ties keep the x87 result instead of asking the engine (no Expression /
	/// Array objects - made by the tens of thousands, some outlived the engine and crashed the quit). Off = exact.
	private bool _approx;

	private double gd_sin(double x)
	{
		double v = TfX87.Sin(x, out bool amb);
		return amb && !_approx ? _engine(0, x) : v;
	}

	private double gd_exp(double x)
	{
		double v = TfX87.Exp(x, out bool amb);
		return amb && !_approx ? _engine(1, x) : v;
	}

	private double gd_log(double x)
	{
		double v = TfX87.Log(x, out bool amb);
		return amb && !_approx ? _engine(2, x) : v;
	}

	/// GDScript's sin / exp / log (fn 0 / 1 / 2), for the tests
	public double x87(long fn, double x)
	{
		bool amb;
		double v = fn == 0 ? TfX87.Sin(x, out amb) : (fn == 1 ? TfX87.Exp(x, out amb) : TfX87.Log(x, out amb));
		return amb ? _engine((int)fn, x) : v;
	}

	/// the emulation alone (no engine fallback)
	public double x87_raw(long fn, double x)
	{
		return fn == 0 ? TfX87.Sin(x, out _) : (fn == 1 ? TfX87.Exp(x, out _) : TfX87.Log(x, out _));
	}

	// ======================================================================
	// the mountain
	// ======================================================================
	public double zc(double x)
	{
		if (x == _zc_x)
			return _zc_v;
		_zc_x = x;
		_zc_v = rp_sg * 40.0 * (gd_sin(x / 260.0 + rp_a) - _sin_rp_a);
		return _zc_v;
	}

	// ---------------- the mountains after the first (TerrainField.range_at) ----------------
	public const double RANGE_X0 = 2100.0, RANGE_P = 2800.0, RANGE_UP = 0.042, RANGE_DOWN = 0.075;
	private double _rg_x = double.NaN, _rg_h, _rg_m;
	public double rg_down;

	private double _range_hash(long k, long ch)
		=> (double)(((k * 73856093) ^ (ch * 19349663) ^ (seed_value * 2654435761)) & 0xffff) / 65536.0;

	public void range_at(double x)
	{
		if (x == _rg_x)
			return;
		_rg_x = x;
		_rg_h = 0.0; _rg_m = 0.0; rg_down = 0.0;
		if (x <= RANGE_X0)
			return;
		long k = floori((x - RANGE_X0) / RANGE_P);
		double u = x - RANGE_X0 - k * RANGE_P;
		double hh = 40.0 + 14.0 * _range_hash(k, 1);
		double a0 = 120.0 + 260.0 * _range_hash(k, 2);
		double lc = hh / RANGE_UP;
		double lp = 50.0 + 40.0 * _range_hash(k, 3);
		double ld = hh / RANGE_DOWN;
		double e = a0 + lc + lp + ld;
		if (u <= a0 - 140.0 || u >= e + 140.0)
			return;
		double up = sm(a0, a0 + lc, u);
		double dn = sm(a0 + lc + lp, e, u);
		_rg_h = hh * up * (1.0 - dn);
		_rg_m = sm(a0 - 140.0, a0, u) * (1.0 - sm(e, e + 140.0, u));
		rg_down = sm(a0 + lc + lp - 30.0, a0 + lc + lp + 20.0, u) * (1.0 - sm(e - 40.0, e + 20.0, u));
	}

	public double mtn(double x, double z)
	{
		if (x == _mt_x && z == _mt_z)
			return _mt_v;
		double v = 0.0;
		if (x > RANGE_X0)
		{
			range_at(x);
			if (_rg_m > 0.0)
				v = _rg_m * (1.0 - sm(MTN_W - 20, MTN_W + 90, Math.Abs(z - zc(x))));
		}
		if (x > -300.0 && x < HILL_LEN + 150)
		{
			double t = (Math.Abs(z - zc(x)) - (MTN_W - 20)) / ((MTN_W + 90) - (MTN_W - 20));
			if (t < 1.0)
			{
				t = t < 0.0 ? 0.0 : t;
				double a = 1.0 - t * t * (3.0 - 2.0 * t);
				t = (x - -300.0) / (-170.0 - -300.0);
				t = t > 1.0 ? 1.0 : t;
				a *= t * t * (3.0 - 2.0 * t);
				t = (x - HILL_LEN) / ((HILL_LEN + 150) - HILL_LEN);
				t = t < 0.0 ? 0.0 : t;
				v = a * (1.0 - t * t * (3.0 - 2.0 * t));
			}
		}
		_mt_x = x; _mt_z = z; _mt_v = v;
		return v;
	}

	public double hill(double x, double z)
	{
		if (x <= -330.0)
			return 0.0;
		double steep = 0.0;
		double t;
		var P = pitches;
		for (int k = 0; k < P.Length; k += 3)
		{
			double c = P[k];
			double l = P[k + 1];
			double a = c - l / 2;
			if (x <= a)
				continue;
			double b = c + l / 2;
			t = (x - a) / (b - a);
			t = t > 1.0 ? 1.0 : t;
			steep += P[k + 2] * (t * t * (3.0 - 2.0 * t));
		}
		double lin_ = minf(1.0, maxf(0.0, x / HILL_LEN));
		t = (x - -10.0) / (HILL_LEN - -10.0);
		t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
		double s1 = t * t * (3.0 - 2.0 * t);
		t = (x - -330.0) / (-90.0 - -330.0);
		t = t > 1.0 ? 1.0 : t;
		double along = (1.0 - steep - (1.0 - pitch_share) * (0.6 * s1 + 0.4 * lin_)) * (t * t * (3.0 - 2.0 * t));
		double top = along > 0.0 ? HILL_TOP * along : 0.0;
		if (x > RANGE_X0)
		{
			range_at(x);
			top += _rg_h;
		}
		if (top <= 0.0)
			return 0.0;
		return top * (1.0 - sm(MTN_W, MTN_W + 260, Math.Abs(z - zc(x))));
	}

	public double route_dist(double x, double z)
	{
		query(x, z);
		return q_d;
	}

	public double pathN(double x, double z)
	{
		if (x == _pn_x && z == _pn_z)
			return _pn_v;
		double v = noise((x + 211.3) * I42, (z - 97.1) * I42);
		double t = (mtn(x, z) - 0.3) / (0.75 - 0.3);
		if (t > 0.0)
		{
			t = t > 1.0 ? 1.0 : t;
			double o = 0.3 * (t * t * (3.0 - 2.0 * t));
			v = v < 0.0 ? v - o : v + o;
		}
		_pn_x = x; _pn_z = z; _pn_v = v;
		return v;
	}

	private void _grad_at(double x, double z)
	{
		if (x == _gr_x && z == _gr_z)
			return;
		_gx = pathN(x + 0.5, z) - pathN(x - 0.5, z);
		_gz = pathN(x, z + 0.5) - pathN(x, z - 0.5);
		_gr_x = x; _gr_z = z;
	}

	public double trail(double x, double z)
	{
		double p = Math.Abs(pathN(x, z));
		query(x, z);
		double main = q_d < 12.0 ? (1.0 - sm(q_w, q_w + 1.2, q_d)) : 0.0;
		double t = (p - 0.03) / (0.075 - 0.03);
		if (t >= 1.0)
			return maxf(0.0, main);
		t = t < 0.0 ? 0.0 : t;
		return maxf(1.0 - t * t * (3.0 - 2.0 * t), main);
	}

	public double across(double x, double z)
	{
		query(x, z);
		if (q_d < q_w + 2.6)
			return q_a;
		_grad_at(x, z);
		return pathN(x, z) / maxf(Math.Sqrt(_gx * _gx + _gz * _gz), 0.012);
	}

	/// where the ridden line sits across the trail (TerrainField.line_off)
	public double line_off(double x, double z)
	{
		double wob = noise((x + 91.7) * I23, (z - 13.3) * I23);
		query(x, z);
		if (q_d < q_w + 2.6)
			return cLN[q_i] + (cLN[q_i + 1] - cLN[q_i]) * q_t + wob * 0.18;
		return wob * 1.5;
	}

	public double line(double x, double z)
	{
		double off = line_off(x, z);
		double a = across(x, z);
		// one ridden line everywhere: only bikes use these trails, so a road has no pair of wheel ruts
		return 1.0 - sm(0.25, 0.7, Math.Abs(a - off));
	}

	// ---------------- berms ----------------
	private double berm_shape(double o, double tn)
	{
		if (o < -1.6)
			return 0.0;
		double edge = 2.7;
		if (o < 0.0)
			return tn * (o + 1.6) * (o + 1.6) / 3.2;
		double om = edge - gd_log(1.0 + gd_exp(2.0 * (edge - o))) / 2.0;
		return tn * (om + 0.8) * (1.0 - sm(edge - 0.5, edge + 6.5, o));
	}

	public double berm(double x, double z)
	{
		double h = 0.0;
		query(x, z);
		// q_bt is signed (> 0 left berm, < 0 right) and already smooth along the course
		double bt = Math.Abs(q_bt) - 0.004;
		if (q_d < 12.0 && bt > 0.0)
			h = maxf(h, q_bt > 0.0 ? berm_shape(-q_a, bt) : berm_shape(q_a, bt));
		double p = pathN(x, z);
		if (Math.Abs(p) < 0.2)
		{
			_grad_at(x, z);
			double gx0 = _gx;
			double gz0 = _gz;
			double g0 = maxf(Math.Sqrt(gx0 * gx0 + gz0 * gz0), 1e-6);
			double s = p / g0;
			double cx = x - s * gx0 / g0;
			double cz = z - s * gz0 / g0;
			double e = 2.0;
			double pc = pathN(cx, cz);
			double pe = pathN(cx + e, cz);
			double pw = pathN(cx - e, cz);
			double pn = pathN(cx, cz + e);
			double ps = pathN(cx, cz - e);
			double px = (pe - pw) / (2 * e);
			double pz = (pn - ps) / (2 * e);
			double pxx = (pe - 2 * pc + pw) / (e * e);
			double pzz = (pn - 2 * pc + ps) / (e * e);
			double pxz = (pathN(cx + e, cz + e) - pathN(cx + e, cz - e) - pathN(cx - e, cz + e) + pathN(cx - e, cz - e)) / (4 * e * e);
			double g = Math.Sqrt(px * px + pz * pz);
			if (g == 0.0)
				g = 1e-6;
			double kap = (pxx * pz * pz - 2 * pxz * px * pz + pzz * px * px) / (g * g * g);
			double ak = Math.Abs(kap);
			double ok = sm(0.012, 0.02, g) * sm(12, 22, route_dist(cx, cz)) * (1.0 - sm(0.12, 0.2, Math.Abs(p)));
			double tn = minf(0.55, 17 * ak) * sm(0.012, 0.03, ak) * (1.0 - sm(0.07, 0.1, ak)) * ok;
			if (tn > 0.0 && Math.Abs(s) < 10.0)
			{
				double bon = sm(0.2, 0.36, noise((cx + 777) * I55, (cz - 333) * I55));
				h = maxf(h, berm_shape(s * signf(kap), tn) * bon);
			}
		}
		return h;
	}

	// ---------------- the land ----------------
	public double landform(double x, double z)
	{
		double calm = 1.0 - 0.85 * mtn(x, z);
		double relief = 1.0 + 1.3 * sm(0.0, 0.35, noise((x + 5000) * I260, (z - 800) * I260));
		double big = sm(-0.15, 0.3, noise((x + 2600) * I700, (z - 3100) * I700));
		double rdg = sm(0.05, 0.35, noise((x - 4100) * I700, (z + 1500) * I700));
		double rr = 1.0 - Math.Abs(noise((x + 820) * I150, (z - 2300) * I150));
		double h = (noise(x * I90, z * I90) * 10 * relief + noise((x + 31.7) * I28, (z - 17.2) * I28) * 3.2 * (0.6 + 0.4 * relief)
			+ noise((x - 1700) * I240, (z + 900) * I240) * 16 * big + (rr * rr - 0.45) * 14 * rdg) * calm + hill(x, z);
		double wm = wild_mask(x, z);
		if (wm == 0.0)
			return h;
		return h + wild(x, z) * wm;
	}

	public double @base(double x, double z)
	{
		double t = trail(x, z);
		double h = landform(x, z);
		double p = pathN(x, z);
		double ap = Math.Abs(p);
		double dist = 99.0;
		if (ap < 0.25)
		{
			_grad_at(x, z);
			double gx = _gx;
			double gz = _gz;
			double g = maxf(Math.Sqrt(gx * gx + gz * gz), 0.012);
			dist = ap / g;
			double bench = (1.0 - sm(3, 9.5, dist)) * sm(6, 16, route_dist(x, z)) * (1.0 - sm(0.15, 0.25, ap));
			if (bench > 0.0)
			{
				double sd = p / g;
				double cx = x - sd * gx / g;
				double cz = z - sd * gz / g;
				double d = (landform(cx, cz) - h) * bench;
				h += d / (1.0 + Math.Abs(d) / 1.1);
			}
		}
		query(x, z);
		if (q_mask > 0.0)
			h += (q_bench - h) * q_mask;
		h += noise((x - 5.3) * I8, (z + 9.1) * I8) * 0.5 * maxf(sm(2.5, 7, dist), sm(0.15, 0.25, ap)) * (1.0 - t);
		h -= 0.15 * t;
		if (t > 0.0)
		{
			double ln = line(x, z);
			h += t * (noise((x + 7.1) * I1_5, (z + 3.3) * I1_5) * 0.028 + noise((x - 2.9) * I3_4, (z + 8.4) * I3_4) * 0.04 * (0.6 + 0.6 * ln) - 0.035 * ln);
		}
		double dry = WATER + 0.5;
		if (h < dry)
		{
			query(x, z);
			double bank = maxf(1.0 - sm(0.05, 0.14, ap), q_d < 20.0 ? (1.0 - sm(q_w, q_w + 4.5, q_d)) : 0.0);
			h += (dry - h) * bank;
		}
		return h;
	}

	// ---------------- biomes ----------------
	public void biome(double x, double z)
	{
		if (x == _bi_x && z == _bi_z)
			return;
		double wx = x + noise(x * I160, (z + 500) * I160) * 60;
		double wz = z + noise((x - 500) * I160, z * I160) * 60;
		b_dry = sm(-0.12, 0.16, noise((wx + 3000) * I380, (wz - 1200) * I380));
		b_rug = sm(-0.08, 0.2, noise((wx - 700) * I300, (wz + 2200) * I300));
		_bi_x = x; _bi_z = z;
	}

	public string biome_name(double x, double z)
	{
		biome(x, z);
		if (b_dry > 0.6)
			return b_rug > 0.5 ? "Red Canyons" : "Dune Sea";
		if (b_dry > 0.35)
			return "Dry Plains";
		return b_rug > 0.5 ? "Rocky Mountains" : "Green Hills";
	}

	public double wild_mask(double x, double z) => (1.0 - mtn(x, z)) * sm(45, 90, Math.Sqrt(x * x + z * z));

	public double trail_metres(double x, double z) => Math.Abs(pathN(x, z)) / 0.022;

	private static double _tier(double f, double t, double k) => k * (0.35 * sm(t - 0.14, t, f) + 0.65 * sm(t, t + 0.06, f));

	public double wild(double x, double z)
	{
		biome(x, z);
		double dry = b_dry;
		double rug = b_rug;
		double h = 0.0;
		double tm = trail_metres(x, z);
		if (rug > 0.0)
		{
			double ex = x + noise(x * I23, (z - 77) * I23) * 7 + noise(x * I7, (z + 31) * I7) * 1.5;
			double ez = z + noise((x + 77) * I23, z * I23) * 7 + noise((x - 31) * I7, z * I7) * 1.5;
			double r = sm(0.15, 1, 1.0 - Math.Abs(noise((x + 1300) * I95, (z - 40) * I95)));
			double peaks = r * 13 + noise((x - 90) * I40, (z + 400) * I40) * 3;
			double f = noise((ex + 900) * I115, (ez - 400) * I115);
			double vary = sm(-0.25, 0.3, noise((x + 55) * I45, (z - 210) * I45));
			double rm = sm(6, 30, tm);
			double kc = vary * rm;
			double cliffs = _tier(f, 0.0, 5.5 * kc) + _tier(f, 0.22, 4.5 * kc);
			double km = (0.4 + 0.6 * vary) * rm;
			double mesas = _tier(f, 0.05, 6.5 * km) + _tier(f, 0.27, 4 * km);
			h += rug * ((1.0 - dry) * (peaks + cliffs) + dry * mesas);
		}
		if (dry > 0.0)
		{
			double dx = x * 0.8 + z * 0.6;
			double dz = -x * 0.6 + z * 0.8;
			double d = 1.0 - Math.Abs(noise((dx / 1.0 + noise(x * I60, z * I60) * 20) * I26, (dz * 0.35) * I26));
			h += dry * (1.0 - rug * 0.7) * (d * d * 3.6 * (0.45 + 0.55 * sm(3, 25, tm)) + noise((x + 40) * I60, z * I60) * 3);
		}
		return h;
	}

	// ======================================================================
	// designed features
	// ======================================================================
	/// TrailFeatures.AIR: where riders are in the air over each feature, [from, to, ...] along it (m)
	private static readonly System.Collections.Generic.Dictionary<string, double[]> AIR = new()
	{
		["table"] = new[] { 15.95, 33.09 }, ["double"] = new[] { 8.0, 17.6 }, ["kicker"] = new[] { 11.45, 25.94 },
		["woodKicker"] = new[] { 3.8, 9.0 }, ["tableLine"] = new[] { 15.95, 33.09, 53.65, 68.14 }, ["flow"] = new[] { 11.45, 25.94 },
		["doubleLine"] = new[] { 8.0, 17.6, 51.25, 65.74 },
	};

	private static readonly System.Collections.Generic.Dictionary<string, double[]> AIR_S = new()
	{
		["table"] = new[] { 5.5, 12.0 }, ["double"] = new[] { 5.0, 11.0 }, ["kicker"] = new[] { 3.6, 9.0 },
		["tableLine"] = new[] { 5.5, 12.0, 27.6, 33.0 }, ["flow"] = new[] { 3.6, 9.0 }, ["doubleLine"] = new[] { 5.0, 11.0, 29.6, 35.0 },
	};

	private static TfFeat make_feat(double x, double z, double dx, double dz, string type, double b0, double b1, bool oldSize = false)
	{
		bool old = oldSize && TfSet.SMALL.ContainsKey(type);
		var prof = old ? TfSet.SMALL[type] : TfSet.PROFILES[type];
		var f = new TfFeat { x = x, z = z, dx = dx, dz = dz, len = prof.length, prof = prof, b0 = b0, b1 = b1, type = type };
		TfSet.WOOD.TryGetValue(type, out f.wood);
		TfSet.DIG.TryGetValue(type, out f.dig);
		f.canyon = type == "rope";
		if ((old ? AIR_S : AIR).TryGetValue(type, out var airv)) f.air = airv;
		f.ramp = type == "rope" ? ROPE_RAMP : 6.0;
		if (type == "rhythm" || type == "flow")
			f.half = 2.3;
		else if (type == "bridge")
			f.half = 2.4;
		else if (type == "gorge")
			f.half = 3.2;
		else if (type == "rope")
			f.half = 3.0;
		else if (type == "skinny")
			f.half = 1.4;
		else
			f.half = 1.9;
		return f;
	}

	private TfFeat _jump_at(long cx, long cz)
	{
		long key = cx * 1048576 + cz;
		if (_jc.TryGetValue(key, out var cached))
			return cached;
		if (_jc.Count > 4096)
			_jc.Clear();
		var rnd = new TfRng(TfRng.i32(cx * 92837111) ^ TfRng.i32(cz * 689287499) ^ TfRng.i32(seed_value * 2654435761));
		TfFeat best = null;
		if (rnd.next() < 0.85)
		{
			double best_v = 0.02;
			bool found = false;
			double bx = 0.0;
			double bz = 0.0;
			for (int i = 0; i < 24; i++)
			{
				double x = (cx + 0.2 + rnd.next() * 0.6) * JC;
				double z = (cz + 0.2 + rnd.next() * 0.6) * JC;
				double pv = Math.Abs(pathN(x, z));
				if (pv < best_v && Math.Sqrt(x * x + z * z) > 20 && route_dist(x, z) > 14)
				{
					best_v = pv; bx = x; bz = z; found = true;
				}
			}
			if (found)
			{
				var types = TfSet.FEATURE_TYPES;
				string type = types[(long)(rnd.next() * types.Length)];
				double len = (TfSet.SMALL.ContainsKey(type) ? TfSet.SMALL[type] : TfSet.PROFILES[type]).length;   // (old-size jumps out here)
				double gx = pathN(bx + 0.5, bz) - pathN(bx - 0.5, bz);
				double gz = pathN(bx, bz + 0.5) - pathN(bx, bz - 0.5);
				double l = Math.Sqrt(gx * gx + gz * gz);
				if (l == 0.0)
					l = 1.0;
				double dx = -gz / l;
				double dz = gx / l;
				double b0 = @base(bx - dx * len / 2, bz - dz * len / 2);
				double b1 = @base(bx + dx * len / 2, bz + dz * len / 2);
				if (b1 > b0)
				{
					dx = -dx; dz = -dz;
					double tmp = b0;
					b0 = b1; b1 = tmp;
				}
				double sx = bx - dx * len / 2;
				double szz = bz - dz * len / 2;
				bool ok = Math.Abs(b1 - b0) / len < 0.14;
				long k = 0;
				while (ok && k <= 10)
				{
					double f = k / 10.0;
					double px = sx + dx * len * f;
					double pz = szz + dz * len * f;
					double b = @base(px, pz);
					double pl = b0 + (b1 - b0) * f;
					if (pl < WATER + 0.6 || Math.Abs(b - pl) > 1.8 || route_dist(px, pz) < 12)
						ok = false;
					k++;
				}
				if (ok && Math.Sqrt(sx * sx + szz * szz) > 34)
					best = make_feat(sx, szz, dx, dz, type, b0, b1, true);
			}
		}
		_jc[key] = best;
		return best;
	}

	/// the jump feature of cell (cx, cz) as a TerrainFeatCs, or null
	public TerrainFeatCs jump_at(long cx, long cz)
	{
		var f = _jump_at(cx, cz);
		if (f == null)
			return null;
		return new TerrainFeatCs(f);
	}

	// ---------------- rope bridge canyons (TerrainField.canyon_rims: same arithmetic, same order) ----------------
	const double CANYON_W = 42.0, CANYON_D = 16.0, CANYON_RIM = 4.2, CANYON_CELL = 64.0, ROPE_RAMP = 22.0;
	private System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<TfFeat>> _canyons = new();

	private void _index_canyons()
	{
		_canyons = new();
		foreach (var j in _route)
		{
			if (!j.canyon)
				continue;
			double mx = j.x + j.dx * j.len * 0.5, mz = j.z + j.dz * j.len * 0.5;
			double r = j.len * 0.5 + CANYON_W + 8.0;
			for (long cx = floori((mx - r) / CANYON_CELL); cx <= floori((mx + r) / CANYON_CELL); cx++)
				for (long cz = floori((mz - r) / CANYON_CELL); cz <= floori((mz + r) / CANYON_CELL); cz++)
				{
					long key = cx * 1048576 + cz;
					if (!_canyons.TryGetValue(key, out var l))
						_canyons[key] = l = new();
					l.Add(j);
				}
		}
	}

	private double _canyon_n(long k, long ch, double t)
	{
		long i = floori(t);
		double f = t - i;
		double h0 = (double)(((k * 73856093) ^ (ch * 19349663) ^ (i * 83492791) ^ (seed_value * 2654435761)) & 0xffff) / 32768.0 - 1.0;
		double h1 = (double)(((k * 73856093) ^ (ch * 19349663) ^ ((i + 1) * 83492791) ^ (seed_value * 2654435761)) & 0xffff) / 32768.0 - 1.0;
		return h0 + (h1 - h0) * (f * f * (3.0 - 2.0 * f));
	}

	private double _canyon_dig(double s, double len, double u, double ws)
	{
		double aw = Math.Abs(ws);
		if (aw >= CANYON_W)
			return 0.0;
		long k = (long)(s * 8.0);
		long sd = ws < 0.0 ? 0 : 3;
		double amp = sm(4.0, 22.0, aw);
		double cen = len * 0.5 + amp * 6.0 * _canyon_n(k, sd, aw / 16.0);
		double hw = (len * 0.5 - CANYON_RIM) * (1.0 - 0.6 * sm(8.0, CANYON_W, aw));
		double a = cen - hw + amp * 3.0 * _canyon_n(k, sd + 1, aw / 7.0);
		double b = cen + hw - amp * 3.0 * _canyon_n(k, sd + 2, aw / 7.0);
		double ww = 1.8 + amp * 1.6;
		double dep = CANYON_D * (1.0 - sm(CANYON_W - 18.0, CANYON_W, aw)) * (1.0 + 0.2 * amp * _canyon_n(k, 6, aw / 11.0));
		double v = Math.Min(sm(a, a + ww, u), 1.0 - sm(b - ww, b, u));
		return v > 0.0 ? -dep * v : 0.0;
	}

	private void _feat_at(TfFeat j, double x, double z)
	{
		double rx = x - j.x;
		double rz = z - j.z;
		double u = rx * j.dx + rz * j.dz;
		if (u < -j.ramp || u > j.len + j.ramp)
			return;
		double w = Math.Abs(-rx * j.dz + rz * j.dx);
		if (w > j.half + 2.5)
			return;
		double acr = 1.0 - sm(j.half, j.half + 1.2, w);
		double ph = j.prof.ev(u) * acr;
		if (ph > fo_h)
			fo_h = ph;
		for (int k = 0; k < j.air.Length; k += 2)
		{
			double av = sm(j.air[k], j.air[k] + 0.35, u) * (1.0 - sm(j.air[k + 1] - 0.9, j.air[k + 1] + 0.9, u)) * acr;
			if (av > fo_air)
				fo_air = av;
		}
		if (j.dig != null)
		{
			double dh = j.dig.ev(u) * acr;
			if (dh < fo_dig)
				fo_dig = dh;
		}
		double cu = u / j.len;
		cu = cu < 0.0 ? 0.0 : (cu > 1.0 ? 1.0 : cu);
		double pl = j.b0 + (j.b1 - j.b0) * cu;
		double mk = (1.0 - sm(j.half + 0.6, j.half + 2.5, w)) * sm(-j.ramp, -1, u) * (1.0 - sm(j.len + 1, j.len + j.ramp, u));
		if (mk > fo_m)
		{
			fo_m = mk;
			fo_plane = pl;
		}
		var wd = j.wood;
		if (wd != null && u >= wd.u0 && u <= wd.u1)
		{
			// grace past the plank edge, then a soft bevel on the low ramp parts (see trail_features.gd)
			double wt = wd.top(u);
			double over = w - wd.half - TfSet.WOOD_EDGE;
			if (over > 0.0 && (wt >= TfSet.WOOD_BEVEL_MAX || over * TfSet.WOOD_BEVEL >= wt))
				return;
			double top = pl + wt - (over > 0.0 ? over : 0.0) * TfSet.WOOD_BEVEL;
			if (!fo_has_wood || top > fo_wood)
			{
				fo_wood = top;
				fo_has_wood = true;
			}
		}
	}

	/// fills fo_h, fo_m, fo_plane, fo_dig, fo_wood/fo_has_wood
	public void jump_eval(double x, double z)
	{
		if (x == _fo_x && z == _fo_z)
			return;
		long cx = floori(x / JC);
		long cz = floori(z / JC);
		fo_h = 0.0; fo_m = 0.0; fo_plane = 0.0; fo_dig = 0.0; fo_wood = 0.0; fo_has_wood = false; fo_air = 0.0;
		for (long dz = -1; dz < 2; dz++)
		{
			for (long dx = -1; dx < 2; dx++)
			{
				long key = (cx + dx) * 1048576 + cz + dz;
				if (!_jc.TryGetValue(key, out var j))
					j = _jump_at(cx + dx, cz + dz);
				if (j == null)
					continue;
				double rx = x - j.x;
				double rz = z - j.z;
				double u = rx * j.dx + rz * j.dz;
				if (u < -j.ramp || u > j.len + j.ramp)
					continue;
				_feat_at(j, x, z);
			}
		}
		query(x, z);
		if (q_d < 12.0)
		{
			double s = q_s;
			// _route is in course order and doesn't overlap: binary search the first one that ends past s
			int lo = 0, hi = _route.Length;
			while (lo < hi)
			{
				int mid = (lo + hi) >> 1;
				var fm = _route[mid];
				if (fm.s + fm.len + fm.ramp + 4.0 > s)
					hi = mid;
				else
					lo = mid + 1;
			}
			for (int k = lo; k < _route.Length; k++)
			{
				var f = _route[k];
				if (f.s - f.ramp - 4.0 >= s)
					break;
				if (s > f.s - f.ramp - 4.0 && s < f.s + f.len + f.ramp + 4.0)
					_feat_at(f, x, z);
			}
		}
		// rope canyons: looked up by place (TerrainField._canyons)
		if (_canyons.Count > 0 && _canyons.TryGetValue(floori(x / CANYON_CELL) * 1048576 + floori(z / CANYON_CELL), out var cl))
		{
			foreach (var j in cl)
			{
				double u = (x - j.x) * j.dx + (z - j.z) * j.dz;
				if (u > -6.0 && u < j.len + 6.0)
				{
					double cd = _canyon_dig(j.s, j.len, u, -(x - j.x) * j.dz + (z - j.z) * j.dx);
					if (cd < fo_dig)
						fo_dig = cd;
				}
			}
		}
		_fo_x = x; _fo_z = z;
	}

	/// [feature height, mask, flattened ground height, dug depth, wood deck top or null]
	public Godot.Collections.Array jump(double x, double z)
	{
		jump_eval(x, z);
		return new Godot.Collections.Array { fo_h, fo_m, fo_plane, fo_dig, fo_has_wood ? fo_wood : new Variant() };
	}

	public double jump_mask(double x, double z)
	{
		jump_eval(x, z);
		return fo_m;
	}

	// ======================================================================
	// ground / deck
	// ======================================================================
	public double ground(double x, double z)
	{
		if (x == _g_x && z == _g_z)
		{
			wood = _g_wood; has_wood = _g_has_wood;
			return _g_v;
		}
		double h = @base(x, z);
		jump_eval(x, z);
		double jm = fo_m;
		if (jm > 0.0)
			h += (fo_plane - h) * jm;
		h += fo_h + fo_dig;
		double w = fo_wood;
		bool hw = fo_has_wood;
		if (jm < 1.0)
			h += berm(x, z) * (1.0 - jm);
		double f = sm(5, 28, Math.Sqrt(x * x + z * z));
		if (f < 1.0)
			h = h * f + (1.0 - f) * (0.8 + hill(x, z));
		double flo = WATER + 0.75;
		if (h < flo)
		{
			double dry_up = 1.0 - sm(-0.05, 0.2, noise((x - 911.3) * I170, (z + 613.7) * I170));
			if (dry_up > 0.0)
				h += (flo - h) * dry_up * 0.92;
		}
		double bed = WATER - 0.35;
		if (h < bed)
			h = bed + (h - bed) * 0.08;
		wood = w; has_wood = hw;
		_g_x = x; _g_z = z; _g_v = h; _g_wood = w; _g_has_wood = hw;
		return h;
	}

	/// ground or a wooden deck where there is one (no rock / log domes)
	public double deck(double x, double z)
	{
		double g = ground(x, z);
		return has_wood && wood > g ? wood : g;
	}

	// ---------------- rock / log / stump domes of the loaded chunks (Terrain._rock_grid) ----------------
	private const double ROCK_CELL = 2.0;
	private sealed class Dome
	{
		public double x, z, r, b, top, sink;   // sink: how far the stone's middle lies under the ground (0 = a half dome)
		public long chunk;
	}
	private readonly Dictionary<long, List<Dome>> _domes = new Dictionary<long, List<Dome>>();
	private readonly Dictionary<long, List<long>> _dome_keys = new Dictionary<long, List<long>>();

	private static long _dome_key(long gx, long gz) => gx * 4294967296L + gz;

	/// a chunk's domes: data = (x, z, r, base, top, sink) per rock / log / stump, registered in every 2 m cell their
	/// bounding square touches (same cells as Terrain._finalize)
	public void domes_add(long chunk, double[] data)
	{
		domes_remove(chunk);
		var keys = new List<long>();
		for (int i = 0; i + 5 < data.Length; i += 6)
		{
			var d = new Dome { x = data[i], z = data[i + 1], r = data[i + 2], b = data[i + 3], top = data[i + 4], sink = data[i + 5], chunk = chunk };
			for (long gx = floori((d.x - d.r) / ROCK_CELL); gx < floori((d.x + d.r) / ROCK_CELL) + 1; gx++)
			{
				for (long gz = floori((d.z - d.r) / ROCK_CELL); gz < floori((d.z + d.r) / ROCK_CELL) + 1; gz++)
				{
					long key = _dome_key(gx, gz);
					if (!_domes.TryGetValue(key, out var l))
						_domes[key] = l = new List<Dome>();
					l.Add(d);
					keys.Add(key);
				}
			}
		}
		_dome_keys[chunk] = keys;
	}

	public void domes_remove(long chunk)
	{
		if (!_dome_keys.TryGetValue(chunk, out var keys))
			return;
		_dome_keys.Remove(chunk);
		foreach (long key in keys)
		{
			if (!_domes.TryGetValue(key, out var l))
				continue;
			l.RemoveAll(d => d.chunk == chunk);
			if (l.Count == 0)
				_domes.Remove(key);
		}
	}

	// ---- the drawn ground mesh of the loaded chunks (Terrain.mesh_height), for the drawn tyres' fit ----
	private const double CHUNK = 48.0;   // Terrain.SIZE
	private readonly Dictionary<long, (int n, float[] g)> _mesh = new Dictionary<long, (int, float[])>();
	private static long _mesh_key(long kx, long kz) => kx * 4294967296L + kz;

	/// a chunk's full-detail height grid (Terrain._finalize: rec N / G); removed by mesh_remove (Terrain._unload)
	public void mesh_add(int kx, int kz, int n, float[] g) => _mesh[_mesh_key(kx, kz)] = (n, g);
	public void mesh_remove(int kx, int kz) => _mesh.Remove(_mesh_key(kx, kz));

	/// Terrain.mesh_height(): the chunk mesh's own triangles; -inf where no chunk is loaded
	public double mesh_height(double x, double z)
	{
		long kx = (long)Math.Floor(x / CHUNK + 0.5), kz = (long)Math.Floor(z / CHUNK + 0.5);
		if (!_mesh.TryGetValue(_mesh_key(kx, kz), out var c))
			return double.NegativeInfinity;
		int N = c.n;
		double d = CHUNK / N;
		int W = N + 3;
		float[] G = c.g;
		double gx = (x - (kx * CHUNK - CHUNK / 2)) / d;
		double gz = (z - (kz * CHUNK - CHUNK / 2)) / d;
		int ix = Math.Clamp((int)Math.Floor(gx), 0, N - 1);
		int iz = Math.Clamp((int)Math.Floor(gz), 0, N - 1);
		double tx = gx - ix, tz = gz - iz;
		int b = (iz + 1) * W + ix + 1;
		double h00 = G[b], h10 = G[b + 1], h01 = G[b + W], h11 = G[b + W + 1];
		if (tx + tz <= 1.0)
			return h00 + (h10 - h00) * tx + (h01 - h00) * tz;
		return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz);
	}

	private static readonly double[] ACROSS = { -0.8, 0.0, 0.8 };   // BikeRig.TYRE_ACROSS

	/// BikeRig.tyre_depth's sample loop in one call: how deep the tyre (centre c, axle ax, d0 = down in the wheel's
	/// plane, side = ax x d0, radius R, casing half width hw) sits inside max(height, mesh_height). n points round the
	/// lower half (full = all the way round), three across the casing each. Same points / order as the GDScript loop.
	public double tyre_worst(Vector3 c, Vector3 ax, Vector3 d0, Vector3 side, double R, double hw, int n, bool full)
	{
		double worst = double.NegativeInfinity;
		for (int i = 0; i < n; i++)
		{
			double a = full ? Math.Tau * i / n : -1.4 + 2.8 * i / (n - 1);
			double ca = Math.Cos(a), sa = Math.Sin(a);
			double dx = d0.X * ca + side.X * sa, dy = d0.Y * ca + side.Y * sa, dz = d0.Z * ca + side.Z * sa;
			foreach (double wo in ACROSS)
			{
				double off = wo * hw;
				double r = R - hw + Math.Sqrt(hw * hw - off * off);
				double px = c.X + dx * r + ax.X * off, py = c.Y + dy * r + ax.Y * off, pz = c.Z + dz * r + ax.Z * off;
				double h = Math.Max(height(px, pz), mesh_height(px, pz));
				if (h - py > worst) worst = h - py;
			}
		}
		return worst;
	}

	/// Terrain.height(): ground, a wooden deck, and a dome over every rock / log / stump of the loaded chunks
	public double height(double x, double z)
	{
		double g = deck(x, z);
		if (_domes.Count == 0 || !_domes.TryGetValue(_dome_key(floori(x / ROCK_CELL), floori(z / ROCK_CELL)), out var list))
			return g;
		foreach (var c in list)
		{
			double dx = x - c.x;
			double dz = z - c.z;
			double r = c.r;
			double q = (dx * dx + dz * dz) / (r * r);
			if (q < 1.0)
			{
				// the visible cap of a stone whose middle is `sink` under the ground: it meets the ground at an angle
				// (~50 deg for a rock) instead of the half dome's vertical wall (see Terrain.dome_h)
				double a = c.top - c.b + c.sink;
				double k = a > 1e-9 ? c.sink / a : 0.0;
				double h = c.b - c.sink + a * Math.Sqrt(1.0 - q * (1.0 - k * k));
				if (h > g)
					g = h;
			}
		}
		return g;
	}

	/// Terrain.surface() after its height: 0 grass, 1 trail, 2 water, 3 sand
	public long surface_at(double x, double z, double h)
	{
		if (h < WATER - 0.05)
			return 2;
		if (trail(x, z) > 0.5)
			return 1;
		if (h < WATER + 0.45)
			return 3;
		biome(x, z);
		if (b_dry > 0.7)
			return 3;
		return 0;
	}

	// ======================================================================
	// colour (terrain.js colorLayers, split like the GDScript field)
	// ======================================================================
	/// part 1 (no normal needed): land colour up to the dunes -> cl_g, trail dirt -> cl_d; returns t
	public double color_pre(double x, double z)
	{
		var C = _sh;
		double v = noise((x + 50) * I6, (z + 50) * I6) * 0.5 + 0.5;
		biome(x, z);
		double dry = b_dry;
		double rug = b_rug;
		cp_dry = dry;
		cp_rug = rug;
		Color g = clerp(C.grassA, C.grassB, v);
		double hh = _cp_h;
		g = clerp(g, C.meadow, sm(3.5, 8, hh) * 0.8 * (1.0 - rug));
		g = clerp(g, C.alpine, rug * (1.0 - dry) * 0.6);
		g = clerp(g, C.dryGrass, sm(0.15, 0.55, dry));
		double wd = sm(0.0, 0.35, noise((x + 400) * I38, z * I38)) * (1.0 - dry);
		g = clerp(g, C.litter, wd * 0.38 * (1.0 - rug * 0.5));
		g = clerp(g, C.clover, sm(0.25, 0.5, noise((x - 71) * I5, (z + 23) * I5)) * 0.35 * (1.0 - dry) * (1.0 - wd));
		g = cmul(g, 1.0 + noise((x + 17) * I2_3, (z - 29) * I2_3) * 0.08);
		Color dune = clerp(C.dune, C.duneDark, v);
		g = clerp(g, dune, sm(0.5, 0.85, dry));
		double tr = trail(x, z);
		double t = maxf(tr, jump_mask(x, z));
		Color d = clerp(clerp(C.dirt, C.dirtDark, sm(-0.4, 0.4, noise(x * I7, z * I7)) * 0.7), C.desertDirt, dry * 0.6);
		if (t > 0.0)
		{
			double ln = line(x, z) * tr;
			double grit = noise((x + 13.7) * I0_9, (z - 4.1) * I0_9);
			d = cmul(d, (1.0 - 0.2 * ln) * (1.0 + (1.0 - ln) * (0.07 + grit * 0.09)));
		}
		query(x, z);
		if (q_d < q_w + 3.0)
		{
			if (q_rd > 0.0)
			{
				Color gv = clerp(C.gravel, C.desertDirt, dry * 0.4);
				d = clerp(d, gv, q_rd * 0.6 * (0.85 + 0.15 * noise(x * 3 * I2, z * 3 * I2)));
			}
			if (q_rk > 0.0)
				d = clerp(d, C.greyDark, q_rk * 0.45 * (0.6 + 0.4 * sm(-0.3, 0.3, noise((x - 9) * I1_3, (z + 4) * I1_3))));
		}
		cl_g = g;
		cl_d = d;
		return t;
	}

	/// part 2: snow, rock faces, beach sand, lake bed (needs h and the normal's y)
	public void color_post(double x, double z, double h, double ny, double dry, double rug)
	{
		var C = _sh;
		Color g = cl_g;
		if (rug > 0.0 && dry < 1.0)
			g = clerp(g, C.snow, sm(11, 19, h - hill(x, z) + noise(x * I9, z * I9) * 3) * rug * (1.0 - dry) * sm(0.75, 0.9, ny));
		double steep = sm(0.86, 0.6, ny);
		if (steep > 0.0)
		{
			double bh = h * 0.3 + noise(x * I40, z * I40) * 0.5;
			long bi = floori(bh);
			double bf = bh - bi;
			double k = sm(0.75, 1, bf);
			Color gb = clerp(C.grey_bands[posmod(bi, 5)], C.grey_bands[posmod(bi + 1, 5)], k);
			Color rb = clerp(C.red_bands[posmod(bi, 6)], C.red_bands[posmod(bi + 1, 6)], k);
			g = clerp(g, clerp(gb, rb, sm(0.35, 0.65, dry)), steep);
		}
		cl_steep = steep;
		if (h < WATER + 0.7)
			g = clerp(g, C.sand, sm(WATER + 0.7, WATER + 0.2, h));
		if (h < WATER)
		{
			g = clerp(g, C.bed, 0.6);
			cl_d = clerp(cl_d, C.bed, 0.6);
		}
		cl_g = g;
	}

	/// terrain.js colorLayers: cl_g = land, cl_d = trail dirt, cl_steep = rock-face weight; returns the dirt weight
	public double color_layers(double x, double z, double h, double ny)
	{
		_cp_h = h;
		double t = color_pre(x, z);
		color_post(x, z, h, ny, cp_dry, cp_rug);
		return t;
	}

	/// the two layers flattened (linear colour, like JS color())
	public Color color(double x, double z, double h, double ny)
	{
		double t = color_layers(x, z, h, ny);
		Color c = clerp(cl_g, cl_d, t);
		c.A = 1.0f;
		return c;
	}

	// ======================================================================
	// chunk builder: the ground + colour stages of TerrainChunkBuilder._build() in one call
	// (same loops, same order, same float32 roundings as the GDScript)
	// ======================================================================
	/// the paper map (ui/paper_map.gd): ground heights for `rows` rows of nx samples every `step` m, the first at
	/// (ox, oz + row0 * step). Batched: per-point calls from GDScript left C# objects behind (crashed the quit).
	public float[] map_heights(double ox, double oz, double step, long nx, long row0, long rows)
	{
		var o = new float[nx * rows];
		_approx = true;
		try
		{
			for (long r = 0; r < rows; r++)
			{
				double z = oz + (row0 + r) * step;
				for (long i = 0; i < nx; i++)
					o[r * nx + i] = (float)ground(ox + i * step, z);
			}
		}
		finally { _approx = false; }
		return o;
	}

	/// far_hills.gd (worker): the backdrop's n x n ground grid in one call (approximate near-ties, like the map)
	public float[] far_ground(double ox, double oz, double step, long n) => map_heights(ox, oz, step, n, 0, n);

	/// far_hills.gd: colours for that grid, h / slope per cell as far_hills computed them
	public Color[] far_colors(double ox, double oz, double step, long n, float[] h, float[] slope)
	{
		var o = new Color[n * n];
		_approx = true;
		try
		{
			for (long iz = 0; iz < n; iz++)
				for (long ix = 0; ix < n; ix++)
				{
					long i = iz * n + ix;
					o[i] = color(ox + ix * step, oz + iz * step, h[i], slope[i]);
				}
		}
		finally { _approx = false; }
		return o;
	}

	/// the paper map: linear ground colours on the same kind of grid; under `water` the alpha is 0
	public Color[] map_colors(double ox, double oz, double step, long nx, long row0, long rows, double water)
	{
		var o = new Color[nx * rows];
		_approx = true;
		try
		{
			for (long r = 0; r < rows; r++)
			{
				double z = oz + (row0 + r) * step;
				for (long i = 0; i < nx; i++)
				{
					double x = ox + i * step;
					double h = ground(x, z);
					o[r * nx + i] = h < water ? new Color(0, 0, 0, 0) : color(x, z, h, 1.0);
				}
			}
		}
		finally { _approx = false; }
		return o;
	}

	public Godot.Collections.Dictionary build_ground(double ox, double oz, long N)
	{
		const double S = 48.0;
		double d = S / N;
		long W = N + 3;
		long NV = N + 1;
		var G = new float[W * W];
		var pre_g = new Color[NV * NV];
		var pre_d = new Color[NV * NV];
		var pre_t = new float[NV * NV];
		var pre_b = new double[NV * NV * 2];
		var TR = new float[NV * NV * 4];   // trail frame for ground.gdshader: across, line offset, along, run-off skid's place
		var T2 = new float[NV * NV * 4];   // road, dry biome, built jump, run-off skid's strength
		var T3 = new float[NV * NV];       // riders in the air over a jump here
		for (long iz = -1; iz < N + 2; iz++)
		{
			for (long ix = -1; ix < N + 2; ix++)
			{
				double x = ox - S / 2 + ix * d;
				double z = oz - S / 2 + iz * d;
				double h = ground(x, z);
				G[(iz + 1) * W + ix + 1] = (float)h;
				if (ix >= 0 && ix <= N && iz >= 0 && iz <= N)
				{
					long o = iz * NV + ix;
					_cp_h = G[(iz + 1) * W + ix + 1];
					pre_t[o] = (float)color_pre(x, z);
					pre_g[o] = cl_g;
					pre_d[o] = cl_d;
					pre_b[o * 2] = cp_dry;
					pre_b[o * 2 + 1] = cp_rug;
					double jm = jump_mask(x, z);
					double ac = across(x, z);
					query(x, z);
					bool on = q_d < q_w + 2.6;
					TR[o * 4] = (float)Math.Clamp(ac, -20.0, 20.0);
					TR[o * 4 + 1] = (float)line_off(x, z);
					TR[o * 4 + 2] = (float)(on ? q_s : x * 0.6 + z * 0.8);
					TR[o * 4 + 3] = (float)(on ? cRO[q_i] + (cRO[q_i + 1] - cRO[q_i]) * q_t : 0.0);
					T2[o * 4] = (float)(on ? q_rd : 0.0);
					T2[o * 4 + 1] = (float)cp_dry;
					T2[o * 4 + 2] = (float)jm;
					T3[o] = (float)fo_air;
					T2[o * 4 + 3] = (float)(on ? cROS[q_i] + (cROS[q_i + 1] - cROS[q_i]) * q_t : 0.0);
				}
			}
		}
		var verts = new Vector3[NV * NV];
		var norms = new Vector3[NV * NV];
		var uvs = new Vector2[NV * NV];
		var LG = new Color[NV * NV];
		var LD = new Color[NV * NV];
		var TW = new float[NV * NV];
		var SW = new float[NV * NV];
		var DRY = new float[NV * NV];   // biome dryness (grass field density, GrassField)
		for (long iz = 0; iz < NV; iz++)
		{
			for (long ix = 0; ix < NV; ix++)
			{
				long k = (iz + 1) * W + ix + 1;
				long o = iz * NV + ix;
				double lx = -S / 2 + ix * d;
				double lz = -S / 2 + iz * d;
				double h = G[k];
				verts[o] = new Vector3((float)lx, (float)h, (float)lz);
				var nv = new Vector3((float)((double)G[k - 1] - G[k + 1]), (float)(2 * d), (float)((double)G[k - W] - G[k + W]));
				float lsq = nv.X * nv.X + nv.Y * nv.Y + nv.Z * nv.Z;
				if (lsq == 0f)
				{
					nv = new Vector3(0, 0, 0);
				}
				else
				{
					float len = MathF.Sqrt(lsq);
					nv = new Vector3(nv.X / len, nv.Y / len, nv.Z / len);
				}
				norms[o] = nv;
				uvs[o] = new Vector2((float)((ix + 0.5) / NV), (float)((iz + 0.5) / NV));
				cl_g = pre_g[o];
				cl_d = pre_d[o];
				color_post(lx + ox, lz + oz, h, nv.Y, pre_b[o * 2], pre_b[o * 2 + 1]);
				TW[o] = pre_t[o];
				SW[o] = (float)cl_steep;
				DRY[o] = (float)pre_b[o * 2];
				LG[o] = cl_g;
				LD[o] = cl_d;
			}
		}
		return new Godot.Collections.Dictionary
		{
			["G"] = G, ["verts"] = verts, ["norms"] = norms, ["uvs"] = uvs,
			["LG"] = LG, ["LD"] = LD, ["TW"] = TW, ["SW"] = SW, ["DRY"] = DRY, ["TR"] = TR, ["T2"] = T2, ["T3"] = T3,
		};
	}

	// ======================================================================
	// the course query (course.js query())
	// ======================================================================
	private void _save_slot(double[] arr)
	{
		arr[0] = q_x; arr[1] = q_z; arr[2] = q_d; arr[3] = q_a; arr[4] = q_i; arr[5] = q_t; arr[6] = q_w;
		arr[7] = q_kind; arr[8] = q_k; arr[9] = q_bt; arr[10] = q_s; arr[11] = q_rd; arr[12] = q_rk;
		arr[13] = q_bench; arr[14] = q_mask;
	}

	private void _load_slot(double[] arr)
	{
		q_x = arr[0]; q_z = arr[1]; q_d = arr[2]; q_a = arr[3]; q_i = (long)arr[4]; q_t = arr[5]; q_w = arr[6];
		q_kind = (long)arr[7]; q_k = arr[8]; q_bt = arr[9]; q_s = arr[10]; q_rd = arr[11]; q_rk = arr[12];
		q_bench = arr[13]; q_mask = arr[14];
	}

	private double[] _qtmp = new double[15];

	public void query(double x, double z)
	{
		if (x == q_x && z == q_z)
			return;
		if (x == _qp[0] && z == _qp[1])
		{
			var tmp = _qtmp;
			_save_slot(tmp);
			_load_slot(_qp);
			_qtmp = _qp;
			_qp = tmp;
			return;
		}
		_save_slot(_qp);
		q_x = x; q_z = z;
		q_d = double.PositiveInfinity; q_mask = 0.0;
		long g0x = Math.Max(floori((x - QR) / CELL), c_gx0);
		long g1x = Math.Min(floori((x + QR) / CELL), c_gx0 + c_gnx - 1);
		long g0z = Math.Max(floori((z - QR) / CELL), c_gz0);
		long g1z = Math.Min(floori((z + QR) / CELL), c_gz0 + c_gnz - 1);
		if (g1x < g0x || g1z < g0z)
			return;
		_cand_n = 0;
		for (long gx = g0x; gx < g1x + 1; gx++)
		{
			long row = (gx - c_gx0) * c_gnz - c_gz0;
			for (long gz = g0z; gz < g1z + 1; gz++)
			{
				long ci = row + gz;
				for (int k = c_run_start[ci]; k < c_run_start[ci + 1]; k++)
				{
					if (_cand_n == _cand.Length)
						Array.Resize(ref _cand, _cand.Length * 2);
					_cand[_cand_n++] = c_runs[k];
				}
			}
		}
		if (_cand_n == 0)
			return;
		Array.Sort(_cand, 0, _cand_n);
		double sw = 0.0;
		double se = 0.0;
		double sk = 0.0;
		double sb = 0.0;
		double leg_d = double.PositiveInfinity;
		long leg_i = 0;
		double leg_t = 0.0;
		long prev = -9;
		double skip_r = QR + 1.03;
		var seg = c_seg;
		for (int ri = 0; ri < _cand_n; ri++)
		{
			long run = _cand[ri];
			long i = run >> 8;
			long i_end = i + (run & 0xFF);
			if (i - prev > 2)
			{
				if (leg_d != double.PositiveInfinity)
					_q_close(leg_d, leg_i, leg_t, x, z);
				leg_d = double.PositiveInfinity;
			}
			while (i <= i_end)
			{
				long o = i * 6;
				double mdx = x - seg[o + 3];
				double mdz = z - seg[o + 4];
				double m2 = mdx * mdx + mdz * mdz;
				if (m2 > seg[o + 5])
				{
					long kk = floori((Math.Sqrt(m2) - skip_r) / 2.002);
					i += 1 + Math.Max(0, kk);
					continue;
				}
				double ax = cX[i];
				double az = cZ[i];
				double bx = seg[o];
				double bz = seg[o + 1];
				double t = ((x - ax) * bx + (z - az) * bz) / seg[o + 2];
				t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
				double ex = x - ax - bx * t;
				double ez = z - az - bz * t;
				double d2 = ex * ex + ez * ez;
				double sd = Math.Sqrt(d2);
				double tt = (sd - (QR - 9)) / ((QR - 2) - (QR - 9));
				if (tt < 1.0)
				{
					tt = tt < 0.0 ? 0.0 : tt;
					double wt = (1.0 - tt * tt * (3.0 - 2.0 * tt)) / ((d2 + 1) * (d2 + 1));
					if (wt > 0.0)
					{
						sw += wt;
						se += wt * (cE[i] + (cE[i + 1] - cE[i]) * t);
						sk += wt * (cKAP[i] + (cKAP[i + 1] - cKAP[i]) * t);
						sb += wt * (cBT[i] + (cBT[i + 1] - cBT[i]) * t);
					}
				}
				if (d2 < leg_d)
				{
					leg_d = d2; leg_i = i; leg_t = t;
				}
				i += 1;
			}
			prev = i_end;
		}
		if (leg_d != double.PositiveInfinity)
			_q_close(leg_d, leg_i, leg_t, x, z);
		if (q_d > QR)
		{
			q_d = double.PositiveInfinity; q_mask = 0.0;
			return;
		}
		if (sw > 0.0)
		{
			q_bench = se / sw;
			q_k = sk / sw;
			q_bt = sb / sw;
		}
		else
		{
			q_bench = cE[q_i] + (cE[q_i + 1] - cE[q_i]) * q_t;
		}
	}

	private void _q_close(double leg_d2, long i, double t, double x, double z)
	{
		double ld = Math.Sqrt(leg_d2);
		double wl = cW[i] + (cW[i + 1] - cW[i]) * t;
		double m = 1.0 - sm(wl + 1.5, wl + 8, ld);
		if (m > q_mask)
			q_mask = m;
		if (ld < q_d)
		{
			q_d = ld; q_i = i; q_t = t; q_w = wl;
			double px = cX[i] + (cX[i + 1] - cX[i]) * t;
			double pz = cZ[i] + (cZ[i + 1] - cZ[i]) * t;
			double tx = cTX[i];
			double tz = cTZ[i];
			q_a = (-(x - px) * tz + (z - pz) * tx < 0.0 ? -1.0 : 1.0) * ld;
			q_kind = cKD[t < 0.5 ? i : i + 1];
			q_k = cKAP[i] + (cKAP[i + 1] - cKAP[i]) * t;
			q_bt = cBT[i] + (cBT[i + 1] - cBT[i]) * t;
			q_s = (i + t) * CSTEP;
			q_rd = cRD[i] + (cRD[i + 1] - cRD[i]) * t;
			q_rk = cRK[i] + (cRK[i + 1] - cRK[i]) * t;
		}
	}
}
