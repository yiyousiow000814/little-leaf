extends RefCounted
## Web-only cancellation precedes Godot's DOM touchcancel -> normal touchend.
## Keep DOM propagation intact; clear both engine input and GUI capture instead.
## No storage permissions are requested. Hide saves are best effort: the isolated
## vault commits asynchronously and cannot guarantee tab-close saves.
const TEMPORARY_PROGRESS = "Temporary progress · Browser storage is unavailable. Reloading or closing this page may lose your café."
const DOM_SOURCE = """
(function () {
    const key = '__littleLeafLifecycleV1';
    if (window[key]) return;
    const api = { current: null };
    api.install = function (callback) {
        if (api.current) api.current.dispose();
        const canvas = document.getElementById('canvas');
        if (!canvas || canvas.tagName !== 'CANVAS') return null;
        const listeners = [];
        const touches = new Set();
        let disposed = false;
        let savedForHide = false;
        let quarantined = false;
        function listen(target, type, handler) {
            target.addEventListener(type, handler, true);
            listeners.push([target, type, handler]);
        }
        function notify(reason, save, ids = Array.from(touches)) {
            if (!disposed) callback(reason, save, JSON.stringify(ids), quarantined);
        }
        function updateContacts(event, starting) {
            const changed = new Set(Array.from(event.changedTouches, touch => touch.identifier));
            const before = Array.from(new Set([...touches, ...changed]));
            const current = event.touches
                ? new Set(Array.from(event.touches).filter(touch => touch.target === canvas).map(touch => touch.identifier))
                : new Set(touches);
            if (!event.touches) for (const id of changed) {
                if (starting) current.add(id); else current.delete(id);
            }
            // A browser may drop endings while backgrounded. An authoritative
            // new start with no surviving old contact begins a fresh session.
            // Drain old queued engine events BEFORE the new DOM start reaches it.
            if (starting && quarantined && !Array.from(touches).some(id => current.has(id) && !changed.has(id))) {
                const old = Array.from(touches);
                quarantined = false;
                notify('touchdrained', false, old);
            }
            touches.clear();
            for (const id of current) touches.add(id);
            return Array.from(new Set([...before, ...current]));
        }
        // Capture at window, ahead of Godot's canvas listeners, including blur.
        // Never preventDefault/stopPropagation: the engine must see DOM endings.
        listen(window, 'touchstart', function (event) {
            if (event.target === canvas) updateContacts(event, true);
        });
        listen(window, 'touchend', function (event) {
            if (event.target !== canvas) return;
            const before = updateContacts(event, false);
            if (quarantined && touches.size === 0) {
                quarantined = false;
                // Engine-side callback drains buffered presses/releases while
                // input remains blocked, then releases canceled-session ownership.
                notify('touchdrained', false, before);
            }
        });
        listen(window, 'touchcancel', function (event) {
            if (event.target !== canvas) return;
            const before = updateContacts(event, false);
            quarantined = touches.size > 0;
            notify('touchcancel', false, before);
        });
        listen(window, 'blur', function (event) {
            if (event.target === window || event.target === canvas) {
                quarantined = touches.size > 0;
                notify('blur', false);
            }
        });
        function hide(reason) {
            const shouldSave = !savedForHide;
            savedForHide = true;
            quarantined = touches.size > 0;
            notify(reason, shouldSave);
        }
        listen(document, 'visibilitychange', function () {
            if (document.visibilityState === 'hidden') hide('hidden');
            else savedForHide = false;
        });
        listen(window, 'pagehide', function () { hide('pagehide'); });
        listen(window, 'pageshow', function () { savedForHide = false; });
        const registration = {
            dispose: function () {
                if (disposed) return;
                disposed = true;
                for (const [target, type, handler] of listeners) {
                    target.removeEventListener(type, handler, true);
                }
                listeners.length = 0;
                touches.clear();
                callback = null;
                if (api.current === registration) api.current = null;
            }
        };
        api.current = registration;
        return registration;
    };
    window[key] = api;
})();
"""
var game_ref:WeakRef
var game:
	get:return game_ref.get_ref()
var enabled=false
var canceling=false
var quarantined=false
var touches:Dictionary={}
var temporary_progress=false
var storage_note:Label
var _callback
var _registration

func _init(owner):game_ref=weakref(owner)

func start():
	if not OS.has_feature("web"):return
	enabled=true
	JavaScriptBridge.eval(DOM_SOURCE,true)
	var api=JavaScriptBridge.get_interface("__littleLeafLifecycleV1")
	_callback=JavaScriptBridge.create_callback(_on_browser_event)
	_registration=api.install(_callback) if api!=null else null
	if _registration==null:push_warning("Web lifecycle listener unavailable: expected the game canvas with id 'canvas'.")
	# userfs is intentionally unmounted; only the vault owns game persistence.
	if not game.save_recovery_blocked:
		show_storage_status(true,game.web_save!=null and game.web_save.ready)

func stop():
	# Main reload removes only this registration; an old owner's exit cannot
	# detach a newer Main's listeners. Keep the callback alive until removal.
	if _registration!=null:_registration.dispose()
	_registration=null;_callback=null;enabled=false;quarantined=false;touches.clear()

