class_name SpawnPositionSpreader
extends RefCounted

# Pure spawn-position spreader (#372). Given a room's world-space origin / size
# and a mob count, returns N distinct, in-bounds, non-overlapping positions.
#
# Contract:
#   - count == 0       -> []
#   - count == 1       -> [room center]   (preserves single-mob behavior)
#   - count >= 2       -> N positions inside (origin, size), each pair separated
#                         by at least MIN_SEPARATION_PX, with EDGE_PADDING_PX
#                         from the walls so mobs aren't pinned to corners.
#
# Deterministic: same (origin, size, count) -> same positions. The RNG is
# seeded from the inputs so callers don't need to thread a seed through.
# A best-effort rejection-sampling pass tries MAX_ATTEMPTS placements per slot;
# if it can't satisfy the separation, a deterministic ring around the center
# fills the remainder so the spawner never sees a short list.

const MIN_SEPARATION_PX: float = 40.0
const EDGE_PADDING_PX: float = 24.0
const MAX_ATTEMPTS: int = 200

static func spread(origin: Vector2, size: Vector2, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var center: Vector2 = origin + size * 0.5
	if count == 1:
		out.append(center)
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = _derive_seed(origin, size, count)

	var inner_origin: Vector2 = origin + Vector2(EDGE_PADDING_PX, EDGE_PADDING_PX)
	var inner_size: Vector2 = size - Vector2(EDGE_PADDING_PX * 2.0, EDGE_PADDING_PX * 2.0)
	if inner_size.x <= 0.0 or inner_size.y <= 0.0:
		inner_origin = origin
		inner_size = size

	var attempts := MAX_ATTEMPTS
	while out.size() < count and attempts > 0:
		attempts -= 1
		var p := Vector2(
			inner_origin.x + rng.randf() * inner_size.x,
			inner_origin.y + rng.randf() * inner_size.y,
		)
		var ok := true
		for q in out:
			if p.distance_to(q) < MIN_SEPARATION_PX:
				ok = false
				break
		if ok:
			out.append(p)

	# Deterministic ring fallback if rejection sampling exhausted attempts
	# without filling every slot. Keeps the contract that we always return N
	# positions even in a pathologically small room.
	while out.size() < count:
		var idx := out.size()
		var angle := TAU * float(idx) / float(count)
		var radius: float = minf(inner_size.x, inner_size.y) * 0.35
		out.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return out

# Seed derivation: hash the input tuple so identical inputs map to identical
# seeds across runs. We use abs() to avoid negative seeds (Godot RNG accepts
# them but the readable form in logs is friendlier as positive).
static func _derive_seed(origin: Vector2, size: Vector2, count: int) -> int:
	return abs(hash([origin.x, origin.y, size.x, size.y, count]))
