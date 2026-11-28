using System.IO;
using Runout.Game;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace Runout.EditorTools
{
    /// Sets the project up from code (re-runnable, changes only what differs):
    ///   menu Runout > Bootstrap Project, or headless:
    ///   Unity.exe -batchmode -projectPath unity -executeMethod Runout.EditorTools.ProjectBootstrap.Run -quit -logFile -
    public static class ProjectBootstrap
    {
        const string Settings = "Assets/Runout/Settings";
        const string ScenePath = "Assets/Runout/Scenes/Ride.unity";
        const string HdriPath = "Assets/Runout/Art/HDRI/kloofendal_43d_clear_puresky_4k.hdr";

        [MenuItem("Runout/Bootstrap Project")]
        public static void Run()
        {
            Directory.CreateDirectory(Settings);
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.companyName = "Runout";
            PlayerSettings.productName = "Runout";
            SetPlayerSetting("activeInputHandler", 1);   // Input System only
            Time.fixedDeltaTime = 1f / 120f;             // PhysX (debris, crashed props) at the ride's rate; the ride itself is Runout.Sim

            SetupHdrp();
            ImportHdri();
            BuildRideScene();
            BuildPlaygroundScene();
            AssetDatabase.SaveAssets();
            Debug.Log("BOOTSTRAP done");
        }

        static void SetPlayerSetting(string prop, int value)
        {
            var ps = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
            if (ps.Length == 0) return;
            var so = new SerializedObject(ps[0]);
            var p = so.FindProperty(prop);
            if (p != null && p.intValue != value) { p.intValue = value; so.ApplyModifiedProperties(); }
        }

        static void SetupHdrp()
        {
            string path = Settings + "/HDRP.asset";
            var asset = AssetDatabase.LoadAssetAtPath<HDRenderPipelineAsset>(path);
            if (asset == null)
            {
                asset = ScriptableObject.CreateInstance<HDRenderPipelineAsset>();
                AssetDatabase.CreateAsset(asset, path);
            }
            // Features the Godot look uses: volumetric fog (haze, sun shafts), SSR, contact shadows, decals.
            var s = asset.currentPlatformRenderPipelineSettings;
            s.supportVolumetrics = true;
            s.supportSSR = true;
            s.supportSSAO = true;
            s.supportDecals = true;
            s.supportMotionVectors = true;
            s.hdShadowInitParams.maxShadowRequests = 128;
            asset.currentPlatformRenderPipelineSettings = s;
            EditorUtility.SetDirty(asset);

            GraphicsSettings.defaultRenderPipeline = asset;
            int cur = QualitySettings.GetQualityLevel();
            for (int i = 0; i < QualitySettings.names.Length; i++)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = asset;
            }
            QualitySettings.SetQualityLevel(cur, false);
        }

        static void ImportHdri()
        {
            var imp = AssetImporter.GetAtPath(HdriPath) as TextureImporter;
            if (imp == null || imp.textureShape == TextureImporterShape.TextureCube) return;
            imp.textureShape = TextureImporterShape.TextureCube;
            imp.SaveAndReimport();
        }

        static void BuildRideScene()
        {
            if (File.Exists(ScenePath)) { WireRideScene(); AddToBuild(); return; }
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // Sun: golden hour like the Godot default (19:20, ~10 deg up).
            var sunGo = new GameObject("Sun");
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sunGo.AddComponent<HDAdditionalLightData>();
            sunGo.transform.rotation = Quaternion.Euler(10f, 230f, 0f);
            sun.shadows = LightShadows.Soft;
            sun.intensity = RideLighting.SUN_LUX;   // (HDRP: lux; a light from code is 1 = night)

            // Sky + fog + exposure in one global volume (physically based, like the Godot SunSky model).
            var volGo = new GameObject("Sky and Fog");
            var vol = volGo.AddComponent<Volume>();
            vol.isGlobal = true;
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();
            AssetDatabase.CreateAsset(profile, Settings + "/RideVolume.asset");
            var vs = profile.Add<VisualEnvironment>(true);
            vs.skyType.Override((int)SkyType.PhysicallyBased);
            profile.Add<PhysicallyBasedSky>(true);
            var fog = profile.Add<Fog>(true);
            fog.enabled.Override(true);
            fog.enableVolumetricFog.Override(true);
            fog.meanFreePath.Override(450f);
            var exp = profile.Add<Exposure>(true);
            exp.mode.Override(ExposureMode.AutomaticHistogram);
            vol.sharedProfile = profile;

            var camGo = new GameObject("Ride Camera");
            camGo.tag = "MainCamera";
            camGo.AddComponent<Camera>().fieldOfView = 50f;
            camGo.AddComponent<HDAdditionalCameraData>();
            camGo.transform.SetPositionAndRotation(new Vector3(-4.2f, 2.2f, 0f), Quaternion.Euler(17f, 90f, 0f));

            // Test ground until the procedural field is ported.
            var td = new TerrainData { heightmapResolution = 257, size = new Vector3(512f, 60f, 512f) };
            AssetDatabase.CreateAsset(td, Settings + "/TestTerrain.asset");
            var terr = Terrain.CreateTerrainGameObject(td);
            terr.name = "Test Terrain";
            terr.transform.position = new Vector3(-256f, 0f, -256f);

            var host = new GameObject("Ride");
            var sim = host.AddComponent<SimHost>();
            sim.input = host.AddComponent<InputReader>();
            var bike = new GameObject("Bike");
            sim.bikeView = bike.AddComponent<BikeView>();
            var dh = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Runout/Art/Models/Bikes/dh.glb");
            if (dh != null) ((GameObject)PrefabUtility.InstantiatePrefab(dh)).transform.SetParent(bike.transform, false);

            EditorSceneManager.SaveScene(scene, ScenePath);
            WireRideScene();
            AddToBuild();
        }

        /// the ride's components on an existing Ride scene (re-runnable: adds only what's missing)
        static void WireRideScene()
        {
            var scene = EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
            var ride = GameObject.Find("Ride");
            var bike = GameObject.Find("Bike");
            var cam = GameObject.Find("Ride Camera");
            if (ride == null || bike == null) { Debug.LogWarning("BOOTSTRAP Ride / Bike objects missing in " + ScenePath); return; }
            var host = Get<SimHost>(ride);
            if (host.input == null) host.input = Get<InputReader>(ride);
            if (host.bikeView == null) host.bikeView = Get<BikeView>(bike);
            var boot = Get<RideBootstrap>(ride);
            if (boot.ground == null) boot.ground = Object.FindFirstObjectByType<Terrain>();
            if (cam != null)
            {
                var chase = Get<ChaseCamera>(cam);
                chase.target = bike.transform;
            }
            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene);
        }

        const string PlaygroundPath = "Assets/Runout/Scenes/Playground.unity";

        /// the test playground (Godot: LEVELS > TEST PLAYGROUND): the reference lanes + berm bowls drawn by PlaygroundWorld,
        /// a "Placed Features" group to put your own features in (three examples beside the lanes), the ride rig
        [MenuItem("Runout/Build Playground Scene")]
        public static void BuildPlaygroundScene()
        {
            if (File.Exists(PlaygroundPath)) { AddToBuild(PlaygroundPath); return; }
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            // clear midday, like the Godot playground (readable reference shots)
            var sunGo = new GameObject("Sun");
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sunGo.AddComponent<HDAdditionalLightData>();
            sunGo.transform.rotation = Quaternion.Euler(55f, 200f, 0f);
            sun.shadows = LightShadows.Soft;
            sun.intensity = RideLighting.SUN_LUX;   // (HDRP: lux; a light from code is 1 = night)
            var volGo = new GameObject("Sky and Fog");
            var vol = volGo.AddComponent<Volume>();
            vol.isGlobal = true;
            vol.sharedProfile = AssetDatabase.LoadAssetAtPath<VolumeProfile>(Settings + "/RideVolume.asset");

            var world = new GameObject("Playground").AddComponent<PlaygroundWorld>();
            var placed = new GameObject("Placed Features");
            AddFeature(placed.transform, "Example table", PlaygroundFeature.Kind.Table, new Vector3(0f, 0f, 130f), 0f);
            AddFeature(placed.transform, "Example rollers", PlaygroundFeature.Kind.Rollers, new Vector3(50f, 0f, 130f), 0f);
            AddFeature(placed.transform, "Example gap (turned)", PlaygroundFeature.Kind.Gap, new Vector3(100f, 0f, 125f), -20f);

            var camGo = new GameObject("Ride Camera");
            camGo.tag = "MainCamera";
            camGo.AddComponent<Camera>().fieldOfView = 50f;
            camGo.AddComponent<HDAdditionalCameraData>();
            camGo.transform.SetPositionAndRotation(new Vector3(-36f, 3f, 0f), Quaternion.Euler(17f, 90f, 0f));

            var ride = new GameObject("Ride");
            var bike = new GameObject("Bike");
            var dh = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Runout/Art/Models/Bikes/dh.glb");
            if (dh != null) ((GameObject)PrefabUtility.InstantiatePrefab(dh)).transform.SetParent(bike.transform, false);
            var host = Get<SimHost>(ride);
            host.input = Get<InputReader>(ride);
            host.bikeView = Get<BikeView>(bike);
            Get<RideBootstrap>(ride);
            Get<ChaseCamera>(camGo).target = bike.transform;
            EditorSceneManager.SaveScene(scene, PlaygroundPath);
            AddToBuild(PlaygroundPath);
        }

        static void AddFeature(Transform parent, string name, PlaygroundFeature.Kind kind, Vector3 pos, float yawDeg)
        {
            var go = new GameObject(name);
            go.transform.SetParent(parent, false);
            go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, yawDeg, 0f));
            var f = go.AddComponent<PlaygroundFeature>();
            f.kind = kind;
            f.ResetArgs();
        }

        static T Get<T>(GameObject go) where T : Component => go.TryGetComponent<T>(out var c) ? c : go.AddComponent<T>();

        static void AddToBuild() => AddToBuild(ScenePath);

        static void AddToBuild(string path)
        {
            foreach (var s in EditorBuildSettings.scenes) if (s.path == path) return;
            var list = new System.Collections.Generic.List<EditorBuildSettingsScene>(EditorBuildSettings.scenes)
                { new EditorBuildSettingsScene(path, true) };
            EditorBuildSettings.scenes = list.ToArray();
        }
    }
}
