class_name CareerMatches
extends RefCounted
## Builds [MatchSetup]s from the career world. This is where career data becomes match data:
## the FPS runtime only ever sees the resulting setup, never the database.


## A local practice match: the human (plus their organisation's teammates when signed, else
## generic practice partners) against [param opponent_org_id]'s starting five.
## Practice scores stay separate from the career calendar.
static func practice_setup(repo: CareerRepository, human_id: String, opponent_org_id: String,
		map_id: String, max_rounds: int = 3) -> MatchSetup:
	var opponent := repo.get_organisation(opponent_org_id)
	if opponent == null:
		return null
	var human := repo.get_player(human_id)
	var setup := MatchSetup.new()
	setup.fixture_id = Ids.generate("practice")
	setup.competition = "Practice"
	setup.max_rounds = max_rounds
	setup.map_id = map_id
	var contract := repo.active_contract(human_id) if human != null else null
	if contract != null and contract.organisation_id != opponent_org_id:
		var own := repo.get_organisation(contract.organisation_id)
		setup.home_team_id = own.id
		setup.home_team_name = own.name
		setup.home_lineup = _with_human_first(repo.lineup(own.id, 6), human_id, human)
	else:
		setup.home_team_id = "team_practice_player"
		setup.home_team_name = "You + practice partners"
		setup.home_lineup = _with_human_first([], human_id, human)
	setup.away_team_id = opponent.id
	setup.away_team_name = opponent.name
	setup.away_lineup = repo.lineup(opponent.id)
	return setup


static func _with_human_first(lineup: Array[Dictionary], human_id: String,
		human: CareerRecords.PlayerRecord) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if human != null:
		result.append({"player_id": human_id, "name": human.nickname, "role": String(human.preferred_role),
			"is_human": true, "abilities": {}})
	for entry: Dictionary in lineup:
		if str(entry["player_id"]) != human_id and result.size() < 5:
			result.append(entry)
	return result
