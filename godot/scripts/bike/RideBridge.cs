using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;
using Godot;
using Runout.Sim;
using GArray = Godot.Collections.Array;
using GDict = Godot.Collections.Dictionary;

/// <summary>
/// Godot glue for the engine-free ride (godot/sim): the terrain / game / suspension behind the core's interfaces, the
/// engine's own math for the few functions SimMath leaves to the platform, and the state mirror between the GDScript
/// BikePhysics and the C# BikeSim (member by member, same names). See docs/physics_port.md.
/// </summary>
public static class RideBridge
{
	private static bool _init;

	/// once: test flags, and the engine answering tan + near-ties (so the C# ride matches GDScript bit for bit on PC)
	public static void Init()
	{
		if (_init)
			return;
		_init = true;
		Runout.Sim.Env.lookup = k => DevFlags.Env(k);
		SimMath.TieBreak = EngineMath.Call;
		SimMath.Platform = (fn, a, b) => fn == SimMath.F_TAN ? EngineMath.Call(fn, a, b) : SimMath.Net(fn, a, b);
	}

	public static V3 V(Vector3 v) => new V3(v.X, v.Y, v.Z);
	public static V2 V(Vector2 v) => new V2(v.X, v.Y);
	public static Vector3 G(V3 v) => new Vector3(v.fx, v.fy, v.fz);
	public static Vector2 G(V2 v) => new Vector2(v.fx, v.fy);

	// ---------------------------------------------------------------- Variant <-> plain values
	public static object Plain(Variant v)
	{
		switch (v.VariantType)
		{
			case Variant.Type.Nil: return null;
			case Variant.Type.Bool: return v.AsBool();
			case Variant.Type.Int: return v.AsInt64();
			case Variant.Type.Float: return v.AsDouble();
			case Variant.Type.String: return v.AsString();
			case Variant.Type.StringName: return v.AsStringName().ToString();
			case Variant.Type.Vector2: return V(v.AsVector2());
			case Variant.Type.Vector3: return V(v.AsVector3());
			case Variant.Type.Dictionary: return ToDict(v.AsGodotDictionary());
			case Variant.Type.PackedVector3Array:
			{
				var a = v.AsVector3Array();
				var l = new List<V3>(a.Length);
				foreach (var p in a) l.Add(V(p));
				return l;
			}
			case Variant.Type.PackedFloat64Array: return v.AsFloat64Array();
			case Variant.Type.PackedFloat32Array: return v.AsFloat32Array();
			case Variant.Type.Array:
			{
				var a = v.AsGodotArray();
				var l = new List<object>(a.Count);
				foreach (var e in a) l.Add(Plain(e));
				return l;
			}
			default: return v.Obj;   // engine objects (nodes, resources) pass through untouched
		}
	}

	public static GdDict ToDict(GDict d, Dictionary<string, GdDict> seen = null)
	{
		var o = new GdDict(d.Count) { src = d };
		foreach (var kv in d)
		{
			string k = kv.Key.AsString();
			if (kv.Value.VariantType == Variant.Type.Dictionary)
			{
				var inner = kv.Value.AsGodotDictionary();
				string id = SpanId(inner);
				if (seen != null && id != null && seen.TryGetValue(id, out var same))
					o.set(k, same);
				else
				{
					var nd = ToDict(inner, seen);
					nd.id = id;
					if (seen != null && id != null) seen[id] = nd;
					o.set(k, nd);
				}
			}
			else
				o.set(k, Plain(kv.Value));
		}
		return o;
	}

	/// a content key for a tape span (its end points): the same span seen through two colliders is one object
	private static string SpanId(GDict d)
	{
		if (!d.ContainsKey("pts"))
			return null;
		var p = d["pts"].AsVector3Array();
		if (p.Length == 0) return null;
		return string.Format(CultureInfo.InvariantCulture, "span {0:R},{1:R},{2:R};{3:R},{4:R};{5}", p[0].X, p[0].Y, p[0].Z, p[^1].X, p[^1].Z, p.Length);
	}

