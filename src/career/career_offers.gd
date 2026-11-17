class_name CareerOffers
extends RefCounted
## The human path to pro. Organisations notice an unsigned human through their visibility
## (reputation, amateur ELO and recent F2F ratings from matches they actually played) and invite
## them to a trial. A trial is a playable match alongside the organisation's own starters; a good
## performance earns a contract offer, and accepting it signs the human into the starting five.
## Every invitation, verdict and offer is a headline, so Continue stops for it.
##
## Organisations judge humans by what the world can see (perceived values, reputation and
## recorded results), never by anything hidden.

## Visibility needed before organisations of each tier take notice (0–100 scale).
const TIER_VISIBILITY: Dictionary[int, float] = {4: 10.0, 3: 25.0, 2: 45.0, 1: 65.0}
## An organisation only considers a human whose perceived level is within this of its tier's norm.
const LEVEL_MARGIN: int = 12
## Daily chance that some interested organisation acts, while the human has room for offers.
const DAILY_INTEREST: float = 0.15
const MAX_OPEN: int = 2
## Days an invitation or offer stays open, and before the same organisation asks again.
const OPEN_DAYS: int = 7
const COOLDOWN_DAYS: int = 60
## Trial verdict: a F2F rating this high passes; a win needs a little less.
const TRIAL_PASS_RATING: float = 1.0
const TRIAL_PASS_WITH_WIN: float = 0.85
const TRIAL_MAX_ROUNDS: int = 5
const TRIAL_COMPETITION: String = "Trial"
const CONTRACT_YEARS: Vector2i = Vector2i(1, 2)

## Contract talks: one request per offer for this much more, granted with this chance when the
## organisation can afford it.
const RAISE_SHARE: float = 0.2
const RAISE_CHANCE: float = 0.55

const KIND_TRIAL: String = "trial"
const KIND_CONTRACT: String = "contract"


## How visible a human is to organisations: half their reputation, their amateur ELO above 800
## (1 point per 20) and recent form (F2F rating 1.0 = neutral). Clamped to 0–100.
static func visibility(reputation: int, elo: int, recent_ratings: Array[float]) -> float:
	var form := 0.0
	if not recent_ratings.is_empty():
		var total := 0.0
		for rating: float in recent_ratings:
			total += rating
		form = clampf((total / recent_ratings.size() - 1.0) * 20.0, -10.0, 10.0)
	return clampf(reputation * 0.5 + clampf((elo - 800) / 20.0, 0.0, 40.0) + form, 0.0, 100.0)


## True when an organisation of [param tier] would invite a human with this visibility and
## perceived rating.
static func would_consider(tier: int, visibility_score: float, perceived: int) -> bool:
	var typical: int = WorldGenerator.TIER_PROFILE.get(tier, WorldGenerator.TIER_PROFILE[4])[0]
	return visibility_score >= TIER_VISIBILITY.get(tier, 100.0) and perceived >= typical - LEVEL_MARGIN


## True when a trial performance earns a contract offer.
static func trial_passed(rating: float, won: bool) -> bool:
	return rating >= TRIAL_PASS_RATING or (won and rating >= TRIAL_PASS_WITH_WIN)


