class_name CareerRecords
extends RefCounted
## Typed records returned by [CareerRepository]. Plain data, no storage knowledge.


class PlayerRecord extends RefCounted:
	var id: String = ""
	var first_name: String = ""
	var last_name: String = ""
	var nickname: String = ""
	var nation_id: String = ""
	var birth_day: int = 0
	var preferred_role: StringName = &"rifler"
	var is_human: bool = false
	var status: String = "active"
	var created_day: int = 0

	## "Rowan "Sable" Hartley"
	func display_name() -> String:
		return "%s \"%s\" %s" % [first_name, nickname, last_name]

	func age(today: int) -> int:
		return GameDate.age(birth_day, today)

	static func from_row(row: Dictionary) -> PlayerRecord:
		var p := PlayerRecord.new()
		p.id = str(row["id"])
		p.first_name = str(row["first_name"])
		p.last_name = str(row["last_name"])
		p.nickname = str(row["nickname"])
		p.nation_id = str(row["nation_id"])
		p.birth_day = int(row["birth_day"])
		p.preferred_role = StringName(str(row["preferred_role"]))
		p.is_human = int(row["is_human"]) == 1
		p.status = str(row["status"])
		p.created_day = int(row["created_day"])
		return p


class OrganisationRecord extends RefCounted:
	var id: String = ""
	var name: String = ""
	var short_name: String = ""
	var region_id: String = ""
	var tier: int = 4
	var founded_day: int = 0
	var colour: String = "888888"
	var active: bool = true

	static func from_row(row: Dictionary) -> OrganisationRecord:
		var o := OrganisationRecord.new()
		o.id = str(row["id"])
		o.name = str(row["name"])
		o.short_name = str(row["short_name"])
		o.region_id = str(row["region_id"])
		o.tier = int(row["tier"])
		o.founded_day = int(row["founded_day"])
		o.colour = str(row["colour"])
		o.active = int(row["active"]) == 1
		return o


class ContractRecord extends RefCounted:
	var id: String = ""
	var player_id: String = ""
	var organisation_id: String = ""
	var role: StringName = &"rifler"
	var is_substitute: bool = false
	var monthly_salary: int = 0
	var start_day: int = 0
	var end_day: int = 0
	var status: String = "active"

	static func from_row(row: Dictionary) -> ContractRecord:
		var c := ContractRecord.new()
		c.id = str(row["id"])
		c.player_id = str(row["player_id"])
		c.organisation_id = str(row["organisation_id"])
		c.role = StringName(str(row["role"]))
		c.is_substitute = int(row["is_substitute"]) == 1
		c.monthly_salary = int(row["monthly_salary"])
		c.start_day = int(row["start_day"])
		c.end_day = int(row["end_day"])
		c.status = str(row["status"])
		return c
