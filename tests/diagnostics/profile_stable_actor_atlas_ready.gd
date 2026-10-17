extends SceneTree
## Diagnostic-only successor of retained control.gd (148b27295aa99e5c...).
## Native READY atlas CPU/resource controls, not GPU, browser or FPS evidence.
const Probe = preload("res://tests/diagnostics/stable_actor_cpu_probe.gd")
const Native = preload("res://scripts/rendering/cafe_native_draw_node.gd")
const Shape = preload("res://scripts/rendering/cafe_shape_2d.gd")
const Prebaked = preload("res://scripts/rendering/cafe_prebaked_atlas.gd")
const PROFILE_KEYS = ["HOME","APPDATA","LOCALAPPDATA","XDG_DATA_HOME","XDG_CONFIG_HOME","XDG_CACHE_HOME"]
const REQUESTED = {"seats":30,"guests":30,"staff":22,"litter":12,"cars":64,"open":false}
const RETAINED_CONTROL_SHA256 = "148b27295aa99e5cde8577d1db43c7730bda8305e18a015437fb41111a39d8a5"
const RETAINED_PROBE_SHA256 = "9392cc468a03838cd8b4b0584633969471223567018102466c01c0707ef3be45"
const WARMUP = 60
const FRAMES = 600
const SEED = 13017
const ATLAS_NAMES = ["furniture","heads","moving"]
const SOURCE_PATHS = ["scripts/main.gd","scripts/rendering/illustrated_cafe.gd","scripts/rendering/cafe_native_draw_node.gd","scripts/rendering/cafe_character_pick_geometry.gd","scripts/rendering/illustrated_furniture.gd","scripts/rendering/character_head_atlas.gd","scripts/rendering/moving_art_atlas.gd","scripts/rendering/furniture_static_atlas.gd","scripts/rendering/cafe_prebaked_atlas.gd"]
class SyntheticMain extends "res://scripts/main.gd":
 var save_calls = 0
 func _load_startup():
  save_writes_suppressed = true
  fresh_start = true
  music_enabled = false
  MinimalStart.apply(model)
  paused = true
 func _setup_music(): pass
 func _save():
  save_calls += 1
  get_tree().forbidden_save()
  return false

var game
var report = {}
var errors = []
var output = OS.get_environment("OUTPUT")
var completed_save_calls = 0
var observations = []
var population_frames = []
var frame_metrics = []
var traffic_moved = 0
var ready_owners = []
var ready_textures = []

func _initialize():
 if "--probe-self-test" in OS.get_cmdline_user_args(): pure_checks.call_deferred()
 else: run.call_deferred()

func plain(value):
 match typeof(value):
  TYPE_VECTOR2,TYPE_VECTOR2I: return [value.x,value.y]
  TYPE_VECTOR3,TYPE_VECTOR3I: return [value.x,value.y,value.z]
  TYPE_COLOR: return [value.r,value.g,value.b,value.a]
  TYPE_RECT2,TYPE_RECT2I: return [plain(value.position),plain(value.size)]
  TYPE_TRANSFORM2D: return [plain(value.x),plain(value.y),plain(value.origin)]
  TYPE_FLOAT: return value if is_finite(value) else ("nan" if is_nan(value) else ("+inf" if value>0 else "-inf"))
  TYPE_DICTIONARY:
   var result = {}
   for key in value:
    if str(key) == "node": continue
    result[str(key)] = plain(value[key])
   return result
  TYPE_ARRAY,TYPE_PACKED_VECTOR2_ARRAY,TYPE_PACKED_VECTOR3_ARRAY,TYPE_PACKED_COLOR_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_STRING_ARRAY:
   var result = []
   for entry in value: result.append(plain(entry))
   return result
  TYPE_OBJECT:
   errors.append("Unnormalized object in semantic state")
   return {"unsupported_object":true}
  _: return value

static func atomic_json(path:String, value:Dictionary)->Error:
 var encoded = JSON.stringify(value,"  ",true,true)
 var temporary = path + ".pending"
 var file = FileAccess.open(temporary,FileAccess.WRITE)
 if file == null: return FileAccess.get_open_error()
 file.store_string(encoded)
 file.flush()
 var error = file.get_error()
 file.close()
 if error != OK: return error
 return DirAccess.rename_absolute(temporary,path)

