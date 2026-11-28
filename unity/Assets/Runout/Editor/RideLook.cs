using System.IO;
using Runout.Game;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.HighDefinition;

namespace Runout.EditorTools
{
    /// The ride's HDRP look, built from scratch (menu Runout > Build HDRP Look; runs once by itself if the bike
    /// materials don't exist yet). Three parts:
    ///  1. Bike materials (Assets/Runout/Art/Materials/Bike/*.mat, HDRP/Lit): car paint = coloured metallic base under a
    ///     clear coat with a metal-flake mask (each ~0.2 mm flake its own metalness + gloss: sparkles under a mirror-smooth
    ///     lacquer, like a real paint job); polished chrome, black anodised alloy, raw / brushed alloy, gold anodised,
    ///     chain steel, rubber and plastic from the CC0 scans already in the project. Scans are mapped triplanar in the
    ///     part's own space (glb UVs aren't made for them; object space = they don't swim as the bike moves).
    ///     Assets/Resources/BikeMaterials.asset maps the glb's part names to them (BikeMaterialSet, used by BikeView).
    ///  2. The ride volume (RideVolume.asset): neutral tonemapping, SSR, SSAO, contact + micro shadows, 4 shadow cascades
    ///     to 200 m, a touch of bloom / vignette, motion blur, neutral colour.
    ///  3. Cameras: TAA (metal edges and flakes shimmer without it), HDRP asset: SSR / AO / volumetrics / decals on.
    /// Re-run the menu to rebuild (it overwrites the materials it made; tune them in the Inspector afterwards and
    /// don't re-run, or change the numbers here).
    [InitializeOnLoad]
    static class RideLook
    {
        const string Dir = "Assets/Runout/Art/Materials/Bike";
        const string TexDir = Dir + "/Tex";
        const string SetPath = "Assets/Resources/BikeMaterials.asset";
        const string Volume = "Assets/Runout/Settings/RideVolume.asset";
        const string Scans = "Assets/Runout/Art/Textures";

        static RideLook() => EditorApplication.delayCall += () =>
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;
            if (AssetDatabase.LoadAssetAtPath<BikeMaterialSet>(SetPath) == null) Build();
        };

        [MenuItem("Runout/Build HDRP Look")]
        static void Build()
        {
            Directory.CreateDirectory(TexDir);
            Directory.CreateDirectory("Assets/Resources");
            BuildMaterials();
            BuildVolume();
            FixCameras();
            AssetDatabase.SaveAssets();
            Debug.Log("Runout: HDRP look built (bike materials in " + Dir + ", ride volume, TAA). Save the open scene(s) to keep the sun + camera fixes.");
        }

        // ---------------------------------------------------------------- materials

        struct Spec
        {
            public string part, file;
            public Color color;
            public float metal0, metal1, smooth0, smooth1, coat, normal, tiles;
            public Texture2D colorMap, normalMap, maskMap;
        }

