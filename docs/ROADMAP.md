# Frag to Fame — Roadmap

Each milestone is a small, independently testable vertical slice. The order may change where
dependencies demand it. The owner asked (2026-11-15) for milestones to be worked through
continuously: each one is validated, committed and pushed, and manual checks are collected in the
README for the owner to run.

Legend: ✅ done · 🔶 in progress / awaiting acceptance · ⬜ not started · ⏸ deferred

| # | Milestone | Depends on | Status |
|---|---|---|---|
| 1 | Runnable application foundation | — | ✅ |
| 2 | Early networking architecture proof | 1 | 🔶 awaiting manual test |
| 3 | Basic runtime map editing | 1 | 🔶 awaiting manual test |
| 4 | Basic FPS mechanics | 1 | 🔶 awaiting manual test |
| 5 | Competitive match rules | 4 | 🔶 awaiting manual test |
| 6 | Individual combat and navigation AI | 3, 4 | 🔶 awaiting manual test |
| 7 | Tactical team AI and IGL | 5, 6, 8, 9, representative maps and gameplay-relevant player traits | ⏸ deferred |
| 8 | Tactical Play Creator | 3, 6 | 🔶 awaiting manual test |
| 9 | Persistent player/team database | 1 | 🔶 awaiting manual test |
| 10 | Career fixtures and playable match integration | 5, 9 | 🔶 awaiting manual test |
| 11 | Detailed statistics | 5, 10 | 🔶 awaiting manual test |
| 12 | Career development and scouting | 9, 11 | 🔶 awaiting manual test |
| 13 | Competition and tournament systems | 9, 10 | 🔶 league scheduling |
| 14 | World progression, transfers, rookies, retirement | 12, 13 | 🔶 living world, path to pro, transfers and finances |
| 15 | Full cooperative career integration | 2, 10, 14 | ⬜ |
| 16 | Official content creation (5–7 maps) | 3, 6, 8 | 🔶 first map; awaiting manual test |
| 17 | Community content import/export | 3, 9, 16 | ⬜ |
| 18 | Steam integration, testing, release preparation | all | ⬜ |
| 19 | Database and Competition Editor | 9, 13 | ⬜ |

**Execution order (updated 2026-11-15):** 1 → 6 → 9 → 8 → **10 → 13 → 14 → 15 → 16 → 19 → 17 → 18**.
M19 comes before M17 because community databases are made with the editor.
M7 is deferred while representative maps and gameplay-relevant player traits are developed.
Those foundations give the team AI real layouts, roles and behaviours to work with when M7 is
revisited. Milestone numbers stay stable for reference.

---

## Milestone 1 — Runnable application foundation ✅

**Goal:** A Godot 4.7.2 project that launches into a working main menu and can enter three
functional shells.

Completion criteria:

- [x] Docs: README, GAME_VISION, ARCHITECTURE, ROADMAP, CLAUDE.md, `.gitignore`.
- [x] Godot project rooted at repo root, Forward+, typed GDScript.
- [x] Main menu: title, subtitle, Career Hub / FPS Sandbox / Creation Studio / Quit — all functional.
- [x] Career Hub: sidebar with Home, Player Profile, Teams, Competitions, Calendar, Statistics;
      clearly labelled development sample data; return to main menu.
- [x] FPS Sandbox: ground + geometry, first-person camera, WASD, mouse look, jump, collision,
      mouse capture/release, return to main menu.
- [x] Creation Studio shell: free-fly camera, visible grid, camera controls, editing UI shell,
      return to main menu.
- [x] Headless import + automated smoke tests pass.
- [x] Validated on the owner's machine (`tools/validate.ps1`); owner moved on to Milestone 2.

## Milestone 2 — Early networking architecture proof 🔶

Prove the two-network split before gameplay hardens around single-player assumptions.

Completion criteria:

- [x] Career host mode owning a tiny authoritative world (dev-sample fixture list, in memory).
- [x] Versioned career-sync protocol with handshake and protocol-version rejection.
- [x] Clients see the same fixture list, "play" a stub match (`MatchSetup` → `StubMatchRunner` →
      `MatchResult`) and submit; the host answers ACCEPTED / DUPLICATE / CONFLICT /
      UNKNOWN_FIXTURE / INVALID and broadcasts world updates with a revision number.
- [x] Pending submissions survive a disconnect and are resent safely after reconnecting.
- [x] Match host listen server in the FPS Sandbox; players see each other move (position + facing).
- [x] Career and match networks run simultaneously and independently (separate transports,
      ports and lifetimes).
- [x] Automated loopback tests: career host + 2 clients; match host + client; both at once.
- [ ] Manual two-instance test (README) completed by the project owner.

Out of scope (later): saving the world, calendar advancement, the career host choosing the match
host, spectating, server-authoritative movement.

## Milestone 3 — Basic runtime map editing 🔶

Completion criteria:

- [x] Versioned map document (`f2f.map` v1) with stable map and piece IDs; strict loading rejects
      unknown formats, versions and piece types.
- [x] Piece catalog: floor, wall, block, pillar, ramp, stairs, props, attacker/defender spawns,
      bombsite, buy zone, callout.
