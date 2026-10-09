extends SceneTree
const Character=preload("res://scripts/directional_character_art.gd")
const Before=preload("res://tests/fixtures/head_polish_before.gd")
const Atlas=preload("res://scripts/character_head_atlas.gd")
class Recorder extends Node2D:
 var commands=[]
 var extents=Rect2()
 var initialized=false
 func mark(point:Vector2):
  if not initialized:extents=Rect2(point,Vector2.ZERO);initialized=true
  else:extents=extents.expand(point)
 func ellipse(p:Vector2,r:Vector2,c):
  commands.append(["ellipse",p,r,c]);mark(p-r);mark(p+r)
 func _face_ellipse(p:Vector2,r:Vector2,c):ellipse(p,r,c)
 func line(p:Vector2,q:Vector2,c,w=1.0):
  commands.append(["line",p,q,c,w]);mark(p-Vector2.ONE*w*.5);mark(p+Vector2.ONE*w*.5);mark(q-Vector2.ONE*w*.5);mark(q+Vector2.ONE*w*.5)
 func _face_line(p:Vector2,q:Vector2,c,w=1.0):line(p,q,c,w)
 func rounded_poly(points:Array,r:float,c):
  commands.append(["shape",points,r,c])
  for point in points:mark(point)
var checks=0
var failures=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func record(script,species,view,hat_on,blinked=false,is_blocked=false):
 var artist=Recorder.new()
 var head=script.new();head.a=artist;head.origin=Vector2.ZERO;head.back=view==3;head.profile=view==2;head.chef_hat=hat_on;head.blink=blinked;head.blocked=is_blocked
 head.head(species)
 return artist
func _initialize():
 var front_record
 var side_record
 var rear_record
 for species in range(3):
  for view in [0,1,2,3]:
   for blinked in [false,true]:
    for blocked in [false,true]:
     var old=record(Before,species,view,false,blinked,blocked)
     var plain=record(Character,species,view,false,blinked,blocked)
     var old_dressed=record(Before,species,view,true,blinked,blocked)
     var dressed=record(Character,species,view,true,blinked,blocked)
     # Head polish intentionally changes the plain face. The fitted hat must
     # still append the exact reviewed geometry, with unchanged ear ports.
     check(old_dressed.commands.slice(old.commands.size())==dressed.commands.slice(plain.commands.size()),"Fitted hat geometry changed")
     check(Character.head_bounds(species,view==2,false).grow(.8).encloses(plain.extents),"Polished plain head exceeds contact envelope")
     old.free();old_dressed.free();plain.free()
     var bounds=Character.head_bounds(species,view==2,true)
     check(bounds.grow(.8).encloses(dressed.extents),"Head bounds clip chef species=%d view=%d"%[species,view])
     check(Atlas.ART_RECT.grow(-1).encloses(dressed.extents),"Head atlas has no transparent gutter")
     if species==0:
      check(dressed.extents.position.y<=(-73 if view==2 else -72),"Rabbit ear tip removed/shortened")
      var ports=0
      for c in dressed.commands:
       if c[0]=="ellipse" and str(c[3])=="c3b28d":ports+=1
      check(ports==2,"Rabbit must have two visible fitted ear openings")
     if species==0 and not blinked and not blocked:
      if view==0:front_record=dressed.commands.duplicate(true)
      elif view==2:side_record=dressed.commands.duplicate(true)
      elif view==3:rear_record=dressed.commands.duplicate(true)
     dressed.free()
 check(front_record!=side_record and front_record!=rear_record and side_record!=rear_record,"Hat/head views must be orientation-aware")
 var atlas=Atlas.new()
 check(atlas.entries.size()==78,"Head cache cardinality changed")
 check(atlas.regions.size()==78,"Head cache keys collide")
 for species in range(3):
  check(Character.head_bounds(species,false,true).position.y<=-63,"Chef thought bubble ignores higher crown")
 print("CHEF_HAT_TESTS checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
