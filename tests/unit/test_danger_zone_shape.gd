extends GutTest

# DangerZoneShape (PRD #518 / tracer slice #533). Pure-geometry module that is
# simultaneously the telegraph renderer's data source and the damage authority
# — "drawn equals hit". No SceneTree: every case below drives the module
# directly, matching the inline-mock style of test_enemy_behavior.gd.


func test_lane_contains_centreline_point_and_excludes_beyond_half_width():
	# Acceptance #1 (core wiring / drawn-equals-hit): a lane built from an
	# origin + heading + length/width contains a point on its centreline and
	# excludes one perpendicular beyond half-width.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	var commit_t := 0.8  # inside the commit window (0.7 -> 0.9)
	assert_true(
		lane.contains(Vector2(50.0, 0.0), commit_t),
		"point on the centreline mid-lane must be inside the zone")
	assert_false(
		lane.contains(Vector2(50.0, 11.0), commit_t),
		"point perpendicular beyond half-width must be outside the zone")


func test_lane_reports_windup_then_commit_then_fade():
	# Acceptance #2 (phase timing): the three-phase lifecycle is a function of
	# elapsed time, and the same point is harmless during the wind-up (so the
	# player can walk clear of a zone that is already drawn) and harmful once
	# the zone commits.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	var point := Vector2(50.0, 0.0)
	assert_eq(lane.phase_at(0.3), DangerZoneShape.Phase.WINDUP,
		"before the wind-up duration elapses the zone is winding up")
	assert_eq(lane.phase_at(0.8), DangerZoneShape.Phase.COMMIT,
		"inside the damage window the zone is committed")
	assert_eq(lane.phase_at(1.0), DangerZoneShape.Phase.FADE,
		"after the damage window the zone is fading")
	assert_false(lane.contains(point, 0.3),
		"a drawn-but-unwound zone must not damage a point inside it")
	assert_true(lane.contains(point, 0.8),
		"the same point must be inside once the zone commits")


func test_tether_contains_along_the_line_and_pulls_toward_the_enemy():
	# Acceptance #3 (tether): the Vacuum's pull is a line from the enemy to the
	# locked target position. A point on that line is inside it at commit, and
	# the pull direction the zone reports points from the player back toward
	# the enemy — the drag the Pull archetype applies.
	var enemy_pos := Vector2(10.0, 10.0)
	var locked_target := Vector2(110.0, 10.0)
	var tether := DangerZoneShape.make_tether(
		enemy_pos, locked_target, 16.0, 0.7, 0.2, 0.3)
	var commit_t := 0.8
	assert_true(tether.contains(Vector2(60.0, 10.0), commit_t),
		"a point on the tether line must be inside the zone at commit")
	assert_false(tether.contains(Vector2(60.0, 40.0), commit_t),
		"a point well off the tether line must be outside the zone")
	assert_eq(tether.pull_direction(Vector2(110.0, 10.0)), Vector2.LEFT,
		"pull direction must point from the player toward the enemy")


# Stand-in for the moving target an ability locks onto at telegraph start.
class _MockTarget:
	var global_position: Vector2 = Vector2.ZERO


func test_lane_geometry_is_locked_at_telegraph_start():
	# Acceptance #4 (content details): the lane is a snapshot. Moving the
	# target after the wind-up begins must not drag the drawn corridor with it,
	# otherwise sidestepping could never work.
	var target := _MockTarget.new()
	target.global_position = Vector2(100.0, 0.0)
	var enemy_pos := Vector2.ZERO
	var span: Vector2 = target.global_position - enemy_pos
	var lane := DangerZoneShape.make_lane(
		enemy_pos, span, span.length(), 20.0, 0.7, 0.2, 0.3)
	var start_origin := lane.origin
	var start_endpoint := lane.endpoint()
	# Player walks away mid-telegraph.
	target.global_position = Vector2(0.0, 400.0)
	assert_eq(lane.origin, start_origin, "lane origin must not follow the target")
	assert_almost_eq(lane.endpoint().x, start_endpoint.x, 0.001,
		"lane endpoint must not follow the target")
	assert_almost_eq(lane.endpoint().y, start_endpoint.y, 0.001,
		"lane endpoint must not follow the target")
	assert_false(lane.contains(target.global_position, 0.8),
		"a target that walked clear of the locked lane must not be hit")


func test_zero_length_lane_contains_nothing_downrange():
	# Edge case: a degenerate lane (target on top of the enemy) must not
	# swallow the whole map.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 0.0, 20.0, 0.7, 0.2, 0.3)
	assert_false(lane.contains(Vector2(5.0, 0.0), 0.8),
		"a zero-length lane must not contain a downrange point")


func test_zero_width_lane_excludes_points_off_the_centreline():
	# Edge case: zero width degenerates to the centreline itself.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 0.0, 0.7, 0.2, 0.3)
	assert_false(lane.contains(Vector2(50.0, 0.5), 0.8),
		"a zero-width lane must not contain a point off its centreline")


func test_point_exactly_on_the_boundary_is_inside():
	# Edge case: the boundary is inclusive, so "drawn equals hit" holds for the
	# outermost pixel the renderer fills rather than a hair inside it.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	assert_true(lane.contains(Vector2(50.0, 10.0), 0.8),
		"a point exactly on the half-width boundary must count as inside")


func test_negative_and_past_fade_times_never_damage():
	# Edge case: a query outside the lifecycle window is harmless in both
	# directions — before the zone exists and after it has faded out.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	assert_false(lane.contains(Vector2(50.0, 0.0), -1.0),
		"a negative-time query must never damage")
	assert_false(lane.contains(Vector2(50.0, 0.0), 99.0),
		"a past-fade query must never damage")


func test_outline_corners_bound_exactly_what_contains_reports():
	# The renderer draws `outline()` and damage asks `contains()`. Both come
	# from this module, and the corners are the half-width rectangle around the
	# locked segment — a lane along +X from the origin, 100 long and 20 wide,
	# has corners at (0,+-10) and (100,+-10).
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	var corners: PackedVector2Array = lane.outline()
	assert_eq(corners.size(), 4, "a lane outlines as a quad")
	assert_eq(corners[0], Vector2(0.0, -10.0), "near-left corner")
	assert_eq(corners[1], Vector2(100.0, -10.0), "far-left corner")
	assert_eq(corners[2], Vector2(100.0, 10.0), "far-right corner")
	assert_eq(corners[3], Vector2(0.0, 10.0), "near-right corner")


func test_colour_language_is_amber_during_windup_and_red_at_commit():
	# Acceptance (colour language, uniform across every enemy): amber while
	# winding up, red once it commits, and transparent once it has faded out.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	var windup: Color = lane.color_at(0.3)
	var commit: Color = lane.color_at(0.8)
	assert_gt(windup.g, windup.b, "the wind-up colour is amber, not blue")
	assert_gt(commit.r, commit.g, "the commit colour flashes red")
	assert_almost_eq(lane.color_at(1.2).a, 0.0, 0.05,
		"the zone is fully transparent once it has faded")
