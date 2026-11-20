using Godot;
using Steamworks;
using System;

/// Steam (Steamworks.NET): start-up, the overlay's callbacks, achievements and the player's name.
/// Made by `steam.gd` (autoload `Steam`) only in the C# build; every call is safe when Steam isn't running:
/// the game then plays as normal and nothing is unlocked.
/// The App ID lives in steam.gd (APP_ID) and `steam_appid.txt` (dev runs outside the Steam client only).
[GlobalClass]
public partial class SteamService : RefCounted
{
	static bool _resolver;

	/// Godot loads our assemblies in its own load context, which doesn't look next to them for native DLLs:
	/// find steam_api64.dll by hand (beside the assembly in an export, beside the exe, or in addons/steamworks).
	static void HookResolver()
	{
		if (_resolver) return;
		_resolver = true;
		System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(typeof(SteamAPI).Assembly, (name, asm, path) =>
		{
			if (!name.StartsWith("steam_api")) return IntPtr.Zero;
			string file = name.EndsWith(".dll") ? name : name + ".dll";
			string[] dirs = {
				System.IO.Path.GetDirectoryName(asm.Location) ?? "",
				System.IO.Path.GetDirectoryName(typeof(SteamService).Assembly.Location) ?? "",
				System.IO.Path.GetDirectoryName(OS.GetExecutablePath()) ?? "",
				ProjectSettings.GlobalizePath("res://addons/steamworks"),
			};
			foreach (var d in dirs)
			{
				if (d == "") continue;
				var p = System.IO.Path.Combine(d, file);
				if (System.IO.File.Exists(p) && System.Runtime.InteropServices.NativeLibrary.TryLoad(p, out IntPtr h)) return h;
			}
			return IntPtr.Zero;
		});
	}

	public SteamService() { HookResolver(); }

	public bool Ready { get; private set; }
	public string Error { get; private set; } = "";
	bool _dirty;   // achievements set but not stored yet

	/// Returns true when the game should quit because Steam will relaunch it (release builds started outside Steam).
	public bool RestartIfNeeded(long appId)
	{
		try { return SteamAPI.RestartAppIfNecessary(new AppId_t((uint)appId)); }
		catch (Exception e) { Error = e.Message; return false; }   // no steam_api64.dll: carry on without Steam
	}

	public bool Init()
	{
		if (Ready) return true;
		try
		{
			if (!Packsize.Test() || !DllCheck.Test()) { Error = "steam_api64.dll does not match Steamworks.NET"; return false; }
			Ready = SteamAPI.Init();
			if (!Ready) Error = "SteamAPI.Init failed (Steam not running, or no steam_appid.txt)";
		}
		catch (Exception e) { Error = e.Message; Ready = false; }
		return Ready;
	}

	/// once a frame: Steam's callbacks (overlay, stats) + store unlocked achievements
	public void Tick()
	{
		if (!Ready) return;
		SteamAPI.RunCallbacks();
		if (_dirty) { _dirty = !SteamUserStats.StoreStats(); }
	}

	public void Shutdown()
	{
		if (!Ready) return;
		if (_dirty) SteamUserStats.StoreStats();
		SteamAPI.Shutdown();
		Ready = false;
	}

	public string PlayerName() => Ready ? SteamFriends.GetPersonaName() : "";
	public string Language() => Ready ? SteamApps.GetCurrentGameLanguage() : "";
	public bool OnDeck() => Ready && SteamUtils.IsSteamRunningOnSteamDeck();

	public bool Unlock(string id)
	{
		if (!Ready) return false;
		if (SteamUserStats.GetAchievement(id, out bool got) && got) return false;
		if (!SteamUserStats.SetAchievement(id)) return false;   // not set up in Steamworks (yet)
		_dirty = true;
		return true;
	}

	public bool Has(string id) => Ready && SteamUserStats.GetAchievement(id, out bool got) && got;

	/// dev only: clears every achievement (Steamworks > Stats & Achievements must list them)
	public void ResetAll()
	{
		if (!Ready) return;
		SteamUserStats.ResetAllStats(true);
		_dirty = true;
	}

	public void SetRichPresence(string key, string value)
	{
		if (Ready) SteamFriends.SetRichPresence(key, value);
	}
}
