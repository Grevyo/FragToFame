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
| 14 | World progression, transfers, rookies, retirement | 12, 13 | ⬜ |
| 15 | Full cooperative career integration | 2, 10, 14 | ⬜ |
| 16 | Official content creation (5–7 maps) | 3, 6, 8 | ⬜ |
| 17 | Community content import/export | 3, 9, 16 | ⬜ |
| 18 | Steam integration, testing, release preparation | all | ⬜ |

**Execution order (updated 2026-11-15):** 1 → 6 → 9 → 8 → **10 onward**.
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

- [x] Three original weapons (VK-12 Vanta rifle, P-4 Kestrel pistol, M-5 Wasp SMG) defined as data
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
      Bots buy (rifle/SMG + armour, kits on defence), spawn per side, attack one site per round,
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
- [ ] Connect playable and simulated fixtures to series results. Handle calendar conflicts, map
      selection and configurable BO1, BO3 and BO5 series, MR length and overtime.
- [ ] Add cup and qualifier brackets, promotion and relegation, season records and the F2F Universal Ladder.

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
