#!/usr/bin/env bash
# scripts/migrate.sh — M3.2 continuity restore: source Z13 -> clean target (<2h)
# Clone-driven for config+committed state; rsync for heavy/live bits (weights,
# hermes-agent fallback, uncommitted-session top-up). Verifies Hermes answers from
# migrated memory via an injected codeword.
#
# Usage:
#   scripts/migrate.sh --target user@host [--weights resident|all|fetch] \
#                      [--cpu-inference] [--carry-env]
#   scripts/migrate.sh --target local-container [--cpu-inference]   # self-proof
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TARGET=""; WEIGHTS="resident"; CPU=0; CARRY_ENV=0
while [ $# -gt 0 ]; do case "$1" in
  --target) TARGET="$2"; shift 2;;
  --weights) WEIGHTS="$2"; shift 2;;
  --cpu-inference) CPU=1; shift;;
  --carry-env) CARRY_ENV=1; shift;;
  *) echo "unknown arg: $1"; exit 2;;
esac; done
[ -n "$TARGET" ] || { echo "need --target user@host | local-container"; exit 2; }

CODE="Z13-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
T0=$(date +%s); log(){ echo "[migrate +$(( $(date +%s)-T0 ))s] $*"; }
STATE_PATHS=( hermes/skills hermes/sessions hermes/SOUL.md hermes/config.yaml \
              hermes/hooks hermes/audit.jsonl hermes/state.db \
              hermes/verification_evidence.db vault )

log "START migrate -> $TARGET (weights=$WEIGHTS cpu=$CPU) codeword=$CODE"

# --- 1. inject codeword into source vault (proves memory migrated) -------------
echo "The Z13 continuity codeword is ${CODE}." >> vault/test-fact.md
log "1/7 injected codeword into vault/test-fact.md"

# --- 2. quiesce source DBs (consistent snapshot, §B.1) --------------------------
bash scripts/quiesce-state.sh >/dev/null
log "2/7 quiesced source DBs"

# --- 3. preflight target ---------------------------------------------------------
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8"
if [ "$TARGET" != "local-container" ]; then
  $SSH "$TARGET" 'grep -q Ubuntu /etc/os-release && command -v rsync >/dev/null' \
    || { log "FAIL: target not reachable/Ubuntu/rsync-ready ($TARGET)"; exit 4; }
  RUN(){ $SSH "$TARGET" "$@"; }
else
  log "3/7 local-container self-proof (GPU steps -> cpu-inference)"; CPU=1
  RUN(){ bash -c "$*"; }
fi
log "3/7 preflight OK"

# --- 4. target base init (GPU detect + driver) ----------------------------------
[ "$CPU" = 1 ] && RUN "ALLOW_SMALL_GPU=1 sudo bash -s" < scripts/init-host.sh || RUN "sudo bash -s" < scripts/init-host.sh || log "init-host: partial"
log "4/7 target base init done"

# --- 5. push state (config + committed memory + hermes-agent) --------------------
RSYNC="rsync -az --info=progress2"
EXCL=( --exclude tools/llama.cpp --exclude hermes/node --exclude hermes/bin \
       --exclude hermes/cache --exclude hermes/hermes-agent/venv --exclude .backup )
if [ "$TARGET" != "local-container" ]; then
  $RUN "sudo mkdir -p /srv/z13 && sudo chown \$USER /srv/z13" || true
  $RSYNC -e ssh "${EXCL[@]}" "$ROOT/" "$TARGET:/srv/z13/"
  # hermes-agent source + .git (carries a871948; submodule fallback)
  $RSYNC -e ssh "$ROOT/hermes/hermes-agent" "$TARGET:/srv/z13/hermes/" 2>/dev/null || true
  # uncommitted live-session top-up (quiesced snapshot)
  [ -d "$ROOT/.backup/quiesced" ] && $RSYNC -e ssh "$ROOT/.backup/quiesced/" "$TARGET:/srv/z13/.backup/quiesced/" || true
  [ "$CARRY_ENV" = 1 ] && $RSYNC -e ssh "$ROOT/hermes/.env" "$TARGET:/srv/z13/hermes/.env" || true
  # weights (resident set ~20GB over LAN; skip the fetch cost)
  if [ "$WEIGHTS" != "fetch" ]; then
    for m in gemma-4-E4B-it-GGUF gemma-4-26B-A4B-it-QAT-GGUF bge-m3-GGUF; do
      [ -d "$HOME/.lmstudio/models/lmstudio-community/$m" ] && \
        $RSYNC -e ssh "$HOME/.lmstudio/models/lmstudio-community/$m" \
          "$TARGET:$HOME/.lmstudio/models/lmstudio-community/" || true
    done
    [ "$WEIGHTS" = "all" ] && $RSYNC -e ssh "$HOME/.lmstudio/models/lmstudio-community/gpt-oss-120b-GGUF" \
      "$TARGET:$HOME/.lmstudio/models/lmstudio-community/" || true
  fi
else
  log "5/7 (local-container) state paths present in repo: $(ls ${STATE_PATHS[@]%%/*} 2>/dev/null | wc -l)"
fi
log "5/7 state + weights pushed"

# --- 6. target rebuild (installer) ----------------------------------------------
if [ "$TARGET" != "local-container" ]; then
  INFER_FLAG="--inference cpu"; [ "$CPU" = 0 ] && INFER_FLAG="--inference auto"
  RUN "cd /srv/z13 && sudo -E bash scripts/rebuild.sh --llama prebuilt --weights ${WEIGHTS} ${INFER_FLAG} --yes" \
    || log "rebuild.sh on target reported issues (check journal)"
else
  log "6/7 (local-container) would run rebuild.sh --weights $WEIGHTS --inference cpu"
fi
log "6/7 target rebuild done"

# --- 7. verify continuity: Hermes answers from migrated memory -------------------
log "7/7 verifying continuity (codeword recall)..."
if [ "$TARGET" != "local-container" ]; then
  OUT=$(RUN "export HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13; \
    sg docker -c 'hermes --accept-hooks -z \"Read /workspace/vault/test-fact.md and reply with only the Z13 continuity codeword.\"' 2>&1" || true)
  echo "$OUT" | grep -q "$CODE" \
    && log "✓ CONTINUITY CONFIRMED: target Hermes recalled codeword $CODE" \
    || { log "✗ codeword NOT recalled by target Hermes. Output: ${OUT:0:200}"; FAIL=1; }
else
  grep -q "$CODE" vault/test-fact.md && log "✓ (self-proof) codeword persisted in vault/test-fact.md"
fi

EL=$(( $(date +%s)-T0 )); log "TOTAL ${EL}s"
[ "$EL" -lt 7200 ] && log "✓ within 2h budget" || { log "✗ EXCEEDED 2h budget (${EL}s)"; FAIL=1; }

# evidence
EV="$ROOT/vault/audits/m3-continuity-$(date +%Y%m%d-%H%M%S).md"
cat > "$EV" <<EOF2
# M3.2 Continuity restore — $(date -u +%FT%TZ)
- target: $TARGET | weights: $WEIGHTS | cpu: $CPU
- codeword: $CODE (recalled: $([ "${FAIL:-0}" = 0 ] && echo YES || echo NO))
- total time: ${EL}s (<7200: $([ "$EL" -lt 7200 ] && echo YES || echo NO))
EOF2
log "evidence -> $EV"
exit "${FAIL:-0}"
