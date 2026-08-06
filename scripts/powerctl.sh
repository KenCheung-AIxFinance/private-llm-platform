#!/usr/bin/env bash
# scripts/powerctl.sh — Z13 power profiles (SOW §I.5, §J.1)
# Replaces the buggy ~/powerctl.sh: fixes the dead charge-threshold test (was
# gated on the non-existent charge_stop_threshold), uses sensors/sysfs instead
# of rocm-smi (ROCm is unreliable on gfx1151, §D.5), and adds PPT cap hooks.
#
# Usage: sudo ./powerctl.sh {eco|batch|status}
# Z13 specifics live in hosts/z13.env (§A.3). Profile wattage values are
# [MEASURE @ M1]; item C validates that the PPT write actually caps the SMU.
set -euo pipefail
ENV_FILE="$(dirname "$0")/../hosts/z13.env"
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

PPT="$PPT_SYSFS"; CHARGE="$CHARGE_THRESH"; PP="$PLATFORM_PROFILE"

set_governor() { for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "$1" | tee "$c" >/dev/null; done; }
set_charge()   { [ -w "$CHARGE" ] && echo "$1" | tee "$CHARGE" >/dev/null || echo "(charge threshold not writable)"; }
set_profile()  { [ -w "$PP" ] && echo "$1" | tee "$PP" >/dev/null 2>/dev/null || true; }
# PPT write — gated: only applied if hosts/z13.env sets TRUST_PPT=1 after C's validation
set_ppt() {
  if [ "${TRUST_PPT:-0}" = "1" ] && [ -w "$PPT/ppt_pl1_spl" ]; then
    echo "$1" | tee "$PPT/ppt_pl1_spl" >/dev/null
  fi
}

case "${1:-}" in
  batch)
    sudo cpupower frequency-set -g performance --max "${BATCH_CPU_MAX_GHZ}GHz" >/dev/null 2>&1 || set_governor performance
    set_governor performance; set_profile "$BATCH_PROFILE"; set_ppt "$BATCH_PPT_PL1_W"; set_charge "$BATCH_CHARGE_PCT"
    echo "[batch] governor=performance max=${BATCH_CPU_MAX_GHZ}GHz profile=$BATCH_PROFILE ppt=${BATCH_PPT_PL1_W}W*(if trusted) charge<=${BATCH_CHARGE_PCT}%"
    ;;
  eco)
    sudo cpupower frequency-set -g powersave --max "${ECO_CPU_MAX_GHZ}GHz" >/dev/null 2>&1 || set_governor powersave
    set_governor powersave; set_profile "$ECO_PROFILE"; set_ppt "$ECO_PPT_PL1_W"; set_charge "$ECO_CHARGE_PCT"
    echo "[eco] governor=powersave max=${ECO_CPU_MAX_GHZ}GHz profile=$ECO_PROFILE ppt=${ECO_PPT_PL1_W}W*(if trusted) charge<=${ECO_CHARGE_PCT}%"
    ;;
  status)
    echo "== CPU governor =="; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    echo "== platform_profile =="; cat "$PP" 2>/dev/null
    echo "== charge threshold =="; cat "$CHARGE" 2>/dev/null
    echo "== PPT (W) =="; awk "BEGIN{printf \"%.1f\n\", $(cat $S_AMDGPU_POWER 2>/dev/null||echo 0)/1000000}"
    echo "== GPU edge (C) =="; awk "BEGIN{printf \"%.1f\n\", $(cat $S_AMDGPU_TEMP 2>/dev/null||echo 0)/1000}"
    echo "== CPU Tctl (C) =="; awk "BEGIN{printf \"%.1f\n\", $(cat $S_K10TEMP 2>/dev/null||echo 0)/1000}"
    echo "== fans (rpm cpu/gpu) =="; echo "$(cat $S_FAN_CPU 2>/dev/null) / $(cat $S_FAN_GPU 2>/dev/null)"
    command -v sensors >/dev/null && sensors k10temp amdgpu 2>/dev/null | grep -iE "Tctl|edge|PPT|fan" || true
    ;;
  *) echo "Usage: sudo $0 {eco|batch|status}"; exit 1 ;;
esac
