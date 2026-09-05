# M2 Acceptance Test Checklist — 验收测试清单

本文档提供逐项测试步骤，用于验证 M2 的所有 10 个 SOW 项目是否满足要求。

**使用方式**：逐项执行测试，记录结果（✅ 通过 / ❌ 失败），最后汇总。

---

## 测试环境确认

在开始测试前，确认：

```bash
# 1. llama-swap 运行中
systemctl status llama-swap | grep "active (running)"

# 2. Open WebUI 运行中
docker ps | grep open-webui

# 3. 状态根存在
ls -la /srv/z13/.git

# 4. Hermes 可执行
export HERMES_HOME=/srv/z13/hermes
hermes --version
```

如果任何检查失败，先执行 `m2-usage-guide.md` 的"快速启动"部分。

---

## SOW M2 项目 #1：14 个别名单端点；已激活云别名可用，未激活返回 key_missing

### 测试步骤

```bash
# 1. 列出所有别名
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id' | sort

# 预期输出（14 个别名）：
# 4 个本地：
#   doc-vision
#   reasoning-max
#   utility-embed
#   utility-fast
# 10 个云端：
#   cloud-azure-gpt4
#   cloud-custom-vllm
#   cloud-deepseek-v4-pro
#   cloud-fable-5
#   cloud-gemini
#   cloud-gpt-4o
#   cloud-gpt-4o-mini
#   cloud-kimi-k3
#   cloud-ollama-cloud
#   cloud-qwen
```

```bash
# 2. 测试本地别名（OpenAI 格式）
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"doc-vision","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
  | jq -r '.choices[0].message.content'

# 预期：返回非空响应（不是错误）
```

```bash
# 3. 测试已激活的云别名（cloud-kimi-k3，应该返回真实响应或 provider 错误）
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"cloud-kimi-k3","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
  | jq .

# 预期：HTTP 200，包含 choices 或错误消息（取决于 Moonshot API 状态）
```

```bash
# 4. 测试未激活的云别名（cloud-gpt-4o，期望 401 key-missing）
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"cloud-gpt-4o","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
  | jq -r '.error.message'

# 预期：HTTP 200，error.message 包含 "OPENAI_API_KEY" 或 "key_missing"
```

### 验收标准

- [ ] 14 个别名全部出现在 `/v1/models`
- [ ] 4 个本地别名（doc-vision, utility-fast, utility-embed, reasoning-max）返回正常响应
- [ ] 已激活的云别名（cloud-kimi-k3）返回真实云端响应或 provider 特定错误（不是 generic 401）
- [ ] 未激活的云别名（cloud-gpt-4o 等）返回 "requires {API_KEY_ENV}" 错误消息（不是 500 server error）

---

## SOW M2 项目 #2：别名交换测试

### 测试步骤

```bash
cd /srv/z13/llama-swap

# 1. 备份当前配置
cp config.yaml config.yaml.test-backup

# 2. 查看 utility-fast 当前模型
grep -A3 "utility-fast:" config.yaml | grep model_path

# 3. 测试原始模型
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"utility-fast","messages":[{"role":"user","content":"What is 7+5?"}],"max_tokens":50}' \
  | jq -r '.choices[0].message.content' > /tmp/response-before.txt

cat /tmp/response-before.txt
```

```bash
# 4. 修改配置（交换到 doc-vision 的权重）
sed -i 's|gemma-4-26B-A4B-it-QAT-Q4_0\.gguf|gemma-4-E4B-it-Q4_K_M.gguf|' config.yaml

# 5. 重启服务
sudo systemctl restart llama-swap
sleep 5

# 6. 使用完全相同的客户端请求测试
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"utility-fast","messages":[{"role":"user","content":"What is 7+5?"}],"max_tokens":50}' \
  | jq -r '.choices[0].message.content' > /tmp/response-after.txt

cat /tmp/response-after.txt
```

```bash
# 7. 恢复配置
cp config.yaml.test-backup config.yaml
sudo systemctl restart llama-swap
```

### 验收标准

- [ ] 客户端请求完全未变（同样的 JSON payload）
- [ ] 响应来自不同的模型（before 可能为空，after 清晰包含 "12"）
- [ ] 别名 `utility-fast` 在两次测试中都有效（没有 404 错误）
- [ ] 零下游配置更改 ✓

