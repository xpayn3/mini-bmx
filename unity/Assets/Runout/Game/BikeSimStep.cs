using Runout.Config;
using Runout.Sim;

namespace Runout.Game
{
    /// BikeSim (godot/sim: the one ride physics, shared with Godot) as a fixed-step simulation for the SimHost.
    public sealed class BikeSimStep : ISimStep
    {
        public readonly BikeSim sim;
        readonly RideHost _host;
        public BikeSimStep(BikeSim s, RideHost h) { sim = s; _host = h; }

        public void Step(double dt, RideInput input)
        {
            _host.tick();
            sim.step(dt, input);
        }

        public void Capture(ref SimPose p)
        {
            p.X = (float)sim.x; p.Y = (float)sim.y_draw; p.Z = (float)sim.z;
            p.Heading = (float)sim.heading; p.Pitch = (float)sim.pitch_draw; p.BikeLean = (float)sim.bike_lean; p.Steer = (float)sim.steer;
            p.Speed = (float)sim.v; p.Vy = (float)sim.vy; p.Air = sim.air;
        }
    }
}
