# Frag to Fame — Roadmap

Each milestone is a small, independently testable vertical slice. The order may change where
dependencies demand it. **Do not start the next milestone until the current one is accepted.**

Legend: ✅ done · 🔶 in progress / awaiting acceptance · ⬜ not started

| # | Milestone | Depends on | Status |
|---|---|---|---|
| 1 | Runnable application foundation | — | 🔶 awaiting manual test |
| 2 | Early networking architecture proof | 1 | ⬜ |
| 3 | Basic runtime map editing | 1 | ⬜ |
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

## Milestone 1 — Runnable application foundation 🔶

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
- [ ] Manual test checklist (README) completed by the project owner.

## Milestone 2 — Early networking architecture proof (proposed next)

Prove the two-network split before gameplay hardens around single-player assumptions:

- Minimal **career host** process/mode exposing a tiny authoritative world (e.g. a fixture list)
  and accepting idempotent result submissions keyed by fixture ID.
- Two clients connect, see the same fixture list, each "plays" a stub match locally, submits a
  result; duplicates are rejected.
- Separately, a **match host** listen-server in the FPS Sandbox with 2 players moving
  (position sync only), independent of the career connection.
- Automated test: in-process host + client over loopback.

## Milestone 3 — Basic runtime map editing

Place/select/move/rotate/delete modular blocks with snapping, undo/redo, save/load a versioned map
document, and "Playtest" that loads the map into the FPS runtime.

## Milestone 4 — Basic FPS mechanics

Hitscan weapon with original stats, recoil pattern, spread, damage, health, death/respawn,
crouch, simple target dummies.

*(Later milestones are elaborated when they become next-up.)*

---

## Progress log

| Date | Entry |
|---|---|
| 2026-11-15 | Milestone 1 implemented; automated checks passing; awaiting manual acceptance. |
