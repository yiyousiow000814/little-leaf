extends "res://tests/presentation/test_shared_work_stance.gd"
const Stance=preload("res://scripts/rendering/shared_work_stance.gd")
func run():
 for roster in [true,false]:
  for done in ["waiter","cleaner"]:completion_case(roster,done)
 restore_case()
 for style in ["basic","cottage","retro","refined"]:wipe_case(style)
 for style in ["basic","cottage","retro","refined"]:
  for rotation in 4:Stance.TableContact.geometry(style,rotation)
 check(Stance.TableContact._styles.size()<=16,"immutable authored geometry cache is bounded to four styles and rotations")
 # The local finishing prop has no external rim: its rigid handle stays held.
 for back in [true,false]:
  var hand=Pose.relaxed_pan_hand(back);var original=Pose.carried_pan(hand,back,0,false)
  for phase in [0.0,.25,.5,.75,1.0]:
   var pose=Pose.local_disposal_pose(hand,back,phase)
   check(pose.hand==hand and is_equal_approx(pose.pan.distance_to(hand),original.pan.distance_to(hand)),"local finishing pan remains rigidly attached to its unchanged paw")
   if phase in [0.0,1.0]:check((pose.pan as Vector2).is_equal_approx(original.pan),"local finish joins carrying pose without a prop teleport")
 print("SHARED_STANCE_LIFECYCLE_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"pixel_qualification":false,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
func completion_case(roster:bool,done:String):
 var g=fixture(roster,2 if done=="cleaner" else 0);var w=worker(g,"waiter");var c=worker(g,"cleaner");var art=Art.new();art.game=g
 tick(g)
 for frame in 12:art.update_motion(.05)
 worker(g,done).job_elapsed=.79 if done=="waiter" else .89
 var minimum=INF;var retired=-1;var crossed=false;var maximum_groups=0
 for frame in 45:
  tick(g);var before=g._current_service_snapshot();var offsets=art.stance_offsets.duplicate(true)
  art.update_motion(.05)
  var shown_w=art._render_position("staff_%s"%g.staff_states.find(w),w.pos);var shown_c=art._render_position("staff_%s"%g.staff_states.find(c),c.pos)
  var gap=separation(shown_w,shown_c);minimum=minf(minimum,gap)
  check(gap>=.99999,done+" first: full departure remains separated at frame "+str(frame)+", roster="+str(roster))
  check(g._current_service_snapshot()==before,"release presentation cannot delay or reschedule service")
  for key in offsets:
   if key.begins_with("staff_") and art.stance_offsets.has(key):check((art.stance_offsets[key] as Vector2).distance_to(offsets[key])<=.075001,"display offset releases at its unchanged speed")
  var ids={};var participants=0
  for cached in art.shared_stance_cache.values():
   for entry in cached.entries:
    participants+=1;check(not ids.has(entry.actor_id),"one retained display entry per stable actor identity");ids[entry.actor_id]=true
    check(g.staff_states[int(entry.worker)].node.get_instance_id()==entry.actor_id,"retained display actor identity matches current roster")
  check(participants<=g.staff_states.size(),"retention is bounded by current roster, not elapsed frames")
  maximum_groups=maxi(maximum_groups,art.shared_stance_cache.size())
  if Vector2i(worker(g,done).pos.floor())!=CELL:crossed=true
  if art.shared_stance_cache.is_empty() and retired<0:retired=frame
 check(crossed and retired>=0 and art.shared_stance_cache.is_empty(),"safe release crosses cell boundary and retires all display history")
 check(w.job_kind!="deliver_meal" and (done!="cleaner" or c.job_kind!="floor"),"completed jobs are not retained for presentation")
 evidence.append({"completion_first":done,"roster_cleaner_first":roster,"minimum_separation":minimum,"retired_frame":retired,"frames":45,"maximum_groups":maximum_groups})
 art.game=null;art.free();release(g)
func restore_case():
 var g=fixture(true);var art=Art.new();art.game=g;tick(g)
 for frame in 12:art.update_motion(.05)
 var bytes=g._current_service_snapshot();g.model.service_snapshot=bytes.duplicate(true);g._restore_service_runtime()
 var restored=g._current_service_snapshot()
 for frame in 12:art.update_motion(.05)
 check(g._current_service_snapshot()==restored,"restore rebuilds display without changing clocks/custody")
 check(worker(g,"waiter").pos==worker(g,"cleaner").pos,"restore keeps original shared logical cell")
 for cached in art.shared_stance_cache.values():
  for entry in cached.entries:check(g.staff_states[int(entry.worker)].node.get_instance_id()==entry.actor_id,"restore discards old node identity")
 art.game=null;art.free();release(g)
func wipe_case(style:String):
 var g=fixture(true);var w=worker(g,"waiter");var c=worker(g,"cleaner");var record=g.service_guests.values()[0]
 g.model.dining_set_for(int(record.guest.table_id)).variant="oak_single" if style=="basic" else style+"_single";g.model.revision+=1
 w.job_kind="cleanup";w.job_step=2;w.job_elapsed=.1
 record.guest.phase="dirty";record.guest.seated=false;record.guest.paid=true;record.guest.x=-1.5;record.guest.z=6.5
 record.dishes_collected=true;record.plate_owner="dish_queue";record.plate_staff_index=-1;record.drink_owner="cleared";record.table_wiped=false
 tick(g);var art=Art.new();art.game=g;var saved=g._current_service_snapshot();var key="staff_%s"%g.staff_states.find(w);var floor_key="staff_%s"%g.staff_states.find(c)
 var minimum_support=INF;var maximum_candidates=0;var maximum_previews=0;var maximum_steps=0;var entry={}
 for frame in 35:
  art.update_motion(.05)
  maximum_candidates=maxi(maximum_candidates,int(art.shared_stance_stats.candidate_checks));maximum_previews=maxi(maximum_previews,int(art.shared_stance_stats.motion_previews));maximum_steps=maxi(maximum_steps,int(art.shared_stance_stats.candidate_steps))
  check(art.shared_stance_stats.motion_previews<=34,"next-pose preview is bounded to current shared wiper candidates")
  check(g._current_service_snapshot()==saved,"wipe rendering cannot change actual eligible service")
  for cached in art.shared_stance_cache.values():
   maximum_candidates=maxi(maximum_candidates,int(cached.placement.metrics.candidate_checks))
   check(cached.placement.metrics.candidate_checks<=32*cached.entries.size(),"bounded candidate domain checks")
   for candidate in cached.entries:
    if candidate.key==key:
     entry=candidate.duplicate();art._shared_contact_geometry(entry,g.model.get_item(int(entry.target_id)))
  if entry.is_empty():continue
  var offset:Vector2=art.stance_offsets[key]
  minimum_support=minf(minimum_support,Stance.TableContact.support_gap(entry,offset,art.motion.sample(key)))
  check(Stance._blocked_by(entry,w.pos,w.pos+offset,g.model)=="","wipe keeps strict unrelated furniture and wall clearance")
 check(not entry.is_empty() and art.shared_stance_constraints.is_empty(),style+" shared wiping has a solved placement, not fallback")
 if not entry.is_empty():
  var offset:Vector2=art.stance_offsets[key]
  check(Stance.TableContact.contact(entry,offset),style+" full cloth reaches actual authored table with unchanged arms")
  check(minimum_support>=Stance.TableContact.INK_MARGIN,style+" actual moving/planted shoes clear target supports")
  check(separation(w.pos+offset,c.pos+art.stance_offsets[floor_key])>=.99999,style+" shared wiping separates intact bodies")
  var current_entries=[]
  for descriptor in art.shared_stance_cache[CELL].entries:
   check(not descriptor.has("clearance_items"),"retention contains no copied furniture/model dictionaries")
   var current=descriptor.duplicate();art._shared_contact_geometry(current,g.model.get_item(int(current.target_id)));current_entries.append(current)
  var solved=Stance.solve(current_entries,g.model,art.stance_offsets,art.shared_stance_cache[CELL].placement.domains)
  check(solved.metrics.domain_reuses==2 and solved.metrics.candidate_checks<=2,"unchanged contact domains reuse immutable contact witnesses")
  var motion_before=art.motion._actors.duplicate(true)
  var predicted=art.motion.preview(key,w.pos+offset,.05)
  check(art.motion._actors==motion_before and not predicted.is_empty(),"one-actor next-pose preview cannot mutate actual motion")
  var cached=art.shared_stance_cache.duplicate(true);art.update_motion(.05)
  check(art.shared_stance_cache==cached,"settled frame performs no new candidate/contact solve")
  check(art.shared_stance_stats.candidate_checks==0 and art.shared_stance_stats.candidate_steps==0 and art.shared_stance_stats.motion_previews==0,"settled feet perform zero domain, step or motion-preview work")
  # Dense verification is test-only; production caches eight phase witnesses.
  check(full_cloth_contact(entry,offset),style+" all 65 test stroke samples stay on the real tabletop")
  evidence.append({"style":style,"wipe_offset":offset,"floor_offset":art.stance_offsets[floor_key],"minimum_drawn_support_gap_px":minimum_support,"candidate_checks":maximum_candidates,"maximum_candidate_steps":maximum_steps,"maximum_motion_previews":maximum_previews,"maximum_preview_actor_copies":maximum_previews})
 art.game=null;art.free();release(g)
func full_cloth_contact(entry:Dictionary,offset:Vector2)->bool:
 var heading:Vector2=entry.contact-entry.center;var back=heading.x+heading.y<0;var mirror=-1.0 if heading.x-heading.y<0 else 1.0
 var near=Vector2(7,-24) if back else Vector2(-7,-24);var far=Vector2(-6,-26.5) if back else Vector2(6,-26.5)
 var floor=Art.MotionArt.project(entry.center+offset-entry.contact);var top=-floor*Vector2(mirror,1)+Vector2(0,-Stance.TableContact.Dining.TABLE_HEIGHT-1)
 for i in 65:
  var pose=Pose.table_pose(near,far,top,float(i)/64)
  if not pose.contact or not is_equal_approx(pose.hand.distance_to(near),10.5):return false
  var hand=floor+pose.hand*Vector2(mirror,1)
  for point in entry.table_geometry.cloth:
   if Stance.TableContact._distance(hand+point*Vector2(mirror,1),entry.table_geometry.top)>-Stance.TableContact.INK_MARGIN:return false
 return true
