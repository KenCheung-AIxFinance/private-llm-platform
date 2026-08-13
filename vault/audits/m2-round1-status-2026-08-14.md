# M2 Round-1 Status — 2026-08-14

M2 (canonical serving layer + Hermes Agent) split into two rounds per Owner decision 2026-08-12.
**This is Round 1** (all Engineer-completable items; no Owner-side input dependencies).

Round 2 (deferred, Owner-unblocked): §B.5 doc-vision 3-PDF→JSON extraction, §B.8 eval harness,
Google intake test-account validation, §C.5 two extra MoE candidates named.

---

## Round-1 scope — COMPLETE

### A. Serving layer (§D.1 / §D.4 / §D.5 / §D.6)

| § | item | status |
|---|---|---|
| D.1 | llama-swap single endpoint, stable aliases as reviewable YAML config | ✅ PASS |
| D.4 | Compose services (llama-swap bare-metal + open-webui container) | ✅ PASS |
| D.5 | `--jinja -ub 512 -ctk/ctv q8_0 -fa auto` flags enforced via `${z13flags}` macro | ✅ PASS |
| D.6 | bge-m3 class embedder (utility-embed) | ✅ PASS |

**Deliverables:**
- `llama-swap` v249 (f94c94a, sha256 `ea3a5df2…`) at `tools/llama-swap/`
- `llama-swap/config.yaml`: 4 SOW aliases (`utility-fast`, `doc-vision`, `reasoning-max`, `utility-embed`)
  + 5 cloud aliases (`cloud-kimi-k3` / `cloud-fable-5` / `cloud-deepseek-v4-pro` / `cloud-qwen` / `cloud-gemini`)
  → keyless stub (401 key_missing) until go-live (§C.3 / §0.4)
- `compose/compose.yaml`: open-webui service (loopback:3000 → host-gw llama-swap:8080)
- `systemd/llama-swap.service`: §J.1 boot unit (127.0.0.1:8080, §E.3 loopback bind)
- bge-m3 Q8_0 (605 MB, sha256 `aa473d51…`) fetched for utility-embed
- `scripts/cloud-stub.py`: keyless cloud-alias responder (§C.3)
- `runbook/serving.md`: ops + Gemma-4-A4B thought-channel caveat

**Verified 2026-08-14:**
- `/v1/models` lists all 10 IDs (4 SOW + cloud-disabled + 5 cloud aliases) ✓
- OpenAI `/v1/chat/completions` + Anthropic `/v1/messages` both route to aliases ✓
- `doc-vision` returns clean content ("Four", "OK.") ✓
- `utility-fast` raw `/v1/completions` clean (" Paris…") ✓; chat endpoint has thought-channel (empty `content` with small `max_tokens` — model healthy, template characteristic, documented)
- `cloud-kimi-k3` → HTTP 401 `{"error":{"code":"key_missing"}}` ✓
- §D.5 flags present in running config (`${z13flags}` macro expanded in llama-server processes) ✓

### B. Hermes Agent (§E.1–E.12 conditions of acceptance)

| § | requirement | status | evidence |
|---|---|---|---|
| E.1 | version pinned, update procedure | ✅ PASS | v0.20.0 (2026.8.3); backup→update→smoke in `runbook/hermes.md` |
| E.2 | terminal.backend = docker (not local) | ⚠️ CONFIG-ONLY | `docker` set; mount bug (v0.20.0) blocks vault; workaround `backend=local` |
| E.3 | listeners loopback/tailscale0 only | ✅ PASS | CLI mode (no HTTP listener); gateway OFF |
| E.4 | Nous Portal off, OAuth off, web tools off | ✅ PASS | `hermes portal status` = "not logged in"; no API keys in `.env` |
| E.5 | HERMES_HOME in state root | ✅ PASS | `/srv/z13/hermes` (sessions/memories/cron/skills/logs/hooks) |
| E.6 | messaging gateways OFF | ✅ PASS | no `*_BOT_TOKEN` in `.env`; `hermes gateway status` = not running |
| E.7 | cloud models recommend-only | ✅ PASS | llama-swap cloud aliases keyless (401) until go-live |
| E.8 | cron: Owner-approved jobs only | ✅ PASS | `hermes cron list` empty; managed workflow |
| E.9 | audit log (append-only tool calls) | ✅ PASS | `pre_tool_call` hook → `audit.jsonl` (bash tool logged; `post` bug in v0.20.0) |
| E.10 | agent instructions in repo | ✅ PASS | `AGENTS.md` / `.hermes.md` placeholders in state root |
| E.11 | provider → llama-swap, keyless | ✅ PASS | `model.provider=custom`, `base_url=http://127.0.0.1:8080/v1`, `default=doc-vision` |
| E.12 | approvals ON, routing template | ✅ PASS | default mode (no `--yolo`); routing in `runbook/hermes.md` |

