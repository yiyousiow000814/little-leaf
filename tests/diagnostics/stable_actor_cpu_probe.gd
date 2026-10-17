extends RefCounted
## Diagnostic-only staged wrappers. Never preload the SceneTree fixture here.
## Inclusive parent time already contains nested overhead: do not add it twice.
static var enabled = false
static var counting_enabled = false
static var stack = []
static var samples = {}
static var counts = {}
static var counts_by_frame = {}
static var deltas_by_frame = {}
static var errors = []
static var frame_index = -1
static var finished_frames = 0

static func reset():
 reset_timings()
 reset_counts()
 counting_enabled = false

static func reset_timings():
 enabled = false
 stack.clear()
 samples.clear()
 deltas_by_frame.clear()
 errors.clear()
 frame_index = -1
 finished_frames = 0

static func reset_counts():
 counts.clear()
 counts_by_frame.clear()

static func begin_frame(index:int):
 if enabled or not stack.is_empty(): errors.append("Timing frame began with an open scope")
 if index != finished_frames: errors.append("Noncontiguous sample frame")
 frame_index = index
 enabled = true

static func end_frame():
 if not stack.is_empty(): errors.append("Timing frame ended with an open scope")
 enabled = false
 finished_frames += 1
 frame_index = -1

static func enter(label:String):
 if enabled: stack.append([label,Time.get_ticks_usec(),0,frame_index])

static func leave():
 if not enabled: return
 if stack.is_empty():
  errors.append("Timer leave without enter")
  return
 var scope = stack.pop_back()
 var elapsed = Time.get_ticks_usec() - int(scope[1])
 if int(scope[3]) != frame_index: errors.append("Timer crossed a sample frame")
 if not stack.is_empty(): stack[-1][2] += elapsed
 record_sample(str(scope[0]),frame_index,elapsed,int(scope[2]))

static func record_sample(label:String, frame:int, inclusive_us:int, nested_us:int):
 # Shared arithmetic for real leave() and deterministic pure tests, no sleeps.
 if inclusive_us < 0 or nested_us < 0 or nested_us > inclusive_us:
  errors.append("Invalid nested timer arithmetic")
  return
 if not samples.has(label): samples[label] = {"inclusive":[],"self_us":0,"by_frame":{},"self_by_frame":{},"calls_by_frame":{}}
 var row = samples[label]
 row.inclusive.append(inclusive_us)
 row.self_us += inclusive_us - nested_us
 row.by_frame[frame] = int(row.by_frame.get(frame,0)) + inclusive_us
 row.self_by_frame[frame] = int(row.self_by_frame.get(frame,0)) + inclusive_us - nested_us
 row.calls_by_frame[frame] = int(row.calls_by_frame.get(frame,0)) + 1

static func count(label:String, amount:int=1):
 if not counting_enabled: return
 if amount < 0:
  errors.append("Negative branch counter increment")
  return
 counts[label] = int(counts.get(label,0)) + amount
 if frame_index >= 0:
  if not counts_by_frame.has(label): counts_by_frame[label] = {}
  counts_by_frame[label][frame_index] = int(counts_by_frame[label].get(frame_index,0)) + amount

static func observe_delta(delta:float):
 if not enabled: return
 if not deltas_by_frame.has(frame_index): deltas_by_frame[frame_index] = []
 deltas_by_frame[frame_index].append(delta)

static func distribution(values:Array)->Dictionary:
 if values.is_empty(): return {"count":0,"total":0,"p50":0,"p95":0,"p99":0,"max":0}
 var ordered = values.duplicate()
 ordered.sort()
 var total = 0
 for value in ordered: total += value
 return {"count":ordered.size(),"total":total,"p50":ordered[ordered.size()/2],"p95":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"p99":ordered[mini(ordered.size()-1,int(ordered.size()*.99))],"max":ordered[-1]}

static func report()->Dictionary:
 var result = {}
 for label in samples:
  var row = samples[label]
  var calls = distribution(row.inclusive)
  var frame_us = []
  var frame_self_us = []
  var frame_calls = []
  for index in finished_frames:
   frame_us.append(int(row.by_frame.get(index,0)))
   frame_self_us.append(int(row.self_by_frame.get(index,0)))
   frame_calls.append(int(row.calls_by_frame.get(index,0)))
  result[label] = {"calls":calls.count,"inclusive_us":calls.total,"self_us_excluding_instrumented_children":row.self_us,"p50_call_us":calls.p50,"p95_call_us":calls.p95,"p99_call_us":calls.p99,"max_call_us":calls.max,"per_sample_frame_us":frame_us,"per_sample_frame_self_us":frame_self_us,"per_sample_frame_calls":frame_calls,"per_sample_frame":distribution(frame_us)}
 return result

static func counter_report()->Dictionary:
 var by_frame = {}
 for label in counts_by_frame:
  var rows = []
  for index in finished_frames: rows.append(int(counts_by_frame[label].get(index,0)))
  by_frame[label] = rows
 return {"totals":counts.duplicate(),"per_sample_frame":by_frame}

static func delta_report()->Array:
 var result = []
 for index in finished_frames: result.append(deltas_by_frame.get(index,[]).duplicate())
 return result

static func pure_checks()->Dictionary:
 reset()
 var checks = []
 count("disabled")
 checks.append({"name":"disabled-counting", "passed":counts.is_empty()})
 counting_enabled = true
 count("heads.sprite",2)
 checks.append({"name":"counts-independent-of-timers", "passed":counts.get("heads.sprite")==2 and not enabled})
 reset_timings()
 checks.append({"name":"timing-reset-retains-counts", "passed":counts.get("heads.sprite")==2})
 reset_counts()
 checks.append({"name":"counter-reset", "passed":counts.is_empty()})
 begin_frame(0)
 observe_delta(1.0/60.0)
 record_sample("parent",0,100,30)
 record_sample("child",0,30,0)
 count("heads.sprite",3)
 end_frame()
 begin_frame(1)
 observe_delta(1.0/60.0)
 end_frame()
 var result = report()
 checks.append({"name":"nested-self-not-double-counted", "passed":result.parent.inclusive_us==100 and result.parent.self_us_excluding_instrumented_children==70 and result.child.inclusive_us==30})
 checks.append({"name":"zero-call-frames-retained", "passed":result.parent.per_sample_frame_us==[100,0] and result.parent.per_sample_frame_calls==[1,0]})
 checks.append({"name":"per-frame-branch-counts", "passed":counter_report().per_sample_frame["heads.sprite"]==[3,0]})
 checks.append({"name":"exact-fixed-deltas", "passed":delta_report()==[[1.0/60.0],[1.0/60.0]]})
 checks.append({"name":"closed-timer-state", "passed":errors.is_empty() and stack.is_empty() and not enabled})
 reset()
 return {"checks":checks,"passed":checks.all(func(row):return row.passed),"native_render_executed":false,"game_instance_created":false,"timing_sample_executed":false}
