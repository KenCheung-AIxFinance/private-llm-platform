# Z13 Private AI Platform — 完整架构文档

**文档版本**：2026-08-28（M2 完整实测版）  
**状态**：生产运行中（10/10 SOW M2 完成）

---

## 架构总览（硬件到应用层）

```
┌──────────────────────────────────────────────────────────────────────┐
│  Layer 5 — 应用层                                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │
│  │  Hermes Agent    │  │  Open WebUI      │  │  Python Client   │   │
│  │  (CLI/Agent)     │  │  (Web UI)        │  │  (API direct)    │   │
│  │  ~/.local/bin/   │  │  :3000           │  │                  │   │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘   │
│           │                     │                     │               │
│           └─────────────────────┴─────────────────────┘               │
│                                 │                                     │
│                    OpenAI/Anthropic 格式 API 请求                      │
│                    "model": "doc-vision" / "cloud-kimi-k3"           │
└──────────────────────────────────┬───────────────────────────────────┘
                                   │
┌──────────────────────────────────▼───────────────────────────────────┐
│  Layer 4 — 服务路由层（单一端点，多后端）                               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  llama-swap v249 (mostlygeek)                                 │   │
│  │  PID: 26344, Listen: 127.0.0.1:8080                          │   │
│  │  /srv/z13/tools/llama-swap/llama-swap                        │   │
│  │                                                               │   │
│  │  功能：别名路由、模型热加载/卸载、健康检查、统一 API          │   │
│  │  配置：/srv/z13/llama-swap/config.yaml                       │   │
│  └────────┬─────────────────────┬───────────────────┬──────────┘   │
│           │ 本地别名              │ 本地别名           │ 云别名       │
└───────────┼─────────────────────┼───────────────────┼──────────────┘
            │                     │                   │
    ┌───────▼──────┐     ┌────────▼────────┐    ┌───▼────────────┐
    │ doc-vision   │     │ utility-fast    │    │ cloud-kimi-k3  │
    │ reasoning-max│     │ utility-embed   │    │ cloud-fable-5  │
    │  (:10002)    │     │  (:10001)       │    │  (401 stub)    │
    └───────┬──────┘     └────────┬────────┘    └───┬────────────┘
            │                     │                  │
┌───────────▼─────────────────────▼──────────────────┼──────────────┐
│  Layer 3 — 本地推理引擎                             │              │
│  ┌────────────────────────────────────────────┐   │              │
│  │  llama-server (llama.cpp, Vulkan build)    │   │              │
│  │  /srv/z13/tools/llama.cpp/build/bin/      │   │              │
│  │  每个本地别名 = 1 个 llama-server 进程      │   │              │
│  │  Ports: 10001, 10002, 10003...             │   │              │
│  │  Flags: --jinja -ub 512 -ctk/-ctv q8_0     │   │              │
│  │         -fa auto (Flash Attn)              │   │              │
│  │         -ngl 999 (全层进 GPU)               │   │              │
│  └────────────────┬───────────────────────────┘   │              │
│                   │ ggml Vulkan backend           │              │
└───────────────────┼───────────────────────────────┼──────────────┘
                    │                               │
┌───────────────────▼───────────────────────────────▼──────────────┐
│  Layer 2 — GPU 运行时                           云端 API           │
│  ┌────────────────────────────────────┐    ┌──────────────────┐ │
│  │  Vulkan 1.3.x (Mesa RADV driver)   │    │ Moonshot/Kimi    │ │
│  │  /usr/lib/x86_64-linux-gnu/        │    │ DeepSeek         │ │
│  │  libvulkan.so                       │    │ Google Gemini    │ │
│  └────────────────┬───────────────────┘    │ ...              │ │
│                   │                         └──────────────────┘ │
└───────────────────┼──────────────────────────────────────────────┘
                    │
┌───────────────────▼───────────────────────────────────────────────┐
│  Layer 1 — 硬件层                                                  │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │  AMD Radeon RX 8060S (gfx1151, RDNA 3.5)               │     │
│  │  96 GB VRAM (HBM3e)                                      │     │
│  │  当前占用：6.9 GB (doc-vision resident)                  │     │
│  │  架构：6144 SP, 192 TMU, 96 ROP                          │     │
│  └─────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────┘
```

---

## 层级详解

### Layer 1 — 硬件层

**GPU**：AMD Radeon RX 8060S (gfx1151)
- VRAM：96 GB HBM3e
- 架构：RDNA 3.5, 6144 shader processors
- 驱动：Mesa RADV (开源 Vulkan 驱动)
- 监控：`rocm-smi --showmeminfo vram`

