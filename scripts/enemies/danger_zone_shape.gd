class_name DangerZoneShape
extends RefCounted

# Danger-zone geometry (PRD #518 / tracer slice #533). One pure module owns the
# shape vocabulary, the three-phase lifecycle and the containment query, so the
# telegraph the player sees and the area that damages them cannot drift apart:
# the renderer draws what `outline()` reports and damage resolution asks
# `contains()` on the same instance. There is no separate Area2D hitbox.
#
# Geometry is a snapshot taken at telegraph start — the caller passes already-
# resolved world coordinates, so a target that keeps moving during the wind-up
# does not drag the zone along with it.

enum Kind {
	LANE,   # straight corridor: origin -> origin + heading * length, `width` wide
	TETHER, # line from the enemy to a locked target point, dragging the player in
	DISC,   # circle of `radius` around `origin` — the zone-denial archetype
	RING,   # expanding shockwave: an annulus of `width` around a radius that
	        # grows from 0 to `radius` across the commit window — the
	        # ground-slam archetype (issue #573)
}

enum Phase {
	WINDUP, # amber outline filling in; drawn but harmless
	COMMIT, # flash to red; the damage window
	FADE,   # fading out; harmless again
}

var kind: int = Kind.LANE
var origin: Vector2 = Vector2.ZERO
var heading: Vector2 = Vector2.RIGHT
var length: float = 0.0
var width: float = 0.0
var radius: float = 0.0
var windup_duration: float = 0.0
var commit_duration: float = 0.0
var fade_duration: float = 0.0


static func make_lane(
	lane_origin: Vector2,
	lane_heading: Vector2,
	lane_length: float,
	lane_width: float,
	windup: float,
	commit: float,
	fade: float
) -> DangerZoneShape:
	var s := DangerZoneShape.new()
	s.kind = Kind.LANE
	s.origin = lane_origin
	s.heading = lane_heading.normalized() if lane_heading != Vector2.ZERO else Vector2.RIGHT
	s.length = maxf(0.0, lane_length)
	s.width = maxf(0.0, lane_width)
	s.windup_duration = maxf(0.0, windup)
	s.commit_duration = maxf(0.0, commit)
	s.fade_duration = maxf(0.0, fade)
	return s


# Endpoint of the lane / tether in world space. Reported (rather than re-derived
# by callers) so the renderer and the damage query agree on the same segment.
func endpoint() -> Vector2:
	return origin + heading * length


func phase_at(t: float) -> int:
	if t < windup_duration:
		return Phase.WINDUP
	if t < windup_duration + commit_duration:
		return Phase.COMMIT
	return Phase.FADE


# True only while the zone is live AND the point is inside its geometry. The
# wind-up deliberately answers false: the zone is drawn so the player can walk
# clear, and it must not hurt anyone until it commits.
func contains(point: Vector2, t: float) -> bool:
	if phase_at(t) != Phase.COMMIT:
		return false
	return _contains_geometry(point, t)


# `t` is only ever consulted by the ring branch below — lane, tether and disc
# containment is a pure function of geometry and ignores it, so threading time
# through this signature (needed for the ring's radius-at-time containment)
# leaves those three shapes' own results unchanged.
func _contains_geometry(point: Vector2, t: float = 0.0) -> bool:
	if kind == Kind.RING:
		var edge := _ring_edge_radius(t)
		var dist := point.distance_to(origin)
		# Inclusive band edges, matching the lane's and disc's own inclusive
		# boundaries: the outermost pixel the renderer fills still counts.
		return absf(dist - edge) <= width * 0.5
	if kind == Kind.DISC:
		# Inclusive boundary, matching the lane's own inclusive half-width edge
		# above: the outermost pixel the renderer fills still counts as hit.
		return point.distance_squared_to(origin) <= radius * radius
	var to_point := point - origin
	var along := to_point.dot(heading)
	if along < 0.0 or along > length:
		return false
	var perpendicular := absf(to_point.cross(heading))
	return perpendicular <= width * 0.5


# The expanding wave's current radius at time t: 0 at commit start, growing
# linearly to `radius` (the ring's max radius) at commit end. Shared by
# containment and outline() so the drawn ring and the hit ring never drift
# apart. A zero commit_duration never reaches Phase.COMMIT at all (phase_at
# skips straight from WINDUP to FADE), so contains() never calls this for
# that case — the radius reported here doesn't matter, but `radius` itself
# (the fully-expanded size) is the least surprising fallback.
func _ring_edge_radius(t: float) -> float:
	if commit_duration <= 0.0:
		return radius
	var commit_t := clampf(t - windup_duration, 0.0, commit_duration)
	return radius * (commit_t / commit_duration)


# Ring of `radius` max extent and `width` band thickness around `origin`,
# expanding outward across the commit window (ground-slam archetype, issue
# #573). Unlike the disc's static area, the ring's dangerous region is the
# sweeping edge itself — a point the edge has already passed is safe again,
# which is what makes "get outside the ring" a real counter rather than
# "stand anywhere but the centre".
static func make_ring(
	ring_origin: Vector2,
	max_radius: float,
	band_width: float,
	windup: float,
	commit: float,
	fade: float
) -> DangerZoneShape:
	var s := DangerZoneShape.new()
	s.kind = Kind.RING
	s.origin = ring_origin
	s.radius = maxf(0.0, max_radius)
	s.width = maxf(0.0, band_width)
	s.windup_duration = maxf(0.0, windup)
	s.commit_duration = maxf(0.0, commit)
	s.fade_duration = maxf(0.0, fade)
	return s


