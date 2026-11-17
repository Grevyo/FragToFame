class_name CareerFixtures
extends RefCounted
## Schedules amateur fixtures and resolves every career fixture (amateur matches, trials from
## [CareerOffers] and league series maps from [CareerLeagueMatches]). The FPS runtime receives
## only a MatchSetup and returns a MatchResult. Result publication and calendar advancement are
## atomic; a map that does not decide its series keeps the day for the next map.

const COMPETITION: String = "Amateur Matchmaking"
const MAX_ROUNDS: int = 5
const TEAM_SIZE: int = 5


## Keep the pending fixture and its original roster until the player completes it.
static func schedule(repo: CareerRepository, player_id: String, map_id: String) -> String:
	if repo.pending_fixture(player_id) != null:
		return ""
	var human := repo.get_player(player_id)
	if human == null or not human.is_human or human.status != "active":
		return "An active career player is required to schedule a fixture."
	var setup := _amateur_setup(repo, human, map_id)
	if setup == null:
		return "The world database needs an opposing organisation with five AI starters."
	var fixture := CareerFixture.new()
	fixture.player_id = player_id
	fixture.scheduled_day = repo.current_day()
	fixture.setup = setup
	if repo.insert_fixture(fixture) or repo.pending_fixture(player_id) != null:
		return ""
	return "Could not schedule the fixture."


## [param allow_simulated]: accept a [constant MatchResult.SOURCE_SIMULATION] result (the
## development "simulate match" option, [CareerMatchSimulator]).
static func record_result(repo: CareerRepository, player_id: String, result: MatchResult,
		allow_simulated: bool = false) -> String:
	if result == null:
		return "Missing match result."
	var problem := result.validate()
	if not problem.is_empty():
		return problem
	var simulated := allow_simulated and result.source == MatchResult.SOURCE_SIMULATION
	if result.source != MatchResult.SOURCE_FPS_RUNTIME and not simulated:
		return "A played FPS match is required for this fixture."

	var rejected: Array[String] = []
	var stored := repo.transaction(func() -> bool:
		var fixture := repo.fixture_by_id(result.fixture_id)
		if fixture == null or fixture.player_id != player_id:
			rejected.append("This result does not belong to your career fixture.")
			return false
		if result.map_id != fixture.setup.map_id:
			rejected.append("The result map does not match the fixture.")
			return false
		var rules := MatchRules.competitive(fixture.setup.max_rounds)
		var target := rules.winning_score(mini(result.home_score, result.away_score))
		if maxi(result.home_score, result.away_score) != target:
			rejected.append("The score does not complete this fixture's match format.")
			return false
		if fixture.result != null:
			if fixture.result.same_outcome_as(result):
				return true
			rejected.append("This fixture already has a different final score.")
			return false
		var totals: Dictionary[String, Dictionary] = {}
		if not result.events.is_empty():
			totals = MatchStatistics.calculate(result)
			if totals.is_empty() or not _covers_lineups(fixture.setup, totals):
				rejected.append("The match statistics do not match the scheduled fixture.")
				return false
		if not repo.store_fixture_result(result):
			return false
		if not totals.is_empty() and not repo.store_fixture_statistics(fixture, result, totals):
			return false
		# Simulated (dev) matches count for ELO and reputation too (owner, 2026-11-17); with no
		# telemetry they move no opinions.
		if fixture.setup.competition == COMPETITION and (not totals.is_empty() or simulated) \
				and not CareerDevelopment.apply_amateur_result(repo, fixture, result, totals.get(player_id, {}) as Dictionary):
			return false
		var series_map := repo.series_map_for_fixture(fixture.setup.fixture_id)
		if not series_map.is_empty():
			var finished: Array[bool] = []
			if not CareerLeagueMatches.record_map(repo, fixture, series_map, finished):
				return false
			if not finished[0]:
				return true  # The next map of the series is played the same day.
		var trial := repo.offer_for_fixture(fixture.setup.fixture_id)
		if not trial.is_empty() and not CareerOffers.apply_trial_result(repo, trial, result,
				totals.get(player_id, {}) as Dictionary):
			return false
		# Days passed while playing resolve their other series and new seasons too.
		return CareerCalendar.advance_to(repo, maxi(repo.current_day(), fixture.scheduled_day + 1)))
	if stored:
		return ""
	return rejected[0] if not rejected.is_empty() else "Could not save the result. Try again from the Career Hub."


static func _covers_lineups(setup: MatchSetup, totals: Dictionary[String, Dictionary]) -> bool:
	for lineup: Array[Dictionary] in [setup.home_lineup, setup.away_lineup]:
		for player: Dictionary in lineup:
			if not totals.has(str(player["player_id"])):
				return false
	return true


static func _amateur_setup(repo: CareerRepository, human: CareerRecords.PlayerRecord, map_id: String) -> MatchSetup:
	var contract := repo.active_contract(human.id)
	var own_id := contract.organisation_id if contract != null else ""
	var organisations := repo.organisations()
	organisations.reverse()
	var candidates: Array[CareerRecords.OrganisationRecord] = []
	var lineups: Array[Array] = []
	for entry: Dictionary in organisations:
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if not candidates.is_empty() and org.tier < candidates[0].tier:
			break
		if org.id == own_id or int(entry["roster_size"]) < TEAM_SIZE:
			continue
		var lineup := repo.lineup(org.id, TEAM_SIZE)
		if lineup.size() == TEAM_SIZE and lineup.all(func(p: Dictionary) -> bool: return not bool(p["is_human"])):
			candidates.append(org)
			lineups.append(lineup)
	if candidates.is_empty():
		return null

	var number := repo.fixture_count(human.id)
	var index := number % candidates.size()
	var opponent := candidates[index]
	var setup := MatchSetup.new()
	setup.fixture_id = Ids.generate("fix")
	setup.competition = COMPETITION
	setup.home_team_id = own_id if not own_id.is_empty() else "mix_" + human.id
	setup.home_team_name = repo.get_organisation(own_id).name if not own_id.is_empty() else "Amateur Mix"
	setup.away_team_id = opponent.id
	setup.away_team_name = opponent.name
	setup.max_rounds = MAX_ROUNDS
	setup.map_id = map_id
	setup.home_lineup.append(repo.match_player(human.id, human.nickname, human.preferred_role, true))
	setup.away_lineup.assign(lineups[index])
	_fill_home(repo, setup, own_id)
	return setup


static func _fill_home(repo: CareerRepository, setup: MatchSetup, own_id: String) -> void:
	if not own_id.is_empty():
		for teammate: Dictionary in repo.lineup(own_id, TEAM_SIZE):
			if not bool(teammate["is_human"]):
				setup.home_lineup.append(teammate)
	var available := TEAM_SIZE - setup.home_lineup.size()
	if available <= 0:
		return
	var free_agents := repo.search_players({"free_agents": true, "ai_only": true, "limit": available})
	for found: Dictionary in free_agents:
		setup.home_lineup.append(repo.match_player(str(found["id"]), str(found["nickname"]),
			StringName(str(found["preferred_role"])), false))
