using UnityEngine;

namespace Runout.Game
{
    /// Stand-in chase camera until the camera rig (CameraRig / TrailView) is ported onto Cinemachine:
    /// behind and above the bike along its heading, smoothed. Godot chase: distance 4.2 m, pitch 17 deg.
    public sealed class ChaseCamera : MonoBehaviour
    {
        public Transform target;
        public float distance = 4.2f, height = 1.6f, lookUp = 0.8f, follow = 4.5f;

        void LateUpdate()
        {
            if (target == null) return;
            Vector3 fwd = target.right;   // the bike's forward is its local +x (the sim's convention)
            fwd.y = 0f;
            if (fwd.sqrMagnitude < 1e-4f) fwd = Vector3.right;
            fwd.Normalize();
            Vector3 want = target.position - fwd * distance + Vector3.up * height;
            float k = 1f - Mathf.Exp(-follow * Time.deltaTime);
            transform.position = Vector3.Lerp(transform.position, want, k);
            transform.rotation = Quaternion.LookRotation(target.position + Vector3.up * lookUp - transform.position, Vector3.up);
        }
    }
}
