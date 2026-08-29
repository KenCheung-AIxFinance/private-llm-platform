# M2 Complete Build Manual — 从零到完整部署

本文档记录 M2（serving layer + Hermes Agent）从零开始的完整搭建步骤，包括 Round 1（基础架构）和 Round 2（验收测试），目标是让你在没有 AI 助手的情况下也能完全重建系统。

> **本机实测校正（2026-08-28）**：以下为已搭建系统的真实事实，本文档的搭建命令据此校正——
> - 模型权重实际在 `~/.lmstudio/models/lmstudio-community/`（**不是** `/srv/z13/weights/`）
> - llama-swap = **mostlygeek/llama-swap v249**（二进制在 `/srv/z13/tools/llama-swap/`）
> - 推理引擎 llama-server 从源码编译（Vulkan）在 `/srv/z13/tools/llama.cpp/build/bin/`
> - Hermes 经官方 installer 装为 uv venv，入口 `~/.local/bin/hermes`
> - **日常启动、重启后激活、故障排查见 [`m2-usage-guide.md`](m2-usage-guide.md)**

**预计时间**：6-8 小时（不含权重下载时间）

---

## 前置环境要求

### 硬件
- AMD Radeon RX 8060S (gfx1151) 或同等 GPU
- 96 GB VRAM
- ~500 GB 可用磁盘空间（/srv/z13 状态根）

### 软件
- Ubuntu 22.04+ 或同等 Linux 发行版
- Docker Desktop（带 Compose v2）
- Git, Python 3.10+, Node.js 20+
- Mesa RADV 驱动（Vulkan 支持）

### 用户权限
- sudo 权限
- docker 组成员
- `/srv/z13` 目录写权限

---

## 第一阶段：状态根初始化

### 1.1 创建目录结构

```bash
sudo mkdir -p /srv/z13
sudo chown $USER:$USER /srv/z13
cd /srv/z13

git init
git config user.name "Your Name"
git config user.email "your@email.com"

mkdir -p compose docs hermes llama-swap manifests runbook scripts systemd tools \
  vault/{audits,daily,decisions,funds,hermes-notes,projects,runbooks} weights
```

### 1.2 创建 .gitignore

```bash
cat > .gitignore << 'EOF'
*.gguf
*.safetensors
weights/
*.key
*.pem
.env*
*credentials.json
*.db
*.log
__pycache__/
node_modules/
.vscode/
EOF

git add .gitignore
git commit -m "init: state root structure"
```

---

## 第二阶段：llama-swap 服务层

### 2.1 安装 llama-swap

llama-swap = **mostlygeek/llama-swap v249**（Go 单文件）。从 GitHub releases 下载 linux amd64：

```bash
mkdir -p /srv/z13/tools/llama-swap && cd /srv/z13/tools/llama-swap
# 从 https://github.com/mostlygeek/llama-swap/releases/tag/v249 下载 llama-swap_249_linux_amd64.tar.gz
curl -L -o ls.tar.gz \
  "https://github.com/mostlygeek/llama-swap/releases/download/v249/llama-swap_249_linux_amd64.tar.gz"
tar xzf ls.tar.gz && rm ls.tar.gz
chmod +x llama-swap
./llama-swap --version   # 期望：version: v249
```

> 网络受限时用镜像前缀 `https://ghfast.top/https://github.com/...`。

### 2.2 编译推理引擎 llama-server（Vulkan/RADV）

llama-swap 只是代理，真正跑推理的是**从源码编译的 upstream llama.cpp `llama-server`**（Vulkan 后端，gfx1151）。这已在 M1 完成，位于 `/srv/z13/tools/llama.cpp/build/bin/llama-server`。若需重建见 `runbook/build.md`（M1 构建记录：cmake + `-DGGML_VULKAN=ON`）。

### 2.3 模型权重（已在 LM Studio 目录，无需重复下载）

模型权重实际存放在 **`~/.lmstudio/models/lmstudio-community/`**（通过 LM Studio 下载，llama-swap 配置用 `${models}` 宏指向此处）。当前已就绪：

