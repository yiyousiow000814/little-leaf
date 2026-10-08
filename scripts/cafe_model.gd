class_name CafeModel
extends RefCounted
## Independent, deterministic Little Leaf Cafe simulation.
## This is a reconstructed NEW game, not a converter for any previous game's save.
## Mutations return false and populate last_error without charging on failure.
## Call tick(delta) only in play mode; the view owns editing and pause controls.

signal changed
signal meal_completed(customer_id: int, payment: int)

const Footprint=preload("res://scripts/cafe_footprint.gd")
const DiningSets=preload("res://scripts/cafe_dining_sets.gd")
const FurnitureMotion=preload("res://scripts/cafe_furniture_motion.gd")
const LayoutAccess=preload("res://scripts/cafe_layout_access.gd")
const OpeningGeometry=preload("res://scripts/cafe_wall_openings.gd")
const ShellSegments=preload("res://scripts/cafe_shell_segments.gd")
const WallGeometry=preload("res://scripts/cafe_walls.gd")
const Money=preload("res://scripts/cafe_money.gd")
const RuntimeCodec=preload("res://scripts/cafe_runtime_codec.gd")
const OutsideQueue=preload("res://scripts/cafe_outside_queue.gd")
const Parking=preload("res://scripts/cafe_parking.gd")
const SaveContract=preload("res://scripts/cafe_save_contract.gd")
const Checkout=preload("res://scripts/cafe_checkout.gd")
const SAVE_SCHEMA = SaveContract.SCHEMA
const SAVE_VERSION = SaveContract.VERSION
const INITIAL_COINS := 1200
const BASE_WIDTH := Footprint.WIDTH
const ORIGINAL_BASE_DEPTH := Footprint.LEGACY_DEPTH # Pre-v12 physical flooring only.
const BASE_DEPTH := Footprint.DEPTH
const MAX_DEPTH := 18
const MAX_WIDTH := 18
const PARCEL_WIDTH := 3
const PARCEL_DEPTH := 3
const PARCEL_ROWS := 3
const PARCEL_COLUMNS := 4
# Provisional land progression. Existing ownership never incurs a new charge.
const PARCEL_RING_COSTS := [10000,18000,30000]
const PARCEL_ROW_COSTS := PARCEL_RING_COSTS # Compatibility name for older callers.
const RIGHT_PARCEL_ROWS := 2
const RIGHT_PARCEL_COLUMNS := 3
const RIGHT_PARCEL_ROW_COSTS := [10000,18000]
const RIGHT_PARCEL_DEPTH := RIGHT_PARCEL_COLUMNS*PARCEL_DEPTH
const PARCEL_COST := 10000 # Compatibility alias for first-row callers.
const LEGACY_PARCEL_IDS := ["front_0", "front_1", "front_2", "front_3"]
const FRONT_PARCEL_IDS := ["front_0", "front_1", "front_2", "front_3", "row2_0", "row2_1", "row2_2", "row2_3", "row3_0", "row3_1", "row3_2", "row3_3"]
const RIGHT_PARCEL_IDS := ["right_0", "right_1", "right_2", "right2_0", "right2_1", "right2_2"]
const V11_PARCEL_IDS := FRONT_PARCEL_IDS+RIGHT_PARCEL_IDS
const CORNER_PARCEL_COLUMNS := 2
const CORNER_PARCEL_ROWS := 3
const CORNER_PARCEL_IDS := ["corner_0", "corner_1", "corner2_0", "corner2_1", "corner3_0", "corner3_1"]
const PARCEL_IDS := V11_PARCEL_IDS+CORNER_PARCEL_IDS
# Compatibility name: expand() now buys one small parcel, never the whole strip.
const EXPANSION_COST := PARCEL_COST
const DOOR_START := Footprint.DOOR_START
const DOOR_END := Footprint.DOOR_END
const EXTERIOR_ARRIVAL_FRONT := 10.5
const EXTERIOR_ARRIVAL_RIGHT := 13.76
const EXTERIOR_EXIT_FRONT := 11.4
const EXTERIOR_EXIT_RIGHT := 12.85
const GUEST_CLEARANCE := 0.44
const STAFF_PLACEMENT_RADIUS := 0.30
# Approved early growth rates apply to future purchases, payments and work.
# Saved balances, accrued payroll and historical purchase costs stay intact.
const HIRE_COST := 2800
const MEAL_PAYMENT := 200
const MAX_COOKS := 3
const STAFF_CAPS={"chef":3,"waiter":4,"cleaner":3,"cashier":1}
const HIRE_FEES={"chef":2800,"waiter":2200,"cleaner":1800}
const WAGE_RATES={"chef":18,"waiter":11,"cleaner":10,"cashier":11} # Future duty only; saved accrual and debt remain exact.
const MAX_STOVE_LEVEL := 3
const ENTRANCE := Footprint.ENTRANCE
const ENTRY_LANDING := Footprint.ENTRY_LANDING
const SERVICE_KINDS := ["table", "chair", "bench", "stove", "beverage", "sink", "counter", "bin", "register"]
const PHASES := ["arriving", "ordering", "cooking", "drinking", "eating", "checkout_wait", "checkout_walk", "paying", "leaving", "dirty", "cleaning"]
const BASE_COOK_SECONDS := 45.0
const ORDER_TAKING_SECONDS := 3.0
const PHASE_SECONDS := {"ordering": ORDER_TAKING_SECONDS, "cooking": BASE_COOK_SECONDS, "drinking": 3.0, "eating": 6.0, "dirty": 1.5, "cleaning": 4.0}
const WALK_SPEED := 1.5
const ARRIVAL_INTERVAL := 4.0
const MAX_ARRIVING := 2
const EXTERIOR_DOOR := Footprint.EXTERIOR_DOOR
const ARRIVAL_LANE_X := -2.76
const ARRIVAL_START_Z := 10.8
const StreetExtent=preload("res://scripts/exterior_world_extent.gd")
const STREET_ROUTE_FORMAT="little_leaf.street_endpoints.v1"
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var catalog: Array[Dictionary] = [
	{"kind":"table_set","name":"Basic oak","price":280,"variant":"oak_single","description":"Round oak table · simple wooden chair"},
	{"kind":"table_set_cottage","name":"Cottage","price":420,"variant":"cottage_single","description":"Cream farmhouse table · sage cross-back chair"},
	{"kind":"table_set_retro","name":"Retro","price":1200,"variant":"retro_single","description":"Mint pedestal table · coral diner chair"},
	{"kind":"table_set_refined","name":"Refined","price":3600,"variant":"refined_single","description":"Ivory-inlaid walnut table · forest upholstered chair"},
	{"kind": "table", "hidden":true, "name": "Cafe table", "price": 100},
	{"kind": "chair", "hidden":true, "name": "Dining chair", "price": 40},
	{"kind": "stove", "name": "Stove", "price": 220},
	{"kind": "beverage", "name": "Beverage station", "price": 160},
	{"kind": "sink", "name": "Dishwashing sink", "price": 140},
	{"kind": "counter", "name": "Service counter", "price": 90},
	{"kind": "bin", "name": "Trash bin", "price": 65},
	{"kind": "register", "name": "Included cash register", "price": 0},
	{"kind": "plant", "name": "Leafy plant", "price": 45},
	{"kind": "lamp", "name": "Floor lamp", "price": 65},
	{"kind": "bookshelf", "name": "Bookshelf", "price": 110},
	{"kind": "rug", "name": "Woven rug", "price": 50},
	{"kind": "bench", "hidden":true, "name": "Dining bench", "price": 75},
	{"kind": "divider", "name": "Room divider", "price": 85},
]

var items: Array[Dictionary] = []
var customers: Array[Dictionary] = []
var outside_queue: Array[Dictionary] = []
var parking_owned=false
var parking_paid_cost=0
var parking_visits:Array[Dictionary]=[]
var _parking_session_purchase=false

func parking_price()->int:return Parking.PRICE
func parking_refund()->int:return parking_paid_cost if decoration_session_active and _parking_session_purchase else int(parking_paid_cost/2)
func buy_parking()->bool:
	if not decoration_session_active:return _fail("Open Decorate to buy parking")
	if parking_owned:return _fail("Parking already owned")
	if coins<parking_price():return _fail("Not enough coins · %s needed"%Money.amount(parking_price()))
	parking_paid_cost=parking_price();coins-=parking_paid_cost;parking_owned=true;_parking_session_purchase=true
	last_error="";last_event="Four parking bays bought · −%s"%Money.amount(parking_paid_cost);_notify();return true
func sell_parking()->bool:
	if not decoration_session_active:return _fail("Open Decorate to sell parking")
	if not parking_owned:return _fail("Parking is not owned")
	if not parking_visits.is_empty():return _fail("Parking occupied · wait for every car to leave")
	var refund=parking_refund();coins+=refund;parking_owned=false;parking_paid_cost=0;_parking_session_purchase=false
	last_error="";last_event="Parking sold · +%s"%Money.amount(refund);_notify();return true

func visual_customers()->Array:
	var visible=customers.filter(func(guest):return not (guest.get("parking_visit",false) and guest.phase in ["dirty","cleaning"]))
	return visible+outside_queue+Parking.visual_walkers(self)
var dining_sets:Array[Dictionary]=[]
var built_walls: Array[Dictionary] = []
var wall_attachments:Array[Dictionary]=[]
var _next_wall_id:int=1
var _next_attachment_id:int=2
const FLOOR_STYLES := ["warm_oak", "cream_tile", "sage_tile"]
const FLOOR_COSTS := {"warm_oak":8,"cream_tile":10,"sage_tile":12}
# Land controls access; installed finishes are a separate, paid surface layer.
var floor_style: String = "warm_oak" # Selected flooring brush.
var floor_finishes: Dictionary = {} # Canonical "x,z" keys, never inferred from land.
var shell_material: String = "original" # Legacy migration field; products own current host styles.
var shell_products:Dictionary = {}
var shell_segment_products:Dictionary = {}
# View supplies current staff centers before preview/commit. Never serialized.
var wall_actor_positions: Array[Vector2] = []
var _wall_index: Dictionary = {}
var _wall_index_revision: int = -1
var _collision_revision:int=-1
var _solid_wall_segments:Array=[]
var _admission_signature:Array=[]
var _fixed_edge_revision:int=-1
var _fixed_edges:Dictionary={}
var coins: int = INITIAL_COINS
# Ownership, not the bounding rectangle, controls every walkable/placeable tile.
# `expanded` is retained for callers: true only when ALL finite parcels are owned.
var owned_parcels: Array[String] = []
var expanded: bool = false
var width: int = BASE_WIDTH
var depth: int = BASE_DEPTH
var _visible_land_bounds_dirty := true
var _visible_land_bounds := Vector2i.ZERO
var _visible_land_floor_size := Vector2i(-1,-1)
var cooks: int = 1
var duty_targets={"chef":1,"waiter":1,"cleaner":1,"cashier":0}
var duty_counts={"chef":1,"waiter":1,"cleaner":1,"cashier":0}
var waiters: int = 1
var cleaners: int = 1
var payroll_elapsed=0.0
var payroll_accrued=0.0
var wages_due=0
var total_wages_paid=0
var served: int = 0
var total_earned: int = 0
var total_cleaned: int = 0
var revision: int = 0
var last_error: String = ""
var last_event: String = "New reconstructed cafe · 1,200 starter coins"
var _next_item_id: int = 1
var _next_customer_id: int = 1
var operating_open: bool = true
var included_bin_pending: bool = true
var included_checkout_pending: bool = true
var cashiers: int = 0
var next_checkout_ticket: int = 1
var service_snapshot: Dictionary = {}
var loaded_save_version: int = SAVE_VERSION
var _arrival_elapsed: float = 0.0
var _walking_customer_id: int = -1
# Current staff centers are transient occupancy, never a permanent layout rule.
var guest_obstacle_positions: Array[Vector2] = []
var checkout_staff_claims:Array[Vector2]=[] # Transient physical/next-leg reservations for deployment.
var _motion_preview_cache: Dictionary = {}
var _mobility_validated: Dictionary = {}
var last_placement_issue: Dictionary = {}


func _init() -> void:
	reset_new()


func reset_new() -> void:
	decoration_session_active=false;decoration_purchases.clear();decoration_build_purchases.clear()
	## A free furnished starter layout leaves the NEW game budget untouched.
	items.clear()
	dining_sets.clear()
	customers.clear()
	outside_queue.clear()
	parking_owned=false;parking_paid_cost=0;parking_visits.clear();_parking_session_purchase=false
	built_walls.clear()
	wall_attachments=OpeningGeometry.initial_attachments();_next_wall_id=1;_next_attachment_id=2
	floor_style="warm_oak";shell_material="original";shell_products=OpeningGeometry.initial_shell_products()
	shell_segment_products=ShellSegments.migrate(shell_products,built_walls).segments
	floor_finishes.clear()
	for z in range(BASE_DEPTH):
		for x in range(BASE_WIDTH):floor_finishes[_floor_key(Vector2i(x,z))]={"style":floor_style,"paid_cost":0}
	wall_actor_positions.clear()
	guest_obstacle_positions.clear();checkout_staff_claims.clear()
	operating_open=true
	included_bin_pending=true
	included_checkout_pending=true;cashiers=0;next_checkout_ticket=1
	service_snapshot.clear()
	loaded_save_version=SAVE_VERSION
	coins = INITIAL_COINS
	owned_parcels.clear()
	_sync_floor_bounds()
	cooks = 1;waiters=1;cleaners=1
	duty_targets={"chef":1,"waiter":1,"cleaner":1,"cashier":0};duty_counts=duty_targets.duplicate()
	payroll_elapsed=0.0;payroll_accrued=0.0;wages_due=0;total_wages_paid=0
	served = 0
	total_earned = 0
	total_cleaned = 0
	_next_item_id = 1
	_next_customer_id = 1
	_arrival_elapsed = 0.0
	_walking_customer_id = -1
	for spec in [
		["stove", 8, 1, 0], ["beverage", 9, 1, 0], ["sink", 10, 1, 0],
		["counter", 8, 2, 0], ["counter", 9, 2, 0],
		["table", 3, 3, 0], ["chair", 3, 4, 0],
		["table", 6, 5, 0], ["chair", 6, 6, 0],
		["plant", 1, 1, 0], ["plant", 10, 6, 0],
		["bookshelf", 5, 0, 0], ["lamp", 1, 7, 0],
	]:
		var item: Dictionary = {"id": _next_item_id, "kind": spec[0], "x": spec[1], "z": spec[2], "rot": spec[3]}
		if item.kind == "stove":
			item["level"] = 1
		items.append(item)
		_next_item_id += 1
	rebuild_dining_sets()
	last_error = ""
	last_event = "New reconstructed cafe · 1,200 starter coins"
	_notify()


func operating_status() -> String:
	if operating_open:return "Open"
	for guest in customers:
		if not bool(guest.get("withdrawn",false)) and str(guest.phase) not in ["dirty","cleaning"] and _customer_admitted(guest):return "Closing"
	return "Closed"

func _customer_admitted(guest:Dictionary) -> bool:
	if bool(guest.get("admitted",false)):return true
	if str(guest.phase)!="arriving":return not bool(guest.get("withdrawn",false))
	return is_floor_owned(Vector2i(floori(float(guest.x)),floori(float(guest.z))))

func set_operating_open(value:bool) -> bool:
	if operating_open==value:return true
	operating_open=value;_arrival_elapsed=0.0
	if not value:
		Parking.close(self)
		for visitor in outside_queue:OutsideQueue.cancel(visitor)
		for guest in customers:
			if str(guest.phase)=="arriving" and not _customer_admitted(guest):_withdraw_exterior_guest(guest)
	last_event="Open · welcoming new guests" if value else "Closing · seated guests may finish; staff keep working"
	_notify();return true

func _withdraw_exterior_guest(guest:Dictionary):
	# Return along the already-travelled exterior prefix, never through the
	# restaurant. In-progress admissions already on owned floor may finish.
	var route:Array[Vector2]=[]
	var old:Array=guest.get("route",[])
	for index in range(mini(int(guest.get("route_index",0))-1,old.size()-1),-1,-1):
		var point:Vector2=old[index]
		if is_floor_owned(Vector2i(floori(point.x),floori(point.y))):continue
		route.append(point)
	var position=Vector2(float(guest.x),float(guest.z))
	if route.is_empty() and absf(position.x-ARRIVAL_LANE_X)>.001:route.append(Vector2(ARRIVAL_LANE_X,position.y))
	# An arrival still on the first pavement segment simply keeps walking
	# outward; do not turn a rear queued guest back into an exiting peer.
	var destination=Parking.HANDOFF.y if guest.get("parking_visit",false) else (float(guest.street_origin_z) if guest.get("street_route_format","")==STREET_ROUTE_FORMAT else maxf(ARRIVAL_START_Z+3.0,position.y+2.0))
	route.append(Vector2(ARRIVAL_LANE_X,destination))
	guest.phase="leaving";guest.seated=false;guest.waiting=false
	guest["withdrawn"]=true;guest["admitted"]=false;guest["exit_completed"]=false
	guest.exterior_exit=true;guest.departure_blocked=false
	guest.route=route;guest.route_index=0;guest.elapsed=0.0
	guest.duration=_route_length(Vector2(float(guest.x),float(guest.z)),route)/WALK_SPEED

func ensure_basic_bin() -> bool:
	if count_kind("bin")>0:included_bin_pending=false;return true
	# Add the newly required free essential only to a clear, reachable owned
	# cell. Existing furniture, coins, staffing and plot ownership never move.
	var candidates:Array[Vector2i]=[Vector2i(11,1),Vector2i(11,2),Vector2i(10,0),Vector2i(11,0)]
	for z in range(depth):
		for x in range(2,width):
			var cell=Vector2i(x,z)
			if not candidates.has(cell):candidates.append(cell)
	for cell in candidates:
		for rotation in range(4):
			if not can_place("bin",cell.x,cell.y,-1,rotation):continue
			var item={"id":_next_item_id,"kind":"bin","x":cell.x,"z":cell.y,"rot":rotation}
			var proposed:Array[Dictionary]=items.duplicate(true);proposed.append(item)
			if not _sale_station_usable_in(item,proposed,_sale_reachable_in(proposed)):continue
			items.append(item);_next_item_id+=1;included_bin_pending=false
			last_error="";last_event="Included trash bin added · existing restaurant preserved"
			_notify();return true
	last_error="No clear space for the included trash bin · make one tile and any adjacent side reachable in Decorate"
	return false

func ensure_basic_register(actors:Array=[]) -> bool:return Checkout.ensure(self,actors)
func checkout_register() -> Dictionary:return Checkout.register(self)
func checkout_rear(item:Dictionary) -> Vector2i:return Checkout.rear(self,item)
func checkout_claims(except_id:int=-1) -> Dictionary:return Checkout.claimed_cells(self,except_id)
func checkout_queue() -> Array:return Checkout.queue(self)
func checkout_ready(guest:Dictionary,register_id:int) -> bool:return Checkout.ready(self,guest,register_id)
func begin_checkout_payment(id:int,ticket:int,register_id:int,token:int) -> bool:return Checkout.begin(self,id,ticket,register_id,token)
func commit_checkout_payment(id:int,ticket:int,register_id:int,token:int) -> bool:return Checkout.commit(self,id,ticket,register_id,token)

func price_of(kind: String) -> int:
	if kind=="bin" and included_bin_pending:return 0
	for entry in catalog:
		if entry.kind == kind:
			return int(entry.price)
	return -1


func is_dining_product(kind:String)->bool:return DiningSets.is_product(kind)
func name_of(kind:String)->String:
	for entry in catalog:
		if entry.kind==kind:return str(entry.name)
	return kind.capitalize()
