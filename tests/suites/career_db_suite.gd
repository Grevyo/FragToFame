class_name CareerDbSuite
extends TestSuite
## Milestone 9: career database — schema/migrations, repository, stat-layer separation, world
## generation, human creation, saves, backups, damage detection and restore.

const TEST_ROOT: String = "user://tests/careers"
const PROFILE: Dictionary = {"first_name": "Rowan", "last_name": "Hartley", "nickname": "Sable",
	"nation_id": "gb", "preferred_role": &"rifler", "difficulty": &"standard", "age": 19}


class FailingRestoreSaves extends CareerSaves:
	var blocked_target: String = ""

	func _move_file(source: String, target: String) -> Error:
		if target == blocked_target and source.contains(".restore_"):
			return ERR_CANT_CREATE
		return super._move_file(source, target)


func suite_name() -> String:
	return "Career database (Milestone 9)"


func run() -> void:
	_clean(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	_test_calendar()
	_test_schema()
	_test_repository()
	_test_generator()
	_test_saves()
	_test_template()
	_test_migration_failures()
	_test_import()
	_clean(TEST_ROOT)


func _test_calendar() -> void:
	section("In-game calendar")
	check(GameDate.format(0) == "01 Jan Y1", "day 0 is 01 Jan Y1 (%s)" % GameDate.format(0))
	check(GameDate.format(31 + 13) == "14 Feb Y1", "day 44 is 14 Feb Y1")
	check(GameDate.format(365) == "01 Jan Y2", "a year has 365 days")
	check(GameDate.make(3, 12, 31) == 3 * 365 - 1, "make() inverts format")
	check(GameDate.age(-19 * 365 - 10, 0) == 19, "age in whole years")
	check(GameDate.format(-1) == "31 Dec Y0", "days before the start belong to Year 0")


func _test_schema() -> void:
	section("Schema and migrations")
	var db := CareerDatabase.new()
	check(db.open(TEST_ROOT + "/schema.db"), "opens a new database file")
	check(db.user_version() == 0, "a new file starts at schema 0")
	check(CareerSchema.migrate(db).is_empty() and db.user_version() == CareerSchema.CURRENT_VERSION,
		"migrates to the current schema (%d)" % CareerSchema.CURRENT_VERSION)
	check(CareerSchema.migrate(db).is_empty(), "migrating an up-to-date database is a no-op")
	check(str(db.scalar("PRAGMA journal_mode;")) == "wal", "WAL journalling is on")
	check(int(db.scalar("PRAGMA foreign_keys;")) == 1, "foreign keys are enforced")
	var rolled_back := db.transaction(func() -> bool:
		db.execute("INSERT INTO meta (key, value) VALUES ('a', '1');")
		return db.execute("INSERT INTO no_such_table VALUES (1);"))
	check(not rolled_back and db.scalar("SELECT value FROM meta WHERE key = 'a';") == null,
		"a failing statement rolls back the whole transaction")
	db.set_user_version(CareerSchema.CURRENT_VERSION + 1)
	check(not CareerSchema.migrate(db).is_empty(), "a save from a newer build is refused, never downgraded")
	db.close()


func _test_repository() -> void:
	section("Repository and stat layers")
	var repo := CareerRepository.new()
	check(repo.open(TEST_ROOT + "/repo.db").is_empty(), "repository opens and migrates")
	check(repo.seed_reference_data(), "regions and nations seeded")
	var org := CareerRecords.OrganisationRecord.new()
	org.id = "org_test"
	org.name = "Test Herons"
	org.short_name = "TH"
	org.region_id = "eu_west"
	org.tier = 2
	org.colour = "336699"
	check(repo.insert_organisation(org), "organisation inserted")
	var dup := CareerRecords.OrganisationRecord.new()
	dup.id = "org_other"
	dup.name = "Test Herons"
	dup.short_name = "TH"
	dup.region_id = "eu_west"
	dup.tier = 2
	check(not repo.insert_organisation(dup), "organisation names are unique")

	var ai := _player("ply_ai", "Basalt", false)
	check(repo.insert_player(ai), "AI player inserted")
	check(repo.set_abilities("ply_ai", {&"aim": 80, &"reaction": 150}), "abilities stored")
	check(repo.abilities("ply_ai")[&"reaction"] == 100, "ability values are clamped to 1–100")
	repo.set_perceived("ply_ai", {&"aim": 72}, 60, 0)
	check(repo.perceived("ply_ai")[&"aim"] == 72 and repo.abilities("ply_ai")[&"aim"] == 80,
		"perceived and true values are separate layers")
	var human := _player("ply_human", "Sable", true)
	repo.insert_player(human)
	check(not repo.set_abilities("ply_human", {&"aim": 99}) and repo.abilities("ply_human").is_empty(),
		"human players can never have simulated abilities")
	check(repo.add_trait("ply_ai", &"tr_aggressive", 2) and not repo.add_trait("ply_ai", &"tr_passive"),
		"conflicting traits are refused")
	check(not repo.add_trait("ply_ai", &"tr_not_a_trait"), "unknown traits are refused")

	var contract := CareerRecords.ContractRecord.new()
	contract.id = "con_1"
	contract.player_id = "ply_ai"
	contract.organisation_id = "org_test"
	contract.role = &"entry"
	contract.monthly_salary = 4000
	contract.start_day = -10
	contract.end_day = 300
	check(repo.sign_contract(contract), "contract signed")
	var second := CareerRecords.ContractRecord.new()
	second.id = "con_2"
	second.player_id = "ply_ai"
	second.organisation_id = "org_test"
	second.start_day = 0
	second.end_day = 100
	check(not repo.sign_contract(second), "a player cannot hold two active contracts")
	var ghost := CareerRecords.ContractRecord.new()
	ghost.id = "con_3"
	ghost.player_id = "ply_missing"
	ghost.organisation_id = "org_test"
	ghost.start_day = 0
	ghost.end_day = 10
	check(not repo.sign_contract(ghost), "contracts must reference existing players")
	check(repo.roster("org_test").size() == 1 and repo.active_contract("ply_ai").role == &"entry", "roster query")
	var lineup := repo.lineup("org_test")
	check(lineup.size() == 1 and (lineup[0]["abilities"] as Dictionary).has("aim"), "lineup carries AI abilities")
	check(repo.end_contract("con_1", "terminated", 50) and repo.active_contract("ply_ai") == null
		and repo.contract_history("ply_ai").size() == 1, "ending a contract keeps it in history")
	check(repo.search_players({"text": "basalt"}).size() == 1, "search by nickname (case-insensitive)")
	check(repo.search_players({"free_agents": true}).size() == 2, "both players are now free agents")
	check(repo.search_players({"sort_ability": "drop table"}).is_empty(), "unknown sort keys are rejected")
	repo.close()


func _test_generator() -> void:
	section("World generation")
	var path := TEST_ROOT + "/world_a.f2fdb"
	var world := WorldDatabase.new()
	var started := Time.get_ticks_msec()
	var error := WorldGenerator.build(path, 1234, "world_test", "Test world", "")
	check(error.is_empty() and world.open(path).is_empty() and world.validate().is_empty(),
		"generator produces a usable draft template (%d ms)" % (Time.get_ticks_msec() - started))
	if not world.is_open():
		return
	var repo := CareerRepository.new()
	repo.open(TEST_ROOT + "/world_a.db")
	check(CareerStart.populate(repo, world, 1234).is_empty(), "draft instantiates a career database")
	var orgs := repo.organisation_count()
	var players := repo.player_count()
	check(orgs == 40, "40 organisations across four tiers (%d)" % orgs)
	check(players == 40 * 5 + 16 + WorldGenerator.DEFAULT_FREE_AGENTS, "rosters + substitutes + free agents (%d players)" % players)
	var listed := repo.organisations()
	check(int((listed[0]["organisation"] as CareerRecords.OrganisationRecord).tier) == 1, "organisations list best tier first")
	var full_rosters := true
	for entry: Dictionary in listed:
		if int(entry["roster_size"]) < 5:
			full_rosters = false
	check(full_rosters, "every organisation fields at least five players")
	var top_org := listed[0]["organisation"] as CareerRecords.OrganisationRecord
	var bottom_org := listed[listed.size() - 1]["organisation"] as CareerRecords.OrganisationRecord
	var top_avg := _lineup_average(repo, top_org.id)
	var bottom_avg := _lineup_average(repo, bottom_org.id)
	check(top_avg > bottom_avg + 12.0, "tier 1 lineups are clearly stronger than amateurs (%.0f vs %.0f)" % [top_avg, bottom_avg])
	var nicknames := int(repo.db.scalar("SELECT COUNT(DISTINCT LOWER(nickname)) FROM player;", [], 0))
	check(int(nicknames) == players, "every professional has a unique nickname")
	var differ := int(repo.db.scalar("""SELECT COUNT(*) FROM player_perceived pp JOIN player_ability pa
		ON pa.player_id = pp.player_id AND pa.ability = pp.ability WHERE pa.value != pp.value;""", [], 0))
	check(differ > 0, "perceived values differ from true values (scouting uncertainty, %d)" % differ)
	var conflicts := 0
	for row: Dictionary in repo.db.rows("SELECT player_id FROM player_trait GROUP BY player_id;"):
		var ids: Array[StringName] = []
		for trait_id: StringName in repo.traits(str(row["player_id"])):
			ids.append(trait_id)
		if not TraitLibrary.compatible(ids):
			conflicts += 1
	check(conflicts == 0, "no player has conflicting traits")
	check(repo.db.integrity_check() == "ok", "generated database passes the integrity check")
	var fingerprint := world.fingerprint()
	world.close()
	repo.close()

	var other := TEST_ROOT + "/world_b.f2fdb"
	var again := WorldDatabase.new()
	check(WorldGenerator.build(other, 1234, "world_test", "Test world", "").is_empty() and again.open(other).is_empty(),
		"generator produces a second template")
	check(again.is_open() and again.fingerprint() == fingerprint, "same draft-generation seed produces the same content")
	again.close()


func _test_saves() -> void:
	section("Career saves")
	var saves := CareerSaves.new(TEST_ROOT + "/slots")
	var bad := saves.create_career("Broken", {"first_name": ""}, "", 1)
	check(not bad.is_ok() and bad.error.contains("required"), "invalid profiles are rejected before anything is written")
	var small := TEST_ROOT + "/small.f2fdb"
	check(WorldGenerator.build(small, 99, "small_test", "Small world", "", {1: 2, 2: 2, 3: 2, 4: 2}, 10).is_empty(),
		"test career uses a small standalone world")
	var session := saves.create_career("Test career", PROFILE, small, 99)
	check(session.is_ok(), "career created (%s)" % session.error)
	if not session.is_ok():
		return
	var human := session.human()
	check(human != null and human.is_human and human.nickname == "Sable", "the human professional exists")
	check(session.repo.abilities(human.id).is_empty(), "the human has perceived values only")
	check(session.repo.perceived(human.id).size() == CareerCatalog.ABILITIES.size(), "perceived values for every ability")
	check(session.repo.active_contract(human.id) == null, "the human starts as a free agent")
	check(saves.backups(session.save_id).size() == 1, "an initial backup is taken")
	session.repo.set_current_day(42)
	for i: int in CareerSaves.MAX_BACKUPS + 3:
		saves.backup(session, "test")
	check(saves.backups(session.save_id).size() == CareerSaves.MAX_BACKUPS, "backups rotate (keep %d)" % CareerSaves.MAX_BACKUPS)
	var save_id := session.save_id
	check(saves.restore_latest_backup(save_id).contains("close the career"), "restore refuses an open career")
	session.close()

	var listed := saves.list_saves()
	check(listed.size() == 1 and str(listed[0]["name"]) == "Test career" and int(listed[0]["current_day"]) == 42
		and str(listed[0]["human"]).contains("Sable"), "save list shows name, date and player (%s)" % str(listed))
	var reopened := saves.open_career(save_id)
	check(reopened.is_ok() and reopened.human_player_id == human.id and reopened.repo.current_day() == 42,
		"a career reopens with its data")
	reopened.close()

	var failure := FailingRestoreSaves.new(saves.root)
	failure.blocked_target = saves.db_path(save_id)
	var live_path := saves.db_path(save_id)
	var original_hash := FileAccess.get_sha256(live_path)
	for suffix: String in ["-wal", "-shm"]:
		var sidecar := FileAccess.open(live_path + suffix, FileAccess.WRITE)
		sidecar.store_string("simulated sidecar " + suffix)
		sidecar.close()
	check(not failure.restore_latest_backup(save_id).is_empty() and FileAccess.get_sha256(live_path) == original_hash
		and FileAccess.get_file_as_string(live_path + "-wal") == "simulated sidecar -wal"
		and FileAccess.get_file_as_string(live_path + "-shm") == "simulated sidecar -shm",
		"failed publication rolls back the original database and both sidecars")
	for suffix: String in ["-wal", "-shm"]:
		DirAccess.remove_absolute(live_path + suffix)
	var corrupt_backup := saves.save_dir(save_id) + "/backups/99999999-broken.db"
	var bad_file := FileAccess.open(corrupt_backup, FileAccess.WRITE)
	bad_file.store_string("not SQLite")
	bad_file.close()
	check(not saves.restore_latest_backup(save_id).is_empty() and FileAccess.get_sha256(live_path) == original_hash,
		"corrupt backup is refused before the live DB moves")
	DirAccess.remove_absolute(corrupt_backup)

	# Corrupt the disposable live file, then restore the latest verified snapshot.
	var live := FileAccess.open(saves.db_path(save_id), FileAccess.READ_WRITE)
	live.seek(4096)
	var junk := PackedByteArray()
	junk.resize(8192)
	junk.fill(0x5a)
	live.store_buffer(junk)
	live.close()
	var damaged := saves.open_career(save_id)
	check(not damaged.is_ok(), "a damaged save is detected (%s)" % damaged.error)
	check(saves.restore_latest_backup(save_id).is_empty(), "restore copies the newest backup in")
	var restored := saves.open_career(save_id)
	check(restored.is_ok() and restored.repo.human_players().size() == 1, "the restored career opens")
	restored.close()
	var kept := DirAccess.get_files_at(ProjectSettings.globalize_path(saves.save_dir(save_id)))
	check(Array(kept).any(func(f: String) -> bool: return f.contains(".damaged-")), "the damaged file is kept aside, not deleted")


func _test_template() -> void:
	section("Shipped world template and independent careers")
	var library := WorldDatabases.new(TEST_ROOT + "/imported")
	var world := library.open_database(WorldDatabases.default_path())
	check(world != null and world.validate().is_empty(), "default world opens and passes validation")
	if world == null:
		return
	var orgs := world.organisation_rows()
	var players := world.player_rows()
	var rosters := world.roster_rows()
	var starter_counts: Dictionary[String, int] = {}
	var regions: Dictionary[String, bool] = {}
	for org: Dictionary in orgs:
		regions[str(org["region_id"])] = true
	for row: Dictionary in rosters:
		if int(row["is_substitute"]) == 0:
			var org_id := str(row["organisation_id"])
			starter_counts[org_id] = starter_counts.get(org_id, 0) + 1
	check(orgs.size() == 40 and regions.size() == 8, "40 organisations across eight regions")
	check(players.size() == 296 and rosters.size() == 216, "296 AI professionals, 216 signed and 80 free agents")
	check(starter_counts.size() == 40 and starter_counts.values().all(func(n: int) -> bool: return n == 5),
		"every organisation has five starters and 16 players are substitutes")
	check(world.competition_count() == 19 and world.range_rows().size() == 296 * 14,
		"19 competition definitions and 14 ranges per AI player")

	var saves := CareerSaves.new(TEST_ROOT + "/independent", library)
	var a := saves.create_career("One", PROFILE, "", 120)
	var b := saves.create_career("Two", PROFILE, "", 120)
	var c := saves.create_career("Three", PROFILE, "", 121)
	check(a.is_ok() and b.is_ok() and c.is_ok(), "three independent careers start from the default template")
	if not (a.is_ok() and b.is_ok() and c.is_ok()):
		world.close()
		return
	var identities := "SELECT id, nickname FROM player WHERE is_human = 0 ORDER BY id;"
	var abilities := "SELECT player_id, ability, value FROM player_ability ORDER BY player_id, ability;"
	check(a.repo.db.rows(identities) == b.repo.db.rows(identities)
		and a.repo.db.rows(identities) == c.repo.db.rows(identities)
		and a.repo.competitions().size() == 19 and a.repo.organisation_count() == 40,
		"career seeds preserve authored identities and copy competitions")
	check(a.repo.db.rows(abilities) == b.repo.db.rows(abilities) and a.repo.db.rows(abilities) != c.repo.db.rows(abilities),
		"same seed repeats AI rolls and a different seed changes them")
	var in_range := true
	for found: Dictionary in world.range_rows():
		var value := int(a.repo.db.scalar("SELECT value FROM player_ability WHERE player_id = ? AND ability = ?;",
			[found["player_id"], found["ability"]], 0))
		if value < int(found["min_value"]) or value > int(found["max_value"]):
			in_range = false
			break
	check(in_range, "all AI abilities and potential stay within their authored ranges")
	var starters_match := true
	for org: Dictionary in orgs:
		var expected: Array = rosters.filter(func(r: Dictionary) -> bool:
			return r["organisation_id"] == org["id"] and int(r["is_substitute"]) == 0)
		var ids: Array = expected.map(func(r: Dictionary) -> String: return str(r["player_id"]))
		var lineup := a.repo.lineup(str(org["id"]))
		if lineup.size() != 5 or not lineup.all(func(r: Dictionary) -> bool: return ids.has(r["player_id"])):
			starters_match = false
			break
	check(starters_match, "every career lineup contains the authored starting five")
	a.repo.set_current_day(42)
	check(b.repo.current_day() == 0 and a.repo.meta_value("career_seed") == "120"
		and a.repo.abilities(a.human_player_id).is_empty(), "the seed is recorded and careers evolve independently")
	a.close()
	b.close()
	c.close()
	world.close()


func _test_migration_failures() -> void:
	section("Real v1 career and migration failure")
	var saves := CareerSaves.new(TEST_ROOT + "/migration")
	var save_id := "sav_v1"
	DirAccess.make_dir_recursive_absolute(saves.save_dir(save_id))
	var path := saves.db_path(save_id)
	var db := CareerDatabase.new()
	db.open(path)
	var v1: Array[PackedStringArray] = [CareerSchema.MIGRATIONS[0]]
	check(CareerDatabase.apply_migrations(db, v1, "test save").is_empty(), "creates a v1 career fixture")
	db.close()
	var legacy := CareerRepository.new()
	legacy.db.open(path)
	legacy.set_meta_value("format", CareerSchema.FORMAT)
	legacy.seed_reference_data()
	var human := HumanCareer.create(legacy, PROFILE, 1, 42)
	legacy.set_current_day(19)
	legacy.close()

	var blocking := FileAccess.open(saves.save_dir(save_id) + "/backups", FileAccess.WRITE)
	blocking.store_string("block backup directory creation")
	blocking.close()
	var aborted := saves.open_career(save_id)
	check(not aborted.is_ok() and aborted.error.contains("pre-migration backup"), "failed backup aborts migration")
	db.open(path)
	check(db.user_version() == 1 and db.integrity_check() == "ok", "the original remains a valid v1 database")
	check(db.execute("CREATE TABLE competition (test INTEGER);"), "creates a conflict for the v2 migration")
	db.close()
	DirAccess.remove_absolute(saves.save_dir(save_id) + "/backups")
	var failed_migration := saves.open_career(save_id)
	check(not failed_migration.is_ok() and failed_migration.error.contains("migration"), "migration errors reach the caller")
	db.open(path)
	check(db.user_version() == 1 and db.integrity_check() == "ok" and saves.backups(save_id).size() == 1,
		"failed migration keeps the v1 file and a verified backup")
	db.execute("DROP TABLE competition;")
	db.close()

	var migrated := saves.open_career(save_id)
	check(migrated.is_ok() and migrated.repo.db.user_version() == 2
		and migrated.human_player_id == human and migrated.repo.current_day() == 19,
		"legacy v1 data is preserved after a successful v2 migration")
	migrated.close()


func _test_import() -> void:
	section("World template imports")
	var library := WorldDatabases.new(TEST_ROOT + "/world_library")
	var source := TEST_ROOT + "/community.f2fdb"
	check(WorldGenerator.build(source, 13, "community_test", "Community", "", {1: 2}, 0).is_empty(),
		"creates an independent community template")
	var imported := library.import_database(source)
	var target := str(imported["path"])
	check(not target.is_empty() and FileAccess.file_exists(target), "valid community template is imported")
	if target.is_empty():
		return
	var hash := FileAccess.get_sha256(target)
	check(bool(library.import_database(source)["requires_confirmation"]), "replacement must be confirmed")
	DirAccess.make_dir_absolute(target + ".bak")
	var blocked := library.import_database(source, true)
	check(not str(blocked["error"]).is_empty() and FileAccess.get_sha256(target) == hash,
		"failed template replacement preserves the previous installed file")
	DirAccess.remove_absolute(target + ".bak")

	var db := CareerDatabase.new()
	db.open(source, false, false)
	db.execute("UPDATE meta SET value = 'Updated Community' WHERE key = 'name';")
	db.close()
	var updated := library.import_database(source, true)
	check(bool(updated["replaced"]) and FileAccess.get_sha256(target + ".bak") == hash
		and FileAccess.get_sha256(target) != hash, "confirmed replacement publishes new data and retains the original")

	db.open(source, false, false)
	db.execute("PRAGMA foreign_keys = OFF;")
	db.execute("INSERT INTO roster VALUES ('ply_ghost', 'org_ghost', 'rifler', 0, 0, 0, 365);")
	db.close()
	check(str(library.import_database(source, true)["error"]).contains("foreign keys"), "template import rejects orphaned records")
	db.open(source, false, false)
	db.execute("DELETE FROM roster WHERE player_id = 'ply_ghost';")
	db.execute("UPDATE meta SET value = 'bad/id' WHERE key = 'database_id';")
	db.close()
	check(str(library.import_database(source, true)["error"]).contains("invalid ID"), "template import rejects unsafe IDs")


func _player(id: String, nickname: String, human: bool) -> CareerRecords.PlayerRecord:
	var p := CareerRecords.PlayerRecord.new()
	p.id = id
	p.first_name = "Test"
	p.last_name = nickname
	p.nickname = nickname
	p.nation_id = "gb"
	p.birth_day = -7000
	p.is_human = human
	return p


func _lineup_average(repo: CareerRepository, org_id: String) -> float:
	var total := 0.0
	var count := 0
	for entry: Dictionary in repo.lineup(org_id):
		for value: Variant in (entry["abilities"] as Dictionary).values():
			total += float(value)
			count += 1
	return total / maxf(count, 1)


func _clean(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	for sub: String in DirAccess.get_directories_at(absolute):
		_clean(path.path_join(sub))
	DirAccess.remove_absolute(absolute)
