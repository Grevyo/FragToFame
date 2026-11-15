class_name MapClipboard
extends RefCounted
## App-wide piece clipboard. It outlives the open document, so pieces copied in one map can be
## pasted into another during the same session. Pieces are stored relative to their pivot.

static var _pieces: Array[Dictionary] = []


static func copy(pieces: Array[Dictionary]) -> int:
	if pieces.is_empty():
		return 0
	_pieces = MapSnapping.relative_to(pieces, MapSnapping.pivot(pieces))
	return _pieces.size()


static func has_content() -> bool:
	return not _pieces.is_empty()


static func size() -> int:
	return _pieces.size()


## A deep copy of the clipboard pieces (relative positions, no IDs).
static func contents() -> Array[Dictionary]:
	return _pieces.duplicate(true)


static func clear() -> void:
	_pieces = []