	/// a content key for a collider (where it stands and how big): the same post / rock from two lookups is one object
	public static string ColliderId(GdDict c) => string.Format(CultureInfo.InvariantCulture, "{0:R},{1:R},{2:R}", c.f("x"), c.f("z"), c.f("r"));

	/// a fresh engine dictionary with the values (never the source object: the ride may have changed them)
	public static GDict ToGodotCopy(GdDict d)
	{
		if (d == null)
			return null;
		var o = new GDict();
		foreach (var kv in d)
			o[kv.Key] = ToVariant(kv.Value);
		return o;
	}

	public static GArray ToArray(System.Collections.IEnumerable l)
	{
		var a = new GArray();
		if (l != null)
			foreach (var e in l) a.Add(ToVariant(e));
		return a;
	}

	public static List<double> ToDoubles(GArray a)
	{
		var l = new List<double>(a?.Count ?? 0);
		if (a != null)
			foreach (var e in a) l.Add(e.VariantType == Variant.Type.Int ? e.AsInt64() : e.AsDouble());
		return l;
	}

	public static List<object> ToObjects(GArray a)
	{
		var l = new List<object>(a?.Count ?? 0);
		if (a != null)
			foreach (var e in a) l.Add(Plain(e));
		return l;
	}

	public static GDict ToGodot(GdDict d)
	{
		if (d.src is GDict g)
			return g;
		var o = new GDict();
		foreach (var kv in d)
			o[kv.Key] = ToVariant(kv.Value);
		return o;
	}

	public static Variant ToVariant(object v) => v switch
	{
		null => default,
		bool b => b,
		double d => d,
		float f => f,
		long l => l,
		int i => i,
		string s => s,
		V3 p => G(p),
		V2 p => G(p),
		GdDict d => ToGodot(d),
		GodotObject o => o,
		_ => default,
	};

	// ---------------------------------------------------------------- the state mirror (BikePhysics <-> BikeSim)
	/// fields that are not ride state (engine links, scratch, probes) or are synced specially
	private static readonly HashSet<string> SKIP = new HashSet<string>
	{
		"host", "prof", "_grip_noise", "_brk_noise", "_tapes_seen", "_eb", "_eb_n", "_jp_prev", "_jp_n", "_jp_t", "_jp_rim",
		"crash_K", "crash_RK",
	};

	private static List<FieldInfo> _fields;

	public static List<FieldInfo> Fields
	{
		get
		{
			if (_fields != null)
				return _fields;
			_fields = new List<FieldInfo>();
			foreach (var f in typeof(BikeSim).GetFields(BindingFlags.Public | BindingFlags.Instance))
				if (!SKIP.Contains(f.Name))
					_fields.Add(f);
			return _fields;
		}
	}

	private static readonly Dictionary<string, StringName> _names = new Dictionary<string, StringName>();

	private static StringName N(string s)
	{
		if (!_names.TryGetValue(s, out var n))
			_names[s] = n = new StringName(s);
		return n;
	}

	/// set a BikeSim field from the GDScript BikePhysics member of the same name
	public static void PullField(GodotObject gd, BikeSim s, FieldInfo f)
	{
		Variant v = gd.Get(N(f.Name));
		f.SetValue(s, Convert(v, f.FieldType, f.Name, s));
	}

	public static void Pull(GodotObject gd, BikeSim s)
	{
		foreach (var f in Fields)
			PullField(gd, s, f);
	}

