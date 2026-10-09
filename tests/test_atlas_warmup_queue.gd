extends SceneTree
## Headless scheduling contract only; actual GPU pixels/timing need rendered CI.
const Queue = preload("res://scripts/cafe_atlas_warmup.gd")
class TestQueue extends Queue:
	var turns = 0
	func _wait_turn():
		await get_tree().process_frame
		turns += 1
class FakeAtlas extends RefCounted:
	var state = "warming"
	var calls = 0
	var name: String
	var events: Array
	var fails = false
	func _init(label: String, log: Array, fail = false):
		name = label;events = log;fails = fail
	func _build(tree: SceneTree):
		calls += 1;events.append(name + " start")
		await tree.process_frame
		await tree.process_frame
		state = "failed_fallback" if fails else "ready"
		events.append(name + " finish")
var checks = 0
var failures = []
func check(ok, label):
	checks += 1
	if not ok:failures.append(label);printerr("FAIL ", label)
func _initialize():run.call_deferred()
func run():
	var queue = TestQueue.new();root.add_child(queue)
	var events = []
	var first = FakeAtlas.new("first", events)
	var failed = FakeAtlas.new("failed", events, true)
	var last = FakeAtlas.new("last", events)
	queue.submit(first);queue.submit(first);queue.submit(failed);queue.submit(last)
	check(events.is_empty(), "no synchronous bake before first frame")
	for i in range(20):await process_frame
	check(events == ["first start", "first finish", "failed start", "failed finish", "last start", "last finish"], "strict FIFO without overlapping asynchronous bakes")
	check(first.calls == 1 and failed.calls == 1 and last.calls == 1, "duplicates ignored and failure does not block later work")
	check(queue.turns == 3, "one presentation wait per bake")
	check(not queue.running and queue.pending.is_empty(), "queue becomes idle")
	queue.submit(first)
	check(not queue.running, "ready atlas not rebaked")
	var later = FakeAtlas.new("later", events)
	queue.submit(later)
	for i in range(8):await process_frame
	check(later.calls == 1 and later.state == "ready", "idle queue restarts for new request")
	# Duplicate requests while a bake is suspended must still be ignored.
	var duplicate = FakeAtlas.new("duplicate", events)
	queue.submit(duplicate)
	while duplicate.calls == 0:await process_frame
	queue.submit(duplicate)
	for i in range(8):await process_frame
	check(duplicate.calls == 1 and queue.pending.is_empty(), "in-flight duplicate is ignored")
	queue.queue_free();await process_frame
	# Enqueue's shared owner is attached to the tree, not to an artist/game.
	var empty = FakeAtlas.new("empty", events);empty.state = "ready"
	Queue.enqueue(empty, self)
	check(is_instance_valid(Queue.shared) and Queue.shared.get_parent() == root, "shared scheduler belongs to SceneTree root")
	Queue.shared.free()
	Queue.enqueue(empty, self)
	check(is_instance_valid(Queue.shared) and Queue.shared.get_parent() == root, "freed shared scheduler is recreated")
	Queue.shared.free()
	var result = {"checks":checks,"failures":failures,"passed":failures.is_empty()}
	print("ATLAS_WARMUP_QUEUE_RESULT ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
