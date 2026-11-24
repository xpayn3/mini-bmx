using System;
using Godot;

/// The hair's guide-lock sim step (rider/hair.gd `_step`), in C#: the GDScript version cost ~2.1-2.5 ms a frame (28 locks
/// x 10 points, ~6 passes each, plus body-sphere collision per sub-step), the biggest untimed _process cost in a ride
/// (found with the frame profiler's node probe, 2026-11-24). Same maths, same order; hair.gd keeps the state in sync
/// (Setup on a style change, SetState on a reset) and reads the points back with GetP() once per frame.
/// Everything is in the head-relative frame (world axes, origin on the head), as in hair.gd.
public partial class HairSimCs : RefCounted
{
	private int _g, _s1, _seg;
	private Vector3[] _p = Array.Empty<Vector3>(), _q = Array.Empty<Vector3>(), _roots = Array.Empty<Vector3>(), _rest = Array.Empty<Vector3>();
	private float[] _len = Array.Empty<float>(), _ph = Array.Empty<float>();
	private float _segLen, _hold, _bend, _flutter, _pr0, _pr1;
	private int _holdN;
	private bool _plait;
	private double _hprev = 1.0 / 120.0;
	private const double DAMP = 2.0;
	private static readonly Vector3 HEAD_C = new Vector3(0.006f, -0.012f, 0.0f);
	private static readonly Vector3 HEAD_R = new Vector3(0.12f, 0.13f, 0.11f);

	public void Setup(int g, int seg, Vector3[] roots, Vector3[] rest, float[] len, float[] ph, float segLen, float hold, int holdN,
		float bend, float flutter, bool plait, float pr0, float pr1)
	{
		_g = g; _seg = seg; _s1 = seg + 1;
		_roots = roots; _rest = rest; _len = len; _ph = ph;
		_segLen = segLen; _hold = hold; _holdN = holdN; _bend = bend; _flutter = flutter; _plait = plait; _pr0 = pr0; _pr1 = pr1;
		if (_p.Length != g * _s1) { _p = new Vector3[g * _s1]; _q = new Vector3[g * _s1]; }
	}

	public void SetState(Vector3[] p, Vector3[] q, double hprev)
	{
		Array.Copy(p, _p, Math.Min(p.Length, _p.Length));
		Array.Copy(q, _q, Math.Min(q.Length, _q.Length));
		_hprev = hprev;
	}

	public Vector3[] GetP() => _p;

	private static float Rate(double a, double h) => (float)(1.0 - Math.Pow(1.0 - Math.Min(a, 0.999), h * 60.0));

	/// one sub-step of length h. spheres = (x, y, z, r) per body sphere, head-relative; t = the sim clock after this step
	public void Step(Basis hb, float[] spheres, double h, Vector3 force, float lively, double t)
	{
		float h2 = (float)(h * h);
		Basis hinv = hb.Inverse();
		float keep = (float)((h / _hprev) * Math.Max(0.0, 1.0 - DAMP * h));
		float bend = Rate(_bend, h);
		float slide = Rate(0.7, h);
		int ns = spheres.Length / 4;
		for (int i = 0; i < _g; i++)
		{
			int b = i * _s1;
			Vector3 root = hb * _roots[i];
			_p[b] = root; _q[b] = root;
			float L = _segLen * _len[i];
			for (int j = 1; j <= _seg; j++)
			{
				int k = b + j;
				Vector3 v = (_p[k] - _q[k]) * keep;
				_q[k] = _p[k];
				float f = (float)j / _seg;
				Vector3 sway = new Vector3(
					(float)Math.Sin(t * 1.7 + _ph[i] * 0.5 - j * 0.45),
					(float)Math.Sin(t * 1.3 + _ph[i] - j * 0.35) * 0.4f,
					(float)Math.Cos(t * 1.5 + _ph[i] * 0.8 - j * 0.4)) * MathF.Sqrt(f);
				_p[k] += v + (force + sway * _flutter * 2.0f * lively) * h2;
			}
			// the first points keep the hairstyle's shape (volume at the scalp)
			for (int j = 1; j <= _holdN; j++)
			{
				Vector3 target = root + hb * _rest[i] * (L * j);
				Vector3 moved = _p[b + j].Lerp(target, Rate(Math.Min(1.0, _hold / j), h));
				_q[b + j] += moved - _p[b + j];
				_p[b + j] = moved;
			}
			for (int it = 0; it < 2; it++)
				for (int j = 1; j <= _seg; j++)
				{
					Vector3 a = _p[b + j - 1];
					Vector3 d = _p[b + j] - a;
					float l = d.Length();
					if (l > 1e-6f) _p[b + j] = a + d * (L / l);
				}
			for (int j = 1; j <= _seg; j++)
			{
				float fj = (float)j / _seg;
				Vector3 lp = hinv * _p[b + j] - HEAD_C;
				Vector3 qv = new Vector3(lp.X / HEAD_R.X, lp.Y / HEAD_R.Y, lp.Z / HEAD_R.Z);
				float ql = qv.Length();
				if (ql < 1.07f && ql > 1e-4f)
				{
					qv *= 1.07f / ql;
					_p[b + j] = hb * (new Vector3(qv.X * HEAD_R.X, qv.Y * HEAD_R.Y, qv.Z * HEAD_R.Z) + HEAD_C);
					_q[b + j] = _q[b + j].Lerp(_p[b + j], slide);
				}
				else if (_p[b + j].Y < -0.1f)
				{
					float thick = _plait ? Mathf.Lerp(_pr0, _pr1, fj) + 0.004f : 0.006f;
					for (int s = 0; s < ns; s++)
					{
						Vector3 c = new Vector3(spheres[4 * s], spheres[4 * s + 1], spheres[4 * s + 2]);
						Vector3 dd = _p[b + j] - c;
						float r = spheres[4 * s + 3] + thick;
						float l2 = dd.LengthSquared();
						if (l2 < r * r && l2 > 1e-9f)
						{
							_p[b + j] = c + dd / MathF.Sqrt(l2) * r;
							_q[b + j] = _q[b + j].Lerp(_p[b + j], slide);
						}
					}
				}
			}
			for (int j = 2; j <= _seg; j++)   // bending stiffness: a lock curves, it does not kink or flap
			{
				Vector3 dir = (_p[b + j - 1] - _p[b + j - 2]).Normalized();
				Vector3 moved = _p[b + j].Lerp(_p[b + j - 1] + dir * L, bend);
				_q[b + j] += moved - _p[b + j];
				_p[b + j] = moved;
			}
			for (int j = 1; j <= _seg; j++)   // last: keep the lengths
			{
				Vector3 a = _p[b + j - 1];
				Vector3 d = _p[b + j] - a;
				float l = d.Length();
				if (l > 1e-6f) _p[b + j] = a + d * (L / l);
			}
		}
		_hprev = h;
	}

