class_name Ids
extends RefCounted
## Stable string ID generation: "<prefix>_<12 hex time><16 hex random>".
##
## Time-prefixed so IDs sort roughly by creation; random suffix makes collisions between
## machines practically impossible. Never use node paths or array indices as entity IDs.

static var _crypto: Crypto = Crypto.new()


static func generate(prefix: String) -> String:
	var time_hex := "%012x" % int(Time.get_unix_time_from_system() * 1000.0)
	return "%s_%s%s" % [prefix, time_hex, _crypto.generate_random_bytes(8).hex_encode()]


## Deterministic ID from a seeded generator (world generation: same seed → same world).
## Same shape as [method generate]; unique within one world, which is all saves require.
static func seeded(prefix: String, rng: RandomNumberGenerator) -> String:
	return "%s_%08x%08x%08x" % [prefix, rng.randi(), rng.randi(), rng.randi()]


static func has_prefix(id: String, prefix: String) -> bool:
	return id.begins_with(prefix + "_") and id.length() > prefix.length() + 1


## Stable content IDs can be used as a single file-name component on Windows and Linux.
static func is_file_id(id: String) -> bool:
	if id.is_empty() or id.length() > 96:
		return false
	for code: int in id.to_ascii_buffer():
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90)
				or (code >= 97 and code <= 122) or code == 45 or code == 95):
			return false
	# Device names are reserved even with an extension.
	var upper := id.to_upper()
	if upper in ["CON", "PRN", "AUX", "NUL"]:
		return false
	return not (upper.length() == 4 and upper.right(1).is_valid_int()
		and (upper.begins_with("COM") or upper.begins_with("LPT")))
