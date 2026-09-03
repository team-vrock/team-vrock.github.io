---
layout: post
title: "Running ComfyUI with ROCm on a Radeon 9070 XT, Part 1: A Working Docker Setup"
date: 2026-05-17 10:00:00 +0000
categories: post
tags: [rocm, amdgpu, comfyui, docker, opensuse, ai]
author: Tobias Geiser
image: "/assets/posts/2026-05-17/amd-rocm-tumbleweed.png"
header: "/assets/posts/2026-05-17/rocm-comfyui-header.png"
excerpt_separator: <!--more-->
---

Most ROCm guides on the internet were written for RDNA3 cards. The Radeon RX 9070 XT is RDNA4 (`gfx1201`), and when I set it up, half of the usual advice was outdated and the other half caused GPU faults. This is Part 1 of the setup that actually worked: a fully containerized ComfyUI on an openSUSE host with no ROCm installed on the host at all.
<!--more-->

**TL;DR:** I run ComfyUI from the official `rocm/pytorch` Ubuntu image with the GPU passed straight into the container. No host-side ROCm install, `HSA_OVERRIDE_GFX_VERSION=12.0.1` for the 7.2.x stack, and — the hard-won part — no `expandable_segments` allocator setting, which crashed the GPU with memory access faults. Part 2 covers training stability and why I ended up keeping a ROCm 7.1.1 container around.

This is Part 1 of a two-part series. [Part 2]({% post_url 2026-05-31-running-comfyui-with-rocm-on-a-radeon-9070-xt-part-2 %}) covers LoRA training stability, crash triage, and the ROCm 7.1.1 fallback.

## Overview

