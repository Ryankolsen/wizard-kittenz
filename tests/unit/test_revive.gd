extends GutTest

# Free revive contract (#27, slice 1 of the monetization pivot).
#
# - ReviveSystem.revive(player) is the only entry point. No try_consume_revive,
#   no inventory dependency.
# - CoopRouter.revive(session, character, local_player_id) routes the
#   half-max revive to the right CharacterData block (real_stats solo, the
#   local member's effective_stats in co-op).
# - HUD.death_screen_state() takes no args and always permits revive.

# --- ReviveSystem.revive -----------------------------------------------------

func test_revive_sets_hp_to_half_max():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 20
	c.hp = 0
	ReviveSystem.revive(c)
	assert_eq(c.hp, 10, "hp restored to 50% of max_hp")

func test_revive_rounds_half_max_hp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 9
	c.hp = 0
	ReviveSystem.revive(c)
	assert_eq(c.hp, 5, "9 max_hp -> revive at 5 (round(4.5))")

func test_revive_floors_at_one_hp_minimum():
	# Degenerate max_hp=1 must not revive at 0 (would loop the death screen).
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 1
	c.hp = 0
	ReviveSystem.revive(c)
	assert_eq(c.hp, 1, "minimum 1 HP after revive even at max_hp=1")

func test_revive_returns_resulting_hp():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE)
	c.max_hp = 10
	c.hp = 0
	assert_eq(ReviveSystem.revive(c), 5, "returns the new hp value")

func test_revive_handles_null_player():
	# Defensive: a pre-spawn / test path with no player must not crash.
	assert_eq(ReviveSystem.revive(null), 0)

# --- CoopRouter.revive — solo branch ----------------------------------

func test_local_revive_router_revive_solo_revives_character():
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.max_hp = 10
	c.hp = 0
	var ok := CoopRouter.revive(null, c, "")
	assert_true(ok)
	assert_eq(c.hp, 5, "character.hp restored to 50% of max_hp")

func test_local_revive_router_revive_null_character_no_op():
	# Null-safe: pre-spawn / test path. Returns false without crashing so the
	# caller's death-screen branch can stay an unconditional call site.
	assert_false(CoopRouter.revive(null, null, ""))

func test_local_revive_router_revive_inherits_min_one_hp_floor():
	# ReviveSystem's min-1 floor inherits through the router unchanged.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.max_hp = 1
	c.hp = 0
	assert_true(CoopRouter.revive(null, c, ""))
	assert_eq(c.hp, 1, "min-1 floor survives the router pass-through")

# --- HUD.death_screen_state — simplified free-revive contract ---------------

func test_death_screen_state_always_can_revive():
	# Acceptance criterion: dying always shows the revive prompt — no token
	# gate. The shape is fixed regardless of any internal state.
	var s := HUD.death_screen_state()
	assert_true(s["can_revive"], "free revive is always available")

func test_death_screen_state_prompt_is_you_died():
	# The HUD label reads from this dict; pin the human-visible string so
	# a refactor that changed the prompt would break the test loudly.
	var s := HUD.death_screen_state()
	assert_eq(s["prompt"], "You Died")

func test_death_screen_state_takes_no_args():
	# Pin the no-arg contract — a regression that re-introduced a token
	# count param would break this call signature.
	var s := HUD.death_screen_state()
	assert_true(s.has("can_revive"))
	assert_true(s.has("prompt"))
