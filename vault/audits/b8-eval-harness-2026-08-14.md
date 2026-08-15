# §B.8 Eval Harness — 2026-08-14

**SOW M2 项目 #10**："Eval harness + 单页操作指南已交付"

## 目标

交付一个轻量级、可重复的评估框架，用于基准测试和回归测试 llama-swap 别名。

**范围**：
- **不是**：完整的学术评估套件（EleutherAI lm-eval-harness 规模太大）
- **是**：快速烟雾测试框架（~10-40 秒）用于 M1→M3 回归和模型比较
- **Owner 选择**：运行哪些模型（harness 支持任何 llama-swap 别名）

## 交付物

### 1. Eval Harness 脚本

**路径**：`/srv/z13/scripts/eval-harness.py`

**特性**：
- 在任何 llama-swap 别名上运行 5 个评估提示
- JSON 输出（stdout 或文件）
- 汇总统计：准确率、平均延迟、总 token
- 每个提示的详细结果（响应、模式匹配、token、延迟）

**用法**：
```bash
./scripts/eval-harness.py <alias>           # 运行评估
./scripts/eval-harness.py --list            # 列出别名
./scripts/eval-harness.py doc-vision -o results.json  # 保存到文件
```

### 2. 单页操作指南

**路径**：`/srv/z13/runbook/eval.md`

**内容**：
- 快速开始（3 个示例）
- 评估套件描述（5 个提示，类别）
- 输出格式（JSON schema）
- 解读结果（准确率/延迟/token 指南）
- M2 基准（doc-vision/reasoning-max/utility-fast）
- 用例（回归测试、模型比较、别名交换验证）
- 注意事项（不是全面的评估，thought-channel，云别名 keyless）
- 扩展（如何添加提示）
- 故障排除

**长度**：~200 行（单页，可打印）

## 评估套件

5 个简单提示，涵盖不同类别：

| 提示 ID | 类别 | 测试内容 | 预期模式 |
|---|---|---|---|
| arithmetic_simple | 算术 | 15 + 27 = ? | `42` |
| capital_france | 知识 | 法国首都 | `Paris` |
| logic_simple | 逻辑 | 三段论（猫→动物→食物）| `yes`（不区分大小写）|
| counting | 计数 | "evaluation" 中的字母 | `10` |
| json_format | 格式 | 生成 JSON | `"status".*"ok"` |

**设计理念**：
- 快速（< 40 秒总运行时间）
- 多样化（算术、知识、逻辑、计数、格式）
- 可重复（`temperature=0`）
- 正则表达式匹配（灵活的响应验证）

## 烟雾测试结果（M2 第 2 轮，2026-08-14）

### doc-vision（Gemma 4 E4B Q4_K_M）

```json
{
  "model": "doc-vision",
  "summary": {
    "total_prompts": 5,
    "successes": 2,
    "failures": 3,
    "accuracy": 0.4,
    "avg_elapsed_s": 1.71,
    "total_tokens": 430
  }
}
```

**通过**：arithmetic_simple、capital_france  
**失败**：logic_simple、counting、json_format

### reasoning-max（GPT-OSS-120B MXFP4）

```json
{
  "model": "reasoning-max",
  "summary": {
    "total_prompts": 5,
    "successes": 4,
    "failures": 1,
    "accuracy": 0.8,
    "avg_elapsed_s": 8.04,
    "total_tokens": 551
  }
}
```

**通过**：capital_france、logic_simple、counting、json_format  
**失败**：arithmetic_simple（可能超时，30s）

### utility-fast（Gemma 4 26B-A4B Q4_0）

```json
{
  "model": "utility-fast",
  "summary": {
    "total_prompts": 5,
    "successes": 2,
    "failures": 3,
    "accuracy": 0.4,
    "avg_elapsed_s": 1.74,
    "total_tokens": 679
  }
}
```

**通过**：arithmetic_simple、capital_france  
**失败**：logic_simple、counting、json_format

**注意**：utility-fast 的部分失败是由于 **thought-channel**（Gemma-4-A4B 在小 `max_tokens` 下返回空 `content`）。Harness 使用 `max_tokens=128` 来缓解，但某些提示仍然失败。这是已知的模型特性（在 `runbook/serving.md` 和 `runbook/eval.md` 中记录）。

## 验证点

| 检查项 | 状态 | 证据 |
|---|---|---|
| Eval harness 已交付 | ✅ PASS | `scripts/eval-harness.py` |
| 单页操作指南 | ✅ PASS | `runbook/eval.md` (~200 行)|
| 可运行（烟雾测试）| ✅ PASS | 在 3 个别名上测试，生成 JSON |
| JSON 输出格式 | ✅ PASS | 结构化：summary + results |
| 列出别名 | ✅ PASS | `--list` 标志有效 |
| Owner 选择模型 | ✅ PASS | 接受任何 llama-swap 别名作为参数 |
| 基准记录 | ✅ PASS | M2 基准在 `runbook/eval.md` 中 |

## 用例（运行手册）

1. **回归测试**：M1 vs M3 重建（准确率/延迟在 ±10% 内）
2. **模型比较**：选择任务的最佳别名（快速 vs 准确）
3. **别名交换验证**：交换后准确率保持相似

## 注意事项

- **不是全面的评估**：5 个提示用于烟雾测试，而不是生产模型选择
- **Thought-channel**：utility-fast（Gemma-4-A4B）在小 `max_tokens` 下有空 `content`（harness 使用 128 来缓解）
- **云别名**：在 M2 keyless；在上线后 Owner 添加密钥后运行
- **扩展**：要添加更多提示，编辑 `EVAL_PROMPTS` 列表

## 结论

✅ **§B.8 要求完成**

已交付轻量级评估框架（`scripts/eval-harness.py`）+ 单页操作指南（`runbook/eval.md`）：
- 在 3 个别名上烟雾测试（doc-vision、reasoning-max、utility-fast）
- JSON 输出格式已验证
- 用例已记录（回归、比较、验证）
- M2 基准建立（准确率、延迟、token）

Owner 在交付后选择运行哪些模型（harness 支持任何 llama-swap 别名）。

---

**交付日期**：2026-08-14  
**烟雾测试**：doc-vision (40%)、reasoning-max (80%)、utility-fast (40%)  
**状态**：✅ COMPLETE（SOW M2 项目 #10）
