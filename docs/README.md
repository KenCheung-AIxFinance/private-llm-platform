# M2 Documentation Index

完整 M2 系统的三个核心文档：

## 1. [Build Manual](m2-build-manual.md) — 从零搭建指南
**用途**：完整重建 M2 系统  
**读者**：需要从头搭建系统的工程师  
**时间**：6-8 小时（不含权重下载）

包含：
- 状态根初始化
- llama-swap 配置和启动
- Open WebUI 部署
- Hermes Agent 安装和配置
- Docker 沙箱修复（§E.2）
- 所有 Round 1 + Round 2 步骤

## 2. [Usage Guide](m2-usage-guide.md) — 日常使用手册
**用途**：在已搭建好的系统上进行日常操作  
**读者**：系统已就绪，需要使用服务的用户  
**时间**：按需参考

包含：
- 启动/停止服务
- 使用 llama-swap API（curl / Python / Open WebUI）
- 使用 Hermes Agent（CLI / 任务 / vault 操作）
- 模型别名管理（查看/交换/添加）
- 运行 eval harness
- PDF→JSON 提取
- MCP 服务器管理（Google Drive）
- 日志和故障排除
- 备份和恢复

## 3. [Acceptance Tests](m2-acceptance-tests.md) — 验收测试清单
**用途**：验证 M2 所有 10 个 SOW 项目  
**读者**：需要正式验收系统的测试人员  
**时间**：1-2 小时（完整测试）

包含：
- SOW 项目 #1-10 的逐项测试步骤
- 预期输出和验收标准
- 测试命令（可复制粘贴）
- 最终汇总表格和报告模板

---

## 快速导航

**我需要...**

- 从零重建系统 → [Build Manual](m2-build-manual.md)
- **机器重启后重新激活服务** → [Usage Guide](m2-usage-guide.md) "快速启动"（含开机自启 + 三大常见故障）
- 日常使用已有系统 → [Usage Guide](m2-usage-guide.md)
- 验证系统是否满足 SOW → [Acceptance Tests](m2-acceptance-tests.md)
- 了解 M2 架构 → [Build Manual](m2-build-manual.md) §1-4
- 排查问题 → [Usage Guide](m2-usage-guide.md) "重启后的三大常见故障" / "日志和故障排除"
- 添加新模型 → [Usage Guide](m2-usage-guide.md) "模型别名管理"
- 运行基准测试 → [Usage Guide](m2-usage-guide.md) "运行评估测试"

---

## 文档版本

- 创建日期：2026-08-26；路径/命令实测校正：2026-08-28
- M2 状态：COMPLETE (10/10 SOW lines)
- 系统版本：llama-swap v249 (mostlygeek), Hermes v0.20.0 (uv venv)
- 覆盖范围：M2 Round 1 + Round 2
- **真实路径基准**：模型在 `~/.lmstudio/models/lmstudio-community/`；llama-server 在 `/srv/z13/tools/llama.cpp/build/bin/`；Hermes 入口 `~/.local/bin/hermes`

## 相关文档

- SOW 原文：`/home/norbert/SOW.pdf`
- 运行手册：`/srv/z13/runbook/`
- 审计记录：`/srv/z13/vault/audits/`
