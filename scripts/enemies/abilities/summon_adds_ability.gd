class_name SummonAddsAbility
extends EnemyAbility

# Summon adds archetype (PRD #518 / issue #537). Old Lady Pearl hangs back and
# calls in cats: every COOLDOWN seconds, while aggroed, it publishes a volley
# of 2-3 standard-mob entries (kind + spawn offset + a deterministic id) for
# the Enemy node to instantiate. The player's counter is "clear the adds or
# eat chip damage while pushing through to her."
#
# No danger zone: unlike Pull/TelegraphedCharge/Ambush this archetype has no
# wind-up telegraph of its own — the summoned cats are the tell, same as the
# catnip bag / spray cone never drawing a zone. `tick` does all the work
# inline (cooldown clock, cap check, publish), so `wants_to_fire`/`begin`
# never fire the base zone/wind-up machinery — `wants_to_fire` stays hard
# false to keep this ability out of the shared pump's begin() path.
#
# Determinism (PRD #518 "Co-op consistency" / issue #534's seeding scheme):
# `roll_summon_batch` seeds its own RandomNumberGenerator from the enemy's
# stable spawn id via EnemyBehavior.spawn_id_of, the same salted-hash scheme
# EnemyBehavior._ensure_rng uses for behavior RNG, so every co-op client rolls
# the same kinds/count/offsets in the same order. A distinct salt keeps this
# stream independent of the enemy's own behavior/wander RNGs.

const CAP: int = 4
const SUMMON_COOLDOWN: float = 8.0
const MIN_ADDS: int = 2
const MAX_ADDS: int = 3
const SPAWN_OFFSET_RADIUS: float = 40.0

const STANDARD_MOB_KINDS: Array = [
	EnemyData.EnemyKind.ANGRY_PIGEON,
	EnemyData.EnemyKind.ROGUE_ROOMBA,
	EnemyData.EnemyKind.DOG_KNIGHT,
	EnemyData.EnemyKind.CATNIP_DEALER,
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
]

const _SUMMON_RNG_SALT: String = "summon:"

# Volley published for the Enemy-side observer: Array[Dictionary{kind:int,
# position:Vector2, enemy_id:String}]. Cleared by the observer once consumed,
# same publish/consume shape as pending_hazard_position elsewhere.
var pending_summons: Array = []

var _cooldown: float
var _cap: int
var _elapsed: float = 0.0
var _alive_count: int = 0
var _next_add_index: int = 0
var _rng: RandomNumberGenerator = null


func _init(cooldown_seconds: float = SUMMON_COOLDOWN, cap: int = CAP) -> void:
	_cooldown = cooldown_seconds
	_cap = cap


func cooldown() -> float:
	return _cooldown


# This archetype never drives the shared zone/wind-up pump — firing is
# entirely inline in `tick`, matching CatnipDealerBehavior/
# HauntedSprayBottleBehavior's self-contained cadence.
func wants_to_fire() -> bool:
	return false


func alive_add_count() -> int:
	return _alive_count


# Called by the Enemy node when a summoned add dies, so the cap tracks reality
# rather than only ever growing. Best-effort per-client bookkeeping — co-op
# determinism here covers what gets summoned (kinds/count/offsets/ids), not
# live-synchronizing the cap itself (PRD #518 explicitly avoids new wire
# traffic for ability state).
func notify_add_died() -> void:
	_alive_count = maxi(0, _alive_count - 1)


func _ensure_summon_rng(enemy) -> RandomNumberGenerator:
	if _rng != null:
		return _rng
	_rng = RandomNumberGenerator.new()
	var eid := EnemyBehavior.spawn_id_of(enemy)
	if eid == "":
		_rng.randomize()
	else:
		_rng.seed = hash(_SUMMON_RNG_SALT + eid)
	return _rng


# Pure roll of one volley's (kind, offset) pairs, seeded from the enemy id.
# No cap or absolute position applied here — callers (tick/_publish_summons)
# clamp to the room remaining and translate offsets to world space. Exposed
# directly so determinism is testable without waiting out the cooldown.
func roll_summon_batch(enemy) -> Array:
	var rng := _ensure_summon_rng(enemy)
	var count := rng.randi_range(MIN_ADDS, MAX_ADDS)
	var entries: Array = []
	for _i in range(count):
		var kind = STANDARD_MOB_KINDS[rng.randi_range(0, STANDARD_MOB_KINDS.size() - 1)]
		var angle := rng.randf_range(0.0, TAU)
		var offset := Vector2(cos(angle), sin(angle)) * SPAWN_OFFSET_RADIUS
		entries.append({"kind": kind, "offset": offset})
	return entries


func tick(_delta: float, enemy) -> void:
	if enemy != null and enemy.get("state") == 3:  # EnemyAIState.State.DEAD
		return
	# Aggro gate (issue #261 / PRD #518): an IDLE Pearl must not accrue the
	# summon cadence — a freshly-loaded level can't be bombarded with adds the
	# player never provoked, and "adds do not summon after Pearl dies" falls
	# out of the DEAD check above plus DEAD never being aggroed anyway.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	_elapsed += _delta
	if _elapsed < _cooldown:
		return
	_elapsed = 0.0
	_publish_summons(enemy)


func _publish_summons(enemy) -> void:
	if enemy == null:
		return
	var origin = enemy.get("global_position")
	if origin == null:
		return
	var room := maxi(0, _cap - _alive_count)
	if room <= 0:
		return
	var batch := roll_summon_batch(enemy)
	if batch.size() > room:
		batch = batch.slice(0, room)
	var spawn_base := EnemyBehavior.spawn_id_of(enemy)
	for entry in batch:
		var add_id := "%s_add%d" % [spawn_base, _next_add_index]
		_next_add_index += 1
		pending_summons.append({
			"kind": entry.get("kind"),
			"position": (origin as Vector2) + (entry.get("offset") as Vector2),
			"enemy_id": add_id,
		})
		_alive_count += 1
