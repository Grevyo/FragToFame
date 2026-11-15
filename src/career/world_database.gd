class_name WorldDatabase
extends RefCounted
## Typed access to one world database file (`.f2fdb`, see [WorldDbSchema]): the shipped default
## world or one a player imported. Careers never play inside it — [CareerStart] copies it into a
## new save once. Files stay single and self-contained (rollback journal, no WAL side files).

const OrganisationRecord := CareerRecords.OrganisationRecord
const PlayerRecord := CareerRecords.PlayerRecord
const ContractRecord := CareerRecords.ContractRecord
const CompetitionRecord := CareerRecords.CompetitionRecord

## Starters every organisation must field for the database to be playable.
const MIN_STARTERS: int = 5
const MAX_REPORTED_PROBLEMS: int = 20

var db := CareerDatabase.new()
var _read_only: bool = false


## Opens an existing world database. Returns "" or a readable error.
func open(path: String) -> String:
	close()
	_read_only = true
	if not FileAccess.file_exists(path):
		return "database file not found: %s" % path
	for suffix: String in ["-wal", "-shm", "-journal"]:
		if FileAccess.file_exists(path + suffix):
			return "close the source database and export a standalone world file"
	if not db.open(path, true, false):
		return db.last_error
	var error := ""
	if db.user_version() != WorldDbSchema.CURRENT_VERSION:
		error = "unsupported world database schema %d" % db.user_version()
	elif meta_value("format") != WorldDbSchema.FORMAT:
		error = "not a Frag to Fame world database (format '%s')" % meta_value("format")
	if not error.is_empty():
		db.close()
	return error


