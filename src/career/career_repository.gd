class_name CareerRepository
extends RefCounted
## Typed access to one career world stored in SQLite. The rest of the game asks this class for
## players, organisations, contracts and opinions; no SQL exists outside `src/career/`.
##
## Stat layers stay separate: [method abilities] (true, AI only), [method perceived] (what the
## world believes), [method reputation] (standing). Human players never have abilities.

const PlayerRecord := CareerRecords.PlayerRecord
const OrganisationRecord := CareerRecords.OrganisationRecord
const ContractRecord := CareerRecords.ContractRecord
const CompetitionRecord := CareerRecords.CompetitionRecord

var db := CareerDatabase.new()


## Opens (or creates) the world database at [param path] and migrates it to the current
## schema. Returns "" on success or a readable error.
func open(path: String) -> String:
	if not db.open(path):
		return db.last_error
	var error := CareerSchema.migrate(db)
	if not error.is_empty():
		db.close()
		return error
	if meta_value("format", "").is_empty():
		set_meta_value("format", CareerSchema.FORMAT)
	return ""


func close() -> void:
	db.close()


func is_open() -> bool:
	return db.is_open()


## Runs [param work] atomically (see [method CareerDatabase.transaction]).
func transaction(work: Callable) -> bool:
	return db.transaction(work)


# --- World metadata ---------------------------------------------------------------------------

func meta_value(key: String, fallback: String = "") -> String:
	var value: Variant = db.scalar("SELECT value FROM meta WHERE key = ?;", [key])
	return str(value) if value != null else fallback


func set_meta_value(key: String, value: Variant) -> bool:
	return db.execute("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
		[key, str(value)])


func current_day() -> int:
	return int(meta_value("current_day", "0"))


func set_current_day(day: int) -> bool:
	return set_meta_value("current_day", day)


## Regions and nations from [CareerCatalog] (idempotent).
func seed_reference_data() -> bool:
	return transaction(func() -> bool:
		for region_id: String in CareerCatalog.REGIONS:
			db.execute("INSERT OR IGNORE INTO region (id, name) VALUES (?, ?);", [region_id, CareerCatalog.REGIONS[region_id]])
		for nation_id: String in CareerCatalog.NATIONS:
			var entry: Array = CareerCatalog.NATIONS[nation_id]
			db.execute("INSERT OR IGNORE INTO nation (id, name, region_id) VALUES (?, ?, ?);", [nation_id, entry[0], entry[1]])
		return true)


# --- Organisations ----------------------------------------------------------------------------

func insert_organisation(org: OrganisationRecord) -> bool:
	return db.execute("""INSERT INTO organisation (id, name, short_name, region_id, tier, founded_day, colour, active)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?);""",
		[org.id, org.name, org.short_name, org.region_id, org.tier, org.founded_day, org.colour, 1 if org.active else 0])


func get_organisation(id: String) -> OrganisationRecord:
	var found := db.row("SELECT * FROM organisation WHERE id = ?;", [id])
	return OrganisationRecord.from_row(found) if not found.is_empty() else null


## All active organisations, best tier and reputation first. Each entry:
## {organisation: OrganisationRecord, reputation: int, roster_size: int}
func organisations() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for found: Dictionary in db.rows("""SELECT o.*, COALESCE(r.value, 0) AS reputation,
			(SELECT COUNT(*) FROM contract c WHERE c.organisation_id = o.id AND c.status = 'active') AS roster_size
		FROM organisation o LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
		WHERE o.active = 1 ORDER BY o.tier ASC, reputation DESC, o.name ASC;"""):
		list.append({"organisation": OrganisationRecord.from_row(found), "reputation": int(found["reputation"]),
			"roster_size": int(found["roster_size"])})
	return list


func organisation_count() -> int:
	return int(db.scalar("SELECT COUNT(*) FROM organisation WHERE active = 1;", [], 0))


func set_organisation_reputation(org_id: String, value: int, day: int) -> bool:
	return db.execute("""INSERT INTO organisation_reputation (organisation_id, value, updated_day) VALUES (?, ?, ?)
		ON CONFLICT(organisation_id) DO UPDATE SET value = excluded.value, updated_day = excluded.updated_day;""",
		[org_id, clampi(value, 0, 100), day])


func organisation_reputation(org_id: String) -> int:
	return int(db.scalar("SELECT value FROM organisation_reputation WHERE organisation_id = ?;", [org_id], 0))


# --- Players ----------------------------------------------------------------------------------

func insert_player(player: PlayerRecord) -> bool:
	return db.execute("""INSERT INTO player (id, first_name, last_name, nickname, nation_id, birth_day,
			preferred_role, is_human, status, created_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);""",
		[player.id, player.first_name, player.last_name, player.nickname, player.nation_id, player.birth_day,
			String(player.preferred_role), 1 if player.is_human else 0, player.status, player.created_day])


func get_player(id: String) -> PlayerRecord:
	var found := db.row("SELECT * FROM player WHERE id = ?;", [id])
	return PlayerRecord.from_row(found) if not found.is_empty() else null