func write_report():
 if output == "": return
 report["errors"] = errors.duplicate()
 report["save_calls"] = completed_save_calls + (game.save_calls if is_instance_valid(game) else 0)
 report["observations"] = observations
 report["population_frames"] = population_frames
 report["sampled_frames"] = population_frames.size()
 var result = atomic_json(output,report)
 if result != OK:
  push_error("Atomic CPU evidence write failed: " + str(result))
  quit(2)

func require(ok:bool, message:String)->bool:
 if not ok: errors.append(message)
 return ok

func forbidden_save():
 errors.append("Synthetic Main invoked a forbidden save callback")
 report["valid"] = false
 write_report()
 push_error(errors[-1])
 quit(2)

func global_inventory()->Dictionary:
 return {"nodes":get_node_count(),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"static_memory_bytes":OS.get_static_memory_usage()}

func inventory()->Dictionary:
 var result = global_inventory()
 if is_instance_valid(game):
  result["native_slots"] = game.illustration.native_object_nodes.size()
  result["world_shapes"] = game.illustration.native_world_shapes.size()
 return result

func walk_capacity(node:Node, totals:Dictionary):
 totals.nodes += 1
 if node.is_queued_for_deletion(): totals.queued_nodes += 1
 if node is CanvasItem:
  if node.is_visible_in_tree(): totals.visible_canvas += 1
  else: totals.hidden_canvas += 1
 if node.get_script() == Native:
  totals.native_groups += 1
  totals.shape_slots += node.shapes.size()
  totals.resource_slots += node.resources.size()
  for child in node.shapes:
   if not is_instance_valid(child): totals.null_or_invalid_shape_slots += 1
 elif node.get_script() == Shape: totals.shape_nodes += 1
 for child in node.get_children(): walk_capacity(child,totals)

func registry_capacity(registry:Dictionary)->Dictionary:
 var totals = {"registered":registry.size(),"valid_roots":0,"invalid_roots":0,"duplicate_roots":0,"nodes":0,"descendants":0,"queued_nodes":0,"visible_canvas":0,"hidden_canvas":0,"native_groups":0,"shape_nodes":0,"shape_slots":0,"null_or_invalid_shape_slots":0,"resource_slots":0}
 var seen = {}
 for node in registry.values():
  if not is_instance_valid(node): totals.invalid_roots += 1;continue
  if seen.has(node.get_instance_id()): totals.duplicate_roots += 1;continue
  seen[node.get_instance_id()] = true
  totals.valid_roots += 1
  walk_capacity(node,totals)
 totals.descendants = totals.nodes - totals.valid_roots
 return totals

func owner_capacity()->Dictionary:
 var art = game.illustration
 var fallback = art.native_fallback_nodes if "native_fallback_nodes" in art else art.native_object_nodes
 var stable = art.native_actor_nodes if "native_actor_nodes" in art else {}
 var all = {"nodes":0,"queued_nodes":0,"visible_canvas":0,"hidden_canvas":0,"native_groups":0,"shape_nodes":0,"shape_slots":0,"null_or_invalid_shape_slots":0,"resource_slots":0}
 walk_capacity(art,all)
 var queued_direct = 0
 for child in art.get_children():
  if child.is_queued_for_deletion(): queued_direct += 1
 return {"fallback":registry_capacity(fallback),"stable":registry_capacity(stable),"world":registry_capacity(art.native_world_shapes),"recursive_artist":all,"queued_direct_native":queued_direct,"current_order_entries":art.native_object_nodes.size(),"actor_record_entries":art.native_actor_records.size() if "native_actor_records" in art else 0,"full_roster":game.model.customers.size()+game.staff_states.size()}

func atlas_owners()->Array:
 return [game.illustration.furniture_art.static_atlas,game.illustration.head_atlas,game.illustration.moving_atlas]