**主机**：
- CPU：(未记录，但足够支撑并发推理)
- 状态根：`/srv/z13` (500+ GB)
- 模型存储：`~/.lmstudio/models/lmstudio-community/` (~70 GB 已用)

### Layer 2 — GPU 运行时 + 云端 API

**本地路径**：
- **Vulkan API**：`libvulkan.so` (Mesa RADV 实现)
- **设备枚举**：`gfx1151` (GPU ID 0)
- **内存管理**：Vulkan VMA, unified memory pool
- **选择原因**：gfx1151 上 Vulkan 比 ROCm 稳定（SOW §D.5）

**云端路径**（keyless stub，等待 Owner 激活）：
- Moonshot/Kimi API：`https://api.moonshot.cn/v1`
- DeepSeek API：`https://api.deepseek.com/v1`
- Google Gemini、Fable 5、Qwen：各自端点

### Layer 3 — 本地推理引擎

**llama-server** (upstream llama.cpp)
- **位置**：`/srv/z13/tools/llama.cpp/build/bin/llama-server`
- **编译**：cmake + `-DGGML_VULKAN=ON` + `-DGGML_FLASH_ATTN=ON`
- **编译时间**：M1 完成，见 `runbook/build.md`

**进程模型**：每个本地别名 = 1 个独立 llama-server
- doc-vision → port 10002 (PID 30767)
- utility-fast → port 10001 (按需冷载)
- utility-embed → port 10003 (按需冷载)
- reasoning-max → port 10004 (ttl 900s，长时空闲卸载)

**关键 flags**（§D.5 强制）：
```bash
--jinja          # 模板支持（Gemma chat 格式）
-ub 512          # batch size 512
-ctk q8_0        # KV cache 类型量化 q8_0
-ctv q8_0        # KV cache 值量化 q8_0
-fa auto         # Flash Attention 自动检测
-ngl 999         # 全部层进 GPU
-t 8             # 8 线程
```

**模型加载**：
- 路径宏：`${models} = ~/.lmstudio/models/lmstudio-community/`
- 格式：GGUF (ggml 统一格式)
- 量化：Q4_K_M (doc-vision/utility-fast), MXFP4 (reasoning-max)

### Layer 4 — 服务路由层

**llama-swap** (mostlygeek/llama-swap v249, Go 单文件)
- **位置**：`/srv/z13/tools/llama-swap/llama-swap`
- **配置**：`/srv/z13/llama-swap/config.yaml`
- **监听**：`127.0.0.1:8080` (loopback-only per §E.6)
- **启动**：`systemctl start llama-swap` (systemd unit, 已设开机自启)

**核心功能**：
1. **别名路由**：客户端请求 `"model": "doc-vision"` → llama-swap 识别别名 → 转发到 `localhost:10002`
2. **模型管理**：
   - `groups.utilities.swap: false` → doc-vision/utility-fast/utility-embed 常驻
   - `reasoning-max.ttl: 900` → 15 分钟无请求自动卸载
   - 首次请求冷载 (healthCheckTimeout: 600s)
3. **健康检查**：每个 llama-server 启动后 GET `/health`，通过才加入路由
4. **统一端点**：对外只暴露 `:8080`，客户端无需知道子进程端口
5. **日志聚合**：llama-server 输出通过 llama-swap 代理到 journalctl

**别名清单**（10 个）：
- **4 个本地别名**：doc-vision (默认 VLM), utility-fast (26B), utility-embed (嵌入), reasoning-max (120B 推理)
- **5 个云别名**：cloud-kimi-k3, cloud-fable-5, cloud-deepseek-v4-pro, cloud-qwen, cloud-gemini
- **1 个 stub**：`cloud-disabled` (Python HTTP，返回 401 key_missing，承接 5 个云别名直到 Owner 加密钥)

**配置 schema**（真实）：
```yaml
macros:
  "llama": "/srv/z13/tools/llama.cpp/build/bin/llama-server --port ${PORT}"
  "z13flags": "--jinja -ub 512 -ctk q8_0 -ctv q8_0 -fa auto -ngl 999 -t 8"
  "models": "${env.HOME}/.lmstudio/models/lmstudio-community"

models:
  doc-vision:
    cmd: |
      ${llama} ${z13flags} -m ${models}/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf
      --mmproj ${models}/gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf
    ttl: 0  # 常驻
  cloud-disabled:
    cmd: /usr/bin/python3 /srv/z13/scripts/cloud-stub.py ${PORT}
    aliases: [cloud-kimi-k3, cloud-fable-5, ...]  # 5 个云别名共享
```

### Layer 5 — 应用层

