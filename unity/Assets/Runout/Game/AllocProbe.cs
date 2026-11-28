using System.Collections.Generic;
using System.Text;

namespace Runout.Game
{
    /// Dev probe: managed bytes each part of a frame allocates (garbage = the collector's pauses). Off unless a test turns
    /// it on; then `long t = AllocProbe.Mark(); ...; AllocProbe.Add("part", t);` round a part. Main thread only.
    public static class AllocProbe
    {
        public static bool on;
        static readonly Dictionary<string, (long bytes, long calls)> _parts = new Dictionary<string, (long, long)>();

        public static long Mark() => on ? UnityEngine.Profiling.Profiler.GetMonoUsedSizeLong() : 0L;

        public static void Add(string part, long t0)
        {
            if (!on) return;
            long d = UnityEngine.Profiling.Profiler.GetMonoUsedSizeLong() - t0;
            if (d < 0) return;   // a collection ran inside the part: this sample says nothing
            _parts.TryGetValue(part, out var p);
            _parts[part] = (p.bytes + d, p.calls + 1);
        }

        public static void Reset() => _parts.Clear();

        /// each part: bytes per frame over `frames`, biggest first
        public static string Report(int frames)
        {
            var l = new List<KeyValuePair<string, (long bytes, long calls)>>(_parts);
            l.Sort((a, b) => b.Value.bytes.CompareTo(a.Value.bytes));
            var sb = new StringBuilder();
            foreach (var kv in l) sb.Append($"{kv.Key} {kv.Value.bytes / (double)System.Math.Max(1, frames) / 1024.0:0.00} KB/frame; ");
            return sb.ToString();
        }
    }
}
