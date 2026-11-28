using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using Runout.Config;
using Runout.Rider;
using Runout.Sim;

namespace Runout.Sim.Tests
{
    /// The crashed bike (Assets/Runout/Rider/CrashBike, port of CrashBikeCs): the DH built from its extras (hull points
    /// per node, placed with the node transforms read from godot/assets/dh.glb) dropped at 10 m/s, 0.5 m up, leaned 0.6
    /// rad over flat ground for 4 s. No NaN, never more than 5 cm into the ground, comes to rest.
    static class CrashBikeSmoke
    {
        public static int Run(string repoUnity)
        {
            string err = null, detail = "";
            try { detail = Go(repoUnity); }
            catch (Exception e) { err = e.GetType().Name + ": " + e.Message + " @ " + e.StackTrace?.Split('\n')[0]; }
            bool ok = err == null && detail.StartsWith("ok");
            Console.WriteLine($"{(ok ? "PASS" : "FAIL")} crashbike_smoke {err ?? detail}");
            return ok ? 0 : 1;
        }

        static string Go(string repoUnity)
        {
            string extrasPath = Path.Combine(repoUnity, "Assets", "Runout", "Art", "Models", "Bikes", "dh.extras.txt");
            string glbPath = Path.Combine(repoUnity, "..", "godot", "assets", "dh.glb");
            var ex = new Dictionary<string, double[]>();
            foreach (var raw in File.ReadAllLines(extrasPath))
            {
                int i = raw.IndexOf('=');
                if (i <= 0 || raw.StartsWith("root=")) continue;
                var parts = raw.Substring(i + 1).Split(',');
                var vals = new double[parts.Length];
                bool good = true;
                for (int k = 0; k < parts.Length; k++) good &= double.TryParse(parts[k], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out vals[k]);
                if (good) ex[raw.Substring(0, i)] = vals;
            }
            var world = NodeWorld(glbPath);   // node name -> world transform in the model's space (the bike root = identity)
            Vec3 V(double[] a, int o = 0) => new Vec3(a[o], a[o + 1], a[o + 2]);

            // the model: placed so the lowest tyre is 0.5 m over flat ground (y = 0), leaned 0.6 rad (lean_g: about x by -lean)
            double rf = ex["wheelRadius"][0], rr = ex["wheelRadiusRear"][0];
            Xf wf0 = world["wheel_front"], wr0 = world["wheel_rear"];
            double lowest = Math.Min(wf0.o.y - rf, wr0.o.y - rr);
            Xf model = new Xf(Basis.axis_angle(Vec3.RIGHT, -0.6), new Vec3(0, 0.5 - lowest, 0));
            Xf W(string n) => CrashBike.Mul(model, world[n]);

            var d = new CrashBikeStartInput { model = model, leanFrame = model, wheelRF = rf, wheelRR = rr };
            foreach (var kv in ex)
            {
                bool fr = kv.Key.StartsWith("rig.hull.frame."), st = kv.Key.StartsWith("rig.hull.steer.");
                if (!fr && !st) continue;
                string node = kv.Key.Substring(15);
                if (!world.ContainsKey(node)) continue;
                Xf nx = W(node);
                for (int k = 0; k + 2 < kv.Value.Length; k += 3) (fr ? d.frameHull : d.steerHull).Add(nx * V(kv.Value, k));
            }
            d.wheelF = W("wheel_front"); d.wheelR = W("wheel_rear");
            Xf steer = W("steer");
            d.steerPivot = steer.o;
            Xf steerParent = W(Parent(glbPath, "steer"));
            d.steerAxis = (steerParent.b * V(ex["steerAxis"])).normalized();
            d.steerAngle = 0.0;
            Xf crank = W("crank");
            d.crank = crank.o;
            d.gripL = steer * V(ex["rig.gripL"]); d.gripR = steer * V(ex["rig.gripR"]);
            d.pedals = new[] { crank * V(ex["rig.pedalL"]), crank * V(ex["rig.pedalR"]) };

            var h = new TraceCompare.Host();
            var s = new BikeSim(h) { T = new Tune().fill(new RideParams()) }; h.phys = s;
            var cfg = new GdDict(); cfg.set("geared", false);
            var ge = new GdDict(); ge["wheelbase"] = ex["wheelbase"][0]; ge["wheelRadius"] = rf; ge["wheelRadiusRear"] = rr; ge["bbToRearAxle"] = ex["bbToRearAxle"][0];
            s.setup(ge, cfg);
            s.reset_at(0, 0, 0);
            s.v = 10.0; s.bike_lean = 0.6;
            s.begin_crash();
            Func<double, double, double> flat = (x, z) => 0.0;
            var built = CrashBikeStart.Build(s, d, flat);
            var b = built.bike;
            double deepest = -1e9, speed = 0;
            int steps = 480;
            for (int i = 0; i < steps; i++)
            {
                CrashBikeHost.Step(s, b, 1.0 / 120.0, flat, null);
                deepest = Math.Max(deepest, b.Deepest());
                double[] p = b.Points();
                foreach (double v in p) if (double.IsNaN(v) || double.IsInfinity(v)) return $"NaN at step {i}";
                if (double.IsNaN(s.x) || double.IsNaN(s.heading) || double.IsNaN(s.bike_lean)) return $"BikeSim NaN at step {i}";
            }
            Vec3 vel = b.Velocity();
            speed = vel.length();
            bool rest = b.Asleep || speed < 0.2;
            string info = $"points {b.PointCount}, deepest {deepest * 100:0.0} cm, end speed {speed:0.00} m/s, asleep {b.Asleep}, " +
                          $"slid to x {s.x:0.00} z {s.z:0.00}, lean {s.bike_lean:0.00} rad, bars {s.steer:0.00} rad, v {s.v:0.00}";
            return (deepest < 0.05 && rest ? "ok: " : "bad: ") + info;
        }

