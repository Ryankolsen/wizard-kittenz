class_name RoomCodeValidator
extends RefCounted

# Validates room codes typed by a friend at the Join Room screen.
# Pure data — no Nakama call. Surface a clear error before the
# network round-trip when the input is structurally wrong.
#
# Accepts the full uppercase-alphanumeric range (A-Z, 0-9). The
# generator (RoomCodeGenerator) emits a stricter confusable-free
# subset, but a hand-typed code that uses the broader range is
# still well-formed structurally — the matchmaker layer rejects
# unknown codes via "no such room", which is a different error
# class than "malformed input".
const CODE_LENGTH: int = 5

# Returns true iff `code` is exactly CODE_LENGTH characters of
# uppercase alphanumeric. Lowercase, mixed case, padding spaces,
# punctuation, and non-CODE_LENGTH inputs all fail.
static func is_valid(code: String) -> bool:
	if code.length() != CODE_LENGTH:
		return false
	for c in code:
		if not _is_uppercase_alphanumeric(c):
			return false
	return true

static func _is_uppercase_alphanumeric(c: String) -> bool:
	if c.length() != 1:
		return false
	var b := c.unicode_at(0)
	# 0-9 -> 48..57; A-Z -> 65..90.
	return (b >= 48 and b <= 57) or (b >= 65 and b <= 90)
