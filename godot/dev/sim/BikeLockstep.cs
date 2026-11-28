using System;
using System.Collections.Generic;
using System.Linq;
using Godot;
using Runout.Sim;

/// <summary>
/// (dev, BMX_PHYS=cmp) The C# ride stepped beside the GDScript one: every physics tick the GDScript BikePhysics' state is
/// copied into a BikeSim, both step with the same input (and the same answers from the game), and every member is
/// compared bit for bit. Re-copied every tick, so a difference shows in the tick it is made. PHYSCMP lines.
/// </summary>
[GlobalClass]
public partial class BikeLockstep : RefCounted
{
	private BikeSim _s;
	private TwinHost _host;
	private RideInput _inp = new RideInput();
	private long _ticks, _bad_ticks, _skipped, _printed, _smash_skipped;
	private readonly Dictionary<string, long> _bad_by = new Dictionary<string, long>();
	private readonly Dictionary<string, string> _first = new Dictionary<string, string>();
	private bool _was_crash;
	/// members the game writes from its effects callbacks (the twin's are no-ops): not ride results
	private static readonly HashSet<string> HOST_OWNED = new HashSet<string> { "chunk_acc" };
	private readonly int _print_max = int.TryParse(DevFlags.Env("BMX_PHYSCMP_PRINT") ?? "", out var pm) ? pm : 40;

	/// before GDScript steps: copy its state in, keep the input
	public void Before(GodotObject phys, Godot.Collections.Dictionary inp, GodotObject game)
	{
		RideBridge.Init();
		if (_s == null)
		{
			_host = new TwinHost(game);
			_s = new BikeSim(_host);
		}
		_was_crash = phys.Get("crash_on").AsBool() || phys.Get("crash_pending").AsString() != "";
		if (_was_crash)
			return;
		RideBridge.Pull(phys, _s);
		_s.host = _host;
		_s.prof = null;
		_inp.v.Clear();
		foreach (var kv in inp)
		{
			var v = kv.Value;
			_inp.v[kv.Key.AsString()] = v.VariantType == Variant.Type.Bool ? (v.AsBool() ? 1.0 : 0.0) : (v.VariantType == Variant.Type.Int ? v.AsInt64() : v.AsDouble());
		}
	}

	/// after GDScript stepped: step the twin with the same answers and compare
	public void After(GodotObject phys, double dt, Godot.Collections.Array answers, bool smashed)
	{
		_ticks++;
		if (_was_crash || phys.Get("crash_on").AsBool())
		{
			_skipped++;
			return;
		}
		if (smashed)
		{
			_smash_skipped++;
			return;
		}
		_host.Answers.Clear();
		foreach (var a in answers) _host.Answers.Enqueue(a.AsBool());
		string err = null;
		try { _s.step(dt, _inp); }
		catch (Exception e) { err = e.GetType().Name + ": " + e.Message + " @ " + e.StackTrace?.Split('\n').FirstOrDefault(l => l.Contains("BikeSim"))?.Trim(); }
		var bad = new List<string>();
		if (err != null) bad.Add("EXCEPTION " + err);
		foreach (var f in RideBridge.Fields)
		{
			if (HOST_OWNED.Contains(f.Name))
				continue;
			if (!RideBridge.Same(phys, _s, f, out string why))
			{
				bad.Add(f.Name + " " + why);
				_bad_by[f.Name] = _bad_by.TryGetValue(f.Name, out long n) ? n + 1 : 1;
				if (!_first.ContainsKey(f.Name)) _first[f.Name] = $"tick {_ticks}: {why}";
			}
		}
		if (bad.Count == 0)
			return;
		_bad_ticks++;
		if (_printed < _print_max)
		{
			_printed++;
			GD.Print($"PHYSCMP tick={_ticks} mismatches={bad.Count} air={phys.Get("air")} v={phys.Get("v").AsDouble():F2} | {string.Join(" | ", bad.Take(8))}");
		}
	}

	public void Report()
	{
		GD.Print($"PHYSCMP SUM ticks={_ticks} compared={_ticks - _skipped - _smash_skipped} bad_ticks={_bad_ticks} crashed_skipped={_skipped} smash_skipped={_smash_skipped} ties={SimMath.Ties}");
		foreach (var kv in _bad_by.OrderByDescending(k => k.Value).Take(40))
			GD.Print($"PHYSCMP FIELD {kv.Key} bad={kv.Value} first {_first[kv.Key]}");
		GD.Print(_bad_ticks == 0 ? "PHYSCMP PASS" : "PHYSCMP FAIL");
	}

	/// the game as the twin's host: reads go to the game; the answers are GDScript's; nothing is drawn / moved twice
	private sealed class TwinHost : GodotRideHost
	{
		public readonly Queue<bool> Answers = new Queue<bool>();
		private GodotSusp _sp;

		public TwinHost(GodotObject game) : base(game) { }

		public override ISusp susp
		{
			get
			{
				var s = base.susp as GodotSusp;
				if (s == null) return null;
				if (_sp == null || _sp.S != s.S) _sp = new GodotSusp(s.S) { Effects = false };
				return _sp;
			}
		}

		private bool Next() => Answers.Count > 0 ? Answers.Dequeue() : false;
		public override bool msg_idle() => Next();
		public override bool smash(GdDict c, V3 vel, V3 pos) => Next();
		public override void flash(string text) { }
		public override void rock_chips(GdDict c) { }
		public override void burst(V3 pos, long n, long surf, double power) { }
		public override void start_crash(string reason) { }
		public override void begin_getup() { }
		public override void on_style(long points, string text) { }
		public override void on_trick(string trick) { }
		public override void on_takeoff() { }
		public override void on_landing(double air_time, double impact) { }
		public override void on_bad_landing(double k) { }
		public override void ride_fx(double dt, V3 f, double va, bool in_water) { }
		public override void flow_up() { }
		public override void log(string text) { }
		public override void crashlog_note(string text) { }
	}
}