func atlas_snapshot()->Dictionary:
 var rows = {}
 var owners = atlas_owners()
 for index in owners.size():
  var atlas = owners[index]
  var texture = atlas.texture
  rows[ATLAS_NAMES[index]] = {"ready":atlas.is_ready(),"state":atlas.state,"reason":atlas.stats.get("reason",""),"prebaked":atlas.stats.get("prebaked",false),"texture_path":texture.resource_path if texture!=null else "","texture_size":plain(texture.get_size()) if texture!=null else [],"stats":plain(atlas.stats),"expected_path":Prebaked.PATHS[ATLAS_NAMES[index]]}
 return rows

func ready_ok()->bool:
 var owners = atlas_owners()
 for index in owners.size():
  var atlas = owners[index]
  if not atlas.is_ready() or atlas.state != "ready" or not bool(atlas.stats.get("prebaked",false)) or atlas.texture.resource_path != Prebaked.PATHS[ATLAS_NAMES[index]]: return false
 return true

func isolated()->bool:
 if not require(output!="" and "saveguard" in output and "saveguard" in OS.get_user_data_dir(),"Disposable output/profile required"): return false
 var roots = []
 for key in PROFILE_KEYS:
  var path = OS.get_environment(key)
  if not require(path.is_absolute_path() and "saveguard" in path and DirAccess.dir_exists_absolute(path),"Isolated profile root missing: " + key): return false
  if not require(path not in roots,"Profile roots must be distinct"): return false
  roots.append(path)
 for property in ProjectSettings.get_property_list():
  if not require(not str(property.name).begins_with("autoload/"),"Autoload is outside generated diagnostic scope"): return false
 if not require(not OS.has_feature("web") and not OS.has_feature("crazygames"),"Native-only generated diagnostic"): return false
 for flag in ["--runtime-atlases","--legacy-heads","--legacy-moving-art","--legacy-furniture","--skip-intro"]:
  if not require(flag not in OS.get_cmdline_user_args(),"Unsupported atlas/startup override: " + flag): return false
 return require(DisplayServer.get_name()=="X11" and RenderingServer.get_current_rendering_method()=="gl_compatibility","Actual native X11 GL Compatibility required")

func new_frozen_main():
 game = SyntheticMain.new()
 root.add_child(game)
 game.set_process(false)
 game.illustration.set_process(false)
 game.music_enabled = false
 game.settings_controls.bgm_enabled = false
 game.settings_controls.sfx_enabled = false
 require(game.web_save==null and game.platform_music==null and game.audio_players.is_empty(),"Account/music route unexpectedly started")

func state()->Dictionary:
 var art = game.illustration
 var model = game.model
 var components = {
  "model":{"width":model.width,"depth":model.depth,"revision":model.revision,"operating_open":model.operating_open,"coins":model.coins,"served":model.served,"earned":model.total_earned,"cleaned":model.total_cleaned,"payroll_elapsed":model.payroll_elapsed,"payroll_accrued":model.payroll_accrued,"wages_due":model.wages_due,"total_wages_paid":model.total_wages_paid,"next_customer_id":model._next_customer_id,"arrival_elapsed":model._arrival_elapsed,"next_checkout_ticket":model.next_checkout_ticket,"first_guest_pending":model.first_guest_pending,"duty_targets":model.duty_targets,"duty_counts":model.duty_counts,"ground_mess_generation":game.ground_mess_generation},
  "layout":{"items":model.items,"walls":model.built_walls,"attachments":model.wall_attachments,"floor_finishes":model.floor_finishes,"dining_sets":model.dining_sets,"owned_parcels":model.owned_parcels},
  "service":{"customers":model.customers,"outside_queue":model.outside_queue,"parking_visits":model.parking_visits,"records":game.service_guests,"floor":game.floor_tasks.snapshot(),"floor_generation":game.floor_tasks.generation,"dishwashing":game.dishwashing.snapshot()},
  "staff":game.staff_states,"staff_positions":game.staff_states.map(func(worker):return worker.node.position),
  "clock":{"animation_time":game.animation_time,"visual_timer":game.visual_timer,"paused":game.paused,"editing":game.editing,"cooking_motion_strength":art.cooking_motion_strength},
  "camera":{"zoom":art.zoom,"pan":art.pan_offset,"origin":art.origin,"tile":art.tile,"ui_scale":art.ui_scale,"wall_detail":game.wall_detail},
  "pose":{"motion":art.motion._actors,"facings":art.character_facings,"seats":art.seat_blends,"stances":art.stance_offsets,"carry_hands":art.carry_hand_offsets,"meal_chairs":art.meal_chair_offsets,"table_directions":art.table_dining_directions},
  "ambient":{"cars":art.road_traffic.cars,"road_elapsed":art.road_traffic.elapsed,"street_walkers":art.street_pedestrians.walkers,"street_departures":art.street_pedestrians.departures,"street_elapsed":art.street_pedestrians.elapsed,"street_motion":art.street_pedestrians.motion._actors,"street_visible":art.street_pedestrians.visible_ambient,"bus_actors":art.bus_stop_pedestrians.actors,"bus_motion":art.bus_stop_pedestrians.motion._actors}}
 return plain(components)

