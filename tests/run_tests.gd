extends SceneTree
## Headless test runner. Runs every suite in SUITES and exits with 0 (all passed) or 1.
##
## Run:  <godot> --headless --path <project> --script res://tests/run_tests.gd
## One or more suites only (file name contains the text):  ... run_tests.gd -- --suite=map_creator
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
	"res://tests/suites/utility_suite.gd",
	"res://tests/suites/movement_suite.gd",
	"res://tests/suites/match_rules_suite.gd",
	"res://tests/suites/practice_match_suite.gd",
	"res://tests/suites/ai_suite.gd",
	"res://tests/suites/bot_match_suite.gd",
	"res://tests/suites/database_suite.gd",
	"res://tests/suites/career_db_suite.gd",
	"res://tests/suites/career_flow_suite.gd",
	"res://tests/suites/tactic_editor_suite.gd",
	"res://tests/suites/map_creator_suite.gd",
	"res://tests/suites/official_map_suite.gd",
	"res://tests/suites/controls_suite.gd",
	"res://tests/suites/cosmetics_suite.gd",
	"res://tests/suites/knife_suite.gd",
	"res://tests/suites/sim_map_suite.gd",
	"res://tests/suites/round_plan_suite.gd",
	"res://tests/suites/career_fixture_suite.gd",
	"res://tests/suites/match_statistics_suite.gd",
	"res://tests/suites/career_development_suite.gd",
	"res://tests/suites/career_competitions_suite.gd",
	"res://tests/suites/career_calendar_suite.gd",
	"res://tests/suites/world_simulation_suite.gd",
	"res://tests/suites/career_offers_suite.gd",
	"res://tests/suites/world_seasons_suite.gd",
	"res://tests/suites/world_cups_suite.gd",
	"res://tests/suites/match_engine_suite.gd",
	"res://tests/suites/training_suite.gd",
	"res://tests/suites/people_suite.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("== Frag to Fame headless tests ==")
	await process_frame
	var passed := 0
	var failed := 0
	var only: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--suite="):
			only.append(argument.trim_prefix("--suite="))
	for path: String in SUITES:
		if not only.is_empty() and not only.any(func(text: String) -> bool: return path.get_file().contains(text)):
			continue
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
