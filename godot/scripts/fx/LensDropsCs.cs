using Godot;
using System;

/// Water drops on the camera lens as mass points (after Nakata, Kakimoto & Nishita, "Real-Time Animation of
/// Droplets on a Hydrophobic Windshield", and Kaneda et al. 1993, "Animation of Water Droplets on a Glass Plate"):
///  * pinning (contact-angle hysteresis) holds a drop until the push beats it: ~ radius (its contact line),
///    with a noisy strength over the glass (dirt, coating) so drops stop and go and meander
///  * gravity ~ r^3 (its mass), the air over the glass ~ r^2 x airspeed^2. On a forward-facing lens the air
///    parts at the middle (stagnation point) and speeds up outward, so at speed the big drops let go first
///    and stream off to the edges, small beads stay stuck near the middle
///  * a moving drop leaves small beads behind it (its trail) and swallows the drops in its way: it grows
///    and runs faster
///  * glass friction ~ the contact: a moving drop runs at (push - pin) / (FRICTION r)
/// Units: screen heights; x in 0..aspect, y 0..1 down. Fed / stepped by fx/lens_fx.gd; Buffer() fills the
/// MultiMesh that draws the drop map (shaders/lens_drop.gdshader) which grade.gdshader refracts through.
[GlobalClass]
public partial class LensDropsCs : RefCounted
{
	const int MAX = 1800;
	// SIZE scales every drop; the forces are scaled with it (pin x S^2, air x S, friction x S^2) so the drops
	// stick, let go and run exactly as before, only bigger (2026-11-24, user: "a little bigger in general")
	const float SIZE = 1.215f;   // 1.35 was a touch too big (user: "10 % smaller")
	const float G = 1.4f;            // gravity's pull per unit mass
	const float PIN = 0.00028f * SIZE * SIZE;   // pinning per unit radius: alone, gravity moves drops past r ~ 0.014 x SIZE
	const float AIR = 0.43f * SIZE;  // the air's push per r^2 per airspeed^2
	const float FRICTION = 0.0019f * SIZE * SIZE;
	const float KINETIC = 0.65f;     // a moving drop's pinning (moving contact line): less than standing
	const float R_MIN = 0.0012f * SIZE;
	const float V_MAX = 3.0f;
	const float FAN = 0.55f;         // how much the upward flow spreads out toward the sides (per screen height off centre)

	readonly float[] _x = new float[MAX], _y = new float[MAX], _r = new float[MAX];
	readonly float[] _vx = new float[MAX], _vy = new float[MAX], _trav = new float[MAX];
	readonly float[] _px = new float[MAX], _py = new float[MAX];   // where it was last step (the rivulet segment)
	float[] _tbuf = Array.Empty<float>();
	int _tn;
	readonly bool[] _mov = new bool[MAX];
	// each drop's own life: how long since it hit the glass, how long it clings there first (a splash drop sits
	// still ~half a second or a bit more, then lets go: user, 2026-11-25), and its own wander (a slow random turn + a phase for
	// its stick-slip) so no two run the same straight line
	readonly float[] _age = new float[MAX], _hold = new float[MAX], _wan = new float[MAX], _seed = new float[MAX];
	readonly float[] _fx = new float[MAX], _fy = new float[MAX], _load = new float[MAX];   // the push's direction, how near it is to letting go (0..1)
	readonly bool[] _splat = new bool[MAX];   // landed from a splash: drawn as an impact that pulls into a bead
	const float HOLD_EASE = 0.3f;    // after its hold the grip lets go over this long (the drop wets out, sags, then goes)
	const float WANDER = 0.12f;      // rad: how far a running drop's own wander turns it off the push (0.75 zig-zagged: user, 2026-11-27)
	const float GLASS_TURN = 0.15f;  // rad, peak to peak: how much the glass's own pattern turns it (was 0.9)
	const float PATH_TURN = 0.1f;    // rad, peak to peak: a slow bend along its own path (was 0.6)
	const float WANDER_RATE = 5f;    // 1/s: how quickly that wander changes
	const float STUTTER = 0.8f;      // 0..1: a running drop's speed swings this much (catches on the glass, lets go)
	int _n;
	readonly Random _rng = new Random(1234);
	float _rainAcc;
	float[] _buf = Array.Empty<float>();
	// merge grid
	const float CELL = 0.04f;
	int[] _head = Array.Empty<int>();
	readonly int[] _next = new int[MAX];

