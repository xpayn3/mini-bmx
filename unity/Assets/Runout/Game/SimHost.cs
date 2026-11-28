using Runout.Config;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// The plug: owns one ISimStep (the ride from godot/sim), steps it at a fixed 120 Hz on its own accumulator (not
    /// Unity's FixedUpdate / PhysX: the ride feel is our code) and hands the interpolated pose to the views every frame.
    [DefaultExecutionOrder(-100)]
    public sealed class SimHost : MonoBehaviour
    {
        public InputReader input;
        public BikeView bikeView;
        /// the full drawing (BikeRig + suspension + Godot's draw pipeline); when set it draws instead of bikeView
        [System.NonSerialized] public BikeDraw drawer;

        FixedStepper _stepper;
        public FixedStepper Stepper => _stepper;
        public ISimStep Sim { get; private set; }
        public SimPose Pose { get; private set; }
        /// tests / replays / the demo rider: when set, used instead of the player's controls
        public RideInput overrideInput;
        readonly RideInput _none = new RideInput();

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
            long a = AllocProbe.Mark();
            RideInput inp = overrideInput ?? (input != null ? input.Read() : _none);
            AllocProbe.Add("input", a); a = AllocProbe.Mark();
            _stepper.Advance(Time.unscaledDeltaTime * Time.timeScale, inp);
            AllocProbe.Add("physics steps", a); a = AllocProbe.Mark();
            Pose = _stepper.Drawn;
            if (drawer != null) drawer.Draw(_stepper.Alpha, Time.deltaTime);
            else if (bikeView != null) bikeView.Apply(Pose);
            AllocProbe.Add("bike + rider drawing", a);
        }
    }
}
