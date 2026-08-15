extends SceneTree

# Dev-only helper: writes user://save.json with all four Kitten archetypes at
# level 15 and every weapon for that class (all rarities, including shop-only)
# dropped into the bag, for manually testing per-item weapon icon art (PRD
# #480) without grinding drops. Not part of the shipped game — run standalone
# via:
#   Godot --headless --path . -s tools/dev_preload_all_weapons.gd

const TARGET_LEVEL := 15
const TARGET_GEMS := 5000

const ARCHETYPES := [
	CharacterData.CharacterClass.BATTLE_KITTEN,
	CharacterData.CharacterClass.WIZARD_KITTEN,
	CharacterData.CharacterClass.SLEEPY_KITTEN,
	CharacterData.CharacterClass.CHONK_KITTEN,
]

static func _weapon_ids_for(klass: int) -> Array[String]:
	var ids: Array[String] = []
	for item in ItemCatalog.all_items():
		if item.slot == ItemData.Slot.WEAPON and item.allowed_classes.has(klass):
			ids.append(item.id)
	return ids

func _init() -> void:
	var bundle := SaveManager.load_bundle()

	for klass in ARCHETYPES:
		var c := CharacterData.make_new(klass, CharacterData.class_name_for(klass).capitalize())
		while c.level < TARGET_LEVEL:
			ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(c.level))
		var slot := CharacterSlotData.from_state(c)
		slot.item_bag = _weapon_ids_for(klass)
		bundle.set_slot(klass, slot)

	var ledger := CurrencyLedger.new()
	ledger.credit(TARGET_GEMS, CurrencyLedger.Currency.GEM)
	bundle.account = AccountSaveData.from_state(ledger)
	bundle.active_slot = SaveBundle.SLOT_CHONK

	var err := SaveManager.save_bundle(bundle)
	if err != OK:
		printerr("Failed to write save: %s" % err)
		quit(1)
		return

	print("Wrote user://save.json — all 4 archetypes at level %d, %d Gems, every class-weapon in bag." % [TARGET_LEVEL, TARGET_GEMS])
	quit(0)
