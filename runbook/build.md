# runbook/build.md — upstream llama.cpp (Vulkan/RADV) build

The binding inference path (SOW §D.5) is **upstream llama.cpp on the Mesa RADV
Vulkan backend** — not LM Studio's pinned AVX2-only binary, not ROCm/HIP. This
document reproduces the build; the clone itself is gitignored (`tools/llama.cpp/`),
so reproducibility lives here.

## Pinned version

- Repo: `https://github.com/ggml-org/llama.cpp`
- Commit: `6a32c29a746a2e44de463de647f9f6661eb5086b` (built 2026-08-03)
- `llama-server --version` reports: `version: 1 (6a32c29)`, built with GCC 13.3
  for Linux x86_64; `ggml_vulkan: Found 1 Vulkan device` (Radeon 8060S / RADV
  GFX1151, Vulkan API 1.4.318).

## Build prerequisites (Ubuntu 24.04 noble)

The Vulkan loader alone is NOT enough; the GLSL→SPIR-V shader toolchain is
required at build time. Install all of:

```
sudo apt install -y cmake ninja-build build-essential \
  libvulkan-dev vulkan-tools \
  glslc glslang-tools spirv-headers spirv-tools
```

(`glslc`+`glslang-tools` give the shader compilers FindVulkan needs; `spirv-headers`
provides the `SPIRV-HeadersConfig.cmake` the Vulkan backend finds.)

CPU has full AVX-512, so `-DGGML_NATIVE=ON` is used (also faster than LM Studio's
AVX2-only build on CPU fallback paths).

## Configure + build

```
cd /srv/z13/tools
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp && git checkout 6a32c29a746a2e44de463de647f9f6661eb5086b
cmake -S . -B build -G Ninja \
  -DGGML_VULKAN=ON -DGGML_NATIVE=ON -DLLAMA_CURL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j"$(nproc)"
# -> build/bin/llama-server , build/bin/llama-bench
```

## Network note (build host)

Direct `git clone` from github.com is throttled from this network. Two working
routes, either is fine (pinning by commit makes the transport irrelevant):
- the FlClash proxy at `127.0.0.1:7890` when its listener is up, or
- the mirror prefix `https://ghfast.top/https://github.com/ggml-org/llama.cpp`.

After cloning, reset the remote to canonical: `git remote set-url origin https://github.com/ggml-org/llama.cpp`.

## Re-pinning / driver changes

After any Mesa/RADV or model change, rebuild not required (binaries link the
runtime loader), but **re-run all §I benchmarks** per §I.4 (floors are binding
across model/driver changes).
