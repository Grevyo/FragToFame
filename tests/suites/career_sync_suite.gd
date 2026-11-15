class_name CareerSyncSuite
extends TestSuite
## Career sync over real ENet loopback: one host, two clients, idempotent result submission,
## protocol-version rejection and resend-after-reconnect.

const PORT: int = 24661
const BIND: String = "127.0.0.1"

var _host: CareerSyncHost
var _a: CareerSyncClient
var _b: CareerSyncClient
var _acks_a: Array[Dictionary] = []
var _acks_b: Array[Dictionary] = []


func suite_name() -> String:
	return "Career sync (loopback)"


func run() -> void:
	_host = CareerSyncHost.new()
	tree.root.add_child(_host)
	_a = CareerSyncClient.new()
	_b = CareerSyncClient.new()
	tree.root.add_child(_a)
	tree.root.add_child(_b)
	_a.result_acknowledged.connect(func(ack: Dictionary) -> void: _acks_a.append(ack))
	_b.result_acknowledged.connect(func(ack: Dictionary) -> void: _acks_b.append(ack))

	await _test_connect()
	if _a.is_ready() and _b.is_ready():
		await _test_submissions()
		await _test_resend_after_reconnect()
	await _test_version_mismatch()

	_a.queue_free()
	_b.queue_free()
	_host.queue_free()
	await wait_frames(2)


func _test_connect() -> void:
	section("Handshake")
	check(_host.start(CareerWorld.create_dev_world(), PORT, BIND) == OK, "host listens on loopback")
	check(_a.connect_to_host("127.0.0.1", PORT, "Alice") == OK, "client A starts connecting")
	check(_b.connect_to_host("127.0.0.1", PORT, "Bob") == OK, "client B starts connecting")
	var both_ready := await wait_until(func() -> bool: return _a.is_ready() and _b.is_ready(), 5.0)
	check(both_ready, "both clients complete the handshake")
	check(_host.authenticated_peer_ids().size() == 2, "host sees two authenticated clients")
	check(_a.peer_id != _b.peer_id and _a.peer_id > 1, "clients get distinct peer ids")
	check(_a.fixtures.size() == 5 and _b.fixtures.size() == 5, "both clients receive the fixture list")
	check(_a.world_id == _host.world.world_id and _a.world_is_dev_sample, "client knows world id and dev-sample flag")
	check(_a.revision == _host.world.revision and _b.revision == _host.world.revision, "clients start at host revision")


func _test_submissions() -> void:
	section("Result submission")
	var fixture: Dictionary = _a.fixtures[0]
	var setup := MatchSetup.from_fixture(fixture)
	var result := StubMatchRunner.run(setup)
	var submission_id := _a.submit_result(result)
	check(_a.pending_submissions.has(submission_id), "submission is pending until acknowledged")
	var acked := await wait_until(func() -> bool: return _acks_a.size() >= 1, 3.0)
	check(acked and _acks_a[0]["status"] == "ACCEPTED", "host ACCEPTS the first result")
	check(not _a.pending_submissions.has(submission_id), "acknowledged submission is no longer pending")
	var b_updated := await wait_until(func() -> bool:
		return not (_b.find_fixture(setup.fixture_id).get("result", {}) as Dictionary).is_empty(), 3.0)
	check(b_updated, "other client receives the world update")
	check(_b.revision == _host.world.revision, "other client is at the new revision")
	var stored := _host.world.get_result(setup.fixture_id)
	check(stored != null and stored.submitted_by == "Alice", "host records who submitted it")

	_a.resend_submission(result.to_dict())
	acked = await wait_until(func() -> bool: return _acks_a.size() >= 2, 3.0)
	check(acked and _acks_a[1]["status"] == "DUPLICATE", "resending the same submission is DUPLICATE")

	var conflicting := MatchResult.create(setup.fixture_id, result.away_score, result.home_score, MatchResult.SOURCE_STUB)
	_b.submit_result(conflicting)
	acked = await wait_until(func() -> bool: return _acks_b.size() >= 1, 3.0)
	check(acked and _acks_b[0]["status"] == "CONFLICT", "a different result from another client is CONFLICT")
	check(_host.world.get_result(setup.fixture_id).submission_id == result.submission_id, "original result is kept")

	var bogus := MatchResult.create("fix_does_not_exist", 11, 0, MatchResult.SOURCE_STUB)
	_b.submit_result(bogus)
	acked = await wait_until(func() -> bool: return _acks_b.size() >= 2, 3.0)
	check(acked and _acks_b[1]["status"] == "UNKNOWN_FIXTURE", "unknown fixture is rejected over the network")

	var second: Dictionary = _b.fixtures[1]
	_b.submit_result(StubMatchRunner.run(MatchSetup.from_fixture(second)))
	acked = await wait_until(func() -> bool: return _acks_b.size() >= 3, 3.0)
	check(acked and _acks_b[2]["status"] == "ACCEPTED", "second client can resolve a different fixture")
	check(_host.world.unresolved_fixture_ids().size() == 3, "host world has exactly two resolved fixtures")


func _test_resend_after_reconnect() -> void:
	section("Recovery after reconnect")
	_a.disconnect_from_host("test")
	await wait_until(func() -> bool: return _host.authenticated_peer_ids().size() == 1, 3.0)
	check(not _a.is_ready(), "client A is offline")
	var fixture: Dictionary = _a.fixtures[2]
	var offline_result := StubMatchRunner.run(MatchSetup.from_fixture(fixture))
	_a.submit_result(offline_result)
	check(_a.pending_submissions.has(offline_result.submission_id), "result submitted while offline is kept pending")
	var acks_before := _acks_a.size()
	_a.connect_to_host("127.0.0.1", PORT, "Alice")
	var acked := await wait_until(func() -> bool: return _acks_a.size() > acks_before, 5.0)
	check(acked and _acks_a.back()["status"] == "ACCEPTED", "pending result is delivered after reconnect")
	check(_a.pending_submissions.is_empty(), "nothing left pending")
	check(_host.world.get_result(str(fixture["id"])) != null, "host applied the recovered result")


func _test_version_mismatch() -> void:
	section("Protocol version check")
	var old_client := CareerSyncClient.new()
	old_client.protocol_version = CareerProtocol.PROTOCOL_VERSION + 1
	tree.root.add_child(old_client)
	var rejected_reason: Array[String] = []
	old_client.rejected.connect(func(reason: String) -> void: rejected_reason.append(reason))
	if not _host.is_running():
		_host.start(CareerWorld.create_dev_world(), PORT, BIND)
	old_client.connect_to_host("127.0.0.1", PORT, "Old")
	var got := await wait_until(func() -> bool: return not rejected_reason.is_empty(), 5.0)
	check(got, "host rejects a client with a different protocol version")
	check(not old_client.is_ready(), "rejected client never becomes ready")
	old_client.queue_free()
	await wait_frames(1)
