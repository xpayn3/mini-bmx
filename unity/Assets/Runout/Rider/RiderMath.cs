using System;
using System.Collections.Generic;

namespace Runout.Rider
{
    /// Godot-semantics vector maths for the rider pose (engine-free, doubles). Same behaviour as Godot's Vector3 / Basis /
    /// Quaternion where the pose solver uses them (rotated, slerp, angle_to, signed_angle_to, project, Basis(axis, angle),
    /// arc quaternions...). Axes as Godot: right-handed, +Y up.
    public struct Vec3
    {
        public double x, y, z;
        public Vec3(double x, double y, double z) { this.x = x; this.y = y; this.z = z; }
        public static readonly Vec3 ZERO = new Vec3(0, 0, 0), ONE = new Vec3(1, 1, 1), UP = new Vec3(0, 1, 0), DOWN = new Vec3(0, -1, 0),
            RIGHT = new Vec3(1, 0, 0), BACK = new Vec3(0, 0, 1), FORWARD = new Vec3(0, 0, -1);
        public static Vec3 operator +(Vec3 a, Vec3 b) => new Vec3(a.x + b.x, a.y + b.y, a.z + b.z);
        public static Vec3 operator -(Vec3 a, Vec3 b) => new Vec3(a.x - b.x, a.y - b.y, a.z - b.z);
        public static Vec3 operator -(Vec3 a) => new Vec3(-a.x, -a.y, -a.z);
        public static Vec3 operator *(Vec3 a, double s) => new Vec3(a.x * s, a.y * s, a.z * s);
        public static Vec3 operator *(double s, Vec3 a) => new Vec3(a.x * s, a.y * s, a.z * s);
        public static Vec3 operator *(Vec3 a, Vec3 b) => new Vec3(a.x * b.x, a.y * b.y, a.z * b.z);
        public static Vec3 operator /(Vec3 a, double s) => new Vec3(a.x / s, a.y / s, a.z / s);
        public static bool operator ==(Vec3 a, Vec3 b) => a.x == b.x && a.y == b.y && a.z == b.z;
        public static bool operator !=(Vec3 a, Vec3 b) => !(a == b);
        public override bool Equals(object o) => o is Vec3 v && v == this;
        public override int GetHashCode() => x.GetHashCode() ^ (y.GetHashCode() << 2) ^ (z.GetHashCode() >> 2);
        public override string ToString() => $"({x:0.###}, {y:0.###}, {z:0.###})";

        public double dot(Vec3 b) => x * b.x + y * b.y + z * b.z;
        public Vec3 cross(Vec3 b) => new Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
        public double length_squared() => x * x + y * y + z * z;
        public double length() => Math.Sqrt(length_squared());
        public Vec3 normalized() { double l = length(); return l == 0 ? ZERO : this / l; }
        public double distance_to(Vec3 b) => (b - this).length();
        public Vec3 lerp(Vec3 b, double t) => new Vec3(x + (b.x - x) * t, y + (b.y - y) * t, z + (b.z - z) * t);
        public double angle_to(Vec3 b) => Math.Atan2(cross(b).length(), dot(b));
        public double signed_angle_to(Vec3 b, Vec3 axis)
        {
            Vec3 c = cross(b);
            double a = Math.Atan2(c.length(), dot(b));
            return c.dot(axis) < 0 ? -a : a;
        }
        /// rotated about a (normalized) axis, right-handed (Godot Vector3.rotated)
        public Vec3 rotated(Vec3 axis, double angle) => Basis.axis_angle(axis, angle) * this;
        public Vec3 project(Vec3 b) { double l = b.length_squared(); return l == 0 ? ZERO : b * (dot(b) / l); }
        public Vec3 clamp(Vec3 lo, Vec3 hi) => new Vec3(Math.Min(Math.Max(x, lo.x), hi.x), Math.Min(Math.Max(y, lo.y), hi.y), Math.Min(Math.Max(z, lo.z), hi.z));
        public bool is_nan() => double.IsNaN(x) || double.IsNaN(y) || double.IsNaN(z);
        /// Godot Vector3.slerp
        public Vec3 slerp(Vec3 to, double w)
        {
            double s0 = length_squared(), s1 = to.length_squared();
            if (s0 == 0.0 || s1 == 0.0) return lerp(to, w);
            Vec3 ax = cross(to);
            double al = ax.length_squared();
            if (al == 0.0) return lerp(to, w);
            ax = ax / Math.Sqrt(al);
            double l0 = Math.Sqrt(s0);
            double rl = l0 + (Math.Sqrt(s1) - l0) * w;
            double ang = angle_to(to);
            return rotated(ax, ang * w) * (rl / l0);
        }
    }