## Creates an empty world database at [param path] (replacing any file there).
func create(path: String, database_id: String, name: String, author: String, description: String,
		status: String = "draft") -> String:
	close()
	_read_only = false
	for suffix: String in ["", "-journal", "-wal", "-shm"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if not db.open(path, false, false):
		return db.last_error
	var error := WorldDbSchema.migrate(db)
	if not error.is_empty():
		return error
	var ok := db.transaction(func() -> bool:
		return set_meta_value("format", WorldDbSchema.FORMAT) and set_meta_value("database_id", database_id) \
			and set_meta_value("name", name) and set_meta_value("author", author) \
			and set_meta_value("description", description) and set_meta_value("status", status))
	return "" if ok else db.last_error


func close() -> void:
	db.close()


func is_open() -> bool:
	return db.is_open()


func transaction(work: Callable) -> bool:
	return db.transaction(work)


func meta_value(key: String, fallback: String = "") -> String:
	var value: Variant = db.scalar("SELECT value FROM meta WHERE key = ?;", [key])
	return str(value) if value != null else fallback


func set_meta_value(key: String, value: Variant) -> bool:
	return db.execute("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
		[key, str(value)])


func database_id() -> String:
	return meta_value("database_id")


func display_name() -> String:
	return meta_value("name", "Unnamed database")


# --- Writing (generator, Database Editor) -------------------------------------------------------

func insert_organisation(org: OrganisationRecord, reputation: Vector2i) -> bool:
	return db.execute("""INSERT INTO organisation (id, name, short_name, region_id, tier, founded_day, colour,
			reputation_min, reputation_max) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);""",
		[org.id, org.name, org.short_name, org.region_id, org.tier, org.founded_day, org.colour,
			clampi(reputation.x, 0, 100), clampi(reputation.y, 0, 100)])


## [param ranges]: {ability or potential: Vector2i(min, max)}.
func insert_player(player: PlayerRecord, ranges: Dictionary[StringName, Vector2i], reputation: Vector2i) -> bool:
	return transaction(func() -> bool:
		if not db.execute("""INSERT INTO player (id, first_name, last_name, nickname, nation_id, birth_day,
				preferred_role, reputation_min, reputation_max) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);""",
				[player.id, player.first_name, player.last_name, player.nickname, player.nation_id, player.birth_day,
					String(player.preferred_role), clampi(reputation.x, 0, 100), clampi(reputation.y, 0, 100)]):
			return false
		for ability: StringName in ranges:
			var span: Vector2i = ranges[ability]
			if not db.execute("INSERT INTO player_range (player_id, ability, min_value, max_value) VALUES (?, ?, ?, ?);",
					[player.id, String(ability), clampi(span.x, 1, 100), clampi(span.y, 1, 100)]):
				return false
		return true)


## Adds a trait unless it is unknown or conflicts with one the player already has.
func add_trait(player_id: String, trait_id: StringName, strength: int = 1) -> bool:
	if not TraitLibrary.has_trait(trait_id):
		return false
	for existing: StringName in traits(player_id):
		if TraitLibrary.conflicts(existing, trait_id):
			return false
	return db.execute("INSERT OR REPLACE INTO player_trait (player_id, trait_id, strength) VALUES (?, ?, ?);",
		[player_id, String(trait_id), clampi(strength, 1, 3)])


## Places a player in an organisation's starting roster ([member ContractRecord.id] is ignored:
## each career creates its own contract records).
func add_to_roster(contract: ContractRecord) -> bool:
	return db.execute("""INSERT INTO roster (player_id, organisation_id, role, is_substitute, monthly_salary,
			start_day, end_day) VALUES (?, ?, ?, ?, ?, ?, ?);""",
		[contract.player_id, contract.organisation_id, String(contract.role), 1 if contract.is_substitute else 0,
			contract.monthly_salary, contract.start_day, contract.end_day])


func insert_competition(competition: CompetitionRecord) -> bool:
	return db.execute("""INSERT INTO competition (id, name, short_name, kind, region_id, tier, team_count, start_month)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?);""",
		[competition.id, competition.name, competition.short_name, competition.kind,
			null if competition.region_id.is_empty() else competition.region_id, competition.tier,
			competition.team_count, competition.start_month])


# --- Reading ----------------------------------------------------------------------------------

func organisation_count() -> int:
	return int(db.scalar("SELECT COUNT(*) FROM organisation;", [], 0))


func player_count() -> int:
	return int(db.scalar("SELECT COUNT(*) FROM player;", [], 0))


func competition_count() -> int:
	return int(db.scalar("SELECT COUNT(*) FROM competition;", [], 0))


## Raw table rows in a stable order (used by [CareerStart] to copy the database).
func organisation_rows() -> Array[Dictionary]:
	return db.rows("SELECT * FROM organisation ORDER BY id;")


func player_rows() -> Array[Dictionary]:
	return db.rows("SELECT * FROM player ORDER BY id;")


func range_rows() -> Array[Dictionary]:
	return db.rows("SELECT * FROM player_range ORDER BY player_id, ability;")


func trait_rows() -> Array[Dictionary]:
	return db.rows("SELECT * FROM player_trait ORDER BY player_id, trait_id;")


func roster_rows() -> Array[Dictionary]:
	return db.rows("SELECT * FROM roster ORDER BY organisation_id, is_substitute, player_id;")


func competition_rows() -> Array[Dictionary]:
	return db.rows("SELECT * FROM competition ORDER BY tier, id;")


func ranges(player_id: String) -> Dictionary[StringName, Vector2i]:
	var result: Dictionary[StringName, Vector2i] = {}
	for found: Dictionary in db.rows("SELECT ability, min_value, max_value FROM player_range WHERE player_id = ?;", [player_id]):
		result[StringName(str(found["ability"]))] = Vector2i(int(found["min_value"]), int(found["max_value"]))
	return result


func traits(player_id: String) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for found: Dictionary in db.rows("SELECT trait_id, strength FROM player_trait WHERE player_id = ? ORDER BY trait_id;", [player_id]):
		result[StringName(str(found["trait_id"]))] = int(found["strength"])
	return result


## {database_id, name, author, description, status, organisations, players, competitions}
func summary() -> Dictionary:
	return {"database_id": database_id(), "name": display_name(), "author": meta_value("author"),
		"description": meta_value("description"), "status": meta_value("status", "community"),
		"organisations": organisation_count(), "players": player_count(), "competitions": competition_count()}


## Content hash of every table (metadata excluded): equal fingerprints = identical worlds.
func fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for table: Array[Dictionary] in [organisation_rows(), player_rows(), range_rows(), trait_rows(), roster_rows(),
			competition_rows()]:
		for found: Dictionary in table:
			ctx.update(str(found).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Problems that make the database unusable for a career (empty = valid).
func validate() -> Array[String]:
	var problems: Array[String] = []
	if db.integrity_check() != "ok":
		problems.append("the file is damaged")
		return problems
	if not db.foreign_keys_are_valid():
		problems.append("the database has invalid foreign keys")
	if not Ids.is_file_id(database_id()):
		problems.append("the database has an invalid ID")
	if meta_value("name").strip_edges().is_empty():
		problems.append("the database has no name")
	if organisation_count() < 2:
		problems.append("at least two organisations are needed")
	for found: Dictionary in organisation_rows():
		if not CareerCatalog.REGIONS.has(str(found["region_id"])):
			problems.append("organisation %s: unknown region '%s'" % [found["id"], found["region_id"]])
	_validate_players(problems)
	for found: Dictionary in db.rows("""SELECT o.id, (SELECT COUNT(*) FROM roster r WHERE r.organisation_id = o.id
			AND r.is_substitute = 0) AS starters FROM organisation o;"""):
		if int(found["starters"]) < MIN_STARTERS:
			problems.append("organisation %s fields %d starters (needs %d)" % [found["id"], found["starters"], MIN_STARTERS])
	for found: Dictionary in roster_rows():
		if not CareerCatalog.ROLES.has(StringName(str(found["role"]))):
			problems.append("roster entry %s: unknown role '%s'" % [found["player_id"], found["role"]])
	for found: Dictionary in competition_rows():
		if found["region_id"] != null and not CareerCatalog.REGIONS.has(str(found["region_id"])):
			problems.append("competition %s: unknown region '%s'" % [found["id"], found["region_id"]])
	if problems.size() > MAX_REPORTED_PROBLEMS:
		var more := problems.size() - MAX_REPORTED_PROBLEMS
		problems.resize(MAX_REPORTED_PROBLEMS)
		problems.append("… and %d more problems" % more)
	return problems


## Copies a standalone template. Writers snapshot through SQLite so committed rows are included.
func export_to(target_path: String) -> String:
	var folder := target_path.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if made != OK and not DirAccess.dir_exists_absolute(folder):
		return "could not create export folder: %s" % error_string(made)
	var stage := target_path + "." + Ids.generate("stage") + ".f2fdb"
	# An opened template is read-only and has no journal. A writer needs a SQLite snapshot.
	var error := ""
	if _read_only:
		var copied := DirAccess.copy_absolute(db.path, stage)
		if copied != OK or FileAccess.get_sha256(stage) != FileAccess.get_sha256(db.path):
			error = "could not copy the world database"
	elif not db.backup_to(stage):
		error = db.last_error
	if error.is_empty():
		var verified := WorldDatabase.new()
		error = verified.open(stage)
		if error.is_empty():
			error = "; ".join(verified.validate())
		verified.close()
	if error.is_empty():
		var installed := FileReplacement.install(stage, target_path, target_path + ".bak")
		if installed != OK:
			error = "could not install the export: %s" % error_string(installed)
	if not error.is_empty() and FileAccess.file_exists(stage):
		DirAccess.remove_absolute(stage)
	return error


func _validate_players(problems: Array[String]) -> void:
	var expected: Array[StringName] = CareerCatalog.ABILITIES.duplicate()
	expected.append(CareerCatalog.POTENTIAL)
	var counts: Dictionary[String, int] = {}
	var minimum_totals: Dictionary[String, int] = {}
	var potential_maxima: Dictionary[String, int] = {}
	for found: Dictionary in range_rows():
		var ability := StringName(str(found["ability"]))
		if not expected.has(ability):
			problems.append("player %s: unknown ability '%s'" % [found["player_id"], ability])
		var player_id := str(found["player_id"])
		counts[player_id] = counts.get(player_id, 0) + 1
		if ability == CareerCatalog.POTENTIAL:
			potential_maxima[player_id] = int(found["max_value"])
		else:
			minimum_totals[player_id] = minimum_totals.get(player_id, 0) + int(found["min_value"])
	for found: Dictionary in player_rows():
		var id := str(found["id"])
		if not CareerCatalog.NATIONS.has(str(found["nation_id"])):
			problems.append("player %s: unknown nation '%s'" % [id, found["nation_id"]])
		if not CareerCatalog.ROLES.has(StringName(str(found["preferred_role"]))):
			problems.append("player %s: unknown role '%s'" % [id, found["preferred_role"]])
		if counts.get(id, 0) != expected.size():
			problems.append("player %s: needs a range for every ability and potential" % id)
		elif minimum_totals.get(id, 0) > potential_maxima.get(id, 0) * CareerCatalog.ABILITIES.size():
			problems.append("player %s: minimum abilities exceed their potential range" % id)
	var by_player: Dictionary[String, Array] = {}
	for found: Dictionary in trait_rows():
		var trait_id := StringName(str(found["trait_id"]))
		if not TraitLibrary.has_trait(trait_id):
			problems.append("player %s: unknown trait '%s'" % [found["player_id"], trait_id])
		if not by_player.has(str(found["player_id"])):
			by_player[str(found["player_id"])] = []
		by_player[str(found["player_id"])].append(trait_id)
	for player_id: String in by_player:
		var ids: Array[StringName] = []
		ids.assign(by_player[player_id])
		if not TraitLibrary.compatible(ids):
			problems.append("player %s: conflicting traits" % player_id)
