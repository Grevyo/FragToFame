class_name CareerDbSuite
extends TestSuite
## Milestone 9: career database — schema/migrations, repository, stat-layer separation, world
## generation, human creation, saves, backups, damage detection and restore.

const TEST_ROOT: String = "user://tests/careers"


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
	var repo := CareerRepository.new()
	repo.open(TEST_ROOT + "/world_a.db")
	var started := Time.get_ticks_msec()
	var error := WorldGenerator.new(repo, 1234).generate()
	var elapsed := Time.get_ticks_msec() - started
	check(error.is_empty(), "default world generates (%d ms) %s" % [elapsed, error])
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
	var first_ids := repo.db.rows("SELECT id, nickname FROM player ORDER BY id LIMIT 5;")
	repo.close()

	var again := CareerRepository.new()
	again.open(TEST_ROOT + "/world_b.db")
	WorldGenerator.new(again, 1234).generate()
	check(again.db.rows("SELECT id, nickname FROM player ORDER BY id LIMIT 5;") == first_ids, "same seed → same world")
	again.close()


func _test_saves() -> void:
	section("Career saves")
	var saves := CareerSaves.new(TEST_ROOT + "/slots")
	var bad := saves.create_career("Broken", 1, {"first_name": ""})
	check(not bad.is_ok() and bad.error.contains("required"), "invalid profiles are rejected before anything is written")
	var profile := {"first_name": "Rowan", "last_name": "Hartley", "nickname": "Sable", "nation_id": "gb",
		"preferred_role": &"rifler", "difficulty": &"standard", "age": 19}
	var small := {"tier_counts": {1: 2, 2: 2, 3: 2, 4: 2}, "free_agents": 10}
	var session := saves.create_career("Test career", 99, profile, small)
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
	session.close()

	var listed := saves.list_saves()
	check(listed.size() == 1 and str(listed[0]["name"]) == "Test career" and int(listed[0]["current_day"]) == 42
		and str(listed[0]["human"]).contains("Sable"), "save list shows name, date and player (%s)" % str(listed))
	var reopened := saves.open_career(save_id)
	check(reopened.is_ok() and reopened.human_player_id == human.id and reopened.repo.current_day() == 42,
		"a career reopens with its data")
	reopened.close()

	# Corrupt the live file: integrity check catches it, restore brings back the latest backup.
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
