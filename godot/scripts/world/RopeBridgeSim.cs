using Godot;
using System;

/// A rope bridge (world/rope_bridge.gd): four ropes of N segments each - the two deck ropes the planks lie
/// on and the two hand ropes - plus the planks' cross ties and the hangers from hand rope down to deck rope.
/// Position-based dynamics (Verlet + distance constraints, several substeps), all in the bridge's own frame:
/// x = along (u), y = up, z = across (w). Ends pinned (tied round the trees). Gravity, damping, wind gusts,
/// and the rider's weight / sideways push are forces on the deck nodes, so the deck sags into a V under the
/// bike, rolls when the weight is off centre and swings. Queries: the deck's height under a point, the
/// deck's own sideways move under a point (carries the bike), and draw buffers (planks + rope tubes).
public partial class RopeBridgeSim : RefCounted
{
	const float G = 9.81f;
	int _n, _m;                       // segments per rope, nodes per rope (n + 1)
	float[] _x, _y, _z, _ox, _oy, _oz;   // now / previous substep (Verlet)
	float[] _ax, _ay, _az;            // external acceleration this tick
	float[] _tx, _ty, _tz, _sx, _sy, _sz;   // end of the last tick / of the tick before (drawing, carry)
	float[] _iw;                      // inverse mass (0 = pinned)
	int[] _ca, _cb;
	float[] _rest, _k;
	bool[] _rope;                     // tension only
	int _cc;
	// planks: s (node index, fractional), t0, t1 (across, 0 = left rope, 1 = right), colour
	float[] _ps, _pt0, _pt1, _pr, _pg, _pb;
	float _plankLen = 0.24f, _plankThick = 0.045f;
	float _time;
	public float HangerK = 0.35f;
	public float DiagK = 0f;     // plank shear stiffness (any made the deck rigid sideways: it hardly swung)

	int DL(int i) => i;
	int DR(int i) => _m + i;
	int HL(int i) => 2 * _m + i;
	int HR(int i) => 3 * _m + i;

	/// n segments; deck from (u0, y0) to (u1, y1), +-hw across, sagging `sag` in the middle; hand ropes from
	/// hu0 to hu1, hh above the deck ends, +-hhw across, sagging hsag; node masses (kg)
	public void Setup(int n, float u0, float y0, float u1, float y1, float hw, float sag,
		float hu0, float hu1, float hh, float hhw, float hsag, float mDeck, float mHand)
	{
		_n = n; _m = n + 1;
		int cnt = 4 * _m;
		_x = new float[cnt]; _y = new float[cnt]; _z = new float[cnt];
		_ox = new float[cnt]; _oy = new float[cnt]; _oz = new float[cnt];
		_ax = new float[cnt]; _ay = new float[cnt]; _az = new float[cnt];
		_tx = new float[cnt]; _ty = new float[cnt]; _tz = new float[cnt];
		_sx = new float[cnt]; _sy = new float[cnt]; _sz = new float[cnt];
		_iw = new float[cnt];
		for (int i = 0; i < _m; i++)
		{
			float f = (float)i / n;
			float dy = y0 + (y1 - y0) * f - 4f * sag * f * (1f - f);
			float du = u0 + (u1 - u0) * f;
			float hy = y0 + (y1 - y0) * f + hh - 4f * hsag * f * (1f - f);
			float hu = hu0 + (hu1 - hu0) * f;
			Set(DL(i), du, dy, -hw); Set(DR(i), du, dy, hw);
			Set(HL(i), hu, hy, -hhw); Set(HR(i), hu, hy, hhw);
			bool pin = i == 0 || i == n;
			_iw[DL(i)] = _iw[DR(i)] = pin ? 0f : 1f / mDeck;
			_iw[HL(i)] = _iw[HR(i)] = pin ? 0f : 1f / mHand;
		}
		int cap = 4 * n + _m + 2 * n + 2 * _m;
		_ca = new int[cap]; _cb = new int[cap]; _rest = new float[cap]; _k = new float[cap]; _rope = new bool[cap];
		_cc = 0;
		for (int i = 0; i < n; i++)
		{
			Add(DL(i), DL(i + 1), 1f, false); Add(DR(i), DR(i + 1), 1f, false);
			Add(HL(i), HL(i + 1), 1f, false); Add(HR(i), HR(i + 1), 1f, false);
			if (DiagK > 0f) { Add(DL(i), DR(i + 1), DiagK, false); Add(DR(i), DL(i + 1), DiagK, false); }   // planks resist shear a little
		}
		for (int i = 0; i < _m; i++)
		{
			Add(DL(i), DR(i), 1f, false);            // the plank: fixed width
			if (i > 0 && i < n)
			{
				Add(HL(i), DL(i), HangerK, true);    // hangers: rope, pull only
				Add(HR(i), DR(i), HangerK, true);
			}
		}
		Snap();
		// settle into the hanging shape before anyone sees it (heavily damped)
		for (int k = 0; k < 360; k++)
			Tick(1f / 60f, 0, 0, 0.9f);
		Snap(); Snap();
	}