- [x] One `MapBuilder` builds the same document for the editor and the FPS runtime.
- [x] Creation Studio: palette, ghost preview, place / select / drag-move / rotate / duplicate /
      delete, snap sizes, build height, inspector editing of position, rotation, size and props.
- [x] Undo/redo for every edit (a drag is a single step); dirty tracking and unsaved-change prompts.
- [x] Save / open / delete maps in `user://maps` with atomic writes and a `.bak` backup.
- [x] Validator with errors (block playtest) and warnings (advisory).
- [x] Playtest loads the map into the FPS runtime and returns to the editor with unsaved work,
      the file path and the camera intact.
- [x] The FPS Sandbox arena is itself a map document (`MapTemplates.sandbox_arena`) and can be
      opened and edited as a template.
- [x] Automated tests: document, validator, storage, controller (incl. leak check), physics
      geometry of ramps/stairs/platforms, studio editing, playtest round trip.
- [ ] Manual editor walkthrough (README) completed by the project owner.

Out of scope (later): multi-select, free rotation, custom materials, lighting tools, navmesh
baking, tactical markers beyond spawns/sites, map sharing.

## Milestone 4 — Basic FPS mechanics 🔶

Completion criteria:

- [x] Ten modelled weapons defined as data
      in `WeaponCatalog`: damage, fire rate, magazine/reserve, reload/draw time, falloff, spread,
      bloom, fixed recoil pattern, recovery.
- [x] `WeaponState`: pure, deterministic (seeded) simulation of cadence, semi/auto, ammo, reload,
      bloom, movement/air/crouch spread and recoil with recovery.
- [x] Hitscan shots on dedicated physics layers (world / characters / hitboxes); per-zone damage
      (head ×4, stomach ×1.25, chest ×1, arms ×0.9, legs ×0.75) with range falloff.
- [x] `Health` component with damage/death/revive events; `DamageInfo` event data; `CombatTally`
      for recorded shooting numbers.
- [x] Player crouch (smaller capsule, lower eye, slower, more accurate, cannot stand under
      ceilings), death (falling out of the world) and timed respawn with refilled ammo.
- [x] Target dummies with hitboxes, damage numbers, elimination and respawn, optional strafing,
      placeable in the editor as a Training piece.
- [x] HUD: dynamic crosshair, hit marker, weapon/ammo/reload, health, training stats, kill feed,
      death overlay. Viewmodel, muzzle flash, tracers and impact marks.
- [x] Automated tests: catalog, damage, cadence, reload, spread, recoil, health, hitscan maths,
      tally, and a scene test that shoots dummies, walls, crouches and respawns.
- [x] Movement rework (2026-11-15): `PlayerMovement` model fitted to recorded reference runs
      (acceleration, friction, counter-strafe stops, walk/crouch speeds, air control, jump arc,
      landing stamina) and weapon mobility (rifle 0.86). Player and bots share it through
      `CombatantMovementBody`; tests cover the curves and player/bot parity.
- [ ] Manual feel test (README) by the project owner.

Out of scope (later): armour, penetration, buying and economy (M5), sounds (no audio assets yet),
networked damage / server-authoritative hits (with match rules), player hitboxes for bots (M6),
grenades and utility, scoped weapons, fall damage.

## Milestone 5 — Competitive match rules 🔶

Completion criteria:

- [x] `MatchRules`: data-driven format (MR n, overtime MR), timings (freeze, buy window, round,
      bomb, plant, defuse with/without kit) and economy (start/overtime/max money, win rewards per
      reason, loss-bonus ladder, plant bonus); competitive and practice presets.
- [x] `ShopCatalog`: original prices for weapons, vest, vest + helmet (helmet upgrade), defuse kit;
      kill rewards by weapon.
- [x] Armour in damage: vests protect all but legs, helmets the head; weapon armour penetration.
- [x] `MatchState`: pure state machine — freeze/live/round-end/match-end, elimination, time,
      detonation and defuse win conditions (attack still loses only if the bomb is defused after
      a plant), bomb carrier/drop/pickup, money, gear kept by survivors and lost on death,
      half-time switch with money reset, overtime blocks with side switches, final
      `MatchResult`, and an event log for future statistics.
- [x] Runtime: `MatchDirector` in the FPS runtime takes a `MatchSetup` + rules, places players and
      combatants per round, freezes players in freeze time, buy menu restricted to own buy zone
      and buy window, bomb plant (hold E on a bombsite) and defuse (hold E near the bomb), bomb
      model, match HUD (scoreboard, clock, money, banners, progress, hints, match-end screen).
- [x] `MapZones` point-in-zone queries; arena template now has 5 spawns per team and a buy zone
      per side.
- [x] Practice match entry (FPS Sandbox pause menu): MR3 vs passive targets, clearly labelled.
- [x] Automated tests: rules suite (armour, loadout, round flow, economy, bomb, halves, overtime,
      event log) and a full scene match (buy, eliminate, plant + detonate, half time, death,
      defuse, match end with a valid `MatchResult`).
- [ ] Manual practice-match walkthrough (README) by the project owner.

