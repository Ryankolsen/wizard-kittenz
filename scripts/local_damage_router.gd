class_name LocalDamageRouter
extends RefCounted

# Per-client damage routing helper. Routes incoming damage (an enemy
# hitting the local player) to the right CharacterData block:
#   - solo / no co-op session: damage hits the player's CharacterData
#     directly (real_stats == effective_stats in solo).
#   - active co-op session: damage hits the local PartyMember's
#     effective_stats (the scaled view). real_stats stays unmodified
#     so the player's persistent character (what's saved, what XP
#     applies to via LocalXPRouter) doesn't carry residual scaled
#     damage out of the run when end() restores scaling.
#
# Sibling-shaped to LocalXPRouter:
#   - LocalXPRouter applies XP to real_stats (use_real_level=true), so
#     a scaled L10 player progresses toward L11 even when their
#     effective_stats stays scaled. (#18 AC#3)
#   - LocalDamageRouter applies damage to effective_stats.hp (the
#     scaled view), so taking damage in a scaled session matches the
#     HUD's scaled HP bar display (when the HP bar rewires to read
#     effective_stats — sibling commit gap noted in 2f38e2f).
#
# Why a separate router (vs. inline branching in Player.gd or in
# DamageResolver):
#   - DamageResolver is general-purpose: it computes mitigated damage
#     and calls target.take_damage(int). It doesn't know about co-op
#     scaling vs. solo. Inlining the branch there would force every
#     caller (enemy attack, spell self-damage, future hazards) to pay
#     for routing they don't need, and would obscure the rule.
#   - In Player.gd / Enemy.gd as inline branching, the routing rule
#     would be hidden in the scene-tree node, untestable in isolation
#     without spawning the scene. The router is RefCounted + all-
#     static so a unit test pins the routing contract without booting
#     a scene.
#   - Same shape as KillRewardRouter (the OUTBOUND seam for kills):
#     RefCounted, all-static, is_coop_route predicate + main routing
#     method. Both helpers branch on the same gates (session non-null
#     + active + local_player_id non-empty + member found), so a
#     refactor of one stays in lockstep with the other.
#
# What this does NOT do:
#   - Touch the scene tree. The Player node's _check_died / died-signal
#     pipe is unchanged; this helper just decides which CharacterData
#     block the damage call lands on.
#   - Apply healing. Heal routing is a sibling concern — solo and co-op
#     both want heals to land on the "current view" of HP, but the
#     contract is that heals can't exceed max_hp, which differs between
#     real_stats and effective_stats. A future LocalHealRouter would
#     be the symmetric helper; outside this commit's scope.
#   - Adjust attacker stats. The attacker's `attack` is read raw — a
#     future "scaled enemy attack" rule (per-floor difficulty curve)
#     would be a separate seam, not part of the routing decision.
#   - Apply damage to remote players. Each client routes damage on its
#     own member — a remote kitten taking damage on its own client is
#     that client's concern. The local router only cares about the
#     local member.

# Whether the "co-op active" branch should fire. Pulled out as a static
# so a test can pin the predicate without exercising the whole damage
# path. A session that exists but isn't active (constructed but start()
# not yet called, or already end()ed) takes the solo branch.
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

# Returns the CharacterData block that damage should land on. Pure
# branching; does NOT mutate state. Solo path returns the input
# character (real_stats). Co-op path returns the local member's
# effective_stats (scaled view). Defensive fall-through to character
# when the member's effective_stats is null (uninitialized member —
# from_character always sets effective_stats so this is a defense-
# in-depth, not a normal path).
static func target_for(session: CoopSession, character: CharacterData, local_player_id: String) -> CharacterData:
	if character == null:
		return null
	if not is_coop_route(session, local_player_id):
		return character
	var member := session.member_for(local_player_id)
	if member == null or member.effective_stats == null:
		return character
	return member.effective_stats

# Applies damage from attacker_stats to the routed target. Returns the
# damage actually dealt (post-mitigation). Null attacker / null
# character degrade to 0 — same shape as KillRewardRouter's null-safe
# fall-through. The DamageResolver.apply contract handles raw-attack
# zero / negative as a no-op (returns 0).
static func apply_damage(session: CoopSession, attacker_stats, character: CharacterData, local_player_id: String, rng: RandomNumberGenerator = null) -> int:
	if attacker_stats == null or character == null:
		return 0
	var target := target_for(session, character, local_player_id)
	if target == null:
		return 0
	return DamageResolver.apply(attacker_stats, target, rng)
