using System.Collections;
using System.IO;
using NUnit.Framework;
using Runout.Game;
using Runout.Sim;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace Runout.Tests
{
    /// The Ride scene in play mode: our physics (Runout.Sim) drives the bike through the Unity adapters.
    public class RideTests
    {
        [UnityTest]
        public IEnumerator PedallingMovesTheBike()
        {
            SceneManager.LoadScene("Ride");
            yield return null;
            yield return null;
            var host = Object.FindFirstObjectByType<SimHost>();
            Assert.NotNull(host, "SimHost in the Ride scene");
            var boot = host.GetComponent<RideBootstrap>();
            Assert.NotNull(boot.Sim, "RideBootstrap built the ride (godot/sim BikeSim)");
            var drawn = Object.FindFirstObjectByType<BikeDraw>();
            Assert.NotNull(drawn, "the full bike drawing (BikeRig + suspension) is built");
            var bike = drawn.rig.model;   // (the model is placed directly; the Bike object stays put)
            Vector3 start = bike.position;
            var inp = new RideInput(); inp.set("throttle", 1.0); host.overrideInput = inp;
            float t = 0f;
            while (t < 3f) { t += Time.deltaTime; yield return null; }
            double v = boot.Sim.v;
            float moved = Vector3.Distance(start, bike.position);
            Debug.Log($"RIDETEST v={v * 3.6:0.0} km/h moved={moved:0.00} m steps air={boot.Sim.air} crashed={boot.Sim.crash_on}");
            string shot = Path.Combine(Application.dataPath, "..", "Logs", "ride_test.png");
            ScreenCapture.CaptureScreenshot(shot);
            yield return null;
            yield return null;
            Assert.Greater(v, 2.0, "the bike got going");
            Assert.Greater(moved, 2.0f, "the drawn bike followed the physics");
            Assert.IsFalse(boot.Sim.crash_on, "no crash on flat ground");
        }
    

        [UnityTest]
        public IEnumerator PlaygroundRollIn()
        {
            SceneManager.LoadScene("Playground");
            yield return null;
            yield return null;
            var world = Object.FindFirstObjectByType<PlaygroundWorld>();
            Assert.NotNull(world, "PlaygroundWorld in the Playground scene");
            Assert.NotNull(world.Course, "the course is built");
            var host = Object.FindFirstObjectByType<SimHost>();
            var boot = host.GetComponent<RideBootstrap>();
            Assert.NotNull(boot.Sim, "the ride is built on the playground");
            double y0 = boot.Sim.y;
            var pedal = new RideInput(); pedal.set("throttle", 1.0);
            host.overrideInput = pedal;   // off the 10 m deck, then hands off down the roll-in
            double vmax = 0;
            float t = 0f;
            while (t < 5f)
            {
                t += Time.deltaTime;
                if (t > 1.5f) host.overrideInput = new RideInput();
                vmax = System.Math.Max(vmax, boot.Sim.v);
                yield return null;
            }
            var draw = Object.FindFirstObjectByType<BikeDraw>();
            Assert.NotNull(draw, "the full bike drawing (BikeRig + suspension) is built");
            Assert.NotNull(draw.rig.susp, "the DH has its suspension rig");
            Debug.Log($"PGTEST start_y={y0:0.00} m vmax={vmax * 3.6:0.0} km/h x={boot.Sim.x:0.0} crashed={boot.Sim.crash_on} placed={world.Course.placed.Count} " +
                $"fork={draw.rig.susp.xF:0.000} rear={draw.rig.susp.xR:0.000} shock_stroke={draw.rig.susp.last_stroke:0.000} cogs={boot.Sim.cogs.Count} land={boot.Sim.LAND:0.00}");
            Assert.Greater(y0, 3.5, "starts on the 4 m roll-in deck");
            Assert.Greater(vmax * 3.6, 20.0, "the roll-in gives ~30 km/h");
            Assert.AreEqual(3, world.Course.placed.Count, "the three example features are placed");
        }
    }
}
