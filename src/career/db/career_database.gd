class_name CareerDatabase
extends RefCounted
## The only class that talks to SQLite (godot-sqlite). Everything else in the career layer goes
## through [CareerRepository], so the storage engine stays an implementation detail.
##
## Connections run with foreign keys on, WAL journalling (crash-safe, readers don't block the
## writer) and every multi-row change inside [method transaction].

var path: String = ""
## Last SQLite error message ("" when the last statement succeeded).
var last_error: String = ""
## Number of statements executed (diagnostics / tests).
var statement_count: int = 0

static var _open_writers: Dictionary[String, Array] = {}

var _db: SQLite = null
var _writer_path: String = ""
var _transaction_depth: int = 0
var _transaction_failed: bool = false


## Opens (creating if needed) the database file at [param db_path]. [param read_only] opens an
## existing file without write access. [param wal] selects WAL journalling (live saves); world
## databases use a classic rollback journal so they stay one self-contained, shareable file.
func open(db_path: String, read_only: bool = false, wal: bool = true) -> bool:
	close()
	path = db_path
	_db = SQLite.new()
	_db.path = db_path
	_db.read_only = read_only
	_db.verbosity_level = SQLite.QUIET
	if not _db.open_db():
		last_error = "could not open %s: %s" % [db_path, _db.error_message]
		_db = null
		return false
	if not execute("PRAGMA foreign_keys = ON;") or (not read_only and (
			not execute("PRAGMA journal_mode = WAL;" if wal else "PRAGMA journal_mode = DELETE;")
			or not execute("PRAGMA synchronous = NORMAL;"))):
		close()
		return false
	if not read_only:
		_writer_path = _path_key(db_path)
		has_open_writer(_writer_path) # Discard expired references before adding this writer.
		if not _open_writers.has(_writer_path):
			_open_writers[_writer_path] = []
		_open_writers[_writer_path].append(get_instance_id())
	return true


static func has_open_writer(db_path: String) -> bool:
	var key := _path_key(db_path)
	if not _open_writers.has(key):
		return false
	var writers: Array = _open_writers[key]
	var active := writers.filter(func(id: int) -> bool: return is_instance_id_valid(id))
	if active.is_empty():
		_open_writers.erase(key)
		return false
	_open_writers[key] = active
	return true


static func _path_key(db_path: String) -> String:
	var absolute := ProjectSettings.globalize_path(db_path).simplify_path()
	return absolute.to_lower() if OS.get_name() == "Windows" else absolute


func is_open() -> bool:
	return _db != null


func close() -> void:
	if _db != null:
		_db.close_db()
		_db = null
	if not _writer_path.is_empty():
		var writers: Array = _open_writers[_writer_path]
		writers.erase(get_instance_id())
		if writers.is_empty():
			_open_writers.erase(_writer_path)
		_writer_path = ""
	_transaction_depth = 0


## Runs a statement that returns no rows. Returns success; on failure [member last_error] is set
## and an enclosing [method transaction] is rolled back.
func execute(sql: String, bindings: Array = []) -> bool:
	if _db == null:
		last_error = "database not open"
		return false
	statement_count += 1
	var ok := _db.query_with_bindings(sql, bindings) if not bindings.is_empty() else _db.query(sql)
	last_error = "" if ok else _db.error_message
	if not ok and _transaction_depth > 0:
		_transaction_failed = true
	return ok


## Runs a query and returns its rows (empty on failure; check [member last_error]).
func rows(sql: String, bindings: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not execute(sql, bindings):
		return result
	for row: Variant in _db.query_result:
		result.append(row as Dictionary)
	return result


## First row of a query, or an empty Dictionary.
func row(sql: String, bindings: Array = []) -> Dictionary:
	var found := rows(sql, bindings)
	return found[0] if not found.is_empty() else {}


## First column of the first row, or [param fallback].
func scalar(sql: String, bindings: Array = [], fallback: Variant = null) -> Variant:
	var first := row(sql, bindings)
	if first.is_empty():
		return fallback
	return first.values()[0]


func last_insert_rowid() -> int:
	return _db.last_insert_rowid if _db != null else 0


## Runs [param work] (a Callable returning bool) atomically. Commits when it returns true and no
## statement failed; otherwise rolls back every change. Nested calls join the outer transaction.
func transaction(work: Callable) -> bool:
	if _db == null:
		return false
	if _transaction_depth > 0:
		_transaction_depth += 1
		var nested_ok: bool = work.call()
		_transaction_depth -= 1
		if not nested_ok:
			_transaction_failed = true
		return nested_ok and not _transaction_failed
	if not execute("BEGIN IMMEDIATE TRANSACTION;"):
		return false
	_transaction_depth = 1
	_transaction_failed = false
	var ok: bool = work.call()
	_transaction_depth = 0
	if ok and not _transaction_failed:
		if execute("COMMIT;"):
			return true
	var error := last_error
	execute("ROLLBACK;")
	last_error = error
	return false


## Schema version stored in the database header (PRAGMA user_version).
func user_version() -> int:
	return int(scalar("PRAGMA user_version;", [], 0))


func set_user_version(version: int) -> bool:
	return execute("PRAGMA user_version = %d;" % version)


## Writes a consistent copy of the live database to [param target_path] (works while open).
func backup_to(target_path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(target_path)
	if FileAccess.file_exists(target_path):
		last_error = "backup destination already exists"
		return false
	return execute("VACUUM INTO ?;", [absolute])


## SQLite's own structural check. Returns "ok" when the file is healthy.
func integrity_check() -> String:
	return str(scalar("PRAGMA integrity_check;", [], "unreadable"))


func foreign_keys_are_valid() -> bool:
	var violations := rows("PRAGMA foreign_key_check;")
	return last_error.is_empty() and violations.is_empty()


## Brings [param db] from its `user_version` up to `migrations.size()`: entry N upgrades N → N+1
## inside one transaction, so a file is never half-migrated. Refuses files from a newer build.
## [param kind] names the file type in errors ("save", "world database").
static func apply_migrations(db: CareerDatabase, migrations: Array[PackedStringArray], kind: String) -> String:
	var current := migrations.size()
	var version := db.user_version()
	if version > current:
		return "this %s was made by a newer version of Frag to Fame (schema %d > %d)" % [kind, version, current]
	while version < current:
		var statements: PackedStringArray = migrations[version]
		var target := version + 1
		var ok := db.transaction(func() -> bool:
			for sql: String in statements:
				if not db.execute(sql):
					return false
			return db.set_user_version(target))
		if not ok:
			return "%s migration to schema %d failed: %s" % [kind, target, db.last_error]
		version = target
	return ""
