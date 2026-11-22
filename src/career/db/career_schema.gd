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
##   career_offer       trial invitations and contract offers to human players
##   league_series_map  which career fixture plays which map of a human organisation's series
##   organisation_finance / player_finance  current balances; finance_ledger  every movement
##   league_record      final table of every finished league season (with prize money)
##   player_honour      top-three finishes of the players in those squads
##   human_service / human_purchase  what a human spends their own money on
##   training_session   the human's played drills and scrims with measured results (bootcamp-marked)
##   person             an AI professional's personality, drive, goal and mood (never for humans)
##   relationship       how two players get on (-100..100)

const FORMAT: String = "f2f.career_db"
const CURRENT_VERSION: int = 16

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
	# v8 — the human path to pro: trials, contract offers and playable league series.
	[
		"""CREATE TABLE career_offer (
			id TEXT PRIMARY KEY,
			player_id TEXT NOT NULL REFERENCES human_profile(player_id),
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			kind TEXT NOT NULL CHECK (kind IN ('trial', 'contract')),
			role TEXT NOT NULL,
			monthly_salary INTEGER NOT NULL CHECK (monthly_salary >= 0),
			years INTEGER NOT NULL CHECK (years BETWEEN 1 AND 5),
			created_day INTEGER NOT NULL,
			expires_day INTEGER NOT NULL,
			status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'passed', 'failed', 'declined',
				'expired', 'withdrawn')),
			fixture_id TEXT UNIQUE REFERENCES career_fixture(id),
			resolved_day INTEGER,
			CHECK (expires_day >= created_day)
		);""",
		"CREATE UNIQUE INDEX career_offer_one_open ON career_offer(player_id, organisation_id) WHERE status = 'pending' OR (status = 'accepted' AND kind = 'trial');",
		"CREATE INDEX career_offer_by_player ON career_offer(player_id, created_day DESC);",
		"""CREATE TABLE league_series_map (
			league_fixture_id INTEGER NOT NULL REFERENCES league_fixture(id),
			map_number INTEGER NOT NULL CHECK (map_number BETWEEN 1 AND 5),
			career_fixture_id TEXT NOT NULL UNIQUE REFERENCES career_fixture(id),
			human_home INTEGER NOT NULL CHECK (human_home IN (0, 1)),
			PRIMARY KEY (league_fixture_id, map_number)
		) WITHOUT ROWID;""",
	],
	# v9 — finances: balances, a ledger of every movement, and contract talks.
	[
		"""CREATE TABLE organisation_finance (
			organisation_id TEXT PRIMARY KEY REFERENCES organisation(id) ON DELETE CASCADE,
			balance INTEGER NOT NULL,
			updated_day INTEGER NOT NULL
		);""",
		"""CREATE TABLE player_finance (
			player_id TEXT PRIMARY KEY REFERENCES player(id) ON DELETE CASCADE,
			balance INTEGER NOT NULL,
			updated_day INTEGER NOT NULL
		);""",
		"""CREATE TABLE finance_ledger (
			id INTEGER PRIMARY KEY,
			day INTEGER NOT NULL,
			organisation_id TEXT REFERENCES organisation(id),
			player_id TEXT REFERENCES player(id),
			kind TEXT NOT NULL CHECK (kind IN ('opening', 'income', 'wages', 'prize', 'fee_paid', 'fee_received', 'salary')),
			amount INTEGER NOT NULL,
			note TEXT NOT NULL DEFAULT '',
			CHECK ((organisation_id IS NULL) <> (player_id IS NULL))
		);""",
		"CREATE INDEX finance_ledger_org ON finance_ledger(organisation_id, day DESC);",
		"CREATE INDEX finance_ledger_player ON finance_ledger(player_id, day DESC);",
		"ALTER TABLE career_offer ADD COLUMN negotiated INTEGER NOT NULL DEFAULT 0 CHECK (negotiated IN (0, 1));",
	],
	# v10 — season records, honours, prize money and human spending. The ledger is rebuilt to
	# allow bonus and expense entries (SQLite cannot alter a CHECK constraint).
	[
		"""CREATE TABLE finance_ledger_v10 (
			id INTEGER PRIMARY KEY,
			day INTEGER NOT NULL,
			organisation_id TEXT REFERENCES organisation(id),
			player_id TEXT REFERENCES player(id),
			kind TEXT NOT NULL CHECK (kind IN ('opening', 'income', 'wages', 'prize', 'fee_paid', 'fee_received',
				'salary', 'bonus', 'expense')),
			amount INTEGER NOT NULL,
			note TEXT NOT NULL DEFAULT '',
			CHECK ((organisation_id IS NULL) <> (player_id IS NULL))
		);""",
		"INSERT INTO finance_ledger_v10 SELECT id, day, organisation_id, player_id, kind, amount, note FROM finance_ledger;",
		"DROP TABLE finance_ledger;",
		"ALTER TABLE finance_ledger_v10 RENAME TO finance_ledger;",
		"CREATE INDEX finance_ledger_org ON finance_ledger(organisation_id, day DESC);",
		"CREATE INDEX finance_ledger_player ON finance_ledger(player_id, day DESC);",
		"""CREATE TABLE league_record (
			competition_id TEXT NOT NULL,
			season_year INTEGER NOT NULL,
			position INTEGER NOT NULL CHECK (position >= 1),
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			won INTEGER NOT NULL,
			lost INTEGER NOT NULL,
			map_diff INTEGER NOT NULL,
			prize INTEGER NOT NULL CHECK (prize >= 0),
			completed_day INTEGER NOT NULL,
			PRIMARY KEY (competition_id, season_year, position),
			FOREIGN KEY (competition_id, season_year) REFERENCES league_season(competition_id, season_year)
		) WITHOUT ROWID;""",
		"CREATE UNIQUE INDEX league_record_once ON league_record(competition_id, season_year, organisation_id);",
		"""CREATE TABLE player_honour (
			player_id TEXT NOT NULL REFERENCES player(id) ON DELETE CASCADE,
			competition_id TEXT NOT NULL,
			season_year INTEGER NOT NULL,
			position INTEGER NOT NULL CHECK (position BETWEEN 1 AND 3),
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			PRIMARY KEY (player_id, competition_id, season_year)
		) WITHOUT ROWID;""",
		"""CREATE TABLE human_service (
			player_id TEXT NOT NULL REFERENCES human_profile(player_id),
			service_id TEXT NOT NULL,
			started_day INTEGER NOT NULL,
			PRIMARY KEY (player_id, service_id)
		) WITHOUT ROWID;""",
		"""CREATE TABLE human_purchase (
			id INTEGER PRIMARY KEY,
			player_id TEXT NOT NULL REFERENCES human_profile(player_id),
			item_id TEXT NOT NULL,
			day INTEGER NOT NULL
		);""",
		"CREATE INDEX human_purchase_by_player ON human_purchase(player_id, item_id, day DESC);",
	],
	# v11 — cups, promotion and relegation, and offers to contracted humans. The offer table is
	# rebuilt to allow transfer and renewal offers with a fee.
	[
		"""CREATE TABLE career_offer_v11 (
			id TEXT PRIMARY KEY,
			player_id TEXT NOT NULL REFERENCES human_profile(player_id),
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			kind TEXT NOT NULL CHECK (kind IN ('trial', 'contract', 'transfer', 'renewal')),
			role TEXT NOT NULL,
			monthly_salary INTEGER NOT NULL CHECK (monthly_salary >= 0),
			years INTEGER NOT NULL CHECK (years BETWEEN 1 AND 5),
			created_day INTEGER NOT NULL,
			expires_day INTEGER NOT NULL,
			status TEXT NOT NULL CHECK (status IN ('pending', 'accepted', 'passed', 'failed', 'declined',
				'expired', 'withdrawn')),
			fixture_id TEXT UNIQUE REFERENCES career_fixture(id),
			resolved_day INTEGER,
			negotiated INTEGER NOT NULL DEFAULT 0 CHECK (negotiated IN (0, 1)),
			fee INTEGER NOT NULL DEFAULT 0 CHECK (fee >= 0),
			CHECK (expires_day >= created_day)
		);""",
		"""INSERT INTO career_offer_v11 (id, player_id, organisation_id, kind, role, monthly_salary, years, created_day,
			expires_day, status, fixture_id, resolved_day, negotiated)
			SELECT id, player_id, organisation_id, kind, role, monthly_salary, years, created_day, expires_day, status,
			fixture_id, resolved_day, negotiated FROM career_offer;""",
		"DROP TABLE career_offer;",
		"ALTER TABLE career_offer_v11 RENAME TO career_offer;",
		"CREATE UNIQUE INDEX career_offer_one_open ON career_offer(player_id, organisation_id) WHERE status = 'pending' OR (status = 'accepted' AND kind = 'trial');",
		"CREATE INDEX career_offer_by_player ON career_offer(player_id, created_day DESC);",
		"""CREATE TABLE cup_seed (
			competition_id TEXT NOT NULL,
			season_year INTEGER NOT NULL,
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			seed INTEGER NOT NULL CHECK (seed >= 1),
			PRIMARY KEY (competition_id, season_year, organisation_id),
			FOREIGN KEY (competition_id, season_year) REFERENCES league_season(competition_id, season_year)
		) WITHOUT ROWID;""",
		"CREATE UNIQUE INDEX cup_seed_once ON cup_seed(competition_id, season_year, seed);",
		"""CREATE TABLE organisation_move (
			id INTEGER PRIMARY KEY,
			organisation_id TEXT NOT NULL REFERENCES organisation(id),
			day INTEGER NOT NULL,
			from_tier INTEGER NOT NULL CHECK (from_tier BETWEEN 1 AND 4),
			to_tier INTEGER NOT NULL CHECK (to_tier BETWEEN 1 AND 4),
			reason TEXT NOT NULL DEFAULT ''
		);""",
		"CREATE INDEX organisation_move_by_org ON organisation_move(organisation_id, day DESC);",
	],
	# v12 — the round-by-round match engine: player morale, simulated map results and the
	# per-player lines of simulated maps (kept apart from statistics recorded in played matches).
	[
		"""CREATE TABLE player_morale (
			player_id TEXT PRIMARY KEY REFERENCES player(id) ON DELETE CASCADE,
			value INTEGER NOT NULL CHECK (value BETWEEN -20 AND 20),
			updated_day INTEGER NOT NULL
		) WITHOUT ROWID;""",
		"""CREATE TABLE sim_map (
			league_fixture_id INTEGER NOT NULL REFERENCES league_fixture(id),
			map_number INTEGER NOT NULL CHECK (map_number BETWEEN 1 AND 5),
			map_id TEXT NOT NULL,
			home_rounds INTEGER NOT NULL,
			away_rounds INTEGER NOT NULL,
			mvp_id TEXT,
			highlights TEXT NOT NULL DEFAULT '',
			PRIMARY KEY (league_fixture_id, map_number)
		) WITHOUT ROWID;""",
		"""CREATE TABLE sim_player_map (
			id INTEGER PRIMARY KEY,
			day INTEGER NOT NULL,
			league_fixture_id INTEGER REFERENCES league_fixture(id),
			career_fixture_id TEXT,
			map_number INTEGER NOT NULL,
			player_id TEXT NOT NULL,
			organisation_id TEXT,
			rounds INTEGER NOT NULL,
			kills INTEGER NOT NULL,
			deaths INTEGER NOT NULL,
			assists INTEGER NOT NULL,
			damage INTEGER NOT NULL,
			kast_rounds INTEGER NOT NULL,
			opening_kills INTEGER NOT NULL,
			clutch_wins INTEGER NOT NULL,
			rating REAL NOT NULL,
			won INTEGER NOT NULL CHECK (won IN (0, 1))
		);""",
		"CREATE INDEX sim_player_map_by_player ON sim_player_map(player_id, day DESC);",
		"CREATE INDEX sim_player_map_by_series ON sim_player_map(league_fixture_id, map_number);",
	],
	# v13 — real training: drills and scrims played in the FPS runtime, with measured results.
	[
		"""CREATE TABLE training_session (
			id INTEGER PRIMARY KEY,
			player_id TEXT NOT NULL REFERENCES player(id),
			day INTEGER NOT NULL,
			drill_id TEXT NOT NULL,
			score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
			metrics_json TEXT NOT NULL,
			evidence INTEGER NOT NULL DEFAULT 0
		);""",
		"CREATE INDEX training_session_by_player ON training_session(player_id, day DESC);",
	],
	# v14 — people: every AI professional's personality, what drives them, a career goal, how
	# happy they are where they are, and their relationships with teammates.
	[
		"""CREATE TABLE person (
			player_id TEXT PRIMARY KEY REFERENCES player(id),
			ambition INTEGER NOT NULL CHECK (ambition BETWEEN 1 AND 20),
			loyalty INTEGER NOT NULL CHECK (loyalty BETWEEN 1 AND 20),
			professionalism INTEGER NOT NULL CHECK (professionalism BETWEEN 1 AND 20),
			temperament INTEGER NOT NULL CHECK (temperament BETWEEN 1 AND 20),
			ego INTEGER NOT NULL CHECK (ego BETWEEN 1 AND 20),
			sociability INTEGER NOT NULL CHECK (sociability BETWEEN 1 AND 20),
			drive TEXT NOT NULL,
			background TEXT NOT NULL,
			goal TEXT NOT NULL,
			goal_done_day INTEGER,
			happiness INTEGER NOT NULL DEFAULT 0 CHECK (happiness BETWEEN -50 AND 50),
			wants_move INTEGER NOT NULL DEFAULT 0 CHECK (wants_move IN (0, 1)),
			mood_reason TEXT NOT NULL DEFAULT '',
			updated_day INTEGER NOT NULL DEFAULT 0
		) WITHOUT ROWID;""",
		"""CREATE TABLE relationship (
			a_id TEXT NOT NULL REFERENCES player(id),
			b_id TEXT NOT NULL REFERENCES player(id),
			strength INTEGER NOT NULL CHECK (strength BETWEEN -100 AND 100),
			since_day INTEGER NOT NULL,
			updated_day INTEGER NOT NULL,
			PRIMARY KEY (a_id, b_id),
			CHECK (a_id < b_id)
		) WITHOUT ROWID;""",
		"CREATE INDEX relationship_by_b ON relationship(b_id);",
	],
	# v15 — the bootcamp is a real programme: sessions played during one are marked.
	[
		"ALTER TABLE training_session ADD COLUMN bootcamp INTEGER NOT NULL DEFAULT 0 CHECK (bootcamp IN (0, 1));",
	],
	# v16 — each simulated line records its map, for map familiarity and comfort (Milestone 21 F).
	[
		"ALTER TABLE sim_player_map ADD COLUMN map_id TEXT NOT NULL DEFAULT '';",
		"""UPDATE sim_player_map SET map_id = COALESCE((SELECT s.map_id FROM sim_map s
			WHERE s.league_fixture_id = sim_player_map.league_fixture_id AND s.map_number = sim_player_map.map_number), '')
			WHERE league_fixture_id IS NOT NULL;""",
		"CREATE INDEX sim_player_map_by_team_map ON sim_player_map(organisation_id, map_id, day);",
	],
]


## Brings [param db] up to [constant CURRENT_VERSION]. Returns "" on success or an error.
## Refuses databases written by a newer build (never downgrade a save).
static func migrate(db: CareerDatabase) -> String:
	return CareerDatabase.apply_migrations(db, MIGRATIONS, "save")
