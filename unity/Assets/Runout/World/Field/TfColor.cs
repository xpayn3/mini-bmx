namespace Runout.World
{
	/// Godot's Color, engine-free: four float32 channels, linear. The field's colour maths (clerp / cmul) round
	/// through float exactly like Godot's Color::lerp and Color * float.
	public struct TfColor
	{
		public float R, G, B, A;

		public TfColor(float r, float g, float b, float a = 1f) { R = r; G = g; B = b; A = a; }
		public TfColor(double r, double g, double b, double a = 1.0) { R = (float)r; G = (float)g; B = (float)b; A = (float)a; }

		public override string ToString() => $"({R}, {G}, {B}, {A})";
	}
}
