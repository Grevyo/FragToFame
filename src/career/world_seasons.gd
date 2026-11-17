class_name WorldSeasons
extends RefCounted
## Closes league seasons. Once every series of a season is scored, its final table is stored as
## the season record, the prize pool is paid by finishing position, the podium gains reputation
## (and last place loses some), and the squads of the top three earn honours. A human in a paid
## squad receives a share of the prize as a bonus. Champions make the news; a human's own
## finish is a headline.

## Prize pool by competition tier.
const PRIZE_POOL: Dictionary[int, int] = {1: 1000000, 2: 300000, 3: 80000, 4: 15000}
## Shares of the pool for the top four; the rest is split evenly across the other places.
const TOP_SHARES: Array[float] = [0.35, 0.2, 0.13, 0.09]
## Reputation for the top three, and the penalty for finishing last.
const PODIUM_REPUTATION: Array[int] = [5, 3, 1]
const LAST_PLACE_REPUTATION: int = -3
## Reputation for each player in a podium squad (players, by position).
const PLAYER_PODIUM_REPUTATION: Array[int] = [2, 1, 1]
## Share of an organisation's prize paid out to its squad as bonuses.
const SQUAD_BONUS_SHARE: float = 0.2


## Share of the pool for each position 1..[param entrants] (sums to 1).
static func prize_shares(entrants: int) -> Array[float]:
	var shares: Array[float] = []
	var top := mini(entrants, TOP_SHARES.size())
	var used := 0.0
	for i: int in top:
		shares.append(TOP_SHARES[i])
		used += TOP_SHARES[i]
	var rest := entrants - top
	for i: int in rest:
		shares.append((1.0 - used) / rest)
	if rest == 0 and not shares.is_empty():
		shares[0] += 1.0 - used
	return shares


static func prize_for(tier: int, entrants: int, position: int) -> int:
	var shares := prize_shares(entrants)
	if position < 1 or position > shares.size():
		return 0
	return roundi(PRIZE_POOL.get(tier, PRIZE_POOL[4]) * shares[position - 1] / 100.0) * 100


static func ordinal(position: int) -> String:
	var suffix := "th"
	if position % 100 < 11 or position % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(position % 10, "th")
	return "%d%s" % [position, suffix]


## Daily: closes every league season whose series are all scored.
static func close_finished(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	for season: Dictionary in repo.seasons_to_close():
		if not _close(repo, season, day, rng):
			return false
	return true


static func _close(repo: CareerRepository, season: Dictionary, day: int, rng: RandomNumberGenerator) -> bool:
	var competition_id := str(season["competition_id"])
	var year := int(season["season_year"])
	var tier := int(season["tier"])
	var name := "%s %s" % [season["name"], GameDate.format_year(GameDate.make(year, 1, 1))]
	var table := CareerCompetitions.standings(repo.league_entrants(competition_id, year), repo.league_fixtures(competition_id, year))
	var human_orgs: Dictionary[String, String] = {}
	for human: CareerRecords.PlayerRecord in repo.human_players():
		var contract := repo.active_contract(human.id)
		if contract != null:
			human_orgs[contract.organisation_id] = human.id
	for index: int in table.size():
		var row := table[index]
		var position := index + 1
		var org_id := str(row["organisation_id"])
		var prize := prize_for(tier, table.size(), position)
		if not repo.insert_league_record(competition_id, year, position, row, prize, day):
			return false
		if prize > 0 and not repo.add_organisation_money(org_id, prize, day, "prize", "%s · %s" % [name, ordinal(position)]):
			return false
		var reputation_change := PODIUM_REPUTATION[index] if index < PODIUM_REPUTATION.size() else 0
		if position == table.size() and table.size() > 3:
			reputation_change = LAST_PLACE_REPUTATION
		if reputation_change != 0 and not repo.set_organisation_reputation(org_id,
				repo.organisation_reputation(org_id) + reputation_change, day):
			return false
		if not _reward_squad(repo, competition_id, year, position, org_id, prize, day, name):
			return false
		if human_orgs.has(org_id):
			var player_id := human_orgs[org_id]
			if not repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.HEADLINE,
					"%s: your organisation finished %s and earned %s in prize money." % [name, ordinal(position),
					CareerCatalog.format_money(prize)], player_id, org_id):
				return false
	if table.is_empty():
		return true
	var champion := table[0]
	return repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.NOTABLE if tier <= 2 else WorldSimulation.MINOR,
		"%s win the %s with %d wins." % [champion["name"], name, int(champion["won"])], "", str(champion["organisation_id"]))


## Honours and reputation for a podium squad; a share of the prize for any human in the squad.
static func _reward_squad(repo: CareerRepository, competition_id: String, year: int, position: int,
		org_id: String, prize: int, day: int, name: String) -> bool:
	var squad := repo.roster(org_id)
	for entry: Dictionary in squad:
		var player := entry["player"] as CareerRecords.PlayerRecord
		if position <= PLAYER_PODIUM_REPUTATION.size():
			if not repo.add_honour(player.id, competition_id, year, position, org_id):
				return false
			if not repo.set_reputation(player.id, repo.reputation(player.id) + PLAYER_PODIUM_REPUTATION[position - 1], day):
				return false
		if player.is_human and prize > 0:
			var bonus := roundi(prize * SQUAD_BONUS_SHARE / maxi(squad.size(), 1))
			if bonus > 0 and not repo.add_player_money(player.id, bonus, day, "bonus", "%s · %s" % [name, ordinal(position)]):
				return false
	return true