        static void BuildMaterials()
        {
            var flakes = FlakeMask(TexDir + "/paint_flakes_mask.png", 512, 5);
            var brushed = Mask(TexDir + "/brushed_mask.png", Scans + "/brushed_metal/metal_rough.jpg", 1024);
            var rubberM = Mask(TexDir + "/rubber_mask.png", Scans + "/rubber/rubber_rough.jpg", 1024, 0f);
            var plasticM = Mask(TexDir + "/plastic_mask.png", Scans + "/plastic/p012a_rough.jpg", 1024, 0f);
            var brushedN = NormalMap(Scans + "/brushed_metal/metal_normal.jpg");
            var rubberN = NormalMap(Scans + "/rubber/rubber_normal.jpg");
            var plasticN = NormalMap(Scans + "/plastic/p012a_normal.jpg");
            var rubberC = ColorMap(Scans + "/rubber/rubber_color.jpg");

            Spec[] specs =
            {
                // frame / swingarm: red pigment (lit by the sun like any paint) with metal flakes in it as sparkle (each
                // flake's metalness 0..0.65: most read as pigment, a few glint), all under a mirror-smooth clear coat.
                // Fully metallic paint only reflects the sky and reads near black outside of a studio.
                new Spec { part = "paint", file = "BikePaint", color = new Color(0.6f, 0.035f, 0.035f),
                           metal0 = 0f, metal1 = 0.65f, smooth0 = 0.5f, smooth1 = 0.85f, coat = 1f, tiles = 45f, maskMap = flakes },
                // stanchions, bolts, polished bits: near-mirror chrome, a faint polish grain.
                new Spec { part = "chrome", file = "BikeChrome", color = new Color(0.93f, 0.93f, 0.92f),
                           metal0 = 1f, metal1 = 1f, smooth0 = 0.9f, smooth1 = 0.97f, normal = 0.08f, tiles = 6f,
                           maskMap = brushed, normalMap = brushedN },
                // bars, cranks, hubs, rims: black anodised alloy (anodising keeps the brushed grain, a little sheen).
                new Spec { part = "black", file = "BikeBlackAnodised", color = new Color(0.05f, 0.05f, 0.055f),
                           metal0 = 1f, metal1 = 1f, smooth0 = 0.55f, smooth1 = 0.78f, coat = 0.25f, normal = 0.35f, tiles = 6f,
                           maskMap = brushed, normalMap = brushedN },
                // chain: oily steel, darker in the scan's rough spots.
                new Spec { part = "chain", file = "BikeChainSteel", color = new Color(0.46f, 0.45f, 0.43f),
                           metal0 = 1f, metal1 = 1f, smooth0 = 0.4f, smooth1 = 0.72f, normal = 0.5f, tiles = 14f,
                           maskMap = brushed, normalMap = brushedN },
                // gold anodised / Kashima bits: gold metal, polished.
                new Spec { part = "gold", file = "BikeGoldAnodised", color = new Color(1f, 0.74f, 0.33f),
                           metal0 = 1f, metal1 = 1f, smooth0 = 0.78f, smooth1 = 0.9f, normal = 0.15f, tiles = 6f,
                           maskMap = brushed, normalMap = brushedN },
                // tyres, grips: dark rubber scan.
                new Spec { part = "rubber", file = "BikeRubber", color = new Color(0.32f, 0.32f, 0.32f),
                           metal0 = 0f, metal1 = 0f, smooth0 = 0.08f, smooth1 = 0.3f, normal = 0.8f, tiles = 10f,
                           colorMap = rubberC, maskMap = rubberM, normalMap = rubberN },
                // levers' bodies, saddle, guards: textured black plastic.
                new Spec { part = "plastic", file = "BikePlastic", color = new Color(0.045f, 0.045f, 0.048f),
                           metal0 = 0f, metal1 = 0f, smooth0 = 0.35f, smooth1 = 0.6f, normal = 0.5f, tiles = 12f,
                           maskMap = plasticM, normalMap = plasticN },
            };

            var set = AssetDatabase.LoadAssetAtPath<BikeMaterialSet>(SetPath);
            if (set == null) { set = ScriptableObject.CreateInstance<BikeMaterialSet>(); AssetDatabase.CreateAsset(set, SetPath); }
            set.entries.Clear();
            var lit = Shader.Find("HDRP/Lit");
            foreach (var s in specs)
            {
                string path = Dir + "/" + s.file + ".mat";
                var m = AssetDatabase.LoadAssetAtPath<Material>(path);
                if (m == null) { m = new Material(lit); AssetDatabase.CreateAsset(m, path); }
                m.shader = lit;
                m.SetFloat("_MaterialID", 1f);                       // Standard (+ clear coat by mask)
                m.SetColor("_BaseColor", s.color);
                m.SetTexture("_BaseColorMap", s.colorMap);
                m.SetFloat("_Metallic", s.metal1);
                m.SetFloat("_Smoothness", s.smooth1);
                m.SetTexture("_MaskMap", s.maskMap);
                m.SetFloat("_MetallicRemapMin", s.metal0); m.SetFloat("_MetallicRemapMax", s.metal1);
                m.SetFloat("_SmoothnessRemapMin", s.smooth0); m.SetFloat("_SmoothnessRemapMax", s.smooth1);
                m.SetFloat("_AORemapMin", 1f); m.SetFloat("_AORemapMax", 1f);
                m.SetTexture("_NormalMap", s.normalMap);
                m.SetFloat("_NormalScale", s.normal);
                m.SetFloat("_CoatMask", s.coat);
                m.SetFloat("_UVBase", 5f);                           // triplanar
                m.SetFloat("_ObjectSpaceUVMapping", 1f);             // in the part's own space
                m.SetTextureScale("_BaseColorMap", new Vector2(s.tiles, s.tiles));   // tiles per metre
                m.SetFloat("_SpecularOcclusionMode", 1f);
                m.enableInstancing = true;
                HDMaterial.ValidateMaterial(m);
                EditorUtility.SetDirty(m);
                set.entries.Add(new BikeMaterialSet.Entry { part = s.part, material = m });
            }
            EditorUtility.SetDirty(set);
        }

