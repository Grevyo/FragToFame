extends SceneTree
## Headless test runner. Runs every suite in SUITES and exits with 0 (all passed) or 1.
##
## Run:  <godot> --headless --path <project> --script res://tests/run_tests.gd
##
## Suites are loaded at runtime (not preloaded) so they can reference autoload singletons such
## as App, which do not exist yet when this script itself is compiled.

const SUITES: Array[String] = [
	"res://tests/suites/foundation_suite.gd",
	"res://tests/suites/career_world_suite.gd",
	"res://tests/suites/career_sync_suite.gd",
	"res://tests/suites/match_session_suite.gd",
	"res://tests/suites/map_editor_suite.gd",
	"res://tests/suites/combat_suite.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Frag to Fame headless tests ==")
	await process_frame
	var passed := 0
	var failed := 0
	for path: String in SUITES:
		var script := load(path) as GDScript
		var suite: TestSuite = script.new() as TestSuite if script != null and script.can_instantiate() else null
		if suite == null:
			printerr("  FAIL  could not load suite %s" % path)
			failed += 1
			continue
		suite.tree = self
		print("\n## %s" % suite.suite_name())
		await suite.run()
		passed += suite.passed
		failed += suite.failed
	print("\n== %d passed, %d failed ==" % [passed, failed])
	quit(1 if failed > 0 else 0)