---

## SOW M2 项目 #3：llama-swap YAML 已提交；§D.5 flags 已验证

### 测试步骤

```bash
cd /srv/z13

# 1. 验证 config.yaml 已提交到 git
git log --oneline --all -- llama-swap/config.yaml | head -3

# 2. 检查 §D.5 强制 flags
grep -E "(--jinja|-ub 512|-ctk q8_0|-ctv q8_0|-fa auto)" llama-swap/config.yaml

# 预期：config 或 macros 中包含这些 flags
```

```bash
# 3. 验证运行时配置（查看实际 llama-server 进程）
ps aux | grep llama-server | head -1

# 预期：命令行包含 --jinja, -ub 512, -ctk q8_0, -ctv q8_0, -fa auto（或在 config 文件中）
```

### 验收标准

- [ ] `llama-swap/config.yaml` 在 git 历史中（至少 1 次提交）
- [ ] §D.5 flags 出现在配置中：`--jinja`, `-ub 512`, `-ctk q8_0 -ctv q8_0`, `-fa auto`
- [ ] 实际运行的 llama-server 使用这些 flags（从 ps 或 config 验证）

---

## SOW M2 项目 #4：doc-vision 3-PDF → schema-valid JSON

### 测试步骤

```bash
cd /srv/z13

# 1. 验证样本文档存在
ls -1 vault/samples/*.txt
# 预期：至少 3 个 .txt 文件（invoice, statement, receipt 等）

# 2. 验证 schema 存在
cat vault/samples/schema.json | jq .
# 预期：valid JSON，包含 required: [doc_type, doc_number, date, total_amount]

# 3. 运行提取脚本
python3 scripts/pdf-to-json.py vault/samples/invoice-001.txt

# 4. 验证生成的 JSON
cat vault/samples/invoice-001.json | jq .

# 5. 使用 jsonschema 验证
python3 << 'EOF'
import json, jsonschema
schema = json.load(open('vault/samples/schema.json'))
data = json.load(open('vault/samples/invoice-001.json'))
jsonschema.validate(data, schema)
print("✓ Valid against schema")
EOF
```

```bash
# 6. 重复另外 2 个文档
python3 scripts/pdf-to-json.py vault/samples/statement-002.txt vault/samples/receipt-003.txt

# 验证所有 3 个 JSON
for f in vault/samples/*.json; do
  echo "Validating $f..."
  python3 -c "import json,jsonschema; jsonschema.validate(json.load(open('$f')), json.load(open('vault/samples/schema.json')))"
done
```

### 验收标准

- [ ] 3 个非机密样本文档在 `vault/samples/*.txt`
- [ ] `vault/samples/schema.json` 定义了 6 字段（doc_type, doc_number, date, total_amount, currency, 等）
- [ ] `scripts/pdf-to-json.py` 成功提取所有 3 个文档
- [ ] 所有 3 个生成的 JSON 通过 jsonschema 验证
- [ ] JSON 包含正确的字段值（例如 invoice-001.json 的 total_amount = 9439.50）

---

## SOW M2 项目 #5：Hermes 多步骤任务，批准开启，所有路由演练

### 测试步骤

```bash
export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13
export PATH="/srv/z13/hermes/bin:$PATH"

# 1. 测试默认路由（doc-vision，便宜/快速）
sg docker -c "hermes --accept-hooks -z 'Calculate 7+5 using bash and echo the result.'" \
  | tail -10 > /tmp/route-test-a.log

cat /tmp/route-test-a.log
# 预期：包含 "12" 或类似计算结果，使用了 bash tool
```

```bash
# 2. 测试机密-困难路由（reasoning-max，本地 120B）
sg docker -c "hermes --accept-hooks -m reasoning-max -z 'If all Bloops are Razzies and all Razzies are Lazzies, are all Bloops definitely Lazzies?'" \
  | tail -15 > /tmp/route-test-b.log

cat /tmp/route-test-b.log
# 预期：包含逻辑推理（"Yes. ... By transitivity..."），使用 reasoning-max
```

