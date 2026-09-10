#!/usr/bin/env bash
# scripts/quiesce-state.sh — produce a consistent snapshot of live SQLite DBs (§B.1 discipline)
# Purpose: BEFORE state migration (W3 migrate), fold WAL into the main DB and make an
# online-consistent copy, so rsync/git never copies a live, mid-write database file.
# (§B.1/§G.3: backing up a live SQLite = corruption path.) NOT a remote-backup tool.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/.backup/quiesced"
mkdir -p "$OUT"
shopt -s nullglob

DBS=( hermes/state.db hermes/verification_evidence.db store/*.db )
count=0
for db in "${DBS[@]}"; do
  [ -f "$db" ] || continue
  # 1) fold WAL -> main file (truncates the -wal side file)
  sqlite3 "$db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
  # 2) integrity gate: refuse to snapshot a corrupt DB
  sqlite3 "$db" "PRAGMA quick_check;" | grep -q '^ok$' \
    || { echo "FAIL: $db failed quick_check (corrupt); aborting" >&2; exit 3; }
  # 3) online-consistent copy (safe even while the app has it open)
  sqlite3 "$db" ".backup '${OUT}/${db//\//_}'"
  echo "OK  $db -> ${OUT}/${db//\//_}"
  count=$((count+1))
done
echo ">>> quiesce-state done: $count DB(s) checkpointed + snapshotted to $OUT"
