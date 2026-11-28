using System;

namespace Runout.Sim
{
    /// Godot's global maths, same names and same behaviour, so ported GDScript reads line for line
    /// (`using static Runout.Sim.Gd;`). Doubles throughout, like GDScript's float.
    public static class Gd
    {
        public const double PI = Math.PI;
        public const double TAU = Math.PI * 2.0;
        public const double INF = double.PositiveInfinity;
        public const double NAN = double.NaN;

        public static double absf(double x) => Math.Abs(x);
        public static int absi(int x) => Math.Abs(x);
        public static double signf(double x) => x > 0 ? 1.0 : (x < 0 ? -1.0 : 0.0);
        public static double sign(double x) => signf(x);
        public static int signi(int x) => Math.Sign(x);
        public static double minf(double a, double b) => a < b ? a : b;
        public static double maxf(double a, double b) => a > b ? a : b;
        public static int mini(int a, int b) => a < b ? a : b;
        public static int maxi(int a, int b) => a > b ? a : b;
        public static double clampf(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
        public static int clampi(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
        public static double lerpf(double a, double b, double t) => a + (b - a) * t;
        public static double lerp(double a, double b, double t) => a + (b - a) * t;
        public static double inverse_lerp(double a, double b, double v) => (v - a) / (b - a);
        public static double remap(double v, double i0, double i1, double o0, double o1) => lerp(o0, o1, inverse_lerp(i0, i1, v));
        public static double sqrt(double x) => Math.Sqrt(x);
        public static double pow(double a, double b) => Math.Pow(a, b);
        public static double exp(double x) => Math.Exp(x);
        public static double log(double x) => Math.Log(x);
        public static double sin(double x) => Math.Sin(x);
        public static double cos(double x) => Math.Cos(x);
        public static double tan(double x) => Math.Tan(x);
        public static double asin(double x) => Math.Asin(x);
        public static double acos(double x) => Math.Acos(x);
        public static double atan(double x) => Math.Atan(x);
        public static double atan2(double y, double x) => Math.Atan2(y, x);
        public static double tanh(double x) => Math.Tanh(x);
        public static double floor(double x) => Math.Floor(x);
        public static double ceil(double x) => Math.Ceiling(x);
        public static double round(double x) => Math.Round(x, MidpointRounding.AwayFromZero);
        public static int roundi(double x) => (int)Math.Round(x, MidpointRounding.AwayFromZero);
        public static int floori(double x) => (int)Math.Floor(x);
        public static int ceili(double x) => (int)Math.Ceiling(x);
        public static bool is_nan(double x) => double.IsNaN(x);
        public static bool is_finite(double x) => !double.IsNaN(x) && !double.IsInfinity(x);
        public static bool is_inf(double x) => double.IsInfinity(x);
        public static bool is_zero_approx(double x) => Math.Abs(x) < 1e-5;
        public static bool is_equal_approx(double a, double b)
        {
            if (a == b) return true;
            double tol = 1e-5 * Math.Abs(a);
            if (tol < 1e-5) tol = 1e-5;
            return Math.Abs(a - b) < tol;
        }
        public static double deg_to_rad(double d) => d * (PI / 180.0);
        public static double rad_to_deg(double r) => r * (180.0 / PI);
        public static double fmod(double a, double b) => a % b;
        public static double fposmod(double a, double b)
        {
            double v = a % b;
            if ((v < 0 && b > 0) || (v > 0 && b < 0)) v += b;
            return v;
        }
        public static double wrapf(double v, double lo, double hi)
        {
            double range = hi - lo;
            if (is_zero_approx(range)) return lo;
            double r = v - range * Math.Floor((v - lo) / range);
            if (is_equal_approx(r, hi)) return lo;
            return r;
        }
        public static double snappedf(double v, double step) => step != 0 ? Math.Floor(v / step + 0.5) * step : v;
        /// Godot 4 smoothstep (from == to: a step)
        public static double smoothstep(double from, double to, double x)
        {
            if (is_equal_approx(from, to))
            {
                if (from <= to) return x <= from ? 0.0 : 1.0;
                return x <= to ? 1.0 : 0.0;
            }
            double s = clampf((x - from) / (to - from), 0.0, 1.0);
            return s * s * (3.0 - 2.0 * s);
        }
        public static double move_toward(double from, double to, double delta)
            => Math.Abs(to - from) <= delta ? to : from + Math.Sign(to - from) * delta;
        public static double angle_difference(double from, double to)
        {
            double diff = (to - from) % TAU;
            return (2.0 * diff) % TAU - diff;
        }
        public static double lerp_angle(double from, double to, double w) => from + angle_difference(from, to) * w;
        public static double ease(double x, double c)
        {
            if (x < 0) x = 0; else if (x > 1) x = 1;
            if (c > 0) return c < 1 ? 1 - Math.Pow(1 - x, 1 / c) : Math.Pow(x, c);
            if (c < 0)
                return x < 0.5 ? Math.Pow(x * 2, -c) * 0.5 : (1 - Math.Pow(1 - (x - 0.5) * 2, -c)) * 0.5 + 0.5;
            return 0;
        }
    }

    /// Godot's Vector3: stored and computed in 32-bit floats like Godot's (real_t = float), while GDScript's scalars are
    /// 64-bit. Matching that rounding is what makes the port follow Godot step for step (doubles here drifted ~1e-8 a step,
    /// and slides / grip amplified it over seconds). Members read / write as double so ported code reads like GDScript.
    public struct V3
    {
        float _x, _y, _z;
        public double x { get => _x; set => _x = (float)value; }
        public double y { get => _y; set => _y = (float)value; }
        public double z { get => _z; set => _z = (float)value; }
        public V3(double x, double y, double z) { _x = (float)x; _y = (float)y; _z = (float)z; }
        V3(float x, float y, float z, bool _) { _x = x; _y = y; _z = z; }
        public static readonly V3 Zero = new V3(0, 0, 0);
        public static readonly V3 UP = new V3(0, 1, 0);
        public static V3 operator +(V3 a, V3 b) => new V3(a._x + b._x, a._y + b._y, a._z + b._z, true);
        public static V3 operator -(V3 a, V3 b) => new V3(a._x - b._x, a._y - b._y, a._z - b._z, true);
        public static V3 operator -(V3 a) => new V3(-a._x, -a._y, -a._z, true);
        public static V3 operator *(V3 a, double k) { float f = (float)k; return new V3(a._x * f, a._y * f, a._z * f, true); }
        public static V3 operator *(double k, V3 a) => a * k;
        public static V3 operator *(V3 a, V3 b) => new V3(a._x * b._x, a._y * b._y, a._z * b._z, true);
        public static V3 operator /(V3 a, double k) { float f = (float)k; return new V3(a._x / f, a._y / f, a._z / f, true); }
        public double dot(V3 b) => _x * b._x + _y * b._y + _z * b._z;
        public V3 cross(V3 b) => new V3(_y * b._z - _z * b._y, _z * b._x - _x * b._z, _x * b._y - _y * b._x, true);
        public double length() => MathF.Sqrt(_x * _x + _y * _y + _z * _z);
        public double length_squared() => _x * _x + _y * _y + _z * _z;
        public V3 normalized()
        {
            float l = _x * _x + _y * _y + _z * _z;
            if (l == 0f) return Zero;
            l = MathF.Sqrt(l);
            return new V3(_x / l, _y / l, _z / l, true);
        }
        public V3 lerp(V3 b, double t) { float w = (float)t; return new V3(_x + w * (b._x - _x), _y + w * (b._y - _y), _z + w * (b._z - _z), true); }
        public double distance_to(V3 b) => (b - this).length();
        public override string ToString() => $"({_x:0.###}, {_y:0.###}, {_z:0.###})";
    }

    /// Godot's Vector2, float32 like Godot's (see V3).
    public struct V2
    {
        float _x, _y;
        public double x { get => _x; set => _x = (float)value; }
        public double y { get => _y; set => _y = (float)value; }
        public V2(double x, double y) { _x = (float)x; _y = (float)y; }
        V2(float x, float y, bool _) { _x = x; _y = y; }
        public static readonly V2 Zero = new V2(0, 0);
        public static V2 operator +(V2 a, V2 b) => new V2(a._x + b._x, a._y + b._y, true);
        public static V2 operator -(V2 a, V2 b) => new V2(a._x - b._x, a._y - b._y, true);
        public static V2 operator -(V2 a) => new V2(-a._x, -a._y, true);
        public static V2 operator *(V2 a, double k) { float f = (float)k; return new V2(a._x * f, a._y * f, true); }
        public static V2 operator *(double k, V2 a) => a * k;
        public static V2 operator /(V2 a, double k) { float f = (float)k; return new V2(a._x / f, a._y / f, true); }
        public double dot(V2 b) => _x * b._x + _y * b._y;
        public double length() => MathF.Sqrt(_x * _x + _y * _y);
        public double length_squared() => _x * _x + _y * _y;
        public V2 normalized()
        {
            float l = _x * _x + _y * _y;
            if (l == 0f) return Zero;
            l = MathF.Sqrt(l);
            return new V2(_x / l, _y / l, true);
        }
        public double angle() => MathF.Atan2(_y, _x);
        public V2 limit_length(double len)
        {
            float l = (float)length(), m = (float)len;
            return l > 0f && m < l ? new V2(_x / l * m, _y / l * m, true) : this;
        }
        public V2 lerp(V2 b, double t) { float w = (float)t; return new V2(_x + w * (b._x - _x), _y + w * (b._y - _y), true); }
        public V2 move_toward(V2 to, double d)
        {
            var vd = to - this; float l = (float)vd.length(); float df = (float)d;
            return l <= df || l < 1e-5f ? to : new V2(_x + vd._x / l * df, _y + vd._y / l * df, true);
        }
    }
}
