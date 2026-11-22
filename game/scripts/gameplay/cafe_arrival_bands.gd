extends RefCounted
## Per-admission weighted entrance searches for dense, canonical west openings.
## The normal small and historical entrance paths remain in CafeModel.
const MIN_ENTRANCES=9
const MAX_BANDS=2
const UNIT_TICKS=1073741824.0
const EXACT_INTEGER_LIMIT=9007199254740992.0

static func prepare(model,start:Vector2,entries:Array,solids:Dictionary)->Dictionary:
 if not start.is_finite() or start.x!=Vector2(model.ARRIVAL_LANE_X,0).x or absf(start.y)>82.0:return {}
 var seeds={}
 var valid_entrances:=0
 for ordinal in entries.size():
  var entry:Dictionary=entries[ordinal]
  if entry.cell.x!=0 or entry.outside!=entry.cell+Vector2i.LEFT or entry.direction!=Vector2i.LEFT:return {}
  if solids.has(entry.cell) or not model.is_floor_owned(entry.cell):continue
  var prefix:Array[Vector2]=model._exterior_approach(entry,true)
  if prefix.size()!=2:return {}
  prefix.append(model.cell_center(entry.cell))
  var cost:float=model._route_length(start,prefix)
  # Interior cardinal half-tile distances are units. Prove the prefix
  # and every subsequent add are exact on a bounded binary64 lattice.
  var fixed:=cost*UNIT_TICKS
  if not is_finite(fixed) or fixed!=floor(fixed) or fixed+(model.MAX_WIDTH*model.MAX_DEPTH+1)*UNIT_TICKS>=EXACT_INTEGER_LIMIT:return {}
  var fraction:=fposmod(cost,1.0)
  if not seeds.has(fraction):
   if seeds.size()>=MAX_BANDS:return {}
   seeds[fraction]=[]
  seeds[fraction].append([floori(cost),ordinal,ordinal,entry.cell,entry.cell])
  valid_entrances+=1
 if valid_entrances<MIN_ENTRANCES:return {}
 var searches={}
 for fraction in seeds:
  var state={"buckets":{},"order":entries.size(),"weight":1000000000,"last_weight":0,
   "offset":0,"sorted":false,"tree":{},"best":{}}
  for seed in seeds[fraction]:_push(state,seed)
  searches[fraction]=state
 return {"entries":entries,"searches":searches}

# Queue row: integer weight, source ordinal, enqueue order, cell, predecessor.
static func _push(state:Dictionary,row:Array)->void:
 var weight:int=row[0]
 var buckets:Dictionary=state.buckets
 if not buckets.has(weight):buckets[weight]=[]
 buckets[weight].append(row)
 state.weight=mini(state.weight,weight);state.last_weight=maxi(state.last_weight,weight)

static func _pop(state:Dictionary)->Array:
 var buckets:Dictionary=state.buckets
 while state.weight<=state.last_weight:
  var weight:int=state.weight
  var rows:Array=buckets.get(weight,[])
  if int(state.offset)>=rows.size():
   state.weight+=1;state.offset=0;state.sorted=false
   buckets.erase(weight)
   continue
  if not state.sorted:
   # Every incoming step costs one, so no new row can enter this layer.
   # One source's FIFO direction discovery matches its old forward BFS.
   rows.sort_custom(func(a,b):return a[1]<b[1] or (a[1]==b[1] and a[2]<b[2]))
   state.sorted=true
  var row:Array=rows[int(state.offset)]
  state.offset+=1
  return row
 return []

static func _settle(model,state:Dictionary,solids:Dictionary,approaches:Array[Vector2i])->Dictionary:
 var tree:Dictionary=state.tree
 var best:Dictionary=state.best
 var pending={}
 for approach in approaches:
  if not tree.has(approach) and not solids.has(approach) and model.is_floor_owned(approach):pending[approach]=true
 while not pending.is_empty():
  var row:=_pop(state)
  if row.is_empty():break
  var at:Vector2i=row[3]
  if tree.has(at):continue
  tree[at]=row;pending.erase(at)
  # Complete this neighbor pass before returning so the next chair can resume.
  for direction in model.DIRECTIONS:
   var next:Vector2i=at+direction
   if tree.has(next) or solids.has(next) or not model.is_floor_owned(next) or model.edge_blocked(at,next):continue
   var weight:int=row[0]+1
   var existing:Array=best.get(next,[])
   if not existing.is_empty() and (weight>existing[0] or (weight==existing[0] and row[1]>=existing[1])):continue
   best[next]=[weight,row[1]]
   _push(state,[weight,row[1],state.order,next,at]);state.order+=1
 return tree

static func access(model,search:Dictionary,solids:Dictionary,chair:Vector2i,forward:Vector2i,approaches:Array[Vector2i])->Dictionary:
 var minima=[]
 for fraction in search.searches:
  var tree:=_settle(model,search.searches[fraction],solids,approaches)
  var best={}
  for i in approaches.size():
   var approach:=approaches[i]
   if not tree.has(approach):continue
   var row:Array=tree[approach]
   var direction:=approach-chair
   var rank:=0 if direction.x*forward.x+direction.y*forward.y==0 else 1
   var length:=float(row[0])+float(fraction)+1.0
   var ordinal:int=row[1]*3+i
   if best.is_empty() or rank<best.rank or (rank==best.rank and (length<best.length or (length==best.length and ordinal<best.ordinal))):
    best={"rank":rank,"length":length,"ordinal":ordinal,"tree":tree,"row":row,"approach":approach}
  if not best.is_empty():minima.append(best)
 # Within one rank, another score in a band is at least a whole step higher.
 # With at most two bands it cannot affect the ordered epsilon tie between
 # the minima. Replay the same entrance/approach order instead of sorting by cost.
 minima.sort_custom(func(a,b):return a.ordinal<b.ordinal)
 var selected={}
 for candidate in minima:
  if selected.is_empty() or candidate.rank<selected.rank or (candidate.rank==selected.rank and candidate.length+.000001<selected.length):selected=candidate
 if selected.is_empty():return {}
 var row:Array=selected.row
 var entry:Dictionary=search.entries[row[1]]
 var route:Array[Vector2]=model._exterior_approach(entry,true)
 var indoor:Array[Vector2]=[model.cell_center(row[3])]
 while row[3]!=row[4]:
  row=selected.tree[row[4]]
  indoor.append(model.cell_center(row[3]))
 indoor.reverse();route.append_array(indoor);route.append(model.cell_center(chair))
 return {"entry_cell":entry.cell,"entry_direction":entry.direction,"entry_outside":entry.outside,
  "approach":selected.approach,"route":route,"length":selected.length,
  "chair_approach":"side" if selected.rank==0 else "rear_fallback"}
