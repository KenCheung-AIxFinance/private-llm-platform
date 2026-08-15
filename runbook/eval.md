# runbook/eval.md — Evaluation harness (§B.8)

轻量级评估框架，用于对 llama-swap 别名进行基准测试和回归测试。

## 快速开始

```bash
cd /srv/z13
# 列出可用别名
./scripts/eval-harness.py --list

# 在模型上运行评估套件
./scripts/eval-harness.py utility-fast

# 保存结果到文件
./scripts/eval-harness.py doc-vision -o eval-results-$(date +%Y%m%d).json
```

## 评估套件

Harness 运行 5 个简单提示，涵盖不同类别：

| 提示 ID | 类别 | 测试内容 |
|---|---|---|
| `arithmetic_simple` | 算术 | 基本加法（15 + 27 = 42）|
| `capital_france` | 知识 | 事实召回（巴黎）|
| `logic_simple` | 逻辑 | 三段论推理（猫需要食物）|
| `counting` | 计数 | 字符串长度（"evaluation" = 10 个字母）|
| `json_format` | 格式 | JSON 生成 |

**设计理念**：快速烟雾测试（~10-40 秒），而不是全面的学术评估。用于：
- M1→M3 回归测试（基准 vs 重建）
- 模型比较（reasoning-max vs utility-fast）
- 配置验证（llama-swap 路由正确工作）

## 输出格式

JSON 输出到 stdout（或使用 `-o` 输出到文件）：

```json
{
  "model": "doc-vision",
  "timestamp": "2026-08-14T08:30:00Z",
  "endpoint": "http://127.0.0.1:8080/v1",
  "summary": {
    "total_prompts": 5,
    "successes": 2,
    "failures": 3,
    "accuracy": 0.4,
    "avg_elapsed_s": 1.71,
    "total_tokens": 430
  },
  "results": [
    {
      "id": "arithmetic_simple",
      "category": "arithmetic",
      "success": true,
      "response": "42",
      "expected_pattern": "42",
      "matched": true,
      "elapsed_s": 3.43,
      "tokens": {"prompt": 20, "completion": 2, "total": 22}
    },
    ...
  ]
}
```

## 解读结果

### 准确率

- **> 60%**：模型在简单任务上表现良好
- **40-60%**：部分通过（可能是 thought-channel 问题或模型限制）
- **< 40%**：可能的配置问题或模型不适合这些提示

### 延迟

- **< 2s**：快速（utility-fast、doc-vision）
- **2-10s**：中等（reasoning-max）
- **> 10s**：慢（可能是 swap 延迟或大型模型）

### Token

`total_tokens` 跟踪 API 使用情况；用于成本估算（当云别名在上线时有密钥时）。

## 基准（M2 第 2 轮烟雾测试 2026-08-14）

| 模型 | 准确率 | 平均延迟 | 总 Token |
|---|---|---|---|
| doc-vision | 40% (2/5) | 1.71s | 430 |
| reasoning-max | 80% (4/5) | 8.04s | 551 |
| utility-fast | 40% (2/5) | 1.74s | 679 |

**注意**：
- **reasoning-max**（120B）表现最好（80%），正如预期
- **doc-vision** 和 **utility-fast**：40%（算术 + 知识通过；逻辑/计数/JSON 失败）
- utility-fast 失败部分是由于 **thought-channel**（Gemma-4-A4B 特性）—— eval harness 使用 `max_tokens=128` 来缓解，但某些提示仍然失败

## 用例

### 1. 回归测试（M1 vs M3）

在 M1 上建立基准：
```bash
./scripts/eval-harness.py doc-vision -o baseline-m1-doc-vision.json
./scripts/eval-harness.py reasoning-max -o baseline-m1-reasoning-max.json
```

M3 重建后重新运行：
```bash
./scripts/eval-harness.py doc-vision -o rebuild-m3-doc-vision.json
```

比较：
```bash
diff <(jq '.summary' baseline-m1-doc-vision.json) \
     <(jq '.summary' rebuild-m3-doc-vision.json)
```

预期：准确率和延迟在 ±10% 内（小的变化是正常的）。

### 2. 模型比较

```bash
for model in utility-fast doc-vision reasoning-max; do
  echo "=== $model ==="
  ./scripts/eval-harness.py $model | jq '.summary'
done
```

用于选择任务的最佳模型（快速 vs 准确）。

### 3. 别名交换验证

交换 `utility-fast` 的模型后（在 `llama-swap/config.yaml` 中）：

```bash
systemctl restart llama-swap
./scripts/eval-harness.py utility-fast -o post-swap.json
```

验证：准确率保持相似（别名抽象有效）。

## 注意事项

- **不是全面的评估**：这是一个快速烟雾测试，而不是 EleutherAI lm-eval-harness 或学术基准
- **提示特定**：5 个提示足以进行回归检查，但不适用于生产模型选择
- **模型选择**：Owner 选择运行哪些模型（harness 支持任何 llama-swap 别名）
- **Thought-channel**：utility-fast（Gemma-4-A4B）有 `<|channel|>thought` 特性；harness 使用 `max_tokens=128` 来缓解
- **云别名**：在 M2 keyless；在 Owner 添加密钥后的上线时运行

## 扩展

要添加更多评估提示，编辑 `scripts/eval-harness.py` 中的 `EVAL_PROMPTS` 列表：

```python
EVAL_PROMPTS.append({
    "id": "new_test",
    "prompt": "Your prompt here",
    "expected_pattern": r"expected.*regex",
    "category": "your-category"
})
```

对于更高级的评估：
- **困惑度**：使用 llama.cpp 的内置 `perplexity` 工具
- **HumanEval**：Python 代码生成（需要执行沙箱）
- **MMLU**：多任务语言理解（大型数据集）

## 故障排除

### "No models found or llama-swap not running"

llama-swap 未在 `127.0.0.1:8080` 上运行。启动它：
```bash
systemctl status llama-swap
# 或手动：
/srv/z13/tools/llama-swap/llama-swap -config /srv/z13/llama-swap/config.yaml -listen 127.0.0.1:8080
```

### "HTTP 401: cloud alias keyless"

云别名在 M2 keyless（设计如此）。在上线后运行，或使用本地别名。

### 所有响应为空字符串

可能是 thought-channel 问题（utility-fast）或 `max_tokens` 太小。Harness 使用 128；如果仍然失败，增加到 256。

---

**交付**：2026-08-14（§B.8）  
**Owner 选择**：运行哪些模型进行评估