This post shows how to run [ComfyUI](https://github.com/Comfy-Org/ComfyUI) on an AMD Radeon RX 9070 XT using ROCm inside Docker, on a host that has no ROCm userspace installed. It is aimed at people who:

- Have a RDNA4 card (RX 9070 / 9070 XT, `gfx1201`) and want to run diffusion workloads locally.
- Prefer containers over system-wide ROCm installs.
- Run a recent Linux with the `amdgpu` kernel driver (openSUSE Tumbleweed in my case, but the approach is distribution-agnostic).

The result is a `docker compose` setup where the container talks to the GPU through `/dev/kfd` and a render node, with PyTorch reporting a real ROCm/HIP backend.

## Architecture

The split of responsibilities is simple:

- **Host kernel only.** The `amdgpu` kernel driver exposes `/dev/kfd` (the compute device) and `/dev/dri/renderD*` (render nodes). Nothing else is needed on the host. I deliberately did not install ROCm userspace there — `rocminfo` does not even exist on my host.
- **Container carries ROCm userspace.** The image is built on top of the official `rocm/pytorch` Ubuntu images, which bundle a matched ROCm + PyTorch pair.
- **Models and outputs live in host volumes.** Everything ComfyUI reads and writes is mounted from the host, so the container image stays disposable.

One subtlety: my machine has two GPUs — an Intel iGPU for display and the Radeon for compute. That makes pinning the *exact* render node in the compose file important, which I cover below.

## Prerequisites

- A Radeon RX 9070 XT (RDNA4, `gfx1201`). Other RDNA4 cards should behave similarly; RDNA3 cards do not need some of the environment knobs below.
- Linux with a recent kernel where `lspci` shows the card and `/dev/kfd` exists. My host: openSUSE Tumbleweed, kernel 7.2.0, Docker 29.4.
- Your user must be in the `render` and `video` groups (or you must know their group IDs for `group_add`).
- Roughly 20 GB of disk for the base image, plus room for models.

### Verify the GPU and kernel driver

Check that the kernel sees the card and that the KFD compute device exists:

```bash
lspci -nn | grep -i vga
ls -l /dev/kfd
```

On my machine:

```text
00:02.0 VGA compatible controller [0300]: Intel Corporation Arrow Lake-S [Intel Graphics] [8086:7d67] (rev 06)
04:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070/9070 XT/9070 GRE] [1002:7550] (rev c0)
crw-rw----+ 1 root render 238, 0 ... /dev/kfd
```

Two things to note:

- The Radeon sits at PCI address `04:00.0`. Note your own address — you need it for stable device paths.
- `/dev/kfd` is owned by the `render` group.

There is no need for `rocminfo` on the host. If it is not installed, that is fine — we verify GPU visibility from inside the container later.

### Find the stable render node path

Render node numbering (`renderD128`, `renderD129`, …) can shift between boots depending on probe order. The stable way to reference a specific GPU is the PCI by-path symlink:

```bash
ls -l /dev/dri/by-path/
```

```text
pci-0000:00:02.0-card -> ../card1
pci-0000:00:02.0-render -> ../renderD128
pci-0000:04:00.0-card -> ../card2
pci-0000:04:00.0-render -> ../renderD129
```

The Intel iGPU owns `00:02.0`, the Radeon owns `04:00.0`. I map the *Radeon's* by-path entries into the container, so the mapping survives reboots and does not depend on which card probes first.

### Note your render/video group IDs

The container needs permission to open `/dev/kfd` and the render node. Pass the host's group IDs via `group_add`:

```bash
getent group render video
```

```text
render:x:486:<user>
video:x:483:<user>
```

Use *your* numbers — these IDs differ between distributions.

## Walkthrough

The project layout is minimal:

```text
~/src/comfyui/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
└── data/            # models, workflows, input, output
```

### Write the Dockerfile

The image starts from an official ROCm PyTorch image, clones ComfyUI at a pinned commit, and installs ComfyUI's dependencies *without* letting them replace the ROCm build of PyTorch:

```dockerfile
ARG ROCM_PYTORCH_IMAGE=rocm/pytorch:rocm7.2.3_ubuntu24.04_py3.12_pytorch_release_2.10.0
FROM ${ROCM_PYTORCH_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    COMFYUI_DIR=/opt/ComfyUI

ARG COMFYUI_REF=<comfyui-commit>

RUN apt-get update && apt-get install -y --no-install-recommends \
    git libgl1 libglib2.0-0 libgomp1 ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --upgrade pip setuptools wheel

WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR" \
    && cd "$COMFYUI_DIR" \
    && git checkout "$COMFYUI_REF"
```

`<comfyui-commit>` is any commit you have tested — pin it so rebuilds are reproducible.

The important trick is filtering ComfyUI's `requirements.txt`. ComfyUI wants to install its own `torch` (the CUDA one), which would silently replace the ROCm build and leave you with a container that sees no GPU:

```dockerfile
RUN cd "$COMFYUI_DIR" \
    && python - <<'PY'
from pathlib import Path

blocked = {"torch", "torchvision", "torchaudio"}
source = Path("requirements.txt")
target = Path("/tmp/comfyui-requirements-without-torch.txt")

lines = []
for line in source.read_text().splitlines():
    package = line.strip().split(";", 1)[0].split("[", 1)[0]
    package = package.replace("==", ">=").replace("~=", ">=").split(">=", 1)[0].split("<", 1)[0].strip().lower()
    if package not in blocked:
        lines.append(line)

target.write_text("\n".join(lines) + "\n")
PY

RUN python -m pip install --upgrade -r /tmp/comfyui-requirements-without-torch.txt
```

Finish with a small entrypoint that symlinks ComfyUI's data directories onto the mounted volume, then expose the port:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$COMFYUI_DIR"
mkdir -p /data/models /data/output /data/input /data/user /data/custom_nodes
for d in models output input user custom_nodes; do
  rm -rf "$d"
  ln -s "/data/$d" "$d"
done
exec "$@"
```

### Map the GPU into the container

The compose file is where the RDNA4-specific decisions live:

```yaml
services:
  comfyui:
    build: .
    image: comfyui-rocm:local
    container_name: comfyui-rocm
    restart: "no"
    ports:
      - "8188:8188"
    devices:
      - source: /dev/kfd
        target: /dev/kfd
        permissions: rwm
      - source: /dev/dri/by-path/pci-0000:<pci-address>-card
        target: /dev/dri/card2
        permissions: rwm
      - source: /dev/dri/by-path/pci-0000:<pci-address>-render
        target: /dev/dri/renderD129
        permissions: rwm
    group_add:
      - "<video-gid>"
      - "<render-gid>"
    ipc: host
    security_opt:
      - seccomp=unconfined
    shm_size: 8gb
    command: ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]
    environment:
      HSA_OVERRIDE_GFX_VERSION: "12.0.1"
      HIP_VISIBLE_DEVICES: "0"
      ROCR_VISIBLE_DEVICES: "0"
      GPU_DEVICE_ORDINAL: "0"
    volumes:
      - ./data:/data
