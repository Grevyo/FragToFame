# Frag to Fame — Game Vision (Canonical)

> **Status:** Canonical long-term design. This document is the destination, not the current
> implementation target. Implementation proceeds milestone by milestone (see `ROADMAP.md`).
> When a design decision changes, update this file in the same commit as the code that changes it.

**Title:** Frag to Fame: FPS Career Simulator (abbreviated **F2F**)
**Type:** Original commercial PC game, distributed on Steam.

---

## Technology

- Engine: Godot 4.7.2 Stable.
- Language: Typed GDScript.
- Initial operating system: Windows.
- Target distribution: Steam.
- Initial 3D renderer: Forward+.
- Career persistence: SQLite, introduced when appropriate.
- Networking: Host-owned career database with independent client-hosted FPS sessions.
- Source control: Git and GitHub (`Grevyo/FragToFame`, branch `main`).

Prefer native Godot features and minimal dependencies. No beta engine versions. No major plugins
without a clear technical justification.

---

## 1. The fundamental concept

Frag to Fame is a first-person shooter esports **Player Career** simulator. It combines:

- **FIFA Player Career:** You are an individual professional athlete, developing your own career.
- **Football Manager:** A detailed, persistent sporting world with contracts, scouting,
  competitions, teams, statistics, personalities, transfers and evolving seasons.
- **Classic tactical FPS gameplay:** Fully playable competitive first-person matches with mechanics
  broadly reminiscent of tactical shooters.

The game is **not** a Counter-Strike modification. All game code, maps, weapons, organisations,
logos, graphics, names, sounds and other content must be original or properly licensed for
commercial use.

LIGA: Pro Journey is a major *experiential* design reference: the enjoyable progression from
amateur matchmaking to professional competition, expanded into a much deeper standalone game.
We do not copy LIGA's proprietary implementation or assets.

---

## 2. Three main game environments

### A. Career Hub — main 2D interface

The primary interface resembles a modern sports management simulator: menu-driven,
database-focused, with a persistent navigation sidebar. Planned sections:

- Home and news dashboard.
- Inbox and notifications.
- Personal player profile.
- Player attributes and match ratings.
- Team and teammates.
- Coaches and staff.
- Training.
- Contracts and transfers.
- Amateur matchmaking.
- Professional leagues.
- Cups and tournaments.
- F2F Universal Ladder.
- Calendar and fixtures.
- Individual and team statistics.
- Player and team database.
- Scouting.
- Rankings and leaderboards.
- Interviews and media.
- Rivalries and relationships.
- Awards and career history.
- Settings and save management.

There is no requirement to walk around a 3D headquarters. Almost all career activities happen
through the interface.

### B. FPS Runtime — 3D gameplay

Actual professional and amateur matches are playable from first person. Core features:

- 5v5 tactical gameplay.
- Bombsite objectives.
- Attacking and defending.
- Original weapons and equipment.
- Shooting, recoil and movement.
- Weapon buying and economy.
- Grenades and utility.
- Round timers and side switching.
- Death, spectating and match results.
- Human and AI teammates.
- Individual AI opponents.
- Human or AI in-game leaders.
- Detailed event tracking and match statistics.

Human players control their own characters, not their entire team. The rules may evolve beyond
traditional conventions — we are creating our own tactical FPS, not a strict reproduction.

### C. Creation Studio — runtime 3D editors

Much of the game's content is created using tools built into the actual game.

**3D Map Creator**

- Modular floors, walls, doors, stairs and props.
- Object selection, placement and transformation.
- Grid snapping.
- Bombsites, spawn locations and buy zones.
- Map callouts.
- Collision and bot navigation.
- Tactical map annotations.
- Save, load, undo, redo and validation.
- Instant in-game playtesting.

Initial goal: 5–7 official competitive maps built with this editor. Official maps must conform to
the same creation capabilities and restrictions available to the community. **No developer-only,
engine-authored maps that ordinary users cannot reproduce.**

**Tactical Play Creator**

- Load any compatible map.
- Switch between overhead and 3D views.
- Position five players.
- Draw individual routes and movement waypoints.
- Assign tactical roles.
- Specify utility throws.
- Define timing and triggers.
- Define conditional alternatives.
- Playtest tactics with AI.
- Save strategies into team playbooks.

The Creation Studio runs on the local player's computer, not on the career database host.

**Database and Competition Editors** — eventually support creating teams, players, organisations,
competitions and entire custom career worlds through the game's interface. Careers start from a
world database (the shipped default or an imported one) whose player values are ranges, rolled
for each new career. The shipped default database is curated in this editor (Milestone 19).

**Community Content** — official careers use official content. Custom single-player and custom
co-op careers may import compatible community maps, organisations, databases, leagues and other
creations. Content must have stable identifiers, versions and dependency validation. Steam
Workshop integration is a later milestone.

