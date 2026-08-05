class_name ScrollDefinition
extends RefCounted

# Pure-data record for one scroll type (issue #456 stub). Mirrors
# PotionDefinition's shape exactly so ScrollCatalog can follow the same
# static-registry pattern once real scroll content is designed (deferred
# per #453's Out of Scope).

var id: String = ""
var display_name: String = ""
var description: String = ""
var effect_kind: int = 0
var magnitude: int = 0
var duration: float = 0.0
var category: String = ""
var icon: Texture2D = null

static func make(p_id: String, p_name: String, p_desc: String, p_kind: int, p_magnitude: int, p_duration: float, p_category: String, p_icon: Texture2D = null) -> ScrollDefinition:
	var d := ScrollDefinition.new()
	d.id = p_id
	d.display_name = p_name
	d.description = p_desc
	d.effect_kind = p_kind
	d.magnitude = p_magnitude
	d.duration = p_duration
	d.category = p_category
	d.icon = p_icon
	return d
