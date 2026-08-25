# M2 System Usage Guide — 日常使用手册

本文档说明如何在已搭建好的 M2 系统上进行日常操作，而不是重建系统。

**适用场景**：系统已按 `m2-build-manual.md` 搭建完成，你需要：
- 启动/停止服务
- 运行推理任务
- 使用 Hermes Agent
- 管理模型别名
- 查看日志和监控

---

## 快速启动

### 启动所有服务

```bash
# 1. 启动 llama-swap
sudo systemctl start llama-swap
systemctl status llama-swap  # 验证运行中

# 2. 启动 Open WebUI
cd /srv/z13/compose
docker compose up -d

# 3. 验证服务
curl -s http://127.0.0.1:8080/v1/models | jq '.data[].id'  # llama-swap
curl -s http://127.0.0.1:3000/health  # Open WebUI
```

### 停止所有服务

```bash
sudo systemctl stop llama-swap
cd /srv/z13/compose && docker compose down
```

---

## 使用 llama-swap（推理服务）

### 方法 1：通过 OpenAI 兼容 API

```bash
# 基本聊天补全
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "doc-vision",
    "messages": [{"role":"user","content":"Hello, how are you?"}],
    "max_tokens": 100
  }' | jq .

# 使用不同别名
# - doc-vision: 默认，9B VLM，适合文档分析
# - utility-fast: 26B，快速响应
# - reasoning-max: 120B，复杂推理（慢）
# - cloud-kimi-k3: 云端（M2 无密钥，返回 401）
```

### 方法 2：通过 Open WebUI（推荐）

访问 `http://127.0.0.1:3000`：

1. 在模型下拉菜单选择别名（doc-vision / utility-fast / reasoning-max）
2. 输入提示并发送
3. 查看流式响应

### 方法 3：通过 Python 客户端

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8080/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="doc-vision",
    messages=[{"role": "user", "content": "Explain quantum computing"}],
    max_tokens=500
)

print(response.choices[0].message.content)
```

---

## 使用 Hermes Agent

### 基本使用

```bash
export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13  # REQUIRED for Docker sandbox
export PATH="/srv/z13/hermes/bin:$PATH"

# CLI 模式（推荐）
sg docker -c 'hermes'

# 一次性任务（--accept-hooks 自动批准工具调用）
sg docker -c "hermes --accept-hooks -z 'List files in /workspace/vault'"
```

### 指定模型

```bash
# 使用 reasoning-max（120B 本地推理）
sg docker -c "hermes --accept-hooks -m reasoning-max -z 'Solve this logic puzzle...'"

# 使用 doc-vision（默认，9B VLM）
sg docker -c "hermes --accept-hooks -z 'Analyze this document...'"
```

### Vault 操作（知识库）

Hermes 在 Docker 沙箱中可以访问 `/workspace/vault`，映射到主机的 `/srv/z13/vault`。

```bash
# 读取 vault 文件
sg docker -c "hermes --accept-hooks -z 'Read /workspace/vault/projects/project-alpha.md and summarize'"

# 写入 vault（自动出现在 git status）
sg docker -c "hermes --accept-hooks -z 'Create /workspace/vault/daily/$(date +%Y-%m-%d).md with today journal'"

# 验证文件已创建
git status vault/daily/
```

### 审计日志

所有工具调用自动记录到 `$HERMES_HOME/audit.jsonl`：

```bash
# 查看最近的工具调用
tail /srv/z13/hermes/audit.jsonl | jq .

# 查看特定工具
grep '"tool":"bash"' /srv/z13/hermes/audit.jsonl | jq .
```

---

## 模型别名管理

### 查看当前别名

```bash
curl -s http://127.0.0.1:8080/v1/models | jq '.data[] | {id, object}'
```

应该看到：
- 4 个本地别名（doc-vision, utility-fast, utility-embed, reasoning-max）
- 5 个云别名（cloud-kimi-k3, cloud-deepseek-v4-pro, ...）

### 交换别名背后的模型

编辑 `/srv/z13/llama-swap/config.yaml`，修改别名的 `model_path`：

```yaml
utility-fast:
  model_path: /srv/z13/weights/new-model.gguf  # 修改这里
```

重启服务：

```bash
sudo systemctl restart llama-swap
```

**重要**：客户端代码无需更改（这就是别名的意义）。

### 添加新别名

在 `config.yaml` 的 `aliases:` 部分添加：

```yaml
my-new-alias:
  model_path: /srv/z13/weights/my-model.gguf
  max_tokens: 4096
  temperature: 0.7
```

重启服务并验证：

```bash
sudo systemctl restart llama-swap
curl -s http://127.0.0.1:8080/v1/models | jq '.data[].id' | grep my-new-alias
```

---

## 运行评估测试

使用 `scripts/eval-harness.py` 对任何别名进行快速烟雾测试：

```bash
cd /srv/z13

# 列出可用别名
python3 scripts/eval-harness.py --list

# 在 doc-vision 上运行 5-prompt 测试
python3 scripts/eval-harness.py doc-vision

# 保存结果到文件
python3 scripts/eval-harness.py reasoning-max -o eval-results-$(date +%Y%m%d).json

# 查看汇总
cat eval-results-*.json | jq '.summary'
```

输出：
- 准确率（5 个提示中通过几个）
- 平均延迟
- 总 token 使用量

**用例**：
- M1→M3 回归测试（重建后验证性能）
- 模型比较（选择最佳别名）
- 别名交换验证（交换后准确率保持相似）

---

## PDF/文档 → JSON 提取

使用 `scripts/pdf-to-json.py` 从结构化文档提取 JSON：

```bash
cd /srv/z13

