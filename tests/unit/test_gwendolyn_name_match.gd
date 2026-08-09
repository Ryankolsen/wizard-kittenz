extends GutTest

# GwendolynNameMatch (PRD #474 / issue #475). Pure name-match helper — no
# state, no scene setup. Detects whether a typed cat name matches "Gwendolyn"
# so the caller can wire the memorial achievement + direct spell grant.

func test_exact_match_returns_true():
	assert_true(GwendolynNameMatch.is_gwendolyn_name("Gwendolyn"))

func test_case_insensitive_and_trimmed_variants_match():
	assert_true(GwendolynNameMatch.is_gwendolyn_name("gwendolyn"))
	assert_true(GwendolynNameMatch.is_gwendolyn_name("GWENDOLYN"))
	assert_true(GwendolynNameMatch.is_gwendolyn_name("  Gwendolyn  "))

func test_non_matches_return_false():
	assert_false(GwendolynNameMatch.is_gwendolyn_name("Gwen"))
	assert_false(GwendolynNameMatch.is_gwendolyn_name(""))
	assert_false(GwendolynNameMatch.is_gwendolyn_name("Gwendolyn2"))