func player_count(include_humans: bool = true) -> int:
	return int(db.scalar("SELECT COUNT(*) FROM player WHERE status = 'active'%s;" % ("" if include_humans else " AND is_human = 0"), [], 0))


## The human professionals of this career (co-op careers have several), by slot.
func human_players() -> Array[PlayerRecord]:
	var list: Array[PlayerRecord] = []
	for found: Dictionary in db.rows("SELECT p.* FROM player p JOIN human_profile h ON h.player_id = p.id ORDER BY h.slot;"):
		list.append(PlayerRecord.from_row(found))
	return list


func human_profile(player_id: String) -> Dictionary:
	return db.row("SELECT * FROM human_profile WHERE player_id = ?;", [player_id])


## Lightweight player list for browsers. [param filter] keys (all optional):
##   text (name/nickname contains), role, region, organisation_id, free_agents (bool),
##   humans (bool: only humans), sort_ability (perceived ability to sort by; default overall),
##   limit (default 50), offset.
## Each row: id, nickname, first_name, last_name, nation_id, preferred_role, birth_day, is_human,
## organisation_id, organisation_name, contract_role, rating (perceived), reputation.
func search_players(filter: Dictionary = {}) -> Array[Dictionary]:
	var where: PackedStringArray = ["p.status = 'active'"]
	var bindings: Array = []
	var text := str(filter.get("text", "")).strip_edges()
	if not text.is_empty():
		where.append("(p.nickname LIKE ? OR p.first_name || ' ' || p.last_name LIKE ?)")
		bindings.append("%" + text + "%")
		bindings.append("%" + text + "%")
	if filter.has("role"):
		where.append("p.preferred_role = ?")
		bindings.append(str(filter["role"]))
	if filter.has("region"):
		where.append("n.region_id = ?")
		bindings.append(str(filter["region"]))
	if filter.has("organisation_id"):
		where.append("c.organisation_id = ?")
		bindings.append(str(filter["organisation_id"]))
	if bool(filter.get("free_agents", false)):
		where.append("c.id IS NULL")
	if bool(filter.get("humans", false)):
		where.append("p.is_human = 1")
	elif bool(filter.get("ai_only", false)):
		where.append("p.is_human = 0")
	var sort_ability := str(filter.get("sort_ability", ""))
	var rating_sql := "(SELECT AVG(value) FROM player_perceived pp WHERE pp.player_id = p.id)"
	if not sort_ability.is_empty():
		if not CareerCatalog.ABILITIES.has(StringName(sort_ability)):
			return []
		rating_sql = "(SELECT value FROM player_perceived pp WHERE pp.player_id = p.id AND pp.ability = ?)"
		bindings.push_front(sort_ability)
	bindings.append(int(filter.get("limit", 50)))
	bindings.append(int(filter.get("offset", 0)))
	var sql := """SELECT p.id, p.nickname, p.first_name, p.last_name, p.nation_id, p.preferred_role, p.birth_day,
			p.is_human, c.organisation_id, o.name AS organisation_name, c.role AS contract_role,
			ROUND(COALESCE(%s, 0)) AS rating, COALESCE(r.value, 0) AS reputation
		FROM player p
		JOIN nation n ON n.id = p.nation_id
		LEFT JOIN contract c ON c.player_id = p.id AND c.status = 'active'
		LEFT JOIN organisation o ON o.id = c.organisation_id
		LEFT JOIN player_reputation r ON r.player_id = p.id
		WHERE %s
		ORDER BY rating DESC, p.nickname ASC, p.id ASC
		LIMIT ? OFFSET ?;""" % [rating_sql, " AND ".join(where)]
	return db.rows(sql, bindings)


# --- Stat layers ------------------------------------------------------------------------------

## Sets true simulated abilities. Refused for human players (their real skill is the human).
func set_abilities(player_id: String, values: Dictionary) -> bool:
	if _is_human(player_id):
		push_error("CareerRepository: humans have no simulated abilities")
		return false
	return transaction(func() -> bool:
		for ability: Variant in values:
			db.execute("""INSERT INTO player_ability (player_id, ability, value) VALUES (?, ?, ?)
				ON CONFLICT(player_id, ability) DO UPDATE SET value = excluded.value;""",
				[player_id, str(ability), clampi(int(values[ability]), 1, 100)])
		return true)


## True abilities as {StringName: int} (empty for humans).
func abilities(player_id: String) -> Dictionary[StringName, int]:
	return _ability_map("SELECT ability, value FROM player_ability WHERE player_id = ?;", player_id)


func set_perceived(player_id: String, values: Dictionary, confidence: int, day: int) -> bool:
	return transaction(func() -> bool:
		for ability: Variant in values:
			db.execute("""INSERT INTO player_perceived (player_id, ability, value, confidence, updated_day)
				VALUES (?, ?, ?, ?, ?) ON CONFLICT(player_id, ability) DO UPDATE SET value = excluded.value,
				confidence = excluded.confidence, updated_day = excluded.updated_day;""",
				[player_id, str(ability), clampi(int(values[ability]), 1, 100), clampi(confidence, 0, 100), day])
		return true)


