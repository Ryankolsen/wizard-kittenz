class_name LobbyPlayer
extends RefCounted

# Pre-game lobby slot — one per connected player. Distinct from
# CharacterData (the persistent kitten) and PartyMember (the in-session
# scaled view): LobbyPlayer is just the bit shown on the lobby screen
# (who's here, are they ready) plus enough identity to dedupe joins.
#
# `player_id` is the stable per-account identifier (Google Play Games
# id today, Nakama user_id after #14 lands). `kitten_name` /
# `class_name_str` mirror CharacterData for the lobby roster row;
# duplicating rather than holding a CharacterData reference keeps the
# lobby decoupled from the (heavier) save layer.
var player_id: String = ""
var kitten_name: String = ""
var class_name_str: String = ""
var ready: bool = false
var is_host: bool = false

static func make(id: String, name: String, klass: String, host: bool = false) -> LobbyPlayer:
	var lp := LobbyPlayer.new()
	lp.player_id = id
	lp.kitten_name = name
	lp.class_name_str = klass
	lp.is_host = host
	return lp

func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"kitten_name": kitten_name,
		"class_name": class_name_str,
		"ready": ready,
		"is_host": is_host,
	}

static func from_dict(d: Dictionary) -> LobbyPlayer:
	var lp := LobbyPlayer.new()
	lp.player_id = String(d.get("player_id", ""))
	lp.kitten_name = String(d.get("kitten_name", ""))
	lp.class_name_str = String(d.get("class_name", ""))
	lp.ready = bool(d.get("ready", false))
	lp.is_host = bool(d.get("is_host", false))
	return lp
