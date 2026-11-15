class_name CareerSyncClient
extends Node
## Career client: connects to a career host, mirrors its fixture list and submits results.
##
## Submissions stay in [member pending_submissions] until the host acknowledges them, and are
## resent automatically after a reconnect. Because the host deduplicates by submission_id,
## resending is always safe.

signal connected_to_host(peer_id: int)
signal rejected(reason: String)
signal disconnected(reason: String)
signal fixtures_changed(revision: int)
signal result_acknowledged(ack: Dictionary)

enum State { OFFLINE, CONNECTING, HANDSHAKING, READY }

var state: State = State.OFFLINE
var peer_id: int = 0
var player_name: String = "Player"
var host_address: String = ""
var host_port: int = 0
var world_id: String = ""
var world_is_dev_sample: bool = false
var revision: int = -1
var fixtures: Array[Dictionary] = []
## submission_id -> MatchResult dict, awaiting a RESULT_ACK.
var pending_submissions: Dictionary[String, Dictionary] = {}
var last_ack: Dictionary = {}
## Protocol version announced in HELLO. Only overridden by tests (version-mismatch check).
var protocol_version: int = CareerProtocol.PROTOCOL_VERSION

var _peer: ENetMultiplayerPeer


func is_ready() -> bool:
	return state == State.READY


func connect_to_host(address: String, port: int = CareerProtocol.DEFAULT_PORT,
		name_for_host: String = "Player") -> Error:
	disconnect_from_host("reconnecting")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_peer = peer
	host_address = address
	host_port = port
	player_name = name_for_host
	state = State.CONNECTING
	return OK


func disconnect_from_host(reason: String = "left") -> void:
	if _peer == null:
		return
	_peer.close()
	_peer = null
	var was_online := state != State.OFFLINE
	state = State.OFFLINE
	peer_id = 0
	if was_online:
		disconnected.emit(reason)


## Queues a result for the host. Returns its submission_id. Safe to call while offline:
## the submission is sent as soon as the connection is ready.
func submit_result(result: MatchResult) -> String:
	if result.submitted_by.is_empty():
		result.submitted_by = player_name
	var data := result.to_dict()
	pending_submissions[result.submission_id] = data
	if is_ready():
		_send(CareerProtocol.make(CareerProtocol.SUBMIT_RESULT, {"result": data}))
	return result.submission_id


## Re-sends an already submitted result unchanged (used to demonstrate idempotency).
func resend_submission(result_dict: Dictionary) -> void:
	if is_ready():
		_send(CareerProtocol.make(CareerProtocol.SUBMIT_RESULT, {"result": result_dict}))


func request_snapshot() -> void:
	if is_ready():
		_send(CareerProtocol.make(CareerProtocol.REQUEST_SNAPSHOT))


func find_fixture(fixture_id: String) -> Dictionary:
	for fixture: Dictionary in fixtures:
		if fixture.get("id", "") == fixture_id:
			return fixture
	return {}


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	if _peer == null:
		return
	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		var reason := "could not reach host" if state == State.CONNECTING else "connection to host lost"
		_peer = null
		state = State.OFFLINE
		peer_id = 0
		disconnected.emit(reason)
		return
	if status == MultiplayerPeer.CONNECTION_CONNECTED and state == State.CONNECTING:
		state = State.HANDSHAKING
		var hello := CareerProtocol.make(CareerProtocol.HELLO, {"player_name": player_name})
		hello["v"] = protocol_version
		_send(hello)
	while _peer != null and _peer.get_available_packet_count() > 0:
		var message := CareerProtocol.decode(_peer.get_packet())
		if not message.is_empty():
			_handle(message)


func _exit_tree() -> void:
	disconnect_from_host("shutting down")


func _handle(message: Dictionary) -> void:
	match str(message["type"]):
		CareerProtocol.WELCOME:
			peer_id = int(message["peer_id"])
			world_id = str(message["world_id"])
			world_is_dev_sample = bool(message.get("is_dev_sample", false))
			state = State.READY
			_apply_snapshot(message)
			connected_to_host.emit(peer_id)
			_resend_pending()
		CareerProtocol.REJECT:
			var reason := str(message.get("reason", "rejected"))
			rejected.emit(reason)
			disconnect_from_host("rejected: " + reason)
		CareerProtocol.SNAPSHOT, CareerProtocol.WORLD_UPDATED:
			_apply_snapshot(message)
		CareerProtocol.RESULT_ACK:
			last_ack = message.duplicate()
			pending_submissions.erase(str(message.get("submission_id", "")))
			result_acknowledged.emit(last_ack)
			if int(message.get("revision", -1)) > revision:
				request_snapshot()


func _apply_snapshot(message: Dictionary) -> void:
	var new_revision := int(message.get("revision", -1))
	if new_revision < revision:
		return  # Stale snapshot; never go backwards.
	revision = new_revision
	fixtures.clear()
	var incoming: Variant = message.get("fixtures", [])
	if incoming is Array:
		for item: Variant in incoming as Array:
			if item is Dictionary:
				fixtures.append(item as Dictionary)
	fixtures_changed.emit(revision)


func _resend_pending() -> void:
	for submission_id: String in pending_submissions:
		_send(CareerProtocol.make(CareerProtocol.SUBMIT_RESULT, {"result": pending_submissions[submission_id]}))


func _send(message: Dictionary) -> void:
	if _peer == null:
		return
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.put_packet(CareerProtocol.encode(message))