	void Set(int a, float x, float y, float z)
	{
		_x[a] = _ox[a] = x; _y[a] = _oy[a] = y; _z[a] = _oz[a] = z;
	}

	void Add(int a, int b, float k, bool rope)
	{
		float dx = _x[b] - _x[a], dy = _y[b] - _y[a], dz = _z[b] - _z[a];
		_ca[_cc] = a; _cb[_cc] = b; _rest[_cc] = MathF.Sqrt(dx * dx + dy * dy + dz * dz); _k[_cc] = k; _rope[_cc] = rope;
		_cc++;
	}

	void Snap()
	{
		Array.Copy(_tx, _sx, _tx.Length); Array.Copy(_ty, _sy, _ty.Length); Array.Copy(_tz, _sz, _tz.Length);
		Array.Copy(_x, _tx, _x.Length); Array.Copy(_y, _ty, _y.Length); Array.Copy(_z, _tz, _z.Length);
	}

	// ------------------------------------------------------------------ dynamics

	/// a force (N) on the deck at (u, w): fy up, fw across (+ = right rope's side)
	public void AddLoad(float u, float w, float fy, float fw)
	{
		if (!Param(u, w, 0.3f, out float s, out float t))
			return;
		int i = Math.Min((int)s, _n - 1);
		float fs = s - i;
		t = Math.Clamp(t, 0f, 1f);
		Push(DL(i), (1 - fs) * (1 - t), fy, fw);
		Push(DL(i + 1), fs * (1 - t), fy, fw);
		Push(DR(i), (1 - fs) * t, fy, fw);
		Push(DR(i + 1), fs * t, fy, fw);
	}

	void Push(int a, float wgt, float fy, float fw)
	{
		_ay[a] += fy * wgt * _iw[a];
		_az[a] += fw * wgt * _iw[a];
	}

	/// one physics tick: wind (m/s, in the bridge's frame) blows on the ropes and planks
	public void Step(float dt, float windX, float windZ)
	{
		_time += dt;
		Tick(dt, windX, windZ, 0.9985f);
		Snap();
		Array.Clear(_ax); Array.Clear(_ay); Array.Clear(_az);
	}

