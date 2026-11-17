class_name WorldSeasons
extends RefCounted
## Closes league seasons and cup editions. Once every series of a season is scored (or a cup's
## final is decided), its final table is stored as the season record, the prize pool is paid by
## finishing position, the podium gains reputation (and last place loses some), and the squads of
## the top three earn honours. A human in a paid squad receives a share of the prize as a bonus.
## Champions make the news; a human's own finish is a headline.
##
## Promotion and relegation follow from final tables ([method _movement], and tier 4 open
## winners in [method close_cup]). Tiers change by swaps, so each tier keeps its size.

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
## Promotion swaps per league: one, or two for a field of at least this many.
const TWO_SWAP_FIELD: int = 12


## Share of the pool for each position 1..[param entrants] (sums to 1).
static func prize_shares(entrants: int) -> Array[float]:
	var shares: Array[float] = []
	var top := mini(entrants, TOP_SHARES.size())
	var used := 0.0
	for i: int in top:
		shares.append(TOP_SHARES[i])
		used += TOP_SHARES[i]
	var rest := entrants - top
	if rest == 0:
		if not shares.is_empty():
			shares[0] += 1.0 - used
		return shares
	# The other places share the remainder, never more each than 4th place; small fields are
	# then scaled up so the whole pool is still paid.
	var each := minf((1.0 - used) / rest, TOP_SHARES[top - 1])
	for i: int in rest:
		shares.append(each)
	var total := used + each * rest
	for i: int in shares.size():
		shares[i] /= total
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


static func season_name(season: Dictionary) -> String:
	return "%s %s" % [season["name"], GameDate.format_year(GameDate.make(int(season["season_year"]), 1, 1))]


## Daily: closes every league season whose series are all scored.
static func close_finished(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	for season: Dictionary in repo.seasons_to_close():
		if not _close(repo, season, day, rng):
			return false
	return true


static func _close(repo: CareerRepository, season: Dictionary, day: int, _rng: RandomNumberGenerator) -> bool:
	var competition_id := str(season["competition_id"])
	var year := int(season["season_year"])
	var table := CareerCompetitions.standings(repo.league_entrants(competition_id, year), repo.league_fixtures(competition_id, year))
	var no_wording: Dictionary[String, String] = {}
	if not _store(repo, season, table, no_wording, day):
		return false
	if table.is_empty():
		return true
	var champion := table[0]
	if not repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.NOTABLE if int(season["tier"]) <= 2 else WorldSimulation.MINOR,
			"%s win the %s with %d wins." % [champion["name"], season_name(season), int(champion["won"])], "",
			str(champion["organisation_id"])):
		return false
	return _movement(repo, season, table, day)


## Closes a cup edition from its final placings ([method CareerCups.final_table]). The winner of
## a regional open from tier 4 moves up to tier 3.
static func close_cup(repo: CareerRepository, season: Dictionary, table: Array[Dictionary], day: int) -> bool:
	var teams := table.size()
	var finishes: Dictionary[String, String] = {}
	for index: int in teams:
		var row := table[index]
		finishes[str(row["organisation_id"])] = "won" if index == 0 else ("reached the final" if index == 1
			else "went out in the %s" % CareerCups.round_name(int(row["_out"]), teams).to_lower())
	if not _store(repo, season, table, finishes, day):
		return false
	var name := season_name(season)
	if not repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.NOTABLE if int(season["tier"]) <= 2 else WorldSimulation.MINOR,
			"%s win the %s, beating %s in the final." % [table[0]["name"], name, table[1]["name"]], "",
			str(table[0]["organisation_id"])):
		return false
	var champion_id := str(table[0]["organisation_id"])
	var champion := repo.get_organisation(champion_id)
	if int(season["tier"]) < 4 or champion == null or champion.tier < 4:
		return true
	var moved: Array[String] = [champion_id]
	var down := repo.weakest_in_tier(3, _region(season), moved)
	if down.is_empty():
		down = repo.weakest_in_tier(3, "", moved)
	return _swap(repo, champion_id, down, 3, day, "after winning the %s" % name, "to make room for %s" % champion.name)


## Stores the record, pays prizes, applies reputation and honours, and tells a human how their
## organisation did ([param finishes] replaces "finished 3rd" with cup wording).
static func _store(repo: CareerRepository, season: Dictionary, table: Array[Dictionary],
		finishes: Dictionary[String, String], day: int) -> bool:
	var competition_id := str(season["competition_id"])
	var year := int(season["season_year"])
	var tier := int(season["tier"])
	var name := season_name(season)
	var human_orgs := _human_orgs(repo)
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
			var finish: String = finishes.get(org_id, "finished %s" % ordinal(position))
			if not repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.HEADLINE,
					"%s: your organisation %s and earned %s in prize money." % [name, finish,
					CareerCatalog.format_money(prize)], human_orgs[org_id], org_id):
				return false
	return true


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


