using UnityEngine;
using UnityEngine.InputSystem;

namespace Runout.Game
{
    /// Stand-in chase camera until the camera rig (CameraRig / TrailView) is ported onto Cinemachine:
    /// behind and above the bike along its heading, smoothed. Godot chase: distance 4.2 m, pitch 17 deg.
    /// Mouse (like the Godot ride camera): right button + drag orbits round the bike, the wheel zooms, and after letting
    /// go it eases back behind the bike (V toggles keeping the view you set).
    public sealed class ChaseCamera : MonoBehaviour
    {
        public Transform target;
        public float distance = 4.2f, height = 1.6f, lookUp = 0.8f, follow = 4.5f;
        [Tooltip("degrees per pixel of mouse drag")] public float orbitSpeed = 0.25f;
        [Tooltip("s after letting go before the view eases back behind the bike")] public float recentreAfter = 1.5f;
        public float recentreRate = 2.0f;

        float _yaw, _pitch, _zoom = 1f, _idle = 99f;
        bool _hold;
        BikeDraw _draw;

        void LateUpdate()
        {
            if (target == null) return;
            long a0 = AllocProbe.Mark();
            Follow();
            AllocProbe.Add("chase camera", a0);
        }

        void Follow()
        {
            ReadMouse();

            // follow the DRAWN bike (BikeDraw moves the model, not the Bike object); without one, the target itself
            if (_draw == null) _draw = target.GetComponentInChildren<BikeDraw>();
            bool drawn = _draw != null && _draw.HasFollow;
            Vector3 tp = drawn ? _draw.FollowPos : target.position;
            Vector3 fwd = drawn ? _draw.FollowFwd : target.right;   // (the sim's forward = the Bike object's local +x)
            fwd.y = 0f;
            if (fwd.sqrMagnitude < 1e-4f) fwd = Vector3.right;
            fwd.Normalize();
            // the orbit: turned round the bike by _yaw, raised by _pitch
            Vector3 back = Quaternion.AngleAxis(_yaw, Vector3.up) * -fwd;
            float d = distance * _zoom;
            float pitch = Mathf.Atan2(height, distance) * Mathf.Rad2Deg + _pitch;
            Vector3 off = back * (d * Mathf.Cos(pitch * Mathf.Deg2Rad)) + Vector3.up * (d * Mathf.Sin(pitch * Mathf.Deg2Rad));
            Vector3 want = tp + off;
            bool dragging = _idle == 0f;
            float k = dragging ? 1f : 1f - Mathf.Exp(-follow * Time.unscaledDeltaTime);
            transform.position = Vector3.Lerp(transform.position, want, k);
            transform.rotation = Quaternion.LookRotation(tp + Vector3.up * lookUp - transform.position, Vector3.up);
        }

        void ReadMouse()
        {
            var m = Mouse.current;
            float dt = Time.unscaledDeltaTime;
            if (Keyboard.current != null && Keyboard.current.vKey.wasPressedThisFrame) _hold = !_hold;
            if (m != null && m.rightButton.isPressed)
            {
                Vector2 dlt = m.delta.ReadValue();
                _yaw += dlt.x * orbitSpeed;
                _pitch = Mathf.Clamp(_pitch - dlt.y * orbitSpeed, -15f, 70f);
                _idle = 0f;
            }
            else _idle += dt;
            if (m != null)
            {
                float wheel = m.scroll.ReadValue().y;
                // (a notch reads as 1 or 120 depending on the Input System's scroll setting: only its direction counts)
                if (wheel != 0f) _zoom = Mathf.Clamp(_zoom * (wheel > 0f ? 0.9f : 1.111f), 0.35f, 6f);
            }
            // ease back behind the bike a while after letting go (unless held with V)
            if (!_hold && _idle > recentreAfter)
            {
                float e = 1f - Mathf.Exp(-recentreRate * dt);
                _yaw = Mathf.LerpAngle(_yaw, 0f, e);
                _pitch = Mathf.Lerp(_pitch, 0f, e);
            }
        }
    }
}
