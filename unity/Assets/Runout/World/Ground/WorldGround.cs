using System;
using System.Collections.Generic;
using Runout.Sim;

namespace Runout.World
{
    /// The ride physics' ground (IGround) over the procedural world, engine-free: Godot's Terrain query side
    /// (terrain.gd height / deck_height / surface / jump_mask) on the C# TerrainField. Sim coordinates (Godot's:
    /// y up, the Unity side maps z -> -z). One instance per thread (the field has per-instance caches).
    /// Not yet: rope bridge decks, ruts, the scatter's colliders (trees / rocks / fences: step 7), the drawn micro
    /// detail in top_height.
    public sealed class WorldGround : IGround
    {
        public readonly TerrainField field;
        static readonly List<GdDict> NONE = new List<GdDict>();

        /// the drawn surface where the host draws one (Unity: the terrain tile there), NaN = none: then the field
        public Func<double, double, double> drawn;

        public WorldGround(TerrainField f) { field = f; }

        public double height(double x, double z) => field.height(x, z);
        public double deck_height(double x, double z) => field.deck(x, z);
        /// what is drawn (tyres, feet, ragdoll and the ride's ground knock touch this): the host's surface, else the field
        public double top_height(double x, double z)
        {
            if (drawn != null)
            {
                double d = drawn(x, z);
                if (!double.IsNaN(d)) return d;
            }
            return field.height(x, z);
        }
        public long surface(double x, double z) => field.surface_at(x, z, field.height(x, z));
        public double jump_mask(double x, double z) => field.jump_mask(x, z);
        public List<GdDict> colliders_near(double x, double z) => NONE;
        public RayHit cast(V3 origin, V3 dir, double max_dist) => new RayHit { hit = false };

        /// where a ride starts: `along` metres down the trail, on its centreline, facing down it.
        /// Returns (x, z, heading) in sim coordinates (heading 0 = +x, forward = (cos h, 0, -sin h)).
        public static (double x, double z, double heading) TrailStart(FieldTables t, double along = 24.0)
        {
            int i = 0;
            double s = 0.0;
            while (i + 1 < t.cX.Length && s < along)
            {
                s += Math.Sqrt((t.cX[i + 1] - t.cX[i]) * (t.cX[i + 1] - t.cX[i]) + (t.cZ[i + 1] - t.cZ[i]) * (t.cZ[i + 1] - t.cZ[i]));
                i++;
            }
            return (t.cX[i], t.cZ[i], Math.Atan2(-t.cTZ[i], t.cTX[i]));
        }
    }
}