## Perceived abilities as {StringName: int}.
func perceived(player_id: String) -> Dictionary[StringName, int]:
	return _ability_map("SELECT ability, value FROM player_perceived WHERE player_id = ?;", player_id)


func perceived_confidence(player_id: String) -> int:
	return int(db.scalar("SELECT ROUND(AVG(confidence)) FROM player_perceived WHERE player_id = ?;", [player_id], 0))


## Mean perceived ability (0 when unknown).
func perceived_rating(player_id: String) -> int:
	return int(db.scalar("SELECT ROUND(AVG(value)) FROM player_perceived WHERE player_id = ?;", [player_id], 0))


func set_reputation(player_id: String, value: int, day: int) -> bool:
	return db.execute("""INSERT INTO player_reputation (player_id, value, updated_day) VALUES (?, ?, ?)
		ON CONFLICT(player_id) DO UPDATE SET value = excluded.value, updated_day = excluded.updated_day;""",
		[player_id, clampi(value, 0, 100), day])


func reputation(player_id: String) -> int:
	return int(db.scalar("SELECT value FROM player_reputation WHERE player_id = ?;", [player_id], 0))


# --- Career development -----------------------------------------------------------------------

func amateur_rating(player_id: String) -> Dictionary:
	return db.row("SELECT rating, last_change, updated_day FROM career_amateur_rating WHERE player_id = ?;", [player_id])


func set_amateur_rating(player_id: String, value: int, change: int, day: int) -> bool:
	return db.execute("""INSERT INTO career_amateur_rating VALUES (?, ?, ?, ?)
		ON CONFLICT(player_id) DO UPDATE SET rating = excluded.rating, last_change = excluded.last_change,
		updated_day = excluded.updated_day;""", [player_id, value, change, day])


func development_today(player_id: String, kind: String) -> Dictionary:
	return db.row("""SELECT day, subject_id, focus, change FROM career_development_activity
		WHERE player_id = ? AND kind = ? AND day = ?;""", [player_id, kind, current_day()])


func last_scout_report(player_id: String, subject_id: String) -> Dictionary:
	return db.row("""SELECT day, change FROM career_development_activity
		WHERE player_id = ? AND subject_id = ? AND kind = 'scouting' ORDER BY day DESC LIMIT 1;""",
		[player_id, subject_id])


func add_development_activity(player_id: String, kind: String, day: int, subject_id: String,
		focus: String, change: int) -> bool:
	return db.execute("INSERT INTO career_development_activity VALUES (?, ?, ?, ?, ?, ?);",
		[player_id, day, kind, subject_id, focus, change])


# --- Traits -----------------------------------------------------------------------------------

## Adds a trait unless it is unknown or conflicts with one the player already has.
func add_trait(player_id: String, trait_id: StringName, strength: int = 1) -> bool:
	if not TraitLibrary.has_trait(trait_id):
		return false
	for existing: StringName in traits(player_id):
		if TraitLibrary.conflicts(existing, trait_id):
			return false
	return db.execute("INSERT OR REPLACE INTO player_trait (player_id, trait_id, strength) VALUES (?, ?, ?);",
		[player_id, String(trait_id), clampi(strength, 1, 3)])


## {trait_id: strength}
func traits(player_id: String) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for found: Dictionary in db.rows("SELECT trait_id, strength FROM player_trait WHERE player_id = ? ORDER BY trait_id;", [player_id]):
		result[StringName(str(found["trait_id"]))] = int(found["strength"])
	return result


# --- Contracts --------------------------------------------------------------------------------

## Signs a contract. Fails (and changes nothing) if the player already has an active contract.
func sign_contract(contract: ContractRecord) -> bool:
	return db.execute("""INSERT INTO contract (id, player_id, organisation_id, role, is_substitute, monthly_salary,
			start_day, end_day, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active');""",
		[contract.id, contract.player_id, contract.organisation_id, String(contract.role),
			1 if contract.is_substitute else 0, contract.monthly_salary, contract.start_day, contract.end_day])


func end_contract(contract_id: String, status: String = "terminated", day: int = -1) -> bool:
	if status != "expired" and status != "terminated":
		return false
	var end_sql := ", end_day = MAX(start_day + 1, ?)" if day >= 0 else ""
	var bindings: Array = [status]
	if day >= 0:
		bindings.append(day)
	bindings.append(contract_id)
	return db.execute("UPDATE contract SET status = ?%s WHERE id = ? AND status = 'active';" % end_sql, bindings)


func active_contract(player_id: String) -> ContractRecord:
	var found := db.row("SELECT * FROM contract WHERE player_id = ? AND status = 'active';", [player_id])
	return ContractRecord.from_row(found) if not found.is_empty() else null


func contract_history(player_id: String) -> Array[ContractRecord]:
	var list: Array[ContractRecord] = []
	for found: Dictionary in db.rows("SELECT * FROM contract WHERE player_id = ? ORDER BY start_day;", [player_id]):
		list.append(ContractRecord.from_row(found))
	return list