	public static object Convert(Variant v, Type t, string name, BikeSim s)
	{
		if (t == typeof(double)) return v.VariantType == Variant.Type.Int ? v.AsInt64() : v.AsDouble();
		if (t == typeof(long)) return v.AsInt64();
		if (t == typeof(bool)) return v.AsBool();
		if (t == typeof(string)) return v.AsString();
		if (t == typeof(V3)) return V(v.AsVector3());
		if (t == typeof(V2)) return V(v.AsVector2());
		if (t == typeof(double[])) return v.VariantType == Variant.Type.Nil ? new double[0] : (double[])v.AsFloat64Array().Clone();
		if (t == typeof(float[])) return v.VariantType == Variant.Type.Nil ? new float[0] : (float[])v.AsFloat32Array().Clone();
		if (t == typeof(List<double>))
		{
			var l = new List<double>();
			if (v.VariantType == Variant.Type.Array) foreach (var e in v.AsGodotArray()) l.Add(e.VariantType == Variant.Type.Int ? e.AsInt64() : e.AsDouble());
			return l;
		}
		if (t == typeof(List<object>))
			return v.VariantType == Variant.Type.Array ? Plain(v) : new List<object>();
		if (t == typeof(GdDict))
		{
			if (v.VariantType != Variant.Type.Dictionary) return name == "joint_rock" ? null : new GdDict();
			var d = ToDict(v.AsGodotDictionary());
			if (name == "joint_rock") d.id = ColliderId(d);
			return d;
		}
		if (t == typeof(Pcg32))
		{
			var g = s._grip_rng ?? new Pcg32();
			if (v.Obj is GodotObject o) g.State = (ulong)o.Get("state").AsInt64();
			return g;
		}
		if (t == typeof(RideParams))
		{
			var p = s.T ?? new RideParams();
			p.v.Clear();
			if (v.VariantType == Variant.Type.Dictionary)
				foreach (var kv in v.AsGodotDictionary())
					p.v[kv.Key.AsString()] = kv.Value.VariantType == Variant.Type.Int ? kv.Value.AsInt64() : (kv.Value.VariantType == Variant.Type.Bool ? (kv.Value.AsBool() ? 1.0 : 0.0) : kv.Value.AsDouble());
			return p;
		}
		if (t == typeof(SusSetup))
			return Sus(v.VariantType == Variant.Type.Dictionary ? v.AsGodotDictionary() : null);
		if (t == typeof(ICrashSim))
			return v.Obj is GodotObject co ? new GodotCrashSim(co) : null;
		if (t == typeof(Noise2S)) return null;
		return Plain(v);
	}

	private static readonly string[] UNIT_KEYS = { "travel", "sag", "prog", "zc", "zr", "hs", "fric", "bump" };

	/// SuspSetup.resolve's dictionary as the core's SusSetup
	public static SusSetup Sus(GDict d)
	{
		var s = new SusSetup();
		if (d == null || d.Count == 0)
			return s;
		s.empty = false;
		int i = 0;
		foreach (string e in new[] { "f", "r" })
		{
			var u = d[e].AsGodotDictionary();
			foreach (string k in UNIT_KEYS)
				s.u[i++] = u[k].AsDouble();
		}
		s.u[16] = d["psi_f"].AsDouble();
		s.u[17] = d["psi_r"].AsDouble();
		return s;
	}

