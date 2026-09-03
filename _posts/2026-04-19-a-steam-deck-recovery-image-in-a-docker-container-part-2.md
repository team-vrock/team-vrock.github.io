---
layout: post
title: "From SteamOS Hack to a Tumbleweed Steam Container, Part 2"
date: 2026-04-19 10:00:00 +0000
categories: post
tags: [docker, steamos, steamdeck, opensuse, containers, gaming]
author: Tobias Geiser
image: "/assets/posts/2026-04-19/steam-deck-tumbleweed.png"
header: "/assets/posts/2026-04-19/steam-deck-tumbleweed-header.png"
excerpt_separator: <!--more-->
---

In [Part 1]({% post_url 2026-04-05-a-steam-deck-recovery-image-in-a-docker-container-part-1 %}) I turned a Steam Deck recovery image into a Docker image. It worked — and it stayed a museum piece. SteamOS inside a container fights you: it wants Steam Deck hardware, it updates through a bootloader-aware A/B flow, and its GPU userspace matches nothing but a deck. So the experiment became a product: a plain openSUSE Tumbleweed Steam container with GPU variant detection, controller passthrough, and persistent state. This post is that second act, including the Docker tag mismatch that briefly convinced me the image was broken.
<!--more-->

**TL;DR:** The daily driver is now `dampfmachine:tumbleweed` — built from a Dockerfile, not imported from a disk image. One `run.sh` detects Intel vs. NVIDIA, mounts Steam's state from the host, passes input devices, and injects CA certificates. The legacy SteamOS import flow survives for experiments. The most common failure mode is not technical: the build script and the run script must agree on the image tag, or Docker silently tries to pull something that does not exist.

This is Part 2 of a two-part series.

## Overview

The repository that grew out of the experiment:

```text
~/src/dampfmachine/
├── Dockerfile.tumbleweed         # the real daily image
├── build-tumbleweed-image.sh     # → dampfmachine:tumbleweed
├── run.sh                        # GPU detection, mounts, devices, CA certs
├── install-proton-ge.sh          # Proton-GE into the compat tools dir
├── cacerts/                      # extra CA certs injected at startup
├── build-steamdeck-image.sh      # legacy: recovery image → docker import
├── build-steamdeck-intel-image.sh
└── build-steamdeck-nvidia-image.sh
```

Why Tumbleweed won:

- It updates with `zypper`, not with a bootloader-aware A/B flow.
- Its Mesa/VA-API stack tracks the host kernel, which matters on AMD and Intel GPUs.
- It is a normal distro, so anything missing is one install away.

## Prerequisites

- Docker on a Linux host with an X11 session (`xhost` available).
- GPU access: `/dev/dri` for Intel/AMD, or the NVIDIA container runtime (`--gpus all`).
- For the legacy flow only: `python3`, `bzip2`, `udisksctl` (see Part 1).

## Walkthrough

### Build the Tumbleweed image

```bash
./build-tumbleweed-image.sh
```

```text
[+] Building openSUSE Tumbleweed image as dampfmachine:tumbleweed
[+] Done: dampfmachine:tumbleweed
```

The script is a thin wrapper around `docker build -f Dockerfile.tumbleweed`, with `--tag` if you want a different name.

### Run Steam with automatic GPU detection

```bash
./run.sh
```

`run.sh` picks the GPU variant automatically: if `nvidia-smi` works and `/dev/nvidiactl` exists, it runs NVIDIA mode (host driver + `--gpus all`); otherwise it assumes Intel/AMD and passes `/dev/dri`. Force it when auto-detection guesses wrong:

```bash
GPU_VARIANT=intel ./run.sh
GPU_VARIANT=nvidia ./run.sh
```

Run the preflight checks alone when something stops working:

```bash
./run.sh --check
```

### Persist Steam across container rebuilds

The launcher mounts Steam's state from host directories into the container home — the `.steam` config, the game library, and the cache. Rebuilding the image never touches your installs or login. Point the paths at a fast disk; the library directory is where games live.

### Pass controllers and input devices

Gamepads are just device nodes. Pass them explicitly:

```bash
./run.sh --device /dev/input/js0 --device /dev/input/event15
```

Or hand over the whole input subsystem when you do not want to chase event numbers:

```bash
./run.sh --device /dev/input --device /dev/uinput
```

### Install Proton-GE

For Windows games that need a newer Proton than Steam ships:

```bash
./install-proton-ge.sh
```

It drops Proton-GE into Steam's compatibility-tools directory inside the container, where Steam picks it up as a runner option.

### Keep the CA certificate story consistent

If your network intercepts TLS (see [my DevOps container post]({% post_url 2026-06-14-a-minimal-tumbleweed-devops-tools-container %}) for the same problem), put your PEM files in `cacerts/` or point `EXTRA_CA_CERT_DIR` at them. `run.sh` injects them into the container trust store at startup — Steam's downloads and logins then survive TLS-intercepting proxies.

## Troubleshooting

### The image is built, but running it says "access denied"

This one cost me an evening. The legacy build script resolves the `preview` channel and imports the result as:

```text
steamdeck-repair:preview
```

But the launcher, in auto mode, looks for `:intel` or `:nvidia` variants and falls back to:

```text
steamdeck-repair:latest
```

That tag did not exist locally — so Docker did the only thing it can do with an unknown name: it tried to **pull** it from a registry, and failed with access denied. Nothing was broken; the build and run paths simply disagreed about the tag.

**Pro tip:** when Docker claims it cannot pull an image you just built, run `docker images` first. A missing local tag always turns into a pull attempt. Align the `--tag` you build with the tag your launcher expects.

### Some recovery builds have no repair image

The channel metadata occasionally resolves to builds without a downloadable repair image, and the download step fails. Pin a known-good `--url` in that case rather than trusting channel resolution:

```bash
./build-steamdeck-image.sh \
  --url https://steamdeck-images.steamos.cloud/recovery/steamdeck-repair-latest.img.bz2
```

### Legacy GPU variants

The derived SteamOS images (`steamdeck-repair:intel`, `steamdeck-repair:nvidia`) layer GPU userspace onto the imported rootfs. They exist for completeness and experiments; the Tumbleweed image replaces them for daily use. If you play with them, remember Part 1's rule: container userspace must match the host kernel driver, and NVIDIA is the only case where tooling does that matching for you.

## Summary

- Import the recovery image once for experiments; run a proper distro image daily.
- `run.sh` handles GPU detection, state mounts, device passthrough, and CA injection in one entry point.
- Keep build tags and run tags identical, or Docker turns your local image into a phantom pull.
- Controllers are device nodes; pass exactly the ones you need or all of `/dev/input`.
- Steam's state lives on the host — rebuild the container freely.

## References

- [Part 1: Turning a Steam Deck Recovery Image into a Docker Container]({% post_url 2026-04-05-a-steam-deck-recovery-image-in-a-docker-container-part-1 %})
- [Proton-GE releases](https://github.com/GloriousEggroll/proton-ge-custom)
- [Steam Deck recovery images](https://store.steampowered.com/steamos/download)
