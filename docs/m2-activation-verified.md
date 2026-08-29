# M2 系统激活步骤（实测验证版）

> 本文档记录**实际验证可用**的激活步骤，取代 `m2-build-manual.md` 中的虚构内容。
> 每一条命令都在 2026-08-28 重启后实测通过。
>
> **适用场景**：系统已搭建完成（组件都在），机器重启后重新激活服务。

---

## 真实的组件位置（重要 —— 与旧文档不同）

| 组件 | 真实路径 | 旧文档错误写法 |
|---|---|---|
| llama-swap 二进制 | `/srv/z13/tools/llama-swap/llama-swap` | ~~tjbck/llama-swap release~~（实际是 mostlygeek/llama-swap v249）|
| llama-server（推理引擎）| `/srv/z13/tools/llama.cpp/build/bin/llama-server`（从源码 Vulkan 编译）| ~~llama-swap 内置~~ |
| 模型权重 | `~/.lmstudio/models/lmstudio-community/`（**不是** `/srv/z13/weights/`）| ~~/srv/z13/weights/~~ |
| Hermes 入口 | `~/.local/bin/hermes` → `/srv/z13/hermes/hermes-agent/venv/bin/python`（uv venv 安装，**不是** GitHub release tar）| ~~hermes-v0.20.0-linux-x64.tar.gz~~ |
| llama-swap 配置 | `/srv/z13/llama-swap/config.yaml`（用 `${models}` 等宏，指向 lmstudio 目录）| ✓ |
| systemd unit | `/etc/systemd/system/llama-swap.service` | ✓ |
| Docker | Docker **Desktop**（context: `desktop-linux`），非原生 dockerd | ✓ |

模型路径宏（config.yaml 顶部）：
```yaml
macros:
  "llama":    "/srv/z13/tools/llama.cpp/build/bin/llama-server --port ${PORT}"
  "z13flags": "--jinja -ub 512 -ctk q8_0 -ctv q8_0 -fa auto -ngl 999 -t 8"
  "models":   "${env.HOME}/.lmstudio/models/lmstudio-community"
```

---

## 重启后一键激活（实测顺序）

### 步骤 1 — 启动 llama-swap（并设开机自启）

```bash
sudo systemctl enable --now llama-swap
# 等待 resident 模型加载（doc-vision + utility-fast + utility-embed）
for i in $(seq 1 20); do
  curl -sf -m2 http://127.0.0.1:8080/v1/models >/dev/null && { echo "ready"; break; }
  sleep 5
done
```

> **关键**：之前服务是 `disabled`（不开机自启），重启后不会自动起来。
> `enable --now` 一次性解决：立即启动 + 设为开机自启。

### 步骤 2 — 启动 Docker Desktop（并设开机自启）

```bash
systemctl --user start docker-desktop
systemctl --user enable docker-desktop     # 开机自启
# 等待 Docker 守护进程就绪
for i in $(seq 1 24); do
  docker ps >/dev/null 2>&1 && { echo "docker ready"; break; }
  sleep 5
done
```

> Docker Desktop 首次启动较慢（~30-60s）。context 必须是 `desktop-linux`（`docker context show` 确认）。

### 步骤 3 — 启动 Open WebUI

```bash
cd /srv/z13/compose
docker compose up -d
# 首次启动会下载 embedding 模型（all-MiniLM-L6-v2），需要 1-2 分钟
sleep 10
docker ps --filter name=open-webui --format "{{.Names}}: {{.Status}}"
```

### 步骤 4 — 验证全系统

```bash
echo "llama-swap: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/models)"   # 期望 200
echo "OpenWebUI:  $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/)"              # 期望 200
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id' | sort                              # 期望 10 个别名
```

---

## Hermes 激活（实测）

Hermes 已在 PATH（`~/.local/bin/hermes`）。**必须**设两个环境变量，且**必须**用 `sg docker` 让它继承 docker 组：

```bash
export HERMES_HOME=/srv/z13/hermes
export TERMINAL_CWD=/srv/z13            # Docker 沙箱挂载 /srv/z13 → /workspace 的关键

# 一次性任务
sg docker -c "HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13 hermes --accept-hooks -z '你的任务'"
```

实测通过的命令：
```bash
sg docker -c "HERMES_HOME=/srv/z13/hermes TERMINAL_CWD=/srv/z13 hermes --accept-hooks \
  -z 'Read /workspace/vault/test-fact.md and reply with only its content.'"
# 返回：# Test Fact for Hermes / The Z13 state root is at `/srv/z13`. ...
```

配置确认（实测值）：
```
model.provider = custom
model.base_url = http://127.0.0.1:8080/v1
model.default  = doc-vision
terminal.backend = docker
```

---

## 常见故障（重启后实测遇到的）

### 故障 1：Hermes 报 "API call failed after 3 retries: Connection error"

**根因**：llama-swap 没跑（重启后服务是 dead）。Hermes 的 provider 指向 `127.0.0.1:8080`，连不上就报这个错。

**验证**：
```bash
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/models
# 返回 000 = llama-swap 挂了；返回 200 = 正常
```

**修复**：`sudo systemctl start llama-swap`（见步骤 1）。

### 故障 2：`docker ps` 报 "Cannot connect to the Docker daemon"

**根因**：Docker Desktop 重启后没自动起来。

**修复**：`systemctl --user start docker-desktop`（见步骤 2）。

### 故障 3：服务重启后全部消失

**根因**：`llama-swap.service` 是 `disabled`，Docker Desktop 也没设自启。

**修复**（一劳永逸）：
```bash
sudo systemctl enable llama-swap
systemctl --user enable docker-desktop
```

---

## 验证清单（重启后照做）

- [ ] `systemctl is-active llama-swap` → `active`
- [ ] `docker ps` → 能连上，看到 open-webui (healthy)
- [ ] `curl http://127.0.0.1:8080/v1/models` → HTTP 200，10 个别名
- [ ] `curl http://127.0.0.1:3000/` → HTTP 200
- [ ] doc-vision 推理 "2+2" → 返回 "4"
- [ ] cloud-kimi-k3 → HTTP 401 key_missing
- [ ] Hermes 读 vault → 返回文件内容

全部通过 = 系统完全激活 ✓

---

**实测日期**：2026-08-28（机器重启后）
**验证者**：实测每条命令均通过