	void Tick(float dt, float windX, float windZ, float damp)
	{
		const int SUB = 4, ITER = 10;
		float h = dt / SUB;
		int cnt = _x.Length;
		for (int sub = 0; sub < SUB; sub++)
		{
			for (int a = 0; a < cnt; a++)
			{
				if (_iw[a] == 0f)
					continue;
				// gusts roll along the bridge; drag ~ wind speed squared, a wide plank catches more than a rope
				float along = _x[a] * 0.21f;
				float gust = 0.6f + 0.4f * MathF.Sin(_time * 1.3f + along) * MathF.Sin(_time * 0.47f + along * 0.6f + 1.1f);
				float cw = a < 2 * _m ? 0.05f : 0.07f;
				float vx = windX * gust, vz = windZ * gust;
				float ax = _ax[a] + cw * vx * MathF.Abs(vx);
				float ay = _ay[a] - G;
				float az = _az[a] + cw * vz * MathF.Abs(vz);
				float nx = _x[a] + (_x[a] - _ox[a]) * damp + ax * h * h;
				float ny = _y[a] + (_y[a] - _oy[a]) * damp + ay * h * h;
				float nz = _z[a] + (_z[a] - _oz[a]) * damp + az * h * h;
				_ox[a] = _x[a]; _oy[a] = _y[a]; _oz[a] = _z[a];
				_x[a] = nx; _y[a] = ny; _z[a] = nz;
			}
			for (int it = 0; it < ITER; it++)
			{
				for (int c = 0; c < _cc; c++)
				{
					int a = _ca[c], b = _cb[c];
					float wa = _iw[a], wb = _iw[b];
					float ws = wa + wb;
					if (ws == 0f)
						continue;
					float dx = _x[b] - _x[a], dy = _y[b] - _y[a], dz = _z[b] - _z[a];
					float d = MathF.Sqrt(dx * dx + dy * dy + dz * dz);
					if (d < 1e-6f)
						continue;
					float diff = d - _rest[c];
					if (_rope[c] && diff <= 0f)
						continue;
					if (_rope[c] && it > 0)
						continue;   // hangers: once a substep, soft (they stretch a little: the deck can swing under them)
					float corr = diff / (d * ws) * _k[c];
					_x[a] += dx * corr * wa; _y[a] += dy * corr * wa; _z[a] += dz * corr * wa;
					_x[b] -= dx * corr * wb; _y[b] -= dy * corr * wb; _z[b] -= dz * corr * wb;
				}
			}
		}
	}

	// ------------------------------------------------------------------ queries (end-of-tick state)

	/// the deck point under (u, w): s = node index (fractional), t = across (0 left rope .. 1 right);
	/// false if (u, w) is off the deck by more than `margin` metres
	bool Param(float u, float w, float margin, out float s, out float t)
	{
		s = 0; t = 0;
		float c0 = (_tx[DL(0)] + _tx[DR(0)]) * 0.5f, c1 = (_tx[DL(_n)] + _tx[DR(_n)]) * 0.5f;
		if (u < c0 || u > c1)
			return false;
		int lo = 0, hi = _n;   // the segment whose centre-line u range holds u
		while (hi - lo > 1)
		{
			int mid = (lo + hi) >> 1;
			if ((_tx[DL(mid)] + _tx[DR(mid)]) * 0.5f <= u) lo = mid; else hi = mid;
		}
		float ua = (_tx[DL(lo)] + _tx[DR(lo)]) * 0.5f, ub = (_tx[DL(hi)] + _tx[DR(hi)]) * 0.5f;
		float fs = ub > ua ? (u - ua) / (ub - ua) : 0f;
		s = lo + fs;
		float lx = _tx[DL(lo)] + (_tx[DL(hi)] - _tx[DL(lo)]) * fs, lz = _tz[DL(lo)] + (_tz[DL(hi)] - _tz[DL(lo)]) * fs;
		float rx = _tx[DR(lo)] + (_tx[DR(hi)] - _tx[DR(lo)]) * fs, rz = _tz[DR(lo)] + (_tz[DR(hi)] - _tz[DR(lo)]) * fs;
		float ex = rx - lx, ez = rz - lz;
		float l2 = ex * ex + ez * ez;
		if (l2 < 1e-6f)
			return false;
		t = ((u - lx) * ex + (w - lz) * ez) / l2;
		float m = margin / MathF.Sqrt(l2);
		return t >= -m && t <= 1f + m;
	}

	Vector3 At(float[] X, float[] Y, float[] Z, float s, float t)
	{
		int i = Math.Clamp((int)s, 0, _n - 1);
		float fs = Math.Clamp(s - i, 0f, 1f);
		int l0 = DL(i), l1 = DL(i + 1), r0 = DR(i), r1 = DR(i + 1);
		float lx = X[l0] + (X[l1] - X[l0]) * fs, ly = Y[l0] + (Y[l1] - Y[l0]) * fs, lz = Z[l0] + (Z[l1] - Z[l0]) * fs;
		float rx = X[r0] + (X[r1] - X[r0]) * fs, ry = Y[r0] + (Y[r1] - Y[r0]) * fs, rz = Z[r0] + (Z[r1] - Z[r0]) * fs;
		return new Vector3(lx + (rx - lx) * t, ly + (ry - ly) * t, lz + (rz - lz) * t);
	}

