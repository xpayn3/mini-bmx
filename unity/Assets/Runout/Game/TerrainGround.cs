using System.Collections.Generic;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// IGround over a Unity Terrain (or flat ground when none), for test scenes. The real world will be the ported
    /// procedural field (TerrainFieldCs -> Runout.Sim, pure C#) implementing IGround directly, so the physics never asks
    /// Unity for heights. Sim z = -Unity z (see BikeView).
    public sealed class TerrainGround : IGround
    {
        readonly Terrain _t;
        public TerrainGround(Terrain t) { _t = t; }

        public double height(double x, double z) =>
            _t != null ? _t.SampleHeight(new Vector3((float)x, 0f, (float)-z)) + _t.transform.position.y : 0.0;
        public double deck_height(double x, double z) => height(x, z);
        public double top_height(double x, double z) => height(x, z);
        public int surface(double x, double z) => Surf.Trail;
        public double jump_mask(double x, double z) => 0.0;
        public void colliders_near(double x, double z, List<Obstacle> into) { }
    }
}
