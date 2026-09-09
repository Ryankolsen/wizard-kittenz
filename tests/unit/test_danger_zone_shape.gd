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


func test_disc_contains_centre_point_during_commit():
	# Test 1 (core wiring, issue #571): a disc built from an origin + radius
	# contains its own centre once it commits.
	var disc := DangerZoneShape.make_disc(Vector2(20.0, 30.0), 40.0, 0.7, 0.2, 0.3)
	assert_true(disc.contains(Vector2(20.0, 30.0), 0.8),
		"the disc's centre must be inside the zone at commit")


func test_disc_boundary_is_inclusive():
	# Test 2 (boundary, issue #571): a point just inside the radius is
	# contained, one just outside is not, and a point exactly on the radius
	# resolves consistently. Boundary is inclusive, matching the lane's own
	# inclusive half-width boundary above.
	var disc := DangerZoneShape.make_disc(Vector2.ZERO, 50.0, 0.7, 0.2, 0.3)
	var commit_t := 0.8
	assert_true(disc.contains(Vector2(49.0, 0.0), commit_t),
		"a point just inside the radius must be inside the zone")
	assert_false(disc.contains(Vector2(51.0, 0.0), commit_t),
		"a point just outside the radius must be outside the zone")
	assert_true(disc.contains(Vector2(50.0, 0.0), commit_t),
		"a point exactly on the radius must count as inside (inclusive boundary)")


func test_disc_is_harmless_during_windup_and_fade():
	# Test 3 (phase gating, issue #571): the "drawn but harmless" rule the lane
	# already holds — the centre point must not be contained during wind-up or
	# fade, only during commit.
	var disc := DangerZoneShape.make_disc(Vector2.ZERO, 40.0, 0.7, 0.2, 0.3)
	var centre := Vector2.ZERO
	assert_false(disc.contains(centre, 0.3),
		"a disc winding up must not damage its centre")
	assert_true(disc.contains(centre, 0.8),
		"the same centre must be inside once the disc commits")
	assert_false(disc.contains(centre, 1.0),
		"a disc that has committed and moved into fade must no longer damage")


func test_disc_edge_cases_zero_radius_negative_radius_and_expiry():
	# Test 4 (edge cases, issue #571): zero radius, negative radius (clamped
	# like make_lane clamps its inputs), and is_expired past total_duration.
	var zero_radius := DangerZoneShape.make_disc(Vector2.ZERO, 0.0, 0.7, 0.2, 0.3)
	assert_false(zero_radius.contains(Vector2(1.0, 0.0), 0.8),
		"a zero-radius disc must not contain a point off its exact centre")
	var negative_radius := DangerZoneShape.make_disc(Vector2.ZERO, -10.0, 0.7, 0.2, 0.3)
	assert_eq(negative_radius.radius, 0.0,
		"a negative radius must clamp to zero, matching make_lane's clamping style")
	var disc := DangerZoneShape.make_disc(Vector2.ZERO, 40.0, 0.7, 0.2, 0.3)
	assert_true(disc.is_expired(1.3), "a disc past total_duration must report expired")


func test_disc_outline_is_a_polygon_the_renderer_can_draw():
	# Disc joins lane/tether in reporting an outline() the renderer draws, using
	# the same shared amber wind-up / red commit colours.
	var disc := DangerZoneShape.make_disc(Vector2(10.0, 10.0), 40.0, 0.7, 0.2, 0.3)
	var points: PackedVector2Array = disc.outline()
	assert_gt(points.size(), 3, "a disc must outline as a many-sided polygon, not a degenerate shape")
	for p in points:
		assert_almost_eq(p.distance_to(Vector2(10.0, 10.0)), 40.0, 0.5,
			"every outline point must sit on the disc's own radius")
	var windup: Color = disc.color_at(0.3)
	var commit: Color = disc.color_at(0.8)
	assert_gt(windup.g, windup.b, "the disc's wind-up colour is the shared amber, not blue")
	assert_gt(commit.r, commit.g, "the disc's commit colour is the shared red flash")


func test_ring_outer_radius_is_contained_once_the_expanding_edge_reaches_it():
	# Test 1 (core wiring, issue #573): a ring built from an origin + max
	# radius contains a point once the expanding edge sweeps out to it. Using
	# windup 0.7 / commit 1.0, the edge reaches 95 of a 100 max radius at
	# t = 1.65 (95% of the way through the commit window).
	var ring := DangerZoneShape.make_ring(Vector2.ZERO, 100.0, 20.0, 0.7, 1.0, 0.3)
	assert_true(ring.contains(Vector2(95.0, 0.0), 1.65),
		"a point the expanding edge has just reached must be inside the zone")


