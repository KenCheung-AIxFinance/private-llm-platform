#!/usr/bin/env python3
"""
Cloud provider proxy for llama-swap - configuration-driven from config.yaml
Only ONE source of truth: /srv/z13/llama-swap/config.yaml

To add a new cloud model:
1. Edit config.yaml, add entry under models: with provider/base_url/api_key_env
2. Restart llama-swap (this script auto-reloads config on each request)
"""
import os, sys, json, http.server, urllib.request, urllib.error, yaml

CONFIG_PATH = "/srv/z13/llama-swap/config.yaml"

def load_cloud_providers():
    """Load cloud provider configs from llama-swap config.yaml"""
    try:
        with open(CONFIG_PATH) as f:
            cfg = yaml.safe_load(f)

        providers = {}
        for alias, model_cfg in cfg.get("models", {}).items():
            # Only include models with provider field (cloud models)
            if "provider" in model_cfg:
                providers[alias] = {
                    "base_url": model_cfg.get("base_url"),
                    "model": model_cfg.get("model", alias),
                    "api_key_env": model_cfg.get("api_key_env"),
                    "provider": model_cfg.get("provider")
                }
        return providers
    except Exception as e:
        print(f"Failed to load config from {CONFIG_PATH}: {e}", file=sys.stderr)
        return {}

class CloudProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        elif self.path == "/v1/models":
            providers = load_cloud_providers()
            models = [{"id": alias, "object": "model", "owned_by": "cloud"}
                     for alias in providers.keys()]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"data": models}).encode())
        else:
            self.send_error(404)

    def do_POST(self):
        if not self.path.startswith("/v1/chat/completions"):
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            req_data = json.loads(body)
            alias = req_data.get("model", "")

            # Reload config on each request (allows hot-reload without restart)
            providers = load_cloud_providers()

            if alias not in providers:
                self._err(400, f"Unknown cloud alias: {alias}. Available: {list(providers.keys())}")
                return

            prov = providers[alias]

            # Check required fields
            if not prov.get("base_url"):
                self._err(500, f"Config error: {alias} missing base_url")
                return
            if not prov.get("api_key_env"):
                self._err(500, f"Config error: {alias} missing api_key_env")
                return

            # Get API key from environment
            key = os.getenv(prov["api_key_env"])
            if not key:
                self._err(
                    401,
                    f"Cloud alias '{alias}' requires {prov['api_key_env']} environment variable. "
                    f"Owner: export {prov['api_key_env']}='sk-...' before starting llama-swap",
                    "authentication_error",
                    "key_missing"
                )
                return

            # Prepare upstream request
            upstream = req_data.copy()
            upstream["model"] = prov["model"]

            # Forward to cloud API
            req = urllib.request.Request(
                prov["base_url"],
                json.dumps(upstream).encode(),
                {
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {key}"
                }
            )

            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    self.send_response(resp.status)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(resp.read())
            except urllib.error.HTTPError as e:
                # Forward upstream error as-is
                self.send_response(e.code)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(e.read())
            except urllib.error.URLError as e:
                self._err(502, f"Cloud API unreachable: {str(e)}")

        except json.JSONDecodeError:
            self._err(400, "Invalid JSON in request body")
        except Exception as e:
            self._err(500, f"Proxy error: {str(e)}")

    def _err(self, code, msg, typ="invalid_request_error", ec=None):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        err = {"error": {"message": msg, "type": typ, "code": ec or f"http_{code}"}}
        self.wfile.write(json.dumps(err).encode())

    def log_message(self, format, *args):
        sys.stderr.write(f"[cloud-proxy] {format % args}\n")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: cloud-proxy.py <port>", file=sys.stderr)
        sys.exit(1)

    port = int(sys.argv[1])
    print(f"Cloud proxy starting on 127.0.0.1:{port}", file=sys.stderr)
    print(f"Reading cloud configs from: {CONFIG_PATH}", file=sys.stderr)

    # Show loaded providers at startup
    providers = load_cloud_providers()
    if providers:
        print(f"Loaded {len(providers)} cloud provider(s): {list(providers.keys())}", file=sys.stderr)
    else:
        print("WARNING: No cloud providers found in config (add models with 'provider' field)", file=sys.stderr)

    http.server.HTTPServer(("127.0.0.1", port), CloudProxyHandler).serve_forever()
