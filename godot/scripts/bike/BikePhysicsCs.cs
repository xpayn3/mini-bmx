using System;
using System.Collections.Generic;
using Godot;
using Runout.Sim;
using GDict = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

/// <summary>
/// The ride in C# (godot/sim BikeSim) as the game's `phys`: every member under its GDScript name (BikePhysicsCs.gen.cs),
/// the same methods as bike_physics.gd. Game makes it with BMX_PHYS=cs. The crashed bike + ragdoll step is here (engine
/// objects): a hand port of BikePhysics._crash_sim_step and the ragdoll part of _crash_step.
/// </summary>
[GlobalClass]
public partial class BikePhysicsCs : RefCounted
{
	public BikeSim S;
	private GodotObject _game;
	private GameHost _host;
	private readonly RideInput _inp = new RideInput();
	private GDict _tuneSrc;
	private bool _tuneDirty;
	private GDict _susSrc = new GDict();
	private GodotObject _crashSim;
	private GDict _profGd;

	/// once after new(): the game is the host (GDScript can't pass constructor arguments to a C# script)
	public void init(GodotObject game)
	{
		RideBridge.Init();
		_game = game;
		_host = new GameHost(this, game);
		S = new BikeSim(_host) { T = new RideParams() };
		var tune = (Engine.GetMainLoop() as SceneTree)?.Root.GetNodeOrNull("Tune");
		tune?.Connect("changed", Callable.From(() => _tuneDirty = true));
	}

	// ---- members held as engine values
	public GodotObject host
	{
		get => _game;
		set { }   // (the lockstep tap swaps the GDScript ride's host; this one always talks to the game)
	}

	public GDict T
	{
		get => _tuneSrc;
		set { _tuneSrc = value; _tuneDirty = true; RefreshTune(); }
	}

	private void RefreshTune()
	{
		if (!_tuneDirty || _tuneSrc == null)
			return;
		_tuneDirty = false;
		var p = S.T;
		p.v.Clear();
		foreach (var kv in _tuneSrc)
		{
			var v = kv.Value;
			p.v[kv.Key.AsString()] = v.VariantType == Variant.Type.Int ? v.AsInt64() : (v.VariantType == Variant.Type.Bool ? (v.AsBool() ? 1.0 : 0.0) : v.AsDouble());
		}
		RideParams.global = p;
	}

	public GDict sus
	{
		get => _susSrc;
		set { _susSrc = value ?? new GDict(); S.sus = RideBridge.Sus(_susSrc); }
	}

	public GodotObject crash_sim
	{
		get => _crashSim;
		set { _crashSim = value; S.crash_sim = value == null ? null : new GodotCrashSim(value); }
	}

	/// the grip randomness, as GDScript's RandomNumberGenerator looks to the game (the playground reseeds it per run)
	public RngView _grip_rng => _rng ??= new RngView(this);
	private RngView _rng;

	public partial class RngView : RefCounted
	{
		private readonly BikePhysicsCs _o;
		public RngView() { }
		public RngView(BikePhysicsCs o) { _o = o; }
		public long seed { get => _o.S._grip_rng.seed; set => _o.S._grip_rng.seed = value; }
		public long state { get => (long)_o.S._grip_rng.State; set => _o.S._grip_rng.State = (ulong)value; }
	}

	public Transform3D crash_K = Transform3D.Identity;
	public Transform3D crash_RK = Transform3D.Identity;

	public GDict prof
	{
		get => _profGd;
		set { _profGd = value; S.prof = value == null ? null : new Dictionary<string, long>(); }
	}

	// ---- the methods the game calls (bike_physics.gd's)
	public void setup(GDict extras, GDict bike_cfg)
	{
		var ex = RideBridge.ToDict(extras);
		var cfg = new GdDict { src = bike_cfg };
		foreach (var kv in bike_cfg)
		{
			string k = kv.Key.AsString();
			if (k != "mods") cfg.set(k, RideBridge.Plain(kv.Value));
		}
		var mods = new GdDict();
		if (bike_cfg.ContainsKey("mods"))
		{
			var md = bike_cfg["mods"].AsGodotDictionary();
			foreach (var kv in md)
			{
				string k = kv.Key.AsString();
				if (k == "cogs") mods.set(k, RideBridge.ToDoubles(kv.Value.AsGodotArray()));
				else if (k == "susp") { _susSrc = kv.Value.AsGodotDictionary(); mods.set(k, RideBridge.Sus(_susSrc)); }
				else mods.set(k, RideBridge.Plain(kv.Value));
			}
		}
		cfg.set("mods", mods);
		S.setup(ex, cfg);
		if (S.sus.is_empty()) _susSrc = new GDict();
	}

