using System;
using System.Collections.Generic;
using Godot;

/// Ruts (2026-11-24): the ground dug in where tyres roll, deeper with every pass (MX vs ATV-style ruts). A sparse set of
/// TILE x TILE-cell tiles (CELL m each, made only where something rolled, oldest dropped past MAX_TILES), each cell a depth
/// in m (+ = dug in, - = the lip of dirt pushed up beside a groove). world/ruts.gd drives it: Stamp() per tyre per physics
/// tick, Depth() for every ground height the physics reads near the bike, Tile() for the ground shader.
/// Every point is dug once per pass: a tyre's stamp covers only the cells whose nearest point on its path is on this tick's
/// stretch (prev -> now, the start excluded), so standing still digs nothing and ticks don't double up.
public partial class RutFieldCs : RefCounted
{
	public const int TILE = 160;          // cells per tile side
	public const float CELL = 0.05f;      // m: a tile is 8 m
	public const int MAX_TILES = 256;     // ~26 MB at most: a ride keeps its ruts ~2 km back

	private readonly Dictionary<long, float[]> _tiles = new();
	private readonly LinkedList<long> _age = new();   // most recently dug last
	private readonly Dictionary<long, LinkedListNode<long>> _ageNode = new();
	private readonly HashSet<long> _dirty = new();
	private readonly Dictionary<int, Vector2> _last = new();   // wheel id -> last stamped point (x, z)
	private float _minX = float.PositiveInfinity, _minZ = float.PositiveInfinity, _maxX = float.NegativeInfinity, _maxZ = float.NegativeInfinity;

	private static long Key(int tx, int tz) => ((long)tx << 32) ^ (uint)tz;

	public void Clear()
	{
		_tiles.Clear(); _age.Clear(); _ageNode.Clear(); _dirty.Clear(); _last.Clear();
		_minX = _minZ = float.PositiveInfinity; _maxX = _maxZ = float.NegativeInfinity;
	}

	/// the area anything was dug in (x0, z0, x1, z1): outside it Depth is 0 without a call
	public Vector4 Bounds() => new Vector4(_minX, _minZ, _maxX, _maxZ);
	public int TileCount() => _tiles.Count;

	private float[] TileFor(int tx, int tz, bool make)
	{
		long k = Key(tx, tz);
		if (_tiles.TryGetValue(k, out var t))
		{
			if (make) { _age.Remove(_ageNode[k]); _ageNode[k] = _age.AddLast(k); }
			return t;
		}
		if (!make) return null;
		t = new float[TILE * TILE];
		_tiles[k] = t;
		_ageNode[k] = _age.AddLast(k);
		if (_tiles.Count > MAX_TILES)
		{
			long old = _age.First.Value;
			_age.RemoveFirst(); _ageNode.Remove(old); _tiles.Remove(old); _dirty.Remove(old);
		}
		float x0 = tx * TILE * CELL, z0 = tz * TILE * CELL, x1 = x0 + TILE * CELL, z1 = z0 + TILE * CELL;
		_minX = Math.Min(_minX, x0); _minZ = Math.Min(_minZ, z0); _maxX = Math.Max(_maxX, x1); _maxZ = Math.Max(_maxZ, z1);
		return t;
	}

	private float Cell(int ix, int iz)
	{
		int tx = (int)Math.Floor((double)ix / TILE), tz = (int)Math.Floor((double)iz / TILE);
		var t = TileFor(tx, tz, false);
		if (t == null) return 0f;
		return t[(iz - tz * TILE) * TILE + (ix - tx * TILE)];
	}

	/// how far the ground is dug in here (m, bilinear; - = a lip)
	public float Depth(float x, float z)
	{
		if (x < _minX || x > _maxX || z < _minZ || z > _maxZ) return 0f;
		float fx = x / CELL - 0.5f, fz = z / CELL - 0.5f;
		int ix = (int)Math.Floor(fx), iz = (int)Math.Floor(fz);
		float u = fx - ix, v = fz - iz;
		float a = Cell(ix, iz), b = Cell(ix + 1, iz), c = Cell(ix, iz + 1), d = Cell(ix + 1, iz + 1);
		return (a + (b - a) * u) + ((c + (d - c) * u) - (a + (b - a) * u)) * v;
	}

