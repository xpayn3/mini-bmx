using System;
using Godot;

/// Where a tyre flings gravel, and how hard (fx/ride_dust.gd `_patch` hands it the tyre's state every frame).
///
/// Stones ride the tread and let go on the way up the back of the wheel. For a wheel turning at surface speed w (= omega R)
/// under a bike moving at v, a stone that leaves at angle phi round from the contact point (0 = the ground, up the rear
/// of the tyre) has, relative to the bike, w backwards * cos(phi) and w upwards * sin(phi); add the bike's own velocity
/// for the world velocity:   x = v - w cos(phi),  y = w sin(phi).
///   rolling (w = v): x = v (1 - cos phi): it falls behind and is lofted, a gentle upward tail
///   wheelspin (w > v): thrown hard backwards at low phi - the roost jet
///   locked (w = 0): nothing rides the tread, the tyre ploughs it forward / out to the side
/// Sideways slip (a carve, a drift, a whip) adds the lateral slide speed to the throw. How many stones: the slip
/// (|w - v|) against the speed, the looseness of the ground, and how hard the tyre is loaded.
public partial class GritSprayCs : RefCounted
{
	public const int N = 3;            // release bins per tyre: low (jet), mid, high (tail)
	public const int STRIDE = 8;       // per bin: pos xyz, velocity xyz, spread (m/s), rate (grains / s)
	private static readonly float[] Phi = { 0.22f, 0.62f, 1.05f };   // rad round the tyre from the ground
	private readonly float[] _out = new float[N * STRIDE];
	private readonly Random _rng = new Random(7);

	/// pos: the patch; (vx, vz): the bike's velocity over the ground; (fx, fz): its heading (unit);
	/// wheelSurf: omega R in m/s (heading direction; 0 = locked, > speed = wheelspin); latSlide: sideways speed of the
	/// tread over the ground, + = to the right of the heading (m/s); rate: grains / s this tyre would give rolling flat out.
	public float[] Spray(float px, float py, float pz, float vx, float vz, float fx, float fz,
		float wheelSurf, float latSlide, float load, float loose, float rate, float release, float bump)
	{
		float v = vx * fx + vz * fz;                              // speed along the heading
		float sx = -fz, sz = fx;                                  // right of the heading
		float slipLong = wheelSurf - v;                           // + wheelspin, - locked / braking
		float slipAbs = Math.Abs(slipLong) + Math.Abs(latSlide);
		float slipK = Mathf.Clamp(slipAbs / (0.18f * Math.Abs(v) + 1.4f), 0f, 1f);
		// stones only come off in numbers when the tread is scrubbing; rolling flicks a few (the tread's own grip on loose bits)
		float slipOnly = Mathf.Clamp((slipK - 0.3f) / 0.7f, 0f, 1f);   // rolling (no slip) throws nothing
		slipOnly = Math.Max(slipOnly, 0.4f * Mathf.Clamp(bump, 0f, 1f));   // a bump kicks a few stones off a rolling tyre
		float amount = 0.5f * slipOnly * Mathf.Clamp(loose, 0f, 1.6f) * Mathf.Clamp(load, 0.25f, 1.8f);
		// the speed a stone leaves the tread at: its share of the tread speed (the rest of the stone's grip lost),
		// grows to all of it when the tyre spins / slides
		float eject = (0.22f + 0.78f * slipK) * release;
		for (int i = 0; i < N; i++)
		{
			float phi = Phi[i] * (0.8f + 0.5f * (float)_rng.NextDouble());
			float cp = Mathf.Cos(phi), sp = Mathf.Sin(phi);
			// tread velocity relative to the bike at that angle, along the heading + up
			float rel = Math.Max(wheelSurf, 0.3f * Math.Abs(v)) * eject;
			float back = -rel * cp;                    // along the heading: negative = thrown backwards
			float up = rel * sp;
			// a locked / braking tyre ploughs the loose stuff forward, not back
			if (slipLong < 0f) back = -slipLong * 0.5f * slipK * cp - rel * cp * (1f - slipK);
			// a spinning / sliding tyre's stones leave with less of the bike's own forward speed
			float wx = vx * (1f - 0.55f * slipK) + fx * back;
			float wz = vz * (1f - 0.55f * slipK) + fz * back;
			// sideways: the tread sliding over the ground flings stones off that side
			wx += sx * latSlide * (0.6f + 0.4f * slipK);
			wz += sz * latSlide * (0.6f + 0.4f * slipK);
			// the low bin is the jet: more of the grains when slipping; the high bin is the tail: more when rolling
			float share = i == 0 ? 0.30f + 0.45f * slipK : (i == 1 ? 0.40f : 0.30f - 0.15f * slipK);
			int o = i * STRIDE;
			_out[o] = px; _out[o + 1] = py + 0.03f + 0.07f * i; _out[o + 2] = pz;
			_out[o + 3] = wx; _out[o + 4] = up; _out[o + 5] = wz;
			_out[o + 6] = 0.18f + 0.22f * Math.Abs(rel) * 0.1f + 0.5f * slipK;   // scatter: tread lugs, stone sizes, turbulence
			_out[o + 7] = rate * amount * share;
		}
		return _out;
	}
}
