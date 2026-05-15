class_name RemoteKitten
extends Node2D

# Visual stand-in for a remote co-op player. One node per other player_id
# in the lobby; spawned and freed by CoopPlayerLayer as the lobby roster
# changes. Reads its position from NetworkSyncManager each frame so the
# already-tested interpolation contract drives the rendering, rather than
# duplicating the lerp here.
#
# Lifecycle:
#   1. CoopPlayerLayer instantiates the scene, assigns player_id /
#      kitten_name / network_sync / tint_color, and adds it as a child.
#   2. _ready hooks the placeholder polygon's modulate to tint_color and
#      the Label's text to kitten_name (also exposed at runtime so the
#      layer can update them mid-session if a future PLAYER_INFO packet
#      changes the name).
#   3. _process samples network_sync.get_display_position_at(player_id, now)
#      each frame; the interpolator handles "no sample yet" (returns
#      Vector2.ZERO so the kitten stays at origin until the first packet
#      lands) and "freshest sample only" (no lerp; kitten pops at first
#      known location).
#   4. CoopPlayerLayer calls queue_free on roster removal.

@export var player_id: String = ""
@export var kitten_name: String = ""
@export var tint_color: Color = Color(1, 1, 1, 1)
# Untyped to avoid a script-level dependency on NetworkSyncManager — RefCounted
# refs round-trip through @export poorly. CoopPlayerLayer assigns this
# directly after instantiate(). Null is treated as "no sync source" and the
# kitten freezes at its current position rather than crashing.
var network_sync = null

@onready var _placeholder: Polygon2D = get_node_or_null("Placeholder")
@onready var _label: Label = get_node_or_null("Label")

func _ready() -> void:
	# Join the taunt-targets group so Enemy._select_taunt_target_by_id can
	# locate this remote kitten by player_id when a TAUNT is applied with a
	# matching taunt_source_id. The local Player joins the same group; both
	# expose a player_id field and a global_position, which is everything the
	# enemy's targeting path needs (contact damage no-ops on non-Player nodes).
	add_to_group("taunt_targets")
	if _placeholder != null:
		_placeholder.modulate = tint_color
	if _label != null:
		_label.text = kitten_name

func _process(_delta: float) -> void:
	if network_sync == null or player_id == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	position = network_sync.get_display_position_at(player_id, now)