func handle_input(event:InputEvent)->bool:
	if canceling:return true
	if not enabled:return false
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:touches[event.index]=event.position
		elif not canceling:touches.erase(event.index)
	elif event is InputEventScreenDrag and touches.has(event.index):touches[event.index]=event.position
	if canceling:return true
	if quarantined and (event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag):return true
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.canceled:
		cancel_pending();return true
	return false

func _on_browser_event(arguments:Array):
	if not enabled or game==null or not game.is_inside_tree():return
	var ids=JSON.parse_string(str(arguments[2])) if arguments.size()>2 else []
	cancel_pending(ids if ids is Array else [])
	# Keep the previous quarantine through the buffer drain and input reset.
	# New touches stay inert until DOM confirms every physical contact ended.
	quarantined=bool(arguments[3]) if arguments.size()>3 else false
	if arguments.size()>1 and bool(arguments[1]):
		# Cancel previews before the validated runtime snapshot. This is not a
		# synchronous IndexedDB flush, and page termination may interrupt it.
		game._save()

func _gui_nodes(node:Node,result:Array):
	result.append(node)
	for child in node.get_children(true):_gui_nodes(child,result)

func cancel_pending(browser_touch_ids:Array=[]):
	# Resize also needs this engine/GUI cancellation on desktop and headless.
	# Browser listener installation remains Web-only.
	if canceling or game==null:return
	canceling=true
	var pending_touch_ids=browser_touch_ids.duplicate()
	if game.compact_ui!=null:
		if game.compact_ui.has_method("held_modal_touch_ids"):
			for index in game.compact_ui.held_modal_touch_ids():
				if not index in pending_touch_ids:pending_touch_ids.append(index)
		if game.compact_ui.has_method("cancel_modal_pointer"):game.compact_ui.cancel_modal_pointer()
	if game.camera_gestures!=null:
		for index in game.camera_gestures.touches:
			if not index in pending_touch_ids:pending_touch_ids.append(index)
		game.camera_gestures.on_focus_lost()
	if game.interaction!=null:game.interaction.on_focus_lost()
	if game.build_tools!=null:game.build_tools.on_focus_lost()
	var nodes:Array=[]
	_gui_nodes(game.ui,nodes)
	# BaseButton ignores InputEvent.canceled. SCROLL_BEGIN clears the press
	# attempt without changing toggle value, disabled state or keyboard focus.
	# The subsequent capture release still emits button_up for HUD animation.
	for node in nodes:
		if node is BaseButton:node.notification(Control.NOTIFICATION_SCROLL_BEGIN)
	var viewports:Array=[game.get_viewport()]
	for node in nodes:
		if node is Viewport and not node in viewports:viewports.append(node)
	var disabled_before:Array=[]
	for viewport in viewports:
		disabled_before.append(viewport.gui_disable_input)
		# Drops GUI mouse capture after button attempts have been canceled.
		viewport.gui_disable_input=true
	# Drain any accumulated DOM press while GUI/world dispatch is disabled.
	# DOM IDs include not-yet-dispatched presses (engine tracking cannot).
	Input.flush_buffered_events()
	var active=touches.duplicate()
	for index in pending_touch_ids:
		if not active.has(int(index)):active[int(index)]=game.get_viewport().get_mouse_position()
	for index in active:
		var release=InputEventScreenTouch.new()
		release.index=int(index);release.position=active[index];release.pressed=false;release.canceled=true
		Input.parse_input_event(release)
	Input.flush_buffered_events()
	# release_pressed_events does not clear the mouse mask or emulated touch
	# index. ScreenTouch endings above clear the index; these clear mouse bits.
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_XBUTTON1,MOUSE_BUTTON_XBUTTON2]:
		if not Input.is_mouse_button_pressed(button):continue
		var release=InputEventMouseButton.new()
		release.button_index=button;release.position=game.get_viewport().get_mouse_position();release.global_position=release.position;release.pressed=false;release.canceled=true
		Input.parse_input_event(release)
	Input.flush_buffered_events()
	touches.clear()
	for index in range(viewports.size()):viewports[index].gui_disable_input=disabled_before[index]
	canceling=false

func show_storage_status(web_runtime:bool,persistent:bool):
	temporary_progress=web_runtime and not persistent
	if not temporary_progress:return
	if not is_instance_valid(storage_note):
		storage_note=game.label(TEMPORARY_PROGRESS,12,Color("855536"))
		storage_note.name="TemporaryProgressNotice"
		storage_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		storage_note.custom_minimum_size.x=180
		storage_note.mouse_filter=Control.MOUSE_FILTER_IGNORE
		storage_note.accessibility_live=DisplayServer.LIVE_POLITE
		for record in game.compact_ui.themed_popups:
			if record.panel==game.settings:
				record.body.add_child(storage_note)
				record.body.move_child(storage_note,1)
				break
	# Use the existing width-bounded notice. Recovery notices keep priority.
	if not game.save_recovery_blocked:
		game._notify(TEMPORARY_PROGRESS);game.status_text.text=TEMPORARY_PROGRESS;game.toast_lifetime=9.0
