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
| 20 | Manager Career mode | 9, 13, 14 (live viewing: 7) | ⬜ |
| 21 | Deep world match simulation | 9, 11, 13, 16 | 🔶 in progress |

**Execution order (updated 2026-11-21):** 1 → 6 → 9 → 8 → 10 → 13 → **21 → 7 → 14 (veto, formats) → 20 → 15 → 16 → 19 → 17 → 18**.
Owner, 2026-11-21: every match played outside the player's own game must play out like a real
one from each player's abilities (Football Manager style) before map veto and formats; then the
bots learn to play as a team (M7) with pro-style executes, built as editable plays.
M20 (Manager Career, owner 2026-11-20) comes before M15 so co-op is built for both career types.
M19 comes before M17 because community databases are made with the editor.
M7 follows M21 and shares its map model and round plans. Its first test bed is the owner's
local Dust II layout study (`user://maps/map_dev_dust2_2020`): local only, never committed, and
no shipped content, test or play depends on it. Milestone numbers stay stable for reference.

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
- [x] Utility and the knife (owner, 2026-11-20):
  - **Knife** (slot 3, always carried): a quick slash that repeats while held and a heavy stab.
    A hit on a victim facing away is a backstab (a stab in the back kills). Knife kills pay
    $1,500.
  - **Utility** (slot 4, press again for the next kind): flashbang ($200, carry 2), smoke
    ($300), frag ($300) and incendiary ($500); four pieces at most. Hold to ready, release to
    throw: full, lob (right button) or medium (both). Flight is deterministic.
  - **Effects:** a frag blast falls off with distance and is stopped by walls. A flash blinds
    by distance, facing and cover, the screen whites out and flashed bots lose their target.
    Smoke blocks sight (bots included) but not bullets. An incendiary spreads over the floor
    and burns anyone standing in it; smoke puts fire out.
  - **Rules and statistics:** survivors keep unused utility. Throws, flashes and utility damage
    are logged. Utility thrown, utility damage, enemies flashed and flash assists are counted
    (flash assists give KAST credit).
  - Bots carry the knife but do not buy or throw utility yet (team tactics, M7).
  - **Inspections** are data (`InspectLibrary`): each grenade has its own; guns keep the
    left-then-right turn.
  - **Knife looks:** seven knife models (Combat, Bayonet, Butterfly, Karambit, Nomad, Skeleton,
    T-Handle Dagger) to choose from in the Armoury, each with its own inspection (the butterfly
    knife flips its handles) and a Coat kit with paint-zone masks. The look never changes how
    the knife plays. The FPS Sandbox shop has a knife column for trying them.
- [ ] Manual practice-match walkthrough (README) by the project owner.
- [ ] Manual utility and knife walkthrough (README).
- [ ] Manual knife looks walkthrough (README).

Out of scope (later): opponents that fight back (M6 AI), teammates, networked matches (rules run
on the match host later), dropping/picking up weapons, spectating dead players, career fixtures
and their result submission (M10).

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

## Milestone 21 — Deep world match simulation 🔶

**Goal:** every match nobody plays (the whole world's fixtures, and "simulate" for the player's
own) plays out round by round like a real one, decided by each player's abilities, role, traits,
form and the team's tactics, on a real map. Not flat bonuses: who does what, where, with what.

Stages (each validated and committed on its own):

- [x] **A. Map model.** A simulation graph per official map, baked from its navmesh: areas
      (callouts, bombsites, spawns), which areas connect and the travel time between them, each
      site's entrances. Pure data in `data/maps/sim/` (`format_version`), read by the career
      layer; `tools/bake_sim_maps.gd` rebuilds it. Every editor map can be baked the same way.
- [x] **B. Round plans and positions.** Defence setups (who holds which area, stacks, rotators)
      and attack strategies (default, execute, split, rush, fake, lurk) chosen by the IGL from
      economy, score, map, team style and what has worked; mid-round calls on information
      (rotate, retake, save). `RoundPlanner` + `RoundPlan`; lurking is a job inside the other
      kinds. Plans are logged per round; fights still come from the duel chain until stage C.
