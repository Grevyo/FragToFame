class_name CareerWorldSuite
extends TestSuite
## Pure-logic tests: MatchResult contract, stub runner, CareerWorld idempotent submission.


func suite_name() -> String:
	return "Career world & match contracts"


func run() -> void:
	_test_ids()
	_test_match_result_contract()
	_test_stub_runner()
	_test_world_submission_rules()


func _test_ids() -> void:
	section("IDs")
	var a := Ids.generate("sub")
	var b := Ids.generate("sub")
	check(Ids.has_prefix(a, "sub"), "generated id carries its prefix")
	check(a != b, "generated ids are unique")


func _test_match_result_contract() -> void:
	section("MatchResult")
	var r := MatchResult.create("fix_x", 11, 7, MatchResult.SOURCE_STUB)
	check(r.validate().is_empty(), "valid result passes validation")
	check(r.winner_side() == "home", "winner side computed")
	var round_trip := MatchResult.from_dict(r.to_dict())
	check(round_trip != null and round_trip.same_outcome_as(r) and round_trip.submission_id == r.submission_id,
		"to_dict/from_dict round-trips")
	var bad_version := r.to_dict()
	bad_version["format_version"] = 99
	check(MatchResult.from_dict(bad_version) == null, "unknown format_version is refused")
	var draw := MatchResult.create("fix_x", 5, 5, MatchResult.SOURCE_STUB)
	check(not draw.validate().is_empty(), "draw is invalid")
	var negative := MatchResult.create("fix_x", -1, 11, MatchResult.SOURCE_STUB)
	check(not negative.validate().is_empty(), "negative score is invalid")


func _test_stub_runner() -> void:
	section("StubMatchRunner")
	var setup := MatchSetup.new()
	setup.fixture_id = "fix_stub"
	setup.max_rounds = 10
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var all_valid := true
	for i: int in 50:
		var r := StubMatchRunner.run(setup, rng)
		var winner := maxi(r.home_score, r.away_score)
		var loser := mini(r.home_score, r.away_score)
		if not r.validate().is_empty() or winner != 11 or loser > 9 or r.fixture_id != "fix_stub":
			all_valid = false
	check(all_valid, "50 stub MR10 results are valid regulation scorelines")


func _test_world_submission_rules() -> void:
	section("CareerWorld submission rules")
	var world := CareerWorld.create_dev_world()
	check(world.is_dev_sample, "dev world is flagged as sample")
	check(world.fixture_count() == 5, "dev world has 5 fixtures")
	var fixture_id: String = world.unresolved_fixture_ids()[0]
	var rev0 := world.revision

	var first := MatchResult.create(fixture_id, 11, 6, MatchResult.SOURCE_STUB)
	check(world.submit_result(first)["status"] == CareerWorld.SubmitStatus.ACCEPTED, "first result ACCEPTED")
	check(world.revision == rev0 + 1, "accepted result increments revision")
	check(world.get_result(fixture_id).submission_id == first.submission_id, "result stored")

	check(world.submit_result(first)["status"] == CareerWorld.SubmitStatus.DUPLICATE, "same submission again is DUPLICATE")
	var same_score := MatchResult.create(fixture_id, 11, 6, MatchResult.SOURCE_STUB)
	check(world.submit_result(same_score)["status"] == CareerWorld.SubmitStatus.DUPLICATE,
		"different submission with identical score is DUPLICATE")
	var different := MatchResult.create(fixture_id, 3, 11, MatchResult.SOURCE_STUB)
	check(world.submit_result(different)["status"] == CareerWorld.SubmitStatus.CONFLICT, "different score is CONFLICT")
	check(world.get_result(fixture_id).submission_id == first.submission_id, "conflict keeps the original result")
	check(world.revision == rev0 + 1, "duplicates and conflicts do not change revision")

	var unknown := MatchResult.create("fix_missing", 11, 2, MatchResult.SOURCE_STUB)
	check(world.submit_result(unknown)["status"] == CareerWorld.SubmitStatus.UNKNOWN_FIXTURE, "unknown fixture rejected")
	var invalid := MatchResult.create(world.unresolved_fixture_ids()[0], 4, 4, MatchResult.SOURCE_STUB)
	check(world.submit_result(invalid)["status"] == CareerWorld.SubmitStatus.INVALID, "invalid result rejected")
	check(world.submit_result(null)["status"] == CareerWorld.SubmitStatus.INVALID, "null result rejected")
	check(world.unresolved_fixture_ids().size() == 4, "exactly one fixture resolved")

	var snapshot := world.fixtures_snapshot()
	var resolved_entry: Dictionary = snapshot[0]
	check(not (resolved_entry["result"] as Dictionary).is_empty(), "snapshot includes recorded result")
	resolved_entry["home_team_name"] = "tampered"
	check(world.get_fixture(fixture_id)["home_team_name"] != "tampered", "snapshot is a copy, not live state")
