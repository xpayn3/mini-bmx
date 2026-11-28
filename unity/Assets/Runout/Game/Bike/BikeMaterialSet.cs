using System;
using System.Collections.Generic;
using UnityEngine;

namespace Runout.Game
{
    /// The bike's HDRP materials, made from scratch by Runout > Build HDRP Look (Editor/RideLook.cs) into
    /// Assets/Runout/Art/Materials/Bike. The glbs only say WHICH part is what (their material names: paint, chrome,
    /// black, rubber, chain, plastic, gold); every renderer under a bike gets our material for that name instead of
    /// the one glTFast made. Edit the .mat files in the Inspector to tune the look; nothing is read from the glb.
    [CreateAssetMenu(menuName = "Runout/Bike Material Set")]
    public sealed class BikeMaterialSet : ScriptableObject
    {
        [Serializable]
        public struct Entry
        {
            [Tooltip("the glb material name this replaces (paint, chrome, black, rubber, chain, plastic, gold)")]
            public string part;
            public Material material;
        }

        public List<Entry> entries = new List<Entry>();

        static BikeMaterialSet _main;
        /// Assets/Resources/BikeMaterials.asset (null until the look has been built).
        public static BikeMaterialSet Main => _main != null ? _main : (_main = Resources.Load<BikeMaterialSet>("BikeMaterials"));

        public Material Find(string glbName)
        {
            if (string.IsNullOrEmpty(glbName)) return null;
            string n = glbName.Replace(" (Instance)", "").Trim().ToLowerInvariant();
            foreach (var e in entries)
                if (e.material != null && !string.IsNullOrEmpty(e.part) && n.StartsWith(e.part.ToLowerInvariant()))
                    return e.material;
            return null;
        }

        /// Swaps every renderer's materials under root for ours. Idempotent (our own materials are left as they are).
        public static void Dress(Transform root)
        {
            var set = Main;
            if (set == null || root == null) return;
            foreach (var r in root.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] == null) continue;
                    var m = set.Find(mats[i].name);
                    if (m != null && m != mats[i]) { mats[i] = m; changed = true; }
                }
                if (changed) r.sharedMaterials = mats;
            }
        }
    }
}
