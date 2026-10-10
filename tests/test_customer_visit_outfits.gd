extends SceneTree
const Base=preload("res://scripts/cafe_model.gd")
const Candidate=preload("res://scripts/customer_visit_outfits.gd")
const Presentation=preload("res://scripts/customer_visit_presentation.gd")
const Codec=preload("res://scripts/cafe_runtime_codec.gd")
var checks=0
var failures:Array=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label)
func encoded(value)->String:return JSON.stringify(Codec.new().encode(value),"",true)
func _initialize():
	var base=Base.new();base.reset_new()
	var candidate=Candidate.new();candidate.reset_new()
	base._spawn_customer();candidate._spawn_customer()
	check(encoded(base.customers)==encoded(candidate.customers),"real spawn unchanged")
	check(base._next_customer_id==candidate._next_customer_id,"allocator unchanged")
	check(not candidate.appearance_for(0).ok and not candidate.appearance_for(candidate._next_customer_id).ok,"invalid visit keeps presentation fallback")
	var selected:Dictionary={}
	for guest in candidate.customers:
		var result:Dictionary=candidate.appearance_for(int(guest.id))
		check(result.ok,"spawn visit resolves outfit")
		selected[int(guest.id)]=encoded(result.customer.appearance)
		check(result.customer.appearance.wardrobe.species=="bear","reviewed bear only")
		check(not Presentation.options(result.customer.appearance).is_empty(),"actual renderer options resolve")
		check(not guest.has("appearance"),"no guest schema injection")
		var owned=result.customer;owned.appearance.wardrobe.items.top="broken"
		check(encoded(candidate.appearance_for(int(guest.id)).customer.appearance)==selected[int(guest.id)],"caller cannot mutate selected outfit")
	check(base.save("user://visit-base.json") and candidate.save("user://visit-candidate.json"),"synthetic codec writes")
	check(FileAccess.get_file_as_string("user://visit-base.json")==FileAccess.get_file_as_string("user://visit-candidate.json"),"old save bytes remain identical")
	for cycle in range(3):
		var loaded=Candidate.new()
		check(loaded.load_save("user://visit-base.json"),"older save without outfit fields loads")
		check(loaded.customers.size()==candidate.customers.size(),"reload preserves visits")
		for guest in loaded.customers:
			check(encoded(loaded.appearance_for(int(guest.id)).customer.appearance)==selected[int(guest.id)],"supported reload reconstructs exact outfit")
	for i in range(10):
		base.tick(.1);candidate.tick(.1)
	check(encoded(base.customers)==encoded(candidate.customers),"movement unchanged")
	for id in selected:check(encoded(candidate.appearance_for(id).customer.appearance)==selected[id],"movement keeps outfit")
	candidate._outfit_cache.clear()
	for id in selected:check(encoded(candidate.appearance_for(id).customer.appearance)==selected[id],"cache regeneration cannot reroll")
	base._spawn_walkers(4);candidate._spawn_walkers(4)
	check(encoded(base.outside_queue)==encoded(candidate.outside_queue),"queue spawn unchanged")
	var combinations:Dictionary={}
	for guest in candidate.customers+candidate.outside_queue:
		var appearance:Dictionary=candidate.appearance_for(int(guest.id)).customer.appearance
		combinations[encoded(Presentation.options(appearance))]=true
	check(combinations.size()>1,"real active visits have distinct visible options")
	check(base.coins==candidate.coins and base.served==candidate.served,"economy untouched")
	check(Presentation.options({}).is_empty(),"invalid appearance rejected")
	print("CUSTOMER_VISIT_OUTFITS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"player_saves_used":false,"scope":"pinned visit recipe; no recurring identity or schema changes"}))
	quit(0 if failures.is_empty() else 1)
