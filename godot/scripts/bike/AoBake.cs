using Godot;
using System;
using System.Collections.Generic;

/// Ambient occlusion baked per vertex for the bike (bike/bike_ao.gd). Close-range only: how much of the
/// hemisphere over each vertex is covered by nearby surface within `radius` (crevices, tube joins, the
/// shock in the frame, spokes at the hub). The surface is turned into small discs (triangles merged per
/// `cell` and normal direction, area-weighted), and each vertex sums the solid angle of the discs in front
/// of it (Bunnell's disc approximation, no visibility test: fine at this short range).
/// Plain float arrays inside (Vector3 structs in hot loops are ~4x slower).
public partial class AoBake : RefCounted
{
	/// verts / normals: every vertex of the group (one space), idx: triangles into them.
	/// Returns 0..1 per vertex: 1 = open, lower = occluded.
	public float[] Bake(Vector3[] verts, Vector3[] normals, int[] idx, float radius, float cell, float strength)
	{
		int nv = verts.Length;
		var px = new float[nv]; var py = new float[nv]; var pz = new float[nv];
		var nx = new float[nv]; var ny = new float[nv]; var nz = new float[nv];
		for (int i = 0; i < nv; i++)
		{
			px[i] = verts[i].X; py[i] = verts[i].Y; pz[i] = verts[i].Z;
			if (i < normals.Length) { nx[i] = normals[i].X; ny[i] = normals[i].Y; nz[i] = normals[i].Z; }
		}
		// 1. discs: triangles merged by (cell, dominant normal axis + sign)
		var disc = new Dictionary<long, int>();
		var dA = new List<float>(); var dX = new List<float>(); var dY = new List<float>(); var dZ = new List<float>();
		var dNX = new List<float>(); var dNY = new List<float>(); var dNZ = new List<float>();
		float inv = 1f / cell;
		for (int t = 0; t + 2 < idx.Length; t += 3)
		{
			int a = idx[t], b = idx[t + 1], c = idx[t + 2];
			if (a >= nv || b >= nv || c >= nv) continue;
			float ex = px[b] - px[a], ey = py[b] - py[a], ez = pz[b] - pz[a];
			float fx = px[c] - px[a], fy = py[c] - py[a], fz = pz[c] - pz[a];
			float cx = ey * fz - ez * fy, cy = ez * fx - ex * fz, cz = ex * fy - ey * fx;
			float len = MathF.Sqrt(cx * cx + cy * cy + cz * cz);
			if (len < 1e-12f) continue;
			float area = 0.5f * len;
			cx /= len; cy /= len; cz /= len;
			float mx = (px[a] + px[b] + px[c]) / 3f, my = (py[a] + py[b] + py[c]) / 3f, mz = (pz[a] + pz[b] + pz[c]) / 3f;
			int dir = MathF.Abs(cx) > MathF.Abs(cy) ? (MathF.Abs(cx) > MathF.Abs(cz) ? (cx > 0 ? 0 : 1) : (cz > 0 ? 4 : 5))
			                                        : (MathF.Abs(cy) > MathF.Abs(cz) ? (cy > 0 ? 2 : 3) : (cz > 0 ? 4 : 5));
			long key = Key((int)MathF.Floor(mx * inv), (int)MathF.Floor(my * inv), (int)MathF.Floor(mz * inv)) * 8 + dir;
			if (!disc.TryGetValue(key, out int k))
			{
				k = dA.Count; disc[key] = k;
				dA.Add(0); dX.Add(0); dY.Add(0); dZ.Add(0); dNX.Add(0); dNY.Add(0); dNZ.Add(0);
			}
			dA[k] += area; dX[k] += mx * area; dY[k] += my * area; dZ[k] += mz * area;
			dNX[k] += cx * area; dNY[k] += cy * area; dNZ[k] += cz * area;
		}
		int nd = dA.Count;
		var qA = new float[nd]; var qX = new float[nd]; var qY = new float[nd]; var qZ = new float[nd];
		var qNX = new float[nd]; var qNY = new float[nd]; var qNZ = new float[nd];
		for (int k = 0; k < nd; k++)
		{
			float A = dA[k];
			qA[k] = A; qX[k] = dX[k] / A; qY[k] = dY[k] / A; qZ[k] = dZ[k] / A;
			float l = MathF.Sqrt(dNX[k] * dNX[k] + dNY[k] * dNY[k] + dNZ[k] * dNZ[k]);
			if (l > 1e-12f) { qNX[k] = dNX[k] / l; qNY[k] = dNY[k] / l; qNZ[k] = dNZ[k] / l; }
		}
		// 2. a grid of the discs, cells as big as the reach
		float ginv = 1f / radius;
		var grid = new Dictionary<long, List<int>>();
		for (int k = 0; k < nd; k++)
		{
			long key = Key((int)MathF.Floor(qX[k] * ginv), (int)MathF.Floor(qY[k] * ginv), (int)MathF.Floor(qZ[k] * ginv));
			if (!grid.TryGetValue(key, out var list)) { list = new List<int>(); grid[key] = list; }
			list.Add(k);
		}
		var cells = new Dictionary<long, int[]>();
		foreach (var kv in grid) cells[kv.Key] = kv.Value.ToArray();
		// 3. every vertex: the discs in front of it within reach
		var ao = new float[nv];
		float r2max = radius * radius;
		float lift = cell * 0.5f;   // start just off the surface: its own disc lies flat beside it
		for (int i = 0; i < nv; i++)
		{
			float vx = px[i] + nx[i] * lift, vy = py[i] + ny[i] * lift, vz = pz[i] + nz[i] * lift;
			int gx = (int)MathF.Floor(vx * ginv), gy = (int)MathF.Floor(vy * ginv), gz = (int)MathF.Floor(vz * ginv);
			float occ = 0f;
			for (int ox = -1; ox <= 1; ox++)
			for (int oy = -1; oy <= 1; oy++)
			for (int oz = -1; oz <= 1; oz++)
			{
				if (!cells.TryGetValue(Key(gx + ox, gy + oy, gz + oz), out var list)) continue;
				foreach (int k in list)
				{
					float dx = qX[k] - vx, dy = qY[k] - vy, dz = qZ[k] - vz;
					float r2 = dx * dx + dy * dy + dz * dz;
					if (r2 > r2max || r2 < 1e-10f) continue;
					float r = MathF.Sqrt(r2);
					float cosR = (dx * nx[i] + dy * ny[i] + dz * nz[i]) / r;
					if (cosR <= 0.1f) continue;   // behind or level with the vertex: no cover
					float cosE = MathF.Abs(dx * qNX[k] + dy * qNY[k] + dz * qNZ[k]) / r;
					float A = qA[k];
					float f = 1f - r / radius;
					occ += (cosR - 0.1f) / 0.9f * (0.3f + 0.7f * cosE) * A / (MathF.PI * r2 + A) * f * f;
				}
			}
			occ = MathF.Min(occ, 1f);
			ao[i] = 1f - strength * MathF.Pow(occ, 1.4f);   // only real crevices go properly dark
		}
		return ao;
	}

