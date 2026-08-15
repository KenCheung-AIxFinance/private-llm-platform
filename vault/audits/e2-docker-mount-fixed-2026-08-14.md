# §E.2 Docker Sandbox Mount Fix — 2026-08-14

**SOW M2 项目 #6**："Hermes 沙箱在 Docker 后端上已确认；监听器仅限 loopback/tailscale；HERMES_HOME 在状态根目录中"

## 问题

M2 第 1 轮测试发现 Hermes 的 Docker 沙箱无法访问 vault 文件，尽管 `docker_mount_cwd_to_workspace=true` 已在 `config.yaml` 中配置。容器的 `/workspace` 目录为空。

## 根本原因分析

通过代码审查（`/srv/z13/hermes/hermes-agent/tools/terminal_tool.py`）发现：

1. Hermes 的 `config["host_cwd"]` 来自 **`TERMINAL_CWD` 环境变量**，而不是 `terminal.cwd` YAML 值
2. 第 1624-1636 行：`host_cwd = os.getenv("TERMINAL_CWD", default_cwd)`
3. 第 1433 行：仅当 `config.get("docker_mount_cwd_to_workspace")` **和** `host_cwd` 都存在时才挂载
4. 在没有 `TERMINAL_CWD` 的情况下调用 Hermes → `host_cwd=None` → 没有挂载

**附加问题**：Docker Desktop 的 `/srv/z13` 不在共享路径列表中（`filesharingDirectories: []`），即使设置了 `TERMINAL_CWD`，Docker 守护进程也会拒绝挂载并返回错误："The path /srv/z13 is not shared from the host"。

## 修复

### 1. 添加 `/srv/z13` 到 Docker Desktop 共享路径

编辑 `~/.docker/desktop/settings-store.json`：

```json
{
  "filesharingDirectories": ["/srv/z13"]
}
```

重启 Docker Desktop 以应用更改。

### 2. 设置 `TERMINAL_CWD` 环境变量

**运行手册更新** (`runbook/hermes.md`)：

```bash
export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13           # REQUIRED for Docker sandbox vault access
sg docker -c 'hermes'
```

**systemd unit 更新** (`systemd/hermes.service`)：

```ini
[Service]
Environment="HERMES_HOME=/srv/z13/hermes"
Environment="TERMINAL_CWD=/srv/z13"
```

### 3. 验证 Docker 挂载生效

手动测试：

```bash
sg docker -c 'docker run --rm -v /srv/z13:/workspace:ro nikolaik/python-nodejs:python3.11-nodejs20 ls /workspace/vault'
```

输出：
```
audits  daily  decisions  funds  hermes-notes  projects  runbooks  test-fact.md
```

✅ Docker 可以挂载 `/srv/z13`

## 验证测试

### 测试 1：Hermes 读取 vault

```bash
export TERMINAL_CWD=/srv/z13
sg docker -c "HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13 hermes --accept-hooks -z 'Read /workspace/vault/test-fact.md and tell me what it says about the state root.'"
```

**结果**：
```
The file states that "The Z13 state root is at `/srv/z13`."
```

✅ Hermes 在 Docker 沙箱中成功读取 vault 文件

### 测试 2：Hermes 写入 vault

```bash
sg docker -c "hermes --accept-hooks -z 'Create a file /workspace/vault/hermes-notes/docker-test-20260815.md with content: Docker sandbox mount fixed on 2026-08-14.'"
```

**结果**：
```
File /workspace/vault/hermes-notes/docker-test-20260815.md created successfully
```

验证文件在 git status 中：
```bash
$ git status --short vault/hermes-notes/
?? vault/hermes-notes/docker-test-20260815.md
```

✅ Hermes 在 Docker 沙箱中成功写入 vault 文件，文件在 git status 中可见

### 测试 3：审计日志

```bash
$ tail -2 /srv/z13/hermes/audit.jsonl | jq -c '.event,.payload.tool'
"pre_tool_call"
"bash"
```

✅ 工具调用在审计日志中记录

## 验收标准（SOW M2 项目 #6）

| 检查项 | 状态 | 证据 |
|---|---|---|
| Hermes 沙箱在 Docker 后端上确认 | ✅ PASS | `terminal.backend=docker` 配置生效 |
| Docker 挂载工作（vault 读取） | ✅ PASS | 读取 `/workspace/vault/test-fact.md` 成功 |
| Docker 挂载工作（vault 写入） | ✅ PASS | 创建 `docker-test-20260815.md`，在 git status 中 |
| 监听器仅限 loopback/tailscale | ✅ PASS | CLI 模式（无 HTTP 监听器）|
| HERMES_HOME 在状态根目录中 | ✅ PASS | `/srv/z13/hermes` |

## 配置摘要

- **Docker Desktop 共享路径**：`/srv/z13` 已添加到 `filesharingDirectories`
- **环境变量**：`TERMINAL_CWD=/srv/z13`（运行手册 + systemd unit）
- **Hermes 配置**：
  - `terminal.backend: docker` ✓
  - `terminal.cwd: /srv/z13` ✓
  - `docker_mount_cwd_to_workspace: true` ✓
- **Docker 组访问**：`sg docker -c 'hermes ...'`

## 状态

✅ **§E.2 Docker 沙箱挂载已修复并验证**（2026-08-14）

第 1 轮的"已知问题"已解决。Docker 沙箱现在可以访问 vault 进行读写操作，满足 SOW §E.2 + §F.3 要求。

---

**修复执行**：2026-08-14  
**验证者**：Engineer  
**状态**：✅ RESOLVED（SOW M2 项目 #6 Docker 沙箱部分完成）
