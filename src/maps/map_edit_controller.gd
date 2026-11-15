class_name MapEditController
extends RefCounted
## All edits to a MapDocument go through here so they are undoable and observable.
##
## Every operation is a list of "piece X goes from state A to state B" changes, where a state is
## a piece Dictionary or {} (absent). Add, delete, move, rotate, resize, property edits and every
## multi-piece edit (group move, paste, prefab placement) are the same primitive recorded as ONE
## undo step, which keeps undo/redo trivially correct. Document-level state (lighting, layers,
## prefabs) is recorded the same way as before/after values. No Nodes: views subscribe to the
## signals and rebuild what changed.

signal piece_added(piece_id: String)
signal piece_removed(piece_id: String)
signal piece_changed(piece_id: String)
signal document_replaced
signal history_changed
## Emitted on every selection change with the primary (last selected) piece ID or "".
signal selection_changed(piece_id: String)
## Emitted when lighting, layers or prefabs change ("lighting" / "layers" / "prefabs").
signal document_state_changed(key: String)

var document: MapDocument
## Primary selection (the last piece selected), "" when nothing is selected.
var selected_id: String = ""
## Every selected piece ID, in selection order.
var selection: Array[String] = []
## Bumped on every applied change; compared with [member saved_version] for the dirty flag.
var version: int = 0
var saved_version: int = 0

var _undo := UndoRedo.new()
## UndoRedo keeps strong references to RefCounted method targets. Recording our own methods
## would create a controller -> UndoRedo -> controller cycle and leak, so history operations
## target this helper, which only holds a weak reference back to the controller.
var _applier := _Applier.new(self)


class _Applier extends RefCounted:
	var _owner_ref: WeakRef

	func _init(owner: MapEditController) -> void:
		_owner_ref = weakref(owner)

	## [param steps] is [[piece_id, state, index], ...] applied in order.
	func apply(steps: Array) -> void:
		var owner := _owner_ref.get_ref() as MapEditController
		if owner != null:
			for step: Array in steps:
				owner._apply(str(step[0]), step[1] as Dictionary, int(step[2]))

	func apply_state(key: String, value: Variant) -> void:
		var owner := _owner_ref.get_ref() as MapEditController
		if owner != null:
			owner._apply_state(key, value)


func _init(doc: MapDocument = null) -> void:
	set_document(doc if doc != null else MapTemplates.blank())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_undo):
		_undo.free()  # UndoRedo is a plain Object, not reference counted.


## Map name/author/description edits are not undoable but do mark the map as changed.
func set_metadata(map_name: String, author: String, description: String) -> void:
	if document.name == map_name and document.author == author and document.description == description:
		return
	document.name = map_name
	document.author = author
	document.description = description
	version += 1
	history_changed.emit()


func set_document(doc: MapDocument) -> void:
	document = doc
	_undo.clear_history()
	selected_id = ""
	selection.clear()
	version = 0
	saved_version = 0
	document_replaced.emit()
	history_changed.emit()
	selection_changed.emit("")


func is_dirty() -> bool:
	return version != saved_version


func mark_saved() -> void:
	saved_version = version
	history_changed.emit()


func can_undo() -> bool:
	return _undo.has_undo()


func can_redo() -> bool:
	return _undo.has_redo()


func undo() -> bool:
	var ok := _undo.undo()
	_prune_selection()
	history_changed.emit()
	return ok


func redo() -> bool:
	var ok := _undo.redo()
	_prune_selection()
	history_changed.emit()
	return ok


func undo_action_name() -> String:
	return _undo.get_current_action_name() if can_undo() else ""


# --- selection ----------------------------------------------------------------------------------

## Selects exactly [param piece_id] ("" clears the selection).
func select(piece_id: String) -> void:
	var ids: Array[String] = []
	if not piece_id.is_empty():
		ids.append(piece_id)
	select_many(ids)


