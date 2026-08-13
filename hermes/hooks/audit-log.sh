#!/usr/bin/env bash
# hermes/hooks/audit-log.sh — §E.9 append-only tool-call audit log
# Registered as pre_tool_call + post_tool_call hook in config.yaml; receives
# the tool-call JSON on stdin and appends a timestamped line to audit.jsonl.
set -euo pipefail
AUDIT=/srv/z13/hermes/audit.jsonl
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EVENT="${1:-unknown}"  # pre_tool_call or post_tool_call
SESSION="${HERMES_SESSION_ID:-<no-session>}"
# read stdin (the tool-call JSON payload), wrap with timestamp+event, append
jq -c --arg ts "$TS" --arg evt "$EVENT" --arg sid "$SESSION" \
  '{ts: $ts, event: $evt, session: $sid, payload: .}' \
  >> "$AUDIT" 2>/dev/null || echo "{\"ts\":\"$TS\",\"event\":\"$EVENT\",\"session\":\"$SESSION\",\"error\":\"jq parse failed\"}" >> "$AUDIT"
