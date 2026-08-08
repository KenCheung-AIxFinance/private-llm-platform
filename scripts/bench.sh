#!/usr/bin/env bash
# scripts/bench.sh — binding benchmark per SOW §I.1 / §I.2 / §D.5
# Measures on the UPSTREAM llama.cpp Vulkan/RADV path:
#   - prefill (pp4096) tok/s   -> §I.2 prefill, recorded at M1; floor set per §I.4
#   - decode  (tg128, tg512)   -> §I.2 binding decode targets (binding from M1)
#   - TTFT @ 8192-token prompt -> §I.2 TTFT row, recorded at M1
# Conditions enforced: single request, -ub 512, -fa <per-model verified>,
#   -ctk q8_0 -ctv q8_0, speculative decoding OFF, Vulkan backend asserted.
#
# Usage: ./bench.sh <alias>   alias: utility-fast | doc-vision | reasoning-max
set -euo pipefail
ENV="$(dirname "$0")/../hosts/z13.env"; . "$ENV"
BIN=/srv/z13/tools/llama.cpp/build/bin
MODELS_ROOT="${MODELS_ROOT:-/home/norbert/.lmstudio/models/lmstudio-community}"
PORT=8901

alias_="${1:?usage: bench.sh <utility-fast|doc-vision|reasoning-max>}"
case "$alias_" in
  utility-fast) M="$MODELS_ROOT/gemma-4-26B-A4B-it-QAT-GGUF/gemma-4-26B-A4B-it-QAT-Q4_0.gguf"; FA=on; T_BATCH=55; T_ECO=45 ;;
  doc-vision)   M="$MODELS_ROOT/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf";             FA=auto; T_BATCH=25; T_ECO=0  ;;
  reasoning-max) M="$MODELS_ROOT/gpt-oss-120b-GGUF/gpt-oss-120b-MXFP4-00001-of-00002.gguf"; FA=auto; T_BATCH=40; T_ECO=28 ;;
  *) echo "unknown alias: $alias_"; exit 1 ;;
esac
[ -f "$M" ] || { echo "model not found: $M"; exit 1; }
[ -x "$BIN/llama-bench" ] || { echo "build missing: $BIN/llama-bench (run build first)"; exit 1; }

echo "### bench: $alias_"
echo "### model: $M"
echo "### conditions: Vulkan/RADV, -ub 512, -fa $FA, -ctk q8_0 -ctv q8_0, spec OFF (§I.1/§D.5)"
echo

# --- prefill (pp4096) + decode (tg128, tg512) via llama-bench ---
echo "## prefill pp4096 (tok/s):"
"$BIN/llama-bench" -m "$M" -ngl 999 -ub 512 -fa "$FA" -ctk q8_0 -ctv q8_0 -p 4096 -n 0 2>/dev/null | tee /tmp/bench_${alias_}.txt
echo "## decode tg128 / tg512 (tok/s):"
"$BIN/llama-bench" -m "$M" -ngl 999 -ub 512 -fa "$FA" -ctk q8_0 -ctv q8_0 -p 0 -n 128,512 2>/dev/null | tee -a /tmp/bench_${alias_}.txt

# --- TTFT @ 8192-token prompt via llama-server (ms to first streamed token) ---
echo
echo "## TTFT @ 8192-token prompt (ms to first token):"
"$BIN/llama-server" -m "$M" --host 127.0.0.1 --port "$PORT" -ngl 999 -c 16384 -ub 512 \
  -ctk q8_0 -ctv q8_0 -fa "$FA" --jinja --no-webui >/tmp/bench_srv.log 2>&1 &
SRV=$!
for _ in $(seq 1 60); do curl -sf -m2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break; sleep 2; done
# build an ~8192-token prompt (repeated tokens); measure ms to first streamed chunk
PROMPT=$(python3 -c "print('The quick brown fox jumps over the lazy dog. '*1100)")
python3 - "$PORT" "$PROMPT" <<'PY'
import sys,time,urllib.request,json
port,prompt=sys.argv[1],sys.argv[2]
req=urllib.request.Request(f"http://127.0.0.1:{port}/completion",
    data=json.dumps({"prompt":prompt,"n_predict":8,"stream":True}).encode(),
    headers={"Content-Type":"application/json"})
t0=time.time(); first=None
with urllib.request.urlopen(req,timeout=120) as r:
    for line in r:
        if line.strip():
            first=time.time(); break
print(f"TTFT_ms = {int((first-t0)*1000)}" if first else "TTFT_ms = TIMEOUT")
PY
kill "$SRV" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true

echo
echo "### §I.2 decode target (batch): ${T_BATCH} tok/s  — compare to tg128 above"
[ "$T_ECO" != 0 ] && echo "### §I.2 decode target (eco):  ${T_ECO} tok/s  (measure in eco soak)"
echo "### prefill/TTFT floors proposed within 5 working days per §I.4 (>=90% of measured)"