## Active roster: starters first, then substitutes. Each entry:
## {player: PlayerRecord, contract: ContractRecord, rating: int (perceived)}
func roster(org_id: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for found: Dictionary in db.rows("""SELECT p.*, c.id AS c_id, c.role AS c_role, c.is_substitute AS c_sub,
			c.monthly_salary AS c_salary, c.start_day AS c_start, c.end_day AS c_end,
			ROUND(COALESCE((SELECT AVG(value) FROM player_perceived pp WHERE pp.player_id = p.id), 0)) AS rating
		FROM contract c JOIN player p ON p.id = c.player_id
		WHERE c.organisation_id = ? AND c.status = 'active'
		ORDER BY c.is_substitute ASC, rating DESC, p.id ASC;""", [org_id]):
		var contract := ContractRecord.new()
		contract.id = str(found["c_id"])
		contract.player_id = str(found["id"])
		contract.organisation_id = org_id
		contract.role = StringName(str(found["c_role"]))
		contract.is_substitute = int(found["c_sub"]) == 1
		contract.monthly_salary = int(found["c_salary"])
		contract.start_day = int(found["c_start"])
		contract.end_day = int(found["c_end"])
		list.append({"player": PlayerRecord.from_row(found), "contract": contract, "rating": int(found["rating"])})
	return list


## Match lineup for an organisation: the five starters as plain data for a [MatchSetup]
## ({player_id, name, role, is_human, abilities}). Abilities are the true simulated values and are
## only included for AI players.
func lineup(org_id: String, size: int = 5) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for entry: Dictionary in roster(org_id):
		if list.size() >= size:
			break
		var player := entry["player"] as PlayerRecord
		var contract := entry["contract"] as ContractRecord
		if contract.is_substitute:
			continue
		list.append(match_player(player.id, player.nickname, contract.role, player.is_human))
	return list


## Snapshot only the abilities the runtime may use. Keep human and hidden potential values out.
func match_player(id: String, nickname: String, role: StringName, is_human: bool) -> Dictionary:
	var ability_values: Dictionary = {}
	if not is_human:
		var values := abilities(id)
		for key: StringName in values:
			if key != CareerCatalog.POTENTIAL:
				ability_values[String(key)] = values[key]
	return {"player_id": id, "name": nickname, "role": String(role),
		"is_human": is_human, "abilities": ability_values}


# --- Career fixtures --------------------------------------------------------------------------

func pending_fixture(player_id: String) -> CareerFixture:
	return CareerFixture.from_row(db.row("""SELECT * FROM career_fixture
		WHERE player_id = ? AND submission_id IS NULL;""", [player_id]))


func fixture_by_id(id: String) -> CareerFixture:
	return CareerFixture.from_row(db.row("SELECT * FROM career_fixture WHERE id = ?;", [id]))


func fixture_count(player_id: String) -> int:
	return int(db.scalar("SELECT COUNT(*) FROM career_fixture WHERE player_id = ?;", [player_id], 0))


func fixtures(player_id: String, limit: int = 30) -> Array[CareerFixture]:
	var list: Array[CareerFixture] = []
	for row: Dictionary in db.rows("""SELECT * FROM career_fixture WHERE player_id = ?
			ORDER BY scheduled_day DESC, id DESC LIMIT ?;""", [player_id, limit]):
		var fixture := CareerFixture.from_row(row)
		if fixture != null:
			list.append(fixture)
	return list


func insert_fixture(fixture: CareerFixture) -> bool:
	return db.execute("""INSERT INTO career_fixture(id, player_id, scheduled_day, setup_json)
		VALUES (?, ?, ?, ?);""", [fixture.setup.fixture_id, fixture.player_id, fixture.scheduled_day,
		JSON.stringify(fixture.setup.to_dict())])


func store_fixture_result(result: MatchResult) -> bool:
	return db.execute("""UPDATE career_fixture SET submission_id = ?, result_json = ?
		WHERE id = ? AND submission_id IS NULL;""",
		[result.submission_id, JSON.stringify(result.to_dict()), result.fixture_id])


# --- Recorded match statistics and calculated ratings ------------------------------------------

## Part of the same transaction as the score and calendar advance.
func store_fixture_statistics(fixture: CareerFixture, result: MatchResult,
		totals: Dictionary[String, Dictionary]) -> bool:
	if not db.execute("INSERT INTO career_match_event VALUES (?, ?, ?);",
			[result.fixture_id, MatchStatistics.EVENT_VERSION, JSON.stringify(result.events)]):
		return false
	for lineup: Array[Dictionary] in [fixture.setup.home_lineup, fixture.setup.away_lineup]:
		for player: Dictionary in lineup:
			var player_id := str(player["player_id"])
			var counts := totals[player_id]
			var keys := [result.fixture_id, player_id]
			if not db.execute("INSERT INTO career_match_stat VALUES (?, ?, ?);", keys + [JSON.stringify(counts)]):
				return false
			if not db.execute("INSERT INTO career_match_rating VALUES (?, ?, ?, ?);",
					keys + [MatchStatistics.RATING_VERSION, MatchStatistics.rating(counts)]):
				return false
	return true


func performance_totals(player_id: String) -> Dictionary:
	var stats_sql: PackedStringArray = ["COUNT(*) AS matches"]
	for counter: String in MatchStatistics.COUNTERS:
		stats_sql.append("COALESCE(SUM(json_extract(counts_json, '$.%s')), 0) AS %s" % [counter, counter])
	return db.row("SELECT %s FROM career_match_stat WHERE player_id = ?;" % ", ".join(stats_sql), [player_id])


## Recent recorded fixtures with per-match counts and their original rating version.
func recent_performance(player_id: String, limit: int = 20) -> Array[Dictionary]:
	var history: Array[Dictionary] = []
	for row: Dictionary in db.rows("""SELECT f.*, s.counts_json, r.rating, r.formula_version
			FROM career_match_stat s
			JOIN career_fixture f ON f.id = s.fixture_id
			JOIN career_match_rating r ON r.fixture_id = s.fixture_id AND r.player_id = s.player_id
			WHERE s.player_id = ? ORDER BY f.scheduled_day DESC, f.id DESC LIMIT ?;""",
			[player_id, limit]):
		var fixture := CareerFixture.from_row(row)
		var counts: Variant = JSON.parse_string(str(row["counts_json"]))
		if fixture != null and fixture.result != null and counts is Dictionary:
			history.append({"fixture": fixture, "counts": counts, "rating": float(row["rating"]),
				"rating_version": int(row["formula_version"])})
	return history


# --- Competition definitions and published league seasons -------------------------------------

func insert_competition(competition: CompetitionRecord) -> bool:
	return db.execute("""INSERT INTO competition (id, name, short_name, kind, region_id, tier, team_count, start_month)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?);""",
		[competition.id, competition.name, competition.short_name, competition.kind,
			null if competition.region_id.is_empty() else competition.region_id, competition.tier,
			competition.team_count, competition.start_month])


func get_competition(id: String) -> CompetitionRecord:
	var found := db.row("SELECT * FROM competition WHERE id = ?;", [id])
	return CompetitionRecord.from_row(found) if not found.is_empty() else null


## Active competitions, top tier first, international before regional.
func competitions() -> Array[CompetitionRecord]:
	var list: Array[CompetitionRecord] = []
	for found: Dictionary in db.rows("""SELECT * FROM competition WHERE active = 1
			ORDER BY tier, region_id IS NOT NULL, region_id, name;"""):
		list.append(CompetitionRecord.from_row(found))
	return list



## Organisations in the defined region and tier or higher, in invitation order.
func eligible_organisations(competition: CompetitionRecord, start_day: int) -> Array[String]:
	var ids: Array[String] = []
	for found: Dictionary in db.rows("""SELECT o.id FROM organisation o
			LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
		WHERE o.active = 1 AND o.founded_day <= ? AND o.tier <= ? AND (? = '' OR o.region_id = ?)
		ORDER BY o.tier ASC, COALESCE(r.value, 0) DESC, o.id ASC;""",
		[start_day, competition.tier, competition.region_id, competition.region_id]):
		ids.append(str(found["id"]))
	return ids


func league_season(competition_id: String, year: int) -> Dictionary:
	return db.row("SELECT * FROM league_season WHERE competition_id = ? AND season_year = ?;",
		[competition_id, year])


func league_years(competition_id: String) -> Array[int]:
	var years: Array[int] = []
	for found: Dictionary in db.rows(
			"SELECT season_year FROM league_season WHERE competition_id = ? ORDER BY season_year DESC;",
			[competition_id]):
		years.append(int(found["season_year"]))
	return years


## Called inside the season publication transaction.
func insert_league_season(competition_id: String, year: int, start_day: int, best_of: int,
		entrants: Array[String], fixtures: Array[Dictionary]) -> bool:
	if not db.execute("INSERT INTO league_season VALUES (?, ?, ?, ?);",
			[competition_id, year, start_day, best_of]):
		return false
	for org_id: String in entrants:
		if not db.execute("INSERT INTO league_entrant VALUES (?, ?, ?);", [competition_id, year, org_id]):
			return false
	for fixture: Dictionary in fixtures:
		if not db.execute("""INSERT INTO league_fixture
				(competition_id, season_year, round_number, scheduled_day, home_id, away_id)
				VALUES (?, ?, ?, ?, ?, ?);""", [
				competition_id, year, fixture["round_number"], fixture["scheduled_day"],
				fixture["home_id"], fixture["away_id"]]):
			return false
	return true


func league_entrants(competition_id: String, year: int) -> Array[Dictionary]:
	return db.rows("""SELECT o.id AS organisation_id, o.name, o.short_name
		FROM league_entrant e JOIN organisation o ON o.id = e.organisation_id
		WHERE e.competition_id = ? AND e.season_year = ? ORDER BY o.name, o.id;""",
		[competition_id, year])


func league_fixtures(competition_id: String, year: int) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, h.short_name AS home_name, a.short_name AS away_name
		FROM league_fixture f JOIN organisation h ON h.id = f.home_id
		JOIN organisation a ON a.id = f.away_id
		WHERE f.competition_id = ? AND f.season_year = ? ORDER BY f.round_number, f.id;""",
		[competition_id, year])


func league_fixture(fixture_id: int) -> Dictionary:
	return db.row("""SELECT f.*, s.best_of FROM league_fixture f JOIN league_season s
		ON s.competition_id = f.competition_id AND s.season_year = f.season_year WHERE f.id = ?;""",
		[fixture_id])


## Unscored series scheduled before [param before_day], oldest first, with their best-of and
## competition tier.
func unresolved_league_fixtures(before_day: int) -> Array[Dictionary]:
	return db.rows("""SELECT f.id, f.home_id, f.away_id, f.scheduled_day, s.best_of, c.tier FROM league_fixture f
		JOIN league_season s ON s.competition_id = f.competition_id AND s.season_year = f.season_year
		JOIN competition c ON c.id = f.competition_id
		WHERE f.home_maps IS NULL AND f.scheduled_day < ? ORDER BY f.scheduled_day, f.id;""", [before_day])


## Series on days [param from_day]..[param to_day], with competition and team names.
func league_fixtures_between(from_day: int, to_day: int, limit: int = 40) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, c.name AS competition_name, h.short_name AS home_name, a.short_name AS away_name
		FROM league_fixture f JOIN competition c ON c.id = f.competition_id
		JOIN organisation h ON h.id = f.home_id JOIN organisation a ON a.id = f.away_id
		WHERE f.scheduled_day BETWEEN ? AND ? ORDER BY f.scheduled_day, c.tier, f.id LIMIT ?;""",
		[from_day, to_day, limit])


