class_name DevSampleData
extends RefCounted
## DEVELOPMENT SAMPLE DATA ONLY.
##
## Hard-coded, fictional placeholder values used to exercise the Career Hub layout during
## Milestone 1. This is NOT a career database, nothing here is persisted, and no simulation
## produced these numbers. It will be replaced by the career world repository (Milestone 9).
## All names are fictional and original.

const NOTICE: String = "Development sample data — no career database exists yet."
const IS_SAMPLE: bool = true


static func player_profile() -> Dictionary:
	return {
		"id": "ply_sample_0001",
		"display_name": "Rowan \"Sable\" Hartley",
		"nickname": "Sable",
		"age": 19,
		"nationality": "United Kingdom",
		"preferred_role": "Rifler",
		"assigned_role": "None (unsigned)",
		"team": "Free agent",
		"reputation": "Unknown amateur",
		"career_difficulty": "Standard",
		"matchmaking_elo": 1240,
		"matchmaking_tier": "Silver Circuit II",
	}


## Perceived ratings — what the esports world believes. They never affect human FPS mechanics.
static func perceived_attributes() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"name": "Aim (perceived)", "value": 58},
		{"name": "Game sense", "value": 52},
		{"name": "Utility usage", "value": 41},
		{"name": "Teamwork", "value": 63},
		{"name": "Composure", "value": 47},
		{"name": "Leadership", "value": 35},
	]
	return list


static func news() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"date": "02 Jan Y1", "headline": "F2F Universal Ladder Season 1 registration opens to all organisations."},
		{"date": "01 Jan Y1", "headline": "Northbridge Vortex confirm search for a fifth rifler."},
		{"date": "30 Dec Y0", "headline": "Ember Open Cup announces 128-team open qualifier."},
		{"date": "28 Dec Y0", "headline": "Amateur matchmaking season resets; placement matches available."},
	]
	return list


static func next_fixture() -> Dictionary:
	return {
		"date": "05 Jan Y1",
		"competition": "Amateur Matchmaking",
		"opponent": "Random lobby",
		"format": "BO1 · MR10",
	}


static func teams() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"id": "org_sample_01", "name": "Northbridge Vortex", "region": "Europe North", "tier": "Professional · Tier 2", "ladder": 1712},
		{"id": "org_sample_02", "name": "Crimson Lantern Esports", "region": "Europe West", "tier": "Professional · Tier 1", "ladder": 1954},
		{"id": "org_sample_03", "name": "Atlas Ronin", "region": "Asia Pacific", "tier": "Professional · Tier 1", "ladder": 1890},
		{"id": "org_sample_04", "name": "Kestrel Gaming", "region": "North America", "tier": "Semi-pro · Tier 3", "ladder": 1488},
		{"id": "org_sample_05", "name": "Saltmarsh Union", "region": "Europe North", "tier": "Amateur", "ladder": 1206},
		{"id": "org_sample_06", "name": "Halcyon Drift", "region": "South America", "tier": "Semi-pro · Tier 3", "ladder": 1531},
	]
	return list


static func calendar() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"date": "03 Jan Y1", "event": "Training day", "detail": "Aim routine & utility lineups"},
		{"date": "05 Jan Y1", "event": "Amateur Matchmaking", "detail": "Placement match 1 · BO1 MR10"},
		{"date": "07 Jan Y1", "event": "Amateur Matchmaking", "detail": "Placement match 2 · BO1 MR10"},
		{"date": "10 Jan Y1", "event": "Trial invitation (example)", "detail": "Saltmarsh Union scrim"},
		{"date": "12 Jan Y1", "event": "Northern Regional League D3", "detail": "Season opener (not participating)"},
		{"date": "20 Jan Y1", "event": "Ember Open Cup", "detail": "Open qualifier day 1"},
	]
	return list


static func statistics_summary() -> Dictionary:
	return {
		"matches": 14,
		"rounds": 236,
		"kd": 1.08,
		"adr": 76.4,
		"kast": 71.2,
		"hs_pct": 44.0,
		"rating": 1.03,
		"opening_win_pct": 52.0,
	}


static func recent_matches() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"date": "29 Dec Y0", "opponent": "Matchmaking lobby", "map": "Foundry", "score": "11–8", "kda": "18-13-4", "adr": 88.1, "rating": 1.21},
		{"date": "27 Dec Y0", "opponent": "Matchmaking lobby", "map": "Harbourline", "score": "6–11", "kda": "11-16-3", "adr": 61.7, "rating": 0.84},
		{"date": "26 Dec Y0", "opponent": "Matchmaking lobby", "map": "Cinderworks", "score": "11–9", "kda": "17-15-6", "adr": 79.0, "rating": 1.07},
		{"date": "22 Dec Y0", "opponent": "Matchmaking lobby", "map": "Foundry", "score": "11–4", "kda": "14-7-5", "adr": 82.6, "rating": 1.28},
		{"date": "20 Dec Y0", "opponent": "Matchmaking lobby", "map": "Harbourline", "score": "9–11", "kda": "15-15-2", "adr": 70.3, "rating": 0.97},
	]
	return list
