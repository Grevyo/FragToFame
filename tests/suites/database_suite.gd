class_name DatabaseSuite
extends TestSuite
## Milestone 9 groundwork: the godot-sqlite GDExtension loads and behaves as the career database
## needs: file databases, parameter bindings, transactions with rollback, foreign keys, reopen.

const TEST_DB_PATH: String = "user://tests/sqlite_smoke.db"


func suite_name() -> String:
	return "SQLite engine (godot-sqlite)"


func run() -> void:
	section("Extension")
	check(ClassDB.class_exists(&"SQLite"), "the SQLite class is registered by the GDExtension")
	if not ClassDB.class_exists(&"SQLite"):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	_remove_db()

	var db := SQLite.new()
	db.path = TEST_DB_PATH
	db.verbosity_level = SQLite.QUIET
	check(db.open_db(), "opens a file database in user://")
	check(db.query("PRAGMA foreign_keys = ON;"), "foreign keys can be enabled")

	section("Schema and bindings")
	check(db.query("CREATE TABLE team (id TEXT PRIMARY KEY, name TEXT NOT NULL);"), "creates a table")
	check(db.query("CREATE TABLE player (id TEXT PRIMARY KEY, name TEXT NOT NULL, aim INTEGER, "
		+ "team_id TEXT REFERENCES team(id));"), "creates a table with a foreign key")
	check(db.query_with_bindings("INSERT INTO team (id, name) VALUES (?, ?);", ["org_test", "Test Org"]),
		"inserts with bindings")
	db.query_with_bindings("INSERT INTO player (id, name, aim, team_id) VALUES (?, ?, ?, ?);",
		["ply_a", "O'Quote \"Name\"", 74, "org_test"])
	check(db.query_with_bindings("SELECT name, aim FROM player WHERE id = ?;", ["ply_a"])
		and db.query_result.size() == 1 and str(db.query_result[0]["name"]) == "O'Quote \"Name\""
		and int(db.query_result[0]["aim"]) == 74, "bindings round-trip awkward strings and integers")
	var orphan := db.query_with_bindings("INSERT INTO player (id, name, team_id) VALUES (?, ?, ?);",
		["ply_b", "Orphan", "org_missing"])
	check(not orphan, "foreign key violations are rejected")

	section("Transactions")
	db.query("BEGIN TRANSACTION;")
	db.query_with_bindings("INSERT INTO player (id, name, team_id) VALUES (?, ?, ?);", ["ply_c", "Rolled back", "org_test"])
	db.query("ROLLBACK;")
	db.query("SELECT COUNT(*) AS n FROM player;")
	check(int(db.query_result[0]["n"]) == 1, "rollback discards the transaction's writes")
	db.query("BEGIN TRANSACTION;")
	for i: int in 500:
		db.query_with_bindings("INSERT INTO player (id, name, aim, team_id) VALUES (?, ?, ?, ?);",
			["ply_bulk_%d" % i, "Bulk %d" % i, i % 100, "org_test"])
	db.query("COMMIT;")
	db.query("SELECT COUNT(*) AS n FROM player;")
	check(int(db.query_result[0]["n"]) == 501, "commit keeps a 500-row batch")
	db.close_db()

	section("Persistence")
	var reopened := SQLite.new()
	reopened.path = TEST_DB_PATH
	reopened.verbosity_level = SQLite.QUIET
	check(reopened.open_db(), "reopens the database file")
	reopened.query("SELECT COUNT(*) AS n FROM player WHERE aim >= 50;")
	check(int(reopened.query_result[0]["n"]) == 251, "data survives closing and reopening (250 bulk + 1 earlier row)")
	reopened.close_db()
	_remove_db()


func _remove_db() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_DB_PATH)
	if FileAccess.file_exists(TEST_DB_PATH):
		DirAccess.remove_absolute(absolute)
