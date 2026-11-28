using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// The game side of the bike physics (Godot: Game, as BikePhysics' host): the world it rides on, the messages it
    /// shows, crashes and getting up. Grows as the HUD / fx / ragdoll are ported.
    public sealed class RideHost : IBikeHost
    {
        public BikePhysics phys;
        readonly IGround _ground;
        public RideHost(IGround ground) { _ground = ground; }

        public IGround terrain => _ground;
        public ISuspensionLimits susp => null;   // the drawn suspension (port step 3: BikeRig)

        public void flash(string text) => Debug.Log("RIDE " + text);
        public bool msg_idle() => true;
        public void flow_up() => phys.flow_up();
        public void start_crash(string reason)
        {
            Debug.Log("CRASH " + reason);
            phys.begin_crash();
        }
        /// until the ragdoll is ported: getting up = back on the bike where it lies
        public void begin_getup() => phys.get_up();
    }
}