	public void step(double dt, GDict inp)
	{
		RefreshTune();
		_inp.v.Clear();
		foreach (var kv in inp)
		{
			var v = kv.Value;
			_inp.v[kv.Key.AsString()] = v.VariantType == Variant.Type.Bool ? (v.AsBool() ? 1.0 : 0.0) : (v.VariantType == Variant.Type.Int ? v.AsInt64() : v.AsDouble());
		}
		S.step(dt, _inp);
		if (_profGd != null && S.prof != null)
		{
			foreach (var kv in S.prof)
				_profGd[kv.Key] = (_profGd.TryGetValue(kv.Key, out var was) ? was.AsInt64() : 0) + kv.Value;
			S.prof.Clear();
		}
	}

	public void reset_at(double px, double pz, double hd) => S.reset_at(px, pz, hd);
	public void get_up() => S.get_up();
	public void begin_crash() => S.begin_crash();
	public bool shift(long d) => S.shift(d);
	public double gear_k() => S.gear_k();
	public void reset_body() => S.reset_body();
	public bool is_sane() => S.is_sane();
	public Vector3 fwd() => RideBridge.G(S.fwd());
	public void flow_up() => S.flow_up();

	// ---------------------------------------------------------------- the host (the game) + the crash body step
	private sealed class GameHost : GodotRideHost
	{
		private readonly BikePhysicsCs _o;
		private const int PELVIS = 2;   // (Ragdoll.PELVIS)
		private const double STEPOFF_DV = 1.4;
		private const double WHEEL_OFF_DV = 7.0, WHEEL_OFF_SPAN = 9.0, WHEEL_OFF_MAX = 0.5;
		private static readonly bool OLD_RIDERBIKE = (DevFlags.Env("BMX_OLD_RIDERBIKE") ?? "") != "";

		public GameHost(BikePhysicsCs o, GodotObject game) : base(game) { _o = o; }

		public override void log(string text) => GD.Print(text);

		/// _crash_sim_step (when the crashed bike is a body), then the ragdoll part of _crash_step
		public override void crash_body_step(BikeSim s, double dt, RideInput inp)
		{
			var terrain = Game.Get("terrain").AsGodotObject();
			var sim = _o._crashSim as CrashBikeCs;
			if (sim != null)
				CrashSimStep(s, sim, terrain, dt);
			var rag = Game.Get("ragdoll").AsGodotObject();
			if (rag == null || !rag.Get("active").AsBool())
				return;
			var P = rag.Get("p").AsGodotArray()[PELVIS].AsVector3();
			var near = terrain.Call("colliders_near", P.X, P.Z).AsGodotArray();
			double rspeed = rag.Get("speed").AsDouble();
			foreach (var e in near)
			{
				var c = e.AsGodotDictionary();
				if (c.TryGetValue("tape", out var tp) && Gd.to_b(RideBridge.Plain(tp))) continue;
				if (!(c.TryGetValue("fence", out var fv) && fv.AsBool()) || rspeed < 2.5
					|| new Vector2((float)(P.X - c["x"].AsDouble()), (float)(P.Z - c["z"].AsDouble())).Length() > c["r"].AsDouble() + 0.3
					|| P.Y > terrain.Call("height", P.X, P.Z).AsDouble() + 1.4)
					continue;
				var Q = rag.Get("q").AsGodotArray()[PELVIS].AsVector3();
				Game.Call("smash", c, (P - Q) / (float)dt * 3.0f * new Vector3(1, 0, 1), P - new Vector3(0, 0.4f, 0));
			}
			rag.Call("step", dt, near);
			bool step_off = rag.Get("bal_on").AsBool() && sim != null && (DevFlags.Env("BMX_OLD_STEPOFF") ?? "") == "";
			if (step_off && !s._bal_shoved)
			{
				s._bal_shoved = true;
				sim.Release();
				var bb = sim.BodyNow().Basis;
				var side_v = new Vector3(bb.Z.X, 0.0f, bb.Z.Z).Normalized();
				float lean_s = Mathf.Sign(bb.Y.Dot(side_v));
				if (lean_s == 0f) lean_s = 1f;
				sim.Shove(side_v * lean_s * (float)STEPOFF_DV, 0.9f);
			}
			if (sim != null && !OLD_RIDERBIKE && !step_off)
			{
				var hp = rag.Get("p").AsVector3Array();
				var hq = rag.Get("q").AsVector3Array();
				int nr = hp.Length;
				bool held = sim.HoldsOn > 0 && (DevFlags.Env("BMX_RAG_NOHOLD") ?? "") == "";
				if (held)
				{
					var hh = sim.HoldBody(hp, hq, (float)dt, (float)rag.Get("last_h").AsDouble());
					hp = hh[..nr]; hq = hh[nr..];
				}
				var radA = rag.Get("rad").AsGodotArray();
				var rad = new float[radA.Count];
				for (int i = 0; i < rad.Length; i++) rad[i] = (float)radA[i].AsDouble();
				var np = sim.CollideBody(hp, hq, rad);
				rag.Call("external_push", np[..nr], np[nr..]);
				rag.Set("contact_ext", (held || sim.LastPush > 0.0005) ? 0.0 : rag.Get("contact_ext").AsDouble() + dt);
			}
			s.crash_rest = rag.Get("speed").AsDouble() < 0.6 ? s.crash_rest + dt : 0.0;
		}

