class_name CareerSyncHost
extends Node
## Career host: owns the authoritative CareerWorld and serves career clients over ENet.
##
## Uses a raw ENetMultiplayerPeer (no SceneMultiplayer / RPC), so it is independent of the
## scene tree and of any in-match networking running in the same process.

signal client_joined(peer_id: int, player_name: String)
signal client_left(peer_id: int)
signal result_processed(peer_id: int, fixture_id: String, status: CareerWorld.SubmitStatus)

var world: CareerWorld
var port: int = 0

## peer_id -> {"player_name": String, "authenticated": bool}
var clients: Dictionary[int, Dictionary] = {}

var _peer: ENetMultiplayerPeer


func is_running() -> bool:
	return _peer != null


## Starts listening. [param bind_address] "*" for LAN/internet, "127.0.0.1" for local only.
func start(host_world: CareerWorld, listen_port: int = CareerProtocol.DEFAULT_PORT,
		bind_address: String = "*") -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	var err := peer.create_server(listen_port, CareerProtocol.MAX_CLIENTS)
	if err != OK:
		push_warning("CareerSyncHost: could not listen on port %d (error %d)" % [listen_port, err])
		return err
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	_peer = peer
	world = host_world
	port = listen_port
	return OK


func stop() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	clients.clear()


func authenticated_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for peer_id: int in clients:
		if clients[peer_id]["authenticated"]:
			ids.append(peer_id)
	return ids


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer != null and _peer.get_available_packet_count() > 0:
		var sender := _peer.get_packet_peer()
		var message := CareerProtocol.decode(_peer.get_packet())
		if not message.is_empty():
			_handle(sender, message)


func _exit_tree() -> void:
	stop()


func _on_peer_connected(peer_id: int) -> void:
	clients[peer_id] = {"player_name": "", "authenticated": false}


func _on_peer_disconnected(peer_id: int) -> void:
	var was_authenticated: bool = clients.has(peer_id) and clients[peer_id]["authenticated"]
	clients.erase(peer_id)
	if was_authenticated:
		client_left.emit(peer_id)


func _handle(sender: int, message: Dictionary) -> void:
	var type := str(message["type"])
	if type == CareerProtocol.HELLO:
		_handle_hello(sender, message)
		return
	if not clients.has(sender) or not clients[sender]["authenticated"]:
		return  # Ignore everything until the handshake succeeds.
	match type:
		CareerProtocol.REQUEST_SNAPSHOT:
			_send(sender, CareerProtocol.make(CareerProtocol.SNAPSHOT, _snapshot_payload()))
		CareerProtocol.SUBMIT_RESULT:
			_handle_submit(sender, message)
		_:
			push_warning("CareerSyncHost: unknown message type '%s' from %d" % [type, sender])


func _handle_hello(sender: int, message: Dictionary) -> void:
	if int(message["v"]) != CareerProtocol.PROTOCOL_VERSION:
		_send(sender, CareerProtocol.make(CareerProtocol.REJECT, {
			"reason": "protocol version mismatch (host %d, client %d)" % [CareerProtocol.PROTOCOL_VERSION, int(message["v"])],
		}))
		return
	var player_name := str(message.get("player_name", "Player %d" % sender))
	clients[sender] = {"player_name": player_name, "authenticated": true}
	var payload := _snapshot_payload()
	payload["peer_id"] = sender
	payload["world_id"] = world.world_id
	payload["is_dev_sample"] = world.is_dev_sample
	_send(sender, CareerProtocol.make(CareerProtocol.WELCOME, payload))
	client_joined.emit(sender, player_name)


func _handle_submit(sender: int, message: Dictionary) -> void:
	var raw: Variant = message.get("result", {})
	var result: MatchResult = MatchResult.from_dict(raw as Dictionary) if raw is Dictionary else null
	var outcome := world.submit_result(result)
	var status: CareerWorld.SubmitStatus = outcome["status"]
	var fixture_id := result.fixture_id if result != null else ""
	_send(sender, CareerProtocol.make(CareerProtocol.RESULT_ACK, {
		"submission_id": result.submission_id if result != null else "",
		"fixture_id": fixture_id,
		"status": CareerWorld.status_name(status),
		"message": outcome["message"],
		"revision": world.revision,
	}))
	result_processed.emit(sender, fixture_id, status)
	if status == CareerWorld.SubmitStatus.ACCEPTED:
		var update := CareerProtocol.make(CareerProtocol.WORLD_UPDATED, _snapshot_payload())
		for peer_id: int in authenticated_peer_ids():
			_send(peer_id, update)


func _snapshot_payload() -> Dictionary:
	return {"revision": world.revision, "fixtures": world.fixtures_snapshot()}


func _send(peer_id: int, message: Dictionary) -> void:
	if _peer == null:
		return
	_peer.set_target_peer(peer_id)
	_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_peer.put_packet(CareerProtocol.encode(message))
