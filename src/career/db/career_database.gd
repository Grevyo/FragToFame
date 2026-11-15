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

var _db: SQLite = null
var _transaction_depth: int = 0
var _transaction_failed: bool = false


## Opens (creating if needed) the database file at [param db_path]. [param read_only] opens an
## existing file without write access (used to read save metadata cheaply).
func open(db_path: String, read_only: bool = false) -> bool:
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
	execute("PRAGMA foreign_keys = ON;")
	if not read_only:
		execute("PRAGMA journal_mode = WAL;")
		execute("PRAGMA synchronous = NORMAL;")
	return true


func is_open() -> bool:
	return _db != null


func close() -> void:
	if _db != null:
		_db.close_db()
		_db = null
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
		DirAccess.remove_absolute(absolute)
	return execute("VACUUM INTO ?;", [absolute])


## SQLite's own structural check. Returns "ok" when the file is healthy.
func integrity_check() -> String:
	return str(scalar("PRAGMA integrity_check;", [], "unreadable"))
