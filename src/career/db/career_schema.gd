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
##   career_match_event / career_match_stat record what happened in playable fixtures.
##   career_match_rating stores independent, versioned performance ratings.
##   organisation_form  recent results momentum (derived from series, never an ability)
##   player_ability_history  monthly overall of AI players after development (history only)
##   world_news         what happened in the world, one row per story

const FORMAT: String = "f2f.career_db"
const CURRENT_VERSION: int = 7

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
	# v4 — raw telemetry, derived counts and calculated ratings are separate layers.
	[
		"""CREATE TABLE career_match_event (
			fixture_id TEXT PRIMARY KEY REFERENCES career_fixture(id),
			format_version INTEGER NOT NULL,
			events_json TEXT NOT NULL
		);""",
		"""CREATE TABLE career_match_stat (
			fixture_id TEXT NOT NULL REFERENCES career_match_event(fixture_id),
			player_id TEXT NOT NULL REFERENCES player(id),
			counts_json TEXT NOT NULL,
			PRIMARY KEY (fixture_id, player_id)
		) WITHOUT ROWID;""",
		"CREATE INDEX career_match_stat_player ON career_match_stat(player_id, fixture_id);",
		"""CREATE TABLE career_match_rating (
			fixture_id TEXT NOT NULL,
			player_id TEXT NOT NULL,
			formula_version INTEGER NOT NULL,
			rating REAL NOT NULL,
			PRIMARY KEY (fixture_id, player_id),
			FOREIGN KEY (fixture_id, player_id) REFERENCES career_match_stat(fixture_id, player_id)
		) WITHOUT ROWID;""",
	],
	# v5 — human amateur standing and the daily training/scouting history.
	[
		"""CREATE TABLE career_amateur_rating (
			player_id TEXT PRIMARY KEY REFERENCES human_profile(player_id),
			rating INTEGER NOT NULL CHECK (rating BETWEEN 100 AND 3500),
			last_change INTEGER NOT NULL,
			updated_day INTEGER NOT NULL
		);""",
		"""CREATE TABLE career_development_activity (
			player_id TEXT NOT NULL REFERENCES human_profile(player_id),
			day INTEGER NOT NULL,
			kind TEXT NOT NULL CHECK (kind IN ('training', 'scouting')),
			subject_id TEXT NOT NULL REFERENCES player(id),
			focus TEXT NOT NULL DEFAULT '',
			change INTEGER NOT NULL,
			PRIMARY KEY (player_id, kind, day)
		) WITHOUT ROWID;""",
		"CREATE INDEX career_development_subject ON career_development_activity(player_id, kind, subject_id, day DESC);",
	],
	# v6 — published league seasons, their locked entrants and organisation series.
	[
		"""CREATE TABLE league_season (
			competition_id TEXT NOT NULL REFERENCES competition(id),
			season_year INTEGER NOT NULL CHECK (season_year >= 1),
			start_day INTEGER NOT NULL CHECK (start_day >= 0),
			best_of INTEGER NOT NULL CHECK (best_of IN (1, 3, 5)),
			PRIMARY KEY (competition_id, season_year)
		) WITHOUT ROWID;""",
		"""CREATE TABLE league_entrant (
			competition_id TEXT NOT NULL,
			season_year INTEGER NOT NULL,
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			PRIMARY KEY (competition_id, season_year, organisation_id),
			FOREIGN KEY (competition_id, season_year) REFERENCES league_season(competition_id, season_year)
		) WITHOUT ROWID;""",
		"""CREATE TABLE league_fixture (
			id INTEGER PRIMARY KEY,
			competition_id TEXT NOT NULL,
			season_year INTEGER NOT NULL,
			round_number INTEGER NOT NULL CHECK (round_number >= 1),
			scheduled_day INTEGER NOT NULL CHECK (scheduled_day >= 0),
			home_id TEXT NOT NULL,
			away_id TEXT NOT NULL,
			home_maps INTEGER CHECK (home_maps BETWEEN 0 AND 3),
			away_maps INTEGER CHECK (away_maps BETWEEN 0 AND 3),
			CHECK (home_id <> away_id),
			CHECK ((home_maps IS NULL) = (away_maps IS NULL)),
			FOREIGN KEY (competition_id, season_year, home_id)
				REFERENCES league_entrant(competition_id, season_year, organisation_id),
			FOREIGN KEY (competition_id, season_year, away_id)
				REFERENCES league_entrant(competition_id, season_year, organisation_id)
		);""",
		"CREATE INDEX league_fixture_round ON league_fixture(competition_id, season_year, round_number);",
		"""CREATE UNIQUE INDEX league_fixture_pair ON league_fixture(competition_id, season_year,
			MIN(home_id, away_id), MAX(home_id, away_id));""",
	],
	# v7 — the living world: organisation form, development history and the news log.
	[
		"""CREATE TABLE organisation_form (
			organisation_id TEXT PRIMARY KEY REFERENCES organisation(id) ON DELETE CASCADE,
			value INTEGER NOT NULL CHECK (value BETWEEN -100 AND 100),
			updated_day INTEGER NOT NULL
		);""",
		"""CREATE TABLE player_ability_history (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			day INTEGER NOT NULL,
			overall INTEGER NOT NULL CHECK (overall BETWEEN 1 AND 100),
			PRIMARY KEY (player_id, day)
		) WITHOUT ROWID;""",
		"""CREATE TABLE world_news (
			id INTEGER PRIMARY KEY,
			day INTEGER NOT NULL CHECK (day >= 0),
			kind TEXT NOT NULL,
			importance INTEGER NOT NULL CHECK (importance BETWEEN 1 AND 3),
			headline TEXT NOT NULL,
			player_id TEXT REFERENCES player(id),
			organisation_id TEXT REFERENCES organisation(id)
		);""",
		"CREATE INDEX world_news_by_day ON world_news(day DESC, id DESC);",
		"CREATE INDEX world_news_by_player ON world_news(player_id, day DESC);",
	],
]


## Brings [param db] up to [constant CURRENT_VERSION]. Returns "" on success or an error.
## Refuses databases written by a newer build (never downgrade a save).
static func migrate(db: CareerDatabase) -> String:
	return CareerDatabase.apply_migrations(db, MIGRATIONS, "save")
