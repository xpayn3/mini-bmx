using System.Collections.Generic;
using Runout.Levels;
using Runout.Sim;
using UnityEngine;
using UnityEngine.Rendering.HighDefinition;

namespace Runout.Game
{
    /// The test playground in Unity (Godot: LEVELS > TEST PLAYGROUND, dev/playground). The course data is engine-free
    /// (Runout.Levels.PlaygroundCourse, ported 1:1 and checked against Godot); this component turns it into the ride's
    /// ground (IGround, what the physics reads) and draws it - in the editor too, so the lanes and every PlaygroundFeature
    /// placed in the scene show without pressing Play. Moving / editing a PlaygroundFeature rebuilds the placed ones.
    /// Sim coordinates (Godot convention) -> Unity: (x, y, z) -> (x, y, -z) (see BikeView).
    [ExecuteAlways]
    public sealed class PlaygroundWorld : MonoBehaviour
    {
        [Tooltip("the fixed reference lanes (tables, gaps, hops, drops, bumps, slopes, camber, rocks, step-downs, brakes, designed jumps) + the berm bowls")]
        public bool referenceLanes = true;
        [Tooltip("a PlaygroundFeature to start in front of (Ride from here sets it); none = the start of the TABLES lane")]
        public PlaygroundFeature startAt;
        [Tooltip("or a feature id from the reference lanes (table_1.5, gap_7, drop_2, roller_0.6, berm_45 ...)")]
        public string startFeatureId = "";
        [Tooltip("metres before the feature to start")]
        public float startBack = 25f;

        public PlaygroundCourse Course { get; private set; }
        public IGround Ground => _ground;
        PlaygroundGround _ground;

        static readonly Color GRASS = new Color(0.40f, 0.47f, 0.31f), DIRT = new Color(0.58f, 0.45f, 0.32f), CLAY = new Color(0.66f, 0.46f, 0.30f);
        static readonly Color[] SURF_COL = { new Color(0.36f, 0.50f, 0.28f), new Color(0.58f, 0.45f, 0.32f), new Color(0.30f, 0.24f, 0.18f), new Color(0.86f, 0.76f, 0.52f) };
        Material[] _mats;   // grass, dirt, clay, surface 0..3
        Material _rockMat, _postMat;
        Transform _fixedRoot, _placedRoot;
        bool _dirty = true, _placedDirty = true;
        float _dirtyAt;

        void OnEnable() { _dirty = true; Rebuild(); }

        void OnDisable() { Clear(true); }

        /// a PlaygroundFeature changed (moved / numbers / added / removed): rebuild the placed ones shortly
        public void MarkPlacedDirty() { _placedDirty = true; _dirtyAt = Time.realtimeSinceStartup; }

        void OnValidate() { _dirty = true; }

        void Update()
        {
            if (_dirty) { Rebuild(); return; }
            if (_placedDirty && Time.realtimeSinceStartup - _dirtyAt > 0.15f) RebuildPlaced();
        }

        public void Rebuild()
        {
            _dirty = false;
            Course = new PlaygroundCourse(referenceLanes);
            _ground = new PlaygroundGround(Course);
            EnsureMaterials();
            Clear(true);
            _fixedRoot = Root("Playground (generated)");
            foreach (var l in Course.lanes) AddMesh(_fixedRoot, "Lane " + l.id, LaneMesh(l));
            foreach (var b in Course.bowls) AddMesh(_fixedRoot, "Bowl " + b.id, GridMesh(b.rect.x, b.rect.z, b.rect.end_x, b.rect.end_z, 0.4, 0.4));
            AddMesh(_fixedRoot, "Plane", PlaneMesh());
            BuildRocks(_fixedRoot, Course.rocks);
            BuildPosts(_fixedRoot, Course.feats);
            RebuildPlaced();
        }

