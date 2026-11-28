using Godot;
using Runout.Sim;

/// dev only: lets tools/sim_math_probe.gd run SimMath on a batch of inputs (GDScript computes the same inputs with
/// its own functions and compares bit for bit)
[GlobalClass]
public partial class SimMathProbeCs : RefCounted
{
	/// fn = SimMath.F_*, a / b = inputs; tie = 0 keep the double-double answer on near-ties, 1 count them as unknown
	public double[] Eval(long fn, double[] a, double[] b)
	{
		var r = new double[a.Length];
		for (int i = 0; i < a.Length; i++)
		{
			double x = a[i], y = b.Length > i ? b[i] : 0.0;
			r[i] = fn switch
			{
				SimMath.F_SIN => SimMath.Sin(x),
				SimMath.F_COS => SimMath.Cos(x),
				SimMath.F_TAN => SimMath.Tan(x),
				SimMath.F_ATAN => SimMath.Atan(x),
				SimMath.F_ASIN => SimMath.Asin(x),
				SimMath.F_ACOS => SimMath.Acos(x),
				SimMath.F_EXP => SimMath.Exp(x),
				SimMath.F_LOG => SimMath.Log(x),
				SimMath.F_TANH => SimMath.Tanh(x),
				SimMath.F_ATAN2 => SimMath.Atan2(x, y),
				SimMath.F_POW => SimMath.Pow(x, y),
				_ => double.NaN,
			};
		}
		return r;
	}

	/// the same with .NET's own Math (to show how far off it would be)
	public double[] EvalNet(long fn, double[] a, double[] b)
	{
		var r = new double[a.Length];
		for (int i = 0; i < a.Length; i++)
		{
			double x = a[i], y = b.Length > i ? b[i] : 0.0;
			r[i] = fn switch
			{
				SimMath.F_SIN => System.Math.Sin(x), SimMath.F_COS => System.Math.Cos(x), SimMath.F_TAN => System.Math.Tan(x),
				SimMath.F_ATAN => System.Math.Atan(x), SimMath.F_ASIN => System.Math.Asin(x), SimMath.F_ACOS => System.Math.Acos(x),
				SimMath.F_EXP => System.Math.Exp(x), SimMath.F_LOG => System.Math.Log(x), SimMath.F_TANH => System.Math.Tanh(x),
				SimMath.F_ATAN2 => System.Math.Atan2(x, y), SimMath.F_POW => System.Math.Pow(x, y), _ => double.NaN,
			};
		}
		return r;
	}

	public void SetModel(long fn, long m) => SimMath.Model[fn] = (int)m;
	public long GetModel(long fn) => SimMath.Model[fn];
	public void SetTanModel(long m) => SimMath.TanModel = (int)m;

	private static readonly string[] NAMES = { "sin", "cos", "tan", "atan", "asin", "acos", "exp", "log", "tanh", "atan2", "pow" };
	private readonly Expression[] _ex = new Expression[11];

	/// near-ties answered by the engine itself (what the Godot adapter will do), or not
	public void SetEngineTies(bool on)
	{
		SimMath.TieBreak = on ? Engine : null;
		// the adapter's platform math: tan from the engine, the rest from .NET (the same CRT as GDScript's)
		SimMath.Platform = on ? (fn, a, b) => fn == SimMath.F_TAN ? Engine(fn, a, b) : SimMath.Net(fn, a, b) : SimMath.Net;
	}

	private double Engine(int fn, double a, double b)
	{
		if (_ex[fn] == null)
		{
			_ex[fn] = new Expression();
			bool two = fn == SimMath.F_ATAN2 || fn == SimMath.F_POW;
			_ex[fn].Parse(two ? NAMES[fn] + "(a, b)" : NAMES[fn] + "(a)", two ? new[] { "a", "b" } : new[] { "a" });
		}
		var args = (fn == SimMath.F_ATAN2 || fn == SimMath.F_POW) ? new Godot.Collections.Array { a, b } : new Godot.Collections.Array { a };
		return _ex[fn].Execute(args).AsDouble();
	}

	public long Ties() => SimMath.Ties;
	public void ResetTies() => SimMath.Ties = 0;
}
