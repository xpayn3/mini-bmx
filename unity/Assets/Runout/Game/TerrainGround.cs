using System.Collections.Generic;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// IGround over a Unity Terrain (or flat ground when none), for test scenes. The real world will be the ported
    /// procedural field (TerrainFieldCs, pure C#) implementing IGround directly, so the physics never asks Unity for
    /// heights. Sim z = -Unity z (see BikeView).
    public sealed class TerrainGround : IGround
    {
        readonly Terrain _t;
        static readonly List<GdDict> NONE = new List<GdDict>();
        public TerrainGround(Terrain t) { _t = t; }

        public double height(double x, double z) =>
            _t != null ? _t.SampleHeight(new Vector3((float)x, 0f, (float)-z)) + _t.transform.position.y : 0.0;
        public double deck_height(double x, double z) => height(x, z);
        public double top_height(double x, double z) => height(x, z);
        public long surface(double x, double z) => 1;   // trail
        public double jump_mask(double x, double z) => 0.0;
        public List<GdDict> colliders_near(double x, double z) => NONE;

        public RayHit cast(V3 origin, V3 dir, double max_dist)
        {
            var o = new Vector3((float)origin.x, (float)origin.y, (float)-origin.z);
            var d = new Vector3((float)dir.x, (float)dir.y, (float)-dir.z);
            if (UnityEngine.Physics.Raycast(o, d, out var h, (float)max_dist))
                return new RayHit { hit = true, point = new V3(h.point.x, h.point.y, -h.point.z), normal = new V3(h.normal.x, h.normal.y, -h.normal.z), surface = 1, distance = h.distance };
            return new RayHit { hit = false };
        }
    }
}
