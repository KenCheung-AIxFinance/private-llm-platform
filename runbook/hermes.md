# runbook/hermes.md — Hermes Agent (SOW §E)

Hermes Agent v0.20.0 (2026.8.3), installed at `/srv/z13/hermes` (HERMES_HOME).
Self-improving AI agent with learning loop, 70+ built-in skills, Docker sandbox.

## §E conditions of M2 acceptance

| § | requirement | status | notes |
|---|---|---|---|
| E.1 | version pinned, update procedure documented | ✓ | v0.20.0 pinned; see Update below |
| E.2 | terminal backend = docker (not local) | ⚠ | **configured** but mount bug prevents vault access; temp workaround `backend=local` |
| E.3 | listeners loopback/tailscale0 only | ✓ | CLI mode (no HTTP listener); gateway OFF |
| E.4 | Nous Portal off, OAuth off, web-search/browser/image/TTS off | ✓ | `hermes portal status` = not logged in; no API keys |
| E.5 | HERMES_HOME in state root | ✓ | `/srv/z13/hermes` (sessions/memories/cron/skills/hooks) |
| E.6 | messaging gateways OFF | ✓ | no TELEGRAM_BOT_TOKEN / SLACK_* / WHATSAPP_* in .env |
| E.7 | cloud models recommend-only | ✓ | llama-swap cloud aliases keyless (401 until go-live) |
| E.8 | cron: Owner-approved only | ✓ | `hermes cron` managed; empty at M2 |
| E.9 | audit log (append-only tool calls) | ✓ | `pre_tool_call` hook → `audit.jsonl` (post hook has bug in v0.20.0) |
| E.10 | agent instructions in repo | ✓ | `AGENTS.md` in state root |
| E.11 | provider → llama-swap, keyless | ✓ | `model.provider=custom`, `base_url=http://127.0.0.1:8080/v1`, `default=doc-vision` |
| E.12 | approvals ON, routing template | ✓ | default mode (no `--yolo`); see Routing below |

## Provider (§E.11)

```
model.provider: custom
model.base_url: http://127.0.0.1:8080/v1
model.default: doc-vision
```

No API key (llama-swap is keyless). Cloud aliases (`cloud-kimi-k3`, etc.) return 401 until Owner adds keys at go-live.

## Sandbox (§E.2)

**Config:** `terminal.backend=docker`, `terminal.cwd=/srv/z13`, `docker_mount_cwd_to_workspace=true`.

**Known issue (v0.20.0):** `docker_mount_cwd_to_workspace` does not actually mount the host cwd into the container's `/workspace`, despite being enabled. Containers see empty `/workspace`. Vault access (§F.3) requires **temporary workaround: `terminal.backend=local`** for file I/O tasks until Hermes updates or a fix is found.

When invoking Hermes, use `sg docker -c 'hermes ...'` so it inherits the docker group for backend=docker.

## Audit log (§E.9)

`/srv/z13/hermes/audit.jsonl` — append-only JSONL; `pre_tool_call` hook captures tool+args+session+timestamp. (`post_tool_call` hook bug in v0.20.0 — only pre fires.)

Read: `jq -c '.payload.tool,.payload.args' /srv/z13/hermes/audit.jsonl | less`

## Vault (§F.3)

Hermes reads `/srv/z13/vault/*.md` (e.g., `test-fact.md`) and writes to `/srv/z13/vault/hermes-notes/*.md`.  
Agent-created notes appear in `git status`. **Requires `terminal.backend=local` workaround** (see Sandbox above).

Verified: Hermes read `vault/test-fact.md` and created `vault/hermes-notes/test-note.md` (in git status ✓).

## Routing template (§E.12)

Approvals ON by default (no `--yolo` flag). Recommended routing for tasks:

| task type | model | reason |
|---|---|---|
| cheap / fast queries | `doc-vision` (default) | 57 tok/s, clean content |
| confidential + hard reasoning | `reasoning-max` | 120B local, 47 tok/s |
| non-confidential hard | cloud aliases (keyless at M2) | when Owner adds keys |
| embeddings | `utility-embed` | bge-m3 |

`utility-fast` (Gemma-4-A4B) has a **thought-channel quirk**: chat responses begin in `<|channel|>thought` before visible content; with small `max_tokens` the OpenAI `content` field is empty. Use `doc-vision` or `reasoning-max` for tasks needing immediate visible text, or request high `max_tokens` to pass the thought channel.

## Update procedure (§E.1)

Owner-triggered (not auto):
1. Backup: `cd /srv/z13 && git add hermes/ && git commit -m "pre-update: hermes $(hermes --version)"`
2. Update: `hermes update`
3. Smoke: `hermes -z "Echo test"` + check `hermes --version` + review changelog
4. Commit: `git add hermes/ && git commit -m "hermes updated to $(hermes --version)"`

## Operate

```
cd /srv/z13
sg docker -c 'hermes'                   # interactive CLI
sg docker -c 'hermes -z "one-shot"'     # batch task
hermes cron list                         # scheduled jobs (Owner-approved only, §E.8)
hermes gateway status                    # messaging gateway (OFF at M2, §E.6)
hermes portal status                     # Nous Portal (not logged in, §E.4)
hermes tools list                        # enabled tools
hermes config get model.provider         # verify llama-swap endpoint
```

## M2 Round 1 verified 2026-08-14

- Hermes v0.20.0 installed, `HERMES_HOME=/srv/z13/hermes` ✓
- Provider = llama-swap (custom, base_url 127.0.0.1:8080, keyless) ✓
- Default model = `doc-vision` (clean chat content) ✓
- `terminal.backend=docker` configured; mount bug requires `backend=local` workaround for vault ⚠
- Nous Portal / gateways / web-search / browser / image / TTS all OFF ✓
- Audit hook `pre_tool_call` → `audit.jsonl` (bash tool logged) ✓
- Vault read (`test-fact.md`) + write (`hermes-notes/test-note.md` in git status) ✓
- Approvals ON (default mode) ✓