func observe(sample_index:int):
 var phases = {};var jobs = {};var actions = {};var active = 0;var moving = 0;var duty = 0
 for guest in game.model.customers: phases[guest.phase] = int(phases.get(guest.phase,0))+1
 for worker in game.staff_states:
  var job = str(worker.get("job_kind",""));jobs[job] = int(jobs.get(job,0))+1
  var action = str(worker.get("art_action",""));actions[action] = int(actions.get(action,0))+1
  if job!="": active += 1
  if worker.path.size()>int(worker.index): moving += 1
  if bool(worker.get("on_duty",false)): duty += 1
 observations.append({"sample_index":sample_index,"customers":game.model.customers.size(),"outside_queue":game.model.outside_queue.size(),"staff":game.staff_states.size(),"on_duty":duty,"job_assigned":active,"moving_staff":moving,"phases":phases,"jobs":jobs,"actions":actions,"served":game.model.served,"dishes_cleaned":game.model.total_cleaned,"litter":game.floor_tasks.messes.size(),"litter_completed":game.floor_tasks.completed,"parking":game.model.parking_visits.size(),"abandoned_active":game.model.customers.filter(func(guest):return bool(guest.get("meal_abandoned",false))).size(),"dishwashing_completed":game.dishwashing.completed,"blocked_staff":game.staff_states.filter(func(worker):return str(worker.get("blocked_reason",""))!="").size()})