```bash
# 3. 测试非机密-困难路由（cloud-kimi-k3，已激活 → 真实云端响应）
sg docker -c "hermes --accept-hooks -m cloud-kimi-k3 -z 'What is the capital of France?'" \
  | tail -10 > /tmp/route-test-c.log

cat /tmp/route-test-c.log
# 预期（Kimi 已激活）：包含真实云端回答（如 "Paris"）
# 注：若 cloud-kimi-k3 未激活，预期返回 401 key-missing（by design）
```

```bash
# 3b.（可选）测试未激活云别名的 keyless 状态（cloud-gpt-4o，期望 401）
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"cloud-gpt-4o","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' \
  | jq -r '.error.message'
# 预期：包含 "OPENAI_API_KEY" / "key_missing"
```

```bash
# 4. 验证防护措施
hermes gateway status | head -3
# 预期：显示 "Gateway is not running" 或类似

hermes portal status | head -3
# 预期：显示 "not logged in" 或类似

# 5. 检查审计日志
tail -5 /srv/z13/hermes/audit.jsonl | jq .
# 预期：包含最近的工具调用记录
```

### 验收标准

- [ ] 任务 A (doc-vision)：成功执行 bash 工具，返回 "12"
- [ ] 任务 B (reasoning-max)：返回逻辑推理，推理质量高于 doc-vision
- [ ] 任务 C (cloud-kimi-k3)：已激活 → 返回真实云端回答；未激活 → 返回 401 key-missing（不是 500 server error）
- [ ] 可选 3b：未激活云别名（cloud-gpt-4o）返回 "requires OPENAI_API_KEY" 错误（证明 keyless 路由生效）
- [ ] `--accept-hooks` 批准模式工作（没有交互式提示）
- [ ] 所有 3 个路由模板路径已演练（便宜/快速、机密-困难、非机密-困难）
- [ ] 防护措施验证：gateway 关闭 ✓，portal 未登录 ✓

---

## SOW M2 项目 #6：Docker 沙箱；loopback/tailscale 监听器；HERMES_HOME 在状态根

### 测试步骤

```bash
export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13

# 1. 验证 Hermes 配置
hermes config get terminal.backend
# 预期：docker

hermes config get terminal.docker_mount_cwd_to_workspace
# 预期：true
```

```bash
# 2. 测试 Docker 沙箱读取 vault
sg docker -c "hermes --accept-hooks -z 'Read /workspace/vault/test-fact.md and tell me its content.'"
# 预期：成功读取文件内容（不是 "file not found"）
```

```bash
# 3. 测试 Docker 沙箱写入 vault
sg docker -c "hermes --accept-hooks -z 'Create /workspace/vault/hermes-notes/sandbox-test-$(date +%Y%m%d).md with content: Sandbox write test on $(date).'"

# 验证文件存在
ls -la /srv/z13/vault/hermes-notes/sandbox-test-*.md

# 验证在 git status 中
cd /srv/z13
git status --short vault/hermes-notes/
# 预期：显示 ?? sandbox-test-*.md（未跟踪的新文件）
```

```bash
# 4. 验证监听器绑定（loopback 或 tailscale）
ss -tlnp | grep -E ':(8080|3000|11434)'
# 预期：所有监听器在 127.0.0.1 或 100.64.x.x（tailscale0），不是 0.0.0.0
```

```bash
# 5. 验证 HERMES_HOME 在状态根
echo $HERMES_HOME
# 预期：/srv/z13/hermes

ls -d $HERMES_HOME
# 预期：目录存在
```

### 验收标准

- [ ] Hermes 使用 Docker 后端（不是 local）
- [ ] Docker 沙箱成功读取 `/workspace/vault` 文件
- [ ] Docker 沙箱成功写入 `/workspace/vault` 文件
- [ ] 写入的文件出现在 git status 中
- [ ] llama-swap (8080), Open WebUI (3000) 监听器绑定到 loopback 或 tailscale0（不是 0.0.0.0）
- [ ] `HERMES_HOME=/srv/z13/hermes` 在状态根内

---

## SOW M2 项目 #7：Vault 双向读写，agent 笔记在 git status

### 测试步骤

