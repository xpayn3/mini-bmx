using System.Collections.Generic;
using Runout.Config;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// Builds a ride in a scene: BikeSim (godot/sim, the ride physics shared with Godot, untouched) on this scene's
    /// ground, plugged into the SimHost. The DH's numbers until bikes / the garage are ported: geometry = dh.glb's
    /// extras (as godot/tools/slope_stress.gd uses them), the stock cassette, the stock suspension setup.
    [RequireComponent(typeof(SimHost))]
    public sealed class RideBootstrap : MonoBehaviour
    {
        public Terrain ground;
        [Tooltip("the bike model's extras (Art/Models/Bikes/<bike>.extras.txt, from unity/Tools/glb_extras.py)")]
        public TextAsset bikeExtras;
        [Tooltip("the ride setup as Godot rides it (Config/Rides/<bike>.ride.txt, from godot/tools/port_trace.tscn ride_out=)")]
        public TextAsset rideConfig;
        [Tooltip("the rider: any Humanoid model (Art/Characters, imported as Humanoid by CharacterImport)")]
        public GameObject riderModel;
        [Tooltip("its colour texture, for HDRP materials when the model's own are for another pipeline")]
        public Texture2D riderAlbedo;
        public Vector3 spawn = new Vector3(0f, 0f, 0f);
        [Tooltip("degrees: 0 = along +x (the sim's heading)")] public float heading = 0f;

        public BikeSim Sim { get; private set; }
        public Tune Tune { get; private set; }

        void Start()
        {
#if UNITY_EDITOR
            OnValidate();   // (the extras / ride files, if the scene was saved before they existed)
#endif
            // the test playground when the scene has one (its course is the ground), else the scene's terrain
            var playground = FindFirstObjectByType<PlaygroundWorld>();
            if (playground != null && playground.Course == null) playground.Rebuild();
            IGround g = playground != null ? playground.Ground : new TerrainGround(ground != null ? ground : Terrain.activeTerrain);
            var host = new RideHost(g);
            // the ride as Godot rides the DH (Config/Rides/dh.ride.txt, from godot/tools/port_trace.tscn ride_out=): the
            // effective Tune values (the player's sliders x the bike's multipliers) and the bike config. None: Tune defaults
            var ride = BikeExtras.Parse(rideConfig != null ? rideConfig.text : "");
            Tune = new Tune();
            var tv = new Dictionary<string, double>();
            foreach (var row in TuneDefs.Rows) if (ride.has("tune." + row.key)) tv[row.key] = ride.f("tune." + row.key);
            foreach (var k in Tune.FOLLOW.Keys) if (ride.has("tune." + k)) tv[k] = ride.f("tune." + k);
            if (tv.Count > 0) Tune.set_effective(tv);
            Sim = new BikeSim(host);
            host.sim = Sim;
            Sim.T = Tune.fill(new RideParams());

            // the bike model + its numbers (the glb's extras) -> the drawn rig, and the same geometry for the physics
            var sh = GetComponent<SimHost>();
            BikeExtras bx = BikeExtras.Parse(bikeExtras != null ? bikeExtras.text : "");
            BikeRig rig = null;
            Transform bikeObj = sh.bikeView != null ? sh.bikeView.transform : null;
            Transform model = bikeObj != null ? BikeRig.Find(bikeObj, bx.root) : null;
            if (model != null && bikeExtras != null)
            {
                rig = new BikeRig(model, bx);
                if (rig.susp != null) host.drawnSusp = new SuspAdapter(rig.susp);
            }
            var extras = new GdDict();
            extras["wheelbase"] = bx.f("wheelbase", 1.2557); extras["wheelRadius"] = bx.f("wheelRadius", 0.374);
            extras["wheelRadiusRear"] = bx.f("wheelRadiusRear", 0.355); extras["bbToRearAxle"] = bx.f("bbToRearAxle", 0.4423);
            var mods = new GdDict();
            var cogs = new List<double>();
            if (ride.has("cogs")) foreach (var c in ride.list("cogs")) cogs.Add(c);
            else cogs.AddRange(new double[] { 11, 12, 14, 16, 18, 21, 24 });
            mods.set("cogs", cogs);
            mods["ring_k"] = ride.f("ring_k", 1.0); mods["land"] = ride.f("mods_land", 1.0);
            if (ride.has("susp.f.travel"))
            {
                var su = new SusSetup { empty = false };
                int i = 0;
                foreach (var e in new[] { "f", "r" })
                    foreach (var k in new[] { "travel", "sag", "prog", "zc", "zr", "hs", "fric", "bump" }) su.u[i++] = ride.f("susp." + e + "." + k);
                su.u[16] = ride.f("susp.psi_f", 23.0); su.u[17] = ride.f("susp.psi_r", 26.0);
                mods.set("susp", su);
            }
            else mods.set("susp", SuspSetup.resolve(null, SuspSetup.DEFAULT_SHOCK, "air", null).to_sim());
            var cfg = new GdDict();
            cfg["land"] = ride.f("land", 1.0); cfg.set("geared", ride.f("geared", 1.0) != 0.0); cfg.set("mods", mods);
            Sim.setup(extras, cfg);
            if (playground != null)
            {
                V3 s = playground.Spawn();   // (x, heading, z) in sim coordinates
                Sim.reset_at(s.x, s.z, s.y);
            }
            else Sim.reset_at(spawn.x, -spawn.z, heading * Mathf.Deg2Rad);
            sh.Attach(new BikeSimStep(Sim, host));
            if (rig != null)
            {
                var draw = bikeObj.gameObject.AddComponent<BikeDraw>();
                draw.Init(Sim, g, rig, sh.Stepper);
                sh.drawer = draw;
                // the crash: our crashed-bike body (and the ragdoll, hooked by the rider below)
                var crashView = new CrashView(Sim, rig, g);
                host.crash = crashView;
                draw.crash = crashView;
                // the rider: a Humanoid model posed by our solver (RiderView)
                if (riderModel != null)
                {
                    var go = Instantiate(riderModel);
                    go.name = "Rider";
                    RiderView.HdrpMaterials(go, riderAlbedo);
                    var anim = go.GetComponentInChildren<Animator>();
                    if (anim == null) anim = go.AddComponent<Animator>();
                    anim.runtimeAnimatorController = null;   // (no clips: our pose drives the bones)
                    anim.applyRootMotion = false;
                    var rv = bikeObj.gameObject.AddComponent<RiderView>();
                    rv.Init(Sim, rig, anim);
                    draw.rider = rv;
                    rv.HookCrash(host, crashView);
                }
            }
            else Debug.LogWarning("RideBootstrap: no bike extras / model found: the bike is drawn as one rigid piece");
        }

        /// bail (Godot: the bail key held BAIL_HOLD_MS = a crash on purpose): hold F / pad B
        float _bailHeld;
        const float BAIL_HOLD = 0.35f;
        void Update()
        {
            if (Sim == null) return;
            var kb = UnityEngine.InputSystem.Keyboard.current;
            var gp = UnityEngine.InputSystem.Gamepad.current;
            bool down = (kb != null && kb.fKey.isPressed) || (gp != null && gp.buttonEast.isPressed);
            _bailHeld = down ? _bailHeld + Time.unscaledDeltaTime : 0f;
            if (_bailHeld >= BAIL_HOLD && !Sim.crash_on && Sim.crash_pending == "")
            {
                Sim.crash_pending = "BAIL!";
                _bailHeld = -999f;   // (once per hold)
            }
        }

#if UNITY_EDITOR
        void OnValidate()
        {
            if (bikeExtras == null)
                bikeExtras = UnityEditor.AssetDatabase.LoadAssetAtPath<TextAsset>("Assets/Runout/Art/Models/Bikes/dh.extras.txt");
            if (rideConfig == null)
                rideConfig = UnityEditor.AssetDatabase.LoadAssetAtPath<TextAsset>("Assets/Runout/Config/Rides/dh.ride.txt");
            if (riderModel == null)
                riderModel = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Runout/Art/Characters/UnityDefaultMale/DefaultMale.fbx");
            if (riderAlbedo == null)
                riderAlbedo = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Runout/Art/Characters/UnityDefaultMale/DefaultMale_Albedo_Light.png");
        }
#endif
    }
}