## True when a human professional has an active contract with the organisation.
func organisation_has_human(org_id: String) -> bool:
	return int(db.scalar("""SELECT COUNT(*) FROM contract c JOIN player p ON p.id = c.player_id
		WHERE c.organisation_id = ? AND c.status = 'active' AND p.is_human = 1;""", [org_id], 0)) > 0


func store_league_score(fixture_id: int, home_maps: int, away_maps: int) -> bool:
	return db.execute("UPDATE league_fixture SET home_maps = ?, away_maps = ? WHERE id = ?;",
		[home_maps, away_maps, fixture_id])


# --- Living world (form, development, market, news) --------------------------------------------

## Recent-results momentum of an organisation, -100..100 (0 = neutral or unknown).
func organisation_form(org_id: String) -> int:
	return int(db.scalar("SELECT value FROM organisation_form WHERE organisation_id = ?;", [org_id], 0))


func set_organisation_form(org_id: String, value: int, day: int) -> bool:
	return db.execute("""INSERT INTO organisation_form (organisation_id, value, updated_day) VALUES (?, ?, ?)
		ON CONFLICT(organisation_id) DO UPDATE SET value = excluded.value, updated_day = excluded.updated_day;""",
		[org_id, clampi(value, -100, 100), day])


## Adds one story to the world news log. [param importance]: 1 minor, 2 notable, 3 headline.
func add_news(day: int, kind: String, importance: int, headline: String, player_id: String = "",
		organisation_id: String = "") -> bool:
	return db.execute("""INSERT INTO world_news (day, kind, importance, headline, player_id, organisation_id)
		VALUES (?, ?, ?, ?, ?, ?);""", [day, kind, clampi(importance, 1, 3), headline,
		null if player_id.is_empty() else player_id, null if organisation_id.is_empty() else organisation_id])