Out of scope (later): opponents that fight back (M6 AI), teammates, networked matches (rules run
on the match host later), dropping/picking up weapons, grenades/utility, spectating dead players,
career fixtures and their result submission (M10).

## Milestone 6 — Individual combat and navigation AI 🔶

**Goal:** Bots that move around any editor-made map, spot, aim and shoot like (imperfect) humans
through the same weapon code as the player, and play practice matches as teammates and opponents
under the M5 rules.

Completion criteria:

- [x] Runtime navmesh: `NavigationBuilder` bakes from the built map's world colliders with
      Godot's `NavigationServer3D` — every map made in the Creation Studio is walkable for bots,
      no separate authoring step. Climb height is one cell (bodies do not auto-step; stairs use
      their walk slope).
- [x] Shared `HumanoidRig`: the player, dummies and bots use the same hitbox layout (head, chest,
      stomach, arms, legs); the player now has hitboxes, follows crouch, and can be shot.
- [x] `BotSkill` presets (easy / normal / hard): reaction time, turn speed, aim gain, acquisition
      error and its decay, recoil control, fire tolerance, view cone/distance, awareness radius,
      burst distance. No impossible accuracy: errors, reaction and turn caps apply at every level.
- [x] `AimModel` (pure maths): capped, lagging turns plus decaying acquisition error.
- [x] `BotController`: perception (view cone, awareness radius, line of sight through world
      geometry only), reaction delay, recoil compensation, bursts at range, semi-auto tapping,
      reload behind basic cover, search the last known position, navigation to goals, watch points.
- [x] Bots never target teammates; damage still respects `friendly_fire`.
- [x] `BotSquad` in practice matches: default practice is 5v5 (you + 4 bot teammates vs 5 bots).
      Bots buy (AK-47 or SKS + armour, kits on defence), spawn per side, attack one site per round,
      the carrier plants, a dropped bomb is recovered, defenders hold both sites, retake and defuse.
      Passive targets remain available as an option (used by the rules tests).
- [x] Kill feed for every match elimination; bot kills feed the same `MatchState` event log.
- [x] Automated tests: aim model, skills, navmesh (paths, unreachable areas), navigation incl.
      the platform, perception and line of sight, combat vs dummies and the player, teams, and a
      bot match (roster, buying, bomb pick-up → plant → defuse, a fought round, respawns).
- [ ] Manual 5v5 practice-match walkthrough (README) by the project owner.

Out of scope (later): coordinated team play, roles, IGL calls and team economy (M7),
utility/grenades, sound-based perception (no audio yet), bot skill from career attributes (M12),
networked bots.

## Milestone 7 — Tactical team AI and IGL

*Deferred until representative maps and gameplay-relevant player traits are available.*

**Goal:** Teams of bots play rounds as a team, driven by one team-tactics layer that an AI IGL —
and later a human IGL — uses to make calls.

Planned scope:

- Team-tactics model (pure, no nodes): a round plan with per-player roles (entry, support, lurk,
  anchor, rotator), positions and phases (default → execute / hold → post-plant / retake).
- Map tactical data derived from the map document: sites, callouts, entrances computed from the
  navmesh, so every editor map works.
- AI IGL: chooses defaults, executes, fakes, rushes, stacks and saves from economy, score, map and
  information (spotted enemies, kills, bomb state); mid-round adaptations (rotate, retake, save).
- Team economy: full buy / force / eco / save decisions shared by the team.
- Coordination: trading (follow the entry), grouping before an execute, holding angles, retake
  gathering; information shared only through team communication (no hidden information).
- Human IGL commands (execute A/B, hold, rotate, save, regroup) issuing the same calls; AI
  teammates respond.
- Intelligence scaling by team tier; difficulty never via impossible aim.
- Tests: plan selection, role assignment, economy decisions, calls → bot goals, a scene match
  where an execute happens as a group.

## Milestone 8 — Tactical Play Creator 🔶

- [x] Switch from Map Creator into tactical mode on a saved map. Reuse the existing map geometry
      and camera, and keep editing and preview local to Creation Studio.
- [x] Place five labelled starts. Add, move and remove ordered waypoints with distinct route
      markers for each player.
- [x] Save and reopen a versioned tactic with a stable ID and the source map ID, revision and
      fingerprint. Refuse incompatible maps and malformed or unsupported tactic documents.
- [x] Run, stop and restart a five-bot route preview with per-slot progress and unreachable-waypoint
      feedback, using the existing navmesh and bot movement.
- [x] Headless tests cover authoring, saving, reopening, revision checks, editing and bot routes.
- [ ] Owner walkthrough in the README, including a game relaunch and viewport editing.

M7 consumes these authored routes. Tactical roles, utility, triggers, adaptive calls and career
integration are outside this slice.

## Milestone 9 — Persistent player/team database 🔶

**Goal:** Every career is a persistent, safe SQLite world of original organisations and
professionals that the Career Hub reads and the match layer can draw lineups from.

Completion criteria:

- [x] `godot-sqlite` GDExtension (MIT) installed; `CareerDatabase` is the only class that touches
      SQLite (WAL, foreign keys, nested transactions with rollback, `VACUUM INTO` snapshots,
      integrity check).
