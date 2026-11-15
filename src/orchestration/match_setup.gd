class_name MatchSetup
extends RefCounted
## Everything a match runner (FPS runtime, simulator or stub) needs to play one fixture.
##
## This is the only career data that crosses into a match. It is plain data and serialises
## to a versioned Dictionary so it can travel over the network or into a file.

const FORMAT: String = "f2f.match_setup"
const FORMAT_VERSION: int = 1

var fixture_id: String = ""
var competition: String = ""
var home_team_id: String = ""
var home_team_name: String = ""
var away_team_id: String = ""
var away_team_name: String = ""
## "MR" value: max regulation rounds per half. MR10 = first to 11 of 20 regulation rounds.
var max_rounds: int = 10
var map_id: String = ""


## Rounds needed to win in regulation.
func rounds_to_win() -> int:
	return max_rounds + 1


static func from_fixture(fixture: Dictionary) -> MatchSetup:
	var setup := MatchSetup.new()
	setup.fixture_id = str(fixture.get("id", ""))
	setup.competition = str(fixture.get("competition", ""))
	setup.home_team_id = str(fixture.get("home_team_id", ""))
	setup.home_team_name = str(fixture.get("home_team_name", ""))
	setup.away_team_id = str(fixture.get("away_team_id", ""))
	setup.away_team_name = str(fixture.get("away_team_name", ""))
	setup.max_rounds = int(fixture.get("max_rounds", 10))
	setup.map_id = str(fixture.get("map_id", ""))
	return setup


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"fixture_id": fixture_id,
		"competition": competition,
		"home_team_id": home_team_id,
		"home_team_name": home_team_name,
		"away_team_id": away_team_id,
		"away_team_name": away_team_name,
		"max_rounds": max_rounds,
		"map_id": map_id,
	}
