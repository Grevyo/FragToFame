class_name CareerHumanContracts
extends RefCounted
## Life under contract for a human. Organisations judge them by what the world can see
## (perceived values, reputation, visibility and the F2F ratings of matches they played):
## - Transfer offers: a higher-tier organisation that would consider the human may offer a
##   contract and pay their organisation a transfer fee. Accepting moves the human at once.
## - Renewal: [constant RENEWAL_NOTICE] days before the contract ends, the organisation offers a
##   new deal or says it will let the human go (released when the contract expires).
## - Benching: monthly, poor recent ratings can cost a starter their place to a better substitute;
##   a benched human can win it back. Benched humans' organisations play (simulated) without them.
## Every decision is a headline, so Continue stops for it.

const KIND_TRANSFER: String = "transfer"
const KIND_RENEWAL: String = "renewal"
## Daily chance that a suitable higher-tier organisation makes a transfer offer.
const TRANSFER_INTEREST: float = 0.02
## A human signed this recently is left alone by other organisations.
const SETTLE_DAYS: int = 90
const RENEWAL_NOTICE: int = 60
const RENEWAL_OPEN_DAYS: int = 30
## Renewals pay this much more when the organisation can afford it.
const RENEWAL_RAISE: float = 0.1
## Recent ratings (at least [constant FORM_MATCHES]) averaging below this put a starter at risk.
const BENCH_RATING: float = 0.85
const FORM_MATCHES: int = 3
const BENCH_CHANCE: float = 0.5
## Monthly chance a benched human is brought back when they are not clearly worse.
const RESTORE_CHANCE: float = 0.35
const RESTORE_MARGIN: int = 3


## Daily, for a contracted human: renewal decisions and transfer interest.
static func daily(repo: CareerRepository, human: CareerRecords.PlayerRecord, contract: CareerRecords.ContractRecord,
		day: int, rng: RandomNumberGenerator) -> bool:
	if contract.end_day - day == RENEWAL_NOTICE and contract.end_day - contract.start_day > RENEWAL_NOTICE:
		if not _renewal(repo, human, contract, day, rng):
			return false
	if day - contract.start_day < SETTLE_DAYS or rng.randf() >= TRANSFER_INTEREST:
		return true
	if repo.offers(human.id, true).any(func(o: Dictionary) -> bool: return str(o["kind"]) == KIND_TRANSFER):
		return true
	return _transfer_offer(repo, human, contract, day, rng)