**Hermes Agent** (NousResearch/hermes-agent v0.20.0)
- **入口**：`~/.local/bin/hermes` (shim → venv)
- **状态目录**：`/srv/z13/hermes/` (HERMES_HOME)
- **配置**：
  ```
  model.provider = custom
  model.base_url = http://127.0.0.1:8080/v1
  model.default = doc-vision
  terminal.backend = docker
  terminal.cwd = /srv/z13 (需 TERMINAL_CWD 环境变量)
  ```
- **Docker 沙箱**：`/srv/z13` 挂载为 `/workspace` (需 Docker Desktop filesharingDirectories)
- **vault 双向**：Agent 可读写 `/workspace/vault` ↔ 主机 `/srv/z13/vault`
- **审计日志**：`/srv/z13/hermes/audit.jsonl` (pre_tool_call hook)

**Open WebUI** (ghcr.io/open-webui/open-webui:main)
- **监听**：`127.0.0.1:3000` (loopback-only)
- **后端**：`OLLAMA_BASE_URL=http://host.docker.internal:8080` (llama-swap)
- **存储**：`open-webui-data` volume (对话历史、用户设置)
- **启动**：`cd /srv/z13/compose && docker compose up -d`
- **认证**：`WEBUI_AUTH=false` (loopback 访问免登录 per §E.6)

**Python/curl 客户端**：直连 `http://127.0.0.1:8080/v1/chat/completions`

---

## 数据流示例

### 场景 A：Open WebUI 用户聊天（本地模型）

```
1. 用户在浏览器访问 http://127.0.0.1:3000
2. Open WebUI 发送：
   POST http://host.docker.internal:8080/v1/chat/completions
   {"model": "doc-vision", "messages": [...]}
3. llama-swap 收到请求：
   - 查找 models.doc-vision
   - 检查 llama-server:10002 是否活着（是，常驻）
   - 反向代理到 http://localhost:10002/v1/chat/completions
4. llama-server:10002 (PID 30767):
   - 加载 context (已缓存)
   - Vulkan 调用 GPU (gfx1151)
   - 推理 token-by-token，流式返回
5. llama-swap 转发流式响应给 Open WebUI
6. 浏览器实时显示生成文本
```

### 场景 B：Hermes Agent 读 vault（Docker 沙箱）

```
1. 用户执行：sg docker -c "HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13 \
   hermes --accept-hooks -z 'Read /workspace/vault/test-fact.md'"
2. Hermes 收到任务：
   - 解析工具调用：Read tool
   - 启动 Docker 容器（backend=docker）
   - 挂载：/srv/z13 → /workspace (由 TERMINAL_CWD 决定)
3. Docker 容器内执行 cat /workspace/vault/test-fact.md
4. Hermes 收到文件内容
5. 调用 llama-swap (model.base_url=http://127.0.0.1:8080/v1):
   POST /v1/chat/completions {"model":"doc-vision", "messages":[...文件内容...]}
6. llama-swap → llama-server:10002 → GPU → 推理回答
7. Hermes 收到回答，写入 audit.jsonl，返回用户
```

### 场景 C：云别名（keyless stub，期望行为）

```
1. 客户端请求 {"model": "cloud-kimi-k3", ...}
2. llama-swap 识别别名 cloud-kimi-k3 → models.cloud-disabled
3. 转发到 http://localhost:10005/v1/chat/completions (cloud-stub.py)
4. cloud-stub.py 返回：
   HTTP 401 Unauthorized
   {"error": {"message": "cloud alias keyless until go-live (SOW §C.3/§0.4); 
              Owner adds provider key", "type": "authentication_error", 
              "code": "key_missing"}}
5. llama-swap 转发 401 给客户端
6. Open WebUI 显示错误消息（预期行为）
```

**注**：云别名激活后，`cloud-disabled` 会被 5 个独立的真实云 provider 配置替换（见下一节"云端激活路线图"）。

---

## 关键路径和文件

| 组件 | 路径 | 说明 |
|---|---|---|
| 状态根 | `/srv/z13/` | git 仓库，所有配置/脚本/文档 |
| llama-swap 二进制 | `/srv/z13/tools/llama-swap/llama-swap` | v249, 23 MB Go 单文件 |
| llama-server 二进制 | `/srv/z13/tools/llama.cpp/build/bin/llama-server` | Vulkan 编译，链接 libvulkan.so |
| llama-swap 配置 | `/srv/z13/llama-swap/config.yaml` | 别名定义、宏、ttl、groups |
| Hermes 状态目录 | `/srv/z13/hermes/` | config.yaml, audit.jsonl, sessions/ |
| 模型权重 | `~/.lmstudio/models/lmstudio-community/` | GGUF 文件，70+ GB |
| Open WebUI compose | `/srv/z13/compose/compose.yaml` | Docker Compose 定义 |
| Vault（知识库）| `/srv/z13/vault/` | 双向读写（Owner ↔ Hermes）|
| 审计日志 | `/srv/z13/hermes/audit.jsonl` | 工具调用审计 |
| systemd units | `/etc/systemd/system/llama-swap.service` | 开机自启 |

