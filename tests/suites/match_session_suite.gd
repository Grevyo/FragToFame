class_name MatchSessionSuite
extends TestSuite
## In-match netcode over real ENet loopback, running at the same time as a career sync session
## to prove the two networks are independent.

const MATCH_PORT: int = 24671
const CAREER_PORT: int = 24662
const BIND: String = "127.0.0.1"


func suite_name() -> String:
	return "Match session (loopback) + independence from career sync"


func run() -> void:
	section("Match session")
	var host_root := Node3D.new()
	host_root.name = "TestMatchHostWorld"
	var client_root := Node3D.new()
	client_root.name = "TestMatchClientWorld"
	tree.root.add_child(host_root)
	tree.root.add_child(client_root)

	var host_session := MatchSession.new()
	host_session.name = "MatchSession"
	var client_session := MatchSession.new()
	client_session.name = "MatchSession"
	host_root.add_child(host_session)
	client_root.add_child(client_session)

	var host_body := Node3D.new()
	var client_body := Node3D.new()
	host_root.add_child(host_body)
	client_root.add_child(client_body)
	host_session.local_body = host_body
	client_session.local_body = client_body
	host_body.global_position = Vector3(1, 0, 2)
	client_body.global_position = Vector3(-3, 0, 5)

	check(host_session.multiplayer != client_session.multiplayer
		and host_session.multiplayer != tree.root.multiplayer, "each session has its own multiplayer branch")

	# A career session runs at the same time on its own port.
	var career_host := CareerSyncHost.new()
	var career_client := CareerSyncClient.new()
	tree.root.add_child(career_host)
	tree.root.add_child(career_client)
	career_host.start(CareerWorld.create_dev_world(), CAREER_PORT, BIND)
	career_client.connect_to_host("127.0.0.1", CAREER_PORT, "Parallel")

	check(host_session.host(MATCH_PORT, BIND) == OK, "match host listens")
	check(host_session.is_connected_to_match() and host_session.local_peer_id() == 1, "host is peer 1")
	check(client_session.join("127.0.0.1", MATCH_PORT) == OK, "client starts joining")
	var joined := await wait_until(func() -> bool:
		return client_session.is_connected_to_match() and host_session.remote_peer_ids().size() == 1, 5.0)
	check(joined, "client is welcomed and host registers it")
	check(client_session.match_id == host_session.match_id and not host_session.match_id.is_empty(),
		"client learns the host's match id")
	var client_id := client_session.local_peer_id()

	var synced := await wait_until(func() -> bool:
		var a := host_session.avatar_for(client_id)
		var b := client_session.avatar_for(1)
		return a != null and b != null and a.target_position.is_equal_approx(client_body.global_position) \
			and b.target_position.is_equal_approx(host_body.global_position), 3.0)
	check(synced, "both peers see each other's initial position")

	client_body.global_position = Vector3(7, 1, -4)
	client_body.rotation.y = 1.25
	host_body.global_position = Vector3(-2, 0, -9)
	var moved := await wait_until(func() -> bool:
		var a := host_session.avatar_for(client_id)
		var b := client_session.avatar_for(1)
		return a != null and b != null and a.target_position.is_equal_approx(Vector3(7, 1, -4)) and is_equal_approx(a.target_yaw, 1.25) \
			and b.target_position.is_equal_approx(Vector3(-2, 0, -9)), 3.0)
	check(moved, "movement and facing propagate in both directions")
	check(host_session.player_count() == 2 and client_session.player_count() == 2, "both report 2 players")

	var career_ready := await wait_until(func() -> bool: return career_client.is_ready(), 3.0)
	check(career_ready, "career sync session works while a match is running")
	if career_ready and not career_client.fixtures.is_empty():
		career_client.submit_result(StubMatchRunner.run(MatchSetup.from_fixture(career_client.fixtures[0])), career_client.world_id)
	var accepted := await wait_until(func() -> bool: return career_host.world.unresolved_fixture_ids().size() == 4, 3.0)
	check(accepted, "career result submission works while a match is running")

	host_session.leave("test over")
	var dropped := await wait_until(func() -> bool: return not client_session.is_active(), 5.0)
	check(dropped, "client notices when the match host leaves")
	check(career_client.is_ready(), "ending the match does not affect the career connection")

	career_client.queue_free()
	career_host.queue_free()
	host_root.queue_free()
	client_root.queue_free()
	await wait_frames(2)