    public struct Vec2
    {
        public double x, y;
        public Vec2(double x, double y) { this.x = x; this.y = y; }
        public static readonly Vec2 ZERO = new Vec2(0, 0), UP = new Vec2(0, -1);   // (Godot Vector2.UP = (0, -1))
        public static Vec2 operator +(Vec2 a, Vec2 b) => new Vec2(a.x + b.x, a.y + b.y);
        public static Vec2 operator -(Vec2 a, Vec2 b) => new Vec2(a.x - b.x, a.y - b.y);
        public static Vec2 operator *(Vec2 a, double s) => new Vec2(a.x * s, a.y * s);
        public static Vec2 operator /(Vec2 a, double s) => new Vec2(a.x / s, a.y / s);
        public static bool operator ==(Vec2 a, Vec2 b) => a.x == b.x && a.y == b.y;
        public static bool operator !=(Vec2 a, Vec2 b) => !(a == b);
        public override bool Equals(object o) => o is Vec2 v && v == this;
        public override int GetHashCode() => x.GetHashCode() ^ (y.GetHashCode() << 2);
        public double dot(Vec2 b) => x * b.x + y * b.y;
        public double length() => Math.Sqrt(x * x + y * y);
        public Vec2 normalized() { double l = length(); return l == 0 ? ZERO : this / l; }
        public Vec2 move_toward(Vec2 to, double d)
        {
            Vec2 v = to - this; double l = v.length();
            return (l <= d || l < 1e-5) ? to : this + v / l * d;
        }
    }

    /// 3x3 basis, columns x / y / z (Godot semantics: Basis * v = x * v.x + y * v.y + z * v.z)
    public struct Basis
    {
        public Vec3 x, y, z;
        public Basis(Vec3 x, Vec3 y, Vec3 z) { this.x = x; this.y = y; this.z = z; }
        public static readonly Basis IDENTITY = new Basis(Vec3.RIGHT, Vec3.UP, Vec3.BACK);
        public static Vec3 operator *(Basis b, Vec3 v) => b.x * v.x + b.y * v.y + b.z * v.z;
        public static Basis operator *(Basis a, Basis b) => new Basis(a * b.x, a * b.y, a * b.z);
        public static bool operator ==(Basis a, Basis b) => a.x == b.x && a.y == b.y && a.z == b.z;
        public static bool operator !=(Basis a, Basis b) => !(a == b);
        public override bool Equals(object o) => o is Basis v && v == this;
        public override int GetHashCode() => x.GetHashCode() ^ y.GetHashCode() ^ z.GetHashCode();

