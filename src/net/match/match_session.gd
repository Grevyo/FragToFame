class_name MatchSession
extends Node3D
## IN-MATCH netcode (Milestone 2 proof): a listen server hosted by one player's PC, with up to
## 10 players whose positions are synchronised.
##
## The session installs its own SceneMultiplayer on its own branch of the scene tree, so its
## RPCs never mix with career sync (which uses a raw ENet peer) or with any other session.
##
## Authority model for this proof: each client is authoritative for its own position and sends
## it to the host; the host rebroadcasts a snapshot of everyone. Server-authoritative movement,
## lag compensation and hit registration are later milestones.
##
## Each player's state is [position, yaw, crouch 0–1, aim pitch, held weapon model ID]. Each
## player's character look ([CharacterAppearance] dictionary, from their cosmetic profile) is sent
## once, reliably, to the host, which shares everyone's looks with everyone; others see the
## player as that character model (or as the plain capsule when they have none). Looks received
## are untrusted data: size-limited here and sanitised against the local catalog when shown.

signal session_started(role: Role)
signal session_ended(reason: String)
signal player_joined(peer_id: int)
signal player_left(peer_id: int)

enum Role { NONE, HOST, CLIENT }

## v2: states carry crouch, aim pitch and held weapon; character looks are exchanged.
const PROTOCOL_VERSION: int = 2
## Largest character look accepted, as JSON text (a full look is about 1 KB).
const MAX_APPEARANCE_BYTES: int = 8192
const DEFAULT_PORT: int = 24570
const MAX_PLAYERS: int = 10
const SEND_RATE_HZ: float = 30.0
const SNAPSHOT_RATE_HZ: float = 20.0

## The local player's body whose transform is broadcast. Set by the owning scene.
var local_body: Node3D
## The local player's character look ([method CharacterAppearance.to_dict]; empty = none).
var local_appearance: Dictionary = {}
var role: Role = Role.NONE
var match_id: String = ""

var _multiplayer: SceneMultiplayer
var _avatars: Dictionary[int, RemotePlayerAvatar] = {}
## Host only: latest state per peer, [position, yaw, crouch, pitch, weapon].
var _states: Dictionary[int, Array] = {}
## Character looks per peer (host: everyone's, including its own as peer 1).
var _appearances: Dictionary[int, Dictionary] = {}
var _welcomed: bool = false
var _send_timer: float = 0.0


func _enter_tree() -> void:
	_multiplayer = SceneMultiplayer.new()
	_multiplayer.server_relay = false
	get_tree().set_multiplayer(_multiplayer, get_path())
	_multiplayer.peer_connected.connect(_on_peer_connected)
	_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_multiplayer.connected_to_server.connect(_on_connected_to_server)
	_multiplayer.connection_failed.connect(_on_connection_failed)
	_multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	leave("session closed")
	get_tree().set_multiplayer(null, get_path())


func is_active() -> bool:
	return role != Role.NONE


func is_connected_to_match() -> bool:
	return role == Role.HOST or (role == Role.CLIENT and _welcomed)


func local_peer_id() -> int:
	return _multiplayer.get_unique_id() if is_active() else 0


func remote_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_avatars.keys())
	ids.sort()
	return ids


func avatar_for(peer_id: int) -> RemotePlayerAvatar:
	return _avatars.get(peer_id, null)


func player_count() -> int:
	return _avatars.size() + (1 if is_connected_to_match() else 0)


func host(port: int = DEFAULT_PORT, bind_address: String = "*") -> Error:
	leave("restarting")
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	_multiplayer.multiplayer_peer = peer
	role = Role.HOST
	match_id = Ids.generate("mch")
	_welcomed = true
	_store_appearance(1, local_appearance)
	session_started.emit(role)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave("restarting")
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_welcomed = false
	return OK


func leave(reason: String = "left") -> void:
	if role == Role.NONE:
		return
	if _multiplayer.multiplayer_peer != null:
		_multiplayer.multiplayer_peer.close()
	_multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for peer_id: int in _avatars.keys():
		_remove_avatar(peer_id)
	_states.clear()
	_appearances.clear()
	role = Role.NONE
	match_id = ""
	_welcomed = false
	session_ended.emit(reason)


func _process(delta: float) -> void:
	if not is_connected_to_match():
		return
	_send_timer += delta
	var interval := 1.0 / (SNAPSHOT_RATE_HZ if role == Role.HOST else SEND_RATE_HZ)
	if _send_timer < interval:
		return
	_send_timer = 0.0
	if role == Role.HOST:
		if local_body != null:
			_states[1] = local_state()
		_rpc_snapshot.rpc(_states)
	elif local_body != null:
		var state := local_state()
		_rpc_client_state.rpc_id(1, state[0] as Vector3, float(state[1]), float(state[2]), float(state[3]), str(state[4]))


## The local player's state as sent: [position, yaw, crouch, pitch, weapon model ID]. Crouch, aim
## and weapon are read when the body has them (a [CombatantMovementBody] with Head and Weapons).
func local_state() -> Array:
	var crouch := 0.0
	var pitch := 0.0
	var weapon := ""
	var mover := local_body as CombatantMovementBody
	if mover != null:
		crouch = mover.crouch_amount
	var head := local_body.get_node_or_null(^"Head") as Node3D
	if head != null:
		pitch = head.rotation.x
	var controller := local_body.get_node_or_null(^"Weapons") as WeaponController
	if controller != null and controller.current() != null:
		weapon = String(CosmeticProfile.current().model_for(controller.current().definition.id))
	return [local_body.global_position, local_body.global_rotation.y, crouch, pitch, weapon]


