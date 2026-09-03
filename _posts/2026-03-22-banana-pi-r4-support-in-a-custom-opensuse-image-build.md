---
layout: post
title: "Bringing Banana Pi R4 Support into a Custom openSUSE Image Build"
date: 2026-03-22 10:00:00 +0000
categories: post
tags: [opensuse, bananapi, kernel, arm, embedded, build]
author: Tobias Geiser
image: "/assets/posts/2026-03-22/banana-pi-cobanero.png"
header: "/assets/posts/2026-03-22/banana-pi-header.png"
excerpt_separator: <!--more-->
---

My router image build system supported a pile of Orange Pi boards — and nothing MediaTek. Then a Banana Pi R4 showed up, with its MT7988 SoC and a kernel tree that lives in a third-party repository. Integrating it meant teaching an Armbian-style build framework about a brand-new board family: board config, family source, kernel defconfig, and a FIT image flow. This is the integration, including the openSUSE-specific bugs it flushed out.
<!--more-->

**TL;DR:** The Banana Pi R4 is now a first-class board in my build tree: `BOARD=bananapir4 BRANCH=current RELEASE=tumbleweed` compiles a 6.12 kernel from the BPI-Router-Linux tree with `mt7988a_bpi-r4_defconfig`. The work was config plumbing, not code — but it exposed two real bugs: the openSUSE rootfs path silently skipping locally built packages, and `sudo` stripping tools like `fakeroot` from the build's PATH.

## Overview

The build system is an Armbian-style framework (forked and refactored for openSUSE targets) that assembles bootable images from three ingredients per board:

- a **board config** describing the hardware,
- a **family/source config** saying where the kernel and U-Boot come from,
- a **kernel config** (defconfig-derived) for the actual build.

The Banana Pi R4 was a net-new integration: the tree had no MediaTek family at all. The kernel support comes from the well-known [BPI-Router-Linux](https://github.com/frank-w/BPI-Router-Linux) tree, which carries explicit R4 support on its `6.12-main` branch — `arm64`, `mt7988a`, defconfig `mt7988a_bpi-r4_defconfig`. The final bootable image is assembled with [KIWI](https://osinside.github.io/kiwi/), openSUSE's own appliance/image-building tool.

![The Banana Pi R4 custom build pipeline: board config, kernel defconfig, and Kiwi build producing a bootable openSUSE ARM64 image.](/assets/posts/2026-03-22/banana-pi-build-flow.png){: style="max-width: 100%; min-width: 100%; height: auto"}

## Architecture

Three new files carry the whole integration:

```text
external/config/boards/bananapir4.conf            # board definition
external/config/sources/families/mt7988.conf      # family: kernel + u-boot sources
external/config/kernel/linux-mt7988-current.config # kernel config
```

The R4 does not boot like the Allwinner boards the tree already knew. Its kernel produces a **FIT image** flow: a `bpi-r4.its` source builds `bpi-r4.itb`, referencing `mt7988a-bananapi-bpi-r4.dtb` plus overlays for SD boot, eMMC, and the MT7996 Wi-Fi. U-Boot comes from a matching fork branch with R4 defconfigs. Both facts shape the family config: it must point at the right kernel branch and carry the FIT/overlay expectations.

## Prerequisites

- The build framework checked out and working for at least one existing board.
- Host toolchain for arm64 cross-compilation (`gcc-aarch64`, `bison`, `flex`, `bc`, device-tree compiler, etc.).
- Network access to fetch the kernel and U-Boot sources during build.
- openSUSE host if you want to reproduce the rootfs quirks below.

## Walkthrough

### Add the board config

The board file declares identity, family, and branch. The important line is the family link, which routes the build to the new MediaTek source config:

```bash
# external/config/boards/bananapir4.conf
BOARDFAMILY="mt7988"
```

### Add the family source config

The family config names the kernel source repository and branch, the U-Boot source and its branch, and the architecture:

- Kernel: BPI-Router-Linux, branch `6.12-main`.
- U-Boot: the matching fork branch that ships the R4 defconfigs (the `configs/` directory of that branch contains the `mt7988a_bpi-r4*` entries).

### Derive the kernel config

Fetch the upstream defconfig as the starting point:

```bash
curl -fsSL https://raw.githubusercontent.com/frank-w/BPI-Router-Linux/6.12-main/arch/arm64/configs/mt7988a_bpi-r4_defconfig \
  -o external/config/kernel/linux-mt7988-current.config
```

Store it as the `current` branch kernel config for the family; the build system diffs and rebuilds from it like any other board.

### Build the kernel

```bash
./build.sh \
  BOARD=bananapir4 \
  BRANCH=current \
  RELEASE=tumbleweed \
  BUILD_MINIMAL=yes \
  BUILD_DESKTOP=no \
  KERNEL_CONFIGURE=no
```

The milestone output that says the integration is real:

```text
DEPMOD  .../output/kernel/bananapir4-current/lib/modules/6.12.77-bpi-r4-mt7988
```

A 6.12 kernel built from the router tree, installed into the output tree under the board name. From here, image assembly reuses the existing framework steps.

## Troubleshooting

### openSUSE rootfs skips locally built packages

Mid-integration, images built but were missing the BSP and kernel packages that the build itself had just produced. Root cause, in the rootfs assembly script: `debootstrap_ng()` runs the common package install **before** the locally built packages get installed — and the local install step is guarded by `if ! is_opensuse_release`, i.e. it is *skipped entirely* for openSUSE targets:

```bash
install_common ...
if ! is_opensuse_release; then
    chroot_installpackages_local   # never runs on openSUSE
fi
```

Debian-family images masked the bug for years. The fix direction: give openSUSE an equivalent local-package install step and order it after `install_common`.

**Pro tip:** when an image builds but boots "incomplete", diff the package list inside the rootfs against what the build produced — silent skips show up there immediately.

### rpmbuild is installed, but the build can't find it

The BSP package step converts the deb-style output into an RPM when `rpmbuild` and `fakeroot` are available:

```bash
if command -v fakeroot >/dev/null 2>&1 && command -v rpmbuild >/dev/null 2>&1; then
    build_rpm_from_deb_dir ...
else
    display_alert "Skipping BSP RPM build" "rpmbuild not available on host" "info"
fi
```

Both tools were installed on my host — yet the check failed during builds. The diagnostics (temporarily logging `PATH` and the executing user inside the script) revealed the classic culprit: the build invokes parts under `sudo`, and `sudo` resets the environment. The tools existed in my interactive shell but not in the script's sanitized PATH.

The durable outcome was better error reporting — the build now says *which* tool is missing:

```text
Skipping BSP RPM build missing: fakeroot
```

If you hit this class of bug, log the environment inside the failing script before anything else; "works in my shell" plus "fails in the build" is almost always an environment delta.

## Summary

- New board family = board config + family source config + kernel config; the R4 needed all three.
- The R4 boots via a FIT image (`bpi-r4.itb` with DTB overlays), not plain `Image` + DTB — the family config must reflect that.
- Kernel builds clean from BPI-Router-Linux `6.12-main` with `mt7988a_bpi-r4_defconfig`.
- openSUSE image assembly silently skipped locally built packages — a Debian-masked ordering bug.
- "Tool installed but not found" under `sudo` builds is a PATH environment problem; log the environment, then fix the message.

## References

- [BPI-Router-Linux kernel tree](https://github.com/frank-w/BPI-Router-Linux)
- [Banana Pi](https://www.banana-pi.org/)
