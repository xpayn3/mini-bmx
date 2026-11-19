using Godot;
using System;

/// Splat textures for the blood Decals (fx/blood.gd): a few merged lobes of random size and place, the
/// outline warped by noise (never a circle), thicker (darker) in the middle, a few droplets thrown just
/// outside it. RGBA8, colour in sRGB, alpha = coverage with a soft 1-2 px edge.
public partial class BloodSplatTex : RefCounted
{
	static float Hash(float x, float z)
	{
		float s = MathF.Sin(x * 127.1f + z * 311.7f) * 43758.5453f;
		return s - MathF.Floor(s);
	}

	static float Vn(float x, float z)
	{
		float ix = MathF.Floor(x), iz = MathF.Floor(z);
		float fx = x - ix, fz = z - iz;
		fx = fx * fx * (3 - 2 * fx);
		fz = fz * fz * (3 - 2 * fz);
		float a = Hash(ix, iz), b = Hash(ix + 1, iz), c = Hash(ix, iz + 1), d = Hash(ix + 1, iz + 1);
		return (a + (b - a) * fx) * (1 - fz) + (c + (d - c) * fx) * fz;
	}

	public Image Make(int seed, int n)
	{
		var rng = new Random(seed);
		int lobes = 3 + rng.Next(3);
		var lx = new float[lobes]; var lz = new float[lobes]; var lr = new float[lobes];
		for (int k = 0; k < lobes; k++)
		{
			float ang = (float)rng.NextDouble() * MathF.Tau;
			float dist = k == 0 ? 0f : 0.12f + 0.3f * (float)rng.NextDouble();
			lx[k] = MathF.Cos(ang) * dist;
			lz[k] = MathF.Sin(ang) * dist;
			lr[k] = (k == 0 ? 0.22f : 0.08f + 0.12f * (float)rng.NextDouble());
		}
		// droplets just outside
		int drops = 6 + rng.Next(10);
		var dx = new float[drops]; var dz = new float[drops]; var dr = new float[drops];
		for (int k = 0; k < drops; k++)
		{
			float ang = (float)rng.NextDouble() * MathF.Tau;
			float dist = 0.5f + 0.4f * (float)rng.NextDouble();
			dx[k] = MathF.Cos(ang) * dist;
			dz[k] = MathF.Sin(ang) * dist;
			dr[k] = 0.012f + 0.03f * (float)rng.NextDouble();
		}
		float sd = seed * 3.7f;
		var bytes = new byte[n * n * 4];
		float px = 2f / n;   // one pixel in the -1..1 square
		for (int j = 0; j < n; j++)
		{
			for (int i = 0; i < n; i++)
			{
				float u = (i + 0.5f) / n * 2f - 1f;
				float v = (j + 0.5f) / n * 2f - 1f;
				// warp the shape
				float wu = u + (Vn(u * 2.3f + sd, v * 2.3f) - 0.5f) * 0.35f + (Vn(u * 7f, v * 7f - sd) - 0.5f) * 0.08f;
				float wv = v + (Vn(u * 2.3f, v * 2.3f + sd + 5f) - 0.5f) * 0.35f + (Vn(u * 7f + sd, v * 7f) - 0.5f) * 0.08f;
				float f = 0;
				for (int k = 0; k < lobes; k++)
				{
					float ddx = wu - lx[k], ddz = wv - lz[k];
					f += lr[k] * lr[k] / (ddx * ddx + ddz * ddz + 1e-4f);
				}
				// coverage: the field's 1-level, softened over ~1.5 px (its slope there ~ 2/r)
				float a = Math.Clamp((f - 1f) / (px * 12f) + 0.5f, 0f, 1f);
				for (int k = 0; k < drops; k++)
				{
					float d = MathF.Sqrt((u - dx[k]) * (u - dx[k]) + (v - dz[k]) * (v - dz[k])) - dr[k];
					a = MathF.Max(a, Math.Clamp(0.5f - d / (px * 1.5f), 0f, 1f));
				}
				// fade out before the square's border
				float r = MathF.Sqrt(u * u + v * v);
				a *= Math.Clamp((1f - r) / 0.05f, 0f, 1f);
				float thick = Math.Clamp((f - 1f) / 2.5f, 0f, 1f);
				// sRGB: thin = a brighter red, pooled = deep dark red
				float cr = 0.42f + (0.17f - 0.42f) * thick;
				float cg = 0.035f + (0.005f - 0.035f) * thick;
				float cb = 0.025f + (0.004f - 0.025f) * thick;
				int o = (i + j * n) * 4;
				bytes[o] = (byte)(cr * 255f);
				bytes[o + 1] = (byte)(cg * 255f);
				bytes[o + 2] = (byte)(cb * 255f);
				bytes[o + 3] = (byte)(a * 255f);
			}
		}
		var img = Image.CreateFromData(n, n, false, Image.Format.Rgba8, bytes);
		img.GenerateMipmaps();
		return img;
	}
}
