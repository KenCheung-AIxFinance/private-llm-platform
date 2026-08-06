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

echo ">>> [3/4] base tooling"
sudo apt-get -o Acquire::http::Proxy=false -o Acquire::https::Proxy=false install -y \
  cmake ninja-build libvulkan-dev vulkan-tools smartmontools sqlite3 age git

echo ">>> [4/4] Docker CE repo (host-neutral)"
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
