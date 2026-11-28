// Engine-free: nothing in godot/sim/ may reference the engine (checked by tools/sim_purity.ps1).
using System;
using System.Collections.Generic;

namespace Runout.Sim
{
	/// <summary>A GDScript-style dictionary of plain values (double / bool / string / nested): colliders, the trouble
	/// meters, the suspension units. `f(key)` reads a number like GDScript's `d.key`.</summary>
	public class GdDict : Dictionary<string, object>
	{
		public GdDict() { }
		public GdDict(int capacity) : base(capacity) { }

		/// the engine-side dictionary this one was made from (handed back to the host: smash, rock_chips)
		public object src;
		/// identity: the same collider / tape span from two lookups has the same id (GDScript compares the objects)
		public string id;

		public static bool operator ==(GdDict a, GdDict b) =>
			ReferenceEquals(a, b) || (a is not null && b is not null && a.id != null && a.id == b.id);
		public static bool operator !=(GdDict a, GdDict b) => !(a == b);
		public override bool Equals(object o) => o is GdDict d && this == d;
		public override int GetHashCode() => id != null ? id.GetHashCode() : base.GetHashCode();
		public string get_s(string k, string d) => this.TryGetValue(k, out var v) && v != null ? Gd.str(v) : d;

		public double f(string k) => this.TryGetValue(k, out var v) ? Gd.to_f(v) : 0.0;
		public bool has(string k) => ContainsKey(k);
		public double get_f(string k, double d) => this.TryGetValue(k, out var v) && v != null ? Gd.to_f(v) : d;
		public bool get_b(string k, bool d) => this.TryGetValue(k, out var v) && v != null ? Gd.to_b(v) : d;
		public object get_o(string k, object d) => this.TryGetValue(k, out var v) ? v : d;
		public List<string> keys() => new List<string>(Keys);
		public new double this[string k]
		{
			get => f(k);
			set => base[k] = value;
		}
		public void set(string k, object v) => base[k] = v;
	}

	/// <summary>The tuning values the ride reads (Tune.v: base x ride x bike multipliers), by key.</summary>
	public sealed class RideParams
	{
		/// the current set (the static helpers read it, like GDScript's Tune.v)
		public static RideParams global = new RideParams();

		public readonly Dictionary<string, double> v = new Dictionary<string, double>(512);
		public double f(string k) => v.TryGetValue(k, out var x) ? x : 0.0;
		public double get(string k, double d) => v.TryGetValue(k, out var x) ? x : d;
		public double this[string k]
		{
			get => f(k);
			set => v[k] = value;
		}
	}

	/// <summary>One physics step's input (the GDScript `inp` dictionary): numbers by key, the bool keys as 0 / 1.</summary>
	public sealed class RideInput
	{
		public readonly Dictionary<string, double> v = new Dictionary<string, double>(32);
		public double f(string k) => v.TryGetValue(k, out var x) ? x : 0.0;
		public bool b(string k) => v.TryGetValue(k, out var x) && x != 0.0;
		public double get(string k, double d) => v.TryGetValue(k, out var x) ? x : d;
		public bool get_b(string k, bool d) => v.TryGetValue(k, out var x) ? x != 0.0 : d;
		public void set(string k, double x) => v[k] = x;
		public void set(string k, bool x) => v[k] = x ? 1.0 : 0.0;
	}

	/// <summary>Test / tuning switches (BMX_* in the game). The host sets the lookup; none = every switch off.</summary>
	public static class Env
	{
		public static Func<string, string> lookup;
		private static readonly Dictionary<string, string> _cache = new Dictionary<string, string>();
		/// (read once per key: the switches don't change during a run, and the ride asks for some every step)
		public static string s(string k)
		{
			if (_cache.TryGetValue(k, out var v)) return v;
			v = lookup?.Invoke(k) ?? "";
			_cache[k] = v;
			return v;
		}
		public static string raw(string k) => s(k);
	}

