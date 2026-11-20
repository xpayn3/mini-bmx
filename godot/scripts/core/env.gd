class_name Env
## Test / probe flags (BMX_*) read once and cached: OS.get_environment is a system call plus a new String, and many
## per-frame code paths check a flag or two. Nothing sets the environment at runtime, so the first read holds.
## Main thread only (the cache is a plain Dictionary).

static var _c := {}

static func s(key: String) -> String:
	var v = _c.get(key)
	if v == null:
		v = OS.get_environment(key)
		_c[key] = v
	return v
