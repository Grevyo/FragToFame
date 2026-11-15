class_name TacticCompatibility
extends RefCounted
## Reports where a saved tactic no longer fits its map. Read-only: it never changes a tactic or
## its file — the author decides what to do with each warning.
##
## An issue is {"tactic_id", "tactic_name", "slot" (1–5), "step" (0 = start, n = waypoint n),
## "code", "text"}. Codes:
##   "area_missing"    the callout area the step was authored in was removed
##   "area_left"       the step is no longer inside that area
##   "anchor_missing"  the tactical anchor the step was snapped to was removed
##   "anchor_moved"    that anchor now sits somewhere else
##   "unreachable"     bots can no longer stand there or walk there from the previous step
##                     (needs a MapAnalysis)

const ANCHOR_MOVE_TOLERANCE: float = 0.5


static func check(tactic: TacticDocument, map: MapDocument, analysis: MapAnalysis = null) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if tactic == null or map == null or tactic.map_id != map.map_id:
		return issues
	for i: int in tactic.slots.size():
		var slot := tactic.slots[i]
		if not slot.has_start:
			continue
		_check_step(issues, tactic, map, analysis, i, 0, slot.start, slot.start_area, slot.start_anchor, null)
		var previous := slot.start
		for j: int in slot.route.size():
			_check_step(issues, tactic, map, analysis, i, j + 1, slot.route[j], slot.area_of(j), slot.anchor_of(j), previous)
			previous = slot.route[j]
	return issues


## Checks every saved tactic of [param map] in [param storage]. Unreadable files are skipped.
static func scan(storage: TacticStorage, map: MapDocument, analysis: MapAnalysis = null) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	for entry: Dictionary in storage.list_for_map(map.map_id):
		issues.append_array(check(entry["tactic"] as TacticDocument, map, analysis))
	return issues


static func texts(issues: Array[Dictionary]) -> Array[String]:
	var lines: Array[String] = []
	for issue: Dictionary in issues:
		lines.append(str(issue["text"]))
	return lines


static func _check_step(issues: Array[Dictionary], tactic: TacticDocument, map: MapDocument, analysis: MapAnalysis,
		slot: int, step: int, point: Vector3, area_id: String, anchor_id: String, previous: Variant) -> void:
	if not area_id.is_empty():
		var area := map.get_piece(area_id)
		if area.get("type", "") != "callout":
			_add(issues, tactic, slot, step, "area_missing", "its callout area (%s) no longer exists" % area_id)
		elif not MapZones.contains(area, point):
			_add(issues, tactic, slot, step, "area_left", "it is no longer inside %s" % str(area.get("props", {}).get("name", area_id)))
	if not anchor_id.is_empty():
		var anchor := map.get_piece(anchor_id)
		if anchor.get("type", "") != "tactical_anchor":
			_add(issues, tactic, slot, step, "anchor_missing", "its tactical anchor (%s) no longer exists" % anchor_id)
		elif (anchor["position"] as Vector3).distance_to(point) > ANCHOR_MOVE_TOLERANCE:
			_add(issues, tactic, slot, step, "anchor_moved", "its anchor %s has moved" % MapTactical.anchor_label(anchor))
	if analysis == null:
		return
	if not analysis.is_reachable(point):
		_add(issues, tactic, slot, step, "unreachable", "bots can no longer reach it")
	elif previous != null and analysis.is_reachable(previous as Vector3) and analysis.path_length(previous as Vector3, point) < 0.0:
		_add(issues, tactic, slot, step, "unreachable", "there is no route to it from the previous step")


static func _add(issues: Array[Dictionary], tactic: TacticDocument, slot: int, step: int, code: String, reason: String) -> void:
	var step_text := "start" if step == 0 else "step %d" % step
	issues.append({
		"tactic_id": tactic.tactic_id, "tactic_name": tactic.display_name, "slot": slot + 1, "step": step, "code": code,
		"text": "Tactic \"%s\": player %d %s — %s." % [tactic.display_name, slot + 1, step_text, reason],
	})
