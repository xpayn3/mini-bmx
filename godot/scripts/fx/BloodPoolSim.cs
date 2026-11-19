using Godot;
using System;

/// A small shallow-liquid simulation for a pool of blood (fx/blood_pool.gd). An N x N grid of CELL-sized
/// cells over the ground: each cell has a ground height (the real terrain, sampled coarsely by GDScript
/// and interpolated here, + small random bumps) and a blood depth. Every iteration each wet cell passes
/// blood to its lower neighbours in proportion to the difference of the liquid SURFACE (ground + depth),
/// but a cell keeps a thin film (its retention, a little random per cell): so the pool runs downhill,
/// fills dips first, spreads round on the flat with an uneven fingered edge, and stops by itself once
/// the front has thinned to that film. Blood is added at a source cell (a pour that slows down).
/// Only the wet box (+1 cell) is iterated. Output: the depths as an Rf image for the shader.
public partial class BloodPoolSim : RefCounted
{
	int _n;
	float _cell;
	float[] _g;      // ground height (m)
	float[] _d;      // blood depth (m)
	float[] _ret;    // the film each cell keeps (m)
	float[] _out;    // scratch: outflow per cell this iteration
	int _x0, _x1, _z0, _z1;   // wet box
	byte[] _bytes;

	/// ground: (gn x gn) heights sampled over the same square (corners included), interpolated
	public void Setup(int n, float cell, float[] ground, int gn, float seed)
	{
		_n = n;
		_cell = cell;
		_g = new float[n * n];
		_d = new float[n * n];
		_ret = new float[n * n];
		_out = new float[n * n];
		_bytes = new byte[n * n * 4];
		var rng = new Random((int)(seed * 1000.0f));
		for (int z = 0; z < n; z++)
		{
			for (int x = 0; x < n; x++)
			{
				float u = (x + 0.5f) / n * (gn - 1);
				float v = (z + 0.5f) / n * (gn - 1);
				int iu = Math.Min((int)u, gn - 2), iv = Math.Min((int)v, gn - 2);
				float fu = u - iu, fv = v - iv;
				float a = ground[iu + iv * gn], b = ground[iu + 1 + iv * gn];
				float c = ground[iu + (iv + 1) * gn], d = ground[iu + 1 + (iv + 1) * gn];
				float h = (a + (b - a) * fu) * (1 - fv) + (c + (d - c) * fu) * fv;
				float wx = x * cell, wz = z * cell;
				// bumps: a few millimetres at 40 cm / 12 cm / 4 cm, so the edge fingers out unevenly
				h += 0.003f * Vn(wx * 2.5f + seed, wz * 2.5f) + 0.0018f * Vn(wx * 8f - seed, wz * 8f) + 0.0008f * Vn(wx * 25f, wz * 25f + seed);
				_g[x + z * n] = h;
				_ret[x + z * n] = 0.0028f + 0.0018f * Vn(wx * 6f + seed * 2f, wz * 6f) + 0.0005f * (float)rng.NextDouble();   // blood is thick: it holds a film of ~3-5 mm
			}
		}
		_x0 = _z0 = n / 2;
		_x1 = _z1 = n / 2;
	}

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

