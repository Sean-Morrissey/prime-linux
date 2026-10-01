#!/usr/bin/env python3
"""A tiny OpenAI-compatible server for testing prime-ask without any real model
or API key. It streams, makes tool calls, and logs every request it gets.

  mock-openai.py PORT LOGFILE

Behaviour (chosen from the last message):
  model "no-tools" + a request with tools  -> HTTP 400 (forces the JSON fallback)
  last message is a tool result             -> streams "All set: <status>."
  user text mentions "accent"               -> calls set_accent {"color": "blue"}
  user text mentions "shortcut"             -> calls add_shortcut (Super+Shift+Y -> Files)
  user text mentions "permissions"          -> calls a tool that doesn't exist (set_autonomy)
  without tools (JSON protocol)             -> answers with a ```prime-action block
  anything else                             -> streams "Hello from the mock."
"""
import json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, LOG = int(sys.argv[1]), sys.argv[2]


def text_of(m):
    c = m.get("content")
    if isinstance(c, list):
        return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
    return c or ""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.endswith("/models"):
            return self.send_json(200, {"data": [{"id": "mock-tools"}, {"id": "no-tools"}]})
        self.send_json(404, {"error": "no"})

    def sse(self, chunks):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for ch in chunks:
            self.wfile.write(b"data: " + json.dumps({"choices": [{"index": 0, "delta": ch}]}).encode() + b"\n\n")
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        with open(LOG, "a") as f:
            f.write(json.dumps({"auth": self.headers.get("Authorization", ""), "body": body}) + "\n")
        msgs = body.get("messages", [])
        last = msgs[-1] if msgs else {}
        tools = body.get("tools")
        if not body.get("stream"):
            return self.send_json(200, {"choices": [{"index": 0, "message": {"role": "assistant", "content": "ok"}}]})
        if tools and body.get("model") == "no-tools":
            return self.send_json(400, {"error": {"message": "tools are not supported by this model"}})
        utext = text_of(last)
        if last.get("role") == "tool" or utext.startswith("[tool result]"):
            res = text_of(last).replace("[tool result] ", "")
            try:
                st = json.loads(res).get("status")
            except ValueError:
                st = "?"
            return self.sse([{"content": "All set: "}, {"content": f"{st}."}])
        call = None
        low = utext.lower()
        if "accent" in low:
            call = ("set_accent", {"color": "blue"})
        elif "shortcut" in low:
            call = ("add_shortcut", {"keys": "Super+Shift+Y", "action": "prime", "target": "files"})
        elif "permissions" in low:
            call = ("set_autonomy", {"level": "auto-all"})
        if call and tools:
            a = json.dumps(call[1])
            return self.sse([
                {"role": "assistant", "content": ""},
                {"tool_calls": [{"index": 0, "id": "call_1", "type": "function",
                                 "function": {"name": call[0], "arguments": a[:7]}}]},
                {"tool_calls": [{"index": 0, "function": {"arguments": a[7:]}}]},
            ])
        if call:
            block = "```prime-action\n" + json.dumps({"tool": call[0], "args": call[1]}) + "\n```"
            return self.sse([{"content": "Sure, one moment.\n"}, {"content": block[:12]}, {"content": block[12:]}])
        self.sse([{"content": "Hello "}, {"content": "from the mock."}])


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
