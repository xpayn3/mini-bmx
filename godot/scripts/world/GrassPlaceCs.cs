using System;
using System.Collections.Generic;
using Godot;

/// The grass field's per-frame tile placement (world/grass_field.gd `_place` + `_tile_range`), in C#: in GDScript it
/// tested ~950 tiles a frame (near + mid ring) against the view, ~0.6 ms (frame profiler node probe, 2026-11-24).
/// Same logic, same order. grass_field.gd hands it the height window when that changes (SetHeights) and per ring
/// calls Place(); the instance buffer only comes back (Buf) when the visible tiles changed.
public partial class GrassPlaceCs : RefCounted
{
	private float[] _h = Array.Empty<float>();
	private int _tex;
	private float _wx, _wz, _tx;
	private readonly Dictionary<long, Vector2>[] _hcache = { new(), new() };
	private readonly float[][] _buf = { Array.Empty<float>(), Array.Empty<float>() };
	private readonly float[][] _prev = { Array.Empty<float>(), Array.Empty<float>() };
	private readonly int[] _prevCount = { -1, -1 };

	/// the height window (TEX x TEX floats, -1000 = no data) and where its texel (0, 0) sits
	public void SetHeights(float[] h, int tex, float wx, float wz, float tx)
	{
		_h = h; _tex = tex; _wx = wx; _wz = wz; _tx = tx;
		_hcache[0].Clear(); _hcache[1].Clear();
	}

	private Vector2 TileRange(float ox, float oz, float tile)
	{
		float lo = float.PositiveInfinity, hi = float.NegativeInfinity;
		for (int j = 0; j < 3; j++)
			for (int i = 0; i < 3; i++)
			{
				int px = Math.Clamp((int)Math.Round((ox + tile * 0.5 * i - _wx) / _tx, MidpointRounding.AwayFromZero), 0, _tex - 1);
				int pz = Math.Clamp((int)Math.Round((oz + tile * 0.5 * j - _wz) / _tx, MidpointRounding.AwayFromZero), 0, _tex - 1);
				float v = _h[pz * _tex + px];
				if (v < -900f) continue;
				lo = Math.Min(lo, v); hi = Math.Max(hi, v);
			}
		if (lo > hi) return new Vector2(1f, 0f);
		return new Vector2(lo - 3f, hi + 3f);
	}

	/// ring k (0 near, 1 mid): fills its buffer with the tiles that reach r0..r1 and touch the view. planes = the camera
	/// frustum as (nx, ny, nz, d) x 6. Returns the count; Changed(k) says whether the buffer differs from last time.
	public int Place(int k, Vector3 cp, float[] planes, float tile, float r0, float r1, float ring, float ground, bool groundNan)
	{
		int n = (int)Math.Ceiling(r1 / tile) + 1;
		int cap = (2 * n + 1) * (2 * n + 1);
		if (_buf[k].Length != cap * 16) _buf[k] = new float[cap * 16];
		var buf = _buf[k];
		long tx0 = (long)Math.Floor(cp.X / tile), tz0 = (long)Math.Floor(cp.Z / tile);
		float hy = groundNan ? cp.Y : ground;
		int c = 0;
		float half = tile * 0.5f, rad = half * 1.4143f, ex = half + 1.0f;
		bool haveH = _h.Length == _tex * _tex && _tex > 0;
		var hcache = _hcache[k];
		int np = planes.Length / 4;
		for (long dz = -n; dz <= n; dz++)
			for (long dx = -n; dx <= n; dx++)
			{
				float ox = (tx0 + dx) * tile, oz = (tz0 + dz) * tile;
				float mx = ox + half, mz = oz + half;
				float ddx = mx - cp.X, ddz = mz - cp.Z;
				float dd = MathF.Sqrt(ddx * ddx + ddz * ddz);
				if (dd - rad > r1 || dd + rad < r0) continue;
				bool inside = true;
				if (haveH)
				{
					long key = ((tx0 + dx) << 32) ^ ((tz0 + dz) & 0xffffffffL);
					if (!hcache.TryGetValue(key, out Vector2 hr)) { hr = TileRange(ox, oz, tile); hcache[key] = hr; }
					if (hr.X > hr.Y) continue;
					float cy = (hr.X + hr.Y) * 0.5f + 0.5f, ey = (hr.Y - hr.X) * 0.5f + 1.5f;
					for (int p = 0; p < np; p++)
					{
						float nx = planes[4 * p], ny = planes[4 * p + 1], nz = planes[4 * p + 2], d = planes[4 * p + 3];
						float r = Math.Abs(nx) * ex + Math.Abs(ny) * ey + Math.Abs(nz) * ex;
						if (nx * mx + ny * cy + nz * mz - d > r) { inside = false; break; }
					}
				}
				else
				{
					float r = rad + 30f;
					for (int p = 0; p < np; p++)
					{
						float nx = planes[4 * p], ny = planes[4 * p + 1], nz = planes[4 * p + 2], d = planes[4 * p + 3];
						if (nx * mx + ny * hy + nz * mz - d > r) { inside = false; break; }
					}
				}
				if (!inside) continue;
				int b = c * 16;
				buf[b] = 1f; buf[b + 1] = 0f; buf[b + 2] = 0f; buf[b + 3] = ox;
				buf[b + 4] = 0f; buf[b + 5] = 1f; buf[b + 6] = 0f; buf[b + 7] = 0f;
				buf[b + 8] = 0f; buf[b + 9] = 0f; buf[b + 10] = 1f; buf[b + 11] = oz;
				buf[b + 12] = ring; buf[b + 13] = 0f; buf[b + 14] = 0f; buf[b + 15] = 0f;
				c++;
			}
		// same tiles as last frame: nothing to hand back / upload
		bool changed = c != _prevCount[k] || _prev[k].Length != buf.Length;
		if (!changed)
			for (int i = 0; i < c * 16; i++)
				if (_prev[k][i] != buf[i]) { changed = true; break; }
		if (changed)
		{
			if (_prev[k].Length != buf.Length) _prev[k] = new float[buf.Length];
			Array.Copy(buf, _prev[k], buf.Length);
			_prevCount[k] = c;
			_changed[k] = true;
		}
		else _changed[k] = false;
		return c;
	}

	private readonly bool[] _changed = { false, false };
	public bool Changed(int k) => _changed[k];
	public float[] Buf(int k) => _buf[k];
}
