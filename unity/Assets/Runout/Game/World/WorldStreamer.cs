using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Runout.World;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace Runout.Game
{
    /// The procedural world in Unity. Our height field (Runout.World, engine-free) decides the land the bike rides;
    /// Unity draws it as streamed Terrain tiles (HDRP Terrain Lit, Unity's own LOD, auto-connected neighbours).
    ///
    /// Two rings of Unity Terrains:
    /// - near: `tileSize` (128 m) tiles at `resolution` (0.5 m), `radius` tiles round the camera, full splat;
    /// - far: `farSize` (1024 m) tiles at `farResolution` (4 m) out to `farRadius` tiles (~2.5 km each way), coarse
    ///   splat. Few big tiles: every Unity Terrain costs CPU each frame (culling, LOD, its draws, again for shadows), so
    ///   the far ring is ~25 tiles, not ~100. The grids line up (1024 = 8 x 128): where a near tile is drawn, the far tile has a Unity Terrain hole,
    ///   so every spot is drawn once (needs HDRP's "Terrain Hole" support, on in the HDRP asset). Far tiles sit
    ///   `farDrop` lower so the seam to the finer ring is a tiny step, never a gap.
    ///
    /// Tiles are filled from the field on worker threads (a field fork per thread: it keeps per-instance caches),
    /// arrays recycled. A finished tile reaches Unity over two frames (heights + Terrain, then splat), one stage a
    /// frame, near tiles first; each stage is timed (`log`). No PhysX colliders (nothing reads them: ride, crash and
    /// ragdoll ask WorldGround). Floating origin (WorldOrigin): tiles sit at W(godot - GodotSpace.Origin). top_height
    /// (what tyres, feet and the ragdoll touch) reads the near tile drawn there.
    [DefaultExecutionOrder(-300)]
    public sealed class WorldStreamer : MonoBehaviour
    {
        [Tooltip("the world: the same seed gives the same trail and land as Godot")]
        public long seed = 4242;
        [Tooltip("Land Lab knobs (godot/data/land_params.json format), under StreamingAssets; missing = defaults")]
        public string landFile = "World/land_params.json";
        [Header("Route style (1 = as designed)")]
        [Range(0.25f, 2.5f)] public float jumps = 1f;
        [Range(0.5f, 1.5f)] public float twist = 1f;
        [Range(0f, 2f)] public float rolling = 1f;
        [Range(0.5f, 1.7f)] public float grade = 1f;
        [Tooltip("0 any, 1 green hills, 2 rocky mountains, 3 dune sea, 4 red canyons")] [Range(0, 4)] public int biome = 0;
        [Header("Near land")]
        [Tooltip("metres per tile side")] public float tileSize = 128f;
        [Tooltip("height samples per tile side (2^n + 1): 257 over 128 m = 0.5 m")] public int resolution = 257;
        [Tooltip("splat texels per tile side (256 over 128 m = 0.5 m)")] public int splatResolution = 256;
        [Tooltip("tiles kept each side of the one under the camera (3 = 0.5 m land ~450 m out)")] public int radius = 3;
        [Tooltip("Unity terrain pixel error: lower = finer LOD further out")] public float pixelError = 3f;
        [Header("Far land (to the horizon)")]
        [Tooltip("metres per far tile side (a whole number of near tiles)")] public float farSize = 1024f;
        [Tooltip("height samples per far tile side: 257 over 1024 m = 4 m")] public int farResolution = 257;
        [Tooltip("splat texels per far tile side (256 over 1024 m = 4 m)")] public int farSplat = 256;
        [Tooltip("far tiles kept each side of the one under the camera (2 = ~2.5 km)")] public int farRadius = 2;
        [Tooltip("m the far land sits under the near land (hides the seam)")] public float farDrop = 0.4f;
        public float farPixelError = 6f;
        [Header("Look")]
        [Tooltip("drawn terrain material (none = HDRP's default Terrain Lit)")] public Material terrainMaterial;
        public TerrainLayer[] layers;
        [Tooltip("print streaming timings (worst main-thread stage)")] public bool log = true;

        public const float MIN_Y = -200f, SIZE_Y = 1000f;   // heights stored 0..1 over this range (~1.5 cm steps)
        /// the splat layers, in order (Editor/TerrainLayers.cs builds them in the same order)
        public static readonly string[] LAYERS = { "Grass", "Forest", "TrailPacked", "Gravel", "Rock", "Mud" };
        const int GRASS = 0, FOREST = 1, PACKED = 2, GRAVEL = 3, ROCK = 4, MUD = 5;

        public FieldTables Tables { get; private set; }
        public TrailCourse Course { get; private set; }
        public TerrainField Field { get; private set; }
        public WorldGround Ground { get; private set; }

        sealed class Ring
        {
            public bool far;
            public float size, drop, pixelError;
            public int res, splat, radius, group;
            public readonly Dictionary<Vector2Int, Tile> tiles = new Dictionary<Vector2Int, Tile>();
            public readonly ConcurrentQueue<Tile> done = new ConcurrentQueue<Tile>();
            public readonly Queue<Tile> splatQ = new Queue<Tile>();
            public readonly Queue<Tile> objQ = new Queue<Tile>();   // heights in, Terrain object next
        }

        sealed class Tile
        {
            public Ring ring;
            public Vector2Int key;          // tile index in absolute Unity xz (no floating origin)
            public Terrain terrain;
            public float[,] heights;        // worker -> stage 1
            public float[,,] alphas;        // worker -> stage 2
            public int stage;               // 0 filling, 1 heights ready, 2 drawn without splat, 3 done
            public TerrainData data;        // stage 1a: heights in, no Terrain yet
            public bool holesDirty;         // far: the near tiles over it changed
        }

        Ring _near, _far;
        /// (tests, HUD) loaded tiles per ring, main-thread stages done, the worst / average stage in ms
        public int NearTiles => _near == null ? 0 : CountMade(_near);
        public int FarTiles => _far == null ? 0 : CountMade(_far);
        public int Stages => _stages;
        public double WorstStageMs => _worstMs;
        public double AvgStageMs => _stages > 0 ? _sumMs / _stages : 0.0;
        static int CountMade(Ring r) { int c = 0; foreach (var t in r.tiles.Values) if (t.terrain != null) c++; return c; }
        readonly ConcurrentDictionary<long, ConcurrentBag<float[,]>> _hPool = new ConcurrentDictionary<long, ConcurrentBag<float[,]>>();
        readonly ConcurrentDictionary<long, ConcurrentBag<float[,,]>> _aPool = new ConcurrentDictionary<long, ConcurrentBag<float[,,]>>();
        ThreadLocal<TerrainField> _forks;
        Transform _root;
        double _worstMs, _sumMs;
        int _stages;
        readonly Dictionary<string, (double worst, double sum, int n)> _parts = new Dictionary<string, (double, double, int)>();
        readonly Stopwatch _psw = new Stopwatch();

        /// time one part of a stage (heights, create, link, splat, holes): the worst and average per part
        void Part(string name)
        {
            double ms = _psw.Elapsed.TotalMilliseconds;
            _parts.TryGetValue(name, out var p);
            _parts[name] = (System.Math.Max(p.worst, ms), p.sum + ms, p.n + 1);
            _psw.Restart();
        }

        /// (tests, logs) each part's worst / average main-thread ms
        public string StageReport
        {
            get
            {
                var sb = new System.Text.StringBuilder();
                foreach (var kv in _parts) sb.Append($"{kv.Key} worst {kv.Value.worst:0.0} avg {kv.Value.sum / System.Math.Max(1, kv.Value.n):0.0} ms ({kv.Value.n}x); ");
                return sb.ToString();
            }
        }

        void Awake()
        {
            if (GetComponent<WorldOrigin>() == null) gameObject.AddComponent<WorldOrigin>();   // big world: floating origin
            Load();
        }

        public void Load()
        {
            if (Field != null) return;
            var sw = Stopwatch.StartNew();
            string lp = Path.Combine(Application.streamingAssetsPath, landFile);
            var knobs = LandParams.FromJson(File.Exists(lp) ? File.ReadAllText(lp) : "");
            var style = new Dictionary<string, double> { ["jumps"] = jumps, ["twist"] = twist, ["rolling"] = rolling, ["grade"] = grade, ["biome"] = biome };
            var w = WorldSetup.Build(seed, style, knobs);
            Tables = w.tables;
            Field = w.field;
            Course = w.course;
            Ground = new WorldGround(Field) { drawn = DrawnHeight };
            var main = Field;
            _forks = new ThreadLocal<TerrainField>(() => { lock (main) return main.fork(); });
            Debug.Log($"WorldStreamer: world seed {seed} built in {sw.Elapsed.TotalMilliseconds:0} ms ({Course.length / 1000.0:0.0} km of trail, {Tables.route_feats.Count} route features)");
        }

        /// (sim x, sim z, heading) of the trail start, a little way down it
        public (double x, double z, double heading) Spawn() => WorldGround.TrailStart(Tables);

        void Start()
        {
            _near = new Ring { size = tileSize, res = resolution, splat = splatResolution, radius = radius, pixelError = pixelError, group = 7 };
            _far = new Ring { far = true, size = farSize, res = farResolution, splat = farSplat, radius = farRadius, drop = farDrop, pixelError = farPixelError, group = 8 };
            _root = new GameObject("World Tiles").transform;
            _root.SetParent(transform, false);
            // the near tiles round the start first, all at once, so the first frame has ground under the bike
            var c = TileOf(_near, FollowAbs());
            var first = new List<Tile>();
            for (int dz = -1; dz <= 1; dz++)
                for (int dx = -1; dx <= 1; dx++)
                    first.Add(Want(_near, new Vector2Int(c.x + dx, c.y + dz), queue: false));
            Parallel.ForEach(first, Fill);
            foreach (var t in first) { MakeTerrain(t); ApplySplat(t); }
        }

        /// the camera (or the spawn) in absolute Unity xz: the floating origin taken back out
        Vector3 FollowAbs()
        {
            var cam = Camera.main;
            Vector3 u;
            if (cam != null) u = cam.transform.position;
            else { var s = Spawn(); u = GodotSpace.P(new Vector3((float)s.x, 0f, (float)s.z)); }
            var g = GodotSpace.PInv(u);
            return new Vector3(g.x, g.y, -g.z);
        }

        static Vector2Int TileOf(Ring r, Vector3 abs) => new Vector2Int(Mathf.FloorToInt(abs.x / r.size), Mathf.FloorToInt(abs.z / r.size));

        Tile Want(Ring r, Vector2Int k, bool queue = true)
        {
            if (r.tiles.TryGetValue(k, out var t)) return t;
            t = new Tile { ring = r, key = k };
            r.tiles[k] = t;
            if (queue) Task.Run(() => { Fill(t); r.done.Enqueue(t); });
            return t;
        }

        // ------------------------------------------------------------------ workers
        float[,] TakeH(int n) => _hPool.GetOrAdd(n, _ => new ConcurrentBag<float[,]>()).TryTake(out var a) ? a : new float[n, n];
        float[,,] TakeA(int n, int l) => _aPool.GetOrAdd(n * 100 + l, _ => new ConcurrentBag<float[,,]>()).TryTake(out var a) ? a : new float[n, n, l];
        void GiveH(float[,] a) => _hPool.GetOrAdd(a.GetLength(0), _ => new ConcurrentBag<float[,]>()).Add(a);
        void GiveA(float[,,] a) => _aPool.GetOrAdd(a.GetLength(0) * 100 + a.GetLength(2), _ => new ConcurrentBag<float[,,]>()).Add(a);

        /// worker: heights (Unity rows = z, columns = x) and splat weights from the field
        void Fill(Tile t)
        {
            var f = _forks.Value;
            var r = t.ring;
            int n = r.res;
            var h = TakeH(n);
            double step = r.size / (n - 1);
            double ox = t.key.x * (double)r.size, oz = t.key.y * (double)r.size;
            for (int j = 0; j < n; j++)
            {
                double uz = oz + j * step;
                for (int i = 0; i < n; i++)
                {
                    double y = f.height(ox + i * step, -uz) - r.drop;
                    h[j, i] = Mathf.Clamp01((float)((y - MIN_Y) / SIZE_Y));
                }
            }
            t.heights = h;
            if (layers != null && layers.Length == LAYERS.Length) t.alphas = Splat(f, r, ox, oz, h, step);
            t.stage = 1;
        }

        static float Sm(double a, double b, double x) { double t = System.Math.Clamp((x - a) / (b - a), 0.0, 1.0); return (float)(t * t * (3 - 2 * t)); }

        /// the ground layers from the field: the trail's packed core and loose edge (trail()), rock on faces steeper than
        /// ~32-42 deg, mud at the water's edge, forest floor / dry gravel by biome, grass elsewhere
        float[,,] Splat(TerrainField f, Ring r, double ox, double oz, float[,] hn, double hstep)
        {
            int n = r.splat, hres = r.res, L = LAYERS.Length;
            var a = TakeA(n, L);
            double step = r.size / n;
            var w = new float[L];
            for (int j = 0; j < n; j++)
            {
                double uz = oz + (j + 0.5) * step;
                for (int i = 0; i < n; i++)
                {
                    double x = ox + (i + 0.5) * step, z = -uz;
                    int hi = System.Math.Clamp((int)((i + 0.5) * step / hstep), 1, hres - 2), hj = System.Math.Clamp((int)((j + 0.5) * step / hstep), 1, hres - 2);
                    double gx = (hn[hj, hi + 1] - hn[hj, hi - 1]) * SIZE_Y / (2 * hstep), gz = (hn[hj + 1, hi] - hn[hj - 1, hi]) * SIZE_Y / (2 * hstep);
                    double slope = System.Math.Sqrt(gx * gx + gz * gz);
                    double y = hn[hj, hi] * SIZE_Y + MIN_Y + r.drop;
                    f.biome(x, z);
                    System.Array.Clear(w, 0, L);
                    float trail = (float)System.Math.Max(f.trail(x, z), f.jump_mask(x, z));
                    float core = Sm(0.55, 0.92, trail);
                    w[PACKED] = core;
                    w[GRAVEL] = (trail - core) * 1.2f;
                    float off = 1f - System.Math.Min(1f, trail);
                    float rock = Sm(0.62, 0.9, slope);
                    float mud = System.Math.Min(1f, Sm(TerrainField.WATER + 0.9, TerrainField.WATER + 0.15, y) + 0.25f * (float)f.b_wet);
                    float forest = (float)f.b_forest;
                    float dry = Sm(0.35, 0.85, f.b_dry);
                    w[ROCK] += off * rock;
                    float land = off * (1f - rock);
                    w[MUD] += land * mud;
                    land *= 1f - mud;
                    w[GRAVEL] += land * dry * 0.8f;
                    land *= 1f - dry * 0.8f;
                    w[FOREST] += land * forest;
                    w[GRASS] += land * (1f - forest);
                    float sum = 0f;
                    for (int k = 0; k < L; k++) sum += w[k];
                    for (int k = 0; k < L; k++) a[j, i, k] = sum > 0f ? w[k] / sum : (k == GRASS ? 1f : 0f);
                }
            }
            return a;
        }

        // ------------------------------------------------------------------ main thread
        /// stage 1: the Terrain with its heights, over two frames (MakeData: heights; MakeTerrain: the Terrain object)
        void MakeTerrain(Tile t)
        {
            if (t.data == null) MakeData(t);
            MakeObject(t);
        }

        void MakeData(Tile t)
        {
            var r = t.ring;
            _psw.Restart();
            var td = new TerrainData { heightmapResolution = r.res };
            td.size = new Vector3(r.size, SIZE_Y, r.size);
            td.SetHeightsDelayLOD(0, 0, t.heights);
            td.SyncHeightmap();
            Part(r.far ? "far heights" : "heights");
            GiveH(t.heights);
            t.heights = null;
            if (layers != null && layers.Length > 0) td.terrainLayers = layers;
            td.baseMapResolution = 32;   // (never drawn: basemapDistance is past the far ring; keeps it free if Unity bakes one)
            t.data = td;
        }

        void MakeObject(Tile t)
        {
            var r = t.ring;
            var td = t.data;
            t.data = null;
            _psw.Restart();
            var go = new GameObject($"{(r.far ? "Far" : "Tile")} {t.key.x},{t.key.y}");
            go.transform.SetParent(_root, false);
            go.transform.position = GodotSpace.P(new Vector3(t.key.x * r.size, MIN_Y, -t.key.y * r.size));
            var ter = go.AddComponent<Terrain>();
            ter.terrainData = td;
            ter.drawInstanced = true;
            ter.heightmapPixelError = r.pixelError;
            // no baked basemap for the far ring: Unity renders one from every layer for each new tile (a ~25 ms GPU spike
            // over several frames per far tile); the far tiles draw with the layers like the near ones
            ter.basemapDistance = 100000f;
            ter.groupingID = r.group;
            ter.allowAutoConnect = false;   // (auto-connect re-links every terrain on each change: linked by hand, locally)
            ter.drawTreesAndFoliage = false;
            if (r.far) ter.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.TwoSided;
            if (terrainMaterial != null) ter.materialTemplate = terrainMaterial;
            t.terrain = ter;
            t.stage = t.alphas != null ? 2 : 3;
            Part(r.far ? "far create" : "create");
            if (r.far) t.holesDirty = true;   // (its holes: a stage of their own, next frames)
            else MarkFar(t.key);
            LinkAround(r, t.key);
            Part("link");
        }

        /// the neighbour links of a tile and the 4 round it (only those change when it comes or goes)
        static void LinkAround(Ring r, Vector2Int key)
        {
            Terrain N(Vector2Int k) => r.tiles.TryGetValue(k, out var o) ? o.terrain : null;
            foreach (var d in new[] { Vector2Int.zero, Vector2Int.left, Vector2Int.right, Vector2Int.up, Vector2Int.down })
            {
                var k = key + d;
                var ter = N(k);
                if (ter == null) continue;
                ter.SetNeighbors(N(k + Vector2Int.left), N(k + Vector2Int.up), N(k + Vector2Int.right), N(k + Vector2Int.down));
            }
        }

        /// stage 2: the splat layers
        void ApplySplat(Tile t)
        {
            if (t.alphas != null && t.terrain != null)
            {
                _psw.Restart();
                var td = t.terrain.terrainData;
                td.alphamapResolution = t.ring.splat;
                td.SetAlphamaps(0, 0, t.alphas);
                Part(t.ring.far ? "far splat" : "splat");
                GiveA(t.alphas);
            }
            t.alphas = null;
            t.stage = 3;
        }

        /// the far tile under a near tile needs its holes redone
        void MarkFar(Vector2Int nearKey)
        {
            int per = Mathf.RoundToInt(_far.size / _near.size);
            var fk = new Vector2Int(Mathf.FloorToInt((float)nearKey.x / per), Mathf.FloorToInt((float)nearKey.y / per));
            if (_far.tiles.TryGetValue(fk, out var f)) f.holesDirty = true;
        }

        bool[,] _solid;   // (Holes: reused, main thread)

        /// a far tile's holes: open where a near tile is drawn (Unity Terrain holes, one per heightmap cell)
        /// (perf experiments) skip cutting the far ring's holes
        public static bool debugNoHoles = false;

        void Holes(Tile ft)
        {
            if (ft.terrain == null) return;
            if (debugNoHoles) { ft.holesDirty = false; return; }
            ft.holesDirty = false;
            int cells = _far.res - 1, per = Mathf.RoundToInt(_far.size / _near.size), cellsPer = cells / per;
            if (_solid == null || _solid.GetLength(0) != cells) _solid = new bool[cells, cells];
            var solid = _solid;
            for (int j = 0; j < cells; j++) for (int i = 0; i < cells; i++) solid[j, i] = true;
            for (int nz = 0; nz < per; nz++)
                for (int nx = 0; nx < per; nx++)
                {
                    var nk = new Vector2Int(ft.key.x * per + nx, ft.key.y * per + nz);
                    if (!_near.tiles.TryGetValue(nk, out var n) || n.terrain == null) continue;
                    for (int j = nz * cellsPer; j < (nz + 1) * cellsPer; j++)
                        for (int i = nx * cellsPer; i < (nx + 1) * cellsPer; i++) solid[j, i] = false;
                }
            _psw.Restart();
            ft.terrain.terrainData.SetHoles(0, 0, solid);
            Part("holes");
        }

        /// the drawn surface at a sim point (the near tile's own interpolation of what it draws), NaN off the loaded
        /// near tiles. Main thread only (Unity's Terrain API).
        public double DrawnHeight(double x, double z)
        {
            if (_near == null) return double.NaN;
            var k = new Vector2Int(Mathf.FloorToInt((float)(x / _near.size)), Mathf.FloorToInt((float)(-z / _near.size)));
            if (!_near.tiles.TryGetValue(k, out var t) || t.terrain == null) return double.NaN;
            Vector3 u = GodotSpace.P(new Vector3((float)x, 0f, (float)z));
            return t.terrain.SampleHeight(u) + t.terrain.transform.position.y;
        }

        void Update()
        {
            if (Field == null || _near == null) return;
            long a0 = AllocProbe.Mark();
            Stream();
            AllocProbe.Add("world streaming", a0);
        }

        int _farGap;
        [Tooltip("frames between two far tiles' heights reaching the GPU (a 1024 m tile's upload is a GPU spike)")] public int farEvery = 6;

        void Stream()
        {
            if (_farGap > 0) _farGap--;
            var abs = FollowAbs();
            Request(_near, abs);
            Request(_far, abs);
            // one main-thread stage a frame: near before far, a tile's splat before a new tile
            var sw = Stopwatch.StartNew();
            bool did = Stage(_near) || Stage(_far);
            // a far tile's holes as a stage of their own (one a frame, never with a new tile)
            if (!did)
                foreach (var ft in _far.tiles.Values)
                    if (ft.holesDirty && ft.terrain != null) { Holes(ft); did = true; What("holes", ft.key); break; }
            if (did) Timed(sw.Elapsed.TotalMilliseconds);
            Drop(_near, abs);
            Drop(_far, abs);
        }

        void Request(Ring r, Vector3 abs)
        {
            var c = TileOf(r, abs);
            for (int d = 0; d <= r.radius; d++)   // nearest first
                for (int dz = -d; dz <= d; dz++)
                    for (int dx = -d; dx <= d; dx++)
                        if (Mathf.Max(Mathf.Abs(dx), Mathf.Abs(dz)) == d)
                            Want(r, new Vector2Int(c.x + dx, c.y + dz));
        }

        bool Stage(Ring r)
        {
            while (r.splatQ.Count > 0)
            {
                var s = r.splatQ.Dequeue();
                if (s.terrain != null) { ApplySplat(s); What(r.far ? "far splat" : "near splat", s.key); return true; }
            }
            if (r.objQ.Count > 0)
            {
                var o = r.objQ.Dequeue();
                if (r.tiles.TryGetValue(o.key, out var cur0) && cur0 == o)
                {
                    MakeObject(o);
                    if (o.stage == 2) r.splatQ.Enqueue(o);
                    What(r.far ? "far object" : "near object", o.key);
                    return true;
                }
                if (o.data != null) { Destroy(o.data); o.data = null; }
            }
            if (r.far && _farGap > 0) return false;   // far heights spaced out (each is a GPU upload spike)
            while (r.done.TryDequeue(out var t))
            {
                if (!r.tiles.TryGetValue(t.key, out var cur) || cur != t) { Recycle(t); continue; }   // dropped meanwhile
                MakeData(t);
                if (r.far) _farGap = farEvery;
                r.objQ.Enqueue(t);
                What(r.far ? "far heights" : "near heights", t.key);
                return true;
            }
            return false;
        }

        void Drop(Ring r, Vector3 abs)
        {
            var c = TileOf(r, abs);
            List<Vector2Int> drop = null;
            foreach (var kv in r.tiles)
            {
                var k = kv.Key;
                if (Mathf.Max(Mathf.Abs(k.x - c.x), Mathf.Abs(k.y - c.y)) > r.radius + 1 && kv.Value.stage >= 2)
                    (drop ??= new List<Vector2Int>()).Add(k);
            }
            if (drop == null) return;
            foreach (var k in drop)
            {
                var o = r.tiles[k];
                r.tiles.Remove(k);
                if (o.terrain != null) { Destroy(o.terrain.terrainData); Destroy(o.terrain.gameObject); o.terrain = null; }
                Recycle(o);
                if (!r.far) MarkFar(k);
                LinkAround(r, k);
            }
        }

        void Recycle(Tile t)
        {
            if (t.heights != null) { GiveH(t.heights); t.heights = null; }
            if (t.alphas != null) { GiveA(t.alphas); t.alphas = null; }
        }

        string _whatKind = "";
        Vector2Int _whatKey;
        void What(string kind, Vector2Int key) { _whatKind = kind; _whatKey = key; }
        /// (tests, logs) every stage over SLOW_MS: what it was, when, how many tiles there were
        public readonly List<string> SlowStages = new List<string>();
        const double SLOW_MS = 10.0;

        readonly (int frame, string kind, Vector2Int key, double ms)[] _hist = new (int, string, Vector2Int, double)[64];
        int _histN;

        /// (tests) the stages run in frames f0..f1 (what, ms), "" if none
        public string StagesIn(int f0, int f1)
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < System.Math.Min(_histN, _hist.Length); i++)
            {
                var h = _hist[(_histN - 1 - i) % _hist.Length];
                if (h.frame < f0) break;
                if (h.frame <= f1) sb.Insert(0, $"[f{h.frame} {h.kind} {h.key} {h.ms:0.0}] ");
            }
            return sb.ToString();
        }

        void Timed(double ms)
        {
            _hist[_histN++ % _hist.Length] = (Time.frameCount, _whatKind, _whatKey, ms);
            if (ms > SLOW_MS && SlowStages.Count < 20)
                SlowStages.Add($"{ms:0.0} ms {_whatKind} {_whatKey} (stage {_stages}, frame {Time.frameCount}, near {_near.tiles.Count} / far {_far.tiles.Count})");
            _stages++;
            _sumMs += ms;
            if (ms > _worstMs) _worstMs = ms;
            if (log && _stages % 40 == 0)
                Debug.Log($"WorldStreamer: {_stages} stages, avg {_sumMs / _stages:0.0} ms, worst {_worstMs:0.0} ms, near {_near.tiles.Count} / far {_far.tiles.Count} tiles | {StageReport}");
        }

        void OnDestroy()
        {
            foreach (var r in new[] { _near, _far })
                if (r != null)
                    foreach (var t in r.tiles.Values)
                        if (t.terrain != null) Destroy(t.terrain.terrainData);
            _forks?.Dispose();
        }
    }
}
