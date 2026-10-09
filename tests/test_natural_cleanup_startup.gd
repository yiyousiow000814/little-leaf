extends "res://tests/observe_natural_cleanup.gd"
## Validate the observation harness starts real play, not cleanup sufficiency.
func run():
 observation_seconds=2.0;drain_seconds=2.0
 await super.run()
func write_result(status:String,_reason:String):
 var failures=[]
 if status!="inconclusive":failures.append("short natural window should explicitly remain inconclusive")
 if wall_seconds()<1.9 or game.animation_time<=0.0 or game.animation_time>wall_seconds()*1.2:failures.append("real normal-speed game time must advance with wall time")
 if samples.size()<2 or not initial.get("open",false):failures.append("actual fresh operating startup and samples required")
 print("NATURAL_CLEANUP_STARTUP_RESULT ",JSON.stringify({"checks":3,"failures":failures,"wall_seconds":wall_seconds(),"game_seconds":game.animation_time,"cleanup_sufficiency_verified":false,"player_save_used":false}))
 quit(0 if failures.is_empty() else 1)
