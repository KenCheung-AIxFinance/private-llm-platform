# Alias-Swap Test — 2026-08-14

**SOW M2 项目 #2**："别名交换测试：utility-fast 背后的模型在零下游配置更改的情况下被替换"

## 目标

证明 llama-swap 的别名抽象有效：可以在 YAML 中交换模型实现，客户端代码（Hermes、open-webui、任何 OpenAI 客户端）**无需任何配置更改**即可继续工作。

## 测试方法

1. **原始配置**：`utility-fast` → Gemma 4 26B-A4B QAT Q4_0（有 thought-channel 特性）
2. **交换配置**：`utility-fast` → Gemma 4 E4B Q4_K_M（doc-vision 的模型，清晰内容）
3. **客户端请求**：使用 `"model":"utility-fast"` 发送相同的 curl 请求（**代码不变**）
4. **验证**：响应来自新模型，客户端无感知

## 配置更改

### 原始（Gemma 4 26B-A4B）

```yaml
  utility-fast:
    name: "Gemma 4 26B-A4B QAT Q4 (utility-fast)"
    cmd: |
      ${llama} ${z13flags} -m ${models}/gemma-4-26B-A4B-it-QAT-GGUF/gemma-4-26B-A4B-it-QAT-Q4_0.gguf
    ttl: 0
    concurrencyLimit: 4
```

### 交换后（Gemma 4 E4B）

```yaml
  utility-fast:
    name: "Gemma 4 E4B Q4_K_M (utility-fast SWAPPED for test)"
    cmd: |
      ${llama} ${z13flags} -m ${models}/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf
      --mmproj ${models}/gemma-4-E4B-it-GGUF/mmproj-gemma-4-E4B-it-BF16.gguf
    ttl: 0
    concurrencyLimit: 4
```

**注意**：仅修改了 `name` 和 `cmd`（模型路径）。别名 ID `utility-fast` 保持不变。

## 客户端请求（不变）

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"utility-fast","messages":[{"role":"user","content":"What is 5+3? Reply with just the number."}],"max_tokens":16,"temperature":0}'
```

**关键点**：客户端仍然请求 `"model":"utility-fast"` —— **零代码更改**。

## 测试结果

### 交换后的响应

```json
{
  "choices": [{
    "message": {
      "content": "8"
    },
    "finish_reason": "stop"
  }],
  "model": "/home/norbert/.lmstudio/models/lmstudio-community/gemma-4-E4B-it-GGUF/gemma-4-E4B-it-Q4_K_M.gguf",
  "usage": {
    "completion_tokens": 2,
    "prompt_tokens": 29,
    "total_tokens": 31
  }
}
```

### 验证点

| 检查项 | 结果 | 证据 |
|---|---|---|
| 客户端请求别名不变 | ✅ PASS | 请求 `"model":"utility-fast"` |
| 响应内容有效 | ✅ PASS | `content: "8"`（清晰内容，不是原 A4B 的空字符串）|
| 响应来自新模型 | ✅ PASS | `model` 字段显示 `gemma-4-E4B-it-Q4_K_M.gguf` |
| finish_reason 正常 | ✅ PASS | `stop`（不是 A4B 的 `length`）|
| 客户端无需配置更改 | ✅ PASS | 相同的 curl 命令，零代码修改 |

### 模型特征差异（确认交换生效）

| 特征 | 原始（A4B） | 交换后（E4B） |
|---|---|---|
| 模型文件 | `gemma-4-26B-A4B-it-QAT-Q4_0.gguf` | `gemma-4-E4B-it-Q4_K_M.gguf` |
| 参数 | 26B | ~9B |
| Thought-channel | 是（chat 端点返回空内容） | 否（返回清晰内容）|
| VLM 支持 | 否 | 是（带 mmproj）|
| 响应内容 | 空字符串 `''` (max_tokens 小时) | 清晰答案 `"8"` |

## 下游客户端验证

交换期间，llama-swap 的 `/v1/models` 端点仍然列出 `utility-fast`，但 `name` 字段已更新：

```json
{
  "id": "utility-fast",
  "name": "Gemma 4 E4B Q4_K_M (utility-fast SWAPPED for test)",
  "object": "model",
  "owned_by": "llama-swap"
}
```

**任何** OpenAI 兼容客户端（Hermes、open-webui、Continue.dev、原始 `openai` Python SDK）都会：
1. 发现端点仍然提供 `utility-fast`
2. 发送请求到 `"model":"utility-fast"`
3. 接收有效响应
4. **完全不知道底层模型已更改**

## 结论

✅ **别名交换测试 PASS**

llama-swap 的别名抽象按设计工作：
- 工程师可以在 `config.yaml` 中交换模型实现（升级、降级、A/B 测试、故障转移）
- 下游客户端（应用层）**无需任何配置更改**
- 别名 ID 保持稳定；实现细节被抽象化

这满足了 SOW §D.1 的"稳定别名作为可审查配置"要求 —— 别名是合约，YAML 是实现。

## 恢复

测试后，`config.yaml` 已恢复为原始配置（Gemma 4 26B-A4B），llama-swap 已重启。备份保存在 `llama-swap/config.yaml.backup`。

---

**测试执行**：2026-08-14  
**测试者**：Engineer  
**状态**：✅ PASS（SOW M2 项目 #2 完成）