func test_ring_mid_radius_point_is_safe_early_and_caught_later():
	# Test 2 (expansion over time, issue #573): this is what separates the ring
	# from the disc. A point at a mid radius (50 of a 100 max radius, 20 wide
	# band) is not yet inside the zone shortly after commit begins (edge at 5),
	# but is inside once the edge has grown out to meet it (edge at 50, t=1.2).
	var ring := DangerZoneShape.make_ring(Vector2.ZERO, 100.0, 20.0, 0.7, 1.0, 0.3)
	var mid_point := Vector2(50.0, 0.0)
	assert_false(ring.contains(mid_point, 0.75),
		"a mid-radius point must not be hit before the expanding edge reaches it")
	assert_true(ring.contains(mid_point, 1.2),
		"the same mid-radius point must be hit once the expanding edge reaches it")


func test_ring_inner_point_is_safe_once_the_wave_has_passed():
	# Test 3 (inner safety, issue #573): standing at the boss's own feet after
	# the wave has swept outward past that point must be safe.
	var ring := DangerZoneShape.make_ring(Vector2.ZERO, 100.0, 20.0, 0.7, 1.0, 0.3)
	var near_origin := Vector2(2.0, 0.0)
	assert_false(ring.contains(near_origin, 1.6),
		"a point near the boss's feet must be safe once the expanding edge has passed it")


func test_ring_is_harmless_during_windup_and_fade():
	# Test 4 (phase gating, issue #573): drawn-but-harmless during wind-up, and
	# harmless again once it fades, matching every other shape's rule.
	var ring := DangerZoneShape.make_ring(Vector2.ZERO, 100.0, 20.0, 0.7, 1.0, 0.3)
	var outer_point := Vector2(95.0, 0.0)
	assert_false(ring.contains(outer_point, 0.3),
		"a ring winding up must not damage any point")
	assert_false(ring.contains(outer_point, 1.8),
		"a ring that has committed and moved into fade must no longer damage")


func test_ring_threading_does_not_regress_lane_tether_or_disc():
	# Test 5 (no regression, issue #573): threading time through
	# _contains_geometry must not disturb the existing shapes' own containment.
	var lane := DangerZoneShape.make_lane(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	assert_true(lane.contains(Vector2(50.0, 0.0), 0.8),
		"lane containment must be unaffected by the ring's time threading")
	var tether := DangerZoneShape.make_tether(
		Vector2(10.0, 10.0), Vector2(110.0, 10.0), 16.0, 0.7, 0.2, 0.3)
	assert_true(tether.contains(Vector2(60.0, 10.0), 0.8),
		"tether containment must be unaffected by the ring's time threading")
	var disc := DangerZoneShape.make_disc(Vector2(20.0, 30.0), 40.0, 0.7, 0.2, 0.3)
	assert_true(disc.contains(Vector2(20.0, 30.0), 0.8),
		"disc containment must be unaffected by the ring's time threading")


func test_ring_edge_cases_zero_radius_zero_commit_and_past_total_duration():
	# Test 6 (edge cases, issue #573): zero max radius, zero commit duration,
	# and a query past total_duration.
	var zero_radius := DangerZoneShape.make_ring(Vector2.ZERO, 0.0, 20.0, 0.7, 1.0, 0.3)
	assert_false(zero_radius.contains(Vector2(100.0, 0.0), 1.2),
		"a zero max-radius ring must not contain a point far from the origin")
	var zero_commit := DangerZoneShape.make_ring(Vector2.ZERO, 100.0, 20.0, 0.7, 0.0, 0.3)
	assert_false(zero_commit.contains(Vector2(50.0, 0.0), 0.75),
		"a zero commit duration never enters the damage window, so nothing is ever hit")
	var ring := DangerZoneShape.make_ring(Vector2.ZERO, 100.0, 20.0, 0.7, 1.0, 0.3)
	assert_true(ring.is_expired(2.5), "a ring queried past total_duration must report expired")
	assert_false(ring.contains(Vector2(95.0, 0.0), 2.5),
		"a ring past its total_duration must never damage")


func test_ring_outline_can_be_drawn_at_both_start_and_end_of_expansion():
	# The ring reports an outline() the renderer can draw across the whole
	# expansion, not just its final size.
	var ring := DangerZoneShape.make_ring(Vector2(10.0, 10.0), 100.0, 20.0, 0.7, 1.0, 0.3)
	var early: PackedVector2Array = ring.outline(0.75)  # edge at 5
	var late: PackedVector2Array = ring.outline(1.65)  # edge at 95
	assert_gt(early.size(), 3, "the ring must outline as a many-sided polygon early in expansion")
	assert_gt(late.size(), 3, "the ring must outline as a many-sided polygon late in expansion")
	for p in early:
		assert_almost_eq(p.distance_to(Vector2(10.0, 10.0)), 5.0, 0.5,
			"early outline points must sit on the edge's current (small) radius")
	for p in late:
		assert_almost_eq(p.distance_to(Vector2(10.0, 10.0)), 95.0, 0.5,
			"late outline points must sit on the edge's current (large) radius")


func test_cone_contains_a_point_ahead_within_length_during_commit():
	# Test 1 (core wiring, issue #576): a cone built from an origin + facing +
	# length + half-angle contains a point directly ahead, inside its length,
	# once it commits.
	var cone := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 30.0, 0.7, 0.2, 0.3)
	var commit_t := 0.8
	assert_true(cone.contains(Vector2(80.0, 0.0), commit_t),
		"a point directly ahead within the cone's length must be inside the zone at commit")


