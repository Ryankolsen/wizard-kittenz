extends GutTest

# PRD #85 / issue #91 — FloatingText is the visual indicator surfaced
# when a physical attack returns 0 (miss/evade) from DamageResolver.
# Tests cover label content, fade-to-zero alpha over DURATION, rise
# direction, queue_free after expiry, and the static spawn helper.

func test_set_text_applies_to_label():
	var ft := FloatingText.new()
	add_child_autofree(ft)
	await get_tree().process_frame
	ft.set_text("Miss", Color(1, 0.6, 0.6))
	var label := ft.get_node("Label") as Label
	assert_eq(label.text, "Miss")
	assert_eq(label.modulate.r, 1.0)

func test_set_text_safe_before_ready():
	# Defensive: a caller that constructs a FloatingText and calls
	# set_text before _ready (no scene attach) shouldn't crash. The
	# label child is built lazily inside set_text in that case.
	var ft := FloatingText.new()
	ft.set_text("Miss")
	var label := ft.get_node_or_null("Label") as Label
	assert_not_null(label, "set_text builds the label lazily")
	assert_eq(label.text, "Miss")
	ft.free()

func test_rises_over_time():
	# Y decreases as the label rises. Use the static spawn helper so
	# this also exercises the wiring path the call sites use.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var ft := FloatingText.spawn(parent, "Miss")
	await get_tree().process_frame
	var start_y := ft.position.y
	ft._process(0.1)
	assert_lt(ft.position.y, start_y, "text rises (y decreases)")

func test_alpha_fades_to_zero_at_duration():
	var parent := Node2D.new()
	add_child_autofree(parent)
	var ft := FloatingText.spawn(parent, "Miss")
	await get_tree().process_frame
	var label := ft.get_node("Label") as Label
	# Half-way through, alpha is roughly 0.5
	ft._process(FloatingText.DURATION * 0.5)
	assert_almost_eq(label.modulate.a, 0.5, 0.05)

func test_queue_free_after_duration():
	# Tick past DURATION and the node should mark itself for free.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var ft := FloatingText.spawn(parent, "Miss")
	await get_tree().process_frame
	ft._process(FloatingText.DURATION + 0.01)
	# is_queued_for_deletion returns true after queue_free runs.
	assert_true(ft.is_queued_for_deletion(), "expires after DURATION")

func test_spawn_with_null_parent_returns_null():
	# Defensive guard — call sites pass node refs that could be null
	# in tests or edge transitions.
	var ft := FloatingText.spawn(null, "Miss")
	assert_null(ft)

func test_spawn_parents_to_target():
	# The text must be a child of the target node so it tracks the
	# enemy/player position for the short lifetime.
	var parent := Node2D.new()
	add_child_autofree(parent)
	var ft := FloatingText.spawn(parent, "Miss")
	assert_eq(ft.get_parent(), parent)
