class_name CareerProtocol
extends RefCounted
## Wire protocol for CAREER SYNC (career host <-> career clients).
##
## Low-frequency, reliable, message-based. Every message is a Dictionary with a protocol
## version "v" and a "type", serialised with var_to_bytes (objects are never allowed).
## This protocol is completely separate from in-match netcode (see MatchSession).

const PROTOCOL_VERSION: int = 2
const DEFAULT_PORT: int = 24560
const MAX_CLIENTS: int = 16

# client -> host
const HELLO: String = "hello"                    # {player_name}
const REQUEST_SNAPSHOT: String = "request_snapshot"
const SUBMIT_RESULT: String = "submit_result"    # {world_id, result: MatchResult dict}
# host -> client
const WELCOME: String = "welcome"                # {peer_id, world_id, is_dev_sample, revision, fixtures}
const REJECT: String = "reject"                  # {reason}
const SNAPSHOT: String = "snapshot"              # {revision, fixtures}
const RESULT_ACK: String = "result_ack"          # {submission_id, fixture_id, status, message, revision}
const WORLD_UPDATED: String = "world_updated"    # {revision, fixtures}


static func make(type: String, payload: Dictionary = {}) -> Dictionary:
	var message := payload.duplicate(true)
	message["v"] = PROTOCOL_VERSION
	message["type"] = type
	return message


static func encode(message: Dictionary) -> PackedByteArray:
	return var_to_bytes(message)


## Returns the decoded message, or an empty Dictionary if the bytes are not a valid message.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {}
	var value: Variant = bytes_to_var(bytes)
	if not value is Dictionary:
		return {}
	var message := value as Dictionary
	if not message.has("type") or not message.has("v"):
		return {}
	return message
