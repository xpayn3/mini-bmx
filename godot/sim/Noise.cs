// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
using System;

namespace Runout.Sim
{
	/// <summary>
	/// The part of FastNoiseLite (Copyright (c) 2023 Jordan Peck and Contributors, MIT licence) the ride uses: 2D OpenSimplex2S ("simplex smooth"), FBm fractal,
	/// in 32-bit floats like Godot's FastNoiseLite resource, so the same seed / frequency / octaves give the same numbers
	/// (checked by tools/sim_rng_probe.gd).
	/// </summary>
	public sealed class Noise2S
	{
		private const int PRIME_X = 501125321;
		private const int PRIME_Y = 1136930381;
		private const float SQRT3 = 1.7320508075688772935274463415059f;
		private const float G2 = (3 - SQRT3) / 6;
		private const float F2 = 0.5f * (SQRT3 - 1);
		private static readonly float[] GRAD = MakeGradients();

		public const int TYPE_SIMPLEX_SMOOTH = 1;
		public int Seed;
		public float Frequency = 0.01f;
		private int _octaves = 5;
		public float Lacunarity = 2.0f;
		public float Gain = 0.5f;
		private float _bounding;

		public int Octaves
		{
			get => _octaves;
			set { _octaves = value; Bound(); }
		}

		public Noise2S() { Bound(); }

		public Noise2S(int seed, float frequency, int octaves)
		{
			Seed = seed; Frequency = frequency; Octaves = octaves;
		}

		private void Bound()
		{
			float gain = Math.Abs(Gain), amp = gain, ampFractal = 1.0f;
			for (int i = 1; i < _octaves; i++)
			{
				ampFractal += amp;
				amp *= gain;
			}
			_bounding = 1 / ampFractal;
		}

		// GDScript's FastNoiseLite names (the ported ride sets them like bike_physics.gd does)
		public int noise_type { get => TYPE_SIMPLEX_SMOOTH; set { } }
		public double frequency { get => Frequency; set => Frequency = (float)value; }
		public long fractal_octaves { get => Octaves; set => Octaves = (int)value; }
		public long seed { get => Seed; set => Seed = (int)value; }
		public double get_noise_2d(double x, double y) => Get((float)x, (float)y);

		/// FastNoiseLite's Gradients2D: the 24-direction block (literals as in its source) five times, then 8 diagonals
		private static float[] MakeGradients()
		{
			float[] block =
			{
				0.130526192220052f, 0.99144486137381f, 0.38268343236509f, 0.923879532511287f, 0.608761429008721f, 0.793353340291235f, 0.793353340291235f, 0.608761429008721f,
				0.923879532511287f, 0.38268343236509f, 0.99144486137381f, 0.130526192220051f, 0.99144486137381f, -0.130526192220051f, 0.923879532511287f, -0.38268343236509f,
				0.793353340291235f, -0.60876142900872f, 0.608761429008721f, -0.793353340291235f, 0.38268343236509f, -0.923879532511287f, 0.130526192220052f, -0.99144486137381f,
				-0.130526192220052f, -0.99144486137381f, -0.38268343236509f, -0.923879532511287f, -0.608761429008721f, -0.793353340291235f, -0.793353340291235f, -0.608761429008721f,
				-0.923879532511287f, -0.38268343236509f, -0.99144486137381f, -0.130526192220052f, -0.99144486137381f, 0.130526192220051f, -0.923879532511287f, 0.38268343236509f,
				-0.793353340291235f, 0.608761429008721f, -0.608761429008721f, 0.793353340291235f, -0.38268343236509f, 0.923879532511287f, -0.130526192220052f, 0.99144486137381f,
			};
			float[] tail =
			{
				0.38268343236509f, 0.923879532511287f, 0.923879532511287f, 0.38268343236509f, 0.923879532511287f, -0.38268343236509f, 0.38268343236509f, -0.923879532511287f,
				-0.38268343236509f, -0.923879532511287f, -0.923879532511287f, -0.38268343236509f, -0.923879532511287f, 0.38268343236509f, -0.38268343236509f, 0.923879532511287f,
			};
			var g = new float[256];
			for (int r = 0; r < 5; r++)
				Array.Copy(block, 0, g, r * 48, 48);
			Array.Copy(tail, 0, g, 240, 16);
			return g;
		}

		/// Godot's get_noise_2d(x, y)
		public float Get(float x, float y)
		{
			x *= Frequency;
			y *= Frequency;
			float t = (x + y) * F2;
			x += t;
			y += t;
			int seed = Seed;
			float sum = 0, amp = _bounding;
			for (int i = 0; i < Octaves; i++)
			{
				float noise = Single(seed++, x, y);
				sum += noise * amp;
				x *= Lacunarity;
				y *= Lacunarity;
				amp *= Gain;
			}
			return sum;
		}