## Monthly: a struggling starter may be benched; a benched human may win their place back.
static func monthly(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	for human: CareerRecords.PlayerRecord in repo.human_players():
		var contract := repo.active_contract(human.id)
		if contract == null or repo.pending_fixture(human.id) != null:
			continue
		var ok := _restore(repo, human, contract, day, rng) if contract.is_substitute else _bench(repo, human, contract, day, rng)
		if not ok:
			return false
	return true


static func average(ratings: Array[float]) -> float:
	if ratings.is_empty():
		return 1.0
	var total := 0.0
	for rating: float in ratings:
		total += rating
	return total / ratings.size()


## Whether the organisation wants to keep the human: level near its tier's norm, no slump, and
## a starter (a benched human is kept half the time).
static func wants_to_keep(tier: int, perceived: int, ratings: Array[float], benched: bool, roll: float) -> bool:
	var typical: int = WorldGenerator.TIER_PROFILE.get(tier, WorldGenerator.TIER_PROFILE[4])[0]
	if perceived < typical - CareerOffers.LEVEL_MARGIN:
		return false
	if ratings.size() >= FORM_MATCHES and average(ratings) < BENCH_RATING:
		return false
	return not benched or roll < 0.5


## True when a starter's recent ratings put their place at risk this month.
static func should_bench(ratings: Array[float], roll: float) -> bool:
	return ratings.size() >= FORM_MATCHES and average(ratings) < BENCH_RATING and roll < BENCH_CHANCE


## Accepts a transfer or renewal offer. Returns "" or why not.
static func accept(repo: CareerRepository, player_id: String, found: Dictionary) -> String:
	var current := repo.active_contract(player_id)
	if current == null:
		return "You are no longer under contract."
	if repo.pending_fixture(player_id) != null:
		return "Play your scheduled match first."
	var day := repo.current_day()
	var buyer_id := str(found["organisation_id"])
	if str(found["kind"]) == KIND_RENEWAL:
		if buyer_id != current.organisation_id:
			return "This renewal is no longer valid."
		var renewed := repo.transaction(func() -> bool:
			var contract := _contract(player_id, buyer_id, current.role, current.is_substitute, int(found["monthly_salary"]),
				day, current.end_day + int(found["years"]) * GameDate.DAYS_PER_YEAR)
			return repo.end_contract(current.id, "expired", day) and repo.sign_contract(contract) \
				and repo.set_offer_status(str(found["id"]), "accepted", day) \
				and repo.add_news(day, WorldSimulation.NEWS_CONTRACT, WorldSimulation.HEADLINE, "You extend with %s until %s." % [
					found["org_name"], GameDate.format(contract.end_day)], player_id, buyer_id))
		return "" if renewed else "Could not renew the contract: %s" % repo.db.last_error
	var fee := int(found["fee"])
	if not WorldFinance.can_afford(repo.organisation_balance(buyer_id), fee, int(found["monthly_salary"])):
		return "%s can no longer afford the fee." % found["org_name"]
	var seller := repo.get_organisation(current.organisation_id)
	var human := repo.get_player(player_id)
	var moved := repo.transaction(func() -> bool:
		if not WorldFinance.pay_fee(repo, buyer_id, current.organisation_id, fee, human.nickname, day):
			return false
		if not repo.end_contract(current.id, "terminated", day):
			return false
		return CareerOffers.sign_human(repo, player_id, found).is_empty() and repo.add_news(day, WorldSimulation.NEWS_TRANSFER,
			WorldSimulation.HEADLINE, "%s pay %s %s for you." % [found["org_name"], seller.name if seller != null else "your club",
				CareerCatalog.format_money(fee)], player_id, buyer_id))
	return "" if moved else "Could not complete the transfer: %s" % repo.db.last_error


static func _renewal(repo: CareerRepository, human: CareerRecords.PlayerRecord, contract: CareerRecords.ContractRecord,
		day: int, rng: RandomNumberGenerator) -> bool:
	var org := repo.get_organisation(contract.organisation_id)
	if org == null:
		return true
	if not wants_to_keep(org.tier, repo.perceived_rating(human.id), repo.recent_ratings(human.id), contract.is_substitute, rng.randf()):
		return repo.add_news(day, WorldSimulation.NEWS_CONTRACT, WorldSimulation.HEADLINE,
			"%s will not renew your contract. It ends on %s and you will be a free agent." % [org.name,
				GameDate.format(contract.end_day)], human.id, org.id)
	var wanted := roundi(contract.monthly_salary * (1.0 + RENEWAL_RAISE) / 50.0) * 50
	var salary := maxi(contract.monthly_salary, WorldFinance.affordable_salary(repo.organisation_balance(org.id), wanted, org.tier))
	var years := rng.randi_range(CareerOffers.CONTRACT_YEARS.x, CareerOffers.CONTRACT_YEARS.y)
	var offer := {"id": Ids.seeded("ofr", rng), "player_id": human.id, "organisation_id": org.id, "kind": KIND_RENEWAL,
		"role": String(contract.role), "monthly_salary": salary, "years": years, "created_day": day,
		"expires_day": mini(contract.end_day - 1, day + RENEWAL_OPEN_DAYS)}
	return repo.insert_offer(offer) and repo.add_news(day, WorldSimulation.NEWS_OFFER, WorldSimulation.HEADLINE,
		"%s offer to extend your contract by %d year%s at %s a month. Answer from Home." % [org.name, years,
			"" if years == 1 else "s", CareerCatalog.format_money(salary)], human.id, org.id)


static func _transfer_offer(repo: CareerRepository, human: CareerRecords.PlayerRecord, contract: CareerRecords.ContractRecord,
		day: int, rng: RandomNumberGenerator) -> bool:
	var current := repo.get_organisation(contract.organisation_id)
	if current == null or current.tier <= 1:
		return true
	var seen := CareerOffers.visibility(repo.reputation(human.id), CareerDevelopment.current_elo(repo, human.id),
		repo.recent_ratings(human.id))
	var perceived := repo.perceived_rating(human.id)
	var suitors := repo.recent_suitors(human.id, day - CareerOffers.COOLDOWN_DAYS)
	var fee := WorldFinance.transfer_fee(perceived, GameDate.age(human.birth_day, day), contract.end_day - day)
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if org.tier >= current.tier or suitors.has(org.id) or repo.organisation_has_human(org.id):
			continue
		if not CareerOffers.would_consider(org.tier, seen, perceived):
			continue
		var salary := WorldFinance.affordable_salary(repo.organisation_balance(org.id), WorldMarket.salary_for(org.tier, perceived), org.tier)
		if WorldFinance.can_afford(repo.organisation_balance(org.id), fee, salary):
			candidates.append({"org": org, "salary": salary})
	if candidates.is_empty():
		return true
	var pick: Dictionary = candidates[rng.randi() % candidates.size()]
	var buyer := pick["org"] as CareerRecords.OrganisationRecord
	var years := rng.randi_range(CareerOffers.CONTRACT_YEARS.x, CareerOffers.CONTRACT_YEARS.y)
	var offer := {"id": Ids.seeded("ofr", rng), "player_id": human.id, "organisation_id": buyer.id, "kind": KIND_TRANSFER,
		"role": String(human.preferred_role), "monthly_salary": int(pick["salary"]), "years": years, "created_day": day,
		"expires_day": day + CareerOffers.OPEN_DAYS, "fee": fee}
	return repo.insert_offer(offer) and repo.add_news(day, WorldSimulation.NEWS_OFFER, WorldSimulation.HEADLINE,
		"%s (%s) want to sign you from %s for %s: %d-year contract at %s a month. Answer from Home." % [buyer.name,
			CareerCatalog.tier_name(buyer.tier), current.name, CareerCatalog.format_money(fee), years,
			CareerCatalog.format_money(int(pick["salary"]))], human.id, buyer.id)


static func _bench(repo: CareerRepository, human: CareerRecords.PlayerRecord, contract: CareerRecords.ContractRecord,
		day: int, rng: RandomNumberGenerator) -> bool:
	var ratings := repo.recent_ratings(human.id)
	if not should_bench(ratings, rng.randf()):
		return true
	var perceived := repo.perceived_rating(human.id)
	for entry: Dictionary in repo.roster(contract.organisation_id):
		var other := entry["contract"] as CareerRecords.ContractRecord
		if not other.is_substitute or (entry["player"] as CareerRecords.PlayerRecord).is_human or int(entry["rating"]) <= perceived:
			continue
		return repo.set_contract_substitute(other.id, false) and repo.set_contract_substitute(contract.id, true) \
			and repo.add_news(day, WorldSimulation.NEWS_CONTRACT, WorldSimulation.HEADLINE,
				"After your recent form (average rating %.2f) you lose your starting place to %s. Train and wait for your chance." % [
					average(ratings), (entry["player"] as CareerRecords.PlayerRecord).nickname], human.id, contract.organisation_id)
	return true


static func _restore(repo: CareerRepository, human: CareerRecords.PlayerRecord, contract: CareerRecords.ContractRecord,
		day: int, rng: RandomNumberGenerator) -> bool:
	var starters: Array[Dictionary] = []
	for entry: Dictionary in repo.roster(contract.organisation_id):
		if not (entry["contract"] as CareerRecords.ContractRecord).is_substitute:
			starters.append(entry)
	var short := starters.size() < CareerFixtures.TEAM_SIZE
	var weakest: Dictionary = starters.back() if not starters.is_empty() else {}
	var close := not weakest.is_empty() and repo.perceived_rating(human.id) + RESTORE_MARGIN >= int(weakest["rating"])
	if not short and not (close and rng.randf() < RESTORE_CHANCE):
		return true
	if not short and not repo.set_contract_substitute((weakest["contract"] as CareerRecords.ContractRecord).id, true):
		return false
	var org := repo.get_organisation(contract.organisation_id)
	return repo.set_contract_substitute(contract.id, false) and repo.add_news(day, WorldSimulation.NEWS_CONTRACT,
		WorldSimulation.HEADLINE, "%s bring you back into the starting five." % (org.name if org != null else "Your organisation"),
		human.id, contract.organisation_id)


static func _contract(player_id: String, org_id: String, role: StringName, substitute: bool, salary: int, start_day: int,
		end_day: int) -> CareerRecords.ContractRecord:
	var contract := CareerRecords.ContractRecord.new()
	contract.id = Ids.generate("con")
	contract.player_id = player_id
	contract.organisation_id = org_id
	contract.role = role
	contract.is_substitute = substitute
	contract.monthly_salary = salary
	contract.start_day = start_day
	contract.end_day = end_day
	return contract
