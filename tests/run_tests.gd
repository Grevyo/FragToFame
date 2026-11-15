extends SceneTree
## Headless test runner. Runs every suite in SUITES and exits with 0 (all passed) or 1.
##
## Run:  <godot> --headless --path <project> --script res://tests/run_tests.gd

const SUITES: Array[GDScript] = [
	preload("res://tests/suites/foundation_suite.gd"),
	preload("res://tests/suites/career_world_suite.gd"),
	preload("res://tests/suites/career_sync_suite.gd"),
	preload("res://tests/suites/match_session_suite.gd"),
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Frag to Fame headless tests ==")
	await process_frame
	var passed := 0
	var failed := 0
	for script: GDScript in SUITES:
		var suite := script.new() as TestSuite
		suite.tree = self
		print("\n## %s" % suite.suite_name())
		await suite.run()
		passed += suite.passed
		failed += suite.failed
	print("\n== %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)