        /// the scene's PlaygroundFeatures -> the course's placed features (the reference lanes stay)
        public void RebuildPlaced()
        {
            _placedDirty = false;
            if (Course == null) { Rebuild(); return; }
            Course.clear_placed();
            var placed = new List<PlacedFeature>();
            foreach (var pf in FindObjectsByType<PlaygroundFeature>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
            {
                var p = pf.ToPlaced();
                if (p == null) continue;
                pf.placed = p;
                Course.add_placed(p);
                placed.Add(p);
            }
            Course.reindex();
            if (_placedRoot != null) DestroyNow(_placedRoot.gameObject);
            _placedRoot = Root("Placed features (generated)");
            foreach (var p in placed)
            {
                AddMesh(_placedRoot, "Placed " + p.feat.id, PlacedMesh(p));
                BuildRocks(_placedRoot, p.rocks);
                BuildPosts(_placedRoot, new List<Feature> { p.feat });
            }
        }

        /// where the ride starts: (x, heading, z) in sim coordinates, like Godot's spawn_for / default_spawn
        public V3 Spawn()
        {
            if (Course == null) Rebuild();
            Feature f = null;
            if (startAt != null && startAt.placed != null) f = startAt.placed.feat;
            else if (!string.IsNullOrEmpty(startFeatureId)) f = Course.feature_by_id(startFeatureId);
            return f != null ? Course.spawn_for(f, startBack) : Course.default_spawn();
        }

        // ---- drawing ------------------------------------------------------------------------------------------
        Transform Root(string name)
        {
            var go = new GameObject(name) { hideFlags = HideFlags.DontSave | HideFlags.NotEditable };
            go.transform.SetParent(transform, false);
            return go.transform;
        }

        void Clear(bool all)
        {
            for (int i = transform.childCount - 1; i >= 0; i--)
            {
                var c = transform.GetChild(i).gameObject;
                if ((c.hideFlags & HideFlags.DontSave) != 0) DestroyNow(c);
            }
            _fixedRoot = null; _placedRoot = null;
        }

        static void DestroyNow(Object o)
        {
            if (Application.isPlaying) Destroy(o); else DestroyImmediate(o);
        }

        void EnsureMaterials()
        {
            if (_mats != null && _mats[0] != null) return;
            var grid = GridTexture();
            Material M(Color c, float smooth)
            {
                var m = new Material(Shader.Find("HDRP/Lit")) { hideFlags = HideFlags.DontSave };
                m.SetColor("_BaseColor", c);
                m.SetTexture("_BaseColorMap", grid);
                m.SetTextureScale("_BaseColorMap", new Vector2(0.2f, 0.2f));   // UV = world metres: one tile = 5 m
                m.SetFloat("_Smoothness", smooth);
                HDMaterial.ValidateMaterial(m);
                return m;
            }
            _mats = new[] { M(GRASS, 0.1f), M(DIRT, 0.15f), M(CLAY, 0.15f), M(SURF_COL[0], 0.1f), M(SURF_COL[1], 0.15f), M(SURF_COL[2], 0.6f), M(SURF_COL[3], 0.05f) };
            _rockMat = new Material(Shader.Find("HDRP/Lit")) { hideFlags = HideFlags.DontSave };
            _rockMat.SetColor("_BaseColor", new Color(0.52f, 0.5f, 0.47f));
            HDMaterial.ValidateMaterial(_rockMat);
            _postMat = new Material(Shader.Find("HDRP/Lit")) { hideFlags = HideFlags.DontSave };
            _postMat.SetColor("_BaseColor", new Color(1.0f, 0.45f, 0.1f));
            HDMaterial.ValidateMaterial(_postMat);
        }

        /// the measuring grid: thin lines every 1 m, bold every 5 m (one texture = 5 m)
        static Texture2D GridTexture()
        {
            const int N = 500;   // 1 cm a texel
            var t = new Texture2D(N, N, TextureFormat.RGBA32, true, true) { hideFlags = HideFlags.DontSave, wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Trilinear, anisoLevel = 8 };
            var px = new Color32[N * N];
            for (int j = 0; j < N; j++)
                for (int i = 0; i < N; i++)
                {
                    bool bold = i < 3 || j < 3;
                    bool thin = i % 100 < 1 || j % 100 < 1;
                    byte v = (byte)(bold ? 160 : thin ? 210 : 255);
                    px[j * N + i] = new Color32(v, v, v, 255);
                }
            t.SetPixels32(px);
            t.Apply(true);
            return t;
        }

        void AddMesh(Transform parent, string name, Mesh m)
        {
            var go = new GameObject(name) { hideFlags = HideFlags.DontSave | HideFlags.NotEditable };
            go.transform.SetParent(parent, false);
            go.AddComponent<MeshFilter>().sharedMesh = m;
            var mr = go.AddComponent<MeshRenderer>();
            var use = new Material[m.subMeshCount];
            for (int i = 0; i < use.Length; i++) use[i] = _mats[i];
            mr.sharedMaterials = use;
        }

        /// 0 grass, 1 dirt, 2 clay (built up / dug), 3..6 a brake strip's surface (grass, dirt, wet, sand)
        int Category(double x, double z, double h)
        {
            int sf = Course.surface_at(x, z);
            if (sf >= 0) return 3 + sf;
            if (System.Math.Abs(h) > 0.02) return 2;
            return Course.is_dirt(x, z) ? 1 : 0;
        }

        /// rows along x: fine (0.1 m) wherever the profile isn't flat, coarse (2 m) on the flat (Godot's _lane_mesh)
        Mesh LaneMesh(Lane l)
        {
            var xs = new List<double>();
            double x = l.rect.x, x_end = l.rect.end_x;
            while (x < x_end - 1e-6)
            {
                xs.Add(x);
                double uu = x - PlaygroundCourse.X0;
                bool busy = false;
                for (int k = -6; k <= 6 && !busy; k++)
                {
                    double q = uu + k * 0.1;
                    if (System.Math.Abs(l.profile(q)) > 1e-4 || (l.camber.Count > 0 && l.tilt_at(q) != 0.0) || System.Math.Abs(l.profile(q) - l.profile(q + 0.05)) > 1e-5) busy = true;
                }
                foreach (var sk in l.skews) if (uu > sk[0] - 7.0 && uu < sk[1] + 7.0) busy = true;
                x += busy ? 0.1 : 2.0;
            }
            xs.Add(x_end);
            var zs = new List<double>();
            for (double z = l.rect.z; z < l.rect.end_z - 1e-6; z += 0.5) zs.Add(z);
            zs.Add(l.rect.end_z);
            return MeshFrom(xs, zs, (a, b) => (a, b));
        }

        Mesh GridMesh(double x0, double z0, double x1, double z1, double dx, double dz)
        {
            var xs = new List<double>(); var zs = new List<double>();
            for (double x = x0; x < x1 - 1e-6; x += dx) xs.Add(x);
            xs.Add(x1);
            for (double z = z0; z < z1 - 1e-6; z += dz) zs.Add(z);
            zs.Add(z1);
            return MeshFrom(xs, zs, (a, b) => (a, b));
        }

        /// a placed feature on its own axis: 0.1 m along it, 0.25 m across, over its whole reach
        Mesh PlacedMesh(PlacedFeature p)
        {
            if (p.bowl != null) return GridMesh(p.rect.x, p.rect.z, p.rect.end_x, p.rect.end_z, 0.4, 0.4);   // (a bowl's origin is its centre)
            var us = new List<double>(); var vs = new List<double>();
            double len = p.length + 4.0, reach = p.reach + 0.5;
            for (double u = -6.0; u < len; u += 0.1) us.Add(u);   // (from -6: a hip's skewed edge reaches ~4.2 m before u = 0)
            us.Add(len);
            for (double v = -reach; v < reach; v += 0.25) vs.Add(v);
            vs.Add(reach);
            V2 o = p.origin(), d = p.dir(), s = p.side();
            return MeshFrom(us, vs, (u, v) => (o.x + d.x * u + s.x * v, o.y + d.y * u + s.y * v));
        }

        /// a grid of (a, b) parameters mapped to sim (x, z) by `at`, heights / colours from the course; one sub-mesh per
        /// ground category so plain HDRP Lit materials colour it
        Mesh MeshFrom(List<double> As, List<double> Bs, System.Func<double, double, (double, double)> at)
        {
            int na = As.Count, nb = Bs.Count;
            var V = new Vector3[na * nb];
            var UV = new Vector2[na * nb];
            var cat = new int[na * nb];
            for (int j = 0; j < nb; j++)
                for (int i = 0; i < na; i++)
                {
                    var (x, z) = at(As[i], Bs[j]);
                    double h = Course.height(x, z);
                    int k = j * na + i;
                    V[k] = new Vector3((float)x, (float)h, (float)-z);
                    UV[k] = new Vector2((float)x, (float)-z);
                    cat[k] = Category(x, z, h);
                }
            var tris = new List<int>[7];
            for (int c = 0; c < 7; c++) tris[c] = new List<int>();
            for (int j = 0; j < nb - 1; j++)
                for (int i = 0; i < na - 1; i++)
                {
                    int a = j * na + i;
                    int c = System.Math.Max(System.Math.Max(cat[a], cat[a + 1]), System.Math.Max(cat[a + na], cat[a + na + 1]));
                    var t = tris[c];
                    // (sim z is mirrored into Unity: a -> a+1 -> a+na is clockwise seen from above = faces up)
                    t.Add(a); t.Add(a + 1); t.Add(a + na);
                    t.Add(a + 1); t.Add(a + na + 1); t.Add(a + na);
                }
            var m = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32, hideFlags = HideFlags.DontSave };
            m.vertices = V; m.uv = UV;
            m.subMeshCount = 7;
            for (int c = 0; c < 7; c++) m.SetTriangles(tris[c], c, false);
            m.RecalculateNormals();
            m.RecalculateBounds();
            return m;
        }

