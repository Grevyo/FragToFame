class_name MapEditController
extends RefCounted
## All edits to a MapDocument go through here so they are undoable and observable.
##
## Every operation is expressed as "piece X goes from state A to state B", where a state is a
## piece Dictionary or {} (absent). Add, delete, move, rotate, resize and property edits are all
## the same primitive, which keeps undo/redo trivially correct. No Nodes: views subscribe to
## the signals and rebuild what changed.

signal piece_added(piece_id: String)
signal piece_removed(piece_id: String)
signal piece_changed(piece_id: String)
signal document_replaced
signal history_changed
signal selection_changed(piece_id: String)

var document: MapDocument
var selected_id: String = ""
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

	func apply(piece_id: String, state: Dictionary, index: int) -> void:
		var owner := _owner_ref.get_ref() as MapEditController
		if owner != null:
			owner._apply(piece_id, state, index)


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
	history_changed.emit()
	return ok


func redo() -> bool:
	var ok := _undo.redo()
	history_changed.emit()
	return ok


func undo_action_name() -> String:
	return _undo.get_current_action_name() if can_undo() else ""


func select(piece_id: String) -> void:
	if piece_id != "" and document.index_of(piece_id) < 0:
		piece_id = ""
	if piece_id == selected_id:
		return
	selected_id = piece_id
	selection_changed.emit(piece_id)


func selected_piece() -> Dictionary:
	return document.get_piece(selected_id) if not selected_id.is_empty() else {}


# --- operations ---------------------------------------------------------------------------------

## Adds a new piece. Returns its ID and selects it.
func add_piece(piece: Dictionary) -> String:
	var state := piece.duplicate(true)
	state["id"] = document.allocate_piece_id()
	_commit("Add %s" % PieceCatalog.label(str(state["type"])), str(state["id"]), {}, state, -1)
	select(str(state["id"]))
	return str(state["id"])


func delete_piece(piece_id: String) -> bool:
	var before := document.get_piece(piece_id)
	if before.is_empty():
		return false
	var index := document.index_of(piece_id)
	_commit("Delete %s" % PieceCatalog.label(str(before["type"])), piece_id, before, {}, index)
	if selected_id == piece_id:
		select("")
	return true


## Replaces a piece's state (move/rotate/resize/props). [param after] must keep the same id.
func update_piece(after: Dictionary, action_name: String = "Edit piece") -> bool:
	var piece_id := str(after.get("id", ""))
	var before := document.get_piece(piece_id)
	if before.is_empty() or before == after:
		return false
	_commit(action_name, piece_id, before, after.duplicate(true), document.index_of(piece_id))
	return true


func move_piece(piece_id: String, new_position: Vector3) -> bool:
	var piece := document.get_piece(piece_id)
	if piece.is_empty():
		return false
	piece["position"] = new_position
	return update_piece(piece, "Move")


func rotate_piece(piece_id: String, degrees: int = MapDocument.ROTATION_STEP) -> bool:
	var piece := document.get_piece(piece_id)
	if piece.is_empty():
		return false
	piece["rotation_y"] = posmod(int(piece["rotation_y"]) + degrees, 360)
	return update_piece(piece, "Rotate")


## Copies a piece, offset by [param offset], and selects the copy.
func duplicate_piece(piece_id: String, offset: Vector3) -> String:
	var source := document.get_piece(piece_id)
	if source.is_empty():
		return ""
	source["id"] = ""
	source["position"] = (source["position"] as Vector3) + offset
	return add_piece(source)


## Live preview during a drag: changes the document WITHOUT recording history.
## Finish with [method commit_preview] (one undo step) or [method cancel_preview].
func preview_piece(state: Dictionary) -> void:
	if document.replace_piece(state):
		piece_changed.emit(str(state["id"]))


func commit_preview(before: Dictionary, after: Dictionary, action_name: String) -> void:
	if before == after:
		return
	_undo.create_action(action_name)
	_undo.add_do_method(_applier.apply.bind(str(after["id"]), after.duplicate(true), -1))
	_undo.add_undo_method(_applier.apply.bind(str(before["id"]), before.duplicate(true), -1))
	_undo.commit_action(false)  # Document already shows "after".
	version += 1
	history_changed.emit()


func cancel_preview(before: Dictionary) -> void:
	preview_piece(before)


# --- internals ----------------------------------------------------------------------------------

func _commit(action_name: String, piece_id: String, before: Dictionary, after: Dictionary, index: int) -> void:
	_undo.create_action(action_name)
	_undo.add_do_method(_applier.apply.bind(piece_id, after, index))
	_undo.add_undo_method(_applier.apply.bind(piece_id, before, index))
	_undo.commit_action()
	history_changed.emit()


## Moves the document so that [param piece_id] has [param state] ({} = absent).
func _apply(piece_id: String, state: Dictionary, index: int) -> void:
	var exists := document.index_of(piece_id) >= 0
	if state.is_empty():
		if exists:
			document.remove_piece(piece_id)
			if selected_id == piece_id:
				select("")
			piece_removed.emit(piece_id)
	elif exists:
		document.replace_piece(state)
		piece_changed.emit(piece_id)
	else:
		document.add_piece(state, index)
		piece_added.emit(piece_id)
	version += 1
