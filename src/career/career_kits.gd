class_name CareerKits
extends RefCounted
## Team uniforms for career matches: each side plays in its organisation's colour (the
## `organisation.colour` the world generator gives every team). When the two colours are too
## alike to tell apart, the away side changes to a contrasting kit, as clubs do. Plain data: the
## colours travel in the [MatchSetup]; the FPS runtime paints players' team-colour channels.

## Below this distance (RGB, 0–1.73) two kits count as clashing.
const CLASH_DISTANCE: float = 0.3
## Neutral kit for a side without an organisation (amateur mixes, practice partners).
const NEUTRAL_KIT: String = "#6b7280"


## Fills [member MatchSetup.home_colour] and [member MatchSetup.away_colour].
static func apply(repo: CareerRepository, setup: MatchSetup) -> void:
	setup.home_colour = colour_of(repo, setup.home_team_id)
	setup.away_colour = away_kit(setup.home_colour, colour_of(repo, setup.away_team_id))


## An organisation's colour as "#rrggbb", or the neutral kit when it is not an organisation.
static func colour_of(repo: CareerRepository, organisation_id: String) -> String:
	var org := repo.get_organisation(organisation_id) if not organisation_id.is_empty() else null
	if org == null or not Color.html_is_valid(org.colour):
		return NEUTRAL_KIT
	return "#" + Color.html(org.colour).to_html(false)


## The away colour: its own, or a contrasting change kit when it clashes with the home colour.
static func away_kit(home: String, away: String) -> String:
	var home_colour := Color.from_string(home, Color.GRAY)
	var away_colour := Color.from_string(away, Color.GRAY)
	if not clashes(home_colour, away_colour):
		return away
	var change := Color.from_hsv(fposmod(home_colour.h + 0.5, 1.0), clampf(home_colour.s, 0.45, 0.85),
		0.85 if home_colour.v < 0.55 else 0.3)
	return "#" + change.to_html(false)


static func clashes(a: Color, b: Color) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < CLASH_DISTANCE
