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
| 4 | Basic FPS mechanics | 1 | ⬜ |
| 5 | Competitive match rules | 4 | ⬜ |
| 6 | Individual combat and navigation AI | 3, 4 | ⬜ |
| 7 | Tactical team AI and IGL | 5, 6 | ⬜ |
| 8 | Tactical Play Creator | 3, 7 | ⬜ |
| 9 | Persistent player/team database | 1 | ⬜ |
| 10 | Career fixtures and playable match integration | 5, 9 | ⬜ |
| 11 | Detailed statistics | 5, 10 | ⬜ |
| 12 | Career development and scouting | 9, 11 | ⬜ |
| 13 | Competition and tournament systems | 9, 10 | ⬜ |
| 14 | World progression, transfers, rookies, retirement | 12, 13 | ⬜ |
| 15 | Full cooperative career integration | 2, 10, 14 | ⬜ |
| 16 | Official content creation (5–7 maps) | 3, 6, 8 | ⬜ |
| 17 | Community content import/export | 3, 9, 16 | ⬜ |
| 18 | Steam integration, testing, release preparation | all | ⬜ |

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

## Milestone 4 — Basic FPS mechanics

Hitscan weapon with original stats, recoil pattern, spread, damage, health, death/respawn,
crouch, simple target dummies.

*(Later milestones are elaborated when they become next-up.)*

---

## Progress log

| Date | Entry |
|---|---|
| 2026-11-15 | Milestone 1 implemented; automated checks passing; awaiting manual acceptance. |
| 2026-11-15 | Milestone 1 accepted. Milestone 2 implemented; automated checks passing; awaiting manual two-instance test. |
| 2026-11-15 | Owner asked for continuous milestone work. Milestone 3 implemented; 234 automated checks passing; awaiting manual editor walkthrough. |
