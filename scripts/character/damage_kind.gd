class_name DamageKind
extends RefCounted

# Issue #343 (PRD #341 — Typed damage points). Enumerates the damage type
# tag carried alongside a damage event and maps each kind to the floating-
# number color used everywhere combat feedback is rendered. A single source
# of truth means the local spawn paths (player melee, wizard cast, spell
# resolver) and the remote damage visualizer pick the same color from the
# same kind value — solo and co-op render identically.
#
# Unknown / out-of-range kinds (mixed-version peer on the wire — see #346)
# fall back to PHYSICAL so a forward-version sender never paints a
# white/blank label on an older receiver.

enum Kind {
	PHYSICAL = 0,
	MAGIC = 1,
}

const COLOR_PHYSICAL: Color = Color(1.0, 0.2, 0.2)
const COLOR_MAGIC: Color = Color(0.4, 0.6, 1.0)

static func color_for(kind: int) -> Color:
	match kind:
		Kind.MAGIC:
			return COLOR_MAGIC
		Kind.PHYSICAL:
			return COLOR_PHYSICAL
		_:
			return COLOR_PHYSICAL
