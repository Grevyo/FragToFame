class_name MapValidator
extends RefCounted
## Structural checks of a MapDocument (pure data). Errors block playtesting; warnings are advice
## for competitive maps. Navigation checks (reachability, islands, route timings) need a baked
## navmesh and live in MapAnalysis (src/ai), which adds its findings to this report.

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
		var material := str(piece.get("material", ""))
		if not material.is_empty() and not MapMaterials.has_material(material):
			errors.append("%s uses unknown material '%s'." % [id, material])
		if doc.layer(str(piece.get("layer", MapDocument.DEFAULT_LAYER))).is_empty():
			errors.append("%s is on a layer that does not exist." % id)
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
	var area_names: Dictionary[String, bool] = {}
	for area: Dictionary in MapTactical.areas(doc):
		var area_name := str(area.get("props", {}).get("name", "")).strip_edges()
		if area_name.is_empty():
			warnings.append("Callout area %s has no name." % area["id"])
		elif area_names.has(area_name.to_lower()):
			warnings.append("Two callout areas are named \"%s\"." % area_name)
		area_names[area_name.to_lower()] = true
	return {"errors": errors, "warnings": warnings}