- [x] **C. Players in places.** Rounds advance in time steps; players move along the graph.
      Fights happen where opponents meet: who sees whom first (positioning, crosshair placement,
      game sense against the peeker's aggression), several exchanges with damage that carries
      over, headshots from aim, weapon match-ups, crossfires and trades from teammates nearby.
      `RoundSim`, 1 s steps; weapons from the team's buy and the player's role until stage D.
      Even teams: attack wins about half the rounds, headshots about half the kills.
- [x] **D. Individual economy and utility.** Each player's own money, weapon, armour and
      grenades; drops; personal saves. Grenades thrown by players with their own utility skill:
      flashes blind named players, smokes cover executes, fire delays pushes, frags damage.
      `SimEconomy` with the game's own prices, rewards, weapons and damage rules. Map balance
      still varies a lot between maps (attack 32–61% on the official ones): stage H.
- [ ] **E. Same events as a played match.** The engine emits the FPS runtime's event stream and
      `MatchStatistics` builds every line from it, so simulated and played statistics agree by
      construction (headshots, utility, flash assists, entries, clutches, trades).
- [ ] **F. People over a match.** Confidence that grows with good rounds, tilt, nerves in big
      rounds, fatigue over a Bo3/Bo5, map familiarity for teams and map comfort for players,
      all from traits and history.
- [ ] **G. Match view.** A round-by-round timeline with each round's plan, kill feed (weapon,
      headshot, utility), economy per player and the scoreboard, for any simulated match.
- [ ] **H. Balance harness.** Thousands of headless matches checked against targets: side
      balance, round and score distributions, rating spread, upset rate, stat ranges by role.

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
- [x] ~~Offer one training focus per career day in Player Profile.~~ Replaced on 2026-11-18 by
      real training (owner: "real training, not 'I'm training aim today'"):
  - **Training Ground** page (sidebar ME): flick range (60 s), reaction test (12 reps, false
    starts), tracking lane (30 s strafing target) and a movement course (checkpoints, falls
    reset to the last one, par time). Each is played in the FPS and scored 1–100.
  - **Scrims:** MR8 5v5 against an organisation near your tier, your teammates as bots.
  - Every session is recorded with its measured numbers and personal bests, and every session
    is evidence for the world's view of your aim, reaction or movement. There are no fixed
    steps (owner, 2026-11-18: "it should be based off of how everything goes"). How far a run
    moves the view depends on its gap from what the world believes, how sure the world is,
    whether it fits your record or looks like a fluke, how often you ran it today and whether it
    was reviewed.
  - Scrims with your own team move each teammate's feelings toward you. The change comes from
    the result and margin, how you played against them, and who they are: temperament, ego,
    sociability, professionalism, mood and your existing relationship.
  - Training maps are editable in the Creation Studio (new course start, checkpoint and finish
    pieces). Save schema v13.
- [x] Offer one scouting report per career day in Players. Reports refine estimates toward AI
      ability and increase confidence while preserving underlying ability and hidden potential.
      How far they move and how much confidence they add depends on the evidence: the player's
      maps in the last 90 days and their tier's visibility. Thin evidence can stall an estimate's progress.
