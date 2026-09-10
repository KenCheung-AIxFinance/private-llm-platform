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
- **云端模型激活（Kimi、DeepSeek 等）**
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

# M3 — 打包平台 + 跨设备全新安装复原

## 4. [Migration Readiness Certificate](migration-readiness-certificate.md) — MRC（§A.4, M3.5）
**用途**：证明平台可移植、可全新安装复原；列出 Z13 专属组件与换机替代、精确重建序列、实测重建时间、已知障碍  
**读者**：Owner 验收 + 迁移到第二台机器的人

**复原主路径**：新机器 `git clone <repo> /srv/z13` → `git submodule update --init` → `./scripts/rebuild.sh`

## M3 安装器脚本（`/srv/z13/scripts/`）
| 脚本 | 用途 |
|---|---|
| `init-host.sh` | 新机初始化 + GPU driver 检测/配置（gfx1151 Vulkan / AMD / NVIDIA / cpu）+ BIOS VRAM/GTT 提示 |
| `rebuild.sh` | **安装器主入口**：init-host → bootstrap → submodule → runtime → fetch-models → secrets → 主机位 → systemd → 验证 |
| `fetch-models.sh` | 按 manifest 下载权重 + sha256（`--only resident` ~20GB / `--all` ~101GB）|
| `migrate.sh` | 连续性复原到第二台机器（<2h，codeword 验证 Hermes 凭迁移记忆回答）|
| `quiesce-state.sh` | 状态迁移前的一致 DB 快照（§B.1 静默纪律）|

**配套**：`manifests/models.yaml`（权重 URL+SHA256）、`manifests/runtimes.yaml`（runtime 版本）、`systemd/z13-stack.service`（§J.1 boot-survival）

---

## 快速导航

**我需要...**

- 从零重建系统 → [Build Manual](m2-build-manual.md)
- **机器重启后重新激活服务** → [Usage Guide](m2-usage-guide.md) "快速启动"（含开机自启 + 三大常见故障）
- **激活云端模型（Kimi、DeepSeek 等）** → [Usage Guide](m2-usage-guide.md) "云端模型激活"
- 日常使用已有系统 → [Usage Guide](m2-usage-guide.md)
- 验证系统是否满足 SOW → [Acceptance Tests](m2-acceptance-tests.md)
- 了解 M2 架构 → [Build Manual](m2-build-manual.md) §1-4
- 查看系统架构图 → [architecture.md](architecture.md)
- 排查问题 → [Usage Guide](m2-usage-guide.md) "重启后的三大常见故障" / "日志和故障排除"
- 添加新模型 → [Usage Guide](m2-usage-guide.md) "模型别名管理" / "云端模型激活"
- 运行基准测试 → [Usage Guide](m2-usage-guide.md) "运行评估测试"

---

## 文档版本

- 创建日期：2026-08-26；路径/命令实测校正：2026-08-28
- M2 状态：COMPLETE (10/10 SOW lines) + 云端模型路由激活
- 系统版本：llama-swap v249 (mostlygeek), Hermes v0.20.0 (uv venv)
- 覆盖范围：M2 Round 1 + Round 2 + 云端模型（Kimi K3 已激活）
- **真实路径基准**：模型在 `~/.lmstudio/models/lmstudio-community/`；llama-server 在 `/srv/z13/tools/llama.cpp/build/bin/`；Hermes 入口 `~/.local/bin/hermes`

## 相关文档

- SOW 原文：`/home/norbert/SOW.pdf`
- 架构文档：`/srv/z13/docs/architecture.md`（完整 5 层架构图）
- 运行手册：`/srv/z13/runbook/`
- 审计记录：`/srv/z13/vault/audits/`