- [x] `CareerSchema` v2 with migrations via `user_version`. A v1 upgrade requires a verified snapshot
      before its schema transaction begins.
- [x] Schema: meta, regions, nations, organisations, players, true abilities (AI only), perceived
      abilities with scouting confidence, player and organisation reputation, traits, contracts
      (one active contract per player enforced), human profiles.
- [x] `CareerRepository`: typed records and queries (organisations, rosters, lineups, player
      search/filter/sort, stat layers, traits, contracts with history). No SQL elsewhere.
- [x] A shipped starting template with 40 organisations across eight regions, 296 AI professionals
      and 19 competition definitions. New careers retain authored identities, traits and rosters,
      and initialise AI abilities within authored ranges. Import checked standalone databases in
      Career Select.
- [x] `TraitLibrary`: 24 data-driven traits in 6 categories with conflict rules (stored and shown;
      consumed by decision systems from M7 onward).
- [x] Human creation (`HumanCareer`): perceived values + reputation from career difficulty, never
      simulated abilities.
- [x] `CareerSaves`: save folders, create/list/open, rotating backups (8), damage detection and
      restore (damaged file kept aside).
- [x] Career select screen (continue / new career) and a career session in `App`.
- [x] Career Hub on real data: Home, Player Profile, Teams (rosters), new Players browser;
      remaining sample pages are labelled with the milestone that replaces them.
- [x] Bots from attributes: `MatchSetup` v2 carries lineups; `BotSkill.from_abilities` maps an AI
      professional's abilities to bot mechanics; practice against any organisation's starting five.
- [x] Validation fails on any GDScript runtime error in the test log.
- [x] Automated tests: SQLite engine, calendar, schema/migrations, repository and layer
      separation, generator (counts, tiers, uniqueness, determinism), saves/backups/restore,
      career flow scenes, practice vs a real roster.
- [ ] Manual career walkthrough (README) by the project owner.

Out of scope (later): fixtures and results in the database (M10), recorded match statistics and
ratings (M11), scouting that updates perceived values (M12), competitions (M13), world
progression, transfers, ageing and rookies (M14), co-op sync of the database (M15), deleting
saves from the UI.

## Milestone 10 — Career fixtures and playable match integration 🔶

- [x] Schedule one pending local 5v5 amateur fixture from Career Home on the existing development
      arena. Use an MR5 match, five AI opponents from a career organisation, and AI teammates
      from the career where available.
- [x] Persist the fixture, scheduled day and lineup snapshot in SQLite. Existing v2 careers
      acquire the new table through the backed-up v3 migration.
- [x] Play through the existing FPS scene with the career player's ID. Return to the Hub after
      completing or leaving the fixture. Unfinished fixtures remain available on the same day.
- [x] Save the final score and advance one career day in the same transaction. Identical
      submissions are idempotent. Invalid or conflicting submissions leave the career unchanged.
- [x] Display scheduled fixtures and completed scores in Calendar. Offer a retry on a failed
      result save while the app still holds it.
- [x] Automated checks cover the v2 migration, scheduling, restart, persistence, result rollback,
      retry, duplicate and conflicting results, and calendar display.
- [ ] Manual walkthrough of a complete fixture using the README checklist.

Later milestones cover league schedules and standings, AI-only world simulation,
production map rotation and multiplayer fixture hosting.

## Milestone 11 — Detailed match statistics 🔶

- [x] Capture live-round weapon attempts, actual health damage, kills, objective events and
      round outcomes for the human and AI players using their match IDs.
- [x] Derive K-D-A, KAST, damage per round, weapon and first-shot accuracy, headshot kills,
      openers, trades, clutch attempts and wins by opponent count, and plants and defuses.
- [x] Store raw events, derived counts and versioned F2F ratings separately in schema v4.
      Commit all three with the fixture score and calendar date in one transaction.
- [x] Show recorded match history, rating, aggregate statistics and recent weapon breakdown in
      Career Hub. Player profiles also show recorded match count and performance rating.
- [x] Tests cover live weapon capture, contextual counters, round normalisation, persistence
      and rollback. Results from older saves retain their scores.
- [ ] Play a career fixture and review the displayed statistics in Godot.

Utility effects, detailed role and situation ratings, and simulated AI-only match telemetry
depend on the corresponding gameplay and world simulation systems.

## Milestone 12 — Career development and scouting 🔶

- [x] Show amateur ELO in Career Home. Use a difficulty-based starting value and update it
      from accepted amateur fixture outcomes.
- [x] Use completed matches to update reputation, confidence and perceived aim, crosshair
      placement and composure when enough relevant events were recorded.
- [x] Offer one training focus per career day in Player Profile. Training changes the selected
      perceived ability and is recorded in the save.
- [x] Offer one scouting report per career day in Players. Reports refine estimates toward AI
      ability and increase confidence while preserving underlying ability and hidden potential.
- [x] Persist career development in schema v5 and test daily limits, save reload, successful,
      duplicate and failed match publication, and the absence of human simulated abilities.
- [ ] Manual training, scouting and match progression walkthrough.

AI development, ageing, roster decisions and trait-driven team tactics are later work.

---

