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


func begin_transaction() -> bool:
	return db.begin_transaction()


func end_transaction(ok: bool) -> bool:
	return db.end_transaction(ok)


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
	return db.execute("""INSERT INTO career_fixture(id, player_id, scheduled_day, kick_off, setup_json)
		VALUES (?, ?, ?, ?, ?);""", [fixture.setup.fixture_id, fixture.player_id, fixture.scheduled_day, fixture.kick_off,
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
				(competition_id, season_year, round_number, scheduled_day, kick_off, home_id, away_id)
				VALUES (?, ?, ?, ?, ?, ?, ?);""", [
				competition_id, year, fixture["round_number"], fixture["scheduled_day"],
				int(fixture.get("kick_off", MatchTimes.DEFAULT_KICK_OFF)), fixture["home_id"], fixture["away_id"]]):
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
## Unplayed series dated before [param before_day], in kick-off order, with names for the calendar.
func unresolved_league_fixtures(before_day: int) -> Array[Dictionary]:
	return db.rows("""SELECT f.id, f.home_id, f.away_id, f.scheduled_day, f.kick_off, s.best_of, c.tier,
		c.name AS competition_name, h.name AS home_name, a.name AS away_name FROM league_fixture f
		JOIN league_season s ON s.competition_id = f.competition_id AND s.season_year = f.season_year
		JOIN competition c ON c.id = f.competition_id
		JOIN organisation h ON h.id = f.home_id JOIN organisation a ON a.id = f.away_id
		WHERE f.home_maps IS NULL AND f.scheduled_day < ? ORDER BY f.scheduled_day, f.kick_off, f.id;""", [before_day])


## Series on days [param from_day]..[param to_day], with competition and team names.
func league_fixtures_between(from_day: int, to_day: int, limit: int = 40) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, c.name AS competition_name, h.short_name AS home_name, a.short_name AS away_name
		FROM league_fixture f JOIN competition c ON c.id = f.competition_id
		JOIN organisation h ON h.id = f.home_id JOIN organisation a ON a.id = f.away_id
		WHERE f.scheduled_day BETWEEN ? AND ? ORDER BY f.scheduled_day, f.kick_off, c.tier, f.id LIMIT ?;""",
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


## AI players under contract who could move: contract and organisation details, perceived
## rating, age inputs. Players who signed on or after [param signed_before] are left alone.
## Rows: player_id, nickname, preferred_role, birth_day, rating, contract_id, end_day,
## is_substitute, organisation_id, org_name, tier, org_reputation, region_id.
func transfer_pool(signed_before: int) -> Array[Dictionary]:
	return db.rows("""SELECT p.id AS player_id, p.nickname, p.preferred_role, p.birth_day,
			ROUND(COALESCE((SELECT AVG(value) FROM player_perceived pp WHERE pp.player_id = p.id), 0)) AS rating,
			c.id AS contract_id, c.end_day, c.is_substitute, o.id AS organisation_id, o.name AS org_name, o.tier,
			COALESCE(r.value, 0) AS org_reputation, o.region_id
		FROM contract c JOIN player p ON p.id = c.player_id JOIN organisation o ON o.id = c.organisation_id
		LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
		WHERE c.status = 'active' AND p.is_human = 0 AND p.status = 'active' AND c.start_day < ?
		ORDER BY rating DESC, p.id;""", [signed_before])


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
			created_day, expires_day, status, fee) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?);""",
		[offer["id"], offer["player_id"], offer["organisation_id"], offer["kind"], str(offer["role"]),
			offer["monthly_salary"], offer["years"], offer["created_day"], offer["expires_day"], int(offer.get("fee", 0))])


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


# --- Finances ---------------------------------------------------------------------------------

## An organisation's balance (0 when it has no finance record yet).
func organisation_balance(org_id: String) -> int:
	return int(db.scalar("SELECT balance FROM organisation_finance WHERE organisation_id = ?;", [org_id], 0))


func has_finances(org_id: String) -> bool:
	return int(db.scalar("SELECT COUNT(*) FROM organisation_finance WHERE organisation_id = ?;", [org_id], 0)) > 0


## Active organisations without a finance record: id, tier, reputation.
func organisations_without_finances() -> Array[Dictionary]:
	return db.rows("""SELECT o.id, o.tier, COALESCE(r.value, 0) AS reputation FROM organisation o
		LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
		LEFT JOIN organisation_finance f ON f.organisation_id = o.id
		WHERE o.active = 1 AND f.organisation_id IS NULL ORDER BY o.id;""")


## Moves money in (+) or out (−) of an organisation and records it in the ledger.
func add_organisation_money(org_id: String, amount: int, day: int, kind: String, note: String = "") -> bool:
	return db.execute("""INSERT INTO organisation_finance (organisation_id, balance, updated_day) VALUES (?, ?, ?)
			ON CONFLICT(organisation_id) DO UPDATE SET balance = balance + excluded.balance, updated_day = excluded.updated_day;""",
			[org_id, amount, day]) \
		and db.execute("INSERT INTO finance_ledger (day, organisation_id, kind, amount, note) VALUES (?, ?, ?, ?, ?);",
			[day, org_id, kind, amount, note])


func player_balance(player_id: String) -> int:
	return int(db.scalar("SELECT balance FROM player_finance WHERE player_id = ?;", [player_id], 0))


## Pays (+) or charges (−) a player and records it in the ledger.
func add_player_money(player_id: String, amount: int, day: int, kind: String, note: String = "") -> bool:
	return db.execute("""INSERT INTO player_finance (player_id, balance, updated_day) VALUES (?, ?, ?)
			ON CONFLICT(player_id) DO UPDATE SET balance = balance + excluded.balance, updated_day = excluded.updated_day;""",
			[player_id, amount, day]) \
		and db.execute("INSERT INTO finance_ledger (day, player_id, kind, amount, note) VALUES (?, ?, ?, ?, ?);",
			[day, player_id, kind, amount, note])


## Monthly wage bill of every organisation with players: {org_id: total}.
func wage_bills() -> Dictionary[String, int]:
	var bills: Dictionary[String, int] = {}
	for found: Dictionary in db.rows("""SELECT organisation_id, SUM(monthly_salary) AS total FROM contract
			WHERE status = 'active' GROUP BY organisation_id;"""):
		bills[str(found["organisation_id"])] = int(found["total"])
	return bills


func wage_bill(org_id: String) -> int:
	return int(db.scalar("SELECT COALESCE(SUM(monthly_salary), 0) FROM contract WHERE organisation_id = ? AND status = 'active';",
		[org_id], 0))


## Active human players under contract: player_id, monthly_salary, organisation_id.
func paid_humans() -> Array[Dictionary]:
	return db.rows("""SELECT c.player_id, c.monthly_salary, c.organisation_id FROM contract c
		JOIN player p ON p.id = c.player_id WHERE c.status = 'active' AND p.is_human = 1;""")


## Latest ledger entries of an organisation (or, with [param player], of a player).
func ledger(owner_id: String, player: bool = false, limit: int = 12) -> Array[Dictionary]:
	return db.rows("SELECT * FROM finance_ledger WHERE %s = ? ORDER BY day DESC, id DESC LIMIT ?;" % (
		"player_id" if player else "organisation_id"), [owner_id, limit])


## Contract talks: a new salary for a pending contract offer, marking it negotiated.
func set_offer_salary(offer_id: String, salary: int) -> bool:
	return db.execute("UPDATE career_offer SET monthly_salary = ?, negotiated = 1 WHERE id = ? AND status = 'pending';",
		[maxi(salary, 0), offer_id])


# --- Season records, honours and human spending ------------------------------------------------

## League seasons whose every series is scored and that have no final record yet:
## competition_id, season_year, name, tier.
func seasons_to_close() -> Array[Dictionary]:
	return db.rows("""SELECT s.competition_id, s.season_year, c.name, c.tier, c.region_id FROM league_season s
		JOIN competition c ON c.id = s.competition_id
		WHERE c.kind = 'league' AND EXISTS (SELECT 1 FROM league_fixture f WHERE f.competition_id = s.competition_id AND f.season_year = s.season_year)
		AND NOT EXISTS (SELECT 1 FROM league_fixture f WHERE f.competition_id = s.competition_id
			AND f.season_year = s.season_year AND f.home_maps IS NULL)
		AND NOT EXISTS (SELECT 1 FROM league_record r WHERE r.competition_id = s.competition_id
			AND r.season_year = s.season_year)
		ORDER BY c.tier, s.competition_id, s.season_year;""")


func insert_league_record(competition_id: String, year: int, position: int, row: Dictionary, prize: int, day: int) -> bool:
	return db.execute("INSERT INTO league_record VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[competition_id, year, position, row["organisation_id"], row["won"], row["lost"], row["map_diff"], prize, day])


## A finished season's final table (position order) with names, or [] when it is still running.
func league_record(competition_id: String, year: int) -> Array[Dictionary]:
	return db.rows("""SELECT r.*, o.name FROM league_record r JOIN organisation o ON o.id = r.organisation_id
		WHERE r.competition_id = ? AND r.season_year = ? ORDER BY r.position;""", [competition_id, year])


## Champions and runners-up of a competition, newest season first.
func league_podiums(competition_id: String) -> Array[Dictionary]:
	return db.rows("""SELECT r.season_year, r.position, r.prize, o.name FROM league_record r
		JOIN organisation o ON o.id = r.organisation_id
		WHERE r.competition_id = ? AND r.position <= 3 ORDER BY r.season_year DESC, r.position;""", [competition_id])


func add_honour(player_id: String, competition_id: String, year: int, position: int, org_id: String) -> bool:
	return db.execute("INSERT OR IGNORE INTO player_honour VALUES (?, ?, ?, ?, ?);",
		[player_id, competition_id, year, position, org_id])


## A player's honours, newest first, with competition and organisation names.
func honours(player_id: String) -> Array[Dictionary]:
	return db.rows("""SELECT h.*, c.name AS competition_name, o.name AS org_name FROM player_honour h
		JOIN competition c ON c.id = h.competition_id JOIN organisation o ON o.id = h.organisation_id
		WHERE h.player_id = ? ORDER BY h.season_year DESC, h.position;""", [player_id])


func services(player_id: String) -> Array[String]:
	var list: Array[String] = []
	for found: Dictionary in db.rows("SELECT service_id FROM human_service WHERE player_id = ? ORDER BY service_id;", [player_id]):
		list.append(str(found["service_id"]))
	return list


## Every active service of every human: player_id, service_id.
func all_services() -> Array[Dictionary]:
	return db.rows("SELECT player_id, service_id FROM human_service ORDER BY player_id, service_id;")


func add_service(player_id: String, service_id: String, day: int) -> bool:
	return db.execute("INSERT INTO human_service VALUES (?, ?, ?);", [player_id, service_id, day])


func remove_service(player_id: String, service_id: String) -> bool:
	return db.execute("DELETE FROM human_service WHERE player_id = ? AND service_id = ?;", [player_id, service_id])


func add_purchase(player_id: String, item_id: String, day: int) -> bool:
	return db.execute("INSERT INTO human_purchase (player_id, item_id, day) VALUES (?, ?, ?);", [player_id, item_id, day])


## Day of the player's latest purchase of [param item_id], or -1.
func last_purchase(player_id: String, item_id: String) -> int:
	return int(db.scalar("SELECT COALESCE(MAX(day), -1) FROM human_purchase WHERE player_id = ? AND item_id = ?;",
		[player_id, item_id], -1))


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


# --- Cups, promotion and relegation ----------------------------------------------------------

## Organisations a cup invites: the competition's region (or everyone for an international cup),
## from one tier above the cup's tier downwards, best tier and reputation first.
func cup_candidates(competition: CompetitionRecord, start_day: int) -> Array[String]:
	var ids: Array[String] = []
	for found: Dictionary in db.rows("""SELECT o.id FROM organisation o
			LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
		WHERE o.active = 1 AND o.founded_day <= ? AND o.tier >= ? AND (? = '' OR o.region_id = ?)
		ORDER BY o.tier ASC, COALESCE(r.value, 0) DESC, o.id ASC LIMIT ?;""",
		[start_day, maxi(1, competition.tier - 1), competition.region_id, competition.region_id, competition.team_count]):
		ids.append(str(found["id"]))
	return ids


## Organisations one tier below a league that may fill its empty places (best reputation first).
func league_fillers(competition: CompetitionRecord, start_day: int, limit: int) -> Array[String]:
	var ids: Array[String] = []
	if limit <= 0 or competition.tier >= 4:
		return ids
	for found: Dictionary in db.rows("""SELECT o.id FROM organisation o
			LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
		WHERE o.active = 1 AND o.founded_day <= ? AND o.tier = ? AND (? = '' OR o.region_id = ?)
		ORDER BY COALESCE(r.value, 0) DESC, o.id ASC LIMIT ?;""",
		[start_day, competition.tier + 1, competition.region_id, competition.region_id, limit]):
		ids.append(str(found["id"]))
	return ids


func insert_cup_seeds(competition_id: String, year: int, seeded: Array[String]) -> bool:
	for index: int in seeded.size():
		if not db.execute("INSERT INTO cup_seed VALUES (?, ?, ?, ?);", [competition_id, year, seeded[index], index + 1]):
			return false
	return true


## A cup edition's organisations in seed order.
func cup_seeds(competition_id: String, year: int) -> Array[String]:
	var ids: Array[String] = []
	for found: Dictionary in db.rows("SELECT organisation_id FROM cup_seed WHERE competition_id = ? AND season_year = ? ORDER BY seed;",
			[competition_id, year]):
		ids.append(str(found["organisation_id"]))
	return ids


## Cup editions that have not been completed yet.
func open_cup_seasons() -> Array[Dictionary]:
	return db.rows("""SELECT s.competition_id, s.season_year, s.start_day, s.best_of, c.name, c.tier, c.region_id
		FROM league_season s JOIN competition c ON c.id = s.competition_id
		WHERE c.kind = 'cup' AND NOT EXISTS (SELECT 1 FROM league_record r WHERE r.competition_id = s.competition_id
			AND r.season_year = s.season_year)
		ORDER BY s.start_day, s.competition_id;""")


func insert_league_fixture(competition_id: String, year: int, round_number: int, day: int, home_id: String, away_id: String,
		kick_off: int = MatchTimes.DEFAULT_KICK_OFF) -> bool:
	return db.execute("""INSERT INTO league_fixture (competition_id, season_year, round_number, scheduled_day, kick_off, home_id, away_id)
		VALUES (?, ?, ?, ?, ?, ?, ?);""", [competition_id, year, round_number, day, kick_off, home_id, away_id])


## Moves an organisation to another tier and records why.
func set_organisation_tier(org_id: String, tier: int, day: int, reason: String) -> bool:
	var org := get_organisation(org_id)
	if org == null or tier < 1 or tier > 4:
		return false
	if org.tier == tier:
		return true
	return db.execute("UPDATE organisation SET tier = ? WHERE id = ?;", [tier, org_id]) \
		and db.execute("INSERT INTO organisation_move (organisation_id, day, from_tier, to_tier, reason) VALUES (?, ?, ?, ?, ?);",
			[org_id, day, org.tier, tier, reason])


## An organisation's tier moves, newest first.
func organisation_moves(org_id: String) -> Array[Dictionary]:
	return db.rows("SELECT * FROM organisation_move WHERE organisation_id = ? ORDER BY day DESC, id DESC;", [org_id])


## The least reputable active organisation of [param tier] (in [param region_id] when given),
## skipping [param exclude]. "" when there is none.
func weakest_in_tier(tier: int, region_id: String, exclude: Array[String]) -> String:
	for found: Dictionary in db.rows("""SELECT o.id FROM organisation o LEFT JOIN organisation_reputation r ON r.organisation_id = o.id
			WHERE o.active = 1 AND o.tier = ? AND (? = '' OR o.region_id = ?)
			ORDER BY COALESCE(r.value, 0) ASC, o.id ASC;""", [tier, region_id, region_id]):
		if not exclude.has(str(found["id"])):
			return str(found["id"])
	return ""


## The human's active starters only: a benched human's organisation plays (and is simulated) without them.
func organisation_has_human_starter(org_id: String) -> bool:
	return int(db.scalar("""SELECT COUNT(*) FROM contract c JOIN player p ON p.id = c.player_id
		WHERE c.organisation_id = ? AND c.status = 'active' AND c.is_substitute = 0 AND p.is_human = 1;""", [org_id], 0)) > 0


func set_contract_end(contract_id: String, end_day: int) -> bool:
	return db.execute("UPDATE contract SET end_day = ? WHERE id = ? AND start_day < ?;", [end_day, contract_id, end_day])


# --- Match engine: morale and simulated maps ---------------------------------------------------

func morale(player_id: String) -> int:
	return int(db.scalar("SELECT value FROM player_morale WHERE player_id = ?;", [player_id], 0))


func set_morale(player_id: String, value: int, day: int) -> bool:
	return db.execute("""INSERT INTO player_morale (player_id, value, updated_day) VALUES (?, ?, ?)
		ON CONFLICT(player_id) DO UPDATE SET value = excluded.value, updated_day = excluded.updated_day;""",
		[player_id, clampi(value, -20, 20), day])


## Morale fades towards neutral (monthly).
func fade_morale(keep: float, day: int) -> bool:
	return db.execute("UPDATE player_morale SET value = CAST(ROUND(value * ?) AS INTEGER), updated_day = ?;", [keep, day])


func insert_sim_map(league_fixture_id: int, map_number: int, map_id: String, score: Vector2i, mvp_id: String,
		highlights: PackedStringArray) -> bool:
	return db.execute("INSERT INTO sim_map VALUES (?, ?, ?, ?, ?, ?, ?);", [league_fixture_id, map_number, map_id,
		score.x, score.y, null if mvp_id.is_empty() else mvp_id, "\n".join(highlights)])


## Simulated maps of a series with the MVP's nickname.
func sim_maps(league_fixture_id: int) -> Array[Dictionary]:
	return db.rows("""SELECT m.*, p.nickname AS mvp_name FROM sim_map m LEFT JOIN player p ON p.id = m.mvp_id
		WHERE m.league_fixture_id = ? ORDER BY m.map_number;""", [league_fixture_id])


## One player's line from a simulated map ([param line] holds the engine's counts and rating).
func insert_sim_line(day: int, league_fixture_id: int, career_fixture_id: String, map_number: int, player_id: String,
		org_id: String, line: Dictionary, won: bool, map_id: String = "") -> bool:
	return db.execute("""INSERT INTO sim_player_map (day, league_fixture_id, career_fixture_id, map_number, player_id,
			organisation_id, rounds, kills, deaths, assists, damage, kast_rounds, opening_kills, clutch_wins, rating, won, map_id)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);""", [day, null if league_fixture_id < 0 else league_fixture_id,
		null if career_fixture_id.is_empty() else career_fixture_id, map_number, player_id, null if org_id.is_empty() else org_id,
		int(line["rounds"]), int(line["kills"]), int(line["deaths"]), int(line["assists"]), int(line["damage"]),
		int(line["kast_rounds"]), int(line["opening_kills"]), int(line["clutch_wins"]), float(line["rating"]), 1 if won else 0, map_id])


## Key of a world series map's timeline.
static func league_timeline_key(league_fixture_id: int, map_number: int) -> String:
	return "L%d:%d" % [league_fixture_id, map_number]


## Key of the human's simulated fixture's timeline.
static func career_timeline_key(career_fixture_id: String) -> String:
	return "C" + career_fixture_id


## Stores a simulated map's [MatchTimeline] under [param key].
func insert_sim_timeline(key: String, day: int, timeline: Dictionary) -> bool:
	return db.execute("INSERT OR REPLACE INTO sim_timeline (key, day, timeline_json) VALUES (?, ?, ?);",
		[key, day, JSON.stringify(timeline)])


## The timeline stored under [param key], or {} (none kept, or from a format this build does not read).
func sim_timeline(key: String) -> Dictionary:
	var text := str(db.scalar("SELECT timeline_json FROM sim_timeline WHERE key = ?;", [key], ""))
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or int((parsed as Dictionary).get("format_version", 0)) != MatchTimeline.FORMAT_VERSION:
		return {}
	return parsed


func has_sim_timeline(key: String) -> bool:
	return int(db.scalar("SELECT COUNT(*) FROM sim_timeline WHERE key = ?;", [key], 0)) > 0


## Drops world series timelines from before [param day] (the human's own are kept).
func prune_sim_timelines(day: int) -> bool:
	return db.execute("DELETE FROM sim_timeline WHERE day < ? AND key LIKE 'L%';", [day])


## How much [param org_id] has played [param map_id] since [param since_day]: {"on_map": maps
## there, "maps": all maps} (simulated maps; a map counts once however many players it lined up).
func team_map_history(org_id: String, map_id: String, since_day: int) -> Dictionary:
	var row := db.row("""SELECT COUNT(DISTINCT CASE WHEN map_id = ? THEN key END) AS on_map, COUNT(DISTINCT key) AS maps
		FROM (SELECT map_id, COALESCE(league_fixture_id, '') || ':' || COALESCE(career_fixture_id, '') || ':' || map_number AS key
			FROM sim_player_map WHERE organisation_id = ? AND day >= ?);""", [map_id, org_id, since_day])
	return {"on_map": int(row.get("on_map", 0)), "maps": int(row.get("maps", 0))}


## Each player's simulated history for [param map_id]: {player_id: {"maps": all maps ever,
## "recent": maps since [param since_day], "rating": their average rating since then, "on_map": maps
## on this map since then, "map_rating": average rating there (0 when none)}}.
func player_map_history(player_ids: Array[String], map_id: String, since_day: int) -> Dictionary:
	var result: Dictionary = {}
	if player_ids.is_empty():
		return result
	var marks := ", ".join(player_ids.map(func(_id: String) -> String: return "?"))
	var bindings: Array = [since_day, since_day, map_id, since_day, map_id, since_day]
	bindings.append_array(player_ids)
	for row: Dictionary in db.rows("""SELECT player_id, COUNT(*) AS maps, SUM(day >= ?) AS recent,
			AVG(CASE WHEN day >= ? THEN rating END) AS rating,
			SUM(map_id = ? AND day >= ?) AS on_map, AVG(CASE WHEN map_id = ? AND day >= ? THEN rating END) AS map_rating
			FROM sim_player_map WHERE player_id IN (%s) GROUP BY player_id;""" % marks, bindings):
		result[str(row["player_id"])] = {"maps": int(row["maps"]), "recent": int(row["recent"]),
			"rating": float(row["rating"]) if row["rating"] != null else 0.0, "on_map": int(row["on_map"]),
			"map_rating": float(row["map_rating"]) if row["map_rating"] != null else 0.0}
	return result


## A player's simulated maps since [param since_day]: totals and the average rating.
func sim_form(player_id: String, since_day: int) -> Dictionary:
	return db.row("""SELECT COUNT(*) AS maps, COALESCE(SUM(won), 0) AS won, COALESCE(SUM(rounds), 0) AS rounds,
			COALESCE(SUM(kills), 0) AS kills, COALESCE(SUM(deaths), 0) AS deaths, COALESCE(SUM(assists), 0) AS assists,
			COALESCE(SUM(opening_kills), 0) AS opening_kills, COALESCE(SUM(clutch_wins), 0) AS clutch_wins,
			COALESCE(AVG(rating), 0) AS rating, COALESCE(MAX(rating), 0) AS best
		FROM sim_player_map WHERE player_id = ? AND day >= ?;""", [player_id, since_day])


## Average simulated rating of AI players with at least [param min_maps] maps since a day.
func sim_ratings_since(since_day: int, min_maps: int) -> Array[Dictionary]:
	return db.rows("""SELECT s.player_id, AVG(s.rating) AS rating, COUNT(*) AS maps FROM sim_player_map s
		JOIN player p ON p.id = s.player_id WHERE p.is_human = 0 AND s.day >= ?
		GROUP BY s.player_id HAVING COUNT(*) >= ?;""", [since_day, min_maps])


## Best simulated performers of a competition season (average rating, at least [param min_maps]).
func top_performers(competition_id: String, year: int, min_maps: int, limit: int = 10) -> Array[Dictionary]:
	return db.rows("""SELECT s.player_id, p.nickname, o.short_name AS org, COUNT(*) AS maps, AVG(s.rating) AS rating,
			SUM(s.kills) AS kills, SUM(s.deaths) AS deaths
		FROM sim_player_map s JOIN league_fixture f ON f.id = s.league_fixture_id
		JOIN player p ON p.id = s.player_id LEFT JOIN organisation o ON o.id = s.organisation_id
		WHERE f.competition_id = ? AND f.season_year = ?
		GROUP BY s.player_id HAVING COUNT(*) >= ? ORDER BY rating DESC LIMIT ?;""", [competition_id, year, min_maps, limit])


# --- Hub navigation views ----------------------------------------------------------------------

## An organisation's series (league and cup), newest first, with names and competition.
func organisation_series(org_id: String, limit: int = 20, upcoming: bool = false) -> Array[Dictionary]:
	return db.rows("""SELECT f.*, c.name AS competition_name, c.kind, h.name AS home_name, a.name AS away_name
		FROM league_fixture f JOIN competition c ON c.id = f.competition_id
		JOIN organisation h ON h.id = f.home_id JOIN organisation a ON a.id = f.away_id
		WHERE (f.home_id = ? OR f.away_id = ?) AND %s
		ORDER BY f.scheduled_day %s, f.id LIMIT ?;""" % ["f.home_maps IS NULL" if upcoming else "f.home_maps IS NOT NULL",
		"ASC" if upcoming else "DESC"], [org_id, org_id, limit])


## One series with its competition and both organisations' names, or {}.
func series_detail(series_id: int) -> Dictionary:
	return db.row("""SELECT f.*, s.best_of, c.name AS competition_name, c.kind, c.tier, h.name AS home_name, a.name AS away_name
		FROM league_fixture f JOIN league_season s ON s.competition_id = f.competition_id AND s.season_year = f.season_year
		JOIN competition c ON c.id = f.competition_id
		JOIN organisation h ON h.id = f.home_id JOIN organisation a ON a.id = f.away_id WHERE f.id = ?;""", [series_id])


## Every player line of a simulated series with nicknames (map order, best rating first).
func series_lines(series_id: int) -> Array[Dictionary]:
	return db.rows("""SELECT s.*, p.nickname FROM sim_player_map s JOIN player p ON p.id = s.player_id
		WHERE s.league_fixture_id = ? ORDER BY s.map_number, s.organisation_id, s.rating DESC;""", [series_id])


## A player's simulated maps, newest first, with the series, competition and opponent.
func player_lines(player_id: String, limit: int = 30) -> Array[Dictionary]:
	return db.rows("""SELECT s.*, f.id AS series_id, c.name AS competition_name,
			CASE WHEN f.home_id = s.organisation_id THEN a.name ELSE h.name END AS opponent_name,
			CASE WHEN f.home_id = s.organisation_id THEN f.away_id ELSE f.home_id END AS opponent_id,
			m.home_rounds, m.away_rounds, m.map_id, (f.home_id = s.organisation_id) AS at_home
		FROM sim_player_map s LEFT JOIN league_fixture f ON f.id = s.league_fixture_id
		LEFT JOIN competition c ON c.id = f.competition_id
		LEFT JOIN organisation h ON h.id = f.home_id LEFT JOIN organisation a ON a.id = f.away_id
		LEFT JOIN sim_map m ON m.league_fixture_id = s.league_fixture_id AND m.map_number = s.map_number
		WHERE s.player_id = ? ORDER BY s.day DESC, s.id DESC LIMIT ?;""", [player_id, limit])


## News about a player or an organisation, newest first.
func news_about(player_id: String, org_id: String, limit: int = 20) -> Array[Dictionary]:
	return db.rows("""SELECT * FROM world_news WHERE (? <> '' AND player_id = ?) OR (? <> '' AND organisation_id = ?)
		ORDER BY day DESC, id DESC LIMIT ?;""", [player_id, player_id, org_id, org_id, limit])


## An organisation's final placings in every completed season, newest first.
func organisation_records(org_id: String) -> Array[Dictionary]:
	return db.rows("""SELECT r.*, c.name AS competition_name, c.kind FROM league_record r
		JOIN competition c ON c.id = r.competition_id WHERE r.organisation_id = ?
		ORDER BY r.season_year DESC, c.tier, c.name;""", [org_id])


## A player's simulated record per map: maps, wins, average rating, kills and deaths.
func player_map_stats(player_id: String) -> Array[Dictionary]:
	return db.rows("""SELECT m.map_id, COUNT(*) AS maps, SUM(s.won) AS won, AVG(s.rating) AS rating,
			SUM(s.kills) AS kills, SUM(s.deaths) AS deaths, SUM(s.rounds) AS rounds
		FROM sim_player_map s JOIN sim_map m ON m.league_fixture_id = s.league_fixture_id AND m.map_number = s.map_number
		WHERE s.player_id = ? GROUP BY m.map_id ORDER BY maps DESC;""", [player_id])


## Players whose nickname or name matches [param text] (the compare picker): id, nickname, org.
func find_players(text: String, limit: int = 12) -> Array[Dictionary]:
	var pattern := "%" + text.strip_edges() + "%"
	return db.rows("""SELECT p.id, p.nickname, o.short_name AS org FROM player p
		LEFT JOIN contract c ON c.player_id = p.id AND c.status = 'active'
		LEFT JOIN organisation o ON o.id = c.organisation_id
		WHERE p.nickname LIKE ? OR (p.first_name || ' ' || p.last_name) LIKE ?
		ORDER BY p.nickname LIMIT ?;""", [pattern, pattern, limit])


# --- Training ----------------------------------------------------------------------------------

## Stores one finished drill or scrim. [param evidence] is the perceived-attribute change it made.
func insert_training(player_id: String, day: int, drill_id: String, score: int, metrics: Dictionary, evidence: int,
		bootcamp: bool = false) -> bool:
	return db.execute("""INSERT INTO training_session (player_id, day, drill_id, score, metrics_json, evidence, bootcamp)
		VALUES (?, ?, ?, ?, ?, ?, ?);""", [player_id, day, drill_id, clampi(score, 0, 100), JSON.stringify(metrics), evidence,
		1 if bootcamp else 0])


## Drill ids already completed as bootcamp sessions since [param since_day].
func bootcamp_done(player_id: String, since_day: int) -> Array[String]:
	var done: Array[String] = []
	for found: Dictionary in db.rows("SELECT DISTINCT drill_id FROM training_session WHERE player_id = ? AND bootcamp = 1 AND day >= ?;",
			[player_id, since_day]):
		done.append(str(found["drill_id"]))
	return done


## A player's training sessions, newest first ({day, drill_id, score, metrics, evidence}).
func training_sessions(player_id: String, limit: int = 20, drill_id: String = "") -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for found: Dictionary in db.rows("""SELECT * FROM training_session WHERE player_id = ? AND (? = '' OR drill_id = ?)
			ORDER BY day DESC, id DESC LIMIT ?;""", [player_id, drill_id, drill_id, limit]):
		var parsed: Variant = JSON.parse_string(str(found["metrics_json"]))
		found["metrics"] = parsed if parsed is Dictionary else {}
		list.append(found)
	return list


## Best score and number of sessions per drill: {drill_id: {best, sessions, average}}.
func training_bests(player_id: String) -> Dictionary[String, Dictionary]:
	var bests: Dictionary[String, Dictionary] = {}
	for found: Dictionary in db.rows("""SELECT drill_id, MAX(score) AS best, COUNT(*) AS sessions, AVG(score) AS average
			FROM training_session WHERE player_id = ? GROUP BY drill_id;""", [player_id]):
		bests[str(found["drill_id"])] = found
	return bests


## True when a drill already counted as evidence today.
func training_count(player_id: String, drill_id: String, day: int) -> int:
	return int(db.scalar("SELECT COUNT(*) FROM training_session WHERE player_id = ? AND drill_id = ? AND day = ?;",
		[player_id, drill_id, day], 0))


## A player's maps since [param since_day]: {maps, rating (average F2F rating), wins}. Simulated
## lines and played career fixtures both count (a played map is counted once).
func form_since(player_id: String, since_day: int) -> Dictionary:
	var sim := db.row("""SELECT COUNT(*) AS maps, COALESCE(SUM(rating), 0) AS total, COALESCE(SUM(won), 0) AS wins
		FROM sim_player_map WHERE player_id = ? AND day >= ?;""", [player_id, since_day])
	var played := db.row("""SELECT COUNT(*) AS maps, COALESCE(SUM(r.rating), 0) AS total FROM career_match_rating r
		JOIN career_fixture f ON f.id = r.fixture_id WHERE r.player_id = ? AND f.scheduled_day >= ?
		AND NOT EXISTS (SELECT 1 FROM sim_player_map s WHERE s.career_fixture_id = r.fixture_id AND s.player_id = r.player_id);""",
		[player_id, since_day])
	var maps := int(sim.get("maps", 0)) + int(played.get("maps", 0))
	var total := float(sim.get("total", 0.0)) + float(played.get("total", 0.0))
	return {"maps": maps, "rating": total / maps if maps > 0 else 0.0, "wins": int(sim.get("wins", 0))}


## Maps each player was seen playing since [param since_day] (simulated lines), by player id.
func maps_since(since_day: int) -> Dictionary[String, int]:
	var counts: Dictionary[String, int] = {}
	for found: Dictionary in db.rows("SELECT player_id, COUNT(*) AS maps FROM sim_player_map WHERE day >= ? GROUP BY player_id;", [since_day]):
		counts[str(found["player_id"])] = int(found["maps"])
	return counts


## Your latest [param limit] scores for a drill, newest first (your record for it).
func training_scores(player_id: String, drill_id: String, limit: int) -> Array[int]:
	var scores: Array[int] = []
	for found: Dictionary in db.rows("SELECT score FROM training_session WHERE player_id = ? AND drill_id = ? ORDER BY day DESC, id DESC LIMIT ?;",
			[player_id, drill_id, limit]):
		scores.append(int(found["score"]))
	return scores


## The sessions that counted for a bootcamp booked on [param since_day].
func bootcamp_sessions(player_id: String, since_day: int) -> Array[Dictionary]:
	return db.rows("SELECT drill_id, score, day FROM training_session WHERE player_id = ? AND bootcamp = 1 AND day >= ? ORDER BY id;",
		[player_id, since_day])


# --- People -----------------------------------------------------------------------------------

const PERSON_FIELDS: Array[String] = ["ambition", "loyalty", "professionalism", "temperament", "ego", "sociability"]


func insert_person(player_id: String, person: Dictionary) -> bool:
	return db.execute("""INSERT OR REPLACE INTO person (player_id, ambition, loyalty, professionalism, temperament, ego,
			sociability, drive, background, goal, happiness, updated_day) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);""",
		[player_id, person["ambition"], person["loyalty"], person["professionalism"], person["temperament"], person["ego"],
			person["sociability"], person["drive"], person["background"], person["goal"], int(person.get("happiness", 0)),
			int(person.get("updated_day", 0))])


## A player's person row, or {} (humans have none: the person is the one playing).
func person(player_id: String) -> Dictionary:
	return db.row("SELECT * FROM person WHERE player_id = ?;", [player_id])


## Every person row by player id.
func people() -> Dictionary[String, Dictionary]:
	var all: Dictionary[String, Dictionary] = {}
	for found: Dictionary in db.rows("SELECT * FROM person;"):
		all[str(found["player_id"])] = found
	return all


## Active AI players without a person yet (new rookies, older saves): id, birth_day.
func players_without_person() -> Array[Dictionary]:
	return db.rows("""SELECT p.id, p.birth_day FROM player p WHERE p.is_human = 0 AND p.status = 'active'
		AND NOT EXISTS (SELECT 1 FROM person x WHERE x.player_id = p.id) ORDER BY p.id;""")


func set_person_mood(player_id: String, happiness: int, wants_move: bool, reason: String, day: int) -> bool:
	return db.execute("UPDATE person SET happiness = ?, wants_move = ?, mood_reason = ?, updated_day = ? WHERE player_id = ?;",
		[clampi(happiness, -50, 50), 1 if wants_move else 0, reason, day, player_id])


func set_goal_done(player_id: String, day: int) -> bool:
	return db.execute("UPDATE person SET goal_done_day = ? WHERE player_id = ? AND goal_done_day IS NULL;", [day, player_id])


## Every active contract with what the people layer needs: player_id, organisation_id, tier,
## is_substitute, monthly_salary, start_day, is_human, birth_day, form.
func contracted_players() -> Array[Dictionary]:
	return db.rows("""SELECT c.player_id, c.organisation_id, o.tier, c.is_substitute, c.monthly_salary, c.start_day,
			p.is_human, p.birth_day, p.nickname, COALESCE(f.value, 0) AS form
		FROM contract c JOIN player p ON p.id = c.player_id JOIN organisation o ON o.id = c.organisation_id
		LEFT JOIN organisation_form f ON f.organisation_id = c.organisation_id
		WHERE c.status = 'active' ORDER BY c.organisation_id, c.is_substitute, c.player_id;""")


## Relationship strength between two players (0 when they have none).
func relationship(a_id: String, b_id: String) -> int:
	var low := a_id if a_id < b_id else b_id
	var high := b_id if a_id < b_id else a_id
	return int(db.scalar("SELECT strength FROM relationship WHERE a_id = ? AND b_id = ?;", [low, high], 0))


## All relationships by "a|b" key (a < b) → strength.
func relationships() -> Dictionary[String, int]:
	var all: Dictionary[String, int] = {}
	for found: Dictionary in db.rows("SELECT a_id, b_id, strength FROM relationship;"):
		all["%s|%s" % [found["a_id"], found["b_id"]]] = int(found["strength"])
	return all


func set_relationship(a_id: String, b_id: String, strength: int, day: int) -> bool:
	var low := a_id if a_id < b_id else b_id
	var high := b_id if a_id < b_id else a_id
	return db.execute("""INSERT INTO relationship (a_id, b_id, strength, since_day, updated_day) VALUES (?, ?, ?, ?, ?)
		ON CONFLICT (a_id, b_id) DO UPDATE SET strength = excluded.strength, updated_day = excluded.updated_day;""",
		[low, high, clampi(strength, -100, 100), day, day])


## A player's relationships, strongest feelings first: other_id, nickname, strength, since_day.
func relationships_of(player_id: String, limit: int = 12) -> Array[Dictionary]:
	return db.rows("""SELECT CASE WHEN r.a_id = ? THEN r.b_id ELSE r.a_id END AS other_id, p.nickname, r.strength, r.since_day
		FROM relationship r JOIN player p ON p.id = (CASE WHEN r.a_id = ? THEN r.b_id ELSE r.a_id END)
		WHERE (r.a_id = ? OR r.b_id = ?) AND r.strength <> 0 ORDER BY ABS(r.strength) DESC LIMIT ?;""",
		[player_id, player_id, player_id, player_id, limit])
