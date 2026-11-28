using System.Collections.Generic;
using static Runout.Sim.Gd;

namespace Runout.World
{
    /// The setup side of the field (terrain_field.gd's GDScript-only part, ported): what the layout of the trail and
    /// the route reads from the field while it is being built.
    public sealed partial class TerrainField
    {
        /// RouteStyle (jumps / twist / rolling / grade / biome sliders): 1.0 = the original layout
        public Dictionary<string, double> style = new Dictionary<string, double>();
        public double style_v(string k) => style != null && style.TryGetValue(k, out var v) ? v : 1.0;

        // spine_near's answer
        public double sp_s, sp_d, sp_ad, sp_dir;

        /// the exact nearest point of the spine (within RouteSpine.R) -> sp_s, sp_d (signed: + = the +z side heading +x),
        /// sp_ad, sp_dir (terrain_field.gd spine_near)
        public void spine_near(double x, double z)
        {
            sp_ad = RouteSpine.R; sp_d = RouteSpine.R; sp_s = 0.0; sp_dir = 0.0;
            long cx = floori(x / RouteSpine.CELL) - s_gx0;
            long cz = floori(z / RouteSpine.CELL) - s_gz0;
            if (cx < 0 || cz < 0 || cx >= s_gnx || cz >= s_gnz)
                return;
            long ci = cz * s_gnx + cx;
            double best = RouteSpine.R * RouteSpine.R;
            for (int k = s_start[ci]; k < s_start[ci + 1]; k++)
            {
                int i = s_items[k];
                double ax = sX[i], az = sZ[i];
                double vx = sX[i + 1] - ax, vz = sZ[i + 1] - az;
                double l2 = vx * vx + vz * vz;
                double t = ((x - ax) * vx + (z - az) * vz) / l2;
                t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
                double ex = x - (ax + vx * t), ez = z - (az + vz * t);
                double d2 = ex * ex + ez * ez;
                if (d2 < best)
                {
                    best = d2;
                    double l = sqrt(l2);
                    sp_ad = sqrt(d2);
                    sp_d = ex * (-vz / l) + ez * (vx / l);
                    sp_s = sS[i] + t * (sS[i + 1] - sS[i]);
                    sp_dir = atan2(vz, vx);
                }
            }
        }
    }
}
