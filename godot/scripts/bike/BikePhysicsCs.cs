using System;
using System.Collections.Generic;
using Godot;
using Runout.Sim;
using GDict = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

/// <summary>
/// The ride's step in C# (godot/sim BikeSim) behind the GDScript BikePhysics the game holds: BikePhysics.step() hands
/// over here. The GDScript object keeps the state between steps (the game reads it at full GDScript speed, the replay /
/// lab / ride log walk it as before); each step its numbers cross in one packed array (bike_mirror.gd <->
/// BikePhysicsCs.gen.cs), the C# ride steps, and they cross back. Before each of the game's callbacks inside the step
/// (effects, events) the state is mirrored to GDScript first, so the game sees the same mid-step values as when GDScript
/// stepped. The crashed bike + ragdoll step (engine objects) is here: a hand port of _crash_sim_step + _crash_step's part.
/// </summary>
[GlobalClass]
public partial class BikePhysicsCs : RefCounted
{
	public BikeSim S;
	private GodotObject _gd;   // the GDScript BikePhysics
	private GameHost _host;
	private readonly RideInput _inp = new RideInput();
	private bool _tuneDirty = true;
	private GodotObject _crashSim;
	private Transform3D _crashRK = Transform3D.Identity;
	private readonly double[] _buf = new double[N];
	/// ride_fx is the step's last statement: the state pushed before it is the step's end state (unless the energy /
	/// jolt probes, which run after it, are on), so the push after the step is skipped
	private bool _pushedAtFx;
	private static readonly bool PROBES_AFTER_FX = (DevFlags.Env("BMX_ENERGY_PROBE") ?? "") != "" || (DevFlags.Env("BMX_JOLT_PROBE") ?? "") != "";
	private static readonly StringName S_OUT = "_cs_out", S_IN = "_cs_in", S_PENDING = "crash_pending", S_RISK = "_risk",
		S_CBHIT = "_cb_hit", S_T = "T", S_CRASH = "crash_sim", S_RK = "crash_RK", S_PROF = "prof", S_CHUNK = "chunk_acc";

	public void Init(GodotObject game)
	{
		RideBridge.Init();
		_host = new GameHost(this, game);
		S = new BikeSim(_host) { T = new RideParams() };
		var tune = (Engine.GetMainLoop() as SceneTree)?.Root.GetNodeOrNull("Tune");
		tune?.Connect("changed", Callable.From(() => _tuneDirty = true));
	}

