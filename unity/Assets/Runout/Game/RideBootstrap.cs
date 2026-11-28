using System.Collections.Generic;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// Builds a ride in a scene: the ported bike physics (Runout.Sim.BikePhysics) on this scene's ground, plugged into the
    /// SimHost. The DH's numbers until bikes / the garage are ported: geometry = dh.glb's extras (as godot/tools/slope_stress.gd
    /// uses them), the stock cassette, the stock coil / air setup.
    [RequireComponent(typeof(SimHost))]
    public sealed class RideBootstrap : MonoBehaviour
    {
        public Terrain ground;
        public Vector3 spawn = new Vector3(0f, 0f, 0f);
        [Tooltip("degrees: 0 = along +x (the sim's heading)")] public float heading = 0f;

        public BikePhysics Physics { get; private set; }
        public Tune Tune { get; private set; }

        void Start()
        {
            var host = new RideHost(new TerrainGround(ground != null ? ground : Terrain.activeTerrain));
            Tune = new Tune();
            Physics = new BikePhysics(host, Tune);
            host.phys = Physics;
            Physics.setup(new BikeConfig
            {
                wheelbase = 1.2557, wheelRadius = 0.374, wheelRadiusRear = 0.355, bbToRearAxle = 0.4423,
                geared = true, cogs = new List<double> { 11, 12, 14, 16, 18, 21, 24 },
                susp = SuspSetup.resolve(null, SuspSetup.DEFAULT_SHOCK, "air", null),
            });
            Physics.reset_at(spawn.x, -spawn.z, heading * Mathf.Deg2Rad);
            GetComponent<SimHost>().Attach(Physics);
        }
    }
}
