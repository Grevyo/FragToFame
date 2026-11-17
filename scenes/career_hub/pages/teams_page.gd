class_name CareerTeamsPage
extends CareerPage
## Every organisation, grouped by tier and ranked by reputation. Each name opens that team's page
## (squad, matches, finances, history).

## One table per tier (tier heading, then the table).
var org_list: VBoxContainer
## How many organisations are listed.
var org_count: int = 0


func get_page_title() -> String:
	return "Teams"


func build_page() -> void:
	if add_no_career_notice():
		return
	var repo := career().repo
	org_list = UIFactory.vbox(18)
	org_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(org_list)
	var by_tier: Dictionary[int, Array] = {}
	var tiers: Array[int] = []
	for entry: Dictionary in repo.organisations():
		var org := entry["organisation"] as CareerRecords.OrganisationRecord
		if not by_tier.has(org.tier):
			by_tier[org.tier] = []
			tiers.append(org.tier)
		by_tier[org.tier].append([cell_team(org.id, org.name), CareerCatalog.region_name(org.region_id),
			str(int(entry["reputation"])), CareerNewsPage.form_label(repo.organisation_form(org.id))])
		org_count += 1
	tiers.sort()
	for tier: int in tiers:
		var card := UIFactory.card(org_list, CareerCatalog.tier_name(tier))
		var rows: Array[Array] = []
		rows.assign(by_tier[tier])
		link_table(card, PackedStringArray(["Organisation", "Region", "Reputation", "Form"]), rows)