## Promotion and relegation after a league of tier T:
## - up to T−1 (T ≥ 2): the best tier T finishers in the top half (one, or two in a field of
##   [constant TWO_SWAP_FIELD]+) swap with the worst tier T−1 entrant below them, or, when none
##   played, the least reputable tier T−1 organisation of the league's region (then anywhere);
## - up to T (T ≤ 3): the best tier T+1 filler in the top half swaps the same way with tier T.
static func _movement(repo: CareerRepository, season: Dictionary, table: Array[Dictionary], day: int) -> bool:
	var tier := int(season["tier"])
	var tiers: Dictionary[String, int] = {}
	for row: Dictionary in table:
		var org := repo.get_organisation(str(row["organisation_id"]))
		tiers[str(row["organisation_id"])] = org.tier if org != null else 4
	var moved: Array[String] = []
	var swaps := 2 if table.size() >= TWO_SWAP_FIELD else 1
	if tier >= 2 and not _promote(repo, season, table, tiers, tier, swaps, moved, day):
		return false
	if tier <= 3 and not _promote(repo, season, table, tiers, tier + 1, 1, moved, day):
		return false
	return true


## Moves up to [param count] organisations of [param from_tier] in the top half up one tier.
static func _promote(repo: CareerRepository, season: Dictionary, table: Array[Dictionary], tiers: Dictionary[String, int],
		from_tier: int, count: int, moved: Array[String], day: int) -> bool:
	var to_tier := from_tier - 1
	var name := season_name(season)
	@warning_ignore("integer_division")
	var top_half := maxi(1, table.size() / 2)
	var done := 0
	for index: int in top_half:
		var up := str(table[index]["organisation_id"])
		if done >= count or tiers[up] != from_tier or moved.has(up):
			continue
		moved.append(up)
		var down := ""
		for below: int in range(table.size() - 1, index, -1):
			var candidate := str(table[below]["organisation_id"])
			if tiers[candidate] == to_tier and not moved.has(candidate):
				down = candidate
				break
		if down.is_empty():
			down = repo.weakest_in_tier(to_tier, _region(season), moved)
		if down.is_empty():
			down = repo.weakest_in_tier(to_tier, "", moved)
		if not down.is_empty():
			moved.append(down)
		if not _swap(repo, up, down, to_tier, day, "after finishing %s in the %s" % [ordinal(index + 1), name],
				"after the %s" % name):
			return false
		done += 1
	return true


## [param up_id] moves up to [param to_tier]; [param down_id] (when not "") drops to the tier below it.
static func _swap(repo: CareerRepository, up_id: String, down_id: String, to_tier: int, day: int, up_reason: String,
		down_reason: String) -> bool:
	var humans := _human_orgs(repo)
	var up := repo.get_organisation(up_id)
	if up == null or not repo.set_organisation_tier(up_id, to_tier, day, "Promoted " + up_reason):
		return false
	if not _move_news(repo, up, to_tier, "%s are promoted to %s %s." % [up.name, CareerCatalog.tier_name(to_tier), up_reason],
			humans, day):
		return false
	if down_id.is_empty():
		return true
	var down := repo.get_organisation(down_id)
	if down == null or not repo.set_organisation_tier(down_id, to_tier + 1, day, "Relegated " + down_reason):
		return false
	return _move_news(repo, down, to_tier + 1, "%s are relegated to %s %s." % [down.name,
		CareerCatalog.tier_name(to_tier + 1), down_reason], humans, day)


static func _move_news(repo: CareerRepository, org: CareerRecords.OrganisationRecord, new_tier: int, text: String,
		humans: Dictionary[String, String], day: int) -> bool:
	if humans.has(org.id):
		return repo.add_news(day, WorldSimulation.NEWS_SEASON, WorldSimulation.HEADLINE, "Your organisation: " + text,
			humans[org.id], org.id)
	var importance := WorldSimulation.NOTABLE if mini(org.tier, new_tier) <= 2 else WorldSimulation.MINOR
	return repo.add_news(day, WorldSimulation.NEWS_SEASON, importance, text, "", org.id)


static func _human_orgs(repo: CareerRepository) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for human: CareerRecords.PlayerRecord in repo.human_players():
		var contract := repo.active_contract(human.id)
		if contract != null:
			found[contract.organisation_id] = human.id
	return found


static func _region(season: Dictionary) -> String:
	return str(season["region_id"]) if season.get("region_id") != null else ""
