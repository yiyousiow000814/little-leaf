extends SceneTree
const Model=preload("res://scripts/cafe_model.gd")
func _initialize():run.call_deferred()
func run():
 var model=Model.new()
 var mode=OS.get_environment("QUEUE_COMPAT_MODE")
 var input=OS.get_environment("QUEUE_COMPAT_INPUT")
 var output=OS.get_environment("QUEUE_COMPAT_OUTPUT")
 var ok=true
 if mode=="produce":
  model.tick(16.0)
  ok=model.get("outside_queue").size()==6 and model.customers.size()==2
 else:ok=model.load_save(input)
 if ok:ok=model.save(output)
 var queue=model.get("outside_queue")
 print("QUEUE_BACKWARD_RESULT ",JSON.stringify({"mode":mode,"ok":ok,"error":model.last_error,"customers":model.customers.size(),"queue":queue.size() if queue is Array else null,"next_id":model._next_customer_id,"user_data":OS.get_user_data_dir()}))
 quit(0 if ok else 1)
