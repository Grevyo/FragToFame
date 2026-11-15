class_name WorldDbSchema
extends RefCounted
## Versioned schema of a **world database** (`.f2fdb`): the starting content a career is created
## from — organisations, professionals, rosters and competitions. It is content, not a save: a
## career copies it once and then evolves on its own.
##
## Player values are **ranges** (`player_range`): every new career rolls each professional's
## abilities and potential inside them, so careers from the same database share organisations,
## rosters and competitions but differ in how good each player really is and becomes.
## Catalogue IDs (regions, nations, roles, abilities, traits) refer to [CareerCatalog] /
## [TraitLibrary] and are checked by [method WorldDatabase.validate].

const FORMAT: String = "f2f.world_db"
const CURRENT_VERSION: int = 1
const FILE_EXTENSION: String = "f2fdb"

const MIGRATIONS: Array[PackedStringArray] = [
	# v1 — metadata, organisations, players with value ranges, traits, rosters, competitions.
	[
		"""CREATE TABLE meta (
			key TEXT PRIMARY KEY,
			value TEXT NOT NULL
		);""",
		"""CREATE TABLE organisation (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			short_name TEXT NOT NULL,
			region_id TEXT NOT NULL,
			tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 4),
			founded_day INTEGER NOT NULL,
			colour TEXT NOT NULL,
			reputation_min INTEGER NOT NULL CHECK (reputation_min BETWEEN 0 AND 100),
			reputation_max INTEGER NOT NULL CHECK (reputation_max BETWEEN 0 AND 100),
			CHECK (reputation_min <= reputation_max)
		);""",
		"""CREATE TABLE player (
			id TEXT PRIMARY KEY,
			first_name TEXT NOT NULL,
			last_name TEXT NOT NULL,
			nickname TEXT NOT NULL,
			nation_id TEXT NOT NULL,
			birth_day INTEGER NOT NULL,
			preferred_role TEXT NOT NULL,
			reputation_min INTEGER NOT NULL CHECK (reputation_min BETWEEN 0 AND 100),
			reputation_max INTEGER NOT NULL CHECK (reputation_max BETWEEN 0 AND 100),
			CHECK (reputation_min <= reputation_max)
		);""",
		"""CREATE TABLE player_range (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			ability TEXT NOT NULL,
			min_value INTEGER NOT NULL CHECK (min_value BETWEEN 1 AND 100),
			max_value INTEGER NOT NULL CHECK (max_value BETWEEN 1 AND 100),
			CHECK (min_value <= max_value),
			PRIMARY KEY (player_id, ability)
		) WITHOUT ROWID;""",
		"""CREATE TABLE player_trait (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			trait_id TEXT NOT NULL,
			strength INTEGER NOT NULL CHECK (strength BETWEEN 1 AND 3),
			PRIMARY KEY (player_id, trait_id)
		) WITHOUT ROWID;""",
		"""CREATE TABLE roster (
			player_id TEXT PRIMARY KEY REFERENCES player(id) ON DELETE CASCADE,
			organisation_id TEXT NOT NULL REFERENCES organisation(id) ON DELETE CASCADE,
			role TEXT NOT NULL,
			is_substitute INTEGER NOT NULL DEFAULT 0,
			monthly_salary INTEGER NOT NULL CHECK (monthly_salary >= 0),
			start_day INTEGER NOT NULL,
			end_day INTEGER NOT NULL,
			CHECK (end_day > start_day)
		);""",
		"CREATE INDEX roster_by_organisation ON roster(organisation_id);",
		"""CREATE TABLE competition (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL UNIQUE,
			short_name TEXT NOT NULL,
			kind TEXT NOT NULL CHECK (kind IN ('league', 'cup')),
			region_id TEXT,
			tier INTEGER NOT NULL CHECK (tier BETWEEN 1 AND 4),
			team_count INTEGER NOT NULL CHECK (team_count BETWEEN 2 AND 64),
			start_month INTEGER NOT NULL CHECK (start_month BETWEEN 1 AND 12)
		);""",
	],
]


static func migrate(db: CareerDatabase) -> String:
	return CareerDatabase.apply_migrations(db, MIGRATIONS, "world database")