	/// <summary>What the ride asks of the ground (metres, Y up). Any terrain can answer it: a height field, a mesh with
	/// downward raycasts, voxels. Cast() is there for a future contact model on walls / overhangs (see docs/physics_port.md).</summary>
	public interface IGround
	{
		/// the ridden surface (rocks / logs / decks included)
		double height(double x, double z);
		/// the same without rock / log bumps (banks, slopes, lean room)
		double deck_height(double x, double z);
		/// the drawn surface
		double top_height(double x, double z);
		/// 0 ground, 1 trail, 2 water, 3 sand
		long surface(double x, double z);
		/// 0..1 on built jumps
		double jump_mask(double x, double z);
		/// posts / trunks / rocks / fences / tape near (x, z): plain dictionaries (x, z, r, top, base, fence, tape, ...)
		List<GdDict> colliders_near(double x, double z);
		/// the general contact query: from `origin` along `dir` up to `max_dist`
		RayHit cast(V3 origin, V3 dir, double max_dist);
	}

	public struct RayHit
	{
		public bool hit;
		public V3 point, normal;
		public int surface;
		public double distance;
	}

	/// <summary>The drawn suspension the physics keeps in step with (null in a headless harness).</summary>
	public interface ISusp
	{
		bool has_f { get; }
		bool has_r { get; }
		bool wheels_follow { get; }
		V3 axis { get; }
		GdDict F { get; }
		GdDict R { get; }
		bool has_method(string name);
		void set_sag(double f, double r);
		void land(double impact, bool front_air, bool rear_air);
		void update(double dt, GdDict state);
	}

	/// <summary>The crashed bike as a body (the Godot build uses CrashBikeCs): its step lives with the host, the ride
	/// only needs to know it exists.</summary>
	public interface ICrashSim { }

	/// <summary>Everything the ride tells the game or asks of it (GDScript's `host`: Game).</summary>
	public interface IRideHost
	{
		IGround terrain { get; }
		ISusp susp { get; }
		object ragdoll { get; }
		object getup_anim { get; }
		/// the cranks' resting angle per pedal [left, right] (the drawn bike's)
		List<double> pedal_a0 { get; }
		bool has_method(string name);
		void flash(string text);
		bool msg_idle();
		bool smash(GdDict c, V3 vel, V3 pos);
		void rock_chips(GdDict c);
		void burst(V3 pos, long n, long surf, double power);
		void start_crash(string reason);
		void begin_getup();
		void on_style(long points, string text);
		void on_trick(string trick);
		void on_takeoff();
		void on_landing(double air_time, double impact);
		void on_bad_landing(double k);
		void ride_fx(double dt, V3 f, double va, bool in_water);
		void log(string text);
		void crashlog_note(string text);
		/// the crash parts that drive engine objects (ragdoll, crashed-bike body): the Godot adapter ports them
		void crash_body_step(BikeSim s, double dt, RideInput inp);   // (CrashBikeCs step if s.crash_sim is set, then the ragdoll)
		long get_ticks_usec();
		long get_ticks_msec();
		long get_physics_frames();
	}

	/// <summary>The suspension setup's numbers (SuspSetup.resolve as plain floats): {} = none (the BMX).</summary>
	public sealed class SusSetup
	{
		public bool empty = true;
		/// fork [travel, sag, prog, zc, zr, hs, fric, bump], shock the same, psi f / r
		public double[] u = new double[18];
		public bool is_empty() => empty;
	}

	/// <summary>SuspSetup's static maths (scripts/bike/susp_setup.gd).</summary>
	public static class SuspMath
	{
		public const double PSI_REF = 25.0;

		/// the compression (m) at which a spring of rate k carries `load`
		public static double rest(double load, double k, double travel, double prog)
		{
			double kk = Gd.maxf(k, 1e-6);
			double it = 1.0 / Gd.maxf(travel, 0.01);
			double x = load / kk;
			for (int i = 0; i < 3; i++)
			{
				double u = Gd.minf(x * it, 1.5);
				x = load / (kk * (1.0 + prog * u * u));
			}
			return Gd.minf(x, travel);
		}
	}
}
