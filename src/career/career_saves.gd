class_name CareerSaves
extends RefCounted
## Career save slots on disk. Each career is a folder:
##
##   user://careers/<save_id>/career.db          the live SQLite world (WAL mode)
##   user://careers/<save_id>/backups/*.db       rotating consistent snapshots (VACUUM INTO)
##
## Safety: a snapshot is taken after creation, before every schema migration and on demand;
## a damaged database is never deleted — restoring moves it aside and copies the newest backup in.

const ROOT: String = "user://careers"
const DB_FILE: String = "career.db"
const BACKUP_DIR: String = "backups"
const MAX_BACKUPS: int = 8

## Overridable root (tests use their own folder).
var root: String = ROOT


func _init(root_path: String = ROOT) -> void:
	root = root_path


func save_dir(save_id: String) -> String:
	return "%s/%s" % [root, save_id]


func db_path(save_id: String) -> String:
	return "%s/%s" % [save_dir(save_id), DB_FILE]


## Creates a new career: generates the world, creates the human professional, snapshots it.
## Returns a [CareerSession] (check [member CareerSession.error]).
func create_career(save_name: String, world_seed: int, human_profile: Dictionary,
		generator_options: Dictionary = {}) -> CareerSession:
	var session := CareerSession.new()
	var problems := HumanCareer.validate(human_profile)
	if save_name.strip_edges().is_empty():
		problems.push_front("career name is required")
	if not problems.is_empty():
		session.error = "; ".join(problems)
		return session
	var save_id := Ids.generate("sav")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir(save_id)))
	var repo := CareerRepository.new()
	var error := repo.open(db_path(save_id))
	if error.is_empty():
		var generator := WorldGenerator.new(repo, world_seed)
		if generator_options.has("tier_counts"):
			generator.tier_counts.clear()
			var counts: Dictionary = generator_options["tier_counts"]
			for tier: Variant in counts:
				generator.tier_counts[int(tier)] = int(counts[tier])
		if generator_options.has("free_agents"):
			generator.free_agents = int(generator_options["free_agents"])
		error = generator.generate()
	if error.is_empty():
		repo.set_meta_value("save_name", save_name.strip_edges())
		repo.set_meta_value("world_id", Ids.generate("wld"))
		repo.set_meta_value("seed", world_seed)
		repo.set_meta_value("created_unix", int(Time.get_unix_time_from_system()))
		var errors: Array[String] = []
		var human_id := HumanCareer.create(repo, human_profile, 1, world_seed ^ 0x5eed, errors)
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
	backup(session, "created")
	return session


## Summaries of every save, newest first: {save_id, name, current_day, human, modified_unix,
## schema, error}.
func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return saves
	for save_id: String in dir.get_directories():
		var path := db_path(save_id)
		if not FileAccess.file_exists(path):
			continue
		var summary := {"save_id": save_id, "name": save_id, "current_day": 0, "human": "",
			"modified_unix": FileAccess.get_modified_time(path), "schema": 0, "error": ""}
		var db := CareerDatabase.new()
		# Normal open: godot-sqlite's read-only mode does not see data still in the WAL file.
		if db.open(path):
			summary["schema"] = db.user_version()
			if int(summary["schema"]) >= 1:
				summary["name"] = str(db.scalar("SELECT value FROM meta WHERE key = 'save_name';", [], save_id))
				summary["current_day"] = int(str(db.scalar("SELECT value FROM meta WHERE key = 'current_day';", [], "0")))
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
	var path := db_path(save_id)
	if not FileAccess.file_exists(path):
		session.error = "save not found"
		return session
	var probe := CareerDatabase.new()
	if not probe.open(path):
		session.error = probe.last_error
		return session
	var integrity := probe.integrity_check()
	var version := probe.user_version()
	if integrity == "ok" and version > 0 and version < CareerSchema.CURRENT_VERSION:
		_snapshot(probe, save_id, "pre_schema_%d" % version)
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


## Replaces a (damaged) live database with the newest backup. The old file is kept beside it as
## career.db.damaged-<time>. Returns "" on success.
func restore_latest_backup(save_id: String) -> String:
	var available := backups(save_id)
	if available.is_empty():
		return "no backups exist for this save"
	var live := ProjectSettings.globalize_path(db_path(save_id))
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	if FileAccess.file_exists(db_path(save_id)):
		var moved := DirAccess.rename_absolute(live, "%s.damaged-%s" % [live, stamp])
		if moved != OK:
			return "could not move the damaged save aside (error %d)" % moved
	for suffix: String in ["-wal", "-shm"]:
		if FileAccess.file_exists(db_path(save_id) + suffix):
			DirAccess.rename_absolute(live + suffix, "%s%s.damaged-%s" % [live, suffix, stamp])
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(available[0]), live)
	return "" if copied == OK else "could not copy the backup (error %d)" % copied


func _snapshot(db: CareerDatabase, save_id: String, reason: String) -> String:
	var folder := "%s/%s" % [save_dir(save_id), BACKUP_DIR]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "")
	var path := "%s/%s_%03d_%s.db" % [folder, stamp, Time.get_ticks_msec() % 1000, reason.validate_filename()]
	if not db.backup_to(path):
		push_warning("CareerSaves: backup failed: %s" % db.last_error)
		return ""
	_rotate(save_id)
	return path


func _rotate(save_id: String) -> void:
	var existing := backups(save_id)
	for i: int in range(MAX_BACKUPS, existing.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(existing[i]))
