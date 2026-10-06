from pathlib import Path
import http.server,threading,subprocess,time,json,gzip
w=Path.cwd();r=w/'crazygames-build';q=w/'crazygames-variant/qa/crazygames';profile=q/'actual-sdk-browser-profile-viewport-fixed';assert not profile.exists()
class Handler(http.server.SimpleHTTPRequestHandler):
 def __init__(self,*a,**k):super().__init__(*a,directory=str(r),**k)
 def log_message(self,*a):pass
 def do_GET(self):
  p=r/self.path.split('?')[0].lstrip('/')
  if p.is_file() and p.suffix in ['.wasm','.pck','.js','.html']:
   b=gzip.compress(p.read_bytes(),compresslevel=9,mtime=0);self.send_response(200);self.send_header('Content-Type',self.guess_type(str(p)));self.send_header('Content-Encoding','gzip');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
  else:super().do_GET()
s=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=s.serve_forever,daemon=True).start()
b=subprocess.Popen([str(Path(r'C:\Program Files\Google\Chrome\Application\chrome.exe')),'--headless=new','--disable-gpu','--enable-unsafe-swiftshader','--use-angle=swiftshader','--window-size=1280,900','--disable-background-networking','--disable-component-update','--disable-default-apps','--no-first-run','--no-default-browser-check','--user-data-dir='+str(profile),'--remote-debugging-port=0','about:blank'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW)
try:
 for i in range(100):
  p=profile/'DevToolsActivePort'
  if p.exists():break
  if b.poll() is not None:raise RuntimeError('Chrome exited')
  time.sleep(.1)
 d=subprocess.run(['node',str(w/'crazygames-tools/check_actual_sdk_browser.js'),p.read_text().splitlines()[0],'http://127.0.0.1:'+str(s.server_port)+'/index.html'],capture_output=True,timeout=105)
 print(d.stdout.decode());print(d.stderr.decode());assert d.returncode==0;b.wait(timeout=10)
finally:
 if b.poll() is None:b.terminate();b.wait(timeout=10)
 s.shutdown();s.server_close()
