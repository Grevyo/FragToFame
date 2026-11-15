class_name CareerSaves
extends RefCounted
## Career save slots on disk. Each career is a folder:
##
##   user://careers/<save_id>/career.db          the live SQLite world (WAL mode)
##   user://careers/<save_id>/backups/*.db       rotating consistent snapshots (VACUUM INTO)
##
## [CareerStart] initialises each new save from a fixed world database ([WorldDatabases]).
##
## Safety: a snapshot is taken after creation, before every schema migration and on demand;
## a damaged database is never deleted — restoring moves it aside and copies the newest backup in.

const ROOT: String = "user://careers"
const DB_FILE: String = "career.db"
const BACKUP_DIR: String = "backups"
const MAX_BACKUPS: int = 8

## Overridable root (tests use their own folder).
var root: String = ROOT
var databases: WorldDatabases


func _init(root_path: String = ROOT, library: WorldDatabases = null) -> void:
	root = root_path
	databases = library if library != null else WorldDatabases.new()


func save_dir(save_id: String) -> String:
	return "%s/%s" % [root, save_id]


func db_path(save_id: String) -> String:
	return "%s/%s" % [save_dir(save_id), DB_FILE]


## Creates a new career from the world database at [param database_path] ("" = the shipped
## default), creates the human professional and snapshots the new save.
func create_career(save_name: String, human_profile: Dictionary, database_path: String = "") -> CareerSession:
	var session := CareerSession.new()
	var problems := HumanCareer.validate(human_profile)
	if save_name.strip_edges().is_empty():
		problems.push_front("career name is required")
	if not problems.is_empty():
		session.error = "; ".join(problems)
		return session
	var errors: Array[String] = []
	var world := databases.open_database(WorldDatabases.default_path() if database_path.is_empty() else database_path, errors)
	if world == null:
		session.error = "could not open the world database: %s" % "; ".join(errors)
		return session
	var problems_with_world := world.validate()
	if not problems_with_world.is_empty():
		world.close()
		session.error = "Invalid world database: %s" % "; ".join(problems_with_world)
		return session
	var save_id := Ids.generate("sav")
	var created := DirAccess.make_dir_recursive_absolute(save_dir(save_id))
	if created != OK:
		world.close()
		session.error = "Could not create the career folder: %s" % error_string(created)
		return session
	var repo := CareerRepository.new()
	var error := repo.open(db_path(save_id))
	if error.is_empty():
		error = CareerStart.populate(repo, world)
	world.close()
	if error.is_empty():
		repo.set_meta_value("save_name", save_name.strip_edges())
		repo.set_meta_value("world_id", Ids.generate("wld"))
		repo.set_meta_value("created_unix", int(Time.get_unix_time_from_system()))
		var human_id := HumanCareer.create(repo, human_profile, 1, errors)
		if human_id.is_empty():
			error = "; ".join(errors)
		else:
			session.human_player_id = human_id
	if not error.is_empty():
		repo.close()
		session.error = error
		return session
	session.save_id = save_id
	session.repo = repo
	if backup(session, "created").is_empty():
		session.warning = "Career created, but its initial backup could not be written."
	return session


## Summaries of every save, newest first: {save_id, name, current_day, human, database,
## modified_unix, schema, error}.
func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return saves
	for save_id: String in dir.get_directories():
		var path := db_path(save_id)
		if not FileAccess.file_exists(path):
			if not backups(save_id).is_empty():
				saves.append({"save_id": save_id, "name": save_id, "current_day": 0, "human": "",
					"database": "", "modified_unix": 0, "schema": 0, "error": "Missing live database"})
			continue
		var summary := {"save_id": save_id, "name": save_id, "current_day": 0, "human": "", "database": "",
			"modified_unix": FileAccess.get_modified_time(path), "schema": 0, "error": ""}
		var db := CareerDatabase.new()
		# Normal open: godot-sqlite's read-only mode does not see data still in the WAL file.
		if db.open(path):
			summary["schema"] = db.user_version()
			if int(summary["schema"]) >= 1:
				summary["name"] = str(db.scalar("SELECT value FROM meta WHERE key = 'save_name';", [], save_id))
				summary["current_day"] = int(str(db.scalar("SELECT value FROM meta WHERE key = 'current_day';", [], "0")))
				summary["database"] = str(db.scalar("SELECT value FROM meta WHERE key = 'database_name';", [], ""))
				summary["human"] = str(db.scalar("""SELECT p.first_name || ' "' || p.nickname || '" ' || p.last_name
					FROM player p JOIN human_profile h ON h.player_id = p.id ORDER BY h.slot LIMIT 1;""", [], ""))
			db.close()
		else:
			summary["error"] = db.last_error
		saves.append(summary)
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["modified_unix"]) > int(b["modified_unix"]))
	return saves


## Opens a career. Checks integrity, snapshots before migrating an older schema.
func open_career(save_id: String) -> CareerSession:
	var session := CareerSession.new()
	if not Ids.is_file_id(save_id):
		session.error = "invalid save ID"
		return session
	var path := db_path(save_id)
	if not FileAccess.file_exists(path):
		session.error = "save not found"
		if not backups(save_id).is_empty():
			session.error = "the live save is missing or damaged; restore a backup"
			session.damaged = true
		return session
	var probe := CareerDatabase.new()
	if not probe.open(path):
		session.error = probe.last_error
		if not backups(save_id).is_empty():
			session.error += " (if damaged, close any other game instance before restoring a backup)"
		return session
	var integrity := probe.integrity_check()
	var version := probe.user_version()
	if integrity == "ok" and version > 0 and version < CareerSchema.CURRENT_VERSION:
		if _snapshot(probe, save_id, "pre_schema_%d" % version).is_empty():
			probe.close()
			session.error = "Migration cancelled because the pre-migration backup could not be verified."
			return session
	probe.close()
	if integrity != "ok":
		session.error = "the save is damaged (%s); restore a backup" % integrity
		session.damaged = true
		return session
	var repo := CareerRepository.new()
	var error := repo.open(path)
	if not error.is_empty():
		session.error = error
		return session
	session.save_id = save_id
	session.repo = repo
	var humans := repo.human_players()
	session.human_player_id = humans[0].id if not humans.is_empty() else ""
	return session


