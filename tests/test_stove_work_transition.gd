extends SceneTree
## Real service approach; never reset feet to make the transition pass.
class GeneratedMain extends "res://scripts/main.gd":
 func _load_startup():save_writes_suppressed=true;fresh_start=true;MinimalStart.apply(model)
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():root.size=Vector2i(1360,880);run.call_deferred()
func run():
 for dt in [.1,1.0/60.0]:
  for rotation in range(4):
   seed(123456)
   var game=GeneratedMain.new();root.add_child(game);game.set_process(false);game.illustration.set_process(false);game.tutorial.skip()
   game.paused=false;game.editing=false;game.model.operating_open=true
   var stove=game.model.get_item(1);stove.x=9;stove.z=4;stove.rot=rotation
   game._rebuild_furniture();game._sync_staff_duty();game.model._spawn_customer()
   var chef={};var previous_render=Vector2.ZERO;var previous_action="";var prep_seen=false;var previous_feet=[]
   for tick in 18000:
    game.model._arrival_elapsed=0;game._tick_live_service(dt);game._update_people();game._animate_staff(dt)
    var logical=[]
    for staff in game.staff_states:logical.append(staff.pos)
    game.illustration.update_motion(dt)
    for i in game.staff_states.size():check(game.staff_states[i].pos==logical[i],"presentation preserves logical staff position")
    for staff in game.staff_states:
     if staff.role!="chef":continue
     var key="staff_%s"%game.staff_states.find(staff)
     var rendered=game.illustration._render_position(key,staff.pos)
     var sample=game.illustration.motion.sample(key)
     var projected=Vector2((rendered.x-rendered.y)*39,(rendered.x+rendered.y)*19.5)
     var feet=[projected+sample.left_ground,projected+sample.right_ground]
     if staff.art_action=="preparing_food":prep_seen=true
     if staff.art_action=="cooking" and previous_action=="preparing_food":
      check(rendered.distance_to(previous_render)<.0001,"prep/cook transition has no retreat")
      check(feet[0].distance_to(previous_feet[0])<.001 and feet[1].distance_to(previous_feet[1])<.001,"planted shoe contacts remain continuous through handoff")
     previous_action=staff.art_action;previous_render=rendered;previous_feet=feet
     if staff.art_action=="cooking" and staff.job_elapsed>=2:chef=staff;break
    if not chef.is_empty():break
   check(not chef.is_empty() and prep_seen,"real preparation and cooking reached")
   if chef.is_empty():game.free();continue
   var key="staff_%s"%game.staff_states.find(chef)
   var logical=chef.pos;var elapsed=chef.job_elapsed
   for tick in int(ceil(2.0/dt)):game.illustration.update_motion(dt)
   var p=game.illustration.motion.sample(key)
   var toward=(Vector2(stove.x+.5,stove.z+.5)-logical).normalized()
   var intended=Vector2((toward.x-toward.y)*39,(toward.x+toward.y)*19.5*.96).normalized()
   check(p.left_lift==0 and p.right_lift==0,"both shoes settled on floor")
   check(p.left_axis.dot(intended)>.95 and p.right_axis.dot(intended)>.95,"shoes face natural stove approach")
   check(chef.pos==logical and chef.job_elapsed==elapsed,"motion settling changes neither position nor recipe clock")
   check((game.illustration._render_position(key,logical)-logical).distance_to(toward*.32)<.0001,"consistent .32 owned stove inset")
   print("STOVE_TRANSITION ",JSON.stringify({"rotation":rotation,"dt":dt,"left_axis":str(p.left_axis),"right_axis":str(p.right_axis),"intended_axis":str(intended),"logical":str(logical)}))
   game.free()
 print("STOVE_WORK_TRANSITION checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