	/// does a BikeSim field equal the GDScript member (bit for bit for numbers)? `why` = both values when not
	public static bool Same(GodotObject gd, BikeSim s, FieldInfo f, out string why)
	{
		why = null;
		Variant v = gd.Get(N(f.Name));
		object c = f.GetValue(s);
		Type t = f.FieldType;
		if (t == typeof(double))
		{
			double a = v.VariantType == Variant.Type.Int ? v.AsInt64() : v.AsDouble(), b = (double)c;
			if (BitConverter.DoubleToInt64Bits(a) == BitConverter.DoubleToInt64Bits(b) || (double.IsNaN(a) && double.IsNaN(b)) || a == b)
				return true;
			why = $"gd={a:R} cs={b:R} d={b - a:G3}";
			return false;
		}
		if (t == typeof(long)) { long a = v.AsInt64(), b = (long)c; if (a == b) return true; why = $"gd={a} cs={b}"; return false; }
		if (t == typeof(bool)) { bool a = v.AsBool(), b = (bool)c; if (a == b) return true; why = $"gd={a} cs={b}"; return false; }
		if (t == typeof(string)) { string a = v.AsString(), b = (string)c ?? ""; if (a == b) return true; why = $"gd='{a}' cs='{b}'"; return false; }
		if (t == typeof(V3))
		{
			var a = v.AsVector3(); var b = (V3)c;
			if (a.X.Equals(b.fx) && a.Y.Equals(b.fy) && a.Z.Equals(b.fz)) return true;
			why = $"gd={a} cs={b}"; return false;
		}
		if (t == typeof(V2))
		{
			var a = v.AsVector2(); var b = (V2)c;
			if (a.X.Equals(b.fx) && a.Y.Equals(b.fy)) return true;
			why = $"gd={a} cs={b}"; return false;
		}
		if (t == typeof(GdDict))
		{
			var b = (GdDict)c;
			if (f.Name == "joint_rock")
			{
				string ia = v.VariantType == Variant.Type.Dictionary ? ColliderId(ToDict(v.AsGodotDictionary())) : null;
				if (ia == b?.id) return true;
				why = $"gd={ia} cs={b?.id}"; return false;
			}
			var a = v.VariantType == Variant.Type.Dictionary ? ToDict(v.AsGodotDictionary()) : new GdDict();
			b ??= new GdDict();
			foreach (var kv in a)
				if (!b.TryGetValue(kv.Key, out var bv) || !Gd.to_f(kv.Value).Equals(Gd.to_f(bv)))
				{
					why = $"[{kv.Key}] gd={Gd.str(kv.Value)} cs={Gd.str(bv)}"; return false;
				}
			foreach (var kv in b)
				if (!a.ContainsKey(kv.Key) && Gd.to_f(kv.Value) != 0.0)
				{
					why = $"[{kv.Key}] gd=<none> cs={Gd.str(kv.Value)}"; return false;
				}
			return true;
		}
		if (t == typeof(double[]))
		{
			var a = v.VariantType == Variant.Type.Nil ? new double[0] : v.AsFloat64Array(); var b = (double[])c;
			if (a.Length != b.Length) { why = $"len gd={a.Length} cs={b.Length}"; return false; }
			for (int i = 0; i < a.Length; i++) if (!a[i].Equals(b[i])) { why = $"[{i}] gd={a[i]:R} cs={b[i]:R}"; return false; }
			return true;
		}
		if (t == typeof(float[]))
		{
			var a = v.VariantType == Variant.Type.Nil ? new float[0] : v.AsFloat32Array(); var b = (float[])c;
			if (a.Length != b.Length) { why = $"len gd={a.Length} cs={b.Length}"; return false; }
			for (int i = 0; i < a.Length; i++) if (!a[i].Equals(b[i])) { why = $"[{i}] gd={a[i]:R} cs={b[i]:R}"; return false; }
			return true;
		}
		if (t == typeof(List<double>))
		{
			var b = (List<double>)c;
			var a = v.VariantType == Variant.Type.Array ? v.AsGodotArray() : new GArray();
			if (a.Count != b.Count) { why = $"len gd={a.Count} cs={b.Count}"; return false; }
			for (int i = 0; i < a.Count; i++) if (!Gd.to_f(Plain(a[i])).Equals(b[i])) { why = $"[{i}]"; return false; }
			return true;
		}
		if (t == typeof(Pcg32))
		{
			var b = (Pcg32)c;
			ulong a = v.Obj is GodotObject o ? (ulong)o.Get("state").AsInt64() : 0;
			if (b == null || a == b.State) return true;
			why = $"rng state gd={a} cs={b.State}"; return false;
		}
		return true;   // (engine links, the tuning set, the suspension setup: inputs, not results)
	}

	// ---------------------------------------------------------------- engine math (tan, near-ties)
	public static class EngineMath
	{
		private static readonly string[] NAMES = { "sin", "cos", "tan", "atan", "asin", "acos", "exp", "log", "tanh", "atan2", "pow" };
		private static readonly Expression[] _ex = new Expression[11];
		private static readonly GArray _a1 = new GArray { 0.0 }, _a2 = new GArray { 0.0, 0.0 };

		public static double Call(int fn, double a, double b)
		{
			bool two = fn == SimMath.F_ATAN2 || fn == SimMath.F_POW;
			if (_ex[fn] == null)
			{
				_ex[fn] = new Expression();
				_ex[fn].Parse(two ? NAMES[fn] + "(a, b)" : NAMES[fn] + "(a)", two ? new[] { "a", "b" } : new[] { "a" });
			}
			if (two)
			{
				_a2[0] = a; _a2[1] = b;
				return _ex[fn].Execute(_a2).AsDouble();
			}
			_a1[0] = a;
			return _ex[fn].Execute(_a1).AsDouble();
		}
	}
}

