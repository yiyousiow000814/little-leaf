extends SceneTree
const Policy=preload("res://scripts/cafe_hidden_time_policy.gd")
var failures=[]
var checks=0
func check(ok,label):
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)
func _initialize():
	check(Policy.local_callbacks_allowed({"serverOwnership":false}),"explicit guest callbacks")
	check(Policy.local_callbacks_allowed({},true,false),"marked bridge-free local vault")
	check(not Policy.local_callbacks_allowed({},true,true),"marker cannot override an unknown bridge")
	check(not Policy.local_callbacks_allowed({"serverOwnership":true},true,true),"marker cannot override cloud authority")
	check(not Policy.local_callbacks_allowed({"serverOwnership":false,"accountChanged":true},true,true),"marker cannot override account change")
	check(Policy.local_callbacks_allowed({"serverOwnership":true,"status":"active","ownershipPaused":false}),"explicit active account permits speculative delivered callbacks")
	for flag in ["accountChanged","choicesAvailable","available","busy","ownershipPaused"]:
		var account={"serverOwnership":true,"status":"active","ownershipPaused":false};account[flag]=true
		check(not Policy.local_callbacks_allowed(account),"account safety gate: "+flag)
	for status in ["offline","other-device","handoff-requested","resume-needed"]:
		check(not Policy.local_callbacks_allowed({"serverOwnership":true,"status":status,"ownershipPaused":false}),"non-active account fails closed: "+status)
	for invalid in [0,"false",null]:check(not Policy.local_callbacks_allowed({"serverOwnership":invalid}),"ownership mode must be an explicit boolean")
	for state in [{},{"serverOwnership":true,"status":"active"},{"serverOwnership":true,"status":"offline"},{"serverOwnership":true,"status":"active","renewed":true},{"serverOwnership":true,"status":"other-device"},{"serverOwnership":false,"accountChanged":true},{"serverOwnership":false,"choicesAvailable":true},{"serverOwnership":false,"busy":true}]:
		check(not Policy.local_callbacks_allowed(state),"unknown/cloud/account/conflict blocked: "+str(state))
	check(Policy.frame_delta(.1,true,true)==.1,"guest callback delivered once")
	check(Policy.frame_delta(.25,true,true)==.25,"inclusive callback budget boundary")
	check(Policy.frame_delta(.250001,true,true)==0.0,"over-budget callback wholly discarded")
	for delta in [1.0,60.0,3600.0,-1.0,INF,NAN]:check(Policy.frame_delta(delta,true,true)==0.0,"gap/invalid discarded")
	check(Policy.frame_delta(.1,true,false)==0.0,"no cloud hidden interval inferred")
	for ignored in range(10):check(Policy.catch_up_seconds()==0.0,"duplicate return/renew/reconnect cannot replay")
	print("HIDDEN_TIME_POLICY_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