	/// a tyre (id) rolled to (x, z): dig its stretch since the last call. halfW = the groove's half width (m), add = depth
	/// this pass adds in its middle (m), maxD = how deep it can get here, lip = share of add pushed up beside it.
	/// jump > 1 m since the last call (respawn, reset) = a new start, nothing dug.
	public void Stamp(int id, float x, float z, float halfW, float add, float maxD, float lip)
	{
		var p = new Vector2(x, z);
		if (!_last.TryGetValue(id, out var a) || a.DistanceTo(p) > 1.0f) { _last[id] = p; return; }
		Vector2 seg = p - a;
		float len = seg.Length();
		if (len < 0.01f) return;   // (not moved: no digging, the start stays where it was)
		_last[id] = p;
		Vector2 dir = seg / len;
		float lipW = halfW * 0.7f;
		float reach = halfW + lipW;
		int ix0 = (int)Math.Floor((Math.Min(a.X, p.X) - reach) / CELL), ix1 = (int)Math.Floor((Math.Max(a.X, p.X) + reach) / CELL);
		int iz0 = (int)Math.Floor((Math.Min(a.Y, p.Y) - reach) / CELL), iz1 = (int)Math.Floor((Math.Max(a.Y, p.Y) + reach) / CELL);
		for (int iz = iz0; iz <= iz1; iz++)
			for (int ix = ix0; ix <= ix1; ix++)
			{
				var c = new Vector2((ix + 0.5f) * CELL, (iz + 0.5f) * CELL);
				float t = (c - a).Dot(dir);
				if (t <= 0f || t > len) continue;   // this cell belongs to another tick's stretch
				float off = Math.Abs((c - a).Dot(new Vector2(-dir.Y, dir.X)));
				if (off > reach) continue;
				int tx = (int)Math.Floor((double)ix / TILE), tz = (int)Math.Floor((double)iz / TILE);
				var tile = TileFor(tx, tz, true);
				int i = (iz - tz * TILE) * TILE + (ix - tx * TILE);
				float cur = tile[i];
				if (off <= halfW)
				{
					// a rounded groove: deepest in the middle, the dig slowing as it nears its limit here
					float prof = 1f - (off / halfW) * (off / halfW);
					float room = Math.Max(0f, maxD - cur) / Math.Max(maxD, 1e-4f);
					tile[i] = Math.Min(maxD, cur + add * prof * (0.25f + 0.75f * room));
				}
				else
				{
					// the lip: dirt pushed out to the side (only up to a third of the groove's depth limit)
					float k = 1f - (off - halfW) / lipW;
					tile[i] = Math.Max(-maxD * 0.33f, cur - add * lip * k);
				}
				_dirty.Add(Key(tx, tz));
			}
	}

	/// the tiles dug since the last call: (tx, tz) pairs
	public int[] TakeDirty()
	{
		var o = new int[_dirty.Count * 2];
		int n = 0;
		foreach (long k in _dirty)
		{
			o[n++] = (int)(k >> 32); o[n++] = (int)(k & 0xffffffffL);
		}
		_dirty.Clear();
		return o;
	}

	/// a tile's depths as 16-bit floats for an image (FORMAT_RH, row by row); empty if it doesn't exist
	public byte[] TileRH(int tx, int tz)
	{
		var t = TileFor(tx, tz, false);
		if (t == null) return Array.Empty<byte>();
		var b = new byte[TILE * TILE * 2];
		for (int i = 0; i < t.Length; i++)
		{
			ushort h = BitConverter.HalfToUInt16Bits((Half)t[i]);
			b[2 * i] = (byte)(h & 0xff); b[2 * i + 1] = (byte)(h >> 8);
		}
		return b;
	}

	public const int FAR = 5;             // far layer: FAR x FAR cells -> one texel (25 cm)

	/// the same tile for the far window: TILE/FAR x TILE/FAR texels, each the deepest of its cells (a 9 cm groove stays a
	/// visible line from a long way off, only wider); 16-bit floats like TileRH; empty if the tile doesn't exist
	public byte[] TileRHFar(int tx, int tz)
	{
		var t = TileFor(tx, tz, false);
		if (t == null) return Array.Empty<byte>();
		int n = TILE / FAR;
		var b = new byte[n * n * 2];
		for (int j = 0; j < n; j++)
			for (int i = 0; i < n; i++)
			{
				float m = 0f;
				for (int dj = 0; dj < FAR; dj++)
					for (int di = 0; di < FAR; di++)
					{
						float v = t[(j * FAR + dj) * TILE + i * FAR + di];
						if (v > m) m = v;
					}
				ushort h = BitConverter.HalfToUInt16Bits((Half)m);
				int o = 2 * (j * n + i);
				b[o] = (byte)(h & 0xff); b[o + 1] = (byte)(h >> 8);
			}
		return b;
	}
}
