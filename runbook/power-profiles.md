# runbook/power-profiles.md — two profiles + §I.5 brackets (M1 line 5)

SOW §I.5 requires both power profiles to **hold a bracketed wattage and
temperature through a 30-minute sustained-decode soak**, with the bracket values
"confirmed or amended from on-device measurement at M1." This document records
those measurements.

## Profiles

| | batch | eco-longevity |
|---|---|---|
| `platform_profile` | `performance` | `quiet` |
| governor / max freq | performance / 5.1 GHz | powersave / 3.0 GHz |
| charge threshold | 100 % | 80 % |
| applied by | `sudo scripts/powerctl.sh batch\|eco` (sources `hosts/z13.env`) |

EPP cannot differentiate profiles on this 6.17-oem kernel (only `performance`
exposed), so governor + max-freq + `platform_profile` are used instead.

## Mechanism — what actually caps the wattage

- **`platform_profile` (performance/quiet) sets the BIOS SPL tables — this is the
  binding cap, proven by the soaks below** (flat plateau at ~60 W batch / ~35 W eco).
- The `asus-nb-wmi` PPT sysfs (`ppt_pl1_spl`, `ppt_pl2_sppt`, `ppt_apu_sppt`,
  `ppt_fppt`) is a **live finer-grain lever** — validated 2026-08-08: writing 40 →
  readback 40, restored to 120. Not relied on for M1 (platform_profile suffices)
  but available for custom wattage; `powerctl.sh` applies it only when
  `TRUST_PPT=1` in `hosts/z13.env`.

## §I.5 brackets — measured (2026-08-07 soaks, utility-fast, 30 min, steady-state = min 10–30)

| | batch | eco |
|---|---|---|
| **PPT steady-state** | **mean 58.8 W / p95 60 / max 60** (flat cap ~60 W) | **mean 34.1 W / p95 35 / max 35** (flat cap ~35 W) |
| GPU edge °C | mean 80.7 / max 87.0 | mean 69.5 / max 75.0 |
| CPU Tctl °C | mean 81.7 / max 85.2 | mean 70.3 / max 71.6 |
| decode tok/s (utility-fast) | 57.2 (≥55 ✅) | 48.9 (≥45 ✅) |
| throttle dips (≥15 % PPT) | 59 | 65 |

**Proposed §I.5 brackets for Owner sign-off: batch ≈ 60 W / ~81 °C; eco ≈ 35 W / ~70 °C.**
(The "max 60" / "max 35" PPT values are flat — the cap holds; the throttle dips
are the SMU modulating around the SPL, not a failure to hold.)

Soak evidence: `runs/soak_{batch,eco}_utility-fast_*.summary.txt` (+ 1 Hz CSV).

## Note on decode vs power (§I.3)

MoE decode on this platform is **memory-bandwidth-bound, not power-bound**, so the
eco profile's lower wattage mainly saves power/heat, not decode throughput:
utility-fast 57 (batch) vs 49 (eco) tok/s; reasoning-max ~47 tok/s under *both*
profiles. Prefill/TTFT are the power-sensitive axes.
