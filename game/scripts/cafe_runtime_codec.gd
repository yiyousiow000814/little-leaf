extends RefCounted
## JSON-only finite snapshot codec. No resource paths, objects or executable data.
## Validation is completed before a saved runtime may replace the live model.
var error:=""
const SaveContract=preload("res://scripts/cafe_save_contract.gd")
const PlacementPause=preload("res://scripts/cafe_placement_pause.gd")
const CHECKOUT_STAGES=["checkout_wait","checkout_walk","paying"]
const NONE=Vector2i(-100,-100)
const PAYMENT_SECONDS=1.6
const FloorTasks=preload("res://scripts/cafe_floor_tasks.gd")
const Dishwashing=preload("res://scripts/cafe_dishwashing.gd")
const JOB_LENGTHS={"wash":1,"floor":4,"":1,"order":1,"cook":4,"brew":3,"deliver_meal":2,"deliver_drink":2,"cleanup":7,"take_payment":1}
const PLATE_OWNERS=["kitchen","station","staff","counter","table","sink","dish_queue","clean"]
const DRINK_OWNERS=["beverage","station","staff","table","cleared"]
# Staff ownership means litter is contained in the carried dustpan. Legacy
# hand-held litter uses the same owner/index and resumes without a reset.
const TRASH_OWNERS=["none","floor","staff","bin","disposed"]
func encode(value):
	if value is Vector2:return {"$vector2":[value.x,value.y]}
	if value is Vector2i:return {"$vector2i":[value.x,value.y]}
	if value is Array:
		var result=[]
		for item in value:result.append(encode(item))
		return result
	if value is Dictionary:
		var result={}
		for key in value:result[str(key)]=encode(value[key])
		return result
	return value
func decode(value,depth=0):
	if depth>10:error="Runtime nesting is too deep";return null
	if value==null or value is bool:return value
	if value is int or value is float:
		if not is_finite(float(value)):error="Non-finite runtime number";return null
		return value
	if value is String:
		if value.length()>1024:error="Runtime text too long";return null
		return value
	if value is Array:
		if value.size()>512:error="Runtime array too large";return null
		var result=[]
		for entry in value:
			result.append(decode(entry,depth+1))
			if error!="":return null
		return result
	if value is Dictionary:
		if value.size()>128:error="Runtime object too large";return null
		for tag in ["$vector2","$vector2i"]:
			if value.has(tag):
				var values=value[tag]
				if value.size()!=1 or not values is Array or values.size()!=2:error="Invalid runtime vector";return null
				for number in values:
					if not _number(number,-1000000,1000000):error="Invalid vector coordinate";return null
					if tag=="$vector2i" and floor(float(number))!=float(number):error="Non-integer cell";return null
				return Vector2i(int(values[0]),int(values[1])) if tag=="$vector2i" else Vector2(float(values[0]),float(values[1]))
		var result={}
		for key in value:
			if not key is String or key.length()>80:error="Invalid runtime key";return null
			result[key]=decode(value[key],depth+1)
			if error!="":return null
		return result
	error="Unsupported runtime value";return null
func _number(value,low:float,high:float)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
func _integer(value,low:int,high:int)->bool:
	return _number(value,low,high) and floor(float(value))==float(value)
# Finite right expansion reaches x=18; exterior arrival/exit lanes need a
# small bounded margin beyond that edge (furthest current arrival x=19.76).
func _point(value)->bool:
	return value is Vector2 and value.is_finite() and value.x>=-6 and value.x<=24 and value.y>=-6 and value.y<=28
func _street_point(value)->bool:
	return value is Vector2 and value.is_finite() and absf(value.x+2.76)<.00001 and value.y>=-82.0 and value.y<=82.0
func _street_path_valid(guest:Dictionary)->bool:
	var has_marker=guest.has("street_route_format") or guest.has("street_origin_z")
	if has_marker:
		if guest.get("street_route_format")!="little_leaf.street_endpoints.v1" or not _number(guest.get("street_origin_z"),-82,82) or absf(float(guest.street_origin_z))!=82.0:return false
	var extended_allowed=has_marker and (guest.phase=="arriving" or (guest.phase=="leaving" and bool(guest.get("withdrawn",false))))
	for index in range(guest.route.size()):
		var point=guest.route[index]
		if _point(point):continue
		if not has_marker or not _street_point(point) or signf(point.y)!=signf(float(guest.street_origin_z)):return false
		if not extended_allowed and index>=int(guest.route_index):return false
	# Rerouting may retain a consumed outer-lane waypoint after the guest is
	# seated. Validate that history as one contiguous same-end approach; it
	# grants no permission for an extended current or remaining service route.
	if has_marker:
		var history:Array=guest.route.duplicate()
		if guest.phase=="leaving" and bool(guest.get("withdrawn",false)):history.reverse()
		if not _street_prefix_valid(history,float(guest.street_origin_z)):return false
	var points=[Vector2(float(guest.x),float(guest.z))]
	points.append_array(guest.route.slice(int(guest.route_index)))
	if not extended_allowed:
		for point in points:
			if not _point(point):return false
		return true
	# An arriving path has one outer prefix. A withdrawn path has the same
	# single lane as its final suffix back to the original road end.
	if guest.phase=="leaving":points.reverse()
	return _street_prefix_valid(points,float(guest.street_origin_z))
func _street_prefix_valid(points:Array,origin:float)->bool:
	var entered_old_bounds=false
	var previous_extended=false
	for point in points:
		if _point(point):
			if previous_extended and absf(point.x+2.76)>.00001:return false
			entered_old_bounds=true;previous_extended=false;continue
		if entered_old_bounds or not _street_point(point) or signf(point.y)!=signf(origin):return false
		previous_extended=true
	return true
func _cell(value,allow_none=false)->bool:
	return value is Vector2i and ((allow_none and value==Vector2i(-100,-100)) or (value.x>=-6 and value.x<=24 and value.y>=-6 and value.y<=28))
func _fail(reason:String)->Dictionary:
	error=reason;return {"ok":false,"error":reason}
