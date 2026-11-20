# Runout on Steam: release kit

Everything in the game is ready for Steam except what needs your Steamworks account or new art.
This folder: `upload.ps1` (export + upload), `scripts/` (SteamPipe build files), `icons/` (rendered from `godot/icon.svg`).

## What is already in the game

| | Where |
|---|---|
| Steamworks (Steamworks.NET 2024.8.0 + `steam_api64.dll`) | `godot/scripts/core/steam.gd` (autoload `Steam`), `SteamService.cs`, `godot/addons/steamworks/` |
| Runs with or without Steam (no crash when Steam is closed / missing) | `Steam.on` is false, every call does nothing |
| 20 achievements, unlocked from records, tricks and events | `Steam.ACHIEVEMENTS` (names + descriptions to type into Steamworks) |
| Rich presence ("Riding · Desert", "In the garage") | `Steam.presence()` |
| Credits + licences screen (title menu > CREDITS): credits, licence texts, Godot + its components | `godot/scripts/ui/credits_menu.gd` |
| No real brands in the game: every bike, part, tyre, helmet, sponsor name is made up | (old saves are converted when they load: `BikeBuild.rebrand()`) |
| Windows export preset: exe icon, version, no console window, licence files packed | `godot/export_presets.cfg`, `godot/icon.ico` |
| Version number in one place | `godot/project.godot` `application/config/version` (shown under the title menu) |

## Steps (in order)

1. **Steamworks account**: partner.steamgames.com, company / bank / tax forms, pay the $100 app fee.
   You get an **App ID**; the Windows depot is usually App ID + 1.
2. **Put the App ID in** (3 places):
   - `godot/scripts/core/steam.gd`: `APP_ID`, and set `RESTART_OUTSIDE_STEAM = true`
   - `godot/steam_appid.txt` (only for running from the editor / command line; not shipped)
   - `steam/scripts/app_build.vdf` (`AppID` + depot ID) and `depot_build.vdf` (`DepotID`)
3. **Steamworks > Installation > General**: launch option `Runout.exe`, OS Windows, 64-bit.
   **Installation > Redistributables**: none needed (.NET is inside the build).
4. **Achievements**: Steamworks > Stats & Achievements, one per entry in `Steam.ACHIEVEMENTS`
   (API name = the key, e.g. `AIR_3S`), plus a 256×256 icon (+ greyed-out version) each. Publish.
   Testing on App ID 480 (Spacewar) won't unlock ours: it has its own list.
5. **Steam Cloud** (Steamworks > Application > Steam Cloud > Auto-Cloud), quota ~50 MB / 200 files:
   - Root `WinAppDataRoaming`, subdirectory `Mini BMX`, patterns: `save.cfg`, `rider.cfg`, `garage.json`,
     `tune.cfg`, `tune_presets.cfg`, `light.cfg`, `freewheel.cfg`, `photo.cfg`, and `logos/*.png`.
   - Leave out `settings.cfg` (graphics, per PC), `screenshots/`, `ridelogs/`, `shader_cache/`, `vulkan/`, `logs/`.
6. **Export templates** (once): Godot editor > Editor > Manage Export Templates > Download (.NET 4.7.2).
7. **Build + upload**: `.\steam\upload.ps1 -User <your build account>` (needs steamcmd from the Steamworks SDK).
   Then Steamworks > SteamPipe > Builds > set it live on `default` (or a `beta` branch first).
8. **Store page**: see the art list below; the description, tags (Racing, Sports, Physics, Procedural
   Generation, Bike, Open World, Singleplayer), system requirements, **content survey**: frequent violence
   and gore (blood, torn-off limbs) - answer honestly; it sets the age gate. The page must be "Coming Soon"
   for 2 weeks before release; Valve reviews the page and the build (a few days each).
9. **Controller support**: tick "Full controller support" (Xbox) - every menu works on a pad (PadNav).
   Steam Deck: ask for a review once it runs there (text sizes!).
10. Release: set the price (Steamworks suggests regional prices), press Release.

## Store art to make

| Asset | Size |
|---|---|
| Header capsule | 920 × 430 |
| Small capsule | 462 × 174 |
| Main capsule | 1232 × 706 |
| Vertical capsule | 748 × 896 |
| Page background (optional) | 1438 × 810 |
| Library capsule | 600 × 900 |
| Library hero | 3840 × 1240 (no text) |
| Library logo | 1280 × 720 (transparent PNG) |
| Client icon | 32 × 32 (`icons/icon_32.png`), Community icon 184 × 184 (`icons/icon_184.png`) |
| Screenshots | at least 5, 1920 × 1080 (photo mode: O) |
| Trailer | MP4, 1080p |

Capsules must show the game name and (except the hero) no review quotes / award text.

## Still to fix before charging money (art / legal - can't be done in code)

These assets still show **real logos or real products**. Replace the art (or get a licence from the brand):

- `godot/assets/helmets/*` - the 6D ATR-2 and TLD SE5 helmet textures carry 6D, TLD, FXR and Oakley logos.
  Repaint the logos out of the textures, or drop those two helmets (the stock helmet is clean).
- ~~TV~~ done: the Magnavox / DVD / DTV / Dolby logos and the anime stickers are painted out of `godot/assets/tv/`
  (albedo, normal, ORM); the front now says VIDAVOX (made up) in the same place and style.
- `godot/assets/ui/xbox_pad.png` - photo of an Xbox controller (Settings > Controller). Without the file the
  game draws its own pad; Microsoft's guidelines allow button names (A / B / X / Y) but not their photos.
- `godot/assets/tues.glb`, `fuzz.glb` (+ their parts / forks / saddles / levers / rotors) and `dh.glb` are
  close copies of the YT Tues, NS Fuzz and GT Glory. Names are changed; the shapes can still count as
  trade dress. Lowest risk: change their silhouettes a little (tube shapes, linkage, graphics).
- `godot/assets/decals/fox_*.png`, `cinelli.png` - no longer used; delete them before release.
- `godot/assets/goggles/` - check the textures for brand marks.
- Made-up names to double-check: **CHARMIN** (bike computer) is Procter & Gamble's toilet paper brand,
  **NITRO** (knee pads / banner) and **APEX** (banner) are real brands. Rename if you want zero risk.
- `godot/scripts/ui/credits_menu.gd`: set `STUDIO` to your name / studio.

## Notes

- Player data is in `%APPDATA%\Mini BMX\` (the folder name is internal; renaming it would lose old saves).
- Test runs (`--autotest` etc.) don't start Steam; `BMX_STEAM=1` forces it, `BMX_NO_STEAM=1` keeps it off.
- Godot, .NET, Steamworks.NET and Debug Draw 3D are MIT: their notices are on the CREDITS screen, which
  satisfies the licences. The Goat DH frame is CC BY 4.0: credited there too.
