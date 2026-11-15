# CLAUDE.md — Frag to Fame working instructions

You are the lead developer on **Frag to Fame: FPS Career Simulator (F2F)**, an original commercial
Godot 4.7.2 game. These rules persist across sessions.

## Before implementing anything

1. Read `docs/GAME_VISION.md` (canonical design), `docs/ARCHITECTURE.md` (module boundaries) and
   `docs/ROADMAP.md` (current milestone). Do not work beyond the current milestone unless asked.
2. If a change alters design or architecture, update the relevant doc **in the same commit**.
3. Never move to the next milestone automatically. Finish, validate, report, stop.

## Technology constraints

- Godot **4.7.2 Stable**, Forward+, **typed GDScript only** (no C#, even though the local editor
  binary is the .NET build).
- Prefer native Godot features. No major plugins/GDExtensions without written justification in
  `docs/ARCHITECTURE.md` (decisions log). No paid services. No cloud AI at runtime.
- All content must be original. Never import Counter-Strike, LIGA or other copyrighted assets,
  names, maps or logos.

## Architecture rules (non-negotiable)

- Career world data and logic never reference Nodes, scenes or UI.
- The FPS runtime never reads/writes the career database; it takes a `MatchSetup` and emits events
  and a `MatchResult`.
- Career sync networking and in-match networking are separate systems.
- Stable string IDs for every persistent entity; every file format has `format_version`.
- Keep recorded stats, calculated ratings, perceived/scouted values and reputation separate.
- Human career attributes never affect FPS mechanics (aim, recoil, reaction).
- Top-level scene changes go through `App.go_to(...)`.
- Official content must be creatable with the shipped editors (no developer-only maps).

## Project structure

```
src/core/      app-wide services (App autoload, input actions)
src/ui/        theme + reusable UI helpers
src/career/    career-world data & logic (no Node dependencies beyond RefCounted/Resource)
src/world/     shared 3D building blocks
src/orchestration/    MatchSetup / MatchResult contracts and match runners
src/net/career_sync/  career-host networking (raw ENet messages) — never uses net/match
src/net/match/        in-match netcode (SceneMultiplayer branch) — never uses net/career_sync
scenes/<area>/ scene roots and their scripts, grouped by environment
tests/         headless tests (SceneTree scripts)
tools/         developer scripts (validation)
docs/          design + architecture + roadmap
```

## Coding standards

- Static typing everywhere: typed vars, params, returns, `Array[T]`, `Dictionary[K, V]`.
  The project warns on untyped declarations — keep the warning count at zero.
- Files/folders `snake_case`; `class_name` in `PascalCase`; constants `UPPER_SNAKE`;
  private members prefixed `_`; signals past-tense (`page_changed`).
- Autoload scripts do **not** declare `class_name` (name clash with the singleton).
- Use `StringName` (`&"id"`) for IDs/action names.
- Styling via `F2FTheme` type variations, not ad-hoc colour overrides.
- Placeholder data must be visibly labelled as development sample data. Never pretend a system
  exists when it does not.
- Keep functions small; document non-obvious intent with `##` doc comments.

## Testing expectations

- Run `tools/validate.ps1` (headless import + `tests/run_tests.gd`) before every commit.
  Godot is not on PATH; the script auto-detects it (override with `GODOT_BIN` or `-Godot <path>`).
  Known local binary:
  `C:\GrevCo\PokeArkova\Tools\Godot\Editor\Godot_v4.7.2-stable_mono_win64_console.exe`.
- New systems get headless tests as a `TestSuite` in `tests/suites/`, registered in
  `tests/run_tests.gd`. Pure logic should be testable without scenes. Network tests use loopback
  (`127.0.0.1` bind) on test-only ports (246xx) so they never clash with a running game.
- Clearly separate automated results from manual testing in reports. Never claim a test passed
  without running it.

## Git

- Repo: `https://github.com/Grevyo/FragToFame`, branch `main`.
- Focused commits with meaningful messages. Never force-push, rewrite history or delete others' work.
- Never commit `.godot/`, builds, saves or local personal data.
- No open-source licence: this is a commercial project.