func dining_variant_for(id:int)->String:
	return str(dining_set_for(id).get("variant","oak_single"))

# Transient navigation facts contain no item Dictionary references. Content
# signatures also cover direct fixture edits/replacements that omit _notify().
var _navigation_signature:Array=[]
var _navigation_cells:Dictionary={}
func navigation_signature()->Array:
	return [revision,hash(items),hash(owned_parcels),hash(built_walls),hash(wall_attachments),hash(shell_products),hash(shell_segment_products),width,depth]

func navigation_cells()->Dictionary:
	var signature=navigation_signature()
	if signature!=_navigation_signature:
		_navigation_signature=signature
		_navigation_cells.clear()
		for item in items:
			var cell=Vector2i(int(item.x),int(item.z))
			if not _navigation_cells.has(cell):_navigation_cells[cell]=str(item.kind)!="rug"
		# Live geometry caches must also notice direct replacement/mutation.
		_fixed_edge_revision=-1;_wall_index_revision=-1;_collision_revision=-1
	return _navigation_cells

func get_item(id: int) -> Dictionary:
	for item in items:
		if int(item.id) == id:
			return item
	return {}


func item_at(x: int, z: int) -> Dictionary:
	for item in items:
		if int(item.x) == x and int(item.z) == z:
			return item
	return {}


func rebuild_dining_sets():
	dining_sets=DiningSets.migrate(items,customers,dining_sets)
func dining_set_for(id:int)->Dictionary:return DiningSets.group_for(dining_sets,id)
func logical_item_id(id:int)->int:
	var group=dining_set_for(id);return int(group.table_id) if not group.is_empty() else id
func logical_kind(id:int)->String:return DiningSets.product_for_variant(dining_variant_for(id)) if not dining_set_for(id).is_empty() else str(get_item(id).get("kind",""))
func logical_rotation(id:int)->int:
	var group=dining_set_for(id);return int(group.rot) if not group.is_empty() else int(get_item(id).get("rot",0))
func logical_members(id:int)->Array:
	var group=dining_set_for(id);return [int(group.table_id),int(group.seat_id)] if not group.is_empty() else [id]
# Session receipts are deliberately memory-only: a reload finalizes interrupted edits.
# IDs are stable through moves; only successful purchases/sales change this ledger.
var decoration_session_active=false
var decoration_purchases:Dictionary={}
var decoration_build_purchases:Dictionary={}
func begin_decoration_session():
	if decoration_session_active:return
	decoration_session_active=true;decoration_purchases.clear();decoration_build_purchases.clear();_notify()
func finish_decoration_session():
	_parking_session_purchase=false
	decoration_session_active=false;decoration_purchases.clear();decoration_build_purchases.clear();_notify()
func record_decoration_purchase(id:int,paid:int):
	if decoration_session_active:decoration_purchases[id]=paid
func consume_decoration_purchase(ids:Array):
	for id in ids:decoration_purchases.erase(int(id))
func decoration_refund_bonus(id:int)->int:
	var bonus=0
	for member in logical_members(id):
		var paid=int(decoration_purchases.get(member,0))
		bonus+=paid-int(paid/2)
	return bonus if decoration_session_active else 0
func record_decoration_build_purchase(category:String,id:int,paid:int):
	if decoration_session_active:decoration_build_purchases[category+":"+str(id)]=paid
func wall_refund(key:String)->int:
	var wall=get_wall(key)
	if wall.is_empty():return 0
	var receipt="wall:"+str(int(wall.id))
	if decoration_session_active and decoration_build_purchases.has(receipt):return int(decoration_build_purchases[receipt])
	return int(wall_price(str(wall.height))/2)
func wall_attachment_refund(id:int)->int:
	var attachment=get_wall_attachment(id)
	if attachment.is_empty():return 0
	var receipt="opening:"+str(id)
	if decoration_session_active and decoration_build_purchases.has(receipt):return int(decoration_build_purchases[receipt])
	return int(int(attachment.paid_cost)/2)
func logical_refund(id:int)->int:
	if get_item(id).is_empty():return 0
	if decoration_session_active and dining_set_for(id).is_empty() and decoration_purchases.has(id):return int(decoration_purchases[id])
	return DiningSets.refund(self,id)+decoration_refund_bonus(id)
func logical_item_count()->int:return items.size()-dining_sets.size()
func placement_parts(kind:String,x:int,z:int,rot:int,id:int=-1)->Array[Dictionary]:
	if is_dining_product(kind) or not dining_set_for(id).is_empty():return DiningSets.parts(self,x,z,rot,id,DiningSets.variant_for_product(kind))
	return [{"id":id if id>=0 else -100,"kind":kind,"x":x,"z":z,"rot":rot}]

func can_place(kind: String, x: int, z: int, ignore_id: int = -1, rot: int = 0, actor_positions: Array = []) -> bool:
	last_error = "";last_placement_issue={}
	if is_dining_product(kind) or not dining_set_for(ignore_id).is_empty():return DiningSets.can_place(self,x,z,rot,ignore_id,actor_positions)
	if kind=="register" and ignore_id<0 and not included_checkout_pending:return _fail("The included register is already placed")
	if price_of(kind) < 0:
		return _fail("Unknown furnishing")
	if not is_floor_owned(Vector2i(x, z)):
		return _fail("Buy this plot first" if not parcel_at(Vector2i(x, z)).is_empty() else "That tile is outside the cafe")
	if Vector2i(x, z) == ENTRANCE or Vector2i(x, z) == ENTRY_LANDING:
		return _fail("Keep the entrance and its landing clear")
	if kind != "rug" and _guest_route_uses(Vector2i(x, z)):
		return _fail("A guest is using that tile or walking route")
	var proposed: Array[Dictionary] = []
	for item in items:
		if int(item.id) == ignore_id:
			continue
		if int(item.x) == x and int(item.z) == z:
			return _fail("That tile is occupied")
		proposed.append(item)
	proposed.append({"id": ignore_id, "kind": kind, "x": x, "z": z, "rot": posmod(rot,4)})
	var actor_error := _furniture_actor_error([proposed[-1]],proposed,actor_positions)
	if actor_error!="":return _fail(actor_error)
	if not _placement_workfaces_allowed(proposed):return false
	var chair_error := _chair_egress_error(built_walls,proposed,owned_parcels,customers)
	if chair_error!="":return _fail(chair_error)
	if kind=="register":
		var register_error=Checkout.placement_error(self,proposed[-1],proposed,_furniture_actor_positions(actor_positions))
		if register_error!="":return _fail(register_error)
	if not _layout_has_access(proposed, depth):
		return _fail("Leave a walkable route to the entrance and service stations")
	if not built_walls.is_empty() or not checkout_claims().is_empty():
		var reason=_wall_egress_error(built_walls,[],proposed,owned_parcels,customers)
		if reason!="":return _fail(reason)
	return true


func place(kind: String, x: int, z: int, rot: int = 0, actor_positions: Array = []) -> bool:
	if is_dining_product(kind):return DiningSets.place(self,x,z,rot,DiningSets.variant_for_product(kind),actor_positions)
	if not can_place(kind, x, z, -1, rot, actor_positions):
		return false
	if kind=="register":
		Checkout.adopt(self,{"id":_next_item_id,"kind":"register","x":x,"z":z,"rot":posmod(rot,4)})
		return true
	var price := price_of(kind)
	if coins < price:
		return _fail("Not enough coins · need %s" % Money.amount(price))
	var item: Dictionary = {"id": _next_item_id, "kind": kind, "x": x, "z": z, "rot": posmod(rot, 4)}
	if kind == "stove":
		item["level"] = 1
	items.append(item)
	if kind=="bin":included_bin_pending=false
	_next_item_id += 1
	coins -= price
	record_decoration_purchase(int(item.id),price)
	rebuild_dining_sets()
	last_event = "Placed %s · −%s coins" % [kind, Money.amount(price)]
	_notify()
	return true


func layout_access_issues(layout:Array=items)->Array:
	return LayoutAccess.issues(self,layout)

func placement_access_issues(kind:String,x:int,z:int,ignore_id:int=-1,rot:int=0)->Array:
	var proposed:Array[Dictionary]=[]
	var omitted=logical_members(ignore_id) if ignore_id>=0 else []
	for item in items:
		if int(item.id) not in omitted:proposed.append(item)
	proposed.append_array(placement_parts(kind,x,z,rot,ignore_id))
	return layout_access_issues(proposed)

func _placement_workfaces_allowed(layout:Array)->bool:
	last_placement_issue=LayoutAccess.introduced(self,layout)
	return true if last_placement_issue.is_empty() else _fail(str(last_placement_issue.reason))

func can_move(id:int,x:int,z:int,rot:int=0,actor_positions:Array=[])->bool:
	var key=[revision,id,x,z,rot,hash(items),hash(customers),hash(actor_positions),hash(built_walls),hash(wall_attachments),hash(owned_parcels)]
	var transaction:Dictionary
	if _motion_preview_cache.get("key",[])==key:transaction=_motion_preview_cache
	else:
		transaction=FurnitureMotion.plan(self,id,x,z,rot,actor_positions)
		_motion_preview_cache={"key":key,"ok":bool(transaction.ok),"error":str(transaction.get("error","")),"issue":transaction.get("issue",{}).duplicate(true)}
	last_error="" if transaction.ok else str(transaction.error)
	last_placement_issue=transaction.get("issue",{}).duplicate(true)
	return bool(transaction.ok)

func move(id: int, x: int, z: int, rot: int = 0, actor_positions: Array = []) -> bool:
	return FurnitureMotion.commit(self,FurnitureMotion.plan(self,id,x,z,rot,actor_positions))

func _layout_motion_geometry_error(guests:Array,layout:Array,walls:Array,ownership:Array,openings:Array)->String:
	return FurnitureMotion.geometry_error(self,guests,layout,walls,ownership,openings)

func _move_static(id: int, x: int, z: int, rot: int = 0, actor_positions: Array = []) -> bool:
	if not dining_set_for(id).is_empty():return DiningSets.move(self,id,x,z,rot,actor_positions)
	var item := get_item(id)
	if item.is_empty():
		return _fail("Select a furnishing first")
	if _item_in_use(id):
		return _fail("Wait until the table is cleaned before moving its furniture")
	if not can_place(str(item.kind), x, z, id, rot, actor_positions):
		return false
	item.x = x
	item.z = z
	item.rot = posmod(rot, 4)
	rebuild_dining_sets()
	last_event = "Moved %s" % item.kind
	_notify()
	return true


func remove(id: int, refund: bool = true) -> bool:
	if not dining_set_for(id).is_empty():return DiningSets.remove(self,id,refund)
	var item := get_item(id)
	if item.is_empty():
		return _fail("Select a furnishing first")
	if _item_in_use(id):
		return _fail("Wait until the table is cleaned before removing its furniture")
	var essential_error := _essential_removal_error([id])
	if essential_error != "":
		return _fail(essential_error)
	var returned: int = logical_refund(id) if refund else 0
	consume_decoration_purchase([id])
	items.erase(item)
	coins += returned
	last_error = ""
	rebuild_dining_sets()
	last_event = "Removed %s · +%s coins" % [item.kind, Money.amount(returned)]
	_notify()
	return true


func _essential_removal_error(removed_ids: Array) -> String:
	# SERVICE_KINDS already defines the model's dining and service furniture.
	# Check the proposed layout before any item, group or wallet mutation.
	var required: Array[String] = []
	var removes_dining := false
	var proposed: Array[Dictionary] = []
	for item in items:
		if int(item.id) not in removed_ids:
			proposed.append(item)
		elif not dining_set_for(int(item.id)).is_empty():
			removes_dining = true
		elif str(item.kind) in SERVICE_KINDS and str(item.kind) not in ["table", "chair", "bench"]:
			required.append(str(item.kind))
	if required.is_empty() and not removes_dining:
		return ""
	var reachable := _sale_reachable_in(proposed)
	for kind in required:
		var replacement := false
		for item in proposed:
			if str(item.kind) == kind and _sale_station_usable_in(item, proposed, reachable):
				replacement = true
				break
		if not replacement:
			return "Keep a usable %s before selling this one" % name_of(kind).to_lower()
	if removes_dining:
		var guest_reachable := _wall_reachable(built_walls, proposed, owned_parcels)
		# Only registered groups can admit diners; adjacent legacy loose parts
		# are not silently relinked by the existing linked-sale path.
		for group in dining_sets:
			if int(group.table_id) in removed_ids or int(group.seat_id) in removed_ids:
				continue
			var table: Dictionary = get_item(int(group.table_id))
			var seat: Dictionary = get_item(int(group.seat_id))
			if table.is_empty() or seat.is_empty():
				continue
			var table_cell := Vector2i(int(table.x), int(table.z))
			var seat_cell := Vector2i(int(seat.x), int(seat.z))
			if edge_blocked(table_cell, seat_cell):
				continue
			if _chair_egress_cells_in(seat_cell, table_cell - seat_cell, built_walls, guest_reachable).is_empty():
				continue
			for side in table_service_cells(table, proposed):
				if reachable.has(side):
					return ""
		return "Keep a usable table set before selling this one"
	return ""


func _sale_reachable_in(layout: Array[Dictionary]) -> Dictionary:
	# Match the runtime's staff grid (x >= 1) and model wall-edge rules from
	# the landing. Actor positions, reservations and current jobs are temporary.
	var blocked: Dictionary = {}
	for item in layout:
		if str(item.kind) != "rug":
			blocked[Vector2i(int(item.x), int(item.z))] = true
	if blocked.has(ENTRY_LANDING):
		return {}
	var reachable: Dictionary = {ENTRY_LANDING: true}
	var queue: Array[Vector2i] = [ENTRY_LANDING]
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction in DIRECTIONS:
			var next: Vector2i = cell + direction
			if next.x < 1 or reachable.has(next) or blocked.has(next) or not is_floor_owned(next) or edge_blocked(cell, next):
				continue
			reachable[next] = true
			queue.append(next)
	return reachable


func _sale_station_usable_in(item: Dictionary, layout: Array[Dictionary], reachable: Dictionary) -> bool:
	if str(item.kind)=="bin":
		for cell in bin_service_cells(item,layout):
			if reachable.has(cell):return true
		return false
	if not _workface_open_in(item, layout) or not reachable.has(workface_cell(item)):
		return false
	if str(item.kind) == "counter":
		# The real pass needs the chef's rear and the waiter's front connected.
		var reverse := item.duplicate()
		reverse.rot = posmod(int(item.get("rot", 0)) + 2, 4)
		return _workface_open_in(reverse, layout) and reachable.has(workface_cell(reverse))
	return true


func stove_upgrade_cost(id: int) -> int:
	var item := get_item(id)
	if item.is_empty() or item.kind != "stove" or int(item.get("level", 1)) >= MAX_STOVE_LEVEL:
		return -1
	return 180 + 80 * (int(item.get("level", 1)) - 1)


func upgrade_stove(id: int) -> bool:
	var item := get_item(id)
	var cost := stove_upgrade_cost(id)
	if cost < 0:
		return _fail("Select a stove below level 3")
	if coins < cost:
		return _fail("Not enough coins · upgrade needs %s" % Money.amount(cost))
	coins -= cost
	item["level"] = int(item.get("level", 1)) + 1
	last_error = ""
	last_event = "Stove upgraded to level %d" % item.level
	_notify()
	return true


func staff_count(role:String)->int:return staff_roster().get(role,0)
func staff_roster()->Dictionary:return {"chef":cooks,"waiter":waiters,"cleaner":cleaners,"cashier":cashiers}
func wage_rate()->int:return int(duty_counts.chef)*int(WAGE_RATES.chef)+int(duty_counts.waiter)*int(WAGE_RATES.waiter)+int(duty_counts.cleaner)*int(WAGE_RATES.cleaner)+int(duty_counts.get("cashier",0))*int(WAGE_RATES.cashier)
func usable_stoves()->int:
	var fronts={}
	for item in items:
		if item.kind!="stove" or not _workface_open_in(item,items):continue
		var front=workface_cell(item)
		if not path_between(ENTRY_LANDING,front).is_empty():fronts[front]=true
	return fronts.size()
func hire_reason(role:String)->String:
	if role=="cashier":return "Included cashier waiting for space" if included_checkout_pending else "Included"
	if not STAFF_CAPS.has(role):return "Unknown role"
	if staff_count(role)>=int(STAFF_CAPS[role]):return "Team full"
	if int(duty_targets[role])<staff_count(role):return "Resume first"
	if role=="chef" and usable_stoves()<=int(duty_counts.chef):return "Add stove"
	if wages_due>0:return "Wages due"
	if coins<int(HIRE_FEES[role]):return "Not enough coins"
	return ""
func request_duty(role:String,change:int)->bool:
	if role=="cashier":return _fail("The included cashier stays on duty while deployed")
	if not STAFF_CAPS.has(role) or change not in [-1,1]:return _fail("Unknown shift change")
	var desired=int(duty_targets[role])+change
	if desired<1:return _fail("Keep one core worker on duty")
	if desired>staff_count(role):return _fail("Everyone is already on duty")
	if role=="chef" and change>0 and desired>usable_stoves():return _fail("Add stove")
	duty_targets[role]=desired;last_error="";last_event="Finish current job, then off duty" if change<0 else "Back on duty · no fee";_notify();return true
func hire_staff(role:String)->bool:
	var reason=hire_reason(role)
	if reason!="":return _fail(reason)
	var fee=int(HIRE_FEES[role])
	coins-=fee
	match role:
		"chef":cooks+=1
		"waiter":waiters+=1
		"cleaner":cleaners+=1
	duty_targets[role]=int(duty_targets[role])+1;duty_counts[role]=int(duty_counts[role])+1
	last_error="";last_event="Hired %s · −%s"%[role,Money.amount(fee)];_notify();return true
func hire_cook()->bool:return hire_staff("chef")
func advance_payroll(delta:float,on_duty:bool)->Dictionary:
	if not on_duty or not is_finite(delta) or delta<=0:return {"paid":0,"charged":0,"due":wages_due}
	# Only simulated on-duty time accrues. No wall-clock/offline timestamp is
	# stored. Joining mid-cycle pays only the actual fraction worked.
	var time=minf(delta,60.0);var charged=0
	while time>.000001:
		var part=minf(time,60.0-payroll_elapsed)
		payroll_elapsed+=part;payroll_accrued+=float(wage_rate())*part/60.0;time-=part
		if payroll_elapsed>=60.0-.000001:
			var bill=floori(payroll_accrued+.000001);payroll_accrued=maxf(0,payroll_accrued-bill);payroll_elapsed=0.0;wages_due+=bill;charged+=bill
	var paid=mini(coins,wages_due)
	if paid>0:coins-=paid;wages_due-=paid;total_wages_paid+=paid
	# A visible outstanding balance is recoverable from later meal income;
	# never negative cash, hidden offline bankruptcy or lost existing service.
	return {"paid":paid,"charged":charged,"due":wages_due}


func _parcel_geometric_ring(parcel:Dictionary)->int:
	# A ring is spatial distance from the starter footprint, not a ledger row.
	var right_band=maxi(0,ceili(float(parcel.x+parcel.w-BASE_WIDTH)/PARCEL_WIDTH))
	var front_band=maxi(0,ceili(float(parcel.z+parcel.h-BASE_DEPTH)/PARCEL_DEPTH))
	return maxi(right_band,front_band)