- [x] Amateur results move reputation by surprise (an upset win says more than an expected
      one), margin and rating, less the better known you are. Confidence grows with rounds
      played, and opinions move by sample size. No fixed ±1 or +3 (owner, 2026-11-18).
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
      is recorded. Perceived values drift towards the truth, faster for players the world
      watched play that month. Confidence grows with maps played, up to their tier's visibility
      cap, and goes stale in months a player is not seen.
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
- [x] Manager-game hub layout (owner, 2026-11-17: layout in the style of football and esports
      management games):
  - **Top bar:** Back and Forward, the page title, the date, **Holiday** and **Continue** at the
    top right. Holiday runs until the next inbox message (a headline), for 1 week to 6 months,
    or to the end of the year. Your own match still stops it; a development checkbox simulates
    it instead.
  - **Sidebar headings:** Career (Home, Inbox, Calendar), Me (Profile, My Team), World
    (Competitions, Teams, Players, News), Data (Statistics, Co-op).
  - **Linked pages** with a history: Teams → a team (Overview, Squad, Matches, Finances,
    History) → a player (Overview with scouting, Stats, Maps, Career, News) → Compare with
    another player. Match reports show every map, the MVP, moments and each player's line.
  - Every team, player and series name in tables, standings, brackets, news and the Calendar
    is a link.
  - Interviews are not built yet; a player's News tab shows the stories about them.
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
- [x] Every AI professional is a person (owner, 2026-11-18: "each and every character in the
      database is its own person"), via `CareerPeople`:
  - **Personality:** ambition, loyalty, professionalism, temperament, ego and sociability,
    shaped by traits. Also a drive (winning, money, fame, team, love of the game), a background
    and a career goal.
  - **Mood:** monthly happiness from playing time, team results, pay against teammates of the
    same level, outgrowing the tier, friends and rivals in the squad, and form. Unhappy players
    want a move.
  - **Relationships** between teammates grow from personalities and results, so friendships and
    rivalries form. A line-up's chemistry adds to or takes from its coordination in the match
    engine.
  - **Life:** practice streams, burnout, veterans mentoring rookies, public fallings-out, and
    goals achieved. Each makes news.
  - **Interviews** in each person's own voice (brash, humble, fiery or measured), given after
    star games and upsets, when unsettled, on joining a club, and when a goal is reached.
  - **Market effects:** unsettled players turn renewals down and are easier to buy. Loyal,
    happy players often refuse moves.
  - **In the hub:** the player page shows the person and their relationships, the squad shows
    moods and the dressing room, and the News tab shows interviews.
  - Save schema v14.
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
  - personal coach ($600 a month): your drills are reviewed, so each one says more about you;
  - PR agent ($400 a month): sells your month (maps played, rating, wins). It works best while
    your reputation lags your perceived level and backfires when it runs far ahead;
  - bootcamp ($2,500, every 180 days): a week-long programme of real sessions you play
    yourself (every drill and a scrim within 7 days; owner, 2026-11-18). Programme sessions
    are reviewed by the camp's staff. Finishing it judges the week as a whole: confidence
    follows how steady you were, the verdict follows how you did against your reputation, and
    each teammate reacts according to their professionalism and how well you worked. Booking
    alone changes nothing. Save schema v15.

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
- [x] Second and third official maps: Switchyard (surface A, underground B) and Kestrel Keep (stone
      fortress), both original layouts (owner, 2026-11-18: continue the two drafts). Building
      them added the pieces the editor could not make and a slope warning (below).
- [ ] Remaining official maps (2–4 more).

**Switchyard** (`map_f2f_switchyard`, `tools/author_switchyard.gd`, revision 4): a rail
switching station over a turbine works, about 120 × 160 m inside an irregular fifteen-sided
perimeter. Most of the play is on the surface; site B is 8 m underground. Site A is the Machine
Hall, a seven-sided shed with five ways in (Loading Gate, the Breach in its angled south-west
corner, Coal Door, Pump Door, North Door), overlooked by the Control Deck on its roof (5 m, open
atrium over the site; reached by an inside stair, the West Stair, the Deck Ramp and an angled
Service Stair). Site B is the Turbine Vault, a seven-sided hall 30 × 32 m and 7 m tall with a
gantry 4 m up along its north wall and six doors: Main and East Doors from the Junction (under
the Freight Yard, reached by the Freight Ramp), West Door from the Coal Tunnel (Coal Stair in
the Coal Lane, or the Coal Chute drop into the Chute Room), Culvert Door at the end of the bent
East Culvert (ramp in the Tank Yard), North Door from the defenders' North Stair, and the West
Stairwell from inside the hall. The angled Cable Gallery joins the Junction to the Coal Tunnel,
so the underground has its own loop; the Vent is a drop from beside site A into site B.
Buildings, tunnels and floors are drawn with the editor's angled walls, Draw Surface polygons
and brushes, so little of the map is square. Timings: defenders reach A in 8.8 s and B in
8.6 s; attackers' first A entrance is 11.5 s (Loading Gate) and first B entrance 11.2 s (Main
Door); the long Culvert flank is 15.6 s. Rotation A to B is 7.5 s.

