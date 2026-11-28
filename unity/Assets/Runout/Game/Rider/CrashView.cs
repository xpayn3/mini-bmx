using System;
using System.Collections.Generic;
using Runout.Rider;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// The crash, hybrid: OUR crashed-bike body (Runout.Rider.CrashBike, port of Godot's CrashBikeCs) and ragdoll step in
    /// the physics' crash steps; Unity gives them the drawn bike's parts at the crash and draws the result. Godot's
    /// game.gd _crash_bike_begin / BikePhysicsCs GameHost.crash_body_step. Getting up (Mecanim clips) comes later: for
    /// now holding hop puts the rider straight back on the bike.
    public sealed class CrashView
    {
        readonly BikeSim st;
        readonly BikeRig rig;
        readonly IGround ground;
        public CrashBike bike;
        CrashBikeStart.Built _built;
        readonly List<(double x, double z, double r, double top)> _near = new List<(double, double, double, double)>();

        public CrashView(BikeSim s, BikeRig r, IGround g) { st = s; rig = r; ground = g; }

        double Top(double x, double z) => ground.top_height(x, z);

        /// right after BikeSim.begin_crash (it is the host's start_crash): the crashed bike from the drawn bike now
        public void Begin(bool bail)
        {
            bike = null;
            if (rig == null || rig.model == null) return;
            var d = new CrashBikeStartInput { bail = bail };
            // the hull: every part's support points (measured off the meshes, glb_extras.py) where that part is now
            foreach (string key in rig.extras.keys("rig.hull."))
            {
                bool steer = key.StartsWith("rig.hull.steer.");
                string node = key.Substring(steer ? "rig.hull.steer.".Length : "rig.hull.frame.".Length);
                Transform t = BikeRig.Find(rig.model, node);
                if (t == null) continue;
                Xf w = GodotSpace.WorldXf(t);
                double[] a = rig.extras.list(key);
                var into = steer ? d.steerHull : d.frameHull;
                for (int i = 0; i + 2 < a.Length; i += 3) into.Add(w.b * new Vec3(a[i], a[i + 1], a[i + 2]) + w.o);
            }
            d.model = GodotSpace.WorldXf(rig.model);
            Quaternion mr = rig.ModelRot;
            d.leanFrame = new Xf(new Basis(GodotSpace.V(mr * Vector3.right), GodotSpace.V(mr * Vector3.up), GodotSpace.V(mr * Vector3.forward)), GodotSpace.V(rig.position));
            if (rig.wheel_f != null) d.wheelF = GodotSpace.WorldXf(rig.wheel_f);
            if (rig.wheel_r != null) d.wheelR = GodotSpace.WorldXf(rig.wheel_r);
            d.wheelRF = rig.wheel_rf; d.wheelRR = rig.wheel_rr; d.tyreHW = rig.tyre_hw;
            if (rig.steer_n != null)
            {
                d.steerPivot = GodotSpace.V(GodotSpace.WorldPos(rig.steer_n));
                Xf par = GodotSpace.WorldXf(rig.steer_n.parent);
                d.steerAxis = (par.b * GodotSpace.V(rig.steer_axis)).normalized();
                d.gripL = GodotSpace.V(BikeRig.GPoint(rig.steer_n, rig.grip_l));
                d.gripR = GodotSpace.V(BikeRig.GPoint(rig.steer_n, rig.grip_r));
            }
            d.steerAngle = st.steer;
            if (rig.crank_n != null)
            {
                d.crank = GodotSpace.V(GodotSpace.WorldPos(rig.crank_n));
                d.pedals = new[] { GodotSpace.V(BikeRig.GPoint(rig.crank_n, rig.pedal_l)), GodotSpace.V(BikeRig.GPoint(rig.crank_n, rig.pedal_r)) };
            }
            _built = CrashBikeStart.Build(st, d, Top);
            bike = _built?.bike;
        }

        /// one physics step of the crash (IRideHost.crash_body_step): the bike, then the ragdoll (RiderView)
        public void Step(double dt, RideInput inp)
        {
            if (bike != null && ReferenceEquals(st.crash_sim, bike))
                CrashBikeHost.Step(st, bike, dt, Top, _near);
        }

        public void End() { bike = null; _built = null; }

        /// draw the crashed bike between physics steps (a = the stepper's interpolation)
        public bool Draw(double a)
        {
            if (bike == null || !ReferenceEquals(st.crash_sim, bike) || rig.model == null) return false;
            GodotSpace.SetModelWorld(rig.model, CrashBike.Mul(bike.BodyAt(a), bike.K));
            rig.set_steer((float)bike.ThetaAt(a));
            return true;
        }
    }
}
