#!/usr/bin/env python3
import json, os, urllib.request, urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

API_KEY = os.environ.get("CLAUDE_API_KEY", "")
MODEL = "claude-sonnet-4-20250514"
HTML_FILE = "/opt/sonatype/tutor/index.html"
SYSTEM_PROMPT = os.environ.get("TUTOR_SYSTEM_PROMPT", "")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass
    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
    def do_GET(self):
        try:
            with open(HTML_FILE, "rb") as f: content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except Exception as e: self.send_error(500, str(e))
    def do_POST(self):
        if self.path != "/chat":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            messages = body.get("messages", [])
            payload = json.dumps({"model": MODEL, "max_tokens": 1024, "system": SYSTEM_PROMPT, "messages": messages}).encode()
            req = urllib.request.Request("https://api.anthropic.com/v1/messages", data=payload,
                headers={"Content-Type": "application/json", "x-api-key": API_KEY, "anthropic-version": "2023-06-01"}, method="POST")
            with urllib.request.urlopen(req) as resp: result = json.loads(resp.read())
            reply = result["content"][0]["text"]
            out = json.dumps({"reply": reply}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(out)
        except Exception as e:
            err = json.dumps({"reply": "Sorry, I could not process that request."}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)

if __name__ == "__main__":
    print("Tutor proxy listening on port 8090...")
    HTTPServer(("", 8090), Handler).serve_forever()