	// ---------------------------------------------------------------- the braid's mesh (hair.gd `_plait_mesh`, same shape)
	// It was rebuilt every frame in GDScript through lambdas (~1,200 triangles): ~1.4 ms a frame. This refills one
	// ArrayMesh in place. line = the plait's centre line (world), sideRef = the head's left-right.
	private const int P_PERIODS = 4, P_STEPS = 8, P_SIDES = 6, P_TAB = 32;
	private readonly System.Collections.Generic.List<Vector3> _pv = new(), _pn = new();
	private readonly System.Collections.Generic.List<Color> _pc = new();

	private static Vector3 Cr(Vector3[] line, float f)
	{
		float x = Math.Clamp(f, 0f, 1f) * (line.Length - 1);
		int i = Math.Min((int)x, line.Length - 2);
		float t = x - i;
		Vector3 p0 = line[Math.Max(i - 1, 0)], p1 = line[i], p2 = line[i + 1], p3 = line[Math.Min(i + 2, line.Length - 1)];
		return 0.5f * ((2f * p1) + (-p0 + p2) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t * t + (-p0 + 3f * p1 - 3f * p2 + p3) * t * t * t);
	}

	private void Tri(Vector3 a, Vector3 b, Vector3 c, Color col, Vector3 mid)
	{
		Vector3 n = (b - a).Cross(c - a);
		if (n.LengthSquared() < 1e-14f) return;
		n = n.Normalized();
		if (n.Dot((a + b + c) / 3f - mid) < 0f) n = -n;
		_pv.Add(a); _pv.Add(b); _pv.Add(c); _pn.Add(n); _pn.Add(n); _pn.Add(n); _pc.Add(col); _pc.Add(col); _pc.Add(col);
	}

	private struct Ring { public Vector3 C; public Color Col; public Vector3[] P; }

	private static Ring MakeRing(Vector3 c, Vector3 t, Vector3 w, float rw, float rh, Color col, float twist)
	{
		Vector3 h = t.Cross(w).Normalized();
		var r = new Ring { C = c, Col = col, P = new Vector3[P_SIDES] };
		for (int k = 0; k < P_SIDES; k++)
		{
			float a = Mathf.Tau * (k + 0.5f) / P_SIDES + twist;
			r.P[k] = c + w * MathF.Cos(a) * rw + h * MathF.Sin(a) * rh;
		}
		return r;
	}

	private void Tube(Ring[] rings)
	{
		for (int r = 0; r < rings.Length - 1; r++)
		{
			Ring A = rings[r], B = rings[r + 1];
			Vector3 mid = (A.C + B.C) * 0.5f;
			for (int k = 0; k < P_SIDES; k++)
			{
				Vector3 a0 = A.P[k], a1 = A.P[(k + 1) % P_SIDES], b0 = B.P[k], b1 = B.P[(k + 1) % P_SIDES];
				Tri(a0, b0, a1, B.Col, mid); Tri(a1, b0, b1, B.Col, mid);
			}
		}
	}

