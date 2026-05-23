class_name RemoteItemDropResolver
extends RefCounted

# Inbound-from-wire counterpart to the item-drop side of KillRewardRouter
# (Slice 7 of PRD #201). Co-op fan-out for item drops: when a remote kill
# packet arrives, each receiving client rolls its own item drop locally
# against its own CharacterData. The roll is independent per-client — one
# player's drop does not influence another's, and items are never carried
# on the wire (only the boss flag is, so receivers pick the right Context).
#
# Pure data — RefCounted with a single static, same shape as
# RemoteKillApplier. Lets unit tests exercise the per-class fan-out matrix
# without a SceneTree.
#
# Wraps the same two-step shape KillRewardRouter uses for the killer's
# local roll: ItemDropResolver.resolve(...) → LuckRewardModifier.bump_item.
# Reusing both keeps the killer and the receiving clients on the same
# rarity-and-luck contract; a future tweak to the luck bump applies
# uniformly across the party.
#
# Null-safe across the board: null character or null rng degrade through
# ItemDropResolver's own null guards. Empty character class (pre-handshake
# / freshly-cleared GameState) returns null because the class-filtered
# pool is empty for a -1 sentinel.

static func resolve(
	character: CharacterData,
	is_boss: bool,
	rng: RandomNumberGenerator = null,
) -> ItemData:
	if character == null:
		return null
	var context: int = ItemDropResolver.Context.BOSS if is_boss else ItemDropResolver.Context.ENEMY
	var item: ItemData = ItemDropResolver.resolve(character, context, rng)
	# Same luck-bump pass as KillRewardRouter so the killer and remote
	# clients share the rarity-bump contract. bump_item is null-safe and
	# no-ops on luck<=0 / EPIC drops.
	item = LuckRewardModifier.bump_item(item, character.luck, rng)
	return item