func _parcel_geometry(index:int)->Dictionary:
	if index<0 or index>=PARCEL_IDS.size():return {}
	var corner=index>=V11_PARCEL_IDS.size()
	var right=not corner and index>=FRONT_PARCEL_IDS.size()
	var offset=V11_PARCEL_IDS.size() if corner else (FRONT_PARCEL_IDS.size() if right else 0)
	var columns=CORNER_PARCEL_COLUMNS if corner else (RIGHT_PARCEL_COLUMNS if right else PARCEL_COLUMNS)
	var local_index=index-offset
	var row=int(local_index/columns);var column=local_index%columns
	var parcel={"id":PARCEL_IDS[index],"direction":"corner" if corner else ("right" if right else "front"),"row":row,"column":column,
		"x":BASE_WIDTH+column*PARCEL_WIDTH if corner else (BASE_WIDTH+row*PARCEL_WIDTH if right else column*PARCEL_WIDTH),
		"z":BASE_DEPTH+row*PARCEL_DEPTH if corner or not right else column*PARCEL_DEPTH,
		"w":PARCEL_WIDTH,"h":PARCEL_DEPTH,
		"prerequisite":"" if row==0 else PARCEL_IDS[index-columns]}

	parcel["cost"]=PARCEL_RING_COSTS[_parcel_geometric_ring(parcel)-1]
	return parcel

func _parcel_has_owned_neighbor(parcel:Dictionary,ownership:Array)->bool:
	for x in range(int(parcel.x),int(parcel.x)+int(parcel.w)):
		for z in [int(parcel.z)-1,int(parcel.z)+int(parcel.h)]:
			if _floor_owned_in(Vector2i(x,z),ownership):return true
	for z in range(int(parcel.z),int(parcel.z)+int(parcel.h)):
		for x in [int(parcel.x)-1,int(parcel.x)+int(parcel.w)]:
			if _floor_owned_in(Vector2i(x,z),ownership):return true
	return false

func expansion_parcels() -> Array[Dictionary]:
	## Original front/right ledgers progress independently. The finite corner
	## has its own first-incomplete-row stage and needs a shared owned edge.
	var parcels:Array[Dictionary]=[]
	var active_rows={"front":active_expansion_row(),"right":active_expansion_row("right"),"corner":active_expansion_row("corner")}
	for index in PARCEL_IDS.size():
		var parcel=_parcel_geometry(index)
		var stage_visible=parcel.row==active_rows[parcel.direction]
		var available=stage_visible
		if parcel.direction=="corner":available=available and _parcel_has_owned_neighbor(parcel,owned_parcels)
		parcel["owned"]=owned_parcels.has(parcel.id)
		parcel["unlocked"]=available
		# The full first geometric ring includes its diagonal corner even while
		# that corner is purchase-locked. Beyond it, reveal existing unlocked
		# expansion choices without changing any purchase or ownership rule.
		var in_first_ring=_parcel_geometric_ring(parcel)==1
		parcel["visible"]=stage_visible and (in_first_ring or available)
		parcels.append(parcel)
	return parcels

func active_expansion_row(direction:String="front")->int:
	var ids=CORNER_PARCEL_IDS if direction=="corner" else (RIGHT_PARCEL_IDS if direction=="right" else FRONT_PARCEL_IDS)
	var columns=CORNER_PARCEL_COLUMNS if direction=="corner" else (RIGHT_PARCEL_COLUMNS if direction=="right" else PARCEL_COLUMNS)
	var rows=CORNER_PARCEL_ROWS if direction=="corner" else (RIGHT_PARCEL_ROWS if direction=="right" else PARCEL_ROWS)
	for row in range(rows):
		for column in range(columns):
			if not owned_parcels.has(ids[row*columns+column]):return row
	return rows

func _ensure_visible_land_bounds():
	# Land ownership determines both axes. Camera pan/zoom, furniture, wages
	# and paint cannot change this derived view; no parcel list is a cache key.
	var floor_size=Vector2i(width,depth)
	if not _visible_land_bounds_dirty and floor_size==_visible_land_floor_size:return
	var bounds=floor_size
	for parcel in expansion_parcels():
		if parcel.visible:
			bounds.x=maxi(bounds.x,int(parcel.x)+int(parcel.w))
			bounds.y=maxi(bounds.y,int(parcel.z)+int(parcel.h))
	_visible_land_bounds=bounds
	_visible_land_floor_size=floor_size
	_visible_land_bounds_dirty=false

func visible_land_depth()->int:
	_ensure_visible_land_bounds()
	return _visible_land_bounds.y

func visible_land_width()->int:
	_ensure_visible_land_bounds()
	return _visible_land_bounds.x

func parcel_by_id(parcel_id:String)->Dictionary:
	var index=PARCEL_IDS.find(parcel_id)
	return expansion_parcels()[index] if index>=0 else {}

func _parcel_index_at(cell:Vector2i)->int:
	if cell.x<0 or cell.x>=MAX_WIDTH or cell.y<0 or cell.y>=MAX_DEPTH:return -1
	if cell.x>=BASE_WIDTH:
		if cell.y>=RIGHT_PARCEL_DEPTH:
			return V11_PARCEL_IDS.size()+int((cell.y-BASE_DEPTH)/PARCEL_DEPTH)*CORNER_PARCEL_COLUMNS+int((cell.x-BASE_WIDTH)/PARCEL_WIDTH)
		return FRONT_PARCEL_IDS.size()+int((cell.x-BASE_WIDTH)/PARCEL_WIDTH)*RIGHT_PARCEL_COLUMNS+int(cell.y/PARCEL_DEPTH)
	if cell.y<BASE_DEPTH:return -1
	return int((cell.y-BASE_DEPTH)/PARCEL_DEPTH)*PARCEL_COLUMNS+int(cell.x/PARCEL_WIDTH)

func parcel_at(cell:Vector2i)->Dictionary:
	var index=_parcel_index_at(cell)
	return expansion_parcels()[index] if index>=0 else {}

func is_floor_owned(cell:Vector2i)->bool:return _floor_owned_in(cell,owned_parcels)

func _floor_owned_in(cell:Vector2i,ownership:Array,layout_depth:int=MAX_DEPTH)->bool:
	if cell.x<0 or cell.x>=MAX_WIDTH or cell.y<0 or cell.y>=mini(layout_depth,MAX_DEPTH):return false
	if cell.x<BASE_WIDTH and cell.y<BASE_DEPTH:return true
	var index=_parcel_index_at(cell)
	return index>=0 and ownership.has(PARCEL_IDS[index])

func _ownership_connected(ownership:Array)->bool:
	for id in ownership:
		var parcel=_parcel_geometry(PARCEL_IDS.find(id))
		if parcel.is_empty():return false
		if parcel.prerequisite!="" and not ownership.has(parcel.prerequisite):return false
	# Flood the parcel graph from the starter footprint. Neighbouring corner
	# plots alone cannot validate an isolated island in a malformed save.
	var connected:Array=[]
	var remaining=ownership.duplicate()
	while not remaining.is_empty():
		var grew=false
		for id in remaining.duplicate():
			if _parcel_has_owned_neighbor(_parcel_geometry(PARCEL_IDS.find(id)),connected):
				connected.append(id);remaining.erase(id);grew=true
		if not grew:return false
	return true

func _depth_for(ownership:Array)->int:
	var result=BASE_DEPTH
	for id in ownership:
		var parcel=_parcel_geometry(PARCEL_IDS.find(id))
		if not parcel.is_empty():result=maxi(result,int(parcel.z)+int(parcel.h))
	return result

func _width_for(ownership:Array)->int:
	var result=BASE_WIDTH
	for id in ownership:
		var parcel=_parcel_geometry(PARCEL_IDS.find(id))
		if not parcel.is_empty():result=maxi(result,int(parcel.x)+int(parcel.w))
	return result

func owned_floor_count()->int:return BASE_WIDTH*BASE_DEPTH+owned_parcels.size()*PARCEL_WIDTH*PARCEL_DEPTH

func _sync_floor_bounds()->void:
	width=_width_for(owned_parcels);depth=_depth_for(owned_parcels);expanded=owned_parcels.size()==PARCEL_IDS.size()
	# Purchase, reset/new game and successful load all finish ownership here.
	_visible_land_bounds_dirty=true

func next_parcel()->Dictionary:
	for parcel in expansion_parcels():
		if not parcel.owned and parcel.unlocked:return parcel
	return {}

func buy_parcel(parcel_id:String)->bool:
	var parcel=parcel_by_id(parcel_id)
	if parcel.is_empty():return _fail("Choose a FOR SALE sign")
	if parcel.owned:return _fail("You already own this plot")
	if not parcel.unlocked:return _fail("Buy adjacent land and finish the current corner row first" if parcel.direction=="corner" else "Finish the current row first")
	if coins<int(parcel.cost):return _fail("Not enough coins · %s needed"%Money.amount(int(parcel.cost)))
	coins-=int(parcel.cost);owned_parcels.append(parcel_id);owned_parcels.sort();_sync_floor_bounds()
	last_error="";last_event="Plot bought · −%s"%Money.amount(int(parcel.cost));_notify();return true

func expand()->bool:
	var parcel=next_parcel()
	return buy_parcel(str(parcel.id)) if not parcel.is_empty() else _fail("All plots owned")


func wall_segments() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for host in OpeningGeometry.shell_hosts(shell_products,built_walls):
		for segment in OpeningGeometry.solid_segments(host,built_walls,wall_attachments):result.append(segment)
	return result

func boundary_has_wall(cell:Vector2i,outward:Vector2i)->bool:
	return edge_blocked(cell,cell+outward)

func boundary_entries() -> Array[Dictionary]:
	## Only free, owned cells touching reachable public exterior qualify. Locked
	## parcels are neither indoor shortcuts nor public approach space.
	var entries: Array[Dictionary] = []
	for z in range(depth):
		for x in range(width):
			var cell := Vector2i(x, z)
			if not _walkable(cell):
				continue
			for direction in DIRECTIONS:
				var outside: Vector2i = cell + direction
				if not _public_exterior_cell(outside) or boundary_has_wall(cell, direction):
					continue
				entries.append({"cell": cell, "outside": outside, "direction": direction})
	return entries


func _public_exterior_cell(cell:Vector2i,ownership:Variant=null)->bool:
	return not _floor_owned_in(cell,owned_parcels if ownership==null else ownership)

func _arrival_front()->float:return maxf(EXTERIOR_ARRIVAL_FRONT,float(depth)+.5)
func _exit_front()->float:return maxf(EXTERIOR_EXIT_FRONT,float(depth)+1.4)
func _arrival_right()->float:return maxf(EXTERIOR_ARRIVAL_RIGHT,float(width)+1.76)
func _exit_right()->float:return maxf(EXTERIOR_EXIT_RIGHT,float(width)+.85)
func _departure_exit_z(id:int)->float:return -2.5 if id%2==0 else maxf(12.5,float(depth)+2.5)


func _exterior_approach(entry: Dictionary, arriving: bool, exit_z: float = 12.5) -> Array[Vector2]:
	var outside := cell_center(entry.outside)
	# Jagged open edges use their unowned column down to the shared front
	# walkway; never cut diagonally through another purchased plot.
	if entry.outside.x>=0 and entry.outside.x<MAX_WIDTH and entry.outside.y>=BASE_DEPTH and entry.outside.y<MAX_DEPTH:
		if arriving:return [Vector2(ARRIVAL_LANE_X,_arrival_front()),Vector2(outside.x-.26,_arrival_front()),Vector2(outside.x-.26,outside.y),outside]
		return [outside,Vector2(outside.x+.26,outside.y),Vector2(outside.x+.26,_exit_front()),Vector2(-.85,_exit_front()),Vector2(-.85,exit_z)]
	# Right-side gaps have an empty horizontal route to the outer lane: each
	# right column owns a prefix, so no later plot can block that route.
	if entry.outside.x>=BASE_WIDTH and entry.outside.y>=0 and entry.outside.y<RIGHT_PARCEL_DEPTH:
		if arriving:return [Vector2(ARRIVAL_LANE_X,_arrival_front()),Vector2(_arrival_right(),_arrival_front()),Vector2(_arrival_right(),outside.y),outside]
		return [outside,Vector2(_exit_right(),outside.y),Vector2(_exit_right(),_exit_front()),Vector2(-.85,_exit_front()),Vector2(-.85,exit_z)]
	if arriving:
		if entry.direction == Vector2i.UP:
			return [Vector2(ARRIVAL_LANE_X,-1.76),Vector2(outside.x,-1.76),outside]
		if entry.direction == Vector2i.LEFT:
			return [Vector2(ARRIVAL_LANE_X, outside.y), outside]
		if entry.direction == Vector2i.DOWN:
			return [Vector2(ARRIVAL_LANE_X, _arrival_front()), Vector2(outside.x-.26, _arrival_front()),Vector2(outside.x-.26,outside.y),outside]
		if entry.direction == Vector2i.RIGHT:
			return [Vector2(ARRIVAL_LANE_X, _arrival_front()), Vector2(_arrival_right(), _arrival_front()), Vector2(_arrival_right(), outside.y), outside]
	else:
		if entry.direction == Vector2i.UP:
			return [outside,Vector2(outside.x,-.85),Vector2(-.85,-.85),Vector2(-.85,exit_z)]
		if entry.direction == Vector2i.LEFT:
			return [outside, Vector2(-0.85, outside.y), Vector2(-0.85, exit_z)]
		if entry.direction == Vector2i.DOWN:
			return [outside,Vector2(outside.x+.26,outside.y),Vector2(outside.x+.26,_exit_front()),Vector2(-0.85,_exit_front()),Vector2(-0.85,exit_z)]
		if entry.direction == Vector2i.RIGHT:
			return [outside, Vector2(_exit_right(), outside.y), Vector2(_exit_right(), _exit_front()), Vector2(-0.85, _exit_front()), Vector2(-0.85, exit_z)]
	return []


func guest_access_for(chair_id: int, arriving: bool = true, start: Vector2 = Vector2(ARRIVAL_LANE_X, ARRIVAL_START_Z), exit_z: float = 12.5, table_id: int = -1, customer_id: int = -1) -> Dictionary:
	## Prefer a reachable chair side, then the shortest complete valid journey.
	## A rear approach remains a compatibility fallback if both sides are blocked.
	## Indoor BFS never traverses unowned floor.
	var chair := get_item(chair_id)
	if chair.is_empty():
		return {}
	var chair_cell := Vector2i(int(chair.x), int(chair.z))
	var best: Dictionary = {}
	var best_length := INF
	var best_rank := 4
	var forward := _chair_table_direction(chair_id,table_id)
	var egress_cells := chair_egress_cells(chair_id,table_id)
	for entry in boundary_entries():
		for approach in egress_cells:
			var direction:Vector2i=approach-chair_cell
			var approach_rank := 0 if direction.x*forward.x+direction.y*forward.y==0 else 1
			if not arriving and _egress_occupied(customer_id,approach):approach_rank+=2
			var indoor := Checkout.path(self,entry.cell,approach)
			if indoor.is_empty():
				continue
			var route: Array[Vector2] = []
			if arriving:
				route.assign(_exterior_approach(entry, true))
				for cell in indoor:
					route.append(cell_center(cell))
				route.append(cell_center(chair_cell))
			else:
				indoor.reverse()
				for cell in indoor:
					route.append(cell_center(cell))
				route.append_array(_exterior_approach(entry, false, exit_z))
			var length := _route_length(start if arriving else cell_center(chair_cell), route)
			if approach_rank<best_rank or (approach_rank==best_rank and length+.000001<best_length):
				best_rank=approach_rank
				best_length = length
				best = {"entry_cell": entry.cell, "entry_direction": entry.direction,
					"entry_outside": entry.outside, "approach": approach,
					"route": route, "length": length,"chair_approach":"side" if approach_rank%2==0 else "rear_fallback"}
	return best


func chair_egress_cells(chair_id:int,table_id:int=-1) -> Array[Vector2i]:
	# Left/right/back only. The diner's own tabletop is never an exit.
	var chair:=get_item(chair_id)
	if chair.is_empty():return []
	var chair_cell:=Vector2i(int(chair.x),int(chair.z))
	var forward:=_chair_table_direction(chair_id,table_id)
	return _chair_egress_cells_in(chair_cell,forward,built_walls,_wall_reachable(built_walls,items,owned_parcels))

func _chair_egress_cells_in(chair_cell:Vector2i,forward:Vector2i,walls:Array,reachable:Dictionary,openings=null) -> Array[Vector2i]:
	var result:Array[Vector2i]=[]
	for direction in [Vector2i(-forward.y,forward.x),Vector2i(forward.y,-forward.x),-forward]:
		var cell:Vector2i=chair_cell+direction
		if reachable.has(cell) and not _fixed_edge_blocked(chair_cell,cell,openings,walls) and not _built_edge_blocked(chair_cell,cell,walls,openings):result.append(cell)
	return result

func _chair_egress_error(walls:Array,layout:Array,ownership:Array,guests:Array,openings=null) -> String:
	var reachable:=_wall_reachable(walls,layout,ownership,openings)
	var reserved_error:=_reserved_chair_egress_error(walls,layout,guests,reachable,openings)
	if reserved_error!="":return reserved_error
	var by_id:Dictionary={}
	for item in layout:by_id[int(item.id)]=item
	for group in DiningSets.migrate(layout,guests,dining_sets):
		var chair:Dictionary=by_id[int(group.seat_id)];var table:Dictionary=by_id[int(group.table_id)]
		var cell:=Vector2i(int(chair.x),int(chair.z))
		var forward:=Vector2i(int(table.x),int(table.z))-cell
		if _chair_egress_cells_in(cell,forward,walls,reachable,openings).is_empty():return "Keep a clear chair exit on its left, right or back, connected to the walkway"
	return ""

func _reserved_chair_egress_error(walls:Array,layout:Array,guests:Array,reachable:Dictionary,openings=null) -> String:
	# A paid diner has committed to one physical dismount leg, even before
	# its first movement tick. Another exit is not a substitute for that leg.
	var by_id:Dictionary={}
	for item in layout:by_id[int(item.id)]=item
	for guest in guests:
		if not bool(guest.get("dismounting",false)) or bool(guest.get("departure_blocked",false)):continue
		var chair:Dictionary=by_id.get(int(guest.chair_id),{});var table:Dictionary=by_id.get(int(guest.table_id),{})
		if not chair.is_empty() and not table.is_empty():
			var cell:=Vector2i(int(chair.x),int(chair.z))
			var forward:=Vector2i(int(table.x),int(table.z))-cell
			if _chair_egress_cells_in(cell,forward,walls,reachable,openings).has(guest.get("egress_cell")):continue
		return "A guest is getting off this chair · keep its reserved chair exit clear"
	return ""

func reserved_guest_egress() -> Vector2i:
	for guest in customers:
		if int(guest.id)==_walking_customer_id and bool(guest.get("dismounting",false)) and not bool(guest.get("departure_blocked",false)):return guest.egress_cell
	return Vector2i(-100,-100)

func _egress_occupied(_customer_id:int,_cell:Vector2i) -> bool:
	# A dismount is transit. Other people do not block its physical landing.
	return false

func _chair_table_direction(chair_id:int,table_id:int=-1) -> Vector2i:
	# Approach a seat through its open side instead of walking through its back.
	# The table used by the visit overrides a chair's editable idle orientation.
	var chair:=get_item(chair_id)
	if chair.is_empty():return Vector2i.UP
	if table_id<0:
		for guest in customers:
			if int(guest.chair_id)==chair_id:table_id=int(guest.table_id);break
	var table:=get_item(table_id)
	if table.is_empty():
		for item in items:
			if item.kind=="table" and absi(int(item.x)-int(chair.x))+absi(int(item.z)-int(chair.z))==1:
				table=item;break
	if not table.is_empty():return Vector2i(int(table.x)-int(chair.x),int(table.z)-int(chair.z))
	return [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT][posmod(int(chair.get("rot",0)),4)]


func count_kind(kind: String) -> int:
	var count := 0
	for item in items:
		if item.kind == kind:
			count += 1
	return count


