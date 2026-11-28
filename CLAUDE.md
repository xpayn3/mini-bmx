# Mini BMX / Runout — PC game, being ported from Godot to Unity

- **`unity/`** = the game from now on (Unity 6.3 LTS, HDRP). Read **[unity/PORTING.md](unity/PORTING.md)** first:
  layout, the engine-plug rule (bike / rider / ragdoll / terrain = our own pure C# in `Runout.Sim`; Unity tech for
  skeletons, animation, rendering, input, cameras), port order and status.
- **`godot/`** = the reference: the original game, still runnable. Port from it, don't develop features there.
  **[godot/HANDOFF.md](godot/HANDOFF.md)** explains how every system works, lessons learned and the user's preferences
  (those preferences still apply).
- `tools/` = Houdini / Blender exporters (they write into `godot/assets/`; copy into `unity/Assets/Runout/Art/`).

@unity/PORTING.md
@godot/HANDOFF.md