func _migrate_guest_egress(guest:Dictionary,chair:Dictionary) -> void:
	# Older snapshots already carry a continuous chair-to-aisle route. Infer
	# this first leg without moving the guest, resetting a meal or replaying pay.
	guest.dismounting=false;guest.egress_cell=Vector2i(-100,-100);guest.dismount_progress=0.0
	if str(guest.phase)!="leaving" or bool(guest.get("withdrawn",false)):return
	var center=Vector2(float(chair.x)+.5,float(chair.z)+.5)
	var position=Vector2(float(guest.x),float(guest.z))
	if guest.departure_blocked and guest.route.is_empty() and position.distance_to(center)<.0001:
		guest.dismounting=true;guest.seated=true;return
	if int(guest.route_index)!=0 or guest.route.is_empty():return
	var landing:Vector2=guest.route[0]
	var delta=landing-center
	if absf(absf(delta.x)+absf(delta.y)-1.0)>.0001 or minf(absf(delta.x),absf(delta.y))>.0001:return
	if position.distance_to(landing)<.0001 or absf(position.distance_to(center)+position.distance_to(landing)-1.0)>.0001:return
	guest.dismounting=true;guest.seated=true
	guest.egress_cell=Vector2i(floori(landing.x),floori(landing.y));guest.dismount_progress=position.distance_to(center)

func _register_front(item:Dictionary)->Vector2i:
	return Vector2i(int(item.x),int(item.z))+[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT][posmod(int(item.get("rot",0)),4)]

func _migrate_checkout(guest:Dictionary)->void:
	guest.settlement_mode="legacy";guest.checkout_ticket=0;guest.checkout_register_id=-1
	guest.checkout_cell=NONE;guest.checkout_token=-1;guest.checkout_reason="";guest.checkout_stall=0.0

func _checkout_guest_error(guest:Dictionary,item_map:Dictionary,source_version:int,next_ticket:int,historical_intent:bool=false)->String:
	if source_version<=SaveContract.LEGACY_MAX_VERSION:
		# A version number may not disguise a newer cashier state as legacy.
		if guest.phase in CHECKOUT_STAGES or guest.get("settlement_mode","legacy")!="legacy" or guest.get("checkout_ticket",0)!=0 or guest.get("checkout_register_id",-1)!=-1 or guest.get("checkout_token",-1)!=-1 or guest.get("checkout_cell",NONE)!=NONE:return "Legacy snapshot contains checkout state"
		_migrate_checkout(guest)
	for key in ["settlement_mode","checkout_ticket","checkout_register_id","checkout_cell","checkout_token","checkout_reason","checkout_stall"]:
		if not guest.has(key):return "Missing checkout field: "+key
	if guest.settlement_mode not in ["legacy","register"] or not _integer(guest.checkout_ticket,0,next_ticket-1) or not _integer(guest.checkout_register_id,-1,1000000000) or (not _integer(guest.checkout_token,-1,1000000000) or guest.checkout_token==0) or not _cell(guest.checkout_cell,true) or not guest.checkout_reason is String or not _number(guest.checkout_stall,0,3600):return "Invalid checkout state"
	if guest.settlement_mode=="legacy":
		if guest.phase in CHECKOUT_STAGES or int(guest.checkout_ticket)!=0 or int(guest.checkout_register_id)!=-1 or int(guest.checkout_token)!=-1 or guest.checkout_cell!=NONE:return "Legacy visit contains register settlement"
		return ""
	var checkout=guest.phase in CHECKOUT_STAGES
	var settled=guest.paid and guest.phase in ["leaving","dirty","cleaning"]
	if checkout and (guest.paid or guest.exterior_exit or bool(guest.get("withdrawn",false))):return "Checkout guest has already left or paid"
	if not guest.paid and guest.exterior_exit and not bool(guest.get("withdrawn",false)) and not bool(guest.get("meal_abandoned",false)):return "Unpaid register guest has an exterior exit"
	if checkout or settled:
		if int(guest.checkout_ticket)<1:return "Finished meal has no checkout ticket"
	else:
		if int(guest.checkout_ticket)!=0 or int(guest.checkout_register_id)!=-1 or guest.checkout_cell!=NONE or int(guest.checkout_token)!=-1:return "Unfinished meal already owns checkout"
		return ""
	if int(guest.checkout_register_id)!=-1:
		if not item_map.has(int(guest.checkout_register_id)) or item_map[int(guest.checkout_register_id)].kind!="register":return "Checkout references a missing register"
	elif guest.checkout_cell!=NONE or guest.phase in ["checkout_walk","paying"] or settled:return "Checkout claim has no register"
	if guest.checkout_cell!=NONE:
		var front=_register_front(item_map[int(guest.checkout_register_id)])
		var direction=front-Vector2i(int(item_map[int(guest.checkout_register_id)].x),int(item_map[int(guest.checkout_register_id)].z))
		var side=Vector2i(-direction.y,direction.x)
		if guest.checkout_cell not in [front,front+side,front-side]:return "Invalid register queue cell"
		if guest.checkout_cell.x<1 or guest.checkout_cell.y<0 or guest.checkout_cell.x>=18 or guest.checkout_cell.y>=18:return "Checkout claim is not indoor floor"
		if guest.checkout_cell in [Vector2i(0,5),Vector2i(1,5)]:return "Checkout claim occupies a door landing"
		for item in item_map.values():
			if not historical_intent and item.kind!="rug" and Vector2i(int(item.x),int(item.z))==guest.checkout_cell:return "Checkout claim is blocked by furniture"
	var position=Vector2(float(guest.x),float(guest.z))
	if guest.phase=="checkout_wait":
		if guest.seated:
			if guest.checkout_cell!=NONE or guest.dismounting:return "Seated overflow owns a walking claim"
			var chair=item_map[int(guest.chair_id)]
			if position.distance_to(Vector2(float(chair.x)+.5,float(chair.z)+.5))>.0001:return "Seated overflow moved off its chair"
		elif _mobility_kind(guest)=="to_assigned_seat":
			pass # Validated unclaimed overflow is walking back to its moved seat.
		elif guest.checkout_cell==NONE or (position.distance_to(Vector2(guest.checkout_cell)+Vector2(.5,.5))>.01 and _mobility_kind(guest)!="to_checkout"):return "Waiting guest is not at its checkout claim"
	if guest.phase=="checkout_walk":
		if guest.checkout_cell==NONE or bool(guest.seated)!=bool(guest.dismounting):return "Checkout movement lost its claim or chair departure"
		if guest.route.is_empty() or guest.route[-1].distance_to(Vector2(guest.checkout_cell)+Vector2(.5,.5))>.0001:return "Checkout route does not reach its claim"
	if guest.phase=="paying":
		if guest.seated or guest.dismounting or guest.checkout_cell!=_register_front(item_map[int(guest.checkout_register_id)]) or (position.distance_to(Vector2(guest.checkout_cell)+Vector2(.5,.5))>.01 and _mobility_kind(guest)!="to_checkout") or int(guest.checkout_token)<1:return "Payment guest is not at the register front"
	if settled and int(guest.checkout_token)<1:return "Paid register visit has no transaction token"
	if guest.phase in ["dirty","cleaning"] and guest.checkout_cell!=NONE:return "Exited visit retains a checkout claim"
	if not settled and guest.phase!="paying" and guest.phase!="checkout_wait" and int(guest.checkout_token)!=-1:return "Checkout token exists before payment assignment"
	return ""

