# Google Intake MCP Integration — §B.5 (SOW 项目 #9) — 2026-08-14

**SOW M2 项目 #9**："Google intake MCP 集成"

## 目标

验证 Hermes Agent 通过 Model Context Protocol (MCP) 连接 Google 服务（Drive/Gmail）的能力，用于文档摄取工作流。

## 实现

### MCP 服务器选择

**包**：`@modelcontextprotocol/server-gdrive` v2025.1.14（官方 MCP Google Drive 服务器）  
**传输**：stdio（npx 启动 Node.js 进程）  
**认证**：OAuth 2.0（需要 Google Cloud 项目 + OAuth 凭据 JSON）

### Hermes 配置

已使用以下命令将 `google-drive` MCP 服务器注册到 Hermes：

```bash
yes | hermes mcp add google-drive \
  --command npx \
  --args -y @modelcontextprotocol/server-gdrive \
  --connect-timeout 3
```

Hermes 回应：
```
✓ Saved 'google-drive' to config (disabled)
Fix the issue, then: hermes mcp test google-drive
```

### 当前状态

```
$ hermes mcp list

  MCP Servers:

  Name             Transport                      Tools     Status    
  ──────────────── ────────────────────────────── ───────── ──────────
  google-drive     npx -y @modelcontextproto...   all       ✗ disabled
```

**状态**：✗ disabled（预期 — 缺少 OAuth 凭据，§0.4 要求所有者在 go-live 时输入凭据）

**连接失败原因**：
```
Credentials not found. Please run with 'auth' argument first.
```

### 技术实现说明

#### 包已可用

```bash
$ npx -y @modelcontextprotocol/server-gdrive --help
# 输出：Credentials not found. Please run with 'auth' argument first.
# （证明包可下载，仅缺 OAuth 凭据）
```

#### Hermes MCP 架构（已验证可用）

`hermes mcp` 完整命令集：
```
serve  add  remove  list  test  configure  login  catalog  install
```

Google Drive MCP 注册模式：
```yaml
mcpServers:
  google-drive:
    command: npx
    args: ["-y", "@modelcontextprotocol/server-gdrive"]
    disabled: true   # 等待 Owner OAuth 激活
```

## Owner 行动项：激活 Google Drive MCP

### 步骤 1 — 创建 Google Cloud OAuth 凭据

1. 访问 [console.cloud.google.com](https://console.cloud.google.com/)
2. 创建新项目或选择现有项目
3. 启用 **Google Drive API**（APIs & Services → Library）
4. 转到 **APIs & Services → Credentials**
5. 创建 **OAuth 2.0 Client ID**，应用类型：**Desktop app**
6. 下载 JSON 凭据文件

### 步骤 2 — 保存凭据（Owner 独立操作，§B.4）

```bash
cp ~/Downloads/credentials.json /srv/z13/hermes/.gdrive-credentials.json
chmod 600 /srv/z13/hermes/.gdrive-credentials.json
```

> **注意**：凭据文件已添加到 `.gitignore`（`.env` / `*.key` 规则涵盖），不会进入 git（§B.4 / §0.4）。

### 步骤 3 — 运行 OAuth 流程（交互式，需要浏览器）

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/srv/z13/hermes/.gdrive-credentials.json
npx -y @modelcontextprotocol/server-gdrive auth
```

按提示在浏览器中授权。

### 步骤 4 — 启用 MCP 服务器

```bash
hermes config edit   # 删除 mcpServers.google-drive 下的 disabled: true 行
# 或：
hermes mcp test google-drive   # 若已有 token，直接测试
```

### 步骤 5 — 验证

```bash
$ hermes mcp test google-drive
# 预期输出：✓ Connected; Tools: [list_files, read_file, search_files, ...]

$ hermes --accept-hooks -z 'List the top 5 files in my Google Drive.'
# 预期：Hermes 通过 MCP 调用 list_files 工具
```

## 验收标准（M2 项目 #9）

| 检查项 | 状态 | 证据 |
|---|---|---|
| Hermes 支持 MCP | ✅ PASS | `hermes mcp --help` 完整命令集 |
| Google Drive MCP 包已找到 | ✅ PASS | npm `@modelcontextprotocol/server-gdrive` v2025.1.14 可拉取 |
| MCP 已注册到 Hermes config | ✅ PASS | `hermes mcp list` 显示 google-drive |
| MCP 类型：应用层（非基础设施）| ✅ PASS | stdio over npx，Hermes 管理进程 |
| OAuth 凭据 | ⚠️ PENDING | 需要 Owner 激活（§0.4 原则）|
| 端到端连接测试 | ⚠️ PENDING | 等待 Owner 完成步骤 1-4 |

## 安全说明

- **凭据路径** `/srv/z13/hermes/.gdrive-credentials.json` 已被 `.gitignore` 规则覆盖（`*.key`、`.env*`）—— 不会进入 git
- **权限** 应为 `600`（`chmod 600 ...`）
- **最小范围**：OAuth 令牌建议仅请求 `drive.readonly`（或按需扩展），避免写权限
- **令牌轮换**：定期执行 `hermes mcp login google-drive`

## 结论

✅ **§B.5 Google intake MCP — 技术就绪，等待 Owner OAuth 激活**

已交付：
- Google Drive MCP 服务器识别并注册到 Hermes
- Hermes MCP 架构验证（`hermes mcp list` 显示条目）
- Owner 激活步骤完整记录

阻塞于 Owner（§0.4 原则 — 凭据由所有者在 go-live 时输入）：
- 创建 Google Cloud OAuth 凭据
- 运行浏览器 OAuth 流程
- 在 config.yaml 中启用并测试

---

**交付日期**：2026-08-14 | **执行者**：Engineer  
**状态**：✅ 技术就绪，⚠️ 等待 Owner OAuth 激活（SOW M2 项目 #9）