**Kestrel Keep** (`map_f2f_kestrel_keep`, `tools/author_kestrel_keep.gd`, revision 2): a granite fortress
above a village. Site A is the Tiltyard, reached by the West Gate road (long, 14.0 s), the Breach
in the curtain wall (short, 10.9 s) or the Bailey Arch. Site B is the Cloister, reached by the
Orchard Walk and Lych Gate (13.9 s), the Undercroft tunnel (10.7 s) or the Bailey Arch. The
Gatehouse is mid: a portcullis passage under a walkable gallery that overlooks the market.
A rampart overlooks the Tiltyard. Defenders reach A in 8.5 s and B in 8.6 s. Rotating through the
Bailey takes 13.9 s, against a 15.1 s attacker crossing from the Breach to the Undercroft.

**Cluts** (`map_f2f_cluts`, `tools/author_cluts.gd`, revision 19): a harbour chronometer
exchange traced from the owner's ground-floor sketch, about 100 × 70 m, with a tidal basin and
quayside skyline beyond the perimeter. Site A is the Dispatch Yard on the surface, entered by
the Hoist Gate, Dispatch Bend and the Yard Door from the Ramp Yard. Site B is the Darkroom in the
plate works 5 m below, reached by the West Shaft stair and Cable Passage, the Dispatch ramp, the
defenders' North Stair and the Pump Stair from the east lane. Revision 11 added the Yard Door and
Pump Stair (third ways into A and B) without changing the traced layout: defenders reach A in
8.6 s and B in 7.7 s; attackers reach their first A entrance in 11.9 s and first B entrance in
13.4 s; rotating takes 7.6 s. Its pieces: iron paling fence, freight gate, louvred shutter,
lettered enamel sign, transit telescope, time ball and a covered stair prefab.
Revision 12 (owner: make it feel like a real place) turns the street walls into building faces
with their own heights (3–7.6 m), pitched ridges with chimneys or flat cornices, upper windows and
shuttered doors, and pitched roofs on the perimeter buildings. The Plate Receiving House is now a
two-storey building whose outer wall is the curved lane wall, with a slate roof, the stair door
on the quay and a side door to a packing room over the stairwell. The Tide Office corner, once a
dead end, has the Tide Well: an open shaft that drops 5 m into the Gauge Chamber, which joins the
plate works beside the West Shaft stair. A raised Exchange Terrace (1.4 m, stairs at both ends)
lines the south hall and a loading dock (1.2 m) stands in the Dispatch Yard.
Revision 13 (owner: thin walls dressed as buildings made no sense, and louvred shutters were
standing in for windows and doors) makes every line between lanes a yard wall: brick on a granite
plinth with limestone coping (granite along the quay), 3.6–4.6 m so nobody can jump-peek over,
with piers at corners, every 5 m and either side of gateways. Only real buildings carry windows
and doors: the perimeter blocks (now 5.8–9.4 m, one to three storeys, string course, pitched roofs,
chimneys), the Plate Receiving House and the Tide Office. Shop shutters on yard walls became
closed yard gates. The editor gained the pieces this needed: **Window** (framed and glazed, panes
across and down, optional open shutters), **Door** (closed, stone frame, panelled leaf, optional
fanlight, walkable step) and **Wall pier** (granite base, shaft, stone cap), plus a glass material.
Revision 14 (owner: open up the walled corner by Lens Delivery; surfaces too flat) removes the
quay wall between Lens Delivery and the Tide Office yard, caps every yard wall with uneven
individual stones, and sets surface relief on every finish (masonry deepest). New in the editor:
**Surface relief** on every solid piece (Inspector, 0 flat to 3 deep): deeper normal maps plus an
occlusion map that keeps grooves dark in direct light, sharing the palette's textures. True
parallax depth is not available because Godot does not support height maps with the editor's
world-space triplanar mapping. Also **Coping stones**: a run of separate, uneven capping stones
(stone length and a variation seed in the Inspector).
Revision 15 (owner: change the ground and give it features; dirt should mound up and down, roads
should be solid; the map needs to look like a real place, perhaps with better lighting) lays the
streets in granite-sett roadway, puts flagstones in the Reading Room square and along the south
exchange row, gravel in the two service lanes behind the north buildings, and trodden dirt in the
Tide Office yard, the Weighbridge yard and the Ramp Yard, where low mounds (0.25–0.8 m) rise and dip.
Masonry relief is toned down so mortar no longer reads as drawn lines. Timings are unchanged
(defenders reach A 3.5 s and B 5.8 s before the first attackers).
The editor gained what this needed: ground textures **Granite setts (road)**, **Trodden dirt**,
**Loose gravel**, **Worn grass** and **Flagstone pavement**, and the **Uneven ground (mounds)**
piece (Slopes group): height is the tallest a mound may rise, with distance between mounds, flat
border, variation seed and an oval option in the Inspector. Its edges and hollows sink 2 cm below
the base so the join with the floor follows the mounds, it collides exactly where it is drawn, and
mounds too steep to walk (over 21°) are lowered so players and bots cross all of it. Every map now
also gets the shared **atmosphere** (editor and game alike): a sky tinted by the sun, soft
four-split sun shadows, ambient occlusion, real-time global illumination (SDFGI) so rooms and
covered passages fall into shade, distance haze (new **Distance haze** lighting setting), gentle
bloom and filmic tonemapping. The overhead plan view turns the haze off.
Revision 16 (owner: redesign the whole Dispatch area and move the bombsite) rebuilds the south-east
as one working yard. The open goods-ramp pit is roofed over by a brick **Goods Ramp** house
(6 m walls, slate gable, timber ceiling, wall lamps) entered at the ramp head from the street, so
the Dispatch ramp to B is now an indoor route. A straight **Dispatch Lane** runs along its north
side and the Ramp Yard along its south; they enter the **Dispatch Yard** at the Lane Mouth and the
Yard Door. Site A moves out of the corner by the loading dock to the middle of the yard (46, 26),
between the Hoist Gate (now a gated opening with granite piers in the wall to the weighbridge
yard), a small dispatch office, a cart, crates and the loading dock. Defenders reach A in 8.0 s and
B in 7.8 s; the first attackers reach the Lane Mouth 3.5 s after defenders reach A; rotating takes
8.4 s.
Revision 17 (owner: the new ground textures sat on top of the old floor) makes each finish part of
the floor itself. Revision 15 had laid the flagstones, gravel and dirt as 5 cm slabs over the sett
floor, so their raised edges showed. Now the author script cuts each region out of the sett floor
and draws it level with the road (Draw Surface pieces, as a mapper would in the Creation Studio),
and the mounds rise straight out of the dirt.
Revision 18 (owner: more dirt but no square patches, props throughout, the ground-floor site in
the Harbour Office) draws every dirt and gravel region as an irregular rounded patch instead of a
rectangle and adds a dozen worn dirt patches where people walk (lane mouths, the courtyard tree,
benches, yard gates). Every street and yard now has props: crates, barrels, carts, benches, a
market stall, trees, troughs and jars. Site A moves to the **Harbour Office** yard in the
north-east (the old defender spawn), with a small limewashed Harbour Office, a braced crate, a
crate stack, a cart, barrels and a trough for cover; it is entered from North Lane, the Stair Head
and the Harbour Gate. Defenders now spawn in the Dispatch Yard. Defenders reach A in 8.4 s and B in
7.5 s; the first attackers reach North Lane 6.5 s after defenders reach A and the Drying Passage
6.2 s after defenders reach B; rotating takes 8.5 s. The author script's floor cutting also became
robust to awkward shapes (it cleans near-duplicate points, splits shapes with holes and falls back
to convex pieces when Draw Surface would refuse an outline).
Revision 19 (owner: light the dark spots on every map, more props to make it feel alive, and no
doors on walls that lead nowhere) removes the three closed freight gates that were stuck flat
against yard walls (Chronometer Exchange, Chronometer Returns and Glass Plates / Goods In): the
walls only divide one lane from another, so a door in them led nowhere. Notice boards and wall
lanterns take their place. The doors and ground-floor windows behind the Exchange Terrace and the
loading dock now open at deck height instead of below it, and the barrels in front of those doors
moved aside. The plate-room baths now stand against the wall, closing a crouch-only gap behind
them. Lamps and props were added to all four maps; see "Lamps and street life" below. Timings
are unchanged (defenders lead by 6.3 s at A and 6.2 s at B).