## Daily: lapsed offers expire, interested organisations may invite unsigned humans, and
## contracted humans get renewal decisions and transfer offers ([CareerHumanContracts]).
static func daily(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	for lapsed: Dictionary in repo.lapsed_offers(day):
		if not repo.set_offer_status(str(lapsed["id"]), "expired", day) or not repo.add_news(day, WorldSimulation.NEWS_OFFER,
				WorldSimulation.MINOR, "%s's %s lapsed." % [lapsed["org_name"], _offer_noun(str(lapsed["kind"]))],
				str(lapsed["player_id"]), str(lapsed["organisation_id"])):
			return false
	for human: CareerRecords.PlayerRecord in repo.human_players():
		if human.status != "active":
			continue
		var contract := repo.active_contract(human.id)
		if contract != null:
			if not CareerHumanContracts.daily(repo, human, contract, day, rng):
				return false
			continue
		if repo.offers(human.id, true).size() >= MAX_OPEN or rng.randf() >= DAILY_INTEREST:
			continue
		var org := _interested_organisation(repo, human.id, day, rng)
		if org.is_empty():
			continue
		var invitation := {"id": Ids.seeded("ofr", rng), "player_id": human.id, "organisation_id": org["id"],
			"kind": KIND_TRIAL, "role": String(human.preferred_role), "monthly_salary": 0, "years": 1,
			"created_day": day, "expires_day": day + OPEN_DAYS}
		if not repo.insert_offer(invitation) or not repo.add_news(day, WorldSimulation.NEWS_OFFER, WorldSimulation.HEADLINE,
				"%s invite you to a trial. Accept it from Home within %d days." % [org["name"], OPEN_DAYS],
				human.id, str(org["id"])):
			return false
	return true


## Accepts an offer. A trial books the trial match (played from Home); a contract signs the human.
## Returns "" or why not.
static func accept(repo: CareerRepository, player_id: String, offer_id: String) -> String:
	var found := repo.offer(offer_id)
	if found.is_empty() or str(found["player_id"]) != player_id or str(found["status"]) != "pending":
		return "This offer is no longer open."
	var kind := str(found["kind"])
	if kind == CareerHumanContracts.KIND_TRANSFER or kind == CareerHumanContracts.KIND_RENEWAL:
		return CareerHumanContracts.accept(repo, player_id, found)
	if repo.active_contract(player_id) != null:
		return "You are already under contract."
	if kind == KIND_TRIAL:
		return _book_trial(repo, player_id, found)
	return sign_human(repo, player_id, found)


## Contract talks: asks once for [constant RAISE_SHARE] more. Returns {ok, message}; ok is true
## when the organisation improved its offer. The offer stays open either way.
static func negotiate(repo: CareerRepository, player_id: String, offer_id: String,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var found := repo.offer(offer_id)
	if found.is_empty() or str(found["player_id"]) != player_id or str(found["status"]) != "pending" \
			or str(found["kind"]) == KIND_TRIAL:
		return {"ok": false, "message": "There is no open contract offer to discuss."}
	if int(found["negotiated"]) == 1:
		return {"ok": false, "message": "%s have already given their final offer." % found["org_name"]}
	var dice := rng
	if dice == null:
		dice = RandomNumberGenerator.new()
		dice.randomize()
	var current := int(found["monthly_salary"])
	var asked := maxi(current + 50, roundi(current * (1.0 + RAISE_SHARE) / 50.0) * 50)
	var org_id := str(found["organisation_id"])
	var granted := dice.randf() < RAISE_CHANCE and WorldFinance.can_afford(repo.organisation_balance(org_id), 0, asked)
	var salary := asked if granted else current
	if not repo.set_offer_salary(offer_id, salary):
		return {"ok": false, "message": "Could not record the talks."}
	if granted:
		return {"ok": true, "message": "%s agree to %s a month. This is their final offer." % [found["org_name"],
			CareerCatalog.format_money(salary)]}
	return {"ok": false, "message": "%s will not go higher than %s a month." % [found["org_name"], CareerCatalog.format_money(current)]}


static func decline(repo: CareerRepository, player_id: String, offer_id: String) -> String:
	var found := repo.offer(offer_id)
	if found.is_empty() or str(found["player_id"]) != player_id or str(found["status"]) != "pending":
		return "This offer is no longer open."
	var day := repo.current_day()
	var ok := repo.transaction(func() -> bool:
		return repo.set_offer_status(offer_id, "declined", day) and repo.add_news(day, WorldSimulation.NEWS_OFFER,
			WorldSimulation.MINOR, "You turned down %s's %s." % [found["org_name"], _offer_noun(str(found["kind"]))],
			player_id, str(found["organisation_id"])))
	return "" if ok else "Could not decline the offer."


## Called once when the trial match result is saved (inside its transaction). Passing earns a
## contract offer; failing closes the door for a while.
static func apply_trial_result(repo: CareerRepository, trial: Dictionary, result: MatchResult, counts: Dictionary) -> bool:
	var player_id := str(trial["player_id"])
	var day := repo.current_day()
	var won := result.home_score > result.away_score
	var rating := MatchStatistics.rating(counts) if not counts.is_empty() else (1.0 if won else 0.7)
	var org_id := str(trial["organisation_id"])
	if not trial_passed(rating, won):
		return repo.set_offer_status(str(trial["id"]), "failed", day) and repo.add_news(day, WorldSimulation.NEWS_OFFER,
			WorldSimulation.HEADLINE, "%s decided not to offer you a contract after your trial (rating %.2f)." % [
				trial["org_name"], rating], player_id, org_id)
	var tier := int(trial["tier"])
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var years := rng.randi_range(CONTRACT_YEARS.x, CONTRACT_YEARS.y)
	var contract := {"id": Ids.generate("ofr"), "player_id": player_id, "organisation_id": org_id,
		"kind": KIND_CONTRACT, "role": str(trial["role"]),
		"monthly_salary": WorldFinance.affordable_salary(repo.organisation_balance(org_id),
			WorldMarket.salary_for(tier, repo.perceived_rating(player_id)), tier), "years": years,
		"created_day": day, "expires_day": day + OPEN_DAYS}
	return repo.set_offer_status(str(trial["id"]), "passed", day) and repo.insert_offer(contract) \
		and repo.add_news(day, WorldSimulation.NEWS_OFFER, WorldSimulation.HEADLINE,
			"%s offer you a %d-year contract after your trial (rating %.2f)." % [trial["org_name"], years, rating],
			player_id, org_id)


static func _interested_organisation(repo: CareerRepository, player_id: String, day: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var seen := visibility(repo.reputation(player_id), CareerDevelopment.current_elo(repo, player_id),
		repo.recent_ratings(player_id))
	var perceived := repo.perceived_rating(player_id)
	var suitors := repo.recent_suitors(player_id, day - COOLDOWN_DAYS)
	var best_tier := 99
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if suitors.has(org.id) or org.tier > best_tier or not would_consider(org.tier, seen, perceived):
			continue
		if repo.organisation_has_human(org.id) or repo.lineup(org.id).size() < CareerFixtures.TEAM_SIZE - 1:
			continue
		if org.tier < best_tier:
			best_tier = org.tier
			candidates.clear()
		candidates.append({"id": org.id, "name": org.name, "tier": org.tier})
	return candidates[rng.randi() % candidates.size()] if not candidates.is_empty() else {}


static func _book_trial(repo: CareerRepository, player_id: String, found: Dictionary) -> String:
	if repo.pending_fixture(player_id) != null:
		return "Play your scheduled match before booking a trial."
	var setup := _trial_setup(repo, player_id, found)
	if setup == null:
		return "%s cannot field a trial match right now." % found["org_name"]
	var fixture := CareerFixture.new()
	fixture.player_id = player_id
	fixture.scheduled_day = repo.current_day()
	fixture.setup = setup
	var ok := repo.transaction(func() -> bool:
		return repo.insert_fixture(fixture) and repo.set_offer_status(str(found["id"]), "accepted",
			repo.current_day(), setup.fixture_id))
	return "" if ok else "Could not book the trial."


## The trial: the human plus the organisation's four best AI starters against a side of the
## same tier (or the nearest one) that fields five AI starters.
static func _trial_setup(repo: CareerRepository, player_id: String, found: Dictionary) -> MatchSetup:
	var human := repo.get_player(player_id)
	var org_id := str(found["organisation_id"])
	var tier := int(found["tier"])
	var teammates: Array[Dictionary] = []
	for member: Dictionary in repo.lineup(org_id):
		if not bool(member["is_human"]) and teammates.size() < CareerFixtures.TEAM_SIZE - 1:
			teammates.append(member)
	var opponent: CareerRecords.OrganisationRecord = null
	var opponent_lineup: Array[Dictionary] = []
	var best_gap := 99
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if org.id == org_id or absi(org.tier - tier) >= best_gap:
			continue
		var lineup := repo.lineup(org.id)
		if lineup.size() == CareerFixtures.TEAM_SIZE and lineup.all(func(p: Dictionary) -> bool: return not bool(p["is_human"])):
			opponent = org
			opponent_lineup = lineup
			best_gap = absi(org.tier - tier)
	if human == null or opponent == null or teammates.is_empty():
		return null
	var setup := MatchSetup.new()
	setup.fixture_id = Ids.generate("fix")
	setup.competition = "%s · %s" % [TRIAL_COMPETITION, found["org_name"]]
	setup.home_team_id = org_id
	setup.home_team_name = str(found["org_name"])
	setup.away_team_id = opponent.id
	setup.away_team_name = opponent.name
	setup.max_rounds = TRIAL_MAX_ROUNDS
	setup.map_id = CareerLeagueMatches.MAP_POOL[0]
	setup.home_lineup.append(repo.match_player(human.id, human.nickname, human.preferred_role, true))
	setup.home_lineup.append_array(teammates)
	setup.away_lineup.assign(opponent_lineup)
	return setup


## Signs the human as a starter. The organisation's weakest AI starter becomes a substitute when
## the five is full, and every other open offer is withdrawn.
static func sign_human(repo: CareerRepository, player_id: String, found: Dictionary) -> String:
	var day := repo.current_day()
	var org_id := str(found["organisation_id"])
	var ok := repo.transaction(func() -> bool:
		var starters: Array[Dictionary] = []
		for entry: Dictionary in repo.roster(org_id):
			if not (entry["contract"] as CareerRecords.ContractRecord).is_substitute:
				starters.append(entry)
		if starters.size() >= CareerFixtures.TEAM_SIZE:
			var weakest := starters[starters.size() - 1]["contract"] as CareerRecords.ContractRecord
			if not repo.set_contract_substitute(weakest.id, true):
				return false
		var contract := CareerRecords.ContractRecord.new()
		contract.id = Ids.generate("con")
		contract.player_id = player_id
		contract.organisation_id = org_id
		contract.role = StringName(str(found["role"]))
		contract.monthly_salary = int(found["monthly_salary"])
		contract.start_day = day
		contract.end_day = day + int(found["years"]) * GameDate.DAYS_PER_YEAR
		if not repo.sign_contract(contract) or not repo.set_offer_status(str(found["id"]), "accepted", day):
			return false
		for other: Dictionary in repo.offers(player_id, true):
			if str(other["id"]) != str(found["id"]) and str(other["status"]) == "pending" \
					and not repo.set_offer_status(str(other["id"]), "withdrawn", day):
				return false
		return repo.add_news(day, WorldSimulation.NEWS_SIGNING, WorldSimulation.HEADLINE,
			"You sign for %s until %s. Their league series are now yours to play." % [found["org_name"],
				GameDate.format(contract.end_day)], player_id, org_id))
	return "" if ok else "Could not sign the contract: %s" % repo.db.last_error


static func _offer_noun(kind: String) -> String:
	return {KIND_TRIAL: "trial invitation", CareerHumanContracts.KIND_TRANSFER: "transfer offer",
		CareerHumanContracts.KIND_RENEWAL: "renewal offer"}.get(kind, "contract offer")