        /// Godot Basis(axis, angle): right-handed rotation about a normalized axis
        public static Basis axis_angle(Vec3 a, double ang)
        {
            double c = Math.Cos(ang), s = Math.Sin(ang), t = 1.0 - c;
            double xx = a.x * a.x, yy = a.y * a.y, zz = a.z * a.z;
            double r00 = xx + c * (1.0 - xx), r11 = yy + c * (1.0 - yy), r22 = zz + c * (1.0 - zz);
            double r01 = a.x * a.y * t - a.z * s, r10 = a.x * a.y * t + a.z * s;
            double r02 = a.x * a.z * t + a.y * s, r20 = a.x * a.z * t - a.y * s;
            double r12 = a.y * a.z * t - a.x * s, r21 = a.y * a.z * t + a.x * s;
            return new Basis(new Vec3(r00, r10, r20), new Vec3(r01, r11, r21), new Vec3(r02, r12, r22));
        }
        public static Basis from_quat(Quat q)
        {
            double d = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
            double s = 2.0 / d;
            double xs = q.x * s, ys = q.y * s, zs = q.z * s;
            double wx = q.w * xs, wy = q.w * ys, wz = q.w * zs;
            double xx = q.x * xs, xy = q.x * ys, xz = q.x * zs;
            double yy = q.y * ys, yz = q.y * zs, zz = q.z * zs;
            // rows: (1-(yy+zz), xy-wz, xz+wy), (xy+wz, 1-(xx+zz), yz-wx), (xz-wy, yz+wx, 1-(xx+yy))
            return new Basis(new Vec3(1.0 - (yy + zz), xy + wz, xz - wy), new Vec3(xy - wz, 1.0 - (xx + zz), yz + wx), new Vec3(xz + wy, yz - wx, 1.0 - (xx + yy)));
        }
        /// Godot Basis(Vector3.RIGHT, x) * Basis(Vector3.UP, y) * Basis(Vector3.BACK, z) (RiderGear.euler_xyz)
        public static Basis euler_xyz(double ex, double ey, double ez) => axis_angle(Vec3.RIGHT, ex) * axis_angle(Vec3.UP, ey) * axis_angle(Vec3.BACK, ez);

        public double determinant() => x.dot(y.cross(z));
        public Basis transposed() => new Basis(new Vec3(x.x, y.x, z.x), new Vec3(x.y, y.y, z.y), new Vec3(x.z, y.z, z.z));
        public Basis inverse()
        {
            // cofactor inverse (general 3x3)
            double det = determinant();
            if (Math.Abs(det) < 1e-30) return IDENTITY;
            Vec3 r0 = y.cross(z) / det, r1 = z.cross(x) / det, r2 = x.cross(y) / det;   // rows of the inverse
            return new Basis(new Vec3(r0.x, r1.x, r2.x), new Vec3(r0.y, r1.y, r2.y), new Vec3(r0.z, r1.z, r2.z));
        }
        /// Godot orthonormalized: Gram-Schmidt on x, y, z
        public Basis orthonormalized()
        {
            Vec3 a = x.normalized();
            Vec3 b = (y - a * a.dot(y)).normalized();
            Vec3 c = (z - a * a.dot(z) - b * b.dot(z)).normalized();
            return new Basis(a, b, c);
        }
        /// a basis scaled along its own local y (Godot scaled_local(Vector3(1, s, 1)))
        public Basis scaled_y(double s) => new Basis(x, y * s, z);
        public Quat get_rotation_quaternion() => Quat.from_basis(orthonormalized());
    }

