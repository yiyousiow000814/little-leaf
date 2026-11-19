"""Reuse the original three observed customer routes, not the obsolete art A/B."""
from hashlib import sha256

FIXTURE = "tests/diagnostics/capture_litter_visibility.gd"


def overlay(original: bytes, expected: str) -> bytes:
    if sha256(original).hexdigest() != expected:
        raise ValueError("Unexpected original litter fixture bytes")
    text = original.decode()
    text = text.replace('const Illustration=preload("res://scripts/rendering/illustrated_cafe.gd")\n', '')
    for line in ("const BeforeArt", "const BeforeGeometry", "const BeforeTasks", "const AfterTasks"):
        text = "\n".join(r for r in text.split("\n") if not r.startswith(line))
    start = text.index("class OldIllustration")
    end = text.index("class FixtureMain", start)
    text = text[:start] + text[end:]
    text = text.replace(' func _save():return true',' var saves=0\n func _save():saves+=1;return true')
    text = text.replace(' var mode=OS.get_environment("LITTER_CAPTURE_MODE")',' seed(320039)\n root.size=Vector2i(1360,880)\n var semantic_only=OS.get_environment("LITTER_SEMANTIC_ONLY")=="1"')
    start = text.index(' if mode=="before":')
    end = text.index(" game.model.customers.clear();game.model._spawn_customer()", start)
    text = text[:start] + ''' game.illustration.set_process(false)
 if not semantic_only:
  for i in range(900):
   if not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed:break
   await process_frame
  assert(not game.startup_preparation_report.is_empty() and not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready==3)
  game.cafe_intro.finish()
  assert(visible_cafe())
 for tween in get_processed_tweens():tween.kill()
''' + text[end:]
    text = text[:text.index(' var cases=[]')] + '''
 assert(game.floor_tasks.messes.size()==3 and game.saves==0 and game.save_writes_suppressed)
 game.illustration.zoom=2.1;game.illustration.pan_offset=Vector2(160,-150)
 game.illustration.update_projection();game._update_ui()
 var anchors=[]
 for record in game.floor_tasks.messes.values():
  assert(game.illustration._floor_mess_active(record))
  var point:Vector2=record.debris_target
  var pixel:Vector2=game.illustration.iso(point.x,point.y)
  if Rect2(48,100,1264,690).has_point(pixel):anchors.append({"id":record.id,"point":pixel})
 assert(not anchors.is_empty(),"Rendered fixture must frame active litter")
 if not semantic_only:
  assert(visible_cafe())
  game.illustration.queue_redraw()
  for i in range(4):await process_frame
  await RenderingServer.frame_post_draw
  assert(visible_cafe())
  var image:=root.get_texture().get_image()
  assert(image!=null and image.get_size()==Vector2i(1360,880))
  assert(image.save_png(OS.get_environment("OUTPUT")+"/litter.png")==OK)
 var report={"semantic_only":semantic_only,"native_visible":not semantic_only and visible_cafe(),"save_attempts":game.saves,"player_save_used":false,"routes":routes,"messes":game.floor_tasks.snapshot(),"in_frame_active_litter":anchors}
 FileAccess.open(OS.get_environment("OUTPUT")+"/runtime.json",FileAccess.WRITE).store_string(JSON.stringify(Codec.new().encode(report),"  "))
 print("LITTER_NATIVE_COMPLETE ",game.floor_tasks.messes.size())
 quit()

func visible_cafe()->bool:
 return game.cafe_intro!=null and not game.cafe_intro.active and not game.cafe_intro.preparing and not game.cafe_intro.cover.is_visible_in_tree()
'''
    return text.encode()
