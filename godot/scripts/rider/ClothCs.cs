using Godot;
using System;

/// <summary>
/// A small cloth patch (rows x cols particles, optionally closed into a tube) simulated with Verlet
/// integration and distance constraints: structural, shear and bend springs. Row 0 is pinned to
/// targets the caller moves every step (the body); the rest hangs, catches the airflow (relative to
/// the moving bike and the wind) and is pushed out of capsules (hips, thighs, arms). World space.
/// The hot loops run on plain float arrays (x / y / z apart) so they compile to tight code.
/// </summary>
[GlobalClass]
public partial class ClothCs : RefCounted
{
    int _rows, _cols, _n;
    bool _loop;
    float[] _px = Array.Empty<float>(), _py = Array.Empty<float>(), _pz = Array.Empty<float>();
    float[] _qx = Array.Empty<float>(), _qy = Array.Empty<float>(), _qz = Array.Empty<float>();
    float[] _nx = Array.Empty<float>(), _ny = Array.Empty<float>(), _nz = Array.Empty<float>();
    int[] _ca = Array.Empty<int>(), _cb = Array.Empty<int>();
    float[] _rest = Array.Empty<float>(), _stiff = Array.Empty<float>();
    float[] _cap = new float[64];   // capsules: ax ay az bx by bz r
    int _ncap;
    float[] _pin0 = Array.Empty<float>(), _pin1 = Array.Empty<float>();
    double _lastDt = 1.0 / 240.0;

    int Idx(int r, int c) => r * _cols + c;

