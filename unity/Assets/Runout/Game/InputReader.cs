using Runout.Sim;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Runout.Game
{
    /// Input System -> RideInput. Default layout = the Godot game's (MX vs ATV on PC): WASD the bike,
    /// arrows the rider's body (= the pad's right stick). Rebinding: InputActionRebindingExtensions later.
    public sealed class InputReader : MonoBehaviour
    {
        InputAction _pedal, _brake, _brakeF, _brakeR, _steer, _hop, _sprint, _body;
        bool _pad;

        void Awake()
        {
            _pedal = Axis("pedal", "<Keyboard>/w", "<Gamepad>/rightTrigger");
            _brake = Axis("brake", "<Keyboard>/s", "<Gamepad>/leftTrigger");
            _brakeF = Axis("brakeFront", "<Keyboard>/ctrl", null);
            _brakeR = Axis("brakeRear", "<Keyboard>/alt", null);
            _hop = Axis("hop", "<Keyboard>/space", "<Gamepad>/buttonWest");
            _sprint = Axis("sprint", "<Keyboard>/shift", "<Gamepad>/buttonSouth");

            _steer = new InputAction("steer", InputActionType.Value);
            _steer.AddCompositeBinding("1DAxis").With("Negative", "<Keyboard>/d").With("Positive", "<Keyboard>/a");
            _steer.AddBinding("<Gamepad>/leftStick/x").WithProcessor("invert");

            _body = new InputAction("body", InputActionType.Value);
            _body.AddCompositeBinding("2DVector")
                .With("Up", "<Keyboard>/upArrow").With("Down", "<Keyboard>/downArrow")
                .With("Left", "<Keyboard>/leftArrow").With("Right", "<Keyboard>/rightArrow");
            _body.AddBinding("<Gamepad>/rightStick");

            foreach (var a in new[] { _pedal, _brake, _brakeF, _brakeR, _steer, _hop, _sprint, _body }) a.Enable();
            InputSystem.onActionChange += (o, c) =>
            {
                if (c == InputActionChange.ActionPerformed && o is InputAction act && act.activeControl != null)
                    _pad = act.activeControl.device is Gamepad;
            };
        }

        static InputAction Axis(string name, string key, string pad)
        {
            var a = new InputAction(name, InputActionType.Value);
            a.AddBinding(key);
            if (pad != null) a.AddBinding(pad);
            return a;
        }

        public RideInput Read()
        {
            Vector2 body = _body.ReadValue<Vector2>();
            var g = Gamepad.current;
            return new RideInput
            {
                throttle = _pedal.ReadValue<float>(),
                brake = _brake.ReadValue<float>(),
                brake_front = _brakeF.ReadValue<float>(),
                brake_rear = _brakeR.ReadValue<float>(),
                steer = Mathf.Clamp(_steer.ReadValue<float>(), -1f, 1f),
                hop = _hop.ReadValue<float>() > 0.5f,
                sprint = _sprint.ReadValue<float>() > 0.5f,
                body_fwd = body.y,
                body_lean = -body.x,
                left_back = g != null ? Mathf.Max(0f, -g.leftStick.ReadValue().y) : 0f,
                pad = _pad,
            };
        }

        void OnDestroy()
        {
            foreach (var a in new[] { _pedal, _brake, _brakeF, _brakeR, _steer, _hop, _sprint, _body }) a?.Dispose();
        }
    }
}