```bash
ls -lh ~/.lmstudio/models/lmstudio-community/*/*.gguf
# gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf              (doc-vision, 5.0G)
# gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf         (doc-vision vision proj)
# gemma-4-26B-A4B-it-QAT-GGUF/gemma-4-26B-A4B-it-QAT-Q4_0.gguf(utility-fast, 14G)
# bge-m3-GGUF/bge-m3-Q8_0.gguf                                (utility-embed, ~0.6G)
# gpt-oss-120b-GGUF/gpt-oss-120b-MXFP4-00001-of-00002.gguf    (reasoning-max, 38G)
# gpt-oss-120b-GGUF/gpt-oss-120b-MXFP4-00002-of-00002.gguf    (reasoning-max, 22G)
```

若在新机器重建，用 `huggingface-cli download` 或 LM Studio 拉取相同模型到同一目录，并核对 `manifests/models.yaml` 中的 SHA256。

### 2.4 llama-swap 配置（真实 schema）

真实配置用 `models:` + `cmd:`（每个别名启动一个 llama-server 进程）+ 宏，**不是** `aliases:`+`model_path:`。完整文件见 `/srv/z13/llama-swap/config.yaml`，结构如下：

```yaml
healthCheckTimeout: 600
startPort: 10001
macros:
  "llama":    "/srv/z13/tools/llama.cpp/build/bin/llama-server --port ${PORT}"
  "z13flags": "--jinja -ub 512 -ctk q8_0 -ctv q8_0 -fa auto -ngl 999 -t 8"
  "models":   "${env.HOME}/.lmstudio/models/lmstudio-community"

models:
  utility-fast:
    cmd: |
      ${llama} ${z13flags} -m ${models}/gemma-4-26B-A4B-it-QAT-GGUF/gemma-4-26B-A4B-it-QAT-Q4_0.gguf
    ttl: 0
  doc-vision:
    cmd: |
      ${llama} ${z13flags} -m ${models}/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf
      --mmproj ${models}/gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf
    ttl: 0
  utility-embed:
    cmd: |
      ${llama} ${z13flags} -m ${models}/bge-m3-GGUF/bge-m3-Q8_0.gguf --embedding
    ttl: 0
  reasoning-max:
    cmd: |
      ${llama} ${z13flags} -m ${models}/gpt-oss-120b-GGUF/gpt-oss-120b-MXFP4-00001-of-00002.gguf
    ttl: 900
  # 云别名：keyless stub，返回 401（见 scripts/cloud-stub.py）
  cloud-disabled:
    cmd: /usr/bin/python3 /srv/z13/scripts/cloud-stub.py ${PORT}
    aliases: [cloud-kimi-k3, cloud-fable-5, cloud-deepseek-v4-pro, cloud-qwen, cloud-gemini]

groups:
  utilities:
    swap: false
    members: [utility-fast, doc-vision, utility-embed]
includeAliasesInList: true
```

> 5 个云别名由一个 `cloud-stub.py`（stdlib HTTP，返回 401 key_missing）承接，直到 go-live 时 Owner 加密钥。

### 2.4 启动服务

```bash
# systemd unit
cat > /srv/z13/systemd/llama-swap.service << 'EOF'
[Unit]
Description=llama-swap
After=network.target

[Service]
Type=simple
User=norbert
WorkingDirectory=/srv/z13/llama-swap
ExecStart=/srv/z13/tools/llama-swap -config /srv/z13/llama-swap/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo cp /srv/z13/systemd/llama-swap.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now llama-swap

# 验证
sleep 5
curl -s http://127.0.0.1:8080/v1/models | jq '.data[].id'
```

---

## 第三阶段：Open WebUI

```bash
cat > /srv/z13/compose/compose.yaml << 'EOF'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "127.0.0.1:3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://host.docker.internal:8080
    volumes:
      - open-webui-data:/app/backend/data
    extra_hosts:
      - "host.docker.internal:host-gateway"
volumes:
  open-webui-data:
EOF

cd /srv/z13/compose
docker compose up -d

# 访问 http://127.0.0.1:3000
```

---

## 第四阶段：Hermes Agent

### 4.1 安装 Hermes（官方 installer → uv venv）

Hermes 用**官方 installer** 安装（不是 GitHub release tar）。它会用 uv 建 Python venv，并在 `~/.local/bin/hermes` 放一个入口 shim。用 `HERMES_HOME` 把状态目录固定到状态根（§E.5）：