func build_fixture()->bool:
 # Same retained control construction order and values; no business shortcuts.
 game.cafe_intro.finish()
 game.paused = true;game.model.coins = 10000000
 game.model.items = game.model.items.filter(func(item):return item.kind not in ["table","chair"])
 while not game.model.next_parcel().is_empty():
  if not require(game.model.expand(),"Expansion: " + game.model.last_error): return false
 var cells = []
 for z in [3,6,9,12,15]:
  for x in [2,5,11]: cells.append(Vector2i(x,z))
 for z in [3,6,9,12,15]: cells.append(Vector2i(14,z))
 for z in [3,6,9,12,15]: cells.append(Vector2i(17,z))
 for x in [2,5,11,14,17]: cells.append(Vector2i(x,0))
 for index in REQUESTED.seats:
  if not require(game.model.place("table_set",cells[index].x,cells[index].y,0,[]),"Seat setup: " + game.model.last_error): return false
 for pos in [Vector2i(13,1),Vector2i(15,1)]:
  if not require(game.model.place("stove",pos.x,pos.y,0,[]),"Stove setup: " + game.model.last_error): return false
 for item in game.model.items:
  if item.kind=="register":
   if not require(game.model.move(int(item.id),7,7,0,[]),"Register setup: " + game.model.last_error): return false
 game.model.rebuild_dining_sets();game.model._notify();game._rebuild_room();game._rebuild_furniture();game._update_people();game._sync_staff_duty()
 report["layout_access_issues"] = game.model.layout_access_issues()
 if not require(report.layout_access_issues.is_empty(),"Layout contains inaccessible station/seat"): return false
 var reachable = 0
 for pair in game.model._seating_pairs():
  if not game.model.guest_access_for(int(pair.chair_id),true,Vector2(-1.5,12.5),12.5,int(pair.table_id)).is_empty(): reachable += 1
 report["reachable_seats"] = reachable
 if not require(reachable==REQUESTED.seats,"Not all seating routes reachable"): return false
 for role in ["chef","chef","waiter","waiter","waiter","cleaner","cleaner"]:
  if not require(game.model.hire_staff(role),"Staff setup: " + game.model.last_error): return false
 game.model.cooks = 6;game.model.waiters = 8;game.model.cleaners = 7
 game.model.duty_targets = {"chef":6,"waiter":8,"cleaner":7,"cashier":1};game.model.duty_counts = game.model.duty_targets.duplicate()
 game._update_people();game._sync_staff_duty()
 game.model.customers.clear();game.model.outside_queue.clear();game.model.operating_open = true
 for batch in int(ceil(REQUESTED.guests/2.0)):
  game.model._spawn_walkers(mini(2,REQUESTED.guests-game.model.customers.size()))
  for guest in game.model.customers:
   var chair = game.model.get_item(int(guest.chair_id));var table = game.model.get_item(int(guest.table_id))
   guest.phase = "ordering";guest.elapsed = 0.0;guest.duration = game.model.ORDER_TAKING_SECONDS;guest.x = chair.x+.5;guest.z = chair.z+.5
   guest.seated = true;guest.admitted = true;guest.waiting = false;guest.route = [];guest.route_index = 0;guest.heading = Vector2(table.x-chair.x,table.z-chair.z);guest.dismounting = false
 if not require(game.model.customers.size()==REQUESTED.guests,"Population setup failed"): return false
 game.model.operating_open = false
 game.model.first_guest_pending = false;game._sync_service_guests();game._update_people()
 for z in range(18):
  for x in range(18):
   if game.floor_tasks.messes.size()<REQUESTED.litter: game.floor_tasks.spawn(Vector2i(x,z),"banana" if (x+z)%2==0 else "crumbs")
 if not require(game.floor_tasks.messes.size()==REQUESTED.litter,"Litter spawn setup failed"): return false
 var traffic = game.illustration.road_traffic
 while traffic.cars.size()<REQUESTED.cars:
  var index = traffic.cars.size();traffic.cars.append({"position":Vector2(traffic.LANES[index%2],-65.0+fmod(index*19.0,140.0)),"direction":1 if index%2==0 else -1,"color":"a2b3b3"})
 game.illustration.zoom = 1.0;game.illustration.pan_offset = Vector2.ZERO;game.illustration.update_projection(false)
 report["setup"] = {"customers":game.model.customers.size(),"staff":game.staff_states.size(),"roster":game.model.staff_roster(),"items":game.model.items.size(),"tables":game.model._seating_pairs().size(),"litter":game.floor_tasks.messes.size(),"ambient_cars":traffic.cars.size(),"width":game.model.width,"depth":game.model.depth,"operating_open":false,"road_visible":traffic.road_visible(game.illustration.origin,game.illustration.tile,game.illustration.render_view_rect())}
 return require(report.setup=={"customers":30,"staff":22,"roster":{"cashier":1,"chef":6,"cleaner":7,"waiter":8},"items":67,"tables":30,"litter":12,"ambient_cars":64,"width":18,"depth":18,"operating_open":false,"road_visible":true},"Setup differs from retained high-load fixture")

func finish(ok:bool):
 Probe.enabled = false;Probe.counting_enabled = false
 report["valid"] = ok and errors.is_empty()
 report["stage"] = "complete" if report.valid else "failed"
 if is_instance_valid(game):
  game.set_process(false)
  game.illustration.set_process(false)
  report["inventory_end"] = inventory()
  report["owner_capacity_end"] = owner_capacity()
 write_report()
 if is_instance_valid(game):
  completed_save_calls += game.save_calls
  game.queue_free()
  await process_frame
  await process_frame
 report["teardown"] = global_inventory()
 report.teardown["game_freed"] = not is_instance_valid(game)
 write_report()
 if not report.valid: push_error("Atlas-ready CPU control failed: " + str(errors))
 quit(0 if report.valid else 2)

