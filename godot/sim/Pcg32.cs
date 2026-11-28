// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
using System;
using System.Numerics;

namespace Runout.Sim
{
	/// <summary>
	/// Godot's RandomNumberGenerator (PCG32, XSH-RR) bit for bit: the same seed gives the same stream on any engine
	/// (checked by tools/sim_rng_probe.gd). randf / randfn follow Godot 4's RandomPCG (open-interval floats from two
	/// draws, Box-Muller from two floats).
	/// </summary>
	public sealed class Pcg32
	{
		private const ulong MULT = 6364136223846793005UL;
		public const ulong DEFAULT_INC = 1442695040888963407UL;
		private ulong _state;
		private ulong _inc;

		public Pcg32(ulong seed = 0x853c49e6748fea9bUL, ulong inc = DEFAULT_INC)
		{
			Seed(seed, inc);
		}

		/// pcg32_srandom_r
		public void Seed(ulong seed, ulong inc = DEFAULT_INC)
		{
			_state = 0UL;
			_inc = (inc << 1) | 1UL;
			Rand();
			_state += seed;
			Rand();
		}

		public ulong State { get => _state; set => _state = value; }

		/// one 32-bit draw (pcg32_random_r)
		public uint Rand()
		{
			ulong old = _state;
			_state = unchecked(old * MULT + _inc);
			uint xorshifted = (uint)(((old >> 18) ^ old) >> 27);
			int rot = (int)(old >> 59);
			return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
		}

		/// [0, 1) as a float (Godot's randf: the exponent from the first draw's leading zeros, the mantissa from the second)
		public float Randf()
		{
			uint proto = Rand();
			if (proto == 0)
				return 0f;
			uint sig = Rand() | 0x80000001u;
			return MathF.ScaleB((float)sig, -32 - BitOperations.LeadingZeroCount(proto));
		}

		/// [0, 1) as a double
		public double Randd()
		{
			uint proto = Rand();
			if (proto == 0)
				return 0.0;
			ulong sig = ((ulong)Rand() << 32) | Rand() | 0x8000000000000001UL;
			return Math.ScaleB((double)sig, -64 - BitOperations.LeadingZeroCount(proto));
		}

		/// a normal draw (Box-Muller), the float version RandomNumberGenerator.randfn uses
		public float Randfn(float mean, float dev)
		{
			float temp = Randf();
			if (temp < 1e-5f)   // CMP_EPSILON
				temp += 1e-5f;
			// Godot: cos(float) and log(float) are the float functions, the product and sqrt in double
			const float TAU_F = (float)(Math.PI * 2.0);
			float c = (float)SimMath.Cos(TAU_F * Randf());
			float lg = (float)SimMath.Log(temp);
			return (float)(mean + dev * (c * Math.Sqrt(-2.0 * lg)));
		}
	}
}
