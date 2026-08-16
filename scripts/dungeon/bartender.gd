class_name Bartender
extends InteractableNPC

# In-dungeon bartender NPC. The bubble menu is
# [Shop, Get a beer, Rent a Hooman, Exit].
#
# Decisions:
# - "Get a beer" costs 25 gold and applies +20% damage for 60s via
#   CharacterData.add_damage_mult_buff. The is_enabled predicate reads the
#   live gold balance, so the option re-renders disabled after the player
#   spends below 25g (e.g. in the shop) and the bubble reopens via
#   BarRoom._on_shop_closed → open_menu().
# - "Rent a Hooman" (PRD #491, issue #495) debits HoomanRentalService.
#   RENT_COST_GOLD and calls HoomanRentalService.activate() for the current
#   floor. Its is_enabled predicate gates on both live gold affordability and
#   solo-only (coop_session == null or not coop_session.is_active()) — the
#   PRD's solo-only rule is enforced here by disabling the row entirely, with
#   no networking work required.
# - Ledger + character are resolved through the GameState autoload by default,
#   with explicit setup_economy() injection seams for tests so the buff /
#   debit / floating-text path can be exercised without booting GameState.
#   setup_hooman_rental() is the equivalent seam for the rental service,
#   floor number, and coop session.
# - Floating text spawns on the bartender node itself (in world space, near
#   the player who is by definition in proximity). The PRD doesn't ask for
#   it to specifically follow the player, and parenting to the bartender
#   keeps the spawn independent of how the test stubs the player.

signal shop_requested()
# Issue #496: fires on every successful rental (first rent of a run and any
# later re-rental on a subsequent floor). main_scene listens (via BarRoom's
# re-emit) and spawns the Hooman node the first time only — later rentals
# just re-activate HoomanRentalService, which is already handled by
# _rent_hooman below.
signal hooman_rented()

const SPRITE_TEXTURE_PATH := "res://assets/sprites/bartender.png"

const BEER_COST: int = 25
const BEER_BUFF_MAGNITUDE: float = 1.2
const BEER_BUFF_DURATION: float = 60.0
const BEER_FLOATING_TEXT: String = "+20% damage 60s"
const RENT_HOOMAN_FLOATING_TEXT: String = "Hooman hired!"

var _ledger_override: CurrencyLedger = null
var _character_override: CharacterData = null
var _hooman_rental_service_override: HoomanRentalService = null
var _floor_number_override: int = -1
var _has_floor_number_override: bool = false
var _coop_session_override: Object = null
var _has_coop_session_override: bool = false


func _ready() -> void:
	super._ready()
	_apply_sprite_texture()


# Test injection seam. Production callers leave both null and the bartender
# reads the GameState autoload at lookup time.
func setup_economy(ledger: CurrencyLedger, character: CharacterData) -> void:
	_ledger_override = ledger
	_character_override = character


# Test injection seam for the Rent a Hooman row. coop_session may be null
# (solo) or any Object exposing is_active() -> bool (a real CoopSession or a
# test stub). Production callers leave everything unset and the bartender
# reads GameState at lookup time.
func setup_hooman_rental(service: HoomanRentalService, floor_number: int, coop_session: Object) -> void:
	_hooman_rental_service_override = service
	_floor_number_override = floor_number
	_has_floor_number_override = true
	_coop_session_override = coop_session
	_has_coop_session_override = true


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


func _hooman_rental_service() -> HoomanRentalService:
	if _hooman_rental_service_override != null:
		return _hooman_rental_service_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.hooman_rental_service


func _floor_number() -> int:
	if _has_floor_number_override:
		return _floor_number_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.meta_tracker == null:
		return 1
	return gs.meta_tracker.dungeons_completed + 1


func _coop_session() -> Object:
	if _has_coop_session_override:
		return _coop_session_override
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.coop_session


func _can_rent_hooman() -> bool:
	var ledger := _ledger()
	if ledger == null:
		return false
	if ledger.balance(CurrencyLedger.Currency.GOLD) < HoomanRentalService.RENT_COST_GOLD:
		return false
	var session := _coop_session()
	if session != null and session.is_active():
		return false
	return true


func _build_option_list() -> NPCOptionList:
	return NPCOptionList.make([
		NPCOption.make("Shop", "open_shop"),
		NPCOption.make("Get a beer", "buy_beer",
			Callable(self, "_can_afford_beer"),
			NPCOption.CurrencyType.GOLD, BEER_COST),
		NPCOption.make("Rent a Hooman", "rent_hooman",
			Callable(self, "_can_rent_hooman"),
			NPCOption.CurrencyType.GOLD, HoomanRentalService.RENT_COST_GOLD),
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
		"rent_hooman":
			_rent_hooman()
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
	# Issue #468: drives the shared drinks counter for the tiered Happy Hour/
	# Bar Regular/Liver of Steel achievements. Only reached after the debit
	# succeeds, so an unaffordable beer never increments it.
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.achievement_service.increment_counter("drinks", 1)
	_close_bubble()


func _rent_hooman() -> void:
	var ledger := _ledger()
	var service := _hooman_rental_service()
	if ledger == null or service == null:
		return
	# Predicate already gates the row (gold + solo-only), but activate()
	# failing on the debit is the source of truth.
	if not service.activate(_floor_number(), ledger):
		return
	FloatingText.spawn(self, RENT_HOOMAN_FLOATING_TEXT, Color(1.0, 0.9, 0.2))
	hooman_rented.emit()
	_close_bubble()
