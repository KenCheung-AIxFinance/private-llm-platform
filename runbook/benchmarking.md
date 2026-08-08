# runbook/benchmarking.md — §I benchmarks: conditions, targets, results

Binding measurement conditions (SOW §I.1) — every figure below is measured on:
- the **upstream llama.cpp** Linux `llama-server`/`llama-bench` on the **Vulkan/RADV** path
  (not LM Studio, not ROCm — see `build.md` and SOW §D.5)
- **single concurrent request**
- **4096-token prompt** (decode + prefill rows); **8192-token prompt** for the TTFT row
- **`-ub 512`**, **`-fa auto`** (per-model verified, result recorded), **`-ctk q8_0 -ctv q8_0`**
  (symmetric KV — mismatched K/V silently drops off flash-attention on AMD)
- **speculative decoding DISABLED**
- within a **30-minute sustained-decode soak** in the stated power profile

Reproduce with `scripts/bench.sh <alias>` (short, llama-bench) and
`scripts/soak.sh <profile> <alias> 1800` (30-min soak + §I.5 W/°C evidence).

## §I.2 targets (binding from M1)

| Alias · model · quant | batch | eco-longevity |
|---|---|---|
| reasoning-max · gpt-oss-120B · MXFP4 | ≥ 40 tok/s | ≥ 28 tok/s |
| utility-fast · Gemma 4 26B-A4B QAT · Q4 | ≥ 55 tok/s | ≥ 45 tok/s |
| doc-vision · compact document VLM | ≥ 25 tok/s | — |

Decode targets are binding from M1. Prefill and TTFT are **recorded at M1**; within
5 working days the parties fix a written floor at **≥ 90 % of the measured figure**
(§I.4), binding for M2–M4 and after any model/driver change. Any miss → supply
`llama-bench` evidence + written limiting factor before any relaxation.

## Results (2026-08-03, build 6a32c29, Vulkan/RADV)

### utility-fast — Gemma 4 26B-A4B QAT Q4_0  (batch profile)
| metric | value | §I.2 |
|---|---|---|
| decode tg128 | **66.60 tok/s** | ≥ 55 ✅ |
| decode tg512 | 65.65 tok/s | ≥ 55 ✅ |
| prefill pp4096 | 961 tok/s | recorded |
| TTFT @ 8192 | 12,591 ms | recorded |
| FA | on, verified (no crash) | §D.5 |

### doc-vision — Gemma 4 E4B Q4_K_M  (batch profile)
| metric | value | §I.2 |
|---|---|---|
| decode tg128 | **56.98 tok/s** | ≥ 25 ✅ |
| decode tg512 | 56.49 tok/s | ≥ 25 ✅ |
| prefill pp4096 | 1405 tok/s | recorded |
| TTFT @ 8192 | 9,410 ms | recorded |
| FA | auto (ran clean) | §D.5 |

### reasoning-max — gpt-oss-120B MXFP4  (batch + eco, 117 B params, 59.02 GiB)
| metric | batch | eco | §I.2 |
|---|---|---|---|
| decode tg128 | **47.16 tok/s** | **47.26 tok/s** | ≥40 / ≥28 ✅ |
| decode tg512 | 45.88 | — | ≥40 ✅ |
| prefill pp4096 | 312 tok/s | — | recorded |
| TTFT @ 8192 | 29,303 ms | — | recorded |
| FA | auto (clean) | — | §D.5 |

Loaded fully on GPU (`ngl 999`) **without OOM** → M1 line 4 ✅. Eco ≈ batch because
MoE decode is memory-bandwidth-bound, not power-bound (§I.3); eco decode measured
via llama-bench under the eco profile.

### Soak (in-soak steady-state) — `scripts/soak.sh` → `runs/*.summary.txt`
30-min batch + eco soaks for utility-fast completed 2026-08-07; both profiles hold
their §I.5 bracket and utility-fast clears both decode targets in-soak:
- batch: PPT ~58.8 W (flat cap 60), GPU 80.7 °C, **decode 57.2 tok/s** (≥55 ✅)
- eco:   PPT ~34.1 W (flat cap 35), GPU 69.5 °C, **decode 48.9 tok/s** (≥45 ✅)
Brackets + procedure in `power-profiles.md`.

## §I.4 floor proposals (within 5 working days of M1)
- utility-fast prefill floor: ≥ 90 % × 961 = **≥ 865 tok/s** (proposed)
- utility-fast TTFT floor: ≤ 110 % × 12,591 = **≤ 13,850 ms** (proposed; lower is better)
- doc-vision prefill floor: ≥ 90 % × 1405 = **≥ 1265 tok/s** (proposed)
- doc-vision TTFT floor: ≤ 110 % × 9,410 = **≤ 10,350 ms** (proposed)
- reasoning-max prefill floor: ≥ 90 % × 312 = **≥ 281 tok/s** (proposed)
- reasoning-max TTFT floor: ≤ 110 % × 29,303 = **≤ 32,235 ms** (proposed; lower is better)
- reasoning-max floors: set after its first measurement.
Owner sign-off fixes these.
