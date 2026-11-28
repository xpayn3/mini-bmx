namespace Runout.World
{
	/// plain float vectors for mesh data the field builds (Godot's Vector3 / Vector2 layout: X, Y, Z floats)
	public struct Vec3
	{
		public float X, Y, Z;
		public Vec3(float x, float y, float z) { X = x; Y = y; Z = z; }
		// Godot's Vector3 arithmetic (float32)
		public static Vec3 operator +(Vec3 a, Vec3 b) => new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
		public static Vec3 operator -(Vec3 a, Vec3 b) => new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
		public static Vec3 operator *(Vec3 a, float s) => new Vec3(a.X * s, a.Y * s, a.Z * s);
		public static Vec3 operator *(float s, Vec3 a) => new Vec3(a.X * s, a.Y * s, a.Z * s);
		public float LengthSquared() => X * X + Y * Y + Z * Z;
		public Vec3 Normalized()
		{
			float l = LengthSquared();
			if (l == 0f) return new Vec3(0f, 0f, 0f);
			l = (float)System.Math.Sqrt(l);
			return new Vec3(X / l, Y / l, Z / l);
		}
	}

	public struct Vec2
	{
		public float X, Y;
		public Vec2(float x, float y) { X = x; Y = y; }
	}

	/// the ruts the tyres dig (the game's rut field): depth at a world point, m
	public interface IRutDepth
	{
		float Depth(float x, float z);
	}
}