## Replaces the selection. Unknown IDs are dropped; the last ID becomes the primary selection.
func select_many(ids: Array[String]) -> void:
	var next: Array[String] = []
	for id: String in ids:
		if document.index_of(id) >= 0 and not next.has(id):
			next.append(id)
	if next == selection:
		return
	selection = next
	selected_id = next[next.size() - 1] if not next.is_empty() else ""
	selection_changed.emit(selected_id)


## Shift-click behaviour: adds the pieces if any is unselected, otherwise removes them.
func toggle_selection(ids: Array[String]) -> void:
	var next := selection.duplicate()
	var all_selected := ids.all(func(id: String) -> bool: return next.has(id))
	for id: String in ids:
		if all_selected:
			next.erase(id)
		elif not next.has(id):
			next.append(id)
	select_many(next)


func is_selected(piece_id: String) -> bool:
	return selection.has(piece_id)


func selected_piece() -> Dictionary:
	return document.get_piece(selected_id) if not selected_id.is_empty() else {}


func selected_pieces() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id: String in selection:
		var piece := document.get_piece(id)
		if not piece.is_empty():  # A piece removed mid-edit stays selected until the edit ends.
			list.append(piece)
	return list


## [param piece_id] plus every piece sharing its group (a placed prefab selects as one unit).
func group_members(piece_id: String) -> Array[String]:
	var list: Array[String] = []
	var group := str(document.get_piece(piece_id).get("group", ""))
	if group.is_empty():
		if document.index_of(piece_id) >= 0:
			list.append(piece_id)
		return list
	for piece: Dictionary in document.pieces:
		if piece.get("group", "") == group:
			list.append(str(piece["id"]))
	return list


## World-space box around the selection (empty AABB when nothing is selected).
func selection_bounds() -> AABB:
	return MapSnapping.bounds(selected_pieces())


## Bottom centre of the selection's bounds: the pivot for group rotation, copy and prefabs.
func selection_pivot() -> Vector3:
	return MapSnapping.pivot(selected_pieces())


# --- single-piece operations --------------------------------------------------------------------

## Adds a new piece. Returns its ID and selects it.
func add_piece(piece: Dictionary) -> String:
	var ids := add_pieces([piece], "Add %s" % PieceCatalog.label(str(piece["type"])))
	return ids[0] if not ids.is_empty() else ""


func delete_piece(piece_id: String) -> bool:
	if document.index_of(piece_id) < 0:
		return false
	return delete_pieces([piece_id])


## Replaces a piece's state (move/rotate/resize/props). [param after] must keep the same id.
func update_piece(after: Dictionary, action_name: String = "Edit piece") -> bool:
	return update_pieces([after], action_name)


func move_piece(piece_id: String, new_position: Vector3) -> bool:
	var piece := document.get_piece(piece_id)
	if piece.is_empty():
		return false
	piece["position"] = new_position
	return update_piece(piece, "Move")


func rotate_piece(piece_id: String, degrees: float = MapDocument.ROTATION_STEP) -> bool:
	var piece := document.get_piece(piece_id)
	if piece.is_empty():
		return false
	piece["rotation_y"] = MapDocument.normalise_rotation(float(piece["rotation_y"]) + degrees)
	return update_piece(piece, "Rotate")


## Copies a piece, offset by [param offset], and selects the copy.
func duplicate_piece(piece_id: String, offset: Vector3) -> String:
	var source := document.get_piece(piece_id)
	if source.is_empty():
		return ""
	source["id"] = ""
	source["group"] = ""
	source["position"] = (source["position"] as Vector3) + offset
	return add_piece(source)


# --- multi-piece operations (each is one undo step) ---------------------------------------------

