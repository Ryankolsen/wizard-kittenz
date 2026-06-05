extends GutTest

# Issue #343: pure kind → color mapping. Single source of truth used by both
# the local FloatingText spawn paths and the remote damage visualizer so
# solo and co-op render identically. Unknown/default falls back to physical
# (red) for mixed-version safety with the upcoming OP_DAMAGE_DEALT kind
# field (issue #346).

func test_physical_kind_maps_to_red():
	assert_eq(DamageKind.color_for(DamageKind.Kind.PHYSICAL), Color(1.0, 0.2, 0.2))

func test_magic_kind_maps_to_blue():
	assert_eq(DamageKind.color_for(DamageKind.Kind.MAGIC), Color(0.4, 0.6, 1.0))

func test_unknown_kind_falls_back_to_physical_red():
	# Unknown int values (mixed-version peer / future kind not yet handled)
	# must degrade to physical red rather than a default Color() white that
	# would look like a UI glitch on screen.
	assert_eq(DamageKind.color_for(999), Color(1.0, 0.2, 0.2))
	assert_eq(DamageKind.color_for(-1), Color(1.0, 0.2, 0.2))