/// (tests, BMX_CSPERF=1) where the C# ride's step time goes: ground calls, host calls, the rest
public static class RidePerf
{
	public static readonly bool On = (DevFlags.Env("BMX_CSPERF") ?? "") != "";
	public static long MirrorTicks, Mirrors, GroundTicks, GroundCalls, HostTicks, HostCalls, StepTicks, Steps, CollTicks, CollCalls;
	public static readonly System.Diagnostics.Stopwatch W = System.Diagnostics.Stopwatch.StartNew();
	public static long Now => W.ElapsedTicks;
	public static double Ms(long t) => t * 1000.0 / System.Diagnostics.Stopwatch.Frequency;

	public static void Report()
	{
		if (Steps == 0) return;
		GD.Print($"CSPERF steps={Steps} step_us={Ms(StepTicks) * 1000 / Steps:F1} ground_us={Ms(GroundTicks) * 1000 / Steps:F1} ({GroundCalls / (double)Steps:F1} calls) colliders_us={Ms(CollTicks) * 1000 / Steps:F1} ({CollCalls / (double)Steps:F2} calls) host_us={Ms(HostTicks) * 1000 / Steps:F1} ({HostCalls / (double)Steps:F1} calls) core_us={(Ms(StepTicks - GroundTicks - HostTicks) * 1000) / Steps:F1} mirror_us={Ms(MirrorTicks) * 1000 / Steps:F1} ({Mirrors / (double)Steps:F1} a step)");
		MirrorTicks = Mirrors = 0;
		GroundTicks = GroundCalls = HostTicks = HostCalls = StepTicks = Steps = CollTicks = CollCalls = 0;
	}
}

/// <summary>The game's Terrain (GDScript) as the core's ground. On the world's own Terrain (no rope bridge loaded) the
/// height / deck / surface / jump queries go straight to the C# objects Terrain itself uses (TerrainFieldCs, RutFieldCs),
/// with the same arithmetic as terrain.gd, so the numbers are the same; anything else asks Terrain.</summary>
public sealed class GodotGround : IGround
{
	public readonly GodotObject T;
	private static readonly StringName S_HEIGHT = "height", S_DECK = "deck_height", S_TOP = "top_height", S_SURF = "surface",
		S_JUMP = "jump_mask", S_NEAR = "colliders_near", S_FCS = "fcs", S_RUT = "rut_field", S_BOX = "rut_box", S_ROPES = "ropes";
	private static readonly bool NO_FAST = (DevFlags.Env("BMX_CS_GROUND_GD") ?? "") != "";
	private readonly bool _plainTerrain;
	private TerrainFieldCs _fcs;
	private RutFieldCs _rut;
	private Vector4 _box;
	private bool _fast;

	public GodotGround(GodotObject terrain)
	{
		T = terrain;
		var scr = terrain.GetScript().Obj as Script;
		_plainTerrain = scr != null && scr.ResourcePath == "res://scripts/world/terrain.gd";
	}

	/// once a physics step: what terrain.gd's queries would read (its field, the ruts' window, rope bridges)
	public void BeginStep()
	{
		_fast = false;
		if (NO_FAST || !_plainTerrain) return;
		_fcs = T.Get(S_FCS).Obj as TerrainFieldCs;
		if (_fcs == null) return;
		if (T.Get(S_ROPES).AsGodotArray().Count > 0) return;   // (rope decks: Terrain._rope_deck)
		_rut = T.Get(S_RUT).Obj as RutFieldCs;
		_box = T.Get(S_BOX).AsVector4();
		_fast = true;
	}

	/// Terrain.rut_at
	private double Rut(double x, double z)
	{
		if (_rut == null || x < _box.X || z < _box.Y || x > _box.Z || z > _box.W) return 0.0;
		return _rut.Depth((float)x, (float)z);
	}