        // ---- the glb's node transforms (glTF: translation / rotation / scale or a matrix, parents first) ----
        static Dictionary<string, Xf> _world;
        static Dictionary<string, string> _parent;

        static JsonElement Json(string glb)
        {
            byte[] b = File.ReadAllBytes(glb);
            int n = BitConverter.ToInt32(b, 12);
            return JsonDocument.Parse(new ReadOnlyMemory<byte>(b, 20, n)).RootElement;
        }

        static string Parent(string glb, string name) { NodeWorld(glb); return _parent.TryGetValue(name, out var p) ? p : name; }

        static Dictionary<string, Xf> NodeWorld(string glb)
        {
            if (_world != null) return _world;
            var j = Json(glb);
            var nodes = j.GetProperty("nodes");
            int cnt = nodes.GetArrayLength();
            var local = new Xf[cnt]; var par = new int[cnt];
            for (int i = 0; i < cnt; i++) par[i] = -1;
            for (int i = 0; i < cnt; i++)
            {
                var n = nodes[i];
                local[i] = Local(n);
                if (n.TryGetProperty("children", out var ch)) foreach (var c in ch.EnumerateArray()) par[c.GetInt32()] = i;
            }
            // the bike's root (the node carrying the extras) = the model's space
            int root = -1;
            for (int i = 0; i < cnt; i++) if (nodes[i].TryGetProperty("extras", out var e) && e.ValueKind == JsonValueKind.Object && e.TryGetProperty("wheelbase", out _)) root = i;
            _world = new Dictionary<string, Xf>(); _parent = new Dictionary<string, string>();
            for (int i = 0; i < cnt; i++)
            {
                Xf w = Xf.IDENTITY; int k = i; bool inside = false;
                while (k >= 0) { if (k == root) { inside = true; break; } w = CrashBike.Mul(local[k], w); k = par[k]; }
                if (!inside && i != root) continue;
                string nm = nodes[i].TryGetProperty("name", out var nn) ? nn.GetString() : "node" + i;
                if (!_world.ContainsKey(nm)) _world[nm] = w;
                if (par[i] >= 0 && nodes[par[i]].TryGetProperty("name", out var pn)) _parent[nm] = pn.GetString();
            }
            return _world;
        }

        static Xf Local(JsonElement n)
        {
            if (n.TryGetProperty("matrix", out var m))
            {
                var a = new double[16]; int i = 0;
                foreach (var v in m.EnumerateArray()) a[i++] = v.GetDouble();
                return new Xf(new Basis(new Vec3(a[0], a[1], a[2]), new Vec3(a[4], a[5], a[6]), new Vec3(a[8], a[9], a[10])), new Vec3(a[12], a[13], a[14]));
            }
            Vec3 t = Vec3.ZERO, sc = new Vec3(1, 1, 1);
            Quat q = Quat.IDENTITY;
            if (n.TryGetProperty("translation", out var tt)) t = new Vec3(tt[0].GetDouble(), tt[1].GetDouble(), tt[2].GetDouble());
            if (n.TryGetProperty("rotation", out var rr)) q = new Quat(rr[0].GetDouble(), rr[1].GetDouble(), rr[2].GetDouble(), rr[3].GetDouble());
            if (n.TryGetProperty("scale", out var ss)) sc = new Vec3(ss[0].GetDouble(), ss[1].GetDouble(), ss[2].GetDouble());
            Basis r = Basis.from_quat(q);
            return new Xf(new Basis(r.x * sc.x, r.y * sc.y, r.z * sc.z), t);
        }
    }
}