		private static int FastFloor(float f) => f >= 0 ? (int)f : (int)f - 1;

		private static float GradCoord(int seed, int xPrimed, int yPrimed, float xd, float yd)
		{
			int hash = unchecked((seed ^ xPrimed ^ yPrimed) * 0x27d4eb2d);
			hash ^= hash >> 15;
			hash &= 127 << 1;
			return xd * GRAD[hash] + yd * GRAD[hash | 1];
		}

		private static float Single(int seed, float x, float y)
		{
			unchecked
			{
				int i = FastFloor(x);
				int j = FastFloor(y);
				float xi = (float)(x - i);
				float yi = (float)(y - j);
				i *= PRIME_X;
				j *= PRIME_Y;
				int i1 = i + PRIME_X;
				int j1 = j + PRIME_Y;

				float t = (xi + yi) * G2;
				float x0 = xi - t;
				float y0 = yi - t;

				float a0 = (2.0f / 3.0f) - x0 * x0 - y0 * y0;
				float value = (a0 * a0) * (a0 * a0) * GradCoord(seed, i, j, x0, y0);

				float a1 = (2 * (1 - 2 * G2) * (1 / G2 - 2)) * t + ((-2 * (1 - 2 * G2) * (1 - 2 * G2)) + a0);
				float x1 = x0 - (1 - 2 * G2);
				float y1 = y0 - (1 - 2 * G2);
				value += (a1 * a1) * (a1 * a1) * GradCoord(seed, i1, j1, x1, y1);

				float xmyi = xi - yi;
				if (t > G2)
				{
					if (xi + xmyi > 1)
					{
						float x2 = x0 + (3 * G2 - 2), y2 = y0 + (3 * G2 - 1);
						float a2 = (2.0f / 3.0f) - x2 * x2 - y2 * y2;
						if (a2 > 0) value += (a2 * a2) * (a2 * a2) * GradCoord(seed, i + (PRIME_X << 1), j + PRIME_Y, x2, y2);
					}
					else
					{
						float x2 = x0 + G2, y2 = y0 + (G2 - 1);
						float a2 = (2.0f / 3.0f) - x2 * x2 - y2 * y2;
						if (a2 > 0) value += (a2 * a2) * (a2 * a2) * GradCoord(seed, i, j + PRIME_Y, x2, y2);
					}
					if (yi - xmyi > 1)
					{
						float x3 = x0 + (3 * G2 - 1), y3 = y0 + (3 * G2 - 2);
						float a3 = (2.0f / 3.0f) - x3 * x3 - y3 * y3;
						if (a3 > 0) value += (a3 * a3) * (a3 * a3) * GradCoord(seed, i + PRIME_X, j + (PRIME_Y << 1), x3, y3);
					}
					else
					{
						float x3 = x0 + (G2 - 1), y3 = y0 + G2;
						float a3 = (2.0f / 3.0f) - x3 * x3 - y3 * y3;
						if (a3 > 0) value += (a3 * a3) * (a3 * a3) * GradCoord(seed, i + PRIME_X, j, x3, y3);
					}
				}
				else
				{
					if (xi + xmyi < 0)
					{
						float x2 = x0 + (1 - G2), y2 = y0 - G2;
						float a2 = (2.0f / 3.0f) - x2 * x2 - y2 * y2;
						if (a2 > 0) value += (a2 * a2) * (a2 * a2) * GradCoord(seed, i - PRIME_X, j, x2, y2);
					}
					else
					{
						float x2 = x0 + (G2 - 1), y2 = y0 + G2;
						float a2 = (2.0f / 3.0f) - x2 * x2 - y2 * y2;
						if (a2 > 0) value += (a2 * a2) * (a2 * a2) * GradCoord(seed, i + PRIME_X, j, x2, y2);
					}
					if (yi < xmyi)
					{
						float x2 = x0 - G2, y2 = y0 - (G2 - 1);
						float a2 = (2.0f / 3.0f) - x2 * x2 - y2 * y2;
						if (a2 > 0) value += (a2 * a2) * (a2 * a2) * GradCoord(seed, i, j - PRIME_Y, x2, y2);
					}
					else
					{
						float x2 = x0 + G2, y2 = y0 + (G2 - 1);
						float a2 = (2.0f / 3.0f) - x2 * x2 - y2 * y2;
						if (a2 > 0) value += (a2 * a2) * (a2 * a2) * GradCoord(seed, i, j + PRIME_Y, x2, y2);
					}
				}
				return value * 18.24196194486065f;
			}
		}
	}
}
