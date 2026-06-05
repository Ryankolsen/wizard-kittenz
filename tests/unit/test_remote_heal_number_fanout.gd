extends GutTest

# Tests for the PRD #341 (issue #345) heal-number fan-out path in
# CoopPlayerLayer. lobby.heal_received is already emitted by NakamaLobby
# when an OP_HEAL packet lands; this slice subscribes that signal in the
# layer and routes the amount to the matching RemoteKitten's
# spawn_heal_number (targeted heal) or to every kitten (AOE — empty
# target_id), so the healed teammate(s)' avatars show a green floating
# number on every peer's screen.

const HEAL_GREEN := Color(0.2, 1.0, 0.4)


func _make_lobby_with_players(local_id: String, ids: Array) -> NakamaLobby:
	var nl := NakamaLobby.new()
	nl.local_player_id = local_id
	var ls := LobbyState.new("ABCDE")
	for id in ids:
		ls.add_player(LobbyPlayer.make(id, "k_%s" % id, "Mage"))
	nl.lobby_state = ls
	return nl


func _make_session_with_party(party_ids: Array) -> CoopSession:
	var session := CoopSession.new()
	session.network_sync = NetworkSyncManager.new()
	for pid in party_ids:
		session.network_sync.apply_remote_state(pid, Vector2.ZERO, 0.0)
	return session


func _find_heal_text(parent: Node, text: String) -> FloatingText:
	for child in parent.get_children():
		if child is FloatingText:
			var ft := child as FloatingText
			var label := ft.get_node_or_null("Label") as Label
			if label != null and label.text == text \
				and label.modulate == HEAL_GREEN:
				return ft
	return null


func before_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.set_lobby(null)
		gs.coop_session = null
		gs.local_player_id = ""


func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.set_lobby(null)
		gs.coop_session = null
		gs.local_player_id = ""


func test_targeted_heal_spawns_number_on_matching_kitten_only():
	# Non-empty target_id matching one teammate: only that teammate's
	# avatar gets the green number.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice", "bob"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	var bob: RemoteKitten = layer.remote_kitten_for("bob")
	lobby.heal_received.emit("caster", "alice", "SMART_HEAL", 4, 0.0)
	assert_not_null(_find_heal_text(alice.get_parent(), "4"),
		"alice (targeted) gets a green heal number")
	# bob shares the layer parent with alice — assert no "4" green text
	# was spawned associated with bob. Since both kittens share the same
	# scene parent (the layer), we assert there is exactly one heal-green
	# "4" FloatingText, not two.
	var count := 0
	for child in alice.get_parent().get_children():
		if child is FloatingText:
			var label := (child as FloatingText).get_node_or_null("Label") as Label
			if label != null and label.text == "4" and label.modulate == HEAL_GREEN:
				count += 1
	assert_eq(count, 1,
		"targeted heal must fan out to exactly one avatar")


func test_aoe_heal_with_empty_target_id_spawns_on_every_remote_kitten():
	# AOE / group sentinel: empty target_id means "every party member".
	# Each remote kitten gets its own green number. The local player_id is
	# skipped — the local Player node renders its own heal number through
	# RemoteHealApplier's existing path.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice", "bob"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	lobby.heal_received.emit("caster", "", "AOE_HEAL", 6, 0.0)
	# Two remote kittens, both sharing the layer as scene parent; the AOE
	# fan-out spawns one FloatingText per kitten.
	var count := 0
	for child in layer.get_children():
		if child is FloatingText:
			var label := (child as FloatingText).get_node_or_null("Label") as Label
			if label != null and label.text == "6" and label.modulate == HEAL_GREEN:
				count += 1
	assert_eq(count, 2,
		"AOE heal spawns one green number per remote kitten")


func test_heal_received_ignores_unknown_target_id():
	# A targeted heal whose target_id matches no spawned kitten (stale
	# packet / mid-roster-update) is a silent no-op — mirrors the
	# position/attack/hit unknown-id guards.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	lobby.heal_received.emit("caster", "ghost", "SMART_HEAL", 4, 0.0)
	for child in layer.get_children():
		assert_false(child is FloatingText,
			"unknown target_id spawns no FloatingText")


func test_zero_amount_heal_spawns_no_number():
	# No spurious zeros — the avatar guard mirrors the damage path.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	lobby.heal_received.emit("caster", "alice", "SMART_HEAL", 0, 0.0)
	for child in layer.get_children():
		assert_false(child is FloatingText,
			"zero amount must spawn no FloatingText")