## Adds [param new_pieces] as one step and selects them. Group IDs shared inside the batch are
## remapped to fresh group IDs so pasted groups never merge with existing ones.
func add_pieces(new_pieces: Array[Dictionary], action_name: String) -> Array[String]:
	var ids: Array[String] = []
	var do_steps: Array = []
	var undo_steps: Array = []
	var groups: Dictionary[String, String] = {}
	for piece: Dictionary in new_pieces:
		var state := piece.duplicate(true)
		state["id"] = document.allocate_piece_id()
		var group := str(state.get("group", ""))
		if not group.is_empty():
			if not groups.has(group):
				groups[group] = document.allocate_group_id()
			state["group"] = groups[group]
		if document.layer(str(state.get("layer", ""))).is_empty():
			state["layer"] = MapDocument.DEFAULT_LAYER
		ids.append(str(state["id"]))
		do_steps.append([state["id"], state, -1])
		undo_steps.push_front([state["id"], {}, -1])
	if ids.is_empty():
		return ids
	_commit(action_name, do_steps, undo_steps)
	select_many(ids)
	return ids


func delete_pieces(ids: Array[String]) -> bool:
	var entries: Array[Array] = []
	for id: String in ids:
		var index := document.index_of(id)
		if index >= 0:
			entries.append([index, document.get_piece(id)])
	if entries.is_empty():
		return false
	# Remove from the highest index down; undo re-inserts from the lowest index up.
	entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var do_steps: Array = []
	var undo_steps: Array = []
	for entry: Array in entries:
		var piece: Dictionary = entry[1]
		do_steps.append([piece["id"], {}, -1])
		undo_steps.push_front([piece["id"], piece, int(entry[0])])
	var name := "Delete %s" % PieceCatalog.label(str((entries[0][1] as Dictionary)["type"])) if entries.size() == 1 \
		else "Delete %d pieces" % entries.size()
	_commit(name, do_steps, undo_steps)
	return true


func delete_selection() -> bool:
	return delete_pieces(selection.duplicate())


## Replaces several pieces at once. Unchanged or unknown pieces are skipped.
func update_pieces(afters: Array[Dictionary], action_name: String) -> bool:
	var do_steps: Array = []
	var undo_steps: Array = []
	for after: Dictionary in afters:
		var piece_id := str(after.get("id", ""))
		var before := document.get_piece(piece_id)
		var state := MapDocument._complete(after.duplicate(true))
		if before.is_empty() or before == state:
			continue
		do_steps.append([piece_id, state, -1])
		undo_steps.push_front([piece_id, before, -1])
	if do_steps.is_empty():
		return false
	_commit(action_name, do_steps, undo_steps)
	return true


func move_selection(offset: Vector3) -> bool:
	return update_pieces(MapSnapping.moved(selected_pieces(), offset), "Move")


## Rotates the selection by [param degrees] around [param pivot] (default: the selection pivot).
func rotate_selection(degrees: float, pivot: Variant = null) -> bool:
	var centre: Vector3 = selection_pivot()
	if pivot is Vector3:
		centre = pivot
	elif selection.size() == 1:
		centre = selected_piece()["position"]  # A single piece turns in place.
	return update_pieces(MapSnapping.rotated(selected_pieces(), centre, degrees), "Rotate")


## Copies the selection, offset by [param offset], and selects the copies.
func duplicate_selection(offset: Vector3) -> Array[String]:
	var copies := MapSnapping.moved(selected_pieces(), offset)
	for piece: Dictionary in copies:
		piece["id"] = ""
	return add_pieces(copies, "Duplicate")


## Gives the selection one shared group so it selects and moves as a unit.
func group_selection() -> String:
	if selection.size() < 2:
		return ""
	var group := document.allocate_group_id()
	return group if _set_on_selection("group", group, "Group") else ""


func ungroup_selection() -> bool:
	return _set_on_selection("group", "", "Ungroup")


func set_selection_layer(layer_id: String) -> bool:
	if document.layer(layer_id).is_empty():
		return false
	return _set_on_selection("layer", layer_id, "Move to layer")


## Applies a palette material ("" = each type's default) to every solid piece selected.
func set_selection_material(material_id: String) -> bool:
	var afters: Array[Dictionary] = []
	for piece: Dictionary in selected_pieces():
		if PieceCatalog.is_solid(str(piece["type"])):
			piece["material"] = material_id
			afters.append(piece)
	return update_pieces(afters, "Set material")