func pure_checks():
 var result = Probe.pure_checks()
 var normalized = plain({"vector":Vector2(1,2),"node":null,"nested":[Vector3(3,4,5)]})
 result.checks.append({"name":"semantic-normalization", "passed":normalized=={"vector":[1.0,2.0],"nested":[[3.0,4.0,5.0]]}})
 result["passed"] = result.checks.all(func(row):return row.passed) and errors.is_empty()
 if output!="" and "saveguard" in output:
  DirAccess.make_dir_recursive_absolute(output.get_base_dir())
  var status = atomic_json(output,result)
  result["passed"] = result.passed and status==OK
 print("STABLE_ACTOR_CPU_PURE_RESULT ",JSON.stringify(result))
 quit(0 if result.passed else 2)

func run():
 report = {"valid":false,"stage":"preflight","case":OS.get_environment("CASE"),"seed":SEED,"warmup":WARMUP,"frames":FRAMES,"requested":REQUESTED,"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":[1360,880],"game_instance_created":false,"generated_profile":true,"retained_control_sha256":RETAINED_CONTROL_SHA256,"retained_probe_sha256":RETAINED_PROBE_SHA256,"fixture_sha256":FileAccess.get_sha256("res://tests/diagnostics/profile_stable_actor_atlas_ready.gd"),"probe_sha256":FileAccess.get_sha256("res://tests/diagnostics/stable_actor_cpu_probe.gd"),"source_sha256":{},"user_arguments":OS.get_cmdline_user_args(),"scope":"Synthetic above-cap52-actor stress capacity, not legal staffing or completed-service throughput. Native software-renderer CPU/resources only; no hardwareGPU, browser, FPS, churn or leak-freedom claim.","sequencing":"Frozen bootstrap normal readiness; teardown; reseed13017; fresh sampled Main and retained scene builder.60 completed native warmup frames then600 completed native frames. Legacy controls used process_frame boundaries, so their headless endpoints are not relabelled as this execution.","counter_scope":"Actual heads.draw_head/_draw_head_legacy, moving.draw_limb/_round_limb_legacy, furniture._cached_part/draw_static_part and actual try_draw_static bool results. Counts are callback branches, not all drawcalls; immutable retained sprites can have zero measured repaint callbacks."}
 if output!="": DirAccess.make_dir_recursive_absolute(output.get_base_dir())
 if not isolated(): await finish(false);return
 root.size = Vector2i(1360,880)
 for path in SOURCE_PATHS: report.source_sha256[path] = FileAccess.get_sha256("res://"+path)
 Probe.reset()
 seed(SEED)
 new_frozen_main()
 report.game_instance_created = true
 report["stage"] = "normal_atlas_preparation"
 write_report()
 var preparation_started = Time.get_ticks_msec()
 while game.startup_preparation_report.is_empty() and Time.get_ticks_msec()-preparation_started<10000:
  if atlas_owners().any(func(atlas):return str(atlas.state).ends_with("fallback")): break
  await process_frame
 report["atlas_ready"] = {"bootstrap":atlas_snapshot(),"preparation":plain(game.startup_preparation_report)}
 if not require(ready_ok() and not game.startup_preparation_report.is_empty() and game.startup_preparation_report.ready==3 and not game.startup_preparation_report.timed_out,"Normal imported original-three READY preparation failed"): await finish(false);return
 ready_owners = atlas_owners()
 for atlas in ready_owners: ready_textures.append(atlas.texture)
 report["bootstrap_business_state"] = {"served":game.model.served,"customers":game.model.customers.size(),"animation_time":game.animation_time,"street_elapsed":game.illustration.street_pedestrians.elapsed,"road_elapsed":game.illustration.road_traffic.elapsed}
 if not require(game.model.served==0 and game.model.customers.is_empty() and game.animation_time==0.0 and game.illustration.street_pedestrians.elapsed==0.0 and game.illustration.road_traffic.elapsed==0.0,"Bootstrap advanced business or ambient simulation"): await finish(false);return
 completed_save_calls += game.save_calls
 game.queue_free()
 await process_frame
 await process_frame
 report["bootstrap_teardown"] = global_inventory()
 if not require(not is_instance_valid(game),"Bootstrap Main remains alive"): await finish(false);return
 seed(SEED)
 Probe.counting_enabled = true
 new_frozen_main()
 var same = ready_owners==atlas_owners()
 for index in ready_owners.size(): same = same and ready_textures[index]==ready_owners[index].texture
 report.atlas_ready["same_owners_and_textures"] = same
 report.atlas_ready["sample_start"] = atlas_snapshot()
 if not require(ready_ok() and same,"Fresh sampled Main changed normal READY atlas ownership"): await finish(false);return
 report["fresh_start_state"] = state()
 if not build_fixture() or not errors.is_empty(): await finish(false);return
 report["initial_state"] = state()
 report["stage"] = "warmup"
 write_report()
 Engine.max_fps = 0
 report["engine_max_fps"] = Engine.max_fps
 report["fixed_simulation_fps"] = 60
 require(root.size==Vector2i(1360,880),"Native viewport changed")
 if not errors.is_empty(): await finish(false);return
 game.paused = false
 game.set_process(true)
 game.illustration.set_process(true)
 for frame in WARMUP:
  await RenderingServer.frame_post_draw
  if not ready_ok(): errors.append("Atlas left READY during warmup");await finish(false);return
 report["branches"] = {"warmup":Probe.counter_report()}
 report["warmup_state"] = state()
 report["inventory_start"] = inventory()
 report["owner_capacity_start"] = owner_capacity()
 observe(-1)
 Probe.reset_timings();Probe.reset_counts()
 report["stage"] = "measuring"
 write_report()
 var traffic = game.illustration.road_traffic
 for index in FRAMES:
  Probe.begin_frame(index)
  var previous = traffic.cars[0].position
  var before = Time.get_ticks_usec()
  await RenderingServer.frame_post_draw
  var after = Time.get_ticks_usec()
  Probe.end_frame()
  if traffic.cars[0].position!=previous: traffic_moved += 1
  population_frames.append({"sample_index":index,"customers":game.model.customers.size(),"outside_queue":game.model.outside_queue.size(),"staff":game.staff_states.size(),"litter":game.floor_tasks.messes.size(),"ambient_cars":traffic.cars.size(),"parking":game.model.parking_visits.size()})
  frame_metrics.append({"sample_index":index,"engine_frame":Engine.get_process_frames(),"boundary_wall_us":after-before,"process_monitor_us":Performance.get_monitor(Performance.TIME_PROCESS)*1000000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
  if not ready_ok() or not Probe.errors.is_empty() or game.save_calls!=0: errors.append("Measured frame lost readiness, timer balance, or save suppression");await finish(false);return
  if index%60==0:
   observe(index)
   write_report()
   print("STABLE_ACTOR_CPU_PROGRESS ",index," ",game.model.served," ",game.floor_tasks.completed)
 Probe.counting_enabled = false
 report["timings"] = Probe.report()
 report.branches["measured"] = Probe.counter_report()
 report["main_deltas"] = Probe.delta_report()
 report["frame_metrics"] = frame_metrics
 report["frame_metrics_scope"] = "Native completed post-draw boundary wall intervals include software-renderer/host scheduling, not GPU timings. Render monitors are raw engine counters, not CPU durations. Nested timings must not be summed twice."
 report["final_state"] = state()
 report["traffic_moving_frames"] = traffic_moved
 report.atlas_ready["sample_end"] = atlas_snapshot()
 var ticks = 0
 for deltas in report.main_deltas:
  ticks += deltas.size()
  if not require(deltas.size()==1 and absf(float(deltas[0])-1.0/60.0)<0.000000001,"Measured frame lacks one exact fixed1/60 Main tick"): break
 require(ticks==FRAMES and Probe.finished_frames==FRAMES,"Measured Main tick/frame count differs")
 require(observations.size()==11,"Activity snapshot cadence differs")
 require(completed_save_calls+game.save_calls==0,"Save callback occurred")
 for label in ["heads.sprite","limbs.sprite","furniture.sprite"]:
  require(int(report.branches.warmup.totals.get(label,0))+int(report.branches.measured.totals.get(label,0))>0,"No actual READY sprite branch observed: "+label)
 await finish(errors.is_empty())
