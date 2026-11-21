class_name CareerUnlockProgress
extends RefCounted
## What a human player has done in a career, counted for character item unlocks
## (CharacterUnlocks): recorded career matches and kills, contracts signed with organisations,
## podium finishes and titles. Plain data from the career database; granting the items to the
## player's cosmetic profile is done by the screen that asks (the career hub).

const MATCHES: String = "matches"
const KILLS: String = "kills"
const CONTRACTS: String = "contracts"
const PODIUMS: String = "podiums"
const TITLES: String = "titles"


static func of(repo: CareerRepository, player_id: String) -> Dictionary:
	var totals := repo.performance_totals(player_id)
	var podiums := 0
	var titles := 0
	for honour: Dictionary in repo.honours(player_id):
		podiums += 1
		titles += 1 if int(honour.get("position", 0)) == 1 else 0
	return {
		MATCHES: int(totals.get("matches", 0)),
		KILLS: int(totals.get("kills", 0)),
		CONTRACTS: repo.contract_history(player_id).size(),
		PODIUMS: podiums,
		TITLES: titles,
	}