		/// BikePhysics._crash_sim_step: one step of the crashed bike (trunks / fences near it, a wheel knocked off by a hard
		/// hit), then x, y, z, heading, pitch, lean, bars, speed read back from it
		private void CrashSimStep(BikeSim s, CrashBikeCs sim, GodotObject terrain, double dt)
		{
			if (!sim.Asleep)
			{
				var c = sim.Centre();
				var vel = sim.Velocity();
				var cyl = new List<float>();
				foreach (var e in terrain.Call("colliders_near", c.X, c.Z).AsGodotArray())
				{
					var col = e.AsGodotDictionary();
					if ((col.TryGetValue("tape", out var tp) && Gd.to_b(RideBridge.Plain(tp))) || col.ContainsKey("sink")) continue;
					bool fence = col.TryGetValue("fence", out var fv) && fv.AsBool();
					bool cactus = col.TryGetValue("cactus", out var cv) && cv.AsBool();
					if (fence || cactus)
					{
						if (vel.Length() > 2.0f && new Vector2((float)(c.X - col["x"].AsDouble()), (float)(c.Z - col["z"].AsDouble())).Length() < col["r"].AsDouble() + 0.7)
							Game.Call("smash", col, vel, c);
						continue;
					}
					double top = col.TryGetValue("top", out var tv) ? tv.AsDouble() : double.PositiveInfinity;
					if (col.ContainsKey("top") && top - (col.TryGetValue("base", out var bv) ? bv.AsDouble() : top - 1.0) < 0.6) continue;
					cyl.Add((float)col["x"].AsDouble()); cyl.Add((float)col["z"].AsDouble()); cyl.Add((float)col["r"].AsDouble());
					cyl.Add((float)(top < 1e6 ? top : 1e6));
				}
				sim.SetColliders(cyl.ToArray());
				sim.Step((float)dt);
				string force = DevFlags.Env("BMX_WHEEL_OFF") ?? "";
				for (int w = 0; w < 2; w++)
				{
					if (sim.WheelOff(w)) continue;
					double hv = w == 0 ? sim.HitFront : sim.HitRear;
					bool go = false;
					if (hv > WHEEL_OFF_DV && s._cb_hit[w] <= WHEEL_OFF_DV)
						go = Gd.randf() < Gd.clampf((hv - WHEEL_OFF_DV) / WHEEL_OFF_SPAN, 0.08, 1.0) * WHEEL_OFF_MAX;
					if (force != "" && s.crash_t > 0.12 && (force == "both" || (force == "front") == (w == 0))) go = true;
					s._cb_hit[w] = hv;
					if (go)
					{
						var kick = new Vector3((float)((Gd.randf() - 0.5) * 2.5), (float)(1.2 + Gd.randf() * 1.6), (float)((Gd.randf() - 0.5) * 2.5)) + vel * 0.15f;
						sim.Detach(w, kick, sim.AxleRoll(w));
						if ((DevFlags.Env("BMX_CRASHBIKE_PROBE") ?? "") != "")
							GD.Print($"CRASHBIKE wheel off {(w == 0 ? "front" : "rear")} hit={hv:F1} t={s.crash_t:F2}");
					}
				}
			}
			var root = sim.BodyAt(1.0f) * _o.crash_RK;
			var bx = root.Basis.X.Normalized();
			s.x = root.Origin.X; s.y = root.Origin.Y; s.z = root.Origin.Z;
			if (new Vector2(bx.X, bx.Z).Length() > 0.05f) s.heading = Gd.atan2(-bx.Z, bx.X);
			s.pitch = Gd.asin(Gd.clampf(bx.Y, -1.0, 1.0));
			s.bike_lean = Gd.asin(Gd.clampf(root.Basis.Z.Normalized().Y, -1.0, 1.0));
			s.steer = sim.ThetaAt(1.0f);
			var vv = sim.Velocity();
			var f = RideBridge.G(s.fwd());
			s.v = new Vector2(vv.X, vv.Z).Length() * (vv.Dot(f) >= 0.0f ? 1.0 : -1.0);
			if (!sim.WheelOff(0)) s.wheel_f += sim.AxleRoll(0) * dt;
			if (!sim.WheelOff(1)) s.wheel_r += sim.AxleRoll(1) * dt;
			s.counter = 0; s.rock = 0; s.pedal = 0; s.hop_nose = 0.0; s.yaw_rate = 0.0;
			s.body_y = s.y; s.body_v = 0; s.y_draw = s.y; s.pitch_draw = s.pitch;
		}
	}
}
