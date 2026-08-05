extends GutTest

# Issue #456. Architecture stub: no scroll content authored yet, just the
# ScrollDefinition/ScrollCatalog shape mirroring PotionDefinition/PotionCatalog.

func test_catalog_returns_empty_array():
	var all := ScrollCatalog.all()
	assert_true(all is Array)
	assert_eq(all.size(), 0)

func test_scroll_definition_make_fields():
	var def := ScrollDefinition.make("test_scroll", "Test Scroll", "desc", 1, 10, 0.0, "test")
	assert_eq(def.id, "test_scroll")
	assert_eq(def.display_name, "Test Scroll")
	assert_eq(def.description, "desc")
	assert_eq(def.effect_kind, 1)
	assert_eq(def.magnitude, 10)
	assert_eq(def.duration, 0.0)
	assert_eq(def.category, "test")

func test_find_unknown_id_returns_null():
	assert_null(ScrollCatalog.find("nonexistent_id"))
