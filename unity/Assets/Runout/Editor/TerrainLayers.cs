using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.HighDefinition;

namespace Runout.EditorTools
{
    /// Runout > Build Terrain Layers: the world's ground layers from the user's Megascans surfaces (E:\Megascans, Fab
    /// licence: used in the game, never committed: Assets/Runout/Art/Megascans is gitignored, like Godot's plants_scan).
    /// Per surface: albedo + normal copied in, an HDRP mask map packed (R metal 0, G AO, B height from the scan's
    /// displacement, A smoothness = gloss), a TerrainLayer at the scan's real size. Then the HDRP Terrain Lit material
    /// the WorldStreamer draws with (height-based blend: stones stand out of the dirt instead of cross-fading).
    /// The layer ORDER is WorldStreamer's splat order (WorldSplat.LAYERS): change both together.
    static class TerrainLayers
    {
        const string SRC = @"E:\Megascans\Downloaded\surface";
        const string DST = "Assets/Runout/Art/Megascans";
        const string MAT = "Assets/Runout/Art/Materials/Terrain/WorldTerrain.mat";

        // (layer name, Megascans folder, file prefix, metres the scan covers)
        static readonly (string name, string folder, string prefix, float metres)[] LAYERS =
        {
            ("Grass", "Moss_Ground_se4rwei", "se4rwei_2K", 2f),
            ("Forest", "Ground_Forest_smspdebp", "smspdebp_2K", 2f),
            ("TrailPacked", "Soil_Hardened_tedkbizo", "tedkbizo_4K", 2f),
            ("Gravel", "Ground_Gravel_ubnmdjecw", "ubnmdjecw_2K", 2f),
            ("Rock", "Rock_Cliffs_ubulehofw", "ubulehofw_2K", 2f),
            ("Mud", "Soil_Mud_pjDtB20", "pjDtB2_4K", 2f),
        };

        [MenuItem("Runout/Build Terrain Layers")]
        static void Build()
        {
            if (!Directory.Exists(SRC)) { Debug.LogError("Runout: no Megascans surfaces at " + SRC); return; }
            Directory.CreateDirectory(DST);
            var made = new TerrainLayer[LAYERS.Length];
            for (int i = 0; i < LAYERS.Length; i++)
            {
                var L = LAYERS[i];
                EditorUtility.DisplayProgressBar("Terrain layers", L.name, (float)i / LAYERS.Length);
                string dir = DST + "/" + L.name;
                Directory.CreateDirectory(dir);
                string src = Path.Combine(SRC, L.folder, L.prefix);
                var albedo = Copy(src + "_Albedo.jpg", dir + "/albedo.jpg", false);
                var normal = Copy(src + "_Normal.jpg", dir + "/normal.jpg", true);
                var mask = PackMask(src, dir + "/mask.png");
                string lp = dir + "/" + L.name + ".terrainlayer";
                var layer = AssetDatabase.LoadAssetAtPath<TerrainLayer>(lp);
                if (layer == null) { layer = new TerrainLayer(); AssetDatabase.CreateAsset(layer, lp); }
                layer.diffuseTexture = albedo;
                layer.normalMapTexture = normal;
                layer.maskMapTexture = mask;
                layer.normalScale = 1f;
                layer.tileSize = new Vector2(L.metres, L.metres);
                layer.maskMapRemapMin = Vector4.zero;
                layer.maskMapRemapMax = Vector4.one;
                layer.smoothness = 0f; layer.metallic = 0f;
                EditorUtility.SetDirty(layer);
                made[i] = layer;
            }
            EditorUtility.ClearProgressBar();

            Directory.CreateDirectory(Path.GetDirectoryName(MAT));
            var m = AssetDatabase.LoadAssetAtPath<Material>(MAT);
            var sh = Shader.Find("HDRP/TerrainLit");
            if (m == null) { m = new Material(sh); AssetDatabase.CreateAsset(m, MAT); }
            m.shader = sh;
            m.SetFloat("_EnableHeightBlend", 1f);
            m.SetFloat("_HeightTransition", 0.15f);
            m.SetFloat("_EnableInstancedPerPixelNormal", 1f);
            HDMaterial.ValidateMaterial(m);
            EditorUtility.SetDirty(m);

            // hand both to every WorldStreamer in the open scenes
            foreach (var ws in Object.FindObjectsByType<Runout.Game.WorldStreamer>(FindObjectsSortMode.None))
            {
                Undo.RecordObject(ws, "Terrain layers");
                ws.layers = made;
                ws.terrainMaterial = m;
                EditorUtility.SetDirty(ws);
            }
            AssetDatabase.SaveAssets();
            Debug.Log($"Runout: {made.Length} terrain layers + {MAT} built from Megascans (save the scene to keep them on the WorldStreamer).");
        }

