"""Exact fixture anchors; transforms apply only to the two disposable copies."""
from qualify import require

SHEET = "tests/diagnostics/capture_sink_washing.gd"
SIDE = "tests/diagnostics/capture_sink_side_handoff.gd"
ROLE = "tests/fixtures/role_fixture.gd"
FIXED = {
    SHEET: "a6449b70c1a9e337d231fd2c296d3d002bbae05bf7832fe4f5c643050c643a7d",
    SIDE: "1bc72537031c8cdd260a7be37a9a171f849cc18028d338f8b68cca532afade78",
    ROLE: "8201012fb673cc738f8651d67dd7120de5cc997d7d21001a7d9e681101ed54d9",
}
SHEET_LABELS = ("wash-cycle-all-rotations", "lift-continuity", "lower-continuity",
                *(f"motion-{i:02}" for i in range(20)), "paused-water-off", "idle-water-off",
                "multiple-sinks")
SIDE_LABELS = ("01-carrying", "02-dropping", "02b-precontact", "03-queued",
               "03b-lowering", "03c-settled", "04-first-clean", "05-all-clean")

MULTI = """ func draw_multiple_sinks():
  game.dishwashing.dishes={90:{"id":90,"sink_id":3,"elapsed":0.0},16:{"id":16,"sink_id":94,"elapsed":0.0},3:{"id":3,"sink_id":3,"elapsed":4.3},50:{"id":50,"sink_id":3,"elapsed":0.0}}
  game.staff_states.clear()
  var sink=game.model.get_item(3);sink.x=0;sink.z=0;sink.rot=0
  var secondary=game.model.get_item(94);secondary.x=3;secondary.z=3;secondary.rot=1
  var empty=game.model.get_item(95);empty.x=5;empty.z=5;empty.rot=3
  game.paused=false;game.animation_time=4.3
  var worker={"role":"cleaner","job_kind":"wash","job_dish_id":3,"station_id":3,"job_elapsed":4.3,"pos":game.model.cell_center(game.model.workface_cell(sink)),"art_action":"washing"}
  game.staff_states.append(worker)
  _begin_drawing_lookups()
  for index in range(3):
   var item=[sink,secondary,empty][index]
   art_transform(Vector2(255+index*410,530),0,Vector2.ONE*4.5)
   furniture_art.draw_item(self,"sink",Vector2.ZERO,int(item.rot),int(item.id));_sink_dishes(int(item.id))
  if has_method("_sink_queue_ids"):
   assert(call("_sink_queue_ids",3,3)==[50,90] and call("_sink_queue_ids",94,-1)==[16] and call("_sink_queue_ids",95,-1)==[],"Expected exact ordered per-sink queues")
  if " _drawing_sink_rows".strip_edges() in self:
   assert(_drawing_sink_rows!=null and _drawing_sink_rows.has(3) and _drawing_sink_rows.has(94) and not _drawing_sink_rows.has(95),"Optimized real draw scope used")
  _finish_drawing_lookups()
  art_transform(Vector2.ZERO)
"""

# Variant-only property must be accessed dynamically: the control type does
# not declare it. GDScript compiles member access even behind a false branch.
MULTI = MULTI.replace('if " _drawing_sink_rows".strip_edges() in self:\n   assert(_drawing_sink_rows!=null and _drawing_sink_rows.has(3) and _drawing_sink_rows.has(94) and not _drawing_sink_rows.has(95),',
                      'if "_drawing_sink_rows" in self:\n   var rows=get("_drawing_sink_rows")\n   assert(rows!=null and rows.has(3) and rows.has(94) and not rows.has(95),')

READY = """ game.set_process(false)
 for wait_frame in 900:
  if not is_instance_valid(game.startup_readiness) or game.startup_readiness.completed:break
  await process_frame
 assert(not game.startup_preparation_report.is_empty() and not game.startup_preparation_report.timed_out and game.startup_preparation_report.ready==3,"Three atlases must reach READY")
 if game.cafe_intro!=null:game.cafe_intro.finish()
 assert(game.cafe_intro!=null and not game.cafe_intro.active and not game.cafe_intro.preparing and not game.cafe_intro.cover.is_visible_in_tree(),"Welcome cover must be gone")
 for tween in get_processed_tweens():tween.kill()
 game.animation_time=1.0
 game.illustration.set_process(false)"""


def overlay(path, original):
    text = original.decode()
    if path == SHEET:
        pairs = (
            ('  var worker=sample(rotation,time,count)', '  var worker=sample(rotation,time,count)\n  _begin_drawing_lookups()'),
            ('  art_transform(Vector2.ZERO)\n func draw_worker', '  art_transform(Vector2.ZERO)\n  _finish_drawing_lookups()\n func draw_worker'),
            (' func _draw():', MULTI + ' func _draw():'),
            ('  else:\n   draw_string(font,Vector2(75,85)', '  elif mode=="multi":draw_multiple_sinks()\n  else:\n   draw_string(font,Vector2(75,85)'),
            (' var fixture=FixtureGame.new();fixture.model.reset_new();root.add_child(fixture)', ''' var fixture=FixtureGame.new();fixture.model.reset_new();root.add_child(fixture)
 fixture.model.items.append({"id":94,"kind":"sink","rot":1,"x":3,"z":3})
 fixture.model.items.append({"id":95,"kind":"sink","rot":3,"x":5,"z":5})
 fixture.model.revision+=1'''),
            (' FileAccess.open(OS.get_environment("OUTPUT")+"/contacts.json"', ''' sheet.mode="multi";await capture(sheet,"multiple-sinks")
 FileAccess.open(OS.get_environment("OUTPUT")+"/contacts.json"'''),
            ('frames=25 rotations=4', 'frames=26 rotations=4 scoped=true'),
        )
    elif path == SIDE:
        pairs = (
            (' game.set_process(false);game.illustration.set_process(false)', READY),
            ('  check(game._service_destination(waiter,sink,from)==right,"occupied left side excludes another character")',
             '''  # The current complementary front-contact path can stay legal.
  # Temporarily close it so this assertion isolates left vs right occupancy.
  var front_blocker={"id":99993,"kind":"stove","x":front.x,"z":front.y,"rot":0}
  game.model.items.append(front_blocker);game.model.revision+=1
  check(game._service_destination(waiter,sink,from)==right,"occupied left side excludes another character")
  game.model.items.erase(front_blocker);game.model.revision+=1'''),
            (' await RenderingServer.frame_post_draw\n root.get_texture()', ''' await RenderingServer.frame_post_draw
 assert(not game.cafe_intro.active and not game.cafe_intro.cover.is_visible_in_tree(),"Visible cafe required after draw")
 root.get_texture()'''),
            (' facts.checks=checks;', ' facts.intro_clear=not game.cafe_intro.active and not game.cafe_intro.cover.is_visible_in_tree();facts.checks=checks;'),
        )
    else:
        return original
    for old, new in pairs:
        require(text.count(old) == 1, "Fixture transform anchor absent or ambiguous: " + path)
        text = text.replace(old, new, 1)
    return text.encode()