## Places clipboard or prefab pieces (already relative to a pivot) at [param position].
func place_relative(relative: Array[Dictionary], position: Vector3, rotation_y: float, action_name: String,
		as_group: bool = false) -> Array[String]:
	var placed := MapSnapping.rotated(MapSnapping.moved(relative, position), position, rotation_y)
	for piece: Dictionary in placed:
		piece["id"] = ""
		if as_group:
			piece["group"] = "prefab"
	return add_pieces(placed, action_name)


# --- prefabs, layers, lighting (document state, undoable) ---------------------------------------

## Saves the selection as a prefab stored in this map. Returns the prefab ID ("" if nothing selected).
func save_prefab(prefab_name: String) -> String:
	if selection.is_empty():
		return ""
	var list := document.prefabs.duplicate(true)
	var id := document.allocate_prefab_id()
	list.append({"id": id, "name": prefab_name.strip_edges() if not prefab_name.strip_edges().is_empty() else "Prefab",
		"pieces": MapSnapping.relative_to(selected_pieces(), selection_pivot())})
	set_state("prefabs", list, "Save prefab")
	return id


func delete_prefab(prefab_id: String) -> bool:
	if document.prefab(prefab_id).is_empty():
		return false
	set_state("prefabs", document.prefabs.filter(func(entry: Dictionary) -> bool: return entry["id"] != prefab_id), "Delete prefab")
	return true


## Places a saved or stock prefab as one grouped unit. Returns the new piece IDs.
func place_prefab(prefab_id: String, position: Vector3, rotation_y: float = 0.0) -> Array[String]:
	var entry := MapPrefabs.find(document, prefab_id)
	if entry.is_empty():
		return []
	var relative: Array[Dictionary] = []
	relative.assign(entry["pieces"] as Array)
	return place_relative(relative, position, rotation_y, "Place %s" % entry["name"], true)


func add_layer(layer_name: String) -> String:
	var list := document.layers.duplicate(true)
	var id := document.allocate_layer_id()
	list.append({"id": id, "name": layer_name.strip_edges() if not layer_name.strip_edges().is_empty() else "Layer",
		"visible": true, "locked": false})
	set_state("layers", list, "Add layer")
	return id


## Changes one field ("name", "visible", "locked") of a layer.
func set_layer_field(layer_id: String, field: String, value: Variant) -> bool:
	var list := document.layers.duplicate(true)
	for entry: Dictionary in list:
		if entry["id"] == layer_id and entry.get(field) != value:
			entry[field] = value
			set_state("layers", list, "Edit layer")
			return true
	return false


## Removes a layer; its pieces move to the default layer in the same undo step.
func remove_layer(layer_id: String) -> bool:
	if layer_id == MapDocument.DEFAULT_LAYER or document.layer(layer_id).is_empty():
		return false
	var do_steps: Array = []
	var undo_steps: Array = []
	for piece: Dictionary in document.pieces:
		if piece.get("layer", "") == layer_id:
			var after := piece.duplicate(true)
			after["layer"] = MapDocument.DEFAULT_LAYER
			do_steps.append([piece["id"], after, -1])
			undo_steps.push_front([piece["id"], piece.duplicate(true), -1])
	var before_layers := document.layers.duplicate(true)
	var after_layers := document.layers.filter(func(entry: Dictionary) -> bool: return entry["id"] != layer_id)
	_undo.create_action("Remove layer")
	_undo.add_do_method(_applier.apply_state.bind("layers", after_layers))
	_undo.add_do_method(_applier.apply.bind(do_steps))
	_undo.add_undo_method(_applier.apply_state.bind("layers", before_layers))
	_undo.add_undo_method(_applier.apply.bind(undo_steps))
	_undo.commit_action()
	history_changed.emit()
	return true


