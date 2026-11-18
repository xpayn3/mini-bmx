class_name WorldRng
extends RefCounted
## mulberry32 exactly as in the JS (same seed -> same stream), plus the JS int32 helpers.

var a: int = 0


func _init(seed_value: int = 0) -> void:
	a = i32(seed_value)


## JS ToInt32 of an (exact) integer value
static func i32(v: int) -> int:
	v = v & 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


## JS `f | 0` for a double
static func i32f(f: float) -> int:
	if is_nan(f) or is_inf(f):
		return 0
	return i32(int(f))


## Math.imul
static func imul(x: int, y: int) -> int:
	x &= 0xFFFFFFFF
	y &= 0xFFFFFFFF
	var lo: int = (x & 0xFFFF) * y
	var hi: int = ((x >> 16) * y) & 0xFFFF
	return i32(lo + (hi << 16))


## JS Math.round (half towards +inf)
static func jround(x: float) -> int:
	return int(floor(x + 0.5))


func next() -> float:
	a = i32(a + 0x6D2B79F5)
	var t: int = imul(a ^ ((a & 0xFFFFFFFF) >> 15), 1 | a)
	t = i32(t + imul(t ^ ((t & 0xFFFFFFFF) >> 7), 61 | t)) ^ t
	return float((t ^ ((t & 0xFFFFFFFF) >> 14)) & 0xFFFFFFFF) / 4294967296.0