**Lamps and street life (all maps, 2026-11-20).** Every map was checked for dark spots: each
reachable floor point (2 m grid, bot navmesh) that is in the sun's shadow and out of reach of
every lamp. Lamp fixtures now cover those spots, on the nearest wall or hung from the ceiling
indoors, with wider spacing in shaded open-air lanes. Shaded, unlit floor fell from 22% to 3% on
Cluts (mostly the plate works), from 9% to 5% on Switchyard (the vault and the machine hall), and
from 3% to 2% on Kestrel Keep and Kilnmarket. These counts leave out open-air shade, which is
lit separately with wider spacing. Between 24 and 34 props per map now stand against walls along the
routes: benches, planters, sacks, notice boards and barrels in the town; crates, barrel clusters
and sacks in the industrial areas; jars and shelves in the market; sacks, barrels, troughs and
braziers in the keep. Props keep at least 3 m of open floor in front of them and stay clear of
doors, stairs, bombsites, spawns and timing chokepoints. Every map was re-authored and passed
navigation, timing and the bots-reach-both-sites test. The editor gained the pieces this needed:
**Lights**: Wall lantern, Street lamp, Hanging lamp, Caged bulkhead lamp and Brazier (solid
fixtures with their own light; Brightness, Light range and Light colour in the Inspector).
**Props**: Wooden pallet, Pile of sacks, Planter box, Park bench, Notice board, Iron bollard and
Washing line (the washing hangs at or above 2 m). Two new materials, Lit lamp glass and Glowing
embers, glow on their own.