	/// Sharp convex edges per vertex, 0 (flat / smooth / concave) .. 1 (a crisp outside edge): the mean
	/// curvature from the vertices within `radius`, (n_j - n_i) . (p_j - p_i) / |p_j - p_i|^2 (= 1 / r on a
	/// sphere of radius r; across a hard crease, ~1 / distance), mapped from k0 (1 / m, no edge) to k1 (full).
	/// Split normals at a crease (vertices on the same spot) are skipped: the neighbours just off it carry it.
	public float[] Edges(Vector3[] verts, Vector3[] normals, float radius, float k0, float k1)
	{
		int nv = verts.Length;
		var px = new float[nv]; var py = new float[nv]; var pz = new float[nv];
		var nx = new float[nv]; var ny = new float[nv]; var nz = new float[nv];
		for (int i = 0; i < nv; i++)
		{
			px[i] = verts[i].X; py[i] = verts[i].Y; pz[i] = verts[i].Z;
			if (i < normals.Length) { nx[i] = normals[i].X; ny[i] = normals[i].Y; nz[i] = normals[i].Z; }
		}
		float ginv = 1f / radius;
		var grid = new Dictionary<long, List<int>>();
		for (int i = 0; i < nv; i++)
		{
			long key = Key((int)MathF.Floor(px[i] * ginv), (int)MathF.Floor(py[i] * ginv), (int)MathF.Floor(pz[i] * ginv));
			if (!grid.TryGetValue(key, out var list)) { list = new List<int>(); grid[key] = list; }
			list.Add(i);
		}
		var cells = new Dictionary<long, int[]>();
		foreach (var kv in grid) cells[kv.Key] = kv.Value.ToArray();
		var e = new float[nv];
		float r2max = radius * radius;
		float same2 = radius * radius * 1e-4f;   // within 1 % of the reach: the same spot (a split normal)
		for (int i = 0; i < nv; i++)
		{
			int gx = (int)MathF.Floor(px[i] * ginv), gy = (int)MathF.Floor(py[i] * ginv), gz = (int)MathF.Floor(pz[i] * ginv);
			float sum = 0f, wsum = 0f;
			for (int ox = -1; ox <= 1; ox++)
			for (int oy = -1; oy <= 1; oy++)
			for (int oz = -1; oz <= 1; oz++)
			{
				if (!cells.TryGetValue(Key(gx + ox, gy + oy, gz + oz), out var list)) continue;
				foreach (int j in list)
				{
					float dx = px[j] - px[i], dy = py[j] - py[i], dz = pz[j] - pz[i];
					float d2 = dx * dx + dy * dy + dz * dz;
					if (d2 > r2max || d2 < same2) continue;
					float c = ((nx[j] - nx[i]) * dx + (ny[j] - ny[i]) * dy + (nz[j] - nz[i]) * dz) / d2;
					float f = 1f - MathF.Sqrt(d2) / radius;
					float w = f * f;
					sum += c * w; wsum += w;
				}
			}
			float k = wsum > 0f ? sum / wsum : 0f;
			float t = Math.Clamp((k - k0) / (k1 - k0), 0f, 1f);
			e[i] = t * t * (3f - 2f * t);
		}
		return e;
	}

