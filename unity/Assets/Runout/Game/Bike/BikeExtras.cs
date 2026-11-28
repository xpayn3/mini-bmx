using System.Collections.Generic;
using System.Globalization;
using UnityEngine;

namespace Runout.Game
{
    /// A bike glb's root extras (Godot: model.get_meta("extras")), read from the <name>.extras.txt that
    /// unity/Tools/glb_extras.py writes next to the model (glTFast drops extras). Keys are dotted paths:
    /// steerAxis, wheelRadius, suspension.rear.G1 ...
    public sealed class BikeExtras
    {
        readonly Dictionary<string, double[]> _v = new Dictionary<string, double[]>();
        public string root = "dh";

        public static BikeExtras Parse(string text)
        {
            var e = new BikeExtras();
            foreach (var raw in text.Split('\n'))
            {
                var ln = raw.Trim();
                int i = ln.IndexOf('=');
                if (i <= 0) continue;
                string k = ln.Substring(0, i), val = ln.Substring(i + 1);
                if (k == "root") { e.root = val; continue; }
                var parts = val.Split(',');
                var d = new double[parts.Length];
                bool ok = true;
                for (int j = 0; j < parts.Length; j++)
                    ok &= double.TryParse(parts[j], NumberStyles.Float, CultureInfo.InvariantCulture, out d[j]);
                if (ok) e._v[k] = d;
            }
            return e;
        }

        public bool has(string k) => _v.ContainsKey(k);
        public bool has_prefix(string p) { foreach (var k in _v.Keys) if (k.StartsWith(p)) return true; return false; }
        public List<string> keys(string prefix) { var o = new List<string>(); foreach (var k in _v.Keys) if (k.StartsWith(prefix)) o.Add(k); return o; }
        public double[] list(string k) => _v.TryGetValue(k, out var a) ? a : new double[0];
        public double f(string k, double d = 0.0) => _v.TryGetValue(k, out var a) && a.Length > 0 ? a[0] : d;
        public Vector2 v2(string k) => _v.TryGetValue(k, out var a) && a.Length >= 2 ? new Vector2((float)a[0], (float)a[1]) : Vector2.zero;
        public Vector3 v3(string k, Vector3 d) => _v.TryGetValue(k, out var a) && a.Length >= 3 ? new Vector3((float)a[0], (float)a[1], (float)a[2]) : d;
    }
}
