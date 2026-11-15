class_name MapValidator
extends RefCounted
## Checks a MapDocument. Errors block playtesting; warnings are advice for competitive maps.

const MAX_HALF_EXTENT: float = 256.0
const MIN_SIZE: float = 0.05
const COMPETITIVE_SPAWNS_PER_TEAM: int = 5


## Returns {"errors": Array[String], "warnings": Array[String]}.
static func validate(doc: MapDocument) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var ids: Dictionary[String, bool] = {}
	var attack_spawns := 0
	var defence_spawns := 0
	var sites: Dictionary[String, int] = {}
	var solid_count := 0

	if doc.name.strip_edges().is_empty():
		errors.append("The map needs a name.")

	for piece: Dictionary in doc.pieces:
		var id := str(piece["id"])
		var type := str(piece["type"])
		if ids.has(id):
			errors.append("Duplicate piece id %s." % id)
		ids[id] = true
		if not PieceCatalog.has_type(type):
			errors.append("%s has unknown type '%s'." % [id, type])
			continue
		var size: Vector3 = piece["size"]
		if size.x < MIN_SIZE or size.y < MIN_SIZE or size.z < MIN_SIZE:
			errors.append("%s (%s) is too small." % [id, PieceCatalog.label(type)])
		var position: Vector3 = piece["position"]
		if absf(position.x) > MAX_HALF_EXTENT or absf(position.z) > MAX_HALF_EXTENT or absf(position.y) > MAX_HALF_EXTENT:
			errors.append("%s is outside the %d m build area." % [id, int(MAX_HALF_EXTENT * 2)])
		if int(piece["rotation_y"]) % MapDocument.ROTATION_STEP != 0:
			errors.append("%s has a rotation that is not a multiple of 90°." % id)
		if PieceCatalog.is_solid(type):
			solid_count += 1
		match type:
			"spawn_attack":
				attack_spawns += 1
			"spawn_defence":
				defence_spawns += 1
			"bombsite":
				var site := str(piece.get("props", {}).get("site", ""))
				sites[site] = sites.get(site, 0) + 1

	if solid_count == 0:
		errors.append("The map has no solid geometry to stand on.")
	if attack_spawns + defence_spawns == 0:
		errors.append("Place at least one spawn point.")
	if attack_spawns < COMPETITIVE_SPAWNS_PER_TEAM:
		warnings.append("Competitive play needs %d attacker spawns (has %d)." % [COMPETITIVE_SPAWNS_PER_TEAM, attack_spawns])
	if defence_spawns < COMPETITIVE_SPAWNS_PER_TEAM:
		warnings.append("Competitive play needs %d defender spawns (has %d)." % [COMPETITIVE_SPAWNS_PER_TEAM, defence_spawns])
	if not sites.has("A") or not sites.has("B"):
		warnings.append("Competitive play needs bombsites A and B.")
	for site: String in sites:
		if sites[site] > 1:
			warnings.append("Bombsite %s is defined %d times." % [site, sites[site]])
	if doc.pieces_of_type("buy_zone").is_empty():
		warnings.append("No buy zones placed.")
	return {"errors": errors, "warnings": warnings}
