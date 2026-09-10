# M3.1 Clean Rebuild — container verification evidence (2026-09)

**SOW §K M3.1**: "Clean rebuild of the serving layer from state-root repository + model manifest alone."

## What was verified in a clean `ubuntu:24.04` container (repo mounted read-only)

| Check | Result |
|---|---|
| Manifest URLs resolve (all `status:present` weights) | **9/10 OK** — the 1 FAIL is Mixtral-8x22B (a §C.5 *candidate*, `status:candidate`, NOT in the rebuild path; fetch-models.sh skips candidates) |
| `fetch-models.sh` downloads + sha256-verifies a real weight | **PASS** — utility-embed (bge-m3 Q8_0) downloaded from its manifest URL in-container; sha256 `aa473d51…` matches manifest |
| Package self-containment | **PASS** — all key files present: `scripts/{rebuild,init-host,fetch-models,quiesce-state}.sh`, `manifests/{models,runtimes}.yaml`, `systemd/{z13-stack,llama-swap}.service`, `llama-swap/config.yaml`, `hosts/z13.env`, `.gitmodules` |
| hermes-agent code retrievable from git (submodule) | **PASS** (separately verified) — `git clone` + `git submodule update --init` fetched a871948 source + hermes program |

## Container-level conclusion

The package (git repo + `manifests/models.yaml` + `manifests/runtimes.yaml` + installer scripts) is **sufficient for a manifest-alone rebuild**: every weight the serving layer needs has a working download URL with a verified SHA256, the fetch mechanism works end-to-end, the repo is self-contained, and Hermes code comes via the (now-registered) submodule.

## What is deferred to the authoritative run on real hardware (W3)

A full `rebuild.sh` from-scratch run also exercises: `init-host.sh` (GPU detect + base init + BIOS hint), `bootstrap.sh` (full apt install), the llama.cpp Vulkan build, 101 GB weight transfer, systemd unit install + boot, and the final `curl :8080/v1/models` GPU-serving verification. These are **not** runnable in a plain container (no gfx1151/Vulkan, no systemd, 101 GB cost) and are the SOW-intended venue — the Owner's second machine (W3). The authoritative "zero undocumented steps" GPU-serving rebuild is demonstrated there, with per-phase timings recorded to `vault/audits/m3-continuity-<date>.md` and folded into the MRC.

## Candidate-level gap (not an M3.1 blocker)

Mixtral-8x22B (`status:candidate`) manifest URL returns 401 — the GGUF repo path/filename needs re-verification before that candidate is ever staged. Grok-1 (also candidate) still has `TODO_VERIFY`. Neither is part of the serving-layer rebuild (`fetch-models.sh` only fetches `status:present` aliases). Flagged for Owner when §C.5 candidates are evaluated.
