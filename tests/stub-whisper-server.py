#!/usr/bin/env python3
"""Stand-in for whisper-server used by tests/queue-test.sh.

Answers GET / and POST /inference. The "audio" is the text REC-<id> written by
the rec stub; the reply is "text-<id>-<language>". Per-recording latency comes
from STUB_DELAYS="id:seconds,..." and a startup delay (model load) from
STUB_SERVER_START. Requests run concurrently, like independent clients would.
"""
import os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[sys.argv.index("--port") + 1])
box = os.environ["STUB_DIR"]
delays = dict(p.split(":") for p in os.environ.get("STUB_DELAYS", "").split(",") if p)

def stamp(name, text):
    with open(os.path.join(box, name), "a") as f:
        f.write(f"{time.time():.3f} {text}\n")

stamp("server-starts", f"pid={os.getpid()} port={port}")
time.sleep(float(os.environ.get("STUB_SERVER_START", "0")))

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        rid = re.search(rb"REC-(\d+)", body).group(1).decode()
        lang = re.search(rb'name="language"\r\n\r\n([^\r]*)', body)
        lang = lang.group(1).decode() if lang else "-"
        stamp("server-requests", f"id={rid} lang={lang}")
        time.sleep(float(delays.get(rid, "0.1")))
        stamp("server-done", f"id={rid}")
        out = f"text-{rid}-{lang}".encode()
        self.send_response(200); self.send_header("Content-Length", str(len(out)))
        self.end_headers(); self.wfile.write(out)

ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