func readiness_text() -> String:
	if count_kind("stove") == 0:
		return "Add a stove to cook meals"
	if count_kind("beverage") == 0:
		return "Add a beverage station for drinks"
	if count_kind("sink") == 0:
		return "Add a sink to wash dishes"
	if _seating_pairs().is_empty():
		return "Place a chair or bench next to a table"
	return "Cafe ready · service stations connected"


func tick(delta: float) -> void:
	## Small internal slices keep outcomes stable with variable rendering rates.
	## Pausing is the caller's responsibility. Long offline catch-up is not done.
	if not is_finite(delta) or delta <= 0.0:
		return
	var remaining: float = minf(delta, 60.0)
	while remaining > 0.000001:
		var step: float = minf(remaining, 0.1)
		_tick_step(step)
		remaining -= step


func _tick_step(delta: float) -> void:
	Checkout.advance(self,delta)
	_choose_walker()
	var cook_slots := mini(cooks, count_kind("stove"))
	var occupied_cooks := 0
	var occupied_sinks := 0
	var departing: Array[Dictionary] = []
	for customer in customers:
		if FurnitureMotion.active(customer):
			FurnitureMotion.advance(self,customer,delta)
			if bool(customer.get("meal_abandoned",false)) and not FurnitureMotion.active(customer):_begin_departure(customer)
			continue
		var phase: String = str(customer.phase)
		if bool(customer.get("meal_abandoned",false)) and phase not in ["leaving","dirty","cleaning"]:
			_begin_departure(customer);continue
		if phase in ["arriving","leaving","checkout_walk"]:
			customer.waiting = false
			_advance_walk(customer, delta)
			if bool(customer.get("exit_completed",false)):departing.append(customer)
			continue
		if phase in ["checkout_wait","paying"]:continue
		var speed: float = 1.0
		if phase == "cooking":
			if occupied_cooks >= cook_slots:
				continue
			occupied_cooks += 1
			speed = _best_stove_speed()
		elif phase == "drinking" and count_kind("beverage") == 0:
			continue
		elif phase == "cleaning":
			if occupied_sinks >= count_kind("sink"):
				continue
			occupied_sinks += 1
		customer.elapsed = float(customer.elapsed) + delta * speed
		if float(customer.elapsed) + 0.000001 < float(customer.duration):
			continue
		var phase_index := PHASES.find(phase)
		if phase == "eating":
			if str(customer.get("settlement_mode","legacy"))=="register":
				Checkout.finish_meal(self,customer);continue
			# No coins are awarded for arrival, orders, drinks, or dirty plates.
			coins += MEAL_PAYMENT
			served += 1
			total_earned += MEAL_PAYMENT
			customer["paid"] = true
			last_event = "Meal enjoyed · +%s coins" % Money.amount(MEAL_PAYMENT)
			meal_completed.emit(int(customer.id), MEAL_PAYMENT)
			_begin_departure(customer)
			continue
		if phase == "cleaning":
			total_cleaned += 1
			departing.append(customer)
		else:
			customer.phase = PHASES[phase_index + 1]
			customer.elapsed = 0.0
			customer.duration = PHASE_SECONDS[customer.phase]
	for customer in departing:
		customers.erase(customer)
	Parking.advance(self,delta)
	OutsideQueue.advance(self,delta)
	if operating_open:_arrival_elapsed += delta
	if operating_open and _arrival_elapsed + 0.000001 >= ARRIVAL_INTERVAL:
		_arrival_elapsed = 0.0
		_spawn_customer()


func _spawn_customer() -> void:
	if not parking_owned:
		_spawn_walkers(2);return
	if not operating_open or count_kind("stove")==0 or count_kind("beverage")==0 or count_kind("sink")==0:return
	for attempt in range(2):
		if _next_customer_id%2==0 and Parking.reserve(self):continue
		_spawn_walkers(1)

func _spawn_walkers(limit:int) -> void:
	if not operating_open:return
	if count_kind("stove") == 0 or count_kind("beverage") == 0 or count_kind("sink") == 0:
		return
	if not outside_queue.is_empty() or Parking.pending_count(self)>0:
		for attempt in range(limit):OutsideQueue.add(self)
		return
	var used_tables: Dictionary = {}
	var used_chairs: Dictionary = {}
	var arriving := 0
	for customer in customers:
		if bool(customer.get("withdrawn",false)):continue
		used_tables[int(customer.table_id)] = true
		used_chairs[int(customer.chair_id)] = true
		if customer.phase == "arriving":
			arriving += 1
	var added := 0
	for pair in _seating_pairs():
		if added >= limit or arriving >= MAX_ARRIVING:
			break
		if used_tables.has(int(pair.table_id)) or used_chairs.has(int(pair.chair_id)):
			continue
		var chair := get_item(int(pair.chair_id))
		var start := _arrival_start_position()
		var access := guest_access_for(int(chair.id),true,start,12.5,int(pair.table_id))
		if access.is_empty():
			continue
		var approach: Vector2i = access.approach
		var route: Array[Vector2] = access.route
		var customer: Dictionary = {
			"id": _next_customer_id, "table_id": pair.table_id, "chair_id": pair.chair_id,
			"mobility":{}, "phase": "arriving", "elapsed": 0.0, "duration": _route_length(start, route) / WALK_SPEED,
			"x": start.x, "z": start.y, "paid": false, "seated": false, "admitted": false, "withdrawn": false, "exit_completed": false,"meal_abandoned":false,
			"street_route_format":STREET_ROUTE_FORMAT,"street_origin_z":start.y,
			"route": route, "route_index": 0, "heading": Vector2.DOWN if start.y<0.0 else Vector2.UP,
			"service_cell": approach, "waiting": true, "exterior_exit": false,
			"entry_cell": access.entry_cell, "entry_direction": access.entry_direction,
			"entry_outside": access.entry_outside, "departure_blocked": false,
			"dismounting": false, "egress_cell": Vector2i(-100,-100), "dismount_progress": 0.0,
		}
		Checkout.init_guest(self,customer)
		customers.append(customer)
		# A visit owns its tableware/service side until cleanup ends. Blocking
		# that side later pauses work; it must not slide a delivered cup across.
		customer["table_service_direction"] = _table_service_direction_in(get_item(int(pair.table_id)), items)
		used_tables[int(pair.table_id)] = true
		used_chairs[int(pair.chair_id)] = true
		_next_customer_id += 1
		added += 1
		arriving += 1
	if added==0:
		for attempt in range(limit):OutsideQueue.add(self)

func _admit_queued_visitor(visitor:Dictionary)->bool:
	var oldest=Parking.oldest_pending(self)
	if oldest>=0 and oldest<int(visitor.id):return false
	var eligibility=[]
	for guest in customers:eligibility.append([int(guest.id),int(guest.table_id),int(guest.chair_id),bool(guest.get("withdrawn",false)),guest.phase=="arriving"])
	var signature=[navigation_signature(),hash(dining_sets),operating_open,eligibility,int(visitor.id),float(visitor.x),float(visitor.z)]
	if signature==_admission_signature:return false
	_admission_signature=signature
	# A failed admission is stable until layout, seat ownership, arrival slots,
	# or this FIFO request changes. Queue movement/wait timers still tick.
	navigation_cells()
	var admitted=_try_admit_queued_visitor(visitor)
	if admitted:_admission_signature=[]
	return admitted

func _try_admit_queued_visitor(visitor:Dictionary)->bool:
	if not operating_open or customers.filter(func(g):return g.phase=="arriving").size()>=MAX_ARRIVING:return false
	var used_tables={};var used_chairs={}
	for guest in customers:
		if bool(guest.get("withdrawn",false)):continue
		used_tables[int(guest.table_id)]=true;used_chairs[int(guest.chair_id)]=true
	var position=Vector2(float(visitor.x),float(visitor.z))
	for pair in _seating_pairs():
		if used_tables.has(int(pair.table_id)) or used_chairs.has(int(pair.chair_id)):continue
		var access=guest_access_for(int(pair.chair_id),true,Vector2(ARRIVAL_LANE_X,position.y),12.5,int(pair.table_id),int(visitor.id))
		if access.is_empty():continue
		var route:Array[Vector2]=[Vector2(ARRIVAL_LANE_X,position.y)]
		route.append_array(access.route)
		var previous=position;var safe=true
		for point in route:
			if segment_blocked(previous,point):safe=false;break
			previous=point
		if not safe:continue
		var guest={"id":visitor.id,"table_id":pair.table_id,"chair_id":pair.chair_id,"mobility":{},"phase":"arriving","elapsed":0.0,"duration":_route_length(position,route)/WALK_SPEED,"x":position.x,"z":position.y,"paid":false,"seated":false,"admitted":false,"withdrawn":false,"exit_completed":false,"meal_abandoned":false,"street_route_format":STREET_ROUTE_FORMAT,"street_origin_z":visitor.origin_z,"route":route,"route_index":0,"heading":Vector2.LEFT,"service_cell":access.approach,"waiting":false,"exterior_exit":false,"entry_cell":access.entry_cell,"entry_direction":access.entry_direction,"entry_outside":access.entry_outside,"departure_blocked":false,"dismounting":false,"egress_cell":Vector2i(-100,-100),"dismount_progress":0.0}
		Checkout.init_guest(self,guest)
		guest["table_service_direction"]=_table_service_direction_in(get_item(int(pair.table_id)),items)
		customers.append(guest);outside_queue.erase(visitor)
		Parking.admitted(self,guest)
		return true
	return false


func table_service_direction(table_id: int) -> Vector2i:
	## Match the actual diner's side while keeping tableware stable when a live
	## actor temporarily occupies or reserves the chosen interaction cell.
	var table := get_item(table_id)
	if table.is_empty() or str(table.kind) != "table":
		return Vector2i.LEFT
	return _table_service_direction_in(table, items)


func table_service_cells(table:Dictionary,layout:Array[Dictionary]=items)->Array:
	# Presentation offsets remain stable; routing independently chooses the
	# closest reachable unoccupied face, never the customer's seated side.
	var result=[]
	var center=Vector2i(int(table.x),int(table.z))
	var guest_side=_table_guest_direction_in(table,layout)
	for direction in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
		if direction==guest_side:continue
		var cell=center+direction
		if _table_side_open_in(cell,layout) and not edge_blocked(center,cell):result.append(cell)
	return result

func _table_guest_direction_in(table: Dictionary, layout: Array[Dictionary]) -> Vector2i:
	var table_cell=Vector2i(int(table.x),int(table.z))
	for guest in customers:
		if int(guest.table_id)!=int(table.id):continue
		for chair in layout:
			if int(chair.id)==int(guest.chair_id):
				var delta=Vector2i(int(chair.x),int(chair.z))-table_cell
				if absi(delta.x)+absi(delta.y)==1:return delta
	var group=dining_set_for(int(table.id))
	if not group.is_empty():
		for linked in layout:
			if int(linked.id)==int(group.seat_id):
				var delta=Vector2i(int(linked.x),int(linked.z))-table_cell
				if absi(delta.x)+absi(delta.y)==1:return delta
	for chair in layout:
		if str(chair.kind) not in ["chair","bench"]:continue
		var delta=Vector2i(int(chair.x),int(chair.z))-table_cell
		if absi(delta.x)+absi(delta.y)==1:return delta
	return Vector2i.DOWN


func _table_service_direction_in(table: Dictionary, layout: Array[Dictionary]) -> Vector2i:
	for guest in customers:
		if int(guest.table_id) == int(table.id) and guest.has("table_service_direction"):
			return guest.table_service_direction
	var toward := _table_guest_direction_in(table, layout)
	var preferred := Vector2i(-toward.y, toward.x)
	var center := Vector2i(int(table.x), int(table.z))
	if _table_side_open_in(center + preferred, layout) and not edge_blocked(center,center+preferred):
		return preferred
	if _table_side_open_in(center - preferred, layout) and not edge_blocked(center,center-preferred):
		return -preferred
	return preferred


func _table_side_open_in(cell: Vector2i, layout: Array[Dictionary]) -> bool:
	# Match the runtime's reserved street-side staff lane (x=0).
	if cell.x < 1 or not is_floor_owned(cell):
		return false
	for item in layout:
		if int(item.x) == cell.x and int(item.z) == cell.y and str(item.kind) != "rug":
			return false
	return true


func workface_cell(item: Dictionary) -> Vector2i:
	var direction: Vector2i=[Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT][posmod(int(item.get("rot",0)),4)]
	return Vector2i(int(item.x),int(item.z))+direction

func bin_service_cells(item: Dictionary, layout=null) -> Array[Vector2i]:
	# Open-top bins have no working front. Use the same four cardinal floor
	# cells at every rotation; walls, solid furniture and ownership still apply.
	var result: Array[Vector2i]=[]
	if str(item.get("kind",""))!="bin":return result
	var proposed: Array[Dictionary]=items if layout==null else layout
	var base=Vector2i(int(item.x),int(item.z))
	if not is_floor_owned(base):return result
	for direction in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]:
		var cell:Vector2i=base+direction
		if _table_side_open_in(cell,proposed) and not edge_blocked(base,cell):result.append(cell)
	return result

func placement_warning(kind: String, x: int, z: int, ignore_id: int = -1, rot: int = 0) -> String:
	if is_dining_product(kind) or not dining_set_for(ignore_id).is_empty():
		var candidate=DiningSets.candidate(self,x,z,rot,ignore_id)
		for item in candidate.layout:
			if item.kind in ["stove","beverage","sink","counter","table","bin","register"]:
				var warning=_operational_warning(item,candidate.layout)
				if warning!="":return warning
		return ""
	var proposed: Array[Dictionary]=[]
	for item in items:
		if int(item.id)!=ignore_id: proposed.append(item)
	proposed.append({"id":ignore_id,"kind":kind,"x":x,"z":z,"rot":posmod(rot,4)})
	for item in proposed:
		if not str(item.kind) in ["stove","beverage","sink","counter","table","bin","register"]: continue
		var warning=_operational_warning(item,proposed)
		if warning=="": continue
		var previous=get_item(int(item.id))
		if int(item.id)==ignore_id or previous.is_empty() or _operational_warning(previous,items)=="": return warning
	return ""

func _operational_warning(item: Dictionary, layout: Array[Dictionary]) -> String:
	if str(item.kind) == "table":
		return "" if not table_service_cells(item,layout).is_empty() else "Table service sides blocked: clear a side beside the diner in Decorate"
	if str(item.kind)=="bin":
		return "" if _sale_station_usable_in(item,layout,_sale_reachable_in(layout)) else "Bin sides blocked: clear any adjacent side in Decorate"
	if not _workface_open_in(item,layout): return "%s front blocked: staff will wait until you make space in Decorate"%str(item.kind).capitalize()
	if str(item.kind) in ["counter","register"]:
		var reverse=item.duplicate();reverse.rot=posmod(int(item.get("rot",0))+2,4)
		if not _workface_open_in(reverse,layout): return "Pass counter back blocked: chef needs a clear drop-off tile"
	return ""

func _workface_open_in(item: Dictionary, layout: Array[Dictionary]) -> bool:
	var cell=workface_cell(item)
	if edge_blocked(Vector2i(int(item.x),int(item.z)),cell):return false
	if cell.x<1 or not is_floor_owned(cell): return false
	for other in layout:
		if int(other.x)==cell.x and int(other.z)==cell.y and str(other.kind)!="rug": return false
	return true

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)


func _arrival_start_position() -> Vector2:
	# The original world's two pavement ends, independent of camera and land
	# growth. The visit follows its real full route at the normal walking speed.
	var z=float(StreetExtent.PAVEMENT_Z_MIN if _next_customer_id%2==0 else StreetExtent.PAVEMENT_Z_MAX)
	return Vector2(ARRIVAL_LANE_X, z)


