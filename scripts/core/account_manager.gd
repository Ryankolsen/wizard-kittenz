class_name AccountManager
extends RefCounted

# Thin in-memory record of the player's account session. Pure data —
# the Google Play Games / Nakama wire integration (#14) wraps this
# with the actual handshake; today AccountManager just owns the
# is-signed-in flag + user_id so the UI can branch on "show sign-in
# button" vs "show synced-cloud icon" without touching the wire layer.
#
# Sign-out is intentionally a no-op against disk: the local save lives
# at save_path and is owned by SaveManager. AccountManager.sign_out()
# only clears the in-memory account record. This matches the "signing
# out does not delete local save data" acceptance criterion — once a
# kitten exists on disk, dropping the cloud account never erases it.
# The "delete local save" path, if it ever ships, lives on a separate
# explicit "Erase All Data" button so it can never collide with a
# routine sign-out.

const DEFAULT_SAVE_PATH := "user://save.json"

signal signed_in(user_id: String)
signal signed_out()

# Configurable so tests can point at a tmp path without monkey-patching
# the constant. Production code uses the default.
var save_path: String = DEFAULT_SAVE_PATH
var user_id: String = ""
var _signed_in: bool = false

func _init(path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = path

func is_signed_in() -> bool:
	return _signed_in

# Records the signed-in user. Empty user_id is rejected so a malformed
# wire payload doesn't quietly mark the session as signed in with no
# identity. Returns true on a state change.
func sign_in(uid: String) -> bool:
	if uid == "":
		return false
	if _signed_in and user_id == uid:
		return false
	user_id = uid
	_signed_in = true
	signed_in.emit(uid)
	return true

# Drops the in-memory account state. Does NOT touch save_path on disk —
# the local save survives sign-out. Returns true when the call actually
# transitioned out of signed-in (idempotent on repeat).
func sign_out() -> bool:
	if not _signed_in:
		return false
	_signed_in = false
	user_id = ""
	signed_out.emit()
	return true
