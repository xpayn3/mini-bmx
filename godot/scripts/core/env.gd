class_name Env
## Test / probe flags (BMX_*) read once and cached: OS.get_environment is a system call plus a new String, and many
## per-frame code paths check a flag or two. Nothing sets the environment at runtime, so the first read holds.
## Main thread only (the cache is a plain Dictionary).
## Release builds (Dev.on false) read none of them: every flag is "" there, so no test switch reaches a player.

static var _c := {}

static func s(key: String) -> String:
	var v = _c.get(key)
	if v == null:
		v = OS.get_environment(key) if Dev.on else ""
		_c[key] = v
	return v

## the same without the cache: safe on worker threads and in static initialisers ("" in a release build)
static func raw(key: String) -> String:
	return OS.get_environment(key) if Dev.on else ""
