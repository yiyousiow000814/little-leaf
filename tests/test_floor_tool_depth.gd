extends SceneTree
const Character=preload("res://scripts/directional_character_art.gd")
class Recorder extends Node2D:
 var commands=[]
 func col(c):return Color(c)
 func art_polyline(_p,_c,_w):pass
 func _face_ellipse(_p,_r,_c):pass
 func _face_line(_p,_q,_c,_w):pass
 func _round_limb(p,q,c,w):commands.append({"kind":"arm","p":p,"q":q,"color":c,"width":w})
 func rounded_poly(p,r,c):commands.append({"kind":"shape","points":p,"color":c,"radius":r})
 func poly(_p,_c):pass
 func ellipse(p,r,c):commands.append({"kind":"ellipse","p":p,"r":r,"color":c})
 func line(_p,_q,_c,_w):pass
 func _draw_head(_p,_s,_b,_blink,_hat,_blocked,_view):commands.append({"kind":"head"})
 func _draw_floor_tools(_at,pose,_action,_payload):commands.append({"kind":"tools","pose":pose})
 func _action_prop(_p,_carry,_action,_t,_payload,_tool,_work_hand,_tip,_floor):pass
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr("FAIL ",label)
func _initialize():
 var art=Recorder.new();var character=Character.new()
 # These include the rejected near-vertical rear mop and back-right sweep.
 for back in [false,true]:
  for contact in [Vector2(3,-16),Vector2(18,-9),Vector2(24,-4),Vector2(24,12)]:
   if not back and contact.y<0:continue
   var previous={}
   for action in ["sweeping","mopping"]:
    for tick in range(101):
     var phase=tick/100.0;art.commands.clear()
     var g=character.draw(art,Vector2.ZERO,2,back,false,0.0,true,false,{"action":action,"tool":"broom" if action=="sweeping" else "mop","progress":phase,"reach":contact-Vector2(3,-3),"role":"cleaner","shirt":"91b2ad"})
     var pose=g.cleaning_pose
     check(is_equal_approx(g.near_shoulder.distance_to(g.near_hand),10.5) and is_equal_approx(g.far_shoulder.distance_to(g.far_hand),10.5),"cleaning retains both short arms")
     var tools=-1;var torso=-1;var head=-1;var far_grip=-1
     for i in art.commands.size():
      var c=art.commands[i]
      if c.kind=="tools":check(tools<0,"floor tools painted only once");tools=i
      elif c.kind=="shape" and c.color is String and c.color=="91b2ad" and torso<0:torso=i
      elif c.kind=="head":head=i
      elif c.kind=="ellipse" and c.p.is_equal_approx(g.far_hand) and c.r==Vector2(2,2):far_grip=i
     check(head>torso and head>tools,"intact head occludes tools")
     if back:
      check(tools<torso,"rear floor tools are behind intact torso")
      if action=="sweeping":check(far_grip>=0 and far_grip<torso,"rear far grip never floats over the back")
      check(pose.near_hand.y<pose.brush.y-5,"rear broom/mop is gripped above the floor head")
      if action=="sweeping":check(pose.far_hand.y<pose.pan.y-5,"rear pan is gripped above its floor tray")
     else:check(tools>torso,"front tool depth stays unchanged")
     if tick>0:
      check(pose.near_hand.distance_to(previous.near_hand)<.5 and pose.far_hand.distance_to(previous.far_hand)<.5,"grips remain continuous throughout a stroke")
     previous=pose
 art.free();print("FLOOR_TOOL_DEPTH_RESULT ",JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
