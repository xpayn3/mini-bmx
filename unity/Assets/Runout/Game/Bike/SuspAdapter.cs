using Runout.Sim;

namespace Runout.Game
{
    /// The drawn suspension as the ride physics sees it (godot/sim ISusp; Godot: host.susp = the Suspension object): the
    /// physics caps its travel at what the drawn fork / rear end can move (F / R min..max), reads the fork's axis and sets
    /// the sag. Riding the wheels follow the ground (BikeRig.fit_wheels), so land / update do nothing, as in Godot.
    public sealed class SuspAdapter : ISusp
    {
        readonly Suspension s;
        readonly GdDict _F = new GdDict(), _R = new GdDict();
        public SuspAdapter(Suspension susp) { s = susp; }

        public bool has_f => s.has_f;
        public bool has_r => s.has_r;
        public bool wheels_follow => s.wheels_follow;
        public V3 axis => new V3(s.axis.x, s.axis.y, s.axis.z);
        public GdDict F { get { _F["min"] = s.F_min; _F["max"] = s.F_max; return _F; } }
        public GdDict R { get { _R["min"] = s.R_min; _R["max"] = s.R_max; return _R; } }
        public bool has_method(string name) => name == "set_sag" || name == "land" || name == "update";
        public void set_sag(double f, double r) => s.set_sag((float)f, (float)r);
        public void land(double impact, bool front_air, bool rear_air) { }
        public void update(double dt, GdDict state) { }
    }
}
