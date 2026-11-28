// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Runout.Sim
{
	/// <summary>
	/// GDScript's global functions with Godot 4.7's exact semantics (edge cases, NaN, ties), so the ported ride reads
	/// line for line like bike_physics.gd: `using static Runout.Sim.Gd;`. Checked by tools/sim_math_probe.gd (helpers).
	/// </summary>
	public static class Gd
	{
		public const double PI = Math.PI;
		public const double TAU = Math.PI * 2.0;
		public const double INF = double.PositiveInfinity;
		public const double NAN = double.NaN;
		private const double CMP_EPSILON = 0.00001;

		// --- the transcendental functions as GDScript computes them (see SimMath)
		public static double sin(double x) => SimMath.Sin(x);
		public static double cos(double x) => SimMath.Cos(x);
		public static double tan(double x) => SimMath.Tan(x);
		public static double atan(double x) => SimMath.Atan(x);
		public static double atan2(double y, double x) => SimMath.Atan2(y, x);
		public static double asin(double x) => SimMath.Asin(x);
		public static double acos(double x) => SimMath.Acos(x);
		public static double exp(double x) => SimMath.Exp(x);
		public static double log(double x) => SimMath.Log(x);
		public static double tanh(double x) => SimMath.Tanh(x);
		public static double pow(double x, double y) => SimMath.Pow(x, y);
		public static double sqrt(double x) => Math.Sqrt(x);

		// --- Godot's MAX / MIN / CLAMP / SIGN macros (comparison order matters for NaN and -0)
		public static double maxf(double a, double b) => a > b ? a : b;
		public static double minf(double a, double b) => a < b ? a : b;
		public static long maxi(long a, long b) => a > b ? a : b;
		public static long mini(long a, long b) => a < b ? a : b;
		public static double clampf(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
		public static long clampi(long v, long lo, long hi) => v < lo ? lo : (v > hi ? hi : v);
		public static double absf(double x) => Math.Abs(x);
		public static long absi(long x) => Math.Abs(x);
		public static double signf(double x) => x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0);
		public static long signi(long x) => x > 0 ? 1 : (x < 0 ? -1 : 0);
		public static double lerpf(double a, double b, double t) => a + (b - a) * t;
		public static double move_toward(double from, double to, double delta) =>
			Math.Abs(to - from) <= delta ? to : from + signf(to - from) * delta;
		public static double floor(double x) => Math.Floor(x);
		public static double ceil(double x) => Math.Ceiling(x);
		public static double round(double x) => Math.Round(x, MidpointRounding.AwayFromZero);
		public static long roundi(double x) => (long)Math.Round(x, MidpointRounding.AwayFromZero);
		public static long floori(double x) => (long)Math.Floor(x);
		public static long ceili(double x) => (long)Math.Ceiling(x);
		// (Godot's roundf / floorf / ceilf: the GDScript bindings take doubles)
		public static double roundf(double x) => Math.Round(x, MidpointRounding.AwayFromZero);
		public static double floorf(double x) => Math.Floor(x);
		public static double ceilf(double x) => Math.Ceiling(x);
		/// GDScript's is_same: the same object (core dictionaries made from the same engine one count as the same)
		public static bool is_same(object a, object b) => ReferenceEquals(a, b) || (a is GdDict da && b is GdDict db && da == db);
		public static double fmod(double a, double b) => a % b;   // (C fmod = C#'s % on doubles)
		public static double fposmod(double a, double b)
		{
			double v = a % b;
			if ((v < 0 && b > 0) || (v > 0 && b < 0))
				v += b;
			return v;
		}
		public static bool is_nan(double x) => double.IsNaN(x);
		public static bool is_finite(double x) => double.IsFinite(x);
		public static bool is_inf(double x) => double.IsInfinity(x);
		public static double rad_to_deg(double r) => r * (180.0 / Math.PI);
		public static double deg_to_rad(double d) => d * (Math.PI / 180.0);

		public static bool is_zero_approx(double x) => Math.Abs(x) < CMP_EPSILON;
		public static bool is_equal_approx(double a, double b)
		{
			if (a == b)
				return true;
			double tol = CMP_EPSILON * Math.Abs(a);
			if (tol < CMP_EPSILON)
				tol = CMP_EPSILON;
			return Math.Abs(a - b) < tol;
		}

		public static double wrapf(double value, double min, double max)
		{
			double range = max - min;
			if (is_zero_approx(range))
				return min;
			double result = value - (range * Math.Floor((value - min) / range));
			if (is_equal_approx(result, max))
				return min;
			return result;
		}

		public static double smoothstep(double from, double to, double s)
		{
			if (is_equal_approx(from, to))
			{
				if (from <= to)
					return s <= from ? 0.0 : 1.0;
				return s <= to ? 1.0 : 0.0;
			}
			double t = clampf((s - from) / (to - from), 0.0, 1.0);
			return t * t * (3.0 - 2.0 * t);
		}

		// --- Variant-style conversions / containers (the few places the ride uses untyped values)
		public static double to_f(object v) => v switch
		{
			double d => d, float f => f, int i => i, long l => l, bool b => b ? 1.0 : 0.0,
			string s => double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var r) ? r : 0.0,
			null => 0.0, _ => Convert.ToDouble(v, CultureInfo.InvariantCulture),
		};
		public static int to_i(object v) => v switch
		{
			double d => (int)d, float f => (int)f, int i => i, long l => (int)l, bool b => b ? 1 : 0,
			string s => int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var r) ? r : (int)to_f(s),
			null => 0, _ => Convert.ToInt32(v, CultureInfo.InvariantCulture),
		};
		public static int to_i(double d) => (int)d;
		public static long to_l(object v) => v is long l ? l : to_i(v);
		public static T as_<T>(object v) => v is T t ? t : default;
		public static bool to_b(object v) => v switch
		{
			bool b => b, double d => d != 0.0, float f => f != 0f, int i => i != 0, long l => l != 0, string s => s != "",
			null => false, _ => true,
		};
		public static bool truthy(System.Collections.ICollection c) => c != null && c.Count > 0;
		public static int len(System.Collections.ICollection c) => c?.Count ?? 0;
		public static int len(string s) => s?.Length ?? 0;
		public static bool in_(object a, object b) => b switch
		{
			string s => s.Contains(a as string ?? ""),
			GdDict d => a is string k && d.ContainsKey(k),
			System.Collections.IList l => l.Contains(a),
			_ => false,
		};
		public static IEnumerable<int> range(long a, long b, long step = 1)
		{
			if (step > 0) for (long i = a; i < b; i += step) yield return (int)i;
			else for (long i = a; i > b; i += step) yield return (int)i;
		}
		public static T pop_front<T>(List<T> l)
		{
			if (l.Count == 0) return default;
			T v = l[0];
			l.RemoveAt(0);
			return v;
		}
		public static void resize(ref double[] a, long n) => Array.Resize(ref a, (int)n);
		public static void resize(ref float[] a, long n) => Array.Resize(ref a, (int)n);

		/// GDScript's global randf (unseeded: crashes only, never the ride's own randomness)
		private static readonly Pcg32 _rng = new Pcg32((ulong)DateTime.Now.Ticks);
		public static double randf() => _rng.Randf();

		// --- GDScript's "%" string formatting (the subset the ride's messages / probes use: %s %d %f %.Nf %%)
		public static string fmt(string f, params object[] a)
		{
			var sb = new StringBuilder();
			int ai = 0;
			for (int i = 0; i < f.Length; i++)
			{
				char c = f[i];
				if (c != '%' || i + 1 >= f.Length)
				{
					sb.Append(c);
					continue;
				}
				int j = i + 1;
				if (f[j] == '%')
				{
					sb.Append('%');
					i = j;
					continue;
				}
				bool plus = false, left = false, zero = false;
				while (j < f.Length && (f[j] == '+' || f[j] == '-' || f[j] == '0'))
				{
					if (f[j] == '+') plus = true; else if (f[j] == '-') left = true; else zero = true;
					j++;
				}
				int width = 0;
				while (j < f.Length && char.IsDigit(f[j]))
					width = width * 10 + (f[j++] - '0');
				int prec = -1;
				if (j < f.Length && f[j] == '.')
				{
					j++;
					prec = 0;
					while (j < f.Length && char.IsDigit(f[j]))
						prec = prec * 10 + (f[j++] - '0');
				}
				if (j >= f.Length)
				{
					sb.Append(f, i, f.Length - i);
					break;
				}
				char k = f[j];
				object v = ai < a.Length ? a[ai++] : "";
				string s = k switch
				{
					'd' or 'i' => Convert.ToInt64(Math.Truncate(Convert.ToDouble(v, CultureInfo.InvariantCulture))).ToString(CultureInfo.InvariantCulture),
					'f' => Convert.ToDouble(v, CultureInfo.InvariantCulture).ToString("F" + (prec < 0 ? 6 : prec), CultureInfo.InvariantCulture),
					_ => str(v),
				};
				if (plus && (k == 'd' || k == 'f') && !s.StartsWith("-"))
					s = "+" + s;
				if (s.Length < width)
					s = left ? s.PadRight(width) : (zero ? s.PadLeft(width, '0') : s.PadLeft(width));
				sb.Append(s);
				i = j;
			}
			return sb.ToString();
		}

		/// GDScript's str() for the values the ride prints
		public static string str(object v) => v switch
		{
			null => "<null>",
			bool b => b ? "true" : "false",
			double d => d == Math.Floor(d) && Math.Abs(d) < 1e15 ? d.ToString("0.0", CultureInfo.InvariantCulture) : d.ToString("R", CultureInfo.InvariantCulture),
			float f => ((double)f).ToString("R", CultureInfo.InvariantCulture),
			IFormattable fo => fo.ToString(null, CultureInfo.InvariantCulture),
			_ => v.ToString(),
		};
	}

	/// <summary>Godot's Vector2: 32-bit float components, every operation rounded to float like the engine's.
	/// Components read as double (GDScript promotes them), constructors take doubles (rounded to float).</summary>
	public struct V2
	{
		public float fx, fy;
		public V2(double x, double y) { fx = (float)x; fy = (float)y; }
		private V2(float x, float y, bool _) { fx = x; fy = y; }
		public double x { get => fx; set => fx = (float)value; }
		public double y { get => fy; set => fy = (float)value; }
		public static readonly V2 ZERO = new V2(0f, 0f, true);
		public static readonly V2 ONE = new V2(1f, 1f, true);
		public static V2 operator +(V2 a, V2 b) => new V2(a.fx + b.fx, a.fy + b.fy, true);
		public static V2 operator -(V2 a, V2 b) => new V2(a.fx - b.fx, a.fy - b.fy, true);
		public static V2 operator -(V2 a) => new V2(-a.fx, -a.fy, true);
		public static V2 operator *(V2 a, V2 b) => new V2(a.fx * b.fx, a.fy * b.fy, true);
		public static V2 operator *(V2 a, double s) { float f = (float)s; return new V2(a.fx * f, a.fy * f, true); }
		public static V2 operator *(double s, V2 a) => a * s;
		public static V2 operator /(V2 a, double s) { float f = (float)s; return new V2(a.fx / f, a.fy / f, true); }
		public double length() => MathF.Sqrt(fx * fx + fy * fy);
		public double length_squared() => fx * fx + fy * fy;
		public double dot(V2 b) => fx * b.fx + fy * b.fy;
		public double cross(V2 b) => fx * b.fy - fy * b.fx;
		public V2 normalized()
		{
			float l = fx * fx + fy * fy;
			if (l == 0f)
				return this;
			l = MathF.Sqrt(l);
			return new V2(fx / l, fy / l, true);
		}
		public V2 limit_length(double len = 1.0)
		{
			float l = (float)length();
			V2 v = this;
			if (l > 0f && (float)len < l)
			{
				v = new V2(v.fx / l, v.fy / l, true);
				v = v * len;
			}
			return v;
		}
		public override string ToString() => $"({Gd.str(fx)}, {Gd.str(fy)})";
	}

	/// <summary>Godot's Vector3: 32-bit float components (see V2).</summary>
	public struct V3
	{
		public float fx, fy, fz;
		public V3(double x, double y, double z) { fx = (float)x; fy = (float)y; fz = (float)z; }
		private V3(float x, float y, float z, bool _) { fx = x; fy = y; fz = z; }
		public double x { get => fx; set => fx = (float)value; }
		public double y { get => fy; set => fy = (float)value; }
		public double z { get => fz; set => fz = (float)value; }
		public static readonly V3 ZERO = new V3(0f, 0f, 0f, true);
		public static readonly V3 ONE = new V3(1f, 1f, 1f, true);
		public static readonly V3 UP = new V3(0f, 1f, 0f, true);
		public static V3 operator +(V3 a, V3 b) => new V3(a.fx + b.fx, a.fy + b.fy, a.fz + b.fz, true);
		public static V3 operator -(V3 a, V3 b) => new V3(a.fx - b.fx, a.fy - b.fy, a.fz - b.fz, true);
		public static V3 operator -(V3 a) => new V3(-a.fx, -a.fy, -a.fz, true);
		public static V3 operator *(V3 a, V3 b) => new V3(a.fx * b.fx, a.fy * b.fy, a.fz * b.fz, true);
		public static V3 operator *(V3 a, double s) { float f = (float)s; return new V3(a.fx * f, a.fy * f, a.fz * f, true); }
		public static V3 operator *(double s, V3 a) => a * s;
		public static V3 operator /(V3 a, double s) { float f = (float)s; return new V3(a.fx / f, a.fy / f, a.fz / f, true); }
		public static V3 operator /(V3 a, V3 b) => new V3(a.fx / b.fx, a.fy / b.fy, a.fz / b.fz, true);
		public double length() { float x2 = fx * fx, y2 = fy * fy, z2 = fz * fz; return MathF.Sqrt(x2 + y2 + z2); }
		public double length_squared() { float x2 = fx * fx, y2 = fy * fy, z2 = fz * fz; return x2 + y2 + z2; }
		public double dot(V3 b) => fx * b.fx + fy * b.fy + fz * b.fz;
		public V3 cross(V3 b) => new V3(fy * b.fz - fz * b.fy, fz * b.fx - fx * b.fz, fx * b.fy - fy * b.fx, true);
		public V3 normalized()
		{
			float l2 = (float)length_squared();
			if (l2 == 0f)
				return ZERO;
			float l = MathF.Sqrt(l2);
			return new V3(fx / l, fy / l, fz / l, true);
		}
		public double distance_to(V3 b) => (b - this).length();
		public override string ToString() => $"({Gd.str(fx)}, {Gd.str(fy)}, {Gd.str(fz)})";
	}
}
