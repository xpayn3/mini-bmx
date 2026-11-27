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
	private readonly Dictionary<long, TrackTile> _tracks = new();   // tyre prints, per tile (made with the first print in it)
	private readonly LinkedList<long> _age = new();   // most recently dug last
	private readonly Dictionary<long, LinkedListNode<long>> _ageNode = new();
	private readonly HashSet<long> _dirty = new();
	private readonly Dictionary<int, Vector2> _last = new();   // wheel id -> last stamped point (x, z)
	private readonly Dictionary<int, Vector2> _lastT = new();  // the same for the prints

	/// Tyre prints (2026-11-25: the tracks moved from a mesh ribbon into the ground, off-road-game style). Per cell:
	/// E = signed distance (m) to the edge of the prints (< 0 inside), kept as the UNION of every print (min), so it
	/// interpolates cleanly between 5 cm cells even where prints overlap (a signed distance field, as font / decal
	/// rendering draws crisp edges from coarse cells); then its strength, how much of it is a skid smear (0..1), blood on
	/// the tyre and its direction as a doubled angle (cos 2a, sin 2a: continuous whichever way it ran). Everything is a
	/// quantity that BLENDS between cells: the ground shader works the across position out of E, so where a skid crosses
	/// the front print nothing jumps. The newest print wins inside its band; E stays the union. Half floats (~300 KB a tile).
	/// (First versions kept one print's SIGNED offset, then its |offset| and a negative strength for skids: neighbouring
	/// cells of overlapping prints held unrelated values and the bilinear blend drew saw-toothed edges, zigzag lines,
	/// holes where + and - strength met, and the tread in 5 cm blocks.)
	private sealed class TrackTile
	{
		public readonly Half[] E = new Half[TILE * TILE];
		public readonly Half[] S = new Half[TILE * TILE];
		public readonly Half[] M = new Half[TILE * TILE];
		public readonly Half[] B = new Half[TILE * TILE];
		public readonly Half[] C2 = new Half[TILE * TILE];
		public readonly Half[] S2 = new Half[TILE * TILE];
		public TrackTile() { Array.Fill(E, (Half)NO_E); }
	}
	public const float NO_E = 9f;         // "no print near this cell"
	private float _minX = float.PositiveInfinity, _minZ = float.PositiveInfinity, _maxX = float.NegativeInfinity, _maxZ = float.NegativeInfinity;

	private static long Key(int tx, int tz) => ((long)tx << 32) ^ (uint)tz;

	public void Clear()
	{
		_tiles.Clear(); _tracks.Clear(); _age.Clear(); _ageNode.Clear(); _dirty.Clear(); _last.Clear(); _lastT.Clear();
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
			_age.RemoveFirst(); _ageNode.Remove(old); _tiles.Remove(old); _tracks.Remove(old); _dirty.Remove(old);
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

	/// a tyre (id) printed its tread to (x, z): its stretch since the last call. halfW = half the print's width (m),
	/// strength 0..1 (how dark), smear = a skid (no tread, streaks), blood 0..1 = red on the tyre. strength 0 = lifted
	/// (the next call starts afresh); a jump > 1.5 m = a new start.
	public void StampTrack(int id, float x, float z, float halfW, float strength, bool smear, float blood)
	{
		var p = new Vector2(x, z);
		if (strength <= 0f) { _lastT.Remove(id); return; }
		if (!_lastT.TryGetValue(id, out var a) || a.DistanceTo(p) > 1.5f) { _lastT[id] = p; return; }
		Vector2 seg = p - a;
		float len = seg.Length();
		if (len < 0.02f) return;
		_lastT[id] = p;
		Vector2 dir = seg / len;
		Vector2 nrm = new Vector2(-dir.Y, dir.X);
		var c2 = (Half)(dir.X * dir.X - dir.Y * dir.Y);
		var s2 = (Half)(2f * dir.X * dir.Y);
		var sv = (Half)strength;
		var mv = (Half)(smear ? 1f : 0f);
		var bv = (Half)blood;
		float reach = halfW + 2.2f * CELL;   // + two cells beside it: the edge interpolates crisply
		int ix0 = (int)Math.Floor((Math.Min(a.X, p.X) - reach) / CELL), ix1 = (int)Math.Floor((Math.Max(a.X, p.X) + reach) / CELL);
		int iz0 = (int)Math.Floor((Math.Min(a.Y, p.Y) - reach) / CELL), iz1 = (int)Math.Floor((Math.Max(a.Y, p.Y) + reach) / CELL);
		for (int iz = iz0; iz <= iz1; iz++)
			for (int ix = ix0; ix <= ix1; ix++)
			{
				var c = new Vector2((ix + 0.5f) * CELL, (iz + 0.5f) * CELL);
				float t = (c - a).Dot(dir);
				if (t <= 0f || t > len) continue;   // another tick's stretch
				float off = (c - a).Dot(nrm);
				if (Math.Abs(off) > reach) continue;
				int tx = (int)Math.Floor((double)ix / TILE), tz = (int)Math.Floor((double)iz / TILE);
				TileFor(tx, tz, true);
				long k = Key(tx, tz);
				if (!_tracks.TryGetValue(k, out var tt)) { tt = new TrackTile(); _tracks[k] = tt; }
				int i = (iz - tz * TILE) * TILE + (ix - tx * TILE);
				float ao = Math.Abs(off);
				float e = ao - halfW;                     // this print's edge distance (< 0 inside)
				float eo = (float)tt.E[i];
				// the union of all prints keeps the smallest edge distance; the print's own data goes where it is inside
				// its band (the newest wins there) or, beside it, where no print reaches nearer
				if (e < 0f || e < eo)
				{
					tt.S[i] = sv; tt.M[i] = mv; tt.B[i] = bv; tt.C2[i] = c2; tt.S2[i] = s2;
				}
				if (e < eo) tt.E[i] = (Half)e;
				_dirty.Add(k);
			}
	}

	/// a shoe sole pressed into the ground (walking after a crash): heel (hx, hz) to toe (tx, tz), a rounded sole a little
	/// wider at the ball; drawn as a plain pressed print (the skid look: no tyre knobs), blood 0..1 = a bloody sole
	public void StampShoe(float hx, float hz, float tx, float tz, float strength, float blood)
	{
		var a = new Vector2(hx, hz); var b = new Vector2(tx, tz);
		Vector2 ab = b - a; float len = ab.Length();
		if (len < 0.05f) return;
		Vector2 dir = ab / len;
		var c2 = (Half)(dir.X * dir.X - dir.Y * dir.Y);
		var s2 = (Half)(2f * dir.X * dir.Y);
		var sv = (Half)strength; var mv = (Half)1f; var bv = (Half)blood;
		float reach = 0.05f + 2.2f * CELL;
		int ix0 = (int)Math.Floor((Math.Min(a.X, b.X) - reach) / CELL), ix1 = (int)Math.Floor((Math.Max(a.X, b.X) + reach) / CELL);
		int iz0 = (int)Math.Floor((Math.Min(a.Y, b.Y) - reach) / CELL), iz1 = (int)Math.Floor((Math.Max(a.Y, b.Y) + reach) / CELL);
		for (int iz = iz0; iz <= iz1; iz++)
			for (int ix = ix0; ix <= ix1; ix++)
			{
				var c = new Vector2((ix + 0.5f) * CELL, (iz + 0.5f) * CELL);
				float t = Math.Clamp((c - a).Dot(dir) / len, 0f, 1f);
				float r = 0.034f + 0.012f * (float)Math.Sin(Math.PI * Math.Min(1f, t * 1.25f));   // heel 3.4 cm, ball ~4.6
				float e = (c - (a + ab * t)).Length() - r;
				if (e > reach - 0.05f) continue;
				int ttx = (int)Math.Floor((double)ix / TILE), ttz = (int)Math.Floor((double)iz / TILE);
				TileFor(ttx, ttz, true);
				long k = Key(ttx, ttz);
				if (!_tracks.TryGetValue(k, out var tt)) { tt = new TrackTile(); _tracks[k] = tt; }
				int i = (iz - ttz * TILE) * TILE + (ix - ttx * TILE);
				float eo = (float)tt.E[i];
				if (e < 0f || e < eo) { tt.S[i] = sv; tt.M[i] = mv; tt.B[i] = bv; tt.C2[i] = c2; tt.S2[i] = s2; }
				if (e < eo) tt.E[i] = (Half)e;
				_dirty.Add(k);
			}
	}

	/// a tile for the ground shader's window: per cell 4 x uint32 = half pairs (depth, edge distance), (strength, blood),
	/// (cos 2a, sin 2a), (smear, 0), row by row (shaders/rut_upload.glsl unpacks them); empty if the tile doesn't exist
	private byte[] _pack;
	public byte[] TilePack(int tx, int tz)
	{
		var d = TileFor(tx, tz, false);
		if (d == null) return Array.Empty<byte>();
		_tracks.TryGetValue(Key(tx, tz), out var tt);
		// one buffer reused for every tile: Godot copies it into a PackedByteArray on return, so it is free again at once.
		// (A fresh 410 KB array per copy, ~30 a second, all went to the large-object heap: gen-2 collections over a
		// heap that grows with the ride = a hitch every so often, worse the longer the ride.)
		var b = _pack ??= new byte[TILE * TILE * 16];
		ushort he0 = BitConverter.HalfToUInt16Bits((Half)NO_E), ha0 = 0, z0 = 0;
		for (int i = 0; i < d.Length; i++)
		{
			int o = 16 * i;
			ushort h0 = BitConverter.HalfToUInt16Bits((Half)d[i]);
			ushort h1 = tt != null ? BitConverter.HalfToUInt16Bits(tt.E[i]) : he0;
			ushort h2 = tt != null ? BitConverter.HalfToUInt16Bits(tt.S[i]) : z0;
			ushort h3 = tt != null ? BitConverter.HalfToUInt16Bits(tt.B[i]) : z0;
			ushort h4 = tt != null ? BitConverter.HalfToUInt16Bits(tt.C2[i]) : z0;
			ushort h5 = tt != null ? BitConverter.HalfToUInt16Bits(tt.S2[i]) : z0;
			ushort h6 = tt != null ? BitConverter.HalfToUInt16Bits(tt.M[i]) : ha0;
			b[o] = (byte)h0; b[o + 1] = (byte)(h0 >> 8); b[o + 2] = (byte)h1; b[o + 3] = (byte)(h1 >> 8);
			b[o + 4] = (byte)h2; b[o + 5] = (byte)(h2 >> 8); b[o + 6] = (byte)h3; b[o + 7] = (byte)(h3 >> 8);
			b[o + 8] = (byte)h4; b[o + 9] = (byte)(h4 >> 8); b[o + 10] = (byte)h5; b[o + 11] = (byte)(h5 >> 8);
			b[o + 12] = (byte)h6; b[o + 13] = (byte)(h6 >> 8);
		}
		return b;
	}

	/// probe: the strongest print within r cells of (x, z) as (min edge distance, strength there, tile exists 0/1, track tile 0/1)
	public Vector4 TrackNear(float x, float z, int r)
	{
		int cx = (int)Math.Floor(x / CELL), cz = (int)Math.Floor(z / CELL);
		float be = NO_E, bs = 0f; bool any = false, anyT = false;
		for (int iz = cz - r; iz <= cz + r; iz++)
			for (int ix = cx - r; ix <= cx + r; ix++)
			{
				int tx = (int)Math.Floor((double)ix / TILE), tz = (int)Math.Floor((double)iz / TILE);
				if (TileFor(tx, tz, false) == null) continue;
				any = true;
				if (!_tracks.TryGetValue(Key(tx, tz), out var tt)) continue;
				anyT = true;
				int i = (iz - tz * TILE) * TILE + (ix - tx * TILE);
				float e = (float)tt.E[i];
				if (e < be) { be = e; bs = (float)tt.S[i]; }
			}
		return new Vector4(be, bs, any ? 1 : 0, anyT ? 1 : 0);
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

	public const int FAR = 5;             // far layer: FAR x FAR cells -> one texel (25 cm)

	/// the same tile for the far window: TILE/FAR x TILE/FAR texels, 16-bit float pairs (FORMAT_RGH): r = the deepest of
	/// its cells (a 9 cm groove stays a visible line from a long way off, only wider), g = how much of it tyre prints cover
	/// (x their strength: from afar a print is its average shade); empty if the tile doesn't exist
	public byte[] TileRGFar(int tx, int tz)
	{
		var t = TileFor(tx, tz, false);
		if (t == null) return Array.Empty<byte>();
		_tracks.TryGetValue(Key(tx, tz), out var tt);
		int n = TILE / FAR;
		var b = new byte[n * n * 4];
		for (int j = 0; j < n; j++)
			for (int i = 0; i < n; i++)
			{
				float m = 0f, cov = 0f;
				for (int dj = 0; dj < FAR; dj++)
					for (int di = 0; di < FAR; di++)
					{
						int c = (j * FAR + dj) * TILE + i * FAR + di;
						float v = t[c];
						if (v > m) m = v;
						if (tt != null && (float)tt.E[c] < 0f)
							cov += (float)tt.S[c] * Math.Min(-(float)tt.E[c] / 0.03f, 1f);
					}
				ushort h = BitConverter.HalfToUInt16Bits((Half)m);
				ushort g = BitConverter.HalfToUInt16Bits((Half)(cov / (FAR * FAR)));
				int o = 4 * (j * n + i);
				b[o] = (byte)(h & 0xff); b[o + 1] = (byte)(h >> 8); b[o + 2] = (byte)(g & 0xff); b[o + 3] = (byte)(g >> 8);
			}
		return b;
	}
}
