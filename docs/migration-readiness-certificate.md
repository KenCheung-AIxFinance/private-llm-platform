# Migration Readiness Certificate (§A.4) — Z13 Private AI Platform

**Deliverable (M3.5).** One page. States, at minimum: (i) which components are
Z13-specific and what replaces them on another host; (ii) the exact rebuild
sequence from a clean OS to a working platform; (iii) measured rebuild time;
(iv) known blockers to migration.

**The package = this git repository** (`/srv/z13` + hermes-agent submodule) +
`manifests/models.yaml` + `manifests/runtimes.yaml` + installer scripts.
Restore = `git clone` + `git submodule update --init` + `./scripts/rebuild.sh`.

---

## (i) Z13-specific components → replacement per host

| Z13-specific | On a new host |
|---|---|
| **New-machine init** (`scripts/init-host.sh`) | run it — detects GPU, installs base, writes `hosts/<host>.env` |
| **GPU driver** — gfx1151 Vulkan/RADV, Mesa `mesa-vulkan-drivers` + `libvulkan`, shader toolchain (`glslc`/`glslang-tools`/`spirv-*`) | gfx1151 → same Vulkan path + OEM kernel `linux-oem-24.04c`; other AMD → Mesa RADV; NVIDIA → CUDA path (not implemented this round); none → `--cpu-inference` |
| **BIOS VRAM/GTT split** (96 GB GPU-visible / 32 GB sys) — firmware, M1 | **Owner firmware action required** on a Strix Halo target (script only detects + warns if VRAM < 90 GB) |
| **OEM kernel** `linux-oem-24.04c` (Strix Halo gfx1151 support) | install only if target is Strix Halo |
| `hosts/z13.env` (GPU, VRAM, §D.5 flags, power sysfs, sensors) | copy → `hosts/<new>.env`; re-measure §I.5 power brackets |
| apt mirror = Tsinghua (bootstrap.sh) | swap for a local mirror |
| power-control sysfs paths (`asus-nb-wmi`, `platform_profile`, `BAT0`) | target's own paths, or drop powerctl |
| sshd `ListenAddress` (source Tailscale IP) | re-pin `ListenAddress $(tailscale ip -4)` (rebuild.md §4.1) |
| model-weights path `~/.lmstudio/models/lmstudio-community/` | same path (matches `${models}` macro), or update macro |
| llama-swap cloud-key override confs (`/etc/systemd/.../cloud-*.conf`) | re-provision API keys on target (never carried in git) |
| hermes-agent gitlink (was mode 160000, no .gitmodules) | **FIXED**: now a proper submodule → official upstream (a871948 is on GitHub main; no fork needed) |

---

## (ii) Exact rebuild sequence (clean OS → working platform)

```bash
# On the new host (Ubuntu 24.04):
git clone <this-repo-url> /srv/z13
cd /srv/z13 && git submodule update --init          # pulls hermes-agent code (§E fix)
./scripts/rebuild.sh --weights resident --inference auto
```

`rebuild.sh` performs, in order (each idempotent):
0. `init-host.sh` — GPU detect + base init + OEM kernel + Vulkan stack + BIOS hint
1. `bootstrap.sh` — apt platform deps + restic/rclone/rsync/jq + Node 22 + uv
2. `git submodule update --init` — hermes-agent code
3. Runtimes per `manifests/runtimes.yaml` — llama.cpp Vulkan build @6a32c29, llama-swap v249, Node + `uv tool install browser-use`
4. `fetch-models.sh --only resident` — download + SHA256 the resident weights (~20 GB)
5. Secrets prompt — `.env`/age/API keys, Owner-entered (§0.4, never from git)
6. Host bits — `hosts/<host>.env` + sshd `ListenAddress` re-pin
7. systemd — install + enable `llama-swap.service`, `z13-stack.service`, `hermes.service`
8. Start + verify — `curl :8080/v1/models` returns all aliases

---

## (iii) Measured rebuild time

- **Package + manifest-alone sufficiency (container-verified, 2026-09):** the manifest→download→SHA256 path and repo self-containment verified in minutes in a clean `ubuntu:24.04` container (see `vault/audits/m3-clean-rebuild-container-2026-09.md`).
- **Full GPU-serving rebuild on real hardware:** *to be measured on the Owner's second machine (the SOW venue, W3)* — includes llama.cpp Vulkan compile (~5–10 min), resident-weight transfer (~3–5 min on gigabit LAN), and full stack bring-up. Recorded per-phase to `vault/audits/m3-continuity-<date>.md` and asserted **< 2 hours** (§K M3.2).

---

## (iv) Known blockers to migration

1. **Strix Halo BIOS VRAM/GTT split is a manual firmware step** — no OS script can set it; without it, only small models or `--cpu-inference` until Owner enters BIOS.
2. **hermes-agent gitlink — FIXED** (now proper submodule, §E). Was a fresh-clone-yields-empty-dir blocker; resolved by registering the submodule (a871948 is on GitHub main).
3. **`hermes/bin/*` absolute symlinks** — recreated via `uv tool install browser-use`, never copied (rebuild.md §4.2).
4. **Secrets are never in git** (§0.4/§B.4) — `.env`, age keyring, API keys, restic password must be Owner-provisioned at restore.
5. **sshd `ListenAddress` pinning** to the source host's Tailscale IP — must be re-pinned on target or connections are refused (rebuild.md §4.1).
6. **101 GB total weights** — transfer is the schedule risk for the 2 h window; mitigated by resident-set (~20 GB) rsync over LAN and deferring reasoning-max (59 GB).
7. **§C.5 candidate models** (Mixtral 401 / Grok `TODO_VERIFY`) — candidate URLs need re-verification before staging; NOT in the serving-layer rebuild path.
8. **Deferred**: SanDisk airplane-mode restore (M3.3 — no disk) and Google cloud repo (M3.4a) — pending Owner hardware/OAuth.

---

*Canonical one-pager: `docs/migration-readiness-certificate.md`. Dated snapshot: `vault/audits/mrc-<date>.md`.*