**What the editor could not make, now added** (all in the palette, with matching collision):
- battlement walls (crenellated, adjustable merlon height);
- round towers;
- a gate with a raised portcullis (adjustable clearance, at least 2 m);
- railings you can see and shoot through;
- catwalks (railings switchable per side);
- pipe runs (on legs when taller than the pipe);
- storage tanks, shipping containers, trees and hanging banners;
- materials: steel grating, hazard stripes, granite blocks, mossy fieldstone, slate and foliage.

Building the Keep also showed that stairs steeper than about 24° split the bot navmesh, because
the bots' 0.1 m climb limit is half a 0.2 m navmesh cell. Validation now warns with the length
a stair needs. Kilnmarket's Overlook stair (26.6°) was lengthened to 6 m (content version 2).

Sublevel Test Bay stays under `authoring/maps` as a geometry fixture for a covered passage,
layer occlusion, stair and ramp access and a notched surface.

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
| Defenders → Site B | 50.5 m | 7.9 s | 9.2 s |
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

## Milestone 20 — Manager Career mode ⬜

**Goal:** A second career type in the same world (see `GAME_VISION.md` section 3A): the human
manages an organisation instead of playing as a professional.

Planned scope:

- [ ] Career type on the save (player or manager) with a migration; a manager record with
      reputation and history, separate from player records. `CareerSession` no longer assumes a
      human player.
- [ ] Human-run organisations: `WorldMarket`, renewals, roster filling and benching skip them;
      incoming bids and requests go to the manager's inbox instead.
