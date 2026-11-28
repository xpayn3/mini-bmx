using Runout.Game;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace Runout.EditorTools
{
    /// Runout > Build World Scene: Scenes/World.unity = the Ride scene (sun, sky volume, camera, bike, rider) on the
    /// procedural world (WorldStreamer: our field, streamed Unity Terrain tiles) instead of the test terrain.
    /// Re-runnable: it starts again from the Ride scene each time.
    static class WorldScene
    {
        const string Ride = "Assets/Runout/Scenes/Ride.unity";
        const string World = "Assets/Runout/Scenes/World.unity";

        [MenuItem("Runout/Build World Scene")]
        static void Build()
        {
            if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
            var scene = EditorSceneManager.OpenScene(Ride, OpenSceneMode.Single);
            foreach (var go in scene.GetRootGameObjects())
                if (go.GetComponent<Terrain>() != null) Object.DestroyImmediate(go);   // the test terrain
            var w = new GameObject("World");
            var ws = w.AddComponent<WorldStreamer>();
            w.AddComponent<WorldOrigin>();   // floating origin (the world runs many km)
            ws.terrainMaterial = AssetDatabase.LoadAssetAtPath<Material>("Assets/Runout/Art/Materials/Terrain/WorldTerrain.mat");
            EditorSceneManager.SaveScene(scene, World);
            EditorSceneManager.OpenScene(World, OpenSceneMode.Single);
            Debug.Log("Runout: " + World + " built (the procedural world, seed " + ws.seed + "). Press Play to ride it.");
        }
    }
}
