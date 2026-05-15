extends GutTest

# Tests for CoopPlayerLayer added in #35. The layer renders one RemoteKitten
# per remote player_id in the active lobby and reconciles spawns/frees as
# the lobby roster changes. The local player_id is always skipped — the
# local Player node renders that one.
#
# Tests use reconcile() directly rather than relying on signal timing so
# the assertions don't depend on a CoopSession round-trip through Nakama.

const REMOTE_KITTEN_PATH := "res://scenes/remote_kitten.tscn"

func _make_lobby_with_players(local_id: String, ids: Array) -> NakamaLobby:
	var nl := NakamaLobby.new()
	nl.local_player_id = local_id
	var ls := LobbyState.new("ABCDE")
	for id in ids:
		ls.add_player(LobbyPlayer.make(id, "k_%s" % id, "Mage"))
	nl.lobby_state = ls
	return nl

func _make_session_with_party(party_ids: Array) -> CoopSession:
	# A minimal session whose network_sync the layer can hand off to
	# RemoteKitten instances. We don't need to call start() — the
	# layer only reads coop_session.network_sync, which we set directly.
	var session := CoopSession.new()
	session.network_sync = NetworkSyncManager.new()
	# party_ids registered for parity with the real flow, but the layer
	# reads roster from the lobby, not the session.
	for pid in party_ids:
		session.network_sync.apply_remote_state(pid, Vector2.ZERO, 0.0)
	return session

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

func test_reconcile_spawns_one_remote_kitten_per_remote_player():
	# Issue acceptance criterion: applying a lobby state with two remote
	# players produces two RemoteKitten children.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice", "bob"]))
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	# _ready already reconciled once; assert end state.
	assert_eq(layer.remote_kitten_count(), 2,
		"two remote players => two RemoteKitten children")
	assert_not_null(layer.remote_kitten_for("alice"))
	assert_not_null(layer.remote_kitten_for("bob"))

func test_reconcile_skips_local_player_id():
	# Issue acceptance criterion: the local player_id never produces a
	# RemoteKitten child — the local Player node already renders that one.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	assert_null(layer.remote_kitten_for("me"),
		"local kitten never rendered through this layer")

func test_reconcile_frees_kitten_when_player_removed():
	# Issue acceptance criterion: removing one player from the lobby frees
	# exactly that child and leaves the other.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice", "bob"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 2)
	# Remove alice from the roster.
	lobby.lobby_state.remove_player("alice")
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 1, "alice freed, bob retained")
	assert_null(layer.remote_kitten_for("alice"))
	assert_not_null(layer.remote_kitten_for("bob"))

func test_reconcile_is_idempotent():
	# Issue acceptance criterion: re-applying the same lobby state is
	# idempotent — no duplicate nodes spawned. Without this, every
	# lobby_updated emission (which can fire on any roster mutation, even
	# unrelated ones like a ready-toggle) would double the child count.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice", "bob"]))
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice_first := layer.remote_kitten_for("alice")
	layer.reconcile()
	layer.reconcile()
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 2, "still two after repeated reconciles")
	assert_eq(layer.remote_kitten_for("alice"), alice_first,
		"existing child instance reused, not respawned")

func test_reconcile_clears_all_when_lobby_cleared():
	# Defensive: if GameState.lobby is set to null mid-session (e.g. host
	# leaves), the layer must drop its kittens rather than holding stale
	# remote players that can't receive position updates anymore.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	gs.set_lobby(null)
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 0, "no lobby => no remote kittens")

func test_reconcile_clears_all_when_session_cleared():
	# Same defensive: session ended but lobby still around (multi-run
	# match between dungeons). No session == no network_sync to drive
	# remote kitten interpolation, so render nothing rather than freeze
	# them at their last position with no incoming updates.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	gs.coop_session = null
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 0, "no session => no remote kittens")

func test_reconcile_assigns_distinct_tints_per_slot():
	# Acceptance criterion #4: remote kittens are visually distinct from
	# the local player. Different remote players get different tints from
	# CoopPlayerLayer.TINTS, indexed by lobby slot.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice", "bob"]))
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice := layer.remote_kitten_for("alice")
	var bob := layer.remote_kitten_for("bob")
	assert_ne(alice.tint_color, bob.tint_color,
		"two remote players get distinct tints")

func test_lobby_updated_signal_triggers_reconcile():
	# Acceptance criterion #6/#7: a new player joining mid-session shows
	# up without a manual reconcile call. The layer subscribes to
	# lobby_updated in _ready, so emitting it after a roster change must
	# spawn the new kitten.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	# bob joins after the layer is in the tree.
	lobby.lobby_state.add_player(LobbyPlayer.make("bob", "k_bob", "Mage"))
	lobby.lobby_updated.emit(lobby.lobby_state)
	assert_eq(layer.remote_kitten_count(), 2,
		"lobby_updated emission spawned bob without manual reconcile")

func test_remote_kitten_joins_taunt_targets_group():
	# PRD #124 cross-client TAUNT: a remote caster is rendered as a
	# RemoteKitten on this client, not a Player node. Enemy._select_taunt
	# _target_by_id walks the "taunt_targets" group looking for a
	# player_id match — RemoteKitten must register itself there.
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	inst.player_id = "p_remote"
	add_child_autofree(inst)
	assert_true(inst.is_in_group("taunt_targets"),
		"RemoteKitten._ready must add the node to the taunt_targets group")
	assert_eq(inst.player_id, "p_remote",
		"player_id is preserved for the id-match resolver")

func test_remote_kitten_scene_loads():
	# Smoke: the .tscn parses cleanly, root node is a RemoteKitten with
	# the placeholder + label children the script expects.
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	assert_not_null(scene, "remote_kitten.tscn must be loadable")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "must instantiate")
	assert_true(inst is RemoteKitten,
		"root node must be bound to RemoteKitten script")
	assert_not_null(inst.get_node_or_null("Placeholder"))
	assert_not_null(inst.get_node_or_null("Label"))
	inst.free()

func test_main_scene_includes_coop_player_layer():
	# Regression guard parallel to test_main_scene_includes_touch_controls:
	# main.tscn must contain a CoopPlayerLayer or remote players never
	# render in the dungeon.
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert_not_null(scene)
	var inst: Node = scene.instantiate()
	var layer: Node = inst.get_node_or_null("CoopPlayerLayer")
	assert_not_null(layer, "main.tscn must contain a CoopPlayerLayer node")
	assert_true(layer is CoopPlayerLayer,
		"CoopPlayerLayer node must be bound to the CoopPlayerLayer script")
	inst.free()
