---
layout: post
title: "Running ComfyUI with ROCm on a Radeon 9070 XT, Part 2: Training Crashes and a ROCm Downgrade"
date: 2026-05-31 10:00:00 +0000
categories: post
tags: [rocm, amdgpu, comfyui, docker, opensuse, ai]
author: Tobias Geiser
image: "/assets/posts/2026-05-31/rocm-troubleshooting.png"
header: "/assets/posts/2026-05-31/rocm-troubleshooting-header.png"
excerpt_separator: <!--more-->
---

In [Part 1]({% post_url 2026-05-17-running-comfyui-with-rocm-on-a-radeon-9070-xt-part-1 %}) I got ComfyUI generating images on a Radeon RX 9070 XT inside Docker. Inference worked. Then I pointed LoRA training at the same card, and it faulted at step 61 — every time, deterministically, hard enough to take the whole desktop down. This post is the triage: every knob I turned, which ones were dead ends, and why the fix turned out to be *going backwards* to ROCm 7.1.1.
<!--more-->

**TL;DR:** On RDNA4 (`gfx1201`), a newer ROCm stack is not automatically a better one. ROCm 7.2.3 with PyTorch 2.10 faulted reproducibly under training load; the same workload completed cleanly on ROCm 7.1.1 with `HSA_ENABLE_SDMA=0`, no GFX override, and a conservative allocator config. Keep a known-good older image around.

This is Part 2 of a two-part series. Part 1 covers the base container setup.

## Overview

The setup from Part 1: ComfyUI in a container on the `rocm/pytorch:rocm7.2.3` base image, `torch 2.10.0+rocm7.2.3`, RX 9070 XT detected correctly. For training I built a separate container on the same base with the usual stack — `transformers`, `trl`, `peft`, `accelerate` — and a chunked LoRA training script.

Symptom: chunk 1 of the training run completed, and chunk 2 died mid-run with the same fault from Part 1:

```text
Memory access fault by GPU node-1 (Agent handle: 0x...)
Reason: Page not present
```

Three details told me this was not a hyperparameter problem:

- The failure was deterministic around **step 61**, run after run.
- It reproduced after a fresh container, a fresh output directory, and a host reboot.
- The fault could hard-crash the desktop session — this card also drives my display.

Deterministic + survives reboot + at the same step = a code path in the GPU stack, not my training config.

## Walkthrough

The debugging method matters as much as the result: change exactly one knob per run, and record `torch.__version__`, `torch.version.hip`, and the environment for every attempt. Otherwise you cannot attribute the outcome.

### Remove the GFX version override

With ROCm 7.2.x, `gfx1201` is detected natively:

```bash
docker exec <training-container> python -c \
  "import torch; print(torch.version.hip); print(torch.cuda.get_device_name(0))"
```

```text
7.2.53211
AMD Radeon RX 9070 XT
```

`HSA_OVERRIDE_GFX_VERSION` exists to make an unsupported GPU masquerade as a supported one. When the runtime already recognizes the card, the override can force compatibility behavior that is no longer needed — so I removed it from the training container. The crash stayed.

### Disable SDMA transfers

`HSA_ENABLE_SDMA=0` forces synchronous memory transfers instead of the GPU's DMA engines. SDMA paths are a recurring suspect in ROCm memory faults:

```yaml
environment:
  HSA_ENABLE_SDMA: "0"
```

Still faulting at the same step.

### Try the kernel-side knobs

Two more attempts, both dead ends worth knowing:

- **`amdgpu.cwsr_enable=0`** (disable checkpoint-restore of GPU waves) as a kernel command-line parameter — no change.
- **`rocm-smi --gpureset`** to reset the GPU between runs — not supported on this system:

```text
GPU reset is not supported on this device
```

I also deliberately did *not* try `HSA_OVERRIDE_GFX_VERSION=11.0.3`. It is a common suggestion in forums: pretend your RDNA4 card is RDNA3. It can hide unsupported paths, but it is a compatibility hack, not a fix for a natively detected `gfx1201`, and it muddies every later comparison.

**Warning:** while debugging this class of fault, run tests from a TTY or over SSH, not from a graphical session on the same GPU. A memory fault on your display GPU takes the desktop with it, and you lose the logs you were about to read.

### Roll back to ROCm 7.1.1

At this point the honest conclusion was: **ROCm 7.2.3 is not stable for this LoRA workload on this card.** The next question was which older stack to trust. The rule I used: pick the newest version that is *still* newer than RDNA4 support landing, i.e. roll back one minor step at a time — 7.1.x first, then 7.0.x, then 6.4.x.

The 7.1.1 base image uses the same PyTorch release, so the comparison stays clean:

