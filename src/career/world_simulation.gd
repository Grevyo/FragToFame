class_name WorldSimulation
extends RefCounted
## The living world: what happens to a career's database on each day that passes. Called by
## [CareerCalendar] (the only date writer) inside the same transaction as the date change, so a
## day either happens completely or not at all.
##
## Every day:   series results move form and reputation; contracts end (renewed or released);
##              organisations short of starters sign free agents; weekly (busiest in the
##              January and July windows, sooner when in poor form) they buy or sign upgrades;
##              season openings make news;
##              finished league seasons close with prizes and records, promotion and
##              relegation ([WorldSeasons]); cup rounds are drawn and finals close the cup
##              ([CareerCups]);
##              organisations may invite an unsigned human to a trial ([CareerOffers]); a
##              contracted human's due league series is booked to play ([CareerLeagueMatches]).
## Each month:  AI players develop or decline, the world's opinion catches up with the truth,
##              reputations drift back towards what an organisation's level supports, and
##              money moves: income in, wages out, humans paid ([WorldFinance]); a struggling
##              human starter may be benched, a benched one recalled ([CareerHumanContracts]).
## Each year:   veterans retire and a class of original rookies enters the scene.
##
## Humans are never developed or re-rated by the world: their skill is the person, and their
## reputation only moves through matches they play (amateur matches, their league series).

## News importance. Continue (FM-style) stops on headlines.
const MINOR: int = 1
const NOTABLE: int = 2
const HEADLINE: int = 3
## News kinds (stable ids stored in saves).
const NEWS_CONTRACT: String = "contract"
const NEWS_RELEASE: String = "release"
const NEWS_SIGNING: String = "signing"
const NEWS_RETIREMENT: String = "retirement"
const NEWS_ROOKIES: String = "rookies"
const NEWS_SEASON: String = "season"
const NEWS_NEW_YEAR: String = "new_year"
const NEWS_OFFER: String = "offer"
const NEWS_TRANSFER: String = "transfer"

## Form after a series: old form × KEEP + GAIN × outcome (outcome 1 = clean sweep, −1 = swept).
const FORM_KEEP: float = 0.6
const FORM_GAIN: float = 40.0
## Strength points per form point when simulating series (±100 form = ±3 ability points).
const FORM_STRENGTH: float = 0.03
## Reputation: Elo-style on the 0–100 scale. Expected score from the reputation gap.
const REPUTATION_SCALE: float = 25.0
## Points at stake per series, by competition tier.
const REPUTATION_K: Dictionary[int, float] = {1: 6.0, 2: 4.5, 3: 3.0, 4: 2.0}
## Share of an organisation's change that its AI starters receive.
const PLAYER_SHARE: float = 0.5
## Monthly drift of organisation reputation towards its tier's typical range.
const ORG_DRIFT_MARGIN: int = 5
## Monthly chances: a free agent is forgotten a little; a signed player converges on the team.
const FREE_AGENT_FADE: float = 0.5
const PLAYER_CONVERGE: float = 0.3
## Rookies per year: at least this many, and enough to replace the retired.
const MIN_ROOKIES: int = 10
const EXTRA_ROOKIES: int = 2
## Retirements notable enough to be their own story.
const NOTABLE_REPUTATION: int = 60


