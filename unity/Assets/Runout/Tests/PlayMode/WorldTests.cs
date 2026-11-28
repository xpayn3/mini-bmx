using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.IO;
using NUnit.Framework;
using Runout.Game;
using Runout.Sim;
using UnityEngine;
using UnityEngine.Rendering.HighDefinition;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace Runout.Tests
{
    /// The procedural world in play mode (Scenes/World.unity): the world built from its seed in C#, the bike ridden down the
    /// real trail by our physics, the terrain streamed round it. Every frame: the physics stays finite and on the ground (never
    /// under it, never floating far above it unless in the air). At the end: near + far tiles loaded, streaming's main-thread
    /// cost, a few screenshots (Logs/world_*.png). Run headless: unity/Tools/test_world.ps1 (or the editor's Test Runner).
    public class WorldTests
    {
        static readonly string Shots = Path.Combine(Application.dataPath, "..", "Logs");

        [UnityTest]
        public IEnumerator RideTheWorld()
        {
            SceneManager.LoadScene("World");
            yield return null;
            yield return null;
            var world = Object.FindFirstObjectByType<WorldStreamer>();
            Assert.NotNull(world, "WorldStreamer in the World scene");
            Assert.NotNull(world.Field, "the world was built from its seed");
            var host = Object.FindFirstObjectByType<SimHost>();
            var boot = host.GetComponent<RideBootstrap>();
            Assert.NotNull(boot.Sim, "the ride is built");
            var sim = boot.Sim;
            var drawn = Object.FindFirstObjectByType<BikeDraw>();
            Debug.Log($"WORLDTEST seed {world.seed}: {world.Course.length / 1000.0:0.0} km of trail, {world.Tables.route_feats.Count} route features, spawn {sim.x:0.0},{sim.z:0.0}");

            double startX = sim.x, startZ = sim.z, vmax = 0.0, worstUnder = 0.0, worstAbove = 0.0, dist = 0.0;
            double px = sim.x, pz = sim.z;
            int frames = 0, airFrames = 0;
            string bad = null;
            var inp = new RideInput();
            inp.set("throttle", 1.0);
            host.overrideInput = inp;
            float t = 0f, nextShot = 2f;
            int shot = 0;
            var ride = new FrameStats { world = world };
            AllocProbe.on = true;
            AllocProbe.Reset();
            var gcRec = Unity.Profiling.ProfilerRecorder.StartNew(Unity.Profiling.ProfilerCategory.Memory, "GC Allocated In Frame");
            long gcBytes = 0; int gcFrames = 0;
            while (t < 20f && bad == null)
            {
                t += Time.deltaTime;
                yield return null;
                frames++;
                ride.Add();
                if (gcRec.Valid) { gcBytes += gcRec.LastValue; gcFrames++; }
                if (double.IsNaN(sim.x) || double.IsNaN(sim.y) || double.IsNaN(sim.z) || double.IsNaN(sim.v)) { bad = $"NaN at {t:0.0} s"; break; }
                double g = world.Ground.height(sim.x, sim.z);
                double gap = sim.y - g;   // the bike's point over the ground it rides
                if (sim.air) airFrames++;
                else
                {
                    worstUnder = System.Math.Min(worstUnder, gap);
                    worstAbove = System.Math.Max(worstAbove, gap);
                }
                if (gap < -0.5) bad = $"under the ground by {-gap:0.00} m at {t:0.0} s ({sim.x:0.0},{sim.z:0.0})";
                vmax = System.Math.Max(vmax, sim.v);
                dist += System.Math.Sqrt((sim.x - px) * (sim.x - px) + (sim.z - pz) * (sim.z - pz));
                px = sim.x; pz = sim.z;
                if (t >= nextShot && drawn != null)
                {
                    Shot(drawn, $"world_{shot++}_ride.png", false);
                    ride.shotFrame = Time.frameCount;
                    nextShot += 9f;
                }
            }
            if (drawn != null) Shot(drawn, "world_high.png", true);
            Debug.Log($"WORLDTEST rode {t:0.0} s, {frames} frames: {dist:0} m ({System.Math.Sqrt((sim.x - startX) * (sim.x - startX) + (sim.z - startZ) * (sim.z - startZ)):0} m from the start), top {vmax * 3.6:0} km/h, air {airFrames} frames, crashed {sim.crash_on} {sim.crash_pending}, on the ground the bike point sat {worstUnder:0.00} .. +{worstAbove:0.00} m from it");
            Debug.Log($"WORLDTEST streaming: near {world.NearTiles} tiles, far {world.FarTiles} tiles, {world.Stages} main-thread stages, avg {world.AvgStageMs:0.0} ms, worst {world.WorstStageMs:0.0} ms");
            Debug.Log($"WORLDTEST stage parts: {world.StageReport}");
            foreach (var sl in world.SlowStages) Debug.Log("WORLDTEST slow stage: " + sl);
            Debug.Log($"WORLDTEST frames while riding + streaming ({Screen.width}x{Screen.height}): {ride.Report()}");
            AllocProbe.on = false;
            Debug.Log($"WORLDTEST memory: {ride.AllocRate()}; Unity total GC alloc {(gcFrames > 0 ? gcBytes / (double)gcFrames / 1024.0 : double.NaN):0.0} KB/frame");
            Debug.Log($"WORLDTEST allocations by part (main thread): {AllocProbe.Report(frames)}");
            gcRec.Dispose();
            Debug.Log($"WORLDTEST spikes (frames over {FrameStats.SPIKE_MS} ms after the first second): {ride.spikes.Count}; terrains now {Object.FindObjectsByType<Terrain>(FindObjectsSortMode.None).Length}");
            foreach (var sp in ride.spikes.Take(40)) Debug.Log("WORLDTEST spike " + sp);

            // what each HDRP feature costs: the bike stopped, streaming settled, each feature off in turn on the main camera
            inp.set("throttle", 0.0);
            inp.set("brake", 1.0);
            for (int i = 0; i < 120; i++) yield return null;
            var cam = Camera.main;
            var hd = cam != null ? cam.GetComponent<HDAdditionalCameraData>() : null;
            if (hd != null)
            {
                var base0 = new FrameStats();
                for (int i = 0; i < 20; i++) yield return null;
                for (int i = 0; i < 150; i++) { yield return null; base0.Add(); }
                Debug.Log($"WORLDTEST cost baseline (all on, standing): {base0.Report()}");
                double baseCpu = base0.Median(base0.cpu), baseGpu = base0.Median(base0.gpu), baseFrame = base0.Median(base0.frame);
                foreach (var (name, apply, undo) in Toggles(hd, cam))
                {
                    apply();
                    var fs = new FrameStats();
                    for (int i = 0; i < 20; i++) yield return null;   // history, exposure, shadow maps settle
                    for (int i = 0; i < 120; i++) { yield return null; fs.Add(); }
                    undo();
                    Debug.Log($"WORLDTEST cost {name,-16} saves frame {baseFrame - fs.Median(fs.frame):+0.00;-0.00} ms, gpu {Saved(baseGpu, fs.Median(fs.gpu))}, cpu {Saved(baseCpu, fs.Median(fs.cpu))} (off: {fs.Report()})");
                }
                Debug.Log("WORLDTEST cost: frame/gpu/cpu = median ms; gpu n/a = this graphics API gave no GPU timing");
            }
            Debug.Log($"WORLDTEST shots in {Path.GetFullPath(Shots)}");
            Assert.IsNull(bad, bad);
            Assert.Greater(dist, 30.0, "the bike rode off down the trail");
            Assert.GreaterOrEqual(world.NearTiles, 9, "near tiles round the rider");
            Assert.Greater(world.FarTiles, 0, "far tiles to the horizon");
            Assert.Less(world.WorstStageMs, 33.0, "no streaming stage over two frames");
        }

        static string Saved(double a, double b) => double.IsNaN(a) || double.IsNaN(b) ? "n/a" : $"{a - b:+0.00;-0.00} ms";

        /// each switch: (name, turn it off, put it back). Frame settings on the camera's own custom frame settings.
        static IEnumerable<(string, System.Action, System.Action)> Toggles(HDAdditionalCameraData hd, Camera cam)
        {
            (string, System.Action, System.Action) Fs(string n, FrameSettingsField f)
            {
                bool had = hd.customRenderingSettings, masked = hd.renderingPathCustomFrameSettingsOverrideMask.mask[(uint)f];
                bool was = hd.renderingPathCustomFrameSettings.IsEnabled(f);
                return (n, () =>
                {
                    hd.customRenderingSettings = true;
                    hd.renderingPathCustomFrameSettingsOverrideMask.mask[(uint)f] = true;
                    hd.renderingPathCustomFrameSettings.SetEnabled(f, false);
                }, () =>
                {
                    hd.renderingPathCustomFrameSettings.SetEnabled(f, was);
                    hd.renderingPathCustomFrameSettingsOverrideMask.mask[(uint)f] = masked;
                    hd.customRenderingSettings = had;
                });
            }
            yield return Fs("SSGI", FrameSettingsField.SSGI);
            yield return Fs("SSR", FrameSettingsField.SSR);
            yield return Fs("SSAO", FrameSettingsField.SSAO);
            yield return Fs("volumetric fog", FrameSettingsField.Volumetrics);
            yield return Fs("contact shadows", FrameSettingsField.ContactShadows);
            yield return Fs("sun shadows", FrameSettingsField.ShadowMaps);
            yield return Fs("motion blur", FrameSettingsField.MotionBlur);
            yield return Fs("bloom", FrameSettingsField.Bloom);
            yield return Fs("post (all)", FrameSettingsField.Postprocess);
            var aa = hd.antialiasing;
            yield return ("TAA", () => hd.antialiasing = HDAdditionalCameraData.AntialiasingMode.None, () => hd.antialiasing = aa);
            var terrains = new List<Terrain>();
            yield return ("terrain", () =>
            {
                terrains.Clear();
                foreach (var tr in Object.FindObjectsByType<Terrain>(FindObjectsSortMode.None)) if (tr.drawHeightmap) { tr.drawHeightmap = false; terrains.Add(tr); }
            }, () => { foreach (var tr in terrains) if (tr != null) tr.drawHeightmap = true; });
            float far = cam.farClipPlane;
            yield return ("far clip 600 m", () => cam.farClipPlane = 600f, () => cam.farClipPlane = far);
        }

        /// frame time, CPU main thread, GPU per frame (FrameTimingManager: needs Player > Frame Timing Stats)
        sealed class FrameStats
        {
            public const double SPIKE_MS = 16.7;
            public readonly List<double> frame = new List<double>(), cpu = new List<double>(), gpu = new List<double>();
            public readonly List<string> spikes = new List<string>();
            public WorldStreamer world;
            public int shotFrame = -100;   // the test's own screenshot (6 renders + PNG encode) lands in the next frame
            long _mem0 = -1; float _memT0;
            public string AllocRate()
            {
                long m = System.GC.GetTotalMemory(false);
                return $"managed heap {m / 1048576.0:0} MB, ~{System.Math.Max(0, m - _mem0) / 1048576.0 / System.Math.Max(0.1, Time.unscaledTime - _memT0):0.0} MB/s net growth since the first frame";
            }   // set: spikes are logged with the streaming stages round them
            readonly FrameTiming[] _ft = new FrameTiming[1];
            readonly int[] _gc = { System.GC.CollectionCount(0), System.GC.CollectionCount(1), System.GC.CollectionCount(2) };
            float _t0 = -1f;

            public void Add()
            {
                double ms = Time.unscaledDeltaTime * 1000.0;
                frame.Add(ms);
                double c = double.NaN, g = double.NaN, rt = double.NaN;
                FrameTimingManager.CaptureFrameTimings();
                if (FrameTimingManager.GetLatestTimings(1, _ft) > 0)
                {
                    if (_ft[0].gpuFrameTime > 0) gpu.Add(g = _ft[0].gpuFrameTime);
                    if (_ft[0].cpuMainThreadFrameTime > 0) cpu.Add(c = _ft[0].cpuMainThreadFrameTime - _ft[0].cpuMainThreadPresentWaitTime);
                    rt = _ft[0].cpuRenderThreadFrameTime;
                }
                int g0 = System.GC.CollectionCount(0) - _gc[0], g1 = System.GC.CollectionCount(1) - _gc[1], g2 = System.GC.CollectionCount(2) - _gc[2];
                _gc[0] += g0; _gc[1] += g1; _gc[2] += g2;
                if (_t0 < 0f) { _t0 = Time.unscaledTime; _mem0 = System.GC.GetTotalMemory(false); _memT0 = Time.unscaledTime; }
                if (world != null && ms > SPIKE_MS && Time.unscaledTime - _t0 > 1f)
                {
                    int f = Time.frameCount;
                    string shift = f - WorldOrigin.LastShiftFrame <= 4 ? " ORIGIN SHIFT" : "";
                    if (f - shotFrame <= 1) shift += " TEST SCREENSHOT";
                    spikes.Add($"frame {f} t {Time.unscaledTime - _t0:0.00} s: {ms:0.0} ms | latest timing cpu {Ms(c)} render thread {Ms(rt)} gpu {Ms(g)}" +
                               $" | gc +{g0}/{g1}/{g2}{shift} | stages f-4..f: {world.StagesIn(f - 4, f)}");
                }
            }

            public double Median(List<double> l) => l.Count == 0 ? double.NaN : l.OrderBy(v => v).ElementAt(l.Count / 2);
            static double Pct(List<double> l, double p) => l.Count == 0 ? double.NaN : l.OrderBy(v => v).ElementAt(System.Math.Min(l.Count - 1, (int)(l.Count * p)));
            static string Ms(double v) => double.IsNaN(v) ? "n/a" : v.ToString("0.0");

            public string Report() =>
                $"{frame.Count} frames, {1000.0 / Median(frame):0} fps median, frame median {Ms(Median(frame))} / 99% {Ms(Pct(frame, 0.99))} / worst {Ms(frame.Count > 0 ? frame.Max() : double.NaN)} ms, " +
                $"cpu main median {Ms(Median(cpu))} / 99% {Ms(Pct(cpu, 0.99))} ms, gpu median {Ms(Median(gpu))} / 99% {Ms(Pct(gpu, 0.99))} ms";
        }

        /// a shot from behind the drawn bike (the chase view), or from high above looking out over the land
        static void Shot(BikeDraw drawn, string file, bool high)
        {
            var camGo = new GameObject("TestCam");
            var cam = camGo.AddComponent<Camera>();
            var main = Camera.main;
            var hd = camGo.AddComponent<UnityEngine.Rendering.HighDefinition.HDAdditionalCameraData>();
            Vector3 c = drawn.FollowPos + Vector3.up * 0.9f;
            Vector3 fwd = drawn.FollowFwd; fwd.y = 0f; fwd.Normalize();
            if (high) { cam.transform.position = c - fwd * 60f + Vector3.up * 45f; cam.transform.LookAt(c + fwd * 250f); cam.fieldOfView = 60f; }
            else { cam.transform.position = c - fwd * 4.2f + Vector3.up * 1.3f; cam.transform.LookAt(c + fwd * 3f); cam.fieldOfView = 55f; }
            cam.farClipPlane = 5000f;
            var rt = new RenderTexture(1600, 900, 24);
            cam.targetTexture = rt;
            // HDRP needs a few frames of history (exposure, TAA) for a clean picture: render a handful, keep the last
            for (int i = 0; i < 6; i++) cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(1600, 900, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, 1600, 900), 0, 0);
            tex.Apply();
            RenderTexture.active = null;
            Directory.CreateDirectory(Shots);
            File.WriteAllBytes(Path.Combine(Shots, file), tex.EncodeToPNG());
            cam.targetTexture = null;
            Object.Destroy(rt);
            Object.Destroy(tex);
            Object.Destroy(camGo);
        }
    }
}