func path_between(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	## Cardinal BFS over actual walkable grid cells. Both endpoints must be open.
	## The route includes start/end. Exterior coordinates are deliberately rejected.
	var empty: Array[Vector2i] = []
	var occupied=navigation_cells()
	if not is_floor_owned(start) or not is_floor_owned(finish) or bool(occupied.get(start,false)) or bool(occupied.get(finish,false)):
		return empty
	var previous: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		if current == finish:
			var route: Array[Vector2i] = [finish]
			while route[-1] != start:
				route.append(previous[route[-1]])
			route.reverse()
			return route
		for direction in DIRECTIONS:
			var next: Vector2i = current + direction
			if not previous.has(next) and is_floor_owned(next) and not bool(occupied.get(next,false)) and (built_walls.is_empty() or not edge_blocked(current,next)):
				previous[next] = current
				queue.append(next)
	return empty


func service_cell_for(id: int, from: Vector2i = ENTRANCE) -> Vector2i:
	var item := get_item(id)
	var result := Vector2i(-1, -1)
	var best_length := 1000000
	if item.is_empty():
		return result
	for direction in DIRECTIONS:
		var candidate: Vector2i = Vector2i(int(item.x), int(item.z)) + direction
		if edge_blocked(Vector2i(int(item.x),int(item.z)),candidate):continue
		var path := path_between(from, candidate)
		if not path.is_empty() and path.size() < best_length:
			best_length = path.size()
			result = candidate
	return result


func _walkable(cell: Vector2i) -> bool:
	if not is_floor_owned(cell):
		return false
	var item := item_at(cell.x, cell.y)
	return item.is_empty() or item.kind == "rug"


func _route_length(start: Vector2, route: Array[Vector2]) -> float:
	var length := 0.0
	var point := start
	for next in route:
		length += point.distance_to(next)
		point = next
	return length


func _checkout_may_walk(guest:Dictionary) -> bool:
	return not bool(guest.get("departure_blocked",false))

func _choose_walker() -> void:
	# Keep the v13 field for save compatibility, but all guests walk together.
	_walking_customer_id = -1

func _advance_walk(customer: Dictionary, delta: float) -> void:
	if bool(customer.get("departure_blocked", false)):
		if str(customer.get("settlement_mode","legacy"))=="register" and customer.paid:Checkout.depart(self,customer)
		else:_begin_departure(customer)
		if bool(customer.get("departure_blocked", false)):
			customer.waiting = true
			return
	if bool(customer.get("dismounting",false)) and _egress_occupied(int(customer.id),customer.egress_cell):
		customer.waiting=true
		return
	var position := Vector2(float(customer.x), float(customer.z))
	if int(customer.route_index)<customer.route.size() and segment_blocked(position,customer.route[int(customer.route_index)]):
		if not reroute_guest(customer):customer.waiting=true;return
	var budget := WALK_SPEED * delta
	var route: Array = customer.route
	while budget > 0.000001 and int(customer.route_index) < route.size():
		var destination: Vector2 = route[int(customer.route_index)]
		if segment_blocked(position,destination):
			if not reroute_guest(customer):customer.waiting=true;break
			route=customer.route;continue
		var difference := destination - position
		var distance := difference.length()
		if distance <= 0.000001:
			customer.route_index = int(customer.route_index) + 1
			continue
		customer.heading = difference / distance
		var step := minf(distance, budget)
		var proposed: Vector2 = position + customer.heading * step
		if segment_blocked(position,proposed) or _guest_body_blocks(int(customer.id), proposed):
			customer.waiting = true
			break
		position = proposed
		if bool(customer.get("dismounting",false)):
			customer.dismount_progress=clampf(1.0-position.distance_to(cell_center(customer.egress_cell)),0.0,1.0)
			if position.distance_to(cell_center(customer.egress_cell))<.00001:
				customer.dismounting=false;customer.seated=false;customer.dismount_progress=1.0
		budget -= step
		customer.elapsed = float(customer.elapsed) + step / WALK_SPEED
		if step + 0.000001 >= distance:
			position = destination
			customer.route_index = int(customer.route_index) + 1
		if customer.phase == "leaving" and _clear_of_entry(customer, position):
			customer.exterior_exit = true
	customer.x = position.x
	customer.z = position.y
	if not bool(customer.get("withdrawn",false)) and is_floor_owned(Vector2i(floori(position.x),floori(position.y))):customer["admitted"]=true
	if int(customer.route_index) < route.size():
		return
	if bool(customer.get("withdrawn",false)):
		Parking.start_return(self,int(customer.id),position)
		customer["exit_completed"]=true
		customer.waiting=false
		return
	if customer.phase=="checkout_walk":
		Checkout.arrived(self,customer);return
	if customer.phase == "arriving":
		customer.phase = "ordering"
		customer.seated = true
	else:
		Parking.start_return(self,int(customer.id),position)
		customer.phase = "dirty"
		customer.seated = false
	customer.elapsed = 0.0
	customer.duration = PHASE_SECONDS[customer.phase]
	customer.waiting = false


func _clear_of_entry(customer: Dictionary, position: Vector2) -> bool:
	var direction: Vector2i = customer.get("entry_direction", Vector2i.LEFT)
	var entry: Vector2i = customer.get("entry_cell", ENTRANCE)
	if direction == Vector2i.LEFT:
		return position.x <= float(entry.x) - 0.849
	if direction == Vector2i.RIGHT:
		return position.x >= float(entry.x + 1) + 0.849
	if direction == Vector2i.DOWN:
		return position.y >= float(entry.y + 1) + 0.849
	return false


func _guest_body_blocks(_customer_id: int, _proposed: Vector2) -> bool:
	# Seats and checkout destinations are reserved independently of bodies.
	return false

func abandon_meal(customer:Dictionary) -> void:
	if bool(customer.get("meal_abandoned",false)):return
	customer["meal_abandoned"]=true
	customer.checkout_ticket=0;customer.checkout_register_id=-1;customer.checkout_token=-1
	customer.checkout_cell=Vector2i(-100,-100);customer.checkout_reason="";customer.checkout_stall=0.0
	# A moved chair may still be receiving its diner. Finish that real route;
	# the model's next movement step starts a normal dismount when it arrives.
	if not FurnitureMotion.active(customer):_begin_departure(customer)

func _begin_departure(customer: Dictionary) -> void:
	var access := guest_access_for(int(customer.chair_id),false,Vector2.ZERO,_departure_exit_z(int(customer.id)),int(customer.table_id),int(customer.id))
	customer.phase = "leaving"
	customer.elapsed = 0.0
	customer.route_index = 0
	customer.seated = true
	customer.dismounting = true
	customer.dismount_progress = 0.0
	customer.egress_cell = Vector2i(-100,-100)
	customer.exterior_exit = false
	customer.waiting = true
	customer.departure_blocked = access.is_empty()
	if access.is_empty():
		# An obstructed externally edited layout may strand a diner. Keep its
		# reservation and position; retry safely instead of teleporting outdoors.
		customer.route = []
		customer.duration = 0.0
		return
	customer.duration = float(access.length) / WALK_SPEED
	customer.egress_cell = access.approach
	customer.route = access.route
	customer.service_cell = access.approach
	customer.entry_cell = access.entry_cell
	customer.entry_direction = access.entry_direction
	customer.entry_outside = access.entry_outside


func _guest_route_uses(cell: Vector2i) -> bool:
	if checkout_claims().has(cell):return true
	for customer in customers:
		if customer.phase in ["dirty", "cleaning"]:
			continue
		var mobility:Dictionary=customer.get("mobility",{})
		if not mobility.is_empty():
			for index in range(int(mobility.route_index),mobility.route.size()):
				if Vector2i(floori(mobility.route[index].x),floori(mobility.route[index].y))==cell:return true
		if int(floor(float(customer.x))) == cell.x and int(floor(float(customer.z))) == cell.y:
			return true
		if customer.phase in ["arriving", "leaving", "checkout_walk"]:
			for index in range(int(customer.route_index), customer.route.size()):
				var point: Vector2 = customer.route[index]
				if point.x >= 0 and Vector2i(floori(point.x), floori(point.y)) == cell:
					return true
	return false


func _seating_pairs() -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	var by_id={}
	for item in items:
		if not by_id.has(int(item.id)):by_id[int(item.id)]=item
	for group in dining_sets:
		var table:Dictionary=by_id.get(int(group.table_id),{});var chair:Dictionary=by_id.get(int(group.seat_id),{})
		if table.is_empty() or chair.is_empty():continue
		if not edge_blocked(Vector2i(int(table.x),int(table.z)),Vector2i(int(chair.x),int(chair.z))):pairs.append({"table_id":table.id,"chair_id":chair.id})
	return pairs


static func stove_speed_multiplier(item: Dictionary) -> float:
	# Existing upgrades keep their 1.0x / 1.4x / 1.8x speeds. New stove
	# tiers can use this same multiplier without changing the base recipe.
	return 1.0 + 0.4 * (clampi(int(item.get("level", 1)), 1, MAX_STOVE_LEVEL) - 1)


static func cooking_seconds(speed_multiplier: float = 1.0) -> float:
	# A 2x stove takes 45 / 2 = 22.5 simulation seconds. Global game speed
	# is applied to delta by Main, so do not multiply it a second time here.
	return BASE_COOK_SECONDS / maxf(speed_multiplier, 0.01)


func _best_stove_speed() -> float:
	var speed := 1.0
	for item in items:
		if item.kind == "stove":
			speed = maxf(speed, stove_speed_multiplier(item))
	return speed


func _item_in_use(id: int) -> bool:
	if Checkout.busy(self,id):return true
	for customer in customers:
		if int(customer.table_id) == id or int(customer.chair_id) == id:
			return true
	return false


func stats_text() -> String:
	return "%d meals served  ·  %d guests  ·  %d/%d cooks\n%s coins earned  ·  %d dishes washed\n%s" % [served, customers.size(), cooks, MAX_COOKS, Money.amount(total_earned), total_cleaned, readiness_text()]


func _layout_has_access(layout: Array[Dictionary], layout_depth: int = MAX_DEPTH, layout_parcels: Variant = null) -> bool:
	var ownership: Array = owned_parcels if layout_parcels == null else layout_parcels
	var blocked: Dictionary = {}
	for item in layout:
		# Rugs still occupy a placement tile but do not block walking.
		if item.kind != "rug":
			blocked[Vector2i(int(item.x), int(item.z))] = true
	if blocked.has(ENTRANCE) or blocked.has(ENTRY_LANDING):
		return false
	var reachable: Dictionary = {ENTRANCE: true}
	var queue: Array[Vector2i] = [ENTRANCE]
	var index := 0
	while index < queue.size():
		var current := queue[index]
		index += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + offset
			if not _floor_owned_in(neighbor, ownership, layout_depth):
				continue
			if blocked.has(neighbor) or reachable.has(neighbor):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)
	for item in layout:
		if item.kind not in SERVICE_KINDS or item.kind=="stove":
			continue
		var accessible := false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if reachable.has(Vector2i(int(item.x), int(item.z)) + offset):
				accessible = true
				break
		if not accessible:
			return false
	return true


func save(path: String = SaveContract.PRIMARY_FILE) -> bool:
	var checkout_error=Checkout.state_error(included_checkout_pending,cashiers,items,customers,duty_targets,duty_counts)
	if checkout_error!="":return _fail(checkout_error)
	checkout_error=Checkout.layout_error(self,items,built_walls,owned_parcels,customers)
	if checkout_error!="":return _fail(checkout_error)
	## Only our explicit reconstructed schema is written; no legacy paths probed.
	var group_check=DiningSets.validate(dining_sets,items,customers)
	if not group_check.ok:return _fail(str(group_check.error))
	var reserved_error:=_reserved_chair_egress_error(built_walls,items,customers,_wall_reachable(built_walls,items,owned_parcels))
	if reserved_error!="":return _fail("Could not save inconsistent active service: "+reserved_error)
	var codec=RuntimeCodec.new()
	var runtime=codec.encode({"customers":customers,"service":service_snapshot,"next_customer_id":_next_customer_id,"arrival_elapsed":_arrival_elapsed,"walking_customer_id":_walking_customer_id,"next_checkout_ticket":next_checkout_ticket,"checkout_format":SaveContract.CHECKOUT_FORMAT,"layout_motion_format":SaveContract.LAYOUT_MOTION_FORMAT})
	var checked=codec.validate(runtime,items,cooks,PHASES,SAVE_VERSION,staff_roster(),duty_counts)
	if not checked.ok:return _fail("Could not save inconsistent active service: "+str(checked.error))
	var outside=codec.encode({"format":OutsideQueue.FORMAT,"visitors":outside_queue})
	var queue_check=OutsideQueue.validate(outside,customers,_next_customer_id)
	if not queue_check.ok:return _fail(str(queue_check.error))
	var parking=codec.encode({"format":Parking.FORMAT,"owned":parking_owned,"paid_cost":parking_paid_cost,"visits":parking_visits})
	var parking_check=Parking.validate(parking,customers,outside_queue,_next_customer_id,operating_open)
	if not parking_check.ok:return _fail(str(parking_check.error))
	var motion_error=_layout_motion_geometry_error(checked.state.customers,items,built_walls,owned_parcels,wall_attachments)
	if motion_error!="":return _fail("Could not save layout motion: "+motion_error)
	checkout_error=Checkout.staff_floor_error(self,checked.state.service,owned_parcels,items)
	if checkout_error!="":return _fail(checkout_error)
	var data: Dictionary = {
		"schema": SAVE_SCHEMA, "version": SAVE_VERSION, "new_reconstruction": true,"checkout_format":SaveContract.CHECKOUT_FORMAT,"layout_motion_format":SaveContract.LAYOUT_MOTION_FORMAT,
		"cashiers":cashiers,"included_checkout_pending":included_checkout_pending,
		"coins": coins, "expanded": expanded, "owned_parcels": owned_parcels, "cooks": cooks, "served": served,
		"total_earned": total_earned, "total_cleaned": total_cleaned,
		"items": items, "next_item_id": _next_item_id,"dining_sets":dining_sets,
		"operating_open":operating_open,"included_bin_pending":included_bin_pending,"runtime":runtime,"outside_queue":outside,"parking":parking,
		"waiters":waiters,"cleaners":cleaners,"duty_targets":duty_targets,"duty_counts":duty_counts,"payroll_elapsed":payroll_elapsed,"payroll_accrued":payroll_accrued,"wages_due":wages_due,"total_wages_paid":total_wages_paid,
		"floor_finishes":floor_finishes,"starter_geometry_version":Footprint.SAVE_REVISION,
		"wall_format":2,"shell_segment_format":ShellSegments.FORMAT,"shell_segment_products":shell_segment_products,"built_walls":built_walls,"floor_style":floor_style,"shell_material":shell_material,"shell_products":shell_products,
		"wall_attachment_format":1,"wall_attachments":wall_attachments,"next_wall_id":_next_wall_id,"next_attachment_id":_next_attachment_id,
	}
	var walls_check=_validate_saved_walls(data,owned_parcels)
	if not walls_check.ok:return _fail("Could not save walls: "+str(walls_check.error))
	var floors_check=_validate_saved_floors(data,owned_parcels,floor_style)
	if not floors_check.ok:return _fail("Could not save flooring: "+str(floors_check.error))
	var openings_check=_validate_saved_attachments(data,built_walls)
	if not openings_check.ok:return _fail("Could not save wall attachments: "+str(openings_check.error))
	# Match load's structural safety gates before touching either destination.
	# In particular an explicitly imported v13 enclosure must be repaired first.
	var saved_actors:Array=[]
	for actor in checked.state.service.get("staff",[]):saved_actors.append(actor.pos)
	var egress_error=_wall_egress_error(built_walls,saved_actors,items,owned_parcels,checked.state.customers,openings_check.attachments)
	if egress_error!="":return _fail("Could not save invalid walls: "+egress_error)
	var actors=saved_actors.duplicate()
	for guest in checked.state.customers:
		if str(guest.phase) not in ["dirty","cleaning"]:actors.append(Vector2(float(guest.x),float(guest.z)))
	var body_error=_opening_body_error(built_walls,openings_check.attachments,actors)
	if body_error!="":return _fail("Could not save invalid walls: "+body_error)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not write the reconstructed save")
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _fail("Save write failed; previous save left unchanged")
	var result := DirAccess.rename_absolute(temp_path, path)
	if result != OK:
		return _fail("Could not finalize the reconstructed save")
	last_error = ""
	last_event = "Reconstructed cafe saved"
	return true


func load_save(path: String = SaveContract.PRIMARY_FILE, allow_enclosed_staff: bool = false) -> bool:
	## Validate all layout, wallet and runtime data before replacing any state.
	## Legacy v1/v2 saves never contained guests; only those open with refreshed tables.
	if not FileAccess.file_exists(path):
		return _fail("No reconstructed save found")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		return _fail("Save is unreadable or too large")
	var json := JSON.new()
	var parse_result := json.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not json.data is Dictionary:
		return _fail("Invalid reconstructed save JSON")
	var data: Dictionary = json.data
	if data.get("schema") != SAVE_SCHEMA or not _valid_int(data.get("version"), 1, SAVE_VERSION) or not data.get("new_reconstruction") is bool or data.get("new_reconstruction") != true:
		return _fail("This is not a supported reconstructed cafe save")
	if not SaveContract.accepts_header(data):return _fail("Unsupported or foreign save format")
	for field in ["coins", "served", "total_earned", "total_cleaned"]:
		if not _valid_int(data.get(field), 0, 1000000000):
			return _fail("Invalid save statistic: %s" % field)
	if not data.get("expanded") is bool or not _valid_int(data.get("cooks"), 1, MAX_COOKS):
		return _fail("Invalid expansion or staffing in save")
	var saved_waiters=2;var saved_cleaners=1;var saved_payroll_elapsed=0.0;var saved_payroll_accrued=0.0;var saved_wages_due=0;var saved_total_wages_paid=0
	if int(data.version)>=9:
		if not _valid_int(data.get("waiters"),1,STAFF_CAPS.waiter) or not _valid_int(data.get("cleaners"),1,STAFF_CAPS.cleaner):return _fail("Invalid saved staff counts")
		var money_codec=RuntimeCodec.new()
		if not money_codec._number(data.get("payroll_elapsed"),0,59.9999999) or not money_codec._number(data.get("payroll_accrued"),0,1000) or not _valid_int(data.get("wages_due"),0,1000000000) or not _valid_int(data.get("total_wages_paid"),0,1000000000):return _fail("Invalid saved payroll")
		saved_waiters=int(data.waiters);saved_cleaners=int(data.cleaners);saved_payroll_elapsed=float(data.payroll_elapsed);saved_payroll_accrued=float(data.payroll_accrued);saved_wages_due=int(data.wages_due);saved_total_wages_paid=int(data.total_wages_paid)
	var saved_cashiers=0;var saved_checkout_pending=true
	if SaveContract.has_checkout(int(data.version)):
		if not _valid_int(data.get("cashiers"),0,1) or not data.get("included_checkout_pending") is bool:return _fail("Invalid included cashier state")
		saved_cashiers=int(data.cashiers);saved_checkout_pending=bool(data.included_checkout_pending)
		if saved_checkout_pending!=(saved_cashiers==0):return _fail("Cashier deployment disagrees with entitlement")
	var saved_duty={"chef":int(data.cooks),"waiter":saved_waiters,"cleaner":saved_cleaners};var saved_targets=saved_duty.duplicate()
	if SaveContract.has_checkout(int(data.version)):saved_duty["cashier"]=saved_cashiers;saved_targets["cashier"]=saved_cashiers
	if int(data.version)>=10:
		for key in ["duty_targets","duty_counts"]:
			if not data.get(key) is Dictionary or data[key].size()!=(4 if SaveContract.has_checkout(int(data.version)) else 3):return _fail("Invalid saved shifts")
			for role in saved_duty:
				if not _valid_int(data[key].get(role),0 if role=="cashier" else 1,int(saved_duty[role])):return _fail("Invalid saved shift count")
		for role in saved_duty:
			if int(data.duty_counts[role])<int(data.duty_targets[role]):return _fail("Missing active shift worker")
		saved_duty=data.duty_counts.duplicate();saved_targets=data.duty_targets.duplicate()
	if not SaveContract.has_checkout(int(data.version)):saved_duty["cashier"]=0;saved_targets["cashier"]=0
	elif int(saved_duty.cashier)!=saved_cashiers or int(saved_targets.cashier)!=saved_cashiers:return _fail("Invalid cashier duty")
	if not data.get("items") is Array or data.items.size() > (118 if int(data.version)<6 else MAX_WIDTH*MAX_DEPTH-2):
		return _fail("Invalid saved furniture list")
	var saved_parcels: Array[String] = []
	if int(data.version) == 1:
		# Historical expansion meant the complete two-row strip, never one plot.
		if data.expanded:
			saved_parcels.assign(LEGACY_PARCEL_IDS)
	else:
		var valid_ids=LEGACY_PARCEL_IDS if int(data.version)<6 else (FRONT_PARCEL_IDS if int(data.version)<11 else (V11_PARCEL_IDS if int(data.version)<12 else PARCEL_IDS))
		if not data.get("owned_parcels") is Array or data.owned_parcels.size()>valid_ids.size():
			return _fail("Invalid saved plot ownership")
		for parcel_id in data.owned_parcels:
			if not parcel_id is String or not valid_ids.has(parcel_id) or saved_parcels.has(parcel_id):
				return _fail("Invalid or duplicate saved plot identity")
			saved_parcels.append(parcel_id)
		if bool(data.expanded) != (saved_parcels.size() == valid_ids.size()):
			return _fail("Saved plot ownership contradicts expansion status")
	saved_parcels.sort()
	if not _ownership_connected(saved_parcels):return _fail("Saved plots are disconnected")
	var saved_depth:int=(BASE_DEPTH if saved_parcels.is_empty() else 10) if int(data.version)<6 else _depth_for(saved_parcels)
	var validated: Array[Dictionary] = []
	var occupied: Dictionary = {}
	var ids: Dictionary = {}
	var highest_id := 0
	for raw in data.items:
		if not raw is Dictionary:
			return _fail("Invalid furniture entry")
		if not _valid_int(raw.get("id"), 1, 1000000000) or not raw.get("kind") is String or price_of(str(raw.kind)) < 0 or is_dining_product(str(raw.kind)):
			return _fail("Invalid furniture identity")
		if not _valid_int(raw.get("x"), 0, _width_for(saved_parcels)-1) or not _valid_int(raw.get("z"), 0, saved_depth - 1) or not _valid_int(raw.get("rot"), 0, 3):
			return _fail("Invalid furniture position")
		var point := Vector2i(int(raw.x), int(raw.z))
		if not _floor_owned_in(point, saved_parcels) or (int(data.version)<12 and not _legacy_floor_owned(point,saved_parcels,int(data.version))):
			return _fail("Saved furniture is on an unowned plot")
		if point == ENTRANCE or point == ENTRY_LANDING or occupied.has(point) or ids.has(int(raw.id)):
			return _fail("Overlapping furniture or blocked entrance in save")
		var item: Dictionary = {"id": int(raw.id), "kind": str(raw.kind), "x": int(raw.x), "z": int(raw.z), "rot": int(raw.rot)}
		if item.kind == "stove":
			if not _valid_int(raw.get("level", 1), 1, MAX_STOVE_LEVEL):
				return _fail("Invalid stove level")
			item["level"] = int(raw.get("level", 1))
		validated.append(item)
		occupied[point] = true
		ids[int(item.id)] = true
		highest_id = maxi(highest_id, int(item.id))
	var register_count=validated.filter(func(item):return item.kind=="register").size()
	if (not SaveContract.has_checkout(int(data.version)) and register_count!=0) or (SaveContract.has_checkout(int(data.version)) and register_count!=saved_cashiers):return _fail("Register count disagrees with deployment")
	if not _valid_int(data.get("next_item_id"), highest_id + 1, 1000000001):
		return _fail("Invalid saved furniture sequence")
	if not _layout_has_access(validated, saved_depth, saved_parcels):
		return _fail("Saved layout blocks access to service stations")
	var checked_walls=_validate_saved_walls(data,saved_parcels)
	if not checked_walls.ok:return _fail(str(checked_walls.error))
	var checked_floors=_validate_saved_floors(data,saved_parcels,str(checked_walls.floor_style))
	if not checked_floors.ok:return _fail(str(checked_floors.error))
	var checked_attachments=_validate_saved_attachments(data,checked_walls.walls)
	if not checked_attachments.ok:return _fail(str(checked_attachments.error))
	var saved_open=true
	var saved_bin_pending=not validated.any(func(item):return item.kind=="bin")
	var runtime_state={"customers":[],"service":{},"next_customer_id":1,"arrival_elapsed":0.0,"walking_customer_id":-1,"next_checkout_ticket":1}
	if int(data.version)>=3:
		if not data.get("operating_open") is bool or not data.get("included_bin_pending") is bool:return _fail("Invalid operating or included-equipment state")
		saved_open=bool(data.operating_open);saved_bin_pending=bool(data.included_bin_pending)
		var codec=RuntimeCodec.new()
		var checked=codec.validate(data.get("runtime"),validated,int(data.cooks),PHASES,int(data.version),{"chef":int(data.cooks),"waiter":saved_waiters,"cleaner":saved_cleaners,"cashier":saved_cashiers},saved_duty)
		if not checked.ok:return _fail("Invalid active service: "+str(checked.error))
		runtime_state=checked.state
	var queue_check=OutsideQueue.validate(data.get("outside_queue",{"format":OutsideQueue.FORMAT,"visitors":[]}),runtime_state.customers,int(runtime_state.next_customer_id))
	if not queue_check.ok:return _fail(str(queue_check.error))
	if not saved_open and queue_check.visitors.any(func(v):return v.phase=="outside_queue"):return _fail("Closed cafe has an active outside request")
	var parking_check=Parking.validate(data.get("parking",Parking.empty_state()),runtime_state.customers,queue_check.visitors,int(runtime_state.next_customer_id),saved_open)
	if not parking_check.ok:return _fail(str(parking_check.error))
	if saved_checkout_pending:
		for guest in runtime_state.customers:
			if str(guest.get("settlement_mode","legacy"))=="register":return _fail("Register-mode guest exists before cashier deployment")
	var saved_sets:Dictionary
	if int(data.version)>=7:saved_sets=DiningSets.validate(data.get("dining_sets"),validated,runtime_state.customers)
	else:saved_sets={"ok":true,"groups":DiningSets.migrate(validated,runtime_state.customers)}
	if not saved_sets.ok:return _fail(str(saved_sets.error))
	var checkout_state_error=Checkout.state_error(saved_checkout_pending,saved_cashiers,validated,runtime_state.customers,saved_targets,saved_duty)
	if checkout_state_error!="":return _fail(checkout_state_error)
	checkout_state_error=Checkout.staff_floor_error(self,runtime_state.service,saved_parcels,validated)
	if checkout_state_error!="":return _fail(checkout_state_error)
	var motion_error=_layout_motion_geometry_error(runtime_state.customers,validated,checked_walls.walls,saved_parcels,checked_attachments.attachments)
	if motion_error!="":return _fail("Invalid saved layout motion: "+motion_error)
	var saved_actors:Array=[]
	for actor in runtime_state.service.get("staff",[]):saved_actors.append(actor.pos)
	var egress_error=_wall_egress_error(checked_walls.walls,saved_actors,validated,saved_parcels,runtime_state.customers,checked_attachments.attachments)
	if egress_error!="" and allow_enclosed_staff and int(data.version)==SaveContract.CHECKOUT_INTRO_VERSION and egress_error=="This wall would seal a staff member away from every exit":
		# Explicit repair import only: preserve the historically enclosed worker,
		# while every entrance, guest, chair and opening check still runs.
		egress_error=_wall_egress_error(checked_walls.walls,[],validated,saved_parcels,runtime_state.customers,checked_attachments.attachments)
	if egress_error!="":return _fail("Invalid saved walls: "+egress_error)
	var actors=saved_actors.duplicate()
	for guest in runtime_state.customers:
		if str(guest.phase) not in ["dirty","cleaning"]:actors.append(Vector2(float(guest.x),float(guest.z)))
	var body_error=_opening_body_error(checked_walls.walls,checked_attachments.attachments,actors)
	if body_error!="":return _fail("Invalid saved walls: "+body_error)
	# Validate the saved layout as written first. Narrow only a matching free
	# starter when its new jambs leave every saved body and remaining route clear.
	checked_attachments.attachments=_align_saved_starter_door(checked_attachments.attachments,checked_walls.walls,runtime_state,validated,saved_parcels)
	finish_decoration_session()
	items = validated
	dining_sets.assign(saved_sets.groups)
	built_walls.assign(checked_walls.walls)
	wall_attachments.assign(checked_attachments.attachments);_next_wall_id=int(checked_walls.next_wall_id);_next_attachment_id=int(checked_attachments.next_attachment_id)
	floor_finishes=checked_floors.finishes
	floor_style=checked_walls.floor_style;shell_material=checked_walls.shell_material;shell_products=checked_walls.shell_products
	shell_segment_products=checked_walls.shell_segment_products
	wall_actor_positions.clear()
	guest_obstacle_positions.clear();checkout_staff_claims.clear()
	coins = int(data.coins)
	owned_parcels = saved_parcels
	_sync_floor_bounds()
	cooks = int(data.cooks);waiters=saved_waiters;cleaners=saved_cleaners;cashiers=saved_cashiers
	included_checkout_pending=saved_checkout_pending;next_checkout_ticket=int(runtime_state.get("next_checkout_ticket",1))
	duty_targets=saved_targets;duty_counts=saved_duty
	payroll_elapsed=saved_payroll_elapsed;payroll_accrued=saved_payroll_accrued;wages_due=saved_wages_due;total_wages_paid=saved_total_wages_paid
	served = int(data.served)
	total_earned = int(data.total_earned)
	total_cleaned = int(data.total_cleaned)
	_next_item_id = int(data.next_item_id)
	customers.assign(runtime_state.customers)
	outside_queue.assign(queue_check.visitors)
	parking_owned=parking_check.state.owned;parking_paid_cost=int(parking_check.state.paid_cost);parking_visits.assign(parking_check.state.visits)
	service_snapshot=runtime_state.service
	operating_open=saved_open;included_bin_pending=saved_bin_pending
	loaded_save_version=int(data.version)
	_next_customer_id=int(runtime_state.next_customer_id)
	_arrival_elapsed=float(runtime_state.arrival_elapsed)
	_walking_customer_id=int(runtime_state.walking_customer_id)
	last_error=""
	last_event="Cafe loaded · active service preserved" if int(data.version)>=3 else "Legacy cafe loaded · layout and wallet preserved"
	_notify()
	return true