## Snapshots an open session. Returns the backup path ("" on failure).
func backup(session: CareerSession, reason: String = "manual") -> String:
	if session == null or session.repo == null:
		return ""
	return _snapshot(session.repo.db, session.save_id, reason)


## Backups of a save, newest first (resource paths).
func backups(save_id: String) -> Array[String]:
	var list: Array[String] = []
	var folder := "%s/%s" % [save_dir(save_id), BACKUP_DIR]
	var dir := DirAccess.open(folder)
	if dir == null:
		return list
	for file: String in dir.get_files():
		if file.ends_with(".db"):
			list.append("%s/%s" % [folder, file])
	list.sort()
	list.reverse()
	return list


## Stages and verifies the backup before changing the live SQLite file set.
func restore_latest_backup(save_id: String) -> String:
	if not Ids.is_file_id(save_id):
		return "invalid save ID"
	var live := db_path(save_id)
	if CareerDatabase.has_open_writer(live):
		return "close the career before restoring a backup"
	var available := backups(save_id)
	if available.is_empty():
		return "no backups exist for this save"
	var staged := live + "." + Ids.generate("restore") + ".db"
	var source := available[0]
	for suffix: String in ["-wal", "-shm", "-journal"]:
		if FileAccess.file_exists(source + suffix):
			return "the latest backup is not a standalone snapshot"
	var copied := DirAccess.copy_absolute(source, staged)
	if copied != OK or FileAccess.get_sha256(staged) != FileAccess.get_sha256(source):
		DirAccess.remove_absolute(staged)
		return "could not stage the backup: %s" % error_string(copied) if copied != OK else "backup copy failed verification"
	var error := _check_snapshot(staged)
	if not error.is_empty():
		DirAccess.remove_absolute(staged)
		return "the latest backup is unusable: " + error

	var archive := live + ".damaged-" + Ids.generate("original")
	var moved: Array[String] = []
	for suffix: String in ["", "-wal", "-shm", "-journal"]:
		if FileAccess.file_exists(live + suffix):
			var status := _move_file(live + suffix, archive + suffix)
			if status != OK:
				error = "could not preserve the original save file set: %s" % error_string(status)
				break
			moved.append(suffix)
	if error.is_empty():
		var installed := _move_file(staged, live)
		if installed == OK:
			return ""
		error = "could not install the backup: %s" % error_string(installed)
	moved.reverse()
	for suffix: String in moved:
		if _move_file(archive + suffix, live + suffix) != OK:
			error += "\nOriginal file retained at %s." % (archive + suffix)
	DirAccess.remove_absolute(staged)
	return error


func _move_file(source: String, target: String) -> Error:
	if FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
		return ERR_ALREADY_EXISTS
	return DirAccess.rename_absolute(source, target)


## VACUUM INTO produces a standalone SQLite file, which can be checked read-only.
func _check_snapshot(path: String) -> String:
	var probe := CareerDatabase.new()
	if not probe.open(path, true):
		return probe.last_error
	var version := probe.user_version()
	var error := ""
	if version < 1 or version > CareerSchema.CURRENT_VERSION:
		error = "unsupported career schema %d" % version
	elif probe.integrity_check() != "ok" or not probe.foreign_keys_are_valid():
		error = "SQLite integrity or foreign-key check failed"
	elif str(probe.scalar("SELECT value FROM meta WHERE key = 'format';", [], "")) != CareerSchema.FORMAT:
		error = "not a Frag to Fame career"
	elif int(probe.scalar("SELECT COUNT(*) FROM human_profile;", [], 0)) == 0:
		error = "no human career profile"
	probe.close()
	return error


func _snapshot(db: CareerDatabase, save_id: String, reason: String) -> String:
	var folder := "%s/%s" % [save_dir(save_id), BACKUP_DIR]
	var made := DirAccess.make_dir_recursive_absolute(folder)
	if made != OK and not DirAccess.dir_exists_absolute(folder):
		return ""
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var path := "%s/%s_%s_%s.db" % [folder, stamp, Ids.generate("snapshot"), reason.validate_filename()]
	# VACUUM INTO may need room for a journal suffix on Windows.
	var staged := "%s/%s.tmp" % [folder, Ids.generate("snap").right(16)]
	if not db.backup_to(staged):
		push_warning("CareerSaves: backup failed: %s" % db.last_error)
		return ""
	var problem := _check_snapshot(staged)
	if problem.is_empty():
		var installed := _move_file(staged, path)
		if installed == OK:
			_rotate(save_id)
			return path
		problem = error_string(installed)
	DirAccess.remove_absolute(staged)
	push_warning("CareerSaves: backup failed: %s" % problem)
	return ""


func _rotate(save_id: String) -> void:
	var existing := backups(save_id)
	for i: int in range(MAX_BACKUPS, existing.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(existing[i]))