## Milestone 13 — Competition and tournament systems 🔶

- [x] Replace sample competitions with definitions from the active world database.
- [x] Publish persistent round-robin editions with locked entrants and calendar dates. Surface
      undersubscribed leagues. Resolve a valid series score once and derive standings from results.
- [ ] Walk through the shipped league calendars and standings in the Career Hub.
- [x] Simulated series: passing a day resolves every due AI series from lineup strength
      (`SeriesSimulator`, `CareerCalendar`), atomically with the date and new seasons. The
      Calendar page advances the day and shows the week's series and recent results. A player's
      unplayed match blocks the day (calendar conflict).
- [x] Playable league series for the player's own organisation (M14 path to pro), map by map.
- [ ] Map selection and veto, configurable MR length and overtime per competition.
- [x] Season records: final tables, prize money and honours (M14).
- [x] Cups (`CareerCups`): single elimination, seeded by tier and reputation, bracket sized to
      the next power of two with byes for the top seeds. Cups invite from one tier above their
      own downwards (in their region, or worldwide). Rounds are weekly from the 4th of the
      start month; each round is drawn once its sides are known. Cup series use the league
      tables, so simulation, the human's playable series and series prizes work the same. The
      final closes the cup with placings, prizes, honours and news.
- [x] Leagues fill empty places from the tier below and run with at least six organisations.
- [x] Promotion and relegation from final tables (`WorldSeasons`), always as swaps so tiers
      keep their size:
  - in a tier T league, the best tier T finisher(s) in the top half (two in a field of 12+) go
    up to T−1. The worst tier T−1 entrant below them goes down, or else the least reputable
    tier T−1 organisation of the region, then anywhere;
  - the best filler from tier T+1 in the top half goes up to T the same way;
  - a tier 4 winner of a regional open goes up to tier 3.

  Every move is recorded (`organisation_move`) and reported in the news.
- [ ] Qualifier brackets and the F2F Universal Ladder.

## Milestone 14 — World progression, transfers, rookies, retirement 🔶

Owner decisions (2026-11-16): the player's own matches are always played, and only played games
move their ELO and reputation (no quick-sim). The calendar has **Next day** and an FM-style
**Continue** that runs days until something needs the player. Build the changing world first,
then the human path to pro. LIGA-style career sims are a mechanics reference only; no names or
content are copied.

First slice — the living world (`WorldSimulation`, run for every day by `CareerCalendar`):

- [x] Form: simulated series results move each organisation's form (−100..100), which adds up to
      ±3 strength points in later simulated series.
- [x] Reputation: Elo-style changes on the 0–100 scale from simulated series, weighted by
      competition tier; AI starters share half. Monthly drift back towards the tier's typical
      range; free agents fade; signed players converge on their organisation.
- [x] Development: monthly growth towards hidden potential while young (fast to 20, slower to 28),
      decline of mechanical abilities from 30 and of experience abilities from 33. Overall history
      is recorded. Perceived values drift towards the truth; contracted players gain scouting
      confidence up to their tier's cap.
- [x] Market: expiring contracts are renewed or released (age, role and level decide). Organisations
      short of five starters promote a substitute or sign the best fitting free agent (perceived
      rating, role fit, region). Salaries follow tier and rating.
- [x] New year: age-driven retirements, and an original rookie class (16–18, raw, high potential)
      that replaces them as free agents.
- [x] News log with importance (minor, notable, headline); News page, Calendar news card, Home
      "Latest news" and organisation form on Teams.
- [x] Continue stops on the player's match day, any headline (their contract, the new year, their
      league starting) or after 31 days.

Second slice — the human path to pro (`CareerOffers`, `CareerLeagueMatches`):

- [x] Visibility from reputation, amateur ELO and recent F2F ratings (only played matches count).
      Each tier looks from a visibility threshold (10 / 25 / 45 / 65) and needs a perceived level
      near its norm. Unsigned humans get at most two open approaches, and an organisation waits
      60 days before asking again.
- [x] Trial invitations (headline, 7 days to answer) → a playable MR5 trial alongside four of
      the organisation's starters. Rating ≥ 1.00 (≥ 0.85 in a win) earns a contract offer.
- [x] Signing makes the human a starter. The weakest AI starter drops to the bench and other
      offers are withdrawn.
