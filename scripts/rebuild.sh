#!/usr/bin/env bash
# scripts/rebuild.sh — M3 installer: clean host -> full platform (fresh-install experience)
# Idempotent. The M3.1 "clean rebuild from repo + manifest alone" entry point.
#
# Usage (on a fresh host, after: git clone <repo> /srv/z13 && git submodule update --init):
#   cd /srv/z13
#   ./scripts/rebuild.sh [--host <name>] [--llama build|prebuilt] \
#                        [--weights resident|all|skip] [--inference auto|vulkan|cpu] [--yes]
#
# Flow: init-host -> bootstrap -> clone/submodule -> runtimes -> weights -> secrets ->
#       host bits -> systemd -> start -> verify.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOST_NAME="$(hostname)"; LLAMA="build"; WEIGHTS="resident"; INFER="auto"; YES=0
while [ $# -gt 0 ]; do case "$1" in
  --host) HOST_NAME="$2"; shift 2;;
  --llama) LLAMA="$2"; shift 2;;
  --weights) WEIGHTS="$2"; shift 2;;
  --inference) INFER="$2"; shift 2;;
  --yes|-y) YES=1; shift;;
  *) echo "unknown arg: $1"; exit 2;;
esac; done

S(){ echo; echo "========== [rebuild] $* =========="; }
ask(){ [ "$YES" = 1 ] && return 0; read -r -p "$1 [Y/n] " r; [[ "${r:-Y}" =~ ^[Yy] ]]; }

# --- 0. new-machine base init + GPU driver -------------------------------------
S "0/8 init-host (base machine + GPU driver)"
[ -x scripts/init-host.sh ] && sudo bash scripts/init-host.sh "$HOST_NAME" || echo "skip (no init-host.sh)"
[ -f "hosts/${HOST_NAME}.env" ] && . "hosts/${HOST_NAME}.env" || true
[ "$INFER" = "auto" ] && INFER="${INFERENCE:-cpu}"
echo ">>> inference path: $INFER"

# --- 1. platform deps ----------------------------------------------------------
S "1/8 bootstrap (platform deps)"
sudo bash scripts/bootstrap.sh

# --- 2. repo already present? (we run from /srv/z13) ----------------------------
S "2/8 repo + submodule"
if [ ! -d "$ROOT/.git" ]; then
  echo ">>> not inside a git checkout — run from the cloned repo root (/srv/z13)."
  echo ">>> (on a fresh host: git clone <repo-url> /srv/z13 && git submodule update --init)"
fi
git -C "$ROOT" submodule update --init 2>/dev/null || true

# --- 3. runtimes (llama.cpp + llama-swap + node/uv) ----------------------------
S "3/8 runtimes (per manifests/runtimes.yaml)"
# llama.cpp (Vulkan build at pinned commit)
LCPP=/srv/z13/tools/llama.cpp
COMMIT=$(python3 -c "import yaml;print(yaml.safe_load(open('manifests/runtimes.yaml'))['llama_cpp']['commit'])" 2>/dev/null || echo 6a32c29a746a2e44de463de647f9f6661eb5086b)
if [ "$LLAMA" = "build" ] && [ ! -x "$LCPP/build/bin/llama-server" ]; then
  echo ">>> building llama.cpp (Vulkan) @ ${COMMIT:0:8} (this takes a few minutes)"
  env -u http_proxy -u https_proxy -u all_proxy git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LCPP" 2>/dev/null || true
  ( cd "$LCPP" && git fetch --depth 1 origin "$COMMIT" 2>/dev/null && git checkout -q "$COMMIT" 2>/dev/null || true )
  ( cd "$LCPP" && cmake -S . -B build -G Ninja -DGGML_VULKAN=ON -DGGML_NATIVE=ON -DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release \
      && cmake --build build --config Release -j"$(nproc)" )
fi
[ -x "$LCPP/build/bin/llama-server" ] && echo ">>> llama-server: $($LCPP/build/bin/llama-server --version 2>/dev/null | head -1 || echo present)"
# llama-swap binary (tracked in git at tools/llama-swap/)
[ -x /srv/z13/tools/llama-swap/llama-swap ] && echo ">>> llama-swap: present ($( /srv/z13/tools/llama-swap/llama-swap --version 2>/dev/null | head -1))"
# node + uv (Hermes runtime)
command -v node >/dev/null && echo ">>> node: $(node -v)" || echo ">>> node: MISSING (bootstrap [4/6] should have installed)"
command -v uv >/dev/null && echo ">>> uv: $(uv --version 2>/dev/null | head -1)" || echo ">>> uv: install manually if Hermes venv build needs it"
command -v uv >/dev/null 2>&1 && ( cd /srv/z13/hermes/hermes-agent 2>/dev/null && uv tool install browser-use >/dev/null 2>&1 || true )

# --- 4. model weights -----------------------------------------------------------
S "4/8 model weights (--weights $WEIGHTS)"
[ "$WEIGHTS" != "skip" ] && bash scripts/fetch-models.sh "--only" "$WEIGHTS" || echo ">>> weights skipped"

# --- 5. secrets -----------------------------------------------------------------
S "5/8 secrets (Owner-provisioned, §0.4 — never from git)"
if [ ! -f /srv/z13/hermes/.env ]; then
  if ask "Hermes .env missing. Provision now?"; then
    echo ">>> create /srv/z13/hermes/.env (0600) with provider/API keys, then re-run."
  else
    echo ">>> continuing WITHOUT secrets (local aliases still work; cloud + Hermes provider limited)"
  fi
fi

# --- 6. host bits ----------------------------------------------------------------
S "6/8 host bits (hosts/${HOST_NAME}.env + sshd)"
# sshd ListenAddress re-pin to this host's Tailscale IP (§4.1 rebuild.md)
if command -v tailscale >/dev/null 2>&1 && ip=$(tailscale ip -4 2>/dev/null | head -1) && [ -n "$ip" ]; then
  if grep -qE '^ListenAddress ' /etc/ssh/sshd_config 2>/dev/null; then
    echo ">>> re-pin sshd ListenAddress -> $ip"
    sudo sed -i -E "s/^ListenAddress .*/ListenAddress $ip/" /etc/ssh/sshd_config
    sudo systemctl daemon-reload 2>/dev/null; sudo systemctl restart ssh.socket 2>/dev/null || true
  fi
fi

# --- 7. systemd units -------------------------------------------------------------
S "7/8 systemd (llama-swap + z13-stack + hermes)"
sudo cp systemd/llama-swap.service systemd/z13-stack.service systemd/hermes.service /etc/systemd/system/ 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl enable llama-swap z13-stack 2>/dev/null || true

# --- 8. start + verify ------------------------------------------------------------
S "8/8 start + verify"
sudo systemctl start llama-swap 2>/dev/null || sudo systemctl restart llama-swap || true
for i in $(seq 1 30); do
  curl -sf -m2 http://127.0.0.1:8080/v1/models >/dev/null 2>&1 && { echo ">>> llama-swap ready (${i}0s)"; break; } || sleep 10
done
echo ">>> aliases:"
curl -s http://127.0.0.1:8080/v1/models 2>/dev/null | python3 -c "import sys,json;[print('  -',m['id']) for m in json.load(sys.stdin).get('data',[])]" 2>/dev/null || echo ">>> (llama-swap not answering yet — check: sudo journalctl -u llama-swap -n 30)"
echo
echo ">>> REBUILD COMPLETE for host '${HOST_NAME}' (inference=${INFER})."