	/// the braid from the sim's own points: the centre line = the mean of the tail guides (hair.gd `_plait_line`), in world
	/// space (origin = the head)
	public void PlaitFromSim(ArrayMesh am, Vector3 origin, bool helmet, Vector3 sideRef, Color baseCol, float r0, float r1)
	{
		var line = new Vector3[_s1];
		int n = 0;
		for (int i = 0; i < _g; i++)
		{
			if (!(helmet || i < _g * 6 / 10)) continue;
			n++;
			for (int j = 0; j < _s1; j++) line[j] += _p[i * _s1 + j];
		}
		for (int j = 0; j < _s1; j++) line[j] = line[j] / Math.Max(1, n) + origin;
		PlaitInto(am, line, sideRef, baseCol, r0, r1);
	}

	public void PlaitInto(ArrayMesh am, Vector3[] line, Vector3 sideRef, Color baseCol, float r0, float r1)
	{
		_pv.Clear(); _pn.Clear(); _pc.Clear();
		var wt = new Vector3[P_TAB + 1];
		Vector3 wRun = sideRef.Normalized();
		for (int m = 0; m <= P_TAB; m++)
		{
			float fm = (float)m / P_TAB;
			Vector3 tm = (Cr(line, fm + 0.02f) - Cr(line, fm - 0.02f)).Normalized();
			Vector3 wn = wRun - tm * wRun.Dot(tm);
			if (wn.LengthSquared() > 1e-8f) wRun = wn.Normalized();
			wt[m] = wRun;
		}
		(Vector3 p, Vector3 t, Vector3 w) Frame(float f)
		{
			Vector3 p = Cr(line, f);
			Vector3 t = (Cr(line, f + 0.02f) - Cr(line, f - 0.02f)).Normalized();
			float x = Math.Clamp(f, 0f, 1f) * P_TAB;
			int i = Math.Min((int)x, P_TAB - 1);
			Vector3 w = wt[i].Lerp(wt[i + 1], x - i);
			w = (w - t * w.Dot(t)).Normalized();
			return (p, t, w);
		}
		var f0 = Frame(0f);
		Color band = baseCol.Darkened(0.55f);
		Tube(new[] { MakeRing(f0.p - f0.t * 0.004f, f0.t, f0.w, r0 * 0.75f, r0 * 0.75f, band, 0f),
			MakeRing(f0.p + f0.t * 0.012f, f0.t, f0.w, r0 * 0.75f, r0 * 0.75f, band, 0f) });
		float endF = 0.9f;
		int samples = P_PERIODS * P_STEPS;
		for (int s = 0; s < 3; s++)
		{
			Color shade = s == 0 ? baseCol.Lightened(0.1f) : (s == 1 ? baseCol : baseCol.Darkened(0.12f));
			var rings = new Ring[samples + 1];
			for (int m = 0; m <= samples; m++)
			{
				float u = (float)m / samples;
				float f = 0.03f + endF * u;
				var F = Frame(f);
				Vector3 h = F.t.Cross(F.w).Normalized();
				float r = Mathf.Lerp(r0, r1, f);
				float ph = Mathf.Tau * P_PERIODS * u + Mathf.Tau * s / 3f;
				float grow = Math.Min(1f, u * 8f);
				Vector3 c = F.p + (F.w * MathF.Cos(ph) + h * MathF.Sin(ph) * 0.8f) * r * 0.62f * grow;
				rings[m] = MakeRing(c, F.t, F.w, r * 0.38f, r * 0.38f, shade, 0f);
			}
			Tube(rings);
		}
		var fe = Frame(endF + 0.03f);
		Vector3 tip = Cr(line, 1f) + fe.t * 0.02f;
		Tube(new[] { MakeRing(fe.p, fe.t, fe.w, r1 * 0.6f, r1 * 0.6f, band, 0f),
			MakeRing(fe.p + fe.t * 0.01f, fe.t, fe.w, r1 * 0.6f, r1 * 0.6f, band, 0f),
			MakeRing(fe.p + fe.t * 0.025f, fe.t, fe.w, r1 * 1.25f, r1 * 1.0f, baseCol, 0.5f),
			MakeRing(tip.Lerp(fe.p, 0.25f), fe.t, fe.w, r1 * 0.8f, r1 * 0.6f, baseCol.Darkened(0.05f), 0.2f),
			MakeRing(tip, fe.t, fe.w, r1 * 0.05f, r1 * 0.05f, baseCol.Darkened(0.1f), 0f) });
		am.ClearSurfaces();
		if (_pv.Count == 0) return;
		var arr = new Godot.Collections.Array();
		arr.Resize((int)Mesh.ArrayType.Max);
		arr[(int)Mesh.ArrayType.Vertex] = _pv.ToArray();
		arr[(int)Mesh.ArrayType.Normal] = _pn.ToArray();
		arr[(int)Mesh.ArrayType.Color] = _pc.ToArray();
		am.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arr);
	}
}
