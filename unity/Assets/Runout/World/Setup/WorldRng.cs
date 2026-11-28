namespace Runout.World
{
    /// mulberry32 exactly as godot/scripts/world/world_rng.gd (and the old JS): the same seed gives the same stream.
    /// A class (not TfRng's struct) because the setup hands one stream through many calls.
    public sealed class WorldRng
    {
        public uint a;

        public WorldRng(long seed = 0) { a = unchecked((uint)(seed & 0xFFFFFFFF)); }

        public double next()
        {
            unchecked
            {
                a += 0x6D2B79F5u;
                uint t = a;
                t = (t ^ (t >> 15)) * (1u | t);
                t = (t + (t ^ (t >> 7)) * (61u | t)) ^ t;
                return (t ^ (t >> 14)) / 4294967296.0;
            }
        }

        /// JS Math.round (half towards +inf)
        public static long jround(double x) => (long)System.Math.Floor(x + 0.5);
    }
}