- [ ] Squad page: starting five, substitutes, roles and IGL, used by every fixture.
- [ ] Transfer and contract pages: scouting search, bids with fees, wage offers, renewals and
      releases, using the existing finances.
- [ ] Team tactics as real match-engine inputs (style, aggression, utility, economy discipline,
      per-map approach); the derived player-based tactics rating stays and combines with them.
- [ ] Staff: coaches, analysts and scouts as persistent people with traits, hired and paid by
      organisations (also used by AI organisations and the Player Career).
- [ ] Match day: the manager's fixtures resolve through the match engine with a round-by-round
      match view and half-time adjustments.
- [ ] Board expectations by tier and reputation, job security, sackings and job offers.
- [ ] Automated tests for each system; manual walkthrough of a manager season.
- [ ] Later (after M7): watch the managed team's matches live in the FPS runtime as a spectator.

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
| 2026-11-19 | M16: two more official maps, Switchyard (stacked sites) and Kestrel Keep (stone fortress). Eleven new catalogue pieces, six materials and a steep-slope warning. |
| 2026-11-19 | Switchyard rework (owner request): play centres on the surface, site B moves 8 m underground to the Turbine Vault, reached by two ramps, two stairs, a coal chute and a vent. Published as revision 2. |
| 2026-11-20 | Switchyard expanded (owner request): bigger and far less square, an irregular perimeter, a seven-sided hall and vault, angled tunnels, the Junction and Cable Gallery underground loop, six doors into B and five into A. Published as revision 3. The analyser no longer reports navmesh pockets sealed inside closed brushes as unreachable floor. |
| 2026-11-18 | No fixed rates: amateur results now move reputation by surprise, margin and rating, and confidence and opinions by the size of the evidence. |
| 2026-11-18 | No fixed rates, continued: the PR agent, scouting reports and the world's monthly confidence follow evidence (maps played, form, visibility, the gap between reputation and level). |
| 2026-11-18 | No fixed rates in training: evidence, confidence, scrim relationships and the bootcamp's outcome all follow how the sessions went and who the people are. |
| 2026-11-18 | Bootcamp is real training: a week's programme of drills and a scrim you play, tracked on the Training Ground. Save schema v15. |
| 2026-11-18 | M14: people. Personality, drive, goal, mood, relationships, life events and interviews for every AI professional, feeding the market and match chemistry. Save schema v14. |
| 2026-11-18 | Real training: flick, reaction, tracking and movement drills and 5v5 scrims played in the FPS, measured and recorded. Collapsible sidebar headings. Save schema v13. |
| 2026-11-17 | Hub layout: Continue and Holiday top right, sidebar headings, routed pages with Back/Forward, team, player, compare, match report and inbox pages, links everywhere. |
| 2026-11-17 | M14: the round-by-round match engine for every simulated series: economy, duels, trades, clutches, day form, morale, traits, per-player simulated lines, opinion from form, and upset/star news. Save schema v12. |
| 2026-11-17 | M13/M14: cups with brackets, promotion and relegation by tier swaps, fuller leagues, transfer offers, renewals, releases and benching for contracted humans, and a different start for every save. Save schema v11. |
| 2026-11-17 | M14: season endings with records, prize pools, reputation rewards and honours. Human spending: coach, PR agent, bootcamp; amateur wins pay. Save schema v10. |
| 2026-11-15 | Shared movement: measured `PlayerMovement` model used by the player and every bot, with weapon mobility. Godot 4.7.2 validation passed 864 checks. Manual feel test remains open. |
| 2026-11-20 | Owner added a Manager Career mode (M20) alongside the Player Career: the human runs an organisation in the same world. Planned before M15 so co-op covers both. |
| 2026-11-20 | Cluts revision 11 (owner: develop it, keep the layout): the Yard Door gives A a third entrance from the Ramp Yard, and the Pump Stair gives B a third from the east lane. Defenders' site times are now 0.9 s apart instead of the 1.5 s limit. |
| 2026-11-20 | Cluts revision 12 (owner request): building faces with varied heights, rooflines and windows; the Plate Receiving House rebuilt into the curved wall; the Tide Well drop from the dead-end Tide Office corner into a new Gauge Chamber; a raised terrace and a loading dock. |
| 2026-11-20 | Cluts revision 13 (owner request): yard walls with piers instead of thin buildings, a consistent brick, granite and limestone palette, and real windows and doors on the buildings. New editor pieces: Window, Door, Wall pier; new glass material. |
| 2026-11-20 | Cluts revision 14 (owner request): the Lens Delivery corner opened to the Tide Office yard, uneven coping stones, surface relief. Editor: Surface relief on every solid piece, Coping stones piece. |
| 2026-11-20 | Cluts revision 15 (owner request): sett roads, flagstone squares, gravel lanes and dirt yards with mounds. Editor: five ground textures, the Uneven ground (mounds) piece, Distance haze. Game and editor: shared atmosphere with sky, soft shadows, SDFGI, haze and tonemapping. |
| 2026-11-20 | Cluts revision 16 (owner request): the Dispatch area rebuilt as one yard with a roofed Goods Ramp house over the B ramp, and site A moved from the loading-dock corner to the middle of the Dispatch Yard. |
| 2026-11-20 | Cluts revision 17 (owner report): ground finishes are cut into the floor, level with the road, instead of 5 cm slabs on top of it. |
| 2026-11-20 | Cluts revision 18 (owner request): irregular dirt and gravel patches instead of rectangles, more worn dirt, props throughout the map, site A moved to the Harbour Office yard and defenders to the Dispatch Yard. |
| 2026-11-20 | Lamps and street life on all four maps (owner request): lamp fixtures on every dark spot found by a lighting check, wall-side props along the routes, and on Cluts the doors that led nowhere removed or raised to deck height. Editor: five lamp fixtures and seven street props. |
| 2026-11-20 | Utility and the knife (owner request): flashbang, smoke, frag and incendiary with deterministic throws, real effects for players and bots, buying, carry limits and utility statistics; a knife with slash, stab and backstabs. Knife models, Coat kits and inspects follow once the knife pack is in. |
| 2026-11-21 | Developer Character Creator (owner request): three downloaded character packs imported (two CC0 committed, one local-only), retargeted to one animation set, 82 items in 16 slots with per-item colours, presets, randomise and the player's stored look; bots can wear random models behind a developer option. |
| 2026-11-21 | Modular Male hats (owner request): adapted hats now sit on the head (bind-pose fit), the hard hat, straw hat and crown are split off their heads as their own items (six hats), and hats made for bald heads hide the hair. |
| 2026-11-21 | Hands through inspections (owner request): gun inspections turn about the firing hand (pistols let the support hand go, rifles keep both hands on), and knife and grenade tricks keep the item in the fist, turning only as far as a wrist while spins carry on in the fingers and tosses leave the hand. |
| 2026-11-21 | Support-hand fit (owner request): the hands were scanned against each gun's geometry in first person; the support hand now wraps the forend (knuckles along the barrel) or presses against the firing hand on pistols, and long rifles' support grips moved back within reach. |
| 2026-11-21 | Holding weapons (owner request): guns stay raised while running (upper-body clip layer), both hands sit on measured grips for every gun (hand reach, grip frames, finger curl), and the player sees their own character's arms in first person holding the viewmodel through every inspection. Developer-option tests no longer write the player's real option file (`DevOptions.reload` shadowed `Script.reload`). |
| 2026-11-21 | Character models in play (owner request): bots wear character models by default instead of box bodies, dressed in the player's saved Character Creator presets (random looks when none are saved), with team-colour channels in the team's colour. |
| 2026-11-21 | Character models, part two (owner request): crouch poses, weapons held in the hand, team uniforms from career organisation colours, other players' looks over the network (match protocol v2) and career unlocks for four outfits. |
| 2026-11-21 | Knife looks (owner request): seven knife models from a CC BY pack, chosen in the Armoury; a Coat kit and paint-zone masks per knife; a unique inspection per knife, with the butterfly knife's handles swinging on their pins. |