    /// rest: rows*cols positions in the rest shape (sets the spring lengths and the start state)
    public void Setup(int rows, int cols, bool loop, Vector3[] rest)
    {
        _rows = rows; _cols = cols; _loop = loop; _n = rows * cols;
        _px = new float[_n]; _py = new float[_n]; _pz = new float[_n];
        _qx = new float[_n]; _qy = new float[_n]; _qz = new float[_n];
        _nx = new float[_n]; _ny = new float[_n]; _nz = new float[_n];
        _pin0 = new float[cols * 3]; _pin1 = new float[cols * 3];
        Reset(rest);
        var a = new System.Collections.Generic.List<int>();
        var b = new System.Collections.Generic.List<int>();
        var k = new System.Collections.Generic.List<float>();
        void Add(int i, int j, float s) { a.Add(i); b.Add(j); k.Add(s); }
        int cmax = loop ? cols : cols - 1;
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < cmax; c++) Add(Idx(r, c), Idx(r, (c + 1) % cols), 1f);          // around
        for (int r = 0; r < rows - 1; r++)
            for (int c = 0; c < cols; c++) Add(Idx(r, c), Idx(r + 1, c), 1f);                  // down
        for (int r = 0; r < rows - 1; r++)
            for (int c = 0; c < cmax; c++)
            {
                Add(Idx(r, c), Idx(r + 1, (c + 1) % cols), 0.6f);                               // shear
                Add(Idx(r, (c + 1) % cols), Idx(r + 1, c), 0.6f);
            }
        for (int r = 0; r < rows - 2; r++)
            for (int c = 0; c < cols; c++) Add(Idx(r, c), Idx(r + 2, c), 0.25f);               // bend (soft)
        _ca = a.ToArray(); _cb = b.ToArray(); _stiff = k.ToArray();
        _rest = new float[_ca.Length];
        for (int i = 0; i < _ca.Length; i++) _rest[i] = rest[_ca[i]].DistanceTo(rest[_cb[i]]);
    }

    /// jump the whole patch to a pose (teleports, respawns): no velocity
    public void Reset(Vector3[] pos)
    {
        for (int i = 0; i < _n && i < pos.Length; i++)
        {
            _px[i] = _qx[i] = pos[i].X; _py[i] = _qy[i] = pos[i].Y; _pz[i] = _qz[i] = pos[i].Z;
        }
    }

    /// a whole frame in one call: n substeps of h seconds, the pins sliding from `from` to `to`
    /// (so a body moving at speed doesn't tear the cloth between frames). caps: pairs (a, b), capR: radii.
    public void StepFrame(double h, int n, Vector3[] from, Vector3[] to, Vector3 wind, Vector3[] caps, float[] capR,
        float drag, float damping, int iters)
    {
        if (_n == 0 || n <= 0) return;
        _ncap = Math.Min(capR.Length, _cap.Length / 7);
        for (int c = 0; c < _ncap; c++)
        {
            Vector3 a = caps[2 * c], b = caps[2 * c + 1];
            _cap[c * 7] = a.X; _cap[c * 7 + 1] = a.Y; _cap[c * 7 + 2] = a.Z;
            _cap[c * 7 + 3] = b.X; _cap[c * 7 + 4] = b.Y; _cap[c * 7 + 5] = b.Z; _cap[c * 7 + 6] = capR[c];
        }
        for (int c = 0; c < _cols; c++)
        {
            _pin0[c * 3] = from[c].X; _pin0[c * 3 + 1] = from[c].Y; _pin0[c * 3 + 2] = from[c].Z;
            _pin1[c * 3] = to[c].X; _pin1[c * 3 + 1] = to[c].Y; _pin1[c * 3 + 2] = to[c].Z;
        }
        for (int s = 0; s < n; s++)
            Step((float)h, (s + 1f) / n, wind.X, wind.Y, wind.Z, drag, damping, iters);
    }

    void Step(float h, float u, float wx, float wy, float wz, float drag, float damping, int iters)
    {
        float ratio = (float)(h / _lastDt);
        _lastDt = h;
        ComputeNormals();
        float hh = h * h, invH = 1f / h;
        for (int i = _cols; i < _n; i++)
        {
            float vx = (_px[i] - _qx[i]) * ratio, vy = (_py[i] - _qy[i]) * ratio, vz = (_pz[i] - _qz[i]) * ratio;
            // aero: air moving through the cloth pushes it along its normal (both faces) + a little skin drag
            float rx = wx - vx * invH, ry = wy - vy * invH, rz = wz - vz * invH;
            float vn = rx * _nx[i] + ry * _ny[i] + rz * _nz[i];
            float an = vn * MathF.Abs(vn) * drag, at = drag * 0.6f;
            float ax = _nx[i] * an + rx * at, ay = _ny[i] * an + ry * at - 9.81f, az = _nz[i] * an + rz * at;
            _qx[i] = _px[i]; _qy[i] = _py[i]; _qz[i] = _pz[i];
            _px[i] += vx * damping + ax * hh; _py[i] += vy * damping + ay * hh; _pz[i] += vz * damping + az * hh;
        }
        for (int c = 0; c < _cols; c++)
        {
            _qx[c] = _px[c]; _qy[c] = _py[c]; _qz[c] = _pz[c];
            _px[c] = _pin0[c * 3] + (_pin1[c * 3] - _pin0[c * 3]) * u;
            _py[c] = _pin0[c * 3 + 1] + (_pin1[c * 3 + 1] - _pin0[c * 3 + 1]) * u;
            _pz[c] = _pin0[c * 3 + 2] + (_pin1[c * 3 + 2] - _pin0[c * 3 + 2]) * u;
        }
        int nc = _ca.Length, cols = _cols;
        for (int it = 0; it < iters; it++)
        {
            for (int k = 0; k < nc; k++)
            {
                int i = _ca[k], j = _cb[k];
                bool pi = i < cols, pj = j < cols;
                if (pi && pj) continue;
                float dx = _px[j] - _px[i], dy = _py[j] - _py[i], dz = _pz[j] - _pz[i];
                float l2 = dx * dx + dy * dy + dz * dz;
                if (l2 < 1e-14f) continue;
                float len = MathF.Sqrt(l2);
                float diff = (len - _rest[k]) / len * _stiff[k];
                if (pi) { _px[j] -= dx * diff; _py[j] -= dy * diff; _pz[j] -= dz * diff; }
                else if (pj) { _px[i] += dx * diff; _py[i] += dy * diff; _pz[i] += dz * diff; }
                else
                {
                    float hd = 0.5f * diff;
                    _px[i] += dx * hd; _py[i] += dy * hd; _pz[i] += dz * hd;
                    _px[j] -= dx * hd; _py[j] -= dy * hd; _pz[j] -= dz * hd;
                }
            }
            Collide();
        }
    }

    void Collide()
    {
        for (int i = _cols; i < _n; i++)
        {
            float x = _px[i], y = _py[i], z = _pz[i];
            for (int c = 0; c < _ncap; c++)
            {
                int o = c * 7;
                float ax = _cap[o], ay = _cap[o + 1], az = _cap[o + 2];
                float bx = _cap[o + 3] - ax, by = _cap[o + 4] - ay, bz = _cap[o + 5] - az, r = _cap[o + 6];
                float bl = bx * bx + by * by + bz * bz;
                float t = bl > 1e-9f ? ((x - ax) * bx + (y - ay) * by + (z - az) * bz) / bl : 0f;
                t = t < 0f ? 0f : (t > 1f ? 1f : t);
                float cx = ax + bx * t, cy = ay + by * t, cz = az + bz * t;
                float dx = x - cx, dy = y - cy, dz = z - cz;
                float d2 = dx * dx + dy * dy + dz * dz;
                if (d2 < r * r && d2 > 1e-12f)
                {
                    float k = r / MathF.Sqrt(d2);
                    x = cx + dx * k; y = cy + dy * k; z = cz + dz * k;
                }
            }
            _px[i] = x; _py[i] = y; _pz[i] = z;
        }
    }

    void ComputeNormals()
    {
        for (int r = 0; r < _rows; r++)
        {
            int ru = r > 0 ? r - 1 : 0, rd = r < _rows - 1 ? r + 1 : _rows - 1;
            for (int c = 0; c < _cols; c++)
            {
                int cl = _loop ? (c - 1 + _cols) % _cols : Math.Max(c - 1, 0);
                int cr = _loop ? (c + 1) % _cols : Math.Min(c + 1, _cols - 1);
                int a = Idx(r, cr), b = Idx(r, cl), u = Idx(ru, c), d = Idx(rd, c);
                float ax = _px[a] - _px[b], ay = _py[a] - _py[b], az = _pz[a] - _pz[b];
                float dx = _px[d] - _px[u], dy = _py[d] - _py[u], dz = _pz[d] - _pz[u];
                float nx = ay * dz - az * dy, ny = az * dx - ax * dz, nz = ax * dy - ay * dx;
                float l = MathF.Sqrt(nx * nx + ny * ny + nz * nz);
                int i = Idx(r, c);
                if (l > 1e-9f) { _nx[i] = nx / l; _ny[i] = ny / l; _nz[i] = nz / l; }
                else { _nx[i] = 0; _ny[i] = 1; _nz[i] = 0; }
            }
        }
    }

    public Vector3[] Positions()
    {
        var o = new Vector3[_n];
        for (int i = 0; i < _n; i++) o[i] = new Vector3(_px[i], _py[i], _pz[i]);
        return o;
    }

    public Vector3[] Normals()
    {
        ComputeNormals();
        var o = new Vector3[_n];
        for (int i = 0; i < _n; i++) o[i] = new Vector3(_nx[i], _ny[i], _nz[i]);
        return o;
    }

    /// largest distance of a free particle from its row-0 pin column (sanity: stretched / exploded?)
    public float MaxSag()
    {
        float m = 0;
        for (int i = _cols; i < _n; i++)
        {
            int p = i % _cols;
            float dx = _px[i] - _px[p], dy = _py[i] - _py[p], dz = _pz[i] - _pz[p];
            m = MathF.Max(m, MathF.Sqrt(dx * dx + dy * dy + dz * dz));
        }
        return m;
    }

    public bool IsFinite()
    {
        for (int i = 0; i < _n; i++) if (!float.IsFinite(_px[i]) || !float.IsFinite(_py[i]) || !float.IsFinite(_pz[i])) return false;
        return true;
    }

    /// profiling: microseconds per StepFrame(4 substeps) measured inside C#
    public double BenchSteps(int reps, Vector3[] pins, Vector3[] caps, float[] capR)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        for (int i = 0; i < reps; i++) StepFrame(1.0 / 240, 4, pins, pins, new Vector3(10, 0, 0), caps, capR, 0.9f, 0.985f, 6);
        return sw.Elapsed.TotalMilliseconds * 1000.0 / reps;
    }
}