func _checkout_queue_error(guests:Dictionary,item_map:Dictionary)->String:
	var tickets={};var claims={};var optional_claims={};var queue=[]
	for guest in guests.values():
		var ticket=int(guest.checkout_ticket)
		if ticket>0:
			if tickets.has(ticket):return "Duplicate checkout ticket"
			tickets[ticket]=int(guest.id)
		if guest.checkout_cell!=NONE and not PlacementPause.blocked(guest):
			if claims.has(guest.checkout_cell):return "Two visits own one checkout cell"
			claims[guest.checkout_cell]=int(guest.id)
			var register_id=int(guest.checkout_register_id)
			if guest.checkout_cell!=_register_front(item_map[register_id]):
				if optional_claims.has(register_id):return "Register has more than one optional queue claim"
				optional_claims[register_id]=true
		if guest.phase in CHECKOUT_STAGES:queue.append(guest)
	queue.sort_custom(func(a,b):return int(a.checkout_ticket)<int(b.checkout_ticket))
	for index in range(queue.size()):
		var guest=queue[index]
		if guest.phase=="paying" and index!=0:return "Payment guest is not FIFO head"
		if guest.checkout_cell!=NONE:
			if index>1:return "Overflow guest owns a physical queue cell"
			if guest.checkout_cell==_register_front(item_map[int(guest.checkout_register_id)]) and index!=0:return "Register front is not owned by FIFO head"
	return ""

func _mobility_kind(guest:Dictionary)->String:
	var mobility=guest.get("mobility",{})
	return str(mobility.get("goal","")) if mobility is Dictionary and mobility.get("kind")=="blocked" else (str(mobility.get("kind","")) if mobility is Dictionary else "")

func _blocked_guest_error(guest:Dictionary,item_map:Dictionary)->String:
	var motion:Dictionary=guest.mobility
	if motion.size()!=6:return "Invalid pending placement fields"
	for key in ["kind","format","goal","position","anchors","previous"]:
		if not motion.has(key):return "Missing pending placement field"
	for key in ["table_id","chair_id","phase","x","z","route","route_index","checkout_register_id"]:
		if not guest.has(key):return "Incomplete pending guest"
	if motion.format!=SaveContract.FOOTPRINT_PLACEMENT_FORMAT or motion.goal not in ["to_assigned_seat","to_checkout","resume_walk"] or (not _point(motion.position) and not _street_point(motion.position)):return "Invalid pending placement capability"
	if not _number(guest.x,-6,24) or not _number(guest.z,-82,82) or motion.position.distance_to(Vector2(float(guest.x),float(guest.z)))>.00001:return "Pending guest changed its frozen position"
	if not motion.previous is Dictionary or motion.previous.get("kind","") not in ["","to_assigned_seat","to_checkout"]:return "Recursive or unknown pending history"
	var goal=str(motion.previous.get("kind",""))
	if goal=="":goal="resume_walk" if guest.phase in ["arriving","leaving","checkout_walk"] else ("to_checkout" if guest.get("checkout_cell",NONE)!=NONE else "to_assigned_seat")
	if goal!=motion.goal or guest.phase in ["dirty","cleaning"]:return "Pending goal contradicts its authoritative phase"
	var required={}
	for id in [guest.table_id,guest.chair_id,guest.checkout_register_id]:
		if not _integer(id,-1,1000000000):return "Invalid pending reference"
		if int(id)>=0:required[int(id)]=true
	if not motion.anchors is Array or motion.anchors.size()!=required.size() or motion.anchors.size()>3:return "Invalid pending anchor count"
	var seen={}
	for anchor in motion.anchors:
		if not anchor is Dictionary or anchor.size()!=5:return "Invalid historical anchor fields"
		for key in ["id","kind","x","z","rot"]:
			if not anchor.has(key):return "Missing historical anchor field"
		if not _integer(anchor.id,1,1000000000) or not required.has(int(anchor.id)) or seen.has(int(anchor.id)) or not item_map.has(int(anchor.id)):return "Duplicate or foreign historical anchor"
		if anchor.kind!=item_map[int(anchor.id)].kind or not _integer(anchor.x,0,17) or not _integer(anchor.z,0,17) or not _integer(anchor.rot,0,3):return "Contradictory historical anchor"
		seen[int(anchor.id)]=true
	var old_items=PlacementPause.historical_items(guest,item_map)
	var old_table=old_items[int(guest.table_id)];var old_chair=old_items[int(guest.chair_id)]
	if absi(int(old_table.x)-int(old_chair.x))+absi(int(old_table.z)-int(old_chair.z))!=1:return "Historical dining anchors disagree with their reserved pair"
	if bool(guest.get("seated",false)) and not bool(guest.get("dismounting",false)):
		var chair=old_items[int(guest.chair_id)]
		if motion.position.distance_to(Vector2(float(chair.x)+.5,float(chair.z)+.5))>.0001:return "Pending seated body left its historical chair"
	if motion.previous.is_empty() and guest.phase in ["arriving","leaving","checkout_walk"]:
		if not guest.route is Array or guest.route.size()>512 or not _integer(guest.route_index,0,guest.route.size()):return "Invalid historical route index"
		var previous:Vector2
		for index in guest.route.size():
			var at=guest.route[index]
			if not _point(at) and not _street_point(at):return "Invalid historical route point"
			if index>0 and absf(previous.x-at.x)>.0001 and absf(previous.y-at.y)>.0001:return "Historical route is not cardinal"
			previous=at
		if not guest.route.is_empty():
			var index=int(guest.route_index)
			if index==guest.route.size():
				if motion.position.distance_to(guest.route[-1])>.0001:return "Historical route completion moved its body"
			else:
				var start:Vector2=guest.route[index-1] if index>0 else motion.position
				var finish:Vector2=guest.route[index]
				if Geometry2D.get_closest_point_to_segment(motion.position,start,finish).distance_to(motion.position)>.0001 or (absf(start.x-finish.x)>.0001 and absf(start.y-finish.y)>.0001):return "Historical body is off its cardinal segment"
	return ""

