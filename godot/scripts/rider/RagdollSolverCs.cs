using System;
using Godot;

/// The crash ragdoll's constraint solver (rider/ragdoll.gd: the 6 passes of `_dist` over bones / limits and `_collide` per
/// part, each substep), in C#: it was ~half of the ragdoll's cost (frame profiler, 2026-11-24). Same maths, same order;
/// only the current contact model (not BMX_OLD_RAGCOL). ragdoll.gd builds the constraint list once per step (torn-off /
/// broken joints already left out) and hands the arrays in per substep; the results come back from the getters.
public partial class RagdollSolverCs : RefCounted
{
	private Vector3[] _p = Array.Empty<Vector3>(), _q = Array.Empty<Vector3>();
	private byte[] _touch = Array.Empty<byte>();
	private float[] _jn = Array.Empty<float>();
	private float _kick;
	private const float BOUNCE = 0.12f, BOUNCE_MIN = 3.0f, ROCK_SLIDE = 0.98f;

	/// cons: (a, b) pairs; clen: length; ck: stiffness; cmin: 1 = only stops it getting shorter (joint limits).
	/// shapes: 6 floats each (rock 1 / 0, x, z, y, R, H).
	public void Solve(Vector3[] p, Vector3[] q, float[] gh, Vector3[] gn, float[] rad, int[] cons, float[] clen, float[] ck,
		byte[] cmin, float[] shapes, float lastH, int iters, float[] jnIn)
	{
		_p = p; _q = q;
		int np = p.Length;
		if (_touch.Length != np) _touch = new byte[np]; else Array.Clear(_touch);
		_jn = jnIn;
		_kick = 0f;
		int nc = clen.Length, ns = shapes.Length / 6;
		for (int it = 0; it < iters; it++)
		{
			for (int c = 0; c < nc; c++)
			{
				int a = cons[2 * c], b = cons[2 * c + 1];
				Vector3 A = _p[a], B = _p[b];
				Vector3 d = B - A;
				float l = d.Length();
				if (l < 1e-6f || (cmin[c] != 0 && l >= clen[c])) continue;
				float k = (l - clen[c]) / l * 0.5f * ck[c];
				_p[a] = A + d * k;
				_p[b] = B - d * k;
			}
			for (int i = 0; i < np; i++) Collide(i, gh, gn, rad, shapes, ns, lastH);
		}
	}

	private static Vector3 SurfaceV(Vector3 v, Vector3 n)
	{
		if (!n.IsFinite()) return v;
		float vn = v.Dot(n);
		if (vn < 0f) v -= n * vn;
		Vector3 vt = v - n * v.Dot(n);
		return v - vt * (1f - ROCK_SLIDE);
	}

	private void Collide(int i, float[] gh, Vector3[] gn, float[] rad, float[] sh, int ns, float lastH)
	{
		Vector3 pp = _p[i], qq = _q[i];
		float r = rad[i];
		float g = gh[i] + r;
		if (pp.Y < g)
		{
			_touch[i] = 1;
			Vector3 v = pp - qq;
			pp.Y = g;
			Vector3 nrm = gn[i];
			float vn = v.Dot(nrm);
			if (vn < 0f)
			{
				float outv = -vn > BOUNCE_MIN * lastH ? -vn * BOUNCE : 0f;
				v += nrm * (-vn + outv);
				_jn[i] += -vn;
			}
			qq = pp - v;
			if (v.Y > 0f) _kick = Math.Max(_kick, v.Y / Math.Max(lastH, 1e-6f));
		}
		for (int s = 0; s < ns; s++)
		{
			int o = 6 * s;
			float cx = sh[o + 1], cz = sh[o + 2];
			float dx = pp.X - cx, dz = pp.Z - cz;
			if (sh[o] > 0.5f)
			{
				float cy = sh[o + 3], R = sh[o + 4] + r, H = sh[o + 5] + r;
				float dy = pp.Y - cy;
				if (dy < -r) continue;
				float k = MathF.Sqrt((dx / R) * (dx / R) + (dy / H) * (dy / H) + (dz / R) * (dz / R));
				if (k >= 1f || k < 1e-4f) continue;
				Vector3 vr = pp - qq;
				pp = new Vector3(cx + dx / k, cy + dy / k, cz + dz / k);
				qq = pp - SurfaceV(vr, new Vector3(dx / (R * R), dy / (H * H), dz / (R * R)).Normalized());
			}
			else
			{
				float d = MathF.Sqrt(dx * dx + dz * dz);
				float m = sh[o + 4] + r * 0.6f;
				if (d < m && d > 1e-4f)
				{
					Vector3 vc = pp - qq;
					pp.X = cx + dx / d * m;
					pp.Z = cz + dz / d * m;
					qq = pp - SurfaceV(vc, new Vector3(dx / d, 0f, dz / d));
				}
			}
		}
		_p[i] = pp; _q[i] = qq;
	}

	public Vector3[] GetP() => _p;
	public Vector3[] GetQ() => _q;
	public byte[] GetTouch() => _touch;
	public float[] GetJn() => _jn;
	public float GetKick() => _kick;
}