	/// BikePhysics.setup's twin (the same extras / bike config)
	public void Setup(GDict extras, GDict bike_cfg)
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
			foreach (var kv in bike_cfg["mods"].AsGodotDictionary())
			{
				string k = kv.Key.AsString();
				if (k == "cogs") mods.set(k, RideBridge.ToDoubles(kv.Value.AsGodotArray()));
				else if (k == "susp") mods.set(k, RideBridge.Sus(kv.Value.AsGodotDictionary()));
				else mods.set(k, RideBridge.Plain(kv.Value));
			}
		}
		cfg.set("mods", mods);
		S.setup(ex, cfg);
	}

	/// one physics step of the GDScript BikePhysics `gd`, done here
	public void Step(GodotObject gd, double dt, GDict inp)
	{
		_gd = gd;
		if (_tuneDirty)
		{
			_tuneDirty = false;
			LoadTune(gd.Get(S_T).AsGodotDictionary());
		}
		var pv = gd.Get(S_PROF);
		var prof = pv.VariantType == Variant.Type.Dictionary ? pv.AsGodotDictionary() : null;
		S.prof = prof == null ? null : (S.prof ?? new Dictionary<string, long>());
		Pull();
		_inp.v.Clear();
		foreach (var kv in inp)
		{
			var v = kv.Value;
			_inp.v[kv.Key.AsString()] = v.VariantType == Variant.Type.Bool ? (v.AsBool() ? 1.0 : 0.0) : (v.VariantType == Variant.Type.Int ? v.AsInt64() : v.AsDouble());
		}
		(_host.terrain as GodotGround)?.BeginStep();
		_pushedAtFx = false;
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		S.step(dt, _inp);
		if (RidePerf.On)
		{
			RidePerf.StepTicks += RidePerf.Now - t0; RidePerf.Steps++;
			if (RidePerf.Steps >= 600) RidePerf.Report();
		}
		if (!_pushedAtFx || PROBES_AFTER_FX)
			Push();
		if (prof != null && S.prof != null)
		{
			foreach (var kv in S.prof)
				prof[kv.Key] = (prof.TryGetValue(kv.Key, out var was) ? was.AsInt64() : 0) + kv.Value;
			S.prof.Clear();
		}
	}

	private void LoadTune(GDict t)
	{
		var p = S.T;
		p.v.Clear();
		if (t != null)
			foreach (var kv in t)
			{
				var v = kv.Value;
				p.v[kv.Key.AsString()] = v.VariantType == Variant.Type.Int ? v.AsInt64() : (v.VariantType == Variant.Type.Bool ? (v.AsBool() ? 1.0 : 0.0) : v.AsDouble());
			}
		RideParams.global = p;
	}

	/// the GDScript object's state into the C# ride (before a step, after a game callback that may have changed it)
	private void Pull()
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		Unpack(_gd.Call(S_OUT).AsFloat64Array());
		S.crash_pending = _gd.Get(S_PENDING).AsString();
		var risk = _gd.Get(S_RISK).AsGodotDictionary();
		if (risk.Count > 0 || S._risk.Count > 0)
		{
			S._risk.Clear();
			foreach (var kv in risk) S._risk.set(kv.Key.AsString(), kv.Value.AsDouble());
		}
		var cb = _gd.Get(S_CBHIT).AsGodotArray();
		if (cb.Count >= 2) { S._cb_hit[0] = cb[0].AsDouble(); S._cb_hit[1] = cb[1].AsDouble(); }
		// the crashed-bike body (Game.start_crash makes it, inside the step: read again after every callback)
		var cs = _gd.Get(S_CRASH).Obj as GodotObject;
		if (cs != _crashSim)
		{
			_crashSim = cs;
			S.crash_sim = cs == null ? null : new GodotCrashSim(cs);
		}
		if (cs != null)
			_crashRK = _gd.Get(S_RK).AsTransform3D();
		if (RidePerf.On) { RidePerf.MirrorTicks += RidePerf.Now - t0; RidePerf.Mirrors++; }
	}

	/// the C# ride's state into the GDScript object (after a step, before a game callback inside one)
	private void Push()
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		Pack(_buf);
		_gd.Call(S_IN, _buf);
		_gd.Set(S_PENDING, S.crash_pending);
		var risk = new GDict();
		foreach (var kv in S._risk) risk[kv.Key] = Gd.to_f(kv.Value);
		_gd.Set(S_RISK, risk);
		_gd.Set(S_CBHIT, new GArray { S._cb_hit[0], S._cb_hit[1] });
		if (RidePerf.On) { RidePerf.MirrorTicks += RidePerf.Now - t0; RidePerf.Mirrors++; }
	}

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

		// the game's callbacks see the state as GDScript would have it at this point of the step, and may change it
		private void Before() => _o.Push();
		private void After() => _o.Pull();
		public override void flash(string text) { Before(); base.flash(text); After(); }
		public override bool smash(GdDict c, V3 vel, V3 pos) { Before(); bool r = base.smash(c, vel, pos); After(); return r; }
		public override void rock_chips(GdDict c) { Before(); base.rock_chips(c); After(); }
		public override void burst(V3 pos, long n, long surf, double power) { Before(); base.burst(pos, n, surf, power); After(); }
		public override void start_crash(string reason) { Before(); base.start_crash(reason); After(); }
		public override void begin_getup() { Before(); base.begin_getup(); After(); }
		public override void on_style(long points, string text) { Before(); base.on_style(points, text); After(); }
		public override void on_trick(string trick) { Before(); base.on_trick(trick); After(); }
		public override void on_takeoff() { Before(); base.on_takeoff(); After(); }
		public override void on_landing(double air_time, double impact) { Before(); base.on_landing(air_time, impact); After(); }
		public override void on_bad_landing(double k) { Before(); base.on_bad_landing(k); After(); }
		public override void flow_up() { Before(); base.flow_up(); After(); }
		public override void ride_fx(double dt, V3 f, double va, bool in_water)
		{
			Before();
			base.ride_fx(dt, f, va, in_water);
			_o.S.chunk_acc = _o._gd.Get(S_CHUNK).AsDouble();   // (all the effects write back)
			_o._pushedAtFx = true;
		}

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
			var root = sim.BodyAt(1.0f) * _o._crashRK;
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
			s.counter = 0; s.rock = 0; s.pedal = 0; s.hop_nose = 0.0; s._hop_nose_t = 0.0; s._hop_nose_m = 0.0; s.yaw_rate = 0.0;
			s.body_y = s.y; s.body_v = 0; s.y_draw = s.y; s.pitch_draw = s.pitch;
		}
	}
}
