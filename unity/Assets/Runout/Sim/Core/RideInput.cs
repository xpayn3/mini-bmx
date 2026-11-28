namespace Runout.Sim
{
    /// One physics step's controls, already filtered (deadzones, stick curves): the Godot input dictionary
    /// (Game._read_input) as a struct, same key names so the port reads `inp.throttle` like GDScript.
    /// The Unity side fills it from the Input System; tests / replays fill it directly.
    public struct RideInput
    {
        public double throttle;     // pedal 0..1
        public double brake;        // both levers with feel 0..1
        public double brake_front;  // bare front lever 0..1
        public double brake_rear;   // bare rear lever 0..1
        public double steer;        // -1 right .. +1 left (Godot convention)
        public bool hop;
        public bool sprint;
        public double body_fwd;     // right stick y: + forward over the bars
        public double body_lean;    // right stick x: + left
        public double left_back;    // raw left stick pulled back (manual gate)
        public bool pad;            // last device was a gamepad
        public bool ws_air;         // classic keys: W / S tilt in the air

        public static RideInput None => default;
    }
}
