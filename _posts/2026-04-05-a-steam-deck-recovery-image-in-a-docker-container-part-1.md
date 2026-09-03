---
layout: post
title: "Turning a Steam Deck Recovery Image into a Docker Container, Part 1"
date: 2026-04-05 10:00:00 +0000
categories: post
tags: [docker, steamos, steamdeck, opensuse, containers, gaming]
author: Tobias Geiser
image: "/assets/posts/2026-04-05/steam-deck-opensuse.png"
header: "/assets/posts/2026-04-05/steam-deck-header.png"
excerpt_separator: <!--more-->
---

Valve publishes Steam Deck recovery images as raw `.img.bz2` disk images — the same images repair shops flash onto decks. I wanted one of those SteamOS root filesystems inside a Docker container. The catch: Docker wants a root filesystem tarball, and what Valve ships is a full disk image with partition table, bootloader, and two A/B root partitions. This post is the conversion, step by honest step.
<!--more-->

**TL;DR:** Decompress the image, parse the GPT table to find the `rootfs-A` partition, mount it via `udisksctl` (plain `mount -o offset` needs root), copy the tree out with a privileged helper container, `tar` it, and `docker import` the result. Along the way: two different permission walls, and a clear answer to "can the container use my GPU?"

This is Part 1 of a two-part series. [Part 2]({% post_url 2026-04-19-a-steam-deck-recovery-image-in-a-docker-container-part-2 %}) covers what I built on top of it and why the daily driver eventually became a plain Tumbleweed image.

## Overview

The goal is a container that contains the SteamOS userspace — Steam, gamescope, the SteamOS tooling — imported from the official recovery image:

```text
https://steamdeck-images.steamos.cloud/recovery/steamdeck-repair-latest.img.bz2
```

The pipeline:

![Steam Deck recovery image extraction pipeline: raw recovery image, loop partition mount, rootfs tree extraction, tar archive, and Docker image import.](/assets/posts/2026-04-05/steam-deck-pipeline.png){: style="max-width: 100%; min-width: 100%; height: auto"}

Two honest caveats before starting:

- The recovery image is built for Steam Deck hardware. Some services and scripts inside simply make no sense in a container.
- Do **not** try to run SteamOS OTA updates inside the container. The RAUC A/B update flow expects real block devices and boot configuration.

## Prerequisites

- A Linux host with Docker, `bzip2`, `python3`, and `udisksctl` (udisks2 — present on most desktops).
- Roughly 15 GB of free disk space: ~4 GB download, ~6 GB decompressed image, ~4 GB extracted rootfs, plus the imported image.
- No root required until the copy step, which we solve with a container anyway.

## Walkthrough

### Download and decompress the image

```bash
curl -fL --retry 3 -o steamdeck-repair-latest.img.bz2 \
  https://steamdeck-images.steamos.cloud/recovery/steamdeck-repair-latest.img.bz2
bzip2 -dk steamdeck-repair-latest.img.bz2
```

If you want a specific update channel instead of the latest repair image, the channel metadata lives at `https://steamdeck-atomupd.steamos.cloud/meta` — resolve a build ID there and download the matching bundle.

### Find the root filesystem partition

The image uses a GPT layout with an ESP, two EFI partitions, and two root partitions (`rootfs-A`, `rootfs-B`). You can parse the GPT entries with a few lines of Python — no `fdisk`/`parted` needed:

```python
import struct

img = 'steamdeck-repair-latest.img'
with open(img, 'rb') as f:
    f.seek(512)                      # GPT header at LBA 1
    hdr = f.read(92)
    part_lba, num, size = struct.unpack('<QII', hdr[72:84])
    f.seek(part_lba * 512)
    for i in range(num):
        entry = f.read(size)
        start, end = struct.unpack('<QQ', entry[32:48])
        name = entry[56:].decode('utf-16-le').rstrip('\x00')
        if name:
            print(f'{i+1}: {name:12} start={start} end={end}')
```

On my image the relevant line:

```text
3: rootfs-A    start=655360 end=11141119
```

That start sector is the number the rest of the walkthrough needs.

### Mount the partition without root

The classic approach fails without privileges:

```bash
mkdir -p rootfs
mount -o loop,ro,offset=$((655360 * 512)) steamdeck-repair-latest.img rootfs
# mount: failed to setup loop device
```

The desktop-friendly way is udisks2, which is allowed for regular users:

```bash
udisksctl loop-setup -f steamdeck-repair-latest.img
udisksctl mount -b /dev/loop0p3
```