- [x] Playable league series: due series are booked map by map (MR8, the human's side at home).
      A map that does not decide the series keeps the day. The final score goes to the table and
      moves form and reputation, including the human's.
- [ ] Map selection and veto, per-competition MR and overtime settings (with the M19 editor).
- [x] Life under contract (`CareerHumanContracts`):
  - **Transfer offers:** a higher-tier organisation that would consider the human may bid.
    The fee is paid to their organisation, and accepting moves them at once.
  - **Renewal:** 60 days before a contract ends the organisation offers a new deal, or says it
    will release the human (level below the tier norm, a slump, or benched).
  - **Benching:** a monthly check. Poor recent ratings can cost a starter their place to a
    better substitute, and a benched human can be recalled. A benched human's organisation is
    simulated without them.
- [x] Deep simulation (owner, 2026-11-17: "much much deeper"). Every series nobody plays goes
      round by round through `MatchEngine` (`CareerSeriesEngine`):
  - **Format and economy:** MR8 halves and overtime; pistol, eco, force and full buys from a
    team bank, with loss bonuses.
  - **Rounds:** attack and defence, plants, defuses and saves. Each round is a chain of duels
    whose fighters are picked by role and personality, with trades, assists and clutches.
  - **What decides a duel:** each player's duel skill on the day, side, numbers, equipment,
    post-plant position, the team's tactics, utility and coordination, how the team executes
    the round, its form on the day, and momentum.
  - **Players:** form on the day comes from consistency, morale and personality (streaky or
    steady). Traits matter: clutch, pressure, tilt, calm, flick and spray specialists,
    aggression, team play.
  - **Calibration** (400 maps per gap): even sides split, with about 42% of maps within three
    rounds. A 3-point gap wins about 58% of maps, a tier (about 8) about 80%, 15 points about
    95%. Average rating is 1.00 and there is about one ace per 10 maps.
  - **Results:** each map's score, MVP and moments are stored, along with a line for every
    player (kills, deaths, assists, damage, KAST, openings, clutches, rating). These are kept
    apart from the statistics of played matches.
  - **Morale:** moves with every map, scaled by personality, and fades monthly.
  - **Reputation and opinion:** standout or poor series move a player's reputation. Monthly,
    the world's opinion follows recent form, within 8 points of the truth.
  - **News:** upsets, star performances, aces and 1v4+ clutches (tiers 1–2).
  - **In the hub:** Calendar shows map scores and the MVP, Competitions top performers, and
    player pages their simulated form and morale.
  - The development "simulate match" uses the same engine.
- [x] Each save starts differently (`CareerStart.vary_world`):
  - three to six tier swaps between adjacent tiers;
  - random starting form;
  - contract end dates moved by −90 to +150 days;
  - young players who may secretly have the top of their authored potential range.
- [x] AI transfers between organisations, weekly all year round (owner, 2026-11-17: windows are
      the busiest time, but the market is never locked):
  - Each week an organisation has a 30% chance to act in the January and July windows and 1.5%
    outside them. Poor form (≤ −30) adds 10% in a window and 6% outside one.
  - It replaces its weakest AI starter with a clearly better player (4+ perceived) who wants
    the step up: a better tier, or the same tier and more reputation.
  - Failing that, it benches the starter for a clearly better free agent. Sellers agree more
      readily when the contract is nearly over and less for their best player. The displaced
      starter is benched, or released from a squad of seven. Players settle for 120 days, and
      nobody over 31 is bought.
- [x] Organisation finances (`WorldFinance`):
  - an opening balance by tier and reputation;
  - monthly income (sponsors and audience) and wages;
  - series prize money;
  - transfer fees by rating, age and contract left, paid buyer → seller;
  - a ledger of every movement.

  Buyers must keep three months of the new salary after a fee. Salaries shrink when money is
  tight. Organisations in debt renew less and sell more readily.
- [x] Human salary paid monthly into their own balance. Contract talks: ask once for about 20%
      more; the organisation may refuse, and the offer stays open.
- [x] Season endings (`WorldSeasons`): when every series is scored, the final table becomes
      the season record.
  - **Prize pool by tier:** $1m / $300k / $80k / $15k. The top four get 35 / 20 / 13 / 9%, and
    the rest is shared evenly by the other places.
  - **Reputation:** +5 / +3 / +1 for the podium, −3 for last.
  - **Honours:** every player in a podium squad gains an honour and reputation. A human in the
    squad gets a bonus of 20% of the prize split across the squad.
  - **Where it shows:** Competitions shows final standings with prizes and the season records
    (podiums); player pages list honours.
- [x] Spending the human's own money (`CareerSpending`), with income from salary, season
      bonuses and amateur wins ($150 each). Effects stay on the career layer only:
  - personal coach ($600 a month): training gives +2;
  - PR agent ($400 a month): reputation +1 a month below 70;
  - bootcamp ($2,500, every 180 days): four teamwork-side perceived attributes +1 and more
    confidence.

  Services you cannot pay end, with a headline.
- [x] Cup prize money and promotion and relegation from final tables (see M13).

## Milestone 16 — Official content creation 🔶

**Goal:** 5–7 official competitive maps built with the shipped Creation Studio. The first slice
makes the map creator a capable level-design tool, adds AI pathing and tactics support, and ships
the first official map.

### Editor gap audit (2026-11-15, before the first slice)

What the M3/M8 editor could do: place one piece at a time from a 15-piece catalogue, select one
piece, drag it on the build plane, rotate in 90° steps, duplicate, delete, edit position/size in
the inspector, undo/redo, save/open, structural validation, playtest from the first attacker spawn.

Gaps against building a full competitive map:

| Area | Gap |
|---|---|
| Selection | Single selection only: no box select, shift-click, group move/rotate/duplicate/delete. |
| Reuse | No copy/paste, no way to carry work between maps, no prefabs or groups. |
| Transform | No gizmos; rotation locked to 90°; five fixed grid sizes; no angle snap, snap-to-surface on move or snap-to-edge; no measuring; no overhead view. |
| Catalogue | Grey-box only: no openings (doorways, arches, windows), no props beyond crates, no vehicles, awnings or sightline blockers; one checker look, no materials. |
| Lighting | Fixed sun and ambient in the scene; no placeable lights (tunnels and interiors cannot be lit). |
| Safety | No autosave or crash recovery; no layers, so large maps cannot be decluttered or locked. |
| Playtest | Always the first attacker spawn; cannot test the defender side or a specific spawn. |
| Pathing | Navmesh is invisible until bots fail; the validator knows nothing about reachability, islands, bot-unpathable jumps or route timings. |
| Tactics | Callouts have no stable role or tactics use; no anchors or AI hints; tactics are bound to one exact map revision, so any map edit orphans them without saying what broke. |
| Content | No official-map location or registry; practice, tactics and fixtures only know the dev arena. |

### Completion criteria (first slice)

- [x] Stage A: multi-select, group edits, copy/paste, prefabs, gizmos, snapping, numeric transform,
      measuring, overhead view, desert-town catalogue with matching collision, materials, lighting,
      autosave/recovery, layers, playtest as either team from any spawn.
- [x] Stage B: navmesh overlay, reachability/island/bot-unpathable validation, route timing readout,
      AI hints, callout areas, tactical anchors, map content version and tactic compatibility.
- [x] Stage C: first official map (Kilnmarket) authored through the Creation Studio, validated,
      selectable for practice, tactics and career fixtures.
- [x] Direct geometry tools for drawing snapped floor and block footprints or wall segments
      with size controls, live previews and a single undo step per stroke.
- [x] Refresh the visible bot navmesh after edits, undo and redo. Run a bot match straight from
      the unsaved map with the chosen side and spawn, then return to the same draft.
- [ ] Owner walkthrough of the editor checklist and the map (README).
- [ ] Remaining official maps (4–6 more).

### Kilnmarket — route timings (2026-11-15, map content version 1)

From the editor's timing readout: shortest navmesh path from the nearest spawn, at the measured
6.35 m/s (G17) and 5.46 m/s (AK-47, mobility 0.86). Acceleration is not modelled.

| Route | Length | G17 | AK-47 |
|---|---|---|---|
| Attackers → Kiln Gate (long A approach) | 88.6 m | 13.9 s | 16.2 s |
| Attackers → Potter's Door (short A route) | 70.5 m | 11.1 s | 12.9 s |
| Attackers → Weigh Door (A from mid) | 83.6 m | 13.2 s | 15.3 s |
| Attackers → Culvert Mouth (B tunnel) | 72.8 m | 11.5 s | 13.3 s |
| Attackers → Dyers' Door (B from mid) | 91.2 m | 14.4 s | 16.7 s |
| Attackers → Dogleg (mid) | 46.1 m | 7.3 s | 8.4 s |
| Defenders → Site A | 49.8 m | 7.8 s | 9.1 s |
| Defenders → Site B | 50.2 m | 7.9 s | 9.2 s |
| Defenders → Dogleg (mid) | 43.8 m | 6.9 s | 8.0 s |
| Rotation Site A ↔ Site B | 89.4 m | 14.1 s | 16.4 s |
| Crossing Kiln Gate ↔ Culvert Mouth | 113.9 m | 17.9 s | 20.9 s |
| Crossing Potter's Door ↔ Culvert Mouth | 101.5 m | 16.0 s | 18.6 s |
| Mid link Weigh Door ↔ Dyers' Door | 59.2 m | 9.3 s | 10.8 s |

Reading: defenders are on either site about 3.3 s (A) and 3.6 s (B) before the first attacker
can reach an entrance. The long A approach costs attackers 2.8 s more than the short route. A
defender rotation (14.1 s) beats crossing between the two main approaches (16.0–17.9 s) but is
far from instant. Holding the middle is what shortens it: door to door through the Crossing is
9.3 s, for either side. Mid is contested (6.9 s vs 7.3 s).

How the map was made: `tools/author_kilnmarket.gd` drives the shipped Creation Studio scene
through its own operations (palette, place, inspector edits, layers, lighting, copy/paste, a
prefab, validate, save) with explicit coordinates for every piece, then copies the saved file to
`data/maps/official/`. It was authored and tuned headlessly from the timing readout; nobody has
yet walked it in a window, so sightlines and feel are unverified until the owner's walkthrough.

## Milestone 19 — Database and Competition Editor ⬜

**Goal:** Every world database, including the shipped default, can be created and curated in the
game. This meets the rule that official content is made with the shipped editors.

Planned scope:

- [ ] Creation Studio section that opens, creates and saves `.f2fdb` world databases (never a
      live career save).
- [ ] Edit organisations (name, short name, region, tier, colour, reputation range) and their
      starting rosters (role, substitute, salary, contract dates).
- [ ] Edit professionals: identity, nation, age, preferred role, a min–max range for every
      ability and for potential, reputation range and traits (conflicts blocked).
- [ ] Edit competition definitions (league or cup, region or international, tier, team count,
      start month) using the M13 formats.
- [ ] Live validation using `WorldDatabase.validate()`; a database with problems cannot be
      published or chosen for a new career.
- [ ] Database metadata (name, author, description, version) and export for sharing; import
      already exists (M9).
- [ ] Curate the shipped default database in the editor and mark it official, replacing the
      generated draft.
- [ ] Automated tests for every edit operation, validation and round-trip save/load.

---

## Progress log

| Date | Entry |
|---|---|
| 2026-11-15 | Milestone 1 implemented; automated checks passing; awaiting manual acceptance. |
| 2026-11-15 | Milestone 1 accepted. Milestone 2 implemented; automated checks passing; awaiting manual two-instance test. |
| 2026-11-15 | Owner asked for continuous milestone work. Milestone 3 implemented; 234 automated checks passing; awaiting manual editor walkthrough. |
| 2026-11-15 | Milestone 4 implemented; 340 automated checks passing; awaiting manual feel test. |
| 2026-11-15 | Milestone 5 implemented; 468 automated checks passing; awaiting manual practice-match walkthrough. |
| 2026-11-15 | Milestone 6 implemented; 514 automated checks passing; awaiting manual 5v5 bot practice match. Order changed: M9 → M8 → M7 next. |
| 2026-11-15 | Career database = SQLite (owner). Milestone 9 implemented; 614 automated checks passing; awaiting manual career walkthrough. |
| 2026-11-15 | M9 stabilisation verified on Godot 4.7.2 with 663 automated checks. World-template creation, backup and restore failures, reconnect isolation, practice pause and replay, and content replacement covered. Manual acceptance remains open. |
| 2026-11-15 | M8 implemented and the full Godot 4.7.2 validation passed with 700 checks, including 37 tactic checks. Manual acceptance remains open. |
| 2026-11-15 | Owner deferred M7 pending representative maps and gameplay-relevant player traits. M10 implemented and validated on Godot 4.7.2 with 732 passing checks. Manual fixture walkthrough remains open. |
| 2026-11-15 | M11 records career match telemetry, statistics and F2F ratings. Godot 4.7.2 validation passed 748 checks. Manual acceptance remains open. |
| 2026-11-15 | M12 adds amateur ELO, match-driven career opinions and reputation, training and scouting. Godot 4.7.2 validation passed 764 checks. Manual acceptance remains open. |
| 2026-11-15 | M13 publishes fixed-database league seasons and derives standings from accepted series results. Godot 4.7.2 validation passed 782 checks. Match and cup integration remain open. |
| 2026-11-15 | Owner approved a Database and Competition Editor milestone (M19), placed before M17. |
| 2026-11-15 | M13: day-by-day calendar with simulated AI series and calendar conflicts. Godot 4.7.2 validation passed 886 checks. |
| 2026-11-15 | M16 first slice: map creator tools (multi-select, clipboard, prefabs, gizmos, snapping, measuring, top view, 54-piece catalogue, materials, lighting, autosave, layers), AI support (navmesh analysis, timings, areas, anchors, hints, tactic compatibility) and the first official map, Kilnmarket. Godot 4.7.2 validation passed 1203 checks. Manual editor and map walkthrough remains open. |
| 2026-11-15 | FPS Sandbox map select, a Controls screen (remapping, up to four bindings per action, saved) and sandbox noclip (V). Owner request, outside the milestone list. |
| 2026-11-16 | Weapons, Coats and Magnets (owner request): ten modelled weapons in first person with inspection, Coat infrastructure for the simplified kits (no Coats shipped), 26 Magnets on five slots per weapon, Armoury screen, saved customisation. |
| 2026-11-16 | M14 first slice, the living world: daily form, reputation and market, monthly development and opinion drift, yearly retirements and rookies, the news log, and Continue. Save schema v7. |
| 2026-11-17 | M14 second slice, the path to pro: visibility, trial invitations, playable trials, contract offers, signing, and playable league series map by map. Save schema v8. |
| 2026-11-17 | M14: AI transfers between organisations in January and July windows (no fees until organisations have finances). |
| 2026-11-17 | M14: organisation finances, transfer fees, human salary and contract talks. Save schema v9. |
| 2026-11-17 | Transfers run weekly all year. Windows stay the busiest; struggling teams bench a starter and sign someone new mid-season. |
| 2026-11-17 | Development option (owner request): Simulate match on Home and the Calendar resolves your pending match like a world series, for quick day testing. Debug builds only; may become a feature later. Simulated results count for ELO and reputation (owner). |
| 2026-11-17 | M14: the round-by-round match engine for every simulated series: economy, duels, trades, clutches, day form, morale, traits, per-player simulated lines, opinion from form, and upset/star news. Save schema v12. |
| 2026-11-17 | M13/M14: cups with brackets, promotion and relegation by tier swaps, fuller leagues, transfer offers, renewals, releases and benching for contracted humans, and a different start for every save. Save schema v11. |
| 2026-11-17 | M14: season endings with records, prize pools, reputation rewards and honours. Human spending: coach, PR agent, bootcamp; amateur wins pay. Save schema v10. |
| 2026-11-15 | Shared movement: measured `PlayerMovement` model used by the player and every bot, with weapon mobility. Godot 4.7.2 validation passed 864 checks. Manual feel test remains open. |