---

## 3. Individual player career

Every human creates one fictional esports professional. Preferred role can be:

- Rifler.
- AWPer.
- Entry fragger.
- Support.
- Lurker.
- IGL.

Preferred role does **not** guarantee deployment in that role. Organisations and coaches can sign
players for different positions, change assignments, bench players or alter team tactics.

Career progression includes:

- Starting reputation and difficulty selection.
- Amateur matchmaking and personal ELO.
- Player discovery and scouting.
- Contract offers and trials.
- Professional team recruitment.
- Salaries, contract negotiations and transfers.
- Squad selection and substitutions.
- Training and career development.
- Professional league participation.
- Cup and tournament appearances.
- International events and major finals.
- Personal and team achievements.
- Relationships, rivalries and reputation.
- Retirement and permanent career history.

Career difficulty can affect starting reputation, estimated player ability, initial matchmaking
rank and how quickly professional opportunities become available — enabling either a long amateur
grind or a start closer to professional consideration.

### Critical rule about human abilities

A human player's career attributes represent **what the esports world believes** about their
ability. They **do not** increase actual mouse accuracy, reduce weapon recoil, improve reaction
times or otherwise give artificial FPS advantages. Human shooting and movement remain skill-based.
Training and match results influence ratings, scouting opinions and reputation.

AI players, however, have underlying simulated mechanical and tactical abilities that genuinely
influence their gameplay.

---

## 4. Extensive player statistics and performance ratings

A deep esports analytics system for every human and AI professional. Record meaningful match
**events**, then calculate statistics from those events.

- **General:** Kills, deaths, assists, K/D, KAST, ADR, round impact, overall performance rating.
- **Aim:** Accuracy, headshot percentage, weapon-specific accuracy, first-shot accuracy, damage
  distribution.
- **Entries:** Opening kills, opening deaths, entry success, opening duel win percentage.
- **Teamwork:** Trades, traded deaths, utility assists, flash assists, support contributions.
- **Utility:** Grenade damage, flash effectiveness, useful smoke coverage, utility efficiency.
- **Clutches:** Clutch attempts, 1v1, 1v2 and larger clutch wins.
- **Situational:** Site attack, site defence, retakes, post-plants, eco rounds, pistol rounds.
- **Consistency:** Recent form, map-specific performance, seasonal averages, long-term trends.
- **Career:** Trophies, MVPs, rankings, peak rating, team history, achievements.

Different match lengths must be compared fairly using **round-normalised** statistics.

Keep these four layers separate:

1. Actual recorded statistics.
2. Calculated performance ratings.
3. Scouting opinions and perceived abilities.
4. Reputation and career standing.

Simulated AI-only matches and actual 3D matches must produce **compatible** statistics.

---

## 5. Persistent individual AI professionals

Every AI player is a persistent individual with a stable identity, unique player ID, career
history, personality, abilities, preferred roles and relationships. A professional who transfers
organisations must remain recognisably the same person. The world should contain substantial
player variety.

### Extensive trait system

A flexible, data-driven framework supporting a large library of traits across categories such as:

- Mechanical preferences.
- Aggression and risk-taking.
- Tactical intelligence.
- Team roles.
- IGL and leadership styles.
- Utility usage.
- Communication.
- Teamwork.
- Pressure and clutch mentality.
- Consistency.
- Temperament.
- Confidence.
- Social personality.
- Career ambition.
- Loyalty.
- Training discipline.
- Adaptability.
- Rivalries and relationships.
- Interview behaviour.

Traits can combine and develop over time. Some traits conflict, so combined effects must follow
sensible rules. **Traits must influence actual decisions**, not merely exist as decorative labels
(e.g. an ambitious but loyal professional may struggle deciding whether to leave a long-term team).

### Interviews and media

Contextual pre-match and post-match interviews. Players react according to personality, form,
relationships, match significance and previous events. Use structured dialogue generation and
content templates initially — **no paid cloud AI**. Long-running rivalries should naturally
influence interviews, transfers and match narratives.

---

## 6. Tactical AI and team intelligence

One of the game's most important features. AI players behave like actual tactical FPS teammates
and understand: site executes, defaults, fakes, rotations, lurking, trades, utility timing,
retakes, saves, economy, team positions, tactical communication and mid-round adaptations.

Every professional has individual strengths, weaknesses and habits.

### The IGL

An AI IGL selects plans according to map, opponent, economy, team abilities, match situation and
available information, and issues contextual calls. AI teammates must actually respond — e.g. when
the IGL calls an A-site execute, the support prepares the specified utility, the entry approaches
the correct location, and others fulfil their responsibilities. Plans adapt when information
changes.

