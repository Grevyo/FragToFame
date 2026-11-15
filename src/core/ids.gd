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
