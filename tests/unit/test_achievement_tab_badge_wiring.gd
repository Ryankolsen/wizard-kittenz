extends GutTest

# Scene-level wiring tests for the Achievements-tab notification dot (#623,
# PRD #620). The reusable NotificationDot component's own poll/predicate
# contract is covered by test_notification_dot.gd; this file pins that the
# pause menu instances one as AchievementsTabBadge under AchievementsTabButton
# and binds it to AchievementBadge.should_show(service.account.achievement_state)
# via _resolve_achievement_service(), mirroring test_achievement_tab.gd's
# bind_achievement_service injection pattern.

func _service_with_state(state: Dictionary) -> AchievementService:
	var account := AccountSaveData.new()
	account.achievement_state = state
	return AchievementService.new(account)

func test_badge_node_exists_and_starts_hidden():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var badge = scene.find_child("AchievementsTabBadge", true, false)
	assert_not_null(badge, "pause_menu.tscn must contain a node named AchievementsTabBadge")
	assert_true(badge is NotificationDot, "AchievementsTabBadge must be a NotificationDot instance")
	var tab_button = scene.find_child("AchievementsTabButton", true, false)
	assert_eq(badge.get_parent(), tab_button, "AchievementsTabBadge must be a child of AchievementsTabButton")
	assert_false(badge.visible, "badge starts hidden before any service is bound")
	scene.free()

func test_badge_visible_with_one_unclaimed_achievement():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_service_with_state({"some_id": {"claimed": false}}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("AchievementsTabBadge", true, false)
	assert_not_null(badge)
	assert_true(badge.visible, "badge must be visible while an unlocked achievement is unclaimed")

func test_badge_hidden_when_all_claimed():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_service_with_state({"some_id": {"claimed": true}}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("AchievementsTabBadge", true, false)
	assert_not_null(badge)
	assert_false(badge.visible, "badge must hide once every unlocked achievement is claimed")

func test_badge_hidden_with_empty_achievement_state():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_service_with_state({}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("AchievementsTabBadge", true, false)
	assert_not_null(badge)
	assert_false(badge.visible, "badge must stay hidden with no achievements unlocked at all")

func test_badge_updates_live_when_achievement_is_claimed():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	var service := _service_with_state({"some_id": {"claimed": false}})
	scene.bind_achievement_service(service)
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("AchievementsTabBadge", true, false)
	assert_true(badge.visible, "badge starts visible while the achievement is unclaimed")
	service.account.achievement_state["some_id"]["claimed"] = true
	await get_tree().process_frame
	assert_false(badge.visible, "badge must hide within one frame of the achievement being claimed")