	public double height(double x, double z)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		double r = _fast ? _fcs.height(x, z) - Rut(x, z) : T.Call(S_HEIGHT, x, z).AsDouble();
		if (RidePerf.On) { RidePerf.GroundTicks += RidePerf.Now - t0; RidePerf.GroundCalls++; }
		return r;
	}

	public double deck_height(double x, double z)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		double r = _fast ? _fcs.deck(x, z) - Rut(x, z) : T.Call(S_DECK, x, z).AsDouble();
		if (RidePerf.On) { RidePerf.GroundTicks += RidePerf.Now - t0; RidePerf.GroundCalls++; }
		return r;
	}

	public double top_height(double x, double z)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		double r = T.Call(S_TOP, x, z).AsDouble();
		if (RidePerf.On) { RidePerf.GroundTicks += RidePerf.Now - t0; RidePerf.GroundCalls++; }
		return r;
	}

	public long surface(double x, double z)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		long r = _fast ? _fcs.surface_at(x, z, _fcs.height(x, z) - Rut(x, z)) : T.Call(S_SURF, x, z).AsInt64();
		if (RidePerf.On) { RidePerf.GroundTicks += RidePerf.Now - t0; RidePerf.GroundCalls++; }
		return r;
	}

	public double jump_mask(double x, double z)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		double r = _fast ? _fcs.jump_mask(x, z) : T.Call(S_JUMP, x, z).AsDouble();
		if (RidePerf.On) { RidePerf.GroundTicks += RidePerf.Now - t0; RidePerf.GroundCalls++; }
		return r;
	}

	public List<GdDict> colliders_near(double x, double z)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		var l0 = Near(x, z);
		if (RidePerf.On) { long d = RidePerf.Now - t0; RidePerf.GroundTicks += d; RidePerf.CollTicks += d; RidePerf.CollCalls++; }
		return l0;
	}

	private List<GdDict> Near(double x, double z)
	{
		var a = T.Call(S_NEAR, x, z).AsGodotArray();
		var l = new List<GdDict>(a.Count);
		var seen = new Dictionary<string, GdDict>();
		foreach (var e in a)
		{
			var d = RideBridge.ToDict(e.AsGodotDictionary(), seen);
			d.id = RideBridge.ColliderId(d);
			l.Add(d);
		}
		return l;
	}

	public RayHit cast(V3 origin, V3 dir, double max_dist)
	{
		// a height field: straight down only (the contact model on walls / overhangs is a future feature)
		var h = new RayHit();
		if (dir.fy >= 0f) return h;
		double gy = height(origin.x, origin.z);
		double d = (origin.y - gy) / -dir.y;
		if (d < 0 || d > max_dist) return h;
		h.hit = true; h.distance = d; h.point = new V3(origin.x, gy, origin.z); h.normal = V3.UP; h.surface = (int)surface(origin.x, origin.z);
		return h;
	}
}

/// <summary>The drawn Suspension (GDScript) for the core.</summary>
public sealed class GodotSusp : ISusp
{
	public readonly GodotObject S;
	public bool Effects = true;   // (the lockstep twin reads it but must not move it)

	public GodotSusp(GodotObject s) { S = s; }

	public bool has_f => S.Get("has_f").AsBool();
	public bool has_r => S.Get("has_r").AsBool();
	public bool wheels_follow => S.Get("wheels_follow").AsBool();
	public V3 axis => RideBridge.V(S.Get("axis").AsVector3());
	public GdDict F => RideBridge.ToDict(S.Get("F").AsGodotDictionary());
	public GdDict R => RideBridge.ToDict(S.Get("R").AsGodotDictionary());
	public bool has_method(string name) => S.HasMethod(name);
	public void set_sag(double f, double r) { if (Effects) S.Call("set_sag", f, r); }
	public void land(double impact, bool front_air, bool rear_air) { if (Effects) S.Call("land", impact, front_air, rear_air); }
	public void update(double dt, GdDict state) { if (Effects) S.Call("update", dt, RideBridge.ToGodot(state)); }
}

/// <summary>A CrashBikeCs (engine object) held by the core while crashed.</summary>
public sealed class GodotCrashSim : ICrashSim
{
	public readonly GodotObject O;
	public GodotCrashSim(GodotObject o) { O = o; }
}