func set_lighting(lighting: Dictionary) -> bool:
	if document.lighting == lighting:
		return false
	set_state("lighting", lighting.duplicate(true), "Edit lighting")
	return true


## Records a change of document-level state ("lighting", "layers", "prefabs") as one undo step.
func set_state(key: String, value: Variant, action_name: String) -> void:
	var before: Variant = (document.get(key) as Variant)
	if before is Array:
		before = (before as Array).duplicate(true)
	elif before is Dictionary:
		before = (before as Dictionary).duplicate(true)
	_undo.create_action(action_name)
	_undo.add_do_method(_applier.apply_state.bind(key, value))
	_undo.add_undo_method(_applier.apply_state.bind(key, before))
	_undo.commit_action()
	history_changed.emit()


# --- live previews (drags and gizmos) -----------------------------------------------------------

## Live preview during a drag: changes the document WITHOUT recording history.
## Finish with [method commit_preview] (one undo step) or [method cancel_preview].
func preview_piece(state: Dictionary) -> void:
	if document.replace_piece(state):
		piece_changed.emit(str(state["id"]))


func preview_pieces(states: Array[Dictionary]) -> void:
	for state: Dictionary in states:
		preview_piece(state)


func commit_preview(before: Dictionary, after: Dictionary, action_name: String) -> void:
	commit_previews([before], action_name)
	if after.is_empty():
		return


## Records the current document state of the previewed pieces against [param befores].
func commit_previews(befores: Array[Dictionary], action_name: String) -> void:
	var do_steps: Array = []
	var undo_steps: Array = []
	for before: Dictionary in befores:
		var after := document.get_piece(str(before["id"]))
		if after.is_empty() or after == before:
			continue
		do_steps.append([before["id"], after, -1])
		undo_steps.push_front([before["id"], before.duplicate(true), -1])
	if do_steps.is_empty():
		return
	_undo.create_action(action_name)
	_undo.add_do_method(_applier.apply.bind(do_steps))
	_undo.add_undo_method(_applier.apply.bind(undo_steps))
	_undo.commit_action(false)  # Document already shows "after".
	version += 1
	history_changed.emit()


func cancel_preview(before: Dictionary) -> void:
	preview_piece(before)


func cancel_previews(befores: Array[Dictionary]) -> void:
	preview_pieces(befores)


# --- internals ----------------------------------------------------------------------------------

func _set_on_selection(field: String, value: Variant, action_name: String) -> bool:
	var afters := selected_pieces()
	for piece: Dictionary in afters:
		piece[field] = value
	return update_pieces(afters, action_name)


func _commit(action_name: String, do_steps: Array, undo_steps: Array) -> void:
	_undo.create_action(action_name)
	_undo.add_do_method(_applier.apply.bind(do_steps))
	_undo.add_undo_method(_applier.apply.bind(undo_steps))
	_undo.commit_action()
	_prune_selection()
	history_changed.emit()


## Moves the document so that [param piece_id] has [param state] ({} = absent).
func _apply(piece_id: String, state: Dictionary, index: int) -> void:
	var exists := document.index_of(piece_id) >= 0
	if state.is_empty():
		if exists:
			document.remove_piece(piece_id)
			piece_removed.emit(piece_id)
	elif exists:
		document.replace_piece(state)
		piece_changed.emit(piece_id)
	else:
		document.add_piece(state, index)
		piece_added.emit(piece_id)
	version += 1


func _apply_state(key: String, value: Variant) -> void:
	match key:
		"lighting":
			document.lighting = (value as Dictionary).duplicate(true)
		"layers":
			document.layers.assign((value as Array).duplicate(true))
		"prefabs":
			document.prefabs.assign((value as Array).duplicate(true))
	version += 1
	document_state_changed.emit(key)


## Drops selected IDs whose pieces no longer exist (after a delete or an undo).
func _prune_selection() -> void:
	var kept: Array[String] = []
	for id: String in selection:
		if document.index_of(id) >= 0:
			kept.append(id)
	if kept != selection:
		select_many(kept)
