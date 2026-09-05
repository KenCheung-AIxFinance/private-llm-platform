# Rebuild the platform on a fresh Ubuntu machine

Migration / packaging spec for Reference Implementation #1. This repo is the
**state root** (§B.2). It is the contract the automated installer / packaging
tool must follow when reproducing the whole platform on a clean Ubuntu 24.04
host.

## 0. The one rule

`git clone` gives you **config + a committed snapshot of state**. It does NOT
give you runtimes, model weights, or secrets — those are **reproduced on the
target machine**, never carried in git. The installer's job is therefore:

> clone → reproduce (runtimes + weights) → provision secrets → wire the few
> host-specific bits → start services → verify.

## 1. What is carried vs reproduced

| Path | In git? | Fresh-machine action |
|---|---|---|
| `compose/`, `llama-swap/`, `systemd/`, `scripts/`, `runbook/`, `docs/`, `manifests/`, `hosts/` | ✅ config | clone |
| `vault/` (memory of record §F.1) | ✅ state | clone |
| `hermes/skills/`, `hermes/sessions/`, `hermes/SOUL.md`, `hermes/config.yaml`, `hermes/hooks/`, `hermes/audit.jsonl`, `hermes/.skills_prompt_snapshot.json` | ✅ state | clone |
| `hermes/state.db`, `hermes/verification_evidence.db` | ✅ state snapshot | clone — but see §4.3 live-DB caveat |
| `store/` (schema + `.gitkeep`) | ✅ | clone; the live `store/*.db` stays gitignored |
| `hermes/node/` | ❌ gitignored | **reinstall Node 22.23.2** |
| `hermes/bin/` (`uv`, `uvx`, browser-use symlinks) | ❌ gitignored | **reinstall uv + `uv tool install`** — see §4.2 |
| `hermes/cache/` | ❌ gitignored | regenerate at runtime |
| `tools/llama.cpp/` | ❌ gitignored | clone + build per `runbook/build.md` |
| `tools/llama-swap/llama-swap` (22 MB binary) | ✅ (currently) | kept in git; may be rebuilt instead |
| model weights | ❌ | fetch per `manifests/models.yaml` (URL + SHA256) |
| `.env`, age keys, API keys | ❌ secrets | Owner provisions at go-live (§0.4) |

State that makes Hermes "the same agent" on a new box = `skills/`, `sessions/`
(conversations), `state.db`, `verification_evidence.db`, `SOUL.md`,
`config.yaml`, `hooks/`. Everything under `node/`, `bin/`, `cache/` is a
re-derivable dependency and is deliberately excluded.

## 2. Recommended flow (fresh Ubuntu 24.04)

1. **Base system** — run `scripts/bootstrap.sh` (apt mirror, toolchain, Docker,
   `age`, `sqlite3`). It lives in this repo, so on a bare machine fetch that one
   file first (or clone to a scratch dir) and run it.
2. **Clone state root** — `git clone <repo-url> /srv/z13` (this path is the
   intended mount point, §M3).
3. **Runtimes**
   - Node **22.23.2** → `hermes/node/`.
   - `uv` / `uvx` → `hermes/bin/` (`systemd/hermes.service` puts it on `PATH`),
     then `uv tool install browser-use` to recreate the `browser*` helpers.
   - llama.cpp → `runbook/build.md` (Vulkan/RADV, pinned commit).
4. **Weights** — fetch per `manifests/models.yaml`, verify SHA256.
5. **Secrets** — `.env` + age keyring + API keys, Owner-entered (§0.4). Never
   from git.
6. **Host-specific** (the only host-coupled bits, §A.3):
   - `hosts/<newhost>.env` (use `hosts/z13.env` as template),
   - apt mirror (bootstrap pins Tsinghua; swap for a local mirror),
   - bring Tailscale up, then **fix `sshd` `ListenAddress`** — see §4.1.
7. **systemd** — install + enable `systemd/llama-swap.service`,
   `systemd/hermes.service`, and the Compose boot unit (§J.1).
8. **Start order** — llama-swap (systemd) →
   `docker compose -f compose/compose.yaml up -d` (Open WebUI) → Hermes.
9. **Verify** — `docs/m2-acceptance-tests.md` (`curl :8080/v1/models`, expect
   the alias list).

## 3. Hermes state migration — the "clone, then copy state" flow

Git already carries the Hermes state as a **snapshot**, so `git clone` restores
it. Only if the target needs state **newer than the last commit** (live
conversations since) do a follow-up copy:

1. On the **source**, quiesce Hermes (stop the gateway/cron so the DBs close).
2. `rsync` only these from source → target (never `node/`, `bin/`, `cache/`):
   ```
   hermes/skills/  hermes/sessions/  hermes/SOUL.md  hermes/config.yaml
   hermes/hooks/   hermes/audit.jsonl
   hermes/state.db hermes/verification_evidence.db
   ```
3. For the two SQLite DBs prefer `sqlite3 X.db ".backup Y.db"` over a raw copy
   (§4.3).

This refines the suggested "先 git clone 再复制指定 state 文件夹" flow: clone
first (gets the quiesced snapshot), then top-up only the listed state paths if
the source moved on.

## 4. Gotchas the installer MUST handle

### 4.1 `sshd` `ListenAddress` is pinned to the source host's Tailscale IP
`/etc/ssh/sshd_config` (outside this repo) carries `ListenAddress
100.75.100.76`. That IP belongs to the **source** host — on any other machine
the socket binds to a non-local address and every connection is refused
(exactly this caused a "connection refused" during M2). Ubuntu 24.04 sshd is
**socket-activated**: a generator maps `ListenAddress` → `ListenStream`.
Installer action on the new host, after Tailscale is up:
```bash
sudo sed -i -E "s/^ListenAddress .*/ListenAddress $(tailscale ip -4)/" /etc/ssh/sshd_config
sudo systemctl daemon-reload && sudo systemctl restart ssh.socket
```
(or drop `ListenAddress` entirely to bind `0.0.0.0`).

### 4.2 `hermes/bin/*` are absolute symlinks — reinstall, don't copy
`browser*` entries point at `/home/<user>/.local/share/uv/tools/...`. They are
machine/user-specific. Recreate with `uv tool install`, never `rsync` them.

### 4.3 Never copy an open SQLite DB (§G.3)
Quiesce the owning service first, or use `sqlite3 db ".backup …"`. The git
snapshot is already quiesced; a live `rsync` of a busy `state.db` can corrupt.

### 4.4 `hermes/hermes-agent` is an embedded repo (gitlink, no `.gitmodules`)
It is a clone of `github.com/NousResearch/hermes-agent` with local commit
`a871948` that is **not** on GitHub. A fresh platform clone yields a dangling
gitlink. Installer must either (a) re-clone upstream and re-apply the local
commits, or (b) push `hermes-agent` to an Owner fork and convert it to a proper
submodule. **Recommend (b) before go-live.**

### 4.5 Secrets are never in git
`.env`, age keys, API keys must be prompted for / injected by the installer, not
expected from the repo (§0.4, §B.4).

### 4.6 Only two things are host-specific by design (§A.3)
`hosts/z13.env` and the apt mirror. Everything else is host-neutral — keep it
that way; add a new `hosts/<host>.env` rather than editing shared files.

## 5. What this repo still owes the installer (optional hardening)

- Convert `hermes/hermes-agent` gitlink → proper submodule or vendor it (§4.4).
- Add a `manifests/runtimes.yaml` pinning the Node version + the `uv tool` list
  so the installer can reproduce `hermes/node` + `hermes/bin` declaratively.
- Decide whether `tools/llama-swap/llama-swap` stays tracked or is built.
