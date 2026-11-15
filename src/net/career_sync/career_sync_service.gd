extends Node
## Autoload "CareerSync": the game's single career-sync connection, alive across scene changes.
##
## Hosting runs a CareerSyncHost (owning the CareerWorld) AND a local CareerSyncClient that
## connects to it over loopback, so the host player uses exactly the same code path as remote
## players. The FPS runtime never touches this; results arrive as MatchResult objects.

enum Role { OFFLINE, HOST, CLIENT }

var role: Role = Role.OFFLINE
var host: CareerSyncHost
var client: CareerSyncClient


func _ready() -> void:
	host = CareerSyncHost.new()
	host.name = "Host"
	add_child(host)
	client = CareerSyncClient.new()
	client.name = "Client"
	add_child(client)
	client.disconnected.connect(_on_client_disconnected)


func default_player_name() -> String:
	return "Player %d" % OS.get_process_id()


## Hosts a new DEVELOPMENT SAMPLE career world and joins it locally.
func host_career(port: int = CareerProtocol.DEFAULT_PORT, bind_address: String = "*") -> Error:
	leave()
	var err := host.start(CareerWorld.create_dev_world(), port, bind_address)
	if err != OK:
		return err
	err = client.connect_to_host("127.0.0.1", port, default_player_name())
	if err != OK:
		host.stop()
		return err
	role = Role.HOST
	return OK


func join_career(address: String, port: int = CareerProtocol.DEFAULT_PORT) -> Error:
	leave()
	var err := client.connect_to_host(address, port, default_player_name())
	if err == OK:
		role = Role.CLIENT
	return err


func leave() -> void:
	client.disconnect_from_host("left")
	host.stop()
	role = Role.OFFLINE


func role_name() -> String:
	return Role.keys()[role]


func _on_client_disconnected(_reason: String) -> void:
	if role == Role.CLIENT:
		role = Role.OFFLINE
