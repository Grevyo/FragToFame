class_name CareerWorld
extends RefCounted
## Minimal authoritative career world for the Milestone 2 networking proof.
##
## Holds fixtures and their results, owned by the career host. Pure data + logic: no Nodes,
## no networking. In-memory only — persistence arrives with the career database (Milestone 9).
##
## Result submission rules (idempotent by design):
## - Unknown fixture                         -> UNKNOWN_FIXTURE (rejected)
## - Malformed result                        -> INVALID (rejected)
## - Fixture has no result yet               -> ACCEPTED (applied, revision += 1)
## - Same submission_id already applied      -> DUPLICATE (acknowledged, nothing changes)
## - Different submission, identical score   -> DUPLICATE (e.g. both participants reported it)
## - Different submission, different score   -> CONFLICT (rejected, existing result kept)

enum SubmitStatus { ACCEPTED, DUPLICATE, CONFLICT, UNKNOWN_FIXTURE, INVALID }

const FORMAT: String = "f2f.career_world"
const FORMAT_VERSION: int = 1

var world_id: String = ""
var is_dev_sample: bool = false
## Increments on every accepted change so clients can tell whether their copy is current.
var revision: int = 0

var _fixtures: Dictionary[String, Dictionary] = {}
var _fixture_order: Array[String] = []
var _results: Dictionary[String, MatchResult] = {}


static func status_name(status: SubmitStatus) -> String:
	return SubmitStatus.keys()[status]


func add_fixture(fixture: Dictionary) -> void:
	var id := str(fixture.get("id", ""))
	assert(not id.is_empty(), "fixture needs an id")
	assert(not _fixtures.has(id), "duplicate fixture id %s" % id)
	_fixtures[id] = fixture.duplicate(true)
	_fixture_order.append(id)
	revision += 1


func has_fixture(fixture_id: String) -> bool:
	return _fixtures.has(fixture_id)


func fixture_count() -> int:
	return _fixture_order.size()


func get_fixture(fixture_id: String) -> Dictionary:
	return _fixtures.get(fixture_id, {}).duplicate(true)


func get_result(fixture_id: String) -> MatchResult:
	return _results.get(fixture_id, null)


func unresolved_fixture_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _fixture_order:
		if not _results.has(id):
			ids.append(id)
	return ids


## Submits a result. Returns {"status": SubmitStatus, "message": String}.
func submit_result(result: MatchResult) -> Dictionary:
	if result == null:
		return _outcome(SubmitStatus.INVALID, "unreadable result")
	if not _fixtures.has(result.fixture_id):
		return _outcome(SubmitStatus.UNKNOWN_FIXTURE, "no fixture '%s'" % result.fixture_id)
	var problem := result.validate()
	if not problem.is_empty():
		return _outcome(SubmitStatus.INVALID, problem)

	var existing: MatchResult = _results.get(result.fixture_id, null)
	if existing != null:
		if existing.submission_id == result.submission_id:
			return _outcome(SubmitStatus.DUPLICATE, "submission already applied")
		if existing.same_outcome_as(result):
			return _outcome(SubmitStatus.DUPLICATE, "identical result already recorded")
		return _outcome(SubmitStatus.CONFLICT, "fixture already has a different result (%d–%d)"
			% [existing.home_score, existing.away_score])

	_results[result.fixture_id] = result
	revision += 1
	return _outcome(SubmitStatus.ACCEPTED, "result recorded")


## Network/UI-safe copy of all fixtures, each with a "result" entry (empty if unresolved).
func fixtures_snapshot() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in _fixture_order:
		var entry: Dictionary = _fixtures[id].duplicate(true)
		var result: MatchResult = _results.get(id, null)
		entry["result"] = result.to_dict() if result != null else {}
		list.append(entry)
	return list


func _outcome(status: SubmitStatus, message: String) -> Dictionary:
	return {"status": status, "message": message}


## DEVELOPMENT SAMPLE world: a handful of fictional fixtures for the networking proof.
static func create_dev_world() -> CareerWorld:
	var world := CareerWorld.new()
	world.world_id = Ids.generate("wld")
	world.is_dev_sample = true
	var teams := DevSampleData.teams()
	var pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(2, 3), Vector2i(4, 5), Vector2i(1, 2), Vector2i(3, 0)]
	var maps: Array[String] = ["map_dev_foundry", "map_dev_harbourline", "map_dev_cinderworks"]
	for i: int in pairs.size():
		var home: Dictionary = teams[pairs[i].x]
		var away: Dictionary = teams[pairs[i].y]
		world.add_fixture({
			"id": "fix_dev_%03d" % (i + 1),
			"competition": "F2F Universal Ladder — Season 1 (dev sample)",
			"date": "%02d Jan Y1" % (5 + i),
			"home_team_id": home["id"],
			"home_team_name": home["name"],
			"away_team_id": away["id"],
			"away_team_name": away["name"],
			"best_of": 1,
			"max_rounds": 10,
			"map_id": maps[i % maps.size()],
			"required": true,
		})
	return world