## Latest stories first. Each row: id, day, kind, importance, headline, player_id, organisation_id.
func news(limit: int = 30, min_importance: int = 1, offset: int = 0) -> Array[Dictionary]:
	return db.rows("""SELECT * FROM world_news WHERE importance >= ?
		ORDER BY day DESC, id DESC LIMIT ? OFFSET ?;""", [min_importance, limit, offset])


## Stories dated [param day] at or above [param min_importance], oldest first.
func news_on(day: int, min_importance: int = 1) -> Array[Dictionary]:
	return db.rows("SELECT * FROM world_news WHERE day = ? AND importance >= ? ORDER BY id;", [day, min_importance])


func player_news(player_id: String, limit: int = 10) -> Array[Dictionary]:
	return db.rows("SELECT * FROM world_news WHERE player_id = ? ORDER BY day DESC, id DESC LIMIT ?;",
		[player_id, limit])


## Active AI players with simulated abilities: id, nickname, birth_day, preferred_role,
## organisation_id (or null), tier (of their organisation, or null), reputation.
func ai_players() -> Array[Dictionary]:
	return db.rows("""SELECT p.id, p.nickname, p.birth_day, p.preferred_role, c.organisation_id, o.tier,
			COALESCE(r.value, 0) AS reputation
		FROM player p
		LEFT JOIN contract c ON c.player_id = p.id AND c.status = 'active'
		LEFT JOIN organisation o ON o.id = c.organisation_id
		LEFT JOIN player_reputation r ON r.player_id = p.id
		WHERE p.status = 'active' AND p.is_human = 0 ORDER BY p.id;""")


## Every AI player's true abilities in one query: {player_id: {ability: value}} (potential included).
func all_abilities() -> Dictionary[String, Dictionary]:
	return _grouped_abilities("""SELECT a.player_id, a.ability, a.value FROM player_ability a
		JOIN player p ON p.id = a.player_id WHERE p.status = 'active';""")


