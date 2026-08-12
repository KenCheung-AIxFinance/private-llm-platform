#!/usr/bin/env python3
# scripts/cloud-stub.py — keyless cloud-alias stub (SOW §C.3 / §E.11 / §0.4)
# Cloud aliases (cloud-kimi-k3, cloud-fable-5, cloud-deepseek-v4-pro, cloud-qwen,
# cloud-gemini) are present and discoverable in /v1/models, but return a clean
# HTTP 401 "key missing" on any inference call until the Owner adds provider keys
# at go-live. Dependency-free stdlib HTTP server; managed by llama-swap like any
# other model.  /health and /v1/models -> 200; everything under /v1/ -> 401.
import http.server, json, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 0
KEYLESS = (b"", 401, {
    "error": {"message": "cloud alias keyless until go-live (SOW §C.3/§0.4); Owner adds provider key",
              "type": "authentication_error", "code": "key_missing"}})

class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if self.path in ("/health", "/v1/models"):
            self._send(200, {"object": "list", "data": [{"id": "cloud-aliases", "object": "model",
                        "owned_by": "keyless-until-go-live"}]})
        else:
            self._send(401, KEYLESS[2])
    def do_POST(self):
        # any /v1/chat/completions, /v1/messages, /v1/embeddings -> clean 401 key-missing
        self._send(401, KEYLESS[2])
    def log_message(self, *a):  # quiet
        pass

if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", PORT), H).serve_forever()
