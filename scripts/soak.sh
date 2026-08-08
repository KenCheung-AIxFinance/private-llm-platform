#!/usr/bin/env bash
# scripts/soak.sh — 30-min sustained-decode soak (SOW §I.1 / §I.5 / M1 lines 5+6)
# One harness produces BOTH:
#   - the §I.2 decode number for <alias> under <profile>  (binding from M1)
#   - the §I.5 W/°C evidence that the profile holds its bracket
# Procedure: apply profile -> settle -> fork 1 Hz sensor CSV logger -> run a
# continuously-decoding llama-server for DURATION -> stop -> compute steady-state
# (mean/p95 of PPT + max temp over minutes 10..end) + tok/s stats + throttle events.
#
# Usage: ./soak.sh <profile> <alias> [duration_sec=1800]
#   profile: batch | eco       (run with sudo; powerctl writes sysfs)
#   alias:   utility-fast | doc-vision | reasoning-max
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/../hosts/z13.env"
BIN=/srv/z13/tools/llama.cpp/build/bin
MODELS_ROOT="${MODELS_ROOT:-/home/norbert/.lmstudio/models/lmstudio-community}"
PORT=8902; TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)"
RUNS=/srv/z13/runs; mkdir -p "$RUNS"

profile="${1:?usage: soak.sh <batch|eco> <alias> [duration_sec]}"
alias_="${2:?usage: soak.sh <batch|eco> <alias> [duration_sec]}"
DUR="${3:-1800}"
case "$alias_" in
  utility-fast)  M="$MODELS_ROOT/gemma-4-26B-A4B-it-QAT-GGUF/gemma-4-26B-A4B-it-QAT-Q4_0.gguf"; FA=auto ;;
  doc-vision)    M="$MODELS_ROOT/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf";             FA=auto ;;
  reasoning-max) M="$MODELS_ROOT/gpt-oss-120b-GGUF/gpt-oss-120b-MXFP4-00001-of-00002.gguf";                   FA=auto ;;
  *) echo "unknown alias"; exit 1 ;;
esac
[ -x "$BIN/llama-server" ] || { echo "build missing"; exit 1; }

CSV="$RUNS/soak_${profile}_${alias_}_${TS}.csv"
TOK="$RUNS/soak_${profile}_${alias_}_${TS}.tok"
SUM="$RUNS/soak_${profile}_${alias_}_${TS}.summary.txt"
PROMPT=$(python3 -c "print('Photosynthesis converts light energy into chemical energy stored in glucose, using carbon dioxide and water, while releasing oxygen as a byproduct. Explain the light-dependent reactions and the Calvin cycle in detail. '*60)")

echo "### soak: profile=$profile alias=$alias_ duration=${DUR}s"
echo "### model: $M"
echo "### CSV -> $CSV"

# 1) apply profile (needs root for sysfs)
sudo "$DIR/powerctl.sh" "$profile" || echo "(powerctl $profile returned nonzero — continuing)"

# 2) 1 Hz sensor logger (background); values via awk -v to avoid shell interpolation
(
  echo "epoch,ppt_w,gpu_c,cpu_c,nvme_c,fan_cpu,fan_gpu,bat_w"
  while :; do
    p=$(cat "$S_AMDGPU_POWER" 2>/dev/null || echo 0)
    tg=$(cat "$S_AMDGPU_TEMP" 2>/dev/null || echo 0)
    tc=$(cat "$S_K10TEMP" 2>/dev/null || echo 0)
    tn=$(cat "$S_NVME_TEMP" 2>/dev/null || echo 0)
    fc=$(cat "$S_FAN_CPU" 2>/dev/null || echo 0)
    fg=$(cat "$S_FAN_GPU" 2>/dev/null || echo 0)
    bw=$(cat "$S_BAT_POWER" 2>/dev/null || echo 0)
    awk -v t="$(date +%s)" -v p="$p" -v tg="$tg" -v tc="$tc" -v tn="$tn" -v fc="$fc" -v fg="$fg" -v bw="$bw" \
      'BEGIN{printf "%d,%.1f,%.1f,%.1f,%.1f,%d,%d,%.1f\n", t, p/1000000, tg/1000, tc/1000, tn/1000, fc, fg, bw/1000000}' >> "$CSV"
    sleep 1
  done
) & LOGGER=$!

# 3) resident llama-server + continuous decode for DURATION (wall clock)
"$BIN/llama-server" -m "$M" --host 127.0.0.1 --port "$PORT" -ngl 999 -c 16384 -ub 512 \
  -ctk q8_0 -ctv q8_0 -fa "$FA" --jinja --no-webui >/tmp/soak_srv.log 2>&1 & SRV=$!
for _ in $(seq 1 90); do curl -sf -m2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && break; sleep 2; done
END=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$END" ]; do
  curl -sf -m 120 "http://127.0.0.1:$PORT/completion" \
    -H 'Content-Type: application/json' \
    -d "{\"prompt\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT"),\"n_predict\":512,\"temperature\":0.0,\"seed\":42,\"stream\":false}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); t=d.get('timings',{}); print(t.get('predicted_per_second',0))" >> "$TOK" 2>/dev/null || echo "0" >> "$TOK"
done

# 4) stop
kill "$SRV" "$LOGGER" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true
sudo "$DIR/powerctl.sh" status > "$RUNS/soak_${profile}_${alias_}_${TS}.poststatus.txt" 2>&1 || true

# 5) steady-state analysis (skip first 600s warmup)
python3 - "$CSV" "$TOK" "$SUM" "$profile" "$alias_" <<'PY'
import sys,statistics
csv,tok,sumf,profile,alias_=sys.argv[1:6]
rows=[r.split(",") for r in open(csv).read().splitlines()[1:] if "," in r]
rows=[r for r in rows if len(r)==8]
ss=rows[600:] if len(rows)>600 else rows
def stats(idx):
    v=[float(r[idx]) for r in ss if r[idx] not in ("","0")]
    if not v: return ("n/a",)*4
    v2=sorted(v); p95=v2[min(len(v2)-1,int(len(v2)*0.95))]
    return (statistics.mean(v), p95, min(v), max(v))
ppt=stats(1); gpu=stats(2); cpu=stats(3)
tk=[float(x) for x in open(tok).read().split() if x not in ("","0")]
tkmean=statistics.mean(tk) if tk else 0; tkmin=min(tk) if tk else 0
ev=0
for i in range(60,len(rows)):
    m=statistics.mean([float(rows[j][1]) for j in range(i-60,i)])
    if float(rows[i][1]) < 0.85*m: ev+=1
with open(sumf,"w") as f:
    f.write(f"soak profile={profile} alias={alias_}\n")
    f.write(f"samples_total={len(rows)} steady_state_samples={len(ss)}\n")
    f.write(f"PPT_W steady-state: mean={ppt[0]:.1f} p95={ppt[1]:.1f} min={ppt[2]:.1f} max={ppt[3]:.1f}\n")
    f.write(f"GPU_edge_C: mean={gpu[0]:.1f} max={gpu[3]:.1f} | CPU_Tctl_C: mean={cpu[0]:.1f} max={cpu[3]:.1f}\n")
    f.write(f"decode tok/s: mean={tkmean:.2f} min={tkmin:.2f} (n={len(tk)})\n")
    f.write(f"throttle_events(>=15% ppt dip): {ev}\n")
print(open(sumf).read())
PY
echo "### summary -> $SUM"
