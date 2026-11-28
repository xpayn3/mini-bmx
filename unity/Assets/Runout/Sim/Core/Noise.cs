using System;

namespace Runout.Sim
{
    /// 2D simplex noise with fractal octaves: stands in for Godot's FastNoiseLite (TYPE_SIMPLEX_SMOOTH, FBM, lacunarity 2,
    /// gain 0.5). Same frequency / octaves / seed settings give the same character (not bit-identical values to Godot).
    public sealed class Noise
    {
        public double frequency = 0.01;
        public int fractal_octaves = 3;
        public double lacunarity = 2.0, gain = 0.5;
        readonly short[] _perm = new short[512];

        public Noise(int seed)
        {
            var p = new short[256];
            for (short i = 0; i < 256; i++) p[i] = i;
            var r = new Rng((ulong)seed * 2654435761UL + 1);
            for (int i = 255; i > 0; i--) { int j = (int)(r.randf() * (i + 1)); if (j > i) j = i; (p[i], p[j]) = (p[j], p[i]); }
            for (int i = 0; i < 512; i++) _perm[i] = p[i & 255];
        }

        /// -1..1 (roughly), like FastNoiseLite.get_noise_2d
        public double get_noise_2d(double x, double y)
        {
            x *= frequency; y *= frequency;
            double sum = 0, amp = 1, norm = 0;
            for (int o = 0; o < fractal_octaves; o++)
            {
                sum += Simplex(x, y) * amp;
                norm += amp; amp *= gain; x *= lacunarity; y *= lacunarity;
            }
            return sum / norm;
        }

        static readonly double F2 = 0.5 * (Math.Sqrt(3.0) - 1.0), G2 = (3.0 - Math.Sqrt(3.0)) / 6.0;
        static readonly int[] GX = { 1, -1, 1, -1, 1, -1, 0, 0 }, GY = { 1, 1, -1, -1, 0, 0, 1, -1 };

        double Simplex(double xin, double yin)
        {
            double s = (xin + yin) * F2;
            int i = (int)Math.Floor(xin + s), j = (int)Math.Floor(yin + s);
            double t = (i + j) * G2;
            double x0 = xin - (i - t), y0 = yin - (j - t);
            int i1 = x0 > y0 ? 1 : 0, j1 = 1 - i1;
            double x1 = x0 - i1 + G2, y1 = y0 - j1 + G2, x2 = x0 - 1.0 + 2.0 * G2, y2 = y0 - 1.0 + 2.0 * G2;
            int ii = i & 255, jj = j & 255;
            double n = 0;
            n += Corner(x0, y0, _perm[ii + _perm[jj]]);
            n += Corner(x1, y1, _perm[ii + i1 + _perm[jj + j1]]);
            n += Corner(x2, y2, _perm[ii + 1 + _perm[jj + 1]]);
            return 70.0 * n;
        }

        static double Corner(double x, double y, int h)
        {
            double t = 0.5 - x * x - y * y;
            if (t < 0) return 0;
            t *= t;
            h &= 7;
            return t * t * (GX[h] * x + GY[h] * y);
        }
    }

    /// Seeded random numbers (Godot's RandomNumberGenerator / randf): deterministic per seed, so a ride replays exactly.
    public sealed class Rng
    {
        ulong _s;
        public Rng(ulong seed) { this.seed = seed; }
        public ulong seed { set { _s = value == 0 ? 0x9E3779B97F4A7C15UL : value; } }
        ulong Next() { _s ^= _s << 13; _s ^= _s >> 7; _s ^= _s << 17; return _s; }
        /// 0..1
        public double randf() => (Next() >> 11) * (1.0 / 9007199254740992.0);
        public double randf_range(double a, double b) => a + (b - a) * randf();
        /// normal distribution (Box-Muller)
        public double randfn(double mean, double dev)
        {
            double u1 = Math.Max(1e-12, randf()), u2 = randf();
            return mean + dev * Math.Sqrt(-2.0 * Math.Log(u1)) * Math.Cos(2.0 * Math.PI * u2);
        }
    }

    /// The crashed bike as a rigid body (Godot: CrashBikeCs, port step 5). The physics steps it and reads the bike back.
    public interface ICrashBody
    {
        bool Asleep { get; }
        void Step(double dt);
        /// the bike's root: position + heading / pitch / lean / bars as the physics reads them back
        void ReadBack(out V3 pos, out double heading, out double pitch, out double lean, out double bars, out V3 velocity);
    }
}
