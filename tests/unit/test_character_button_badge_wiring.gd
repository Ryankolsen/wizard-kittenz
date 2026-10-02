extends GutTest

# Scene-level wiring tests for the root-menu "Character" button notification
# dot (issue #624, PRD #620). The dot is a NotificationDot instance bound to
# an inline OR of StatBadge.should_show(current_character.skill_points) and
# AchievementBadge.should_show(achievement_service.account.achievement_state)
# — mirroring the existing instantiate-scene + bind_character / bind_
# achievement_service + add_child_autofree + await process_frame pattern used
# in test_stat_badge_wiring.gd and test_achievement_tab.gd.

# GameState is a shared autoload singleton across the whole GUT run (282
# scripts in one process) — earlier test files can leave current_character /
# achievement_service mutated. before_each resets to a pristine state so
# test_character_button_badge_exists_and_hidden_by_default (which reads
# GameState directly, with no character/service bound on the scene) isn't
# sensitive to whatever ran immediately before it in the full-suite order.
func before_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func after_each():
	get_tree().paused = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()

func _make_character(skill_points: int) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Pixel")
	c.skill_points = skill_points
	return c

func _make_achievement_service(achievement_state: Dictionary) -> AchievementService:
	var account := AccountSaveData.new()
	account.achievement_state = achievement_state
	return AchievementService.new(account)

func test_character_button_badge_exists_and_hidden_by_default():
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	add_child_autofree(scene)
	var badge = scene.find_child("CharacterButtonBadge", true, false)
	assert_not_null(badge, "pause_menu.tscn must contain a node named CharacterButtonBadge")
	assert_true(badge is NotificationDot, "CharacterButtonBadge must be a NotificationDot")
	var character_btn = scene.find_child("Character", true, false)
	assert_eq(badge.get_parent(), character_btn, "CharacterButtonBadge must be a child of the Character button")
	await get_tree().process_frame
	assert_false(badge.visible, "badge starts hidden with no character/service bound")

func test_character_button_badge_visible_from_stat_points_alone():
	var gs := get_node("/root/GameState")
	gs.set_character(_make_character(3))
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_make_achievement_service({}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("CharacterButtonBadge", true, false)
	assert_true(badge.visible, "badge must be visible when skill_points > 0, even with no achievements pending")

func test_character_button_badge_visible_from_unclaimed_achievement_alone():
	var gs := get_node("/root/GameState")
	gs.set_character(_make_character(0))
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_make_achievement_service({"some_id": {"claimed": false}}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("CharacterButtonBadge", true, false)
	assert_true(badge.visible, "badge must be visible when there is an unclaimed achievement, even with zero unspent stat points")

func test_character_button_badge_hidden_when_both_conditions_false():
	var gs := get_node("/root/GameState")
	gs.set_character(_make_character(0))
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_make_achievement_service({}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("CharacterButtonBadge", true, false)
	assert_false(badge.visible, "badge must stay hidden when there are no unspent points and no unclaimed achievements")

func test_character_button_badge_visible_when_both_conditions_true():
	var gs := get_node("/root/GameState")
	gs.set_character(_make_character(3))
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_make_achievement_service({"some_id": {"claimed": false}}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("CharacterButtonBadge", true, false)
	assert_true(badge.visible, "badge must stay visible when both conditions are true simultaneously")

func test_character_button_badge_updates_live_when_last_pending_item_clears():
	var gs := get_node("/root/GameState")
	var c := _make_character(3)
	gs.set_character(c)
	var scene = load("res://scenes/pause_menu.tscn").instantiate()
	scene.bind_achievement_service(_make_achievement_service({}))
	add_child_autofree(scene)
	await get_tree().process_frame
	var badge = scene.find_child("CharacterButtonBadge", true, false)
	assert_true(badge.visible, "badge starts visible via stat points alone")
	c.skill_points = 0
	await get_tree().process_frame
	assert_false(badge.visible, "badge must hide within one frame once stat points are fully spent")