/// <summary>Game (GDScript) as the core's host.</summary>
public class GodotRideHost : IRideHost
{
	public readonly GodotObject Game;
	private GodotGround _ground;
	private GodotSusp _susp;
	private static readonly StringName S_TERRAIN = "terrain", S_SUSP = "susp", S_RAG = "ragdoll", S_GETUP = "getup_anim", S_PEDAL = "pedal_a0";

	public GodotRideHost(GodotObject game) { Game = game; }

	public IGround terrain
	{
		get
		{
			long t0 = RidePerf.On ? RidePerf.Now : 0;
			var t = Game.Get(S_TERRAIN).Obj as GodotObject;
			if (RidePerf.On) { RidePerf.HostTicks += RidePerf.Now - t0; RidePerf.HostCalls++; }
			if (t == null) return null;
			if (_ground == null || _ground.T != t) _ground = new GodotGround(t);
			return _ground;
		}
	}

	public virtual ISusp susp
	{
		get
		{
			var s = Game.Get(S_SUSP).Obj as GodotObject;
			if (s == null) return null;
			if (_susp == null || _susp.S != s) _susp = new GodotSusp(s);
			return _susp;
		}
	}

	public object ragdoll => Game.Get(S_RAG).Obj;
	public object getup_anim => Game.Get(S_GETUP).Obj;

	public List<double> pedal_a0
	{
		get
		{
			var l = new List<double>(2);
			foreach (var e in Game.Get(S_PEDAL).AsGodotArray()) l.Add(e.AsDouble());
			return l;
		}
	}

	public bool has_method(string name) => Game.HasMethod(name);
	public virtual void flash(string text) => Game.Call("flash", text);
	public virtual bool msg_idle()
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		bool r = Game.Call("msg_idle").AsBool();
		if (RidePerf.On) { RidePerf.HostTicks += RidePerf.Now - t0; RidePerf.HostCalls++; }
		return r;
	}
	public virtual bool smash(GdDict c, V3 vel, V3 pos) => Game.Call("smash", RideBridge.ToGodot(c), RideBridge.G(vel), RideBridge.G(pos)).AsBool();
	public virtual void rock_chips(GdDict c) => Game.Call("rock_chips", RideBridge.ToGodot(c));
	public virtual void burst(V3 pos, long n, long surf, double power) => Game.Call("burst", RideBridge.G(pos), n, surf, power);
	public virtual void start_crash(string reason) => Game.Call("start_crash", reason);
	public virtual void begin_getup() => Game.Call("begin_getup");
	public virtual void on_style(long points, string text) => Game.Call("on_style", points, text);
	public virtual void on_trick(string trick) => Game.Call("on_trick", trick);
	public virtual void on_takeoff() => Game.Call("on_takeoff");
	public virtual void on_landing(double air_time, double impact) => Game.Call("on_landing", air_time, impact);
	public virtual void on_bad_landing(double k) => Game.Call("on_bad_landing", k);
	public virtual void ride_fx(double dt, V3 f, double va, bool in_water)
	{
		long t0 = RidePerf.On ? RidePerf.Now : 0;
		Game.Call("ride_fx", dt, RideBridge.G(f), va, in_water);
		if (RidePerf.On) { RidePerf.HostTicks += RidePerf.Now - t0; RidePerf.HostCalls++; }
	}
	public virtual void flow_up() => Game.Call("flow_up");
	public virtual void log(string text) => GD.Print(text);
	public virtual void crashlog_note(string text) => ((Engine.GetMainLoop() as SceneTree)?.Root.GetNodeOrNull("CrashLog"))?.Call("note", text);
	public virtual void crash_body_step(BikeSim s, double dt, RideInput inp) { }   // (C# mode: the crashed bike + ragdoll, step 5)
	public long get_ticks_usec() => (long)Time.GetTicksUsec();
	public long get_ticks_msec() => (long)Time.GetTicksMsec();
	public long get_physics_frames() => (long)Engine.GetPhysicsFrames();
}