        /// the flat out to the horizon, a hair under the strips (their flat parts sit at 0)
        Mesh PlaneMesh()
        {
            const float F = 2400f, Y = -0.01f;
            var m = new Mesh { hideFlags = HideFlags.DontSave };
            m.vertices = new[] { new Vector3(-F, Y, -F), new Vector3(F, Y, -F), new Vector3(-F, Y, F), new Vector3(F, Y, F) };
            m.uv = new[] { new Vector2(-F, -F), new Vector2(F, -F), new Vector2(-F, F), new Vector2(F, F) };
            m.subMeshCount = 7;
            m.SetTriangles(new[] { 0, 2, 1, 1, 2, 3 }, 0);
            for (int c = 1; c < 7; c++) m.SetTriangles(new int[0], c);
            m.RecalculateNormals();
            return m;
        }

        void BuildRocks(Transform parent, List<Rock> rocks)
        {
            if (rocks == null || rocks.Count == 0) return;
            var root = new GameObject("Rocks") { hideFlags = HideFlags.DontSave | HideFlags.NotEditable }.transform;
            root.SetParent(parent, false);
            foreach (var r in rocks)
            {
                var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                go.hideFlags = HideFlags.DontSave | HideFlags.NotEditable;
                DestroyNow(go.GetComponent<Collider>());
                go.transform.SetParent(root, false);
                go.transform.localPosition = new Vector3((float)r.x, (float)(-r.sc * 0.3), (float)-r.z);
                go.transform.localRotation = Quaternion.AngleAxis((float)(-r.yaw * Mathf.Rad2Deg), Vector3.up);
                go.transform.localScale = new Vector3((float)r.sx, (float)r.sy, (float)r.sc) * 2f;
                go.GetComponent<MeshRenderer>().sharedMaterial = _rockMat;
            }
        }

