extends SceneTree
const Character=preload("res://scripts/directional_character_art.gd")
const Occlusion=preload("res://scripts/character_arm_occlusion.gd")
const Harness=preload("res://tests/test_arm_occlusion.gd")
var checks=0
var failures=[]
func check(ok,label):
 checks+=1
 if not ok and not failures.has(label):failures.append(label);printerr(label)
func area(p:PackedVector2Array)->float:
 var result=0.0
 for i in p.size():result+=p[i].cross(p[(i+1)%p.size()])
 return absf(result)*.5
func _initialize():
 var artist=Harness.Artist.new();var painter=Character.new()
 for back in [false,true]:
  for mirror in [1.0,-1.0]:
   var plate=Vector2(39*.88-5*mirror,(-19.5 if back else 19.5)*.88-32.5)
   for species in range(3):
    for phase in [.0,.03,.05,.0625,.08,.10,.14,.18,.21,.24,.25,.44,.745,.805,.82,.92,.99,1.0]:
     var settings={"action":"eating","progress":phase,"reach":plate,"seat_mix":1.0,"mirror":mirror,"view_back":back,"shirt":"95b9bb","hide_reach":not back}
     artist.commands.clear()
     var base=painter.draw(artist,Vector2.ZERO,species,back,false,0.0,false,false,settings)
     var shoulder=(Vector2(-6,-26.5) if back else Vector2(6,-26.5))+base.body
     check(base.far_shoulder==shoulder,"Dining integration moves original far socket")
     var arm_indices=[];var torso=-1
     for index in artist.commands.size():
      var c=artist.commands[index]
      if c.kind=="limb" and c.start==base.far_shoulder and is_equal_approx(c.width,4.4):arm_indices.append(index)
      if c.kind=="shape" and c.color is String and c.color=="95b9bb" and torso<0:torso=index
     check(arm_indices.size()==1 and arm_indices[0]<torso,"Dining far arm is not drawn once behind torso")
     if not back:
      artist.commands.clear();settings.hide_reach=false;settings.reach_overlay=true
      var over=painter.draw(artist,Vector2.ZERO,species,back,false,0.0,false,false,settings)
      check(over.far_shoulder==base.far_shoulder and over.far_hand==base.far_hand,"Dining overlay changes the physical pose")
      check(artist.commands.filter(func(c):return c.kind=="limb").is_empty(),"Dining overlay repaints a whole arm")
      if not over.dining_pose.over_table:check(artist.commands.is_empty(),"Lowered dining arm escapes table/cup occlusion")
      var masks:Array[PackedVector2Array]=[Occlusion.rounded(Occlusion.torso_points(false),3.5)]
      masks.append_array(Occlusion.head_masks(false,false,species,over.dining_pose.head_offset))
      for c in artist.commands:
       if c.kind!="clipped":continue
       var local=PackedVector2Array()
       for point in c.points:local.append(point-base.body)
       check(not Geometry2D.is_point_in_polygon(Vector2(6,-26.5),local),"Dining far shoulder root is exposed")
       for mask in masks:
        var overlap=0.0
        for polygon in Geometry2D.intersect_polygons(local,mask):overlap+=area(polygon)
        check(overlap<.0005,"Dining overlay paints through torso/head")
 artist.free()
 print("DINING_OCCLUSION_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