func _valid_int(value: Variant, low: int, high: int) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number >= low and number <= high and floor(number) == number


func _fail(message: String) -> bool:
	last_error = message
	return false


func _notify() -> void:
	revision += 1
	changed.emit()


# Player-built walls: explicit purchases, independent of land ownership.
func wall_price(height: String) -> int:
	return int(WallGeometry.PRICES.get(height,-1))

func get_wall(key: String) -> Dictionary:
	for wall in built_walls:
		if WallGeometry.key_of(wall)==key:return wall
	return {}

func built_wall_segments() -> Array[Dictionary]:
	return built_walls.duplicate(true)

func _fixed_edge_blocked(a:Vector2i,b:Vector2i,openings=null,walls=null)->bool:
	if absi(a.x-b.x)+absi(a.y-b.y)!=1:return false
	var on_back=a.y!=b.y and mini(a.y,b.y)==-1 and maxi(a.y,b.y)==0 and a.x>=0 and a.x<BASE_WIDTH
	var on_west=a.x!=b.x and mini(a.x,b.x)==-1 and maxi(a.x,b.x)==0 and a.y>=0 and a.y<BASE_DEPTH
	if not on_back and not on_west:return false
	# Live navigation repeats the same shell edges across many BFS expansions.
	# Revision is the same conservative invalidation used by the wall indexes.
	# Proposed edit/save-validation geometry must always resolve its own inputs.
	var live=openings==null and walls==null
	var key=Vector2i(a.x,0) if on_back else Vector2i(-1,a.y)
	if live:
		if _fixed_edge_revision!=revision:
			_fixed_edges.clear();_fixed_edge_revision=revision
		if _fixed_edges.has(key):return _fixed_edges[key]
	var effective_walls:Array=built_walls if walls==null else walls
	var shell=OpeningGeometry.shell_hosts(shell_products,effective_walls)
	var host=shell[0] if on_back else shell[1]
	var blocked=not (on_west and a.y>=int(host.b.y)) and not OpeningGeometry.point_in_door((cell_center(a)+cell_center(b))*.5,host,effective_walls,wall_attachments if openings==null else openings,.23)
	if live:_fixed_edges[key]=blocked
	return blocked

func _built_edge_blocked(a:Vector2i,b:Vector2i,walls:Array,openings=null)->bool:
	var key=WallGeometry.edge_between(a,b)
	if key=="":return false
	for wall in walls:
		if WallGeometry.key_of(wall)==key:
			return not OpeningGeometry.point_in_door((cell_center(a)+cell_center(b))*.5,OpeningGeometry.wall_host(wall),walls,wall_attachments if openings==null else openings,.23)
	return false

func edge_blocked(a:Vector2i,b:Vector2i)->bool:
	if _fixed_edge_blocked(a,b):return true
	if _wall_index_revision!=revision:
		_wall_index.clear()
		for wall in built_walls:
			var sides=WallGeometry.adjacent_cells(wall)
			if _built_edge_blocked(sides[0],sides[1],built_walls):_wall_index[WallGeometry.key_of(wall)]=true
		_wall_index_revision=revision
	return _wall_index.has(WallGeometry.edge_between(a,b))

func segment_blocked(a:Vector2,b:Vector2)->bool:
	if _collision_revision!=revision:
		_solid_wall_segments.clear()
		for host in OpeningGeometry.hosts(built_walls,shell_products):
			_solid_wall_segments.append_array(OpeningGeometry.solid_segments(host,built_walls,wall_attachments))
		_collision_revision=revision
	for segment in _solid_wall_segments:
		if OpeningGeometry.crosses(segment,a,b):return true
	return false

func workface_accessible(item: Dictionary,reverse: bool=false) -> bool:
	if item.is_empty():return false
	if str(item.get("kind",""))=="bin":return not bin_service_cells(item).is_empty()
	var copy:=item.duplicate()
	if reverse:copy.rot=posmod(int(copy.get("rot",0))+2,4)
	return _workface_open_in(copy,items)

func _wall_edge_error(wall:Dictionary,ownership:Array) -> String:
	if not WallGeometry.valid_shape(wall,MAX_WIDTH,MAX_DEPTH):return "Choose a valid one-tile edge, height and wallpaper"
	var sides:=WallGeometry.adjacent_cells(wall)
	if not _floor_owned_in(sides[0],ownership) and not _floor_owned_in(sides[1],ownership):return "Buy the adjacent plot before building a wall"
	if Footprint.is_shell_edge(wall):return "The original cafe shell is already here · attach a door/window or choose wallpaper"
	return ""

func _furniture_actor_positions(extra:Array) -> Array[Vector2]:
	# Keep the legacy model-only hook, but live edit callers must supply current
	# simulation positions on every preview and commit; runtime never fills it.
	var result:Array[Vector2]=wall_actor_positions.duplicate()
	for point in extra:
		if point is Vector2 and point.is_finite():result.append(point)
	return result

func _furniture_actor_error(parts:Array,layout:Array,actor_positions:Array) -> String:
	var actors:=_furniture_actor_positions(actor_positions)
	if actors.is_empty():return ""
	# Authoritative body clearance also covers selected-item R rotation, which
	# does not pass through the drag preview. Rugs are still walkable.
	for part in parts:
		if str(part.kind)=="rug":continue
		var minimum:=Vector2(int(part.x),int(part.z));var maximum:=minimum+Vector2.ONE
		for point in actors:
			if point.distance_squared_to(point.clamp(minimum,maximum))<STAFF_PLACEMENT_RADIUS*STAFF_PLACEMENT_RADIUS:
				return "A staff member is using part of this space"
	# Staff cannot use the x=0 arrival strip or unowned exterior grass to
	# bypass furniture. Their escape is an indoor route to the service floor
	# at ENTRY_LANDING, even when the pocket touches a public outdoor edge.
	var reachable:=_furniture_actor_component(ENTRY_LANDING,layout)
	var previous_reachable:Dictionary={}
	var checked_previous:=false
	for point in actors:
		var cell:=Vector2i(floori(point.x),floori(point.y))
		if not _floor_owned_in(cell,owned_parcels) or reachable.has(cell):continue
		if not checked_previous:
			previous_reachable=_furniture_actor_component(ENTRY_LANDING,items);checked_previous=true
		if previous_reachable.has(cell):
			return "This layout would seal a staff member away from every exit"
		# A legacy save can already contain a trapped worker. Allow opening its
		# enclosure and unrelated edits, but do not take away more of its aisle.
		var before:=_furniture_actor_component(cell,items)
		var after:=_furniture_actor_component(cell,layout)
		for accessible in before:
			if not after.has(accessible):return "Keep the trapped staff member's remaining walkway clear"
	return ""

func _furniture_actor_component(start:Vector2i,layout:Array,walls=null,openings=null) -> Dictionary:
	var blocked:Dictionary={}
	for item in layout:
		if str(item.kind)!="rug":blocked[Vector2i(int(item.x),int(item.z))]=true
	if start.x<1 or blocked.has(start) or not is_floor_owned(start):return {}
	var wall_edges:Dictionary={}
	if walls!=null:
		for wall in walls:
			var sides=WallGeometry.adjacent_cells(wall)
			if _built_edge_blocked(sides[0],sides[1],walls,openings):wall_edges[WallGeometry.key_of(wall)]=true
	var reached:Dictionary={start:true}
	var queue:Array[Vector2i]=[start];var cursor:=0
	while cursor<queue.size():
		var cell:=queue[cursor];cursor+=1
		for direction in DIRECTIONS:
			var next:Vector2i=cell+direction
			if next.x<1 or reached.has(next) or blocked.has(next) or not is_floor_owned(next):continue
			var blocked_edge=edge_blocked(cell,next) if walls==null else (_fixed_edge_blocked(cell,next,openings,walls) or wall_edges.has(WallGeometry.edge_between(cell,next)))
			if blocked_edge:continue
			reached[next]=true;queue.append(next)
	return reached

func _wall_actor_list(extra:Array) -> Array[Vector2]:
	var result:Array[Vector2]=wall_actor_positions.duplicate()
	for point in extra:
		if point is Vector2 and point.is_finite():result.append(point)
	for guest in customers:
		if str(guest.phase) not in ["dirty","cleaning"]:result.append(Vector2(float(guest.x),float(guest.z)))
	return result

func _wall_reachable(walls:Array,layout:Array,ownership:Array,openings=null) -> Dictionary:
	# Start on every still-open public edge. Locked parcels are not pavement.
	var blocked:Dictionary={}
	for item in layout:
		if str(item.kind)!="rug":blocked[Vector2i(int(item.x),int(item.z))]=true
	var keys:Dictionary={}
	for wall in walls:
		var sides=WallGeometry.adjacent_cells(wall)
		if _built_edge_blocked(sides[0],sides[1],walls,openings):keys[WallGeometry.key_of(wall)]=true
	var reachable:Dictionary={}
	var queue:Array[Vector2i]=[]
	for z in range(MAX_DEPTH):
		for x in range(MAX_WIDTH):
			var cell:=Vector2i(x,z)
			if not _floor_owned_in(cell,ownership) or blocked.has(cell):continue
			for direction in DIRECTIONS:
				var outside:Vector2i=cell+direction
				if _public_exterior_cell(outside,ownership) and not _fixed_edge_blocked(cell,outside,openings,walls) and not keys.has(WallGeometry.edge_between(cell,outside)):
					reachable[cell]=true;queue.append(cell);break
	var cursor:=0
	while cursor<queue.size():
		var cell:=queue[cursor];cursor+=1
		for direction in DIRECTIONS:
			var next:Vector2i=cell+direction
			if reachable.has(next) or blocked.has(next) or not _floor_owned_in(next,ownership) or keys.has(WallGeometry.edge_between(cell,next)):continue
			reachable[next]=true;queue.append(next)
	return reachable

func _wall_egress_error(walls:Array,actors:Array,layout:Array,ownership:Array,guests:Array,openings=null) -> String:
	var motion_error=_layout_motion_geometry_error(guests,layout,walls,ownership,wall_attachments if openings==null else openings)
	if motion_error!="":return motion_error
	var checkout_error=Checkout.layout_error(self,layout,walls,ownership,guests,openings)
	if checkout_error!="":return checkout_error
	var reachable:=_wall_reachable(walls,layout,ownership,openings)
	var reserved_error:=_reserved_chair_egress_error(walls,layout,guests,reachable,openings)
	if reserved_error!="":return reserved_error
	if not reachable.has(ENTRY_LANDING):return "Keep a reachable open entrance and exit for the cafe"
	for point in actors:
		var cell:=Vector2i(floori(point.x),floori(point.y))
		if _floor_owned_in(cell,ownership) and not reachable.has(cell):
			var seated:=false
			for guest in guests:
				if str(guest.phase) in ["dirty","cleaning"]:continue
				var guest_point=Vector2(float(guest.x),float(guest.z))
				# The renderer nudges a seated body .12 tiles toward its table.
				# Its extra collision sample is the same diner, not a worker
				# trapped inside the non-walkable chair tile. Guest egress is
				# checked separately below and still needs a clear adjacent aisle.
				var same_seat=bool(guest.get("seated",false)) and cell==Vector2i(floori(guest_point.x),floori(guest_point.y)) and guest_point.distance_to(point)<=.15
				if guest_point.distance_to(point)<.01 or same_seat:seated=true;break
			if not seated:return "This wall would seal a staff member away from every exit"
	for guest in guests:
		if str(guest.phase) in ["dirty","cleaning"] or bool(guest.get("withdrawn",false)):continue
		var position:=Vector2i(floori(float(guest.x)),floori(float(guest.z)))
		if not _floor_owned_in(position,ownership):continue
		if reachable.has(position):continue
		# A seat is a blocked furniture tile; a legal un-walled adjacent aisle
		# suffices. A walking guest, by contrast, must itself be on reachable floor.
		var chair:Dictionary={}
		for item in layout:
			if int(item.id)==int(guest.chair_id):chair=item;break
		var has_exit:=false
		if not chair.is_empty() and position==Vector2i(int(chair.x),int(chair.z)):
			for direction in DIRECTIONS:
				if reachable.has(position+direction) and not _built_edge_blocked(position,position+direction,walls,openings):has_exit=true;break
		if not has_exit:return "This wall would seal a guest away from every exit"
	return ""