```text
Mapped file ... as /dev/loop0.
Mounted /dev/loop0p3 at /run/media/<user>/rootfs.
```

`/dev/loop0p3` is partition 3 — `rootfs-A`. udisks auto-mounts it under `/run/media/<user>/`.

### Copy the tree out as root

A naive copy dies on root-only files:

```bash
cp -a /run/media/<user>/rootfs/. rootfs/
# cp: cannot open '.../etc/crypttab' for reading: Permission denied
```

The clean fix is to do the copying as root inside a throwaway container, binding both the mounted partition and the target directory:

```bash
docker run --rm \
  -v /run/media/<user>/rootfs:/src:ro \
  -v "$PWD/rootfs:/dst" \
  alpine:3.20 sh -c "cp -a /src/. /dst/"
```

**Gotcha:** if a previous failed copy left root-owned files in `rootfs/`, even the container cannot delete them as your user. Wipe from inside the container too:

```bash
docker run --rm \
  -v /run/media/<user>/rootfs:/src:ro \
  -v "$PWD/rootfs:/dst" \
  alpine:3.20 sh -c "rm -rf /dst/* /dst/.[!.]* /dst/..?* 2>/dev/null; cp -a /src/. /dst/"
```

### Tar it and import it

Create the tarball from the extracted tree, then import:

```bash
tar -C rootfs -cpf steamdeck-rootfs.tar .
docker import steamdeck-rootfs.tar steamdeck-repair:latest
```

`docker import` turns any rootfs tarball into a flat image. The alternative is a Dockerfile with `FROM scratch` and `ADD steamdeck-rootfs.tar /`, which buys you a place for `CMD`/`ENV` later.

### Verify what you got

Check the users and the tooling:

```bash
docker run --rm --entrypoint /bin/sh steamdeck-repair:latest \
  -c 'id -u; getent passwd 1000'
docker run --rm --entrypoint /bin/sh steamdeck-repair:latest \
  -c 'command -v steam; command -v gamescope; command -v steamos-update'
```

```text
/usr/sbin/steam
/usr/sbin/gamescope
/usr/sbin/steamos-session-select
/usr/sbin/steamos-update
/usr/sbin/atomupd-manager
```

Two facts that matter for how you run it:

- The interactive user is `deck` (UID 1000), and the Steam homes live under `/home/deck/`.
- The imported image has **no** `CMD`/`ENTRYPOINT` — every `docker run` needs an explicit command until you wrap it in a Dockerfile.

### GPU expectations

The question everyone asks next: can the container use my GPU? The honest answer:

- Kernel drivers (`amdgpu`, `i915`, `xe`, `nvidia`) always come from the **host** kernel. A container cannot load them; it only gets what the host exposes via `/dev/dri`.
- What the container carries is the *userspace* stack (Mesa/Vulkan/VA-API libs), and it must be ABI-compatible with the host kernel driver.
- NVIDIA is the easy case (the nvidia-container runtime injects matching userspace). For Intel/AMD, install a matching Mesa inside the image rather than bind-mounting host libraries — mixing host/container Mesa versions breaks in confusing ways.

## Troubleshooting

### `failed to setup loop device`

`mount -o loop,offset=` requires root. Use `udisksctl loop-setup` as a regular user, or run the mount with sudo if you prefer. Remember to clean up afterwards:

```bash
udisksctl unmount -b /dev/loop0p3
udisksctl loop-delete -b /dev/loop0
```

### Permission denied while copying the rootfs

Twice, in different directions: host-side `cp` cannot read root-owned source files; a leftover root-owned `rootfs/` directory cannot be cleaned as your user. In both cases, do the file operations inside a privileged-enough container instead of fighting ownership on the host.

## Summary

- A recovery image is a GPT disk image; find `rootfs-A` by parsing the partition table.
- `udisksctl` mounts partitions as a regular user when `mount -o offset` cannot.
- Do root-owned copies inside a container; `tar` + `docker import` finishes the job.
- The imported image runs as user `deck`, has no default entrypoint, and must never run OTA updates.
- GPU support is host-kernel + matched-container-userspace; nothing more.

## References

- [Part 2: From SteamOS Hack to a Tumbleweed Steam Container]({% post_url 2026-04-19-a-steam-deck-recovery-image-in-a-docker-container-part-2 %})
- [Steam Deck recovery images](https://store.steampowered.com/steamos/download)
- [udisks2 documentation](https://github.com/storaged-project/udisks)
