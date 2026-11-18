# Mini BMX — Godot 4 PC version

A port of the three.js web game (`../src`, `../index.html`) to **Godot 4.7** (GDScript, Forward+).

## Run

- Open the editor: `C:\Users\Luka\Godot\Godot_v4.7.2-stable_win64.exe --path godot -e`, then F5.
- Play straight away: `C:\Users\Luka\Godot\Godot_v4.7.2-stable_win64.exe --path godot`
- Skip the title screen: add `-- --ride`.
- Unattended smoke test (rides 10 s, prints FPS / state, quits): `..._console.exe --path godot -- --autotest=10`

Graphics, quality presets, frame times and test flags (`--bench`, `--showcase`, `--quality`): see
[docs/GRAPHICS.md](docs/GRAPHICS.md). Photo mode: O.

## Build a standalone .exe

Install the export templates once (Editor → Manage Export Templates → Download), then
`..._console.exe --headless --path godot --export-release "Windows Desktop" build/windows/MiniBMX.exe`.

## Layout

| Folder | What |
|---|---|
| `scripts/core` | autoloads: `Settings` (graphics, controls, rebinding, saved to `user://settings.cfg`), `Tune` (ride feel, `user://tune.cfg`), `GameState` (bikes, seed, records, `user://save.cfg`) |
| `scripts/bike` | `bike_physics.gd` (the ride, 1:1 port of `physics()` in main.js at a fixed 120 Hz), `bike_rig.gd` (model, pedals, grips), suspension, paint, decals |
| `scripts/rider` | procedural rider + ragdoll |
| `scripts/world` | procedural terrain, trails, jumps, obstacles, water |
| `scripts/fx` | dust, dirt chunks, tyre tracks |
| `scripts/game` | `game.gd` (one ride), `camera_rig.gd` (all camera presets), `ride_audio.gd` (procedural sound) |
| `scripts/ui` | HUD, menus, settings, tune panel |

Player data lives in `%APPDATA%\Godot\app_userdata\Mini BMX\` (screenshots: F12 → `screenshots/`).

The web version's bike builder (U) is intentionally left out of the PC version.
