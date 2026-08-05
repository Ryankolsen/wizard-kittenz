class_name IdleTracker
extends RefCounted

# Pure elapsed-time accumulator backing "Nap Time" (issue #472). Scene-tree-
# free by design (RefCounted, driven by an externally-supplied delta) so it
# can be unit tested without booting Player/SceneTree, matching
# AchievementService's own scene-tree-free convention. Any input activity
# resets the accumulator, mirroring a real idle timer.

const IDLE_THRESHOLD_SECONDS: float = 300.0

var _elapsed: float = 0.0
var _fired: bool = false

# Advances the tracker by delta seconds. Returns true exactly once, the
# frame the idle threshold is first crossed; false otherwise (including
# every frame after that until input_active resets the tracker).
func advance(delta: float, input_active: bool) -> bool:
	if input_active:
		_elapsed = 0.0
		_fired = false
		return false
	_elapsed += delta
	if not _fired and _elapsed >= IDLE_THRESHOLD_SECONDS:
		_fired = true
		return true
	return false