func _mobility_guest_error(guest:Dictionary,item_map:Dictionary)->String:
	if not guest.get("mobility") is Dictionary:return "Missing or invalid guest mobility"
	var mobility:Dictionary=guest.mobility
	if mobility.is_empty():return ""
	if mobility.size()!=4 or not mobility.has("kind") or not mobility.has("origin") or not mobility.has("route") or not mobility.has("route_index"):return "Invalid layout motion fields"
	if mobility.kind not in ["to_assigned_seat","to_checkout"]:return "Invalid layout motion kind"
	if not _point(mobility.origin) or not mobility.route is Array or mobility.route.is_empty() or mobility.route.size()>512 or not _integer(mobility.route_index,0,mobility.route.size()-1):return "Invalid layout motion route"
	if guest.paid or bool(guest.get("withdrawn",false)) or guest.exterior_exit or guest.seated or guest.dismounting or not guest.route.is_empty() or int(guest.route_index)!=0:return "Layout motion conflicts with guest state"
	var target:Vector2
	if mobility.kind=="to_assigned_seat":
		if guest.phase not in ["ordering","cooking","drinking","eating","checkout_wait"]:return "Seat motion conflicts with meal phase"
		if guest.phase=="checkout_wait" and (guest.get("checkout_cell")!=NONE or guest.get("checkout_token")!=-1):return "Seat motion checkout guest owns a claim or token"
		var chair:Dictionary=item_map[int(guest.chair_id)]
		target=Vector2(float(chair.x)+.5,float(chair.z)+.5)
	else:
		if guest.phase not in ["checkout_wait","paying"] or not _cell(guest.get("checkout_cell")) or guest.get("checkout_cell")==NONE:return "Checkout motion has no valid claim or phase"
		target=Vector2(guest.checkout_cell)+Vector2(.5,.5)
	var previous:Vector2=mobility.origin
	for point in mobility.route:
		if not _point(point):return "Invalid layout motion route point"
		var delta:Vector2=point-previous
		if delta.length()<=.0001 or (absf(delta.x)>.0001 and absf(delta.y)>.0001):return "Layout motion route is not cardinal"
		previous=point
	if previous.distance_to(target)>.0001:return "Layout motion route misses its current target"
	var index=int(mobility.route_index)
	var start:Vector2=mobility.origin if index==0 else mobility.route[index-1]
	var finish:Vector2=mobility.route[index]
	var position=Vector2(float(guest.x),float(guest.z))
	var on_segment:bool
	if absf(start.x-finish.x)<=.0001:
		on_segment=absf(position.x-start.x)<=.0001 and position.y>=minf(start.y,finish.y)-.0001 and position.y<=maxf(start.y,finish.y)+.0001
	else:
		on_segment=absf(position.y-start.y)<=.0001 and position.x>=minf(start.x,finish.x)-.0001 and position.x<=maxf(start.x,finish.x)+.0001
	if not on_segment:return "Layout motion position is off its active segment"
	return ""

func _validated_state(state:Dictionary,source_version:int)->Dictionary:
	# Do not weaken or mutate a legacy snapshot before its original validation.
	if not SaveContract.has_layout_motion(source_version):
		for guest in state.customers:guest.mobility={}
		state.layout_motion_format=SaveContract.LAYOUT_MOTION_FORMAT
	else:
		for guest in state.customers:
			if PlacementPause.blocked(guest):
				for anchor in guest.mobility.anchors:
					for key in ["id","x","z","rot"]:anchor[key]=int(anchor[key])
				if not guest.mobility.previous.is_empty():guest.mobility.previous.route_index=int(guest.mobility.previous.route_index)
			elif not guest.mobility.is_empty():guest.mobility.route_index=int(guest.mobility.route_index)
	return {"ok":true,"state":state}

