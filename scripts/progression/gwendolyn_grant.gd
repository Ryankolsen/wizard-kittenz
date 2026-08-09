class_name GwendolynGrant
extends RefCounted

# PRD #474 / issue #475. Grants the summon_gwendolyn skill node directly to a
# character whose name matched GwendolynNameMatch — independent of the
# achievement-claim flow (the memorial achievement's own claim() reward is a
# no-op; the real reward is delivered here). Mirrors AchievementService's TOME
# active/inactive-slot grant shape.

const NODE_ID: String = "summon_gwendolyn"
const SPELL_ID: String = "summon_gwendolyn"

# Active-slot path: the character being created/renamed is the currently
# live one, so mutate its live SkillTree/Quickbar directly.
static func grant_to_active(skill_tree: SkillTree, quickbar: Quickbar) -> void:
	if skill_tree == null:
		return
	skill_tree.unlock(NODE_ID)
	if quickbar == null:
		return
	var node := skill_tree.find(NODE_ID)
	if node != null and node.spell != null:
		quickbar.on_spell_unlocked(node.spell)

# Inactive-slot path: no live SkillTree/Quickbar exists to hydrate, so the
# unlock/assignment is mirrored directly onto the raw CharacterSlotData
# fields (same shape as AchievementService._grant_tome_to_slot_data).
static func grant_to_slot(slot: CharacterSlotData) -> void:
	if slot == null:
		return
	if not slot.unlocked_skill_ids.has(NODE_ID):
		slot.unlocked_skill_ids.append(NODE_ID)
	if slot.quickbar_slots.has(SPELL_ID):
		return
	for i in range(Quickbar.SLOT_COUNT):
		if i >= slot.quickbar_slots.size():
			slot.quickbar_slots.append(SPELL_ID)
			return
		if slot.quickbar_slots[i] == "":
			slot.quickbar_slots[i] = SPELL_ID
			return
