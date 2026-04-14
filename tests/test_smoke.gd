extends GutTest

# Smoke test — confirms GUT is wired up and can run tests.
# Delete this once real rule tests exist.

func test_smoke() -> void:
	assert_eq(1 + 1, 2, "math still works")
