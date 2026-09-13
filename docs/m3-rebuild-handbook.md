# M3 新机器手动重建操作手册

> 在第二台机器上**手动**把 Z13 平台复原出来的步骤。与自动安装器 `scripts/rebuild.sh` 等价，但逐步可控、可理解。
> 前提：git 仓库已 publish；新机器已装 Ubuntu 24.04；你有 sudo。
>
> **复原主路径**：clone 仓库 → 补 Hermes 代码（submodule）→ 新机底座+GPU → 依赖 → runtime → 权重 → secrets → 主机位 → 起服务 → 验证。

**预估时间**：纯结构 ~30-60 min；含 llama.cpp Vulkan 编译 +5-10 min；权重下载视模式（resident ~20GB LAN ~5min / all ~101GB）。

---

## 阶段 0 — 在新机器上拿到代码（2 min）

```bash
sudo apt-get update && sudo apt-get install -y git
git clone <你的-publish-repo-url> /srv/z13
cd /srv/z13
git submodule update --init          # 关键：拉全 hermes-agent 代码（方案A，无需 fork）
# 验证 hermes 代码在：ls hermes/hermes-agent/hermes  （应存在）
```

> ⚠️ 若 `hermes/hermes-agent/` 是空的：说明 submodule 没初始化，再跑 `git submodule update --init`。

---

## 阶段 1 — 新机初始化 + GPU driver（5-10 min）

这一层管"机器底座"：用户/组、（Strix Halo 才需要的）OEM 内核、Vulkan 驱动、Docker。

```bash
sudo bash /srv/z13/scripts/init-host.sh
```

它会：检测 GPU → 装底座 → 写 `hosts/<hostname>.env`（记录 GPU + INFERENCE）。

**对照你的机器**：
- **是 Strix Halo (gfx1151)**：会自动装 `linux-oem-24.04c`（装完**需重启**进新内核）。
- **其他 AMD**：自动装 Mesa RADV 驱动，走 Vulkan。
- **NVIDIA**：本轮回退 CPU（`--cpu-inference`）。
- **无 GPU**：直接 CPU 推理。

**⚠️ Strix Halo 专属 BIOS 前置（脚本改不了固件）**：能跑 96GB 模型靠 BIOS 的 VRAM/GTT 切分。检测：
```bash
cat /sys/class/drm/card*/device/mem_info_vram_total   # 期望 ~103079215104 (96GB)
# 若远小于 96GB → 进 BIOS 设 VRAM reservation + 提升 GTT/TTM（否则只能跑小模型或 CPU）
```

---

## 阶段 2 — 平台依赖（3-5 min）

```bash
sudo bash /srv/z13/scripts/bootstrap.sh
```
装编译工具链、restic/rclone/rsync/jq、Node 22、uv、Docker CE。  
（glslc/着色器链已在 init-host 的 GPU 段装好。）

验证：`node -v`（应 v22.x）、`uv --version`、`docker ps`（先 `sudo usermod -aG docker $USER && newgrp docker`）。

---

## 阶段 3 — Runtime：llama.cpp + llama-swap + Hermes venv（10-20 min）

### 3a. llama.cpp（Vulkan 编译）
```bash
cd /srv/z13/tools
env -u http_proxy -u https_proxy -u all_proxy git clone --depth 1 https://github.com/ggml-org/llama.cpp
cd llama.cpp && git fetch --depth 1 origin 6a32c29a746a2e44de463de647f9f6661eb5086b && git checkout -q 6a32c29
cmake -S . -B build -G Ninja -DGGML_VULKAN=ON -DGGML_NATIVE=ON -DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j"$(nproc)"
./build/bin/llama-server --version     # 期望: version: 1 (6a32c29)
```
> 想省编译时间：可直接从源机 rsync 已编好的二进制 `/srv/z13/tools/llama.cpp/build/bin/llama-server`（同架构 x86_64 + Vulkan 即可直接用）。

### 3b. llama-swap（已在 git 里，直接用）
```bash
/srv/z13/tools/llama-swap/llama-swap --version   # 期望: v249
```

### 3c. Hermes venv（**关键，缺了 hermes 跑不起来**）
```bash
cd /srv/z13/hermes/hermes-agent
uv venv venv --python 3.11
uv pip install -e .
uv tool install browser-use
# 验证：/srv/z13/hermes/hermes-agent/venv/bin/python -c "import sys;print(sys.version)"
```
> Hermes 入口 shim `~/.local/bin/hermes` 指向这个 venv 的 python；venv 不进 git，必须在新机重建。

