extends Node

# Autoload (PRD #596, issue #602). Two independent jobs:
#
# 1. queue_topic/consume_pending — a one-slot mailbox for topics whose steps
#    span a scene change (none of TutorialCatalog's topics need this today;
#    the mechanism exists for future topics that do). Last write wins; no
#    FIFO, since only one pending topic is ever needed at a time.
#
# 2. replay_topic — force-shows a topic's overlay right now regardless of
#    TutorialProgress seen-state, for the help-icon "replay" affordance. On
#    the overlay's `finished` signal, marks the topic seen and saves.
#
# This module doesn't call TutorialTrigger.should_trigger itself — each
# wiring slice decides when to trigger and either calls TutorialOverlay
# directly (immediate case) or queue_topic (deferred-across-scene case).

const TutorialOverlayScene := preload("res://scenes/tutorial_overlay.tscn")

var _pending_topic_id: String = ""

func queue_topic(topic_id: String) -> void:
	_pending_topic_id = topic_id

func consume_pending() -> String:
	var topic_id := _pending_topic_id
	_pending_topic_id = ""
	return topic_id

# Force-shows topic_id's overlay regardless of seen-state. On finish, marks
# it seen and saves (best-effort: save_from_state no-ops without an active
# character, which is fine since the help icon that calls this only exists
# in the dungeon HUD where a character is always active).
func replay_topic(topic_id: String) -> void:
	var overlay: Node = TutorialOverlayScene.instantiate()
	get_tree().root.add_child(overlay)
	overlay.finished.connect(_on_replay_finished)
	overlay.open(topic_id)

func _on_replay_finished(topic_id: String) -> void:
	GameState.tutorial_seen_topics = TutorialProgress.mark_seen(GameState.tutorial_seen_topics, topic_id)
	SaveManager.save_from_state()
