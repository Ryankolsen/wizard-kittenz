extends GutTest

const SPRITE_PATHS := [
	"res://assets/sprites/armor_common.png",
	"res://assets/sprites/armor_rare.png",
	"res://assets/sprites/armor_epic.png",
	"res://assets/sprites/accessory_common.png",
	"res://assets/sprites/accessory_rare.png",
	"res://assets/sprites/accessory_epic.png",
]

func test_all_six_tier_sprites_resolve():
	for path in SPRITE_PATHS:
		assert_true(ResourceLoader.exists(path), "Missing sprite resource: %s" % path)

func test_armor_common_has_transparent_corner():
	var tex: Texture2D = load("res://assets/sprites/armor_common.png")
	assert_not_null(tex, "Failed to load armor_common.png as Texture2D")
	var img := tex.get_image()
	assert_not_null(img, "Texture has no Image data")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "Corner pixel should be fully transparent")
