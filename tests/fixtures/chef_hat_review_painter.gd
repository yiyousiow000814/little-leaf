extends "res://scripts/illustrated_cafe.gd"
const BeforeCharacter=preload("res://tests/fixtures/chef_hat_before.gd")
var reviewed_species=0
var before=false
var cached=false
func _ready():
 set_process(false)
 texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
 head_atlas.request(self)
func _draw_head(p:Vector2,species:int,away:bool,blinked:bool,hat_on:bool,is_blocked:bool,view:int=-1):
 if before:
  var old=BeforeCharacter.new();old.a=self;old.origin=p;old.back=away;old.profile=view==2;old.blink=blinked;old.chef_hat=hat_on;old.blocked=is_blocked;old.head(species)
 elif cached and head_atlas.is_ready():head_atlas.draw_head(self,p,species,away,blinked,hat_on,is_blocked,view)
 else:_draw_head_legacy(p,species,away,blinked,hat_on,is_blocked,view)
func label_at(p:Vector2,text:String,size=20,color=Color("4e624b")):
 draw_string(ThemeDB.fallback_font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func _draw():
 draw_rect(Rect2(0,0,1360,880),Color("eee2c4"))
 label_at(Vector2(36,39),"CHEF HAT FIT / NATIVE GODOT 4.6.3",24)
 label_at(Vector2(36,70),["RABBIT", "FOX", "BEAR"][reviewed_species]+"   |   Left: baseline 0663eb1     Right: fitted candidate",18)
 for column in range(2):
  before=column==0
  var left=float(column)*680
  label_at(Vector2(left+35,105),"BEFORE" if before else "AFTER",22)
  for row in range(3):
   var top=120.0+float(row)*240
   var rear=row==2
   var side=row==1
   var view=2 if side else (3 if rear else 0)
   draw_line(Vector2(left+25,top),Vector2(left+650,top),Color("d4c5a3"),1)
   label_at(Vector2(left+34,top+30),["Front 3/4", "Side profile", "Rear 3/4"][row],17)
   art_transform(Vector2(left+135,top+154),0,Vector2.ONE*1.15)
   var character=DirectionalCharacter.new()
   character.draw(self,Vector2.ZERO,reviewed_species,rear,false,0,true,side,{"chef_hat":true,"role":"chef","action":"idle"})
   art_transform(Vector2.ZERO)
   label_at(Vector2(left+70,top+186),"1.15x play scale",15)
   art_transform(Vector2(left+430,top+307),0,Vector2.ONE*4)
   _draw_head(Vector2.ZERO,reviewed_species,rear,false,true,false,view)
   art_transform(Vector2.ZERO)
   label_at(Vector2(left+366,top+218),"4x native close view",15)
 draw_line(Vector2(680,82),Vector2(680,866),Color("d4c5a3"),2)
