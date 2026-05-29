class_name DailyLoginPopup
extends CanvasLayer

# Daily-login claim popup (PRD #237 / issue #243). Presentation only — given
# a DailyStreakEngine.resolve() result, renders the background art, today's
# focal reward, a next-3-days preview row, and (on a missed-streak reset) a
# broken-streak banner before the Day 1 claim. The Claim button emits
# `claimed`; the wiring slice (#244) owns the reward applier call and
# dismissal — see _on_claim_pressed below for the self-dismiss fallback.
#
# Cloned shape from CongratulationsScreen: CanvasLayer + dimmed ColorRect +
# centered PanelContainer, process_mode = PROCESS_MODE_ALWAYS so it shows
# over the main menu without depending on tree pause state.

signal claimed

const _ART_BASE := preload("res://assets/base_wizard_study.png")
const _ART_DAY30 := preload("res://assets/day30_jackpot.png")
const _ART_FOCAL_GOLD := preload("res://assets/focal_gold_chest.png")
const _ART_FOCAL_XP := preload("res://assets/focal_xp_spellbook.png")
const _ART_FOCAL_GEM := preload("res://assets/focal_gem_jar.png")

var _background: TextureRect
var _broken_banner: Label
var _day_label: Label
var _focal_image: TextureRect
var _reward_label: Label
var _preview_row: HBoxContainer
var _claim_button: Button
var _panel: PanelContainer
var _claimed_already := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_background = $Backdrop/Panel/Background
	_broken_banner = $Backdrop/Panel/VBox/BrokenBanner
	_day_label = $Backdrop/Panel/VBox/DayLabel
	_focal_image = $Backdrop/Panel/VBox/ScrollContent/InnerVBox/Focal
	_reward_label = $Backdrop/Panel/VBox/ScrollContent/InnerVBox/RewardLabel
	_preview_row = $Backdrop/Panel/VBox/ScrollContent/InnerVBox/Preview
	_claim_button = $Backdrop/Panel/VBox/ClaimButton
	_panel = $Backdrop/Panel
	_claim_button.pressed.connect(_on_claim_pressed)

# Populate from a DailyStreakEngine.resolve() result. Safe to call before or
# after _ready — defers if nodes aren't bound yet (mirrors the
# CongratulationsScreen.populate null-guard pattern).
func populate(result: Dictionary) -> void:
	if _day_label == null:
		call_deferred("populate", result)
		return
	var day := int(result.get("day", 0))
	var reward: Dictionary = result.get("reward", {})
	var reset_reason := int(result.get("reset_reason", DailyStreakEngine.ResetReason.NONE))
	var previous_streak := int(result.get("previous_streak", 0))

	var is_jackpot := day == 30
	_background.texture = _ART_DAY30 if is_jackpot else _ART_BASE

	_day_label.text = "Day %d" % day if day > 0 else ""

	if reset_reason == DailyStreakEngine.ResetReason.MISSED:
		_broken_banner.visible = true
		_broken_banner.text = "Your streak was broken — starting fresh! (was Day %d)" % previous_streak
	else:
		_broken_banner.visible = false
		_broken_banner.text = ""

	_focal_image.texture = _focal_texture_for(reward)
	_reward_label.text = _format_reward(reward)

	_populate_preview(day)

func _focal_texture_for(reward: Dictionary) -> Texture2D:
	if reward == null or reward.is_empty():
		return null
	match int(reward.get("type", -1)):
		DailyStreakSchedule.RewardType.GOLD:
			return _ART_FOCAL_GOLD
		DailyStreakSchedule.RewardType.XP:
			return _ART_FOCAL_XP
		DailyStreakSchedule.RewardType.GEM:
			return _ART_FOCAL_GEM
		_:
			return null

func _format_reward(reward: Dictionary) -> String:
	if reward == null or reward.is_empty():
		return ""
	var amount := int(reward.get("amount", 0))
	match int(reward.get("type", -1)):
		DailyStreakSchedule.RewardType.GOLD:
			return "+%d Gold" % amount
		DailyStreakSchedule.RewardType.XP:
			return "+%d XP" % amount
		DailyStreakSchedule.RewardType.GEM:
			return "+%d Gems" % amount
		_:
			return ""

# Renders rows for day+1, day+2, day+3. DailyStreakSchedule.reward_for
# clamps overshoot at 30, so probing past the cycle end is safe.
func _populate_preview(day: int) -> void:
	for child in _preview_row.get_children():
		child.queue_free()
	if day <= 0:
		return
	for offset in [1, 2, 3]:
		var next_day: int = day + offset
		if next_day > 30:
			break
		var reward := DailyStreakSchedule.reward_for(next_day)
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var day_lbl := Label.new()
		day_lbl.text = "Day %d" % next_day
		day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		day_lbl.add_theme_font_size_override("font_size", 10)
		day_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		day_lbl.add_theme_constant_override("outline_size", 3)
		cell.add_child(day_lbl)
		var icon := TextureRect.new()
		icon.texture = _focal_texture_for(reward)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(28, 28)
		cell.add_child(icon)
		var amount_lbl := Label.new()
		amount_lbl.text = _format_reward(reward)
		amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_lbl.add_theme_font_size_override("font_size", 10)
		amount_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		amount_lbl.add_theme_constant_override("outline_size", 3)
		cell.add_child(amount_lbl)
		_preview_row.add_child(cell)

func _on_claim_pressed() -> void:
	if _claimed_already:
		return
	_claimed_already = true
	_claim_button.disabled = true
	_play_claim_animation()

# Brief pop-and-fade on the panel as the claim feedback. Tween auto-frees
# itself; on completion we emit `claimed` and dismiss. Wiring (#244) listens
# for the signal — the popup dismisses itself so callers don't need to.
func _play_claim_animation() -> void:
	_panel.pivot_offset = _panel.size * 0.5
	var tween := create_tween()
	tween.tween_property(_panel, "scale", Vector2(1.15, 1.15), 0.12).from(Vector2.ONE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(_finish_claim)

func _finish_claim() -> void:
	claimed.emit()
	queue_free()