---

## 监控和验证

### 健康检查（重启后验证）

```bash
# 1. llama-swap 端点
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/models  # 期望 200

# 2. Open WebUI
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/  # 期望 200

# 3. 别名清单
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id' | sort  # 10 个

# 4. GPU 占用
rocm-smi --showmeminfo vram | grep -i used  # 期望 6-10 GB (resident 模型)

# 5. llama-server 进程
pgrep -af llama-server | wc -l  # 期望 1-4 (按需)

# 6. Hermes 配置
export HERMES_HOME=/srv/z13/hermes
hermes config get model.base_url  # 期望 http://127.0.0.1:8080/v1
```

### 性能基准（M2 实测，gfx1151, 96GB VRAM）

| 别名 | 模型 | 延迟（avg） | tok/s | 适用场景 |
|---|---|---|---|---|
| doc-vision | Gemma-4 E4B 9B VLM | ~2s | 57 | 文档分析、默认 |
| utility-fast | Gemma-4 26B-A4B | ~2s | 55 | 快速响应 |
| reasoning-max | GPT-OSS 120B | ~8s | 47 | 复杂推理 |
| utility-embed | bge-m3 Q8 | ~0.5s | N/A | 向量嵌入 |

---

## 云端激活路线图（待 Owner 执行）

当前云别名状态：5 个别名 → 1 个 stub (cloud-stub.py) → HTTP 401 keyless

**激活步骤**（Owner 独立操作，§0.4）：

1. 获取 API keys（保存到环境或 vault，不进 git）：
   ```bash
   export KIMI_API_KEY="sk-..."
   export DEEPSEEK_API_KEY="sk-..."
   export GEMINI_API_KEY="..."
   ```

2. 编辑 `/srv/z13/llama-swap/config.yaml`，将 `cloud-disabled` 替换为独立配置：
   ```yaml
   models:
     cloud-kimi-k3:
       provider: openai  # OpenAI 兼容
       base_url: https://api.moonshot.cn/v1
       model: moonshot-v1-128k
       api_key_env: KIMI_API_KEY
     cloud-deepseek-v4-pro:
       provider: openai
       base_url: https://api.deepseek.com/v1
       model: deepseek-chat
       api_key_env: DEEPSEEK_API_KEY
     # ... 其他 3 个云别名
   ```

3. 重启 llama-swap：`sudo systemctl restart llama-swap`

4. 测试云别名：
   ```bash
   curl http://127.0.0.1:8080/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"cloud-kimi-k3","messages":[{"role":"user","content":"hi"}]}'
   # 期望：真实回答（不是 401）
   ```

5. 在 Open WebUI 中选择云别名，验证响应。

---

## 故障排查快速参考

| 症状 | 根因 | 修复 |
|---|---|---|
| Hermes `Connection error` | llama-swap 没跑 | `sudo systemctl start llama-swap` |
| `docker ps` 报 daemon 不可达 | Docker Desktop 没起 | `systemctl --user start docker-desktop` |
| 重启后服务全停 | 没设开机自启 | `sudo systemctl enable llama-swap; systemctl --user enable docker-desktop` |
| Open WebUI 无别名 | llama-swap 未就绪 | 等待 10-30s (resident 模型加载) |
| GPU VRAM 0% | llama-server 未启动或 `-ngl 0` | 检查 `pgrep llama-server`; 配置应为 `-ngl 999` |
| 云别名 401 | 预期行为（keyless） | Owner 激活（见上节）|

---

## 文档引用

- **使用指南**：`/srv/z13/docs/m2-usage-guide.md` (日常启动、重启激活、故障排查)
- **搭建手册**：`/srv/z13/docs/m2-build-manual.md` (从零重建)
- **验收测试**：`/srv/z13/docs/m2-acceptance-tests.md` (SOW 10 项验证)
- **运行手册**：`/srv/z13/runbook/` (llama.cpp 编译、eval、benchmarking)
- **审计记录**：`/srv/z13/vault/audits/` (M2 每轮交付证据)

---

**维护者**：Owner  
**最后更新**：2026-08-28（实测架构 + 云端激活流程）  
**下一里程碑**：M3 — 可移植性与恢复（~2026-08-22）
