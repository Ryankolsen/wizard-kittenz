class_name GwendolynNameMatch
extends RefCounted

# PRD #474 / issue #475. Pure helper: does a typed cat name match "Gwendolyn"
# (case-insensitive, trimmed of surrounding whitespace, exact match only —
# "Gwen" or "Gwendolyn2" don't count)?

const TARGET_NAME: String = "gwendolyn"

static func is_gwendolyn_name(name: String) -> bool:
	return name.strip_edges().to_lower() == TARGET_NAME
