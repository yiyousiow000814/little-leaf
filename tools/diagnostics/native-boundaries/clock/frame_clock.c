/* Diagnostic-only clock extension; Linux x86_64, Godot 4.6.3 generated ABI.
 * No callbacks, worker threads, hooks, process attachment, or persistent writes.
 * cpu_ns is CLOCK_THREAD_CPUTIME_ID: on-CPU time of the calling thread.
 * process_cpu_ns is CLOCK_PROCESS_CPUTIME_ID: all threads, NOT wall-additive. */
#define _GNU_SOURCE
#include "gdextension_interface.h"
#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceStringNameNewWithLatin1Chars sn_new;
static GDExtensionInterfaceStringNewWithUtf8Chars str_new;
static GDExtensionInterfaceClassdbRegisterExtensionClass4 register_class;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionPtrDestructor sn_destroy, str_destroy;
static GDExtensionVariantFromTypeConstructorFunc int_variant;
static uint64_t class_name;
static int64_t value(void *user) {
 if ((intptr_t)user==2) return syscall(SYS_gettid);
 struct timespec t;
 if (clock_gettime((intptr_t)user==1?CLOCK_PROCESS_CPUTIME_ID:CLOCK_THREAD_CPUTIME_ID,&t)) return -1;
 return (int64_t)t.tv_sec*1000000000LL+t.tv_nsec;
}
static void call(void *user,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *args,GDExtensionInt n,GDExtensionVariantPtr out,GDExtensionCallError *error) {
 (void)instance;(void)args;
 if (n!=0) {error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT;return;}
 int64_t v=value(user);int_variant(out,&v);error->error=GDEXTENSION_CALL_OK;
}
static void ptrcall(void *user,GDExtensionClassInstancePtr instance,const GDExtensionConstTypePtr *args,GDExtensionTypePtr out) {
 (void)instance;(void)args;*(int64_t*)out=value(user);
}
static void initialize(void *data,GDExtensionInitializationLevel level) {
 (void)data;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;
 uint64_t parent,empty_name,empty_string;
 sn_new(&class_name,"FrameClock",0);sn_new(&parent,"Object",0);
 sn_new(&empty_name,"",0);str_new(&empty_string,"");
 GDExtensionClassCreationInfo4 ci={0};ci.is_abstract=1;ci.is_exposed=1;
 register_class(library,&class_name,&parent,&ci);
 const char *names[]={"cpu_ns","process_cpu_ns","tid"};
 for(int i=0;i<3;i++){
  uint64_t method;sn_new(&method,names[i],0);
  GDExtensionPropertyInfo ri={0};ri.type=GDEXTENSION_VARIANT_TYPE_INT;ri.name=&empty_name;ri.class_name=&empty_name;ri.hint_string=&empty_string;
  GDExtensionClassMethodInfo mi={0};mi.name=&method;mi.method_userdata=(void*)(intptr_t)i;mi.call_func=call;mi.ptrcall_func=ptrcall;mi.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_STATIC;mi.has_return_value=1;mi.return_value_info=&ri;mi.return_value_metadata=GDEXTENSION_METHOD_ARGUMENT_METADATA_INT_IS_INT64;
  register_method(library,&class_name,&mi);sn_destroy(&method);
 }
 sn_destroy(&parent);sn_destroy(&empty_name);str_destroy(&empty_string);
}
static void deinitialize(void *data,GDExtensionInitializationLevel level){
 (void)data;if(level!=GDEXTENSION_INITIALIZATION_SCENE)return;unregister_class(library,&class_name);sn_destroy(&class_name);
}
__attribute__((visibility("default"))) GDExtensionBool frame_clock_init(GDExtensionInterfaceGetProcAddress get,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init){
 library=lib;
 sn_new=(GDExtensionInterfaceStringNameNewWithLatin1Chars)get("string_name_new_with_latin1_chars");
 str_new=(GDExtensionInterfaceStringNewWithUtf8Chars)get("string_new_with_utf8_chars");
 register_class=(GDExtensionInterfaceClassdbRegisterExtensionClass4)get("classdb_register_extension_class4");
 unregister_class=(GDExtensionInterfaceClassdbUnregisterExtensionClass)get("classdb_unregister_extension_class");
 register_method=(GDExtensionInterfaceClassdbRegisterExtensionClassMethod)get("classdb_register_extension_class_method");
 GDExtensionInterfaceVariantGetPtrDestructor destructor=(GDExtensionInterfaceVariantGetPtrDestructor)get("variant_get_ptr_destructor");
 sn_destroy=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);str_destroy=destructor(GDEXTENSION_VARIANT_TYPE_STRING);
 int_variant=((GDExtensionInterfaceGetVariantFromTypeConstructor)get("get_variant_from_type_constructor"))(GDEXTENSION_VARIANT_TYPE_INT);
 init->initialize=initialize;init->deinitialize=deinitialize;init->userdata=NULL;init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;return 1;
}
