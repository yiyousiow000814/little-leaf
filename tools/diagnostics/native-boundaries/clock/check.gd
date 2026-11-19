extends SceneTree
func cpu()->int:return ClassDB.class_call_static(&"FrameClock",&"cpu_ns")
func _initialize():
 var status=GDExtensionManager.load_extension("res://frame_clock.gdextension")
 var c0=cpu();var w0=Time.get_ticks_usec()
 OS.delay_msec(60)
 var sleep_cpu=cpu()-c0;var sleep_wall=Time.get_ticks_usec()-w0
 c0=cpu();w0=Time.get_ticks_usec()
 while Time.get_ticks_usec()-w0<60000:pass
 var busy_cpu=cpu()-c0;var busy_wall=Time.get_ticks_usec()-w0
 w0=Time.get_ticks_usec()
 for i in 10000:cpu()
 var call_us=float(Time.get_ticks_usec()-w0)/10000
 print(JSON.stringify({"status":status,"tid":ClassDB.class_call_static(&"FrameClock",&"tid"),"pid":OS.get_process_id(),"sleep_cpu_ns":sleep_cpu,"sleep_wall_us":sleep_wall,"busy_cpu_ns":busy_cpu,"busy_wall_us":busy_wall,"clock_call_mean_us":call_us}))
 quit(0 if sleep_cpu>=0 and sleep_cpu<10000000 and busy_cpu>30000000 else 2)
