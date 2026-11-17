class_name WorldFinance
extends RefCounted
## Organisation money: an opening balance, monthly income (sponsors and audience, by tier and
## reputation), monthly wages for every contracted player, prize money for series wins and
## transfer fees between organisations. Every movement is written to the ledger. Organisations
## in debt cannot buy and sell more readily ([WorldMarket]).
##
## Humans are paid their contract salary monthly into their own balance, then their services
## ([CareerSpending]) are charged.

## Opening balance by tier (scaled by reputation) for organisations without finances yet.
const TIER_FUNDS: Dictionary[int, int] = {1: 900000, 2: 300000, 3: 80000, 4: 12000}
## Monthly income by tier before the reputation factor.
const TIER_INCOME: Dictionary[int, int] = {1: 115000, 2: 45000, 3: 15000, 4: 3500}
## Prize money for winning a series, by competition tier.
const SERIES_PRIZE: Dictionary[int, int] = {1: 15000, 2: 5000, 3: 1500, 4: 400}
## A buyer keeps this many months of the new player's salary in hand after paying a fee.
const RUNWAY_MONTHS: int = 3
## Fees: (rating − 40)² × this, then age and contract-length factors, rounded to a thousand.
const FEE_SCALE: float = 60.0
const MIN_CONTRACT_SHARE: float = 0.25


## Reputation factor 0.75–1.25: bigger names attract more sponsors and viewers.
static func reputation_factor(reputation: int) -> float:
	return 0.75 + 0.5 * clampf(reputation / 100.0, 0.0, 1.0)


static func opening_balance(tier: int, reputation: int) -> int:
	return roundi(TIER_FUNDS.get(tier, TIER_FUNDS[4]) * reputation_factor(reputation) / 1000.0) * 1000


static func monthly_income(tier: int, reputation: int) -> int:
	return roundi(TIER_INCOME.get(tier, TIER_INCOME[4]) * reputation_factor(reputation) / 100.0) * 100


## Fee the selling organisation asks for a player.
static func transfer_fee(rating: int, age: int, days_left: int) -> int:
	var age_factor := 1.4 if age <= 21 else (1.15 if age <= 26 else (1.0 if age <= 29 else 0.7))
	var contract := clampf(days_left / 730.0, MIN_CONTRACT_SHARE, 1.0)
	var value := pow(maxf(rating - 40.0, 1.0), 2.0) * FEE_SCALE * age_factor * contract
	return maxi(1000, roundi(value / 1000.0) * 1000)


## True when [param balance] covers [param fee] and a few months of [param salary].
static func can_afford(balance: int, fee: int, salary: int) -> bool:
	return balance >= fee + salary * RUNWAY_MONTHS


## The salary an organisation can actually offer: what the player is worth, or less when money
## is tight (never below the tier's minimum).
static func affordable_salary(balance: int, wanted: int, tier: int) -> int:
	var minimum: int = WorldGenerator.TIER_PROFILE.get(tier, WorldGenerator.TIER_PROFILE[4])[3]
	return maxi(minimum, mini(wanted, roundi(maxf(balance, 0.0) / (RUNWAY_MONTHS * 2) / 50.0) * 50))


## Gives every organisation without finances its opening balance (new careers and older saves).
static func ensure(repo: CareerRepository, day: int) -> bool:
	for found: Dictionary in repo.organisations_without_finances():
		if not repo.add_organisation_money(str(found["id"]), opening_balance(int(found["tier"]), int(found["reputation"])),
				day, "opening", "Opening balance"):
			return false
	return true


## Monthly: income in, wages out, and humans paid.
static func monthly(repo: CareerRepository, day: int) -> bool:
	var bills := repo.wage_bills()
	var month := GameDate.format(day).substr(3)
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if not repo.add_organisation_money(org.id, monthly_income(org.tier, int(entry["reputation"])), day, "income",
				"Sponsors and audience · %s" % month):
			return false
		var wages: int = bills.get(org.id, 0)
		if wages > 0 and not repo.add_organisation_money(org.id, -wages, day, "wages", "Player wages · %s" % month):
			return false
	for paid: Dictionary in repo.paid_humans():
		var salary := int(paid["monthly_salary"])
		if salary > 0 and not repo.add_player_money(str(paid["player_id"]), salary, day, "salary", "Salary · %s" % month):
			return false
	return CareerSpending.monthly(repo, day)


static func award_series(repo: CareerRepository, winner_id: String, tier: int, day: int) -> bool:
	return repo.add_organisation_money(winner_id, SERIES_PRIZE.get(tier, SERIES_PRIZE[4]), day, "prize", "Series win")


## Moves a transfer fee from buyer to seller.
static func pay_fee(repo: CareerRepository, buyer_id: String, seller_id: String, fee: int, nickname: String, day: int) -> bool:
	return repo.add_organisation_money(buyer_id, -fee, day, "fee_paid", "Signed %s" % nickname) \
		and repo.add_organisation_money(seller_id, fee, day, "fee_received", "Sold %s" % nickname)
