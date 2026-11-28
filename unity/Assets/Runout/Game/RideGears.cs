using System.Collections.Generic;
using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// Gears, chain and the rider's effort for one ride (Godot: Game._shift, BikeRig.chain, hud.gd's effort numbers).
    /// Q / E or LB / RB shift easier / harder into BikeSim.shift (the sim owns the cassette, the real drive ratio, spin-out
    /// and the chain skipping under load); the drawn chain follows the gear; one of the user's shifter recordings plays
    /// (Art/Audio/shifter). A stand-in readout (OnGUI) shows speed, gear, ratio, cadence, heart rate, power and stamina
    /// until the HUD is ported. Runs before SimHost so a shift lands before this frame's physics ticks.
    [DefaultExecutionOrder(-110)]
    public sealed class RideGears : MonoBehaviour
    {
        public BikeSim sim;
        public BikeChain chain;
        public InputReader input;
        public readonly RiderEffort effort = new RiderEffort();
        [Tooltip("the stand-in ride readout (speed, gear, cadence, heart rate, stamina)")] public bool showReadout = true;
        public AudioClip[] shiftClips;
        [Tooltip("the rear derailleur (Art/Models/Bikes/rd_sram.glb, tools/export_rd_sram.py) and its kinematics")]
        public GameObject derailleurModel;
        public TextAsset derailleurKinematics;

        AudioSource _src;
        int _lastClip = -1;
        string _msg; float _msgT;

        public void Init(BikeSim s, BikeRig rig, RiderView rider, InputReader inp)
        {
            sim = s; input = inp;
            if (rider != null) rider.effort = effort;
#if UNITY_EDITOR
            if (derailleurModel == null) derailleurModel = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Runout/Art/Models/Bikes/rd_sram.glb");
            if (derailleurKinematics == null) derailleurKinematics = UnityEditor.AssetDatabase.LoadAssetAtPath<TextAsset>("Assets/Runout/Art/Models/Bikes/rd_sram.extras.txt");
            if (shiftClips == null || shiftClips.Length == 0)
            {
                var l = new List<AudioClip>();
                for (int i = 0; i < 6; i++)
                {
                    var c = UnityEditor.AssetDatabase.LoadAssetAtPath<AudioClip>($"Assets/Runout/Art/Audio/shifter/shift_{i}.ogg");
                    if (c != null) l.Add(c);
                }
                shiftClips = l.ToArray();
            }
#endif
            if (rig != null) chain = BikeChain.Attach(rig, s, derailleurModel, derailleurKinematics != null ? derailleurKinematics.text : null);
            _src = gameObject.AddComponent<AudioSource>();
            _src.playOnAwake = false; _src.spatialBlend = 0f; _src.volume = 0.8f;
        }

        void Update()
        {
            if (sim == null) return;
            long a0 = AllocProbe.Mark();
            Tick();
            AllocProbe.Add("gears + effort", a0);
        }

        void Tick()
        {
            int d = input != null ? input.ShiftPressed() : 0;
            if (d != 0) Shift(d);
            effort.Update(sim, Time.deltaTime);
            if (_msgT > 0f) _msgT -= Time.unscaledDeltaTime;
            var kb = UnityEngine.InputSystem.Keyboard.current;
            if (kb != null && kb.f7Key.wasPressedThisFrame) ToggleDrivetrainCam();
        }

        /// F7: a close-up camera riding with the bike on the drive side, aimed at the derailleur + cassette + ring
        /// (judging the chain / derailleur sim); F7 again goes back to the ride camera
        Camera _dtCam, _mainCam;
        void ToggleDrivetrainCam()
        {
            if (chain == null) return;
            if (_dtCam != null)
            {
                Destroy(_dtCam.gameObject); _dtCam = null;
                if (_mainCam != null) _mainCam.enabled = true;
                return;
            }
            _mainCam = Camera.main;
            var model = chain.transform.parent;   // (the chain sits under the bike model)
            var go = new GameObject("drivetrain_cam");
            go.transform.SetParent(model, false);
            // Godot model space: behind-ish the BB, out on the drive side, looking at the rear axle area
            Vector3 eye = new Vector3(-0.18f, 0.42f, 0.62f), at = new Vector3(-0.30f, 0.31f, 0.05f);
            Vector3 fwd = GodotSpace.M(at - eye).normalized;
            go.transform.localPosition = GodotSpace.M(eye);
            go.transform.localRotation = Quaternion.LookRotation(fwd, Vector3.up);
            _dtCam = go.AddComponent<Camera>();
            _dtCam.fieldOfView = 38f; _dtCam.nearClipPlane = 0.02f;
            if (_mainCam != null) _mainCam.enabled = false;
        }

        /// d = +1 easier (a bigger cog), -1 harder (Godot gear_easier / gear_harder)
        public void Shift(int d)
        {
            if (!sim.geared) { Flash("SINGLE SPEED"); return; }
            if (!sim.shift(d)) { Flash(d > 0 ? "EASIEST GEAR" : "HARDEST GEAR"); return; }
            if (shiftClips != null && shiftClips.Length > 0)
            {
                int k = Random.Range(0, shiftClips.Length);
                if (k == _lastClip && shiftClips.Length > 1) k = (k + 1) % shiftClips.Length;   // (never the same twice in a row)
                _lastClip = k;
                _src.PlayOneShot(shiftClips[k]);
            }
        }

        void Flash(string s) { _msg = s; _msgT = 1.2f; }

        GUIStyle _st, _big, _rich;
        void OnGUI()
        {
            if (!showReadout || sim == null) return;
            if (_st == null)
            {
                _st = new GUIStyle(GUI.skin.label) { fontSize = 14 };
                _st.normal.textColor = Color.white;
                _big = new GUIStyle(_st) { fontSize = 28, fontStyle = FontStyle.Bold };
                _rich = new GUIStyle(_st) { richText = true };
            }
            var r = new Rect(16, Screen.height - 196, 260, 180);
            GUI.color = new Color(0f, 0f, 0f, 0.55f);
            GUI.DrawTexture(r, Texture2D.whiteTexture);
            GUI.color = Color.white;
            GUI.Label(new Rect(r.x + 10, r.y + 4, 240, 34), $"{System.Math.Abs(sim.v) * 3.6:0} km/h", _big);
            string gear = sim.geared && sim.gear >= 0
                ? $"GEAR {sim.cogs.Count - sim.gear}/{sim.cogs.Count}   {34.0 * sim.ring_k:0}x{sim.cogs[(int)sim.gear]:0}T   ratio {sim.drive_ratio():0.00}"
                : $"SINGLE SPEED   ratio {sim.drive_ratio():0.00}";
            GUI.Label(new Rect(r.x + 10, r.y + 40, 250, 20), gear, _st);
            GUI.Label(new Rect(r.x + 10, r.y + 60, 250, 20),
                $"{effort.cad:0} rpm   {effort.power:0} W" + (sim.chain_slip > 0 ? "   CHAIN SKIP" : "") + (sim.spin_out_k > 0.5 ? "   SPUN OUT" : ""), _st);
            float beat = Mathf.Pow(Mathf.Max(0f, Mathf.Sin(Time.time * (float)effort.hr / 60f * Mathf.PI * 2f)), 8f);
            GUI.Label(new Rect(r.x + 10, r.y + 80, 250, 20), $"<color=#{(beat > 0.5f ? "ff6070" : "ffffff")}>♥</color> {effort.hr:0} bpm   zone {effort.Zone}", _rich);
            GUI.Label(new Rect(r.x + 10, r.y + 102, 80, 20), "STAMINA", _st);
            var bar = new Rect(r.x + 90, r.y + 107, 150, 10);
            GUI.color = new Color(1f, 1f, 1f, 0.25f); GUI.DrawTexture(bar, Texture2D.whiteTexture);
            GUI.color = sim.tired ? new Color(0.85f, 0.2f, 0.29f) : (sim.sprint > 0.05 ? new Color(1f, 0.85f, 0.3f) : Color.white);
            GUI.DrawTexture(new Rect(bar.x, bar.y, bar.width * Mathf.Clamp01((float)sim.stamina), bar.height), Texture2D.whiteTexture);
            GUI.color = Color.white;
            if (chain != null)
            {
                var rd = chain.rd;
                GUI.Label(new Rect(r.x + 10, r.y + 124, 250, 20), $"chain {chain.Links} links  cage {rd.cage * 57.2958:0}°  {rd.tension:0} N", _st);
                GUI.Label(new Rect(r.x + 10, r.y + 142, 250, 20), chain.Problem != null ? "<color=#ff8080>MECH CAN'T RUN THIS CASSETTE</color>"
                    : $"bow top {rd.bowTop * 1000:0} mm  low {rd.bowLow * 1000:0} mm", _rich);
            }
            if (_msgT > 0f) GUI.Label(new Rect(r.x + 10, r.y - 30, 250, 28), _msg, _big);
        }
    }
}
