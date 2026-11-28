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
            var bike = host.bikeView.transform;
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
    }
}
