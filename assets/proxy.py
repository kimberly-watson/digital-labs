#!/usr/bin/env python3
"""
Lab Tutor proxy — forwards chat requests to the Anthropic API.
API key is read from the CLAUDE_API_KEY environment variable,
which is injected at service start from /etc/lab-tutor.env (root:root 600).
The key is never written to disk or logged.
"""
import json, os, base64, urllib.request, urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

MODEL    = "claude-sonnet-4-20250514"
HTML_FILE = "/opt/sonatype/tutor/index.html"
API_KEY  = os.environ.get("CLAUDE_API_KEY", "")

# TUTOR_SYSTEM_PROMPT_B64 is base64-encoded so systemd EnvironmentFile
# doesn't silently truncate it at the first newline.
_prompt_b64 = os.environ.get("TUTOR_SYSTEM_PROMPT_B64", "")
SYSTEM_PROMPT = base64.b64decode(_prompt_b64).decode("utf-8") if _prompt_b64 else os.environ.get("TUTOR_SYSTEM_PROMPT", "")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_OPTIONS(self):
        origin = f"http://{self.headers.get('Host', 'localhost').split(':')[0]}"
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", origin)
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

        # Enforce browser-only access at the application layer
        ua = self.headers.get("User-Agent", "")
        if "Mozilla" not in ua:
            self.send_response(403)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Browser access only.")
            return

        try:
            length   = int(self.headers.get("Content-Length", 0))
            body     = json.loads(self.rfile.read(length))
            messages = body.get("messages", [])

            # Sanitize context fields — strip control characters and cap length
            # to prevent prompt injection via client-supplied product/pageUrl.
            def sanitize(val, max_len=200):
                if not isinstance(val, str):
                    return ""
                # Remove newlines, carriage returns, and other control chars
                cleaned = "".join(c for c in val if c >= " " and c != "\x7f")
                return cleaned[:max_len].strip()

            product  = sanitize(body.get("product", ""))
            page_url = sanitize(body.get("pageUrl", ""))

            # Allowlist: only accept known lab product names — prevents a crafted
            # product string from injecting arbitrary text into the system prompt.
            ALLOWED_PRODUCTS = {"Nexus Repository", "IQ Server"}
            if product not in ALLOWED_PRODUCTS:
                product = ""

            system   = SYSTEM_PROMPT
            if product:
                context = f"\n\nContext: the user is currently viewing {product}"
                if page_url:
                    context += f" at {page_url}"
                context += ". Tailor your guidance and examples to that interface and page."
                system = system + context
            payload  = json.dumps({
                "model":      MODEL,
                "max_tokens": 1024,
                "system":     system,
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
            # Lock CORS to same host — prevents cross-origin callers from
            # using this as an open proxy to the Claude API key.
            origin = f"http://{self.headers.get('Host', 'localhost').split(':')[0]}"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.send_header("Access-Control-Allow-Origin", origin)
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