func _wall_candidate_error(wall:Dictionary,actors:Array,ignore_key:String="") -> String:
	if not wall.has("id"):wall["id"]=_next_wall_id
	var reason:=_wall_edge_error(wall,owned_parcels)
	if reason!="":return reason
	var key:=WallGeometry.key_of(wall)
	if key!=ignore_key and not get_wall(key).is_empty():return "A wall already occupies this edge"
	for point in actors:
		if WallGeometry.body_touches(wall,point):return "An actor is crossing this edge · wait until the edge is clear"
	if key!=ignore_key:
		for group in dining_sets:
			var table=get_item(int(group.table_id));var seat=get_item(int(group.seat_id))
			if not table.is_empty() and not seat.is_empty() and WallGeometry.edge_between(Vector2i(int(table.x),int(table.z)),Vector2i(int(seat.x),int(seat.z)))==key:return "A wall cannot split a table set"
	var sides:=WallGeometry.adjacent_cells(wall)
	for guest in customers:
		if str(guest.phase) in ["dirty","cleaning"]:continue
		var table:=get_item(int(guest.table_id));var chair:=get_item(int(guest.chair_id))
		if not table.is_empty() and not chair.is_empty() and sides.has(Vector2i(int(table.x),int(table.z))) and sides.has(Vector2i(int(chair.x),int(chair.z))):return "A guest is using this dining edge · wait until the table is clear"
	var proposed:Array=[]
	for current in built_walls:
		if WallGeometry.key_of(current)!=ignore_key:proposed.append(current)
	proposed.append(wall)
	var hosted_error=_attachment_layout_error(proposed,wall_attachments)
	if hosted_error!="":return hosted_error
	var stove_error=_stove_wall_edit_error(proposed)
	if stove_error!="":return stove_error
	var chair_error:=_chair_egress_error(proposed,items,owned_parcels,customers)
	if chair_error!="":return chair_error
	return _wall_egress_error(proposed,actors,items,owned_parcels,customers)

func _stove_wall_edit_error(walls:Array,openings=null)->String:
	var issue=LayoutAccess.introduced_stove_wall(self,walls,openings)
	return "" if issue.is_empty() else str(issue.reason)

func can_place_wall(axis:String,x:int,z:int,height:String="full",material:String="sage_panels",actor_positions:Array=[]) -> bool:
	last_error=""
	var reason:=_wall_candidate_error(WallGeometry.make(axis,x,z,height,material),_wall_actor_list(actor_positions))
	return true if reason=="" else _fail(reason)

func place_wall(axis:String,x:int,z:int,height:String="full",material:String="sage_panels",actor_positions:Array=[]) -> bool:
	if not can_place_wall(axis,x,z,height,material,actor_positions):return false
	var price:=wall_price(height)
	if coins<price:return _fail("Not enough coins · this wall needs %s"%Money.amount(price))
	var wall=WallGeometry.make(axis,x,z,height,material);wall["id"]=_next_wall_id;_next_wall_id+=1
	built_walls.append(wall);coins-=price
	record_decoration_build_purchase("wall",int(wall.id),price)
	last_error="";last_event="Built %s wall · −%s coins"%[height,Money.amount(price)]
	_notify();return true

func wall_replacement_quote(key:String,height:String,material:String,actor_positions:Array=[]) -> Dictionary:
	if key in OpeningGeometry.SHELL_HOSTS:return _shell_replacement_quote(key,height,material)
	var segment=ShellSegments.parse_key(key)
	if not segment.is_empty():return ShellSegments.quote(ShellSegments.state(shell_products,shell_segment_products),built_walls,wall_attachments,segment.root_id,int(segment.index),height,material,coins)
	# Quoting never changes the wall, attachments, wallet, IDs or revision.
	var wall:=get_wall(key)
	var quote={"valid":false,"new_cost":wall_price(height),"refund":0,"net":0,"reason":""}
	if wall.is_empty():quote.reason="Select a player-built wall first";return quote
	quote.refund=int(wall_price(str(wall.height))/2)
	quote.net=int(quote.new_cost)-int(quote.refund)
	if height not in WallGeometry.HEIGHTS:quote.reason="Choose half or full wall height";return quote
	if material not in WallGeometry.MATERIALS:quote.reason="Choose a listed wallpaper";return quote
	if wall.height==height and wall.material==material:quote.reason="This wall already has this style";return quote
	var proposed_wall=wall.duplicate(true);proposed_wall.height=height;proposed_wall.material=material
	var proposed:Array=[]
	for current in built_walls:proposed.append(proposed_wall if WallGeometry.key_of(current)==key else current)
	# Keep the same host identity, but validate every host (including a wide
	# opening spanning two segments) before touching either model or wallet.
	var reason="" if Footprint.is_extension_wall(wall) else _wall_edge_error(proposed_wall,owned_parcels)
	if reason=="":reason=_attachment_layout_error(proposed,wall_attachments)
	if reason=="":reason=_stove_wall_edit_error(proposed)
	if reason=="":reason=_chair_egress_error(proposed,items,owned_parcels,customers)
	if reason=="":reason=_wall_egress_error(proposed,_wall_actor_list(actor_positions),items,owned_parcels,customers)
	if reason!="":quote.reason=reason;return quote
	if coins<int(quote.net):quote.reason="Not enough coins · replacement needs "+Money.amount(int(quote.net))+" after refund";return quote
	quote.valid=true
	return quote

func _shell_replacement_quote(_key:String,_height:String,_material:String)->Dictionary:
	return {"valid":false,"new_cost":0,"refund":0,"net":0,"units":0,"reason":"Select one wall tile"}

func can_replace_wall(key:String,height:String,material:String,actor_positions:Array=[]) -> bool:
	var quote=wall_replacement_quote(key,height,material,actor_positions)
	last_error="" if quote.valid else str(quote.reason)
	return bool(quote.valid)

func replace_wall(key:String,height:String,material:String,actor_positions:Array=[]) -> bool:
	var quote=wall_replacement_quote(key,height,material,actor_positions)
	if not quote.valid:return _fail(str(quote.reason))
	var segment=ShellSegments.parse_key(key)
	if not segment.is_empty():
		var cost=int(quote.new_cost)
		shell_segment_products[key]={"height":height,"material":material,"paid_cost":cost,"refund_credit":cost/2}
	else:
		var wall=get_wall(key);wall.height=height;wall.material=material
		# Replacement keeps its existing half credit; only the new product receipt remains.
		record_decoration_build_purchase("wall",int(wall.id),int(quote.new_cost))
	# One commit and one notification. There is no intermediate sale, missing
	# host, temporary refund or ID change for a failed/cancelled replacement.
	coins-=int(quote.net)
	last_error="";last_event="Wall replaced · new %s · refund %s · pay %s"%[Money.amount(int(quote.new_cost)),Money.amount(int(quote.refund)),Money.amount(int(quote.net))]
	_notify();return true

func can_remove_wall(key:String) -> bool:
	last_error=""
	var wall:=get_wall(key)
	if wall.is_empty():return _fail("Select a player-built wall first")
	if not attachments_for_wall(int(wall.id)).is_empty():return _fail("Remove or move the attached door/window before removing this wall")
	return true

func remove_wall(key:String,refund:bool=true) -> bool:
	if not can_remove_wall(key):return false
	var wall:=get_wall(key)
	var returned:=wall_refund(key) if refund else 0
	decoration_build_purchases.erase("wall:"+str(int(wall.id)))
	built_walls.erase(wall);coins+=returned
	last_error="";last_event="Removed wall · +%s coins"%Money.amount(returned)
	_notify();return true

func move_wall(key:String,axis:String,x:int,z:int,actor_positions:Array=[]) -> bool:
	var wall:=get_wall(key)
	if wall.is_empty():return _fail("Select a player-built wall first")
	for attachment in attachments_for_wall(int(wall.id)):
		if OpeningGeometry.resolve_host(attachment.host_id,built_walls).wall_ids.size()>1:return _fail("Move the wide doorway before moving one of its supporting wall segments")
	var proposed:=WallGeometry.make(axis,x,z,str(wall.height),str(wall.material));proposed["id"]=int(wall.id)
	var reason:=_wall_candidate_error(proposed,_wall_actor_list(actor_positions),key)
	if reason!="":return _fail(reason)
	wall.axis=axis;wall.x=x;wall.z=z
	last_error="";last_event="Moved wall"
	_notify();return true

func paint_wall(key:String,material:String) -> bool:
	var wall:=get_wall(key)
	if wall.is_empty():return _fail("Select a player-built wall first")
	if material not in WallGeometry.MATERIALS:return _fail("Choose a listed wallpaper")
	if wall.material==material:last_error="";return true
	wall.material=material
	last_error="";last_event="Wallpaper changed"
	_notify();return true

func set_wall_height(key:String,height:String,actor_positions:Array=[]) -> bool:
	var wall:=get_wall(key)
	if wall.is_empty():return _fail("Select a player-built wall first")
	if height not in WallGeometry.HEIGHTS:return _fail("Choose half or full wall height")
	if wall.height==height:last_error="";return true
	if height=="half" and not attachments_for_wall(int(wall.id)).is_empty():return _fail("Remove or move the attached door/window before lowering its wall")
	var difference:=wall_price(height)-wall_price(str(wall.height))
	if difference>coins:return _fail("Not enough coins · taller wall needs %s"%Money.amount(difference))
	# Height changes never move a solid edge or alter routes; no unsafe new
	# footprint. Downgrading refunds the exact difference, so cycling is neutral.
	wall.height=height;coins-=difference
	var receipt="wall:"+str(int(wall.id))
	if decoration_session_active and decoration_build_purchases.has(receipt):decoration_build_purchases[receipt]=int(decoration_build_purchases[receipt])+difference
	last_error="";last_event="Wall height changed · %s coins"%Money.amount(-difference)
	_notify();return true

static func _floor_key(cell:Vector2i)->String:return "%d,%d"%[cell.x,cell.y]

func floor_style_at(cell:Vector2i)->String:
	return str(floor_finishes.get(_floor_key(cell),{}).get("style","")) if is_floor_owned(cell) else ""

func starter_floor_gap_cells() -> Array[Vector2i]:
	# Explicit repair only: old starters owned row 8 but installed just rows 0..7.
	# Existing finishes, including deliberately chosen custom tiles, win.
	var cells:Array[Vector2i]=[]
	for x in range(BASE_WIDTH):
		var cell=Vector2i(x,ORIGINAL_BASE_DEPTH)
		if is_floor_owned(cell) and not floor_finishes.has(_floor_key(cell)):cells.append(cell)
	return cells

func repair_starter_floor_gap() -> int:
	# No load-time call. The user-facing action must opt in and save normally.
	var cells=starter_floor_gap_cells()
	if cells.is_empty():return 0
	for cell in cells:floor_finishes[_floor_key(cell)]={"style":"warm_oak","paid_cost":0}
	last_error="";last_event="Starter floor completed · %d included tiles"%cells.size()
	_notify()
	return cells.size()

func floor_price(style:String)->int:return int(FLOOR_COSTS.get(style,-1))

func floor_quote(cell:Vector2i,style:String)->Dictionary:
	var new_cost=floor_price(style)
	var previous=floor_finishes.get(_floor_key(cell),{})
	var refund=int(int(previous.get("paid_cost",0))/2)
	var quote={"valid":false,"new_cost":maxi(0,new_cost),"refund":refund,"net":maxi(0,new_cost)-refund,"reason":""}
	if style not in FLOOR_STYLES:quote.reason="Choose a listed floor finish"
	elif not is_floor_owned(cell):quote.reason="Buy this plot before adding flooring"
	elif floor_style_at(cell)==style:
		quote.reason="This tile already has that flooring";quote.new_cost=0;quote.refund=0;quote.net=0
	elif coins<int(quote.net):quote.reason="Not enough coins · %s needed"%Money.amount(int(quote.net))
	else:quote.valid=true
	return quote

func can_place_floor(cell:Vector2i,style:String)->bool:
	var quote=floor_quote(cell,style)
	if not quote.valid:return _fail(str(quote.reason))
	last_error="";return true

func place_floor(cell:Vector2i,style:String)->bool:
	var quote=floor_quote(cell,style)
	if not quote.valid:return _fail(str(quote.reason))
	coins-=int(quote.net);floor_finishes[_floor_key(cell)]={"style":style,"paid_cost":int(quote.new_cost)}
	last_error="";last_event="Flooring placed · −%s"%Money.amount(int(quote.net));_notify();return true

func set_floor_style(style:String) -> bool:
	if style not in FLOOR_STYLES:return _fail("Choose a listed floor finish")
	if floor_style==style:last_error="";return true
	floor_style=style;last_error="";last_event="Flooring selected · choose an owned tile"
	_notify();return true

func _legacy_floor_owned(cell:Vector2i,ownership:Array,version:int)->bool:
	# Before v12 decorative floor followed the old physical footprint. Keep
	# those exact cells, never shift installed finishes with the parcel ledger.
	if cell.x<0 or cell.y<0:return false
	if cell.x<BASE_WIDTH:
		if cell.y<ORIGINAL_BASE_DEPTH:return true
		var old_limit=10 if version<6 else 17
		if cell.y>=old_limit:return false
		var index=int((cell.y-ORIGINAL_BASE_DEPTH)/PARCEL_DEPTH)*PARCEL_COLUMNS+int(cell.x/PARCEL_WIDTH)
		return ownership.has(FRONT_PARCEL_IDS[index])
	if version<11 or cell.x>=MAX_WIDTH or cell.y>=RIGHT_PARCEL_DEPTH:return false
	var index=int((cell.x-BASE_WIDTH)/PARCEL_WIDTH)*RIGHT_PARCEL_COLUMNS+int(cell.y/PARCEL_DEPTH)
	return ownership.has(RIGHT_PARCEL_IDS[index])

func _validate_saved_floors(data:Dictionary,ownership:Array,legacy_style:String)->Dictionary:
	if data.has("starter_geometry_version") and not _valid_int(data.starter_geometry_version,Footprint.SAVE_REVISION,Footprint.SAVE_REVISION):return {"ok":false,"error":"Invalid starter geometry version"}
	var finishes={}
	if int(data.version)<12:
		for z in range(MAX_DEPTH):
			for x in range(MAX_WIDTH):
				var cell=Vector2i(x,z)
				if _legacy_floor_owned(cell,ownership,int(data.version)):finishes[_floor_key(cell)]={"style":legacy_style,"paid_cost":0}
		_complete_legacy_starter_floor(finishes,data)
		return {"ok":true,"finishes":finishes}
	var failed={"ok":false,"error":"Invalid saved flooring"}
	if not data.get("floor_finishes") is Dictionary or data.floor_finishes.size()>MAX_WIDTH*MAX_DEPTH:return failed
	for key in data.floor_finishes:
		if not key is String or not data.floor_finishes[key] is Dictionary:return failed
		var tile=data.floor_finishes[key]
		if tile.size()!=2 or tile.get("style") not in FLOOR_STYLES or not _valid_int(tile.get("paid_cost"),0,1000000):return failed
		if int(tile.paid_cost) not in [0,floor_price(str(tile.style))]:return failed
		var parts=key.split(",")
		if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return failed
		var cell=Vector2i(int(parts[0]),int(parts[1]))
		if _floor_key(cell)!=key or not _floor_owned_in(cell,ownership):return failed
		finishes[key]={"style":str(tile.style),"paid_cost":int(tile.paid_cost)}
	_complete_legacy_starter_floor(finishes,data)
	return {"ok":true,"finishes":finishes}

func _complete_legacy_starter_floor(finishes:Dictionary,data:Dictionary)->void:
	# Validate into a new dictionary first; failed loads never alter live state
	# or the imported file. A saved revision makes the repair one-time.
	if data.has("starter_geometry_version"):return
	for z in range(Footprint.LEGACY_DEPTH,Footprint.DEPTH):
		for x in range(Footprint.WIDTH):
			var key=_floor_key(Vector2i(x,z))
			if not finishes.has(key):finishes[key]={"style":"warm_oak","paid_cost":0}

func set_shell_material(_material:String) -> bool:
	return _fail("Select one wall tile")

func _wall_operational_warnings(walls:Array) -> Dictionary:
	var warnings:Dictionary={}
	var reachable:=_wall_reachable(walls,items,owned_parcels)
	for item in items:
		var cell:=Vector2i(int(item.x),int(item.z))
		if str(item.kind)=="table":
			var usable=false
			var guest_side=_table_guest_direction_in(item,items)
			for direction in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
				var side:Vector2i=cell+direction
				if direction!=guest_side and _table_side_open_in(side,items) and not _built_edge_blocked(cell,side,walls) and reachable.has(side):usable=true;break
			if not usable:warnings[str(item.id)+":front"]="Table service sides blocked: staff will wait until you move the wall"
		elif str(item.kind)=="bin":
			var usable=false
			for direction in DIRECTIONS:
				var side:Vector2i=cell+direction
				if _table_side_open_in(side,items) and not _fixed_edge_blocked(cell,side,null,walls) and not _built_edge_blocked(cell,side,walls) and reachable.has(side):usable=true;break
			if not usable:warnings[str(item.id)+":sides"]="Bin sides blocked: staff will wait until you clear an adjacent side"
		elif str(item.kind) in ["stove","beverage","sink","counter"]:
			var front:=workface_cell(item)
			if _built_edge_blocked(cell,front,walls) or not reachable.has(front):warnings[str(item.id)+":front"]="%s front blocked: staff will wait until you move the wall"%str(item.kind).capitalize()
			if str(item.kind)=="counter":
				var rear:Vector2i=cell*2-front
				if _built_edge_blocked(cell,rear,walls) or not reachable.has(rear):warnings[str(item.id)+":rear"]="Pass counter back blocked: chef will wait until you move the wall"
	return warnings

func wall_placement_warning(axis:String,x:int,z:int,height:String="full",material:String="sage_panels",_actor_positions:Array=[]) -> String:
	var wall:=WallGeometry.make(axis,x,z,height,material);wall["id"]=_next_wall_id
	if _wall_edge_error(wall,owned_parcels)!="":return ""
	var proposed:Array=built_walls.duplicate();proposed.append(wall)
	var before:=_wall_operational_warnings(built_walls)
	var after:=_wall_operational_warnings(proposed)
	for key in after:
		if not before.has(key):return str(after[key])
	return ""

func _validate_saved_walls(data:Dictionary,ownership:Array) -> Dictionary:
	var walls:Array[Dictionary]=[]
	var fail_result:Dictionary={"ok":false,"error":"Invalid saved wall or finish data"}
	if int(data.version)>=4 and (not data.has("wall_format") or not data.has("built_walls") or not data.has("floor_style") or not data.has("shell_material")):return fail_result
	if data.has("wall_format") and (not _valid_int(data.wall_format,1,2)):return fail_result
	if int(data.get("wall_format",1))==2 and int(data.version)!=SAVE_VERSION:return fail_result
	if data.has("built_walls") and (not data.built_walls is Array or data.built_walls.size()>(262 if int(data.version)<6 else MAX_WIDTH*(MAX_DEPTH+1)+(MAX_WIDTH+1)*MAX_DEPTH)):return fail_result
	if data.has("built_walls") and not data.has("wall_format"):return fail_result
	var keys:Dictionary={};var wall_ids={};var highest_wall_id=0
	for raw in data.get("built_walls",[]):
		if not WallGeometry.valid_shape(raw,MAX_WIDTH,MAX_DEPTH):return fail_result
		var wall:=WallGeometry.make(str(raw.axis),int(raw.x),int(raw.z),str(raw.height),str(raw.material))
		var edge_error=_wall_edge_error(wall,ownership)
		# Preserve historical doorway overlays and player walls on the former
		# starter gap. The latter replace, rather than overlap, the default edge.
		var legacy_overlay=(wall.axis=="z" and int(wall.x)==0 and int(wall.z)==5) or Footprint.is_extension_wall(wall)
		if (edge_error!="" and not legacy_overlay) or keys.has(WallGeometry.key_of(wall)):return fail_result
		var id=int(raw.get("id",walls.size()+1))
		if int(data.version)>=5 and not _valid_int(raw.get("id"),1,1000000000):return fail_result
		if wall_ids.has(id):return fail_result
		wall["id"]=id;wall_ids[id]=true;highest_wall_id=maxi(highest_wall_id,id)
		keys[WallGeometry.key_of(wall)]=true;walls.append(wall)
	var saved_floor=data.get("floor_style","warm_oak")
	var saved_shell=data.get("shell_material","original")
	if saved_floor not in FLOOR_STYLES or (saved_shell!="original" and saved_shell not in WallGeometry.MATERIALS):return fail_result
	var products=_validated_shell_products(data)
	if products.is_empty():return fail_result
	var segments=ShellSegments.from_save(data,walls,products)
	if not segments.ok:return {"ok":false,"error":str(segments.error)}
	var next_id=highest_wall_id+1
	if int(data.version)>=5:
		if not _valid_int(data.get("next_wall_id"),next_id,1000000001):return fail_result
		next_id=int(data.next_wall_id)
	return {"ok":true,"walls":walls,"floor_style":saved_floor,"shell_material":saved_shell,"shell_products":products,"shell_segment_products":segments.state.segments,"next_wall_id":next_id}

