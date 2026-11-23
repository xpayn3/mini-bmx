using Godot;
using System;
using System.Collections.Generic;

/// The hot loops of world/tape_sim.gd (torn race tape) in C#: one Verlet step of a foil strip (wind, drag,
/// distance constraints, pins, ground with friction) and its drawn ribbon (Catmull-Rom through the points,
/// a twisting width). Stateless: TapeSim keeps every strip's state and passes it in; each call does a whole
/// frame's work for one strip, so there is one GDScript -> C# call per strip per frame. Must do exactly what
/// TapeSim._step / _ribbon do (they stay as the fallback without C#).
public partial class TapeStripCs : RefCounted
{
	float[] _px = Array.Empty<float>(), _py = Array.Empty<float>(), _pz = Array.Empty<float>();
	float[] _qx = Array.Empty<float>(), _qy = Array.Empty<float>(), _qz = Array.Empty<float>();

	void Ensure(int n)
	{
		if (_px.Length >= n) return;
		_px = new float[n]; _py = new float[n]; _pz = new float[n];
		_qx = new float[n]; _qy = new float[n]; _qz = new float[n];
	}

	/// sub substeps of length h (the first scaled by ratio = h / last h); iter constraint passes (+6 when taut =
	/// tied at both ends). pin / pin2 / gat (grab point, gi > 0) are held fixed. Returns [P, Q].
	public Godot.Collections.Array Step(Vector3[] P, Vector3[] Q, float[] G, float[] segs, float segLen,
		float h, float ratio, int sub, int iter, bool pinned, Vector3 pin, bool pinned2, Vector3 pin2,
		int gi, Vector3 gat, float t, float tw0, Vector3 wdir, float ws)
	{
		int n = P.Length;
		Ensure(n);
		float[] px = _px, py = _py, pz = _pz, qx = _qx, qy = _qy, qz = _qz;
		for (int i = 0; i < n; i++)
		{
			px[i] = P[i].X; py[i] = P[i].Y; pz[i] = P[i].Z;
			qx[i] = Q[i].X; qy[i] = Q[i].Y; qz[i] = Q[i].Z;
		}
		bool taut = pinned2;
		bool useSegs = segs != null && segs.Length == n - 1;
		const float drag = 3.2f;
		float wdx = wdir.X, wdz = wdir.Z;
		int passes = iter + (taut ? 6 : 0);
		for (int s = 0; s < sub; s++)
		{
			float r = s == 0 ? ratio : 1f;
			float ih = r / h, hh = h * h;
			for (int i = 0; i < n; i++)
			{
				float tu = t * 3f + i * 0.55f + tw0;
				float wmag = ws * (0.8f + 0.35f * MathF.Sin(tu * 1.7f));
				float wx = wdx * wmag + MathF.Sin(tu * 2.3f + i) * ws * 0.35f;
				float wz = wdz * wmag + MathF.Cos(tu * 2.9f - i) * ws * 0.35f;
				float alt = Math.Clamp(1f - (py[i] - G[i]) / 9f, 0f, 1f);
				float wy = ws * (0.16f * alt + 0.3f * MathF.Sin(tu * 1.3f + i * 0.7f));
				if (taut) { wx *= 0.25f; wy *= 0.25f; wz *= 0.25f; }
				float vx = (px[i] - qx[i]) * ih, vy = (py[i] - qy[i]) * ih, vz = (pz[i] - qz[i]) * ih;
				float ax = (wx - vx) * drag, ay = (wy - vy) * drag - 9.81f * 0.35f, az = (wz - vz) * drag;
				qx[i] = px[i]; qy[i] = py[i]; qz[i] = pz[i];
				px[i] += vx * h + ax * hh; py[i] += vy * h + ay * hh; pz[i] += vz * h + az * hh;
			}
			for (int it = 0; it < passes; it++)
			{
				if (pinned) { px[0] = pin.X; py[0] = pin.Y; pz[0] = pin.Z; }
				if (pinned2) { px[n - 1] = pin2.X; py[n - 1] = pin2.Y; pz[n - 1] = pin2.Z; }
				if (gi > 0) { px[gi] = gat.X; py[gi] = gat.Y; pz[gi] = gat.Z; }
				for (int i = 0; i < n - 1; i++)
				{
					float dx = px[i + 1] - px[i], dy = py[i + 1] - py[i], dz = pz[i + 1] - pz[i];
					float l = MathF.Sqrt(dx * dx + dy * dy + dz * dz);
					if (l == 0f) l = 1e-6f;
					float sl = useSegs ? segs[i] : segLen;
					float diff = (l - sl) / l;
					bool fa = (pinned && i == 0) || gi == i;
					bool fb = (pinned2 && i + 1 == n - 1) || gi == i + 1;
					float wa = fa ? 0f : (fb ? 1f : 0.5f);
					float wb = fb ? 0f : (fa ? 1f : 0.5f);
					float ka = diff * wa, kb = diff * wb;
					px[i] += dx * ka; py[i] += dy * ka; pz[i] += dz * ka;
					px[i + 1] -= dx * kb; py[i + 1] -= dy * kb; pz[i + 1] -= dz * kb;
				}
			}
			if (pinned) { px[0] = pin.X; py[0] = pin.Y; pz[0] = pin.Z; }
			if (pinned2) { px[n - 1] = pin2.X; py[n - 1] = pin2.Y; pz[n - 1] = pin2.Z; }
			if (gi > 0) { px[gi] = gat.X; py[gi] = gat.Y; pz[gi] = gat.Z; }
			for (int i = 0; i < n; i++)
			{
				float g = G[i] + 0.01f;
				if (py[i] < g)
				{
					py[i] = g;
					qx[i] += (px[i] - qx[i]) * 0.5f;
					qz[i] += (pz[i] - qz[i]) * 0.5f;
					qy[i] = g;
				}
			}
		}
		for (int i = 0; i < n; i++)
		{
			P[i] = new Vector3(px[i], py[i], pz[i]);
			Q[i] = new Vector3(qx[i], qy[i], qz[i]);
		}
		return new Godot.Collections.Array { P, Q };
	}

