using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// The plug: owns one ISimStep (the bike + rider sim from Runout.Sim), steps it at a fixed 120 Hz on its
    /// own accumulator (not Unity's FixedUpdate / PhysX: the ride feel is our code) and hands the interpolated
    /// pose to the views every frame.
    [DefaultExecutionOrder(-100)]
    public sealed class SimHost : MonoBehaviour
    {
        public InputReader input;
        public BikeView bikeView;

        FixedStepper _stepper;
        public ISimStep Sim { get; private set; }
        public SimPose Pose { get; private set; }
        /// tests / replays / the demo rider: when set, used instead of the player's controls
        public RideInput? overrideInput;

        /// Called by whoever builds the ride (the sim objects are plain C#, made from code, not components).
        public void Attach(ISimStep sim)
        {
            Sim = sim;
            _stepper = new FixedStepper(sim);
            Pose = _stepper.Drawn;
        }

        void Update()
        {
            if (_stepper == null) return;
            RideInput inp = overrideInput ?? (input != null ? input.Read() : RideInput.None);
            _stepper.Advance(Time.unscaledDeltaTime * Time.timeScale, inp);
            Pose = _stepper.Drawn;
            if (bikeView != null) bikeView.Apply(Pose);
        }
    }
}
