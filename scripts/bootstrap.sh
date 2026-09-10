#!/usr/bin/env bash
# scripts/bootstrap.sh — reproduce the base system from a clean Ubuntu 24.04
# so the state root can be rebuilt (host-neutral except the apt mirror, which
# is China-specific on this build host — swap for a local mirror elsewhere).
set -euo pipefail

echo ">>> [1/4] apt mirror (Tsinghua domestic — direct, no proxy needed)"
SRC=/etc/apt/sources.list.d/ubuntu.sources
if grep -q "hk.archive.ubuntu.com" "$SRC" 2>/dev/null; then
  sudo cp -n "$SRC" "$SRC.bak"
  sudo sed -i -e 's|hk.archive.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' \
              -e 's|security.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' "$SRC"
fi

echo ">>> [2/4] apt update (proxy disabled — FlClash 7890 is not reliable here)"
sudo apt-get -o Acquire::http::Proxy=false -o Acquire::https::Proxy=false update

echo ">>> [3/6] base tooling"
sudo apt-get -o Acquire::http::Proxy=false -o Acquire::https::Proxy=false install -y \
  cmake ninja-build libvulkan-dev vulkan-tools smartmontools sqlite3 age git \
  restic rclone rsync jq curl

echo ">>> [4/6] Node.js 22 (for Hermes agent runtime, per manifests/runtimes.yaml)"
if ! command -v node >/dev/null 2>&1 || [ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)" != "22" ]; then
  sudo install -m0755 -d /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
  sudo chmod a+r /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  sudo apt-get -o Acquire::http::Proxy=false -o Acquire::https::Proxy=false update
  sudo apt-get install -y nodejs || echo "WARN: NodeSource nodejs install failed — install Node 22 manually (nvm)"
fi

echo ">>> [5/6] uv (Astral Python package manager, for Hermes venv + tools)"
if ! command -v uv >/dev/null 2>&1; then
  curl -fsSL https://astral.sh/uv/install.sh -o /tmp/uv-install.sh
  sh /tmp/uv-install.sh >/dev/null 2>&1 || echo "WARN: uv install failed — install manually"
  rm -f /tmp/uv-install.sh
fi

echo ">>> [6/6] Docker CE repo (host-neutral)"
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  sudo install -m0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "$UBUNTU_CODENAME" >/dev/null
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  sudo apt-get -o Acquire::http::Proxy=false -o Acquire::https::Proxy=false update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo ">>> bootstrap complete"
echo "NOTE: amdgpu-top is not in apt; install via 'cargo install amdgpu_top' if desired (§J.2)."