	/// How many edges are longer than maxEdge (0 = nothing to split).
	public int LongEdges(Vector3[] v, int[] idx, float maxEdge)
	{
		int n = 0;
		float m2 = maxEdge * maxEdge;
		for (int t = 0; t + 2 < idx.Length; t += 3)
			for (int e = 0; e < 3; e++)
				if (v[idx[t + e]].DistanceSquaredTo(v[idx[t + (e + 1) % 3]]) > m2) n++;
		return n;
	}

	/// Splits edges longer than maxEdge at their middle until none is (conforming: an edge is split for both
	/// its triangles, so no cracks). attr = per-vertex floats, `stride` each, the first 3 = position; a new
	/// vertex is the average of the edge's two (the caller renormalises normals / tangents).
	/// Returns [float[] attr, int[] idx].
	public Godot.Collections.Array Subdivide(float[] attr, int stride, int[] idx, float maxEdge, int maxPasses)
	{
		var A = new List<float>(attr);
		var I = new List<int>(idx);
		float m2 = maxEdge * maxEdge;
		for (int pass = 0; pass < maxPasses; pass++)
		{
			var mid = new Dictionary<long, int>();
			int added = 0;
			int nTri = I.Count / 3;
			var outI = new List<int>(I.Count * 2);
			int Mid(int a, int b)
			{
				long k = a < b ? ((long)a << 32) | (uint)b : ((long)b << 32) | (uint)a;
				if (mid.TryGetValue(k, out int m)) return m;
				m = A.Count / stride;
				for (int s = 0; s < stride; s++) A.Add(0.5f * (A[a * stride + s] + A[b * stride + s]));
				mid[k] = m; added++;
				return m;
			}
			bool Long(int a, int b)
			{
				float dx = A[a * stride] - A[b * stride], dy = A[a * stride + 1] - A[b * stride + 1], dz = A[a * stride + 2] - A[b * stride + 2];
				return dx * dx + dy * dy + dz * dz > m2;
			}
			// decide splits per edge first (both triangles of an edge see the same answer)
			for (int t = 0; t < nTri; t++)
			{
				int a = I[t * 3], b = I[t * 3 + 1], c = I[t * 3 + 2];
				if (Long(a, b)) Mid(a, b);
				if (Long(b, c)) Mid(b, c);
				if (Long(c, a)) Mid(c, a);
			}
			if (added == 0) break;
			for (int t = 0; t < nTri; t++)
			{
				int a = I[t * 3], b = I[t * 3 + 1], c = I[t * 3 + 2];
				int ab = Find(mid, a, b), bc = Find(mid, b, c), ca = Find(mid, c, a);
				int k = (ab >= 0 ? 1 : 0) + (bc >= 0 ? 1 : 0) + (ca >= 0 ? 1 : 0);
				if (k == 0) { outI.Add(a); outI.Add(b); outI.Add(c); continue; }
				if (k == 3)
				{
					outI.AddRange(new[] { a, ab, ca, ab, b, bc, ca, bc, c, ab, bc, ca });
					continue;
				}
				// rotate so the (first) split edge is a-b
				for (int r = 0; r < 3 && ab < 0; r++)
				{
					(a, b, c) = (b, c, a);
					ab = Find(mid, a, b); bc = Find(mid, b, c); ca = Find(mid, c, a);
				}
				if (k == 1) { outI.AddRange(new[] { a, ab, c, ab, b, c }); continue; }
				// two split edges: a-b and one of b-c / c-a
				if (bc >= 0) outI.AddRange(new[] { a, ab, c, ab, b, bc, ab, bc, c });
				else outI.AddRange(new[] { a, ab, ca, ab, b, c, ab, c, ca });
			}
			I = outI;
		}
		return new Godot.Collections.Array { A.ToArray(), I.ToArray() };
	}

	static int Find(Dictionary<long, int> mid, int a, int b)
	{
		long k = a < b ? ((long)a << 32) | (uint)b : ((long)b << 32) | (uint)a;
		return mid.TryGetValue(k, out int m) ? m : -1;
	}

	static long Key(int x, int y, int z) => (((long)(x & 0xFFFFF)) << 40) | (((long)(y & 0xFFFFF)) << 20) | (long)(z & 0xFFFFF);
}