## Every active player's perceived abilities: {player_id: {ability: value}}.
func all_perceived() -> Dictionary[String, Dictionary]:
	return _grouped_abilities("""SELECT pp.player_id, pp.ability, pp.value FROM player_perceived pp
		JOIN player p ON p.id = pp.player_id WHERE p.status = 'active';""")


func record_ability_history(player_id: String, day: int, overall: int) -> bool:
	return db.execute("INSERT OR REPLACE INTO player_ability_history VALUES (?, ?, ?);",
		[player_id, day, clampi(overall, 1, 100)])


## {day, overall} rows, oldest first.
func ability_history(player_id: String) -> Array[Dictionary]:
	return db.rows("SELECT day, overall FROM player_ability_history WHERE player_id = ? ORDER BY day;", [player_id])


## Active contracts ending on or before [param day], with what the market needs to decide.
## Rows: contract columns + is_human, nickname, birth_day, tier, org_name.
func contracts_ending(day: int) -> Array[Dictionary]:
	return db.rows("""SELECT c.*, p.is_human, p.nickname, p.birth_day, o.tier, o.name AS org_name
		FROM contract c JOIN player p ON p.id = c.player_id JOIN organisation o ON o.id = c.organisation_id
		WHERE c.status = 'active' AND c.end_day <= ? ORDER BY c.end_day, c.id;""", [day])


## Active organisations with fewer than [param size] starters: id, name, tier, region_id,
## starters, substitutes, has_human. Best tier first so the strongest teams pick first.
func organisations_short_of_starters(size: int = 5) -> Array[Dictionary]:
	return db.rows("""SELECT o.id, o.name, o.tier, o.region_id,
			SUM(CASE WHEN c.id IS NOT NULL AND c.is_substitute = 0 THEN 1 ELSE 0 END) AS starters,
			SUM(CASE WHEN c.id IS NOT NULL AND c.is_substitute = 1 THEN 1 ELSE 0 END) AS substitutes,
			MAX(CASE WHEN p.is_human = 1 THEN 1 ELSE 0 END) AS has_human
		FROM organisation o
		LEFT JOIN contract c ON c.organisation_id = o.id AND c.status = 'active'
		LEFT JOIN player p ON p.id = c.player_id
		WHERE o.active = 1 GROUP BY o.id HAVING starters < ?
		ORDER BY o.tier, o.id;""", [size])


## Unsigned active AI players for the market: id, nickname, preferred_role, region_id, birth_day,
## rating (perceived), reputation. Best perceived first.
func free_agent_pool() -> Array[Dictionary]:
	return db.rows("""SELECT p.id, p.nickname, p.preferred_role, n.region_id, p.birth_day,
			ROUND(COALESCE((SELECT AVG(value) FROM player_perceived pp WHERE pp.player_id = p.id), 0)) AS rating,
			COALESCE(r.value, 0) AS reputation
		FROM player p JOIN nation n ON n.id = p.nation_id
		LEFT JOIN contract c ON c.player_id = p.id AND c.status = 'active'
		LEFT JOIN player_reputation r ON r.player_id = p.id
		WHERE p.status = 'active' AND p.is_human = 0 AND c.id IS NULL
		ORDER BY rating DESC, p.id;""")


func set_contract_substitute(contract_id: String, is_substitute: bool) -> bool:
	return db.execute("UPDATE contract SET is_substitute = ? WHERE id = ? AND status = 'active';",
		[1 if is_substitute else 0, contract_id])


## Retires an AI player: ends any active contract and marks them retired. Humans never retire here.
func retire_player(player_id: String, day: int) -> bool:
	if _is_human(player_id):
		return false
	var contract := active_contract(player_id)
	if contract != null and not end_contract(contract.id, "terminated", day):
		return false
	return db.execute("UPDATE player SET status = 'retired' WHERE id = ?;", [player_id])


func nickname_taken(nickname: String) -> bool:
	return int(db.scalar("SELECT COUNT(*) FROM player WHERE nickname = ? COLLATE NOCASE;", [nickname], 0)) > 0


## League seasons whose first day is [param day]: competition_id, name, tier, season_year.
func seasons_starting(day: int) -> Array[Dictionary]:
	return db.rows("""SELECT s.competition_id, c.name, c.tier, s.season_year FROM league_season s
		JOIN competition c ON c.id = s.competition_id WHERE s.start_day = ? ORDER BY c.tier, c.name;""", [day])


func is_league_entrant(competition_id: String, year: int, org_id: String) -> bool:
	return int(db.scalar("""SELECT COUNT(*) FROM league_entrant
		WHERE competition_id = ? AND season_year = ? AND organisation_id = ?;""", [competition_id, year, org_id], 0)) > 0


# --- Offers to humans and playable league series ---------------------------------------------

func insert_offer(offer: Dictionary) -> bool:
	return db.execute("""INSERT INTO career_offer (id, player_id, organisation_id, kind, role, monthly_salary, years,
			created_day, expires_day, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending');""",
		[offer["id"], offer["player_id"], offer["organisation_id"], offer["kind"], str(offer["role"]),
			offer["monthly_salary"], offer["years"], offer["created_day"], offer["expires_day"]])