## Runs everything that happens on [param day] apart from resolving series (the calendar does
## that first so today's world sees yesterday's results).
static func simulate_day(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	if not WorldFinance.ensure(repo, day):
		return false
	if GameDate.day_of_year(day) == 0:
		if not _new_year(repo, day, rng) or not CareerCompetitions.ensure_league_seasons(repo, GameDate.year_of(day)):
			return false
	if not _season_openings(repo, day) or not WorldSeasons.close_finished(repo, day, rng) \
			or not CareerCups.progress(repo, day):
		return false
	if GameDate.month_and_day(day).y == 1 and day > 0:
		if not WorldDevelopment.monthly(repo, day, rng) or not _reputation_drift(repo, day, rng) \
				or not WorldFinance.monthly(repo, day) or not CareerHumanContracts.monthly(repo, day, rng) \
				or not CareerSeriesEngine.monthly(repo, day):
			return false
	return WorldMarket.process_contracts(repo, day, rng) and WorldMarket.transfers(repo, day, rng) \
		and WorldMarket.fill_rosters(repo, day, rng) \
		and CareerOffers.daily(repo, day, rng) and CareerLeagueMatches.schedule_due(repo, day)


## Simulated strength bonus from an organisation's form.
static func form_bonus(repo: CareerRepository, org_id: String) -> float:
	return repo.organisation_form(org_id) * FORM_STRENGTH


## Form after a series with [param outcome] in −1..1.
static func next_form(form: int, outcome: float) -> int:
	return clampi(roundi(form * FORM_KEEP + FORM_GAIN * outcome), -100, 100)


## Expected series score of a side with reputation [param own] against [param other] (0..1).
static func expected_score(own: int, other: int) -> float:
	return 1.0 / (1.0 + pow(10.0, (other - own) / REPUTATION_SCALE))


## Reputation change of the home side: positive for an upset win, small for a favourite's win.
static func reputation_change(home: int, away: int, home_won: bool, tier: int) -> float:
	var k: float = REPUTATION_K.get(tier, REPUTATION_K[4])
	return k * ((1.0 if home_won else 0.0) - expected_score(home, away))


## Applies a finished organisation series to both sides' form and reputation (and their AI
## starters' reputation). [param score]: maps won (home, away). [param played]: a human played
## the series, so human starters' reputation moves too (only real games move theirs).
static func apply_series(repo: CareerRepository, home_id: String, away_id: String, score: Vector2i,
		best_of: int, tier: int, day: int, rng: RandomNumberGenerator, played: bool = false) -> bool:
	@warning_ignore("integer_division")
	var target := float(best_of / 2 + 1)
	var outcome := float(score.x - score.y) / target
	var home_rep := repo.organisation_reputation(home_id)
	var away_rep := repo.organisation_reputation(away_id)
	var change := reputation_change(home_rep, away_rep, score.x > score.y, tier)
	if not WorldFinance.award_series(repo, home_id if score.x > score.y else away_id, tier, day):
		return false
	for side: Array in [[home_id, outcome, change, home_rep], [away_id, -outcome, -change, away_rep]]:
		var org_id := str(side[0])
		var delta := float(side[2])
		if not repo.set_organisation_form(org_id, next_form(repo.organisation_form(org_id), float(side[1])), day):
			return false
		if not repo.set_organisation_reputation(org_id, int(side[3]) + stochastic_round(delta, rng), day):
			return false
		for entry: Dictionary in repo.lineup(org_id):
			if bool(entry["is_human"]) and not played:
				continue
			var player_id := str(entry["player_id"])
			var step := stochastic_round(delta * PLAYER_SHARE, rng)
			if step != 0 and not repo.set_reputation(player_id, repo.reputation(player_id) + step, day):
				return false
	return true


## Rounds up or down with probability equal to the fraction, so small changes add up fairly.
static func stochastic_round(value: float, rng: RandomNumberGenerator) -> int:
	var whole := floorf(value)
	return int(whole) + (1 if rng.randf() < value - whole else 0)


static func _new_year(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	var retired: Array[Dictionary] = []
	if not WorldDevelopment.retirements(repo, day, rng, retired):
		return false
	for player: Dictionary in retired:
		var team := "" if str(player["org_name"]).is_empty() else " after playing for %s" % player["org_name"]
		if not repo.add_news(day, NEWS_RETIREMENT, NOTABLE if int(player["reputation"]) >= NOTABLE_REPUTATION else MINOR,
				"%s retires at %d%s." % [player["nickname"], int(player["age"]), team], str(player["id"])):
			return false
	var rookies: Array[String] = []
	if not WorldRookies.generate(repo, maxi(MIN_ROOKIES, retired.size() + EXTRA_ROOKIES), day, rng, rookies):
		return false
	if not repo.add_news(day, NEWS_ROOKIES, MINOR, "%d rookies enter the scene as free agents." % rookies.size()):
		return false
	return repo.add_news(day, NEWS_NEW_YEAR, HEADLINE, "%s begins: %d player%s retired over the break and %d rookies arrived."
		% [GameDate.format_year(day), retired.size(), "" if retired.size() == 1 else "s", rookies.size()])


## News for league seasons that start today; a headline when a human's organisation plays.
static func _season_openings(repo: CareerRepository, day: int) -> bool:
	var starting := repo.seasons_starting(day)
	if starting.is_empty() or day == 0:
		return true
	var human_orgs: Array[String] = []
	for human: CareerRecords.PlayerRecord in repo.human_players():
		var contract := repo.active_contract(human.id)
		if contract != null:
			human_orgs.append(contract.organisation_id)
	for season: Dictionary in starting:
		var org_id := ""
		for candidate: String in human_orgs:
			if repo.is_league_entrant(str(season["competition_id"]), int(season["season_year"]), candidate):
				org_id = candidate
		var importance := HEADLINE if not org_id.is_empty() else (NOTABLE if int(season["tier"]) <= 2 else MINOR)
		var headline := "The %s season starts today%s." % [season["name"], " with your organisation in it" if not org_id.is_empty() else ""]
		if not repo.add_news(day, NEWS_SEASON, importance, headline, "", org_id):
			return false
	return true


## Monthly: organisations far from their tier's typical reputation drift back by a point; free
## agents fade from memory; signed players converge on their organisation's standing.
static func _reputation_drift(repo: CareerRepository, day: int, rng: RandomNumberGenerator) -> bool:
	var org_reputation: Dictionary[String, int] = {}
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		var value := int(entry["reputation"])
		var profile: Array = WorldGenerator.TIER_PROFILE.get(org.tier, WorldGenerator.TIER_PROFILE[4])
		var low := int(profile[1]) - ORG_DRIFT_MARGIN
		var high := int(profile[2]) + ORG_DRIFT_MARGIN
		var drifted := value + (1 if value < low else (-1 if value > high else 0))
		if drifted != value and not repo.set_organisation_reputation(org.id, drifted, day):
			return false
		org_reputation[org.id] = drifted
	for found: Dictionary in repo.ai_players():
		var id := str(found["id"])
		var value := int(found["reputation"])
		var next := value
		if found["organisation_id"] == null:
			if value > 1 and rng.randf() < FREE_AGENT_FADE:
				next -= 1
		elif rng.randf() < PLAYER_CONVERGE:
			next += signi(org_reputation.get(str(found["organisation_id"]), value) - value)
		if next != value and not repo.set_reputation(id, next, day):
			return false
	return true
