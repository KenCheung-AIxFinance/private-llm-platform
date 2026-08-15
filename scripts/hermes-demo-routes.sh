#!/bin/bash
# scripts/hermes-demo-routes.sh — §E.12 routing demo (SOW M2 项目 #5)
# 演练所有路由模板路径：doc-vision（便宜）、reasoning-max（机密-困难）、
# cloud-kimi-k3（非机密-困难，401）。验证批准开启、工具调用在审计日志中、
# 网关关闭、Nous Portal 关闭。

set -euo pipefail
export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13
export PATH="/srv/z13/hermes/bin:/home/norbert/.local/bin:$PATH"

echo "=== Hermes 路由演示 — §E.12 (SOW M2 项目 #5) ==="
echo "路由模板："
echo "  便宜/快速 → doc-vision (默认)"
echo "  机密+困难推理 → reasoning-max (本地 120B)"
echo "  非机密+困难 → cloud 别名 (keyless, 401)"
echo

# 审计日志起始位置
AUDIT_START=$(wc -l < /srv/z13/hermes/audit.jsonl 2>/dev/null || echo 0)
echo "审计日志起始行数: $AUDIT_START"
echo

# --- 任务 A: doc-vision (便宜/快速，默认) ---
echo "=== 任务 A: 便宜/快速路由 (doc-vision, 默认模型) ==="
echo "提示: 使用 bash 工具计算 7+5 并回显结果"
echo "预期: doc-vision 响应，bash 工具调用在审计日志中"
echo

sg docker -c "hermes --accept-hooks -z 'Calculate 7+5 using the bash tool and echo the result. Reply with just the answer.'" 2>&1 | tee /tmp/hermes-demo-a.log | tail -10

echo
echo "--- 任务 A 完成 ---"
sleep 2
echo

# --- 任务 B: reasoning-max (机密-困难推理，本地 120B) ---
echo "=== 任务 B: 机密+困难推理路由 (reasoning-max, 本地 120B) ==="
echo "提示: 简单逻辑难题（手动指定 -m reasoning-max）"
echo "预期: reasoning-max 模型响应"
echo

sg docker -c "hermes --accept-hooks -m reasoning-max -z 'If all Bloops are Razzies and all Razzies are Lazzies, are all Bloops definitely Lazzies? Answer yes or no with brief reasoning.'" 2>&1 | tee /tmp/hermes-demo-b.log | tail -15

echo
echo "--- 任务 B 完成 ---"
sleep 2
echo

# --- 任务 C: cloud-kimi-k3 (非机密-困难，keyless 401) ---
echo "=== 任务 C: 非机密+困难路由 (cloud-kimi-k3, keyless 期望 401) ==="
echo "提示: 调用云别名（手动指定 -m cloud-kimi-k3）"
echo "预期: 401 key_missing 错误（云别名在 M2 keyless）"
echo

sg docker -c "hermes --accept-hooks -m cloud-kimi-k3 -z 'What is the capital of France?'" 2>&1 | tee /tmp/hermes-demo-c.log | tail -15

echo
echo "--- 任务 C 完成 ---"
echo

# --- 验证：审计日志 ---
echo "=== 验证：审计日志中的工具调用 ==="
AUDIT_END=$(wc -l < /srv/z13/hermes/audit.jsonl 2>/dev/null || echo 0)
AUDIT_NEW=$((AUDIT_END - AUDIT_START))
echo "新审计条目: $AUDIT_NEW"

if [ $AUDIT_NEW -gt 0 ]; then
  echo "最近的工具调用:"
  tail -n $AUDIT_NEW /srv/z13/hermes/audit.jsonl | jq -c '{event: .event, tool: .payload.tool, args: .payload.args | keys}' 2>/dev/null || tail -n $AUDIT_NEW /srv/z13/hermes/audit.jsonl
else
  echo "(无新审计条目 — 检查任务 A bash 工具是否触发)"
fi
echo

# --- 验证：网关和 Nous Portal 状态 ---
echo "=== 验证：网关和 Nous Portal 状态 (§E.4, §E.6) ==="
echo "--- hermes gateway status ---"
hermes gateway status 2>&1 | head -5 || echo "(gateway 未运行或未安装)"
echo
echo "--- hermes portal status ---"
hermes portal status 2>&1 | head -10
echo

echo "=== 演示完成 ==="
echo "日志保存于: /tmp/hermes-demo-{a,b,c}.log"
echo "审计日志: /srv/z13/hermes/audit.jsonl (新增 $AUDIT_NEW 条目)"