func validate(raw,items:Array,cooks:int,phases:Array,source_version:int=10,staffing:Dictionary={},duty:Dictionary={},allow_footprint_placement:bool=false)->Dictionary:
	error=""
	var state=decode(raw)
	if error!="":return _fail(error)
	if not state is Dictionary:return _fail("Missing runtime snapshot")
	if not SaveContract.accepts_version(source_version,allow_footprint_placement):return _fail("Unsupported runtime source version")
	if state.has("navigation_format") or state.has("footprint_placement_format"):return _fail("Foreign runtime capability marker")
	if state.get("service") is Dictionary:
		for staff in state.service.get("staff",[]):
			if staff is Dictionary and staff.has("navigation_phase"):return _fail("Placement runtime contains navigation state")
	if SaveContract.has_layout_motion(source_version):
		if state.get("layout_motion_format")!=SaveContract.LAYOUT_MOTION_FORMAT:return _fail("Invalid layout motion runtime format")
	elif state.has("layout_motion_format"):return _fail("Legacy runtime contains layout motion format")
	if SaveContract.has_checkout(source_version):
		if state.get("checkout_format")!=SaveContract.CHECKOUT_FORMAT or not _integer(state.get("next_checkout_ticket"),1,1000000001):return _fail("Invalid cashier runtime format or ticket sequence")
	else:
		if state.has("checkout_format") and state.checkout_format!=SaveContract.CHECKOUT_FORMAT:return _fail("Foreign legacy checkout marker")
		state.checkout_format=SaveContract.CHECKOUT_FORMAT;state.next_checkout_ticket=1
	for key in ["customers","service","next_customer_id","arrival_elapsed","walking_customer_id"]:
		if not state.has(key):return _fail("Missing runtime field: "+key)
	if not state.customers is Array or state.customers.size()>60:return _fail("Invalid saved customers")
	if not _integer(state.next_customer_id,1,1000000001) or not _integer(state.walking_customer_id,-1,1000000000) or not _number(state.arrival_elapsed,0,4.00001):return _fail("Invalid customer sequence or arrival clock")
	var item_map={}
	for item in items:item_map[int(item.id)]=item
	var guests={};var tables={};var seats={}
	for guest in state.customers:
		if not guest is Dictionary:return _fail("Invalid saved customer entry")
		var live_guest:Dictionary=guest
		var guest_items=item_map
		var historical_intent=PlacementPause.blocked(guest)
		if historical_intent:
			if source_version!=SaveContract.FOOTPRINT_PLACEMENT_VERSION:return _fail("Blocked guest needs the explicit placement version")
			var pending_error=_blocked_guest_error(guest,item_map)
			if pending_error!="":return _fail(pending_error)
			guest_items=PlacementPause.historical_items(guest,item_map)
			guest=PlacementPause.historical_guest(guest)
		if not SaveContract.has_layout_motion(source_version) and guest.has("mobility"):return _fail("Legacy guest contains layout motion state")
		for key in ["id","table_id","chair_id","phase","elapsed","duration","x","z","paid","seated","route","route_index","heading","service_cell","waiting","exterior_exit","entry_cell","entry_direction","entry_outside","departure_blocked","table_service_direction"]:
			if not guest.has(key):return _fail("Missing customer field: "+key)
		if not _integer(guest.id,1,int(state.next_customer_id)-1) or guests.has(int(guest.id)):return _fail("Invalid or duplicate saved guest identity")
		if not _integer(guest.table_id,1,1000000000) or not _integer(guest.chair_id,1,1000000000):return _fail("Invalid guest furnishing identity")
		if not guest_items.has(int(guest.table_id)) or guest_items[int(guest.table_id)].kind!="table" or not guest_items.has(int(guest.chair_id)) or guest_items[int(guest.chair_id)].kind not in ["chair","bench"]:return _fail("Guest references a missing table or seat")
		if not guest.phase is String or not phases.has(guest.phase):return _fail("Invalid customer phase")
		if not _number(guest.x,-6,24) or not _number(guest.z,-82,82) or not _number(guest.elapsed,0,1000000) or not _number(guest.duration,0,1000000):return _fail("Invalid guest position or clock")
		for key in ["paid","seated","waiting","exterior_exit","departure_blocked"]:
			if not guest[key] is bool:return _fail("Invalid guest flag: "+key)
		for key in ["admitted","withdrawn","exit_completed","meal_abandoned"]:
			if guest.has(key) and not guest[key] is bool:return _fail("Invalid operating guest flag")
		var withdrawn=bool(guest.get("withdrawn",false))
		if not guest.has("meal_abandoned"):guest.meal_abandoned=false
		var abandoned=bool(guest.meal_abandoned)
		if abandoned:
			if not state.service is Dictionary or not _integer(state.service.get("version"),SaveContract.MEAL_DEPARTURE_SERVICE_VERSION,SaveContract.SERVICE_VERSION):return _fail("Unserved meal departure needs its service format")
			var moving_to_seat=guest.phase in ["ordering","cooking"] and _mobility_kind(guest)=="to_assigned_seat"
			if guest.paid or withdrawn or (guest.phase not in ["leaving","dirty","cleaning"] and not moving_to_seat):return _fail("Invalid abandoned meal state")
		if withdrawn and (guest.phase!="leaving" or guest.paid or guest.seated):return _fail("Invalid unserved departure")
		if not withdrawn:
			if tables.has(int(guest.table_id)) or seats.has(int(guest.chair_id)):return _fail("Two guests reserve the same dining pair")
			tables[int(guest.table_id)]=true;seats[int(guest.chair_id)]=true
			if bool(guest.paid)!=(str(guest.phase) in ["leaving","dirty","cleaning"] and not abandoned):return _fail("Payment disagrees with meal phase")
		if not _point(guest.heading) or not _cell(guest.entry_outside):return _fail("Invalid guest direction")
		for key in ["service_cell","entry_cell","entry_direction","table_service_direction"]:
			if not _cell(guest[key]):return _fail("Invalid guest cell field: "+key)
		if not guest.route is Array or guest.route.size()>512 or not _integer(guest.route_index,0,guest.route.size()):return _fail("Invalid guest route index")
		for point in guest.route:
			if not _point(point) and not _street_point(point):return _fail("Invalid saved route point")
		if not _street_path_valid(guest):return _fail("Invalid street endpoint route")
		var egress_fields=0
		for key in ["dismounting","egress_cell","dismount_progress"]:
			if guest.has(key):egress_fields+=1
		if egress_fields==0 and source_version<11:_migrate_guest_egress(guest,guest_items[int(guest.chair_id)])
		elif egress_fields!=3:return _fail("Incomplete chair departure state")
		if not guest.dismounting is bool or not _cell(guest.egress_cell,true) or not _number(guest.dismount_progress,0,1):return _fail("Invalid chair departure state")
		if guest.dismounting:
			var paid_departure=guest.phase=="leaving" and (guest.paid or abandoned)
			var unpaid_checkout=SaveContract.has_checkout(source_version) and guest.phase=="checkout_walk" and not guest.paid and guest.get("settlement_mode")=="register"
			if not (paid_departure or unpaid_checkout) or withdrawn or not guest.seated or guest.exterior_exit or int(guest.route_index)!=0:return _fail("Chair departure disagrees with guest phase")
			var chair=guest_items[int(guest.chair_id)];var table=guest_items[int(guest.table_id)]
			var seat_cell=Vector2i(int(chair.x),int(chair.z));var center=Vector2(seat_cell)+Vector2(.5,.5)
			var position=Vector2(float(guest.x),float(guest.z))
			if guest.departure_blocked:
				if guest.egress_cell!=Vector2i(-100,-100) or not guest.route.is_empty() or position.distance_to(center)>.0001 or float(guest.dismount_progress)>.0001:return _fail("Blocked chair departure moved off its seat")
			else:
				var delta=guest.egress_cell-seat_cell
				if absi(delta.x)+absi(delta.y)!=1 or guest.egress_cell==Vector2i(int(table.x),int(table.z)):return _fail("Chair exit must be left, right or back")
				for item in items:
					if not historical_intent and str(item.kind)!="rug" and guest.egress_cell==Vector2i(int(item.x),int(item.z)):return _fail("Chair exit is blocked by furniture")
				var landing=Vector2(guest.egress_cell)+Vector2(.5,.5)
				if guest.route.is_empty() or guest.route[0].distance_to(landing)>.0001:return _fail("Chair departure lost its reserved landing")
				if absf(position.distance_to(center)+position.distance_to(landing)-1.0)>.0001 or absf(float(guest.dismount_progress)-position.distance_to(center))>.0001:return _fail("Chair departure position disagrees with progress")
		elif guest.phase=="leaving" and guest.seated:return _fail("Leaving guest is seated without a chair departure")
		if source_version==SaveContract.FOOTPRINT_PLACEMENT_VERSION and not historical_intent and guest.seated and not guest.dismounting:
			var current_chair=guest_items[int(guest.chair_id)]
			if Vector2(float(guest.x),float(guest.z)).distance_to(Vector2(float(current_chair.x)+.5,float(current_chair.z)+.5))>.0001:return _fail("Current seated body disagrees with its chair")
		if SaveContract.has_layout_motion(source_version):
			var mobility_error=_mobility_guest_error(guest,guest_items)
			if mobility_error!="":return _fail(mobility_error)
		var checkout_error=_checkout_guest_error(guest,guest_items,source_version,int(state.next_checkout_ticket),historical_intent)
		if checkout_error!="":return _fail(checkout_error)
		guests[int(guest.id)]=live_guest
	if int(state.walking_customer_id)!=-1 and not guests.has(int(state.walking_customer_id)):return _fail("Walking owner is not present")
	var queue_error=_checkout_queue_error(guests,item_map)
	if queue_error!="":return _fail(queue_error)
	if int(state.walking_customer_id)!=-1:
		var walker=guests[int(state.walking_customer_id)]
		if walker.phase in ["checkout_wait","paying"]:return _fail("Stationary checkout guest owns the walking slot")
	var expected_cashiers=int(staffing.get("cashier",0))
	if expected_cashiers not in [0,1] or (source_version<=SaveContract.LEGACY_MAX_VERSION and expected_cashiers!=0):return _fail("Invalid cashier staffing for source version")
	if source_version<=SaveContract.LEGACY_MAX_VERSION:
		for item in items:
			if item.kind=="register":return _fail("Legacy snapshot contains a register")
	var expected_waiters=int(staffing.get("waiter",2 if source_version<9 else 1));var expected_cleaners=int(staffing.get("cleaner",1));var expected_total=cooks+expected_waiters+expected_cleaners+expected_cashiers
	var service=state.service
	if not service is Dictionary:return _fail("Invalid service snapshot")
	# Empty service is a supported standalone-model save. The running game
	# always supplies the full ledger below before saving active jobs.
	if service.is_empty():return _validated_state(state,source_version)
	if SaveContract.has_checkout(source_version):
		if not _integer(service.get("version"),SaveContract.LEGACY_SERVICE_VERSION,SaveContract.SERVICE_VERSION) or service.get("checkout_format")!=SaveContract.CHECKOUT_FORMAT:return _fail("Invalid cashier service format")
	elif not _integer(service.get("version"),1,2):return _fail("Legacy save contains a newer service format")
	if not _integer(service.get("serial"),0,1000000000) or not _number(service.get("animation_time"),0,1000000000):return _fail("Invalid service version or clock")
	if not service.get("records") is Array or service.records.size()!=guests.size() or not service.get("staff") is Array or service.staff.size() not in [0,expected_total]:return _fail("Invalid service record/staff count")
	if not guests.is_empty() and service.staff.size()!=expected_total:return _fail("Active service is missing its staff")
	if source_version<6:
		for staff in service.staff:
			if staff is Dictionary and staff.get("role")=="barista":staff.role="waiter"
	var floor_checked=FloorTasks.validate_snapshot(service.get("floor_tasks",{"next_id":1,"completed":0,"messes":[],"walks":[]}),service.staff,item_map,guests,self)
	if not floor_checked.ok:return _fail(floor_checked.error)
	var records={};var roles={};var tokens={};var counter_slots={}
	for record in service.records:
		if not record is Dictionary or not _integer(record.get("guest_id"),1,1000000000) or not guests.has(int(record.guest_id)) or records.has(int(record.guest_id)):return _fail("Invalid service guest identity")
		if not _integer(record.get("token"),1,int(service.serial)) or tokens.has(int(record.token)):return _fail("Invalid service token")
		tokens[int(record.token)]=true
		# Missing legacy metadata receives a fresh grace period;
		# phase elapsed is clamped by service and cannot reconstruct meal waiting.
		if not record.has("meal_wait_seconds"):record.meal_wait_seconds=0.0
		if not _number(record.meal_wait_seconds,0,1000000000):return _fail("Invalid seated meal wait clock")
		if bool(guests[int(record.guest_id)].meal_abandoned):
			if float(record.meal_wait_seconds)<120.0 or record.get("meal_ready")!=false or record.get("meal_done")!=false or record.get("pass_reserved")!=false:return _fail("Abandoned meal retains prepared food or invalid deadline")
			if record.get("plate_owner") not in ["clean","staff","dish_queue"] or record.get("drink_owner") not in ["table","cleared"]:return _fail("Abandoned meal retains unfinished service payload")
			if record.get("meal_station_id")!=-1 or record.get("meal_pass_id")!=-1 or record.get("drink_station_id")!=-1:return _fail("Abandoned meal retains a service station")
		for key in ["order_done","meal_ready","drink_ready","floor_cleaned","floor_dirty","meal_done","drink_done","dishes_collected","table_wiped","cleanup_done","pass_reserved","floor_spill","spill_cleaned"]:
			if not record.get(key) is bool:return _fail("Invalid service flag: "+key)
		if not PLATE_OWNERS.has(record.get("plate_owner")) or not DRINK_OWNERS.has(record.get("drink_owner")) or not TRASH_OWNERS.has(record.get("trash_owner")):return _fail("Invalid payload owner")
		if record.get("floor_debris") not in ["none","banana","crumbs"] or not _number(record.get("spill_remaining"),0,1):return _fail("Invalid floor mess")
		for key in ["floor_target","debris_target","spill_target"]:
			if not _point(record.get(key)):return _fail("Invalid floor target")
		if not record.has("floor_cell"):
			# Preserve an earlier in-flight save's physical mess location.
			record.floor_cell=Vector2i(floori(record.floor_target.x),floori(record.floor_target.y))
		if not _cell(record.floor_cell):return _fail("Invalid floor cleanup cell")
		var floor_geometry_error=FloorTasks.validate_geometry(record,self)
		if floor_geometry_error!="":return _fail(floor_geometry_error)
		for key in ["plate_staff_index","drink_staff_index","trash_staff_index"]:
			if not _integer(record.get(key),-1,service.staff.size()-1):return _fail("Invalid payload staff index")
		for key in ["meal_station_id","meal_pass_id","drink_station_id","plate_target_id","drink_target_id","trash_target_id"]:
			if not _integer(record.get(key),-1,1000000000) or (int(record[key])!=-1 and not item_map.has(int(record[key]))):return _fail("Payload references missing furniture")
		for prefix in ["plate","drink","trash"]:
			if record[prefix+"_owner"]=="staff" and int(record[prefix+"_staff_index"])<0:return _fail("Held payload has no hand owner")
		for prefix in ["plate","drink","trash"]:
			var owner=str(record[prefix+"_owner"])
			var hand=int(record[prefix+"_staff_index"])
			var target=int(record[prefix+"_target_id"])
			if owner!="staff" and hand!=-1:return _fail("Unheld payload retains a hand owner")
			if owner=="staff":
				if hand<0 or hand>=service.staff.size() or not service.staff[hand] is Dictionary:return _fail("Payload hand is absent")
				var holder=service.staff[hand]
				if holder.get("job_kind")=="floor":return _fail("Floor worker cannot own a guest payload")
				if int(holder.get("job_guest_id",-1))!=int(record.guest_id):return _fail("Held payload belongs to another guest job")
				if prefix=="drink" and holder.get("role")!="waiter":return _fail("Drink is in the wrong staff role")
				if prefix=="trash" and holder.get("role")!="cleaner":return _fail("Garbage is in the wrong staff role")
			if owner in ["table","counter","sink","bin","station"]:
				if target<0 or not item_map.has(target):return _fail("Placed payload has no furnishing")
				var wanted="beverage" if owner=="station" and prefix=="drink" else ("stove" if owner=="station" else owner)
				if str(item_map[target].kind)!=wanted:return _fail("Payload is on the wrong furnishing type")
				if owner=="table" and target!=int(guests[int(record.guest_id)].table_id):return _fail("Payload is on another guest table")
		if record.pass_reserved and (int(record.meal_pass_id)<0 or item_map[int(record.meal_pass_id)].kind!="counter"):return _fail("Pass reservation has no counter")
		if record.floor_debris=="none" and record.trash_owner!="none":return _fail("Garbage owner exists without debris")
		if record.spill_cleaned and float(record.spill_remaining)>.000001:return _fail("Clean floor retains spill amount")
		if record.cleanup_done and (record.plate_owner not in ["clean","dish_queue"] or record.drink_owner!="cleared" or not record.table_wiped or record.trash_owner not in ["none","disposed"] or not record.spill_cleaned or not record.floor_cleaned or record.floor_dirty):return _fail("Completed cleanup retains unfinished work")
		if record.plate_owner=="counter":
			var slot=int(record.plate_target_id)
			if slot<0 or item_map[slot].kind!="counter" or counter_slots.has(slot):return _fail("Invalid or duplicated pass-counter plate")
			counter_slots[slot]=true
		records[int(record.guest_id)]=record
	if int(service.version)>=4 and not service.has("dishwashing"):return _fail("Missing dishwashing ledger")
	if int(service.version)<4 and service.has("dishwashing"):return _fail("Legacy service contains newer dishwashing state")
	var dish_checked=Dishwashing.validate_snapshot(service.get("dishwashing",{"format":Dishwashing.FORMAT,"next_id":1,"completed":0,"dishes":[]}),service.staff,records,item_map,self)
	if not dish_checked.ok:return _fail(dish_checked.error)
	var duty_actual={"chef":0,"waiter":0,"cleaner":0,"cashier":0}
	var payment_claims={};var register_jobs={}
	var floor_job_claims={}
	for staff in service.staff:
		if not staff is Dictionary or staff.get("role") not in (["chef","waiter","cleaner","cashier"] if SaveContract.has_checkout(source_version) else ["chef","waiter","cleaner"]):return _fail("Invalid staff role")
		roles[staff.role]=int(roles.get(staff.role,0))+1
		if source_version>=10:
			if not staff.get("on_duty") is bool or not staff.get("duty_pending") is bool:return _fail("Invalid worker shift state")
			if not staff.on_duty and (staff.job_kind!="" or staff.duty_pending):return _fail("Off-duty worker retains active work")
			if staff.on_duty:duty_actual[staff.role]+=1
		else:staff.on_duty=true;staff.duty_pending=false;duty_actual[staff.role]+=1
		if not _point(staff.get("pos")) or not _cell(staff.get("destination"),true) or not staff.get("path") is Array or staff.path.size()>512 or not _integer(staff.get("index"),0,staff.path.size()):return _fail("Invalid staff position or route")
		for cell in staff.path:
			if not _cell(cell):return _fail("Invalid staff path cell")
		if not JOB_LENGTHS.has(staff.get("job_kind")) or not _integer(staff.get("job_step"),0,int(JOB_LENGTHS[staff.job_kind])-1) or not _number(staff.get("job_elapsed"),0,3600):return _fail("Invalid saved work stage")
		if str(staff.job_kind) not in {"chef":["","cook"],"waiter":["","order","brew","deliver_meal","deliver_drink","cleanup"],"cleaner":["","cleanup","floor","wash"],"cashier":["","take_payment"]}[staff.role]:return _fail("Work does not match staff role")
		if staff.has("table_face_id") and (not _integer(staff.table_face_id,-1,1000000000) or (int(staff.table_face_id)!=-1 and (not item_map.has(int(staff.table_face_id)) or item_map[int(staff.table_face_id)].kind!="table"))):return _fail("Invalid reserved table face")
		if staff.has("table_face_cell") and not _cell(staff.table_face_cell):return _fail("Invalid table face cell")
		if not _integer(staff.get("station_id"),-1,1000000000) or (int(staff.station_id)!=-1 and not item_map.has(int(staff.station_id))):return _fail("Missing saved work station")
		for key in ["yield_time","blocked_time","stalled_time"]:
			if not _number(staff.get(key,0.0),0,1000000):return _fail("Invalid staff delay")
		if not _integer(staff.get("job_guest_id"),-1,1000000000) or not _integer(staff.get("job_token"),-1,1000000000):return _fail("Invalid saved job ownership")
		if staff.job_kind=="floor":
			if int(staff.job_guest_id)!=-1:return _fail("Floor job cannot reference a guest")
			if not _integer(staff.get("job_mess_id"),1,1000000000) or not floor_checked.records.has(int(staff.job_mess_id)) or int(staff.job_token)!=int(floor_checked.records[int(staff.job_mess_id)].token):return _fail("Floor job token mismatch")
			if floor_job_claims.has(int(staff.job_mess_id)):return _fail("Two workers own the same floor job")
			floor_job_claims[int(staff.job_mess_id)]=true
		elif staff.job_kind not in ["","wash"] and (not records.has(int(staff.job_guest_id)) or int(staff.job_token)!=int(records[int(staff.job_guest_id)].token)):return _fail("Job token does not match guest")
		if guests.has(int(staff.job_guest_id)) and bool(guests[int(staff.job_guest_id)].meal_abandoned) and staff.job_kind not in ["","cleanup"]:return _fail("Abandoned meal retains an active service job")
		if staff.job_kind=="take_payment":
			var id=int(staff.job_guest_id);var guest=guests[id];var record=records[id];var register_id=int(staff.station_id)
			if not _number(staff.job_elapsed,0,PAYMENT_SECONDS) or not item_map.has(register_id) or item_map[register_id].kind!="register" or register_id!=int(guest.checkout_register_id):return _fail("Invalid cashier station or payment progress")
			if guest.phase not in ["checkout_wait","paying"] or guest.paid or guest.seated or guest.checkout_cell!=_register_front(PlacementPause.historical_items(guest,item_map)[register_id]) or (Vector2(float(guest.x),float(guest.z)).distance_to(Vector2(guest.checkout_cell)+Vector2(.5,.5))>.01 and _mobility_kind(guest)!="to_checkout"):return _fail("Cashier job guest is not at the register front")
			if int(guest.checkout_token)!=int(record.token):return _fail("Checkout token does not match service record")
			if payment_claims.has(id) or register_jobs.has(register_id):return _fail("Duplicate cashier payment job")
			payment_claims[id]=true;register_jobs[register_id]=true
			for other in guests.values():
				if other.phase in CHECKOUT_STAGES and int(other.checkout_ticket)<int(guest.checkout_ticket):return _fail("Cashier job is not for FIFO head")
			if float(staff.job_elapsed)>0 and guest.phase!="paying":return _fail("Payment clock advanced before payment began")
	for guest in guests.values():
		if guest.phase=="paying" and not payment_claims.has(int(guest.id)):return _fail("Paying guest has no cashier job")
		if guest.phase in CHECKOUT_STAGES:
			var record=records[int(guest.id)]
			if not record.meal_done or not record.drink_done or record.plate_owner!="table" or record.drink_owner!="table" or record.dishes_collected or record.cleanup_done:return _fail("Checkout visit lost its unfinished table cleanup")
			if int(guest.checkout_token)!=-1 and not payment_claims.has(int(guest.id)):return _fail("Checkout token has no cashier job")
		for staff in service.staff:
			if staff.job_kind=="cleanup" and int(staff.job_guest_id)==int(guest.id) and guest.phase in CHECKOUT_STAGES:return _fail("Checkout visit has premature cleanup")
	if source_version>=8:
		for record in records.values():
			if record.plate_owner=="staff":
				var holder=service.staff[int(record.plate_staff_index)]
				if holder.job_kind=="cleanup" and int(holder.job_step) not in [0,1]:return _fail("Dirty dishes held during a non-dish task")
			if record.trash_owner=="staff":
				var holder=service.staff[int(record.trash_staff_index)]
				if holder.job_kind=="cleanup" and int(holder.job_step) not in [3,4,5]:return _fail("Rubbish held during an incompatible task")
	if source_version<8:
		var cleanup_step_map=[0,2,6,1,3,4,5]
		for staff in service.staff:
			if staff.job_kind=="cleanup":staff.job_step=cleanup_step_map[int(staff.job_step)]
	# Cleaner table stages remain readable solely for in-flight legacy work.
	# Runtime preparation releases unstarted work without changing identities.
	for staff in service.staff:
		if staff.role=="waiter" and staff.job_kind=="cleanup" and int(staff.job_step)>=3:return _fail("Waiter cannot own floor cleanup")
	if not service.staff.is_empty() and (int(roles.get("chef",0))!=cooks or int(roles.get("waiter",0))!=expected_waiters or int(roles.get("cleaner",0))!=expected_cleaners or int(roles.get("cashier",0))!=expected_cashiers):return _fail("Saved staff roles disagree with staffing")
	if source_version>=10 and not service.staff.is_empty() and not duty.is_empty():
		for role in duty_actual:
			if int(duty_actual[role])!=int(duty.get(role,0 if role=="cashier" and source_version<=SaveContract.LEGACY_MAX_VERSION else -1)):return _fail("Payroll disagrees with active shifts")
	if int(service.version)<4:Dishwashing.migrate_snapshot(service)
	service.version=SaveContract.SERVICE_VERSION;service.checkout_format=SaveContract.CHECKOUT_FORMAT
	return _validated_state(state,source_version)
