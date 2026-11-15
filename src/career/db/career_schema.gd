class_name CareerSchema
extends RefCounted
## Versioned schema of the career database. The version lives in SQLite's `user_version` header;
## each entry of [constant MIGRATIONS] upgrades version N-1 → N inside one transaction, so saves
## from older builds are upgraded in place (after a backup) and never half-migrated.
##
## Stat layers are separate tables, never mixed:
##   player_ability     true simulated abilities (AI players only; never exists for humans)
##   player_perceived   what scouts / the public believe (every player, incl. humans)
##   player_reputation  career standing
##   (recorded match statistics and calculated ratings arrive with Milestone 11)

const FORMAT: String = "f2f.career_db"
const CURRENT_VERSION: int = 3

const MIGRATIONS: Array[PackedStringArray] = [
	# v1 — world, organisations, players, abilities, perception, reputation, traits, contracts.
	[
		"""CREATE TABLE meta (
			key TEXT PRIMARY KEY,
			value TEXT NOT NULL
		);""",
		"""CREATE TABLE region (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL
		);""",
		"""CREATE TABLE nation (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			region_id TEXT NOT NULL REFERENCES region(id)
		);""",
		"""CREATE TABLE organisation (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			short_name TEXT NOT NULL,
			region_id TEXT NOT NULL REFERENCES region(id),
			tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 4),
			founded_day INTEGER NOT NULL,
			colour TEXT NOT NULL,
			active INTEGER NOT NULL DEFAULT 1
		);""",
		"""CREATE TABLE player (
			id TEXT PRIMARY KEY,
			first_name TEXT NOT NULL,
			last_name TEXT NOT NULL,
			nickname TEXT NOT NULL,
			nation_id TEXT NOT NULL REFERENCES nation(id),
			birth_day INTEGER NOT NULL,
			preferred_role TEXT NOT NULL,
			is_human INTEGER NOT NULL DEFAULT 0,
			status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'retired')),
			created_day INTEGER NOT NULL
		);""",
		"CREATE INDEX player_nickname ON player(nickname COLLATE NOCASE);",
		"""CREATE TABLE player_ability (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			ability TEXT NOT NULL,
			value INTEGER NOT NULL CHECK (value BETWEEN 1 AND 100),
			PRIMARY KEY (player_id, ability)
		) WITHOUT ROWID;""",
		"""CREATE TABLE player_perceived (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			ability TEXT NOT NULL,
			value INTEGER NOT NULL CHECK (value BETWEEN 1 AND 100),
			confidence INTEGER NOT NULL CHECK (confidence BETWEEN 0 AND 100),
			updated_day INTEGER NOT NULL,
			PRIMARY KEY (player_id, ability)
		) WITHOUT ROWID;""",
		"""CREATE TABLE player_reputation (
			player_id TEXT PRIMARY KEY REFERENCES player(id) ON DELETE CASCADE,
			value INTEGER NOT NULL CHECK (value BETWEEN 0 AND 100),
			updated_day INTEGER NOT NULL
		);""",
		"""CREATE TABLE organisation_reputation (
			organisation_id TEXT PRIMARY KEY REFERENCES organisation(id) ON DELETE CASCADE,
			value INTEGER NOT NULL CHECK (value BETWEEN 0 AND 100),
			updated_day INTEGER NOT NULL
		);""",
		"""CREATE TABLE player_trait (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			trait_id TEXT NOT NULL,
			strength INTEGER NOT NULL CHECK (strength BETWEEN 1 AND 3),
			PRIMARY KEY (player_id, trait_id)
		) WITHOUT ROWID;""",
		"""CREATE TABLE contract (
			id TEXT PRIMARY KEY,
			player_id TEXT NOT NULL REFERENCES player(id),
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			role TEXT NOT NULL,
			is_substitute INTEGER NOT NULL DEFAULT 0,
			monthly_salary INTEGER NOT NULL CHECK (monthly_salary >= 0),
			start_day INTEGER NOT NULL,
			end_day INTEGER NOT NULL,
			status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'terminated')),
			CHECK (end_day > start_day)
		);""",
		"CREATE UNIQUE INDEX contract_one_active ON contract(player_id) WHERE status = 'active';",
		"CREATE INDEX contract_by_organisation ON contract(organisation_id, status);",
		"""CREATE TABLE human_profile (
			player_id TEXT PRIMARY KEY REFERENCES player(id),
			slot INTEGER NOT NULL UNIQUE,
			difficulty TEXT NOT NULL,
			created_day INTEGER NOT NULL
		);""",
	],
	# v2 — competitions copied from the world database the career started from.
	[
		"""CREATE TABLE competition (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			short_name TEXT NOT NULL,
			kind TEXT NOT NULL CHECK (kind IN ('league', 'cup')),
			region_id TEXT REFERENCES region(id),
			tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 4),
			team_count INTEGER NOT NULL CHECK (team_count BETWEEN 2 AND 64),
			start_month INTEGER NOT NULL CHECK (start_month BETWEEN 1 AND 12),
			active INTEGER NOT NULL DEFAULT 1
		);""",
	],
	# v3 — immutable match setups and submitted outcomes for career fixtures.
	[
		"""CREATE TABLE career_fixture (
			id TEXT PRIMARY KEY,
			player_id TEXT NOT NULL REFERENCES human_profile(player_id),
			scheduled_day INTEGER NOT NULL CHECK (scheduled_day >= 0),
			setup_json TEXT NOT NULL,
			submission_id TEXT UNIQUE,
			result_json TEXT,
			CHECK ((submission_id IS NULL) = (result_json IS NULL))
		);""",
		"CREATE UNIQUE INDEX career_fixture_one_pending ON career_fixture(player_id) WHERE submission_id IS NULL;",
		"CREATE INDEX career_fixture_calendar ON career_fixture(player_id, scheduled_day DESC, id DESC);",
	],
]


## Brings [param db] up to [constant CURRENT_VERSION]. Returns "" on success or an error.
## Refuses databases written by a newer build (never downgrade a save).
static func migrate(db: CareerDatabase) -> String:
	return CareerDatabase.apply_migrations(db, MIGRATIONS, "save")