## The character look a peer sent (empty when none arrived).
func appearance_of(peer_id: int) -> Dictionary:
	return _appearances.get(peer_id, {})


## Changes the local look mid-session (e.g. after the Character Creator) and shares it.
func set_local_appearance(look: Dictionary) -> void:
	local_appearance = look.duplicate(true)
	if role == Role.HOST:
		_store_appearance(1, local_appearance)
		_rpc_appearances.rpc(_appearances)
	elif is_connected_to_match():
		_rpc_appearance.rpc_id(1, local_appearance)


# --- connection events ---------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	_rpc_welcome.rpc_id(peer_id, PROTOCOL_VERSION, match_id)
	_ensure_avatar(peer_id)
	_rpc_appearances.rpc_id(peer_id, _appearances)
	player_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	_states.erase(peer_id)
	_appearances.erase(peer_id)
	_remove_avatar(peer_id)
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	pass  # Wait for _rpc_welcome before considering the session started.


func _on_connection_failed() -> void:
	leave("could not reach match host")


func _on_server_disconnected() -> void:
	leave("match host disconnected")


# --- RPCs ----------------------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(host_protocol: int, host_match_id: String) -> void:
	if host_protocol != PROTOCOL_VERSION:
		leave("match protocol mismatch (host %d, client %d)" % [host_protocol, PROTOCOL_VERSION])
		return
	match_id = host_match_id
	_welcomed = true
	_rpc_appearance.rpc_id(1, local_appearance)
	session_started.emit(role)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_client_state(world_position: Vector3, yaw: float, crouch: float, pitch: float, weapon: String) -> void:
	if role != Role.HOST:
		return
	var sender := _multiplayer.get_remote_sender_id()
	var state: Array = [world_position, yaw, clampf(crouch, 0.0, 1.0), clampf(pitch, -PI / 2.0, PI / 2.0), weapon.left(64)]
	_states[sender] = state
	_apply_state(_ensure_avatar(sender), state)


## A client's look, sent once after joining (and again if it changes).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_appearance(look: Dictionary) -> void:
	if role != Role.HOST:
		return
	var sender := _multiplayer.get_remote_sender_id()
	if not _store_appearance(sender, look):
		return
	_ensure_avatar(sender).apply_appearance(_appearances.get(sender, {}))
	_rpc_appearances.rpc(_appearances)


## Everyone's looks, from the host.
@rpc("authority", "call_remote", "reliable")
func _rpc_appearances(looks: Dictionary) -> void:
	if role != Role.CLIENT:
		return
	var me := _multiplayer.get_unique_id()
	for key: Variant in looks:
		var peer_id := int(key)
		if peer_id == me or not looks[key] is Dictionary:
			continue
		if _store_appearance(peer_id, looks[key] as Dictionary):
			_ensure_avatar(peer_id).apply_appearance(_appearances.get(peer_id, {}))


## Keeps a received look when it is small enough to be one. Returns whether it was kept.
func _store_appearance(peer_id: int, look: Dictionary) -> bool:
	if JSON.stringify(look).length() > MAX_APPEARANCE_BYTES:
		return false
	if look.is_empty():
		_appearances.erase(peer_id)
	else:
		_appearances[peer_id] = look.duplicate(true)
	return true


static func _apply_state(avatar: RemotePlayerAvatar, state: Array) -> void:
	if state.size() < 2:
		return
	avatar.apply_state(state[0] as Vector3, float(state[1]),
		float(state[2]) if state.size() > 2 else 0.0,
		float(state[3]) if state.size() > 3 else 0.0,
		StringName(str(state[4])) if state.size() > 4 else &"")


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(states: Dictionary) -> void:
	if role != Role.CLIENT or not _welcomed:
		return
	var me := _multiplayer.get_unique_id()
	for key: Variant in states:
		var peer_id := int(key)
		if peer_id == me:
			continue
		var state: Array = states[key]
		if state.size() < 2:
			continue
		_apply_state(_ensure_avatar(peer_id), state)
	for peer_id: int in _avatars.keys():
		if not states.has(peer_id):
			_remove_avatar(peer_id)
			player_left.emit(peer_id)


# --- avatars -------------------------------------------------------------------------------------

func _ensure_avatar(peer_id: int) -> RemotePlayerAvatar:
	if _avatars.has(peer_id):
		return _avatars[peer_id]
	var avatar := RemotePlayerAvatar.new()
	avatar.setup(peer_id)
	add_child(avatar)
	_avatars[peer_id] = avatar
	if _appearances.has(peer_id):
		avatar.apply_appearance(_appearances[peer_id])
	if role == Role.CLIENT:
		player_joined.emit(peer_id)
	return avatar


func _remove_avatar(peer_id: int) -> void:
	var avatar: RemotePlayerAvatar = _avatars.get(peer_id, null)
	if avatar != null:
		avatar.queue_free()
	_avatars.erase(peer_id)
