class_name CoopRouter
extends RefCounted

# Single-seam solo/co-op event router. Decides which CharacterData block
# game events (damage, revive) should land on:
#   - solo / no co-op session: events hit the player's CharacterData
#     directly (real_stats == effective_stats in solo).
#   - active co-op session: events hit the local PartyMember's
#     effective_stats (the scaled view). real_stats stays unmodified
#     so the persistent character (what's saved, what XP applies to
#     via CoopXPSubscriber) doesn't carry residual scaled damage out
#     of the run when end() restores scaling.
#
# Consolidates LocalDamageRouter + LocalReviveRouter into one module so
# the solo/co-op branch rule lives in one place. Sibling-shaped to
# KillRewardRouter (the OUTBOUND seam for kills): RefCounted, all-
# static, delegates to session.is_routing_ready() for the co-op gate.
#
# Distinct from CoopXPSubscriber (the XP path) — XP is a stateful
# signal subscription with a bind/unbind lifecycle, whereas damage and
# revive are pure branching decisions that don't need an instance.

# Returns the CharacterData block that an event should land on. Pure
# branching; does NOT mutate state. Solo path returns the input
# character (real_stats). Co-op path returns the local member's
# effective_stats (scaled view). Defensive fall-through to character
# when the member's effective_stats is null (uninitialized member —
# from_character always sets effective_stats so this is defense-in-
# depth, not a normal path).
static func target_for(session: CoopSession, character: CharacterData, local_player_id: String) -> CharacterData:
	if character == null:
		return null
	if session == null or not session.is_routing_ready():
		return character
	var member := session.member_for(local_player_id)
	if member == null or member.effective_stats == null:
		return character
	return member.effective_stats

# Applies damage from attacker_stats to the routed target. Returns the
# damage actually dealt (post-mitigation). Null attacker / null
# character degrade to 0. DamageResolver.apply handles raw-attack
# zero / negative as a no-op (returns 0).
static func apply_damage(session: CoopSession, attacker_stats, character: CharacterData, local_player_id: String, rng: RandomNumberGenerator = null) -> int:
	if attacker_stats == null or character == null:
		return 0
	var target := target_for(session, character, local_player_id)
	if target == null:
		return 0
	return CharacterMutator.new(target).apply_damage(attacker_stats, rng)

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
	CharacterMutator.new(target).revive()
	return true
