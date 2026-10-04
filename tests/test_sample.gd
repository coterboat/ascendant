extends "res://tests/test_case.gd"
## Sample tests proving the runner works. Replace or extend as real rules land.


func test_arithmetic() -> void:
	assert_eq(2 + 2, 4)


func test_seeded_rng_is_deterministic() -> void:
	# Turn resolution relies on seeded RNG replaying identically.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 12345
	b.seed = 12345
	for i in 10:
		assert_eq(a.randi(), b.randi(), "roll %d" % i)


func test_main_scene_is_set() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_true(ResourceLoader.exists(main_scene), "main scene %s exists" % main_scene)