---

## 阶段 4 — 模型权重（视模式 5-30 min）

二选一：

**A. 从源机 rsync（最快，LAN，保 2h 窗口，推荐）**
```bash
# 在【新机器】上执行，从源机拉 resident 三个模型（~20GB）
for m in gemma-4-E4B-it-GGUF gemma-4-26B-A4B-it-QAT-GGUF bge-m3-GGUF; do
  rsync -a norbert@<源机-IP>:~/.lmstudio/models/lmstudio-community/$m \
        ~/.lmstudio/models/lmstudio-community/
done
# 要 reasoning-max 就再加 gpt-oss-120b-GGUF（59GB）
```

**B. 从 HuggingFace 下载（按 manifest）**
```bash
bash /srv/z13/scripts/fetch-models.sh --only resident   # ~20GB
# 或全部: bash /srv/z13/scripts/fetch-models.sh --all   # ~101GB
```
（sha256 自动校验；`--only resident` 拉 doc-vision/utility-fast/utility-embed。）

---

## 阶段 5 — Secrets（Owner 输入，1 min）

```bash
install -m 600 /dev/null /srv/z13/hermes/.env
# 编辑填入 provider / API keys（§0.4：Owner 亲手输，绝不从 git 拿）
```
> 没有也能跑：本地别名（doc-vision 等）照常；云别名 + Hermes provider 受限。

---

## 阶段 6 — 主机位（1 min）

```bash
# hosts/<hostname>.env 已由 init-host 写好（含 GPU + INFERENCE）
# sshd 重钉到本机 Tailscale IP（§B.3/§4.1）：
IP=$(tailscale ip -4 | head -1)
[ -n "$IP" ] && sudo sed -i -E "s/^ListenAddress .*/ListenAddress $IP/" /etc/ssh/sshd_config \
  && sudo systemctl restart ssh.socket
```

---

## 阶段 7 — 装/启服务（2 min）

```bash
sudo cp /srv/z13/systemd/{llama-swap,z13-stack,hermes}.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now llama-swap z13-stack
# 等 resident 模型加载：
for i in $(seq 1 30); do curl -sf -m2 http://127.0.0.1:8080/v1/models >/dev/null && break || sleep 10; done
```

---

## 阶段 8 — 验证（2 min）

```bash
# 1) 服务/别名
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id' | sort    # 应列出本地+云别名
# 2) 本地推理
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"doc-vision","messages":[{"role":"user","content":"2+2=?"}],"max_tokens":16}' \
  | jq -r '.choices[0].message.content'
# 3) Open WebUI: 浏览器 http://127.0.0.1:3000
# 4) Hermes（agent 记忆随 git 快照来）:
export HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13
sg docker -c "hermes --accept-hooks -z 'Read /workspace/vault/test-fact.md and tell me its content.'"
#    → 应引用 vault/test-fact.md 的内容（证明记忆迁移成功）
```

---

## 排错速查

| 现象 | 原因 | 处理 |
|---|---|---|
| `hermes/hermes-agent/` 空 | submodule 没 init | `git submodule update --init` |
| hermes 报 venv/python 找不到 | venv 未重建（阶段 3c）| 在 hermes-agent 里 `uv venv venv --python 3.11 && uv pip install -e .` |
| ssh 连不上新机器 | sshd 还钉着源机 IP | 阶段 6 重钉 `ListenAddress` 或删掉该行 |
| GPU 模型 OOM / 跑不动 | Strix Halo BIOS 未切分 VRAM/GTT | 进 BIOS 设（阶段 1 提示）；或 `--cpu-inference` |
| llama-server 起不来 | 缺 Vulkan 驱动/着色器链 | 重跑 init-host.sh（GPU 段）|
| `curl :8080` 超时 | resident 模型还在加载 | `sudo journalctl -u llama-swap -f` 看加载日志，多等 |
| `docker ps` 报 daemon 不可达 | Docker 没起 / 不在组 | `systemctl --user start docker-desktop` 或 `sudo systemctl start docker` + `usermod -aG docker $USER` |

---

**与自动安装器的关系**：`scripts/rebuild.sh` 就是把阶段 1-8 串成一个幂等脚本；`scripts/migrate.sh` 是连续性复原（含 codeword 记忆验证、2h 计时）。想手动就用本手册，想一键就跑那两个脚本。