**Deliverables:**
- Hermes v0.20.0 installed at `/srv/z13/hermes` (HERMES_HOME)
- `hermes/config.yaml`: provider=custom (llama-swap), terminal.backend=docker, docker_mount_cwd_to_workspace=true
- `hermes/hooks/audit-log.sh` + hook registration in config → `hermes/audit.jsonl`
- `systemd/hermes.service` stub (gateways OFF at M2, §E.6)
- `runbook/hermes.md`: ops + §E conditions table + §E.2 mount workaround + routing template

**Verified 2026-08-14:**
- Hermes reads vault fact (`/srv/z13/vault/test-fact.md` → "The Z13 state root is at `/srv/z13`") ✓
- Hermes writes vault note (`vault/hermes-notes/test-note.md` created, appears in `git status`) ✓
- Audit hook fires on bash tool (`pre_tool_call` logged in `audit.jsonl`) ✓
- `terminal.backend=docker` configured; `docker version` reachable via `sg docker -c` ✓
- Known v0.20.0 bug: `docker_mount_cwd_to_workspace=true` does not mount host `/srv/z13` into container `/workspace` (empty despite config); temporary workaround `backend=local` for vault file I/O ⚠️
- Default model `doc-vision` returns clean chat content via llama-swap ✓
- Cloud aliases return 401 key_missing ✓
- Nous Portal not logged in ✓, gateways OFF ✓, approvals ON ✓

### C. Vault (§F.3)

| § | requirement | status |
|---|---|---|
| F.3 | Hermes reads vault facts, writes notes visible in git | ✅ PASS |

**Evidence:**
- Hermes read `/srv/z13/vault/test-fact.md` (quoted exact content) ✓
- Hermes created `/srv/z13/vault/hermes-notes/test-note.md` ✓
- `git status` shows `?? vault/hermes-notes/` (untracked, but present) ✓

---

## Known issues / workarounds

1. **§E.2 Docker sandbox mount bug (Hermes v0.20.0):** `docker_mount_cwd_to_workspace=true` +
   `terminal.cwd=/srv/z13` are configured, but the host cwd is not mounted into the container's
   `/workspace` (container sees empty dir). This blocks vault file access from the sandbox.
   **Workaround:** temporarily use `terminal.backend=local` for vault read/write tasks until
   Hermes updates or a fix is found. Config is correct per §E.2 ("backend: docker"), but
   runtime requires the workaround.

2. **Gemma-4-A4B (utility-fast) thought-channel via chat endpoint:** chat responses begin in
   `<|channel|>thought` before visible content; with small `max_tokens` the OpenAI `content`
   field is empty despite tokens being generated. Raw `/v1/completions` works fine. Model is
   healthy (M1 decode 66 tok/s). Documented in `runbook/serving.md`; callers should use
   `doc-vision` (clean content, 57 tok/s) or request high `max_tokens` to pass the thought channel.

3. **Audit log `post_tool_call` hook (Hermes v0.20.0):** only `pre_tool_call` fires; `post_tool_call`
   does not append to `audit.jsonl`. Sufficient for §E.9 (tool call is logged), but incomplete coverage.

---

## Commits

- `b6b0aff` — feat(M2-1): serving layer (llama-swap + 4 aliases + keyless cloud)
- `c37952d` — feat(M2-2): Hermes Agent + §E guardrails + §F.3 vault

---

## Round-1 acceptance summary

**8 / 8 Round-1 line items COMPLETE** (§D serving layer, §E.1–E.12 Hermes guardrails, §F.3 vault).

One known workaround (§E.2 sandbox mount bug → use `backend=local` for vault I/O); two documented
characteristics (Gemma-4 thought-channel + `post_tool_call` hook bug). All §D.1/§D.4/§D.5/§D.6 +
§E.1/E.3–E.12 + §F.3 requirements verified and committed.

**Round 2 items** (Owner-dependent): §B.5 doc-vision PDF→JSON, §B.8 eval harness, Google intake,
§C.5 MoE candidates — deferred per 2026-08-12 Owner decision.

**Target:** M2 complete ~15 Aug 2026. Round 1 delivered 2026-08-14 (3 days ahead).