```bash
cd /srv/z13
export HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13

# 1. Hermes 读取 vault
sg docker -c "hermes --accept-hooks -z 'List the directories in /workspace/vault and count them.'"
# 预期：返回目录列表（audits, daily, decisions, funds, hermes-notes, projects, runbooks）

# 2. Hermes 写入 vault
sg docker -c "hermes --accept-hooks -z 'Create /workspace/vault/hermes-notes/test-bidirectional-$(date +%s).md with content: Bidirectional test.'"

# 3. 验证在 git status
git status vault/hermes-notes/ | grep test-bidirectional
# 预期：显示新文件（untracked）

# 4. 人工写入 vault，Hermes 读取
echo "Manual fact: The Z13 state root is at /srv/z13." > vault/test-fact.md

sg docker -c "hermes --accept-hooks -z 'Read /workspace/vault/test-fact.md and summarize.'"
# 预期：Hermes 成功读取并总结人工写入的内容
```

### 验收标准

- [ ] Hermes 成功读取 vault 文件（Owner 写入）
- [ ] Hermes 成功写入 vault 文件（agent 写入）
- [ ] Agent 创建的笔记出现在 `git status` 中
- [ ] Vault 是双向的（Owner ↔ Hermes 都可读写）

---

## SOW M2 项目 #8：§C.5 两个大型 MoE 候选者（名称+量化+占用空间）

### 测试步骤

```bash
cd /srv/z13

# 1. 检查 manifests/models.yaml
grep -A10 "mixtral-8x22b:" manifests/models.yaml
grep -A10 "grok-1:" manifests/models.yaml

# 2. 验证字段
python3 << 'EOF'
import yaml
with open('manifests/models.yaml') as f:
    models = yaml.safe_load(f)

# Mixtral 8x22B
m1 = models.get('mixtral-8x22b')
assert m1, "mixtral-8x22b not found"
assert m1.get('total_params_b') == 141, f"Expected 141B, got {m1.get('total_params_b')}"
assert m1.get('quant') == 'Q4_K_M', f"Expected Q4_K_M, got {m1.get('quant')}"
assert m1.get('footprint_gb') >= 70, f"Expected >=70GB, got {m1.get('footprint_gb')}"
print(f"✓ Mixtral 8x22B: {m1['total_params_b']}B, {m1['quant']}, {m1['footprint_gb']}GB")

# Grok-1
m2 = models.get('grok-1')
assert m2, "grok-1 not found"
assert m2.get('total_params_b') >= 100, f"Expected >=100B, got {m2.get('total_params_b')}"
assert m2.get('footprint_gb') >= 80, f"Expected >=80GB, got {m2.get('footprint_gb')}"
print(f"✓ Grok-1: {m2['total_params_b']}B, {m2['quant']}, {m2['footprint_gb']}GB")
EOF
```

### 验收标准

- [ ] `manifests/models.yaml` 包含 `mixtral-8x22b` 条目
- [ ] Mixtral 8x22B: total_params_b=141, quant=Q4_K_M, footprint_gb≈74
- [ ] `manifests/models.yaml` 包含 `grok-1` 条目
- [ ] Grok-1: total_params_b≥100 (实际 314), footprint_gb≥80 (实际 92)
- [ ] 两个候选者均为 MoE 架构（architecture: MoE 或 experts: 8）
- [ ] §C.5 要求满足（2 个 100B+ MoE，显式命名+量化+占用空间）

---

## SOW M2 项目 #9：Google intake MCP 集成（测试账户）

### 测试步骤

```bash
export HERMES_HOME=/srv/z13/hermes

# 1. 验证 MCP 服务器已注册
hermes mcp list | grep google-drive

# 预期输出：
# google-drive    npx -y @modelcontext...    all    ✗ disabled (或 ✓ connected)
```

```bash
# 2. 如果是 disabled，说明等待 Owner OAuth 激活
hermes config get mcp.servers.google-drive.disabled
# 预期：true（M2 状态）或不存在（已激活）

# 3. 测试命令存在
which npx
npx -y @modelcontextprotocol/server-gdrive --version

# 4. 如果已激活（Owner 完成 OAuth），测试连接
# hermes mcp test google-drive
# 预期：显示可用工具（list_files, read_file, search_files, ...）
```

### 验收标准

- [ ] `google-drive` 出现在 `hermes mcp list` 中
- [ ] MCP 服务器注册为 `npx -y @modelcontextprotocol/server-gdrive`
- [ ] 技术就绪（可测试账户 / 等待 Owner OAuth 激活）
- [ ] **如果 disabled=true**：这是预期状态（M2 完成，等待 go-live）
- [ ] **如果 connected**：`hermes mcp test google-drive` 返回工具列表

