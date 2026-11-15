class_name FileReplacement
extends RefCounted
## Installs a closed, validated temporary file. Keep the previous version in a sibling backup.
## Rename only to vacant paths: Godot's Windows rename deletes an existing destination first.


static func install(staged: String, target: String, backup: String) -> Error:
	if not FileAccess.file_exists(staged) or DirAccess.dir_exists_absolute(target) 			or DirAccess.dir_exists_absolute(backup):
		return ERR_CANT_CREATE
	if not FileAccess.file_exists(target):
		return DirAccess.rename_absolute(staged, target)

	var previous_backup := backup + "." + Ids.generate("previous")
	var had_backup := FileAccess.file_exists(backup)
	if had_backup:
		var parked := DirAccess.rename_absolute(backup, previous_backup)
		if parked != OK:
			return parked
	var archived := DirAccess.rename_absolute(target, backup)
	if archived != OK:
		if had_backup:
			_move_back(previous_backup, backup)
		return archived
	var installed := DirAccess.rename_absolute(staged, target)
	if installed != OK:
		if _move_back(backup, target) and had_backup:
			_move_back(previous_backup, backup)
		return installed
	if had_backup and DirAccess.remove_absolute(previous_backup) != OK:
		push_warning("Earlier backup retained at %s" % previous_backup)
	return OK


static func _move_back(source: String, target: String) -> bool:
	if FileAccess.file_exists(target) or DirAccess.rename_absolute(source, target) != OK:
		push_warning("Could not restore %s. The previous file is at %s." % [target, source])
		return false
	return true