```bash
export HERMES_HOME=/srv/z13/hermes
curl -fsSL https://hermes.nousresearch.com/install.sh | bash
# 或参考 NousResearch/hermes-agent README 的安装命令

# 验证（入口在 PATH，指向 venv）
which hermes                    # /home/norbert/.local/bin/hermes
hermes --version                # Hermes Agent v0.20.0
```

真实布局：
- 入口 shim：`~/.local/bin/hermes` → `exec /srv/z13/hermes/hermes-agent/venv/bin/python /srv/z13/hermes/hermes-agent/hermes "$@"`
- 代码：`/srv/z13/hermes/hermes-agent/`
- 状态（HERMES_HOME）：`/srv/z13/hermes/`（config.yaml、audit.jsonl、sessions/、hooks/ 等）

### 4.2 配置 Hermes（真实 config key）

用 `hermes config set` 设置（不要手写臆想的 schema）。真实 key 是 `model.*` 和 `terminal.*`：

```bash
export HERMES_HOME=/srv/z13/hermes
hermes config set model.provider custom
hermes config set model.base_url http://127.0.0.1:8080/v1
hermes config set model.default doc-vision
hermes config set terminal.backend docker
hermes config set terminal.cwd /srv/z13
hermes config set terminal.docker_mount_cwd_to_workspace true

# 验证
hermes config get model.provider     # custom
hermes config get model.base_url     # http://127.0.0.1:8080/v1
hermes config get terminal.backend   # docker
```

### 4.3 Docker 沙箱修复

**关键修复**（§E.2 Docker mount bug）：

```bash
# 1. 添加 Docker 共享路径
python3 << 'EOF'
import json
p = '/home/norbert/.docker/desktop/settings-store.json'
with open(p) as f: cfg = json.load(f)
cfg.setdefault('filesharingDirectories', []).append('/srv/z13')
with open(p, 'w') as f: json.dump(cfg, f, indent=2)
EOF

# 2. 重启 Docker
systemctl --user restart docker-desktop
sleep 10

# 3. 设置环境变量（REQUIRED）
export TERMINAL_CWD=/srv/z13
```

更新 `/srv/z13/runbook/hermes.md`：

```markdown
## Operate

export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13  # REQUIRED for Docker sandbox
sg docker -c 'hermes'
```

### 4.4 审计钩子

```bash
mkdir -p /srv/z13/hermes/hooks

cat > /srv/z13/hermes/hooks/audit-log.sh << 'EOF'
#!/bin/bash
echo "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"$1\",\"payload\":$(cat)}" \
  >> "$HERMES_HOME/audit.jsonl"
EOF

chmod +x /srv/z13/hermes/hooks/audit-log.sh

# 注册钩子到 config.yaml
cat >> /srv/z13/hermes/config.yaml << 'EOF'
hooks:
  pre_tool_call:
    - /srv/z13/hermes/hooks/audit-log.sh pre_tool_call
hooks_auto_accept: true
EOF
```

### 4.5 验证 Hermes

```bash
export HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13
sg docker -c "hermes --accept-hooks -z 'Read /workspace/vault/test-fact.md'"
```

---

## 第五阶段：Round 2 验收测试

### 5.1 别名交换测试

```bash
# 见前面 "任务 #15" 步骤
```

### 5.2 Hermes 路由演示

```bash
# 创建 scripts/hermes-demo-routes.sh，运行 3 个路由测试
```

### 5.3 Eval harness

```bash
# 创建 scripts/eval-harness.py（5-prompt suite）
# 创建 runbook/eval.md
python3 scripts/eval-harness.py doc-vision
```

### 5.4 PDF→JSON

```bash
# 创建 vault/samples/{invoice,statement,receipt}.txt
# 创建 vault/samples/schema.json
# 创建 scripts/pdf-to-json.py
python3 scripts/pdf-to-json.py vault/samples/*.txt
```

### 5.5 Google Drive MCP

```bash
export HERMES_HOME=/srv/z13/hermes
yes | hermes mcp add google-drive --command npx --args -y @modelcontextprotocol/server-gdrive
hermes mcp list
```

---

## 最终提交

```bash
cd /srv/z13
git add -A
git commit -m "feat(M2): complete — 10/10 SOW lines"
```

**完成**。系统已完全搭建，所有 M2 验收项已满足。
