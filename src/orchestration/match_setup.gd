class_name MatchSetup
extends RefCounted
## Everything a match runner (FPS runtime, simulator or stub) needs to play one fixture.
##
## This is the only career data that crosses into a match. It is plain data and serialises
## to a versioned Dictionary so it can travel over the network or into a file.

const FORMAT: String = "f2f.match_setup"
## v2 adds team lineups.
const FORMAT_VERSION: int = 2

var fixture_id: String = ""
var competition: String = ""
var home_team_id: String = ""
var home_team_name: String = ""
var away_team_id: String = ""
var away_team_name: String = ""
## "MR" value: max regulation rounds per half. MR10 = first to 11 of 20 regulation rounds.
var max_rounds: int = 10
var map_id: String = ""
## Lineups (optional; empty = the runtime fills teams itself). Each entry:
## {player_id, name, role, is_human, abilities: {ability: 1–100}}. Abilities are AI players'
## simulated values and only ever drive bots; human entries carry none.
var home_lineup: Array[Dictionary] = []
var away_lineup: Array[Dictionary] = []


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
	setup.home_lineup = _lineup_from(fixture.get("home_lineup", []))
	setup.away_lineup = _lineup_from(fixture.get("away_lineup", []))
	return setup


func lineup(team_index: int) -> Array[Dictionary]:
	return home_lineup if team_index == 0 else away_lineup


static func _lineup_from(value: Variant) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value:
			if entry is Dictionary:
				list.append((entry as Dictionary).duplicate(true))
	return list


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
		"home_lineup": home_lineup.duplicate(true),
		"away_lineup": away_lineup.duplicate(true),
	}