# Disc of `radius` around `origin` (zone-denial archetype, issue #571). Unlike
# the lane/tether, a disc has no heading or length — it is just an origin and
# a radius, clamped the same way `make_lane` clamps its inputs.
static func make_disc(
	disc_origin: Vector2,
	disc_radius: float,
	windup: float,
	commit: float,
	fade: float
) -> DangerZoneShape:
	var s := DangerZoneShape.new()
	s.kind = Kind.DISC
	s.origin = disc_origin
	s.radius = maxf(0.0, disc_radius)
	s.windup_duration = maxf(0.0, windup)
	s.commit_duration = maxf(0.0, commit)
	s.fade_duration = maxf(0.0, fade)
	return s


# Tether from the enemy to a locked target point (Pull archetype). Same segment
# containment as a lane — the distinction is what the ability does on commit,
# which is why the tether also answers `pull_direction`.
static func make_tether(
	enemy_position: Vector2,
	locked_target: Vector2,
	tether_width: float,
	windup: float,
	commit: float,
	fade: float
) -> DangerZoneShape:
	var span := locked_target - enemy_position
	var s := make_lane(
		enemy_position, span, span.length(), tether_width, windup, commit, fade)
	s.kind = Kind.TETHER
	return s


# Unit vector from `point` back toward the zone's origin (the enemy). The Pull
# archetype drags the player along this, so the direction is reported by the
# same module that decides whether the player was caught at all.
func pull_direction(point: Vector2) -> Vector2:
	var to_origin := origin - point
	if to_origin == Vector2.ZERO:
		return Vector2.ZERO
	return to_origin.normalized()


# The zone's whole lifetime. Past it the zone has finished fading and the
# renderer can free itself.
func total_duration() -> float:
	return windup_duration + commit_duration + fade_duration


func is_expired(t: float) -> bool:
	return t >= total_duration()


# --- Presentation, reported by the geometry rather than authored separately ---
#
# DangerZoneRenderer draws these two and nothing else, which is what keeps the
# telegraph and the hitbox from drifting: the polygon below is the same
# half-width rectangle around the same locked segment that `contains` tests.

# Corner ring of the zone in the same world space `contains` is queried with,
# wound near-left -> far-left -> far-right -> near-right.
const DISC_OUTLINE_SEGMENTS: int = 24

# `t` is only consulted by the ring branch (its polygon radius changes across
# the commit window); lane/tether/disc outlines are static and ignore it.
func outline(t: float = 0.0) -> PackedVector2Array:
	if kind == Kind.RING:
		var points := PackedVector2Array()
		var edge := _ring_edge_radius(t)
		for i in range(DISC_OUTLINE_SEGMENTS):
			var angle := TAU * float(i) / float(DISC_OUTLINE_SEGMENTS)
			points.append(origin + Vector2(cos(angle), sin(angle)) * edge)
		return points
	if kind == Kind.DISC:
		var points := PackedVector2Array()
		for i in range(DISC_OUTLINE_SEGMENTS):
			var angle := TAU * float(i) / float(DISC_OUTLINE_SEGMENTS)
			points.append(origin + Vector2(cos(angle), sin(angle)) * radius)
		return points
	# Left-hand normal of the heading, so the winding is stable for any heading.
	var side := Vector2(-heading.y, heading.x) * (width * 0.5)
	var far := endpoint()
	return PackedVector2Array([
		origin - side,
		far - side,
		far + side,
		origin + side,
	])


# How much of the zone has filled in during the wind-up: 0 at telegraph start,
# 1 at commit. The renderer sweeps its fill with this so the player can read
# time-to-impact off the zone itself.
func fill_progress(t: float) -> float:
	if windup_duration <= 0.0:
		return 1.0
	return clampf(t / windup_duration, 0.0, 1.0)


const WINDUP_COLOR := Color(1.0, 0.72, 0.2, 0.45)  # amber
const COMMIT_COLOR := Color(1.0, 0.2, 0.15, 0.65)  # flash to red


# Uniform colour language across every enemy (PRD #518 user story 4): amber
# while winding up, red at commit, fading to nothing after.
func color_at(t: float) -> Color:
	match phase_at(t):
		Phase.WINDUP:
			var c := WINDUP_COLOR
			# Alpha ramps with the fill so the telegraph reads as "charging".
			c.a *= 0.35 + 0.65 * fill_progress(t)
			return c
		Phase.COMMIT:
			return COMMIT_COLOR
		_:
			var c2 := COMMIT_COLOR
			if fade_duration <= 0.0:
				c2.a = 0.0
				return c2
			var faded := (t - windup_duration - commit_duration) / fade_duration
			c2.a *= clampf(1.0 - faded, 0.0, 1.0)
			return c2