func _validated_shell_products(data:Dictionary)->Dictionary:
	var legacy=str(data.get("shell_material","original"))
	if not data.has("shell_products"):
		return OpeningGeometry.initial_shell_products(legacy) if int(data.get("version",0))<=10 else {}
	var raw=data.shell_products
	if not raw is Dictionary or raw.size()!=OpeningGeometry.SHELL_HOSTS.size():return {}
	var result={}
	for key in OpeningGeometry.SHELL_HOSTS:
		if not raw.get(key) is Dictionary:return {}
		var product=raw[key]
		if product.get("height") not in WallGeometry.HEIGHTS:return {}
		if product.get("material")!="original" and product.get("material") not in WallGeometry.MATERIALS:return {}
		var price=int(ShellSegments.LEGACY_PRICES[product.height])*(Footprint.WIDTH if key=="shell:back" else Footprint.DEPTH)
		var legacy_price=int(ShellSegments.LEGACY_PRICES[product.height])*(Footprint.WIDTH if key=="shell:back" else Footprint.LEGACY_DEPTH)
		# Keep the exact amount previously paid; extending the included shell
		# must neither charge the player nor invent refundable value.
		if not _valid_int(product.get("paid_cost"),0,price) or int(product.paid_cost) not in [0,legacy_price,price]:return {}
		result[key]={"height":str(product.height),"material":str(product.material),"paid_cost":int(product.paid_cost)}
	return result

func reroute_guest(guest:Dictionary) -> bool:
	if guest.phase=="checkout_walk":return Checkout._route_to(self,guest,guest.checkout_cell)
	if guest.phase=="leaving" and guest.paid and str(guest.get("settlement_mode","legacy"))=="register" and is_floor_owned(Vector2i(floori(float(guest.x)),floori(float(guest.z)))):
		return Checkout.depart(self,guest)
	# Layout edits may invalidate future legs, but never reset the actor's
	# actual position, meal state, payments or reservation. Route from here.
	if str(guest.phase) not in ["arriving","leaving"] or bool(guest.get("withdrawn",false)):return false
	var position:=Vector2(float(guest.x),float(guest.z))
	var cell:=Vector2i(floori(position.x),floori(position.y))
	var chair:=get_item(int(guest.chair_id))
	if chair.is_empty():return false
	var chair_cell:=Vector2i(int(chair.x),int(chair.z))
	if str(guest.phase)=="leaving" and not is_floor_owned(cell):
		# An already-departing guest keeps its remaining outdoor route. There
		# is no indoor start cell from which to ask for another exit path.
		var route_index=int(guest.route_index)
		if route_index<0 or route_index>=guest.route.size():return false
		var solids=[]
		for item in items:
			if item.kind!="rug":solids.append(Rect2(Vector2(item.x,item.z),Vector2.ONE).grow(.23))
		var previous=position
		for index in range(route_index,guest.route.size()):
			var next:Vector2=guest.route[index]
			if not next.is_finite() or segment_blocked(previous,next):return false
			if absf(next.x-previous.x)>.0001 and absf(next.y-previous.y)>.0001:return false
			# Check the whole remaining body sweep, including just beyond an
			# owned edge; a clear center tile alone can still clip furniture.
			for rect in solids:
				if rect.has_point(previous) or rect.has_point(next):return false
				var corners=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
				for edge in range(4):
					if Geometry2D.segment_intersects_segment(previous,next,corners[edge],corners[(edge+1)%4])!=null:return false
			previous=next
		return true
	var route:Array[Vector2]=[]
	var best:Dictionary={}
	var best_length:=INF
	if bool(guest.get("dismounting",false)):
		# Preserve the reserved physical step and current continuous position.
		# Rerouting must never turn halfway across the chair or reset its pose.
		if not chair_egress_cells(int(guest.chair_id),int(guest.table_id)).has(guest.egress_cell):return false
		cell=guest.egress_cell
	if is_floor_owned(cell) and _walkable(cell):
		if str(guest.phase)=="arriving":
			for approach in chair_egress_cells(int(guest.chair_id),int(guest.table_id)):
				var path:=Checkout.path(self,cell,approach)
				if path.is_empty():continue
				var candidate:Array[Vector2]=[]
				for step in path:candidate.append(cell_center(step))
				candidate.append(cell_center(chair_cell))
				var length:=_route_length(position,candidate)
				if length<best_length:best_length=length;route=candidate;best={"approach":approach}
		else:
			for entry in boundary_entries():
				var path:=Checkout.path(self,cell,entry.cell)
				if path.is_empty():continue
				var candidate:Array[Vector2]=[]
				for step in path:candidate.append(cell_center(step))
				candidate.append_array(_exterior_approach(entry,false,_departure_exit_z(int(guest.id))))
				var length:=_route_length(position,candidate)
				if length<best_length:best_length=length;route=candidate;best=entry
	elif cell==chair_cell and str(guest.phase)=="leaving":
		_begin_departure(guest)
		return not bool(guest.departure_blocked)
	elif not is_floor_owned(cell) and str(guest.phase)=="arriving":
		# Outside walkways form three clear perimeter lanes. Return to the
		# corresponding lane before choosing another open edge; never diagonal
		# through unowned plots or across the fixed shell.
		var prefix:Array[Vector2]=[]
		if position.x>=BASE_WIDTH and position.y<RIGHT_PARCEL_DEPTH:
			prefix=[Vector2(_arrival_right(),position.y),Vector2(_arrival_right(),_arrival_front()),Vector2(ARRIVAL_LANE_X,_arrival_front())]
		elif position.y>=BASE_DEPTH and position.x>=0 and position.x<MAX_WIDTH:
			prefix=[Vector2(position.x,_arrival_front()),Vector2(ARRIVAL_LANE_X,_arrival_front())]
		elif position.x<0:prefix=[Vector2(ARRIVAL_LANE_X,position.y)]
		elif position.y<0:prefix=[Vector2(position.x,-1.76),Vector2(ARRIVAL_LANE_X,-1.76)]
		else:return false
		var access:=guest_access_for(int(guest.chair_id),true,prefix[-1],12.5,int(guest.table_id))
		if not access.is_empty():
			route=prefix;route.append_array(access.route);best=access
	if route.is_empty():return false
	# Do not accept any newly constructed shortcut through a wall at corners.
	var previous:=position
	for point in route:
		if segment_blocked(previous,point):return false
		previous=point
	guest.route=route;guest.route_index=0;guest.departure_blocked=false;guest.waiting=false
	if best.has("entry_cell"):
		guest.entry_cell=best.entry_cell;guest.entry_direction=best.entry_direction;guest.entry_outside=best.entry_outside
	elif best.has("cell"):
		guest.entry_cell=best.cell;guest.entry_direction=best.direction;guest.entry_outside=best.outside
	if best.has("approach"):guest.service_cell=best.approach
	return true

# Hosted doors/windows. Stable wall IDs survive moving a wall; apertures are
# derived from the host, never saved as independent floating floor furniture.
func wall_hosts()->Array[Dictionary]:return OpeningGeometry.hosts(built_walls,shell_products)
func get_wall_host(host_id:String)->Dictionary:
	var segment=ShellSegments.parse_key(host_id)
	if not segment.is_empty():return ShellSegments.segment_host(ShellSegments.state(shell_products,shell_segment_products),built_walls,segment.root_id,int(segment.index))
	return OpeningGeometry.resolve_host(host_id,built_walls,shell_products)
func selectable_wall_hosts()->Array[Dictionary]:return ShellSegments.selectable_hosts(shell_products,shell_segment_products,built_walls)
func shell_render_host(root_id:String,preview:Dictionary={})->Dictionary:return ShellSegments.render_host(shell_products,shell_segment_products,built_walls,root_id,preview)
func get_wall_attachment(id:int)->Dictionary:
	for attachment in wall_attachments:
		if int(attachment.id)==id:return attachment
	return {}
func attachments_for_wall(wall_id:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for attachment in wall_attachments:
		var host=OpeningGeometry.resolve_host(attachment.host_id,built_walls)
		if not host.is_empty() and host.wall_ids.has(wall_id):result.append(attachment)
	return result
func wall_openings()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for attachment in wall_attachments:
		var opening=OpeningGeometry.aperture(attachment,built_walls,shell_products)
		if not opening.is_empty():result.append(opening)
	return result
func attachment_price(kind:String)->int:return int(OpeningGeometry.PRICES.get(kind,-1))
func _attachment_layout_error(walls:Array,attachments:Array,products=null,segments=null)->String:
	var roots=shell_products if products==null else products
	var ledger=shell_segment_products if segments==null and products==null else (ShellSegments.migrate(roots,walls).segments if segments==null else segments)
	return ShellSegments.support_error(ShellSegments.state(roots,ledger),walls,attachments)

func _opening_body_error(walls:Array,attachments:Array,actors:Array)->String:
	for host in OpeningGeometry.hosts(walls):
		for segment in OpeningGeometry.solid_segments(host,walls,attachments):
			for point in actors:
				if OpeningGeometry.body_touches(segment,point):return "An actor is crossing this opening · wait until the doorway is clear"
	return ""
func _attachment_change_error(proposed:Array,actor_positions:Array)->String:
	var reason=_attachment_layout_error(built_walls,proposed)
	if reason!="":return reason
	reason=_stove_wall_edit_error(built_walls,proposed)
	if reason!="":return reason
	var actors=_wall_actor_list(actor_positions)
	reason=_opening_body_error(built_walls,proposed,actors)
	if reason!="":return reason
	# Closing a door next to a used chair/table may not obstruct the meal.
	for guest in customers:
		if str(guest.phase) in ["dirty","cleaning"] or bool(guest.get("withdrawn",false)):continue
		var table=get_item(int(guest.table_id));var chair=get_item(int(guest.chair_id))
		if table.is_empty() or chair.is_empty():continue
		var a=Vector2i(int(table.x),int(table.z));var b=Vector2i(int(chair.x),int(chair.z))
		if _built_edge_blocked(a,b,built_walls,proposed) and not _built_edge_blocked(a,b,built_walls):return "A guest is using this dining opening · wait until the table is clear"
	var chair_error:=_chair_egress_error(built_walls,items,owned_parcels,customers,proposed)
	if chair_error!="":return chair_error
	return _wall_egress_error(built_walls,actors,items,owned_parcels,customers,proposed)
func can_place_wall_attachment(kind:String,host_id:String,offset:float,actor_positions:Array=[])->bool:
	last_error=""
	if attachment_price(kind)<0:return _fail("Choose a door or window")
	var attachment={"id":_next_attachment_id,"kind":kind,"host_id":host_id,"offset":offset,"width":float(OpeningGeometry.WIDTHS[kind]),"paid_cost":attachment_price(kind)}
	var proposed=wall_attachments.duplicate(true);proposed.append(attachment)
	var reason=_attachment_change_error(proposed,actor_positions)
	return true if reason=="" else _fail(reason)
func place_wall_attachment(kind:String,host_id:String,offset:float,actor_positions:Array=[])->bool:
	if not can_place_wall_attachment(kind,host_id,offset,actor_positions):return false
	var cost=attachment_price(kind)
	if coins<cost:return _fail("Not enough coins · %s needs %s"%[kind,Money.amount(cost)])
	wall_attachments.append({"id":_next_attachment_id,"kind":kind,"host_id":host_id,"offset":offset,"width":float(OpeningGeometry.WIDTHS[kind]),"paid_cost":cost})
	record_decoration_build_purchase("opening",_next_attachment_id,cost)
	_next_attachment_id+=1;coins-=cost;last_error="";last_event="Attached %s · −%s coins"%[kind,Money.amount(cost)];_notify();return true
func can_move_wall_attachment(id:int,host_id:String,offset:float,actor_positions:Array=[])->bool:
	last_error=""
	if get_wall_attachment(id).is_empty():return _fail("Select an attached door or window first")
	var proposed=wall_attachments.duplicate(true)
	for attachment in proposed:
		if int(attachment.id)==id:attachment.host_id=host_id;attachment.offset=offset
	var reason=_attachment_change_error(proposed,actor_positions)
	return true if reason=="" else _fail(reason)
func move_wall_attachment(id:int,host_id:String,offset:float,actor_positions:Array=[])->bool:
	if not can_move_wall_attachment(id,host_id,offset,actor_positions):return false
	var attachment=get_wall_attachment(id);attachment.host_id=host_id;attachment.offset=offset
	last_error="";last_event="Moved %s · old wall restored"%attachment.kind;_notify();return true
func can_remove_wall_attachment(id:int,actor_positions:Array=[])->bool:
	last_error=""
	if get_wall_attachment(id).is_empty():return _fail("Select an attached door or window first")
	var proposed=[]
	for attachment in wall_attachments:
		if int(attachment.id)!=id:proposed.append(attachment)
	var reason=_attachment_change_error(proposed,actor_positions)
	return true if reason=="" else _fail(reason)
func remove_wall_attachment(id:int,actor_positions:Array=[],refund=true)->bool:
	if not can_remove_wall_attachment(id,actor_positions):return false
	var attachment=get_wall_attachment(id);var amount=wall_attachment_refund(id) if refund else 0
	decoration_build_purchases.erase("opening:"+str(id))
	var kind=str(attachment.kind);wall_attachments.erase(attachment);coins+=amount
	last_error="";last_event="Removed %s · wall restored · +%s coins"%[kind,Money.amount(amount)];_notify();return true
func host_for_attachment_width(host_id:String,width:float)->Dictionary:
	var host=get_wall_host(host_id)
	if host.is_empty() or host.a.distance_to(host.b)+.00001>=width:return host
	if host.wall_ids.size()!=1:return {}
	var first_id=int(host.wall_ids[0])
	for wall in built_walls:
		if int(wall.id)==first_id:continue
		var ref="span:%d,%d"%[first_id,int(wall.id)]
		var span=get_wall_host(ref)
		if not span.is_empty() and span.a.distance_to(span.b)>=width:return span
	return {}
func _validate_saved_attachments(data:Dictionary,walls:Array)->Dictionary:
	if int(data.version)<5:
		var legacy=OpeningGeometry.initial_attachments();legacy[0].width=Footprint.LEGACY_DOOR_WIDTH
		return {"ok":true,"attachments":legacy,"next_attachment_id":2}
	var bad={"ok":false,"error":"Invalid hosted door/window data"}
	if not _valid_int(data.get("wall_attachment_format"),1,1) or not data.get("wall_attachments") is Array or data.wall_attachments.size()>300:return bad
	var attachments:Array[Dictionary]=[];var ids={};var highest=0
	for raw in data.wall_attachments:
		if not raw is Dictionary or not _valid_int(raw.get("id"),1,1000000000) or ids.has(int(raw.id)):return bad
		if raw.get("kind") not in OpeningGeometry.PRICES or not raw.get("host_id") is String or raw.host_id.length()>80:return bad
		var width=raw.get("width");var offset=raw.get("offset")
		if not (width is int or width is float) or not (offset is int or offset is float) or not is_finite(float(width)) or not is_finite(float(offset)):return bad
		if not is_equal_approx(float(width),float(OpeningGeometry.WIDTHS[raw.kind])) and not (raw.kind=="door" and (is_equal_approx(float(width),Footprint.LEGACY_DOOR_WIDTH) or is_equal_approx(float(width),Footprint.DOOR_WIDTH))):return bad
		if not _valid_int(raw.get("paid_cost"),0,int(OpeningGeometry.PRICES[raw.kind])) or int(raw.paid_cost) not in [0,int(OpeningGeometry.PRICES[raw.kind])]:return bad
		attachments.append({"id":int(raw.id),"kind":str(raw.kind),"host_id":str(raw.host_id),"offset":float(offset),"width":float(width),"paid_cost":int(raw.paid_cost)})
		ids[int(raw.id)]=true;highest=maxi(highest,int(raw.id))
	if not _valid_int(data.get("next_attachment_id"),highest+1,1000000001):return bad
	var products=_validated_shell_products(data)
	if products.is_empty():return bad
	var segments=ShellSegments.from_save(data,walls,products)
	if not segments.ok:return {"ok":false,"error":str(segments.error)}
	var reason=_attachment_layout_error(walls,attachments,products,segments.state.segments)
	if reason!="":return {"ok":false,"error":reason}
	return {"ok":true,"attachments":attachments,"next_attachment_id":int(data.next_attachment_id)}

func _align_saved_starter_door(attachments:Array,walls:Array,runtime:Dictionary,layout:Array,ownership:Array)->Array:
	var proposed=attachments.duplicate(true)
	var changed=false
	for attachment in proposed:
		if OpeningGeometry.is_legacy_starter_door(attachment):attachment.width=Footprint.DOOR_WIDTH;changed=true
	if not changed:return attachments
	var staff:Array=[];var actors:Array=[]
	for actor in runtime.service.get("staff",[]):staff.append(actor.pos);actors.append(actor.pos)
	for guest in runtime.customers:
		if str(guest.phase) not in ["dirty","cleaning"]:actors.append(Vector2(float(guest.x),float(guest.z)))
	if _opening_body_error(walls,proposed,actors)!="":return attachments
	if _wall_egress_error(walls,staff,layout,ownership,runtime.customers,proposed)!="":return attachments
	# This deliberately defers, rather than moving a person or replacing a saved
	# route. The same signature can be aligned on a later load after it is clear.
	var host=OpeningGeometry.resolve_host("shell:west",walls)
	var old_start=Footprint.DOOR_CENTER-Footprint.LEGACY_DOOR_WIDTH*.5
	var old_end=Footprint.DOOR_CENTER+Footprint.LEGACY_DOOR_WIDTH*.5
	var added=[]
	for span in [Vector2(old_start,Footprint.DOOR_START),Vector2(Footprint.DOOR_END,old_end)]:
		added.append(OpeningGeometry.segment_rect({"a":Vector2(0,span.x),"b":Vector2(0,span.y),"host":host}).grow(.23))
	for actor in runtime.service.get("staff",[]):
		var route=[]
		for cell in actor.path:route.append(cell_center(cell))
		if not _starter_door_route_clear(actor.pos,route,int(actor.index),added):return attachments
	for guest in runtime.customers:
		if str(guest.phase) in ["dirty","cleaning"]:continue
		var position=Vector2(float(guest.x),float(guest.z))
		if not _starter_door_route_clear(position,guest.route,int(guest.route_index),added):return attachments
		var motion:Dictionary=guest.get("mobility",{})
		if not motion.is_empty() and not _starter_door_route_clear(position,motion.route,int(motion.route_index),added):return attachments
	return proposed

func _starter_door_route_clear(start:Vector2,route:Array,index:int,added:Array)->bool:
	for i in range(index,route.size()):
		var finish:Vector2=route[i]
		for rect in added:
			if rect.has_point(start) or rect.has_point(finish):return false
			var corners=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
			for edge in range(4):
				if Geometry2D.segment_intersects_segment(start,finish,corners[edge],corners[(edge+1)%4])!=null:return false
		start=finish
	return true
