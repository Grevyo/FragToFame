class_name CareerFixture
extends RefCounted
## A local career calendar entry with its scheduled lineups and eventual score.

var player_id: String
var scheduled_day: int
## Minutes after midnight ([MatchTimes]).
var kick_off: int = MatchTimes.DEFAULT_KICK_OFF
var setup: MatchSetup
var result: MatchResult


static func from_row(row: Dictionary) -> CareerFixture:
	if row.is_empty():
		return null
	var setup_data: Variant = JSON.parse_string(str(row["setup_json"]))
	if not setup_data is Dictionary:
		return null
	var decoded := MatchSetup.from_dict(setup_data as Dictionary)
	if decoded == null or decoded.fixture_id != str(row["id"]):
		return null

	var fixture := CareerFixture.new()
	fixture.player_id = str(row["player_id"])
	fixture.scheduled_day = int(row["scheduled_day"])
	fixture.kick_off = int(row.get("kick_off", MatchTimes.DEFAULT_KICK_OFF))
	fixture.setup = decoded
	if row["submission_id"] != null:
		var result_data: Variant = JSON.parse_string(str(row["result_json"]))
		if not result_data is Dictionary:
			return null
		fixture.result = MatchResult.from_dict(result_data as Dictionary)
		if fixture.result == null or fixture.result.fixture_id != decoded.fixture_id \
				or fixture.result.submission_id != str(row["submission_id"]):
			return null
	return fixture