	/// the deck top under (u, w), NaN off the deck (margin: how far past a rope still counts, a tyre's half width)
	public float Height(float u, float w, float margin)
	{
		if (!Param(u, w, margin, out float s, out float t))
			return float.NaN;
		return At(_tx, _ty, _tz, s, Math.Clamp(t, 0f, 1f)).Y;
	}

	/// how far the deck under (u, w) moved along / across in the last tick (u, w)
	public Vector2 Carry(float u, float w)
	{
		if (!Param(u, w, 0.3f, out float s, out float t))
			return Vector2.Zero;
		t = Math.Clamp(t, 0f, 1f);
		Vector3 a = At(_tx, _ty, _tz, s, t), b = At(_sx, _sy, _sz, s, t);
		return new Vector2(a.X - b.X, a.Z - b.Z);
	}

	/// the deck's centre point at fraction f of the length (tests): (u, y, w)
	public Vector3 Centre(float f) => At(_tx, _ty, _tz, f * _n, 0.5f);

	// ------------------------------------------------------------------ drawing

	float[] _dx, _dy, _dz;   // interpolated draw state

	void DrawState(float a)
	{
		int cnt = _x.Length;
		if (_dx == null || _dx.Length != cnt) { _dx = new float[cnt]; _dy = new float[cnt]; _dz = new float[cnt]; }
		for (int i = 0; i < cnt; i++)
		{
			_dx[i] = _sx[i] + (_tx[i] - _sx[i]) * a;
			_dy[i] = _sy[i] + (_ty[i] - _sy[i]) * a;
			_dz[i] = _sz[i] + (_tz[i] - _sz[i]) * a;
		}
	}

	/// planks: s, t0, t1, r, g, b per plank (6 floats each)
	public void SetPlanks(float[] p, float len, float thick)
	{
		int k = p.Length / 6;
		_ps = new float[k]; _pt0 = new float[k]; _pt1 = new float[k]; _pr = new float[k]; _pg = new float[k]; _pb = new float[k];
		for (int i = 0; i < k; i++)
		{
			_ps[i] = p[i * 6]; _pt0[i] = p[i * 6 + 1]; _pt1[i] = p[i * 6 + 2];
			_pr[i] = p[i * 6 + 3]; _pg[i] = p[i * 6 + 4]; _pb[i] = p[i * 6 + 5];
		}
		_plankLen = len; _plankThick = thick;
	}

	/// MultiMesh buffer (transform 3x4 row-major + colour) for the planks, drawn at fraction a between ticks
	public float[] PlankBuffer(float a)
	{
		DrawState(a);
		int k = _ps.Length;
		var o = new float[k * 16];
		for (int i = 0; i < k; i++)
		{
			float s = _ps[i], tm = (_pt0[i] + _pt1[i]) * 0.5f;
			Vector3 p0 = At(_dx, _dy, _dz, s, _pt0[i]), p1 = At(_dx, _dy, _dz, s, _pt1[i]);
			Vector3 fa = At(_dx, _dy, _dz, Math.Max(0f, s - 0.1f), tm), fb = At(_dx, _dy, _dz, Math.Min(_n, s + 0.1f), tm);
			Vector3 X = (fb - fa).Normalized();
			Vector3 Z = p1 - p0;
			float wid = Z.Length();
			Z -= X * X.Dot(Z);
			Z = Z.Normalized();
			Vector3 Y = Z.Cross(X).Normalized();
			Vector3 c = (p0 + p1) * 0.5f - Y * (_plankThick * 0.5f);
			Vector3 bx = X * _plankLen, by = Y * _plankThick, bz = Z * wid;
			int j = i * 16;
			o[j] = bx.X; o[j + 1] = by.X; o[j + 2] = bz.X; o[j + 3] = c.X;
			o[j + 4] = bx.Y; o[j + 5] = by.Y; o[j + 6] = bz.Y; o[j + 7] = c.Y;
			o[j + 8] = bx.Z; o[j + 9] = by.Z; o[j + 10] = bz.Z; o[j + 11] = c.Z;
			o[j + 12] = _pr[i]; o[j + 13] = _pg[i]; o[j + 14] = _pb[i]; o[j + 15] = 1f;
		}
		return o;
	}