        /// Metal flakes: a grid of cells, each a flake (offset a little so the grid doesn't show) with its own
        /// metalness (R) and gloss (A). Linear, mipmapped: far away the flakes average out into the base's sheen.
        static Texture2D FlakeMask(string path, int size, int cell)
        {
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
            var rng = new System.Random(1337);
            int n = size / cell;
            var metal = new float[n * n]; var gloss = new float[n * n];
            for (int i = 0; i < n * n; i++)
            {
                float k = (float)rng.NextDouble();
                metal[i] = k * k;                                   // most flakes dull, a few bright
                gloss[i] = 0.3f + 0.7f * (float)rng.NextDouble();
            }
            var px = new Color[size * size];
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    int cx = (x / cell) % n, cy = (y / cell) % n;
                    float fx = (x % cell + 0.5f) / cell - 0.5f, fy = (y % cell + 0.5f) / cell - 0.5f;
                    bool edge = fx * fx + fy * fy > 0.2f;            // round flakes, base paint between them
                    int c = cy * n + cx;
                    float m = edge ? 0.15f : metal[c], g = edge ? 0.6f : gloss[c];
                    px[y * size + x] = new Color(m, 1f, 0f, g);
                }
            tex.SetPixels(px);
            return SaveLinear(tex, path);
        }

        /// Packs a roughness scan into an HDRP mask map: R metal (given), G AO 1, B 0, A smoothness = 1 - roughness,
        /// stretched to the scan's own range so the material's remap min / max set the real gloss.
        static Texture2D Mask(string path, string roughJpg, int size, float metal = 1f)
        {
            var src = new Texture2D(2, 2);
            src.LoadImage(File.ReadAllBytes(roughJpg));
            var px = new Color[size * size];
            float lo = 1f, hi = 0f;
            for (int i = 0; i < px.Length; i++)
            {
                float r = src.GetPixelBilinear((i % size + 0.5f) / size, (i / size + 0.5f) / size).r;
                px[i].a = r; lo = Mathf.Min(lo, r); hi = Mathf.Max(hi, r);
            }
            float span = Mathf.Max(1e-3f, hi - lo);
            for (int i = 0; i < px.Length; i++) px[i] = new Color(metal, 1f, 0f, 1f - (px[i].a - lo) / span);
            Object.DestroyImmediate(src);
            var tex = new Texture2D(size, size, TextureFormat.RGBA32, false, true);
            tex.SetPixels(px);
            return SaveLinear(tex, path);
        }

        static Texture2D SaveLinear(Texture2D tex, string path)
        {
            File.WriteAllBytes(path, tex.EncodeToPNG());
            Object.DestroyImmediate(tex);
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceSynchronousImport);
            var imp = (TextureImporter)AssetImporter.GetAtPath(path);
            imp.sRGBTexture = false;
            imp.mipmapEnabled = true;
            imp.anisoLevel = 16;
            imp.wrapMode = TextureWrapMode.Repeat;
            imp.textureCompression = TextureImporterCompression.CompressedHQ;   // BC7
            imp.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        static Texture2D NormalMap(string path)
        {
            var imp = AssetImporter.GetAtPath(path) as TextureImporter;
            if (imp == null) return null;
            if (imp.textureType != TextureImporterType.NormalMap || imp.anisoLevel < 8)
            {
                imp.textureType = TextureImporterType.NormalMap;
                imp.mipmapEnabled = true;
                imp.anisoLevel = 16;
                imp.textureCompression = TextureImporterCompression.CompressedHQ;
                imp.SaveAndReimport();
            }
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        static Texture2D ColorMap(string path)
        {
            var imp = AssetImporter.GetAtPath(path) as TextureImporter;
            if (imp == null) return null;
            if (imp.anisoLevel < 8) { imp.anisoLevel = 16; imp.mipmapEnabled = true; imp.SaveAndReimport(); }
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        // ---------------------------------------------------------------- volume

        /// A component of the profile, made if missing and saved INTO the profile asset (VolumeProfile.Add alone keeps it
        /// in memory only: it was gone after the next reload, which is how the ride volume lost its sky).
        static T Get<T>(VolumeProfile p) where T : VolumeComponent
        {
            if (!p.TryGet(out T c)) c = p.Add<T>(true);
            c.active = true;
            Persist(p);
            return c;
        }

        /// Drops empty slots and writes every in-memory component into the profile's asset file.
        public static void Persist(VolumeProfile p)
        {
            string path = AssetDatabase.GetAssetPath(p);
            if (string.IsNullOrEmpty(path)) return;
            p.components.RemoveAll(c => c == null);
            foreach (var c in p.components)
                if (!AssetDatabase.Contains(c))
                {
                    c.name = c.GetType().Name;
                    c.hideFlags = HideFlags.HideInInspector | HideFlags.HideInHierarchy;
                    AssetDatabase.AddObjectToAsset(c, path);
                }
            EditorUtility.SetDirty(p);
        }

        [MenuItem("Runout/Rebuild Ride Lighting (sky, sun, camera, post)")]
        static void VolumeMenu()
        {
            BuildVolume();
            FixCameras();
            AssetDatabase.SaveAssets();
            Debug.Log("Runout: ride volume, sun and camera rebuilt. Save the open scene(s) to keep the sun + camera fixes.");
        }

        static void BuildVolume()
        {
            var p = AssetDatabase.LoadAssetAtPath<VolumeProfile>(Volume);
            if (p == null) { Debug.LogWarning("Runout: no " + Volume + " (run Runout > Bootstrap Project first)"); return; }

            // sky: physically based (the sun light drives it), its light used for ambient + reflections
            var env = Get<VisualEnvironment>(p);
            env.skyType.Override((int)SkyType.PhysicallyBased);
            env.skyAmbientMode.Override(SkyAmbientMode.Dynamic);
            // the sky's "planet ground" is what the ambient light sees below the horizon: lit by the sun like the real
            // ground, so a sand / dirt albedo here = the bounce off sunlit trail onto the shaded side of rider and bike
            // (at the default near-black grey 0.12 the shaded side went black)
            var sky = Get<PhysicallyBasedSky>(p);
            sky.groundTint.Override(new Color(0.42f, 0.32f, 0.24f));
            // real local bounce (ramps, berms, the trail beside the bike): screen-space GI
            var gi = Get<GlobalIllumination>(p);
            gi.enable.Override(true);
            gi.quality.Override((int)ScalableSettingLevelParameter.Level.Medium);
            var fog = Get<Fog>(p);
            fog.enabled.Override(true);
            fog.enableVolumetricFog.Override(true);
            fog.meanFreePath.Override(450f);
            fog.maximumHeight.Override(250f);
            // exposure for a 100 000 lux sun (RideLighting.SUN_LUX): auto, but capped at EV 14 (one stop under "sunny 16"):
            // at EV 15 the physically based sky reads navy next to sunlit ground; photos of a sunny trail sit ~EV 14.
            // Center-weighted, the bright sand doesn't push the exposure down by itself.
            var exp = Get<Exposure>(p);
            exp.mode.Override(ExposureMode.AutomaticHistogram);
            exp.meteringMode.Override(MeteringMode.CenterWeighted);
            exp.limitMin.Override(10f);
            exp.limitMax.Override(14f);
            exp.compensation.Override(0f);
            exp.histogramPercentages.Override(new Vector2(40f, 90f));

            // Neutral tonemapping: keeps hues and saturation as lit (ACES pushes oranges / reds and adds contrast)
            Get<Tonemapping>(p).mode.Override(TonemappingMode.Neutral);

            var ssr = Get<ScreenSpaceReflection>(p);
            ssr.enabled.Override(true);
            ssr.quality.Override((int)ScalableSettingLevelParameter.Level.High);

            var ao = Get<ScreenSpaceAmbientOcclusion>(p);
            ao.intensity.Override(0.8f);
            ao.quality.Override((int)ScalableSettingLevelParameter.Level.High);

            var cs = Get<ContactShadows>(p);
            cs.enable.Override(true);
            cs.length.Override(0.15f);
            Get<MicroShadowing>(p).enable.Override(true);

            var sh = Get<HDShadowSettings>(p);
            sh.maxShadowDistance.Override(200f);
            sh.cascadeShadowSplitCount.Override(4);

            var bloom = Get<Bloom>(p);
            bloom.intensity.Override(0.08f);
            bloom.scatter.Override(0.6f);

            Get<Vignette>(p).intensity.Override(0.1f);
            Get<ChromaticAberration>(p).intensity.Override(0f);
            Get<MotionBlur>(p).intensity.Override(0.35f);
            Get<WhiteBalance>(p).temperature.Override(0f);   // neutral: the sun's own colour decides
            var ca = Get<ColorAdjustments>(p);
            ca.contrast.Override(0f);
            ca.saturation.Override(0f);

            EditorUtility.SetDirty(p);

            var asset = GraphicsSettings.defaultRenderPipeline as HDRenderPipelineAsset;
            if (asset != null)
            {
                var s = asset.currentPlatformRenderPipelineSettings;
                s.supportSSR = true; s.supportSSAO = true; s.supportVolumetrics = true; s.supportDecals = true;
                s.supportMotionVectors = true;
                s.supportSSGI = true;
                s.supportTerrainHole = true;   // the far land rings punch holes where the detailed tiles are
                // sun shadows: 4096 maps, the soft PCSS-style filter (contact-hardening: sharp at the tyre, soft far away)
                s.hdShadowInitParams.maxDirectionalShadowMapResolution = 4096;
                s.hdShadowInitParams.directionalShadowFilteringQuality = HDShadowFilteringQuality.High;
                // the sky cubemap every metal / clear coat reflects: 256 px read as mush on chrome
                s.lightLoopSettings.skyReflectionSize = SkyResolution.SkyResolution1024;
                asset.currentPlatformRenderPipelineSettings = s;
                EditorUtility.SetDirty(asset);
            }
        }

        static void FixCameras()
        {
            for (int i = 0; i < EditorSceneManager.sceneCount; i++)
            {
                var scene = EditorSceneManager.GetSceneAt(i);
                if (!scene.isLoaded) continue;
                bool changed = false;
                foreach (var root in scene.GetRootGameObjects())
                {
                    foreach (var cam in root.GetComponentsInChildren<Camera>(true))
                    {
                        var hd = cam.GetComponent<HDAdditionalCameraData>() ?? cam.gameObject.AddComponent<HDAdditionalCameraData>();
                        Undo.RecordObject(hd, "Ride camera look");
                        hd.antialiasing = HDAdditionalCameraData.AntialiasingMode.TemporalAntialiasing;
                        hd.TAAQuality = HDAdditionalCameraData.TAAQualityLevel.High;
                        // make sure the camera itself renders every effect the volume turns on
                        hd.customRenderingSettings = true;
                        foreach (var f in new[] { FrameSettingsField.SSGI, FrameSettingsField.SSR, FrameSettingsField.SSAO,
                                                  FrameSettingsField.ContactShadows, FrameSettingsField.Volumetrics,
                                                  FrameSettingsField.ShadowMaps, FrameSettingsField.MotionBlur })
                        {
                            hd.renderingPathCustomFrameSettingsOverrideMask.mask[(uint)f] = true;
                            hd.renderingPathCustomFrameSettings.SetEnabled(f, true);
                        }
                        EditorUtility.SetDirty(hd);
                        changed = true;
                    }
                    foreach (var l in root.GetComponentsInChildren<Light>(true))
                    {
                        if (l.type != LightType.Directional) continue;
                        var hl = l.GetComponent<HDAdditionalLightData>();
                        Undo.RecordObject(l, "Sun");
                        l.intensity = RideLighting.SUN_LUX;
                        l.useColorTemperature = true;
                        l.colorTemperature = 6000f;   // midday sun, near neutral
                        l.shadows = LightShadows.Soft;
                        if (hl != null)
                        {
                            Undo.RecordObject(hl, "Sun");
                            hl.SetShadowResolutionOverride(false);     // was forced to 512
                            hl.SetShadowResolutionLevel(3);            // the asset's top level (4096)
                            hl.useContactShadow.useOverride = true;    // contact shadows need the light's OK too
                            hl.useContactShadow.@override = true;
                            hl.angularDiameter = 0.53f;
                            EditorUtility.SetDirty(hl);
                        }
                        EditorUtility.SetDirty(l);
                        changed = true;
                    }
                    foreach (var bv in root.GetComponentsInChildren<BikeView>(true)) BikeMaterialSet.Dress(bv.transform);
                    changed = true;
                }
                if (changed) EditorSceneManager.MarkSceneDirty(scene);
            }
        }
    }
}
