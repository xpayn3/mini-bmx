using Runout.Sim;
using UnityEngine;

namespace Runout.Game
{
    /// Places the drawn bike from the sim pose. Coordinate bridge: the sim uses the Godot convention
    /// (right-handed, y up, heading 0 = +x, + lean = left); Unity is left-handed (y up, z forward).
    /// We map sim (x, y, z) -> Unity (x, y, -z) and flip the handedness of rotations accordingly.
    public sealed class BikeView : MonoBehaviour
    {
        public Transform steer;   // the steering assembly's pivot (turns about its local up)

        public static Vector3 ToUnity(float x, float y, float z) => new Vector3(x, y, -z);

        public void Apply(in SimPose p)
        {
            transform.position = ToUnity(p.X, p.Y, p.Z);
            // Godot: forward = (cos h, 0, -sin h), + pitch = nose up, + lean / + steer = left (left = -z there).
            // Unity (z mirrored): forward = (cos h, 0, sin h) = yaw by -h; nose up = +a about z (x -> y);
            // left = +z, so lean left = +a about x (y -> z); steer left = -a about y (x -> +z).
            Quaternion yaw = Quaternion.AngleAxis(-p.Heading * Mathf.Rad2Deg, Vector3.up);
            Quaternion pitch = Quaternion.AngleAxis(p.Pitch * Mathf.Rad2Deg, Vector3.forward);
            Quaternion roll = Quaternion.AngleAxis(p.BikeLean * Mathf.Rad2Deg, Vector3.right);
            transform.rotation = yaw * pitch * roll;
            if (steer != null) steer.localRotation = Quaternion.AngleAxis(-p.Steer * Mathf.Rad2Deg, Vector3.up);
        }
    }
}