	readonly System.Collections.Generic.List<Vector3> _v = new();
	readonly System.Collections.Generic.List<Vector3> _nm = new();
	readonly System.Collections.Generic.List<int> _ix = new();
	Vector3[] _line = new Vector3[512];

	/// the rope tubes (deck ropes under the plank ends, hand ropes, hangers): [verts, normals, indices]
	public Godot.Collections.Array RopeMesh(float a)
	{
		DrawState(a);
		_v.Clear(); _nm.Clear(); _ix.Clear();
		const int SUBD = 3;
		for (int r = 0; r < 4; r++)
		{
			int b = r * _m;
			float drop = r < 2 ? -0.03f : 0f;
			int cnt = 0;
			for (int i = 0; i < _n; i++)
			{
				Vector3 p0 = P(b + Math.Max(0, i - 1)), p1 = P(b + i), p2 = P(b + i + 1), p3 = P(b + Math.Min(_n, i + 2));
				for (int k = 0; k < SUBD; k++)
				{
					float t = (float)k / SUBD;
					_line[cnt++] = CatmullRom(p0, p1, p2, p3, t) + new Vector3(0, drop, 0);
				}
			}
			_line[cnt++] = P(b + _n) + new Vector3(0, drop, 0);
			Tube(cnt, r < 2 ? 0.026f : 0.022f, 6);
		}
		for (int i = 1; i < _n; i++)
		{
			for (int side = 0; side < 2; side++)
			{
				int h = side == 0 ? HL(i) : HR(i), d = side == 0 ? DL(i) : DR(i);
				_line[0] = P(h); _line[1] = P(d) + new Vector3(0, -0.03f, 0);
				Tube(2, 0.010f, 4);
			}
		}
		return new Godot.Collections.Array { _v.ToArray(), _nm.ToArray(), _ix.ToArray() };
	}

	Vector3 P(int a) => new Vector3(_dx[a], _dy[a], _dz[a]);

	static Vector3 CatmullRom(Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3, float t)
	{
		float t2 = t * t, t3 = t2 * t;
		return 0.5f * (2f * p1 + (p2 - p0) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 + (3f * p1 - p0 - 3f * p2 + p3) * t3);
	}

	void Tube(int cnt, float rad, int sides)
	{
		int start = _v.Count;
		for (int i = 0; i < cnt; i++)
		{
			Vector3 T = (_line[Math.Min(cnt - 1, i + 1)] - _line[Math.Max(0, i - 1)]).Normalized();
			Vector3 N = T.Cross(Vector3.Up);
			if (N.LengthSquared() < 1e-4f) N = T.Cross(Vector3.Right);
			N = N.Normalized();
			Vector3 B = T.Cross(N);
			for (int k = 0; k < sides; k++)
			{
				float ang = k * MathF.Tau / sides;
				Vector3 n = N * MathF.Cos(ang) + B * MathF.Sin(ang);
				_v.Add(_line[i] + n * rad);
				_nm.Add(n);
			}
		}
		for (int i = 0; i < cnt - 1; i++)
		{
			for (int k = 0; k < sides; k++)
			{
				int a0 = start + i * sides + k, a1 = start + i * sides + (k + 1) % sides;
				int b0 = a0 + sides, b1 = a1 + sides;
				_ix.Add(a0); _ix.Add(b0); _ix.Add(a1);
				_ix.Add(a1); _ix.Add(b0); _ix.Add(b1);
			}
		}
	}
}