	public int Count() => _n;
	/// test probe: (x, y, radius, age) of drop i
	public Vector4 Get(int i) => i < _n ? new Vector4(_x[i], _y[i], _r[i], _age[i]) : Vector4.Zero;
	public void Clear() { _n = 0; _rainAcc = 0f; }

	float Rnd() => (float)_rng.NextDouble();

	// drop sizes: many small, few big (power law)
	float RandR(float rmin, float rmax) => (rmin + (rmax - rmin) * MathF.Pow(Rnd(), 2.6f)) * SIZE;

	public void Add(float x, float y, float r) => Add(x, y, r, 0f);

	public void Add(float x, float y, float r, float hold)
	{
		if (r < R_MIN) return;
		if (_n >= MAX)
		{   // full: drop the smallest of a few
			int lo = _rng.Next(_n);
			for (int k = 0; k < 6; k++) { int j = _rng.Next(_n); if (_r[j] < _r[lo]) lo = j; }
			if (_r[lo] >= r) return;
			Set(lo, x, y, r, hold);
			return;
		}
		Set(_n++, x, y, r, hold);
	}

	void Set(int i, float x, float y, float r, float hold)
	{
		_age[i] = 0f; _hold[i] = hold; _fx[i] = 0f; _fy[i] = 1f; _load[i] = 0f; _splat[i] = hold > 0.25f; _wan[i] = (Rnd() - 0.5f) * WANDER; _seed[i] = Rnd() * 100f;
		_x[i] = x; _y[i] = y; _px[i] = x; _py[i] = y; _r[i] = r; _vx[i] = 0f; _vy[i] = 0f; _trav[i] = 0f; _mov[i] = false;
	}

	/// a splash: count drops over the screen (more low down), sized rmin..rmax
	public void Splash(int count, float aspect, float rmin, float rmax)
	{
		for (int k = 0; k < count; k++)
		{
			float x = Rnd() * aspect, y = 1f - MathF.Pow(Rnd(), 0.7f), r = RandR(rmin, rmax);
			Add(x, y, r, 0.45f + 0.35f * Rnd());
			// a big splat throws a ring of fine mist beads round it (they cling and dry; the odd one joins it)
			if (r > 0.006f * SIZE)
			{
				int sat = 3 + _rng.Next(5);
				for (int j = 0; j < sat; j++)
				{
					float a = Rnd() * MathF.Tau, d = r * (1.4f + 1.6f * Rnd());
					Add(x + MathF.Cos(a) * d, y + MathF.Sin(a) * d, r * (0.1f + 0.14f * Rnd()), 0.6f);
				}
			}
		}
	}

	static float Hash(int x, int y)
	{
		uint h = (uint)(x * 374761393 + y * 668265263);
		h = (h ^ (h >> 13)) * 1274126177u;
		return ((h ^ (h >> 16)) & 0xffffff) / 16777215f;
	}

	static float Noise(float x, float y)
	{
		int ix = (int)MathF.Floor(x), iy = (int)MathF.Floor(y);
		float fx = x - ix, fy = y - iy;
		fx = fx * fx * (3f - 2f * fx); fy = fy * fy * (3f - 2f * fy);
		float a = Hash(ix, iy), b = Hash(ix + 1, iy), c = Hash(ix, iy + 1), d = Hash(ix + 1, iy + 1);
		return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
	}

