extends GutTest

# PRD #280 / issue #281: Player's combat weapon visual must read from the
# player's actually equipped weapon and respond live to loadout changes.
# Mirrors test_character_avatar.test_live_update_via_loadout_changed_signal,
# but at the Player (combat) layer rather than the CharacterAvatar (UI) layer.

const SwordTex := "res://assets/sprites/weapon_slippery_mackerel.png"

class FakeGameState:
	var local_player_id: String = "test_player"
	var coop_session = null
	var lobby = null
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()

func _make_player(inv: ItemInventory) -> Player:
	var fake := FakeGameState.new()
	fake.item_inventory = inv
	fake.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p._inject_game_state(fake)
	add_child_autofree(p)
	return p

func _combat_weapon_sprite(p: Player) -> Sprite2D:
	var pivot := p.find_child("WeaponPivot", true, false)
	if pivot == null:
		return null
	return pivot.get_node_or_null("Sprite2D") as Sprite2D

func test_empty_inventory_starts_unarmed_with_hidden_weapon_sprite():
	var inv := ItemInventory.new()
	var p := _make_player(inv)
	var ws := _combat_weapon_sprite(p)
	assert_not_null(ws, "weapon sprite node exists for battle class")
	assert_false(ws.visible, "no weapon equipped → combat weapon sprite hidden")

func test_equipping_iron_sword_swaps_combat_sprite_live():
	var inv := ItemInventory.new()
	var p := _make_player(inv)
	inv.equip(ItemCatalog.find("iron_sword"))
	var ws := _combat_weapon_sprite(p)
	assert_true(ws.visible, "equipping must show the combat weapon sprite live")
	assert_not_null(ws.texture)
	assert_eq(ws.texture.resource_path, SwordTex,
		"combat sprite uses the per-id mackerel texture, not a hardcoded class default")

func test_unequipping_weapon_hides_combat_sprite_live():
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	var p := _make_player(inv)
	var ws := _combat_weapon_sprite(p)
	assert_true(ws.visible, "starts armed when inventory has a weapon at _ready time")
	inv.unequip(ItemData.Slot.WEAPON)
	assert_false(ws.visible, "unequipping mid-dungeon must hide the weapon sprite live")


# --- Slice 3 of PRD #328 (issue #331): equip-swap PLAYER_INFO broadcast ------

class SpyLobby:
	extends NakamaLobby
	var sent: Array = []  # each entry is the LobbyPlayer passed in
	func send_player_info_async(player: LobbyPlayer) -> void:
		sent.append(player)


class FakeGameStateWithLobby:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null  # SpyLobby
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()


func _make_player_with_spy_lobby(inv: ItemInventory) -> Dictionary:
	var fake := FakeGameStateWithLobby.new()
	fake.item_inventory = inv
	fake.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var spy := SpyLobby.new()
	spy.local_player_id = "me"
	var ls := LobbyState.new("ABCDE")
	ls.add_player(LobbyPlayer.make("me", "Me", "Battle Kitten",
		true, CharacterData.CharacterClass.BATTLE_KITTEN))
	spy.lobby_state = ls
	fake.lobby = spy
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p._inject_game_state(fake)
	add_child_autofree(p)
	return {"player": p, "spy": spy}


func test_equipping_weapon_triggers_player_info_broadcast() -> void:
	# Issue #331 AC: equipping a weapon triggers a PLAYER_INFO rebroadcast
	# with the new equipped_weapon_id so every peer's RemoteKitten can
	# update its WeaponPivot through HeldWeaponResolver.
	var inv := ItemInventory.new()
	var fixture := _make_player_with_spy_lobby(inv)
	var spy: SpyLobby = fixture["spy"]
	# _ready may have triggered a refresh that broadcast an empty state.
	# Clear the spy and assert only the equip-induced send.
	spy.sent.clear()
	inv.equip(ItemCatalog.find("iron_sword"))
	assert_eq(spy.sent.size(), 1,
		"equip must trigger exactly one PLAYER_INFO broadcast")
	var broadcast_player: LobbyPlayer = spy.sent[0]
	assert_eq(broadcast_player.equipped_weapon_id, "iron_sword",
		"broadcast LobbyPlayer carries the new weapon id")


func test_unequipping_weapon_triggers_player_info_broadcast_with_empty_id() -> void:
	# Unequip mirrors equip — the broadcast goes out with "" so peers
	# revert their RemoteKitten to the class-default pose (no weapon
	# sprite). Without this, a peer that disarms would still appear
	# armed on remote clients until their next reconnect.
	var inv := ItemInventory.new()
	inv.equip(ItemCatalog.find("iron_sword"))
	var fixture := _make_player_with_spy_lobby(inv)
	var spy: SpyLobby = fixture["spy"]
	spy.sent.clear()
	inv.unequip(ItemData.Slot.WEAPON)
	assert_eq(spy.sent.size(), 1,
		"unequip must trigger exactly one PLAYER_INFO broadcast")
	assert_eq(spy.sent[0].equipped_weapon_id, "",
		"unequipped state broadcasts as empty id — the unarmed sentinel")
