using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace Runout.World
{
	/// Reads the tagged binary tree godot/tools/world_dump.gd writes ("RWD1"): Godot's world tables, as the reference
	/// the port is checked against. Values: null, bool, long, double, string, double[] (f64), float[] (f32), int[],
	/// long[], TfColor, List<object>, Dictionary<object, object>, RwdObject, TfColor[], Vec2, Vec3, string[].
	public static class Rwd
	{
		public static object Load(string path)
		{
			using var s = File.OpenRead(path);
			using var r = new BinaryReader(s);
			var magic = Encoding.ASCII.GetString(r.ReadBytes(4));
			if (magic != "RWD1") throw new InvalidDataException(path + ": not an RWD1 file");
			var objs = new List<RwdObject>();
			return Val(r, objs);
		}

		static string Str(BinaryReader r) => Encoding.UTF8.GetString(r.ReadBytes(r.ReadInt32()));

		static object Val(BinaryReader r, List<RwdObject> objs)
		{
			int tag = r.ReadByte();
			int n;
			switch (tag)
			{
				case 0: return null;
				case 1: return r.ReadByte() != 0;
				case 2: return r.ReadInt64();
				case 3: return r.ReadDouble();
				case 4: return Str(r);
				case 5: { n = r.ReadInt32(); var a = new double[n]; for (int i = 0; i < n; i++) a[i] = r.ReadDouble(); return a; }
				case 6: { n = r.ReadInt32(); var a = new float[n]; for (int i = 0; i < n; i++) a[i] = r.ReadSingle(); return a; }
				case 7: { n = r.ReadInt32(); var a = new int[n]; for (int i = 0; i < n; i++) a[i] = r.ReadInt32(); return a; }
				case 8: { n = r.ReadInt32(); var a = new long[n]; for (int i = 0; i < n; i++) a[i] = r.ReadInt64(); return a; }
				case 9: return new TfColor(r.ReadSingle(), r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
				case 10: { n = r.ReadInt32(); var a = new List<object>(n); for (int i = 0; i < n; i++) a.Add(Val(r, objs)); return a; }
				case 11:
				{
					n = r.ReadInt32();
					var d = new Dictionary<object, object>(n);
					for (int i = 0; i < n; i++) { var k = Val(r, objs); d[k] = Val(r, objs); }
					return d;
				}
				case 12:
				{
					var o = new RwdObject { Class = Str(r) };
					objs.Add(o);
					var d = (Dictionary<object, object>)Val(r, objs);
					foreach (var kv in d) o.Fields[(string)kv.Key] = kv.Value;
					return o;
				}
				case 13: return objs[r.ReadInt32()];
				case 14:
				{
					n = r.ReadInt32();
					var a = new TfColor[n];
					for (int i = 0; i < n; i++) a[i] = new TfColor(r.ReadSingle(), r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
					return a;
				}
				case 15: return new Vec2(r.ReadSingle(), r.ReadSingle());
				case 16: return new Vec3(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());
				case 17: { n = r.ReadInt32(); var a = new string[n]; for (int i = 0; i < n; i++) a[i] = Str(r); return a; }
				default: throw new InvalidDataException("RWD: unknown tag " + tag);
			}
		}

		// ---------------- typed reads (Godot's packed arrays widen to double like TerrainFieldCs did)
		public static double D(object v) => v switch { double d => d, long l => l, bool b => b ? 1 : 0, _ => throw new InvalidCastException("RWD: not a number: " + v) };
		public static long L(object v) => v switch { long l => l, double d => (long)d, bool b => b ? 1 : 0, _ => throw new InvalidCastException("RWD: not an int: " + v) };
		public static double[] F64(object v)
		{
			switch (v)
			{
				case double[] d: return d;
				case float[] f: { var o = new double[f.Length]; for (int i = 0; i < f.Length; i++) o[i] = f[i]; return o; }
				case List<object> l: { var o = new double[l.Count]; for (int i = 0; i < l.Count; i++) o[i] = D(l[i]); return o; }
				case int[] n: { var o = new double[n.Length]; for (int i = 0; i < n.Length; i++) o[i] = n[i]; return o; }
				case long[] n: { var o = new double[n.Length]; for (int i = 0; i < n.Length; i++) o[i] = n[i]; return o; }
				case null: return Array.Empty<double>();
				default: throw new InvalidCastException("RWD: not a float array: " + v);
			}
		}
		public static int[] I32(object v) => v switch { int[] i => i, null => Array.Empty<int>(), _ => throw new InvalidCastException("RWD: not an int array: " + v) };
	}

	/// a GDScript object in the dump: its class and script variables
	public sealed class RwdObject
	{
		public string Class;
		public readonly Dictionary<string, object> Fields = new Dictionary<string, object>();
		public object this[string k] => Fields.TryGetValue(k, out var v) ? v : null;
		public bool Has(string k) => Fields.ContainsKey(k);
	}
}
