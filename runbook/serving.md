# runbook/serving.md — canonical serving layer (§D.1 / §D.4 / §D.5 / §D.6 / §C.3)

One OpenAI- **and** Anthropic-compatible endpoint fronting the bare-metal
`llama-server` instances on the Vulkan/RADV path. Managed by **llama-swap v249**
(`f94c94a`, `/srv/z13/tools/llama-swap/llama-swap`); config at `llama-swap/config.yaml`
— this YAML is the §D.1 "stable aliases as reviewable configuration".

## Components

| | what | where |
|---|---|---|
| llama-swap | proxy, hot-swap, OpenAI+Anthropic API | bare-metal, systemd `llama-swap.service`, `127.0.0.1:8080` |
| llama-server (×N) | upstream instances on Vulkan/RADV | spawned by llama-swap on ports from `startPort: 10001` |
| Open WebUI | primary interface | compose service, `127.0.0.1:3000` → host-gateway:8080 |

## Aliases (§I.2 + §D.6 + §C.3)

`utility-fast` (Gemma4 26B-A4B QAT), `doc-vision` (Gemma4 E4B, +mmproj),
`reasoning-max` (gpt-oss-120B MXFP4, ttl 900s, swap-in), `utility-embed` (bge-m3 Q8_0),
and keyless cloud aliases `cloud-kimi-k3` / `cloud-fable-5` / `cloud-deepseek-v4-pro` /
`cloud-qwen` / `cloud-gemini` (→ `scripts/cloud-stub.py`, 401 until go-live, §C.3).

`groups.utilities` keeps utility-fast + doc-vision + utility-embed resident
(`swap:false`); reasoning-max swaps in/out. Resident budget ≈ 19 GB; +59 GB when
reasoning-max loaded ≈ 78 GB of 96.

## §D.5 flags (enforced via the `${z13flags}` macro in config.yaml)

`--jinja -ub 512 -ctk q8_0 -ctv q8_0 -fa auto -ngl 999 -t 8`, speculative off.

## ⚠ Gemma-4-A4B "thought channel" via the chat endpoint

`utility-fast` (Gemma 4 26B-A4B QAT) uses a multi-channel chat template: chat
responses begin in a `<|channel|>thought\n…` channel before the visible answer.
Symptom: with a small `max_tokens` the OpenAI `content` field comes back **empty**
(`finish_reason: length`) even though the model generated tokens. Raw
`/v1/completions` returns text normally (verified " Paris…"), and the model itself
is healthy (M1 decode 66 tok/s). For callers (incl. Hermes §E.11 default):

- request enough `max_tokens` to pass the thought channel and reach the answer, and
- read `logprobs`/the `thought` channel, or route `reasoning-max`/`doc-vision` for
  tasks needing immediate visible text (doc-vision returns clean content, verified "Four").

This is a model-template characteristic, not a serving-layer bug. (Hermes routing
template §E.12 accounts for it.)

## Operate

```
sudo systemctl enable --now llama-swap        # boot-survival, §J.1
curl http://127.0.0.1:8080/v1/models           # discovery
docker compose -f /srv/z13/compose/compose.yaml up -d   # open-webui
```
Edit aliases → edit `config.yaml` → `systemctl restart llama-swap` (or `-watch-config`).

## Verified 2026-08-13
- `/v1/models` lists all 10 IDs (4 SOW + cloud-disabled + 5 cloud aliases).
- OpenAI `/v1/chat/completions` + Anthropic `/v1/messages` both route `utility-fast`/`doc-vision`.
- `doc-vision` returns clean content ("Four"); `utility-fast` raw completion clean (chat = thought-channel caveat above).
- cloud alias `cloud-kimi-k3` → 401 `key_missing`.