        static Texture2D Copy(string from, string to, bool normal)
        {
            if (!File.Exists(to)) File.Copy(from, to);
            AssetDatabase.ImportAsset(to, ImportAssetOptions.ForceSynchronousImport);
            var imp = (TextureImporter)AssetImporter.GetAtPath(to);
            imp.textureType = normal ? TextureImporterType.NormalMap : TextureImporterType.Default;
            imp.sRGBTexture = !normal;
            imp.mipmapEnabled = true;
            imp.anisoLevel = 16;
            imp.maxTextureSize = 2048;
            imp.textureCompression = TextureImporterCompression.CompressedHQ;
            imp.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(to);
        }

        /// R metal 0, G AO, B height (the displacement, stretched to its own range), A smoothness (gloss), 2048 px
        static Texture2D PackMask(string src, string to)
        {
            const int N = 2048;
            float[] ao = Gray(src + "_AO.jpg", N), gloss = Gray(src + "_Gloss.jpg", N);
            float[] hgt = File.Exists(src + "_Displacement.exr") ? Gray(src + "_Displacement.exr", N) : Gray(src + "_Displacement.jpg", N);
            float lo = float.MaxValue, hi = float.MinValue;
            foreach (var v in hgt) { lo = Mathf.Min(lo, v); hi = Mathf.Max(hi, v); }
            float span = Mathf.Max(1e-5f, hi - lo);
            var px = new Color[N * N];
            for (int i = 0; i < px.Length; i++)
                px[i] = new Color(0f, ao != null ? ao[i] : 1f, (hgt[i] - lo) / span, gloss != null ? gloss[i] : 0.3f);
            var t = new Texture2D(N, N, TextureFormat.RGBA32, false, true);
            t.SetPixels(px);
            File.WriteAllBytes(to, t.EncodeToPNG());
            Object.DestroyImmediate(t);
            AssetDatabase.ImportAsset(to, ImportAssetOptions.ForceSynchronousImport);
            var imp = (TextureImporter)AssetImporter.GetAtPath(to);
            imp.sRGBTexture = false;
            imp.mipmapEnabled = true;
            imp.anisoLevel = 16;
            imp.textureCompression = TextureImporterCompression.CompressedHQ;
            imp.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(to);
        }

        /// a scan channel resampled to n x n (jpg via LoadImage; exr via a temporary readable import)
        static float[] Gray(string path, int n)
        {
            if (!File.Exists(path)) return null;
            Texture2D src;
            string tmp = null;
            if (path.EndsWith(".exr"))
            {
                tmp = "Assets/Runout/Art/Megascans/_tmp.exr";
                File.Copy(path, tmp, true);
                AssetDatabase.ImportAsset(tmp, ImportAssetOptions.ForceSynchronousImport);
                var imp = (TextureImporter)AssetImporter.GetAtPath(tmp);
                imp.isReadable = true; imp.sRGBTexture = false; imp.mipmapEnabled = false;
                imp.textureCompression = TextureImporterCompression.Uncompressed;
                imp.maxTextureSize = 8192;
                imp.SaveAndReimport();
                src = AssetDatabase.LoadAssetAtPath<Texture2D>(tmp);
            }
            else
            {
                src = new Texture2D(2, 2, TextureFormat.RGBA32, false, true);
                src.LoadImage(File.ReadAllBytes(path));
            }
            var o = new float[n * n];
            for (int y = 0; y < n; y++)
                for (int x = 0; x < n; x++)
                    o[y * n + x] = src.GetPixelBilinear((x + 0.5f) / n, (y + 0.5f) / n).r;
            if (tmp != null) AssetDatabase.DeleteAsset(tmp);
            else Object.DestroyImmediate(src);
            return o;
        }
    }
}
