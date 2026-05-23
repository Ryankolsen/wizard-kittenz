class_name Bartender
extends InteractableNPC

# In-dungeon bartender NPC. The bubble menu is [Shop, Get a beer, Exit].
#
# Decisions:
# - "Get a beer" costs 25 gold and applies +20% damage for 60s via
#   CharacterData.add_damage_mult_buff. The is_enabled predicate reads the
#   live gold balance, so the option re-renders disabled after the player
#   spends below 25g (e.g. in the shop) and the bubble reopens via
#   BarRoom._on_shop_closed → open_menu().
# - Ledger + character are resolved through the GameState autoload by default,
#   with explicit setup_economy() injection seams for tests so the buff /
#   debit / floating-text path can be exercised without booting GameState.
# - Floating text spawns on the bartender node itself (in world space, near
#   the player who is by definition in proximity). The PRD doesn't ask for
#   it to specifically follow the player, and parenting to the bartender
#   keeps the spawn independent of how the test stubs the player.

signal shop_requested()

const SPRITE_TEXTURE_PATH := "res://assets/sprites/bartender.png"

const BEER_COST: int = 25
const BEER_BUFF_MAGNITUDE: float = 1.2
const BEER_BUFF_DURATION: float = 60.0
const BEER_FLOATING_TEXT: String = "+20% damage 60s"

var _ledger_override: CurrencyLedger = null
var _character_override: CharacterData = null


func _ready() -> void:
	super._ready()
	_apply_sprite_texture()


# Test injection seam. Production callers leave both null and the bartender
# reads the GameState autoload at lookup time.
func setup_economy(ledger: CurrencyLedger, character: CharacterData) -> void:
	_ledger_override = ledger
	_character_override = character


func _apply_sprite_texture() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	if not ResourceLoader.exists(SPRITE_TEXTURE_PATH):
		return
	var tex := load(SPRITE_TEXTURE_PATH) as Texture2D
	if tex != null:
		sprite.texture = tex


func _ledger() -> CurrencyLedger:
	if _ledger_override != null:
		return _ledger_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.currency_ledger


func _character() -> CharacterData:
	if _character_override != null:
		return _character_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.current_character


func _can_afford_beer() -> bool:
	var ledger := _ledger()
	if ledger == null:
		return false
	return ledger.balance(CurrencyLedger.Currency.GOLD) >= BEER_COST


func _build_option_list() -> NPCOptionList:
	return NPCOptionList.make([
		NPCOption.make("Shop", "open_shop"),
		NPCOption.make("Get a beer", "buy_beer",
			Callable(self, "_can_afford_beer"),
			NPCOption.CurrencyType.GOLD, BEER_COST),
		NPCOption.make("Exit", "close"),
	] as Array[NPCOption])


func _handle_effect(effect_id: String) -> void:
	match effect_id:
		"open_shop":
			# Tear the bubble down so the shop overlay sits cleanly on top.
			# BarRoom._on_shop_closed re-opens the menu when the overlay closes.
			_close_bubble()
			shop_requested.emit()
		"buy_beer":
			_buy_beer()
		"close":
			_close_bubble()


func _buy_beer() -> void:
	var ledger := _ledger()
	var character := _character()
	if ledger == null or character == null:
		return
	# Predicate already gates the row, but debit failing is the source of truth.
	if not ledger.debit(BEER_COST, CurrencyLedger.Currency.GOLD):
		return
	character.add_damage_mult_buff(BEER_BUFF_MAGNITUDE, BEER_BUFF_DURATION)
	FloatingText.spawn(self, BEER_FLOATING_TEXT, Color(1.0, 0.9, 0.2))
	_close_bubble()
