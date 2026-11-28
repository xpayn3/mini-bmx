using System.Collections.Generic;
using Runout.Levels;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// A feature put down anywhere in the playground scene: pick a kind, set its numbers, move / turn it (its red arrow,
    /// local +x, is the way it's ridden; its position is where the feature starts). Built by exactly the code that lays
    /// out the reference lanes (Runout.Levels.PlacedFeature), so a placed 1.5 m table is the lanes' 1.5 m table.
    /// Press Play to ride it; "Ride from here" (Inspector) starts in front of it.
    [ExecuteAlways]
    public sealed class PlaygroundFeature : MonoBehaviour
    {
        public enum Kind { Table, Gap, Hop, Drop, StepUp, StepDown, DropToLanding, Rollers, Pump, Curb, Pothole, Washboard, Rough, Slope, Camber, RockRow, RockGarden, Designed, Bowl }

        public Kind kind = Kind.Table;
        [Tooltip("the numbers of this kind (labels in the Inspector)")] public float[] args = new float[0];
        [Tooltip("riding half width (m): the flat top of the feature")] public float halfWidth = 3f;

        [System.NonSerialized] public PlacedFeature placed;

        /// per kind: the labels and defaults of its numbers, in the order the lane method takes them
        public static readonly Dictionary<Kind, (string label, float def)[]> ARGS = new Dictionary<Kind, (string, float)[]>
        {
            [Kind.Table] = new[] { ("Height (m)", 1.5f), ("Lip angle (deg)", 32f), ("Deck (m)", 4f), ("Landing angle (deg)", 30f) },
            [Kind.Gap] = new[] { ("Kicker height (m)", 1.6f), ("Lip angle (deg)", 35f), ("Gap (m)", 7f), ("Landing height (m)", 1.7f), ("Landing angle (deg)", 35f) },
            [Kind.Hop] = new[] { ("Height (m)", 0.6f), ("Lip angle (deg)", 30f) },
            [Kind.Drop] = new[] { ("Height (m)", 1.5f) },
            [Kind.StepUp] = new[] { ("Kicker height (m)", 1.2f), ("Lip angle (deg)", 35f), ("Gap (m)", 4f), ("Deck height (m)", 1.6f) },
            [Kind.StepDown] = new[] { ("Deck height (m)", 1.2f), ("Lip height (m)", 0.6f), ("Lip angle (deg)", 28f), ("Gap (m)", 4f), ("Landing height (m)", 0.8f), ("Landing angle (deg)", 30f) },
            [Kind.DropToLanding] = new[] { ("Height (m)", 1.5f), ("Landing angle (deg)", 30f) },
            [Kind.Rollers] = new[] { ("Amplitude (m)", 0.6f), ("Wavelength (m)", 6f), ("Count", 5f) },
            [Kind.Pump] = new[] { ("Amplitude (m)", 0.8f), ("Wavelength (m)", 5f), ("Count", 8f) },
            [Kind.Curb] = new[] { ("Height (m)", 0.2f), ("Length (m)", 3f) },
            [Kind.Pothole] = new[] { ("Depth (m)", 0.15f), ("Length (m)", 1f) },
            [Kind.Washboard] = new[] { ("Amplitude (m)", 0.05f), ("Wavelength (m)", 0.5f), ("Length (m)", 30f) },
            [Kind.Rough] = new[] { ("Amplitude (m)", 0.15f), ("Length (m)", 40f), ("Seed", 11f) },
            [Kind.Slope] = new[] { ("Angle (deg)", 15f), ("Length up (m)", 18f) },
            [Kind.Camber] = new[] { ("Angle (deg)", 15f), ("Length (m)", 24f) },
            [Kind.RockRow] = new[] { ("Rock scale", 0.3f), ("Height factor", 0.7f), ("Count", 4f), ("Spacing (m)", 4f) },
            [Kind.RockGarden] = new[] { ("Length (m)", 40f), ("Seed", 7f), ("Clean line (1 = yes)", 1f) },
            [Kind.Designed] = new[] { ("Design speed (m/s)", 12f), ("Lip angle (deg)", 26f), ("Gap (1 = gap, 0 = table)", 0f) },
            [Kind.Bowl] = new[] { ("Radius (m)", 13f), ("Banked width (m)", 5f), ("Bank angle (deg)", 45f) },
        };

        /// the kind's lane-method name in Runout.Levels (PlacedFeature.kind)
        public static string KindName(Kind k)
        {
            switch (k)
            {
                case Kind.StepUp: return "step_up";
                case Kind.StepDown: return "step_down";
                case Kind.DropToLanding: return "drop_land";
                case Kind.Rough: return "chatter";
                case Kind.RockRow: return "rock_row";
                case Kind.RockGarden: return "rock_garden";
                default: return k.ToString().ToLowerInvariant();
            }
        }

        /// args sized to the kind, missing ones at their defaults
        public void FitArgs()
        {
            var spec = ARGS[kind];
            if (args != null && args.Length == spec.Length) return;
            var a = new float[spec.Length];
            for (int i = 0; i < a.Length; i++) a[i] = args != null && i < args.Length ? args[i] : spec[i].def;
            args = a;
        }

        public void ResetArgs()
        {
            var spec = ARGS[kind];
            args = new float[spec.Length];
            for (int i = 0; i < args.Length; i++) args[i] = spec[i].def;
        }

        /// this object as the course's placed feature, in sim coordinates (Godot convention: z = -Unity z, yaw 0 = +x,
        /// the ridden direction (cos yaw, -sin yaw))
        public PlacedFeature ToPlaced()
        {
            FitArgs();
            Vector3 p = transform.position, r = transform.right;
            double yaw = System.Math.Atan2(r.z, r.x);
            var d = new double[args.Length];
            for (int i = 0; i < d.Length; i++) d[i] = args[i];
            return PlacedFeature.make(KindName(kind), d, p.x, -p.z, yaw, halfWidth, name);
        }

        void OnValidate()
        {
            FitArgs();
            Notify();
        }

        void OnEnable() => Notify();
        void OnDisable() => Notify();

        void Update()
        {
            if (transform.hasChanged) { transform.hasChanged = false; Notify(); }
        }

        void Notify()
        {
            var w = FindFirstObjectByType<PlaygroundWorld>();
            if (w != null) w.MarkPlacedDirty();
        }

#if UNITY_EDITOR
        void OnDrawGizmos()
        {
            Vector3 p = transform.position, f = transform.right;
            Gizmos.color = new Color(1f, 0.35f, 0.1f);
            Gizmos.DrawLine(p, p + f * 6f);
            Gizmos.DrawLine(p + f * 6f, p + f * 5f + transform.forward * 0.6f);
            Gizmos.DrawLine(p + f * 6f, p + f * 5f - transform.forward * 0.6f);
            Gizmos.DrawSphere(p, 0.25f);
            UnityEditor.Handles.Label(p + Vector3.up * 2.5f, name + "\n" + (placed != null ? placed.feat.desc : kind.ToString()));
        }
#endif
    }
}
