using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace Runout.EditorTools
{
    /// Daylight in physical units, as HDRP wants it: the sun ~100 000 lux (a plain Unity light added from code is 1 lux:
    /// the scenes were near black) and the auto exposure in a sunny day's range (EV 10 .. 14). Runs by itself after
    /// every compile on the open scene(s) and the ride volume (idempotent; only fixes what is still at the dark defaults),
    /// or from the menu Runout > Fix Ride Lighting.
    [InitializeOnLoad]
    static class RideLighting
    {
        public const float SUN_LUX = 100000f;
        const string Volume = "Assets/Runout/Settings/RideVolume.asset";

        static RideLighting() => EditorApplication.delayCall += () => Apply(false);

        [MenuItem("Runout/Fix Ride Lighting")]
        static void Menu() => Apply(true);

        static void Apply(bool force)
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;
            var profile = AssetDatabase.LoadAssetAtPath<VolumeProfile>(Volume);
            if (profile != null)
            {
                bool fresh = !profile.TryGet(out Exposure exp);
                if (fresh) exp = profile.Add<Exposure>(false);
                if (force || fresh || !exp.active || !exp.limitMin.overrideState)
                {
                    exp.active = true;
                    exp.mode.Override(ExposureMode.AutomaticHistogram);
                    exp.meteringMode.Override(MeteringMode.CenterWeighted);
                    exp.limitMin.Override(10f);   // same as RideLook: EV 10..14 (at 15 the physical sky reads navy)
                    exp.limitMax.Override(14f);
                    exp.compensation.Override(0f);
                    RideLook.Persist(profile);    // save it INTO the asset (Add alone is lost on reload)
                    EditorUtility.SetDirty(profile);
                    AssetDatabase.SaveAssets();
                }
            }
            for (int i = 0; i < EditorSceneManager.sceneCount; i++)
            {
                var scene = EditorSceneManager.GetSceneAt(i);
                if (!scene.isLoaded) continue;
                bool changed = false;
                foreach (var root in scene.GetRootGameObjects())
                    foreach (var l in root.GetComponentsInChildren<Light>(true))
                        if (l.type == LightType.Directional && (force || l.intensity < 1000f))
                        {
                            Undo.RecordObject(l, "Ride lighting");
                            l.intensity = SUN_LUX;
                            l.useColorTemperature = true;
                            l.colorTemperature = 5600f;
                            changed = true;
                        }
                if (changed)
                {
                    EditorSceneManager.MarkSceneDirty(scene);
                    Debug.Log($"Runout: daylight set in {scene.name} (sun {SUN_LUX:0} lux, exposure EV 9..15). Save the scene to keep it.");
                }
            }
        }
    }
}
