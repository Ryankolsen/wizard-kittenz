extends GutTest

# Component tests for the reusable NotificationDot (#621, PRD #620). This
# is the deep module for the whole PRD — a Control that mirrors a bound
# zero-arg boolean Callable's return value as its own visibility, with no
# knowledge of StatBadge/AchievementBadge/CharacterData. Later slices (#622-
# #625) instantiate this same scene in each of the four screens; this file
# only pins the standalone contract.

func test_bound_predicate_true_becomes_visible_after_a_frame():
	var scene = load("res://scenes/ui/notification_dot.tscn").instantiate()
	add_child_autofree(scene)
	scene.bind_predicate(func(): return true)
	await get_tree().process_frame
	assert_true(scene.visible, "visible must mirror a predicate returning true")

func test_starts_hidden_before_any_bind():
	var scene = load("res://scenes/ui/notification_dot.tscn").instantiate()
	assert_false(scene.visible, "must start hidden before any predicate is bound")
	scene.free()

func test_stays_hidden_with_no_predicate_even_after_ticking():
	var scene = load("res://scenes/ui/notification_dot.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_false(scene.visible, "no predicate bound — must remain hidden after a frame")

func test_bound_predicate_false_stays_hidden():
	var scene = load("res://scenes/ui/notification_dot.tscn").instantiate()
	add_child_autofree(scene)
	scene.bind_predicate(func(): return false)
	await get_tree().process_frame
	assert_false(scene.visible, "visible must mirror a predicate returning false")

func test_updates_live_when_condition_changes():
	var scene = load("res://scenes/ui/notification_dot.tscn").instantiate()
	add_child_autofree(scene)
	# GDScript lambdas capture local variables by value, not by reference, so
	# a reassigned local bool would not be visible to an already-created
	# Callable. Box the flag in a single-element Array (a reference type) so
	# the predicate reads the live value on every call, matching how a real
	# predicate (e.g. StatBadge.should_show reading CharacterData) observes
	# state that mutates after the Callable is created.
	var flag := [false]
	scene.bind_predicate(func(): return flag[0])
	await get_tree().process_frame
	assert_false(scene.visible, "must be hidden while flag is false")
	flag[0] = true
	await get_tree().process_frame
	assert_true(scene.visible, "must become visible within one subsequent process frame of the flag flipping true")

func test_rebinding_predicate_replaces_the_old_one():
	var scene = load("res://scenes/ui/notification_dot.tscn").instantiate()
	add_child_autofree(scene)
	scene.bind_predicate(func(): return false)
	await get_tree().process_frame
	scene.bind_predicate(func(): return true)
	await get_tree().process_frame
	assert_true(scene.visible, "re-binding must replace the old predicate, not stack with it")