    public struct Quat
    {
        public double x, y, z, w;
        public Quat(double x, double y, double z, double w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        public static readonly Quat IDENTITY = new Quat(0, 0, 0, 1);
        public static Quat operator *(Quat a, Quat b) => new Quat(
            a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
            a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
            a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);
        public double dot(Quat b) => x * b.x + y * b.y + z * b.z + w * b.w;
        public double length() => Math.Sqrt(dot(this));
        public Quat normalized() { double l = length(); return l == 0 ? IDENTITY : new Quat(x / l, y / l, z / l, w / l); }
        public static Quat axis_angle(Vec3 a, double ang)
        {
            double s = Math.Sin(ang * 0.5);
            return new Quat(a.x * s, a.y * s, a.z * s, Math.Cos(ang * 0.5));
        }
        /// Godot Quaternion(from, to): the shortest arc between two unit vectors
        public static Quat arc(Vec3 v0, Vec3 v1)
        {
            Vec3 c = v0.cross(v1);
            double d = v0.dot(v1);
            if (d < -1.0 + 1e-5 || c.length_squared() < 1e-10)
            {
                if (d > 0) return IDENTITY;
                // any perpendicular axis, half a turn
                Vec3 ax = Math.Abs(v0.x) <= Math.Abs(v0.y) && Math.Abs(v0.x) <= Math.Abs(v0.z) ? v0.cross(Vec3.RIGHT)
                    : (Math.Abs(v0.y) <= Math.Abs(v0.z) ? v0.cross(Vec3.UP) : v0.cross(Vec3.BACK));
                ax = ax.normalized();
                return new Quat(ax.x, ax.y, ax.z, 0);
            }
            double s = Math.Sqrt((1.0 + d) * 2.0), rs = 1.0 / s;
            return new Quat(c.x * rs, c.y * rs, c.z * rs, s * 0.5);
        }
        public static Quat from_basis(Basis b)
        {
            // rows m[r][c] = column c element r
            double m00 = b.x.x, m11 = b.y.y, m22 = b.z.z;
            double tr = m00 + m11 + m22;
            if (tr > 0.0)
            {
                double s = Math.Sqrt(tr + 1.0) * 2.0;
                return new Quat((b.y.z - b.z.y) / s, (b.z.x - b.x.z) / s, (b.x.y - b.y.x) / s, 0.25 * s);
            }
            if (m00 > m11 && m00 > m22)
            {
                double s = Math.Sqrt(1.0 + m00 - m11 - m22) * 2.0;
                return new Quat(0.25 * s, (b.y.x + b.x.y) / s, (b.z.x + b.x.z) / s, (b.y.z - b.z.y) / s);
            }
            if (m11 > m22)
            {
                double s = Math.Sqrt(1.0 + m11 - m00 - m22) * 2.0;
                return new Quat((b.y.x + b.x.y) / s, 0.25 * s, (b.z.y + b.y.z) / s, (b.z.x - b.x.z) / s);
            }
            {
                double s = Math.Sqrt(1.0 + m22 - m00 - m11) * 2.0;
                return new Quat((b.z.x + b.x.z) / s, (b.z.y + b.y.z) / s, 0.25 * s, (b.x.y - b.y.x) / s);
            }
        }
        /// Godot Quaternion.slerp (shortest way)
        public Quat slerp(Quat to, double t)
        {
            double c = dot(to);
            Quat t1 = to;
            if (c < 0) { c = -c; t1 = new Quat(-to.x, -to.y, -to.z, -to.w); }
            double s0, s1;
            if (1.0 - c > 1e-5)
            {
                double om = Math.Acos(c), sn = Math.Sin(om);
                s0 = Math.Sin((1.0 - t) * om) / sn; s1 = Math.Sin(t * om) / sn;
            }
            else { s0 = 1.0 - t; s1 = t; }
            return new Quat(s0 * x + s1 * t1.x, s0 * y + s1 * t1.y, s0 * z + s1 * t1.z, s0 * w + s1 * t1.w);
        }
    }

    /// a transform: basis + origin (Godot Transform3D). Xf * v = b * v + o
    public struct Xf
    {
        public Basis b; public Vec3 o;
        public Xf(Basis b, Vec3 o) { this.b = b; this.o = o; }
        public static readonly Xf IDENTITY = new Xf(Basis.IDENTITY, Vec3.ZERO);
        public static Vec3 operator *(Xf t, Vec3 v) => t.b * v + t.o;
        public static Xf operator *(Xf a, Xf c) => new Xf(a.b * c.b, a.b * c.o + a.o);
        public Xf affine_inverse() { Basis bi = b.inverse(); return new Xf(bi, -(bi * o)); }
    }

    /// the pose inputs, Godot's `p` dictionary: values double, bool, Vec3 or null (and "pk": a Dictionary<string, double>)
    public sealed class PoseInput : Dictionary<string, object>
    {
        public PoseInput() { }
        public PoseInput(PoseInput o) : base(o) { }
        public object get(string k) => TryGetValue(k, out var v) ? v : null;
        public Vec3 vec(string k, Vec3 d) => TryGetValue(k, out var v) && v is Vec3 x ? x : d;
        public bool has(string k) => ContainsKey(k);
    }
}
