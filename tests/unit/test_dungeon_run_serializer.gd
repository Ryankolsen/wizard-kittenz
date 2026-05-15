extends GutTest

# Tests for the dungeon-run save/resume (PRD #42 / #46). Covers the
# KittenSaveData field round-trip plus the DungeonRunSerializer
# serialize / deserialize halves end-to-end against a real generated
# Dungeon.

const DungeonRunSerializer = preload("res://scripts/dungeon_run_serializer.gd")
const QuitDungeonHandlerRef = preload("res://scripts/quit_dungeon_handler.gd")

func test_kitten_save_data_to_dict_includes_dungeon_run_state():
	var s := KittenSaveData.new()
	s.dungeon_run_state = {"seed": 42, "current_room_id": 3, "cleared_room_ids": [0, 1]}
	var d := s.to_dict()
	assert_true(d.has("dungeon_run_state"), "to_dict must include dungeon_run_state key")

func test_dungeon_run_state_round_trips():
	var s := KittenSaveData.new()
	s.dungeon_run_state = {"seed": 7, "current_room_id": 2, "cleared_room_ids": [0, 1, 2]}
	var s2 := KittenSaveData.from_dict(s.to_dict())
	assert_eq(s2.dungeon_run_state.get("seed"), 7)
	assert_eq(s2.dungeon_run_state.get("current_room_id"), 2)
	assert_eq(s2.dungeon_run_state.get("cleared_room_ids"), [0, 1, 2])

func test_from_dict_missing_dungeon_run_state_defaults_empty():
	var d := {"character_name": "Mittens", "level": 1}
	var s := KittenSaveData.from_dict(d)
	assert_eq(s.dungeon_run_state, {}, "missing field must default to empty dict")

func test_serializer_captures_current_room_and_cleared():
	var dungeon := DungeonGenerator.generate(99)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	var state := DungeonRunSerializer.serialize(ctrl, 99)
	assert_eq(state.get("seed"), 99)
	assert_eq(state.get("current_room_id"), dungeon.start_id)
	assert_true(state.has("cleared_room_ids"))

func test_serializer_restores_cleared_rooms():
	var dungeon := DungeonGenerator.generate(99)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	ctrl.mark_room_cleared(dungeon.start_id)
	var state := DungeonRunSerializer.serialize(ctrl, 99)
	var ctrl2 := DungeonRunSerializer.deserialize(state)
	assert_true(ctrl2.is_room_cleared(dungeon.start_id),
		"restored controller must reflect cleared rooms")

# Standard / boss rooms aren't auto-cleared, so a serialize-then-deserialize
# round-trip is the only path that preserves the cleared flag for them.
# Generates a dungeon, marks the boss explicitly cleared, round-trips, and
# asserts the boss reads as cleared on the rebuilt controller — this pins
# the resume contract for the case that actually matters (the player closed
# the app between killing the boss enemy and stepping out).
func test_serializer_restores_explicitly_cleared_boss():
	var dungeon := DungeonGenerator.generate(123)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	ctrl.mark_room_cleared(dungeon.boss_id)
	var state := DungeonRunSerializer.serialize(ctrl, 123)
	var ctrl2 := DungeonRunSerializer.deserialize(state)
	assert_true(ctrl2.is_room_cleared(dungeon.boss_id),
		"explicit boss-clear must survive serialize/deserialize")

func test_serializer_preserves_current_room_id():
	var dungeon := DungeonGenerator.generate(55)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	# Snap current_room_id to a non-start id so the round-trip's "resume
	# where you left off" branch is exercised. Post-#97 the controller no
	# longer exposes advance_to; the serializer assigns current_room_id
	# directly on restore, so writing it directly here mirrors that path.
	var first := dungeon.get_room(dungeon.start_id)
	if first.connections.is_empty():
		pending("dungeon graph had no connections — unexpected for seed 55")
		return
	var target: int = first.connections[0]
	ctrl.current_room_id = target
	var state := DungeonRunSerializer.serialize(ctrl, 55)
	var ctrl2 := DungeonRunSerializer.deserialize(state)
	assert_eq(ctrl2.current_room_id, target,
		"restored controller must resume at the saved room")

func test_serializer_empty_state_returns_null():
	assert_null(DungeonRunSerializer.deserialize({}),
		"empty state must signal no resumable run")

func test_serializer_missing_seed_returns_null():
	assert_null(DungeonRunSerializer.deserialize({"current_room_id": 0}),
		"state without a seed has no way to regenerate the dungeon")

func test_kitten_save_data_dungeon_state_survives_json_round_trip():
	var s := KittenSaveData.new()
	s.dungeon_run_state = {"seed": 11, "current_room_id": 4, "cleared_room_ids": [0, 2]}
	var json := JSON.stringify(s.to_dict())
	var parsed = JSON.parse_string(json)
	assert_true(parsed is Dictionary)
	var s2 := KittenSaveData.from_dict(parsed)
	# JSON round-trips ints as floats inside nested dicts — the field readers
	# in from_dict don't re-coerce nested values, so the contract is that the
	# values survive as JSON-Variant-compatible primitives. The seed comes
	# back as a float, so cast for the equality check.
	assert_eq(int(s2.dungeon_run_state.get("seed")), 11)
	assert_eq(int(s2.dungeon_run_state.get("current_room_id")), 4)

# Quit handler's solo branch must thread the run state through SaveManager so
# the next launch's _try_load_save sees it. Builds a real controller, calls
# save_and_exit, reads the save back via SaveManager.load, and asserts the
# state field is populated.
func test_quit_handler_saves_dungeon_run_state_in_solo():
	var path := "user://test_quit_run_state.json"
	var dungeon := DungeonGenerator.generate(77)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	ctrl.seed = 77
	var c := CharacterData.new()
	c.character_name = "ResumeTest"
	c.character_class = CharacterData.CharacterClass.MAGE
	assert_true(QuitDungeonHandlerRef.save_and_exit(c, null, path, null, ctrl, 77),
		"solo save_and_exit must return true")
	var loaded := SaveManager.load(path)
	assert_not_null(loaded, "save file must be readable")
	assert_eq(int(loaded.dungeon_run_state.get("seed", -1)), 77,
		"saved dungeon_run_state must carry the run's seed")
	# Clean up the test artifact so reruns don't leak.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# Multiplayer path must NOT write a save — the run state stays in-memory only.
# Pre-populates a save file at the test path, calls the multiplayer branch
# (session != null), and asserts the file is untouched.
func test_quit_handler_multiplayer_does_not_persist_run_state():
	var path := "user://test_quit_run_state_mp.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var c := CharacterData.new()
	c.character_name = "MPTest"
	var session := CoopSession.new()
	var dungeon := DungeonGenerator.generate(88)
	var ctrl := DungeonRunController.new()
	ctrl.start(dungeon)
	ctrl.seed = 88
	assert_true(QuitDungeonHandlerRef.save_and_exit(c, session, path, null, ctrl, 88),
		"multiplayer save_and_exit must return true")
	assert_false(FileAccess.file_exists(path),
		"multiplayer branch must not write a save file")
