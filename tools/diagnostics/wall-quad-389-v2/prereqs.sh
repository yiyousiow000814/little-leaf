# Called after source/candidate/engine identity checks. Separate stamps preserve
# precisely which prerequisite failed, with no package installation or host dump.
wall_prereqs() {
  fail x11_xvfb_binary
  command -v Xvfb >/dev/null || return 21
  fail x11_xvfb_wrapper
  command -v xvfb-run >/dev/null || return 22
  fail x11_xauth_binary
  command -v xauth >/dev/null || return 23
  fail x11_display_startup
  # Exercise the actual runner's wrapper, X authority and display startup.
  timeout 15 xvfb-run -a -s '-screen 0 1600x1000x24' "$py" -S -c 'import ctypes as c,sys;x=c.CDLL("libX11.so.6");x.XOpenDisplay.argtypes=[c.c_char_p];x.XOpenDisplay.restype=c.c_void_p;display=x.XOpenDisplay(None);x.XCloseDisplay.argtypes=[c.c_void_p];sys.exit(0 if display and x.XCloseDisplay(display)==0 else 1)' > "$priv/x11-preflight.log" 2>&1 || return 24
  fail native_png_decoder
  timeout 20 "$bin" --headless --path "$decoder" --script res://decode.gd -- --self-test > "$priv/png-preflight.log" 2>&1 || return 25
  grep -q '^WALL_PNG_DECODER_OK$' "$priv/png-preflight.log" || return 26
}