func test_cone_angle_boundary_is_inclusive_and_behind_is_never_contained():
	# Test 2 (angle boundary, issue #576): a point just inside the half-angle
	# is contained, one just outside is not, and a point directly behind the
	# origin — the case that makes flanking a real counter — is never
	# contained regardless of half-angle.
	var cone := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 30.0, 0.7, 0.2, 0.3)
	var commit_t := 0.8
	var inside_angle := deg_to_rad(29.0)
	var outside_angle := deg_to_rad(31.0)
	var inside_point := Vector2(50.0, 0.0).rotated(inside_angle)
	var outside_point := Vector2(50.0, 0.0).rotated(outside_angle)
	assert_true(cone.contains(inside_point, commit_t),
		"a point just inside the half-angle must be inside the zone")
	assert_false(cone.contains(outside_point, commit_t),
		"a point just outside the half-angle must be outside the zone")
	assert_false(cone.contains(Vector2(-50.0, 0.0), commit_t),
		"a point directly behind the origin must never be contained, which is what makes flanking work")


func test_cone_length_boundary_excludes_points_beyond_it():
	# Test 3 (length boundary, issue #576): a point on the centre line beyond
	# the cone's length is not contained.
	var cone := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 30.0, 0.7, 0.2, 0.3)
	assert_false(cone.contains(Vector2(150.0, 0.0), 0.8),
		"a point on the centre line beyond the cone's length must be outside the zone")


func test_cone_is_harmless_during_windup_and_fade():
	# Test 4 (phase gating, issue #576): the "drawn but harmless" rule every
	# other shape holds — a point straight ahead is not contained during
	# wind-up or fade, only during commit.
	var cone := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 30.0, 0.7, 0.2, 0.3)
	var point := Vector2(50.0, 0.0)
	assert_false(cone.contains(point, 0.3),
		"a cone winding up must not damage a point ahead of it")
	assert_true(cone.contains(point, 0.8),
		"the same point must be inside once the cone commits")
	assert_false(cone.contains(point, 1.0),
		"a cone that has committed and moved into fade must no longer damage")


func test_cone_edge_cases_zero_half_angle_wide_half_angle_zero_length_and_zero_facing():
	# Test 5 (edge cases, issue #576): zero half-angle collapses the cone to
	# its centre line; a half-angle at or above 180 degrees must still never
	# contain a point directly behind the origin; zero length excludes every
	# point but the origin itself; and a zero-length facing vector falls back
	# to a stable default the way make_lane falls back to Vector2.RIGHT.
	var zero_half_angle := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 0.0, 0.7, 0.2, 0.3)
	assert_true(zero_half_angle.contains(Vector2(50.0, 0.0), 0.8),
		"a zero half-angle cone must still contain a point exactly on its centre line")
	var wide_half_angle := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 100.0, 200.0, 0.7, 0.2, 0.3)
	assert_false(wide_half_angle.contains(Vector2(-50.0, 0.0), 0.8),
		"a half-angle at or above 180 degrees must still never contain a point directly behind the origin")
	var zero_length := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.RIGHT, 0.0, 30.0, 0.7, 0.2, 0.3)
	assert_false(zero_length.contains(Vector2(1.0, 0.0), 0.8),
		"a zero-length cone must not contain a point ahead of its exact origin")
	var zero_facing := DangerZoneShape.make_cone(
		Vector2.ZERO, Vector2.ZERO, 100.0, 30.0, 0.7, 0.2, 0.3)
	assert_eq(zero_facing.heading, Vector2.RIGHT,
		"a zero-length facing vector must fall back to Vector2.RIGHT, matching make_lane's fallback")


func test_cone_outline_is_a_polygon_the_renderer_can_draw():
	# The cone reports an outline() the renderer can draw, approximating the
	# arc as a polygon, using the same shared amber wind-up / red commit
	# colours every other shape reports.
	var cone := DangerZoneShape.make_cone(
		Vector2(10.0, 10.0), Vector2.RIGHT, 100.0, 30.0, 0.7, 0.2, 0.3)
	var points: PackedVector2Array = cone.outline()
	assert_gt(points.size(), 3, "a cone must outline as a many-sided polygon, not a degenerate shape")
	var windup: Color = cone.color_at(0.3)
	var commit: Color = cone.color_at(0.8)
	assert_gt(windup.g, windup.b, "the cone's wind-up colour is the shared amber, not blue")
	assert_gt(commit.r, commit.g, "the cone's commit colour is the shared red flash")


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
