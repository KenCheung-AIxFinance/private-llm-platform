#!/usr/bin/env python3
"""
Universal cloud provider proxy for llama-swap - configuration-driven from config.yaml

Supports ANY OpenAI-compatible API endpoint (Kimi, DeepSeek, OpenAI, Azure, custom, etc.)
Only ONE source of truth: /srv/z13/llama-swap/config.yaml

To add ANY cloud model:
1. Edit config.yaml, add entry under models: with provider/base_url/model/api_key_env
2. Set API key via systemd override or environment
3. Restart llama-swap

Compatible with:
- OpenAI (api.openai.com)
- Moonshot/Kimi (api.moonshot.cn)
- DeepSeek (api.deepseek.com)
- Azure OpenAI (your-resource.openai.azure.com)
- Custom OpenAI-compatible endpoints (vLLM, Ollama cloud, etc.)
"""
import os, sys, json, http.server, urllib.request, urllib.error, yaml, re

CONFIG_PATH = "/srv/z13/llama-swap/config.yaml"

def load_cloud_providers():
    """
    Load ALL provider configs from llama-swap config.yaml.
    Supports:
    - provider: openai (OpenAI, Kimi, DeepSeek, custom OpenAI-compatible)
    - provider: azure (Azure OpenAI with deployment_name)
    - provider: anthropic (Claude)
    - provider: google (Gemini)
    - provider: custom (generic OpenAI-compatible)
    """
    try:
        with open(CONFIG_PATH) as f:
            cfg = yaml.safe_load(f)

        providers = {}
        for alias, model_cfg in cfg.get("models", {}).items():
            if "provider" not in model_cfg:
                continue

            provider_type = model_cfg["provider"]
            prov = {
                "type": provider_type,
                "base_url": model_cfg.get("base_url"),
                "model": model_cfg.get("model", alias),
                "api_key_env": model_cfg.get("api_key_env"),
                "api_version": model_cfg.get("api_version", "2024-02-15-preview"),  # Azure
                "deployment_name": model_cfg.get("deployment_name"),  # Azure
                "custom_headers": model_cfg.get("custom_headers", {}),  # Custom headers
            }

            # Auto-detect endpoint type from base_url if provider type is generic
            if provider_type == "openai":
                if "moonshot" in prov["base_url"]:
                    prov["endpoint_type"] = "moonshot"
                elif "deepseek" in prov["base_url"]:
                    prov["endpoint_type"] = "deepseek"
                elif "azure" in prov["base_url"]:
                    prov["endpoint_type"] = "azure"
                else:
                    prov["endpoint_type"] = "openai"
            else:
                prov["endpoint_type"] = provider_type

            providers[alias] = prov

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
            models = []
            for alias, prov in providers.items():
                models.append({
                    "id": alias,
                    "object": "model",
                    "owned_by": prov["endpoint_type"],
                    "provider": prov["type"],
                    "base_url": prov["base_url"]
                })
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

            # Reload config on each request (allows hot-reload)
            providers = load_cloud_providers()

            if alias not in providers:
                self._err(400, f"Unknown cloud alias: {alias}. Available: {list(providers.keys())}")
                return

            prov = providers[alias]

            # Validate required fields
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
                    f"Set it via systemd override: /etc/systemd/system/llama-swap.service.d/cloud-{alias}.conf",
                    "authentication_error",
                    "key_missing"
                )
                return

            # Build upstream request based on provider type
            upstream_req = self._build_upstream_request(prov, req_data, key)

            try:
                with urllib.request.urlopen(upstream_req, timeout=60) as resp:
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

    def _build_upstream_request(self, prov, req_data, api_key):
        """Build upstream request based on provider type"""
        upstream_data = req_data.copy()
        upstream_data["model"] = prov["model"]

        # Build URL
        if prov["endpoint_type"] == "azure":
            # Azure OpenAI format
            deployment = prov.get("deployment_name", prov["model"])
            version = prov.get("api_version", "2024-02-15-preview")
            base = prov["base_url"].rstrip("/")
            url = f"{base}/openai/deployments/{deployment}/chat/completions?api-version={version}"
        else:
            # Standard OpenAI-compatible endpoint
            url = prov["base_url"]

        # Build headers
        headers = {
            "Content-Type": "application/json"
        }

        # Provider-specific auth headers
        if prov["endpoint_type"] == "azure":
            headers["api-key"] = api_key
        elif prov["endpoint_type"] == "google":
            # Google uses API key in URL params
            url = f"{url}?key={api_key}"
            # Convert OpenAI format to Gemini format
            upstream_data = self._convert_to_gemini_format(upstream_data)
        elif prov["endpoint_type"] == "anthropic":
            headers["x-api-key"] = api_key
            headers["anthropic-version"] = "2023-06-01"
            # Convert to Anthropic format
            upstream_data = self._convert_to_anthropic_format(upstream_data)
        else:
            # Standard Bearer token (OpenAI, Moonshot, DeepSeek, etc.)
            headers["Authorization"] = f"Bearer {api_key}"

        # Add custom headers if specified
        if prov.get("custom_headers"):
            headers.update(prov["custom_headers"])

        return urllib.request.Request(url, json.dumps(upstream_data).encode(), headers)

    def _convert_to_gemini_format(self, openai_data):
        """Convert OpenAI chat format to Google Gemini format"""
        # Gemini uses different message format
        messages = openai_data.get("messages", [])
        gemini_messages = []

        for msg in messages:
            role = msg.get("role", "user")
            if role == "system":
                # Gemini doesn't have system role, prepend to first user message
                continue
            elif role == "assistant":
                role = "model"

            gemini_messages.append({
                "role": role,
                "parts": [{"text": msg.get("content", "")}]
            })

        return {
            "contents": gemini_messages,
            "generationConfig": {
                "maxOutputTokens": openai_data.get("max_tokens", 100),
                "temperature": openai_data.get("temperature", 0.7)
            }
        }

    def _convert_to_anthropic_format(self, openai_data):
        """Convert OpenAI chat format to Anthropic messages format"""
        # Anthropic uses max_tokens (required) and different structure
        return {
            "model": openai_data.get("model"),
            "max_tokens": openai_data.get("max_tokens", 1024),
            "messages": openai_data.get("messages", []),
            "temperature": openai_data.get("temperature", 0.7)
        }

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
    print(f"Universal cloud proxy starting on 127.0.0.1:{port}", file=sys.stderr)
    print(f"Reading configs from: {CONFIG_PATH}", file=sys.stderr)

    providers = load_cloud_providers()
    if providers:
        print(f"Loaded {len(providers)} cloud provider(s):", file=sys.stderr)
        for alias, prov in providers.items():
            print(f"  - {alias}: {prov['endpoint_type']} ({prov['base_url']})", file=sys.stderr)
    else:
        print("WARNING: No cloud providers found", file=sys.stderr)

    http.server.HTTPServer(("127.0.0.1", port), CloudProxyHandler).serve_forever()