        /// an orange post beside every lip / brake line (Godot's sign posts)
        void BuildPosts(Transform parent, List<Feature> feats)
        {
            foreach (var f in feats)
            {
                if (f.lip < 0 || f.bowl != null) continue;
                V3 p = Course.feat_point(f, f.lip);
                double side = (f.placed != null ? f.placed.width : 3.0) + 0.8;
                V2 s = f.placed != null ? f.placed.side() : new V2(0, 1);
                var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                go.name = "Lip " + f.id;
                go.hideFlags = HideFlags.DontSave | HideFlags.NotEditable;
                DestroyNow(go.GetComponent<Collider>());
                go.transform.SetParent(parent, false);
                double px = p.x + s.x * side, pz = p.z + s.y * side;
                go.transform.localPosition = new Vector3((float)px, (float)p.y + 0.6f, (float)-pz);
                go.transform.localScale = new Vector3(0.08f, 0.6f, 0.08f);
                go.GetComponent<MeshRenderer>().sharedMaterial = _postMat;
            }
        }

#if UNITY_EDITOR
        void OnDrawGizmos()
        {
            if (Course == null) return;
            foreach (var f in Course.feats)
            {
                if (f.bowl != null || f.placed != null) continue;
                V3 p = Course.feat_point(f, f.u0);
                UnityEditor.Handles.Label(new Vector3((float)p.x, (float)p.y + 2.2f, (float)-p.z + 4f), f.id);
            }
        }
#endif
    }

    /// the course as the ride's ground (Godot: PlaygroundTerrain). Rocks are domes in height() and colliders_near()
    public sealed class PlaygroundGround : IGround
    {
        readonly PlaygroundCourse _c;
        static readonly List<GdDict> NONE = new List<GdDict>();
        public PlaygroundGround(PlaygroundCourse c) { _c = c; }

        public double height(double x, double z) => _c.height_rocks(x, z);
        public double deck_height(double x, double z) => _c.height(x, z);
        public double top_height(double x, double z) => _c.height_rocks(x, z);
        public long surface(double x, double z)
        {
            int sf = _c.surface_at(x, z);
            if (sf >= 0) return sf;
            return _c.is_dirt(x, z) ? 1 : 0;
        }
        public double jump_mask(double x, double z) => _c.jump_mask(x, z);

        /// a fresh list when there are rocks (the ride may look again while it walks one), a shared empty one otherwise
        public List<GdDict> colliders_near(double x, double z)
        {
            var rocks = _c.rocks_near(x, z);
            if (rocks.Count == 0) return NONE;
            var _near = new List<GdDict>(rocks.Count);
            foreach (var r in rocks)
            {
                var d = new GdDict { id = "rock" + r.x.ToString("R") + "," + r.z.ToString("R") };
                d["x"] = r.x; d["z"] = r.z; d["r"] = r.r; d["top"] = r.top; d["base"] = r.@base; d["sink"] = r.sink;
                d.src = r;
                _near.Add(d);
            }
            return _near;
        }

        public RayHit cast(V3 origin, V3 dir, double max_dist) => new RayHit { hit = false };
    }
}