	// drawn ribbons by strip id (kept while a strip sleeps: nothing to rebuild)
	class Rib { public Vector3[] V, N; public Color[] C; public int[] I; public Vector3[] P, E; public Vector3 Ax0; }
	readonly Dictionary<long, Rib> _rib = new();
	readonly HashSet<long> _seen = new();
	readonly List<Rib> _order = new();
	Vector3[] _AV = Array.Empty<Vector3>(), _AN = Array.Empty<Vector3>();
	Color[] _AC = Array.Empty<Color>();
	int[] _AI = Array.Empty<int>();

	/// run every path once at the start of a ride (the JIT compiles them now, not in the frame the tape snaps)
	public void Warm()
	{
		var P = new Vector3[] { Vector3.Zero, new Vector3(0.25f, 0, 0), new Vector3(0.5f, 0, 0) };
		Step(P, (Vector3[])P.Clone(), new float[3], new float[2] { 0.25f, 0.25f }, 0.25f, 1f / 180f, 1f, 3, 6,
			true, P[0], true, P[2], 1, P[1], 0f, 0f, Vector3.Right, 4f);
		var d = new Godot.Collections.Dictionary { { "id", -1L }, { "redo", true }, { "P", P }, { "tw", new float[3] },
			{ "tr", 1f }, { "tk", 0.3f }, { "ta", 1f }, { "td", 0f }, { "tp", 0f }, { "cols", new Godot.Collections.Array { Colors.White, Colors.Red } } };
		var m = new ArrayMesh();
		Draw(m, new Godot.Collections.Array { d }, 0f, 0.075f, 4);
		Draw(m, new Godot.Collections.Array(), 0f, 0.075f, 4);
	}

