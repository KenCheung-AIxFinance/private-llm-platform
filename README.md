# /srv/z13 — Z13 private-AI platform state root

Single canonical state root for Reference Implementation #1 of the private AI
platform (SOW Addendum A, Rev 6.1 amended). This directory is a **git
repository**; everything needed to rebuild the serving layer lives here.

## Layout (SOW §B.2)

| Path | Holds |
|---|---|
| `compose/` | Docker Compose files (services of §D.4) |
| `llama-swap/` | llama-swap YAML: alias → launch command (§D.1) |
| `systemd/` | unit sources (single Compose-boot unit per §J.1) |
| `hermes/` | HERMES_HOME (§E.5) — M2 |
| `vault/` | markdown vault, the memory of record (§F.1) |
| `store/` | SQLite structured store (§G.1) |
| `runbook/` | runbook + benchmark/power evidence |
| `scripts/` | powerctl, soak, bench, backup hooks, bootstrap |
| `tools/` | build scripts (the llama.cpp clone/build is gitignored) |
| `hosts/z13.env` | **single** Z13-specific tuning file (§A.3 host-neutrality) |
| `manifests/models.yaml` | model manifest: alias → {url, SHA256, quant, footprint} |

## What is NOT in this repo

- **Model weights** — replaced by `manifests/models.yaml`. A clean rebuild
  fetches weights by URL and verifies SHA256.
- **Secrets** — `.env` / age-encrypted, gitignored. Entered by the Owner alone
  at go-live (§0.4).

## Mount point note

`/srv/z13` currently lives on the internal NVMe (root ext4). Rev 6.1 §M3 calls
for it to be the mount point of the **external encrypted state-root drive**;
that move (LUKS + TPM2/PIN) is deferred by the Owner. Moving is a one-line
mount-point change — repo content is unchanged, which is the whole point of the
host-neutral layout (§A.3).

## Network note (build environment)

The build host runs FlClash (Clash) with `*_proxy=http://127.0.0.1:7890` in the
shell env, but the 7890 listener is intermittently down. Direct internet works
fully. `scripts/bootstrap.sh` therefore pins the apt mirror to the Tsinghua
domestic mirror and disables apt's proxy so builds are reproducible without the
proxy. See `runbook/build.md`.
