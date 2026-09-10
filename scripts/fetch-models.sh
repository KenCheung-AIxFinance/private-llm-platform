#!/usr/bin/env bash
# scripts/fetch-models.sh — fetch model weights per manifests/models.yaml (M3.1)
# Downloads each file's url -> ~/.lmstudio/models/lmstudio-community/<source-basename>/<name>
# and verifies SHA256. Weights are reproduced, never committed to git (§B.2).
# Usage:
#   fetch-models.sh --only resident   # utility-fast + doc-vision + utility-embed (~20 GB)
#   fetch-models.sh --all             # every status:present alias (~101 GB)
#   fetch-models.sh <alias>           # one alias (e.g. reasoning-max)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/manifests/models.yaml"
DEST_BASE="${MODELS_ROOT:-$HOME/.lmstudio/models/lmstudio-community}"
MODE="${1:---only}"

# resident set = the always-loaded aliases (small enough for a 2h restore window)
RESIDENT="utility-fast doc-vision utility-embed"

mapfile -t ENTRIES < <(python3 - "$MANIFEST" <<'PY'
import sys,yaml
d=yaml.safe_load(open(sys.argv[1]))
for alias,cfg in d.get("aliases",{}).items():
    if not isinstance(cfg,dict): continue
    if cfg.get("status")!="present": continue
    src=cfg.get("source","")
    sub=src.split("/")[-1] if "/" in src else src
    for f in cfg.get("files",[]):
        print("\t".join([alias,sub,f.get("name",""),f.get("url",""),f.get("sha256","")]))
PY
)

want(){
  local alias="$1"
  case "$MODE" in
    --all) return 0;;
    --only) [ "${2:-}" = "resident" ] || return 1; echo " $RESIDENT " | grep -q " $alias ";;
    *) [ "$alias" = "$MODE" ];;
  esac
}

fetched=0; skipped=0
for line in "${ENTRIES[@]}"; do
  IFS=$'\t' read -r alias sub name url sha <<<"$line"
  want "$alias" || { skipped=$((skipped+1)); continue; }
  [ -n "$url" ] || { echo "SKIP $alias/$name (no url)"; continue; }
  dest="$DEST_BASE/$sub/$name"
  mkdir -p "$(dirname "$dest")"
  if [ -s "$dest" ] && [ -n "$sha" ] && echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then
    echo "OK   $alias/$name (already present, sha256 verified)"
    continue
  fi
  echo "GET  $alias/$name  <-  $url"
  curl --noproxy '*' -fL --retry 3 -C - -o "$dest" "$url"
  if [ -n "$sha" ]; then
    echo "$sha  $dest" | sha256sum -c - >/dev/null \
      && echo "OK   $alias/$name (sha256 verified)" \
      || { echo "FAIL $alias/$name sha256 mismatch"; rm -f "$dest"; exit 1; }
  fi
  fetched=$((fetched+1))
done
echo ">>> fetch-models done: $fetched downloaded, $skipped skipped (mode=$MODE)"
