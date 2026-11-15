class_name MatchResult
extends RefCounted
## The final outcome of one fixture, produced by a match runner and submitted to the career host.
##
## [member submission_id] makes submission idempotent: resending the same submission (e.g. after
## a reconnect) is recognised as a duplicate instead of being applied twice.

const FORMAT: String = "f2f.match_result"
const FORMAT_VERSION: int = 1

const SOURCE_STUB: String = "stub"
const SOURCE_FPS_RUNTIME: String = "fps_runtime"
const SOURCE_SIMULATION: String = "simulation"

var fixture_id: String = ""
var submission_id: String = ""
var submitted_by: String = ""
var source: String = SOURCE_STUB
var home_score: int = 0
var away_score: int = 0
var rounds_played: int = 0
var map_id: String = ""


static func create(fixture_id_value: String, home: int, away: int, source_value: String) -> MatchResult:
	var result := MatchResult.new()
	result.fixture_id = fixture_id_value
	result.submission_id = Ids.generate("sub")
	result.source = source_value
	result.home_score = home
	result.away_score = away
	result.rounds_played = home + away
	return result


func winner_side() -> String:
	if home_score > away_score:
		return "home"
	if away_score > home_score:
		return "away"
	return "none"


## True if the scoreline (the part that matters for standings) matches [param other].
func same_outcome_as(other: MatchResult) -> bool:
	return fixture_id == other.fixture_id and home_score == other.home_score \
		and away_score == other.away_score


## Returns an empty string if valid, otherwise a human-readable reason.
func validate() -> String:
	if fixture_id.is_empty():
		return "missing fixture_id"
	if submission_id.is_empty():
		return "missing submission_id"
	if home_score < 0 or away_score < 0:
		return "scores must be non-negative"
	if home_score == away_score:
		return "a match result cannot be a draw"
	if rounds_played != home_score + away_score:
		return "rounds_played does not match the score"
	return ""


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"fixture_id": fixture_id,
		"submission_id": submission_id,
		"submitted_by": submitted_by,
		"source": source,
		"home_score": home_score,
		"away_score": away_score,
		"rounds_played": rounds_played,
		"map_id": map_id,
	}


## Parses a dictionary. Returns null if the format or version is not understood.
static func from_dict(data: Dictionary) -> MatchResult:
	if data.get("format", "") != FORMAT or int(data.get("format_version", 0)) != FORMAT_VERSION:
		return null
	var result := MatchResult.new()
	result.fixture_id = str(data.get("fixture_id", ""))
	result.submission_id = str(data.get("submission_id", ""))
	result.submitted_by = str(data.get("submitted_by", ""))
	result.source = str(data.get("source", ""))
	result.home_score = int(data.get("home_score", -1))
	result.away_score = int(data.get("away_score", -1))
	result.rounds_played = int(data.get("rounds_played", -1))
	result.map_id = str(data.get("map_id", ""))
	return result
