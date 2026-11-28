using System.Collections.Generic;
using Runout.Config;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// Builds a ride in a scene: BikeSim (godot/sim, the ride physics shared with Godot, untouched) on this scene's
    /// ground, plugged into the SimHost. The DH's numbers until bikes / the garage are ported: geometry = dh.glb's
    /// extras (as godot/tools/slope_stress.gd uses them), the stock cassette, the stock suspension setup.
    [RequireComponent(typeof(SimHost))]
    public sealed class RideBootstrap : MonoBehaviour
    {
        public Terrain ground;
        public Vector3 spawn = new Vector3(0f, 0f, 0f);
        [Tooltip("degrees: 0 = along +x (the sim's heading)")] public float heading = 0f;

        public BikeSim Sim { get; private set; }
        public Tune Tune { get; private set; }

        void Start()
        {
            var host = new RideHost(new TerrainGround(ground != null ? ground : Terrain.activeTerrain));
            Tune = new Tune();
            Sim = new BikeSim(host);
            host.sim = Sim;
            Sim.T = Tune.fill(new RideParams());
            Tune.changed += () => Tune.fill(Sim.T);

            var extras = new GdDict();
            extras["wheelbase"] = 1.2557; extras["wheelRadius"] = 0.374; extras["wheelRadiusRear"] = 0.355; extras["bbToRearAxle"] = 0.4423;
            var mods = new GdDict();
            mods.set("cogs", new List<double> { 11, 12, 14, 16, 18, 21, 24 });
            mods["ring_k"] = 1.0; mods["land"] = 1.0;
            mods.set("susp", SuspSetup.resolve(null, SuspSetup.DEFAULT_SHOCK, "air", null).to_sim());
            var cfg = new GdDict();
            cfg["land"] = 1.0; cfg.set("geared", true); cfg.set("mods", mods);
            Sim.setup(extras, cfg);
            Sim.reset_at(spawn.x, -spawn.z, heading * Mathf.Deg2Rad);
            GetComponent<SimHost>().Attach(new BikeSimStep(Sim, host));
        }
    }
}