	/// every strip into `mesh` as one indexed surface (TapeSim._draw): a strip with "redo" (or new) gets its
	/// ribbon rebuilt from "P", the rest reuse their last one. Returns the vertex count.
	public int Draw(ArrayMesh mesh, Godot.Collections.Array strips, float t, float w, int subd)
	{
		_seen.Clear();
		_order.Clear();
		int nv = 0, ni = 0;
		foreach (Variant sv in strips)
		{
			var s = sv.AsGodotDictionary();
			long id = s["id"].AsInt64();
			_seen.Add(id);
			bool has = _rib.TryGetValue(id, out Rib r);
			if (!has || s["redo"].AsBool())
			{
				s["redo"] = false;
				if (!has) { r = new Rib(); _rib[id] = r; }
				float twk = s.TryGetValue("tw_k", out Variant tk) ? tk.AsSingle() : 1f;
				float tb = s.TryGetValue("tb", out Variant tbv) ? tbv.AsSingle() : t;
				Build(r, s["P"].AsVector3Array(), s["tw"].AsFloat32Array(), s["tr"].AsSingle(), s["tk"].AsSingle(),
					s["ta"].AsSingle(), s["td"].AsSingle(), s["tp"].AsSingle(), twk, t, tb, w, subd);
				if (r.C == null || r.C.Length != r.V.Length)
				{
					var cols = s["cols"].AsGodotArray();
					int per = 2 * (subd + 1);
					r.C = new Color[r.V.Length];
					for (int k = 0; k < r.C.Length; k++) r.C[k] = cols[Math.Min(cols.Count - 1, k / per)].AsColor();
				}
			}
			_order.Add(r);
			nv += r.V.Length;
			ni += r.I.Length;
		}
		if (_rib.Count != _seen.Count)
		{
			var gone = new List<long>();
			foreach (var k in _rib.Keys) if (!_seen.Contains(k)) gone.Add(k);
			foreach (var k in gone) _rib.Remove(k);
		}
		mesh.ClearSurfaces();
		if (nv == 0) return 0;
		if (_AV.Length != nv) { _AV = new Vector3[nv]; _AN = new Vector3[nv]; _AC = new Color[nv]; }
		if (_AI.Length != ni) _AI = new int[ni];
		int o = 0, oi = 0;
		foreach (Rib r in _order)
		{
			Array.Copy(r.V, 0, _AV, o, r.V.Length);
			Array.Copy(r.N, 0, _AN, o, r.N.Length);
			Array.Copy(r.C, 0, _AC, o, r.C.Length);
			for (int k = 0; k < r.I.Length; k++) _AI[oi + k] = r.I[k] + o;
			o += r.V.Length;
			oi += r.I.Length;
		}
		var arr = new Godot.Collections.Array();
		arr.Resize((int)Mesh.ArrayType.Max);
		arr[(int)Mesh.ArrayType.Vertex] = _AV;
		arr[(int)Mesh.ArrayType.Normal] = _AN;
		arr[(int)Mesh.ArrayType.Color] = _AC;
		arr[(int)Mesh.ArrayType.Index] = _AI;
		mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);
		return nv;
	}

	/// the strip's ribbon into r: P0 drawn through a Catmull-Rom spline (subd pieces per segment), its width (w)
	/// turned about the strip by the twist (tr, tk, ta, td, tp, twk; tw = per-point phases), as TapeSim._ribbon.
	/// Shared vertices within each sim segment (its stripe colour), split between segments; smooth normals.
	static void Build(Rib r, Vector3[] P0, float[] tw, float tr, float tk, float ta, float td, float tp,
		float twk, float t, float tb, float w, int subd)
	{
		int n0 = P0.Length;
		int n = (n0 - 1) * subd + 1;
		if (r.P == null || r.P.Length != n) { r.P = new Vector3[n]; r.E = new Vector3[n]; }
		Vector3[] P = r.P, E = r.E;
		for (int i = 0; i < n0 - 1; i++)
		{
			Vector3 pa = P0[Math.Max(0, i - 1)], pb = P0[i], pc = P0[i + 1], pd = P0[Math.Min(n0 - 1, i + 2)];
			for (int j = 0; j < subd; j++)
			{
				float u = (float)j / subd, u2 = u * u, u3 = u2 * u;
				P[i * subd + j] = 0.5f * (2f * pb + (pc - pa) * u + (2f * pa - 5f * pb + 4f * pc - pd) * u2
					+ (3f * pb - pa - 3f * pc + pd) * u3);
			}
		}
		P[n - 1] = P0[n0 - 1];
		float W = w / 2f;
		int seg = n0 - 1, per = 2 * (subd + 1);
		int nv = seg * per;
		if (r.V == null || r.V.Length != nv)
		{
			r.V = new Vector3[nv]; r.N = new Vector3[nv]; r.C = null;
			r.I = new int[seg * subd * 6];
			int q = 0;
			for (int sg = 0; sg < seg; sg++)
				for (int j = 0; j < subd; j++)
				{
					int a = sg * per + 2 * j;   // a = p0 + e0, a + 1 = p0 - e0, a + 2 = p1 + e1, a + 3 = p1 - e1
					r.I[q++] = a; r.I[q++] = a + 2; r.I[q++] = a + 1;
					r.I[q++] = a + 2; r.I[q++] = a + 3; r.I[q++] = a + 1;
				}
		}
		Vector3[] V = r.V, N = r.N;
		Vector3 axPrev = Vector3.Zero;
		for (int i = 0; i < n; i++)
		{
			float fi = (float)i / subd;
			Vector3 d = (P[Math.Min(n - 1, i + 1)] - P[Math.Max(0, i - 1)]).Normalized();
			// the width's base direction: across the strip and level at its first point, then carried along it
			// with the least turn (parallel transport). Each point's own d x up jumped wherever the tape pointed
			// straight up / down (a torn half whipping back over its stake): the ribbon flipped edge-on = flicker
			Vector3 ax;
			if (i == 0)
			{
				// last frame's, squared to d: it only ever turns as far as the tape did (no flip between frames);
				// the first frame: level across the strip
				ax = r.Ax0 - d * r.Ax0.Dot(d);
				if (ax.LengthSquared() < 1e-6f) ax = d.Cross(Vector3.Up);
				if (ax.LengthSquared() < 1e-8f) ax = new Vector3(1, 0, 0);
				ax = ax.Normalized();
				r.Ax0 = ax;
			}
			else
			{
				ax = axPrev - d * axPrev.Dot(d);
				if (ax.LengthSquared() < 1e-8f) ax = d.Cross(Vector3.Up);
				if (ax.LengthSquared() < 1e-8f) ax = new Vector3(1, 0, 0);
				ax = ax.Normalized();
			}
			axPrev = ax;
			Vector3 bx = ax.Cross(d);
			float twa = (MathF.Sin(tp + t * tr - fi * tk) * ta
				+ MathF.Sin(t * tr * 0.37f + fi * tk * 2.3f + tw[Math.Min(n0 - 1, (int)fi)] * 0.15f) * ta * 0.5f
				+ fi * td * 0.2f + (t - tb) * td) * twk;   // drift since the strip was made (tb): with the ride's
				// whole clock (minutes) x the twist's 0..1 ramp after a tear, a torn half spun ~13 turns / s: a strobe
			Vector3 e = bx * (MathF.Cos(twa) * W) + ax * (MathF.Sin(twa) * W);
			E[i] = e;
			Vector3 nn = d.Cross(e).Normalized();
			// point i is the end of segment (i - 1) / subd's last piece and the start of segment i / subd's first
			int sA = i / subd, jA = i % subd;
			if (sA < seg) { int k = sA * per + 2 * jA; V[k] = P[i] + e; V[k + 1] = P[i] - e; N[k] = nn; N[k + 1] = nn; }
			if (jA == 0 && i > 0) { int k = (sA - 1) * per + 2 * subd; V[k] = P[i] + e; V[k + 1] = P[i] - e; N[k] = nn; N[k + 1] = nn; }
		}
	}
}