	/// rain: drops per second landing on the glass; wind 0..1 = the air over it; (fx, fy) the view's middle;
	/// (flowX, flowY) = the air's direction over the glass in screen space (unit length; y down: forward motion = up)
	public void Step(float dt, float rain, float wind, float aspect, float fx, float fy, float dryRate, float flowX, float flowY)
	{
		if (dt <= 0f) return;
		_rainAcc += dt * rain * 140f;
		while (_rainAcc >= 1f) { _rainAcc -= 1f; Add(Rnd() * aspect, Rnd(), RandR(0.0015f, 0.011f), 0.1f + 0.25f * Rnd()); }

		int born = _n;   // beads left this step are appended after this
		for (int i = 0; i < born; i++)
		{
			_px[i] = _x[i]; _py[i] = _y[i];
			float r = _r[i];
			float m = r * r * r;
			float dx = _x[i] - fx, dy = _y[i] - fy;
			float d = MathF.Sqrt(dx * dx + dy * dy) + 1e-4f;
			// airflow: at speed the water streams DOWN the glass (windshield-style "up" read as inverted) and fans out a little toward
			// the sides, about as strong everywhere; cornering pushes the water to the outside of the turn.
			// (A radial flow out of the view's middle looked like a hyperspace jump: user, 2026-11-24.)
			// (flowX, flowY) = the way the air runs over the glass on screen, from the camera's own motion;
			// the forward part (flowY > 0: streaming down the glass) fans out toward the sides
			float ax = flowX + dx * FAN * MathF.Max(flowY, 0f), ay = flowY;
			float al = MathF.Sqrt(ax * ax + ay * ay) + 1e-5f;
			float u = wind * (0.85f + 0.35f * MathF.Min(MathF.Abs(dx), 1f));
			float fa = AIR * u * u * r * r;
			float Fx = fa * ax / al, Fy = fa * ay / al + G * m;
			float F = MathF.Sqrt(Fx * Fx + Fy * Fy);
			if (F > 1e-9f) { _fx[i] = Fx / F; _fy[i] = Fy / F; }
			_age[i] += dt;
			// the drop's own wander: a slow random walk of its heading (pulled back toward straight)
			_wan[i] += ((Rnd() - 0.5f) * 2f * WANDER * MathF.Sqrt(WANDER_RATE * dt * 2f)) - _wan[i] * WANDER_RATE * dt * 0.5f;
			_wan[i] = Math.Clamp(_wan[i], -1.2f * WANDER, 1.2f * WANDER);
			float pin = PIN * r * (0.45f + 1.1f * Noise(_x[i] * 45f, _y[i] * 45f)) * (_mov[i] ? KINETIC : 1f);
			// fresh on the glass it clings (held far past any push), then its grip eases off
			float ho = _age[i] - _hold[i];
			if (ho < HOLD_EASE) pin *= 1f + 40f * (ho <= 0f ? 1f : 1f - ho / HOLD_EASE) * (ho <= 0f ? 1f : 1f - ho / HOLD_EASE);
			_load[i] += (Math.Clamp(F / (pin / (_mov[i] ? KINETIC : 1f) + 1e-12f), 0f, 1f) - _load[i]) * MathF.Min(1f, dt * 8f);
			if (F <= pin)
			{
				_mov[i] = false;
				_vx[i] *= MathF.Max(0f, 1f - dt * 25f); _vy[i] *= MathF.Max(0f, 1f - dt * 25f);
			}
			else
			{
				_mov[i] = true;
				float vt = MathF.Min((F - pin) / (FRICTION * r), V_MAX);   // runs at what glass friction lets it
				// meander: the glass's own pattern turns it a little (both ways)
				float turn = (Noise(_x[i] * 80f + 17f, _y[i] * 80f) - 0.5f) * GLASS_TURN + _wan[i]
					+ (Noise(_seed[i], _age[i] * 3f) - 0.5f) * PATH_TURN;
				// stick-slip: it catches on the glass and lets go, faster / slower along its own path
				vt *= 1f - STUTTER * Noise(_seed[i] + 31f, _age[i] * 4.5f) * Noise(_x[i] * 140f, _y[i] * 140f + _seed[i]);
				float cx = Fx / F, cy = Fy / F;
				float cs = MathF.Cos(turn), sn = MathF.Sin(turn);
				float tx = (cx * cs - cy * sn) * vt, ty = (cx * sn + cy * cs) * vt;
				float k = MathF.Min(1f, dt * 9f);
				_vx[i] += (tx - _vx[i]) * k; _vy[i] += (ty - _vy[i]) * k;
			}
			float sx = _vx[i] * dt, sy = _vy[i] * dt;
			_x[i] += sx; _y[i] += sy;
			if (_mov[i])
			{
				_trav[i] += MathF.Sqrt(sx * sx + sy * sy);
				// the trail: a bead left behind every couple of radii
				if (_trav[i] > r * 2.2f && r > 0.004f * SIZE)
				{
					_trav[i] = 0f;
					if (Rnd() < 0.75f)
					{
						float rb = r * (0.2f + 0.18f * Rnd());
						_r[i] = MathF.Cbrt(r * r * r - rb * rb * rb);
						Add(_x[i] - sx * 2f + (Rnd() - 0.5f) * r * 0.6f, _y[i] - sy * 2f + (Rnd() - 0.5f) * r * 0.6f, rb);
					}
				}
			}
			else
			{
				// still drops dry slowly (the air dries them faster)
				_r[i] -= dt * dryRate * (0.00008f + 0.0004f * wind) * SIZE;
			}
		}
		Merge(aspect);
		// cull: dried up / off the glass
		int w = 0;
		for (int i = 0; i < _n; i++)
		{
			if (_r[i] < R_MIN || _y[i] > 1.08f || _y[i] < -0.08f || _x[i] < -0.08f || _x[i] > aspect + 0.08f) continue;
			if (w != i) Copy(i, w);
			w++;
		}
		_n = w;
	}