### Human IGL

Humans can become IGLs, with practical commands for instructing AI teammates. **The same
underlying team-tactics system is used for both AI and human leaders.**

### Intelligence scaling

Higher-ranked teams and prestigious tournaments feature more sophisticated tactical AI. Amateur AI
makes mistakes and uses simpler strategies; elite teams communicate, coordinate and adapt more
effectively. **Avoid achieving difficulty through impossible accuracy, reaction times or hidden
information.** Individual talent and personality still matter at every tier.

---

## 7. The living esports universe

The world progresses over many in-game seasons. AI professionals train and improve, experience form
changes, develop and evolve, change teams, build relationships and rivalries, age and potentially
decline, occasionally experience injuries or career breaks (relatively rare), eventually retire and
sometimes enter coaching roles.

New generations of fictional rookies continually enter the ecosystem. Organisations recruit,
develop talent, change coaches, alter tactics, manage rosters and experience success or decline.

The world preserves historical records, champions, achievements and professional legacies. It uses
an **in-game calendar**, not real-world background progression.

---

## 8. Comprehensive competition ecosystem

Competition types:

- Amateur matchmaking ladders.
- Regional leagues.
- National leagues.
- Professional tiers.
- Promotion and relegation.
- Open cups.
- Invitation-only competitions.
- Regional qualifiers.
- International qualifiers.
- Swiss tournaments.
- Round-robin leagues.
- Group stages.
- Single-elimination brackets.
- Double-elimination brackets.
- Hybrid tournament structures.
- International championships.
- Major tournaments.
- Custom competitions.

Series: BO1, BO3, BO5 (especially major finals).

Round formats:

- Amateur/unsigned games: MR5 or MR10.
- Professional matches: MR10 or MR15.
- Custom competitions: configurable.

Overtime, qualification rules, map vetoes and tournament scheduling are **data-driven**.

### The F2F Universal Ladder

A flagship, massive season-long competition open to every registered organisation in the world.
Teams of all levels participate, gaining and losing ladder rating, developing positions and earning
historical achievements. It exists separately from individual matchmaking ratings and traditional
league standings. The host's lightweight career simulation resolves AI-only ladder fixtures without
launching 3D matches.

Teams may participate in several competitions in parallel. The calendar handles overlapping events,
registration, scheduling and qualification rules. All results and historical records persist.

---

## 9. Football Manager-style cooperative career

Multiple humans join one shared persistent career universe, each with an independent player
career. Friends may join different teams or the same team, receive their own contracts, transfer
independently, play together, face each other in official fixtures and meet in championship finals.

### Critical distinction: career host vs FPS match host

The **career host** owns the authoritative world database and coordinates persistent changes:
player and organisation records, contracts and transfers, fixtures and schedules, off-screen career
progression, database-backed results and statistics, standings and historical records, shared
calendar advancement, saving and restoring the world.

The career host does **not** run or render everyone's 3D matches. Each playable FPS match is hosted
by a participating player's PC. Different humans can have separate FPS matches running
simultaneously. When multiple humans share a fixture, one participating client is selected as match
host and the others connect to it. The 3D map editor and tactical editing sessions also run
locally. Players may spectate friends' matches when not playing their own fixture.

### Calendar synchronisation

Fixtures are coordinated without forcing every match to run sequentially. While one player finishes
a match, others can finish theirs and return to career menus. The world does not advance past
unresolved required fixtures until their results are received or recovered.

### Database safety

Unique fixture IDs and safe result submission. Prevent duplicate results, accidental conflicting
updates and save corruption. Provide backups, migrations and recovery mechanisms.

No competitive anti-cheat is needed — this is a fun-focused private co-op and single-player game.
Focus on reliable saves, networking and preventing accidental inconsistencies.

---

## 10. Customisation and official content

- 5–7 original official competitive maps, all created using the shipped in-game map editor.
- Official career saves use the default official universe.
- Custom single-player or co-op saves may import user-made maps, teams, competitions and database
  packs.
- User-created content must not unexpectedly alter an existing official career.
- Content versions and dependencies are recorded in each save.
- Custom tournaments can exist outside the main career mode and within compatible custom worlds.
- Community publishing and Steam Workshop support are later goals.

---

## Engineering principles (from the brief)

- Use stable entity IDs.
- Keep the database independent from Godot UI scenes.
- Avoid coupling the career world to the 3D FPS scene.
- Keep local-match networking separate from persistent career synchronisation.
- Use versioned data formats; preserve backward compatibility where practical.
- Separate simulated abilities from perceived ratings and actual recorded statistics.
- No premature complexity, but avoid decisions that prevent future co-op or runtime editing.
- Optimise for maintainability and incremental development.
