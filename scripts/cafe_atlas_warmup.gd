extends Node
## Serialize unchanged native atlas bakes. Let a frame be presented before the
## first bake and between bakes; original geometry remains the warming fallback.
## Owned by the SceneTree, not a game instance, so rebuilding a cafe cannot
## strand a shared atlas midway through its asynchronous bake.
static var shared
var pending: Array = []
var running = false

static func enqueue(atlas, tree: SceneTree):
	if not is_instance_valid(shared) or shared.get_tree() != tree:
		shared = load("res://scripts/cafe_atlas_warmup.gd").new()
		tree.root.add_child(shared)
	shared.submit(atlas)

func submit(atlas):
	# request() already changes cold to warming; also reject duplicate callers.
	if atlas in pending or atlas.state != "warming":return
	pending.append(atlas)
	if not running:
		running = true
		_drain.call_deferred()

func _wait_turn():
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

func _drain():
	while not pending.is_empty():
		await _wait_turn()
		var atlas = pending[0]
		if atlas.state == "warming":await atlas._build(get_tree())
		pending.pop_front()
	running = false
