class_name LocalReviveRouter
extends RefCounted

# Per-client revive routing helper. Routes a revive (the player spends a
# token to come back at half HP at the location of death) to the right
# CharacterData block:
#   - solo / no co-op session: revive lands on the player's CharacterData
#     directly (real_stats == effective_stats in solo).
#   - active co-op session: revive lands on the local PartyMember's
#     effective_stats (the scaled view that took the damage). real_stats
#     stays at full HP throughout the run because LocalDamageRouter
#     routes incoming damage to effective_stats too — so the persistent
#     character (what's saved, what session.end()'s remove_scaling clones
#     back over effective) doesn't carry residual half-HP out of the run.
#
# Sibling-shaped to LocalDamageRouter:
#   - LocalDamageRouter routes incoming damage to effective_stats so the
#     scaled HP pool is the one that takes hits.
#   - LocalReviveRouter routes the half-max revive to effective_stats so
#     the player comes back at half of the SCALED max_hp, not half of
#     the unscaled real_stats.max_hp. A scaled L10-in-an-L3-party Mage
#     reviving at 13 HP (half of 26) while the HUD's effective bar caps
#     at 12 would visually pin to full and cosmetically lie about the
#     revive amount; pinning revive to effective fixes both the math and
#     the display.
#
# Same gate predicate as LocalDamageRouter (session non-null + active +
# local_player_id non-empty + member found) — a refactor of one stays in
# lockstep with the other so a future scaling shape change (e.g. adding
# a "remote player took damage on my client" case) lands consistently.
#
# Why a separate router (vs. inline branching in ReviveSystem):
#   - ReviveSystem is general-purpose: it spends a token + sets hp to
#     half max_hp. It doesn't know about co-op scaling. Inlining the
#     branch there would force every caller (solo death screen, co-op
#     death screen, future hazard auto-revive) to pay for routing they
#     don't need.
#   - As inline branching in the future death-screen scene, the rule
#     would be hidden in the scene-tree node, untestable in isolation.
#     The router is RefCounted + all-static so a unit test pins the
#     contract without booting a scene.
#   - Mirrors LocalDamageRouter exactly so the routing rules for the
#     same player stay symmetric: damage-routes-to-X implies revive-
#     routes-to-X, period.
#
# What this does NOT do:
#   - Apply general healing. A "+5 HP heal pickup" mid-run is a sibling
#     concern (LocalHealRouter): solo + co-op both want heals to land
#     on the "current view" of HP, but the heal-clamping ceiling is
#     max_hp, which differs between real_stats and effective_stats.
#     Outside this commit's scope.
#   - Heal remote players. Each client revives its own member — a
#     remote kitten's revive is that client's concern.
#   - Touch the scene tree. The future death-screen scene calls into
#     this helper rather than ReviveSystem.try_consume_revive directly;
#     the router decides which CharacterData block is the target.
#   - Adjust the revive HP fraction. ReviveSystem's REVIVE_HP_FRACTION
#     (0.5) and minimum-1 floor inherit through the helper unchanged.
#     A future "revive at full HP" debuff or class perk would be a
#     separate seam.

# Whether the "co-op active" branch should fire. Same gate as
# LocalDamageRouter.is_coop_route — pulled out as a static so a test
# pins the predicate without exercising the whole revive path. A
# session that exists but isn't active (constructed but start() not
# yet called, or already end()ed) takes the solo branch.
static func is_coop_route(session: CoopSession, local_player_id: String) -> bool:
	if session == null:
		return false
	if not session.is_active():
		return false
	if local_player_id == "":
		return false
	if session.member_for(local_player_id) == null:
		return false
	return true

# Returns the CharacterData block that the revive should land on. Pure
# branching; does NOT mutate state. Solo path returns the input
# character (real_stats). Co-op path returns the local member's
# effective_stats. Defensive fall-through to character when the member's
# effective_stats is null (uninitialized member — from_character always
# sets effective_stats so this is defense-in-depth, not a normal path).
static func target_for(session: CoopSession, character: CharacterData, local_player_id: String) -> CharacterData:
	if character == null:
		return null
	if not is_coop_route(session, local_player_id):
		return character
	var member := session.member_for(local_player_id)
	if member == null or member.effective_stats == null:
		return character
	return member.effective_stats

# Spends one token from the inventory and revives the routed target.
# Returns true on success; false (with no mutation to the target or
# inventory) when:
#   - inventory is null (test path / fresh-install)
#   - inventory is empty (caller's death-screen surfaces the "Buy More"
#     branch)
#   - character is null (pre-spawn / test path; defensive)
# Same shape as ReviveSystem.try_consume_revive — the router just
# decides which CharacterData block gets handed to ReviveSystem.
static func try_consume_revive(session: CoopSession, character: CharacterData, inventory: TokenInventory, local_player_id: String) -> bool:
	if character == null:
		return false
	var target := target_for(session, character, local_player_id)
	if target == null:
		return false
	return ReviveSystem.try_consume_revive(target, inventory)