```yaml
services:
  comfyui:
    build:
      context: .
      args:
        ROCM_PYTORCH_IMAGE: rocm/pytorch:rocm7.1.1_ubuntu24.04_py3.12_pytorch_release_2.10.0
```

Verify what the container sees now:

```bash
docker exec <container> python -c \
  "import torch; print(torch.__version__); print(torch.version.hip); print(torch.cuda.get_device_name(0))"
```

```text
2.10.0+rocm7.1.1.gitd9556b05
7.1.52802
AMD Radeon RX 9070 XT
```

`gfx1201` detected natively, bf16 supported, no GFX override needed.

The controlled test — same data, same seed, same 70 steps that always died before — completed:

```text
70/70 steps completed
```

And longer runs stayed stable afterwards. Same PyTorch release, one ROCm minor version down, fault gone.

### Keep both stacks side by side

I did not tear the 7.2.3 container down. Both variants now live in the same project, on different ports, selected by compose file:

```bash
# ROCm 7.2.3, inference — port 8188
docker compose -f docker-compose.yml up -d comfyui

# ROCm 7.1.1, stability variant — port 8189
docker compose -f docker-compose.rocm71.yml up -d comfyui
```

The stable variant's environment is the final, hard-won configuration:

```yaml
container_name: comfyui-rocm71
environment:
  HIP_VISIBLE_DEVICES: "0"
  ROCR_VISIBLE_DEVICES: "0"
  GPU_DEVICE_ORDINAL: "0"
  HSA_ENABLE_SDMA: "0"
  FLASH_ATTENTION_TRITON_AMD_ENABLE: "FALSE"
  PYTORCH_HIP_ALLOC_CONF: "garbage_collection_threshold:0.8,max_split_size_mb:128"
```

Note the allocator setting: instead of `expandable_segments:True` (the crash trigger from Part 1), this is a conservative configuration — collect garbage earlier and cap split size — which keeps VRAM behavior predictable under repeated runs.

**Pro tip:** do not run ComfyUI and LoRA training at the same time on a 16 GB RDNA4 card. Stop the inference container before training:

```bash
docker stop comfyui-rocm71
```

## Keep LoRA training stable on RDNA4

The checklist I would hand to anyone starting from scratch on an RX 9070 XT:

- **Match the stack.** Use a PyTorch build and ROCm userspace from the same image. Never mix a wheel built for one ROCm version with a runtime of another.
- **Newest is not best.** Use the newest ROCm your whole stack explicitly supports, and keep a known-good older image as fallback.
- **Control variables.** Batch size 1, fixed gradient accumulation, bf16 first, dataloader workers 0, gradient checkpointing on, same seed and step count between comparisons.
- **Record everything.** Container tag, `torch.__version__`, `torch.version.hip`, environment variables, and the exact failing step for every run.
- **Expect RDNA4 quirks.** `gfx1201` support is young; deterministic GPU faults are usually stack bugs, not your hyperparameters.

## Troubleshooting

### GPU fault takes down the desktop

Symptom: whole session freezes when the fault hits. Cause: the training GPU is also the display GPU. Mitigation: debug over SSH or from a TTY, keep the card idle except for the test, and consider a second GPU (even an iGPU) for display.

### `rocm-smi --gpureset` does nothing

Not supported on this device. Do not build a recovery workflow around it; a container restart plus, in the worst case, a host reboot is the actual recovery path.

### Out-of-memory advice that makes things worse

PyTorch's OOM message recommends `expandable_segments:True`. On this stack that setting caused memory faults (see Part 1). If you hit OOM, reduce resolution, sequence length, or model size before touching the allocator.

## Summary

- Deterministic mid-run GPU faults on RDNA4 are a stack problem, not a training-parameter problem.
- `HSA_OVERRIDE_GFX_VERSION` is unnecessary (and suspect) once `gfx1201` is detected natively; `HSA_ENABLE_SDMA=0` is cheap to try.
- Rolling back one ROCm minor version (7.2.3 → 7.1.1, same PyTorch) fixed what no environment knob could.
- Keep the stable stack's recipe exact: no GFX override, SDMA off, Triton flash-attention off, conservative `PYTORCH_HIP_ALLOC_CONF`.
- Never run inference and training on the same 16 GB card at once.

## References

- [Part 1: A Working Docker Setup]({% post_url 2026-05-17-running-comfyui-with-rocm-on-a-radeon-9070-xt-part-1 %})
- [ROCm PyTorch Docker images](https://hub.docker.com/r/rocm/pytorch)
- [PyTorch: memory management environment variables](https://docs.pytorch.org/docs/stable/notes/cuda.html)