## One offer with its organisation's name and tier, or {}.
func offer(offer_id: String) -> Dictionary:
	return db.row("""SELECT f.*, o.name AS org_name, o.tier FROM career_offer f
		JOIN organisation o ON o.id = f.organisation_id WHERE f.id = ?;""", [offer_id])


## The trial offer a career fixture was scheduled for, or {}.
func offer_for_fixture(fixture_id: String) -> Dictionary:
	return db.row("""SELECT f.*, o.name AS org_name, o.tier FROM career_offer f
		JOIN organisation o ON o.id = f.organisation_id WHERE f.fixture_id = ?;""", [fixture_id])


## A player's offers, newest first; [param open_only] keeps pending ones and booked trials.
func offers(player_id: String, open_only: bool = false, limit: int = 20) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, o.name AS org_name, o.tier FROM career_offer f
		JOIN organisation o ON o.id = f.organisation_id
		WHERE f.player_id = ? %s ORDER BY f.created_day DESC, f.id DESC LIMIT ?;""" % (
		"AND (f.status = 'pending' OR (f.status = 'accepted' AND f.kind = 'trial'))" if open_only else ""),
		[player_id, limit])


func set_offer_status(offer_id: String, status: String, day: int, fixture_id: String = "") -> bool:
	return db.execute("UPDATE career_offer SET status = ?, resolved_day = ?, fixture_id = COALESCE(?, fixture_id) WHERE id = ?;",
		[status, day, null if fixture_id.is_empty() else fixture_id, offer_id])


## Pending offers that ran out before [param day].
func lapsed_offers(day: int) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, o.name AS org_name FROM career_offer f JOIN organisation o ON o.id = f.organisation_id
		WHERE f.status = 'pending' AND f.expires_day < ?;""", [day])


## Organisations that approached [param player_id] on or after [param since_day] (or still are).
func recent_suitors(player_id: String, since_day: int) -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for found: Dictionary in db.rows("""SELECT DISTINCT organisation_id FROM career_offer WHERE player_id = ?
			AND (status = 'pending' OR (status = 'accepted' AND kind = 'trial')
				OR COALESCE(resolved_day, created_day) >= ?);""", [player_id, since_day]):
		result[str(found["organisation_id"])] = true
	return result


## Recent recorded F2F ratings of a player (newest first).
func recent_ratings(player_id: String, limit: int = 5) -> Array[float]:
	var list: Array[float] = []
	for found: Dictionary in db.rows("""SELECT r.rating FROM career_match_rating r JOIN career_fixture f ON f.id = r.fixture_id
			WHERE r.player_id = ? ORDER BY f.scheduled_day DESC, f.id DESC LIMIT ?;""", [player_id, limit]):
		list.append(float(found["rating"]))
	return list


func insert_series_map(league_fixture_id: int, map_number: int, career_fixture_id: String, human_home: bool) -> bool:
	return db.execute("INSERT INTO league_series_map VALUES (?, ?, ?, ?);",
		[league_fixture_id, map_number, career_fixture_id, 1 if human_home else 0])


## The series map a career fixture plays, or {} (league_fixture_id, map_number, human_home).
func series_map_for_fixture(career_fixture_id: String) -> Dictionary:
	return db.row("SELECT * FROM league_series_map WHERE career_fixture_id = ?;", [career_fixture_id])


## Maps of a series booked so far, in order: map_number, human_home, career_fixture_id.
func series_maps(league_fixture_id: int) -> Array[Dictionary]:
	return db.rows("""SELECT map_number, human_home, career_fixture_id FROM league_series_map
		WHERE league_fixture_id = ? ORDER BY map_number;""", [league_fixture_id])


## Unscored series of [param org_id] scheduled on or before [param day], oldest first, with the
## competition's name and tier.
func due_series_for(org_id: String, day: int) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, s.best_of, c.name AS competition_name, c.tier,
			h.name AS home_name, a.name AS away_name FROM league_fixture f
		JOIN league_season s ON s.competition_id = f.competition_id AND s.season_year = f.season_year
		JOIN competition c ON c.id = f.competition_id
		JOIN organisation h ON h.id = f.home_id JOIN organisation a ON a.id = f.away_id
		WHERE f.home_maps IS NULL AND f.scheduled_day <= ? AND (f.home_id = ? OR f.away_id = ?)
		ORDER BY f.scheduled_day, f.id;""", [day, org_id, org_id])


# --- Helpers ----------------------------------------------------------------------------------

func _is_human(player_id: String) -> bool:
	return int(db.scalar("SELECT is_human FROM player WHERE id = ?;", [player_id], 0)) == 1


func _ability_map(sql: String, player_id: String) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for found: Dictionary in db.rows(sql, [player_id]):
		result[StringName(str(found["ability"]))] = int(found["value"])
	return result


func _grouped_abilities(sql: String) -> Dictionary[String, Dictionary]:
	var result: Dictionary[String, Dictionary] = {}
	for found: Dictionary in db.rows(sql):
		var id := str(found["player_id"])
		if not result.has(id):
			result[id] = {}
		result[id][StringName(str(found["ability"]))] = int(found["value"])
	return result