	void Copy(int i, int w)
	{
		_px[w] = _px[i]; _py[w] = _py[i];
		_age[w] = _age[i]; _hold[w] = _hold[i]; _wan[w] = _wan[i]; _seed[w] = _seed[i];
		_fx[w] = _fx[i]; _fy[w] = _fy[i]; _load[w] = _load[i]; _splat[w] = _splat[i];
		_x[w] = _x[i]; _y[w] = _y[i]; _r[w] = _r[i]; _vx[w] = _vx[i]; _vy[w] = _vy[i]; _trav[w] = _trav[i]; _mov[w] = _mov[i];
	}

	// drops that touch run together into one (volume kept, momentum shared): a running drop sweeps its path
	void Merge(float aspect)
	{
		int gw = (int)(aspect / CELL) + 4, gh = (int)(1f / CELL) + 4;
		if (_head.Length < gw * gh) _head = new int[gw * gh];
		Array.Fill(_head, -1, 0, gw * gh);
		for (int i = 0; i < _n; i++)
		{
			int cx = Math.Clamp((int)((_x[i] + 0.08f) / CELL), 0, gw - 1);
			int cy = Math.Clamp((int)((_y[i] + 0.08f) / CELL), 0, gh - 1);
			int c = cx + cy * gw;
			_next[i] = _head[c]; _head[c] = i;
		}
		for (int i = 0; i < _n; i++)
		{
			if (_r[i] <= 0f) continue;
			int cx = Math.Clamp((int)((_x[i] + 0.08f) / CELL), 0, gw - 1);
			int cy = Math.Clamp((int)((_y[i] + 0.08f) / CELL), 0, gh - 1);
			for (int oy = -1; oy <= 1; oy++)
			for (int ox = -1; ox <= 1; ox++)
			{
				int gx = cx + ox, gy = cy + oy;
				if (gx < 0 || gy < 0 || gx >= gw || gy >= gh) continue;
				for (int j = _head[gx + gy * gw]; j >= 0; j = _next[j])
				{
					if (j <= i || _r[j] <= 0f || _r[i] <= 0f) continue;
					float dx = _x[j] - _x[i], dy = _y[j] - _y[i];
					float rr = (_r[i] + _r[j]) * 0.85f;
					if (dx * dx + dy * dy > rr * rr) continue;
					int a = _r[i] >= _r[j] ? i : j, b = a == i ? j : i;   // the bigger one takes the other in
					float va = _r[a] * _r[a] * _r[a], vb = _r[b] * _r[b] * _r[b], vs = va + vb;
					_x[a] = (_x[a] * va + _x[b] * vb) / vs; _y[a] = (_y[a] * va + _y[b] * vb) / vs;
					_vx[a] = (_vx[a] * va + _vx[b] * vb) / vs; _vy[a] = (_vy[a] * va + _vy[b] * vb) / vs;
					_r[a] = MathF.Cbrt(vs);
					_mov[a] = _mov[a] || _mov[b];
					if (_mov[a]) _hold[a] = MathF.Min(_hold[a], _age[a]);   // swallowed into a runner: no new cling
					_r[b] = 0f;
				}
			}
		}
	}

	public int TrailCount() => _tn;