---

## SOW M2 项目 #10：§B.8 eval harness + 单页操作指南

### 测试步骤

```bash
cd /srv/z13

# 1. 验证脚本存在且可执行
ls -l scripts/eval-harness.py
# 预期：-rwxr-xr-x 或类似（可执行）

# 2. 列出测试套件
python3 scripts/eval-harness.py --help
python3 scripts/eval-harness.py --list

# 预期：显示 5 个提示（arithmetic, capital, logic, instruction, json）
```

```bash
# 3. 在 doc-vision 上运行测试
python3 scripts/eval-harness.py doc-vision -o /tmp/eval-doc-vision.json

# 4. 检查结果
cat /tmp/eval-doc-vision.json | jq .
# 预期：
# {
#   "model": "doc-vision",
#   "timestamp": "...",
#   "results": [ ... 5 个测试 ... ],
#   "summary": {
#     "passed": 4-5,
#     "failed": 0-1,
#     "accuracy": 0.8-1.0,
#     "avg_latency_s": <number>
#   }
# }
```

```bash
# 5. 验证操作指南存在
cat runbook/eval.md | head -20
# 预期：单页 markdown，包含：
#   - 快速启动（python3 scripts/eval-harness.py <alias>）
#   - 可用别名列表
#   - 输出格式说明
#   - 验收标准
```

### 验收标准

- [ ] `scripts/eval-harness.py` 存在且可执行
- [ ] 包含 5 个不同类型的提示（算术、常识、逻辑、指令遵循、JSON）
- [ ] 在 doc-vision 上运行返回结构化 JSON（包含 summary.accuracy）
- [ ] `runbook/eval.md` 存在，单页（<100 行），包含快速启动示例
- [ ] 可在任意别名上运行（doc-vision, reasoning-max, utility-fast）
- [ ] 输出包含通过率、延迟、token 统计

---

## 最终汇总

完成所有 10 个测试后，填写：

| 项目 # | 描述 | 状态 | 备注 |
|---|---|---|---|
| 1 | 14 个别名单端点；已激活云别名可用，未激活返回 key_missing | ☐ ✅ / ☐ ❌ | |
| 2 | 别名交换测试 | ☐ ✅ / ☐ ❌ | |
| 3 | llama-swap YAML 提交；§D.5 flags | ☐ ✅ / ☐ ❌ | |
| 4 | doc-vision 3-PDF→JSON | ☐ ✅ / ☐ ❌ | |
| 5 | Hermes 路由演示 | ☐ ✅ / ☐ ❌ | |
| 6 | Docker 沙箱；loopback 监听器 | ☐ ✅ / ☐ ❌ | |
| 7 | Vault 双向读写 | ☐ ✅ / ☐ ❌ | |
| 8 | §C.5 两个 MoE 候选者 | ☐ ✅ / ☐ ❌ | |
| 9 | Google Drive MCP 集成 | ☐ ✅ / ☐ ❌ | |
| 10 | §B.8 eval harness | ☐ ✅ / ☐ ❌ | |

**M2 验收结果**：____ / 10 PASS

如果所有 10 项均 ✅，M2 完整验收通过 ✓

---

## 生成验收报告

```bash
cd /srv/z13

cat > vault/audits/m2-acceptance-$(date +%Y%m%d).md << 'EOF'
# M2 Acceptance Report — $(date +%Y-%m-%d)

Tester: [Your Name]
System: Z13 (gfx1151, 96GB VRAM)
Build: M2 Round 1+2

## Results

[粘贴上面的汇总表格]

## Evidence

- llama-swap logs: [附件或路径]
- Hermes audit.jsonl: [最后 20 行]
- eval harness results: /tmp/eval-*.json

## Conclusion

M2 验收状态：[PASS / CONDITIONAL PASS / FAIL]

未解决问题（如有）：
- [列出]

签字：___________    日期：___________
EOF

git add vault/audits/m2-acceptance-*.md
git commit -m "docs(M2): acceptance test report — $(date +%Y%m%d)"
```

**完成**。你现在有完整的 M2 验收测试清单。
