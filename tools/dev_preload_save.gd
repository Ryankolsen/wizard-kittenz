extends SceneTree

# Dev-only helper: writes user://save.json with all four Kitten archetypes at
# level 15 and 5000 Gems on the account, for manually testing the Cat-tier
# Shop upgrade + evolve-congrats flow (PRD #439) without grinding XP/gold.
# Not part of the shipped game — run standalone via:
#   Godot --headless --path . -s tools/dev_preload_save.gd

const TARGET_LEVEL := 15
const TARGET_GEMS := 5000

const ARCHETYPES := [
	CharacterData.CharacterClass.BATTLE_KITTEN,
	CharacterData.CharacterClass.WIZARD_KITTEN,
	CharacterData.CharacterClass.SLEEPY_KITTEN,
	CharacterData.CharacterClass.CHONK_KITTEN,
]

func _init() -> void:
	var bundle := SaveManager.load_bundle()

	for klass in ARCHETYPES:
		var c := CharacterData.make_new(klass, CharacterData.class_name_for(klass).capitalize())
		while c.level < TARGET_LEVEL:
			ProgressionSystem.add_xp(c, ProgressionSystem.xp_to_next_level(c.level))
		var slot := CharacterSlotData.from_state(c)
		bundle.set_slot(klass, slot)

	var ledger := CurrencyLedger.new()
	ledger.credit(TARGET_GEMS, CurrencyLedger.Currency.GEM)
	bundle.account = AccountSaveData.from_state(ledger)
	bundle.active_slot = SaveBundle.SLOT_BATTLE

	var err := SaveManager.save_bundle(bundle)
	if err != OK:
		printerr("Failed to write save: %s" % err)
		quit(1)
		return

	print("Wrote user://save.json — all 4 Kitten archetypes at level %d, %d Gems." % [TARGET_LEVEL, TARGET_GEMS])
	quit(0)