	/// pour `vol` m^3 in at cell (sx, sz) (spread over a small disc), then run `iters` flow iterations
	public void Step(float vol, int sx, int sz, int iters)
	{
		int n = _n;
		if (vol > 0)
		{
			// a 5x5 disc round the source
			float per = vol / (_cell * _cell) / 21f;
			for (int dz = -2; dz <= 2; dz++)
				for (int dx = -2; dx <= 2; dx++)
				{
					if (dx * dx + dz * dz > 5) continue;
					int x = sx + dx, z = sz + dz;
					if (x < 1 || z < 1 || x >= n - 1 || z >= n - 1) continue;
					_d[x + z * n] += per;
					Grow(x, z);
				}
		}
		const float K = 0.22f;   // share of the surface difference that moves per iteration (stable < 0.25)
		for (int it = 0; it < iters; it++)
		{
			int x0 = Math.Max(1, _x0 - 1), x1 = Math.Min(n - 2, _x1 + 1);
			int z0 = Math.Max(1, _z0 - 1), z1 = Math.Min(n - 2, _z1 + 1);
			// 1) outflows: to each lower neighbour by the surface difference, limited to what's above the film
			for (int z = z0; z <= z1; z++)
			{
				for (int x = x0; x <= x1; x++)
				{
					int i = x + z * n;
					_out[i] = 0;
					float d = _d[i];
					float free = d - _ret[i];
					if (free <= 0) continue;
					float s = _g[i] + d;
					float f0 = Math.Max(0, s - (_g[i - 1] + _d[i - 1]));
					float f1 = Math.Max(0, s - (_g[i + 1] + _d[i + 1]));
					float f2 = Math.Max(0, s - (_g[i - n] + _d[i - n]));
					float f3 = Math.Max(0, s - (_g[i + n] + _d[i + n]));
					float tot = (f0 + f1 + f2 + f3) * K;
					if (tot <= 1e-9f) continue;
					_out[i] = Math.Min(1f, free / tot);   // scale so it never gives away its film
				}
			}
			// 2) move it (each cell gives, neighbours take), keeping the total exactly
			for (int z = z0; z <= z1; z++)
			{
				for (int x = x0; x <= x1; x++)
				{
					int i = x + z * n;
					float sc = _out[i];
					if (sc <= 0) continue;
					float s = _g[i] + _d[i];
					for (int k = 0; k < 4; k++)
					{
						int j = k == 0 ? i - 1 : k == 1 ? i + 1 : k == 2 ? i - n : i + n;
						float f = (s - (_g[j] + _d[j])) * K * sc;
						if (f <= 0) continue;
						_d[i] -= f;
						_d[j] += f;
						if (_d[j] > 1e-5f) Grow(j % n, j / n);
					}
				}
			}
			// 3) a thin film soaks into the dirt (the running front slows and stops, as on real soil; a
			//    thick pool stays); whatever still reaches the border drains away (no pile-up line there)
			for (int z = z0; z <= z1; z++)
			{
				for (int x = x0; x <= x1; x++)
				{
					int i = x + z * n;
					float d = _d[i];
					if (d > 0 && d < SOAK_BELOW) _d[i] = Math.Max(0f, d - SOAK);
				}
			}
			for (int k = 0; k < n; k++)
			{
				_d[k] = 0; _d[k + (n - 1) * n] = 0; _d[k * n] = 0; _d[k * n + n - 1] = 0;
			}
		}
	}

	const float SOAK = 6e-7f;          // m per iteration (~0.2 mm/s at 6 iterations a frame)
	const float SOAK_BELOW = 0.0045f;  // only a film thinner than this soaks in

	void Grow(int x, int z)
	{
		if (x < _x0) _x0 = x;
		if (x > _x1) _x1 = x;
		if (z < _z0) _z0 = z;
		if (z > _z1) _z1 = z;
	}

	/// true when the wet box touches the grid's edge (it would be cut off there)
	public bool AtEdge() => _x0 <= 1 || _z0 <= 1 || _x1 >= _n - 2 || _z1 >= _n - 2;

	/// the depths (m) as a single-channel float image
	public Image MakeImage()
	{
		Buffer.BlockCopy(_d, 0, _bytes, 0, _bytes.Length);
		return Image.CreateFromData(_n, _n, false, Image.Format.Rf, _bytes);
	}

	/// blood depth (m) at grid cell (x, z); 0 outside
	public float DepthAt(int x, int z)
	{
		if (x < 0 || z < 0 || x >= _n || z >= _n) return 0f;
		return _d[x + z * _n];
	}

	public float Volume()
	{
		double v = 0;
		for (int i = 0; i < _d.Length; i++) v += _d[i];
		return (float)(v * _cell * _cell);
	}
}
