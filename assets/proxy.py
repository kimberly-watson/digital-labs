#!/usr/bin/env python3
"""
Lab Tutor proxy — forwards chat requests to the Anthropic API.
API key is read from the CLAUDE_API_KEY environment variable,
which is injected at service start from /etc/lab-tutor.env (root:root 600).
The key is never written to disk or logged.
"""
import json, os, urllib.request, urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

MODEL         = "claude-sonnet-4-20250514"
HTML_FILE     = "/opt/sonatype/tutor/index.html"
API_KEY       = os.environ.get("CLAUDE_API_KEY", "")
SYSTEM_PROMPT = os.environ.get("TUTOR_SYSTEM_PROMPT", "")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        try:
            with open(HTML_FILE, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_error(500, str(e))

    def do_POST(self):
        if self.path != "/chat":
            self.send_error(404)
            return
        try:
            length   = int(self.headers.get("Content-Length", 0))
            body     = json.loads(self.rfile.read(length))
            messages = body.get("messages", [])
            payload  = json.dumps({
                "model":      MODEL,
                "max_tokens": 1024,
                "system":     SYSTEM_PROMPT,
                "messages":   messages
            }).encode()
            req = urllib.request.Request(
                "https://api.anthropic.com/v1/messages",
                data    = payload,
                headers = {
                    "Content-Type":      "application/json",
                    "x-api-key":         API_KEY,
                    "anthropic-version": "2023-06-01"
                },
                method = "POST"
            )
            with urllib.request.urlopen(req) as resp:
                result = json.loads(resp.read())
            reply = result["content"][0]["text"]
            out   = json.dumps({"reply": reply}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(out)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            print(f"Anthropic API error {e.code}: {body}")
            err = json.dumps({"reply": f"API error {e.code} — check server logs."}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)
        except Exception as e:
            print(f"Unexpected error: {e}")
            err = json.dumps({"reply": "An unexpected error occurred."}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)


if __name__ == "__main__":
    if not API_KEY:
        raise RuntimeError("CLAUDE_API_KEY environment variable is not set.")
    print(f"Lab Tutor proxy listening on port 8090 (model: {MODEL})")
    HTTPServer(("", 8090), Handler).serve_forever()