```

Replace `<pci-address>` with your card's address from `lspci` (for example `04:00.0`), and the two group IDs with yours. The pieces that matter:

- **`/dev/kfd` plus card and render node** — the full compute path. Using `/dev/dri/by-path/...` as the source keeps the mapping stable when both an iGPU and a dGPU are present.
- **`ipc: host` and `shm_size: 8gb`** — PyTorch dataloaders need shared memory; too-small `/dev/shm` shows up as bizarre crashes later.
- **`seccomp=unconfined`** — ROCm uses syscalls the default Docker profile blocks.
- **`HSA_OVERRIDE_GFX_VERSION: "12.0.1"`** — with ROCm 7.2.x images I kept this set for the inference container. In Part 2 I revisit whether it is still needed, so treat it as a knob, not a law.

### Verify the GPU is visible

Build and start, then ask PyTorch what it sees:

```bash
docker compose up -d
docker exec comfyui-rocm python -c \
  "import torch; print(torch.__version__); print(torch.version.hip); print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0))"
```

```text
2.10.0+rocm7.2.3.git1a270074
6.4.xxxxx
True
AMD Radeon RX 9070 XT
```

And from ComfyUI's own startup log:

```text
Total VRAM 16304 MB, total RAM 95811 MB
pytorch version: 2.10.0+rocm7.2.3
```

16 GB of VRAM visible, HIP backend active — the container is really computing on the card. The web UI should now respond on `http://127.0.0.1:8188/`.

## Troubleshooting

### The GPU faults after a few generations

Everything above worked on the first run. Then, after a handful of image generations, the container died with:

```text
Memory access fault by GPU node-1 (Agent handle: 0x...)
Reason: Page not present
```

followed by a Python abort. The first generation after a container restart always succeeded; a later one would fault. That pattern — works once, dies later — is the signature of something accumulating, not a compatibility problem.

I suspected the allocator and tested one change at a time. The compose file at that point contained:

```yaml
PYTORCH_HIP_ALLOC_CONF: "expandable_segments:True"
```

Removing exactly that line fixed it. Repeated runs of the same workflow, no fault. The isolate was unambiguous: `expandable_segments:True` on this ROCm/PyTorch/gfx1201 combination is a crash path, not an optimization.

**Gotcha:** PyTorch's own out-of-memory message tells you to set `expandable_segments:True` to reduce fragmentation:

```text
torch.OutOfMemoryError: HIP out of memory. Tried to allocate 20.02 GiB. ...
If reserved but unallocated memory is large try setting
PYTORCH_ALLOC_CONF=expandable_segments:True to avoid fragmentation.
```

On this stack, do not follow that advice blindly — it is exactly the setting that caused the memory faults here. Part 2 shows the allocator configuration I use instead.

### rocminfo not found on the host

Not a problem. ROCm userspace lives in the container. Verify from inside:

```bash
docker exec comfyui-rocm rocminfo | grep -E "Name:|Marketing Name" | head
```

## Summary

- Run ROCm entirely in the container; the host only needs the `amdgpu` driver, `/dev/kfd`, and a render node.
- Pin devices by PCI by-path when the machine has more than one GPU.
- Filter `torch` out of ComfyUI's requirements so the ROCm PyTorch survives.
- Pass host `render`/`video` group IDs via `group_add`; set `ipc: host`, `shm_size`, and `seccomp=unconfined`.
- If the GPU faults with "Page not present" after repeated runs, suspect `PYTORCH_HIP_ALLOC_CONF=expandable_segments:True` first.

## References

- [ComfyUI](https://github.com/Comfy-Org/ComfyUI)
- [ROCm PyTorch Docker images](https://hub.docker.com/r/rocm/pytorch)
- [ROCm documentation: compatibility](https://rocm.docs.amd.com/)
