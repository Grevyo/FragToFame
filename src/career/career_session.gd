class_name CareerSession
extends RefCounted
## One open career: the save it belongs to, its repository and the local human professional.

var save_id: String = ""
var repo: CareerRepository = null
var human_player_id: String = ""
## Non-empty when opening/creating failed.
var error: String = ""
## True when the save failed its integrity check (offer a backup restore).
var damaged: bool = false


func is_ok() -> bool:
	return error.is_empty() and repo != null and repo.is_open()


func human() -> CareerRecords.PlayerRecord:
	return repo.get_player(human_player_id) if repo != null and not human_player_id.is_empty() else null


func close() -> void:
	if repo != null:
		repo.close()
	repo = null