# 提取单个文档
python3 scripts/pdf-to-json.py vault/samples/invoice-001.txt

# 提取多个文档
python3 scripts/pdf-to-json.py vault/samples/*.txt --validate

# 使用不同模型
python3 scripts/pdf-to-json.py document.txt --model reasoning-max
```

输出 JSON 保存到 `vault/samples/{basename}.json`。

**Schema 定义**：`vault/samples/schema.json`（可自定义）

---

## MCP 服务器管理（Google Drive 等）

### 查看已注册的 MCP 服务器

```bash
export HERMES_HOME=/srv/z13/hermes
hermes mcp list
```

当前已注册：
- `google-drive`（状态：disabled，等待你的 OAuth 激活）

### 激活 Google Drive MCP

**前提**：你已创建 Google Cloud 项目 + OAuth 凭据。

```bash
# 1. 保存凭据
cp ~/Downloads/credentials.json /srv/z13/hermes/.gdrive-credentials.json
chmod 600 /srv/z13/hermes/.gdrive-credentials.json

# 2. 运行 OAuth 流程（会打开浏览器）
export GOOGLE_APPLICATION_CREDENTIALS=/srv/z13/hermes/.gdrive-credentials.json
npx -y @modelcontextprotocol/server-gdrive auth

# 3. 编辑 config.yaml，移除 google-drive 下的 disabled: true

# 4. 测试连接
hermes mcp test google-drive
```

应该看到：`✓ Connected; Tools: [list_files, read_file, search_files, ...]`

### 在 Hermes 中使用 Google Drive

```bash
sg docker -c "hermes --accept-hooks -z 'List the top 5 files in my Google Drive'"
```

Hermes 会自动调用 `google-drive` MCP 的 `list_files` 工具。

---

## 日志和故障排除

### llama-swap 日志

```bash
# 实时跟踪
sudo journalctl -u llama-swap -f

# 查看最近错误
sudo journalctl -u llama-swap -p err --since today
```

### Hermes 审计日志

```bash
# 最近的工具调用
tail -20 /srv/z13/hermes/audit.jsonl | jq .

# 按工具类型过滤
grep '"tool":"bash"' /srv/z13/hermes/audit.jsonl | jq .
```

### Open WebUI 日志

```bash
cd /srv/z13/compose
docker compose logs -f open-webui
```

### 常见问题

**Q: llama-swap 返回 "Failed to load model"**
- 检查权重文件是否存在：`ls -lh /srv/z13/weights/`
- 检查路径拼写：`grep model_path /srv/z13/llama-swap/config.yaml`

**Q: Hermes 在 Docker 中看不到 vault**
- 确保设置了 `export TERMINAL_CWD=/srv/z13`
- 确保 `/srv/z13` 在 Docker Desktop 的 filesharingDirectories 中
- 手动测试：`sg docker -c 'docker run --rm -v /srv/z13:/workspace:ro alpine ls /workspace/vault'`

**Q: 云别名返回 401**
- 预期行为（M2 keyless per §C.3/§0.4）
- 在 go-live 时，你需要添加 API key 到环境变量或 config.yaml

**Q: Gemma-4-A4B (utility-fast) 返回空响应**
- 这是已知的 "thought-channel" 特性
- 增加 `max_tokens` 到 128+ 或使用 doc-vision (E4B)

---

## 性能基准（参考）

基于 M2 烟雾测试（gfx1151, 96GB VRAM）：

| 别名 | 模型大小 | 平均延迟 | tok/s (batch) | 适用场景 |
|---|---|---|---|---|
| doc-vision | 9B VLM | ~2s | 57 tok/s | 文档分析、默认 |
| utility-fast | 26B | ~2s | 55 tok/s | 快速响应 |
| reasoning-max | 120B | ~8s | 47 tok/s | 复杂推理 |

---

## 系统维护

### 每日操作

- 检查服务状态：`systemctl status llama-swap`
- 查看审计日志：`tail /srv/z13/hermes/audit.jsonl`
- 提交 vault 更新：`cd /srv/z13 && git add vault/ && git commit -m "daily: vault updates"`

### 每周操作

- 运行 eval harness 回归测试
- 清理旧日志：`journalctl --vacuum-time=7d`
- 检查磁盘空间：`df -h /srv/z13`

### 添加新模型权重

1. 下载到 `/srv/z13/weights/new-model.gguf`
2. 更新 `manifests/models.yaml`（添加条目）
3. 在 `llama-swap/config.yaml` 添加别名或替换现有别名
4. 重启：`sudo systemctl restart llama-swap`
5. 提交：`git add manifests/ llama-swap/ && git commit -m "feat: add new-model alias"`

---

## 备份和恢复

### 备份状态根

```bash
# 完整备份（不含权重）
cd /srv
tar czf z13-backup-$(date +%Y%m%d).tar.gz \
  --exclude='z13/weights' \
  --exclude='z13/hermes/*.db' \
  z13/

# 仅 git 仓库（最小）
cd /srv/z13
git bundle create /tmp/z13-$(date +%Y%m%d).bundle --all
```

### 恢复

```bash
# 从 tar 恢复
cd /srv
sudo tar xzf z13-backup-YYYYMMDD.tar.gz
sudo chown -R $USER:$USER /srv/z13

# 从 bundle 恢复
git clone /tmp/z13-YYYYMMDD.bundle /srv/z13

# 重新下载权重（见 m2-build-manual.md §2.2）
# 重启服务
```

---

## 下一步

- **M3 准备**：学习 restic 备份、airplane-mode 恢复
- **生产化**：考虑 TLS、认证、监控
- **扩展**：添加更多 MCP 服务器（Gmail、Linear、GitHub 等）

**完成**。你现在可以日常使用 M2 系统。
