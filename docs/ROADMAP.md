# Frag to Fame — Roadmap

Each milestone is a small, independently testable vertical slice. The order may change where
dependencies demand it. The owner asked (2026-11-15) for milestones to be worked through
continuously: each one is validated, committed and pushed, and manual checks are collected in the
README for the owner to run.

Legend: ✅ done · 🔶 in progress / awaiting acceptance · ⬜ not started

| # | Milestone | Depends on | Status |
|---|---|---|---|
| 1 | Runnable application foundation | — | ✅ |
| 2 | Early networking architecture proof | 1 | 🔶 awaiting manual test |
| 3 | Basic runtime map editing | 1 | 🔶 awaiting manual test |
| 4 | Basic FPS mechanics | 1 | 🔶 awaiting manual test |
| 5 | Competitive match rules | 4 | 🔶 awaiting manual test |
| 6 | Individual combat and navigation AI | 3, 4 | 🔶 awaiting manual test |
| 7 | Tactical team AI and IGL | 5, 6, 8, 9 | ⬜ |
| 8 | Tactical Play Creator | 3, 6 | ⬜ |
| 9 | Persistent player/team database | 1 | 🔶 awaiting manual test |
| 10 | Career fixtures and playable match integration | 5, 9 | ⬜ |
| 11 | Detailed statistics | 5, 10 | ⬜ |
| 12 | Career development and scouting | 9, 11 | ⬜ |
| 13 | Competition and tournament systems | 9, 10 | ⬜ |
| 14 | World progression, transfers, rookies, retirement | 12, 13 | ⬜ |
| 15 | Full cooperative career integration | 2, 10, 14 | ⬜ |
| 16 | Official content creation (5–7 maps) | 3, 6, 8 | ⬜ |
| 17 | Community content import/export | 3, 9, 16 | ⬜ |
| 18 | Steam integration, testing, release preparation | all | ⬜ |

**Execution order (changed 2026-11-15, owner agreed):** 1 → 6, then **9 → 8 → 7**, then 10 onward.
Deep team AI (M7) is built after the player/team database (M9) and the tactic document format
and editor (M8), so the IGL plays authored tactics with real player attributes instead of
throw-away logic. Numbers stay stable for reference.

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
career submission of practice results (M10).

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

*Scheduled after Milestones 9 and 8 (see execution order).*

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

## Milestone 9 — Persistent player/team database 🔶

**Goal:** Every career is a persistent, safe SQLite world of original organisations and
professionals that the Career Hub reads and the match layer can draw lineups from.

Completion criteria:

- [x] `godot-sqlite` GDExtension (MIT) installed; `CareerDatabase` is the only class that touches
      SQLite (WAL, foreign keys, nested transactions with rollback, `VACUUM INTO` snapshots,
      integrity check).
- [x] `CareerSchema` v1 with migrations via `user_version`; newer saves are refused, older ones are
      snapshotted then upgraded in one transaction.
- [x] Schema: meta, regions, nations, organisations, players, true abilities (AI only), perceived
      abilities with scouting confidence, player and organisation reputation, traits, contracts
      (one active contract per player enforced), human profiles.
- [x] `CareerRepository`: typed records and queries (organisations, rosters, lineups, player
      search/filter/sort, stat layers, traits, contracts with history). No SQL elsewhere.
- [x] `WorldGenerator`: deterministic per seed; 40 organisations over 4 tiers and 8 regions, 296
      professionals with original nicknames and organisation names, role-shaped abilities,
      hidden potential, noisy perceived values, reputation, compatible traits, contracts.
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
ratings (M11), scouting that updates perceived values (M12), competitions (M13), calendar
advancement, transfers, ageing and rookies (M14), co-op sync of the database (M15), deleting
saves from the UI.

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
