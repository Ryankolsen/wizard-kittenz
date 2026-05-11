class_name LocalReviveRouter
extends RefCounted

# Per-client revive routing helper. Routes a free half-HP revive (post-#27,
# monetization pivot — no token cost) to the right CharacterData block:
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

# Revives the routed target at half max_hp. Returns true on success;
# false (with no mutation) when character is null (pre-spawn / test
# path; defensive). The router just decides which CharacterData block
# gets handed to ReviveSystem — no token gate, free at the point of use.
static func revive(session: CoopSession, character: CharacterData, local_player_id: String) -> bool:
	if character == null:
		return false
	var target := target_for(session, character, local_player_id)
	if target == null:
		return false
	ReviveSystem.revive(target)
	return true
