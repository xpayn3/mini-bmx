using Godot;
using System;

/// The level builder's light bake (step 3): for every cell of a level's height grid, how much sun reaches it at the
/// level's fixed time of day (the hills, ramps and tree crowns between it and the sun, with a soft edge) and how
/// open it is to the sky (ambient occlusion from the land round it). Plain float arrays in, RG bytes out (R = sun,
/// G = sky), one call per level. Used by LevelBake (GDScript); [Tool] so the editor's Bake button can run it.
[Tool]
[GlobalClass]
public partial class LevelShadeBake : RefCounted
{
    float[] _h;
    int _nx, _nz;
    float _x0, _z0, _step;
    float _maxH;
    // tree crowns on a 1 m grid: lowest / highest crown height there (NaN = none)
    float[] _lo, _hi;
    int _cnx, _cnz;
    float _cx0, _cz0;

    float H(float x, float z)
    {
        float fx = (x - _x0) / _step, fz = (z - _z0) / _step;
        if (fx < 0) fx = 0; if (fz < 0) fz = 0;
        if (fx > _nx - 1.001f) fx = _nx - 1.001f; if (fz > _nz - 1.001f) fz = _nz - 1.001f;
        int i = (int)fx, j = (int)fz;
        float u = fx - i, w = fz - j;
        int k = j * _nx + i;
        float a = _h[k] + (_h[k + 1] - _h[k]) * u;
        float b = _h[k + _nx] + (_h[k + _nx + 1] - _h[k + _nx]) * u;
        return a + (b - a) * w;
    }

    /// heights: the level's grid (nx x nz at step m from x0, z0); toSun: unit vector towards the sun;
    /// crowns: x, z, radius, lo, hi per tree; every: output every n-th grid point (2 at 0.5 m = 1 m)
    public byte[] Bake(float[] heights, int nx, int nz, float x0, float z0, float step, Vector3 toSun, float[] crowns, int every)
    {
        _h = heights; _nx = nx; _nz = nz; _x0 = x0; _z0 = z0; _step = step;
        _maxH = float.MinValue;
        foreach (var v in heights) if (v > _maxH) _maxH = v;
        // crown grid
        _cx0 = x0; _cz0 = z0;
        _cnx = (int)((nx - 1) * step) + 1; _cnz = (int)((nz - 1) * step) + 1;
        _lo = new float[_cnx * _cnz]; _hi = new float[_cnx * _cnz];
        for (int q = 0; q < _lo.Length; q++) { _lo[q] = float.NaN; _hi[q] = float.NaN; }
        float crownTop = _maxH;
        for (int t = 0; t + 4 < crowns.Length; t += 5)
        {
            float cx = crowns[t], cz = crowns[t + 1], r = crowns[t + 2], lo = crowns[t + 3], hi = crowns[t + 4];
            if (hi > crownTop) crownTop = hi;
            for (int gz = (int)Math.Floor(cz - r - _cz0); gz <= (int)Math.Ceiling(cz + r - _cz0); gz++)
                for (int gx = (int)Math.Floor(cx - r - _cx0); gx <= (int)Math.Ceiling(cx + r - _cx0); gx++)
                {
                    if (gx < 0 || gz < 0 || gx >= _cnx || gz >= _cnz) continue;
                    float dx = gx + _cx0 - cx, dz = gz + _cz0 - cz;
                    if (dx * dx + dz * dz > r * r) continue;
                    int k = gz * _cnx + gx;
                    _lo[k] = float.IsNaN(_lo[k]) ? lo : Math.Min(_lo[k], lo);
                    _hi[k] = float.IsNaN(_hi[k]) ? hi : Math.Max(_hi[k], hi);
                }
        }
        int ox = (nx - 1) / every + 1, oz = (nz - 1) / every + 1;
        var outb = new byte[ox * oz * 2];
        var sd = new Vector2(toSun.X, toSun.Z);
        float horiz = sd.Length();
        if (horiz < 1e-4f) sd = new Vector2(1, 0); else sd /= horiz;
        float rise = toSun.Y / Math.Max(horiz, 1e-3f);   // m up per m towards the sun
        float top = Math.Max(_maxH, crownTop) + 0.5f;
        // AO directions + distances
        int nd = 8;
        float[] dist = { 1.0f, 2.5f, 5.0f, 9.0f, 16.0f };
        for (int j = 0; j < oz; j++)
        {
            for (int i = 0; i < ox; i++)
            {
                int gi = Math.Min(i * every, nx - 1), gj = Math.Min(j * every, nz - 1);
                float x = x0 + gi * step, z = z0 + gj * step;
                float y0 = heights[gj * nx + gi] + 0.05f;
                // sun: march towards it; the soft edge from how close the ray passes over what it clears
                float vis = 1.0f;
                if (toSun.Y <= 0.0f) vis = 0.0f;
                else
                {
                    float t = 0.5f;
                    while (t < 900.0f)
                    {
                        float px = x + sd.X * t, pz = z + sd.Y * t;
                        float ry = y0 + rise * t;
                        if (ry > top) break;
                        float g = H(px, pz);
                        float clear = (ry - g) / (0.35f + 0.035f * t);   // penumbra grows with distance
                        if (clear < vis) vis = Math.Max(0.0f, clear);
                        int cxk = (int)Math.Round(px - _cx0), czk = (int)Math.Round(pz - _cz0);
                        if (cxk >= 0 && czk >= 0 && cxk < _cnx && czk < _cnz)
                        {
                            int k = czk * _cnx + cxk;
                            if (!float.IsNaN(_lo[k]) && ry > _lo[k] && ry < _hi[k]) vis = Math.Min(vis, 0.25f);   // a crown: dappled
                        }
                        if (vis <= 0.0f) break;
                        t += t < 8.0f ? 0.5f : (t < 60.0f ? 1.0f : 2.0f);
                    }
                }
                // sky: the horizon's height round the point
                float occ = 0.0f;
                for (int d = 0; d < nd; d++)
                {
                    float a = d * Mathf.Tau / nd;
                    float dx = Mathf.Cos(a), dz = Mathf.Sin(a);
                    float best = 0.0f;
                    foreach (float r in dist)
                    {
                        float s = (H(x + dx * r, z + dz * r) - y0) / r;
                        if (s > best) best = s;
                    }
                    occ += best / Mathf.Sqrt(1.0f + best * best);   // sin of the horizon angle
                }
                float ao = 1.0f - Math.Min(1.0f, occ / nd * 1.3f);
                int o = (j * ox + i) * 2;
                outb[o] = (byte)Math.Round(Math.Clamp(vis, 0.0f, 1.0f) * 255.0f);
                outb[o + 1] = (byte)Math.Round(Math.Clamp(ao, 0.0f, 1.0f) * 255.0f);
            }
        }
        return outb;
    }
}
