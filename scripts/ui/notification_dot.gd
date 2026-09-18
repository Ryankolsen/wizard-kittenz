class_name NotificationDot
extends Label

# Reusable notification dot (#621, PRD #620). This is the deep module for
# the whole "notification dot consolidation" effort: it knows nothing about
# StatBadge, AchievementBadge, CharacterData, or any other game-specific
# class. Given a zero-arg Callable returning bool, it mirrors that return
# value as its own `visible` state every frame — matching the polling
# cadence already used by StatsTabBadge/AchievementBadge (both re-checked
# every frame via their owning screen's _process).
#
# Later slices (#622-#625) instantiate notification_dot.tscn in the Stats
# tab, Achievements tab, Character button, and HUD pause button, each
# binding their own predicate and positioning the instance themselves —
# this scene has no positioning/anchoring opinion beyond Control/Label
# defaults.

var _predicate: Callable

func _ready() -> void:
	visible = false

func bind_predicate(predicate: Callable) -> void:
	_predicate = predicate
	_poll()

func _process(_delta: float) -> void:
	_poll()

func _poll() -> void:
	if not _predicate.is_valid():
		visible = false
		return
	visible = _predicate.call()
