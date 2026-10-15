extends SceneTree
const Music=preload("res://scripts/platform/crazygames_music.gd")
class ControlledMusic extends Music:
	var clock=1000
	var start_error=OK
	var last_request:HTTPRequest
	var reported_warnings=[]
	func _report_warning(message:String):reported_warnings.append(message)
	func _now_msec()->int:return clock
	func _start_request()->Error:
		last_request=request
		return request.request("http://127.0.0.1:1/music.pck") if start_error==OK else start_error
class Settings extends RefCounted:
	var applied=0
	func _apply_buses():applied+=1
class Owner extends Node:
	var setups=0
	var audio_players={}
	var music_catalog_ready=false
	var settings_controls=Settings.new()
	func _setup_music():
		setups+=1
		music_catalog_ready=true
		for state in ["service","busy","decorate"]:
			var player=AudioStreamPlayer.new();add_child(player)
			audio_players[state]=player
var checks=0
var failures=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label)
func _init():call_deferred("run")
func run():
	var owner=Owner.new();root.add_child(owner)
	var music=ControlledMusic.new(owner)
	music.begin()
	var first=music.request
	check(first!=null and owner.get_child_count()==1,"one active owned HTTPRequest")
	check(first.timeout==30.0 and not first.accept_gzip,"bounded download preserves browser decoding")
	for i in range(100):music.begin()
	check(music.request==first and music.attempts==1,"foreground frames never duplicate active request")
	first.request_completed.emit(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())
	check(music.request==null and owner.get_child_count()==0 and not music.requested,"network failure releases ownership and enables recovery")
	await process_frame
	check(not is_instance_valid(first),"failed HTTPRequest is physically freed")
	for i in range(100):music.begin()
	music.clock=5999;music.begin()
	check(music.attempts==1 and music.request==null,"no retry before five-second deadline")
	music.clock=6000;music.begin()
	var second=music.request
	check(second!=null and music.attempts==2,"next eligible foreground call retries once")
	second.request_completed.emit(HTTPRequest.RESULT_SUCCESS,503,PackedStringArray(),PackedByteArray())
	check(not music.requested and music.request==null,"HTTP failure remains recoverable")
	await process_frame
	check(not is_instance_valid(second),"HTTP error request is physically freed")
	music.clock=11000
	check(owner.get_child_count()==0 and music.attempts==2,"time alone starts no background retry")
	music.begin()
	var third=music.request
	third.request_completed.emit(HTTPRequest.RESULT_TIMEOUT,0,PackedStringArray(),PackedByteArray())
	await process_frame
	check(not is_instance_valid(third),"timed-out request is physically freed")
	music.clock=1000000
	for i in range(100):music.begin()
	check(music.attempts==3 and music.request==null and owner.get_child_count()==0,"three-attempt cap prevents unbounded failure retries")
	check(music.reported_warnings==["Background music could not load; gameplay and saves remain available","Background music could not load; gameplay and saves remain available","Background music could not load; gameplay and saves remain available"],"network/HTTP/timeout preserve all three exact warning diagnostics")
	owner.free();music=null

	# A controlled start rejection has no completion signal to clean up.
	owner=Owner.new();root.add_child(owner);music=ControlledMusic.new(owner)
	music.start_error=ERR_CANT_CONNECT;music.begin()
	var start_rejected=music.last_request
	check(not music.requested and music.request==null and owner.get_child_count()==0,"immediate start error detaches request")
	await process_frame
	check(not is_instance_valid(start_rejected),"start-rejected request is physically freed")
	music.clock+=5000;music.start_error=OK;music.begin()
	check(music.request!=null and music.attempts==2,"start error permits delayed foreground retry")
	check(music.reported_warnings==["Background music could not start loading; gameplay and saves remain available"],"immediate start rejection preserves exact warning diagnostic")
	var interrupted=music.request
	owner.free();music=null
	check(not is_instance_valid(interrupted),"scene teardown frees in-flight request")

	# A generated pack exercises the actual write/mount path without game assets.
	var marker="user://music-test-marker.txt"
	var file=FileAccess.open(marker,FileAccess.WRITE);file.store_string("synthetic music recovery fixture");file.close()
	var pack=PCKPacker.new()
	check(pack.pck_start("user://music-test.pck")==OK,"synthetic pack starts")
	check(pack.add_file("res://music-test-marker.txt",marker)==OK and pack.flush()==OK,"synthetic pack generated")
	var body=FileAccess.get_file_as_bytes("user://music-test.pck")
	owner=Owner.new();root.add_child(owner);music=ControlledMusic.new(owner);music.begin()
	var rejected=music.request
	rejected.request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),PackedByteArray())
	check(not music.requested and owner.setups==0,"unreadable package permits retry without players")
	await process_frame
	check(not is_instance_valid(rejected),"unreadable-package request is freed")
	music.clock+=5000;music.begin()
	var successful=music.request
	successful.request_completed.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),body)
	await process_frame
	check(not is_instance_valid(successful) and music.request==null,"successful request is freed")
	check(owner.setups==1 and owner.audio_players.size()==3 and owner.get_child_count()==3,"recovery sets up exactly three owned music players")
	check(owner.settings_controls.applied==1,"recovery reapplies current bus preferences once")
	check(FileAccess.get_file_as_string("res://music-test-marker.txt")=="synthetic music recovery fixture","actual generated pack mounted")
	music.clock=1000000
	for i in range(100):music.begin()
	check(music.requested and music.attempts==2 and owner.setups==1 and owner.get_child_count()==3,"success never retries or duplicates players")
	check(music.reported_warnings==["Background music package could not be opened; gameplay and saves remain available"],"unreadable pack preserves exact warning diagnostic")
	var players=owner.audio_players.values();owner.free();music=null
	for player in players:check(not is_instance_valid(player),"scene teardown frees owned music player")
	print("CRAZYGAMES_MUSIC_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"fixture":"synthetic pack and HTTPRequest completion signals","listening_acceptance":false}))
	quit(0 if failures.is_empty() else 1)