	/// The rivulets: every running drop paints the stretch it ran this step as a thin wet channel (into a
	/// map that is never cleared, only dried: fx/lens_fx.gd). Its width wanders along the way like real
	/// rivulets (thicker where the drop slowed, pinched where it ran). Same layout as Buffer(), custom.x = 2.
	public float[] TrailBuffer(float vpH)
	{
		if (_tbuf.Length < MAX * 12) _tbuf = new float[MAX * 12];
		_tn = 0;
		for (int i = 0; i < _n; i++)
		{
			if (!_mov[i] || _r[i] < 0.003f * SIZE) continue;
			float dx = _x[i] - _px[i], dy = _y[i] - _py[i];
			float d = MathF.Sqrt(dx * dx + dy * dy);
			if (d < 1e-5f) continue;
			float c = dx / d, s = dy / d;
			float wob = 0.75f + 0.5f * Noise(_x[i] * 120f, _y[i] * 120f);
			float wid = 2f * _r[i] * 0.32f * wob * vpH;
			float len = (d + _r[i] * 0.4f) * vpH;
			int o = _tn * 12;
			_tbuf[o + 0] = c * len; _tbuf[o + 1] = -s * wid; _tbuf[o + 2] = 0f; _tbuf[o + 3] = (_x[i] + _px[i]) * 0.5f * vpH;
			_tbuf[o + 4] = s * len; _tbuf[o + 5] = c * wid; _tbuf[o + 6] = 0f; _tbuf[o + 7] = (_y[i] + _py[i]) * 0.5f * vpH;
			_tbuf[o + 8] = 2f; _tbuf[o + 9] = Math.Min(_r[i] * 12f * 0.7f, 1f); _tbuf[o + 10] = c; _tbuf[o + 11] = s;
			_tn++;
		}
		return _tbuf;
	}

	/// MultiMesh buffer (2D transform + custom data, 12 floats a drop) for a drop map vpH pixels high.
	/// Custom: x = how drawn-out (0 round .. 1 a long streak), y = radius x 12 (the dome's height = how far it
	/// bends the view), zw = its heading (cos, sin) to turn its normals to the screen.
	public float[] Buffer(float vpH)
	{
		if (_buf.Length < MAX * 12) _buf = new float[MAX * 12];   // always the MultiMesh's whole size
		for (int i = 0; i < _n; i++)
		{
			float r = _r[i];
			float sp = MathF.Sqrt(_vx[i] * _vx[i] + _vy[i] * _vy[i]);
			float k = Math.Clamp(sp * 1.1f, 0f, 1f);
			float c = _fx[i], s = _fy[i];
			if (sp > 1e-4f) { c = _vx[i] / sp; s = _vy[i] / sp; }
			// a still drop the push is nearly beating sags toward it (a teardrop about to go), like a sim's rain drops
			float sag = _mov[i] ? 0f : 0.35f * MathF.Max(0f, _load[i] - 0.45f) / 0.55f;
			k = MathF.Max(k, sag);
			// a splash drop lands as a flat splat and pulls together into its bead with a little wobble
			float spl = 1f, wsp = 1f, hk = 1f;
			if (_splat[i] && _age[i] < 0.35f)
			{
				float e = MathF.Exp(-_age[i] * 14f);
				spl = 1f + 0.75f * e * MathF.Cos(_age[i] * 38f);
				wsp = 1f + 0.75f * e * MathF.Cos(_age[i] * 38f + 1.4f);   // out of step: it rings, not just shrinks
				hk = 1f - 0.7f * e;
			}
			float len = 2f * r * (1f + 1.8f * k) * spl * vpH;   // a running drop is drawn out along its path
			float wid = 2f * r * (1f - 0.25f * k) * wsp * vpH;
			int o = i * 12;
			_buf[o + 0] = c * len; _buf[o + 1] = -s * wid; _buf[o + 2] = 0f; _buf[o + 3] = _x[i] * vpH;
			_buf[o + 4] = s * len; _buf[o + 5] = c * wid; _buf[o + 6] = 0f; _buf[o + 7] = _y[i] * vpH;
			_buf[o + 8] = k; _buf[o + 9] = Math.Min(r * 12f, 1f) * hk; _buf[o + 10] = c; _buf[o + 11] = s;
		}
		return _buf;
	}
}
